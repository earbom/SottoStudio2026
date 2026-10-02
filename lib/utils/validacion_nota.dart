/// Convierte el texto escrito por el profesor en una nota válida
/// (0-10, admite coma decimal). Devuelve null si está vacío o fuera de
/// rango — nunca se debe guardar un 0 por defecto cuando el campo se
/// deja en blanco.
double? parsearValorNota(String texto) {
  final valor = double.tryParse(texto.trim().replaceAll(',', '.'));
  if (valor == null || valor < 0 || valor > 10) return null;
  return valor;
}

const mensajeErrorValorNota = 'Escribe una nota entre 0 y 10 (p. ej. 7,5).';
