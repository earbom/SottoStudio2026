import 'dart:math' as math;

const _nombresNotas = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];

/// Frecuencia en Hz de una nota+octava en temperamento igual,
/// referencia La4 (A4) = 440 Hz — mismo convenio que
/// `AfinadorService._frecuenciaANota` (MIDI 69 = A4, C4 = MIDI 60).
double frecuenciaDeNota(String nota, int octava) {
  final indice = _nombresNotas.indexOf(nota);
  final midi = (octava + 1) * 12 + indice;
  return 440 * math.pow(2, (midi - 69) / 12).toDouble();
}

/// Una nota objetivo dentro de una afinación: o bien una cuerda
/// concreta (guitarra, violín...) o la nota de referencia habitual de
/// un instrumento de viento (no tiene "cuerdas", pero sí una nota a la
/// que se afina por convención).
class NotaObjetivo {
  final String etiqueta;
  final String nota;
  final int octava;

  const NotaObjetivo(this.etiqueta, this.nota, this.octava);

  double get frecuencia => frecuenciaDeNota(nota, octava);
}

class AfinacionInstrumento {
  final String nombre;
  final List<NotaObjetivo> notas;

  const AfinacionInstrumento(this.nombre, this.notas);
}

/// Un instrumento seleccionable en el afinador. `frecuenciaMin`/`Max`
/// acotan el rango de análisis de `AfinadorService` a la tesitura real
/// del instrumento (mejora la detección y evita errores de octava);
/// `afinaciones` son las distintas formas de afinarlo — para
/// instrumentos de viento siempre hay una única "afinación" con una
/// sola nota de referencia, no varias cuerdas.
class InstrumentoAfinador {
  final String id;
  final String nombre;
  final double frecuenciaMin;
  final double frecuenciaMax;
  final List<AfinacionInstrumento> afinaciones;

  const InstrumentoAfinador({
    required this.id,
    required this.nombre,
    required this.frecuenciaMin,
    required this.frecuenciaMax,
    required this.afinaciones,
  });
}

