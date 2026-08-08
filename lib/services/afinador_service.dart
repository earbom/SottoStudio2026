import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:record/record.dart';

class LecturaAfinador {
  final bool detectada;
  final String? nota;
  final int? octava;
  final double? frecuencia;
  final double? cents;
  final double confianza;

  LecturaAfinador({
    required this.detectada,
    this.nota,
    this.octava,
    this.frecuencia,
    this.cents,
    required this.confianza,
  });
}

/// Afinador cromático: captura el micrófono en PCM crudo (no se
/// guarda audio en ningún momento, igual que GrabadorEstudio) y
/// detecta la frecuencia fundamental mediante autocorrelación
/// normalizada. Rango 55-2000 Hz, referencia La4=440Hz, umbral de
/// confianza 0.85 (por debajo no se informa una nota, para evitar
/// falsos positivos con ruido).
class AfinadorService {
  static const int sampleRate = 44100;
  static const int tamanoVentana = 4096;
  static const double umbralConfianza = 0.85;
  static const double umbralSilencioRms = 0.01;
  static const Duration intervaloAnalisis = Duration(milliseconds: 200);

  // Configurables en caliente según el instrumento seleccionado en
  // AfinadorScreen (ver lib/utils/instrumentos_afinador.dart): acotar
  // el rango a la tesitura real del instrumento mejora la detección y
  // evita errores de octava. Por defecto, el rango general anterior.
  double frecuenciaMin;
  double frecuenciaMax;

  AfinadorService({this.frecuenciaMin = 55, this.frecuenciaMax = 2000});

  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _sub;
  final List<double> _buffer = [];
  DateTime _ultimoAnalisis = DateTime.fromMillisecondsSinceEpoch(0);

  final _lecturaController = StreamController<LecturaAfinador>.broadcast();
  Stream<LecturaAfinador> get lecturas => _lecturaController.stream;

  bool get escuchando => _sub != null;

  Future<void> iniciar() async {
    if (!await _recorder.hasPermission()) {
      throw Exception('Permiso de micrófono denegado.');
    }
    _buffer.clear();
    final stream = await _recorder.startStream(const RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: sampleRate,
      numChannels: 1,
    ));
    _sub = stream.listen(_procesarChunk);
  }

  Future<void> detener() async {
    await _sub?.cancel();
    _sub = null;
    if (await _recorder.isRecording()) {
      await _recorder.stop();
    }
  }

  void _procesarChunk(Uint8List chunk) {
    for (var i = 0; i + 1 < chunk.length; i += 2) {
      final entero = (chunk[i] | (chunk[i + 1] << 8)).toSigned(16);
      _buffer.add(entero / 32768.0);
    }
    if (_buffer.length > tamanoVentana) {
      _buffer.removeRange(0, _buffer.length - tamanoVentana);
    }
    if (_buffer.length < tamanoVentana) return;

    final ahora = DateTime.now();
    if (ahora.difference(_ultimoAnalisis) < intervaloAnalisis) return;
    _ultimoAnalisis = ahora;
    _analizar(List<double>.of(_buffer));
  }

  void _analizar(List<double> frame) {
    var energia = 0.0;
    for (final s in frame) {
      energia += s * s;
    }
    final rms = math.sqrt(energia / frame.length);
    if (rms < umbralSilencioRms) {
      _lecturaController.add(LecturaAfinador(detectada: false, confianza: 0));
      return;
    }

    final lagMin = (sampleRate / frecuenciaMax).floor().clamp(1, frame.length - 2);
    final lagMax = (sampleRate / frecuenciaMin).ceil().clamp(lagMin + 1, frame.length - 1);

    var mejorR = -1.0;
    var mejorLag = -1;
    for (var lag = lagMin; lag <= lagMax; lag++) {
      var num = 0.0, denomA = 0.0, denomB = 0.0;
      final limite = frame.length - lag;
      for (var i = 0; i < limite; i++) {
        final a = frame[i];
        final b = frame[i + lag];
        num += a * b;
        denomA += a * a;
        denomB += b * b;
      }
      final denom = math.sqrt(denomA * denomB);
      if (denom > 0) {
        final r = num / denom;
        if (r > mejorR) {
          mejorR = r;
          mejorLag = lag;
        }
      }
    }

    if (mejorLag <= 0 || mejorR < umbralConfianza) {
      _lecturaController.add(LecturaAfinador(detectada: false, confianza: mejorR.clamp(0, 1)));
      return;
    }

    final frecuencia = sampleRate / mejorLag;
    final info = _frecuenciaANota(frecuencia);
    _lecturaController.add(LecturaAfinador(
      detectada: true,
      nota: info.nota,
      octava: info.octava,
      frecuencia: frecuencia,
      cents: info.cents,
      confianza: mejorR,
    ));
  }

  /// Referencia La4 (A4) = 440 Hz. MIDI 69 = A4.
  ({String nota, int octava, double cents}) _frecuenciaANota(double frecuencia) {
    final midiFloat = 69 + 12 * (math.log(frecuencia / 440) / math.ln2);
    final midiRedondeado = midiFloat.round();
    final cents = 100 * (midiFloat - midiRedondeado);
    const nombres = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
    final indice = midiRedondeado % 12;
    final octava = (midiRedondeado ~/ 12) - 1;
    return (nota: nombres[indice], octava: octava, cents: cents);
  }

  Future<void> dispose() async {
    await detener();
    await _lecturaController.close();
  }
}
