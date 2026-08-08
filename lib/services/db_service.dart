import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/sesion_estudio.dart';
import '../models/nota.dart';
import '../models/usuario.dart';
import '../models/curso.dart';
import '../models/asignatura.dart';
import '../models/matricula.dart';
import '../models/asistencia.dart';
import '../models/criterio_evaluacion.dart';
import '../models/sustitucion.dart';
import '../models/horario_laboral.dart';
import '../models/marcaje.dart';

/// Centraliza el acceso a Firestore. Los nombres de colección aquí
/// deben coincidir EXACTAMENTE con los usados en firestore.rules.
class DbService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // -------------------------------------------------------------
  // Configuración del centro / curso escolar (documento único
  // configuracion/centro). Ver CLAUDE.md, discriminación por curso
  // escolar: un único curso "activo" global que dirección avanza una
  // vez al año, con historial de cursos anteriores para poder
  // consultarlos (no editarlos) desde las pantallas afectadas.
  // -------------------------------------------------------------
  static const _cursoEscolarPorDefecto = '2025-2026';

  Stream<String> cursoEscolarActivo() {
    return _db.collection('configuracion').doc('centro').snapshots().map(
          (doc) => doc.data()?['cursoEscolarActivo'] as String? ?? _cursoEscolarPorDefecto,
        );
  }

  Stream<List<String>> historialCursosEscolares() {
    return _db.collection('configuracion').doc('centro').snapshots().map((doc) {
      final historial = List<String>.from(doc.data()?['historialCursosEscolares'] ?? const []);
      return historial.isEmpty ? [_cursoEscolarPorDefecto] : historial;
    });
  }

  /// Avanza el curso escolar activo del centro: lo añade al historial
  /// (si no estuviera ya) y lo marca como activo. Los cursos anteriores
  /// quedan intactos, solo consultables desde cada pantalla.
  Future<void> avanzarCursoEscolar(String nuevoCursoEscolar) async {
    final ref = _db.collection('configuracion').doc('centro');
    final actual = await ref.get();
    final historial = List<String>.from(actual.data()?['historialCursosEscolares'] ?? const []);
    if (!historial.contains(nuevoCursoEscolar)) historial.add(nuevoCursoEscolar);
    await ref.set({
      'cursoEscolarActivo': nuevoCursoEscolar,
      'historialCursosEscolares': historial,
    }, SetOptions(merge: true));
  }

  // -------------------------------------------------------------
  // Sesiones de estudio
  // -------------------------------------------------------------
  Future<void> guardarSesion(SesionEstudio sesion) async {
    // 'alumnoNombre' denormalizado (no es un campo del modelo Dart,
    // igual que Nota.fechaDia/cursoEscolar): el Cuadro de Honor
    // necesita mostrar el nombre de OTROS alumnos, y las reglas de
    // `usuarios` no permiten a un alumno leer el perfil de otro — con
    // el nombre ya copiado en la propia sesión, cuadroDeHonorMensual()
    // no necesita leer `usuarios` de nadie más (ver CLAUDE.md).
    final alumno = await obtenerUsuario(sesion.alumnoId);
    await _db.collection('sesionesEstudio').add({
      ...sesion.toMap(),
      'alumnoNombre': alumno?.nombre ?? '',
    });
    // La actualización de estadisticasAlumno la hace una Cloud Function
    // (ver /functions) al detectar la creación de este documento.
    // No se escribe estadisticasAlumno desde el cliente (ver rules).
  }

  Stream<List<SesionEstudio>> historialAlumno(String alumnoId) {
    return _db
        .collection('sesionesEstudio')
        .where('alumnoId', isEqualTo: alumnoId)
        .orderBy('fechaInicio', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => SesionEstudio.fromMap(d.id, d.data()))
            .toList());
  }

  // -------------------------------------------------------------
  // Estadísticas agregadas (solo lectura desde el cliente)
  // -------------------------------------------------------------
  Future<Map<String, dynamic>?> estadisticasAlumno(String alumnoId) async {
    final doc = await _db.collection('estadisticasAlumno').doc(alumnoId).get();
    return doc.data();
  }

  /// Informe de dirección: horas efectivas del MES ACTUAL por alumno
  /// (las horas objetivo son mensuales, ver CLAUDE.md), ordenadas de
  /// mayor a menor, junto con el objetivo mensual combinado del alumno
  /// (suma de `horasObjetivoMensual` de los CURSOS DISTINTOS entre sus
  /// asignaturas con matrícula activa — el objetivo es por curso, no
  /// por asignatura, así que no se cuenta dos veces si el alumno tiene
  /// varias asignaturas del mismo curso) para poder colorear en
  /// rojo/verde en la UI.
  ///
  /// FASE DE PRUEBAS: agrega `sesionesEstudio`/`matriculas`/`asignaturas`
  /// en el propio cliente en vez de leer `estadisticasAlumno`, porque
  /// esa colección solo la actualiza la Cloud Function de
  /// `functions/index.js` y esta requiere el plan Blaze — el centro aún
  /// no lo ha contratado. Cuando lo haga, desplegar la función y volver
  /// a leer `estadisticasAlumno` (ver README, sección "Cloud Function:
  /// estadisticasAlumno").
  Stream<List<Map<String, dynamic>>> informeDireccion({required String cursoEscolar}) {
    return _db.collection('sesionesEstudio').snapshots().asyncMap((snap) async {
      final ahora = DateTime.now();
      final inicioMes = DateTime(ahora.year, ahora.month, 1);

      final msEfectivoMesPorAlumno = <String, int>{};
      for (final doc in snap.docs) {
        final data = doc.data();
        final alumnoId = data['alumnoId'] as String? ?? '';
        final fechaInicio = DateTime.tryParse(data['fechaInicio'] ?? '');
        if (fechaInicio == null || fechaInicio.isBefore(inicioMes)) continue;
        final efectivoMs = (data['duracionEfectivaMs'] as num?)?.toInt() ?? 0;
        msEfectivoMesPorAlumno[alumnoId] = (msEfectivoMesPorAlumno[alumnoId] ?? 0) + efectivoMs;
      }

      final asignaturasSnap = await _db.collection('asignaturas').get();
      final cursoIdPorAsignatura = {
        for (final d in asignaturasSnap.docs) d.id: d.data()['cursoId'] as String? ?? ''
      };

      final cursosSnap = await _db.collection('cursos').get();
      final objetivoPorCurso = {
        for (final d in cursosSnap.docs)
          d.id: (d.data()['horasObjetivoMensual'] as num?)?.toDouble() ?? 0.0
      };

      final matriculasSnap = await _db
          .collection('matriculas')
          .where('cursoEscolar', isEqualTo: cursoEscolar)
          .where('activa', isEqualTo: true)
          .get();
      final cursosPorAlumno = <String, Set<String>>{};
      for (final d in matriculasSnap.docs) {
        final m = d.data();
        final alumnoId = m['alumnoId'] as String? ?? '';
        final asignaturaId = m['asignaturaId'] as String? ?? '';
        final cursoId = cursoIdPorAsignatura[asignaturaId] ?? '';
        if (cursoId.isEmpty) continue;
        (cursosPorAlumno[alumnoId] ??= {}).add(cursoId);
      }
      final objetivoPorAlumno = {
        for (final entry in cursosPorAlumno.entries)
          entry.key: entry.value
              .fold<double>(0, (acc, cursoId) => acc + (objetivoPorCurso[cursoId] ?? 0))
      };

      final alumnosIds = {...msEfectivoMesPorAlumno.keys, ...objetivoPorAlumno.keys};
      final filas = alumnosIds.map((alumnoId) {
        final horasMes = (msEfectivoMesPorAlumno[alumnoId] ?? 0) / 3600000;
        final objetivo = objetivoPorAlumno[alumnoId] ?? 0;
        return {
          'alumnoId': alumnoId,
          'horasEfectivasMes': horasMes,
          'objetivoMensual': objetivo,
          'cumpleObjetivo': objetivo <= 0 || horasMes >= objetivo,
        };
      }).toList()
        ..sort((a, b) =>
            (b['horasEfectivasMes'] as double).compareTo(a['horasEfectivasMes'] as double));

      return filas;
    });
  }

  /// Resuelve, para un curso escolar dado, a qué Curso(s) está
  /// matriculado cada alumno (vía matriculas activas → asignatura →
  /// curso). Compartido por Cuadro de honor, Alumnos e Informe de
  /// horas, que agrupan por curso con la misma resolución. Un alumno
  /// con asignaturas de varios cursos aparece en varias entradas de la
  /// lista — quien agrupe debe iterar todos los cursos de cada alumno,
  /// no asumir uno solo.
  Future<Map<String, List<Curso>>> cursosPorAlumno(
      {required String cursoEscolar}) async {
    final asignaturasSnap = await _db.collection('asignaturas').get();
    final cursoIdPorAsignatura = {
      for (final d in asignaturasSnap.docs) d.id: d.data()['cursoId'] as String? ?? ''
    };

    final cursosSnap = await _db.collection('cursos').get();
    final cursoPorId = {
      for (final d in cursosSnap.docs) d.id: Curso.fromMap(d.id, d.data())
    };

    final matriculasSnap = await _db
        .collection('matriculas')
        .where('cursoEscolar', isEqualTo: cursoEscolar)
        .where('activa', isEqualTo: true)
        .get();

    final cursoIdsPorAlumno = <String, Set<String>>{};
    for (final d in matriculasSnap.docs) {
      final m = d.data();
      final alumnoId = m['alumnoId'] as String? ?? '';
      final asignaturaId = m['asignaturaId'] as String? ?? '';
      final cursoId = cursoIdPorAsignatura[asignaturaId] ?? '';
      if (cursoId.isEmpty) continue;
      (cursoIdsPorAlumno[alumnoId] ??= {}).add(cursoId);
    }

    return {
      for (final entry in cursoIdsPorAlumno.entries)
        entry.key:
            entry.value.map((id) => cursoPorId[id]).whereType<Curso>().toList()
              ..sort((a, b) => a.nivel.index != b.nivel.index
                  ? a.nivel.index.compareTo(b.nivel.index)
                  : (a.numeroCurso ?? 0).compareTo(b.numeroCurso ?? 0))
    };
  }

  /// Cuadro de honor: ranking GLOBAL (no por asignatura) de horas
  /// efectivas de estudio de INSTRUMENTO (no teórico) del mes en curso,
  /// con nombre de alumno — a diferencia del ranking por asignatura,
  /// visible también para alumnos (ver CLAUDE.md, excepción deliberada
  /// al punto 14 de privacidad). Mismo patrón de agregación en cliente
  /// que `informeDireccion()`, temporal hasta desplegar Cloud Functions.
  ///
  /// El filtro `tipo == 'instrumento'` va en la propia consulta (no
  /// solo como `continue` en el bucle): la regla de lectura de
  /// `sesionesEstudio` para alumno solo permite ver sesiones propias o
  /// de tipo 'instrumento' — una consulta sin ese `where` no es
  /// "provably compliant" y Firestore la rechaza entera con
  /// permission-denied para el rol alumno (mismo patrón que CLAUDE.md
  /// punto 25). El nombre sale de `alumnoNombre`, denormalizado en la
  /// propia sesión al grabarla (`guardarSesion`) — un alumno no puede
  /// leer el documento `usuarios` de otro alumno, así que no se puede
  /// resolver el nombre con un `obtenerUsuario()` por cada fila aquí.
  Stream<List<({String alumnoId, String alumnoNombre, String? instrumento, double horasEfectivasMes})>>
      cuadroDeHonorMensual() {
    return _db
        .collection('sesionesEstudio')
        .where('tipo', isEqualTo: 'instrumento')
        .snapshots()
        .map((snap) {
      final ahora = DateTime.now();
      final inicioMes = DateTime(ahora.year, ahora.month, 1);

      final msPorAlumno = <String, int>{};
      final nombrePorAlumno = <String, String>{};
      final instrumentoPorAlumno = <String, String?>{};
      for (final doc in snap.docs) {
        final data = doc.data();
        final fechaInicio = DateTime.tryParse(data['fechaInicio'] ?? '');
        if (fechaInicio == null || fechaInicio.isBefore(inicioMes)) continue;
        final alumnoId = data['alumnoId'] as String? ?? '';
        final efectivoMs = (data['duracionEfectivaMs'] as num?)?.toInt() ?? 0;
        msPorAlumno[alumnoId] = (msPorAlumno[alumnoId] ?? 0) + efectivoMs;
        nombrePorAlumno[alumnoId] = data['alumnoNombre'] as String? ?? '';
        instrumentoPorAlumno[alumnoId] = data['instrumento'] as String?;
      }

      final filas = msPorAlumno.entries
          .map((entrada) => (
                alumnoId: entrada.key,
                alumnoNombre: nombrePorAlumno[entrada.key] ?? '',
                instrumento: instrumentoPorAlumno[entrada.key],
                horasEfectivasMes: entrada.value / 3600000,
              ))
          .toList()
        ..sort((a, b) => b.horasEfectivasMes.compareTo(a.horasEfectivasMes));
      return filas;
    });
  }

  // -------------------------------------------------------------
  // Notas
  // -------------------------------------------------------------
  Future<void> crearNota(Nota nota) async {
    await _db.collection('notas').add(nota.toMap());
  }

  Stream<List<Nota>> notasDeAlumno(String alumnoId) {
    return _db
        .collection('notas')
        .where('alumnoId', isEqualTo: alumnoId)
        .orderBy('fecha', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) => Nota.fromMap(d.id, d.data())).toList());
  }

  /// Notas pendientes de supervisión por dirección.
  Stream<List<Nota>> notasPendientesSupervision() {
    return _db
        .collection('notas')
        .where('estado', isEqualTo: 'pendiente')
        .orderBy('fecha', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) => Nota.fromMap(d.id, d.data())).toList());
  }

  Future<void> actualizarEstadoNota(String notaId, EstadoNota nuevoEstado) async {
    await _db.collection('notas').doc(notaId).update({'estado': nuevoEstado.name});
  }

  /// Igual que `actualizarEstadoNota` pero para varias notas a la vez
  /// (p. ej. todas las de un examen), en un único `WriteBatch` en vez
  /// de un `await` por nota — más rápido y evita dejar la lista a
  /// medio actualizar si una escritura individual fallara a mitad.
  Future<void> actualizarEstadoNotas(List<String> notaIds, EstadoNota nuevoEstado) async {
    final batch = _db.batch();
    for (final id in notaIds) {
      batch.update(_db.collection('notas').doc(id), {'estado': nuevoEstado.name});
    }
    await batch.commit();
  }

  // -------------------------------------------------------------
  // Criterios de evaluación (pesos configurables por dirección)
  // -------------------------------------------------------------
  Future<String> crearCriterio(CriterioEvaluacion criterio) async {
    final ref = await _db.collection('criteriosEvaluacion').add(criterio.toMap());
    return ref.id;
  }

  Future<void> actualizarCriterio(String criterioId, Map<String, dynamic> cambios) {
    return _db.collection('criteriosEvaluacion').doc(criterioId).update(cambios);
  }

  Future<void> eliminarCriterio(String criterioId) {
    return _db.collection('criteriosEvaluacion').doc(criterioId).delete();
  }

  Future<CriterioEvaluacion?> criterio(String criterioId) async {
    final doc = await _db.collection('criteriosEvaluacion').doc(criterioId).get();
    if (!doc.exists) return null;
    return CriterioEvaluacion.fromMap(doc.id, doc.data()!);
  }

  Stream<List<CriterioEvaluacion>> criteriosDeAsignatura(String asignaturaId) {
    return _db
        .collection('criteriosEvaluacion')
        .where('asignaturaId', isEqualTo: asignaturaId)
        .snapshots()
        .map((snap) => snap.docs.map((d) => CriterioEvaluacion.fromMap(d.id, d.data())).toList());
  }

  // -------------------------------------------------------------
  // Usuarios / listados
  // -------------------------------------------------------------
  // Piloto de un solo centro: sin filtro por centroId (ver CLAUDE.md,
  // backlog de multi-centro). Un solo filtro arrayContains, sin
  // necesidad de índice compuesto.
  Stream<List<Usuario>> alumnosDelCentro() {
    return _db
        .collection('usuarios')
        .where('permisos', arrayContains: 'alumno')
        .snapshots()
        .map((snap) => snap.docs.map((d) => Usuario.fromMap(d.id, d.data())).toList());
  }

  Stream<List<Usuario>> profesoresDelCentro() {
    return _db
        .collection('usuarios')
        .where('permisos', arrayContains: 'profesor')
        .snapshots()
        .map((snap) => snap.docs.map((d) => Usuario.fromMap(d.id, d.data())).toList());
  }

  Future<Usuario?> obtenerUsuario(String uid) async {
    final doc = await _db.collection('usuarios').doc(uid).get();
    if (!doc.exists) return null;
    return Usuario.fromMap(doc.id, doc.data()!);
  }

  /// Registra la visita actual (campo `ultimaVisita`) y devuelve la
  /// anterior (o null si es la primera vez), para poder calcular
  /// avisos in-app tipo "notas nuevas desde tu última visita" sin
  /// depender de una notificación push real (ver InicioScreen).
  Future<DateTime?> registrarVisitaYObtenerAnterior(String uid) async {
    final ref = _db.collection('usuarios').doc(uid);
    final doc = await ref.get();
    final anteriorTexto = doc.data()?['ultimaVisita'] as String?;
    final anterior = anteriorTexto != null ? DateTime.tryParse(anteriorTexto) : null;
    await ref.set({'ultimaVisita': DateTime.now().toIso8601String()}, SetOptions(merge: true));
    return anterior;
  }

  // -------------------------------------------------------------
  // Cursos
  // -------------------------------------------------------------
  Future<String> crearCurso(Curso curso) async {
    final ref = await _db.collection('cursos').add(curso.toMap());
    return ref.id;
  }

  Future<Curso?> curso(String cursoId) async {
    final doc = await _db.collection('cursos').doc(cursoId).get();
    if (!doc.exists) return null;
    return Curso.fromMap(doc.id, doc.data()!);
  }

  Future<void> actualizarCurso(String cursoId, Map<String, dynamic> cambios) {
    return _db.collection('cursos').doc(cursoId).update(cambios);
  }

  /// Solo se puede eliminar un curso sin asignaturas, para no dejar
  /// asignaturas huérfanas apuntando a un cursoId inexistente.
  Future<void> eliminarCurso(String cursoId) async {
    final asignaturas = await asignaturasDeCurso(cursoId).first;
    if (asignaturas.isNotEmpty) {
      throw Exception('No se puede eliminar un curso que todavía tiene asignaturas.');
    }
    await _db.collection('cursos').doc(cursoId).delete();
  }

  // Ordenados por nivel (sensibilización → elemental → avanzado →
  // libre) y luego número de curso, no por orden de inserción — si no,
  // la cuadrícula de CursosScreen queda desordenada según en qué orden
  // dirección los haya ido creando.
  Stream<List<Curso>> cursos() {
    return _db.collection('cursos').snapshots().map((snap) => snap.docs
        .map((d) => Curso.fromMap(d.id, d.data()))
        .toList()
      ..sort((a, b) => a.nivel.index != b.nivel.index
          ? a.nivel.index.compareTo(b.nivel.index)
          : (a.numeroCurso ?? 0) != (b.numeroCurso ?? 0)
              ? (a.numeroCurso ?? 0).compareTo(b.numeroCurso ?? 0)
              : a.nombre.compareTo(b.nombre)));
  }

  // -------------------------------------------------------------
  // Asignaturas
  // -------------------------------------------------------------
  Future<String> crearAsignatura(Asignatura asignatura) async {
    final ref = await _db.collection('asignaturas').add(asignatura.toMap());
    return ref.id;
  }

  Future<void> actualizarAsignatura(String asignaturaId, Map<String, dynamic> cambios) {
    return _db.collection('asignaturas').doc(asignaturaId).update(cambios);
  }

  /// Solo se puede eliminar una asignatura sin alumnos matriculados
  /// (activos) EN NINGÚN curso escolar, para no perder el historial de
  /// sesiones/notas/asistencias que siguen referenciando esa
  /// asignaturaId. A diferencia de matriculasDeAsignatura(), esta
  /// comprobación mira todos los cursos escolares a la vez.
  Future<void> eliminarAsignatura(String asignaturaId) async {
    final snap = await _db
        .collection('matriculas')
        .where('asignaturaId', isEqualTo: asignaturaId)
        .where('activa', isEqualTo: true)
        .get();
    if (snap.docs.isNotEmpty) {
      throw Exception('No se puede eliminar una asignatura con alumnos matriculados.');
    }
    await _db.collection('asignaturas').doc(asignaturaId).delete();
  }

  Future<Asignatura?> asignatura(String asignaturaId) async {
    final doc = await _db.collection('asignaturas').doc(asignaturaId).get();
    if (!doc.exists) return null;
    return Asignatura.fromMap(doc.id, doc.data()!);
  }

  // Ordenadas por nombre — a diferencia de Curso, una asignatura no
  // tiene nivel/número propio (todas las de este stream comparten el
  // mismo curso), así que el orden alfabético es el criterio sensato.
  Stream<List<Asignatura>> asignaturasDeCurso(String cursoId) {
    return _db
        .collection('asignaturas')
        .where('cursoId', isEqualTo: cursoId)
        .snapshots()
        .map((snap) => snap.docs.map((d) => Asignatura.fromMap(d.id, d.data())).toList()
          ..sort((a, b) => a.nombre.compareTo(b.nombre)));
  }

  Stream<List<Asignatura>> asignaturasDeProfesor(String profesorUid) {
    return _db
        .collection('asignaturas')
        .where('profesorIds', arrayContains: profesorUid)
        .snapshots()
        .map((snap) => snap.docs.map((d) => Asignatura.fromMap(d.id, d.data())).toList());
  }

  Stream<List<Asignatura>> todasLasAsignaturas() {
    return _db
        .collection('asignaturas')
        .snapshots()
        .map((snap) => snap.docs.map((d) => Asignatura.fromMap(d.id, d.data())).toList());
  }

  /// Añade o quita a un profesor de `profesorIds` de una asignatura
  /// (una asignatura puede tener varios profesores).
  Future<void> asignarProfesorAAsignatura({
    required String asignaturaId,
    required String profesorId,
    required bool asignar,
  }) {
    return _db.collection('asignaturas').doc(asignaturaId).update({
      'profesorIds': asignar
          ? FieldValue.arrayUnion([profesorId])
          : FieldValue.arrayRemove([profesorId]),
    });
  }

  // -------------------------------------------------------------
  // Matrículas
  // -------------------------------------------------------------
  Future<void> matricular({
    required String alumnoId,
    required String asignaturaId,
    required String cursoId,
    required String cursoEscolar,
    List<int> diasSemana = const [],
    String profesorId = '',
  }) {
    final id = Matricula.idPara(alumnoId: alumnoId, asignaturaId: asignaturaId, cursoEscolar: cursoEscolar);
    final matricula = Matricula(
      alumnoId: alumnoId,
      asignaturaId: asignaturaId,
      cursoId: cursoId,
      cursoEscolar: cursoEscolar,
      fechaAlta: DateTime.now(),
      diasSemana: diasSemana,
      profesorId: profesorId,
    );
    return _db.collection('matriculas').doc(id).set(matricula.toMap(), SetOptions(merge: true));
  }

  Future<void> actualizarDiasClaseMatricula({
    required String alumnoId,
    required String asignaturaId,
    required String cursoEscolar,
    required List<int> diasSemana,
  }) {
    final id = Matricula.idPara(alumnoId: alumnoId, asignaturaId: asignaturaId, cursoEscolar: cursoEscolar);
    return _db.collection('matriculas').doc(id).update({'diasSemana': diasSemana});
  }

  /// Profesor responsable de este alumno en esta asignatura (una
  /// asignatura puede tener varios profesores con alumnos distintos).
  Future<void> actualizarProfesorMatricula({
    required String alumnoId,
    required String asignaturaId,
    required String cursoEscolar,
    required String profesorId,
  }) {
    final id = Matricula.idPara(alumnoId: alumnoId, asignaturaId: asignaturaId, cursoEscolar: cursoEscolar);
    return _db.collection('matriculas').doc(id).update({'profesorId': profesorId});
  }

  Future<void> desmatricular({
    required String alumnoId,
    required String asignaturaId,
    required String cursoEscolar,
  }) {
    final id = Matricula.idPara(alumnoId: alumnoId, asignaturaId: asignaturaId, cursoEscolar: cursoEscolar);
    return _db.collection('matriculas').doc(id).update({'activa': false});
  }

  Future<Matricula?> matricula({
    required String alumnoId,
    required String asignaturaId,
    required String cursoEscolar,
  }) async {
    final id = Matricula.idPara(alumnoId: alumnoId, asignaturaId: asignaturaId, cursoEscolar: cursoEscolar);
    final doc = await _db.collection('matriculas').doc(id).get();
    if (!doc.exists) return null;
    return Matricula.fromMap(doc.id, doc.data()!);
  }

  Stream<List<Matricula>> matriculasDeAlumno(String alumnoId, {required String cursoEscolar}) {
    return _db
        .collection('matriculas')
        .where('alumnoId', isEqualTo: alumnoId)
        .where('cursoEscolar', isEqualTo: cursoEscolar)
        .where('activa', isEqualTo: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) => Matricula.fromMap(d.id, d.data())).toList());
  }

  /// Todas las matrículas activas del centro en un curso escolar dado
  /// (uso de dirección, p.ej. para detectar asistencia sin marcar).
  /// Puras igualdades, sin índice compuesto.
  Stream<List<Matricula>> todasLasMatriculasActivas({required String cursoEscolar}) {
    return _db
        .collection('matriculas')
        .where('cursoEscolar', isEqualTo: cursoEscolar)
        .where('activa', isEqualTo: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) => Matricula.fromMap(d.id, d.data())).toList());
  }

  Stream<List<Matricula>> matriculasDeAsignatura(String asignaturaId, {required String cursoEscolar}) {
    return _db
        .collection('matriculas')
        .where('asignaturaId', isEqualTo: asignaturaId)
        .where('cursoEscolar', isEqualTo: cursoEscolar)
        .where('activa', isEqualTo: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) => Matricula.fromMap(d.id, d.data())).toList());
  }

  // -------------------------------------------------------------
  // Asistencias
  // -------------------------------------------------------------
  Future<void> marcarAsistencia({
    required String alumnoId,
    required String asignaturaId,
    required DateTime fecha,
    required bool asistio,
    bool retraso = false,
    required String marcadaPor,
  }) {
    final id = Asistencia.idPara(alumnoId: alumnoId, asignaturaId: asignaturaId, fecha: fecha);
    final asistencia = Asistencia(
      alumnoId: alumnoId,
      asignaturaId: asignaturaId,
      fecha: Asistencia.formatearFecha(fecha),
      asistio: asistio,
      retraso: retraso,
      marcadaPor: marcadaPor,
      marcadaEn: DateTime.now(),
    );
    return _db.collection('asistencias').doc(id).set(asistencia.toMap(), SetOptions(merge: true));
  }

  Future<Asistencia?> asistenciaDelDia({
    required String alumnoId,
    required String asignaturaId,
    required DateTime fecha,
  }) async {
    final id = Asistencia.idPara(alumnoId: alumnoId, asignaturaId: asignaturaId, fecha: fecha);
    final doc = await _db.collection('asistencias').doc(id).get();
    if (!doc.exists) return null;
    return Asistencia.fromMap(doc.id, doc.data()!);
  }

  /// Igual que `asistenciaDelDia` pero en vivo: usado por los botones
  /// rápidos de la lista de la asignatura (`_FilaMatricula`) para que
  /// se actualicen solos si la asistencia se marca desde otra pantalla
  /// (p. ej. el calendario del detalle del alumno) mientras la fila
  /// sigue montada debajo en la pila de navegación — un fetch de un
  /// solo uso se quedaba con el valor de cuando se montó la fila.
  Stream<Asistencia?> asistenciaDelDiaStream({
    required String alumnoId,
    required String asignaturaId,
    required DateTime fecha,
  }) {
    final id = Asistencia.idPara(alumnoId: alumnoId, asignaturaId: asignaturaId, fecha: fecha);
    return _db
        .collection('asistencias')
        .doc(id)
        .snapshots()
        .map((doc) => doc.exists ? Asistencia.fromMap(doc.id, doc.data()!) : null);
  }

  /// Lista todas las asistencias de un alumno en una asignatura.
  ///
  /// Dos igualdades sin orderBy adicional: no hace falta índice
  /// compuesto (Firestore resuelve varias igualdades con sus índices
  /// automáticos de un solo campo). Antes se usaba un rango de
  /// prefijo sobre el ID del documento para evitar ESE índice, pero
  /// eso rompía la lectura para profesor: su regla de acceso depende
  /// de `resource.data.asignaturaId`, y Firestore no puede demostrar
  /// en tiempo de planificación de la consulta que un rango de ID
  /// implica una condición sobre un campo — rechazaba la consulta
  /// entera con `permission-denied` (dirección no se veía afectada
  /// porque su regla no depende de datos del documento). Con una
  /// igualdad explícita `asignaturaId == asignaturaId` en la propia
  /// consulta, Firestore sí puede verificarlo.
  Future<List<Asistencia>> asistenciasDeAlumnoEnAsignatura({
    required String alumnoId,
    required String asignaturaId,
  }) async {
    final snap = await _db
        .collection('asistencias')
        .where('alumnoId', isEqualTo: alumnoId)
        .where('asignaturaId', isEqualTo: asignaturaId)
        .get();
    return snap.docs.map((d) => Asistencia.fromMap(d.id, d.data())).toList();
  }

  // -------------------------------------------------------------
  // Sustituciones (acceso temporal de un profesor a toda una
  // asignatura para un día concreto, p.ej. baja del profesor habitual)
  // -------------------------------------------------------------
  Future<void> crearSustitucion({
    required String asignaturaId,
    required String profesorId,
    required DateTime fecha,
    required String creadaPor,
  }) {
    final id = Sustitucion.idPara(asignaturaId: asignaturaId, profesorId: profesorId, fecha: fecha);
    final sustitucion = Sustitucion(
      asignaturaId: asignaturaId,
      profesorId: profesorId,
      fecha: Sustitucion.formatearFecha(fecha),
      creadaPor: creadaPor,
      creadaEn: DateTime.now(),
    );
    return _db.collection('sustituciones').doc(id).set(sustitucion.toMap(), SetOptions(merge: true));
  }

  Future<void> eliminarSustitucion({
    required String asignaturaId,
    required String profesorId,
    required DateTime fecha,
  }) {
    final id = Sustitucion.idPara(asignaturaId: asignaturaId, profesorId: profesorId, fecha: fecha);
    return _db.collection('sustituciones').doc(id).delete();
  }

  Stream<List<Sustitucion>> sustitucionesDeAsignatura(String asignaturaId) {
    return _db
        .collection('sustituciones')
        .where('asignaturaId', isEqualTo: asignaturaId)
        .snapshots()
        .map((snap) => snap.docs.map((d) => Sustitucion.fromMap(d.id, d.data())).toList());
  }

  Future<bool> tieneSustitucionEnFecha({
    required String asignaturaId,
    required String profesorId,
    required DateTime fecha,
  }) async {
    final id = Sustitucion.idPara(asignaturaId: asignaturaId, profesorId: profesorId, fecha: fecha);
    final doc = await _db.collection('sustituciones').doc(id).get();
    return doc.exists;
  }

  // -------------------------------------------------------------
  // Sesiones filtradas por asignatura (para calendario/estadísticas)
  // -------------------------------------------------------------
  Future<List<SesionEstudio>> sesionesDelDia({
    required String alumnoId,
    required String asignaturaId,
    required DateTime dia,
  }) async {
    final inicioDia = DateTime(dia.year, dia.month, dia.day);
    final finDia = inicioDia.add(const Duration(days: 1));
    final snap = await _db
        .collection('sesionesEstudio')
        .where('alumnoId', isEqualTo: alumnoId)
        .where('asignaturaId', isEqualTo: asignaturaId)
        .where('fechaInicio', isGreaterThanOrEqualTo: inicioDia.toIso8601String())
        .where('fechaInicio', isLessThan: finDia.toIso8601String())
        .get();
    return snap.docs.map((d) => SesionEstudio.fromMap(d.id, d.data())).toList();
  }

  Stream<List<SesionEstudio>> sesionesDeAlumnoEnAsignatura({
    required String alumnoId,
    required String asignaturaId,
  }) {
    return _db
        .collection('sesionesEstudio')
        .where('alumnoId', isEqualTo: alumnoId)
        .where('asignaturaId', isEqualTo: asignaturaId)
        .orderBy('fechaInicio')
        .snapshots()
        .map((snap) => snap.docs.map((d) => SesionEstudio.fromMap(d.id, d.data())).toList());
  }

  // -------------------------------------------------------------
  // Registro horario (Art. 34.9 ET / RD-ley 8/2019): horario laboral
  // configurable por el propio trabajador y fichajes de entrada/salida.
  // -------------------------------------------------------------
  Stream<List<Usuario>> trabajadoresDelCentro() {
    return _db
        .collection('usuarios')
        .where('permisos', arrayContainsAny: ['profesor', 'direccion'])
        .snapshots()
        .map((snap) => snap.docs.map((d) => Usuario.fromMap(d.id, d.data())).toList());
  }

  Future<void> guardarHorarioLaboral(HorarioLaboral horario) {
    return _db.collection('horariosLaborales').doc(horario.empleadoId).set(horario.toMap());
  }

  Future<HorarioLaboral?> obtenerHorarioLaboral(String empleadoId) async {
    final doc = await _db.collection('horariosLaborales').doc(empleadoId).get();
    if (!doc.exists) return null;
    return HorarioLaboral.fromMap(doc.id, doc.data()!);
  }

  Future<void> ficharEntrada(String empleadoId) {
    final fecha = Marcaje.formatearFecha(DateTime.now());
    final id = Marcaje.idPara(empleadoId: empleadoId, fecha: fecha);
    final marcaje = Marcaje(empleadoId: empleadoId, fecha: fecha, horaEntrada: DateTime.now());
    return _db.collection('marcajes').doc(id).set(marcaje.toMap());
  }

  Future<void> ficharSalida(String empleadoId) {
    final fecha = Marcaje.formatearFecha(DateTime.now());
    final id = Marcaje.idPara(empleadoId: empleadoId, fecha: fecha);
    return _db.collection('marcajes').doc(id).update({'horaSalida': DateTime.now().toIso8601String()});
  }

  /// Corrección por dirección (p.ej. un trabajador olvidó fichar).
  /// Nunca sobrescribe en silencio: siempre queda quién y cuándo.
  Future<void> corregirMarcaje({
    required String empleadoId,
    required String fecha,
    DateTime? horaEntrada,
    DateTime? horaSalida,
    required String corregidoPor,
  }) {
    final id = Marcaje.idPara(empleadoId: empleadoId, fecha: fecha);
    return _db.collection('marcajes').doc(id).set({
      'empleadoId': empleadoId,
      'fecha': fecha,
      if (horaEntrada != null) 'horaEntrada': horaEntrada.toIso8601String(),
      if (horaSalida != null) 'horaSalida': horaSalida.toIso8601String(),
      'corregidoPor': corregidoPor,
      'corregidoEn': DateTime.now().toIso8601String(),
    }, SetOptions(merge: true));
  }

  /// Autoinforme del propio trabajador de un día PASADO sin ningún
  /// marcaje todavía (olvido de fichaje) — queda `pendienteValidacion`
  /// hasta que dirección lo revise (`validarMarcaje`). Si ya existe un
  /// marcaje ese día, aunque sea parcial, falla: un marcaje ya fichado
  /// es inmutable para el propio trabajador (ver CLAUDE.md punto 15),
  /// así que debe pedir a dirección que lo corrija directamente en vez
  /// de autoinformar un "olvido" sobre un día que sí tiene registro.
  Future<void> reportarOlvidoMarcaje({
    required String empleadoId,
    required String fecha,
    required DateTime horaEntrada,
    required DateTime horaSalida,
  }) async {
    final id = Marcaje.idPara(empleadoId: empleadoId, fecha: fecha);
    final ref = _db.collection('marcajes').doc(id);
    final existente = await ref.get();
    if (existente.exists) {
      throw Exception('Ya hay un fichaje registrado ese día. Pide a dirección que lo corrija.');
    }
    await ref.set({
      'empleadoId': empleadoId,
      'fecha': fecha,
      'horaEntrada': horaEntrada.toIso8601String(),
      'horaSalida': horaSalida.toIso8601String(),
      'pendienteValidacion': true,
    });
  }

  /// Dirección valida (opcionalmente tras ajustar horas) un autoinforme
  /// de olvido de fichaje — reutiliza `corregirMarcaje` para que quede
  /// igualmente registrado quién y cuándo, y además apaga
  /// `pendienteValidacion`.
  Future<void> validarMarcaje({
    required String empleadoId,
    required String fecha,
    required DateTime horaEntrada,
    required DateTime horaSalida,
    required String validadoPor,
  }) async {
    final id = Marcaje.idPara(empleadoId: empleadoId, fecha: fecha);
    await _db.collection('marcajes').doc(id).set({
      'empleadoId': empleadoId,
      'fecha': fecha,
      'horaEntrada': horaEntrada.toIso8601String(),
      'horaSalida': horaSalida.toIso8601String(),
      'corregidoPor': validadoPor,
      'corregidoEn': DateTime.now().toIso8601String(),
      'pendienteValidacion': false,
    }, SetOptions(merge: true));
  }

  Future<Marcaje?> marcajeDeHoy(String empleadoId) async {
    final fecha = Marcaje.formatearFecha(DateTime.now());
    final id = Marcaje.idPara(empleadoId: empleadoId, fecha: fecha);
    final doc = await _db.collection('marcajes').doc(id).get();
    if (!doc.exists) return null;
    return Marcaje.fromMap(doc.id, doc.data()!);
  }

  /// Historial propio del trabajador (necesita índice compuesto
  /// empleadoId+fecha, ver firestore.indexes.json).
  Stream<List<Marcaje>> marcajesDeEmpleado(String empleadoId) {
    return _db
        .collection('marcajes')
        .where('empleadoId', isEqualTo: empleadoId)
        .orderBy('fecha', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) => Marcaje.fromMap(d.id, d.data())).toList());
  }

  /// Vista de dirección: todos los marcajes en un rango de fechas
  /// (para mostrar a un inspector o exportar a Excel). Rango sobre un
  /// único campo ('fecha'), sin índice compuesto adicional.
  Stream<List<Marcaje>> marcajesEnRango({required DateTime desde, required DateTime hasta}) {
    final desdeTexto = Marcaje.formatearFecha(desde);
    final hastaTexto = Marcaje.formatearFecha(hasta);
    return _db
        .collection('marcajes')
        .where('fecha', isGreaterThanOrEqualTo: desdeTexto)
        .where('fecha', isLessThanOrEqualTo: hastaTexto)
        .orderBy('fecha')
        .snapshots()
        .map((snap) => snap.docs.map((d) => Marcaje.fromMap(d.id, d.data())).toList());
  }
}
