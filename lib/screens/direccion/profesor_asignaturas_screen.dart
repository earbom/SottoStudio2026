import 'package:flutter/material.dart';
import '../../models/asignatura.dart';
import '../../models/curso.dart';
import '../../models/usuario.dart';
import '../../services/db_service.dart';
import '../../utils/mensaje_error.dart';
import '../../widgets/error_carga.dart';
import '../../widgets/acciones_usuario.dart';
import 'sustitucion_profesor_screen.dart';

/// Permite a dirección asignar/desasignar un profesor a varias
/// asignaturas (una asignatura puede tener más de un profesor).
class ProfesorAsignaturasScreen extends StatelessWidget {
  final Usuario profesor;

  const ProfesorAsignaturasScreen({super.key, required this.profesor});

  @override
  Widget build(BuildContext context) {
    final db = DbService();
    return Scaffold(
      appBar: AppBar(
        title: Text('Asignaturas de ${profesor.nombre}'),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => SustitucionProfesorScreen(profesor: profesor)),
            ),
            icon: const Icon(Icons.swap_horiz),
            label: const Text('Sustituir'),
          ),
          MenuAccionesUsuario(usuario: profesor, esAlumno: false),
        ],
      ),
      body: StreamBuilder<List<Curso>>(
        stream: db.cursos(),
        builder: (context, snapCursos) {
          if (snapCursos.hasError) {
            return const ErrorCarga();
          }
          if (!snapCursos.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final cursos = {for (final c in snapCursos.data!) c.id!: c.nombre};

          return StreamBuilder<List<Asignatura>>(
            stream: db.todasLasAsignaturas(),
            builder: (context, snapAsignaturas) {
              if (snapAsignaturas.hasError) {
                return const ErrorCarga();
              }
              if (!snapAsignaturas.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final asignaturas = snapAsignaturas.data!;
              if (asignaturas.isEmpty) {
                return const Center(child: Text('Aún no hay asignaturas creadas.'));
              }

              // Agrupadas por curso para que sea fácil de escanear.
              final porCurso = <String, List<Asignatura>>{};
              for (final a in asignaturas) {
                porCurso.putIfAbsent(a.cursoId, () => []).add(a);
              }

              return ListView(
                children: porCurso.entries.map((entry) {
                  final nombreCurso = cursos[entry.key] ?? 'Curso';
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                        child: Text(nombreCurso, style: const TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      ...entry.value.map((asignatura) => CheckboxListTile(
                            title: Text(asignatura.nombre),
                            value: asignatura.profesorIds.contains(profesor.uid),
                            onChanged: (asignar) async {
                              try {
                                await db.asignarProfesorAAsignatura(
                                  asignaturaId: asignatura.id!,
                                  profesorId: profesor.uid,
                                  asignar: asignar == true,
                                );
                              } catch (e) {
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(mensajeError(e, porDefecto: 'No se pudo actualizar.'))),
                                );
                              }
                            },
                          )),
                    ],
                  );
                }).toList(),
              );
            },
          );
        },
      ),
    );
  }
}
