import 'package:flutter/material.dart';
import '../../models/curso.dart';
import '../../models/usuario.dart';
import '../../services/db_service.dart';
import '../direccion/alumno_perfil_screen.dart';
import '../direccion/crear_alumno_screen.dart';
import 'alumno_asistencia_hoy_screen.dart';

/// Listado de alumnos, alfabético por apellidos, SIN agrupar por
/// curso (un alumno puede tener asignaturas de cursos distintos, así
/// que la agrupación por curso dejó de tener sentido — reportado en
/// el piloto). Para dirección es el listado completo del centro, con
/// acceso a la ficha del alumno (boletín de notas) y de alta de
/// nuevos alumnos. Para profesor es solo SUS alumnos (los que tiene
/// asignados, ver `DbService.alumnosDeProfesorAgrupados`), y tocar uno
/// lleva directamente a marcar la asistencia de hoy — pensado para no
/// tener que entrar en cada asignatura por separado.
class AlumnosScreen extends StatelessWidget {
  final Usuario perfil;

  const AlumnosScreen({super.key, required this.perfil});

  @override
  Widget build(BuildContext context) {
    final db = DbService();
    return Scaffold(
      body: StreamBuilder<String>(
        stream: db.cursoEscolarActivo(),
        builder: (context, snapActivo) {
          if (!snapActivo.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final cursoEscolar = snapActivo.data!;

          if (!perfil.esDireccion) {
            return FutureBuilder<({List<Usuario> alumnos, Map<String, List<Curso>> cursosPorAlumno})>(
              future: db.alumnosDeProfesorAgrupados(profesorId: perfil.uid, cursoEscolar: cursoEscolar),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.data!.alumnos.isEmpty) {
                  return const Center(child: Text('Todavía no tienes alumnos asignados.'));
                }
                return _ListaAlfabetica(
                  alumnos: snap.data!.alumnos,
                  onTap: (alumno) => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AlumnoAsistenciaHoyScreen(alumno: alumno, perfil: perfil),
                    ),
                  ),
                );
              },
            );
          }

          return StreamBuilder<List<Usuario>>(
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
          );
        },
      ),
      floatingActionButton: perfil.esDireccion
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CrearAlumnoScreen()),
              ),
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Nuevo alumno'),
            )
          : null,
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
