import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../models/asignatura.dart';
import '../../models/asistencia.dart';
import '../../models/sesion_estudio.dart';
import '../../models/nota.dart';
import '../../models/criterio_evaluacion.dart';
import '../../models/usuario.dart';
import '../../services/auth_service.dart';
import '../../services/db_service.dart';
import '../../utils/mensaje_error.dart';
import '../../widgets/error_carga.dart';
import '../../utils/validacion_nota.dart';

/// Vista de un alumno concreto dentro de una asignatura: calendario de
/// asistencia + horas de estudio, estadísticas (tabla y gráficas), y
/// notas. Compartida entre profesor y dirección; en modo alumno
/// (perfil sin permiso profesor/dirección) los controles de edición
/// quedan ocultos.
class AlumnoEnAsignaturaScreen extends StatefulWidget {
  final Usuario alumno;
  final Asignatura asignatura;
  final Usuario perfil;
  // Curso escolar cuya matrícula/calendario se está consultando (ver
  // CLAUDE.md, discriminación por curso escolar). Normalmente el activo,
  // salvo que se llegue aquí desde una consulta de un curso anterior.
  final String cursoEscolar;
  // Pestaña con la que se abre (0=Calendario, 1=Estadísticas,
  // 2=Notas) — por defecto Calendario; la cuadrícula de notas de la
  // asignatura abre directamente en Notas al ver el histórico de un
  // alumno.
  final int pestanaInicial;

  const AlumnoEnAsignaturaScreen({
    super.key,
    required this.alumno,
    required this.asignatura,
    required this.perfil,
    required this.cursoEscolar,
    this.pestanaInicial = 0,
  });

  @override
  State<AlumnoEnAsignaturaScreen> createState() => _AlumnoEnAsignaturaScreenState();
}

class _AlumnoEnAsignaturaScreenState extends State<AlumnoEnAsignaturaScreen> {
  final DbService _db = DbService();
  final AuthService _authService = AuthService();
  bool _puedeGestionar = false;
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _resolverPermiso();
  }

  /// Dirección siempre puede gestionar. Un profesor solo si es el
  /// asignado a ESTE alumno en la matrícula, o tiene una sustitución
  /// activa hoy para esta asignatura (ver firestore.rules, mismo
  /// criterio server-side).
  Future<void> _resolverPermiso() async {
    if (widget.perfil.esDireccion) {
      setState(() {
        _puedeGestionar = true;
        _cargando = false;
      });
      return;
    }
    if (!widget.perfil.esProfesor) {
      setState(() => _cargando = false);
      return;
    }
    final matricula = await _db.matricula(
      alumnoId: widget.alumno.uid,
      asignaturaId: widget.asignatura.id!,
      cursoEscolar: widget.cursoEscolar,
    );
    if (matricula?.profesorId == widget.perfil.uid) {
      if (!mounted) return;
      setState(() {
        _puedeGestionar = true;
        _cargando = false;
      });
      return;
    }
    final sustitucion = await _db.tieneSustitucionEnFecha(
      asignaturaId: widget.asignatura.id!,
      profesorId: widget.perfil.uid,
      fecha: DateTime.now(),
    );
    if (!mounted) return;
    setState(() {
      _puedeGestionar = sustitucion;
      _cargando = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return DefaultTabController(
      length: 3,
      initialIndex: widget.pestanaInicial,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.alumno.nombre),
          bottom: const TabBar(tabs: [
            Tab(text: 'Calendario'),
            Tab(text: 'Estadísticas'),
            Tab(text: 'Notas'),
          ]),
        ),
        body: TabBarView(
          children: [
            _TabCalendario(
              alumnoId: widget.alumno.uid,
              asignatura: widget.asignatura,
              cursoEscolar: widget.cursoEscolar,
              puedeGestionar: _puedeGestionar,
              marcadaPorUid: _authService.usuarioActual?.uid ?? '',
              // El propio alumno viendo su calendario: colorear por
              // horas de estudio en vez de por asistencia (ver
              // CLAUDE.md) — se detecta comparando uid, no el permiso
              // (un alumno siempre pasa su propio uid como alumno Y
              // como perfil al verse a sí mismo).
              esVistaPropia: widget.perfil.uid == widget.alumno.uid,
              db: _db,
            ),
            _TabEstadisticas(alumnoId: widget.alumno.uid, asignatura: widget.asignatura, db: _db),
            _TabNotas(
              alumno: widget.alumno,
              asignatura: widget.asignatura,
              perfil: widget.perfil,
              puedeGestionar: _puedeGestionar,
              db: _db,
            ),
          ],
        ),
      ),
    );
  }
}

