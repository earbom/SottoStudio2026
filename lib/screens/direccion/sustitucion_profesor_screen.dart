import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import '../../models/asignatura.dart';
import '../../models/curso.dart';
import '../../models/usuario.dart';
import '../../services/auth_service.dart';
import '../../services/db_service.dart';
import '../../utils/mensaje_error.dart';
import '../../widgets/error_carga.dart';

final _formatoFecha = DateFormat('dd/MM/yyyy');

/// Baja de un profesor: programar de una vez un sustituto para TODAS
/// sus asignaturas (de todos los cursos) en los días elegidos, en vez
/// de ir asignatura por asignatura en `SustitucionesScreen`. Crea los
/// mismos documentos de `sustituciones` (uno por asignatura y día).
class SustitucionProfesorScreen extends StatefulWidget {
  final Usuario profesor;

  const SustitucionProfesorScreen({super.key, required this.profesor});

  @override
  State<SustitucionProfesorScreen> createState() => _SustitucionProfesorScreenState();
}

class _SustitucionProfesorScreenState extends State<SustitucionProfesorScreen> {
  final _db = DbService();
  late final Future<(List<Asignatura>, Map<String, Curso>, List<Usuario>)> _datos = Future.wait([
    _db.todasLasAsignaturas().first,
    _db.cursos().first,
    _db.profesoresDelCentro().first,
  ]).then((r) => (
        (r[0] as List<Asignatura>).where((a) => a.profesorIds.contains(widget.profesor.uid)).toList()
          ..sort((a, b) => a.nombre.compareTo(b.nombre)),
        {for (final c in r[1] as List<Curso>) c.id!: c},
        (r[2] as List<Usuario>).where((p) => p.uid != widget.profesor.uid).toList(),
      ));

  Usuario? _sustituto;
  final Set<DateTime> _dias = {};
  Set<String>? _asignaturasElegidas;
  DateTime _enfocado = DateTime.now();
  bool _guardando = false;

  Future<void> _guardar() async {
    final ids = _asignaturasElegidas ?? {};
    if (_sustituto == null || _dias.isEmpty || ids.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Elige el profesor sustituto, al menos un día y al menos una asignatura.')),
      );
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _guardando = true);
    try {
      final creadaPor = AuthService().usuarioActual?.uid ?? '';
      for (final asignaturaId in ids) {
        for (final dia in _dias) {
          await _db.crearSustitucion(
            asignaturaId: asignaturaId,
            profesorId: _sustituto!.uid,
            fecha: dia,
            creadaPor: creadaPor,
          );
        }
      }
      messenger.showSnackBar(SnackBar(
        content: Text('${_sustituto!.nombre} sustituirá a ${widget.profesor.nombre} '
            '${_dias.length == 1 ? 'el día elegido' : 'los ${_dias.length} días elegidos'} '
            'en ${ids.length} asignatura(s).'),
      ));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(mensajeError(e, porDefecto: 'No se pudo guardar la sustitución.'))));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Sustituir a ${widget.profesor.nombre}')),
      body: FutureBuilder(
        future: _datos,
        builder: (context, snap) {
          if (snap.hasError) return const ErrorCarga();
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final (asignaturas, cursoPorId, otrosProfesores) = snap.data!;
          _asignaturasElegidas ??= asignaturas.map((a) => a.id!).toSet();
          if (asignaturas.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Este profesor no tiene asignaturas asignadas.', textAlign: TextAlign.center),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Text('1. ¿Quién le sustituye?', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: DropdownButtonFormField<Usuario>(
                  initialValue: _sustituto,
                  decoration: const InputDecoration(labelText: 'Profesor sustituto'),
                  items: otrosProfesores.map((p) => DropdownMenuItem(value: p, child: Text(p.nombre))).toList(),
                  onChanged: (p) => setState(() => _sustituto = p),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 24, 16, 0),
                child: Text('2. ¿Qué días? (toca uno o varios)', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              TableCalendar(
                locale: Localizations.localeOf(context).toLanguageTag(),
                startingDayOfWeek: StartingDayOfWeek.monday,
                headerStyle: const HeaderStyle(formatButtonVisible: false, titleCentered: true),
                firstDay: DateTime.now().subtract(const Duration(days: 30)),
                lastDay: DateTime.now().add(const Duration(days: 180)),
                focusedDay: _enfocado,
                selectedDayPredicate: (d) => _dias.any((x) => isSameDay(x, d)),
                onDaySelected: (dia, enfocado) => setState(() {
                  _enfocado = enfocado;
                  final existente = _dias.where((x) => isSameDay(x, dia)).toList();
                  existente.isEmpty ? _dias.add(dia) : _dias.remove(existente.first);
                }),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(_dias.isEmpty
                    ? 'Ningún día elegido.'
                    : 'Días: ${(_dias.toList()..sort()).map(_formatoFecha.format).join(', ')}'),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 24, 16, 0),
                child: Text('3. ¿En qué asignaturas?', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              for (final a in asignaturas)
                CheckboxListTile(
                  title: Text(a.nombre),
                  subtitle: Text(cursoPorId[a.cursoId]?.nombre ?? ''),
                  value: _asignaturasElegidas!.contains(a.id),
                  onChanged: (v) => setState(() {
                    v == true ? _asignaturasElegidas!.add(a.id!) : _asignaturasElegidas!.remove(a.id);
                  }),
                ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton.icon(
                  onPressed: _guardando ? null : _guardar,
                  icon: _guardando
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.swap_horiz),
                  label: const Text('Guardar sustitución'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
