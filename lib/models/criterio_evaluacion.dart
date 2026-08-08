/// Un criterio de evaluación define, para una asignatura, una
/// actividad/control puntuable y el peso (%) que tiene esa nota en la
/// calificación final. Lo configura dirección; el profesor solo elige
/// el criterio al poner una nota, no re-introduce el peso cada vez.
class CriterioEvaluacion {
  final String? id;
  final String asignaturaId;
  final String nombre;
  final double peso; // porcentaje, 0-100
  final DateTime createdAt;
  final String createdBy;

  CriterioEvaluacion({
    this.id,
    required this.asignaturaId,
    required this.nombre,
    required this.peso,
    required this.createdAt,
    required this.createdBy,
  });

  factory CriterioEvaluacion.fromMap(String id, Map<String, dynamic> data) {
    return CriterioEvaluacion(
      id: id,
      asignaturaId: data['asignaturaId'] ?? '',
      nombre: data['nombre'] ?? '',
      peso: (data['peso'] as num?)?.toDouble() ?? 0,
      createdAt: DateTime.tryParse(data['createdAt'] ?? '') ?? DateTime.now(),
      createdBy: data['createdBy'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'asignaturaId': asignaturaId,
      'nombre': nombre,
      'peso': peso,
      'createdAt': createdAt.toIso8601String(),
      'createdBy': createdBy,
    };
  }
}