class _TabCalendario extends StatefulWidget {
  final String alumnoId;
  final Asignatura asignatura;
  final String cursoEscolar;
  final bool puedeGestionar;
  final String marcadaPorUid;
  final bool esVistaPropia;
  final DbService db;

  const _TabCalendario({
    required this.alumnoId,
    required this.asignatura,
    required this.cursoEscolar,
    required this.puedeGestionar,
    required this.marcadaPorUid,
    required this.esVistaPropia,
    required this.db,
  });

  @override
  State<_TabCalendario> createState() => _TabCalendarioState();
}

class _TabCalendarioState extends State<_TabCalendario> {
  DateTime _diaSeleccionado = DateTime.now();
  DateTime _diaEnfocado = DateTime.now();
  Asistencia? _asistencia;
  List<SesionEstudio> _sesiones = [];
  // Días de clase de ESTE alumno en la asignatura (vienen de su
  // matrícula, no de la asignatura: las clases de instrumento son
  // individuales y cada alumno puede tener un horario distinto).
  List<int> _diasSemana = [];
  bool _cargando = true;
  // Todas las asistencias de este alumno en esta asignatura, indexadas
  // por 'fecha' ('yyyy-MM-dd'), para pintar el calendario completo de
  // un vistazo (verde/naranja/rojo) sin depender del día seleccionado.
  // Solo se usa cuando NO es la vista propia del alumno (ver CLAUDE.md:
  // la asistencia por colores no aporta nada al propio alumno, que ve
  // en su lugar sus horas de estudio).
  Map<String, Asistencia> _asistenciasPorFecha = {};
  // ms efectivos por 'fecha' ('yyyy-MM-dd'), para la vista propia del
  // alumno. Objetivo diario/semanal salen de
  // Asignatura.horasObjetivoSemanal (diario = semanal/7), configurable
  // por dirección desde CriteriosEvaluacionScreen (ver CLAUDE.md).
  Map<String, int> _msEfectivoPorFecha = {};
  double _objetivoDiarioHoras = 0;
  double _objetivoSemanalHoras = 0;
  // Fechas de inicio de semana (lunes, 'yyyy-MM-dd') donde el acumulado
  // de esa semana ya alcanza el objetivo semanal — permite que el fin
  // de semana "recupere" horas que faltaban entre semana.
  Set<String> _semanasCompletas = {};

  @override
  void initState() {
    super.initState();
    _cargarMatricula();
    _cargarDia(_diaSeleccionado);
    if (widget.esVistaPropia) {
      _cargarHorasEstudio();
    } else {
      _cargarTodasLasAsistencias();
    }
  }

  DateTime _inicioDeSemana(DateTime dia) {
    final soloFecha = DateTime(dia.year, dia.month, dia.day);
    return soloFecha.subtract(Duration(days: soloFecha.weekday - DateTime.monday));
  }

  Future<void> _cargarHorasEstudio() async {
    final sesiones = await widget.db
        .sesionesDeAlumnoEnAsignatura(alumnoId: widget.alumnoId, asignaturaId: widget.asignatura.id!)
        .first;

    final msPorFecha = <String, int>{};
    for (final s in sesiones) {
      final clave = Asistencia.formatearFecha(s.fechaInicio);
      msPorFecha[clave] = (msPorFecha[clave] ?? 0) + s.duracionEfectivaMs;
    }

    final objetivoSemanal = widget.asignatura.horasObjetivoSemanal;
    final objetivoDiario = objetivoSemanal / 7;

    final msPorSemana = <String, int>{};
    for (final entry in msPorFecha.entries) {
      final inicioSemana = _inicioDeSemana(DateTime.parse(entry.key));
      final clave = Asistencia.formatearFecha(inicioSemana);
      msPorSemana[clave] = (msPorSemana[clave] ?? 0) + entry.value;
    }
    final semanasCompletas = <String>{
      if (objetivoSemanal > 0)
        for (final entry in msPorSemana.entries)
          if (entry.value / 3600000 >= objetivoSemanal) entry.key,
    };

    if (!mounted) return;
    setState(() {
      _msEfectivoPorFecha = msPorFecha;
      _objetivoDiarioHoras = objetivoDiario;
      _objetivoSemanalHoras = objetivoSemanal;
      _semanasCompletas = semanasCompletas;
    });
  }

  Future<void> _cargarTodasLasAsistencias() async {
    final lista = await widget.db.asistenciasDeAlumnoEnAsignatura(
      alumnoId: widget.alumnoId,
      asignaturaId: widget.asignatura.id!,
    );
    if (!mounted) return;
    setState(() => _asistenciasPorFecha = {for (final a in lista) a.fecha: a});
  }

  Future<void> _cargarMatricula() async {
    final matricula = await widget.db.matricula(
      alumnoId: widget.alumnoId,
      asignaturaId: widget.asignatura.id!,
      cursoEscolar: widget.cursoEscolar,
    );
    if (!mounted) return;
    setState(() => _diasSemana = matricula?.diasSemana ?? []);
  }

