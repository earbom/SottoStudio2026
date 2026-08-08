import 'package:flutter/material.dart';
import '../../models/asignatura.dart';
import '../../models/matricula.dart';
import '../../models/usuario.dart';
import '../../services/db_service.dart';
import '../../widgets/selector_curso_escolar.dart';

class _FilaRanking {
  final Usuario alumno;
  final double horasEfectivasMes;
  _FilaRanking(this.alumno, this.horasEfectivasMes);
}

/// Ranking de horas efectivas dentro de UNA asignatura. Por privacidad
/// (hay menores implicados, ver CLAUDE.md), solo lo ven profesor y
/// dirección — y un profesor solo ve a SUS alumnos asignados en esa
/// asignatura, nunca a los de otro profesor (misma restricción que ya
/// aplica al listado de matriculados en AsignaturaDetalleScreen).
/// Se puede consultar un curso escolar anterior (ver CLAUDE.md,
/// discriminación por curso escolar), no solo el activo.
class RankingAsignaturaScreen extends StatefulWidget {
  final Asignatura asignatura;
  final Usuario perfil;

  const RankingAsignaturaScreen(
      {super.key, required this.asignatura, required this.perfil});

  @override
  State<RankingAsignaturaScreen> createState() =>
      _RankingAsignaturaScreenState();
}

class _RankingAsignaturaScreenState extends State<RankingAsignaturaScreen> {
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

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<String>(
      stream: _db.cursoEscolarActivo(),
      builder: (context, snapActivo) {
        if (!snapActivo.hasData) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        final activo = snapActivo.data!;
        final cursoEscolar = _cursoSeleccionado ?? activo;
        return Scaffold(
          appBar: AppBar(
            title: Text('Ranking · ${widget.asignatura.nombre}'),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(28),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Center(
                  child: SelectorCursoEscolar(
                    cursoMostrado: cursoEscolar,
                    esActivo: cursoEscolar == activo,
                    onPressed: () => _elegirCursoEscolar(activo),
                  ),
                ),
              ),
            ),
          ),
          body: StreamBuilder<List<Matricula>>(
            stream: _db.matriculasDeAsignatura(widget.asignatura.id!,
                cursoEscolar: cursoEscolar),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final matriculas = widget.perfil.esDireccion
                  ? snapshot.data!
                  : snapshot.data!
                      .where((m) => m.profesorId == widget.perfil.uid)
                      .toList();

              if (matriculas.isEmpty) {
                return const Center(
                    child: Text('No hay alumnos para mostrar en el ranking.'));
              }

              return FutureBuilder<({List<_FilaRanking> filas, double objetivo})>(
                future: _cargarDatosRanking(_db, matriculas),
                builder: (context, snapRanking) {
                  if (!snapRanking.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final filas = snapRanking.data!.filas;
                  final objetivo = snapRanking.data!.objetivo;
                  final tieneObjetivo = objetivo > 0;
                  return Column(
                    children: [
                      if (tieneObjetivo)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                          child: Text(
                              'Objetivo mensual: ${objetivo.toStringAsFixed(1)} h efectivas'),
                        ),
                      Expanded(
                        child: ListView.separated(
                          itemCount: filas.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, i) {
                            final fila = filas[i];
                            final cumple = !tieneObjetivo ||
                                fila.horasEfectivasMes >= objetivo;
                            return ListTile(
                              leading: CircleAvatar(child: Text('${i + 1}')),
                              title: Text(fila.alumno.nombre),
                              trailing: Text(
                                '${fila.horasEfectivasMes.toStringAsFixed(1)} h / mes',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: !tieneObjetivo
                                      ? null
                                      : (cumple ? Colors.green : Colors.red),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        );
      },
    );
  }

  Future<({List<_FilaRanking> filas, double objetivo})> _cargarDatosRanking(
      DbService db, List<Matricula> matriculas) async {
    final curso = await db.curso(widget.asignatura.cursoId);
    final filas = await _calcularRanking(db, matriculas);
    return (filas: filas, objetivo: curso?.horasObjetivoMensual ?? 0);
  }

  Future<List<_FilaRanking>> _calcularRanking(
      DbService db, List<Matricula> matriculas) async {
    final ahora = DateTime.now();
    final inicioMes = DateTime(ahora.year, ahora.month, 1);
    final filas = <_FilaRanking>[];
    for (final matricula in matriculas) {
      final alumno = await db.obtenerUsuario(matricula.alumnoId);
      if (alumno == null) continue;
      final sesiones = await db
          .sesionesDeAlumnoEnAsignatura(
              alumnoId: matricula.alumnoId,
              asignaturaId: matricula.asignaturaId)
          .first;
      final horasMes = sesiones
              .where((s) => !s.fechaInicio.isBefore(inicioMes))
              .fold<int>(0, (acc, s) => acc + s.duracionEfectivaMs) /
          3600000;
      filas.add(_FilaRanking(alumno, horasMes));
    }
    filas.sort((a, b) => b.horasEfectivasMes.compareTo(a.horasEfectivasMes));
    return filas;
  }
}
