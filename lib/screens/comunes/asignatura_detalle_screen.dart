import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/asignatura.dart';
import '../../models/asistencia.dart';
import '../../models/matricula.dart';
import '../../models/usuario.dart';
import '../../services/db_service.dart';
import '../../widgets/selector_curso_escolar.dart';
import '../direccion/criterios_evaluacion_screen.dart';
import '../direccion/sustituciones_screen.dart';
import 'alumno_en_asignatura_screen.dart';
import 'ranking_asignatura_screen.dart';

const nombresDiasSemana = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];

/// Diálogo para configurar la matrícula de UN alumno en esta
/// asignatura: días de clase semanales y qué profesor concreto le
/// corresponde. Es por alumno (no por asignatura) porque las clases
/// de instrumento suelen ser individuales, y una asignatura puede
/// tener varios profesores con alumnos distintos (p.ej. dos de
/// guitarra) — solo el profesor aquí asignado puede poner notas o
/// marcar asistencia de este alumno (ver Sustitucion para bajas).
Future<({List<int> dias, String profesorId})?> _configurarMatricula(
  BuildContext context, {
  required List<Usuario> profesoresDeLaAsignatura,
  List<int> diasIniciales = const [],
  String profesorIdInicial = '',
}) {
  final seleccionados = diasIniciales.toSet();
  String profesorId = profesorIdInicial;

  return showDialog<({List<int> dias, String profesorId})>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setStateDialog) => AlertDialog(
        title: const Text('Configurar matrícula'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Días de clase'),
              Wrap(
                spacing: 6,
                children: List.generate(7, (i) {
                  final dia = i + 1;
                  return FilterChip(
                    label: Text(nombresDiasSemana[i]),
                    selected: seleccionados.contains(dia),
                    onSelected: (v) => setStateDialog(() {
                      v ? seleccionados.add(dia) : seleccionados.remove(dia);
                    }),
                  );
                }),
              ),
              const SizedBox(height: 16),
              const Text('Profesor asignado'),
              if (profesoresDeLaAsignatura.isEmpty)
                const Text('Esta asignatura no tiene profesores todavía.',
                    style: TextStyle(fontStyle: FontStyle.italic))
              else
                DropdownButtonFormField<String>(
                  initialValue: profesorId.isEmpty ? null : profesorId,
                  hint: const Text('Sin asignar'),
                  items: profesoresDeLaAsignatura
                      .map((p) =>
                          DropdownMenuItem(value: p.uid, child: Text(p.nombre)))
                      .toList(),
                  onChanged: (v) => setStateDialog(() => profesorId = v ?? ''),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(context,
                (dias: seleccionados.toList()..sort(), profesorId: profesorId)),
            child: const Text('Guardar'),
          ),
        ],
      ),
    ),
  );
}

/// Pantalla compartida entre dirección y profesor: matriculados de la
/// asignatura y acceso a la vista por alumno.
class AsignaturaDetalleScreen extends StatefulWidget {
  final Asignatura asignatura;
  final Usuario perfil;

  const AsignaturaDetalleScreen(
      {super.key, required this.asignatura, required this.perfil});

  @override
  State<AsignaturaDetalleScreen> createState() =>
      _AsignaturaDetalleScreenState();
}

class _AsignaturaDetalleScreenState extends State<AsignaturaDetalleScreen> {
  final DbService _db = DbService();
  bool _sustitucionHoy = false;
  bool _cargandoSustitucion = true;
  // null = ver el curso escolar activo. Solo se puede matricular/editar/
  // marcar asistencia cuando se está viendo el activo — un curso pasado
  // es solo consulta (ver CLAUDE.md, discriminación por curso escolar).
  String? _cursoSeleccionado;

  @override
  void initState() {
    super.initState();
    _comprobarSustitucionHoy();
  }

