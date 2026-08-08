import 'package:flutter/material.dart';
import '../../models/asignatura.dart';
import '../../models/curso.dart';
import '../../models/usuario.dart';
import '../../services/db_service.dart';

/// Permite a dirección asignar/desasignar un profesor a varias
/// asignaturas (una asignatura puede tener más de un profesor).
class ProfesorAsignaturasScreen extends StatelessWidget {
  final Usuario profesor;

  const ProfesorAsignaturasScreen({super.key, required this.profesor});

  @override
  Widget build(BuildContext context) {
    final db = DbService();
    return Scaffold(
      appBar: AppBar(title: Text('Asignaturas de ${profesor.nombre}')),
      body: StreamBuilder<List<Curso>>(
        stream: db.cursos(),
        builder: (context, snapCursos) {
          if (!snapCursos.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final cursos = {for (final c in snapCursos.data!) c.id!: c.nombre};

          return StreamBuilder<List<Asignatura>>(
            stream: db.todasLasAsignaturas(),
            builder: (context, snapAsignaturas) {
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
                            onChanged: (asignar) => db.asignarProfesorAAsignatura(
                              asignaturaId: asignatura.id!,
                              profesorId: profesor.uid,
                              asignar: asignar == true,
                            ),
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
