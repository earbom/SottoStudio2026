class Asignatura {
  final String? id;
  final String cursoId;
  final String nombre;
  final List<String> profesorIds;
  final DateTime createdAt;
  final String createdBy;
  // Referencia a IconoAsignatura.id (lib/utils/iconos_asignatura.dart).
  // Vacío/desconocido -> icono por defecto, resuelto siempre en
  // cliente para poder ampliar el catálogo sin migrar documentos.
  final String iconoId;
  // Si el alumno puede grabar sesiones de estudio en esta asignatura.
  // Por defecto false: solo dirección lo activa explícitamente para
  // asignaturas de instrumento — una asignatura teórica (armonía,
  // lenguaje musical...) no tiene sentido que permita grabar (ver
  // CLAUDE.md). Las asignaturas creadas antes de este campo no lo
  // tienen, así que quedan sin permiso hasta que dirección lo active.
  final bool permiteGrabarEstudio;

  Asignatura({
    this.id,
    required this.cursoId,
    required this.nombre,
    required this.profesorIds,
    required this.createdAt,
    required this.createdBy,
    this.iconoId = '',
    this.permiteGrabarEstudio = false,
  });

  factory Asignatura.fromMap(String id, Map<String, dynamic> data) {
    return Asignatura(
      id: id,
      cursoId: data['cursoId'] ?? '',
      nombre: data['nombre'] ?? '',
      profesorIds: List<String>.from(data['profesorIds'] ?? const []),
      createdAt: DateTime.tryParse(data['createdAt'] ?? '') ?? DateTime.now(),
      createdBy: data['createdBy'] ?? '',
      iconoId: data['iconoId'] ?? '',
      permiteGrabarEstudio: data['permiteGrabarEstudio'] ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'cursoId': cursoId,
      'nombre': nombre,
      'profesorIds': profesorIds,
      'createdAt': createdAt.toIso8601String(),
      'createdBy': createdBy,
      'iconoId': iconoId,
      'permiteGrabarEstudio': permiteGrabarEstudio,
    };
  }
}
