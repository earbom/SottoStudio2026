enum TipoSesion { instrumento, teorico }

TipoSesion tipoSesionDesdeTexto(String texto) =>
    texto == 'teorico' ? TipoSesion.teorico : TipoSesion.instrumento;

class SesionEstudio {
  final String? id;
  final String alumnoId;
  final TipoSesion tipo;
  final String? instrumento;
  final DateTime fechaInicio;
  final DateTime? fechaFin;
  final int duracionTotalMs;
  final int duracionEfectivaMs;
  final double? umbralDbUsado;

  SesionEstudio({
    this.id,
    required this.alumnoId,
    required this.tipo,
    this.instrumento,
    required this.fechaInicio,
    this.fechaFin,
    required this.duracionTotalMs,
    required this.duracionEfectivaMs,
    this.umbralDbUsado,
  });

  factory SesionEstudio.fromMap(String id, Map<String, dynamic> data) {
    return SesionEstudio(
      id: id,
      alumnoId: data['alumnoId'] ?? '',
      tipo: tipoSesionDesdeTexto(data['tipo'] ?? 'instrumento'),
      instrumento: data['instrumento'],
      fechaInicio: DateTime.tryParse(data['fechaInicio'] ?? '') ?? DateTime.now(),
      fechaFin: data['fechaFin'] != null
          ? DateTime.tryParse(data['fechaFin'])
          : null,
      duracionTotalMs: data['duracionTotalMs'] ?? 0,
      duracionEfectivaMs: data['duracionEfectivaMs'] ?? 0,
      umbralDbUsado: (data['umbralDbUsado'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'alumnoId': alumnoId,
      'tipo': tipo.name,
      'instrumento': instrumento,
      'fechaInicio': fechaInicio.toIso8601String(),
      'fechaFin': fechaFin?.toIso8601String(),
      'duracionTotalMs': duracionTotalMs,
      'duracionEfectivaMs': duracionEfectivaMs,
      'umbralDbUsado': umbralDbUsado,
    };
  }
}
