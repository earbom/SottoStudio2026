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
  bool _grabando = false;
  EstadoGrabacion? _ultimoEstado;

  @override
  void initState() {
    super.initState();
    _grabador.estado.listen((estado) => setState(() => _ultimoEstado = estado));
  }

  Future<void> _alternarGrabacion() async {
    if (!_grabando) {
      await _grabador.iniciar();
      setState(() => _grabando = true);
      widget.onGrabandoChanged?.call(true);
    } else {
      final resultado = await _grabador.detener();
      setState(() => _grabando = false);
      widget.onGrabandoChanged?.call(false);

      final sesion = SesionEstudio(
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
      await _db.guardarSesion(sesion);
    }
  }

  String _formatoMs(int ms) {
    final segundos = (ms / 1000).floor();
    final m = (segundos ~/ 60).toString().padLeft(2, '0');
    final s = (segundos % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  void dispose() {
    _grabador.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final efectivo = _ultimoEstado?.msEfectivoAcumulado ?? 0;
    final total = _ultimoEstado?.msTotalAcumulado ?? 0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(l10n.grabarEstudioEfectivo(_formatoMs(efectivo)), style: const TextStyle(fontSize: 32)),
        Text(l10n.grabarEstudioTotal(_formatoMs(total)),
            style: const TextStyle(fontSize: 16, color: Colors.grey)),
        const SizedBox(height: 32),
        IconButton(
          iconSize: 72,
          color: _grabando ? Colors.red : Colors.grey,
          icon: Icon(_grabando ? Icons.stop_circle : Icons.mic),
          onPressed: _alternarGrabacion,
        ),
      ],
    );
  }
}
