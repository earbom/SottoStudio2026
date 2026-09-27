import 'package:flutter/material.dart';
import '../../models/asignatura.dart';
import '../../models/usuario.dart';
import 'asistencias_asignatura_screen.dart';
import 'horas_asignatura_screen.dart';
import 'notas_asignatura_grid_screen.dart';
import 'vista_global_asignatura_screen.dart';

/// Las secciones que ve un profesor PURO (no dirección) al entrar en un
/// curso+asignatura ya elegidos (orden Asignatura → Curso → Menú, ver
/// CLAUDE.md) — para cualquier asignatura, no solo instrumento. Cada
/// alumno se ve junto al resto para poder comparar y editar sin entrar
/// uno a uno. `vistaGlobal` (pedida explícitamente por dirección)
/// combina las otras 3 en una sola ventana en vez de tener que entrar
/// en cada una por separado — ver `VistaGlobalAsignaturaScreen`.
enum SeccionAsignatura { asistencias, notas, horas, vistaGlobal }

/// Menú mostrado a un profesor puro tras elegir curso, en
/// `AsignaturaNombreCursosScreen` — ya no hay que volver a elegir nada
/// aquí, `asignatura`/`cursoEscolar` vienen fijados.
class SeccionesAsignaturaScreen extends StatelessWidget {
  final Asignatura asignatura;
  final Usuario perfil;
  final String cursoEscolar;

  const SeccionesAsignaturaScreen({
    super.key,
    required this.asignatura,
    required this.perfil,
    required this.cursoEscolar,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(asignatura.nombre)),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.check_circle_outline),
            title: const Text('Asistencias'),
            subtitle: const Text('Marcar la asistencia de hoy'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _ir(context, SeccionAsignatura.asistencias),
          ),
          ListTile(
            leading: const Icon(Icons.grid_on_outlined),
            title: const Text('Notas'),
            subtitle: const Text('Comparar y calificar por criterio'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _ir(context, SeccionAsignatura.notas),
          ),
          ListTile(
            leading: const Icon(Icons.timer_outlined),
            title: const Text('Horas de estudio'),
            subtitle: const Text('Horas efectivas del mes de todos los alumnos'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _ir(context, SeccionAsignatura.horas),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.dashboard_outlined),
            title: const Text('Vista global'),
            subtitle: const Text('Asistencia, notas y horas juntas en una sola ventana'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _ir(context, SeccionAsignatura.vistaGlobal),
          ),
        ],
      ),
    );
  }

  void _ir(BuildContext context, SeccionAsignatura seccion) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => pantallaDeSeccion(
          seccion: seccion,
          asignatura: asignatura,
          perfil: perfil,
          cursoEscolar: cursoEscolar,
        ),
      ),
    );
  }
}

/// Construye la pantalla final de una sección para un curso+asignatura
/// concreto, a partir del menú de [SeccionesAsignaturaScreen].
Widget pantallaDeSeccion({
  required SeccionAsignatura seccion,
  required Asignatura asignatura,
  required Usuario perfil,
  required String cursoEscolar,
}) {
  switch (seccion) {
    case SeccionAsignatura.asistencias:
      return AsistenciasAsignaturaScreen(asignatura: asignatura, perfil: perfil, cursoEscolar: cursoEscolar);
    case SeccionAsignatura.notas:
      return NotasAsignaturaGridScreen(asignatura: asignatura, perfil: perfil, cursoEscolar: cursoEscolar);
    case SeccionAsignatura.horas:
      return HorasAsignaturaScreen(asignatura: asignatura, perfil: perfil);
    case SeccionAsignatura.vistaGlobal:
      return VistaGlobalAsignaturaScreen(asignatura: asignatura, perfil: perfil, cursoEscolar: cursoEscolar);
  }
}
