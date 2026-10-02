/// Una franja horaria de GRUPO de una asignatura (ver `Asignatura.franjasHorario`
/// y CLAUDE.md punto 69): una misma asignatura teórica puede impartirse
/// en varios grupos a días/horas distintos (p. ej. "Lenguaje musical"
/// los lunes y miércoles de 17:00 a 18:00 para un grupo, y los martes y
/// jueves de 18:00 a 19:00 para otro) — cada una es una `FranjaHoraria`
/// independiente dentro de la lista de la asignatura. `id` se genera en
/// cliente al crearla (marca de tiempo, único dentro de esa lista) y es
/// estable mientras no se borre: `Matricula.franjaHorarioId` lo
/// referencia para saber a qué franja pertenece cada alumno y poder
/// re-sincronizar solo esas matrículas si la franja cambia.
class FranjaHoraria {
  final String id;
  final List<int> diasSemana;
  final String horaInicio;
  final String horaFin;

  FranjaHoraria({
    required this.id,
    required this.diasSemana,
    required this.horaInicio,
    required this.horaFin,
  });

  factory FranjaHoraria.fromMap(Map<String, dynamic> data) {
    return FranjaHoraria(
      id: data['id'] ?? '',
      diasSemana: List<int>.from(data['diasSemana'] ?? const []),
      horaInicio: data['horaInicio'] ?? '',
      horaFin: data['horaFin'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'diasSemana': diasSemana,
      'horaInicio': horaInicio,
      'horaFin': horaFin,
    };
  }
}

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
  // Objetivo de horas de estudio POR ASIGNATURA (0 = sin objetivo) —
  // ÚNICA fuente de objetivo de horas de toda la app: vivió antes
  // también en `Curso` (histórico, retirado de ahí — cada asignatura
  // tiene su propia cantidad de horas, no tenía sentido un valor
  // compartido por todas las de un mismo curso). Configurado por
  // dirección desde `CriteriosEvaluacionScreen`, no cuenta para la
  // nota — ver CLAUDE.md.
  final double horasObjetivoSemanal;
  final double horasObjetivoMensual;
  // Días que tarda una nota nueva en hacerse visible para el alumno
  // tras ponerse (0 = visible al momento, como antes). Configurable
  // por el profesor desde CriteriosEvaluacionScreen, igual que los
  // objetivos de horas — pedido por dirección. Profesor/dirección
  // siempre ven la nota al momento; el retraso solo afecta al lado
  // alumno (_TabNotas/MisNotasScreen filtran en cliente comparando
  // Nota.fecha + este valor contra la hora actual — no es un campo de
  // seguridad, así que no hace falta reforzarlo en firestore.rules).
  final int diasRetrasoVisibilidadNotas;
  // Franjas horarias de GRUPO (pedido en el piloto: las asignaturas
  // teóricas suelen tener siempre el mismo horario para cada uno de
  // sus grupos, a diferencia de instrumento —individual, ver CLAUDE.md
  // punto 7— donde cada alumno tiene el suyo). Lista vacía = sin
  // franjas configuradas, que es el caso normal para instrumento:
  // entonces sigue rigiendo el horario POR MATRÍCULA de siempre, sin
  // cambios. Con una o más franjas, `_configurarMatricula`
  // (asignatura_detalle_screen.dart) deja de pedir días/hora por
  // alumno y en su lugar pide ELEGIR una franja — el alumno hereda sus
  // días/hora, copiados a su propia matrícula
  // (`Matricula.franjaHorarioId` + `DbService.asignarFranjaMatricula`)
  // para que el horario general siga leyendo siempre de `Matricula`
  // sin distinguir casos. Editar o borrar una franja re-sincroniza
  // solo las matrículas que la tenían asignada — ver CLAUDE.md punto
  // 69 (actualizado: antes una única franja por asignatura, ahora
  // varias).
  final List<FranjaHoraria> franjasHorario;

  Asignatura({
    this.id,
    required this.cursoId,
    required this.nombre,
    required this.profesorIds,
    required this.createdAt,
    required this.createdBy,
    this.iconoId = '',
    this.permiteGrabarEstudio = false,
    this.horasObjetivoSemanal = 0,
    this.horasObjetivoMensual = 0,
    this.diasRetrasoVisibilidadNotas = 0,
    this.franjasHorario = const [],
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
      horasObjetivoSemanal: (data['horasObjetivoSemanal'] as num?)?.toDouble() ?? 0,
      horasObjetivoMensual: (data['horasObjetivoMensual'] as num?)?.toDouble() ?? 0,
      diasRetrasoVisibilidadNotas: (data['diasRetrasoVisibilidadNotas'] as num?)?.toInt() ?? 0,
      franjasHorario: (data['franjasHorario'] as List<dynamic>? ?? const [])
          .map((f) => FranjaHoraria.fromMap(Map<String, dynamic>.from(f)))
          .toList(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'cursoId': cursoId,
      'nombre': nombre,
      // Denormalizado, no es un campo del modelo Dart (igual que
      // Nota.fechaDia/cursoEscolar): permite a firestore.rules agrupar
      // por nombre vía gruposAsignatura/{nombreNormalizado} para el
      // permiso cruzado entre cursos (ver CLAUDE.md).
      'nombreNormalizado': nombre.trim().toLowerCase(),
      'profesorIds': profesorIds,
      'createdAt': createdAt.toIso8601String(),
      'createdBy': createdBy,
      'iconoId': iconoId,
      'permiteGrabarEstudio': permiteGrabarEstudio,
      'horasObjetivoSemanal': horasObjetivoSemanal,
      'horasObjetivoMensual': horasObjetivoMensual,
      'diasRetrasoVisibilidadNotas': diasRetrasoVisibilidadNotas,
      'franjasHorario': franjasHorario.map((f) => f.toMap()).toList(),
    };
  }
}
