import 'package:flutter/material.dart';
import '../../models/usuario.dart';
import '../../services/db_service.dart';
import '../direccion/alumno_perfil_screen.dart';
import '../direccion/crear_alumno_screen.dart';

/// Listado de alumnos del centro, alfabético por apellidos, SIN agrupar
/// por curso (un alumno puede tener asignaturas de cursos distintos, así
/// que la agrupación por curso dejó de tener sentido — reportado en el
/// piloto). Dirección-only: da acceso a la ficha del alumno (boletín de
/// notas) y de alta de nuevos alumnos.
///
/// Antes también era accesible para profesor (marcar asistencia de sus
/// alumnos de un vistazo, ver historial), pero dirección pidió
/// retirarla de ese lado: el profesor ya tiene la misma acción desde
/// "Asistencias" dentro de cada asignatura.
class AlumnosScreen extends StatelessWidget {
  final Usuario perfil;

  const AlumnosScreen({super.key, required this.perfil});

  @override
  Widget build(BuildContext context) {
    final db = DbService();
    return Scaffold(
      body: StreamBuilder<List<Usuario>>(
        stream: db.alumnosDelCentro(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final alumnos = snapshot.data!;
          if (alumnos.isEmpty) {
            return const Center(child: Text('Aún no hay alumnos dados de alta.'));
          }
          return _ListaAlfabetica(
            alumnos: alumnos,
            onTap: (alumno) => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => AlumnoPerfilScreen(alumno: alumno)),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CrearAlumnoScreen()),
        ),
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Nuevo alumno'),
      ),
    );
  }
}

class _ListaAlfabetica extends StatelessWidget {
  final List<Usuario> alumnos;
  final void Function(Usuario alumno) onTap;

  const _ListaAlfabetica({required this.alumnos, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final ordenados = [...alumnos]
      ..sort((a, b) => _claveOrden(a).compareTo(_claveOrden(b)));

    // Agrupado por letra inicial del apellido (o nombre de respaldo):
    // se inserta una cabecera cada vez que cambia la primera letra de
    // la lista ya ordenada, mismo patrón visual que
    // _ListaAgrupadaPorInstrumento en cuadro_de_honor_screen.dart.
    final hijos = <Widget>[];
    String? letraActual;
    for (final alumno in ordenados) {
      final letra = _letra(alumno);
      if (letra != letraActual) {
        if (letraActual != null) hijos.add(const Divider(height: 1));
        hijos.add(Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(letra,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        ));
        letraActual = letra;
      }
      hijos.add(_filaAlumno(context, alumno));
    }
    return ListView(children: hijos);
  }

  Widget _filaAlumno(BuildContext context, Usuario alumno) {
    final apellidos = alumno.apellidos;
    final etiqueta =
        (apellidos != null && apellidos.isNotEmpty) ? '$apellidos, ${alumno.nombre}' : alumno.nombre;
    return ListTile(
      leading: const CircleAvatar(child: Icon(Icons.person_outline)),
      title: Text(etiqueta),
      subtitle: Text(alumno.tieneCuenta
          ? (alumno.email ?? '')
          : 'Sin acceso a la app'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => onTap(alumno),
    );
  }

  String _letra(Usuario u) {
    final clave = _claveOrden(u);
    return clave.isEmpty ? '#' : clave[0].toUpperCase();
  }

  // Cuentas antiguas sin apellidos ordenan por nombre, sin romper.
  String _claveOrden(Usuario u) =>
      (u.apellidos != null && u.apellidos!.isNotEmpty) ? u.apellidos! : u.nombre;
}
