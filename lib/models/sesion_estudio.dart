enum TipoSesion { instrumento, teorico }

TipoSesion tipoSesionDesdeTexto(String texto) =>
    texto == 'teorico' ? TipoSesion.teorico : TipoSesion.instrumento;

class SesionEstudio {
  final String? id;
  final String alumnoId;
  final TipoSesion tipo;
  final String? instrumento;
  final String? asignaturaId; // null = práctica libre, no ligada a asignatura
  final DateTime fechaInicio;
  final DateTime? fechaFin;
  final int duracionTotalMs;
  final int duracionEfectivaMs;
  final double? umbralDbUsado;
  // null = grabada por el propio alumno (micrófono). Con valor = un
  // profesor la anotó a mano (horas semanales de teoría recogidas de
  // un cuaderno en papel, ver CLAUDE.md) — el uid de ESE profesor.
  final String? registradoPorProfesorId;

  SesionEstudio({
    this.id,
    required this.alumnoId,
    required this.tipo,
    this.instrumento,
    this.asignaturaId,
    required this.fechaInicio,
    this.fechaFin,
    required this.duracionTotalMs,
    required this.duracionEfectivaMs,
    this.umbralDbUsado,
    this.registradoPorProfesorId,
  });

  factory SesionEstudio.fromMap(String id, Map<String, dynamic> data) {
    return SesionEstudio(
      id: id,
      alumnoId: data['alumnoId'] ?? '',
      tipo: tipoSesionDesdeTexto(data['tipo'] ?? 'instrumento'),
      instrumento: data['instrumento'],
      asignaturaId: data['asignaturaId'],
      fechaInicio: DateTime.tryParse(data['fechaInicio'] ?? '') ?? DateTime.now(),
      fechaFin: data['fechaFin'] != null
          ? DateTime.tryParse(data['fechaFin'])
          : null,
      duracionTotalMs: data['duracionTotalMs'] ?? 0,
      duracionEfectivaMs: data['duracionEfectivaMs'] ?? 0,
      umbralDbUsado: (data['umbralDbUsado'] as num?)?.toDouble(),
      registradoPorProfesorId: data['registradoPorProfesorId'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'alumnoId': alumnoId,
      'tipo': tipo.name,
      'instrumento': instrumento,
      'asignaturaId': asignaturaId,
      'fechaInicio': fechaInicio.toIso8601String(),
      'fechaFin': fechaFin?.toIso8601String(),
      'duracionTotalMs': duracionTotalMs,
      'duracionEfectivaMs': duracionEfectivaMs,
      'umbralDbUsado': umbralDbUsado,
      'registradoPorProfesorId': registradoPorProfesorId,
    };
  }
}