  Future<void> _elegirCursoEscolar(String activo) async {
    final historial = await _db.historialCursosEscolares().first;
    if (!mounted) return;
    final elegido = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Ver curso escolar'),
        children: historial.reversed
            .map((curso) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, curso),
                  child: Row(
                    children: [
                      Expanded(child: Text(curso)),
                      if (curso == activo)
                        const Text('(activo)',
                            style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                ))
            .toList(),
      ),
    );
    if (elegido == null) return;
    setState(() => _cursoSeleccionado = elegido == activo ? null : elegido);
  }

  Future<void> _comprobarSustitucionHoy() async {
    if (!widget.perfil.esProfesor) {
      setState(() => _cargandoSustitucion = false);
      return;
    }
    final tiene = await _db.tieneSustitucionEnFecha(
      asignaturaId: widget.asignatura.id!,
      profesorId: widget.perfil.uid,
      fecha: DateTime.now(),
    );
    if (!mounted) return;
    setState(() {
      _sustitucionHoy = tiene;
      _cargandoSustitucion = false;
    });
  }

  Future<List<Usuario>> _profesoresDeLaAsignatura() async {
    final todos = await _db.profesoresDelCentro().first;
    return todos
        .where((p) => widget.asignatura.profesorIds.contains(p.uid))
        .toList();
  }

  Future<void> _matricularAlumno() async {
    final cursoEscolar = await _db.cursoEscolarActivo().first;
    final todosLosAlumnos = await _db.alumnosDelCentro().first;
    final matriculasActuales = await _db
        .matriculasDeAsignatura(widget.asignatura.id!,
            cursoEscolar: cursoEscolar)
        .first;
    final profesores = await _profesoresDeLaAsignatura();
    if (!mounted) return;

    final idsYaMatriculados = matriculasActuales.map((m) => m.alumnoId).toSet();
    final disponibles = todosLosAlumnos
        .where((a) => !idsYaMatriculados.contains(a.uid))
        .toList();

    if (disponibles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Todos los alumnos del centro ya están matriculados aquí.')),
      );
      return;
    }

    final elegido = await showDialog<Usuario>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Matricular alumno'),
        children: disponibles
            .map((a) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, a),
                  child: Text(a.nombre),
                ))
            .toList(),
      ),
    );

    if (elegido == null) return;
    if (!mounted) return;

    final config = await _configurarMatricula(context,
        profesoresDeLaAsignatura: profesores);
    if (config == null) return;

    await _db.matricular(
      alumnoId: elegido.uid,
      asignaturaId: widget.asignatura.id!,
      cursoId: widget.asignatura.cursoId,
      cursoEscolar: cursoEscolar,
      diasSemana: config.dias,
      profesorId: config.profesorId,
    );
  }

  Future<void> _editarMatricula(Matricula matricula) async {
    final profesores = await _profesoresDeLaAsignatura();
    if (!mounted) return;
    final config = await _configurarMatricula(
      context,
      profesoresDeLaAsignatura: profesores,
      diasIniciales: matricula.diasSemana,
      profesorIdInicial: matricula.profesorId,
    );
    if (config == null) return;
    await _db.actualizarDiasClaseMatricula(
      alumnoId: matricula.alumnoId,
      asignaturaId: widget.asignatura.id!,
      cursoEscolar: matricula.cursoEscolar,
      diasSemana: config.dias,
    );
    await _db.actualizarProfesorMatricula(
      alumnoId: matricula.alumnoId,
      asignaturaId: widget.asignatura.id!,
      cursoEscolar: matricula.cursoEscolar,
      profesorId: config.profesorId,
    );
  }

  @override
  Widget build(BuildContext context) {
    final asignatura = widget.asignatura;

    return StreamBuilder<String>(
      stream: _db.cursoEscolarActivo(),
      builder: (context, snapActivo) {
        if (!snapActivo.hasData) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        final activo = snapActivo.data!;
        final cursoEfectivo = _cursoSeleccionado ?? activo;
        final esActivo = cursoEfectivo == activo;

        return Scaffold(
          appBar: AppBar(
            title: Text(asignatura.nombre),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(28),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Center(
                  child: SelectorCursoEscolar(
                    cursoMostrado: cursoEfectivo,
                    esActivo: esActivo,
                    onPressed: () => _elegirCursoEscolar(activo),
                  ),
                ),
              ),
            ),
            actions: [
              // Ranking: nunca para alumno (vería nombres/rendimiento de
              // compañeros menores de edad). Esta pantalla en la práctica
              // solo la abren profesor/dirección, pero se comprueba aquí
              // también por si cambia la navegación en el futuro.
              if (widget.perfil.esDireccion || widget.perfil.esProfesor)
                IconButton(
                  icon: const Icon(Icons.emoji_events_outlined),
                  tooltip: 'Ranking',
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => RankingAsignaturaScreen(
                          asignatura: asignatura, perfil: widget.perfil),
                    ),
                  ),
                ),
              if (widget.perfil.esDireccion) ...[
                IconButton(
                  icon: const Icon(Icons.rule_outlined),
                  tooltip: 'Criterios de evaluación',
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          CriteriosEvaluacionScreen(asignatura: asignatura),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.swap_horiz),
                  tooltip: 'Sustituciones',
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          SustitucionesScreen(asignatura: asignatura),
                    ),
                  ),
                ),
              ],
            ],
          ),
          body: _cargandoSustitucion
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    if (_sustitucionHoy && esActivo)
                      Container(
                        width: double.infinity,
                        color: Colors.blue.withValues(alpha: 0.15),
                        padding: const EdgeInsets.all(12),
                        child: const Text(
                          'Sustitución activa hoy: ves todos los alumnos de la asignatura.',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    Expanded(
                      child: StreamBuilder<List<Matricula>>(
                        stream: _db.matriculasDeAsignatura(asignatura.id!,
                            cursoEscolar: cursoEfectivo),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) {
                            return const Center(
                                child: CircularProgressIndicator());
                          }
                          final esMio = !widget.perfil.esDireccion &&
                              !(_sustitucionHoy && esActivo);
                          final matriculas = esMio
                              ? snapshot.data!
                                  .where(
                                      (m) => m.profesorId == widget.perfil.uid)
                                  .toList()
                              : snapshot.data!;
                          if (matriculas.isEmpty) {
                            return Center(
                              child: Text(esMio
                                  ? 'No tienes alumnos asignados en esta asignatura todavía.'
                                  : 'Aún no hay alumnos matriculados.'),
                            );
                          }
                          return ListView.separated(
                            itemCount: matriculas.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (context, i) => _FilaMatricula(
                              key: ValueKey(matriculas[i].id),
                              matricula: matriculas[i],
                              asignatura: asignatura,
                              perfil: widget.perfil,
                              db: _db,
                              soloLectura: !esActivo,
                              onEditarMatricula: () =>
                                  _editarMatricula(matriculas[i]),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
          floatingActionButton: widget.perfil.esDireccion && esActivo
              ? FloatingActionButton.extended(
                  onPressed: _matricularAlumno,
                  icon: const Icon(Icons.person_add_alt_1),
                  label: const Text('Matricular alumno'),
                )
              : null,
        );
      },
    );
  }
}

