import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/sesion_estudio.dart';
import '../models/nota.dart';
import '../models/usuario.dart';

/// Centraliza el acceso a Firestore. Los nombres de colección aquí
/// deben coincidir EXACTAMENTE con los usados en firestore.rules.
class DbService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // -------------------------------------------------------------
  // Sesiones de estudio
  // -------------------------------------------------------------
  Future<void> guardarSesion(SesionEstudio sesion) async {
    await _db.collection('sesionesEstudio').add(sesion.toMap());
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

  /// Informe de dirección: alumnos ordenados por horas efectivas totales,
  /// de mayor a menor.
  ///
  /// FASE DE PRUEBAS: agrega `sesionesEstudio` en el propio cliente en
  /// vez de leer `estadisticasAlumno`, porque esa colección solo la
  /// actualiza la Cloud Function de `functions/index.js` y esta
  /// requiere el plan Blaze — el centro aún no lo ha contratado. Cuando
  /// lo haga, desplegar la función y volver a leer `estadisticasAlumno`
  /// (ver README, sección "Cloud Function: estadisticasAlumno").
  Stream<List<Map<String, dynamic>>> informeDireccion() {
    return _db.collection('sesionesEstudio').snapshots().map((snap) {
      final msEfectivoPorAlumno = <String, int>{};
      for (final doc in snap.docs) {
        final data = doc.data();
        final alumnoId = data['alumnoId'] as String? ?? '';
        final efectivoMs = (data['duracionEfectivaMs'] as num?)?.toInt() ?? 0;
        msEfectivoPorAlumno[alumnoId] =
            (msEfectivoPorAlumno[alumnoId] ?? 0) + efectivoMs;
      }

      final filas = msEfectivoPorAlumno.entries
          .map((e) => {
                'alumnoId': e.key,
                'horasEfectivasTotales': e.value / 3600000,
              })
          .toList()
        ..sort((a, b) => (b['horasEfectivasTotales'] as double)
            .compareTo(a['horasEfectivasTotales'] as double));

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

  // -------------------------------------------------------------
  // Usuarios / listados
  // -------------------------------------------------------------
  Stream<List<Usuario>> alumnosDelCentro(String centroId) {
    return _db
        .collection('usuarios')
        .where('centroId', isEqualTo: centroId)
        .where('rol', isEqualTo: 'alumno')
        .snapshots()
        .map((snap) => snap.docs.map((d) => Usuario.fromMap(d.id, d.data())).toList());
  }

  Stream<List<Usuario>> profesoresDelCentro(String centroId) {
    return _db
        .collection('usuarios')
        .where('centroId', isEqualTo: centroId)
        .where('rol', isEqualTo: 'profesor')
        .snapshots()
        .map((snap) => snap.docs.map((d) => Usuario.fromMap(d.id, d.data())).toList());
  }
}
