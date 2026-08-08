/// Turno recurrente semanal de un trabajador (profesor o dirección):
/// qué día de la semana trabaja y a qué hora entra/sale. Se usa tanto
/// para mostrar su horario como para programar el recordatorio local
/// de fichaje (ver RecordatorioFichajeService).
class TurnoLaboral {
  final int diaSemana; // 1=lunes..7=domingo (DateTime.weekday)
  final String horaEntrada; // 'HH:mm'
  final String horaSalida; // 'HH:mm'

  TurnoLaboral({
    required this.diaSemana,
    required this.horaEntrada,
    required this.horaSalida,
  });

  factory TurnoLaboral.fromMap(Map<String, dynamic> data) {
    return TurnoLaboral(
      diaSemana: (data['diaSemana'] as num?)?.toInt() ?? 1,
      horaEntrada: data['horaEntrada'] ?? '09:00',
      horaSalida: data['horaSalida'] ?? '17:00',
    );
  }

  Map<String, dynamic> toMap() => {
        'diaSemana': diaSemana,
        'horaEntrada': horaEntrada,
        'horaSalida': horaSalida,
      };
}

/// Horario laboral configurado por el propio trabajador (Art. 34.9 ET
/// no exige que el trabajador lo autoconfigure, pero así se pidió: el
/// trabajador indica qué días y a qué hora trabaja). Un doc por
/// empleado (id == uid).
class HorarioLaboral {
  final String empleadoId;
  final List<TurnoLaboral> turnos;
  final int minutosAvisoAntes;

  HorarioLaboral({
    required this.empleadoId,
    required this.turnos,
    this.minutosAvisoAntes = 10,
  });

  factory HorarioLaboral.fromMap(String id, Map<String, dynamic> data) {
    return HorarioLaboral(
      empleadoId: id,
      turnos: (data['turnos'] as List<dynamic>? ?? [])
          .map((t) => TurnoLaboral.fromMap(Map<String, dynamic>.from(t)))
          .toList(),
      minutosAvisoAntes: (data['minutosAvisoAntes'] as num?)?.toInt() ?? 10,
    );
  }

  Map<String, dynamic> toMap() => {
        'turnos': turnos.map((t) => t.toMap()).toList(),
        'minutosAvisoAntes': minutosAvisoAntes,
      };
}
