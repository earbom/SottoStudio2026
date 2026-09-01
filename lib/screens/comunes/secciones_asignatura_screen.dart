import 'package:flutter/material.dart';
import '../../models/asignatura.dart';
import '../../models/usuario.dart';
import 'asignatura_nombre_cursos_screen.dart';

/// Las 3 secciones que ve un profesor PURO (no dirección) al entrar en
/// una asignatura, antes de elegir curso — para cualquier asignatura,
/// no solo instrumento (ver CLAUDE.md, decisión "siempre menú antes
/// del curso"). Cada alumno se ve junto al resto para poder comparar
/// y editar sin entrar uno a uno.
enum SeccionAsignatura { asistencias, notas, horas }

/// Menú intermedio mostrado a un profesor puro al elegir una
/// asignatura por nombre, ANTES de elegir curso. Cada opción enruta a
/// AsignaturaNombreCursosScreen con `seccion` fijada, para que allí
/// elegir un curso lleve directo a la pantalla de esa sección (sin
/// pasar por AsignaturaDetalleScreen, que sigue siendo el flujo de
/// dirección).
class SeccionesAsignaturaScreen extends StatelessWidget {
  final String nombreGrupo;
  final List<Asignatura> asignaturas;
  final Usuario perfil;

  const SeccionesAsignaturaScreen({
    super.key,
    required this.nombreGrupo,
    required this.asignaturas,
    required this.perfil,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(nombreGrupo)),
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
        ],
      ),
    );
  }

  void _ir(BuildContext context, SeccionAsignatura seccion) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AsignaturaNombreCursosScreen(
          nombreGrupo: nombreGrupo,
          asignaturas: asignaturas,
          perfil: perfil,
          seccion: seccion,
        ),
      ),
    );
  }
}
