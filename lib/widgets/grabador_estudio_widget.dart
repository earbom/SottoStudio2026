import 'dart:async';
import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../services/grabador_estudio.dart';
import '../services/db_service.dart';
import '../models/sesion_estudio.dart';

/// Botón de grabar/parar + contadores de tiempo efectivo/total,
/// extraído de `GrabarEstudioScreen` para poder reutilizarlo también
/// desde `EmpezarEstudioScreen` (que añade un desplegable de
/// asignatura por encima). Siempre ligado a una asignatura de
/// instrumento concreta — ver CLAUDE.md, ya no existe la práctica
/// libre sin asignatura.
///
/// Una sesión en curso NUNCA se pierde en silencio: el botón atrás pide
/// confirmación (PopScope) y, si la pantalla se cierra por otra vía
/// (p. ej. el botón flotante de volver al menú, que hace popUntil y se
/// salta PopScope), `dispose` detiene y guarda lo grabado igualmente.
class GrabadorEstudioWidget extends StatefulWidget {
  final String alumnoId;
  final String? instrumento;
  final String asignaturaId;
  // Notifica cuándo empieza/termina una grabación, para que quien lo
  // use (p.ej. EmpezarEstudioScreen) pueda bloquear otros controles
  // (como el desplegable de asignatura) mientras está grabando, y así
  // no perder una sesión a medio grabar por cambiarla de sitio.
  final ValueChanged<bool>? onGrabandoChanged;

  const GrabadorEstudioWidget({
    super.key,
    required this.alumnoId,
    this.instrumento,
    required this.asignaturaId,
    this.onGrabandoChanged,
  });

  @override
  State<GrabadorEstudioWidget> createState() => _GrabadorEstudioWidgetState();
}

class _GrabadorEstudioWidgetState extends State<GrabadorEstudioWidget> {
  final _grabador = GrabadorEstudio();
  final _db = DbService();
  StreamSubscription<EstadoGrabacion>? _estadoSub;
  bool _grabando = false;
  bool _ocupado = false;
  EstadoGrabacion? _ultimoEstado;

  @override
  void initState() {
    super.initState();
    _estadoSub = _grabador.estado.listen((estado) {
      if (mounted) setState(() => _ultimoEstado = estado);
    });
  }

  SesionEstudio _sesionDesde(ResultadoSesion resultado) => SesionEstudio(
        alumnoId: widget.alumnoId,
        tipo: TipoSesion.instrumento,
        instrumento: widget.instrumento,
        asignaturaId: widget.asignaturaId,
        fechaInicio: resultado.fechaInicio,
        fechaFin: resultado.fechaFin,
        duracionTotalMs: resultado.duracionTotalMs,
        duracionEfectivaMs: resultado.duracionEfectivaMs,
        umbralDbUsado: resultado.umbralDbUsado,
      );

  Future<void> _empezar() async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _ocupado = true);
    try {
      await _grabador.iniciar();
      if (!mounted) return;
      setState(() => _grabando = true);
      widget.onGrabandoChanged?.call(true);
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.grabarEstudioErrorMicro)));
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  /// Detiene y guarda. Devuelve false si no se pudo guardar.
  Future<bool> _detenerYGuardar() async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _ocupado = true);
    final resultado = await _grabador.detener();
    _grabando = false;
    widget.onGrabandoChanged?.call(false);
    try {
      await _db.guardarSesion(_sesionDesde(resultado));
      final minutos = (resultado.duracionEfectivaMs / 60000).round();
      messenger.showSnackBar(SnackBar(content: Text(l10n.grabarEstudioGuardada(minutos))));
      return true;
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.grabarEstudioErrorGuardar)));
      return false;
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _confirmarSalida() async {
    final l10n = AppLocalizations.of(context)!;
    final guardarYSalir = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.grabarEstudioSalirTitulo),
        content: Text(l10n.grabarEstudioSalirTexto),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.grabarEstudioSeguir)),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(l10n.grabarEstudioGuardarYSalir)),
        ],
      ),
    );
    if (guardarYSalir != true || !mounted) return;
    await _detenerYGuardar();
    if (mounted) Navigator.of(context).pop();
  }

  String _formatoMs(int ms) {
    final segundos = (ms / 1000).floor();
    final m = (segundos ~/ 60).toString().padLeft(2, '0');
    final s = (segundos % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  void dispose() {
    _estadoSub?.cancel();
    final grabador = _grabador;
    if (_grabando) {
      // Red de seguridad: la pantalla se cerró sin pasar por PopScope.
      final db = _db;
      final sesionDe = _sesionDesde;
      grabador
          .detener()
          .then((r) => db.guardarSesion(sesionDe(r)))
          .catchError((_) {})
          .whenComplete(grabador.dispose);
    } else {
      grabador.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final esquema = Theme.of(context).colorScheme;
    final efectivo = _ultimoEstado?.msEfectivoAcumulado ?? 0;
    final total = _ultimoEstado?.msTotalAcumulado ?? 0;

    return PopScope(
      canPop: !_grabando,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmarSalida();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.grabarEstudioEfectivo(_formatoMs(efectivo)), style: const TextStyle(fontSize: 32)),
            Text(l10n.grabarEstudioTotal(_formatoMs(total)),
                style: TextStyle(fontSize: 16, color: esquema.onSurfaceVariant)),
            const SizedBox(height: 32),
            SizedBox(
              width: 112,
              height: 112,
              child: _ocupado
                  ? const Padding(
                      padding: EdgeInsets.all(36),
                      child: CircularProgressIndicator(),
                    )
                  : IconButton.filled(
                      iconSize: 64,
                      style: IconButton.styleFrom(
                        backgroundColor: _grabando ? Colors.red : esquema.primary,
                        foregroundColor: Colors.white,
                      ),
                      icon: Icon(_grabando ? Icons.stop : Icons.mic),
                      onPressed: _grabando ? _detenerYGuardar : _empezar,
                    ),
            ),
            const SizedBox(height: 16),
            Text(
              _grabando ? l10n.grabarEstudioGrabando : l10n.grabarEstudioPulsaEmpezar,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Text(
              l10n.grabarEstudioExplicacion,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: esquema.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
