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
import '../models/incidencia.dart';
import '../models/plus_orquesta.dart';
import '../models/contacto_alumno.dart';
import '../utils/curso_escolar.dart';

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
  /// quedan intactos, solo consultables desde cada pantalla. También
  /// sirve para VOLVER a un año anterior (no comprueba que el nuevo
  /// sea cronológicamente posterior, solo el formato en la UI) — ver
  /// CLAUDE.md.
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

  /// Comprueba si un curso escolar tiene alguna matrícula real (activa
  /// o no) antes de dejar eliminarlo del historial, para poder avisar
  /// a dirección de que hay datos detrás. Igualdad simple, sin índice
  /// compuesto.
  Future<bool> tieneDatosCursoEscolar(String cursoEscolar) async {
    final snap = await _db
        .collection('matriculas')
        .where('cursoEscolar', isEqualTo: cursoEscolar)
        .limit(1)
        .get();
    return snap.docs.isNotEmpty;
  }

  /// Quita un año SOLO del historial (deja de aparecer como opción de
  /// curso escolar) — nunca borra matrículas/asistencias/notas reales
  /// de ese año, que siguen existiendo en Firestore (ver CLAUDE.md).
  /// El llamador debe comprobar antes que no es el curso activo.
  Future<void> eliminarCursoEscolarDelHistorial(String cursoEscolar) {
    return _db.collection('configuracion').doc('centro').update({
      'historialCursosEscolares': FieldValue.arrayRemove([cursoEscolar]),
    });
  }

  // -------------------------------------------------------------
  // Sesiones de estudio
  // -------------------------------------------------------------
  Future<void> guardarSesion(SesionEstudio sesion) async {
    // 'alumnoNombre' denormalizado (no es un campo del modelo Dart,
    // igual que Nota.fechaDia/cursoEscolar): el Cuadro de Honor
    // necesita mostrar el nombre de OTROS alumnos, y las reglas de
    // `usuarios` no permiten a un alumno leer el perfil de otro — con
    // el nombre ya copiado en la propia sesión, horasPorAsignaturaMensual()
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

  /// Registra horas de estudio TEÓRICO reportadas por el propio
  /// profesor para una semana completa (p. ej. "3 horas" de un
  /// cuaderno en papel de una asignatura no instrumental — ver
  /// CLAUDE.md). Sin grabación de audio ni distinción efectivo/total
  /// real (no aplica la lógica de 3 estados del punto 2):
  /// duracionTotalMs == duracionEfectivaMs a propósito, es un total
  /// autoinformado, no una medición. fechaInicio = lunes de esa
  /// semana, fechaFin = domingo.
  /// Registra o corrige el total MENSUAL de horas de estudio manual de
  /// un alumno en una asignatura (sustituye al antiguo registro
  /// semanal — ver CLAUDE.md, los profesores solo recogen totales
  /// mensuales, editando directamente una celda de
  /// `HorasAsignaturaScreen`). Sin distinción efectivo/total real (no
  /// aplica la lógica de 3 estados del punto 2): duracionTotalMs ==
  /// duracionEfectivaMs a propósito, es un total autoinformado. Si ya
  /// existe una entrada manual de ESE alumno+asignatura+mes, la
  /// actualiza en vez de duplicarla — se localiza con una consulta de
  /// dos igualdades (alumnoId+asignaturaId, ya "provably compliant")
  /// filtrando en cliente por mes y `registradoPorProfesorId` no nulo.
  Future<void> registrarHorasManualesMes({
    required String alumnoId,
    required String asignaturaId,
    required DateTime mes, // cualquier día de ese mes
    required double horas,
    required String profesorId,
  }) async {
    final inicioMes = DateTime(mes.year, mes.month, 1);
    final finMes = DateTime(mes.year, mes.month + 1, 0);
    final ms = (horas * 3600000).round();

    final existentes = await _db
        .collection('sesionesEstudio')
        .where('alumnoId', isEqualTo: alumnoId)
        .where('asignaturaId', isEqualTo: asignaturaId)
        .get();
    QueryDocumentSnapshot<Map<String, dynamic>>? existente;
    for (final d in existentes.docs) {
      final data = d.data();
      if (data['registradoPorProfesorId'] == null) continue;
      final fi = DateTime.tryParse(data['fechaInicio'] ?? '');
      if (fi != null && fi.year == inicioMes.year && fi.month == inicioMes.month) {
        existente = d;
        break;
      }
    }

    if (existente != null) {
      await _db.collection('sesionesEstudio').doc(existente.id).update({
        'duracionTotalMs': ms,
        'duracionEfectivaMs': ms,
        'registradoPorProfesorId': profesorId,
      });
    } else {
      await guardarSesion(SesionEstudio(
        alumnoId: alumnoId,
        tipo: TipoSesion.teorico,
        asignaturaId: asignaturaId,
        fechaInicio: inicioMes,
        fechaFin: finMes,
        duracionTotalMs: ms,
        duracionEfectivaMs: ms,
        registradoPorProfesorId: profesorId,
      ));
    }
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
  /// (suma de `Asignatura.horasObjetivoMensual` de sus asignaturas con
  /// matrícula activa — el objetivo vivía antes en `Curso`, retirado
  /// de ahí: cada asignatura tiene su propia cantidad de horas, ver
  /// CLAUDE.md) para poder colorear en rojo/verde en la UI.
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
      final objetivoPorAsignatura = {
        for (final d in asignaturasSnap.docs)
          d.id: (d.data()['horasObjetivoMensual'] as num?)?.toDouble() ?? 0.0
      };

      final matriculasSnap = await _db
          .collection('matriculas')
          .where('cursoEscolar', isEqualTo: cursoEscolar)
          .where('activa', isEqualTo: true)
          .get();
      final asignaturasPorAlumno = <String, Set<String>>{};
      for (final d in matriculasSnap.docs) {
        final m = d.data();
        final alumnoId = m['alumnoId'] as String? ?? '';
        final asignaturaId = m['asignaturaId'] as String? ?? '';
        if (asignaturaId.isEmpty) continue;
        (asignaturasPorAlumno[alumnoId] ??= {}).add(asignaturaId);
      }
      final objetivoPorAlumno = {
        for (final entry in asignaturasPorAlumno.entries)
          entry.key: entry.value.fold<double>(
              0, (acc, asignaturaId) => acc + (objetivoPorAsignatura[asignaturaId] ?? 0))
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

  /// Cuadro de Honor: horas efectivas del MES ANTERIOR YA CERRADO
  /// (pedido por dirección: deja de ser en tiempo real sobre el mes en
  /// curso, para que la clasificación no cambie bajo los pies mientras
  /// el mes todavía está en marcha) agrupadas por curso → asignatura
  /// (ver CLAUDE.md), de CUALQUIER tipo de sesión (instrumento +
  /// teórico). Visible a TODOS los permisos: excepción deliberada del
  /// punto 14 (privacidad de nombres) — DISTINTA de
  /// `HorasAsignaturaScreen` (sigue siendo solo profesor/dirección, y
  /// esa sí es del mes en curso). El filtro `tipo in [...]` va en la
  /// propia consulta para ser "provably compliant" para alumno (ver
  /// CLAUDE.md puntos 25/42/53).
  Stream<
      List<
          ({
            String alumnoId,
            String alumnoNombre,
            String asignaturaId,
            double horasEfectivasMes
          })>> horasPorAsignaturaMensual() {
    return _db
        .collection('sesionesEstudio')
        .where('tipo', whereIn: ['instrumento', 'teorico'])
        .snapshots()
        .map((snap) {
      final ahora = DateTime.now();
      final inicioMes = DateTime(ahora.year, ahora.month - 1, 1);
      final finMes = DateTime(ahora.year, ahora.month, 1);

      final msPorAlumnoYAsignatura = <String, Map<String, int>>{};
      final nombrePorAlumno = <String, String>{};
      for (final doc in snap.docs) {
        final data = doc.data();
        final fechaInicio = DateTime.tryParse(data['fechaInicio'] ?? '');
        if (fechaInicio == null ||
            fechaInicio.isBefore(inicioMes) ||
            !fechaInicio.isBefore(finMes)) {
          continue;
        }
        final asignaturaId = data['asignaturaId'] as String?;
        if (asignaturaId == null || asignaturaId.isEmpty) continue;
        final alumnoId = data['alumnoId'] as String? ?? '';
        final efectivoMs = (data['duracionEfectivaMs'] as num?)?.toInt() ?? 0;
        final porAsignatura = msPorAlumnoYAsignatura[alumnoId] ??= {};
        porAsignatura[asignaturaId] = (porAsignatura[asignaturaId] ?? 0) + efectivoMs;
        // Mismo bug ya corregido en cuadroDeHonorMensual (punto 50): no
        // dejar que un valor ausente sobrescriba un alumnoNombre ya
        // conocido.
        final nombreNuevo = data['alumnoNombre'] as String?;
        if (nombreNuevo != null && nombreNuevo.isNotEmpty) {
          nombrePorAlumno[alumnoId] = nombreNuevo;
        } else {
          nombrePorAlumno.putIfAbsent(alumnoId, () => '');
        }
      }

      return [
        for (final alumnoEntry in msPorAlumnoYAsignatura.entries)
          for (final asigEntry in alumnoEntry.value.entries)
            (
              alumnoId: alumnoEntry.key,
              alumnoNombre: nombrePorAlumno[alumnoEntry.key] ?? '',
              asignaturaId: asigEntry.key,
              horasEfectivasMes: asigEntry.value / 3600000,
            )
      ];
    });
  }

  // -------------------------------------------------------------
  // Notas
  // -------------------------------------------------------------
  Future<void> crearNota(Nota nota) async {
    await _db.collection('notas').add(nota.toMap());
  }

  /// Corregir una nota mal puesta. Las reglas solo lo permiten a
  /// dirección o al profesor que la puso mientras siga pendiente.
  Future<void> actualizarNota(String notaId, {required double valor, required String comentario}) {
    return _db.collection('notas').doc(notaId).update({'valor': valor, 'comentario': comentario});
  }

  /// Borrar una nota puesta por error (mismas condiciones que editar).
  Future<void> eliminarNota(String notaId) {
    return _db.collection('notas').doc(notaId).delete();
  }

  Stream<List<Nota>> notasDeAlumno(String alumnoId) {
    return _db
        .collection('notas')
        .where('alumnoId', isEqualTo: alumnoId)
        .orderBy('fecha', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) => Nota.fromMap(d.id, d.data())).toList());
  }

  /// Todas las notas de una asignatura (de cualquier alumno) — a
  /// diferencia de `notasDeAlumno`, no filtra por alumno: es la
  /// fuente de la cuadrícula de notas (filas=alumnos,
  /// columnas=criterios). Sin `orderBy` (se indexa client-side por
  /// alumnoId+criterioId en la cuadrícula), así que basta el índice
  /// automático de un solo campo.
  ///
  /// La regla de lectura de `notas` para profesor/dirección
  /// (`esProfesorODireccion()`) NO depende de `resource.data` —a
  /// diferencia de `matriculas`/`asistencias`—, así que cualquier
  /// consulta (con o sin más filtros) es "provably compliant" para
  /// esos roles; no hace falta acotar más esta consulta (ver CLAUDE.md
  /// punto 25 para el caso contrario).
  Stream<List<Nota>> notasDeAsignatura(String asignaturaId) {
    return _db
        .collection('notas')
        .where('asignaturaId', isEqualTo: asignaturaId)
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
  // Pluses de orquesta (dirección los configura, se eligen al
  // matricular — ver CLAUDE.md y PlusOrquesta)
  // -------------------------------------------------------------
  Future<String> crearPlusOrquesta(PlusOrquesta plus) async {
    final ref = await _db.collection('plusesOrquesta').add(plus.toMap());
    return ref.id;
  }

  Future<void> actualizarPlusOrquesta(String id, Map<String, dynamic> cambios) {
    return _db.collection('plusesOrquesta').doc(id).update(cambios);
  }

  Future<void> eliminarPlusOrquesta(String id) {
    return _db.collection('plusesOrquesta').doc(id).delete();
  }

  Future<PlusOrquesta?> plusOrquesta(String id) async {
    if (id.isEmpty) return null;
    final doc = await _db.collection('plusesOrquesta').doc(id).get();
    if (!doc.exists) return null;
    return PlusOrquesta.fromMap(doc.id, doc.data()!);
  }

  Stream<List<PlusOrquesta>> plusesOrquesta() {
    return _db
        .collection('plusesOrquesta')
        .snapshots()
        .map((snap) => snap.docs.map((d) => PlusOrquesta.fromMap(d.id, d.data())).toList());
  }

  /// Pluses de orquesta aplicables a `asignaturaDestinoId` para este
  /// alumno en este curso escolar (ver CLAUDE.md,
  /// `Matricula.plusOrquestaId`), con la fecha de alta de la matrícula
  /// que lo aplica — necesaria para no proyectar el plus hacia meses
  /// ANTERIORES a que esa matrícula existiera al agregarlo por mes
  /// (ver `CuerpoHorasAsignatura`). No son sesiones reales, es un
  /// extra fijo mientras la matrícula con el plus siga activa; se suma
  /// aparte en cada pantalla de horas de estudio, no se persiste como
  /// `sesionesEstudio`. En MINUTOS (como `PlusOrquesta.minutosSemana`),
  /// no horas — quien consuma esto convierte según necesite.
  Future<List<({int minutosSemana, DateTime desde})>> plusesOrquestaAplicablesDeAlumno({
    required String alumnoId,
    required String asignaturaDestinoId,
    required String cursoEscolar,
  }) async {
    final matriculas = await matriculasDeAlumno(alumnoId, cursoEscolar: cursoEscolar).first;
    final resultado = <({int minutosSemana, DateTime desde})>[];
    for (final m in matriculas) {
      if (m.plusOrquestaId.isEmpty) continue;
      final plus = await plusOrquesta(m.plusOrquestaId);
      if (plus != null && plus.asignaturaDestinoId == asignaturaDestinoId) {
        resultado.add((minutosSemana: plus.minutosSemana, desde: m.fechaAlta));
      }
    }
    return resultado;
  }

  /// Suma en HORAS de los pluses aplicables (convertido desde minutos)
  /// — para la SEMANA actual, donde no hace falta distinguir desde
  /// cuándo (si la matrícula empezó esta misma semana, se cuenta igual
  /// completa, aproximación aceptada). Ver
  /// `plusesOrquestaAplicablesDeAlumno`.
  Future<double> horasPlusOrquestaSemanalDeAlumno({
    required String alumnoId,
    required String asignaturaDestinoId,
    required String cursoEscolar,
  }) async {
    final pluses = await plusesOrquestaAplicablesDeAlumno(
        alumnoId: alumnoId, asignaturaDestinoId: asignaturaDestinoId, cursoEscolar: cursoEscolar);
    return pluses.fold<double>(0, (acc, p) => acc + p.minutosSemana / 60.0);
  }

  // -------------------------------------------------------------
  // Usuarios / listados
  // -------------------------------------------------------------
  // Piloto de un solo centro: sin filtro por centroId (ver CLAUDE.md,
  // backlog de multi-centro). Un solo filtro arrayContains, sin
  // necesidad de índice compuesto.
  // Los dados de baja (`activo == false`) se filtran en cliente y no
  // con un where: los documentos antiguos no tienen el campo, y un
  // where('activo', isEqualTo: true) los dejaría fuera.
  Stream<List<Usuario>> _usuariosConPermiso(String permiso, {required bool activos}) {
    return _db
        .collection('usuarios')
        .where('permisos', arrayContains: permiso)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => Usuario.fromMap(d.id, d.data()))
            .where((u) => u.activo == activos)
            .toList());
  }

  Stream<List<Usuario>> alumnosDelCentro() => _usuariosConPermiso('alumno', activos: true);

  Stream<List<Usuario>> profesoresDelCentro() => _usuariosConPermiso('profesor', activos: true);

  Stream<List<Usuario>> alumnosDadosDeBaja() => _usuariosConPermiso('alumno', activos: false);

  Stream<List<Usuario>> profesoresDadosDeBaja() => _usuariosConPermiso('profesor', activos: false);

  /// Contacto de la familia (solo dirección, ver ContactoAlumno). Un
  /// get() de un doc que aún no existe es el caso normal (ver reglas).
  Future<ContactoAlumno> contactoAlumno(String alumnoId) async {
    final doc = await _db.collection('contactosAlumno').doc(alumnoId).get();
    return doc.exists
        ? ContactoAlumno.fromMap(alumnoId, doc.data()!)
        : ContactoAlumno(alumnoId: alumnoId);
  }

  Future<void> guardarContactoAlumno(ContactoAlumno contacto) {
    return _db.collection('contactosAlumno').doc(contacto.alumnoId).set(contacto.toMap());
  }

  /// Datos personales editables por dirección. El email de acceso NO se
  /// puede cambiar desde la app (Firebase Auth solo deja cambiar el de
  /// otra persona con Admin SDK, es decir, con Cloud Functions/Blaze).
  Future<void> actualizarDatosUsuario(
    String uid, {
    required String nombre,
    String? apellidos,
    String? instrumento,
  }) {
    return _db.collection('usuarios').doc(uid).update({
      'nombre': nombre,
      'apellidos': apellidos,
      'instrumento': instrumento,
    });
  }

  /// Baja del centro: marca `activo: false` (las reglas le retiran
  /// todos los permisos) y desactiva todas sus matrículas activas. No
  /// borra nada — notas, asistencias, horas y fichajes se conservan.
  Future<void> darDeBajaUsuario(String uid) async {
    final batch = _db.batch();
    batch.update(_db.collection('usuarios').doc(uid), {
      'activo': false,
      'bajaEn': DateTime.now().toIso8601String(),
    });
    final matriculas = await _db
        .collection('matriculas')
        .where('alumnoId', isEqualTo: uid)
        .where('activa', isEqualTo: true)
        .get();
    for (final d in matriculas.docs) {
      batch.update(d.reference, {'activa': false});
    }
    await batch.commit();
  }

  /// Vuelve a dar acceso. Las matrículas que se desactivaron con la baja
  /// NO se recuperan solas: hay que volver a matricularlo.
  Future<void> reactivarUsuario(String uid) {
    return _db.collection('usuarios').doc(uid).update({'activo': true, 'bajaEn': null});
  }

  Future<Usuario?> obtenerUsuario(String uid) async {
    final doc = await _db.collection('usuarios').doc(uid).get();
    if (!doc.exists) return null;
    return Usuario.fromMap(doc.id, doc.data()!);
  }

  /// Busca un usuario por email exacto — usado por la importación
  /// masiva desde Excel para no duplicar un alumno ya existente al
  /// reimportar el mismo archivo (ver CLAUDE.md). La regla de lectura
  /// de `usuarios` para profesor/dirección no depende de
  /// `resource.data`, así que esta consulta es "provably compliant"
  /// sin más condición (mismo criterio que `notas`, CLAUDE.md punto 25).
  Future<Usuario?> obtenerUsuarioPorEmail(String email) async {
    final snap =
        await _db.collection('usuarios').where('email', isEqualTo: email).limit(1).get();
    if (snap.docs.isEmpty) return null;
    return Usuario.fromMap(snap.docs.first.id, snap.docs.first.data());
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

  /// Recalcula gruposAsignatura/{nombreNormalizado}.profesorIds como la
  /// UNIÓN de profesorIds de TODAS las asignaturas (de cualquier
  /// curso) que comparten ese nombre normalizado. Sin Cloud Functions
  /// desplegadas, esto corre en cliente cada vez que se crea/edita una
  /// asignatura o se (des)asigna un profesor — ver CLAUDE.md, permiso
  /// cross-curso por nombre de asignatura.
  Future<void> _sincronizarGrupoAsignatura(String nombreNormalizado) async {
    if (nombreNormalizado.isEmpty) return;
    final snap = await _db
        .collection('asignaturas')
        .where('nombreNormalizado', isEqualTo: nombreNormalizado)
        .get();
    final union = <String>{
      for (final d in snap.docs)
        ...List<String>.from(d.data()['profesorIds'] ?? const [])
    }.toList();
    await _db
        .collection('gruposAsignatura')
        .doc(nombreNormalizado)
        .set({'profesorIds': union}, SetOptions(merge: true));
  }

  /// Migración ÚNICA a ejecutar una sola vez tras desplegar el permiso
  /// cross-curso (ver CLAUDE.md): rellena `nombreNormalizado` en las
  /// asignaturas creadas antes de este cambio y reconstruye desde cero
  /// TODOS los documentos de `gruposAsignatura`. Después de esta
  /// migración, la sincronización normal ya corre sola en cada
  /// escritura (crear/editar asignatura, (des)asignar profesor).
  Future<void> migrarGruposAsignatura() async {
    final snap = await _db.collection('asignaturas').get();
    final union = <String, Set<String>>{};
    final batchDocs = _db.batch();
    for (final d in snap.docs) {
      final nombre = d.data()['nombre'] as String? ?? '';
      final clave = nombre.trim().toLowerCase();
      if (d.data()['nombreNormalizado'] != clave) {
        batchDocs.update(d.reference, {'nombreNormalizado': clave});
      }
      (union[clave] ??= {}).addAll(List<String>.from(d.data()['profesorIds'] ?? const []));
    }
    await batchDocs.commit();
    final batchGrupos = _db.batch();
    for (final entry in union.entries) {
      if (entry.key.isEmpty) continue;
      batchGrupos.set(
        _db.collection('gruposAsignatura').doc(entry.key),
        {'profesorIds': entry.value.toList()},
        SetOptions(merge: true),
      );
    }
    await batchGrupos.commit();
  }

  Future<String> crearAsignatura(Asignatura asignatura) async {
    final ref = await _db.collection('asignaturas').add(asignatura.toMap());
    await _sincronizarGrupoAsignatura(asignatura.nombre.trim().toLowerCase());
    return ref.id;
  }

  /// Si `cambios` incluye 'nombre' o 'profesorIds', resincroniza el/los
  /// grupo(s) de gruposAsignatura afectados (ver
  /// `_sincronizarGrupoAsignatura`) — necesario para que el permiso
  /// cruzado entre cursos siga reflejando quién enseña qué.
  Future<void> actualizarAsignatura(String asignaturaId, Map<String, dynamic> cambios) async {
    final tocaNombre = cambios.containsKey('nombre');
    final tocaProfesores = cambios.containsKey('profesorIds');
    String? nombreAnterior;
    if (tocaNombre) {
      final actual = await _db.collection('asignaturas').doc(asignaturaId).get();
      nombreAnterior = actual.data()?['nombre'] as String?;
      cambios = {
        ...cambios,
        'nombreNormalizado': (cambios['nombre'] as String).trim().toLowerCase(),
      };
    }
    await _db.collection('asignaturas').doc(asignaturaId).update(cambios);

    if (tocaNombre) {
      final claveNueva = (cambios['nombre'] as String).trim().toLowerCase();
      await _sincronizarGrupoAsignatura(claveNueva);
      final claveVieja = nombreAnterior?.trim().toLowerCase();
      if (claveVieja != null && claveVieja != claveNueva) {
        await _sincronizarGrupoAsignatura(claveVieja);
      }
    } else if (tocaProfesores) {
      final doc = await _db.collection('asignaturas').doc(asignaturaId).get();
      final nombre = doc.data()?['nombre'] as String? ?? '';
      await _sincronizarGrupoAsignatura(nombre.trim().toLowerCase());
    }
  }

  /// Asigna una franja horaria de GRUPO (ver CLAUDE.md punto 69,
  /// `FranjaHoraria`) a la matrícula de UN alumno: copia sus
  /// días/hora a los campos que lee el horario general
  /// (`Matricula.diasSemana`/`horaInicio`/`horaFin`) y guarda
  /// `franjaHorarioId` para poder re-sincronizar si la franja cambia
  /// después. `franja == null` quita la franja asignada (vuelve a
  /// horario individual sin definir).
  Future<void> asignarFranjaMatricula({
    required String alumnoId,
    required String asignaturaId,
    required String cursoEscolar,
    FranjaHoraria? franja,
  }) {
    final id = Matricula.idPara(alumnoId: alumnoId, asignaturaId: asignaturaId, cursoEscolar: cursoEscolar);
    return _db.collection('matriculas').doc(id).update({
      'franjaHorarioId': franja?.id ?? '',
      'diasSemana': franja?.diasSemana ?? const [],
      'horaInicio': franja?.horaInicio ?? '',
      'horaFin': franja?.horaFin ?? '',
    });
  }

  /// Re-sincroniza las matrículas que ya tenían asignada esta franja
  /// (`franjaHorarioId == franja.id`) tras editarla desde
  /// `CursoDetalleScreen` — para que cambiar los días/hora de un grupo
  /// también actualice a los alumnos ya matriculados en él, no solo a
  /// los nuevos. Un solo `WriteBatch`, igual que
  /// `asignarProfesorAAsignatura` y similares.
  Future<void> sincronizarFranjaHoraria({
    required String asignaturaId,
    required String cursoEscolar,
    required FranjaHoraria franja,
  }) async {
    final matriculas = await matriculasDeAsignatura(asignaturaId, cursoEscolar: cursoEscolar).first;
    final afectadas = matriculas.where((m) => m.franjaHorarioId == franja.id).toList();
    if (afectadas.isEmpty) return;
    final batch = _db.batch();
    for (final m in afectadas) {
      batch.update(_db.collection('matriculas').doc(m.id), {
        'diasSemana': franja.diasSemana,
        'horaInicio': franja.horaInicio,
        'horaFin': franja.horaFin,
      });
    }
    await batch.commit();
  }

  /// Asigna una franja de golpe a VARIOS alumnos ya matriculados (ver
  /// CLAUDE.md): crear/editar franjas en la asignatura no vincula sola
  /// a los alumnos que ya estaban matriculados de antes de que
  /// existiera esa franja — hay que asignarla explícitamente. Pensado
  /// para dirección al añadir la primera franja a una asignatura que
  /// ya tenía roster, para no tener que editar matrícula por matrícula.
  Future<void> asignarFranjaAMatriculas({
    required String asignaturaId,
    required String cursoEscolar,
    required List<String> alumnoIds,
    required FranjaHoraria franja,
  }) async {
    if (alumnoIds.isEmpty) return;
    final batch = _db.batch();
    for (final alumnoId in alumnoIds) {
      final id = Matricula.idPara(alumnoId: alumnoId, asignaturaId: asignaturaId, cursoEscolar: cursoEscolar);
      batch.update(_db.collection('matriculas').doc(id), {
        'franjaHorarioId': franja.id,
        'diasSemana': franja.diasSemana,
        'horaInicio': franja.horaInicio,
        'horaFin': franja.horaFin,
      });
    }
    await batch.commit();
  }

  /// Al borrar una franja horaria de la asignatura, las matrículas que
  /// la tenían asignada se quedan sin horario (no tiene sentido dejar
  /// un `diasSemana`/`horaInicio`/`horaFin` "fantasma" de una franja
  /// que ya no existe) — dirección tendrá que asignarles otra.
  Future<void> limpiarFranjaDeMatriculas({
    required String asignaturaId,
    required String cursoEscolar,
    required String franjaId,
  }) async {
    final matriculas = await matriculasDeAsignatura(asignaturaId, cursoEscolar: cursoEscolar).first;
    final afectadas = matriculas.where((m) => m.franjaHorarioId == franjaId).toList();
    if (afectadas.isEmpty) return;
    final batch = _db.batch();
    for (final m in afectadas) {
      batch.update(_db.collection('matriculas').doc(m.id), {
        'franjaHorarioId': '',
        'diasSemana': const [],
        'horaInicio': '',
        'horaFin': '',
      });
    }
    await batch.commit();
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
    final doc = await _db.collection('asignaturas').doc(asignaturaId).get();
    final nombre = doc.data()?['nombre'] as String? ?? '';
    await _db.collection('asignaturas').doc(asignaturaId).delete();
    await _sincronizarGrupoAsignatura(nombre.trim().toLowerCase());
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

  /// Todas las asignaturas (de CUALQUIER curso) que comparten nombre
  /// con alguna donde este profesor figura en profesorIds —
  /// generalización cross-curso de `asignaturasDeProfesor`: ve TODOS
  /// los cursos que ofrecen p.ej. "Piano", no solo aquel en el que
  /// dirección lo puso originalmente en profesorIds (ver CLAUDE.md,
  /// permiso cruzado entre cursos). Agregación en cliente sobre el
  /// stream ya abierto de `asignaturas` (lectura abierta a cualquier
  /// autenticado), sin necesitar un índice ni consultar
  /// gruposAsignatura (que solo hace falta en las reglas).
  Stream<List<Asignatura>> asignaturasDeProfesorCrossCurso(String profesorUid) {
    return _db.collection('asignaturas').snapshots().map((snap) {
      final todas = snap.docs.map((d) => Asignatura.fromMap(d.id, d.data())).toList();
      final nombresDelProfesor = todas
          .where((a) => a.profesorIds.contains(profesorUid))
          .map((a) => a.nombre.trim().toLowerCase())
          .toSet();
      return todas.where((a) => nombresDelProfesor.contains(a.nombre.trim().toLowerCase())).toList();
    });
  }

  /// Lo que un profesor ve en "Mis asignaturas": las suyas (cross-curso,
  /// ver arriba) MÁS las que cubre HOY como sustituto aunque no las dé
  /// normalmente — si no, un sustituto de otra materia no tenía forma
  /// de llegar a la lista para pasar asistencia. Solo hoy: las reglas
  /// solo le dejan leer la lista de alumnos el día de la sustitución.
  Stream<List<Asignatura>> asignaturasVisiblesParaProfesor(String profesorUid) {
    return asignaturasDeProfesorCrossCurso(profesorUid).asyncMap((propias) async {
      final sustituciones = await _db
          .collection('sustituciones')
          .where('profesorId', isEqualTo: profesorUid)
          .where('fecha', isEqualTo: Sustitucion.formatearFecha(DateTime.now()))
          .get();
      final idsPropias = propias.map((a) => a.id).toSet();
      final extra = <Asignatura>[];
      for (final d in sustituciones.docs) {
        final id = d.data()['asignaturaId'] as String? ?? '';
        if (id.isEmpty || idsPropias.contains(id)) continue;
        final asignatura = await this.asignatura(id);
        if (asignatura != null) extra.add(asignatura);
      }
      return [...propias, ...extra];
    });
  }

  Stream<List<Asignatura>> todasLasAsignaturas() {
    return _db
        .collection('asignaturas')
        .snapshots()
        .map((snap) => snap.docs.map((d) => Asignatura.fromMap(d.id, d.data())).toList());
  }

  /// Añade o quita a un profesor de `profesorIds` de una asignatura
  /// (una asignatura puede tener varios profesores). Resincroniza el
  /// grupo de gruposAsignatura de esa asignatura después, para que el
  /// permiso cruzado entre cursos vea el cambio (ver CLAUDE.md).
  Future<void> asignarProfesorAAsignatura({
    required String asignaturaId,
    required String profesorId,
    required bool asignar,
  }) async {
    final ref = _db.collection('asignaturas').doc(asignaturaId);
    await ref.update({
      'profesorIds': asignar
          ? FieldValue.arrayUnion([profesorId])
          : FieldValue.arrayRemove([profesorId]),
    });
    final doc = await ref.get();
    final nombre = doc.data()?['nombre'] as String? ?? '';
    await _sincronizarGrupoAsignatura(nombre.trim().toLowerCase());
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
    String plusOrquestaId = '',
    String horaInicio = '',
    String horaFin = '',
    String franjaHorarioId = '',
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
      plusOrquestaId: plusOrquestaId,
      horaInicio: horaInicio,
      horaFin: horaFin,
      franjaHorarioId: franjaHorarioId,
    );
    return _db.collection('matriculas').doc(id).set(matricula.toMap(), SetOptions(merge: true));
  }

  /// Franja horaria de esta matrícula (ver CLAUDE.md, horario general).
  Future<void> actualizarHorarioMatricula({
    required String alumnoId,
    required String asignaturaId,
    required String cursoEscolar,
    required String horaInicio,
    required String horaFin,
  }) {
    final id = Matricula.idPara(alumnoId: alumnoId, asignaturaId: asignaturaId, cursoEscolar: cursoEscolar);
    return _db.collection('matriculas').doc(id).update({'horaInicio': horaInicio, 'horaFin': horaFin});
  }

  /// Franja de grupo elegida para esta matrícula ('' = ninguna) — ver
  /// CLAUDE.md punto 69. Guarda solo la referencia; los días/hora
  /// copiados van aparte por `actualizarDiasClaseMatricula`/
  /// `actualizarHorarioMatricula` (llamados junto a este desde
  /// `_editarMatricula`).
  Future<void> actualizarFranjaHorarioIdMatricula({
    required String alumnoId,
    required String asignaturaId,
    required String cursoEscolar,
    required String franjaHorarioId,
  }) {
    final id = Matricula.idPara(alumnoId: alumnoId, asignaturaId: asignaturaId, cursoEscolar: cursoEscolar);
    return _db.collection('matriculas').doc(id).update({'franjaHorarioId': franjaHorarioId});
  }

  /// Mueve UNA ocurrencia de clase (un día concreto de una matrícula) a
  /// otro día/hora — usado por arrastrar-soltar en `HorarioGeneralScreen`
  /// (ver CLAUDE.md: MVP deliberado SIN detección de conflictos, soltar
  /// sobre una celda ya ocupada simplemente añade otra clase ahí). Si el
  /// alumno tenía más días además del de origen, se conservan tal cual
  /// —solo se sustituye el día arrastrado por el de destino—, pero
  /// TODOS comparten la misma franja horaria (ver `Matricula.horaInicio`/
  /// `horaFin`), así que mover a una hora distinta también cambia la
  /// hora del resto de días. Se desvincula de cualquier franja de grupo
  /// que tuviera (`franjaHorarioId` = ''), porque su horario ya puede no
  /// coincidir con el resto del grupo — si se quiere podar el vínculo,
  /// dirección puede reasignarle una franja de nuevo desde la matrícula.
  Future<void> moverOcurrenciaHorario({
    required String alumnoId,
    required String asignaturaId,
    required String cursoEscolar,
    required int diaOrigen,
    required int diaDestino,
    required String horaInicioDestino,
    required String horaFinDestino,
  }) async {
    final id = Matricula.idPara(alumnoId: alumnoId, asignaturaId: asignaturaId, cursoEscolar: cursoEscolar);
    final doc = await _db.collection('matriculas').doc(id).get();
    if (!doc.exists) return;
    final matricula = Matricula.fromMap(doc.id, doc.data()!);
    final nuevosDias = {...matricula.diasSemana.where((d) => d != diaOrigen), diaDestino}.toList()..sort();
    await _db.collection('matriculas').doc(id).update({
      'diasSemana': nuevosDias,
      'horaInicio': horaInicioDestino,
      'horaFin': horaFinDestino,
      'franjaHorarioId': '',
    });
  }

  /// Plus de orquesta aplicado a esta matrícula ('' = ninguno) — ver
  /// CLAUDE.md y `PlusOrquesta`.
  Future<void> actualizarPlusOrquestaMatricula({
    required String alumnoId,
    required String asignaturaId,
    required String cursoEscolar,
    required String plusOrquestaId,
  }) {
    final id = Matricula.idPara(alumnoId: alumnoId, asignaturaId: asignaturaId, cursoEscolar: cursoEscolar);
    return _db.collection('matriculas').doc(id).update({'plusOrquestaId': plusOrquestaId});
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
  /// Matrículas activas de TODAS las asignaturas de un profesor
  /// (cross-curso, ver CLAUDE.md) en un curso escolar — para su
  /// horario visible. Mismo motivo que `alumnosDeProfesorAgrupados`
  /// (ya retirado, ver punto 8): la regla de lectura de `matriculas`
  /// para profesor depende de `resource.data.asignaturaId`, así que se
  /// itera por sus asignaturas en vez de filtrar `matriculas`
  /// directamente (no sería provably compliant).
  Future<List<Matricula>> matriculasDeProfesor({
    required String profesorId,
    required String cursoEscolar,
  }) async {
    final asignaturas = await asignaturasDeProfesorCrossCurso(profesorId).first;
    final resultado = <Matricula>[];
    for (final asignatura in asignaturas) {
      final matriculas =
          await matriculasDeAsignatura(asignatura.id!, cursoEscolar: cursoEscolar).first;
      resultado.addAll(matriculas);
    }
    return resultado;
  }

  /// Días de clase de los últimos [diasAtras] días (incluido hoy) sin
  /// asistencia marcada, para dirección. Una sola consulta de
  /// asistencias por rango de fecha en vez de una lectura por
  /// alumno·asignatura·día (antes tardaba mucho con muchos alumnos).
  Future<List<({Matricula matricula, DateTime fecha})>> asistenciasSinMarcar({int diasAtras = 7}) async {
    final cursoEscolar = await cursoEscolarActivo().first;
    final matriculas = await todasLasMatriculasActivas(cursoEscolar: cursoEscolar).first;
    final hoy = DateTime.now();
    final hoySoloFecha = DateTime(hoy.year, hoy.month, hoy.day);
    final desde = hoySoloFecha.subtract(Duration(days: diasAtras - 1));
    final marcadas = await _db
        .collection('asistencias')
        .where('fecha', isGreaterThanOrEqualTo: Asistencia.formatearFecha(desde))
        .get();
    final clavesMarcadas = {
      for (final d in marcadas.docs) '${d.data()['alumnoId']}_${d.data()['asignaturaId']}_${d.data()['fecha']}'
    };
    final pendientes = <({Matricula matricula, DateTime fecha})>[];
    for (final m in matriculas) {
      if (m.diasSemana.isEmpty) continue;
      final alta = DateTime(m.fechaAlta.year, m.fechaAlta.month, m.fechaAlta.day);
      for (var i = 0; i < diasAtras; i++) {
        final dia = hoySoloFecha.subtract(Duration(days: i));
        if (dia.isBefore(alta) || !m.diasSemana.contains(dia.weekday)) continue;
        if (!clavesMarcadas.contains('${m.alumnoId}_${m.asignaturaId}_${Asistencia.formatearFecha(dia)}')) {
          pendientes.add((matricula: m, fecha: dia));
        }
      }
    }
    pendientes.sort((a, b) => b.fecha.compareTo(a.fecha));
    return pendientes;
  }

  /// Notas FINALES listas para que dirección las valide: un grupo
  /// alumno·asignatura con alguna nota pendiente y nota en TODOS los
  /// criterios de la asignatura (ver CLAUDE.md punto 59). La nota final
  /// usa la más reciente de cada criterio. Los grupos incompletos se
  /// devuelven aparte (solo el recuento), para poder explicar por qué
  /// no aparecen todavía.
  Future<({List<({String alumnoId, String asignaturaId, List<String> notaIds, double notaFinal})> listas, int incompletas})>
      notasFinalesPorValidar() async {
    final pendientes = await notasPendientesSupervision().first;
    final grupos = <String, List<Nota>>{};
    for (final n in pendientes) {
      (grupos['${n.alumnoId}_${n.asignaturaId}'] ??= []).add(n);
    }
    final criteriosCache = <String, List<CriterioEvaluacion>>{};
    final notasAlumnoCache = <String, List<Nota>>{};
    final listas = <({String alumnoId, String asignaturaId, List<String> notaIds, double notaFinal})>[];
    var incompletas = 0;
    for (final grupo in grupos.values) {
      final alumnoId = grupo.first.alumnoId;
      final asignaturaId = grupo.first.asignaturaId;
      final criterios = criteriosCache[asignaturaId] ??= await criteriosDeAsignatura(asignaturaId).first;
      if (criterios.isEmpty) {
        incompletas++;
        continue;
      }
      final notas = (notasAlumnoCache[alumnoId] ??= await notasDeAlumno(alumnoId).first)
          .where((n) => n.asignaturaId == asignaturaId)
          .toList();
      final cubiertos = notas.map((n) => n.criterioId).toSet();
      if (!criterios.every((c) => cubiertos.contains(c.id))) {
        incompletas++;
        continue;
      }
      final masReciente = <String, Nota>{};
      for (final n in notas) {
        final actual = masReciente[n.criterioId];
        if (actual == null || n.fecha.isAfter(actual.fecha)) masReciente[n.criterioId] = n;
      }
      final pesoPorId = {for (final c in criterios) c.id!: c.peso};
      final notaFinal = masReciente.values
          .fold<double>(0, (acc, n) => acc + n.valor * (pesoPorId[n.criterioId] ?? 0) / 100);
      listas.add((
        alumnoId: alumnoId,
        asignaturaId: asignaturaId,
        notaIds: grupo.map((n) => n.id!).toList(),
        notaFinal: notaFinal,
      ));
    }
    return (listas: listas, incompletas: incompletas);
  }

  /// Fichajes autoinformados pendientes de que dirección los valide.
  Stream<int> numeroMarcajesPendientesValidacion() {
    return _db
        .collection('marcajes')
        .where('pendienteValidacion', isEqualTo: true)
        .snapshots()
        .map((snap) => snap.docs.length);
  }

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
  }) async {
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
    await _db.collection('asistencias').doc(id).set(asistencia.toMap(), SetOptions(merge: true));
    await _sincronizarSesionDeAsistencia(
      alumnoId: alumnoId,
      asignaturaId: asignaturaId,
      fecha: fecha,
      asistio: asistio,
    );
  }

  /// ID determinista de la sesión sintética que genera una asistencia
  /// (mismo patrón que Asistencia.idPara, con prefijo para no chocar
  /// con IDs autogenerados de sesionesEstudio "reales").
  String _idSesionDeAsistencia({
    required String alumnoId,
    required String asignaturaId,
    required DateTime fecha,
  }) =>
      'asistencia_${alumnoId}_${asignaturaId}_${Asistencia.formatearFecha(fecha)}';

  /// Marcar asistencia en una asignatura de INSTRUMENTO cuenta como
  /// horas de estudio (pedido en el piloto): crea/actualiza una
  /// SesionEstudio sintética con la duración horaFin-horaInicio de la
  /// matrícula, con ID determinista para que volver a marcar el mismo
  /// día no duplique horas (ver CLAUDE.md). La borra si se marca
  /// "faltó" (no hubo clase), si la asignatura no es de instrumento, o
  /// si la matrícula no tiene horario configurado (no hay duración que
  /// calcular) — en cualquiera de esos casos, delete() sobre un
  /// documento que no existe no falla, así que no hace falta comprobar
  /// antes si ya existía.
  Future<void> _sincronizarSesionDeAsistencia({
    required String alumnoId,
    required String asignaturaId,
    required DateTime fecha,
    required bool asistio,
  }) async {
    final id = _idSesionDeAsistencia(alumnoId: alumnoId, asignaturaId: asignaturaId, fecha: fecha);
    final ref = _db.collection('sesionesEstudio').doc(id);
    if (!asistio) {
      await ref.delete();
      return;
    }

    final asig = await asignatura(asignaturaId);
    if (asig == null || !asig.permiteGrabarEstudio) {
      await ref.delete();
      return;
    }

    final cursoEscolar = cursoEscolarDeFecha(fecha);
    final matriculaId = Matricula.idPara(alumnoId: alumnoId, asignaturaId: asignaturaId, cursoEscolar: cursoEscolar);
    final doc = await _db.collection('matriculas').doc(matriculaId).get();
    if (!doc.exists) {
      await ref.delete();
      return;
    }
    final matricula = Matricula.fromMap(doc.id, doc.data()!);
    final duracionMs = _duracionClaseMs(matricula.horaInicio, matricula.horaFin);
    if (duracionMs <= 0) {
      await ref.delete();
      return;
    }

    final alumno = await obtenerUsuario(alumnoId);
    final sesion = SesionEstudio(
      alumnoId: alumnoId,
      tipo: TipoSesion.instrumento,
      asignaturaId: asignaturaId,
      fechaInicio: fecha,
      fechaFin: fecha,
      duracionTotalMs: duracionMs,
      duracionEfectivaMs: duracionMs,
    );
    await ref.set({
      ...sesion.toMap(),
      'alumnoNombre': alumno?.nombre ?? '',
      // No son campos del modelo Dart SesionEstudio, ver comentario de
      // esGeneradaPorAsistencia() en firestore.rules.
      'origenAsistencia': true,
      'fechaDia': Asistencia.formatearFecha(fecha),
    });
  }

  /// 'HH:mm' a 'HH:mm' → milisegundos, o 0 si cualquiera está vacío o
  /// no tiene formato válido (matrícula sin horario configurado
  /// todavía — ver CLAUDE.md).
  int _duracionClaseMs(String horaInicio, String horaFin) {
    final inicio = _minutosDesdeHHmm(horaInicio);
    final fin = _minutosDesdeHHmm(horaFin);
    if (inicio == null || fin == null || fin <= inicio) return 0;
    return (fin - inicio) * 60000;
  }

  int? _minutosDesdeHHmm(String hhmm) {
    final partes = hhmm.split(':');
    if (partes.length != 2) return null;
    final h = int.tryParse(partes[0]);
    final m = int.tryParse(partes[1]);
    if (h == null || m == null) return null;
    return h * 60 + m;
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

  // -------------------------------------------------------------
  // Incidencias (feedback/bugs) — ver CLAUDE.md, modo desarrollador
  // -------------------------------------------------------------

  /// Denormaliza `autorNombre` al crear (mismo patrón que
  /// `guardarSesion`/`sesionesEstudio.alumnoNombre`): un autor normal
  /// no puede leer el perfil `usuarios` de otro, así que el
  /// desarrollador necesita el nombre ya guardado en la propia
  /// incidencia para poder listarlas sin una lectura extra por fila.
  Future<void> crearIncidencia(Incidencia incidencia) async {
    final autor = await obtenerUsuario(incidencia.autorId);
    await _db.collection('incidencias').add({
      ...incidencia.toMap(),
      'autorNombre': autor?.nombre ?? '',
    });
  }

  Stream<List<Incidencia>> misIncidencias(String uid) {
    return _db
        .collection('incidencias')
        .where('autorId', isEqualTo: uid)
        .orderBy('fecha', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) => Incidencia.fromMap(d.id, d.data())).toList());
  }

  /// Solo alcanzable en la práctica por una cuenta con permiso
  /// `desarrollador` — la regla de `incidencias` concede lectura sin
  /// condición sobre `resource.data` para ese permiso (mismo patrón
  /// que `esProfesorODireccion()` en `notas`), así que esta consulta
  /// sin `where` es "provably compliant" sin filtrar nada más aquí.
  Stream<List<Incidencia>> todasLasIncidencias() {
    return _db
        .collection('incidencias')
        .orderBy('fecha', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) => Incidencia.fromMap(d.id, d.data())).toList());
  }

  Future<void> actualizarEstadoIncidencia(String id, EstadoIncidencia estado) {
    return _db.collection('incidencias').doc(id).update({'estado': estado.name});
  }

  Future<void> agregarComentarioIncidencia(String id, ComentarioIncidencia comentario) {
    return _db.collection('incidencias').doc(id).update({
      'comentarios': FieldValue.arrayUnion([comentario.toMap()]),
    });
  }
}
