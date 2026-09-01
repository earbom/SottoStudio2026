import 'package:flutter/material.dart';
import '../../models/asignatura.dart';
import '../../models/criterio_evaluacion.dart';
import '../../models/nota.dart';
import '../../models/usuario.dart';
import '../../services/db_service.dart';

/// Dirección ya no valida nota por nota (era demasiado trabajo:
/// aprobar cada examen suelto de cada alumno) — solo valida la NOTA
/// FINAL de un alumno en una asignatura, y solo cuando ese alumno ya
/// tiene una nota puesta para TODOS los criterios de evaluación
/// configurados (excluyendo las horas de estudio, que ni siquiera son
/// un criterio). Mientras falte algún criterio, ese alumno·asignatura
/// simplemente no aparece en esta lista.
class NotasPendientesScreen extends StatelessWidget {
  const NotasPendientesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final db = DbService();
    return Scaffold(
      body: StreamBuilder<List<Nota>>(
        stream: db.notasPendientesSupervision(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final pendientes = snapshot.data!;
          if (pendientes.isEmpty) {
            return const Center(child: Text('No hay notas pendientes de supervisión.'));
          }

          // Agrupadas por alumno+asignatura: cada grupo es una posible
          // "nota final" a validar, no una nota suelta.
          final grupos = <String, List<Nota>>{};
          for (final n in pendientes) {
            (grupos['${n.alumnoId}_${n.asignaturaId}'] ??= []).add(n);
          }

          return ListView(
            children: [
              for (final grupo in grupos.values)
                _FilaNotaFinal(
                  alumnoId: grupo.first.alumnoId,
                  asignaturaId: grupo.first.asignaturaId,
                  notasPendientesIds: grupo.map((n) => n.id!).toList(),
                  db: db,
                ),
            ],
          );
        },
      ),
    );
  }
}

class _FilaNotaFinal extends StatelessWidget {
  final String alumnoId;
  final String asignaturaId;
  final List<String> notasPendientesIds;
  final DbService db;

  const _FilaNotaFinal({
    required this.alumnoId,
    required this.asignaturaId,
    required this.notasPendientesIds,
    required this.db,
  });

  Future<void> _marcar(BuildContext context, EstadoNota estado) async {
    try {
      await db.actualizarEstadoNotas(notasPendientesIds, estado);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo actualizar: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<CriterioEvaluacion>>(
      future: db.criteriosDeAsignatura(asignaturaId).first,
      builder: (context, snapCriterios) {
        if (!snapCriterios.hasData) return const SizedBox.shrink();
        final criterios = snapCriterios.data!;
        // Sin criterios configurados no hay "nota final" que validar.
        if (criterios.isEmpty) return const SizedBox.shrink();

        return FutureBuilder<List<Nota>>(
          future: db.notasDeAlumno(alumnoId).first,
          builder: (context, snapNotas) {
            if (!snapNotas.hasData) return const SizedBox.shrink();
            final notas = snapNotas.data!.where((n) => n.asignaturaId == asignaturaId).toList();

            // Completo = hay al menos una nota (de cualquier estado)
            // por cada criterio configurado.
            final criterioIds = criterios.map((c) => c.id).toSet();
            final cubiertos = notas.map((n) => n.criterioId).toSet();
            if (!criterioIds.every(cubiertos.contains)) return const SizedBox.shrink();

            // Nota ponderada con la MÁS RECIENTE de cada criterio.
            final criteriosPorId = {for (final c in criterios) c.id!: c};
            final masRecientePorCriterio = <String, Nota>{};
            for (final n in notas) {
              final actual = masRecientePorCriterio[n.criterioId];
              if (actual == null || n.fecha.isAfter(actual.fecha)) {
                masRecientePorCriterio[n.criterioId] = n;
              }
            }
            final notaFinal = masRecientePorCriterio.values.fold<double>(0, (acc, n) {
              final criterio = criteriosPorId[n.criterioId];
              if (criterio == null) return acc;
              return acc + n.valor * criterio.peso / 100;
            });

            return FutureBuilder<Usuario?>(
              future: db.obtenerUsuario(alumnoId),
              builder: (context, snapAlumno) {
                final nombreAlumno = snapAlumno.data?.nombre ?? alumnoId;
                return FutureBuilder<Asignatura?>(
                  future: db.asignatura(asignaturaId),
                  builder: (context, snapAsignatura) {
                    final nombreAsignatura = snapAsignatura.data?.nombre ?? asignaturaId;
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('$nombreAlumno · $nombreAsignatura',
                                style: const TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            Text('Nota final: ${notaFinal.toStringAsFixed(2)}'),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () => _marcar(context, EstadoNota.supervisada),
                                    child: const Text('Marcar supervisada'),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: FilledButton(
                                    onPressed: () => _marcar(context, EstadoNota.corregida),
                                    child: const Text('Marcar corregida'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}
