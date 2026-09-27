import 'package:flutter/material.dart';
import '../../models/asignatura.dart';
import '../../models/matricula.dart';
import '../../models/usuario.dart';
import '../../services/db_service.dart';
import '../comunes/asignatura_detalle_screen.dart';

/// Horario general de dirección — MVP deliberadamente simplificado (ver
/// CLAUDE.md): no es un editor de arrastrar y soltar, es una
/// VISUALIZACIÓN de las franjas horarias ya guardadas en cada matrícula
/// (`Matricula.horaInicio`/`horaFin`, ver ese modelo) con filtros de
/// capa, más un enlace directo a la pantalla de asignatura de siempre
/// para añadir/editar/quitar — reutiliza el flujo de matricular que ya
/// existe en vez de duplicar un editor aparte. Punto 14 (propagación
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
      appBar: AppBar(title: const Text('Horario general')),
      body: StreamBuilder<String>(
        stream: _db.cursoEscolarActivo(),
        builder: (context, snapActivo) {
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

class _TablaHorario extends StatelessWidget {
  final List<_Clase> clases;
  final Map<String, Usuario> profesorPorId;
  final List<int> dias;
  final Usuario perfil;

  const _TablaHorario({
    required this.clases,
    required this.profesorPorId,
    required this.dias,
    required this.perfil,
  });

  @override
  Widget build(BuildContext context) {
    final horas = clases.map((c) => c.matricula.horaInicio).toSet().toList()..sort();

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
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: clases
                          .where((c) => c.matricula.horaInicio == hora && c.matricula.diasSemana.contains(dia))
                          .map((c) => ActionChip(
                                label: Text(
                                  c.alumno != null
                                      ? '${c.asignatura.nombre} · ${c.alumno!.nombre}'
                                      : c.asignatura.nombre,
                                  style: const TextStyle(fontSize: 12),
                                ),
                                onPressed: () => _abrirDetalle(context, c),
                              ))
                          .toList(),
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