  bool get _esDiaDeClase => _diasSemana.contains(_diaSeleccionado.weekday);

  Future<void> _cargarDia(DateTime dia) async {
    setState(() => _cargando = true);
    final asistencia = await widget.db.asistenciaDelDia(
      alumnoId: widget.alumnoId,
      asignaturaId: widget.asignatura.id!,
      fecha: dia,
    );
    final sesiones = await widget.db.sesionesDelDia(
      alumnoId: widget.alumnoId,
      asignaturaId: widget.asignatura.id!,
      dia: dia,
    );
    if (!mounted) return;
    setState(() {
      _asistencia = asistencia;
      _sesiones = sesiones;
      _cargando = false;
    });
  }

  Future<void> _marcar(bool asistio, {bool retraso = false}) async {
    try {
      await widget.db.marcarAsistencia(
        alumnoId: widget.alumnoId,
        asignaturaId: widget.asignatura.id!,
        fecha: _diaSeleccionado,
        asistio: asistio,
        retraso: retraso,
        marcadaPor: widget.marcadaPorUid,
      );
      await _cargarDia(_diaSeleccionado);
      await _cargarTodasLasAsistencias();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(mensajeError(e, porDefecto: 'No se pudo marcar la asistencia.'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final msEfectivo = _sesiones.fold<int>(0, (acc, s) => acc + s.duracionEfectivaMs);
    final horasEfectivas = msEfectivo / 3600000;

    return Column(
      children: [
        TableCalendar(
          headerStyle: const HeaderStyle(formatButtonVisible: false, titleCentered: true),
          locale: Localizations.localeOf(context).toLanguageTag(),
          startingDayOfWeek: StartingDayOfWeek.monday,
          firstDay: DateTime.now().subtract(const Duration(days: 365)),
          lastDay: DateTime.now().add(const Duration(days: 30)),
          focusedDay: _diaEnfocado,
          selectedDayPredicate: (day) => isSameDay(day, _diaSeleccionado),
          onDaySelected: (selected, focused) {
            setState(() {
              _diaSeleccionado = selected;
              _diaEnfocado = focused;
            });
            _cargarDia(selected);
          },
          calendarBuilders: CalendarBuilders(
            defaultBuilder: (context, day, focusedDay) {
              if (widget.esVistaPropia) return _construirDiaEstudio(context, day);
              return _construirDiaAsistencia(context, day);
            },
          ),
        ),
        // Leyenda: los colores del calendario no se explicaban en
        // ningún sitio (y el color solo no basta para daltónicos).
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Wrap(
            spacing: 12,
            runSpacing: 4,
            children: widget.esVistaPropia
                ? [
                    if (_objetivoDiarioHoras > 0) ...[
                      const _Leyenda(color: Colors.green, texto: 'Objetivo del día cumplido'),
                      _Leyenda(color: Colors.amber.shade700, texto: 'Estudió, pero menos'),
                      const _Leyenda(color: Colors.red, texto: 'No estudió'),
                    ] else
                      const _Leyenda(color: Colors.green, texto: 'Día con estudio'),
                  ]
                : [
                    const _Leyenda(color: Colors.green, texto: 'Asistió'),
                    const _Leyenda(color: Colors.orange, texto: 'Retraso'),
                    const _Leyenda(color: Colors.red, texto: 'Faltó'),
                    _Leyenda(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        texto: 'Día de clase sin marcar',
                        relleno: true),
                  ],
          ),
        ),
        if (widget.esVistaPropia && _objetivoDiarioHoras > 0)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Text(
              'Objetivo: ${_objetivoSemanalHoras.toStringAsFixed(1)} h/semana '
              '(${_objetivoDiarioHoras.toStringAsFixed(2)} h/día). El fin de semana cuenta para '
              'recuperar horas de la semana — si la semana llega al objetivo, verás ⭐ en sus días.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        const Divider(height: 1),
        if (_cargando)
          const Padding(
            padding: EdgeInsets.all(24),
            child: CircularProgressIndicator(),
          )
        else
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Horas de estudio efectivas ese día: ${horasEfectivas.toStringAsFixed(2)} h',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                if (_esDiaDeClase) ...[
                  Text(_textoAsistencia()),
                  if (widget.puedeGestionar) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        _botonEstadoAsistencia(
                          icon: Icons.check,
                          label: 'Asistió',
                          activo: _asistencia?.asistio == true && _asistencia?.retraso != true,
                          color: Colors.green,
                          onPressed: () => _marcar(true),
                        ),
                        _botonEstadoAsistencia(
                          icon: Icons.watch_later_outlined,
                          label: 'Retraso',
                          activo: _asistencia?.asistio == true && _asistencia?.retraso == true,
                          color: Colors.orange,
                          onPressed: () => _marcar(true, retraso: true),
                        ),
                        _botonEstadoAsistencia(
                          icon: Icons.close,
                          label: 'Faltó',
                          activo: _asistencia != null && _asistencia!.asistio == false,
                          color: Colors.red,
                          onPressed: () => _marcar(false),
                        ),
                      ],
                    ),
                  ],
                ] else
                  const Text(
                      'Este día no corresponde a un día de clase de esta asignatura, así que no '
                      'se puede marcar asistencia — pero el estudio en casa se registra cualquier '
                      'día, y las horas de arriba ya lo reflejan.'),
              ],
            ),
          ),
      ],
    );
  }

  Widget? _construirDiaAsistencia(BuildContext context, DateTime day) {
    final asistencia = _asistenciasPorFecha[Asistencia.formatearFecha(day)];
    final esDiaClaseSemana = _diasSemana.contains(day.weekday);
    if (asistencia == null && !esDiaClaseSemana) return null;

    // Verde = asistió, naranja = asistió con retraso, rojo = faltó —
    // mismos colores que los botones de marcar asistencia
    // (_botonEstadoAsistencia) y que _FilaMatricula en
    // asignatura_detalle_screen.dart, para que la vista de un mes
    // entero se lea de un vistazo.
    Color? colorAsistencia;
    if (asistencia != null) {
      colorAsistencia =
          !asistencia.asistio ? Colors.red : (asistencia.retraso ? Colors.orange : Colors.green);
    }

    return Center(
      child: Container(
        margin: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: colorAsistencia?.withValues(alpha: 0.25) ??
              Theme.of(context).colorScheme.primaryContainer,
          shape: BoxShape.circle,
          border: colorAsistencia != null ? Border.all(color: colorAsistencia, width: 2) : null,
        ),
        alignment: Alignment.center,
        child: Text('${day.day}'),
      ),
    );
  }

  Widget? _construirDiaEstudio(BuildContext context, DateTime day) {
    final claveFecha = Asistencia.formatearFecha(day);
    final msEfectivo = _msEfectivoPorFecha[claveFecha] ?? 0;
    final tieneObjetivo = _objetivoDiarioHoras > 0;

    // Rojo = no estudió ese día, ámbar = estudió pero no llegó al
    // objetivo diario, verde = lo alcanzó o superó. Sin objetivo
    // definido para el curso, solo se marca en verde si hubo estudio
    // (sin rojo/ámbar: no hay nada real contra lo que comparar).
    Color? colorEstudio;
    if (tieneObjetivo) {
      colorEstudio = msEfectivo == 0
          ? Colors.red
          : ((msEfectivo / 3600000) < _objetivoDiarioHoras ? Colors.amber.shade700 : Colors.green);
    } else if (msEfectivo > 0) {
      colorEstudio = Colors.green;
    }

    final claveSemana = Asistencia.formatearFecha(_inicioDeSemana(day));
    final semanaCompleta = _semanasCompletas.contains(claveSemana);

    if (colorEstudio == null && !semanaCompleta) return null;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Center(
          child: Container(
            margin: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: colorEstudio?.withValues(alpha: 0.25) ??
                  Theme.of(context).colorScheme.primaryContainer,
              shape: BoxShape.circle,
              border: colorEstudio != null ? Border.all(color: colorEstudio, width: 2) : null,
            ),
            alignment: Alignment.center,
            child: Text('${day.day}'),
          ),
        ),
        // Semana completada (incluido el fin de semana recuperando
        // horas): estrella en cada día de esa semana, no solo el
        // domingo, para que se vea sea cual sea el día enfocado.
        if (semanaCompleta)
          const Positioned(
            top: 0,
            right: 4,
            child: Icon(Icons.star, size: 14, color: Colors.amber),
          ),
      ],
    );
  }

  Widget _botonEstadoAsistencia({
    required IconData icon,
    required String label,
    required bool activo,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return activo
        ? FilledButton.icon(
            onPressed: onPressed,
            icon: Icon(icon),
            label: Text(label),
            style: FilledButton.styleFrom(backgroundColor: color),
          )
        : OutlinedButton.icon(
            onPressed: onPressed,
            icon: Icon(icon, color: color),
            label: Text(label),
            style: OutlinedButton.styleFrom(foregroundColor: color, side: BorderSide(color: color)),
          );
  }

  String _textoAsistencia() {
    if (_asistencia == null) return 'Asistencia: sin marcar.';
    if (!_asistencia!.asistio) return 'Asistencia: faltó.';
    return _asistencia!.retraso ? 'Asistencia: asistió con retraso.' : 'Asistencia: asistió.';
  }
}

