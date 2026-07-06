enum EstadoNota { pendiente, supervisada, corregida }

EstadoNota estadoNotaDesdeTexto(String texto) {
  switch (texto) {
    case 'supervisada':
      return EstadoNota.supervisada;
    case 'corregida':
      return EstadoNota.corregida;
    case 'pendiente':
    default:
      return EstadoNota.pendiente;
  }
}

class Nota {
  final String? id;
  final String alumnoId;
  final String profesorId;
  final String asignatura;
  final double valor; // 0-10
  final String comentario;
  final DateTime fecha;
  final EstadoNota estado;

  Nota({
    this.id,
    required this.alumnoId,
    required this.profesorId,
    required this.asignatura,
    required this.valor,
    required this.comentario,
    required this.fecha,
    this.estado = EstadoNota.pendiente,
  });

  factory Nota.fromMap(String id, Map<String, dynamic> data) {
    return Nota(
      id: id,
      alumnoId: data['alumnoId'] ?? '',
      profesorId: data['profesorId'] ?? '',
      asignatura: data['asignatura'] ?? '',
      valor: (data['valor'] as num?)?.toDouble() ?? 0,
      comentario: data['comentario'] ?? '',
      fecha: DateTime.tryParse(data['fecha'] ?? '') ?? DateTime.now(),
      estado: estadoNotaDesdeTexto(data['estado'] ?? 'pendiente'),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'alumnoId': alumnoId,
      'profesorId': profesorId,
      'asignatura': asignatura,
      'valor': valor,
      'comentario': comentario,
      'fecha': fecha.toIso8601String(),
      'estado': estado.name,
    };
  }
}
