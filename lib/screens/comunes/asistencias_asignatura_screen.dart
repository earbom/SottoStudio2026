import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/asignatura.dart';
import '../../models/asistencia.dart';
import '../../models/matricula.dart';
import '../../models/usuario.dart';
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
class CuerpoAsistenciasAsignatura extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final db = DbService();
    return StreamBuilder<List<Matricula>>(
      stream: db.matriculasDeAsignatura(asignatura.id!, cursoEscolar: cursoEscolar),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final matriculas = snapshot.data!;
        if (matriculas.isEmpty) {
          return const Center(child: Text('Aún no hay alumnos matriculados.'));
        }
        return ListView.separated(
          shrinkWrap: dentroDeScroll,
          physics: dentroDeScroll ? const NeverScrollableScrollPhysics() : null,
          itemCount: matriculas.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, i) => _FilaAsistenciaHoy(
            key: ValueKey(matriculas[i].id),
            matricula: matriculas[i],
            asignatura: asignatura,
            perfil: perfil,
            db: db,
          ),
        );
      },
    );
  }
}

class _FilaAsistenciaHoy extends StatefulWidget {
  final Matricula matricula;
  final Asignatura asignatura;
  final Usuario perfil;
  final DbService db;

  const _FilaAsistenciaHoy({
    super.key,
    required this.matricula,
    required this.asignatura,
    required this.perfil,
    required this.db,
  });

  @override
  State<_FilaAsistenciaHoy> createState() => _FilaAsistenciaHoyState();
}

class _FilaAsistenciaHoyState extends State<_FilaAsistenciaHoy> {
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
    });
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
    setState(() => _marcando = true);
    await widget.db.marcarAsistencia(
      alumnoId: widget.matricula.alumnoId,
      asignaturaId: widget.asignatura.id!,
      fecha: DateTime.now(),
      asistio: asistio,
      retraso: retraso,
      marcadaPor: widget.perfil.uid,
    );
    if (!mounted) return;
    setState(() => _marcando = false);
  }

  Widget _botonAsistencia({
    required IconData icon,
    required String tooltip,
    required bool activo,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onPressed,
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: activo ? color.withValues(alpha: 0.2) : Colors.transparent,
            border: Border.all(color: activo ? color : Colors.grey.shade400),
          ),
          child: Icon(icon, size: 20, color: activo ? color : Colors.grey.shade600),
        ),
      ),
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
    final nombre = _alumno?.nombre ?? widget.matricula.alumnoId;
    return ListTile(
      leading: const CircleAvatar(child: Icon(Icons.person_outline)),
      title: Text(nombre),
      subtitle: _marcando
          ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(strokeWidth: 2))
          : Wrap(
              spacing: 6,
              children: [
                _botonAsistencia(
                  icon: Icons.check_circle_outline,
                  tooltip: 'Asistió',
                  activo: _asistenciaHoy?.asistio == true && _asistenciaHoy?.retraso != true,
                  color: Colors.green,
                  onPressed: () => _marcar(true),
                ),
                _botonAsistencia(
                  icon: Icons.watch_later_outlined,
                  tooltip: 'Retraso',
                  activo: _asistenciaHoy?.asistio == true && _asistenciaHoy?.retraso == true,
                  color: Colors.orange,
                  onPressed: () => _marcar(true, retraso: true),
                ),
                _botonAsistencia(
                  icon: Icons.cancel_outlined,
                  tooltip: 'Faltó',
                  activo: _asistenciaHoy != null && !_asistenciaHoy!.asistio,
                  color: Colors.red,
                  onPressed: () => _marcar(false),
                ),
              ],
            ),
    );
  }
}
