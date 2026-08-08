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
    };
  }
}