class _TabEstadisticas extends StatelessWidget {
  final String alumnoId;
  final Asignatura asignatura;
  final DbService db;

  const _TabEstadisticas({required this.alumnoId, required this.asignatura, required this.db});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: Future.wait([
        db.asistenciasDeAlumnoEnAsignatura(alumnoId: alumnoId, asignaturaId: asignatura.id!),
        db.sesionesDeAlumnoEnAsignatura(alumnoId: alumnoId, asignaturaId: asignatura.id!).first,
      ]),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('No se pudieron cargar las estadísticas: ${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final asistencias = snapshot.data![0] as List<Asistencia>;
        final sesiones = snapshot.data![1] as List<SesionEstudio>;

        final horasEfectivasTotales =
            sesiones.fold<int>(0, (acc, s) => acc + s.duracionEfectivaMs) / 3600000;

        // Objetivo anual = objetivo mensual de la ASIGNATURA × 12 (no
        // se modela un calendario lectivo con meses sin clase, ver
        // CLAUDE.md). Horas del año en curso, no las totales
        // históricas: así el indicador rojo/verde refleja el progreso
        // del año actual.
        final inicioAnio = DateTime(DateTime.now().year, 1, 1);
        final horasEfectivasAnio = sesiones
                .where((s) => !s.fechaInicio.isBefore(inicioAnio))
                .fold<int>(0, (acc, s) => acc + s.duracionEfectivaMs) /
            3600000;
        final objetivoAnual = asignatura.horasObjetivoMensual * 12;
        final tieneObjetivoAnual = objetivoAnual > 0;
        final diferenciaAnual = horasEfectivasAnio - objetivoAnual;

        final nFaltas = asistencias.where((a) => !a.asistio).length;
        final nAsistencias = asistencias.where((a) => a.asistio).length;
        final nClasesRegistradas = asistencias.length;

        final semanas = <String, double>{};
        for (final s in sesiones) {
          final clave = _claveSemana(s.fechaInicio);
          semanas[clave] = (semanas[clave] ?? 0) + s.duracionEfectivaMs / 3600000;
        }
        final semanasOrdenadas = semanas.keys.toList()..sort();
        final ultimasSemanas = semanasOrdenadas.length > 6
            ? semanasOrdenadas.sublist(semanasOrdenadas.length - 6)
            : semanasOrdenadas;
        final promedioSemanal = ultimasSemanas.isEmpty
            ? 0.0
            : ultimasSemanas.map((k) => semanas[k]!).reduce((a, b) => a + b) / ultimasSemanas.length;

        final escala = _escalaEjeHoras(
            ultimasSemanas.isEmpty ? 0 : ultimasSemanas.map((k) => semanas[k]!).reduce((a, b) => a > b ? a : b));

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (tieneObjetivoAnual) ...[
              Card(
                color: (diferenciaAnual >= 0 ? Colors.green : Colors.red).withValues(alpha: 0.12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(
                        diferenciaAnual >= 0 ? Icons.trending_up : Icons.trending_down,
                        color: diferenciaAnual >= 0 ? Colors.green : Colors.red,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Objetivo anual: ${objetivoAnual.toStringAsFixed(1)} h · '
                              'Este año: ${horasEfectivasAnio.toStringAsFixed(1)} h',
                            ),
                            Text(
                              diferenciaAnual >= 0
                                  ? 'Excede el objetivo en ${diferenciaAnual.toStringAsFixed(1)} h'
                                  : 'Faltan ${(-diferenciaAnual).toStringAsFixed(1)} h para el objetivo',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: diferenciaAnual >= 0 ? Colors.green : Colors.red,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            DataTable(
              columns: const [
                DataColumn(label: Text('Métrica')),
                DataColumn(label: Text('Valor')),
              ],
              rows: [
                DataRow(cells: [
                  const DataCell(Text('Horas efectivas totales')),
                  DataCell(Text('${horasEfectivasTotales.toStringAsFixed(1)} h')),
                ]),
                DataRow(cells: [
                  const DataCell(Text('Nº de faltas')),
                  DataCell(Text('$nFaltas')),
                ]),
                DataRow(cells: [
                  const DataCell(Text('Nº de clases impartidas')),
                  DataCell(Text('$nClasesRegistradas')),
                ]),
                DataRow(cells: [
                  const DataCell(Text('Promedio semanal (últimas semanas)')),
                  DataCell(Text('${promedioSemanal.toStringAsFixed(1)} h')),
                ]),
              ],
            ),
            const SizedBox(height: 32),
            if (ultimasSemanas.isNotEmpty) ...[
              Text(escala.enMinutos ? 'Minutos de estudio por semana' : 'Horas de estudio por semana',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              SizedBox(
                height: 200,
                child: BarChart(
                  BarChartData(
                    minY: 0,
                    maxY: escala.maxY,
                    barTouchData: BarTouchData(
                      touchTooltipData: BarTouchTooltipData(
                        getTooltipItem: (grupo, _, barra, __) => BarTooltipItem(
                          '${_formatearValorEje(barra.toY)} ${escala.enMinutos ? 'min' : 'h'}',
                          const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    barGroups: [
                      for (var i = 0; i < ultimasSemanas.length; i++)
                        BarChartGroupData(x: i, barRods: [
                          BarChartRodData(toY: semanas[ultimasSemanas[i]]! * escala.factor, width: 18),
                        ]),
                    ],
                    titlesData: FlTitlesData(
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (value, meta) {
                            final i = value.toInt();
                            if (i < 0 || i >= ultimasSemanas.length) return const SizedBox.shrink();
                            return Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(ultimasSemanas[i].substring(5), style: const TextStyle(fontSize: 12)),
                            );
                          },
                        ),
                      ),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 40,
                          interval: escala.intervalo,
                          getTitlesWidget: (value, meta) => SideTitleWidget(
                            meta: meta,
                            child: Text(_formatearValorEje(value), style: const TextStyle(fontSize: 12)),
                          ),
                        ),
                      ),
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    ),
                    borderData: FlBorderData(show: false),
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      horizontalInterval: escala.intervalo,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 32),
            ],
            if (nClasesRegistradas > 0) ...[
              const Text('Asistencia', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              SizedBox(
                height: 200,
                child: PieChart(
                  PieChartData(sections: [
                    PieChartSectionData(
                      value: nAsistencias.toDouble(),
                      title: 'Asistió\n$nAsistencias',
                      color: Colors.green,
                      radius: 60,
                    ),
                    PieChartSectionData(
                      value: nFaltas.toDouble(),
                      title: 'Faltó\n$nFaltas',
                      color: Colors.redAccent,
                      radius: 60,
                    ),
                  ]),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  String _claveSemana(DateTime fecha) {
    final diasDesdeInicioAnio = fecha.difference(DateTime(fecha.year, 1, 1)).inDays;
    final semana = (diasDesdeInicioAnio / 7).floor() + 1;
    return '${fecha.year}-W${semana.toString().padLeft(2, '0')}';
  }
}

class _TabNotas extends StatelessWidget {
  final Usuario alumno;
  final Asignatura asignatura;
  final Usuario perfil;
  final bool puedeGestionar;
  final DbService db;

  const _TabNotas({
    required this.alumno,
    required this.asignatura,
    required this.perfil,
    required this.puedeGestionar,
    required this.db,
  });

  Future<void> _crearNota(
    BuildContext context,
    List<CriterioEvaluacion> criterios, {
    CriterioEvaluacion? preseleccionado,
  }) async {
    if (criterios.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Dirección aún no ha definido criterios de evaluación para esta asignatura.'),
        ),
      );
      return;
    }

    final valorCtrl = TextEditingController();
    final comentarioCtrl = TextEditingController();
    CriterioEvaluacion criterioElegido = preseleccionado ?? criterios.first;
    String? error;

    final valor = await showDialog<double>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) {
          void guardar() {
            final v = parsearValorNota(valorCtrl.text);
            if (v == null) {
              setStateDialog(() => error = mensajeErrorValorNota);
              return;
            }
            Navigator.pop(context, v);
          }

          return AlertDialog(
            title: const Text('Nueva nota'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<CriterioEvaluacion>(
                  initialValue: criterioElegido,
                  decoration: const InputDecoration(labelText: 'Criterio'),
                  items: criterios
                      .map((c) => DropdownMenuItem(
                            value: c,
                            child: Text('${c.nombre} (${c.peso.toStringAsFixed(0)}%)'),
                          ))
                      .toList(),
                  onChanged: (c) => setStateDialog(() => criterioElegido = c!),
                ),
                TextField(
                  controller: valorCtrl,
                  decoration: InputDecoration(labelText: 'Nota (0-10)', errorText: error),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onSubmitted: (_) => guardar(),
                ),
                TextField(
                  controller: comentarioCtrl,
                  decoration: const InputDecoration(labelText: 'Comentario (opcional)'),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
              FilledButton(onPressed: guardar, child: const Text('Guardar')),
            ],
          );
        },
      ),
    );

    if (valor == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await db.crearNota(Nota(
        alumnoId: alumno.uid,
        profesorId: perfil.uid,
        asignaturaId: asignatura.id!,
        criterioId: criterioElegido.id!,
        valor: valor,
        comentario: comentarioCtrl.text.trim(),
        fecha: DateTime.now(),
      ));
      messenger.showSnackBar(SnackBar(content: Text('Nota guardada: ${valor.toStringAsFixed(1)}')));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(
          content: Text('No se pudo guardar la nota. Comprueba la conexión o que tengas permiso en esta asignatura.')));
    }
  }

  // Dirección siempre; el profesor que la puso, mientras siga pendiente
  // de validar (mismo criterio que firestore.rules).
  bool _puedeCorregir(Nota nota) =>
      puedeGestionar &&
      (perfil.esDireccion || (nota.profesorId == perfil.uid && nota.estado == EstadoNota.pendiente));

  Widget _filaNota(BuildContext context, Nota nota) {
    final f = nota.fecha;
    final fecha = '${f.day.toString().padLeft(2, '0')}/${f.month.toString().padLeft(2, '0')}/${f.year}';
    final lineas = [
      if (nota.comentario.isNotEmpty) nota.comentario,
      '$fecha · ${nota.estado.etiqueta}',
    ];
    return ListTile(
      title: Text(nota.valor.toStringAsFixed(1).replaceAll('.', ',')),
      subtitle: Text(lineas.join('\n')),
      isThreeLine: lineas.length > 1,
      trailing: _puedeCorregir(nota)
          ? IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Corregir o borrar esta nota',
              onPressed: () => _corregirNota(context, nota),
            )
          : null,
    );
  }

  Future<void> _corregirNota(BuildContext context, Nota nota) async {
    final valorCtrl = TextEditingController(text: nota.valor.toStringAsFixed(1).replaceAll('.', ','));
    final comentarioCtrl = TextEditingController(text: nota.comentario);
    String? error;
    final accion = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: const Text('Corregir nota'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: valorCtrl,
                decoration: InputDecoration(labelText: 'Nota (0-10)', errorText: error),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
              TextField(
                controller: comentarioCtrl,
                decoration: const InputDecoration(labelText: 'Comentario (opcional)'),
              ),
            ],
          ),
          actions: [
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              onPressed: () => Navigator.pop(context, 'borrar'),
              child: const Text('Borrar nota'),
            ),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () {
                if (parsearValorNota(valorCtrl.text) == null) {
                  setStateDialog(() => error = mensajeErrorValorNota);
                  return;
                }
                Navigator.pop(context, 'guardar');
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    if (accion == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (accion == 'borrar') {
        final seguro = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Borrar nota'),
            content: Text('¿Borrar la nota ${nota.valor.toStringAsFixed(1).replaceAll('.', ',')}? No se puede deshacer.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Borrar'),
              ),
            ],
          ),
        );
        if (seguro != true) return;
        await db.eliminarNota(nota.id!);
        messenger.showSnackBar(const SnackBar(content: Text('Nota borrada.')));
      } else {
        await db.actualizarNota(nota.id!,
            valor: parsearValorNota(valorCtrl.text)!, comentario: comentarioCtrl.text.trim());
        messenger.showSnackBar(const SnackBar(content: Text('Nota corregida.')));
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(mensajeError(e, porDefecto: 'No se pudo guardar el cambio.'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<CriterioEvaluacion>>(
      stream: db.criteriosDeAsignatura(asignatura.id!),
      builder: (context, snapCriterios) {
        if (snapCriterios.hasError) {
          return const Scaffold(body: ErrorCarga());
        }
        if (!snapCriterios.hasData) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final criterios = snapCriterios.data!;
        final criteriosPorId = {for (final c in criterios) c.id!: c};

        return Scaffold(
          body: StreamBuilder<List<Nota>>(
            stream: db.notasDeAlumno(alumno.uid),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const ErrorCarga();
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final todasLasNotas = snapshot.data!.where((n) => n.asignaturaId == asignatura.id).toList();
              // Retraso de visibilidad (ver CLAUDE.md, Asignatura.
              // diasRetrasoVisibilidadNotas): solo se aplica cuando quien
              // mira es el propio alumno (!puedeGestionar) — profesor y
              // dirección siempre ven la nota al momento. Se filtra ANTES
              // de calcular la ponderada/agrupación, para que una nota
              // todavía no visible tampoco altere esos cálculos (si no,
              // el alumno notaría el cambio en la ponderada sin ver por
              // qué, lo que delataría igualmente la nota oculta).
              final notas = puedeGestionar
                  ? todasLasNotas
                  : todasLasNotas
                      .where((n) => !n.fecha
                          .add(Duration(days: asignatura.diasRetrasoVisibilidadNotas))
                          .isAfter(DateTime.now()))
                      .toList();

              final notaPonderada = notas.fold<double>(0, (acc, n) {
                final criterio = criteriosPorId[n.criterioId];
                if (criterio == null) return acc;
                return acc + n.valor * criterio.peso / 100;
              });

              // Agrupadas por criterio (no una lista plana de notas):
              // así un criterio sin ninguna nota puesta todavía también
              // aparece, marcado como "Pendiente" — antes solo era
              // visible como opción del desplegable al pulsar "+", sin
              // ninguna vista de qué pruebas existen en total (ver
              // CLAUDE.md).
              final notasPorCriterio = <String, List<Nota>>{};
              for (final n in notas) {
                (notasPorCriterio[n.criterioId] ??= []).add(n);
              }
              // Notas cuyo criterio ya no existe (borrado después de
              // puntuar) — no deben desaparecer solo por no encajar en
              // la agrupación por criterio actual.
              final notasSinCriterio =
                  notas.where((n) => !criteriosPorId.containsKey(n.criterioId)).toList();

              return Column(
                children: [
                  if (notas.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'Nota ponderada acumulada: ${notaPonderada.toStringAsFixed(2)}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  Expanded(
                    child: criterios.isEmpty && notasSinCriterio.isEmpty
                        ? const Center(
                            child: Text(
                                'Dirección aún no ha definido criterios de evaluación para esta asignatura.'))
                        : ListView(
                            children: [
                              for (final criterio in criterios) ...[
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                                  child: Text(
                                    '${criterio.nombre} (${criterio.peso.toStringAsFixed(0)}%)',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(fontWeight: FontWeight.bold),
                                  ),
                                ),
                                if ((notasPorCriterio[criterio.id] ?? const []).isEmpty)
                                  ListTile(
                                    leading: const Icon(Icons.schedule_outlined),
                                    title: const Text('Pendiente'),
                                    trailing: perfil.esProfesor && puedeGestionar
                                        ? IconButton(
                                            icon: const Icon(Icons.add),
                                            tooltip: 'Añadir nota para este criterio',
                                            onPressed: () => _crearNota(context, criterios,
                                                preseleccionado: criterio),
                                          )
                                        : null,
                                  )
                                else
                                  for (final nota in notasPorCriterio[criterio.id]!)
                                    _filaNota(context, nota),
                                const Divider(height: 1),
                              ],
                              if (notasSinCriterio.isNotEmpty) ...[
                                const Padding(
                                  padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                                  child: Text('(criterio eliminado)',
                                      style: TextStyle(fontWeight: FontWeight.bold)),
                                ),
                                for (final nota in notasSinCriterio)
                                  _filaNota(context, nota),
                              ],
                            ],
                          ),
                  ),
                ],
              );
            },
          ),
          floatingActionButton: perfil.esProfesor && puedeGestionar
              ? FloatingActionButton(
                  onPressed: () => _crearNota(context, criterios),
                  child: const Icon(Icons.add),
                )
              : null,
        );
      },
    );
  }
}

/// Escala del eje Y de la gráfica de horas por semana: siempre 4 marcas
/// con valores "redondos" (múltiplos de 1, 2 o 5 × 10^n) calculados a
/// partir del máximo, en vez de dejar que fl_chart elija el intervalo —
/// con valores pequeños generaba decenas de etiquetas con muchos
/// decimales, superpuestas. Si todo queda por debajo de 1 h, se pasa a
/// minutos para no mostrar "0,05 h".
({double maxY, double intervalo, double factor, bool enMinutos}) _escalaEjeHoras(double maxHoras) {
  final enMinutos = maxHoras < 1;
  final factor = enMinutos ? 60.0 : 1.0;
  final maximo = maxHoras * factor;
  const marcas = 4;
  if (maximo <= 0) return (maxY: marcas.toDouble(), intervalo: 1, factor: factor, enMinutos: enMinutos);
  final bruto = maximo / marcas;
  final magnitud = math.pow(10, (math.log(bruto) / math.ln10).floor()).toDouble();
  final normalizado = bruto / magnitud;
  final paso = (normalizado <= 1
          ? 1
          : normalizado <= 2
              ? 2
              : normalizado <= 5
                  ? 5
                  : 10) *
      magnitud;
  final maxY = (maximo / paso).ceil() * paso;
  return (maxY: maxY, intervalo: paso, factor: factor, enMinutos: enMinutos);
}

String _formatearValorEje(double v) {
  if ((v - v.roundToDouble()).abs() < 0.001) return v.round().toString();
  return v.toStringAsFixed(v < 1 ? 2 : 1).replaceAll('.', ',');
}

class _Leyenda extends StatelessWidget {
  final Color color;
  final String texto;
  final bool relleno;

  const _Leyenda({required this.color, required this.texto, this.relleno = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: relleno ? color : color.withValues(alpha: 0.25),
            border: relleno ? null : Border.all(color: color, width: 2),
          ),
        ),
        const SizedBox(width: 4),
        Text(texto, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
