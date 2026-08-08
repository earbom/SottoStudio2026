import 'package:intl/intl.dart';

final _formatoFecha = DateFormat('yyyy-MM-dd');

/// Concede a un profesor acceso temporal (poner notas, marcar
/// asistencia) a TODOS los alumnos de una asignatura para UN día
/// concreto — cubre el caso de que el profesor habitual falte y otro
/// dé la clase ese día. Un documento por día sustituido (ver idPara).
class Sustitucion {
  final String? id;
  final String asignaturaId;
  final String profesorId;
  final String fecha; // 'yyyy-MM-dd'
  final String creadaPor;
  final DateTime creadaEn;

  Sustitucion({
    this.id,
    required this.asignaturaId,
    required this.profesorId,
    required this.fecha,
    required this.creadaPor,
    required this.creadaEn,
  });

  static String idPara({
    required String asignaturaId,
    required String profesorId,
    required DateTime fecha,
  }) =>
      '${asignaturaId}_${profesorId}_${formatearFecha(fecha)}';

  static String formatearFecha(DateTime fecha) => _formatoFecha.format(fecha);

  factory Sustitucion.fromMap(String id, Map<String, dynamic> data) {
    return Sustitucion(
      id: id,
      asignaturaId: data['asignaturaId'] ?? '',
      profesorId: data['profesorId'] ?? '',
      fecha: data['fecha'] ?? '',
      creadaPor: data['creadaPor'] ?? '',
      creadaEn: DateTime.tryParse(data['creadaEn'] ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'asignaturaId': asignaturaId,
      'profesorId': profesorId,
      'fecha': fecha,
      'creadaPor': creadaPor,
      'creadaEn': creadaEn.toIso8601String(),
    };
  }
}
