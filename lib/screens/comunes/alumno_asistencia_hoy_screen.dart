import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/asignatura.dart';
import '../../models/asistencia.dart';
import '../../models/usuario.dart';
import '../../services/db_service.dart';

/// Marcar la asistencia de HOY de un alumno concreto, desde el punto
/// de vista del profesor: solo muestra las asignaturas de ese alumno
/// que este profesor imparte (o donde tiene una sustitución activa
/// hoy, ver CLAUDE.md punto 10) Y que tienen clase programada hoy
/// según `Matricula.diasSemana`. Pensado para marcar asistencia sin
/// tener que entrar en cada asignatura por separado.
class AlumnoAsistenciaHoyScreen extends StatefulWidget {
  final Usuario alumno;
  final Usuario perfil;

  const AlumnoAsistenciaHoyScreen({super.key, required this.alumno, required this.perfil});

  @override
  State<AlumnoAsistenciaHoyScreen> createState() => _AlumnoAsistenciaHoyScreenState();
}

class _AlumnoAsistenciaHoyScreenState extends State<AlumnoAsistenciaHoyScreen> {
  final DbService _db = DbService();
  bool _cargando = true;
  List<Asignatura> _asignaturasHoy = [];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final cursoEscolar = await _db.cursoEscolarActivo().first;
    final hoy = DateTime.now();

    // 1) Asignaturas donde el profesor es el asignado habitual de
    //    este alumno.
    final matriculasPropias = await _db.matriculasDeAlumnoImpartidasPorProfesor(
      alumnoId: widget.alumno.uid,
      profesorId: widget.perfil.uid,
      cursoEscolar: cursoEscolar,
    );
    final idsHoy = <String>{
      for (final m in matriculasPropias)
        if (m.diasSemana.contains(hoy.weekday)) m.asignaturaId,
    };

    // 2) Asignaturas donde el profesor tiene sustitución activa hoy Y
    //    el alumno está matriculado hoy, aunque el profesor habitual
    //    de ese alumno sea otro — la sustitución cubre a TODOS los
    //    alumnos de la asignatura ese día concreto.
    final todasLasAsignaturas = await _db.todasLasAsignaturas().first;
    for (final asignatura in todasLasAsignaturas) {
      if (idsHoy.contains(asignatura.id)) continue;
      final tieneSustitucion = await _db.tieneSustitucionEnFecha(
        asignaturaId: asignatura.id!,
        profesorId: widget.perfil.uid,
        fecha: hoy,
      );
      if (!tieneSustitucion) continue;
      final matriculas =
          await _db.matriculasDeAsignatura(asignatura.id!, cursoEscolar: cursoEscolar).first;
      final propia = matriculas.where((m) => m.alumnoId == widget.alumno.uid);
      if (propia.isNotEmpty && propia.first.diasSemana.contains(hoy.weekday)) {
        idsHoy.add(asignatura.id!);
      }
    }

    final asignaturas = todasLasAsignaturas.where((a) => idsHoy.contains(a.id)).toList()
      ..sort((a, b) => a.nombre.compareTo(b.nombre));

    if (!mounted) return;
    setState(() {
      _asignaturasHoy = asignaturas;
      _cargando = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.alumno.nombre)),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _asignaturasHoy.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Este alumno no tiene ninguna clase contigo programada hoy.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _asignaturasHoy.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) => _FilaAsistenciaHoy(
                    alumno: widget.alumno,
                    asignatura: _asignaturasHoy[i],
                    perfil: widget.perfil,
                    db: _db,
                  ),
                ),
    );
  }
}

class _FilaAsistenciaHoy extends StatefulWidget {
  final Usuario alumno;
  final Asignatura asignatura;
  final Usuario perfil;
  final DbService db;

  const _FilaAsistenciaHoy({
    required this.alumno,
    required this.asignatura,
    required this.perfil,
    required this.db,
  });

  @override
  State<_FilaAsistenciaHoy> createState() => _FilaAsistenciaHoyState();
}

class _FilaAsistenciaHoyState extends State<_FilaAsistenciaHoy> {
  Asistencia? _asistenciaHoy;
  bool _marcando = false;
  StreamSubscription<Asistencia?>? _asistenciaSub;

  @override
  void initState() {
    super.initState();
    // En vivo, no un fetch de un solo uso: si esta misma asistencia se
    // marca desde otra pantalla mientras esta fila sigue montada, se
    // refresca sola (mismo motivo que _FilaMatricula en
    // asignatura_detalle_screen.dart, ver CLAUDE.md punto 24).
    _asistenciaSub = widget.db
        .asistenciaDelDiaStream(
      alumnoId: widget.alumno.uid,
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

  Future<void> _marcar(bool asistio, {bool retraso = false}) async {
    setState(() => _marcando = true);
    await widget.db.marcarAsistencia(
      alumnoId: widget.alumno.uid,
      asignaturaId: widget.asignatura.id!,
      fecha: DateTime.now(),
      asistio: asistio,
      retraso: retraso,
      marcadaPor: widget.perfil.uid,
    );
    // El StreamSubscription de arriba refresca _asistenciaHoy solo.
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.asignatura.nombre,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            _marcando
                ? const SizedBox(
                    height: 24, width: 24, child: CircularProgressIndicator(strokeWidth: 2))
                : Wrap(
                    spacing: 8,
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
          ],
        ),
      ),
    );
  }
}
