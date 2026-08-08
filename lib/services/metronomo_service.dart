import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;

/// Figura de subdivisión del clic dentro de cada pulso.
enum FiguraClic { negra, corchea, tresillo, semicorchea }

extension FiguraClicInfo on FiguraClic {
  /// Nº de clics por pulso (1 = solo el pulso, sin subdividir).
  int get subdivisiones => switch (this) {
        FiguraClic.negra => 1,
        FiguraClic.corchea => 2,
        FiguraClic.tresillo => 3,
        FiguraClic.semicorchea => 4,
      };

  String get etiqueta => switch (this) {
        FiguraClic.negra => 'Negra',
        FiguraClic.corchea => 'Corcheas',
        FiguraClic.tresillo => 'Tresillo',
        FiguraClic.semicorchea => 'Semicorcheas',
      };
}

class Compas {
  final String nombre;
  final int pulsos;
  const Compas(this.nombre, this.pulsos);
}

const compasesDisponibles = [
  Compas('2/4', 2),
  Compas('3/4', 3),
  Compas('4/4', 4),
  Compas('2/2', 2),
  Compas('3/8', 3),
  Compas('6/8', 6),
  Compas('9/8', 9),
  Compas('12/8', 12),
  Compas('5/4', 5),
  Compas('7/4', 7),
  Compas('5/8', 5),
  Compas('7/8', 7),
];

/// Nombre italiano del tempo según el BPM (de larghissimo a
/// prestissimo). Los límites entre denominaciones varían algo según
/// la fuente; se ha elegido una división continua y sin solapes que
/// cubre todo el rango soportado (20-240 BPM).
String nombreItalianoTempo(int bpm) {
  if (bpm <= 24) return 'Larghissimo';
  if (bpm <= 45) return 'Grave';
  if (bpm <= 60) return 'Largo';
  if (bpm <= 66) return 'Larghetto';
  if (bpm <= 76) return 'Adagio';
  if (bpm <= 108) return 'Andante';
  if (bpm <= 120) return 'Moderato';
  if (bpm <= 156) return 'Allegro';
  if (bpm <= 176) return 'Vivace';
  if (bpm <= 200) return 'Presto';
  return 'Prestissimo';
}

/// Pool de reproductores para un mismo sonido: a tempos altos con
/// subdivisión (hasta 16 clics/seg) reutilizar un único AudioPlayer
/// con seek()+resume() en cada tick provoca condiciones de carrera en
/// el backend web (errores "Bad state: No element"). Rotando entre
/// varias instancias, cada una tiene tiempo de sobra para terminar su
/// reproducción corta antes de que le vuelva a tocar turno.
class _PoolSonido {
  final List<AudioPlayer> _jugadores;
  int _indice = 0;
  // lowLatency (SoundPool) en Android tiene un bug conocido con
  // AssetSource: no suena y no lanza ningún error (ver
  // github.com/bluefireteam/audioplayers/issues/1193) — se reproduce
  // igual en audioplayers 6.8.1. En mediaPlayer, a diferencia de
  // SoundPool, `resume()` no reinicia el clip a 0 si ya había
  // terminado de sonar (retoma desde donde se quedó, es decir, desde
  // el final = silencio) — por eso Android necesita también un
  // seek(Duration.zero) antes de cada resume(). El resto de
  // plataformas mantiene solo resume(): con seek() de por medio se
  // reproducían condiciones de carrera en el backend web ("Bad state:
  // No element", ver comentario de la clase) que el pool rotatorio ya
  // evita sin necesidad de seek.
  final bool _esAndroid;

  _PoolSonido(String nombre, {int tamano = 4})
      : _jugadores = List.generate(tamano, (i) => AudioPlayer(playerId: 'metronomo_${nombre}_$i')),
        _esAndroid = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> preparar(String assetPath) => Future.wait(_jugadores.map((p) async {
        await p.setPlayerMode(_esAndroid ? PlayerMode.mediaPlayer : PlayerMode.lowLatency);
        await p.setSource(AssetSource(assetPath));
      }));

