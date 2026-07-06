import 'dart:async';
import 'dart:io';
import 'package:record/record.dart';

/// Detector de práctica efectiva.
///
/// Lógica de 3 estados (no 2):
///  1. Tocando: amplitud > umbral -> cuenta como tiempo efectivo.
///  2. Silencio musical corto (<= [graciaSilencioMs], rodeado de
///     música): NO se sabe si es corto hasta que termina, así que se
///     acumula en un buffer temporal. Si el sonido vuelve antes de
///     agotar la gracia, ese silencio se suma retroactivamente al
///     tiempo efectivo.
///  3. Parón largo (> [graciaSilencioMs]): una vez agotada la gracia,
///     el silencio deja de contar como efectivo (pero sigue sumando
///     al tiempo total mientras la grabación esté activa).
///
/// No se guarda audio en ningún momento: solo se lee la amplitud en
/// tiempo real. El archivo temporal que exige el sistema para poder
/// grabar se descarta al finalizar (ver [detener]).
class GrabadorEstudio {
  final AudioRecorder _recorder = AudioRecorder();

  /// Umbral de amplitud (dBFS, típicamente entre -160 y 0) por encima
  /// del cual se considera que el instrumento está sonando.
  /// VALOR DE PARTIDA - requiere calibración con instrumentos reales
  /// durante el piloto. Criterio de aceptación: funcionar con al
  /// menos 3 tipos de instrumento distintos.
  double umbralDb;

  static const Duration graciaSilencio = Duration(seconds: 4);
  static const Duration intervaloMuestreo = Duration(milliseconds: 200);

  StreamSubscription<Amplitude>? _sub;
  Timer? _muestreoTimer;

  DateTime? _inicioSesion;
  DateTime? _inicioSilencioActual;
  bool _sonandoAhora = false;

  int _msEfectivoAcumulado = 0;
  int _msTotalAcumulado = 0;
  DateTime? _ultimaMarcaTiempo;

  final _estadoController = StreamController<EstadoGrabacion>.broadcast();
  Stream<EstadoGrabacion> get estado => _estadoController.stream;

  GrabadorEstudio({this.umbralDb = -30.0});

  Future<void> iniciar() async {
    if (!await _recorder.hasPermission()) {
      throw Exception('Permiso de micrófono denegado.');
    }

    _msEfectivoAcumulado = 0;
    _msTotalAcumulado = 0;
    _inicioSesion = DateTime.now();
    _ultimaMarcaTiempo = _inicioSesion;
    _inicioSilencioActual = null;
    _sonandoAhora = false;

    // El path es obligatorio por la API de `record`, pero el archivo
    // se borra al detener: NUNCA se conserva ni se sube a ningún sitio.
    await _recorder.start(
      const RecordConfig(),
      path: '_tmp_sotto_studio_no_conservar.m4a',
    );

    _muestreoTimer = Timer.periodic(intervaloMuestreo, (_) => _procesarMuestra());
  }

  Future<void> _procesarMuestra() async {
    final amplitud = await _recorder.getAmplitude();
    final ahora = DateTime.now();
    final deltaMs = ahora.difference(_ultimaMarcaTiempo!).inMilliseconds;
    _ultimaMarcaTiempo = ahora;
    _msTotalAcumulado += deltaMs;

    final estaSonando = amplitud.current > umbralDb;

    if (estaSonando) {
      // Si veníamos de un silencio corto, ese silencio se recupera
      // retroactivamente como tiempo efectivo (regla 2).
      if (_inicioSilencioActual != null) {
        final duracionSilencio = ahora.difference(_inicioSilencioActual!);
        if (duracionSilencio <= graciaSilencio) {
          _msEfectivoAcumulado += duracionSilencio.inMilliseconds;
        }
        _inicioSilencioActual = null;
      }
      _msEfectivoAcumulado += deltaMs;
      _sonandoAhora = true;
    } else {
      if (_sonandoAhora) {
        // Empieza un posible silencio.
        _inicioSilencioActual = ahora;
        _sonandoAhora = false;
      }
      // Si el silencio ya lleva más de la gracia, no se suma nada
      // más a efectivo (regla 3): el parón ya está "consumido".
    }

    _estadoController.add(EstadoGrabacion(
      sonando: estaSonando,
      msEfectivoAcumulado: _msEfectivoAcumulado,
      msTotalAcumulado: _msTotalAcumulado,
      amplitudActual: amplitud.current,
    ));
  }

  /// Detiene la grabación, descarta el archivo temporal y devuelve
  /// el resultado final de la sesión.
  Future<ResultadoSesion> detener() async {
    _muestreoTimer?.cancel();
    final path = await _recorder.stop();

    // Descartar el archivo temporal: no se guarda audio nunca.
    if (path != null) {
      try {
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {
        // Si falla el borrado no es crítico para la lógica de negocio,
        // pero debe registrarse/alertarse en producción (ej. Crashlytics).
      }
    }

    return ResultadoSesion(
      fechaInicio: _inicioSesion ?? DateTime.now(),
      fechaFin: DateTime.now(),
      duracionTotalMs: _msTotalAcumulado,
      duracionEfectivaMs: _msEfectivoAcumulado,
      umbralDbUsado: umbralDb,
    );
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    _muestreoTimer?.cancel();
    await _estadoController.close();
  }
}

class EstadoGrabacion {
  final bool sonando;
  final int msEfectivoAcumulado;
  final int msTotalAcumulado;
  final double amplitudActual;

  EstadoGrabacion({
    required this.sonando,
    required this.msEfectivoAcumulado,
    required this.msTotalAcumulado,
    required this.amplitudActual,
  });
}

class ResultadoSesion {
  final DateTime fechaInicio;
  final DateTime fechaFin;
  final int duracionTotalMs;
  final int duracionEfectivaMs;
  final double umbralDbUsado;

  ResultadoSesion({
    required this.fechaInicio,
    required this.fechaFin,
    required this.duracionTotalMs,
    required this.duracionEfectivaMs,
    required this.umbralDbUsado,
  });
}

