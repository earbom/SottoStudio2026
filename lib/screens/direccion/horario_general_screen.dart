import 'package:flutter/material.dart';
import '../../models/asignatura.dart';
import '../../models/matricula.dart';
import '../../models/usuario.dart';
import '../../services/db_service.dart';
import '../../utils/mensaje_error.dart';
import '../../widgets/error_carga.dart';
import '../comunes/asignatura_detalle_screen.dart';

/// Horario general de dirección. Sobre la visualización base (ver
/// CLAUDE.md punto 13) se añade arrastrar y soltar para mover una
/// clase de día/hora (`_TablaHorario`, `LongPressDraggable`/
/// `DragTarget`, sin dependencia externa — ver CLAUDE.md, siguiente
/// punto): MVP deliberado SIN detección de conflictos, soltar sobre
/// una celda ya ocupada simplemente añade otra clase ahí, sin avisar.
/// Añadir/quitar un alumno entero sigue yendo por el enlace a
/// `AsignaturaDetalleScreen` de siempre — arrastrar solo mueve una
/// clase YA existente a otro día/hora. Punto 14 (propagación
/// automática a alumno/profesor) sale gratis: todas las vistas leen la
/// misma matrícula vía stream.
class HorarioGeneralScreen extends StatefulWidget {
  final Usuario perfil;

  const HorarioGeneralScreen({super.key, required this.perfil});

  @override
  State<HorarioGeneralScreen> createState() => _HorarioGeneralScreenState();
}

enum _Vista { semana, dia }

