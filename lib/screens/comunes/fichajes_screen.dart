import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../l10n/app_localizations.dart';
import '../../models/marcaje.dart';
import '../../models/horario_laboral.dart';
import '../../models/usuario.dart';
import '../../services/db_service.dart';
import '../../services/recordatorio_fichaje_service.dart';

final _formatoHora = DateFormat('HH:mm');
final _formatoFecha = DateFormat('dd/MM/yyyy');

/// Fichaje de entrada/salida y configuración del horario laboral
/// propio (Art. 34.9 ET, ver CLAUDE.md). El registro de cada día no
/// se puede editar una vez fichado: solo dirección puede corregirlo.
class FichajesScreen extends StatefulWidget {
  final Usuario perfil;

  const FichajesScreen({super.key, required this.perfil});

  @override
  State<FichajesScreen> createState() => _FichajesScreenState();
}

class _FichajesScreenState extends State<FichajesScreen> {
  final _db = DbService();
  final _recordatorios = RecordatorioFichajeService();
  Marcaje? _marcajeHoy;
  HorarioLaboral? _horario;
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final marcaje = await _db.marcajeDeHoy(widget.perfil.uid);
      final horario = await _db.obtenerHorarioLaboral(widget.perfil.uid);
      if (!mounted) return;
      setState(() {
        _marcajeHoy = marcaje;
        _horario = horario;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AppLocalizations.of(context)!.fichajesErrorCarga('$e');
        _cargando = false;
      });
    }
  }

  Future<void> _ficharEntrada() async {
    await _db.ficharEntrada(widget.perfil.uid);
    _cargar();
  }

  Future<void> _ficharSalida() async {
    await _db.ficharSalida(widget.perfil.uid);
    _cargar();
  }

  Future<void> _reportarOlvido() async {
    final l10n = AppLocalizations.of(context)!;
    final hoy = DateTime.now();
    final fecha = await showDatePicker(
      context: context,
      initialDate: hoy.subtract(const Duration(days: 1)),
      firstDate: hoy.subtract(const Duration(days: 30)),
      lastDate: hoy.subtract(const Duration(days: 1)),
      helpText: l10n.fichajesEligeOlvidaste,
    );
    if (fecha == null) return;
    if (!mounted) return;

    final entrada = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 9, minute: 0),
      helpText: l10n.fichajesHoraEntrada,
    );
    if (entrada == null) return;
    if (!mounted) return;

    final salida = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 17, minute: 0),
      helpText: l10n.fichajesHoraSalida,
    );
    if (salida == null) return;
    if (!mounted) return;

    try {
      await _db.reportarOlvidoMarcaje(
        empleadoId: widget.perfil.uid,
        fecha: Marcaje.formatearFecha(fecha),
        horaEntrada: DateTime(fecha.year, fecha.month, fecha.day, entrada.hour, entrada.minute),
        horaSalida: DateTime(fecha.year, fecha.month, fecha.day, salida.hour, salida.minute),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.fichajesEnviadoPendiente)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _configurarHorario() async {
    final l10n = AppLocalizations.of(context)!;
    final nombresDiasSemana = [
      l10n.diaLunes,
      l10n.diaMartes,
      l10n.diaMiercoles,
      l10n.diaJueves,
      l10n.diaViernes,
      l10n.diaSabado,
      l10n.diaDomingo,
    ];
    final turnos = List<TurnoLaboral>.from(_horario?.turnos ?? []);
    var minutosAviso = _horario?.minutosAvisoAntes ?? 10;

    final guardar = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) {
          Future<void> anadirTurno() async {
            final dia = await showDialog<int>(
              context: context,
              builder: (context) => SimpleDialog(
                title: Text(l10n.fichajesDiaSemana),
                children: List.generate(
                  7,
                  (i) => SimpleDialogOption(
                    onPressed: () => Navigator.pop(context, i + 1),
                    child: Text(nombresDiasSemana[i]),
                  ),
                ),
              ),
            );
            if (dia == null) return;
            if (!context.mounted) return;
            final entrada = await showTimePicker(
              context: context,
              initialTime: const TimeOfDay(hour: 9, minute: 0),
            );
            if (entrada == null) return;
            if (!context.mounted) return;
            final salida = await showTimePicker(
              context: context,
              initialTime: const TimeOfDay(hour: 17, minute: 0),
            );
            if (salida == null) return;
            setStateDialog(() {
              turnos.add(TurnoLaboral(
                diaSemana: dia,
                horaEntrada: '${entrada.hour.toString().padLeft(2, '0')}:${entrada.minute.toString().padLeft(2, '0')}',
                horaSalida: '${salida.hour.toString().padLeft(2, '0')}:${salida.minute.toString().padLeft(2, '0')}',
              ));
            });
          }

          return AlertDialog(
            title: Text(l10n.fichajesMiHorarioLaboral),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (turnos.isEmpty) Text(l10n.fichajesSinTurnos),
                  ...turnos.asMap().entries.map((entry) => ListTile(
                        dense: true,
                        title: Text(nombresDiasSemana[entry.value.diaSemana - 1]),
                        subtitle: Text('${entry.value.horaEntrada} - ${entry.value.horaSalida}'),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => setStateDialog(() => turnos.removeAt(entry.key)),
                        ),
                      )),
                  TextButton.icon(
                    onPressed: anadirTurno,
                    icon: const Icon(Icons.add),
                    label: Text(l10n.fichajesAnadirTurno),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: Text(l10n.fichajesAvisarAntes)),
                      SizedBox(
                        width: 60,
                        child: TextField(
                          keyboardType: TextInputType.number,
                          controller: TextEditingController(text: '$minutosAviso'),
                          onChanged: (v) => minutosAviso = int.tryParse(v) ?? minutosAviso,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false), child: Text(l10n.comunCancelar)),
              FilledButton(
                  onPressed: () => Navigator.pop(context, true), child: Text(l10n.comunGuardar)),
            ],
          );
        },
      ),
    );

    if (guardar != true) return;
    final horario = HorarioLaboral(empleadoId: widget.perfil.uid, turnos: turnos, minutosAvisoAntes: minutosAviso);
    await _db.guardarHorarioLaboral(horario);
    try {
      await _recordatorios.inicializar(onNotificacionTocada: (_) {});
      await _recordatorios.solicitarPermiso();
      await _recordatorios.reprogramar(horario);
    } catch (_) {
      // Las notificaciones locales son "best effort" (sobre todo en
      // web); un fallo aquí no debe impedir guardar el horario.
    }
    _cargar();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (_cargando) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final marcaje = _marcajeHoy;
    final yaFichoEntrada = marcaje?.horaEntrada != null;
    final yaFichoSalida = marcaje?.horaSalida != null;

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
          Text(_formatoFecha.format(DateTime.now()), style: const TextStyle(fontSize: 16, color: Colors.grey)),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(
                    !yaFichoEntrada
                        ? l10n.fichajesNoHasFichado
                        : !yaFichoSalida
                            ? '${l10n.fichajesEntrada}: ${_formatoHora.format(marcaje!.horaEntrada!)}'
                            : '${l10n.fichajesEntrada}: ${_formatoHora.format(marcaje!.horaEntrada!)} · '
                                '${l10n.fichajesSalida}: ${_formatoHora.format(marcaje.horaSalida!)}',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  if (!yaFichoEntrada)
                    FilledButton.icon(
                      onPressed: _ficharEntrada,
                      icon: const Icon(Icons.login),
                      label: Text(l10n.fichajesFicharEntrada),
                    )
                  else if (!yaFichoSalida)
                    FilledButton.icon(
                      onPressed: _ficharSalida,
                      icon: const Icon(Icons.logout),
                      label: Text(l10n.fichajesFicharSalida),
                    )
                  else
                    Text(l10n.fichajesJornadaCompletada, style: const TextStyle(color: Colors.green)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          ListTile(
            leading: const Icon(Icons.schedule_outlined),
            title: Text(l10n.fichajesMiHorarioLaboral),
            subtitle: Text(_horario == null || _horario!.turnos.isEmpty
                ? l10n.fichajesSinConfigurar
                : l10n.fichajesTurnos(_horario!.turnos.length, _horario!.minutosAvisoAntes)),
            trailing: const Icon(Icons.chevron_right),
            onTap: _configurarHorario,
          ),
          ListTile(
            leading: const Icon(Icons.report_gmailerrorred_outlined),
            title: Text(l10n.fichajesOlvidasteFichar),
            subtitle: Text(l10n.fichajesAutoinformar),
            trailing: const Icon(Icons.chevron_right),
            onTap: _reportarOlvido,
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(l10n.fichajesMisUltimosFichajes, style: Theme.of(context).textTheme.titleMedium),
          ),
          StreamBuilder<List<Marcaje>>(
            stream: _db.marcajesDeEmpleado(widget.perfil.uid),
            builder: (context, snapshot) {
              final marcajes = (snapshot.data ?? []).take(14).toList();
              if (marcajes.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(l10n.fichajesSinFichajes),
                );
              }
              return Column(
                children: marcajes.map((m) {
                  final entrada = m.horaEntrada != null ? _formatoHora.format(m.horaEntrada!) : '--:--';
                  final salida = m.horaSalida != null ? _formatoHora.format(m.horaSalida!) : '--:--';
                  return ListTile(
                    dense: true,
                    title: Text(m.fecha),
                    subtitle: Text('${l10n.fichajesEntrada} $entrada · ${l10n.fichajesSalida} $salida'
                        '${m.corregidoPor != null ? ' ${l10n.fichajesCorregido}' : ''}'),
                    trailing: m.pendienteValidacion
                        ? Tooltip(
                            message: l10n.fichajesPendienteValidar,
                            child: const Icon(Icons.hourglass_top, color: Colors.orange),
                          )
                        : null,
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
