/// Plus de horas por orquesta (pedido por dirección): matricular a un
/// alumno en una asignatura tipo "Orquesta de guitarras" puede sumar
/// tiempo fijo semanal al cómputo de OTRA asignatura (p.ej. "Guitarra")
/// — pensado para reconocer que tocar en una orquesta también es
/// práctica del instrumento. Catálogo gestionado por dirección; se
/// elige uno (o ninguno) al matricular, ver `Matricula.plusOrquestaId`.
///
/// `minutosSemana` (antes `horasSemana`, un `double`): el tiempo que
/// aporta un plus suele ser más corto que una hora completa (p. ej.
/// 15-20 min de ensayo de orquesta), así que introducirlo en minutos
/// (entero) es más natural que forzar fracciones de hora imprecisas —
/// reportado tras probar la app.
class PlusOrquesta {
  final String? id;
  final String nombre;
  final String asignaturaDestinoId;
  final int minutosSemana;
  final DateTime createdAt;
  final String createdBy;

  PlusOrquesta({
    this.id,
    required this.nombre,
    required this.asignaturaDestinoId,
    required this.minutosSemana,
    required this.createdAt,
    required this.createdBy,
  });

  factory PlusOrquesta.fromMap(String id, Map<String, dynamic> data) {
    return PlusOrquesta(
      id: id,
      nombre: data['nombre'] ?? '',
      asignaturaDestinoId: data['asignaturaDestinoId'] ?? '',
      minutosSemana: (data['minutosSemana'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.tryParse(data['createdAt'] ?? '') ?? DateTime.now(),
      createdBy: data['createdBy'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'nombre': nombre,
      'asignaturaDestinoId': asignaturaDestinoId,
      'minutosSemana': minutosSemana,
      'createdAt': createdAt.toIso8601String(),
      'createdBy': createdBy,
    };
  }
}
