import 'package:flutter/material.dart';
import '../../models/curso.dart';
import '../../models/usuario.dart';
import '../../services/db_service.dart';
import 'alumno_perfil_screen.dart';
import 'crear_alumno_screen.dart';

class AlumnosScreen extends StatelessWidget {
  const AlumnosScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final db = DbService();
    return Scaffold(
      body: StreamBuilder<List<Usuario>>(
        stream: db.alumnosDelCentro(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final alumnos = snapshot.data!;
          if (alumnos.isEmpty) {
            return const Center(child: Text('Aún no hay alumnos dados de alta.'));
          }
          return StreamBuilder<String>(
            stream: db.cursoEscolarActivo(),
            builder: (context, snapActivo) {
              if (!snapActivo.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              return FutureBuilder<Map<String, List<Curso>>>(
                future: db.cursosPorAlumno(cursoEscolar: snapActivo.data!),
                builder: (context, snapCursos) {
                  if (!snapCursos.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final cursosPorAlumno = snapCursos.data!;

                  final grupos = <String, ({Curso? curso, List<Usuario> alumnos})>{};
                  for (final alumno in alumnos) {
                    final cursos = cursosPorAlumno[alumno.uid] ?? const [];
                    if (cursos.isEmpty) {
                      final actual = grupos['_sin_matricular'];
                      grupos['_sin_matricular'] = (
                        curso: null,
                        alumnos: [...(actual?.alumnos ?? const []), alumno],
                      );
                      continue;
                    }
                    for (final curso in cursos) {
                      final actual = grupos[curso.id];
                      grupos[curso.id!] = (
                        curso: curso,
                        alumnos: [...(actual?.alumnos ?? const []), alumno],
                      );
                    }
                  }

                  final entradas = grupos.values.toList()
                    ..sort((a, b) {
                      if (a.curso == null) return 1;
                      if (b.curso == null) return -1;
                      return a.curso!.nivel.index != b.curso!.nivel.index
                          ? a.curso!.nivel.index.compareTo(b.curso!.nivel.index)
                          : (a.curso!.numeroCurso ?? 0).compareTo(b.curso!.numeroCurso ?? 0);
                    });

                  return ListView(
                    children: [
                      for (final entrada in entradas) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                          child: Text(
                            entrada.curso?.nombre ?? 'Sin matricular',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ),
                        for (final alumno in entrada.alumnos)
                          ListTile(
                            leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                            title: Text(alumno.nombre),
                            subtitle: Text(alumno.email),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => AlumnoPerfilScreen(alumno: alumno)),
                            ),
                          ),
                        const Divider(height: 1),
                      ],
                    ],
                  );
                },
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CrearAlumnoScreen()),
        ),
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Nuevo alumno'),
      ),
    );
  }
}
