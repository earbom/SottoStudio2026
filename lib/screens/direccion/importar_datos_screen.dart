import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import '../../models/asignatura.dart';
import '../../models/curso.dart';
import '../../services/auth_service.dart';
import '../../services/db_service.dart';
import '../../utils/mensaje_error.dart';
import '../../utils/excel_plantilla_importacion.dart';

/// Volcado masivo de cursos/asignaturas/alumnos desde una plantilla
/// Excel FIJA (ver CLAUDE.md) — dirección descarga la plantilla, la
/// rellena con sus datos (hoy en hojas no homogéneas de Google Drive)
/// y la vuelve a subir aquí. Cursos/asignaturas que ya existan con el
/// mismo nombre se REUTILIZAN (permite reimportar el mismo archivo
/// actualizado sin duplicar); un alumno ya existente se detecta solo
/// por email exacto — dos alumnos sin email y mismo nombre+apellidos
/// se crean como registros distintos (limitación conocida, visible en
/// la previsualización).
class ImportarDatosScreen extends StatefulWidget {
  const ImportarDatosScreen({super.key});

  @override
  State<ImportarDatosScreen> createState() => _ImportarDatosScreenState();
}

typedef _Resultado = ({
  int cursosCreados,
  int asignaturasCreadas,
  int alumnosCreados,
  int alumnosSinCuenta,
  int matriculasCreadas,
  List<({String email, String password})> credenciales,
});

class _ImportarDatosScreenState extends State<ImportarDatosScreen> {
  final _db = DbService();
  final _auth = AuthService();
  bool _cargandoArchivo = false;
  bool _importando = false;
  String? _errorArchivo;
  ({List<FilaCursoAsignatura> cursos, List<FilaAlumnoMatricula> alumnos})? _datos;
  List<String> _erroresValidacion = [];
  _Resultado? _resultado;

  Future<void> _descargarPlantilla() async {
    final bytes = generarPlantillaImportacion();
    await FileSaver.instance.saveFile(
      name: 'plantilla_importacion_sotto_studio',
      bytes: bytes,
      fileExtension: 'xlsx',
      mimeType: MimeType.microsoftExcel,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Plantilla descargada.')),
    );
  }

  List<String> _validar(({List<FilaCursoAsignatura> cursos, List<FilaAlumnoMatricula> alumnos}) datos) {
    final errores = <String>[];
    final clavesCursoAsig = datos.cursos
        .map((c) => '${c.curso.trim().toLowerCase()}|${c.asignatura.trim().toLowerCase()}')
        .toSet();
    for (final fila in datos.alumnos) {
      final clave = '${fila.curso.trim().toLowerCase()}|${fila.asignatura.trim().toLowerCase()}';
      if (!clavesCursoAsig.contains(clave)) {
        errores.add(
            '${fila.nombre} ${fila.apellidos}: la asignatura "${fila.asignatura}" del curso "${fila.curso}" no aparece en la hoja "$hojaCursosAsignaturas".');
      }
    }
    return errores;
  }

