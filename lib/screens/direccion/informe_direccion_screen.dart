import 'package:flutter/material.dart';
import '../../models/curso.dart';
import '../../models/usuario.dart';
import '../../services/db_service.dart';
import '../../widgets/error_carga.dart';
import '../../widgets/selector_curso_escolar.dart';

/// Vista clave de dirección: horas efectivas del MES ACTUAL de todos
/// los alumnos matriculados en el curso escolar consultado (activo por
/// defecto, o uno anterior — ver CLAUDE.md, discriminación por curso
/// escolar), agrupadas por curso (mismo agrupamiento que Alumnos y
/// Cuadro de honor) y ordenadas de mayor a menor dentro de cada grupo.
/// Si el alumno tiene un objetivo mensual combinado (suma de
/// `Asignatura.horasObjetivoMensual` de sus asignaturas matriculadas —
/// cada asignatura tiene su propia cantidad de horas, ver CLAUDE.md),
/// se colorea en verde si lo alcanza y en rojo si no — sin objetivo
/// definido no se colorea.
class InformeDireccionScreen extends StatefulWidget {
  const InformeDireccionScreen({super.key});

  @override
  State<InformeDireccionScreen> createState() => _InformeDireccionScreenState();
}

class _InformeDireccionScreenState extends State<InformeDireccionScreen> {
  final DbService _db = DbService();
  String? _cursoSeleccionado;

  Future<void> _elegirCursoEscolar(String activo) async {
    final historial = await _db.historialCursosEscolares().first;
    if (!mounted) return;
    final elegido = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Ver curso escolar'),
        children: historial.reversed
            .map((curso) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, curso),
                  child: Row(
                    children: [
                      Expanded(child: Text(curso)),
                      if (curso == activo)
                        const Text('(activo)',
                            style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                ))
            .toList(),
      ),
    );
    if (elegido == null) return;
    setState(() => _cursoSeleccionado = elegido == activo ? null : elegido);
  }

  Future<({Map<String, Usuario> alumnos, Map<String, List<Curso>> cursos})>
      _cargarDatosAgrupacion(
          List<Map<String, dynamic>> filas, String cursoEscolar) async {
    final cursosPorAlumno =
        await _db.cursosPorAlumno(cursoEscolar: cursoEscolar);
    final alumnos = <String, Usuario>{};
    for (final fila in filas) {
      final alumnoId = fila['alumnoId'] as String? ?? '';
      if (alumnoId.isEmpty || alumnos.containsKey(alumnoId)) continue;
      final alumno = await _db.obtenerUsuario(alumnoId);
      if (alumno != null) alumnos[alumnoId] = alumno;
    }
    return (alumnos: alumnos, cursos: cursosPorAlumno);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<String>(
      stream: _db.cursoEscolarActivo(),
      builder: (context, snapActivo) {
        if (snapActivo.hasError) {
          return const Scaffold(body: ErrorCarga());
        }
        if (!snapActivo.hasData) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        final activo = snapActivo.data!;
        final cursoEscolar = _cursoSeleccionado ?? activo;
        return Scaffold(
          body: Column(
            children: [
              Container(
                width: double.infinity,
                color: Theme.of(context).colorScheme.primary,
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Center(
                  child: SelectorCursoEscolar(
                    cursoMostrado: cursoEscolar,
                    esActivo: cursoEscolar == activo,
                    onPressed: () => _elegirCursoEscolar(activo),
                  ),
                ),
              ),
              Expanded(
                child: StreamBuilder<List<Map<String, dynamic>>>(
                  stream: _db.informeDireccion(cursoEscolar: cursoEscolar),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return const ErrorCarga();
                    }
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final filas = snapshot.data!;
                    if (filas.isEmpty) {
                      return const Center(
                          child: Text('Todavía no hay horas registradas.'));
                    }
                    return FutureBuilder<
                        ({
                          Map<String, Usuario> alumnos,
                          Map<String, List<Curso>> cursos
                        })>(
                      future: _cargarDatosAgrupacion(filas, cursoEscolar),
                      builder: (context, snapDatos) {
                        if (!snapDatos.hasData) {
                          return const Center(
                              child: CircularProgressIndicator());
                        }
                        final alumnosPorId = snapDatos.data!.alumnos;
                        final cursosPorAlumno = snapDatos.data!.cursos;

                        final grupos = <String,
                            ({
                          Curso? curso,
                          List<Map<String, dynamic>> filas
                        })>{};
                        for (final fila in filas) {
                          final alumnoId = fila['alumnoId'] as String? ?? '';
                          final cursos = cursosPorAlumno[alumnoId] ?? const [];
                          if (cursos.isEmpty) {
                            final actual = grupos['_sin_matricular'];
                            grupos['_sin_matricular'] = (
                              curso: null,
                              filas: [...(actual?.filas ?? const []), fila],
                            );
                            continue;
                          }
                          for (final curso in cursos) {
                            final actual = grupos[curso.id];
                            grupos[curso.id!] = (
                              curso: curso,
                              filas: [...(actual?.filas ?? const []), fila],
                            );
                          }
                        }

                        final entradas = grupos.values.toList()
                          ..sort((a, b) {
                            if (a.curso == null) return 1;
                            if (b.curso == null) return -1;
                            return a.curso!.nivel.index != b.curso!.nivel.index
                                ? a.curso!.nivel.index
                                    .compareTo(b.curso!.nivel.index)
                                : (a.curso!.numeroCurso ?? 0)
                                    .compareTo(b.curso!.numeroCurso ?? 0);
                          });

                        return ListView(
                          children: [
                            for (final entrada in entradas) ...[
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 16, 16, 4),
                                child: Text(
                                  entrada.curso?.nombre ?? 'Sin matricular',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                              ),
                              for (var i = 0; i < entrada.filas.length; i++)
                                _filaInforme(
                                    context, entrada.filas[i], alumnosPorId, i),
                              const Divider(height: 1),
                            ],
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _filaInforme(BuildContext context, Map<String, dynamic> fila,
      Map<String, Usuario> alumnosPorId, int posicion) {
    final alumnoId = fila['alumnoId'] as String? ?? '';
    final horas = ((fila['horasEfectivasMes'] ?? 0) as num).toStringAsFixed(1);
    final objetivo = (fila['objetivoMensual'] ?? 0) as num;
    final cumpleObjetivo = fila['cumpleObjetivo'] as bool? ?? true;
    final tieneObjetivo = objetivo > 0;
    return ListTile(
      leading: CircleAvatar(child: Text('${posicion + 1}')),
      title: Text(alumnosPorId[alumnoId]?.nombre ?? alumnoId),
      subtitle: tieneObjetivo
          ? Text('Objetivo mensual: ${objetivo.toStringAsFixed(1)} h')
          : null,
      trailing: Text(
        '$horas h / mes',
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: !tieneObjetivo
              ? null
              : (cumpleObjetivo ? Colors.green : Colors.red),
        ),
      ),
    );
  }
}