const instrumentosAfinador = [
  InstrumentoAfinador(
    id: '',
    nombre: 'Ninguno (cromático general)',
    frecuenciaMin: 55,
    frecuenciaMax: 2000,
    afinaciones: [],
  ),
  InstrumentoAfinador(
    id: 'guitarra',
    nombre: 'Guitarra',
    frecuenciaMin: 65,
    frecuenciaMax: 1000,
    afinaciones: [
      AfinacionInstrumento('Estándar (Mi La Re Sol Si Mi)', [
        NotaObjetivo('6ª · Mi grave', 'E', 2),
        NotaObjetivo('5ª · La', 'A', 2),
        NotaObjetivo('4ª · Re', 'D', 3),
        NotaObjetivo('3ª · Sol', 'G', 3),
        NotaObjetivo('2ª · Si', 'B', 3),
        NotaObjetivo('1ª · Mi agudo', 'E', 4),
      ]),
      AfinacionInstrumento('Drop D (Re La Re Sol Si Mi)', [
        NotaObjetivo('6ª · Re grave', 'D', 2),
        NotaObjetivo('5ª · La', 'A', 2),
        NotaObjetivo('4ª · Re', 'D', 3),
        NotaObjetivo('3ª · Sol', 'G', 3),
        NotaObjetivo('2ª · Si', 'B', 3),
        NotaObjetivo('1ª · Mi agudo', 'E', 4),
      ]),
      AfinacionInstrumento('Media afinación (medio tono abajo)', [
        NotaObjetivo('6ª', 'D#', 2),
        NotaObjetivo('5ª', 'G#', 2),
        NotaObjetivo('4ª', 'C#', 3),
        NotaObjetivo('3ª', 'F#', 3),
        NotaObjetivo('2ª', 'A#', 3),
        NotaObjetivo('1ª', 'D#', 4),
      ]),
      AfinacionInstrumento('Open G (Re Sol Re Sol Si Re)', [
        NotaObjetivo('6ª', 'D', 2),
        NotaObjetivo('5ª', 'G', 2),
        NotaObjetivo('4ª', 'D', 3),
        NotaObjetivo('3ª', 'G', 3),
        NotaObjetivo('2ª', 'B', 3),
        NotaObjetivo('1ª', 'D', 4),
      ]),
      AfinacionInstrumento('Open D (Re La Re Fa# La Re)', [
        NotaObjetivo('6ª', 'D', 2),
        NotaObjetivo('5ª', 'A', 2),
        NotaObjetivo('4ª', 'D', 3),
        NotaObjetivo('3ª', 'F#', 3),
        NotaObjetivo('2ª', 'A', 3),
        NotaObjetivo('1ª', 'D', 4),
      ]),
      AfinacionInstrumento('DADGAD', [
        NotaObjetivo('6ª', 'D', 2),
        NotaObjetivo('5ª', 'A', 2),
        NotaObjetivo('4ª', 'D', 3),
        NotaObjetivo('3ª', 'G', 3),
        NotaObjetivo('2ª', 'A', 3),
        NotaObjetivo('1ª', 'D', 4),
      ]),
    ],
  ),
  InstrumentoAfinador(
    id: 'ukelele',
    nombre: 'Ukelele',
    frecuenciaMin: 240,
    frecuenciaMax: 500,
    afinaciones: [
      AfinacionInstrumento('Estándar reentrante (Sol Do Mi La)', [
        NotaObjetivo('4ª · Sol', 'G', 4),
        NotaObjetivo('3ª · Do', 'C', 4),
        NotaObjetivo('2ª · Mi', 'E', 4),
        NotaObjetivo('1ª · La', 'A', 4),
      ]),
    ],
  ),
  InstrumentoAfinador(
    id: 'violin',
    nombre: 'Violín',
    frecuenciaMin: 150,
    frecuenciaMax: 2000,
    afinaciones: [
      AfinacionInstrumento('Estándar (Sol Re La Mi)', [
        NotaObjetivo('4ª · Sol', 'G', 3),
        NotaObjetivo('3ª · Re', 'D', 4),
        NotaObjetivo('2ª · La', 'A', 4),
        NotaObjetivo('1ª · Mi', 'E', 5),
      ]),
    ],
  ),
  InstrumentoAfinador(
    id: 'viola',
    nombre: 'Viola',
    frecuenciaMin: 100,
    frecuenciaMax: 1500,
    afinaciones: [
      AfinacionInstrumento('Estándar (Do Sol Re La)', [
        NotaObjetivo('4ª · Do grave', 'C', 3),
        NotaObjetivo('3ª · Sol', 'G', 3),
        NotaObjetivo('2ª · Re', 'D', 4),
        NotaObjetivo('1ª · La', 'A', 4),
      ]),
    ],
  ),
  InstrumentoAfinador(
    id: 'violonchelo',
    nombre: 'Violonchelo',
    frecuenciaMin: 50,
    frecuenciaMax: 1000,
    afinaciones: [
      AfinacionInstrumento('Estándar (Do Sol Re La)', [
        NotaObjetivo('4ª · Do grave', 'C', 2),
        NotaObjetivo('3ª · Sol', 'G', 2),
        NotaObjetivo('2ª · Re', 'D', 3),
        NotaObjetivo('1ª · La', 'A', 3),
      ]),
    ],
  ),
  InstrumentoAfinador(
    id: 'contrabajo',
    nombre: 'Contrabajo',
    frecuenciaMin: 30,
    frecuenciaMax: 500,
    afinaciones: [
      AfinacionInstrumento('Estándar orquestal (Mi La Re Sol)', [
        NotaObjetivo('4ª · Mi grave', 'E', 1),
        NotaObjetivo('3ª · La', 'A', 1),
        NotaObjetivo('2ª · Re', 'D', 2),
        NotaObjetivo('1ª · Sol', 'G', 2),
      ]),
    ],
  ),
  InstrumentoAfinador(
    id: 'flauta',
    nombre: 'Flauta travesera',
    frecuenciaMin: 200,
    frecuenciaMax: 2200,
    afinaciones: [
      AfinacionInstrumento('Nota de referencia', [
        NotaObjetivo('La (afinación orquestal)', 'A', 4),
      ]),
    ],
  ),
  InstrumentoAfinador(
    id: 'oboe',
    nombre: 'Oboe',
    frecuenciaMin: 200,
    frecuenciaMax: 2000,
    afinaciones: [
      AfinacionInstrumento('Nota de referencia', [
        NotaObjetivo('La (da el diapasón a la orquesta)', 'A', 4),
      ]),
    ],
  ),
  InstrumentoAfinador(
    id: 'clarinete',
    nombre: 'Clarinete',
    frecuenciaMin: 140,
    frecuenciaMax: 2000,
    afinaciones: [
      AfinacionInstrumento('Nota de referencia', [
        NotaObjetivo('Si bemol (afinación de banda)', 'A#', 4),
      ]),
    ],
  ),
  InstrumentoAfinador(
    id: 'fagot',
    nombre: 'Fagot',
    frecuenciaMin: 40,
    frecuenciaMax: 1000,
    afinaciones: [
      AfinacionInstrumento('Nota de referencia', [
        NotaObjetivo('Si bemol', 'A#', 2),
      ]),
    ],
  ),
  InstrumentoAfinador(
    id: 'trompa',
    nombre: 'Trompa',
    frecuenciaMin: 50,
    frecuenciaMax: 1000,
    afinaciones: [
      AfinacionInstrumento('Nota de referencia', [
        NotaObjetivo('Fa', 'F', 3),
      ]),
    ],
  ),
  InstrumentoAfinador(
    id: 'trompeta',
    nombre: 'Trompeta',
    frecuenciaMin: 150,
    frecuenciaMax: 1500,
    afinaciones: [
      AfinacionInstrumento('Nota de referencia', [
        NotaObjetivo('Si bemol (afinación de banda)', 'A#', 4),
      ]),
    ],
  ),
  InstrumentoAfinador(
    id: 'trombon',
    nombre: 'Trombón',
    frecuenciaMin: 60,
    frecuenciaMax: 1000,
    afinaciones: [
      AfinacionInstrumento('Nota de referencia', [
        NotaObjetivo('Si bemol', 'A#', 3),
      ]),
    ],
  ),
  InstrumentoAfinador(
    id: 'saxofon',
    nombre: 'Saxofón',
    frecuenciaMin: 100,
    frecuenciaMax: 1000,
    afinaciones: [
      AfinacionInstrumento('Nota de referencia', [
        NotaObjetivo('Si bemol (afinación de banda)', 'A#', 4),
      ]),
    ],
  ),
  InstrumentoAfinador(
    id: 'tuba',
    nombre: 'Tuba',
    frecuenciaMin: 30,
    frecuenciaMax: 1000,
    afinaciones: [
      AfinacionInstrumento('Nota de referencia', [
        NotaObjetivo('Si bemol', 'A#', 1),
      ]),
    ],
  ),
];
