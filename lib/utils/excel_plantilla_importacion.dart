import 'dart:typed_data';
import 'package:excel/excel.dart' as xls;

/// Nombres de columnas y hojas de la plantilla de importación masiva
/// (ver CLAUDE.md) — dirección descarga esta plantilla FIJA, la
/// rellena con sus datos (hoy en hojas de Excel/Google Drive no
/// homogéneas) y la vuelve a subir. Deliberadamente NO se intenta
/// adivinar el formato de una hoja ya existente de dirección: es más
/// fiable pedirle que copie sus datos a este formato conocido una vez,
/// que a un "importador inteligente" que se rompería con cada
/// variación real de sus hojas.
const hojaCursosAsignaturas = 'Cursos y asignaturas';
const hojaAlumnosMatriculas = 'Alumnos y matrículas';

const _nombresDiasSemana = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];

/// Una fila de la hoja "Cursos y asignaturas": un (curso, asignatura).
class FilaCursoAsignatura {
  final String curso;
  final String asignatura;
  final bool instrumento;
  final double objetivoSemanal;
  final double objetivoMensual;

  FilaCursoAsignatura({
    required this.curso,
    required this.asignatura,
    required this.instrumento,
    required this.objetivoSemanal,
    required this.objetivoMensual,
  });
}

/// Una fila de la hoja "Alumnos y matrículas": un (alumno, asignatura)
/// — una fila por cada combinación, no listas separadas por comas
/// (decisión confirmada con dirección).
class FilaAlumnoMatricula {
  final String nombre;
  final String apellidos;
  final String? email; // vacío = alumno sin cuenta de acceso, ver CLAUDE.md
  final String curso;
  final String asignatura;
  final List<int> diasSemana;

  FilaAlumnoMatricula({
    required this.nombre,
    required this.apellidos,
    required this.email,
    required this.curso,
    required this.asignatura,
    required this.diasSemana,
  });
}

/// Genera la plantilla en blanco (cabeceras + 2 filas de ejemplo) para
/// que dirección la descargue y rellene.
Uint8List generarPlantillaImportacion() {
  final libro = xls.Excel.createExcel();

  libro.appendRow(hojaCursosAsignaturas, [
    xls.TextCellValue('Curso'),
    xls.TextCellValue('Asignatura'),
    xls.TextCellValue('Instrumento (Sí/No)'),
    xls.TextCellValue('Objetivo semanal horas (opcional)'),
    xls.TextCellValue('Objetivo mensual horas (opcional)'),
  ]);
  libro.appendRow(hojaCursosAsignaturas, [
    xls.TextCellValue('1º Elemental'),
    xls.TextCellValue('Piano'),
    xls.TextCellValue('Sí'),
    xls.TextCellValue('2'),
    xls.TextCellValue('8'),
  ]);
  libro.appendRow(hojaCursosAsignaturas, [
    xls.TextCellValue('1º Elemental'),
    xls.TextCellValue('Lenguaje musical'),
    xls.TextCellValue('No'),
    xls.TextCellValue(''),
    xls.TextCellValue(''),
  ]);

  libro.appendRow(hojaAlumnosMatriculas, [
    xls.TextCellValue('Nombre'),
    xls.TextCellValue('Apellidos'),
    xls.TextCellValue('Email (opcional, vacío = sin cuenta de acceso)'),
    xls.TextCellValue('Curso'),
    xls.TextCellValue('Asignatura'),
    xls.TextCellValue('Días de clase (opcional, ej. L,X)'),
  ]);
  libro.appendRow(hojaAlumnosMatriculas, [
    xls.TextCellValue('Ana'),
    xls.TextCellValue('García López'),
    xls.TextCellValue('ana@example.com'),
    xls.TextCellValue('1º Elemental'),
    xls.TextCellValue('Piano'),
    xls.TextCellValue('L'),
  ]);
  libro.appendRow(hojaAlumnosMatriculas, [
    xls.TextCellValue('Ana'),
    xls.TextCellValue('García López'),
    xls.TextCellValue('ana@example.com'),
    xls.TextCellValue('1º Elemental'),
    xls.TextCellValue('Lenguaje musical'),
    xls.TextCellValue('X'),
  ]);

  // La plantilla no necesita la hoja "Sheet1" por defecto, vacía.
  if (libro.sheets.containsKey('Sheet1')) {
    libro.delete('Sheet1');
  }

  return Uint8List.fromList(libro.save()!);
}

String _celda(List<xls.Data?> fila, int i) {
  if (i >= fila.length) return '';
  return fila[i]?.value?.toString().trim() ?? '';
}

bool _esSiNo(String texto) => texto.trim().toLowerCase().startsWith('s');

double _numero(String texto) => double.tryParse(texto.replaceAll(',', '.')) ?? 0;

List<int> _diasDesdeTexto(String texto) {
  if (texto.trim().isEmpty) return const [];
  return texto
      .split(',')
      .map((s) => s.trim().toUpperCase())
      .map((s) => _nombresDiasSemana.indexOf(s) + 1)
      .where((d) => d > 0)
      .toList();
}

/// Lee un archivo .xlsx con el formato de [generarPlantillaImportacion]
/// y lo convierte en listas de filas Dart, saltando la fila de
/// cabecera de cada hoja. Lanza [FormatException] si falta alguna de
/// las dos hojas esperadas.
({List<FilaCursoAsignatura> cursos, List<FilaAlumnoMatricula> alumnos})
    parsearPlantillaImportacion(Uint8List bytes) {
  final libro = xls.Excel.decodeBytes(bytes);

  final hojaCursos = libro.sheets[hojaCursosAsignaturas];
  final hojaAlumnos = libro.sheets[hojaAlumnosMatriculas];
  if (hojaCursos == null || hojaAlumnos == null) {
    throw const FormatException(
        'El archivo no tiene las hojas esperadas ("$hojaCursosAsignaturas" y "$hojaAlumnosMatriculas"). '
        'Descarga la plantilla y rellénala sin cambiar los nombres de las hojas.');
  }

  final cursos = <FilaCursoAsignatura>[];
  for (final fila in hojaCursos.rows.skip(1)) {
    final curso = _celda(fila, 0);
    final asignatura = _celda(fila, 1);
    if (curso.isEmpty || asignatura.isEmpty) continue;
    cursos.add(FilaCursoAsignatura(
      curso: curso,
      asignatura: asignatura,
      instrumento: _esSiNo(_celda(fila, 2)),
      objetivoSemanal: _numero(_celda(fila, 3)),
      objetivoMensual: _numero(_celda(fila, 4)),
    ));
  }

  final alumnos = <FilaAlumnoMatricula>[];
  for (final fila in hojaAlumnos.rows.skip(1)) {
    final nombre = _celda(fila, 0);
    final curso = _celda(fila, 3);
    final asignatura = _celda(fila, 4);
    if (nombre.isEmpty || curso.isEmpty || asignatura.isEmpty) continue;
    final email = _celda(fila, 2);
    alumnos.add(FilaAlumnoMatricula(
      nombre: nombre,
      apellidos: _celda(fila, 1),
      email: email.isEmpty ? null : email,
      curso: curso,
      asignatura: asignatura,
      diasSemana: _diasDesdeTexto(_celda(fila, 5)),
    ));
  }

  return (cursos: cursos, alumnos: alumnos);
}
