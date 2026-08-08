import 'package:intl/intl.dart';

final _formatoFecha = DateFormat('yyyy-MM-dd');

/// Registro de fichaje de un trabajador (profesor o dirección) para
/// UN día concreto: hora exacta de entrada y salida, tal como exige
/// el Art. 34.9 del Estatuto de los Trabajadores (RD-ley 8/2019).
/// Una vez fichada la entrada/salida no se edita en el cliente (ver
/// firestore.rules): solo dirección puede corregir un olvido, y en
/// ese caso queda registrado quién y cuándo (`corregidoPor`/
/// `corregidoEn`) — nunca se sobrescribe en silencio. Tampoco se
/// borra nunca: la ley obliga a conservar el registro 4 años.
///
/// `pendienteValidacion`: el propio trabajador puede autoinformar de
/// un día pasado sin ningún marcaje (olvido) con hora de entrada Y
/// salida ya puestas, quedando en este estado hasta que dirección lo
/// valide (`DbService.reportarOlvidoMarcaje`/`validarMarcaje`) — no es
/// una alternativa a la corrección de dirección, es un paso previo
/// para los días en los que el trabajador no fichó absolutamente nada.
class Marcaje {
  final String? id;
  final String empleadoId;
  final String fecha; // 'yyyy-MM-dd'
  final DateTime? horaEntrada;
  final DateTime? horaSalida;
  final String? corregidoPor;
  final DateTime? corregidoEn;
  final bool pendienteValidacion;

  Marcaje({
    this.id,
    required this.empleadoId,
    required this.fecha,
    this.horaEntrada,
    this.horaSalida,
    this.corregidoPor,
    this.corregidoEn,
    this.pendienteValidacion = false,
  });

  static String idPara({required String empleadoId, required String fecha}) =>
      '${empleadoId}_$fecha';

  static String formatearFecha(DateTime fecha) => _formatoFecha.format(fecha);

  factory Marcaje.fromMap(String id, Map<String, dynamic> data) {
    return Marcaje(
      id: id,
      empleadoId: data['empleadoId'] ?? '',
      fecha: data['fecha'] ?? '',
      horaEntrada: data['horaEntrada'] != null ? DateTime.tryParse(data['horaEntrada']) : null,
      horaSalida: data['horaSalida'] != null ? DateTime.tryParse(data['horaSalida']) : null,
      corregidoPor: data['corregidoPor'],
      corregidoEn: data['corregidoEn'] != null ? DateTime.tryParse(data['corregidoEn']) : null,
      pendienteValidacion: data['pendienteValidacion'] ?? false,
    );
  }

  Map<String, dynamic> toMap() => {
        'empleadoId': empleadoId,
        'fecha': fecha,
        'horaEntrada': horaEntrada?.toIso8601String(),
        'horaSalida': horaSalida?.toIso8601String(),
        if (corregidoPor != null) 'corregidoPor': corregidoPor,
        if (corregidoEn != null) 'corregidoEn': corregidoEn!.toIso8601String(),
        'pendienteValidacion': pendienteValidacion,
      };
}