  Future<void> _elegirArchivo() async {
    setState(() {
      _cargandoArchivo = true;
      _errorArchivo = null;
      _datos = null;
      _resultado = null;
    });
    try {
      final resultado = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
        withData: true,
      );
      final bytes = resultado?.files.single.bytes;
      if (bytes == null) return;
      final datos = parsearPlantillaImportacion(bytes);
      setState(() {
        _datos = datos;
        _erroresValidacion = _validar(datos);
      });
    } catch (e) {
      setState(() => _errorArchivo = mensajeError(e, porDefecto: 'No se pudo leer el archivo. ¿Es la plantilla de Excel descargada desde aquí?'));
    } finally {
      if (mounted) setState(() => _cargandoArchivo = false);
    }
  }

  Future<void> _confirmarImportacion() async {
    final datos = _datos;
    if (datos == null) return;
    setState(() => _importando = true);
    try {
      final cursoEscolar = await _db.cursoEscolarActivo().first;
      final uid = _auth.usuarioActual?.uid ?? '';

      final cursosExistentes = await _db.cursos().first;
      final cursoIdPorNombre = <String, String>{
        for (final c in cursosExistentes) c.nombre.trim().toLowerCase(): c.id!,
      };
      var cursosCreados = 0;
      for (final nombreCurso in datos.cursos.map((c) => c.curso).toSet()) {
        final clave = nombreCurso.trim().toLowerCase();
        if (cursoIdPorNombre.containsKey(clave)) continue;
        final id = await _db.crearCurso(Curso(
          nombre: nombreCurso,
          createdAt: DateTime.now(),
          createdBy: uid,
        ));
        cursoIdPorNombre[clave] = id;
        cursosCreados++;
      }

      final asignaturasExistentes = await _db.todasLasAsignaturas().first;
      final asignaturaIdPorClave = <String, String>{
        for (final a in asignaturasExistentes) '${a.cursoId}|${a.nombre.trim().toLowerCase()}': a.id!,
      };
      var asignaturasCreadas = 0;
      for (final fila in datos.cursos) {
        final cursoId = cursoIdPorNombre[fila.curso.trim().toLowerCase()]!;
        final claveAsig = '$cursoId|${fila.asignatura.trim().toLowerCase()}';
        if (asignaturaIdPorClave.containsKey(claveAsig)) continue;
        final id = await _db.crearAsignatura(Asignatura(
          cursoId: cursoId,
          nombre: fila.asignatura,
          profesorIds: const [],
          createdAt: DateTime.now(),
          createdBy: uid,
          permiteGrabarEstudio: fila.instrumento,
          horasObjetivoSemanal: fila.objetivoSemanal,
          horasObjetivoMensual: fila.objetivoMensual,
        ));
        asignaturaIdPorClave[claveAsig] = id;
        asignaturasCreadas++;
      }

      // Una fila representativa por alumno (varias filas pueden ser el
      // mismo alumno en distintas asignaturas) — agrupado por email si
      // lo hay, si no por nombre+apellidos (ver limitación en CLAUDE.md).
      final filaPorClaveAlumno = <String, FilaAlumnoMatricula>{};
      for (final fila in datos.alumnos) {
        final clave = (fila.email ?? '${fila.nombre.trim().toLowerCase()}|${fila.apellidos.trim().toLowerCase()}');
        filaPorClaveAlumno.putIfAbsent(clave, () => fila);
      }
      final alumnoIdPorClave = <String, String>{};
      final credenciales = <({String email, String password})>[];
      var alumnosCreados = 0;
      var alumnosSinCuenta = 0;
      for (final entry in filaPorClaveAlumno.entries) {
        final fila = entry.value;
        String? alumnoId;
        if (fila.email != null) {
          final existente = await _db.obtenerUsuarioPorEmail(fila.email!);
          alumnoId = existente?.uid;
        }
        if (alumnoId == null) {
          if (fila.email != null) {
            final password = await _auth.crearAlumno(
              nombre: fila.nombre,
              apellidos: fila.apellidos.isEmpty ? null : fila.apellidos,
              email: fila.email!,
            );
            final creado = await _db.obtenerUsuarioPorEmail(fila.email!);
            alumnoId = creado!.uid;
            credenciales.add((email: fila.email!, password: password));
          } else {
            alumnoId = await _auth.crearAlumnoSinCuenta(
              nombre: fila.nombre,
              apellidos: fila.apellidos.isEmpty ? null : fila.apellidos,
            );
            alumnosSinCuenta++;
          }
          alumnosCreados++;
        }
        alumnoIdPorClave[entry.key] = alumnoId;
      }

      var matriculasCreadas = 0;
      for (final fila in datos.alumnos) {
        final claveAlumno =
            (fila.email ?? '${fila.nombre.trim().toLowerCase()}|${fila.apellidos.trim().toLowerCase()}');
        final alumnoId = alumnoIdPorClave[claveAlumno]!;
        final cursoId = cursoIdPorNombre[fila.curso.trim().toLowerCase()]!;
        final asignaturaId = asignaturaIdPorClave['$cursoId|${fila.asignatura.trim().toLowerCase()}']!;
        await _db.matricular(
          alumnoId: alumnoId,
          asignaturaId: asignaturaId,
          cursoId: cursoId,
          cursoEscolar: cursoEscolar,
          diasSemana: fila.diasSemana,
        );
        matriculasCreadas++;
      }

      if (!mounted) return;
      setState(() {
        _resultado = (
          cursosCreados: cursosCreados,
          asignaturasCreadas: asignaturasCreadas,
          alumnosCreados: alumnosCreados,
          alumnosSinCuenta: alumnosSinCuenta,
          matriculasCreadas: matriculasCreadas,
          credenciales: credenciales,
        );
        _datos = null;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(mensajeError(e, porDefecto: 'La importación se detuvo por un error. Revisa el archivo e inténtalo de nuevo.'))),
      );
    } finally {
      if (mounted) setState(() => _importando = false);
    }
  }

  Future<void> _descargarCredenciales(List<({String email, String password})> credenciales) async {
    final buffer = StringBuffer('Email,Contraseña temporal\n');
    for (final c in credenciales) {
      buffer.writeln('${c.email},${c.password}');
    }
    await FileSaver.instance.saveFile(
      name: 'credenciales_importacion',
      bytes: Uint8List.fromList(buffer.toString().codeUnits),
      fileExtension: 'csv',
      mimeType: MimeType.csv,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Importar datos desde Excel')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Descarga la plantilla, rellénala con tus cursos, asignaturas y '
              'alumnos, y vuelve a subirla aquí. Los cursos/asignaturas que ya '
              'existan con el mismo nombre se reutilizan (puedes reimportar el '
              'mismo archivo actualizado sin duplicar nada).',
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                OutlinedButton.icon(
                  onPressed: _descargarPlantilla,
                  icon: const Icon(Icons.download_outlined),
                  label: const Text('Descargar plantilla'),
                ),
                FilledButton.icon(
                  onPressed: _cargandoArchivo ? null : _elegirArchivo,
                  icon: _cargandoArchivo
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.upload_file_outlined),
                  label: const Text('Importar desde Excel'),
                ),
              ],
            ),
            if (_errorArchivo != null) ...[
              const SizedBox(height: 16),
              Text(_errorArchivo!, style: const TextStyle(color: Colors.red)),
            ],
            if (_resultado != null) ...[
              const SizedBox(height: 24),
              Card(
                color: Colors.green.withValues(alpha: 0.1),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Importación completada', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Text('Cursos creados: ${_resultado!.cursosCreados}'),
                      Text('Asignaturas creadas: ${_resultado!.asignaturasCreadas}'),
                      Text(
                          'Alumnos creados: ${_resultado!.alumnosCreados} (de ellos ${_resultado!.alumnosSinCuenta} sin cuenta de acceso)'),
                      Text('Matrículas creadas: ${_resultado!.matriculasCreadas}'),
                      if (_resultado!.credenciales.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: () => _descargarCredenciales(_resultado!.credenciales),
                          icon: const Icon(Icons.file_download_outlined),
                          label: const Text('Descargar email + contraseñas temporales'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
            if (_datos != null) ...[
              const SizedBox(height: 24),
              const Text('Previsualización', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),
              Text('${_datos!.cursos.map((c) => c.curso).toSet().length} cursos mencionados'),
              Text('${_datos!.cursos.length} asignaturas mencionadas'),
              Text(
                  '${_datos!.alumnos.map((a) => a.email ?? '${a.nombre}|${a.apellidos}').toSet().length} alumnos distintos detectados'),
              Text('${_datos!.alumnos.length} matrículas (filas alumno+asignatura)'),
              if (_erroresValidacion.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('No se puede importar — hay ${_erroresValidacion.length} error(es):',
                    style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                ..._erroresValidacion.map((e) => Text('• $e', style: const TextStyle(color: Colors.red))),
              ] else ...[
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _importando ? null : _confirmarImportacion,
                  icon: _importando
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.check_circle_outline),
                  label: const Text('Confirmar importación'),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
