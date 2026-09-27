import 'package:flutter/material.dart';
import '../../models/asignatura.dart';
import '../../models/matricula.dart';
import '../../models/usuario.dart';
import '../../services/db_service.dart';
import '../../utils/curso_escolar.dart';
import '../../widgets/selector_curso_escolar.dart';

class _FilaHoras {
  final Usuario alumno;
  final List<double> horasPorMes; // 12 posiciones, septiembre..agosto
  _FilaHoras(this.alumno, this.horasPorMes);
}

const _nombresMes = [
  'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun',
  'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic',
];

String _nombreMes(DateTime mes) => '${_nombresMes[mes.month - 1]} ${mes.year}';

/// Cuadrícula de horas de estudio efectivas de una asignatura: filas =
/// alumnos matriculados, columnas = los 12 meses del curso escolar
/// mostrado (septiembre a agosto), celdas = horas efectivas de ese mes
/// (mismo patrón que `NotasAsignaturaGridScreen`, sustituye a la
/// antigua lista-ranking + diálogo semanal). En asignaturas NO
/// instrumentales (`!permiteGrabarEstudio`) la celda es editable: un
/// profesor introduce o corrige el total mensual a mano; en
/// asignaturas de instrumento las horas son reales (grabadas con
/// micrófono) y la celda es de solo lectura.
///
/// Por privacidad (hay menores implicados, ver CLAUDE.md), solo lo ven
/// profesor y dirección — cualquier profesor de la asignatura ve a
/// TODOS sus matriculados (permiso cruzado entre cursos,
/// matriculas.profesorId ya no filtra el acceso). Se puede consultar
/// un curso escolar anterior, no solo el activo.
class HorasAsignaturaScreen extends StatefulWidget {
  final Asignatura asignatura;
  final Usuario perfil;

  const HorasAsignaturaScreen({super.key, required this.asignatura, required this.perfil});

  @override
  State<HorasAsignaturaScreen> createState() => _HorasAsignaturaScreenState();
}

class _HorasAsignaturaScreenState extends State<HorasAsignaturaScreen> {
  final DbService _db = DbService();
  String? _cursoSeleccionado;

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
                        const Text('(activo)', style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                ))
            .toList(),
      ),
    );
    if (elegido == null) return;
    setState(() => _cursoSeleccionado = elegido == activo ? null : elegido);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<String>(
      stream: _db.cursoEscolarActivo(),
      builder: (context, snapActivo) {
        if (!snapActivo.hasData) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final activo = snapActivo.data!;
        final cursoEscolar = _cursoSeleccionado ?? activo;

        return Scaffold(
          appBar: AppBar(
            title: Text('Horas de estudio · ${widget.asignatura.nombre}'),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(28),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Center(
                  child: SelectorCursoEscolar(
                    cursoMostrado: cursoEscolar,
                    esActivo: cursoEscolar == activo,
                    onPressed: () => _elegirCursoEscolar(activo),
                  ),
                ),
              ),
            ),
          ),
          body: CuerpoHorasAsignatura(
            asignatura: widget.asignatura,
            perfil: widget.perfil,
            cursoEscolar: cursoEscolar,
          ),
        );
      },
    );
  }
}

/// Cuerpo reutilizable (sin Scaffold/AppBar/selector de curso escolar
/// propios) — ver el mismo patrón en `CuerpoAsistenciasAsignatura`.
/// `dentroDeScroll` quita el `Expanded` (que exige un `Column` con
/// altura acotada, como el `body` de un `Scaffold`) cuando este cuerpo
/// vive embebido dentro del scroll vertical de
/// `VistaGlobalAsignaturaScreen`: ahí el propio `SingleChildScrollView`
/// de la página ya se encarga de darle a la tabla toda la altura que
/// necesite, en vez de forzarla a caber en el espacio restante.
class CuerpoHorasAsignatura extends StatefulWidget {
  final Asignatura asignatura;
  final Usuario perfil;
  final String cursoEscolar;
  final bool dentroDeScroll;

  const CuerpoHorasAsignatura({
    super.key,
    required this.asignatura,
    required this.perfil,
    required this.cursoEscolar,
    this.dentroDeScroll = false,
  });

  @override
  State<CuerpoHorasAsignatura> createState() => _CuerpoHorasAsignaturaState();
}

class _CuerpoHorasAsignaturaState extends State<CuerpoHorasAsignatura> {
  final DbService _db = DbService();

