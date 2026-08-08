import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import '../../models/asignatura.dart';
import '../../models/curso.dart';
import '../../models/usuario.dart';
import '../../services/ajustes_service.dart';
import '../../services/db_service.dart';
import '../../utils/iconos_asignatura.dart';
import '../comunes/asignatura_detalle_screen.dart';

/// Asignaturas del profesor agrupadas por curso: un profesor puede dar
/// la "misma" asignatura (p. ej. Armonía) en varios cursos distintos —
/// son documentos `Asignatura` independientes con el mismo nombre, así
/// que sin agrupar aparecían varias tarjetas idénticas sin forma de
/// distinguir a qué curso pertenece cada una (reportado durante el
/// piloto).
class DashboardProfesorScreen extends StatelessWidget {
  final Usuario perfil;

  const DashboardProfesorScreen({super.key, required this.perfil});

  @override
  Widget build(BuildContext context) {
    final db = DbService();
    return Scaffold(
      body: StreamBuilder<List<Asignatura>>(
        stream: db.asignaturasDeProfesor(perfil.uid),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final asignaturas = snapshot.data!;
          if (asignaturas.isEmpty) {
            return const Center(child: Text('Todavía no tienes asignaturas asignadas.'));
          }
          return FutureBuilder<List<Curso>>(
            future: db.cursos().first,
            builder: (context, snapCursos) {
              if (!snapCursos.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final cursoPorId = {for (final c in snapCursos.data!) c.id: c};

              final grupos = <String, ({Curso? curso, List<Asignatura> asignaturas})>{};
              for (final asignatura in asignaturas) {
                final curso = cursoPorId[asignatura.cursoId];
                final clave = curso?.id ?? '_sin_curso';
                final actual = grupos[clave];
                grupos[clave] = (
                  curso: curso,
                  asignaturas: [...(actual?.asignaturas ?? const []), asignatura],
                );
              }
              final entradas = grupos.values.toList()
                ..sort((a, b) {
                  if (a.curso == null) return 1;
                  if (b.curso == null) return -1;
                  return a.curso!.nivel.index != b.curso!.nivel.index
                      ? a.curso!.nivel.index.compareTo(b.curso!.nivel.index)
                      : (a.curso!.numeroCurso ?? 0).compareTo(b.curso!.numeroCurso ?? 0);
                });

              final escalaIconos = context.watch<AjustesService>().escalaIconos;
              return ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  for (final entrada in entradas) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                      child: Text(
                        entrada.curso?.nombre ?? 'Sin curso',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                    GridView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 140,
                        mainAxisSpacing: 16,
                        crossAxisSpacing: 16,
                        childAspectRatio: 0.85,
                      ),
                      itemCount: entrada.asignaturas.length,
                      itemBuilder: (context, i) {
                        final asignatura = entrada.asignaturas[i];
                        final icono = iconoAsignaturaPorId(asignatura.iconoId);
                        return InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  AsignaturaDetalleScreen(asignatura: asignatura, perfil: perfil),
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 64 * escalaIconos,
                                height: 64 * escalaIconos,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Theme.of(context).colorScheme.primaryContainer,
                                ),
                                child: Center(
                                  child: FaIcon(
                                    icono.icono,
                                    size: 28 * escalaIconos,
                                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                asignatura.nombre,
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ],
              );
            },
          );
        },
      ),
    );
  }
}
