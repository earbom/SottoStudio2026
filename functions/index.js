const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");

initializeApp();
const db = getFirestore();

const MS_POR_HORA = 3_600_000;

// Mantiene estadisticasAlumno/{alumnoId} al día cada vez que se crea una
// sesionEstudio. Es la ÚNICA vía de escritura de esa colección (ver
// firestore.rules: `allow write: if false` para el cliente) — así ningún
// alumno puede inflar su propio ranking editando Firestore desde la app.
exports.actualizarEstadisticasAlumno = onDocumentCreated(
  "sesionesEstudio/{sesionId}",
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const sesion = snap.data();
    const alumnoId = sesion.alumnoId;
    if (!alumnoId) return;

    const duracionEfectivaMs = sesion.duracionEfectivaMs ?? 0;
    const duracionTotalMs = sesion.duracionTotalMs ?? 0;

    await db.collection("estadisticasAlumno").doc(alumnoId).set(
      {
        // Acumuladores exactos en ms (fuente de verdad).
        msEfectivoTotal: FieldValue.increment(duracionEfectivaMs),
        msTotalAcumulado: FieldValue.increment(duracionTotalMs),
        // Derivados en horas, listos para el informe de dirección
        // (DbService.informeDireccion ordena por horasEfectivasTotales).
        horasEfectivasTotales: FieldValue.increment(duracionEfectivaMs / MS_POR_HORA),
        horasTotalesTotales: FieldValue.increment(duracionTotalMs / MS_POR_HORA),
        numeroSesiones: FieldValue.increment(1),
        ultimaSesionFecha: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
  }
);
