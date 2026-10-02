import 'package:flutter/material.dart';
import '../../models/usuario.dart';
import '../../services/db_service.dart';
import '../direccion/alumno_perfil_screen.dart';
import '../direccion/crear_alumno_screen.dart';
import '../../widgets/acciones_usuario.dart';
import '../../widgets/error_carga.dart';
import '../../widgets/campo_busqueda.dart';

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
class AlumnosScreen extends StatefulWidget {
  final Usuario perfil;

  const AlumnosScreen({super.key, required this.perfil});

  @override
  State<AlumnosScreen> createState() => _AlumnosScreenState();
}

class _AlumnosScreenState extends State<AlumnosScreen> {
  final db = DbService();
  late final _stream = db.alumnosDelCentro();
  String _busqueda = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: StreamBuilder<List<Usuario>>(
        stream: _stream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const ErrorCarga();
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final alumnos = filtrarUsuarios(snapshot.data!, _busqueda);
          return _ListaAlfabetica(
            buscador: CampoBusqueda(
              hint: 'Buscar alumno por nombre, apellidos o email',
              onChanged: (v) => setState(() => _busqueda = v),
            ),
            hayBusqueda: _busqueda.trim().isNotEmpty,
            alumnos: alumnos,
            pie: SeccionDadosDeBaja(stream: db.alumnosDadosDeBaja()),
            onTap: (alumno) => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => AlumnoPerfilScreen(alumno: alumno, perfil: widget.perfil)),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => CrearAlumnoScreen(perfil: widget.perfil)),
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
  final Widget pie;
  final Widget buscador;
  final bool hayBusqueda;

  const _ListaAlfabetica({
    required this.alumnos,
    required this.onTap,
    required this.pie,
    required this.buscador,
    required this.hayBusqueda,
  });

  @override
  Widget build(BuildContext context) {
    final ordenados = [...alumnos]
      ..sort((a, b) => _claveOrden(a).compareTo(_claveOrden(b)));

    // Agrupado por letra inicial del apellido (o nombre de respaldo):
    // se inserta una cabecera cada vez que cambia la primera letra de
    // la lista ya ordenada, mismo patrón visual que
    // _ListaAgrupadaPorInstrumento en cuadro_de_honor_screen.dart.
    final hijos = <Widget>[buscador];
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
    if (ordenados.isEmpty) {
      hijos.add(Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
            child: Text(hayBusqueda
                ? 'Ningún alumno coincide con la búsqueda.'
                : 'Aún no hay alumnos. Pulsa «Nuevo alumno» para dar de alta el primero.')),
      ));
    }
    if (!hayBusqueda) hijos.add(pie);
    // Hueco final para que el botón flotante no tape la última fila.
    hijos.add(const SizedBox(height: 88));
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
