import 'dart:math';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../../models/asignatura.dart';
import '../../models/matricula.dart';
import '../../models/sesion_estudio.dart';
import '../../models/usuario.dart';
import '../../services/db_service.dart';
import '../../widgets/error_carga.dart';
import '../../utils/iconos_asignatura.dart';

/// Sistema de horas pendientes SEMANALES de estudio, por asignatura
/// (pedido por dirección): un "rosco" (anillo) se va rellenando según
/// se acumulan horas efectivas de la semana en curso hasta llegar al
/// objetivo (`Asignatura.horasObjetivoSemanal`, ya existía — ver
/// CLAUDE.md punto 52); al llegar, el rosco se sustituye por una
/// medalla. Solo se muestran las asignaturas matriculadas CON objetivo
/// semanal configurado — sin objetivo no hay nada que rellenar.
///
/// Reutiliza `DbService.historialAlumno()` (ya "provably compliant"
/// para alumno leyendo sus propias sesiones, ver CLAUDE.md) y agrega en
/// cliente, mismo patrón que el resto de agregaciones de la app
/// mientras no haya Cloud Functions desplegadas.
class MedallasRoscosScreen extends StatelessWidget {
  final Usuario perfil;

  const MedallasRoscosScreen({super.key, required this.perfil});

  @override
  Widget build(BuildContext context) {
    final db = DbService();
    return Scaffold(
      appBar: AppBar(title: const Text('Medallas y roscos')),
      body: StreamBuilder<String>(
        stream: db.cursoEscolarActivo(),
        builder: (context, snapActivo) {
          if (snapActivo.hasError) {
            return const ErrorCarga();
          }
          if (!snapActivo.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return StreamBuilder<List<Matricula>>(
            stream: db.matriculasDeAlumno(perfil.uid, cursoEscolar: snapActivo.data!),
            builder: (context, snapMatriculas) {
              if (snapMatriculas.hasError) {
                return const ErrorCarga();
              }
              if (!snapMatriculas.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final matriculas = snapMatriculas.data!;
              if (matriculas.isEmpty) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Todavía no estás matriculado en ninguna asignatura.'),
                  ),
                );
              }
              return StreamBuilder<List<SesionEstudio>>(
                stream: db.historialAlumno(perfil.uid),
                builder: (context, snapSesiones) {
                  if (snapSesiones.hasError) {
                    return const ErrorCarga();
                  }
                  if (!snapSesiones.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final horasSemana = _horasSemanaPorAsignatura(snapSesiones.data!);
                  return FutureBuilder<List<Asignatura>>(
                    future: Future.wait(matriculas.map((m) => db.asignatura(m.asignaturaId)))
                        .then((r) => r.whereType<Asignatura>().toList()),
                    builder: (context, snapAsignaturas) {
                      if (snapAsignaturas.hasError) {
                        return const ErrorCarga();
                      }
                      if (!snapAsignaturas.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final conObjetivo = snapAsignaturas.data!
                          .where((a) => a.horasObjetivoSemanal > 0)
                          .toList()
                        ..sort((a, b) => a.nombre.compareTo(b.nombre));
                      if (conObjetivo.isEmpty) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                              'Ninguna de tus asignaturas tiene un objetivo semanal de horas '
                              'configurado todavía.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        );
                      }
                      return ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: conObjetivo.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final asignatura = conObjetivo[i];
                          // Plus de orquesta (ver CLAUDE.md): suma horas
                          // fijas/semana si alguna otra matrícula activa
                          // del alumno lo aplica hacia esta asignatura.
                          return FutureBuilder<double>(
                            future: db.horasPlusOrquestaSemanalDeAlumno(
                              alumnoId: perfil.uid,
                              asignaturaDestinoId: asignatura.id!,
                              cursoEscolar: snapActivo.data!,
                            ),
                            builder: (context, snapPlus) => _FilaRoscoOMedalla(
                              asignatura: asignatura,
                              horasSemana: (horasSemana[asignatura.id] ?? 0) + (snapPlus.data ?? 0),
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
        },
      ),
    );
  }

  Map<String, double> _horasSemanaPorAsignatura(List<SesionEstudio> sesiones) {
    final ahora = DateTime.now();
    final hoy = DateTime(ahora.year, ahora.month, ahora.day);
    final lunes = hoy.subtract(Duration(days: ahora.weekday - 1));
    final siguienteLunes = lunes.add(const Duration(days: 7));

    final resultado = <String, double>{};
    for (final sesion in sesiones) {
      final asignaturaId = sesion.asignaturaId;
      if (asignaturaId == null || asignaturaId.isEmpty) continue;
      if (sesion.fechaInicio.isBefore(lunes) || !sesion.fechaInicio.isBefore(siguienteLunes)) continue;
      resultado[asignaturaId] = (resultado[asignaturaId] ?? 0) + sesion.duracionEfectivaMs / 3600000;
    }
    return resultado;
  }
}

class _FilaRoscoOMedalla extends StatelessWidget {
  final Asignatura asignatura;
  final double horasSemana;

  const _FilaRoscoOMedalla({required this.asignatura, required this.horasSemana});

  @override
  Widget build(BuildContext context) {
    final objetivo = asignatura.horasObjetivoSemanal;
    final cumplido = horasSemana >= objetivo;
    final icono = iconoAsignaturaPorId(asignatura.iconoId);
    final progreso = objetivo > 0 ? (horasSemana / objetivo).clamp(0.0, 1.0) : 0.0;
    final porcentaje = (progreso * 100).round();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            height: 56,
            child: cumplido
                ? Icon(Icons.emoji_events, size: 40, color: Colors.amber.shade700)
                : CustomPaint(
                    painter: _RoscoPainter(
                      progreso: progreso,
                      color: Theme.of(context).colorScheme.primary,
                      fondo: Theme.of(context).colorScheme.surfaceContainerHighest,
                    ),
                    child: Center(
                      child: FaIcon(icono.icono, size: 18, color: Theme.of(context).colorScheme.primary),
                    ),
                  ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(asignatura.nombre,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 2),
                Text(
                  cumplido
                      ? '${horasSemana.toStringAsFixed(1)} h esta semana · objetivo cumplido'
                      : 'Faltan ${(objetivo - horasSemana).toStringAsFixed(1)} h · $porcentaje% completado',
                  style: TextStyle(
                    color: cumplido ? Colors.green : Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: cumplido ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Anillo de progreso simple: arco relleno proporcional a [progreso]
/// (0-1) sobre una pista de fondo, mismo espíritu que un donut chart
/// mínimo — sin librería nueva, un solo `CustomPainter`.
class _RoscoPainter extends CustomPainter {
  final double progreso;
  final Color color;
  final Color fondo;

  _RoscoPainter({required this.progreso, required this.color, required this.fondo});

  @override
  void paint(Canvas canvas, Size size) {
    const grosor = 5.0;
    final centro = size.center(Offset.zero);
    final radio = (min(size.width, size.height) - grosor) / 2;
    final rect = Rect.fromCircle(center: centro, radius: radio);

    final pistaPaint = Paint()
      ..color = fondo
      ..style = PaintingStyle.stroke
      ..strokeWidth = grosor;
    canvas.drawCircle(centro, radio, pistaPaint);

    if (progreso <= 0) return;
    final progresoPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = grosor
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, -pi / 2, 2 * pi * progreso, false, progresoPaint);
  }

  @override
  bool shouldRepaint(covariant _RoscoPainter oldDelegate) =>
      oldDelegate.progreso != progreso || oldDelegate.color != color || oldDelegate.fondo != fondo;
}
