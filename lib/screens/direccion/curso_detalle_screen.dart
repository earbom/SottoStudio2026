import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import '../../models/curso.dart';
import '../../models/asignatura.dart';
import '../../models/matricula.dart';
import '../../models/usuario.dart';
import '../../services/ajustes_service.dart';
import '../../services/db_service.dart';
import '../../utils/iconos_asignatura.dart';
import '../comunes/asignatura_detalle_screen.dart';
import '../../utils/mensaje_error.dart';
import '../../widgets/error_carga.dart';
import 'formulario_asignatura.dart';

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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensajeError(e, porDefecto: 'No se pudo eliminar la asignatura.'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.curso.nombre)),
      body: StreamBuilder<String>(
        stream: _db.cursoEscolarActivo(),
        builder: (context, snapActivo) {
          if (snapActivo.hasError) {
            return const ErrorCarga();
          }
          if (!snapActivo.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final cursoEscolar = snapActivo.data!;
          return StreamBuilder<List<Asignatura>>(
            stream: _db.asignaturasDeCurso(widget.curso.id!),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const ErrorCarga();
              }
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
                                  '$nMatriculados ${nMatriculados == 1 ? 'alumno' : 'alumnos'}',
                                  style: TextStyle(
                                      fontSize: 12,
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
                                    editarAsignatura(context, asignatura);
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => crearAsignaturaEnCurso(context, widget.curso.id!),
        icon: const Icon(Icons.add),
        label: const Text('Nueva asignatura'),
      ),
    );
  }
}