  Future<void> _tocarCelda(Usuario alumno, DateTime mes, double horasActuales) async {
    final ctrl = TextEditingController(
      text: horasActuales > 0 ? horasActuales.toStringAsFixed(1) : '',
    );
    final guardar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${alumno.nombre} · ${_nombreMes(mes)}'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(labelText: 'Horas efectivas del mes'),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Guardar')),
        ],
      ),
    );
    if (guardar != true) return;

    final horas = double.tryParse(ctrl.text.replaceAll(',', '.')) ?? 0;
    try {
      await _db.registrarHorasManualesMes(
        alumnoId: alumno.uid,
        asignaturaId: widget.asignatura.id!,
        mes: mes,
        horas: horas,
        profesorId: widget.perfil.uid,
      );
      if (mounted) setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo guardar: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final rango = rangoDeCursoEscolar(widget.cursoEscolar);
    final meses = List<DateTime>.generate(
      12,
      (i) => DateTime(rango.inicio.year, rango.inicio.month + i, 1),
    );

    return StreamBuilder<List<Matricula>>(
      stream: _db.matriculasDeAsignatura(widget.asignatura.id!, cursoEscolar: widget.cursoEscolar),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final matriculas = snapshot.data!;
        if (matriculas.isEmpty) {
          return const Center(child: Text('No hay alumnos para mostrar.'));
        }

        return FutureBuilder<List<_FilaHoras>>(
          future: _cargarFilas(matriculas, meses),
          builder: (context, snapFilas) {
            if (!snapFilas.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final filas = snapFilas.data!;
            final objetivo = widget.asignatura.horasObjetivoMensual;
            final editable = !widget.asignatura.permiteGrabarEstudio;

            final tabla = SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: [
                  const DataColumn(label: Text('Alumno')),
                  for (final mes in meses) DataColumn(label: Text(_nombreMes(mes))),
                ],
                rows: [
                  for (final fila in filas)
                    DataRow(cells: [
                      DataCell(Text(fila.alumno.nombre)),
                      for (var i = 0; i < meses.length; i++)
                        DataCell(
                          Builder(builder: (context) {
                            final horas = fila.horasPorMes[i];
                            final cumple = objetivo <= 0 || horas >= objetivo;
                            return Text(
                              horas > 0 ? horas.toStringAsFixed(1) : '—',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: horas <= 0
                                    ? Colors.grey
                                    : (objetivo <= 0 ? null : (cumple ? Colors.green : Colors.red)),
                              ),
                            );
                          }),
                          onTap: editable ? () => _tocarCelda(fila.alumno, meses[i], fila.horasPorMes[i]) : null,
                        ),
                    ]),
                ],
              ),
            );

            final banner = objetivo > 0
                ? Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: Text('Objetivo mensual: ${objetivo.toStringAsFixed(1)} h efectivas'),
                  )
                : null;

            if (widget.dentroDeScroll) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [if (banner != null) banner, tabla],
              );
            }

            return Column(
              children: [
                if (banner != null) banner,
                Expanded(child: SingleChildScrollView(child: tabla)),
              ],
            );
          },
        );
      },
    );
  }

  Future<List<_FilaHoras>> _cargarFilas(List<Matricula> matriculas, List<DateTime> meses) async {
    final filas = <_FilaHoras>[];
    for (final matricula in matriculas) {
      final alumno = await _db.obtenerUsuario(matricula.alumnoId);
      if (alumno == null) continue;
      final sesiones = await _db
          .sesionesDeAlumnoEnAsignatura(alumnoId: matricula.alumnoId, asignaturaId: matricula.asignaturaId)
          .first;
      // Plus de orquesta (ver CLAUDE.md): aproximación horasSemana × 4
      // por mes, mismo criterio ya usado en la app para "objetivo
      // anual = mensual × 12" (punto 17) — solo cuenta desde el mes en
      // que empezó la matrícula que lo aplica, no hacia atrás.
      final pluses = await _db.plusesOrquestaAplicablesDeAlumno(
        alumnoId: matricula.alumnoId,
        asignaturaDestinoId: widget.asignatura.id!,
        cursoEscolar: widget.cursoEscolar,
      );
      final horasPorMes = meses.map((mes) {
        final finMes = DateTime(mes.year, mes.month + 1, 1);
        final ms = sesiones
            .where((s) => !s.fechaInicio.isBefore(mes) && s.fechaInicio.isBefore(finMes))
            .fold<int>(0, (acc, s) => acc + s.duracionEfectivaMs);
        final plusMes = pluses
            .where((p) => !p.desde.isAfter(finMes))
            .fold<double>(0, (acc, p) => acc + p.horasSemana * 4);
        return ms / 3600000 + plusMes;
      }).toList();
      filas.add(_FilaHoras(alumno, horasPorMes));
    }
    filas.sort((a, b) => a.alumno.nombre.compareTo(b.alumno.nombre));
    return filas;
  }
}
