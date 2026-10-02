import 'package:intl/intl.dart';
import '../utils/curso_escolar.dart';

final _formatoFechaDia = DateFormat('yyyy-MM-dd');

// Dirección solo VALIDA la nota final (un único botón): se guarda como
// `supervisada`. `corregida` queda por compatibilidad con notas
// antiguas y se muestra igual, como validada.
enum EstadoNota { pendiente, supervisada, corregida }

extension EtiquetaEstadoNota on EstadoNota {
  String get etiqueta => this == EstadoNota.pendiente ? 'Pendiente de validar' : 'Validada por dirección';
}

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
  final String asignaturaId;
  final String criterioId; // referencia a criteriosEvaluacion/{id}: define el peso
  final double valor; // 0-10
  final String comentario;
  final DateTime fecha;
  final EstadoNota estado;

  Nota({
    this.id,
    required this.alumnoId,
    required this.profesorId,
    required this.asignaturaId,
    required this.criterioId,
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
      asignaturaId: data['asignaturaId'] ?? '',
      criterioId: data['criterioId'] ?? '',
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
      'asignaturaId': asignaturaId,
      'criterioId': criterioId,
      'valor': valor,
      'comentario': comentario,
      'fecha': fecha.toIso8601String(),
      // Derivado de 'fecha', solo para que firestore.rules pueda
      // comprobar sustituciones (ver Sustitucion) sin parsear fechas.
      'fechaDia': _formatoFechaDia.format(fecha),
      // Igual que fechaDia: derivado de 'fecha', no es un campo propio
      // del modelo Dart. Permite a las reglas saber a qué matrícula
      // corresponde esta nota (matriculas/{alumnoId}_{asignaturaId}_
      // {cursoEscolar}) sin consultar configuracion/centro.
      'cursoEscolar': cursoEscolarDeFecha(fecha),
      'estado': estado.name,
    };
  }
}
