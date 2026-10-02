import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import '../../models/asignatura.dart';
import '../../models/sustitucion.dart';
import '../../models/usuario.dart';
import '../../services/auth_service.dart';
import '../../services/db_service.dart';

final _formatoFecha = DateFormat('dd/MM/yyyy');

/// Dirección da de alta aquí sustituciones temporales: un profesor
/// (no necesariamente ya asignado a esta asignatura) recibe acceso a
/// TODOS los alumnos de la asignatura para los días concretos
/// seleccionados en el calendario — cubre el caso de que el profesor
/// habitual falte y otro dé la clase ese día.
class SustitucionesScreen extends StatefulWidget {
  final Asignatura asignatura;

  const SustitucionesScreen({super.key, required this.asignatura});

  @override
  State<SustitucionesScreen> createState() => _SustitucionesScreenState();
}

class _SustitucionesScreenState extends State<SustitucionesScreen> {
  final DbService _db = DbService();
  final AuthService _auth = AuthService();

  Usuario? _profesorElegido;
  final Set<DateTime> _diasSeleccionados = {};
  DateTime _diaEnfocado = DateTime.now();
  bool _guardando = false;

  Future<void> _guardar() async {
    if (_profesorElegido == null || _diasSeleccionados.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Elige un profesor y al menos un día.')),
      );
      return;
    }
    setState(() => _guardando = true);
    final creadaPor = _auth.usuarioActual?.uid ?? '';
    try {
      for (final dia in _diasSeleccionados) {
        await _db.crearSustitucion(
          asignaturaId: widget.asignatura.id!,
          profesorId: _profesorElegido!.uid,
          fecha: dia,
          creadaPor: creadaPor,
        );
      }
      if (!mounted) return;
      setState(() {
        _diasSeleccionados.clear();
        _profesorElegido = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sustitución guardada.')),
      );
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Sustituciones · ${widget.asignatura.nombre}')),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: StreamBuilder<List<Usuario>>(
              stream: _db.profesoresDelCentro(),
              builder: (context, snapshot) {
                final profesores = snapshot.data ?? [];
                return DropdownButtonFormField<Usuario>(
                  initialValue: _profesorElegido,
                  decoration: const InputDecoration(labelText: 'Profesor sustituto'),
                  items: profesores
                      .map((p) => DropdownMenuItem(value: p, child: Text(p.nombre)))
                      .toList(),
                  onChanged: (p) => setState(() => _profesorElegido = p),
                );
              },
            ),
          ),
          TableCalendar(
            headerStyle: const HeaderStyle(formatButtonVisible: false, titleCentered: true),
            locale: Localizations.localeOf(context).toLanguageTag(),
            startingDayOfWeek: StartingDayOfWeek.monday,
            firstDay: DateTime.now().subtract(const Duration(days: 30)),
            lastDay: DateTime.now().add(const Duration(days: 180)),
            focusedDay: _diaEnfocado,
            selectedDayPredicate: (day) => _diasSeleccionados.any((d) => isSameDay(d, day)),
            onDaySelected: (dia, focused) {
              setState(() {
                _diaEnfocado = focused;
                final yaEstaba = _diasSeleccionados.firstWhere(
                  (d) => isSameDay(d, dia),
                  orElse: () => DateTime(0),
                );
                if (yaEstaba.year == 0) {
                  _diasSeleccionados.add(dia);
                } else {
                  _diasSeleccionados.remove(yaEstaba);
                }
              });
            },
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              _diasSeleccionados.isEmpty
                  ? 'Toca uno o varios días en el calendario.'
                  : 'Días elegidos: ${(_diasSeleccionados.toList()..sort()).map((d) => _formatoFecha.format(d)).join(', ')}',
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton(
              onPressed: _guardando ? null : _guardar,
              child: _guardando
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Guardar sustitución'),
            ),
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text('Sustituciones programadas', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          StreamBuilder<List<Sustitucion>>(
            stream: _db.sustitucionesDeAsignatura(widget.asignatura.id!),
            builder: (context, snapshot) {
              final sustituciones = snapshot.data ?? [];
              if (sustituciones.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No hay sustituciones programadas.'),
                );
              }
              sustituciones.sort((a, b) => a.fecha.compareTo(b.fecha));
              return Column(
                children: sustituciones.map((s) {
                  return FutureBuilder<Usuario?>(
                    future: _db.obtenerUsuario(s.profesorId),
                    builder: (context, snapProfesor) {
                      final nombre = snapProfesor.data?.nombre ?? s.profesorId;
                      return ListTile(
                        leading: const Icon(Icons.swap_horiz),
                        title: Text(nombre),
                        subtitle: Text(_formatoFecha.format(DateTime.parse(s.fecha))),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: 'Anular sustitución',
                          onPressed: () async {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('Anular sustitución'),
                                content: Text(
                                    '¿Anular la sustitución de $nombre el ${_formatoFecha.format(DateTime.parse(s.fecha))}?'),
                                actions: [
                                  TextButton(
                                      onPressed: () => Navigator.pop(context, false),
                                      child: const Text('Cancelar')),
                                  FilledButton(
                                      onPressed: () => Navigator.pop(context, true),
                                      child: const Text('Anular')),
                                ],
                              ),
                            );
                            if (ok != true) return;
                            await _db.eliminarSustitucion(
                              asignaturaId: s.asignaturaId,
                              profesorId: s.profesorId,
                              fecha: DateTime.parse(s.fecha),
                            );
                          },
                        ),
                      );
                    },
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}
