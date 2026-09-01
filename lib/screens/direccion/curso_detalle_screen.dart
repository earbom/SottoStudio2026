import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import '../../models/curso.dart';
import '../../models/asignatura.dart';
import '../../models/matricula.dart';
import '../../models/usuario.dart';
import '../../services/ajustes_service.dart';
import '../../services/auth_service.dart';
import '../../services/db_service.dart';
import '../../utils/iconos_asignatura.dart';
import '../comunes/asignatura_detalle_screen.dart';

class CursoDetalleScreen extends StatefulWidget {
  final Curso curso;
  final Usuario perfil;

  const CursoDetalleScreen(
      {super.key, required this.curso, required this.perfil});

  @override
  State<CursoDetalleScreen> createState() => _CursoDetalleScreenState();
}

class _CursoDetalleScreenState extends State<CursoDetalleScreen> {
  final DbService _db = DbService();
  final AuthService _auth = AuthService();

  Future<
      ({
        String nombre,
        List<String> profesorIds,
        String iconoId,
        bool permiteGrabarEstudio,
      })?> _mostrarFormularioAsignatura({
    String nombreInicial = '',
    List<String> profesorIdsIniciales = const [],
    String iconoIdInicial = '',
    bool permiteGrabarEstudioInicial = false,
  }) async {
    final controladorNombre = TextEditingController(text: nombreInicial);
    final profesoresSeleccionados = profesorIdsIniciales.toSet();
    String iconoId = iconoIdInicial.isEmpty
        ? iconosAsignaturaDisponibles.first.id
        : iconoIdInicial;
    var permiteGrabarEstudio = permiteGrabarEstudioInicial;
    final profesores = await _db.profesoresDelCentro().first;
    if (!mounted) return null;

    return showDialog<
        ({
          String nombre,
          List<String> profesorIds,
          String iconoId,
          bool permiteGrabarEstudio,
        })>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: Text(
              nombreInicial.isEmpty ? 'Nueva asignatura' : 'Editar asignatura'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: controladorNombre,
                  decoration: const InputDecoration(
                      labelText: 'Nombre (ej. Violín, Lenguaje musical...)'),
                  autofocus: true,
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Permite grabar estudio'),
                  subtitle: const Text(
                      'Solo para instrumento: el alumno podrá grabar sesiones de práctica en esta asignatura.'),
                  value: permiteGrabarEstudio,
                  onChanged: (v) =>
                      setStateDialog(() => permiteGrabarEstudio = v),
                ),
                const SizedBox(height: 4),
                const Text('Icono'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: iconosAsignaturaDisponibles.map((icono) {
                    final seleccionado = icono.id == iconoId;
                    return Tooltip(
                      message: icono.etiqueta,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(24),
                        onTap: () => setStateDialog(() => iconoId = icono.id),
                        child: Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: seleccionado
                                ? Theme.of(context).colorScheme.primaryContainer
                                : Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHighest,
                            border: seleccionado
                                ? Border.all(
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                    width: 2)
                                : null,
                          ),
                          child: Center(
                            child: FaIcon(
                              icono.icono,
                              size: 20,
                              color: seleccionado
                                  ? Theme.of(context)
                                      .colorScheme
                                      .onPrimaryContainer
                                  : Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                const Text('Profesorado'),
                if (profesores.isEmpty)
                  const Text('No hay profesores dados de alta todavía.',
                      style: TextStyle(fontStyle: FontStyle.italic)),
                ...profesores.map((p) => CheckboxListTile(
                      dense: true,
                      title: Text(p.nombre),
                      value: profesoresSeleccionados.contains(p.uid),
                      onChanged: (v) => setStateDialog(() {
                        v == true
                            ? profesoresSeleccionados.add(p.uid)
                            : profesoresSeleccionados.remove(p.uid);
                      }),
                    )),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar')),
            FilledButton(
              onPressed: () => Navigator.pop(
                context,
                (
                  nombre: controladorNombre.text.trim(),
                  profesorIds: profesoresSeleccionados.toList(),
                  iconoId: iconoId,
                  permiteGrabarEstudio: permiteGrabarEstudio,
                ),
              ),
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _crearAsignatura() async {
    final resultado = await _mostrarFormularioAsignatura();
    if (resultado == null || resultado.nombre.isEmpty) return;

    final uid = _auth.usuarioActual?.uid ?? '';
    await _db.crearAsignatura(Asignatura(
      cursoId: widget.curso.id!,
      nombre: resultado.nombre,
      profesorIds: resultado.profesorIds,
      createdAt: DateTime.now(),
      createdBy: uid,
      iconoId: resultado.iconoId,
      permiteGrabarEstudio: resultado.permiteGrabarEstudio,
    ));
  }

  Future<void> _editarAsignatura(Asignatura asignatura) async {
    final resultado = await _mostrarFormularioAsignatura(
      nombreInicial: asignatura.nombre,
      profesorIdsIniciales: asignatura.profesorIds,
      iconoIdInicial: asignatura.iconoId,
      permiteGrabarEstudioInicial: asignatura.permiteGrabarEstudio,
    );
    if (resultado == null || resultado.nombre.isEmpty) return;

    await _db.actualizarAsignatura(asignatura.id!, {
      'nombre': resultado.nombre,
      'profesorIds': resultado.profesorIds,
      'iconoId': resultado.iconoId,
      'permiteGrabarEstudio': resultado.permiteGrabarEstudio,
    });
  }

  Future<void> _eliminarAsignatura(Asignatura asignatura) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar asignatura'),
        content: Text(
            '¿Eliminar "${asignatura.nombre}"? Solo es posible si no tiene alumnos matriculados.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Eliminar')),
        ],
      ),
    );
    if (confirmar != true) return;

    try {
      await _db.eliminarAsignatura(asignatura.id!);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.curso.nombre)),
      body: StreamBuilder<String>(
        stream: _db.cursoEscolarActivo(),
        builder: (context, snapActivo) {
          if (!snapActivo.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final cursoEscolar = snapActivo.data!;
          return StreamBuilder<List<Asignatura>>(
            stream: _db.asignaturasDeCurso(widget.curso.id!),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final asignaturas = snapshot.data!;
              if (asignaturas.isEmpty) {
                return const Center(
                    child: Text('Aún no hay asignaturas en este curso.'));
              }
              final escalaIconos = context.watch<AjustesService>().escalaIconos;
              return GridView.builder(
                padding: const EdgeInsets.all(16),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 140,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  childAspectRatio: 0.85,
                ),
                itemCount: asignaturas.length,
                itemBuilder: (context, i) {
                  final asignatura = asignaturas[i];
                  final icono = iconoAsignaturaPorId(asignatura.iconoId);
                  return StreamBuilder<List<Matricula>>(
                    stream: _db.matriculasDeAsignatura(asignatura.id!,
                        cursoEscolar: cursoEscolar),
                    builder: (context, snapMatriculas) {
                      final nMatriculados = snapMatriculas.data?.length ?? 0;
                      return InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => AsignaturaDetalleScreen(
                              asignatura: asignatura,
                              perfil: widget.perfil,
                            ),
                          ),
                        ),
                        child: Stack(
                          children: [
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  width: 64 * escalaIconos,
                                  height: 64 * escalaIconos,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primaryContainer,
                                  ),
                                  child: Center(
                                    child: FaIcon(
                                      icono.icono,
                                      size: 28 * escalaIconos,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onPrimaryContainer,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  asignatura.nombre,
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600),
                                ),
                                Text(
                                  '$nMatriculados alumno(s)',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .outline),
                                ),
                              ],
                            ),
                            Positioned(
                              top: 0,
                              right: 0,
                              child: PopupMenuButton<String>(
                                icon: const Icon(Icons.more_vert, size: 18),
                                tooltip: 'Opciones',
                                onSelected: (v) {
                                  if (v == 'editar') {
                                    _editarAsignatura(asignatura);
                                  }
                                  if (v == 'eliminar') {
                                    _eliminarAsignatura(asignatura);
                                  }
                                },
                                itemBuilder: (context) => const [
                                  PopupMenuItem(
                                      value: 'editar', child: Text('Editar')),
                                  PopupMenuItem(
                                      value: 'eliminar',
                                      child: Text('Eliminar')),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _crearAsignatura,
        child: const Icon(Icons.add),
      ),
    );
  }
}