/// Fila de un alumno matriculado: nombre, profesor y — si quien mira
/// puede marcar asistencia (profesor/dirección) — tres botones para
/// asistió/retraso/faltó de HOY sin tener que entrar en el detalle del
/// alumno. Es su propio StatefulWidget (no un FutureBuilder anidado
/// más) porque necesita refrescar solo su estado de asistencia tras
/// marcar, sin recargar la lista de matriculados entera.
class _FilaMatricula extends StatefulWidget {
  final Matricula matricula;
  final Asignatura asignatura;
  final Usuario perfil;
  final DbService db;
  final VoidCallback onEditarMatricula;
  // true cuando se está consultando un curso escolar pasado (no el
  // activo): oculta edición de matrícula y botones rápidos de
  // asistencia, ver CLAUDE.md.
  final bool soloLectura;

  const _FilaMatricula({
    super.key,
    required this.matricula,
    required this.asignatura,
    required this.perfil,
    required this.db,
    required this.onEditarMatricula,
    this.soloLectura = false,
  });

  @override
  State<_FilaMatricula> createState() => _FilaMatriculaState();
}

class _FilaMatriculaState extends State<_FilaMatricula> {
  Usuario? _alumno;
  Usuario? _profesor;
  Asistencia? _asistenciaHoy;
  bool _marcando = false;
  bool _cargado = false;
  StreamSubscription<Asistencia?>? _asistenciaSub;

