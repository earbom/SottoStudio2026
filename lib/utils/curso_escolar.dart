/// Un curso escolar se representa como texto "yyyy-yyyy" (p.ej.
/// "2026-2027") y sigue la convención española estándar: va del 1 de
/// septiembre del primer año al 31 de agosto del segundo. Se usa '-' y
/// no '/' porque este valor forma parte de IDs deterministas de
/// Firestore (matriculas) — '/' ahí se interpretaría como separador de
/// ruta y rompería el ID. No se modela un calendario lectivo con
/// festivos/vacaciones (mismo criterio que el resto de la app, ver
/// CLAUDE.md).
({DateTime inicio, DateTime fin}) rangoDeCursoEscolar(String cursoEscolar) {
  final partes = cursoEscolar.split('-');
  final anioInicio = int.parse(partes[0]);
  final anioFin = int.parse(partes[1]);
  return (
    inicio: DateTime(anioInicio, 9, 1),
    fin: DateTime(anioFin, 8, 31, 23, 59, 59),
  );
}

/// Curso escolar al que pertenece una fecha dada (inverso de
/// `rangoDeCursoEscolar`): útil para clasificar datos históricos por
/// curso escolar sin tener que guardar el campo en cada documento.
String cursoEscolarDeFecha(DateTime fecha) {
  final anioInicio = fecha.month >= 9 ? fecha.year : fecha.year - 1;
  return '$anioInicio-${anioInicio + 1}';
}
