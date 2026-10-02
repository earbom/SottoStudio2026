import 'package:flutter/material.dart';
import '../../models/nota.dart';
import '../../models/asignatura.dart';
import '../../models/criterio_evaluacion.dart';
import '../../widgets/error_carga.dart';
import '../../services/db_service.dart';

/// Todas las notas del alumno, agrupadas por asignatura, con la nota
/// ponderada acumulada de cada una (mismo cálculo que en
/// alumno_en_asignatura_screen.dart: Σ(valor × peso/100)).
class MisNotasScreen extends StatelessWidget {
  final String alumnoId;

  const MisNotasScreen({super.key, required this.alumnoId});

  @override
  Widget build(BuildContext context) {
    final db = DbService();
    return Scaffold(
      appBar: AppBar(title: const Text('Mis notas')),
      body: StreamBuilder<List<Nota>>(
        stream: db.notasDeAlumno(alumnoId),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const ErrorCarga();
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final notas = snapshot.data!;
          if (notas.isEmpty) {
            return const Center(child: Text('Aún no tienes notas registradas.'));
          }

          final porAsignatura = <String, List<Nota>>{};
          for (final n in notas) {
            porAsignatura.putIfAbsent(n.asignaturaId, () => []).add(n);
          }

          return ListView(
            children: porAsignatura.entries.map((entry) {
              return FutureBuilder<Asignatura?>(
                future: db.asignatura(entry.key),
                builder: (context, snapAsignatura) {
                  final nombreAsignatura = snapAsignatura.data?.nombre ?? '…';
                  final diasRetraso = snapAsignatura.data?.diasRetrasoVisibilidadNotas ?? 0;
                  return FutureBuilder<List<CriterioEvaluacion>>(
                    future: db.criteriosDeAsignatura(entry.key).first,
                    builder: (context, snapCriterios) {
                      final criterios = {
                        for (final c in snapCriterios.data ?? <CriterioEvaluacion>[]) c.id!: c
                      };
                      // Retraso de visibilidad (ver CLAUDE.md): esta
                      // pantalla es siempre el propio alumno mirando sus
                      // notas, así que se filtra sin condición de rol —
                      // a diferencia de _TabNotas, que también la usan
                      // profesor/dirección viendo a OTRO alumno.
                      final notasAsignatura = entry.value
                          .where((n) => !n.fecha
                              .add(Duration(days: diasRetraso))
                              .isAfter(DateTime.now()))
                          .toList();
                      if (notasAsignatura.isEmpty) return const SizedBox.shrink();
                      final notaPonderada = notasAsignatura.fold<double>(0, (acc, n) {
                        final criterio = criterios[n.criterioId];
                        if (criterio == null) return acc;
                        return acc + n.valor * criterio.peso / 100;
                      });

                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(nombreAsignatura,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                  Text('Nota final: ${notaPonderada.toStringAsFixed(2).replaceAll('.', ',')}',
                                      style: const TextStyle(fontWeight: FontWeight.bold)),
                                ],
                              ),
                              const Divider(),
                              ...notasAsignatura.map((nota) {
                                final criterio = criterios[nota.criterioId];
                                final nombreCriterio = criterio?.nombre ?? '(criterio eliminado)';
                                final peso = criterio != null ? ' · ${criterio.peso.toStringAsFixed(0)}%' : '';
                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  child: Row(
                                    children: [
                                      Expanded(child: Text('$nombreCriterio$peso')),
                                      Text(nota.valor.toStringAsFixed(1),
                                          style: const TextStyle(fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                );
                              }),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              );
            }).toList(),
          );
        },
      ),
    );
  }
}