  void reproducir() {
    final jugador = _jugadores[_indice];
    _indice = (_indice + 1) % _jugadores.length;
    // Un fallo puntual de reproducción no debe tumbar el reloj del
    // metrónomo ni aparecer como excepción no controlada.
    if (_esAndroid) {
      jugador.seek(Duration.zero).then((_) => jugador.resume()).catchError((_) {});
    } else {
      jugador.resume().catchError((_) {});
    }
  }

  Future<void> dispose() => Future.wait(_jugadores.map((p) => p.dispose()));
}

/// Metrónomo digital: BPM 20-240, compases 2/4 3/4 4/4 6/8, acento en
/// el primer pulso, figuras de subdivisión (negra/corchea/tresillo/
/// semicorchea). Usa reloj absoluto (cada tick se reprograma contra
/// la hora objetivo desde el inicio, no un intervalo fijo repetido)
/// para que el tempo no se desvíe con el uso prolongado.
class MetronomoService {
  int bpm;
  Compas compas;
  FiguraClic figura;

  final _sonidoAlto = _PoolSonido('alto');
  final _sonidoMedio = _PoolSonido('medio');
  final _sonidoBajo = _PoolSonido('bajo');
  bool _playersListos = false;

  Timer? _timer;
  DateTime? _inicio;
  int _tickIndex = 0;

  final _pulsoController = StreamController<int>.broadcast();

  /// Emite el nº de pulso (1-indexado) cada vez que empieza uno nuevo.
  Stream<int> get pulsoActual => _pulsoController.stream;
  bool get sonando => _timer != null;

  MetronomoService({
    this.bpm = 100,
    Compas? compas,
    this.figura = FiguraClic.negra,
  }) : compas = compas ?? compasesDisponibles[2];

  Future<void> _prepararPlayers() async {
    if (_playersListos) return;
    await Future.wait([
      _sonidoAlto.preparar('audio/click_alto.wav'),
      _sonidoMedio.preparar('audio/click_medio.wav'),
      _sonidoBajo.preparar('audio/click_bajo.wav'),
    ]);
    _playersListos = true;
  }

  Future<void> iniciar() async {
    if (sonando) return;
    await _prepararPlayers();
    _tickIndex = 0;
    _inicio = DateTime.now();
    _programarSiguiente();
  }

  Future<void> detener() async {
    _timer?.cancel();
    _timer = null;
  }

  void cambiarBpm(int nuevoBpm) {
    bpm = nuevoBpm.clamp(20, 240);
    _reiniciarReloj();
  }

  void cambiarCompas(Compas nuevo) {
    compas = nuevo;
    _reiniciarReloj();
  }

  void cambiarFigura(FiguraClic nueva) {
    figura = nueva;
    _reiniciarReloj();
  }

  /// Al cambiar tempo/compás/figura en marcha, redefine la referencia
  /// del reloj absoluto en "ahora" en vez de intentar cuadrar los
  /// ticks pasados con el nuevo intervalo (evitaría un salto raro).
  void _reiniciarReloj() {
    if (!sonando) return;
    _timer?.cancel();
    _tickIndex = 0;
    _inicio = DateTime.now();
    _programarSiguiente();
  }

  void _programarSiguiente() {
    final msPorPulso = 60000 / bpm;
    final msPorSubclick = msPorPulso / figura.subdivisiones;
    final objetivo = _inicio!.add(Duration(microseconds: (_tickIndex * msPorSubclick * 1000).round()));
    final retraso = objetivo.difference(DateTime.now());
    _timer = Timer(retraso.isNegative ? Duration.zero : retraso, _tick);
  }

  void _tick() {
    final subdivisiones = figura.subdivisiones;
    final pulsoIndex = (_tickIndex ~/ subdivisiones) % compas.pulsos;
    final subclickIndex = _tickIndex % subdivisiones;

    if (subclickIndex == 0) {
      _pulsoController.add(pulsoIndex + 1);
      (pulsoIndex == 0 ? _sonidoAlto : _sonidoMedio).reproducir();
    } else {
      _sonidoBajo.reproducir();
    }

    _tickIndex++;
    _programarSiguiente();
  }

  Future<void> dispose() async {
    _timer?.cancel();
    await _sonidoAlto.dispose();
    await _sonidoMedio.dispose();
    await _sonidoBajo.dispose();
    await _pulsoController.close();
  }
}
