class Matricula {
  final String? id;
  final String alumnoId;
  final String asignaturaId;
  final String cursoId; // denormalizado, no autoritativo
  // Curso escolar (p.ej. "2026/2027") al que pertenece esta matrícula —
  // ver lib/utils/curso_escolar.dart. Forma parte del ID determinista
  // (idPara) para que un mismo alumno pueda tener una matrícula distinta
  // de la misma asignatura en cada curso escolar, en vez de que el
  // set(merge:true) del año siguiente reescriba la del año anterior.
  final String cursoEscolar;
  final DateTime fechaAlta;
  final bool activa;
  // Días de clase de ESTE alumno en ESTA asignatura (1=lunes..7=domingo,
  // DateTime.weekday). Va en la matrícula y no en la asignatura porque
  // las clases de instrumento son individuales: cada alumno tiene su
  // propio horario dentro de la misma asignatura (p.ej. Guitarra: un
  // alumno los lunes, otro los miércoles). Para asignaturas grupales
  // (teoría, conjunto...) simplemente se repiten los mismos días en
  // cada matrícula del grupo.
  final List<int> diasSemana;
  // Profesor responsable de ESTE alumno en ESTA asignatura ('' = sin
  // asignar). Una asignatura puede tener varios profesores (p.ej. dos
  // de guitarra), cada uno con sus propios alumnos: solo el profesor
  // aquí asignado (o quien tenga una sustitución activa ese día, ver
  // Sustitucion) puede poner notas o marcar asistencia de este alumno.
  final String profesorId;
  // Plus de orquesta aplicado a ESTA matrícula ('' = ninguno) —
  // referencia a plusesOrquesta/{id}. P.ej. matricular a un alumno en
  // "Orquesta de guitarras" con este campo apuntando al plus que suma
  // horas semanales a la asignatura "Guitarra" (PlusOrquesta.
  // asignaturaDestinoId), configurable al matricular. Ver CLAUDE.md.
  final String plusOrquestaId;
  // Franja horaria de ESTE alumno en ESTA asignatura ('HH:mm', '' = sin
  // definir) — la misma franja se aplica a todos los días de
  // `diasSemana` (una clase de instrumento dura lo mismo cada semana;
  // para grupales, todo el grupo comparte franja). Base del horario
  // general de dirección (ver CLAUDE.md): horario de alumno/profesor y
  // la propagación automática de cambios salen gratis de leer estos
  // mismos campos vía StreamBuilder, sin un sistema de horario aparte.
  final String horaInicio;
  final String horaFin;
  // Franja horaria de GRUPO elegida para este alumno ('' = ninguna,
  // caso normal para instrumento) — referencia a un elemento de
  // `Asignatura.franjasHorario`. `diasSemana`/`horaInicio`/`horaFin` de
  // arriba siguen siendo la fuente que lee el horario general (copiados
  // de la franja al elegirla, ver `DbService.asignarFranjaMatricula`);
  // este campo solo sirve para saber A CUÁL re-sincronizar si la franja
  // se edita o borra después. Ver CLAUDE.md punto 69.
  final String franjaHorarioId;

  Matricula({
    this.id,
    required this.alumnoId,
    required this.asignaturaId,
    required this.cursoId,
    required this.cursoEscolar,
    required this.fechaAlta,
    this.activa = true,
    this.diasSemana = const [],
    this.profesorId = '',
    this.plusOrquestaId = '',
    this.horaInicio = '',
    this.horaFin = '',
    this.franjaHorarioId = '',
  });

  /// ID determinista: matricular es idempotente (set con merge) y a la
  /// vez distingue cursos escolares distintos del mismo alumno en la
  /// misma asignatura.
  static String idPara({
    required String alumnoId,
    required String asignaturaId,
    required String cursoEscolar,
  }) =>
      '${alumnoId}_${asignaturaId}_$cursoEscolar';

  factory Matricula.fromMap(String id, Map<String, dynamic> data) {
    return Matricula(
      id: id,
      alumnoId: data['alumnoId'] ?? '',
      asignaturaId: data['asignaturaId'] ?? '',
      cursoId: data['cursoId'] ?? '',
      cursoEscolar: data['cursoEscolar'] ?? '',
      fechaAlta: DateTime.tryParse(data['fechaAlta'] ?? '') ?? DateTime.now(),
      activa: data['activa'] ?? true,
      diasSemana: List<int>.from(data['diasSemana'] ?? const []),
      profesorId: data['profesorId'] ?? '',
      plusOrquestaId: data['plusOrquestaId'] ?? '',
      horaInicio: data['horaInicio'] ?? '',
      horaFin: data['horaFin'] ?? '',
      franjaHorarioId: data['franjaHorarioId'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'alumnoId': alumnoId,
      'asignaturaId': asignaturaId,
      'cursoId': cursoId,
      'cursoEscolar': cursoEscolar,
      'fechaAlta': fechaAlta.toIso8601String(),
      'activa': activa,
      'diasSemana': diasSemana,
      'profesorId': profesorId,
      'plusOrquestaId': plusOrquestaId,
      'horaInicio': horaInicio,
      'horaFin': horaFin,
      'franjaHorarioId': franjaHorarioId,
    };
  }
}
