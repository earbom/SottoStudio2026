/// Los estudios musicales del centro se organizan en estos niveles.
/// "Sensibilización" no tiene 1º (empieza en 2º); "libre" no tiene
/// número de curso (no sigue una progresión anual).
enum NivelCurso { sensibilizacion, elemental, avanzado, libre }

NivelCurso nivelCursoDesdeTexto(String texto) {
  switch (texto) {
    case 'elemental':
      return NivelCurso.elemental;
    case 'avanzado':
      return NivelCurso.avanzado;
    case 'libre':
      return NivelCurso.libre;
    case 'sensibilizacion':
    default:
      return NivelCurso.sensibilizacion;
  }
}

extension NivelCursoInfo on NivelCurso {
  String get etiqueta => switch (this) {
        NivelCurso.sensibilizacion => 'Sensibilización',
        NivelCurso.elemental => 'Elemental',
        NivelCurso.avanzado => 'Avanzado',
        NivelCurso.libre => 'Estudios libres',
      };

  /// Números de curso válidos para este nivel — vacío para "libre"
  /// (no tiene progresión anual), sin el 1º para sensibilización.
  List<int> get numerosValidos => switch (this) {
        NivelCurso.sensibilizacion => const [2, 3, 4],
        NivelCurso.elemental => const [1, 2, 3, 4],
        NivelCurso.avanzado => const [1, 2, 3, 4],
        NivelCurso.libre => const [],
      };
}

class Curso {
  final String? id;
  final String nombre;
  final String? descripcion;
  final NivelCurso nivel;
  // null para nivel "libre"; para el resto, uno de nivel.numerosValidos.
  final int? numeroCurso;
  // Referencia a IconoAsignatura.id (lib/utils/iconos_asignatura.dart),
  // mismo catálogo que las asignaturas.
  final String iconoId;
  final DateTime createdAt;
  final String createdBy;

  Curso({
    this.id,
    required this.nombre,
    this.descripcion,
    this.nivel = NivelCurso.libre,
    this.numeroCurso,
    this.iconoId = '',
    required this.createdAt,
    required this.createdBy,
  });

  factory Curso.fromMap(String id, Map<String, dynamic> data) {
    return Curso(
      id: id,
      nombre: data['nombre'] ?? '',
      descripcion: data['descripcion'],
      nivel: nivelCursoDesdeTexto(data['nivel'] ?? 'libre'),
      numeroCurso: (data['numeroCurso'] as num?)?.toInt(),
      iconoId: data['iconoId'] ?? '',
      createdAt: DateTime.tryParse(data['createdAt'] ?? '') ?? DateTime.now(),
      createdBy: data['createdBy'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'nombre': nombre,
      'descripcion': descripcion,
      'nivel': nivel.name,
      'numeroCurso': numeroCurso,
      'iconoId': iconoId,
      'createdAt': createdAt.toIso8601String(),
      'createdBy': createdBy,
    };
  }
}
