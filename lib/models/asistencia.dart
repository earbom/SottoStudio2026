import 'package:intl/intl.dart';
import '../utils/curso_escolar.dart';

final _formatoFecha = DateFormat('yyyy-MM-dd');

class Asistencia {
  final String? id;
  final String alumnoId;
  final String asignaturaId;
  final String fecha; // 'yyyy-MM-dd'
  final bool asistio;
  // Solo tiene sentido cuando asistio == true: asistió pero llegó
  // tarde. No es un tercer valor de "asistio" para no romper el resto
  // de lógica (rankings, estadísticas...) que ya asume booleano.
  final bool retraso;
  final String marcadaPor;
  final DateTime marcadaEn;

  Asistencia({
    this.id,
    required this.alumnoId,
    required this.asignaturaId,
    required this.fecha,
    required this.asistio,
    this.retraso = false,
    required this.marcadaPor,
    required this.marcadaEn,
  });

  /// ID determinista: permite marcar asistencia con un set(merge:true)
  /// idempotente y listar por rango de prefijo de documentId() sin
  /// necesitar un índice compuesto adicional. Depende de que '_' nunca
  /// aparezca en un uid de Firebase Auth ni en un id autogenerado de
  /// Firestore (cierto hoy, no cambiar el separador sin comprobarlo).
  static String idPara({
    required String alumnoId,
    required String asignaturaId,
    required DateTime fecha,
  }) =>
      '${alumnoId}_${asignaturaId}_${formatearFecha(fecha)}';

  static String formatearFecha(DateTime fecha) => _formatoFecha.format(fecha);

  factory Asistencia.fromMap(String id, Map<String, dynamic> data) {
    return Asistencia(
      id: id,
      alumnoId: data['alumnoId'] ?? '',
      asignaturaId: data['asignaturaId'] ?? '',
      fecha: data['fecha'] ?? '',
      asistio: data['asistio'] ?? false,
      retraso: data['retraso'] ?? false,
      marcadaPor: data['marcadaPor'] ?? '',
      marcadaEn: DateTime.tryParse(data['marcadaEn'] ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'alumnoId': alumnoId,
      'asignaturaId': asignaturaId,
      'fecha': fecha,
      'asistio': asistio,
      'retraso': retraso,
      'marcadaPor': marcadaPor,
      'marcadaEn': marcadaEn.toIso8601String(),
      // Derivado de 'fecha', no es un campo propio del modelo Dart
      // (no se lee de vuelta en fromMap) — solo para que
      // firestore.rules pueda saber a qué matrícula corresponde este
      // registro (matriculas/{alumnoId}_{asignaturaId}_{cursoEscolar})
      // sin tener que parsear fechas ni consultar configuracion/centro
      // desde la regla. Mismo patrón que Nota.fechaDia.
      'cursoEscolar': cursoEscolarDeFecha(DateTime.parse(fecha)),
    };
  }
}