  @override
  void initState() {
    super.initState();
    _cargarDatos();
    // En vivo (no un fetch de un solo uso): si la asistencia de hoy se
    // marca desde otra pantalla (p. ej. el calendario del detalle del
    // alumno) mientras esta fila sigue montada debajo en la pila de
    // navegación, se refresca sola al volver — antes se quedaba
    // congelada con el valor de cuando se montó la fila.
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
    final profesor = widget.matricula.profesorId.isEmpty
        ? null
        : await widget.db.obtenerUsuario(widget.matricula.profesorId);
    if (!mounted) return;
    setState(() {
      _alumno = alumno;
      _profesor = profesor;
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
    // No hace falta releer aquí: el StreamSubscription de arriba
    // recibirá la actualización y refrescará _asistenciaHoy solo.
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
          child: Icon(icon,
              size: 20, color: activo ? color : Colors.grey.shade600),
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

    final dias = widget.matricula.diasSemana
        .map((d) => nombresDiasSemana[d - 1])
        .join(', ');
    final diasTexto = dias.isEmpty ? 'sin días' : dias;
    final nombre = _alumno?.nombre ?? widget.matricula.alumnoId;
    final nombreProfesor = widget.matricula.profesorId.isEmpty
        ? 'sin profesor asignado'
        : (_profesor?.nombre ?? widget.matricula.profesorId);
    final puedeMarcar = !widget.soloLectura &&
        (widget.perfil.esDireccion || widget.perfil.esProfesor);

    return ListTile(
      leading: const CircleAvatar(child: Icon(Icons.person_outline)),
      title: Text(nombre),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$diasTexto · Profesor: $nombreProfesor'),
          if (puedeMarcar) ...[
            const SizedBox(height: 6),
            _marcando
                ? const SizedBox(
                    height: 24,
                    width: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Wrap(
                    spacing: 6,
                    children: [
                      _botonAsistencia(
                        icon: Icons.check_circle_outline,
                        tooltip: 'Asistió',
                        activo: _asistenciaHoy?.asistio == true &&
                            _asistenciaHoy?.retraso != true,
                        color: Colors.green,
                        onPressed: () => _marcar(true),
                      ),
                      _botonAsistencia(
                        icon: Icons.watch_later_outlined,
                        tooltip: 'Retraso',
                        activo: _asistenciaHoy?.asistio == true &&
                            _asistenciaHoy?.retraso == true,
                        color: Colors.orange,
                        onPressed: () => _marcar(true, retraso: true),
                      ),
                      _botonAsistencia(
                        icon: Icons.cancel_outlined,
                        tooltip: 'Faltó',
                        activo:
                            _asistenciaHoy != null && !_asistenciaHoy!.asistio,
                        color: Colors.red,
                        onPressed: () => _marcar(false),
                      ),
                    ],
                  ),
          ],
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.perfil.esDireccion && !widget.soloLectura)
            IconButton(
              icon: const Icon(Icons.edit_calendar_outlined),
              tooltip: 'Editar matrícula',
              onPressed: widget.onEditarMatricula,
            ),
          const Icon(Icons.chevron_right),
        ],
      ),
      onTap: () {
        if (_alumno == null) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => AlumnoEnAsignaturaScreen(
              alumno: _alumno!,
              asignatura: widget.asignatura,
              perfil: widget.perfil,
              cursoEscolar: widget.matricula.cursoEscolar,
            ),
          ),
        );
      },
    );
  }
}
