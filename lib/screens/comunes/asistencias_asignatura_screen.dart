import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/asignatura.dart';
import '../../models/asistencia.dart';
import '../../models/matricula.dart';
import '../../models/usuario.dart';
import '../../widgets/error_carga.dart';
import '../../services/db_service.dart';

/// Vista "solo asistencia de HOY" de TODOS los alumnos de un
/// curso+asignatura, para el flujo de menú-antes-de-curso del
/// profesor (ver CLAUDE.md). Extrae SOLO el patrón de 3 botones
/// rápidos de `_FilaMatricula` (asignatura_detalle_screen.dart) — sin
/// edición de matrícula ni registro de horas manuales, que no encajan
/// en esta vista dedicada. Duplicación deliberada de ese patrón en vez
/// de reutilizar el widget privado de esa pantalla (que arrastra
/// props que no pintan aquí); si se quiere extraer un mixin
/// compartido más adelante, este archivo y `_FilaMatricula` son los
/// dos puntos a unificar.
class AsistenciasAsignaturaScreen extends StatelessWidget {
  final Asignatura asignatura;
  final Usuario perfil;
  final String cursoEscolar;

  const AsistenciasAsignaturaScreen({
    super.key,
    required this.asignatura,
    required this.perfil,
    required this.cursoEscolar,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Asistencias · ${asignatura.nombre}')),
      body: CuerpoAsistenciasAsignatura(
        asignatura: asignatura,
        perfil: perfil,
        cursoEscolar: cursoEscolar,
      ),
    );
  }
}

/// Cuerpo reutilizable (sin Scaffold/AppBar propios): usado tanto por
/// [AsistenciasAsignaturaScreen] en solitario como embebido dentro de
/// `VistaGlobalAsignaturaScreen`. `dentroDeScroll` desactiva el scroll
/// propio del `ListView` (con `shrinkWrap`) cuando ya vive dentro del
/// scroll vertical de la vista global — en solitario, el `Scaffold`
/// ya le da altura acotada y el `ListView` puede scrollear solo.
class CuerpoAsistenciasAsignatura extends StatefulWidget {
  final Asignatura asignatura;
  final Usuario perfil;
  final String cursoEscolar;
  final bool dentroDeScroll;

  const CuerpoAsistenciasAsignatura({
    super.key,
    required this.asignatura,
    required this.perfil,
    required this.cursoEscolar,
    this.dentroDeScroll = false,
  });

  @override
  State<CuerpoAsistenciasAsignatura> createState() => _CuerpoAsistenciasAsignaturaState();
}

const _nombresDia = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];

/// Por defecto solo se listan los alumnos que tienen clase HOY según
/// su matrícula (pasar lista es para la clase de hoy); "Ver todos"
/// muestra el resto por si alguien vino otro día.
class _CuerpoAsistenciasAsignaturaState extends State<CuerpoAsistenciasAsignatura> {
  final db = DbService();
  late final _stream = db.matriculasDeAsignatura(widget.asignatura.id!, cursoEscolar: widget.cursoEscolar);
  bool _verTodos = false;

  @override
  Widget build(BuildContext context) {
    final hoy = DateTime.now().weekday;
    return StreamBuilder<List<Matricula>>(
      stream: _stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const ErrorCarga();
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final todas = snapshot.data!;
        if (todas.isEmpty) {
          return const Center(child: Text('Aún no hay alumnos matriculados.'));
        }
        final deHoy = todas.where((m) => m.diasSemana.contains(hoy)).toList();
        final mostradas = _verTodos ? todas : deHoy;
        final cabecera = SwitchListTile(
          title: Text(_verTodos
              ? 'Todos los alumnos (${todas.length})'
              : 'Con clase hoy, ${_nombresDia[hoy - 1]} (${deHoy.length})'),
          subtitle: const Text('Ver también a los que no tienen clase hoy'),
          value: _verTodos,
          onChanged: (v) => setState(() => _verTodos = v),
        );
        return ListView.separated(
          shrinkWrap: widget.dentroDeScroll,
          physics: widget.dentroDeScroll ? const NeverScrollableScrollPhysics() : null,
          itemCount: mostradas.length + 1 + (mostradas.isEmpty ? 1 : 0),
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, i) {
            if (i == 0) return cabecera;
            if (mostradas.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Text('Hoy no hay ningún alumno con clase en esta asignatura.', textAlign: TextAlign.center),
              );
            }
            final m = mostradas[i - 1];
            return FilaAsistenciaHoy(
              key: ValueKey(m.id),
              matricula: m,
              asignatura: widget.asignatura,
              perfil: widget.perfil,
              db: db,
              detalle: m.horaInicio.isEmpty ? null : '${m.horaInicio}-${m.horaFin}',
            );
          },
        );
      },
    );
  }
}