class _HorarioGeneralScreenState extends State<HorarioGeneralScreen> {
  final DbService _db = DbService();
  _Vista _vista = _Vista.semana;
  int _diaSeleccionado = DateTime.now().weekday;
  bool _mostrarInstrumento = true;
  bool _mostrarTeoria = true;
  String? _profesorFiltro; // null = todos

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: StreamBuilder<String>(
        stream: _db.cursoEscolarActivo(),
        builder: (context, snapActivo) {
          if (snapActivo.hasError) {
            return const ErrorCarga();
          }
          if (!snapActivo.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final cursoEscolar = snapActivo.data!;
          return FutureBuilder<(List<Asignatura>, List<Usuario>, List<Usuario>)>(
            future: Future.wait([
              _db.todasLasAsignaturas().first,
              _db.alumnosDelCentro().first,
              _db.profesoresDelCentro().first,
            ]).then((r) => (
                  r[0] as List<Asignatura>,
                  r[1] as List<Usuario>,
                  r[2] as List<Usuario>,
                )),
            builder: (context, snapRef) {
              if (snapRef.hasError) {
                return const ErrorCarga();
              }
              if (!snapRef.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final (asignaturas, alumnos, profesores) = snapRef.data!;
              final asignaturaPorId = {for (final a in asignaturas) a.id!: a};
              final alumnoPorId = {for (final a in alumnos) a.uid: a};
              final profesorPorId = {for (final p in profesores) p.uid: p};

              return StreamBuilder<List<Matricula>>(
                stream: _db.todasLasMatriculasActivas(cursoEscolar: cursoEscolar),
                builder: (context, snapMatriculas) {
                  if (snapMatriculas.hasError) {
                    return const ErrorCarga();
                  }
                  if (!snapMatriculas.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final clases = snapMatriculas.data!
                      .where((m) => m.horaInicio.isNotEmpty && m.diasSemana.isNotEmpty)
                      .map((m) {
                        final asignatura = asignaturaPorId[m.asignaturaId];
                        return asignatura == null
                            ? null
                            : (matricula: m, asignatura: asignatura, alumno: alumnoPorId[m.alumnoId]);
                      })
                      .whereType<({Matricula matricula, Asignatura asignatura, Usuario? alumno})>()
                      .where((c) => c.asignatura.permiteGrabarEstudio ? _mostrarInstrumento : _mostrarTeoria)
                      .where((c) => _profesorFiltro == null || c.matricula.profesorId == _profesorFiltro)
                      .toList();

                  return Column(
                    children: [
                      _BarraFiltros(
                        vista: _vista,
                        onVista: (v) => setState(() => _vista = v),
                        diaSeleccionado: _diaSeleccionado,
                        onDia: (d) => setState(() => _diaSeleccionado = d),
                        mostrarInstrumento: _mostrarInstrumento,
                        mostrarTeoria: _mostrarTeoria,
                        onInstrumento: (v) => setState(() => _mostrarInstrumento = v),
                        onTeoria: (v) => setState(() => _mostrarTeoria = v),
                        profesores: profesores,
                        profesorFiltro: _profesorFiltro,
                        onProfesor: (v) => setState(() => _profesorFiltro = v),
                      ),
                      if (clases.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                          child: Row(
                            children: [
                              const Icon(Icons.pan_tool_alt_outlined, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Toca una clase para ver sus datos. Para cambiarla de día u hora, '
                                  'mantenla pulsada y arrástrala a otra casilla.',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                            ],
                          ),
                        ),
                      const Divider(height: 1),
                      Expanded(
                        child: clases.isEmpty
                            ? const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(24),
                                  child: Text(
                                    'No hay clases con horario configurado todavía. '
                                    'Añade una hora de inicio/fin al matricular o editar una matrícula.',
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              )
                            : _TablaHorario(
                                clases: clases,
                                profesorPorId: profesorPorId,
                                dias: _vista == _Vista.semana ? List.generate(7, (i) => i + 1) : [_diaSeleccionado],
                                perfil: widget.perfil,
                                cursoEscolar: cursoEscolar,
                              ),
                      ),
                    ],
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _BarraFiltros extends StatelessWidget {
  final _Vista vista;
  final ValueChanged<_Vista> onVista;
  final int diaSeleccionado;
  final ValueChanged<int> onDia;
  final bool mostrarInstrumento;
  final bool mostrarTeoria;
  final ValueChanged<bool> onInstrumento;
  final ValueChanged<bool> onTeoria;
  final List<Usuario> profesores;
  final String? profesorFiltro;
  final ValueChanged<String?> onProfesor;

  const _BarraFiltros({
    required this.vista,
    required this.onVista,
    required this.diaSeleccionado,
    required this.onDia,
    required this.mostrarInstrumento,
    required this.mostrarTeoria,
    required this.onInstrumento,
    required this.onTeoria,
    required this.profesores,
    required this.profesorFiltro,
    required this.onProfesor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SegmentedButton<_Vista>(
            segments: const [
              ButtonSegment(value: _Vista.semana, label: Text('Semana')),
              ButtonSegment(value: _Vista.dia, label: Text('Día')),
            ],
            selected: {vista},
            onSelectionChanged: (s) => onVista(s.first),
          ),
          if (vista == _Vista.dia)
            DropdownButton<int>(
              value: diaSeleccionado,
              items: List.generate(
                  7, (i) => DropdownMenuItem(value: i + 1, child: Text(nombresDiasSemana[i]))),
              onChanged: (v) => onDia(v ?? diaSeleccionado),
            ),
          FilterChip(
            label: const Text('Instrumento'),
            selected: mostrarInstrumento,
            onSelected: onInstrumento,
          ),
          FilterChip(
            label: const Text('Teoría'),
            selected: mostrarTeoria,
            onSelected: onTeoria,
          ),
          DropdownButton<String?>(
            value: profesorFiltro,
            hint: const Text('Todos los profesores'),
            items: [
              const DropdownMenuItem(value: null, child: Text('Todos los profesores')),
              ...profesores.map((p) => DropdownMenuItem(value: p.uid, child: Text(p.nombre))),
            ],
            onChanged: onProfesor,
          ),
        ],
      ),
    );
  }
}

typedef _Clase = ({Matricula matricula, Asignatura asignatura, Usuario? alumno});

/// Una clase arrastrada, junto con el día concreto de origen — una
/// misma `_Clase` puede aparecer en varias columnas (varios días de la
/// semana), así que hace falta saber CUÁL de esas casillas es la que
/// se está soltando en otro sitio (ver `DbService.moverOcurrenciaHorario`).
typedef _ClaseArrastrada = ({_Clase clase, int diaOrigen});

int _minutosDesdeHHmm(String hhmm) {
  final partes = hhmm.split(':');
  return int.parse(partes[0]) * 60 + int.parse(partes[1]);
}

String _hhmmDesdeMinutos(int minutos) {
  final total = minutos.clamp(0, 24 * 60 - 1);
  final h = total ~/ 60;
  final m = total % 60;
  return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
}

/// Filas de la rejilla: cada media hora entre la clase más temprana y
/// la más tardía (con un margen de una hora a cada lado para poder
/// arrastrar a un hueco libre antes/después) — no solo las horas que
/// ya tienen alguna clase, para que también haya sitio donde soltar.
List<String> _franjasDeLaRejilla(List<_Clase> clases) {
  if (clases.isEmpty) {
    return [for (var m = 16 * 60; m <= 20 * 60; m += 30) _hhmmDesdeMinutos(m)];
  }
  final minutos = clases.map((c) => _minutosDesdeHHmm(c.matricula.horaInicio));
  final minimo = ((minutos.reduce((a, b) => a < b ? a : b) - 60) ~/ 30) * 30;
  final maximo = (((minutos.reduce((a, b) => a > b ? a : b) + 90) + 29) ~/ 30) * 30;
  return [for (var m = minimo; m <= maximo; m += 30) _hhmmDesdeMinutos(m)];
}

class _TablaHorario extends StatelessWidget {
  final List<_Clase> clases;
  final Map<String, Usuario> profesorPorId;
  final List<int> dias;
  final Usuario perfil;
  final String cursoEscolar;

  const _TablaHorario({
    required this.clases,
    required this.profesorPorId,
    required this.dias,
    required this.perfil,
    required this.cursoEscolar,
  });

  Future<void> _mover(BuildContext context, _ClaseArrastrada arrastrada, int diaDestino, String horaDestino) async {
    final matricula = arrastrada.clase.matricula;
    final duracionMin =
        _minutosDesdeHHmm(matricula.horaFin) - _minutosDesdeHHmm(matricula.horaInicio);
    final horaFinDestino = _hhmmDesdeMinutos(_minutosDesdeHHmm(horaDestino) + (duracionMin > 0 ? duracionMin : 60));
    if (diaDestino == arrastrada.diaOrigen && horaDestino == matricula.horaInicio) return;
    final db = DbService();
    final messenger = ScaffoldMessenger.of(context);
    try {
      await db.moverOcurrenciaHorario(
        alumnoId: matricula.alumnoId,
        asignaturaId: matricula.asignaturaId,
        cursoEscolar: cursoEscolar,
        diaOrigen: arrastrada.diaOrigen,
        diaDestino: diaDestino,
        horaInicioDestino: horaDestino,
        horaFinDestino: horaFinDestino,
      );
      final quien = arrastrada.clase.alumno?.nombre ?? arrastrada.clase.asignatura.nombre;
      messenger.showSnackBar(SnackBar(
        duration: const Duration(seconds: 8),
        content: Text('$quien: ${nombresDiasSemana[diaDestino - 1]} $horaDestino'),
        // Deshacer restaura exactamente la matrícula de antes (días,
        // horas y grupo), por si se soltó en la casilla equivocada.
        action: SnackBarAction(
          label: 'Deshacer',
          onPressed: () async {
            try {
              await db.actualizarDiasClaseMatricula(
                  alumnoId: matricula.alumnoId,
                  asignaturaId: matricula.asignaturaId,
                  cursoEscolar: cursoEscolar,
                  diasSemana: matricula.diasSemana);
              await db.actualizarHorarioMatricula(
                  alumnoId: matricula.alumnoId,
                  asignaturaId: matricula.asignaturaId,
                  cursoEscolar: cursoEscolar,
                  horaInicio: matricula.horaInicio,
                  horaFin: matricula.horaFin);
              await db.actualizarFranjaHorarioIdMatricula(
                  alumnoId: matricula.alumnoId,
                  asignaturaId: matricula.asignaturaId,
                  cursoEscolar: cursoEscolar,
                  franjaHorarioId: matricula.franjaHorarioId);
            } catch (e) {
              messenger.showSnackBar(SnackBar(content: Text(mensajeError(e, porDefecto: 'No se pudo deshacer.'))));
            }
          },
        ),
      ));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensajeError(e, porDefecto: 'No se pudo mover la clase.'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final horas = _franjasDeLaRejilla(clases);

    return SingleChildScrollView(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: [
            const DataColumn(label: Text('Hora')),
            for (final dia in dias) DataColumn(label: Text(nombresDiasSemana[dia - 1])),
          ],
          rows: [
            for (final hora in horas)
              DataRow(cells: [
                DataCell(Text(hora)),
                for (final dia in dias)
                  DataCell(
                    DragTarget<_ClaseArrastrada>(
                      onAcceptWithDetails: (details) => _mover(context, details.data, dia, hora),
                      builder: (context, candidatos, rechazados) => Container(
                        constraints: const BoxConstraints(minWidth: 90, minHeight: 40),
                        color: candidatos.isNotEmpty
                            ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.5)
                            : null,
                        child: Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: clases
                              .where((c) =>
                                  c.matricula.horaInicio == hora && c.matricula.diasSemana.contains(dia))
                              .map((c) {
                            final etiqueta = c.alumno != null
                                ? '${c.asignatura.nombre} · ${c.alumno!.nombre}'
                                : c.asignatura.nombre;
                            final arrastrada = (clase: c, diaOrigen: dia);
                            return LongPressDraggable<_ClaseArrastrada>(
                              data: arrastrada,
                              feedback: Material(
                                elevation: 4,
                                borderRadius: BorderRadius.circular(20),
                                child: Chip(label: Text(etiqueta, style: const TextStyle(fontSize: 12))),
                              ),
                              childWhenDragging: Opacity(
                                opacity: 0.3,
                                child: ActionChip(
                                  label: Text(etiqueta, style: const TextStyle(fontSize: 12)),
                                  onPressed: null,
                                ),
                              ),
                              child: ActionChip(
                                label: Text(etiqueta, style: const TextStyle(fontSize: 12)),
                                onPressed: () => _abrirDetalle(context, c),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ),
              ]),
          ],
        ),
      ),
    );
  }

  void _abrirDetalle(BuildContext context, _Clase clase) {
    final profesor = profesorPorId[clase.matricula.profesorId];
    showModalBottomSheet(
      context: context,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(clase.asignatura.nombre,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 8),
            if (clase.alumno != null) Text('Alumno: ${clase.alumno!.nombre}'),
            Text('Horario: ${clase.matricula.horaInicio} - ${clase.matricula.horaFin}'),
            Text('Días: ${clase.matricula.diasSemana.map((d) => nombresDiasSemana[d - 1]).join(', ')}'),
            Text('Profesor de referencia: ${profesor?.nombre ?? 'Sin asignar'}'),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        AsignaturaDetalleScreen(asignatura: clase.asignatura, perfil: perfil),
                  ),
                );
              },
              child: const Text('Editar matrícula'),
            ),
          ],
        ),
      ),
    );
  }
}
