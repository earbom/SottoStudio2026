import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/asignatura.dart';
import '../../models/asistencia.dart';
import '../../models/matricula.dart';
import '../../models/plus_orquesta.dart';
import '../../models/usuario.dart';
import '../../services/db_service.dart';
import '../../widgets/selector_curso_escolar.dart';
import '../../widgets/campo_busqueda.dart';
import '../direccion/criterios_evaluacion_screen.dart';
import '../direccion/formulario_asignatura.dart';
import '../direccion/sustituciones_screen.dart';
import 'alumno_en_asignatura_screen.dart';
import 'horas_asignatura_screen.dart';
import '../../utils/mensaje_error.dart';
import '../../widgets/error_carga.dart';
import 'notas_asignatura_grid_screen.dart';

const nombresDiasSemana = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];

/// Diálogo para configurar la matrícula de UN alumno en esta
/// asignatura: días de clase semanales y qué profesor de referencia
/// le corresponde. Es por alumno (no por asignatura) porque las clases
/// de instrumento suelen ser individuales. Desde el permiso cruzado
/// entre cursos (ver CLAUDE.md), este campo es solo informativo —
/// CUALQUIER profesor de la asignatura (de cualquier curso que
/// comparta nombre) puede poner notas o marcar asistencia de
/// cualquier alumno, no solo el aquí asignado.
///
/// `franjasDisponibles` (no vacío cuando `Asignatura.franjasHorario`
/// tiene alguna, ver CLAUDE.md punto 69): asignaturas NO instrumentales
/// pueden tener varios grupos a días/horas distintos, configurados
/// desde la propia asignatura (`CursoDetalleScreen`) — aquí solo se
/// ELIGE a cuál pertenece este alumno, no se editan días/hora sueltos.
/// Con la lista vacía (caso normal de instrumento), el diálogo pide
/// días/hora individuales como siempre.
Future<
    ({
      List<int> dias,
      String profesorId,
      String plusOrquestaId,
      String horaInicio,
      String horaFin,
      String franjaHorarioId,
    })?> _configurarMatricula(
  BuildContext context, {
  required List<Usuario> profesoresDeLaAsignatura,
  required List<PlusOrquesta> plusesDisponibles,
  List<int> diasIniciales = const [],
  String profesorIdInicial = '',
  String plusOrquestaIdInicial = '',
  String horaInicioInicial = '',
  String horaFinInicial = '',
  List<FranjaHoraria> franjasDisponibles = const [],
  String franjaHorarioIdInicial = '',
}) {
  final seleccionados = diasIniciales.toSet();
  String profesorId = profesorIdInicial;
  String plusOrquestaId = plusOrquestaIdInicial;
  String horaInicio = horaInicioInicial;
  String horaFin = horaFinInicial;
  String franjaHorarioId = franjaHorarioIdInicial;

  Future<void> elegirHora(
      BuildContext context, void Function(String) onElegida, String actual) async {
    final partes = actual.split(':');
    final inicial = partes.length == 2
        ? TimeOfDay(hour: int.tryParse(partes[0]) ?? 9, minute: int.tryParse(partes[1]) ?? 0)
        : const TimeOfDay(hour: 9, minute: 0);
    final elegida = await showTimePicker(context: context, initialTime: inicial);
    if (elegida == null) return;
    onElegida(
        '${elegida.hour.toString().padLeft(2, '0')}:${elegida.minute.toString().padLeft(2, '0')}');
  }

  return showDialog<
      ({
        List<int> dias,
        String profesorId,
        String plusOrquestaId,
        String horaInicio,
        String horaFin,
        String franjaHorarioId,
      })>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setStateDialog) => AlertDialog(
        title: const Text('Configurar matrícula'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (franjasDisponibles.isNotEmpty) ...[
                const Text('Grupo de clase'),
                const SizedBox(height: 4),
                DropdownButtonFormField<String>(
                  initialValue: franjaHorarioId.isEmpty ? null : franjaHorarioId,
                  hint: const Text('Elige un grupo'),
                  items: franjasDisponibles
                      .map((f) => DropdownMenuItem(
                            value: f.id,
                            child: Text(
                                '${f.diasSemana.map((d) => nombresDiasSemana[d - 1]).join(', ')} · ${f.horaInicio} - ${f.horaFin}'),
                          ))
                      .toList(),
                  onChanged: (v) => setStateDialog(() => franjaHorarioId = v ?? ''),
                ),
              ] else ...[
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
                const Text('Horario (misma franja todos los días de clase elegidos)'),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => elegirHora(
                            context, (h) => setStateDialog(() => horaInicio = h), horaInicio),
                        child: Text(horaInicio.isEmpty ? 'Hora inicio' : horaInicio),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () =>
                            elegirHora(context, (h) => setStateDialog(() => horaFin = h), horaFin),
                        child: Text(horaFin.isEmpty ? 'Hora fin' : horaFin),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              const Text('Profesor habitual'),
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
              if (plusesDisponibles.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text('Plus de orquesta (suma tiempo de estudio a otra asignatura)'),
                DropdownButtonFormField<String>(
                  initialValue: plusOrquestaId.isEmpty ? null : plusOrquestaId,
                  hint: const Text('Ninguno'),
                  items: plusesDisponibles
                      .map((p) => DropdownMenuItem(
                          value: p.id,
                          child: Text('${p.nombre} (+${p.minutosSemana} min/sem)')))
                      .toList(),
                  onChanged: (v) => setStateDialog(() => plusOrquestaId = v ?? ''),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              if (franjasDisponibles.isEmpty) {
                Navigator.pop(
                    context,
                    (
                      dias: seleccionados.toList()..sort(),
                      profesorId: profesorId,
                      plusOrquestaId: plusOrquestaId,
                      horaInicio: horaInicio,
                      horaFin: horaFin,
                      franjaHorarioId: '',
                    ));
                return;
              }
              final elegidas =
                  franjasDisponibles.where((f) => f.id == franjaHorarioId).toList();
              final franja = elegidas.isEmpty ? null : elegidas.first;
              Navigator.pop(
                  context,
                  (
                    dias: franja?.diasSemana ?? const <int>[],
                    profesorId: profesorId,
                    plusOrquestaId: plusOrquestaId,
                    horaInicio: franja?.horaInicio ?? '',
                    horaFin: franja?.horaFin ?? '',
                    franjaHorarioId: franjaHorarioId,
                  ));
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    ),
  );
}

/// Pide días/hora (o grupo), profesor habitual y plus, y matricula al
/// alumno en la asignatura en el curso escolar activo. Compartido entre
/// la ficha de la asignatura y la ficha del alumno (matricular desde
/// cualquiera de los dos lados). Devuelve true si se matriculó.
Future<bool> configurarYMatricular(
  BuildContext context, {
  required Usuario alumno,
  required Asignatura asignatura,
}) async {
  final db = DbService();
  final cursoEscolar = await db.cursoEscolarActivo().first;
  final todosProfesores = await db.profesoresDelCentro().first;
  final profesores = todosProfesores.where((p) => asignatura.profesorIds.contains(p.uid)).toList();
  final pluses = await db.plusesOrquesta().first;
  if (!context.mounted) return false;
  final config = await _configurarMatricula(context,
      profesoresDeLaAsignatura: profesores,
      plusesDisponibles: pluses,
      franjasDisponibles: asignatura.franjasHorario);
  if (config == null || !context.mounted) return false;
  final messenger = ScaffoldMessenger.of(context);
  try {
    await db.matricular(
      alumnoId: alumno.uid,
      asignaturaId: asignatura.id!,
      cursoId: asignatura.cursoId,
      cursoEscolar: cursoEscolar,
      diasSemana: config.dias,
      profesorId: config.profesorId,
      plusOrquestaId: config.plusOrquestaId,
      horaInicio: config.horaInicio,
      horaFin: config.horaFin,
      franjaHorarioId: config.franjaHorarioId,
    );
    messenger.showSnackBar(SnackBar(content: Text('${alumno.nombre} matriculado en ${asignatura.nombre}.')));
    return true;
  } catch (e) {
    messenger.showSnackBar(
        SnackBar(content: Text(mensajeError(e, porDefecto: 'No se pudo matricular. Inténtalo de nuevo.'))));
    return false;
  }
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
  // Copia local: tras editar la asignatura desde esta misma pantalla se
  // recarga, para que nombre/grupos horarios mostrados no queden viejos.
  late Asignatura _asignatura = widget.asignatura;
  bool _sustitucionHoy = false;
  bool _cargandoSustitucion = true;
  // null = ver el curso escolar activo. Solo se puede matricular/editar/
  // marcar asistencia cuando se está viendo el activo — un curso pasado
  // es solo consulta (ver CLAUDE.md, discriminación por curso escolar).
  String? _cursoSeleccionado;

  // Franjas horarias de grupo de la asignatura (ver CLAUDE.md punto
  // 69) — no vacía cuando hay alguna configurada, en cuyo caso
  // _configurarMatricula deja de pedir días/hora sueltos y pide elegir
  // una de estas franjas.
  List<FranjaHoraria> get _franjasDisponibles => _asignatura.franjasHorario;

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
      asignaturaId: _asignatura.id!,
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
        .where((p) => _asignatura.profesorIds.contains(p.uid))
        .toList();
  }

  Future<void> _matricularAlumno() async {
    final cursoEscolar = await _db.cursoEscolarActivo().first;
    final todosLosAlumnos = await _db.alumnosDelCentro().first;
    final matriculasActuales = await _db
        .matriculasDeAsignatura(_asignatura.id!,
            cursoEscolar: cursoEscolar)
        .first;
    if (!mounted) return;

    final idsYaMatriculados = matriculasActuales.map((m) => m.alumnoId).toSet();
    String etiqueta(Usuario a) =>
        (a.apellidos?.isNotEmpty ?? false) ? '${a.apellidos}, ${a.nombre}' : a.nombre;
    final disponibles = todosLosAlumnos
        .where((a) => !idsYaMatriculados.contains(a.uid))
        .toList()
      ..sort((a, b) => etiqueta(a).toLowerCase().compareTo(etiqueta(b).toLowerCase()));

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
      builder: (context) => _DialogoElegirAlumno(alumnos: disponibles, etiqueta: etiqueta),
    );

    if (elegido == null) return;
    if (!mounted) return;

    await configurarYMatricular(context, alumno: elegido, asignatura: _asignatura);
  }

  Future<void> _editarMatricula(Matricula matricula) async {
    final profesores = await _profesoresDeLaAsignatura();
    final pluses = await _db.plusesOrquesta().first;
    if (!mounted) return;
    final config = await _configurarMatricula(
      context,
      profesoresDeLaAsignatura: profesores,
      plusesDisponibles: pluses,
      diasIniciales: matricula.diasSemana,
      profesorIdInicial: matricula.profesorId,
      plusOrquestaIdInicial: matricula.plusOrquestaId,
      horaInicioInicial: matricula.horaInicio,
      horaFinInicial: matricula.horaFin,
      franjasDisponibles: _franjasDisponibles,
      franjaHorarioIdInicial: matricula.franjaHorarioId,
    );
    if (config == null) return;
    try {
      await _db.actualizarDiasClaseMatricula(
        alumnoId: matricula.alumnoId,
        asignaturaId: _asignatura.id!,
        cursoEscolar: matricula.cursoEscolar,
        diasSemana: config.dias,
      );
      await _db.actualizarProfesorMatricula(
        alumnoId: matricula.alumnoId,
        asignaturaId: _asignatura.id!,
        cursoEscolar: matricula.cursoEscolar,
        profesorId: config.profesorId,
      );
      await _db.actualizarPlusOrquestaMatricula(
        alumnoId: matricula.alumnoId,
        asignaturaId: _asignatura.id!,
        cursoEscolar: matricula.cursoEscolar,
        plusOrquestaId: config.plusOrquestaId,
      );
      await _db.actualizarHorarioMatricula(
        alumnoId: matricula.alumnoId,
        asignaturaId: _asignatura.id!,
        cursoEscolar: matricula.cursoEscolar,
        horaInicio: config.horaInicio,
        horaFin: config.horaFin,
      );
      await _db.actualizarFranjaHorarioIdMatricula(
        alumnoId: matricula.alumnoId,
        asignaturaId: _asignatura.id!,
        cursoEscolar: matricula.cursoEscolar,
        franjaHorarioId: config.franjaHorarioId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Matrícula actualizada.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('No se pudo actualizar la matrícula. Inténtalo de nuevo.')));
    }
  }

  /// Aplica una franja horaria a varios alumnos YA matriculados de
  /// golpe — necesario porque crear/editar una franja en la asignatura
  /// no vincula sola a quien ya estaba matriculado de antes (ver
  /// CLAUDE.md); sin esto, tocaría editar matrícula por matrícula, que
  /// es justo lo que las franjas de grupo querían evitar.
  Future<void> _asignarFranjaEnBloque() async {
    final cursoEscolar = await _db.cursoEscolarActivo().first;
    final matriculas = await _db
        .matriculasDeAsignatura(_asignatura.id!, cursoEscolar: cursoEscolar)
        .first;
    if (!mounted) return;
    if (matriculas.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Todavía no hay alumnos matriculados.')));
      return;
    }

    final alumnoPorId = <String, Usuario>{};
    for (final m in matriculas) {
      final u = await _db.obtenerUsuario(m.alumnoId);
      if (u != null) alumnoPorId[m.alumnoId] = u;
    }
    if (!mounted) return;

    String? franjaId = _franjasDisponibles.first.id;
    final seleccionados = matriculas.map((m) => m.alumnoId).toSet();

    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: const Text('Asignar franja horaria en bloque'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: franjaId,
                  decoration: const InputDecoration(labelText: 'Franja horaria'),
                  items: _franjasDisponibles
                      .map((f) => DropdownMenuItem(
                            value: f.id,
                            child: Text(
                                '${f.diasSemana.map((d) => nombresDiasSemana[d - 1]).join(', ')} · ${f.horaInicio} - ${f.horaFin}'),
                          ))
                      .toList(),
                  onChanged: (v) => setStateDialog(() => franjaId = v),
                ),
                const SizedBox(height: 12),
                const Text('Alumnos a los que se aplica'),
                ...matriculas.map((m) {
                  final nombre = alumnoPorId[m.alumnoId]?.nombre ?? m.alumnoId;
                  return CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(nombre),
                    value: seleccionados.contains(m.alumnoId),
                    onChanged: (v) => setStateDialog(() {
                      v == true ? seleccionados.add(m.alumnoId) : seleccionados.remove(m.alumnoId);
                    }),
                  );
                }),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar')),
            FilledButton(
              onPressed: seleccionados.isEmpty || franjaId == null
                  ? null
                  : () => Navigator.pop(context, true),
              child: const Text('Aplicar'),
            ),
          ],
        ),
      ),
    );

    if (confirmado != true || franjaId == null) return;
    final franja = _franjasDisponibles.firstWhere((f) => f.id == franjaId);
    try {
      await _db.asignarFranjaAMatriculas(
        asignaturaId: _asignatura.id!,
        cursoEscolar: cursoEscolar,
        alumnoIds: seleccionados.toList(),
        franja: franja,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Grupo asignado a ${seleccionados.length == 1 ? '1 alumno' : '${seleccionados.length} alumnos'}.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(mensajeError(e, porDefecto: 'No se pudo aplicar el grupo.'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final asignatura = _asignatura;

    return StreamBuilder<String>(
      stream: _db.cursoEscolarActivo(),
      builder: (context, snapActivo) {
        if (snapActivo.hasError) {
          return const Scaffold(body: ErrorCarga());
        }
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
              // Horas de estudio: nunca para alumno (vería nombres/
              // rendimiento de compañeros menores de edad). Esta
              // pantalla en la práctica solo la abren profesor/
              // dirección, pero se comprueba aquí también por si
              // cambia la navegación en el futuro.
              if (widget.perfil.esDireccion || widget.perfil.esProfesor) ...[
                IconButton(
                  icon: const Icon(Icons.timer_outlined),
                  tooltip: 'Horas de estudio',
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => HorasAsignaturaScreen(
                          asignatura: asignatura, perfil: widget.perfil),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.grid_on_outlined),
                  tooltip: 'Notas (cuadrícula)',
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => NotasAsignaturaGridScreen(
                        asignatura: asignatura,
                        perfil: widget.perfil,
                        cursoEscolar: cursoEfectivo,
                      ),
                    ),
                  ),
                ),
              ],
              // Acciones de dirección en un menú CON TEXTO, no como
              // iconos sueltos: en el móvil el tooltip de un icono solo
              // aparece manteniendo pulsado, y dirección no lo descubría.
              if (widget.perfil.esDireccion)
                PopupMenuButton<String>(
                  tooltip: 'Más opciones',
                  onSelected: (opcion) async {
                    switch (opcion) {
                      case 'editar':
                        final guardado = await editarAsignatura(context, asignatura);
                        if (!guardado) return;
                        final recargada = await _db.asignatura(asignatura.id!);
                        if (recargada != null && mounted) setState(() => _asignatura = recargada);
                      case 'criterios':
                        if (!context.mounted) return;
                        Navigator.push(context,
                            MaterialPageRoute(builder: (_) => CriteriosEvaluacionScreen(asignatura: asignatura)));
                      case 'sustituciones':
                        if (!context.mounted) return;
                        Navigator.push(context,
                            MaterialPageRoute(builder: (_) => SustitucionesScreen(asignatura: asignatura)));
                      case 'grupos':
                        _asignarFranjaEnBloque();
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'editar',
                      child: ListTile(
                        leading: Icon(Icons.edit_outlined),
                        title: Text('Editar asignatura'),
                        subtitle: Text('Nombre, horas de estudio, grupos, profesorado'),
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'criterios',
                      child: ListTile(
                        leading: Icon(Icons.rule_outlined),
                        title: Text('Criterios de evaluación'),
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'sustituciones',
                      child: ListTile(
                        leading: Icon(Icons.swap_horiz),
                        title: Text('Sustituciones'),
                      ),
                    ),
                    if (_franjasDisponibles.isNotEmpty)
                      const PopupMenuItem(
                        value: 'grupos',
                        child: ListTile(
                          leading: Icon(Icons.group_work_outlined),
                          title: Text('Asignar grupo a varios alumnos'),
                        ),
                      ),
                  ],
                ),
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
                          // Ya no se filtra por profesorId == uid: con el
                          // permiso cruzado entre cursos (ver CLAUDE.md),
                          // cualquier profesor de esta asignatura (de
                          // cualquier curso que comparta nombre) gestiona a
                          // TODOS los matriculados, no solo a los que
                          // matriculas.profesorId le fija (ese campo pasó a
                          // ser informativo).
                          final matriculas = snapshot.data!;
                          if (matriculas.isEmpty) {
                            return const Center(
                              child: Text('Aún no hay alumnos matriculados.'),
                            );
                          }
                          return _ListaMatriculasPorProfesor(
                            matriculas: matriculas,
                            asignatura: asignatura,
                            perfil: widget.perfil,
                            db: _db,
                            soloLectura: !esActivo,
                            onEditarMatricula: _editarMatricula,
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

/// Agrupa el roster de una asignatura por profesor asignado
/// (`matricula.profesorId`, ya puramente informativo desde el permiso
/// cruzado entre cursos — ver CLAUDE.md), con cabeceras ordenadas
/// alfabéticamente por el nombre resuelto del profesor ("Sin profesor
/// asignado" siempre al final). A diferencia del listado de alumnos
/// (item 1), aquí NO se desglosa además por letra — dirección lo
/// confirmó así.
class _ListaMatriculasPorProfesor extends StatelessWidget {
  final List<Matricula> matriculas;
  final Asignatura asignatura;
  final Usuario perfil;
  final DbService db;
  final bool soloLectura;
  final void Function(Matricula) onEditarMatricula;

  const _ListaMatriculasPorProfesor({
    required this.matriculas,
    required this.asignatura,
    required this.perfil,
    required this.db,
    required this.soloLectura,
    required this.onEditarMatricula,
  });

  // Mismo criterio que _ListaAlfabetica en alumnos_screen.dart: ordena
  // por apellidos, con el nombre como respaldo para cuentas antiguas
  // sin apellidos.
  String _claveOrdenAlumno(Usuario u) =>
      (u.apellidos != null && u.apellidos!.isNotEmpty) ? u.apellidos! : u.nombre;

  @override
  Widget build(BuildContext context) {
    final idsProfesor = matriculas.map((m) => m.profesorId).where((id) => id.isNotEmpty).toSet();
    final idsAlumno = matriculas.map((m) => m.alumnoId).toSet();
    return FutureBuilder<({List<Usuario?> profesores, List<Usuario?> alumnos})>(
      future: Future.wait([
        Future.wait(idsProfesor.map((id) => db.obtenerUsuario(id))),
        Future.wait(idsAlumno.map((id) => db.obtenerUsuario(id))),
      ]).then((r) => (profesores: r[0], alumnos: r[1])),
      builder: (context, snap) {
        if (snap.hasError) {
          return const ErrorCarga();
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final nombrePorId = <String, String>{
          for (final p in snap.data!.profesores.whereType<Usuario>()) p.uid: p.nombre,
        };
        final alumnoPorId = <String, Usuario>{
          for (final a in snap.data!.alumnos.whereType<Usuario>()) a.uid: a,
        };

        final grupos = <String, List<Matricula>>{};
        for (final m in matriculas) {
          final clave = m.profesorId.isEmpty ? '' : (nombrePorId[m.profesorId] ?? m.profesorId);
          (grupos[clave] ??= []).add(m);
        }
        for (final lista in grupos.values) {
          lista.sort((a, b) {
            final alumnoA = alumnoPorId[a.alumnoId];
            final alumnoB = alumnoPorId[b.alumnoId];
            final claveA = alumnoA == null ? a.alumnoId : _claveOrdenAlumno(alumnoA);
            final claveB = alumnoB == null ? b.alumnoId : _claveOrdenAlumno(alumnoB);
            return claveA.compareTo(claveB);
          });
        }
        final claves = grupos.keys.toList()
          ..sort((a, b) {
            if (a.isEmpty) return 1;
            if (b.isEmpty) return -1;
            return a.compareTo(b);
          });

        return ListView(
          children: [
            for (final clave in claves) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text(clave.isEmpty ? 'Sin profesor asignado' : clave,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              ),
              for (final matricula in grupos[clave]!)
                _FilaMatricula(
                  key: ValueKey(matricula.id),
                  matricula: matricula,
                  asignatura: asignatura,
                  perfil: perfil,
                  db: db,
                  soloLectura: soloLectura,
                  onEditarMatricula: () => onEditarMatricula(matricula),
                ),
              const Divider(height: 1),
            ],
          ],
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
      // No hace falta releer aquí: el StreamSubscription de arriba
      // recibirá la actualización y refrescará _asistenciaHoy solo.
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text(mensajeError(e, porDefecto: 'No se pudo marcar la asistencia.'))));
    } finally {
      if (mounted) setState(() => _marcando = false);
    }
  }

  Future<void> _darDeBaja() async {
    final nombre = _alumno?.nombre ?? 'este alumno';
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Dar de baja de la asignatura'),
        content: Text(
            '¿Dar de baja a $nombre de ${widget.asignatura.nombre}?\n\n'
            'Dejará de aparecer en la lista y en el horario. Sus notas, asistencias '
            'y horas de estudio se conservan.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Dar de baja'),
          ),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.db.desmatricular(
        alumnoId: widget.matricula.alumnoId,
        asignaturaId: widget.asignatura.id!,
        cursoEscolar: widget.matricula.cursoEscolar,
      );
      messenger.showSnackBar(SnackBar(content: Text('$nombre dado de baja de ${widget.asignatura.nombre}.')));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('No se pudo dar de baja. Inténtalo de nuevo.')));
    }
  }

  // Mismo estilo que FilaAsistenciaHoy: texto además de color (no solo
  // un icono coloreado) y al menos 40 px de alto.
  Widget _botonAsistencia({
    required IconData icon,
    required String tooltip,
    required bool activo,
    required Color color,
    required VoidCallback onPressed,
  }) {
    final tono = color is MaterialColor ? color.shade700 : color;
    return OutlinedButton.icon(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(0, 40)),
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 10)),
        visualDensity: VisualDensity.compact,
        foregroundColor: WidgetStatePropertyAll(activo ? Colors.white : tono),
        backgroundColor: WidgetStatePropertyAll(activo ? tono : Colors.transparent),
        side: WidgetStatePropertyAll(BorderSide(color: tono)),
      ),
      onPressed: onPressed,
      icon: Icon(activo ? Icons.check : icon, size: 18),
      label: Text(tooltip),
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
                    runSpacing: 6,
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
            PopupMenuButton<String>(
              tooltip: 'Opciones del alumno',
              onSelected: (opcion) {
                if (opcion == 'editar') widget.onEditarMatricula();
                if (opcion == 'baja') _darDeBaja();
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: 'editar',
                  child: ListTile(
                    leading: Icon(Icons.edit_calendar_outlined),
                    title: Text('Cambiar horario, grupo o profesor'),
                  ),
                ),
                PopupMenuItem(
                  value: 'baja',
                  child: ListTile(
                    leading: Icon(Icons.person_remove_outlined, color: Colors.red),
                    title: Text('Dar de baja de esta asignatura'),
                  ),
                ),
              ],
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

/// Elegir a quién matricular, con buscador: con muchos alumnos una
/// lista sin búsqueda era impracticable.
class _DialogoElegirAlumno extends StatefulWidget {
  final List<Usuario> alumnos;
  final String Function(Usuario) etiqueta;

  const _DialogoElegirAlumno({required this.alumnos, required this.etiqueta});

  @override
  State<_DialogoElegirAlumno> createState() => _DialogoElegirAlumnoState();
}

class _DialogoElegirAlumnoState extends State<_DialogoElegirAlumno> {
  String _busqueda = '';

  @override
  Widget build(BuildContext context) {
    final filtrados = filtrarUsuarios(widget.alumnos, _busqueda);
    return AlertDialog(
      title: const Text('Matricular alumno'),
      contentPadding: const EdgeInsets.only(top: 8),
      content: SizedBox(
        width: 420,
        height: 420,
        child: Column(
          children: [
            CampoBusqueda(
              hint: 'Buscar por nombre o apellidos',
              autofocus: true,
              onChanged: (v) => setState(() => _busqueda = v),
            ),
            Expanded(
              child: filtrados.isEmpty
                  ? const Center(child: Text('Ningún alumno coincide.'))
                  : ListView.builder(
                      itemCount: filtrados.length,
                      itemBuilder: (context, i) => ListTile(
                        leading: const Icon(Icons.person_outline),
                        title: Text(widget.etiqueta(filtrados[i])),
                        subtitle: filtrados[i].instrumento?.isNotEmpty ?? false
                            ? Text(filtrados[i].instrumento!)
                            : null,
                        onTap: () => Navigator.pop(context, filtrados[i]),
                      ),
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
      ],
    );
  }
}
