import 'package:flutter/material.dart';
import '../../models/asignatura.dart';
import '../../models/matricula.dart';
import '../../models/usuario.dart';
import '../../services/db_service.dart';

enum HorarioModo { alumno, profesor }

/// Horario visible de alumno/profesor (ver CLAUDE.md, horario general):
/// misma fuente de datos que `HorarioGeneralScreen`
/// (`Matricula.horaInicio`/`horaFin`), agrupado por día en vez de en
/// rejilla — para UNA sola persona una lista se lee mejor que una
/// tabla. La propagación automática de cambios (punto 14) sale gratis
/// al ser un `StreamBuilder` sobre la misma matrícula que edita
/// dirección.
class HorarioScreen extends StatelessWidget {
  final Usuario perfil;
  final HorarioModo modo;

  const HorarioScreen({super.key, required this.perfil, required this.modo});

  @override
  Widget build(BuildContext context) {
    final db = DbService();
    return Scaffold(
      appBar: AppBar(title: const Text('Horario')),
      body: StreamBuilder<String>(
        stream: db.cursoEscolarActivo(),
        builder: (context, snapActivo) {
          if (!snapActivo.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final cursoEscolar = snapActivo.data!;
          return FutureBuilder<List<Matricula>>(
            future: modo == HorarioModo.alumno
                ? db.matriculasDeAlumno(perfil.uid, cursoEscolar: cursoEscolar).first
                : db.matriculasDeProfesor(profesorId: perfil.uid, cursoEscolar: cursoEscolar),
            builder: (context, snapMatriculas) {
              if (!snapMatriculas.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final conHorario = snapMatriculas.data!
                  .where((m) => m.horaInicio.isNotEmpty && m.diasSemana.isNotEmpty)
                  .toList();
              if (conHorario.isEmpty) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Todavía no tienes ninguna clase con horario configurado.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }
              return FutureBuilder<List<Asignatura>>(
                future: Future.wait(conHorario.map((m) => m.asignaturaId).toSet().map(db.asignatura))
                    .then((r) => r.whereType<Asignatura>().toList()),
                builder: (context, snapAsignaturas) {
                  if (!snapAsignaturas.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final asignaturaPorId = {for (final a in snapAsignaturas.data!) a.id!: a};

                  return modo == HorarioModo.alumno
                      ? _agenda(context, db, conHorario, asignaturaPorId, mostrarAlumno: false)
                      : FutureBuilder<List<Usuario>>(
                          future: db.alumnosDelCentro().first,
                          builder: (context, snapAlumnos) {
                            if (!snapAlumnos.hasData) {
                              return const Center(child: CircularProgressIndicator());
                            }
                            final alumnoPorId = {for (final a in snapAlumnos.data!) a.uid: a};
                            return _agenda(context, db, conHorario, asignaturaPorId,
                                mostrarAlumno: true, alumnoPorId: alumnoPorId);
                          },
                        );
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _agenda(
    BuildContext context,
    DbService db,
    List<Matricula> matriculas,
    Map<String, Asignatura> asignaturaPorId, {
    required bool mostrarAlumno,
    Map<String, Usuario>? alumnoPorId,
  }) {
    final porDia = <int, List<Matricula>>{};
    for (final m in matriculas) {
      for (final dia in m.diasSemana) {
        (porDia[dia] ??= []).add(m);
      }
    }
    for (final lista in porDia.values) {
      lista.sort((a, b) => a.horaInicio.compareTo(b.horaInicio));
    }
    final dias = porDia.keys.toList()..sort();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final dia in dias) ...[
          Text(nombresDiasSemanaCompletos[dia - 1],
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          for (final m in porDia[dia]!)
            Card(
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: ListTile(
                leading: const Icon(Icons.schedule_outlined),
                title: Text(asignaturaPorId[m.asignaturaId]?.nombre ?? '…'),
                subtitle: Text(mostrarAlumno && alumnoPorId != null
                    ? '${m.horaInicio} - ${m.horaFin} · ${alumnoPorId[m.alumnoId]?.nombre ?? '…'}'
                    : '${m.horaInicio} - ${m.horaFin}'),
              ),
            ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

const nombresDiasSemanaCompletos = [
  'Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado', 'Domingo',
];