/// Fila de un alumno con los tres botones de asistencia de HOY.
/// Pública porque también la usa "Mis clases de hoy" en Inicio.
/// Los botones llevan texto además de color (accesibilidad: el color
/// solo no basta para daltónicos) y miden al menos 40 px de alto.
class FilaAsistenciaHoy extends StatefulWidget {
  final Matricula matricula;
  final Asignatura asignatura;
  final Usuario perfil;
  final DbService db;
  final String? detalle;

  const FilaAsistenciaHoy({
    super.key,
    required this.matricula,
    required this.asignatura,
    required this.perfil,
    required this.db,
    this.detalle,
  });

  @override
  State<FilaAsistenciaHoy> createState() => _FilaAsistenciaHoyState();
}

class _FilaAsistenciaHoyState extends State<FilaAsistenciaHoy> {
  Usuario? _alumno;
  Asistencia? _asistenciaHoy;
  bool _marcando = false;
  bool _cargado = false;
  StreamSubscription<Asistencia?>? _asistenciaSub;

  @override
  void initState() {
    super.initState();
    _cargarDatos();
    _asistenciaSub = widget.db
        .asistenciaDelDiaStream(
      alumnoId: widget.matricula.alumnoId,
      asignaturaId: widget.asignatura.id!,
      fecha: DateTime.now(),
    )
        .listen((asistencia) {
      if (!mounted) return;
      setState(() => _asistenciaHoy = asistencia);
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _asistenciaSub?.cancel();
    super.dispose();
  }

  Future<void> _cargarDatos() async {
    final alumno = await widget.db.obtenerUsuario(widget.matricula.alumnoId);
    if (!mounted) return;
    setState(() {
      _alumno = alumno;
      _cargado = true;
    });
  }

  Future<void> _marcar(bool asistio, {bool retraso = false}) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _marcando = true);
    try {
      await widget.db.marcarAsistencia(
        alumnoId: widget.matricula.alumnoId,
        asignaturaId: widget.asignatura.id!,
        fecha: DateTime.now(),
        asistio: asistio,
        retraso: retraso,
        marcadaPor: widget.perfil.uid,
      );
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('No se pudo marcar la asistencia. Inténtalo de nuevo.')));
    } finally {
      if (mounted) setState(() => _marcando = false);
    }
  }

  Widget _boton({
    required IconData icon,
    required String texto,
    required bool activo,
    required Color color,
    required VoidCallback onPressed,
  }) {
    final estilo = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(0, 40)),
      padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 10)),
      visualDensity: VisualDensity.compact,
      foregroundColor: WidgetStatePropertyAll(activo ? Colors.white : color),
      backgroundColor: WidgetStatePropertyAll(activo ? color : Colors.transparent),
      side: WidgetStatePropertyAll(BorderSide(color: color)),
    );
    return OutlinedButton.icon(
      style: estilo,
      onPressed: onPressed,
      icon: Icon(activo ? Icons.check : icon, size: 18),
      label: Text(texto),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_cargado) {
      return const ListTile(
        leading: CircleAvatar(child: Icon(Icons.person_outline)),
        title: Text('Cargando…'),
      );
    }
    final a = _alumno;
    final nombre = a == null
        ? 'Alumno'
        : ((a.apellidos?.isNotEmpty ?? false) ? '${a.nombre} ${a.apellidos}' : a.nombre);
    return ListTile(
      leading: const CircleAvatar(child: Icon(Icons.person_outline)),
      title: Text(nombre),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.detalle != null) Text(widget.detalle!),
          const SizedBox(height: 6),
          _marcando
              ? const SizedBox(height: 40, child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
              : Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _boton(
                      icon: Icons.check_circle_outline,
                      texto: 'Asistió',
                      activo: _asistenciaHoy?.asistio == true && _asistenciaHoy?.retraso != true,
                      color: Colors.green.shade700,
                      onPressed: () => _marcar(true),
                    ),
                    _boton(
                      icon: Icons.watch_later_outlined,
                      texto: 'Retraso',
                      activo: _asistenciaHoy?.asistio == true && _asistenciaHoy?.retraso == true,
                      color: Colors.orange.shade800,
                      onPressed: () => _marcar(true, retraso: true),
                    ),
                    _boton(
                      icon: Icons.cancel_outlined,
                      texto: 'Faltó',
                      activo: _asistenciaHoy != null && !_asistenciaHoy!.asistio,
                      color: Colors.red.shade700,
                      onPressed: () => _marcar(false),
                    ),
                  ],
                ),
        ],
      ),
    );
  }
}
