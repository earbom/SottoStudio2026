import 'package:flutter/material.dart';
import '../../models/asignatura.dart';
import '../../models/matricula.dart';
import '../../models/usuario.dart';
import '../../services/db_service.dart';
import 'asistencias_asignatura_screen.dart';
import 'horas_asignatura_screen.dart';
import 'notas_asignatura_grid_screen.dart';

/// Todo lo que un profesor vería por separado en Asistencias, Notas y
/// Horas de estudio de una asignatura, apilado en una sola ventana con
/// scroll — pedido explícitamente por dirección tras probar el menú de
/// secciones (`SeccionesAsignaturaScreen`) y encontrar tener que entrar
/// en cada apartado por separado poco ágil. Reutiliza el mismo `Cuerpo*`
/// que cada pantalla dedicada (sin su propio Scaffold/AppBar), así que
/// cualquier cambio en una de esas tres sigue aplicando aquí sin
/// duplicar lógica. Horas de estudio se muestra siempre del curso
/// escolar ACTIVO, sin el selector de curso escolar anteriores que sí
/// tiene `HorasAsignaturaScreen` en solitario — mantiene esta vista
/// simple, para consultar el día a día, no el histórico.
class VistaGlobalAsignaturaScreen extends StatelessWidget {
  final Asignatura asignatura;
  final Usuario perfil;
  final String cursoEscolar;

  const VistaGlobalAsignaturaScreen({
    super.key,
    required this.asignatura,
    required this.perfil,
    required this.cursoEscolar,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Vista global · ${asignatura.nombre}')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (asignatura.horasObjetivoMensual > 0)
              _Seccion(
                titulo: 'Progreso del objetivo este mes',
                child: _ProgresoObjetivoAsignatura(asignatura: asignatura, cursoEscolar: cursoEscolar),
              ),
            _Seccion(
              titulo: 'Asistencia de hoy',
              child: CuerpoAsistenciasAsignatura(
                asignatura: asignatura,
                perfil: perfil,
                cursoEscolar: cursoEscolar,
                dentroDeScroll: true,
              ),
            ),
            _Seccion(
              titulo: 'Notas',
              child: CuerpoNotasAsignatura(
                asignatura: asignatura,
                perfil: perfil,
                cursoEscolar: cursoEscolar,
              ),
            ),
            _Seccion(
              titulo: 'Horas de estudio · $cursoEscolar',
              child: CuerpoHorasAsignatura(
                asignatura: asignatura,
                perfil: perfil,
                cursoEscolar: cursoEscolar,
                dentroDeScroll: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Resumen "de un vistazo" (pedido explícitamente por dirección): quién
/// ya llegó al objetivo mensual de horas efectivas y a quién le falta
/// cuánto — sin tener que leer la cuadrícula de 12 meses de la sección
/// de Horas de estudio de más abajo. Horas del MES EN CURSO (no el
/// mes vencido del Cuadro de Honor, ver CLAUDE.md — aquí interesa el
/// progreso de hoy, no un cierre). Solo se muestra esta sección si la
/// asignatura tiene objetivo configurado (ver el `if` en el padre).
class _ProgresoObjetivoAsignatura extends StatelessWidget {
  final Asignatura asignatura;
  final String cursoEscolar;

  const _ProgresoObjetivoAsignatura({required this.asignatura, required this.cursoEscolar});

  @override
  Widget build(BuildContext context) {
    final db = DbService();
    final objetivo = asignatura.horasObjetivoMensual;
    return StreamBuilder<List<Matricula>>(
      stream: db.matriculasDeAsignatura(asignatura.id!, cursoEscolar: cursoEscolar),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final matriculas = snapshot.data!;
        if (matriculas.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text('Aún no hay alumnos matriculados.'),
          );
        }
        return FutureBuilder<List<({Usuario alumno, double horasMes})>>(
          future: _cargar(db, matriculas),
          builder: (context, snapFilas) {
            if (!snapFilas.hasData) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final filas = [...snapFilas.data!]
              ..sort((a, b) => a.alumno.nombre.compareTo(b.alumno.nombre));
            return Column(
              children: [
                for (final fila in filas)
                  ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      backgroundColor:
                          fila.horasMes >= objetivo ? Colors.green.withValues(alpha: 0.15) : null,
                      child: Icon(
                        fila.horasMes >= objetivo ? Icons.emoji_events_outlined : Icons.person_outline,
                        color: fila.horasMes >= objetivo ? Colors.green : null,
                      ),
                    ),
                    title: Text(fila.alumno.nombre),
                    trailing: Text(
                      fila.horasMes >= objetivo
                          ? 'Objetivo cumplido'
                          : 'Faltan ${(objetivo - fila.horasMes).toStringAsFixed(1)} h',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: fila.horasMes >= objetivo ? Colors.green : Colors.red,
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Future<List<({Usuario alumno, double horasMes})>> _cargar(
      DbService db, List<Matricula> matriculas) async {
    final ahora = DateTime.now();
    final inicioMes = DateTime(ahora.year, ahora.month, 1);
    final finMes = DateTime(ahora.year, ahora.month + 1, 1);
    final resultado = <({Usuario alumno, double horasMes})>[];
    for (final m in matriculas) {
      final alumno = await db.obtenerUsuario(m.alumnoId);
      if (alumno == null) continue;
      final sesiones =
          await db.sesionesDeAlumnoEnAsignatura(alumnoId: m.alumnoId, asignaturaId: m.asignaturaId).first;
      final ms = sesiones
          .where((s) => !s.fechaInicio.isBefore(inicioMes) && s.fechaInicio.isBefore(finMes))
          .fold<int>(0, (acc, s) => acc + s.duracionEfectivaMs);
      // Plus de orquesta (ver CLAUDE.md): misma aproximación
      // minutosSemana × 4 / 60 que en la cuadrícula mensual de Horas.
      final pluses = await db.plusesOrquestaAplicablesDeAlumno(
        alumnoId: m.alumnoId,
        asignaturaDestinoId: asignatura.id!,
        cursoEscolar: cursoEscolar,
      );
      final plusMes = pluses
          .where((p) => !p.desde.isAfter(finMes))
          .fold<double>(0, (acc, p) => acc + p.minutosSemana * 4 / 60.0);
      resultado.add((alumno: alumno, horasMes: ms / 3600000 + plusMes));
    }
    return resultado;
  }
}

class _Seccion extends StatelessWidget {
  final String titulo;
  final Widget child;

  const _Seccion({required this.titulo, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
          child: Text(titulo,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        ),
        child,
        const Divider(height: 32),
      ],
    );
  }
}
