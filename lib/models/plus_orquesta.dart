/// Plus de horas por orquesta (pedido por dirección): matricular a un
/// alumno en una asignatura tipo "Orquesta de guitarras" puede sumar
/// horas fijas semanales al cómputo de OTRA asignatura (p.ej.
/// "Guitarra") — pensado para reconocer que tocar en una orquesta
/// también es práctica del instrumento. Catálogo gestionado por
/// dirección; se elige uno (o ninguno) al matricular, ver
/// `Matricula.plusOrquestaId`.
class PlusOrquesta {
  final String? id;
  final String nombre;
  final String asignaturaDestinoId;
  final double horasSemana;
  final DateTime createdAt;
  final String createdBy;

  PlusOrquesta({
    this.id,
    required this.nombre,
    required this.asignaturaDestinoId,
    required this.horasSemana,
    required this.createdAt,
    required this.createdBy,
  });

  factory PlusOrquesta.fromMap(String id, Map<String, dynamic> data) {
    return PlusOrquesta(
      id: id,
      nombre: data['nombre'] ?? '',
      asignaturaDestinoId: data['asignaturaDestinoId'] ?? '',
      horasSemana: (data['horasSemana'] as num?)?.toDouble() ?? 0,
      createdAt: DateTime.tryParse(data['createdAt'] ?? '') ?? DateTime.now(),
      createdBy: data['createdBy'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'nombre': nombre,
      'asignaturaDestinoId': asignaturaDestinoId,
      'horasSemana': horasSemana,
      'createdAt': createdAt.toIso8601String(),
      'createdBy': createdBy,
    };
  }
}
