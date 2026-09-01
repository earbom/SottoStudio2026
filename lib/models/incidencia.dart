enum TipoIncidencia { problema, sugerencia }
enum EstadoIncidencia { pendiente, resuelto }

TipoIncidencia tipoIncidenciaDesdeTexto(String texto) =>
    texto == 'sugerencia' ? TipoIncidencia.sugerencia : TipoIncidencia.problema;

EstadoIncidencia estadoIncidenciaDesdeTexto(String texto) =>
    texto == 'resuelto' ? EstadoIncidencia.resuelto : EstadoIncidencia.pendiente;

/// Un comentario dentro del hilo de una incidencia — embebido en el
/// propio documento (no una subcolección, convención del resto del
/// proyecto, ver CLAUDE.md).
class ComentarioIncidencia {
  final String autorId;
  final String autorNombre;
  final String texto;
  final DateTime fecha;

  ComentarioIncidencia({
    required this.autorId,
    required this.autorNombre,
    required this.texto,
    required this.fecha,
  });

  factory ComentarioIncidencia.fromMap(Map<String, dynamic> data) => ComentarioIncidencia(
        autorId: data['autorId'] ?? '',
        autorNombre: data['autorNombre'] ?? '',
        texto: data['texto'] ?? '',
        fecha: DateTime.tryParse(data['fecha']?.toString() ?? '') ?? DateTime.now(),
      );

  Map<String, dynamic> toMap() => {
        'autorId': autorId,
        'autorNombre': autorNombre,
        'texto': texto,
        'fecha': fecha.toIso8601String(),
      };
}

/// Reporte de un problema o sugerencia enviado por cualquier usuario
/// autenticado (ver CLAUDE.md, modo desarrollador). Solo el
/// desarrollador puede leer/gestionar todos; cada autor solo ve y
/// comenta los suyos, sin poder resolverlos él mismo.
class Incidencia {
  final String? id;
  final String autorId;
  // Denormalizado al crear (mismo patrón que sesionesEstudio.alumnoNombre):
  // un autor normal no puede leer el perfil `usuarios` de otro, y el
  // desarrollador necesita ver el nombre sin una lectura extra por fila.
  final String autorNombre;
  final TipoIncidencia tipo;
  final String descripcion;
  final EstadoIncidencia estado;
  final DateTime fecha;
  final List<ComentarioIncidencia> comentarios;

  Incidencia({
    this.id,
    required this.autorId,
    required this.autorNombre,
    required this.tipo,
    required this.descripcion,
    this.estado = EstadoIncidencia.pendiente,
    required this.fecha,
    this.comentarios = const [],
  });

  factory Incidencia.fromMap(String id, Map<String, dynamic> data) => Incidencia(
        id: id,
        autorId: data['autorId'] ?? '',
        autorNombre: data['autorNombre'] ?? '',
        tipo: tipoIncidenciaDesdeTexto(data['tipo'] ?? 'problema'),
        descripcion: data['descripcion'] ?? '',
        estado: estadoIncidenciaDesdeTexto(data['estado'] ?? 'pendiente'),
        fecha: DateTime.tryParse(data['fecha']?.toString() ?? '') ?? DateTime.now(),
        comentarios: (data['comentarios'] as List<dynamic>? ?? [])
            .map((c) => ComentarioIncidencia.fromMap(Map<String, dynamic>.from(c as Map)))
            .toList(),
      );

  Map<String, dynamic> toMap() => {
        'autorId': autorId,
        'autorNombre': autorNombre,
        'tipo': tipo.name,
        'descripcion': descripcion,
        'estado': estado.name,
        'fecha': fecha.toIso8601String(),
        'comentarios': comentarios.map((c) => c.toMap()).toList(),
      };
}
