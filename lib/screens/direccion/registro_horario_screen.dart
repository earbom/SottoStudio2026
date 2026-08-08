import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:file_saver/file_saver.dart';
import '../../models/marcaje.dart';
import '../../models/usuario.dart';
import '../../services/auth_service.dart';
import '../../services/db_service.dart';
import '../../utils/excel_marcajes.dart';

final _formatoFecha = DateFormat('dd/MM/yyyy');

/// Vista de dirección del registro horario de todos los trabajadores
/// (Art. 34.9 ET): quién fichó qué día, a qué hora entró y salió —
/// para poder mostrarlo a la Inspección de Trabajo si lo pidiera, y
/// exportarlo a Excel. La fuente de verdad es siempre `marcajes` en
/// Firestore; el Excel es solo un informe derivado, no el registro en
/// sí (ver CLAUDE.md sobre el estado de la reforma de registro digital).
class RegistroHorarioScreen extends StatefulWidget {
  const RegistroHorarioScreen({super.key});

  @override
  State<RegistroHorarioScreen> createState() => _RegistroHorarioScreenState();
}

class _RegistroHorarioScreenState extends State<RegistroHorarioScreen> {
  final _db = DbService();
  final _auth = AuthService();
  DateTime _desde = DateTime.now().subtract(const Duration(days: 30));
  DateTime _hasta = DateTime.now();

  Future<void> _elegirRango() async {
    final rango = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 365 * 2)),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _desde, end: _hasta),
    );
    if (rango == null) return;
    setState(() {
      _desde = rango.start;
      _hasta = rango.end;
    });
  }

  Future<void> _corregirMarcaje(Marcaje marcaje) async {
    TimeOfDay? entrada = marcaje.horaEntrada != null
        ? TimeOfDay(hour: marcaje.horaEntrada!.hour, minute: marcaje.horaEntrada!.minute)
        : null;
    TimeOfDay? salida = marcaje.horaSalida != null
        ? TimeOfDay(hour: marcaje.horaSalida!.hour, minute: marcaje.horaSalida!.minute)
        : null;

    final guardar = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: Text(marcaje.pendienteValidacion
              ? 'Revisar y validar ${marcaje.fecha}'
              : 'Corregir ${marcaje.fecha}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text('Entrada: ${entrada != null ? '${entrada!.hour.toString().padLeft(2, '0')}:${entrada!.minute.toString().padLeft(2, '0')}' : '--:--'}'),
                trailing: const Icon(Icons.edit),
                onTap: () async {
                  final elegido = await showTimePicker(context: context, initialTime: entrada ?? TimeOfDay.now());
                  if (elegido != null) setStateDialog(() => entrada = elegido);
                },
              ),
              ListTile(
                title: Text('Salida: ${salida != null ? '${salida!.hour.toString().padLeft(2, '0')}:${salida!.minute.toString().padLeft(2, '0')}' : '--:--'}'),
                trailing: const Icon(Icons.edit),
                onTap: () async {
                  final elegido = await showTimePicker(context: context, initialTime: salida ?? TimeOfDay.now());
                  if (elegido != null) setStateDialog(() => salida = elegido);
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Guardar')),
          ],
        ),
      ),
    );

    if (guardar != true) return;
    final fechaBase = DateTime.parse(marcaje.fecha);
    final horaEntrada = entrada != null
        ? DateTime(fechaBase.year, fechaBase.month, fechaBase.day, entrada!.hour, entrada!.minute)
        : null;
    final horaSalida = salida != null
        ? DateTime(fechaBase.year, fechaBase.month, fechaBase.day, salida!.hour, salida!.minute)
        : null;
    final validadoPor = _auth.usuarioActual?.uid ?? '';

    if (marcaje.pendienteValidacion) {
      await _db.validarMarcaje(
        empleadoId: marcaje.empleadoId,
        fecha: marcaje.fecha,
        horaEntrada: horaEntrada ?? marcaje.horaEntrada!,
        horaSalida: horaSalida ?? marcaje.horaSalida!,
        validadoPor: validadoPor,
      );
    } else {
      await _db.corregirMarcaje(
        empleadoId: marcaje.empleadoId,
        fecha: marcaje.fecha,
        horaEntrada: horaEntrada,
        horaSalida: horaSalida,
        corregidoPor: validadoPor,
      );
    }
  }

  Future<void> _exportarExcel(List<Marcaje> marcajes, Map<String, String> nombres) async {
    final bytes = generarExcelMarcajes(marcajes, nombres);

    await FileSaver.instance.saveFile(
      name: 'registro_horario_${Marcaje.formatearFecha(_desde)}_${Marcaje.formatearFecha(_hasta)}',
      bytes: bytes,
      fileExtension: 'xlsx',
      mimeType: MimeType.microsoftExcel,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Excel exportado.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${_formatoFecha.format(_desde)} — ${_formatoFecha.format(_hasta)}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                TextButton.icon(
                  onPressed: _elegirRango,
                  icon: const Icon(Icons.date_range_outlined),
                  label: const Text('Cambiar rango'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: StreamBuilder<List<Usuario>>(
              stream: _db.trabajadoresDelCentro(),
              builder: (context, snapTrabajadores) {
                final nombres = {for (final t in snapTrabajadores.data ?? <Usuario>[]) t.uid: t.nombre};
                return StreamBuilder<List<Marcaje>>(
                  stream: _db.marcajesEnRango(desde: _desde, hasta: _hasta),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final marcajes = snapshot.data!;
                    if (marcajes.isEmpty) {
                      return const Center(child: Text('No hay fichajes en este rango de fechas.'));
                    }
                    return ListView.separated(
                      itemCount: marcajes.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final m = marcajes[i];
                        final nombre = nombres[m.empleadoId] ?? m.empleadoId;
                        final entrada = m.horaEntrada != null ? DateFormat('HH:mm').format(m.horaEntrada!) : '--:--';
                        final salida = m.horaSalida != null ? DateFormat('HH:mm').format(m.horaSalida!) : '--:--';
                        return ListTile(
                          tileColor: m.pendienteValidacion
                              ? Colors.orange.withValues(alpha: 0.12)
                              : null,
                          leading: m.pendienteValidacion
                              ? const Icon(Icons.hourglass_top, color: Colors.orange)
                              : null,
                          title: Text('$nombre · ${m.fecha}'),
                          subtitle: Text('Entrada $entrada · Salida $salida'
                              '${m.pendienteValidacion ? ' (pendiente de validar)' : m.corregidoPor != null ? ' (corregido)' : ''}'),
                          trailing: IconButton(
                            icon: Icon(m.pendienteValidacion ? Icons.fact_check_outlined : Icons.edit_outlined),
                            tooltip: m.pendienteValidacion ? 'Revisar y validar' : 'Corregir',
                            onPressed: () => _corregirMarcaje(m),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: StreamBuilder<List<Usuario>>(
        stream: _db.trabajadoresDelCentro(),
        builder: (context, snapTrabajadores) {
          final nombres = {for (final t in snapTrabajadores.data ?? <Usuario>[]) t.uid: t.nombre};
          return StreamBuilder<List<Marcaje>>(
            stream: _db.marcajesEnRango(desde: _desde, hasta: _hasta),
            builder: (context, snapshot) {
              final marcajes = snapshot.data ?? [];
              return FloatingActionButton.extended(
                onPressed: marcajes.isEmpty ? null : () => _exportarExcel(marcajes, nombres),
                icon: const Icon(Icons.download_outlined),
                label: const Text('Exportar a Excel'),
              );
            },
          );
        },
      ),
    );
  }
}
