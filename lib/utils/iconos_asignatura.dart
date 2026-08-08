import 'package:flutter/material.dart' show Icons;
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

/// Catálogo fijo de iconos seleccionables para una asignatura O UN
/// CURSO (mismo catálogo para ambos), pensado como "iconos de
/// escritorio". La clave (`id`) es lo único que se guarda en Firestore
/// (`Asignatura.iconoId` / `Curso.iconoId`); el `FaIconData` se
/// resuelve en cliente (ver `iconoAsignaturaPorId`) para poder ampliar
/// o reordenar el catálogo sin migrar datos.
///
/// Font Awesome Free no tiene iconos de viento o cuerda-frotada
/// (violín, trompeta...) como glifos propios — solo guitarra y
/// batería entre instrumentos concretos — así que el resto del
/// catálogo usa iconos musicales/de estudio genéricos en vez de
/// inventar glifos que no existen en la librería. Tampoco tiene un
/// piano de verdad (`solidKeyboard` es un teclado de ordenador, no un
/// piano) — para ese caso concreto se envuelve un icono de Material
/// (`Icons.piano`, sí incluido en Flutter) en `FaIconData`: `FaIcon`
/// no exige que el glifo sea de Font Awesome, solo pinta el
/// `IconData` que se le pase (ver `FaIcon.build`), así que mezclar
/// ambas fuentes en el mismo catálogo es válido sin tocar el resto
/// del código que renderiza con `FaIcon`.
class IconoAsignatura {
  final String id;
  final String etiqueta;
  final FaIconData icono;

  const IconoAsignatura(this.id, this.etiqueta, this.icono);
}

const iconosAsignaturaDisponibles = [
  IconoAsignatura('guitarra', 'Guitarra', FontAwesomeIcons.guitar),
  IconoAsignatura('piano', 'Piano', FaIconData(Icons.piano)),
  IconoAsignatura('teclado', 'Teclado', FontAwesomeIcons.solidKeyboard),
  IconoAsignatura('bateria', 'Batería / percusión', FontAwesomeIcons.drum),
  IconoAsignatura('viento', 'Instrumento de viento', FontAwesomeIcons.bullhorn),
  IconoAsignatura('canto', 'Canto / voz', FontAwesomeIcons.microphone),
  IconoAsignatura('auriculares', 'Audición / oído', FontAwesomeIcons.headphones),
  IconoAsignatura('nota_musical', 'Nota musical', FontAwesomeIcons.music),
  IconoAsignatura('disco', 'Grabación / audio', FontAwesomeIcons.compactDisc),
  IconoAsignatura('partitura', 'Partitura / lenguaje musical', FontAwesomeIcons.fileWaveform),
  IconoAsignatura('teoria', 'Teoría / armonía', FontAwesomeIcons.bookOpen),
  IconoAsignatura('conjunto', 'Coro / conjunto', FontAwesomeIcons.peopleGroup),
  IconoAsignatura('estudio', 'Estudio general', FontAwesomeIcons.graduationCap),
  IconoAsignatura('interpretacion', 'Interpretación', FontAwesomeIcons.masksTheater),
  IconoAsignatura('percusion_corporal', 'Percusión corporal / ritmo', FontAwesomeIcons.handsClapping),
  IconoAsignatura('historia_musica', 'Historia de la música', FontAwesomeIcons.recordVinyl),
  IconoAsignatura('tecnica_produccion', 'Técnica / producción', FontAwesomeIcons.sliders),
  IconoAsignatura('acustica_electronica', 'Acústica / electrónica', FontAwesomeIcons.waveSquare),
  IconoAsignatura('clase_colectiva', 'Clase colectiva', FontAwesomeIcons.personChalkboard),
  IconoAsignatura('composicion', 'Composición', FontAwesomeIcons.pencil),
  IconoAsignatura('analisis_musical', 'Análisis musical', FontAwesomeIcons.bookOpenReader),
  IconoAsignatura('dinamica', 'Dinámica / expresión', FontAwesomeIcons.volumeHigh),
];

const _iconoPorDefecto = IconoAsignatura('nota_musical', 'Nota musical', FontAwesomeIcons.music);

IconoAsignatura iconoAsignaturaPorId(String? id) {
  if (id == null || id.isEmpty) return _iconoPorDefecto;
  for (final i in iconosAsignaturaDisponibles) {
    if (i.id == id) return i;
  }
  return _iconoPorDefecto;
}
