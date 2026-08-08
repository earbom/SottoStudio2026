import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../../models/matricula.dart';
import '../../models/asignatura.dart';
import '../../models/usuario.dart';
import '../../services/db_service.dart';
import '../../utils/iconos_asignatura.dart';
import '../comunes/alumno_en_asignatura_screen.dart';
import 'grabar_estudio_screen.dart';
import 'historial_estudio_screen.dart';
import 'mis_notas_screen.dart';

class DashboardAlumnoScreen extends StatelessWidget {
  final Usuario perfil;

  const DashboardAlumnoScreen({super.key, required this.perfil});

  @override
  Widget build(BuildContext context) {
    final db = DbService();
    return Scaffold(
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.history),
            title: const Text('Historial de estudio'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => HistorialEstudioScreen(alumnoId: perfil.uid)),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.grade_outlined),
            title: const Text('Mis notas'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => MisNotasScreen(alumnoId: perfil.uid)),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('Mis asignaturas',
                style: Theme.of(context).textTheme.titleMedium),
          ),
          StreamBuilder<String>(
            stream: db.cursoEscolarActivo(),
            builder: (context, snapActivo) {
              if (!snapActivo.hasData) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              return StreamBuilder<List<Matricula>>(
                stream: db.matriculasDeAlumno(perfil.uid,
                    cursoEscolar: snapActivo.data!),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final matriculas = snapshot.data!;
                  if (matriculas.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                          'Todavía no estás matriculado en ninguna asignatura.'),
                    );
                  }
                  return Column(
                    children: matriculas
                        .map((m) => FutureBuilder<Asignatura?>(
                              future: db.asignatura(m.asignaturaId),
                              builder: (context, snapAsignatura) {
                                final asignatura = snapAsignatura.data;
                                if (asignatura == null)
                                  return const SizedBox.shrink();
                                final icono =
                                    iconoAsignaturaPorId(asignatura.iconoId);
                                return Card(
                                  margin: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 6),
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            FaIcon(icono.icono,
                                                size: 18,
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .primary),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(asignatura.nombre,
                                                  style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 16)),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        Row(
                                          children: [
                                            if (asignatura.permiteGrabarEstudio) ...[
                                              Expanded(
                                                child: FilledButton.icon(
                                                  onPressed: () => Navigator.push(
                                                    context,
                                                    MaterialPageRoute(
                                                      builder: (_) =>
                                                          GrabarEstudioScreen(
                                                        alumnoId: perfil.uid,
                                                        instrumento:
                                                            perfil.instrumento,
                                                        asignaturaId:
                                                            asignatura.id!,
                                                      ),
                                                    ),
                                                  ),
                                                  icon: const Icon(
                                                      Icons.mic_none_outlined),
                                                  label: const Text(
                                                      'Grabar estudio'),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                            ],
                                            Expanded(
                                              child: OutlinedButton.icon(
                                                onPressed: () => Navigator.push(
                                                  context,
                                                  MaterialPageRoute(
                                                    builder: (_) =>
                                                        AlumnoEnAsignaturaScreen(
                                                      alumno: perfil,
                                                      asignatura: asignatura,
                                                      perfil: perfil,
                                                      cursoEscolar:
                                                          snapActivo.data!,
                                                    ),
                                                  ),
                                                ),
                                                icon: const Icon(
                                                    Icons.insights_outlined),
                                                label:
                                                    const Text('Mi progreso'),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ))
                        .toList(),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}
