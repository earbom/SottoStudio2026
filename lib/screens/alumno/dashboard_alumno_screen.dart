import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../../models/matricula.dart';
import '../../models/asignatura.dart';
import '../../models/usuario.dart';
import '../../services/db_service.dart';
import '../../utils/iconos_asignatura.dart';
import '../comunes/alumno_en_asignatura_screen.dart';
import 'empezar_estudio_screen.dart';
import 'grabar_estudio_screen.dart';
import 'historial_estudio_screen.dart';
import 'mis_notas_screen.dart';

class DashboardAlumnoScreen extends StatelessWidget {
  final Usuario perfil;

  const DashboardAlumnoScreen({super.key, required this.perfil});

  @override
  Widget build(BuildContext context) {
    final db = DbService();
    final esquema = Theme.of(context).colorScheme;
    final primerNombre = perfil.nombre.trim().split(RegExp(r'\s+')).first;
    final subtitulo = (perfil.instrumento?.trim().isNotEmpty ?? false)
        ? 'Instrumento: ${perfil.instrumento}'
        : 'Aquí tienes tus asignaturas y tu progreso.';

    return Scaffold(
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  top: 2,
                  right: 0,
                  width: 110,
                  height: 30,
                  child: _Pentagrama(
                    color: esquema.primary.withValues(alpha: 0.16),
                    lineas: 5,
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Hola, $primerNombre',
                      style: TextStyle(
                        fontSize: 27,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                        color: esquema.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitulo,
                      style: TextStyle(
                        fontSize: 14.5,
                        color: esquema.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Row(
              children: [
                _accionRapida(
                  context,
                  icono: Icons.mic_none_outlined,
                  etiqueta: 'Empezar\nestudio',
                  acento: esquema.primary,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => EmpezarEstudioScreen(perfil: perfil)),
                  ),
                ),
                _accionRapida(
                  context,
                  icono: Icons.history,
                  etiqueta: 'Historial\nde estudio',
                  acento: esquema.secondary,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) =>
                            HistorialEstudioScreen(alumnoId: perfil.uid)),
                  ),
                ),
                _accionRapida(
                  context,
                  icono: Icons.grade_outlined,
                  etiqueta: 'Mis\nnotas',
                  acento: esquema.tertiary,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) =>
                            MisNotasScreen(alumnoId: perfil.uid)),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 6),
            child: Text(
              'Tus asignaturas',
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
                color: esquema.onSurface,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: SizedBox(
              height: 8,
              child: _Pentagrama(color: esquema.outlineVariant, lineas: 2),
            ),
          ),
          const SizedBox(height: 8),
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
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                      child: Text(
                        'Todavía no tienes asignaturas. En cuanto dirección '
                        'te matricule, aparecerán aquí.',
                        style: TextStyle(color: esquema.onSurfaceVariant),
                      ),
                    );
                  }
                  return Column(
                    children: matriculas
                        .map((m) => FutureBuilder<Asignatura?>(
                              future: db.asignatura(m.asignaturaId),
                              builder: (context, snapAsignatura) {
                                final asignatura = snapAsignatura.data;
                                if (asignatura == null) {
                                  return const SizedBox.shrink();
                                }
                                final icono =
                                    iconoAsignaturaPorId(asignatura.iconoId);
                                return Container(
                                  margin: const EdgeInsets.fromLTRB(
                                      20, 0, 20, 14),
                                  padding: const EdgeInsets.fromLTRB(
                                      14, 12, 14, 12),
                                  decoration: BoxDecoration(
                                    border: Border(
                                      left: BorderSide(
                                          color: esquema.primary, width: 3),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          FaIcon(icono.icono,
                                              size: 17,
                                              color: esquema.primary),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              asignatura.nombre,
                                              style: TextStyle(
                                                fontWeight: FontWeight.w600,
                                                fontSize: 16,
                                                color: esquema.onSurface,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 10),
                                      Row(
                                        children: [
                                          if (asignatura
                                              .permiteGrabarEstudio) ...[
                                            Expanded(
                                              child: FilledButton(
                                                onPressed: () =>
                                                    Navigator.push(
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
                                                child: const Text(
                                                    'Grabar estudio'),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                          ],
                                          Expanded(
                                            child: OutlinedButton(
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
                                              child:
                                                  const Text('Mi progreso'),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
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

  Widget _accionRapida(
    BuildContext context, {
    required IconData icono,
    required String etiqueta,
    required Color acento,
    required VoidCallback onTap,
  }) {
    final esquema = Theme.of(context).colorScheme;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          child: Column(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: acento.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(icono, color: acento, size: 24),
              ),
              const SizedBox(height: 8),
              Text(
                etiqueta,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  height: 1.15,
                  color: esquema.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Cinco líneas finas evocando un pentagrama: motivo visual propio del
/// centro (conservatorio), reutilizado como flourish bajo el saludo y,
/// con 2 líneas, como separador de la sección de asignaturas.
class _Pentagrama extends StatelessWidget {
  final Color color;
  final int lineas;

  const _Pentagrama({required this.color, this.lineas = 5});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _PentagramaPainter(color: color, lineas: lineas));
  }
}

class _PentagramaPainter extends CustomPainter {
  final Color color;
  final int lineas;

  _PentagramaPainter({required this.color, required this.lineas});

  @override
  void paint(Canvas canvas, Size size) {
    final pintura = Paint()
      ..color = color
      ..strokeWidth = 1.1;
    final espacio = size.height / (lineas + 1);
    for (var i = 1; i <= lineas; i++) {
      final y = espacio * i;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), pintura);
    }
  }

  @override
  bool shouldRepaint(covariant _PentagramaPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.lineas != lineas;
}
