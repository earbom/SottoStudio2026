// Tests de firestore.rules contra el emulador local de Firestore.
// Ejecutar desde este directorio: `npm test` (requiere `npm install`
// una vez). Nunca corre contra el proyecto real: initializeTestEnvironment
// usa el emulador (127.0.0.1:8080), no Firestore de producción.
'use strict';

const { before, after, beforeEach, describe, it } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require('@firebase/rules-unit-testing');

let testEnv;

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'sottostudio-test',
    firestore: {
      rules: fs.readFileSync(path.resolve(__dirname, '../firestore.rules'), 'utf8'),
      host: '127.0.0.1',
      port: 8080,
    },
  });
});

after(async () => {
  await testEnv.cleanup();
});

beforeEach(async () => {
  await testEnv.clearFirestore();
});

// Puebla datos saltándose las reglas (contexto de administrador),
// para preparar el estado previo de cada test sin depender de que
// las propias reglas de escritura ya funcionen.
async function conDatosDePrueba(fn) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await fn(context.firestore());
  });
}

describe('usuarios', () => {
  it('un alumno puede crear su propio documento con permisos [alumno]', async () => {
    const alumno = testEnv.authenticatedContext('alumno1').firestore();
    await assertSucceeds(
      alumno
        .collection('usuarios')
        .doc('alumno1')
        .set({ nombre: 'Alumno Uno', email: 'a1@test.com', permisos: ['alumno'], createdAt: new Date().toISOString() })
    );
  });

  it('un alumno NO puede crearse a sí mismo con permisos de dirección', async () => {
    const alumno = testEnv.authenticatedContext('alumno1').firestore();
    await assertFails(
      alumno
        .collection('usuarios')
        .doc('alumno1')
        .set({ nombre: 'Alumno Uno', email: 'a1@test.com', permisos: ['direccion'], createdAt: new Date().toISOString() })
    );
  });
});

describe('sesionesEstudio', () => {
  beforeEach(async () => {
    await conDatosDePrueba(async (db) => {
      await db.collection('usuarios').doc('alumno1').set({ permisos: ['alumno'] });
      await db.collection('usuarios').doc('alumno2').set({ permisos: ['alumno'] });
      await db.collection('asignaturas').doc('violin').set({
        cursoId: 'curso1',
        nombre: 'Violín',
        permiteGrabarEstudio: true,
      });
      await db.collection('asignaturas').doc('armonia').set({
        cursoId: 'curso1',
        nombre: 'Armonía',
        permiteGrabarEstudio: false,
      });
    });
  });

  it('un alumno puede crear una sesión en una asignatura que permite grabar', async () => {
    const alumno = testEnv.authenticatedContext('alumno1').firestore();
    await assertSucceeds(
      alumno.collection('sesionesEstudio').add({
        alumnoId: 'alumno1',
        tipo: 'instrumento',
        asignaturaId: 'violin',
        fechaInicio: new Date().toISOString(),
        duracionTotalMs: 1000,
        duracionEfectivaMs: 800,
      })
    );
  });

  it('un alumno NO puede crear una sesión en una asignatura que NO permite grabar (p. ej. teórica)', async () => {
    const alumno = testEnv.authenticatedContext('alumno1').firestore();
    await assertFails(
      alumno.collection('sesionesEstudio').add({
        alumnoId: 'alumno1',
        tipo: 'instrumento',
        asignaturaId: 'armonia',
        fechaInicio: new Date().toISOString(),
        duracionTotalMs: 1000,
        duracionEfectivaMs: 800,
      })
    );
  });

  it('un alumno NO puede crear una sesión sin asignaturaId (ya no existe la práctica libre)', async () => {
    const alumno = testEnv.authenticatedContext('alumno1').firestore();
    await assertFails(
      alumno.collection('sesionesEstudio').add({
        alumnoId: 'alumno1',
        tipo: 'instrumento',
        fechaInicio: new Date().toISOString(),
        duracionTotalMs: 1000,
        duracionEfectivaMs: 800,
      })
    );
  });

  it('un alumno NO puede crear una sesión para otro alumno', async () => {
    const alumno = testEnv.authenticatedContext('alumno1').firestore();
    await assertFails(
      alumno.collection('sesionesEstudio').add({
        alumnoId: 'alumno2',
        tipo: 'instrumento',
        asignaturaId: 'violin',
        fechaInicio: new Date().toISOString(),
        duracionTotalMs: 1000,
        duracionEfectivaMs: 800,
      })
    );
  });

  it('un alumno NO puede leer la sesión TEÓRICA de otro alumno', async () => {
    // Nota: una sesión de tipo 'instrumento' de otro alumno SÍ es
    // legible — excepción deliberada para el Cuadro de Honor, ver
    // describe('sesionesEstudio: Cuadro de Honor visible para alumnos').
    let sesionId;
    await conDatosDePrueba(async (db) => {
      const ref = await db.collection('sesionesEstudio').add({
        alumnoId: 'alumno2',
        tipo: 'teorico',
        fechaInicio: new Date().toISOString(),
        duracionTotalMs: 1000,
        duracionEfectivaMs: 800,
      });
      sesionId = ref.id;
    });
    const alumno = testEnv.authenticatedContext('alumno1').firestore();
    await assertFails(alumno.collection('sesionesEstudio').doc(sesionId).get());
  });
});

describe('notas: asignación por alumno y sustituciones', () => {
  beforeEach(async () => {
    await conDatosDePrueba(async (db) => {
      await db.collection('usuarios').doc('profesorA').set({ permisos: ['profesor'] });
      await db.collection('usuarios').doc('profesorB').set({ permisos: ['profesor'] });
      await db.collection('asignaturas').doc('guitarra').set({
        cursoId: 'curso1',
        nombre: 'Guitarra',
        profesorIds: ['profesorA', 'profesorB'],
        createdAt: new Date().toISOString(),
        createdBy: 'dir1',
      });
      await db.collection('matriculas').doc('alumno1_guitarra_2026-2027').set({
        alumnoId: 'alumno1',
        asignaturaId: 'guitarra',
        cursoId: 'curso1',
        cursoEscolar: '2026-2027',
        activa: true,
        fechaAlta: new Date().toISOString(),
        diasSemana: [1],
        profesorId: 'profesorA',
      });
    });
  });

  const notaBase = {
    alumnoId: 'alumno1',
    asignaturaId: 'guitarra',
    criterioId: 'c1',
    valor: 7,
    comentario: '',
    fecha: new Date().toISOString(),
    fechaDia: '2026-01-01',
    cursoEscolar: '2026-2027',
    estado: 'pendiente',
  };

  it('el profesor asignado a ese alumno SÍ puede ponerle nota', async () => {
    const profesorA = testEnv.authenticatedContext('profesorA').firestore();
    await assertSucceeds(
      profesorA.collection('notas').add({ ...notaBase, profesorId: 'profesorA' })
    );
  });

  it('un profesor de la MISMA asignatura pero sin ese alumno asignado NO puede puntuarlo', async () => {
    const profesorB = testEnv.authenticatedContext('profesorB').firestore();
    await assertFails(
      profesorB.collection('notas').add({ ...notaBase, profesorId: 'profesorB' })
    );
  });

  it('con una sustitución activa ese día, el otro profesor SÍ puede puntuar', async () => {
    await conDatosDePrueba(async (db) => {
      await db.collection('sustituciones').doc('guitarra_profesorB_2026-01-01').set({
        asignaturaId: 'guitarra',
        profesorId: 'profesorB',
        fecha: '2026-01-01',
        creadaPor: 'dir1',
        creadaEn: new Date().toISOString(),
      });
    });
    const profesorB = testEnv.authenticatedContext('profesorB').firestore();
    await assertSucceeds(
      profesorB.collection('notas').add({ ...notaBase, profesorId: 'profesorB' })
    );
  });

  it('rechaza un valor de nota fuera de 0-10', async () => {
    const profesorA = testEnv.authenticatedContext('profesorA').firestore();
    await assertFails(
      profesorA.collection('notas').add({ ...notaBase, profesorId: 'profesorA', valor: 99 })
    );
  });

  it('un alumno no puede leer la nota de otro alumno', async () => {
    let notaId;
    await conDatosDePrueba(async (db) => {
      await db.collection('usuarios').doc('alumno1').set({ permisos: ['alumno'] });
      await db.collection('usuarios').doc('alumno2').set({ permisos: ['alumno'] });
      const ref = await db.collection('notas').add({ ...notaBase, profesorId: 'profesorA' });
      notaId = ref.id;
    });
    const alumno2 = testEnv.authenticatedContext('alumno2').firestore();
    await assertFails(alumno2.collection('notas').doc(notaId).get());
  });
});

describe('criteriosEvaluacion', () => {
  beforeEach(async () => {
    await conDatosDePrueba(async (db) => {
      await db.collection('usuarios').doc('dir1').set({ permisos: ['direccion'] });
      await db.collection('usuarios').doc('profesorA').set({ permisos: ['profesor'] });
    });
  });

  it('dirección puede crear un criterio con peso válido', async () => {
    const direccion = testEnv.authenticatedContext('dir1').firestore();
    await assertSucceeds(
      direccion.collection('criteriosEvaluacion').add({
        asignaturaId: 'guitarra',
        nombre: 'Control',
        peso: 20,
        createdAt: new Date().toISOString(),
        createdBy: 'dir1',
      })
    );
  });

  it('rechaza un peso fuera de 0-100', async () => {
    const direccion = testEnv.authenticatedContext('dir1').firestore();
    await assertFails(
      direccion.collection('criteriosEvaluacion').add({
        asignaturaId: 'guitarra',
        nombre: 'Control',
        peso: 150,
        createdAt: new Date().toISOString(),
        createdBy: 'dir1',
      })
    );
  });

  it('un profesor NO puede crear un criterio de evaluación', async () => {
    const profesor = testEnv.authenticatedContext('profesorA').firestore();
    await assertFails(
      profesor.collection('criteriosEvaluacion').add({
        asignaturaId: 'guitarra',
        nombre: 'Control',
        peso: 20,
        createdAt: new Date().toISOString(),
        createdBy: 'profesorA',
      })
    );
  });
});

describe('cursos y asignaturas: control total de dirección', () => {
  beforeEach(async () => {
    await conDatosDePrueba(async (db) => {
      await db.collection('usuarios').doc('dir1').set({ permisos: ['direccion'] });
      await db.collection('usuarios').doc('alumno1').set({ permisos: ['alumno'] });
    });
  });

  it('dirección puede crear un curso', async () => {
    const direccion = testEnv.authenticatedContext('dir1').firestore();
    await assertSucceeds(
      direccion.collection('cursos').add({ nombre: 'Reglado 1', createdAt: new Date().toISOString(), createdBy: 'dir1' })
    );
  });

  it('un alumno NO puede crear un curso', async () => {
    const alumno = testEnv.authenticatedContext('alumno1').firestore();
    await assertFails(
      alumno.collection('cursos').add({ nombre: 'Reglado 1', createdAt: new Date().toISOString(), createdBy: 'alumno1' })
    );
  });
});

describe('configuracion: curso escolar activo', () => {
  beforeEach(async () => {
    await conDatosDePrueba(async (db) => {
      await db.collection('usuarios').doc('dir1').set({ permisos: ['direccion'] });
      await db.collection('usuarios').doc('profesorA').set({ permisos: ['profesor'] });
    });
  });

  it('dirección puede fijar el curso escolar activo', async () => {
    const direccion = testEnv.authenticatedContext('dir1').firestore();
    await assertSucceeds(
      direccion
        .collection('configuracion')
        .doc('centro')
        .set({ cursoEscolarActivo: '2026-2027', historialCursosEscolares: ['2026-2027'] })
    );
  });

  it('un profesor NO puede cambiar el curso escolar activo', async () => {
    const profesor = testEnv.authenticatedContext('profesorA').firestore();
    await assertFails(
      profesor
        .collection('configuracion')
        .doc('centro')
        .set({ cursoEscolarActivo: '2026-2027', historialCursosEscolares: ['2026-2027'] })
    );
  });

  it('un profesor SÍ puede leer el curso escolar activo', async () => {
    await conDatosDePrueba(async (db) => {
      await db.collection('configuracion').doc('centro').set({
        cursoEscolarActivo: '2026-2027',
        historialCursosEscolares: ['2026-2027'],
      });
    });
    const profesor = testEnv.authenticatedContext('profesorA').firestore();
    await assertSucceeds(profesor.collection('configuracion').doc('centro').get());
  });

  it('nadie puede borrar la configuración del centro', async () => {
    await conDatosDePrueba(async (db) => {
      await db.collection('configuracion').doc('centro').set({ cursoEscolarActivo: '2026-2027' });
    });
    const direccion = testEnv.authenticatedContext('dir1').firestore();
    await assertFails(direccion.collection('configuracion').doc('centro').delete());
  });
});

describe('matriculas: ID distingue curso escolar', () => {
  beforeEach(async () => {
    await conDatosDePrueba(async (db) => {
      await db.collection('usuarios').doc('dir1').set({ permisos: ['direccion'] });
      await db.collection('usuarios').doc('alumno1').set({ permisos: ['alumno'] });
    });
  });

  it('un mismo alumno puede tener matrícula en la misma asignatura en dos cursos escolares distintos', async () => {
    const direccion = testEnv.authenticatedContext('dir1').firestore();
    await assertSucceeds(
      direccion.collection('matriculas').doc('alumno1_guitarra_2025-2026').set({
        alumnoId: 'alumno1',
        asignaturaId: 'guitarra',
        cursoId: 'curso1',
        cursoEscolar: '2025-2026',
        activa: true,
        fechaAlta: new Date().toISOString(),
      })
    );
    await assertSucceeds(
      direccion.collection('matriculas').doc('alumno1_guitarra_2026-2027').set({
        alumnoId: 'alumno1',
        asignaturaId: 'guitarra',
        cursoId: 'curso1',
        cursoEscolar: '2026-2027',
        activa: true,
        fechaAlta: new Date().toISOString(),
      })
    );
    // el documento del curso anterior sigue existiendo, no se pisó
    const anterior = await direccion.collection('matriculas').doc('alumno1_guitarra_2025-2026').get();
    assert.equal(anterior.exists, true);
    assert.equal(anterior.data().cursoEscolar, '2025-2026');
  });
});

describe('sesionesEstudio: Cuadro de Honor visible para alumnos', () => {
  beforeEach(async () => {
    await conDatosDePrueba(async (db) => {
      await db.collection('usuarios').doc('alumno1').set({ permisos: ['alumno'] });
      await db.collection('usuarios').doc('alumno2').set({ permisos: ['alumno'] });
    });
  });

  it('un alumno SÍ puede leer una sesión de instrumento de OTRO alumno (para el Cuadro de Honor)', async () => {
    let sesionId;
    await conDatosDePrueba(async (db) => {
      const ref = await db.collection('sesionesEstudio').add({
        alumnoId: 'alumno2',
        tipo: 'instrumento',
        fechaInicio: new Date().toISOString(),
        duracionTotalMs: 1000,
        duracionEfectivaMs: 800,
      });
      sesionId = ref.id;
    });
    const alumno1 = testEnv.authenticatedContext('alumno1').firestore();
    await assertSucceeds(alumno1.collection('sesionesEstudio').doc(sesionId).get());
  });

  it('un alumno NO puede leer una sesión de estudio TEÓRICO de otro alumno', async () => {
    let sesionId;
    await conDatosDePrueba(async (db) => {
      const ref = await db.collection('sesionesEstudio').add({
        alumnoId: 'alumno2',
        tipo: 'teorico',
        fechaInicio: new Date().toISOString(),
        duracionTotalMs: 1000,
        duracionEfectivaMs: 800,
      });
      sesionId = ref.id;
    });
    const alumno1 = testEnv.authenticatedContext('alumno1').firestore();
    await assertFails(alumno1.collection('sesionesEstudio').doc(sesionId).get());
  });

  it('un alumno puede consultar la colección entera filtrando por tipo == instrumento (query real del Cuadro de Honor)', async () => {
    await conDatosDePrueba(async (db) => {
      await db.collection('sesionesEstudio').add({
        alumnoId: 'alumno2',
        tipo: 'instrumento',
        fechaInicio: new Date().toISOString(),
        duracionTotalMs: 1000,
        duracionEfectivaMs: 800,
      });
    });
    const alumno1 = testEnv.authenticatedContext('alumno1').firestore();
    // Regresión: una consulta de la colección SIN el where('tipo', ...)
    // no es "provably compliant" con la regla de lectura de alumno y
    // Firestore la rechaza entera, aunque cada doc individual sí fuera
    // legible — por eso cuadroDeHonorMensual() necesita ese filtro en
    // la propia consulta, no solo como `continue` tras leer.
    await assertFails(alumno1.collection('sesionesEstudio').get());
    await assertSucceeds(alumno1.collection('sesionesEstudio').where('tipo', '==', 'instrumento').get());
  });
});

describe('registro horario (Art. 34.9 ET): horariosLaborales y marcajes', () => {
  beforeEach(async () => {
    await conDatosDePrueba(async (db) => {
      await db.collection('usuarios').doc('profesorA').set({ permisos: ['profesor'] });
      await db.collection('usuarios').doc('profesorB').set({ permisos: ['profesor'] });
      await db.collection('usuarios').doc('dir1').set({ permisos: ['direccion'] });
      await db.collection('usuarios').doc('alumno1').set({ permisos: ['alumno'] });
    });
  });

  it('un profesor puede configurar su propio horario laboral', async () => {
    const profesorA = testEnv.authenticatedContext('profesorA').firestore();
    await assertSucceeds(
      profesorA.collection('horariosLaborales').doc('profesorA').set({
        turnos: [{ diaSemana: 1, horaEntrada: '16:00', horaSalida: '20:00' }],
        minutosAvisoAntes: 10,
      })
    );
  });

  it('un profesor NO puede configurar el horario laboral de otro', async () => {
    const profesorA = testEnv.authenticatedContext('profesorA').firestore();
    await assertFails(
      profesorA.collection('horariosLaborales').doc('profesorB').set({
        turnos: [{ diaSemana: 1, horaEntrada: '16:00', horaSalida: '20:00' }],
        minutosAvisoAntes: 10,
      })
    );
  });

  it('un alumno no puede configurar un horario laboral (no es trabajador)', async () => {
    const alumno = testEnv.authenticatedContext('alumno1').firestore();
    await assertFails(
      alumno.collection('horariosLaborales').doc('alumno1').set({
        turnos: [{ diaSemana: 1, horaEntrada: '16:00', horaSalida: '20:00' }],
        minutosAvisoAntes: 10,
      })
    );
  });

  it('un profesor puede fichar su propia entrada', async () => {
    const profesorA = testEnv.authenticatedContext('profesorA').firestore();
    await assertSucceeds(
      profesorA
        .collection('marcajes')
        .doc('profesorA_2026-01-05')
        .set({ empleadoId: 'profesorA', fecha: '2026-01-05', horaEntrada: new Date().toISOString(), horaSalida: null })
    );
  });

  it('un profesor NO puede fichar la entrada de otro profesor', async () => {
    const profesorA = testEnv.authenticatedContext('profesorA').firestore();
    await assertFails(
      profesorA
        .collection('marcajes')
        .doc('profesorB_2026-01-05')
        .set({ empleadoId: 'profesorB', fecha: '2026-01-05', horaEntrada: new Date().toISOString(), horaSalida: null })
    );
  });

  it('un profesor puede fichar su salida tras haber fichado entrada', async () => {
    await conDatosDePrueba(async (db) => {
      await db.collection('marcajes').doc('profesorA_2026-01-05').set({
        empleadoId: 'profesorA',
        fecha: '2026-01-05',
        horaEntrada: new Date('2026-01-05T16:00:00').toISOString(),
        horaSalida: null,
      });
    });
    const profesorA = testEnv.authenticatedContext('profesorA').firestore();
    await assertSucceeds(
      profesorA
        .collection('marcajes')
        .doc('profesorA_2026-01-05')
        .update({ horaSalida: new Date('2026-01-05T20:00:00').toISOString() })
    );
  });

  it('un profesor NO puede reescribir su hora de entrada ya fichada', async () => {
    await conDatosDePrueba(async (db) => {
      await db.collection('marcajes').doc('profesorA_2026-01-05').set({
        empleadoId: 'profesorA',
        fecha: '2026-01-05',
        horaEntrada: new Date('2026-01-05T16:00:00').toISOString(),
        horaSalida: null,
      });
    });
    const profesorA = testEnv.authenticatedContext('profesorA').firestore();
    await assertFails(
      profesorA
        .collection('marcajes')
        .doc('profesorA_2026-01-05')
        .update({ horaEntrada: new Date('2026-01-05T15:00:00').toISOString() })
    );
  });

  it('dirección puede leer y corregir el marcaje de cualquier trabajador', async () => {
    await conDatosDePrueba(async (db) => {
      await db.collection('marcajes').doc('profesorA_2026-01-05').set({
        empleadoId: 'profesorA',
        fecha: '2026-01-05',
        horaEntrada: new Date('2026-01-05T16:00:00').toISOString(),
        horaSalida: null,
      });
    });
    const direccion = testEnv.authenticatedContext('dir1').firestore();
    await assertSucceeds(direccion.collection('marcajes').doc('profesorA_2026-01-05').get());
    await assertSucceeds(
      direccion.collection('marcajes').doc('profesorA_2026-01-05').set(
        {
          horaSalida: new Date('2026-01-05T20:00:00').toISOString(),
          corregidoPor: 'dir1',
          corregidoEn: new Date().toISOString(),
        },
        { merge: true }
      )
    );
  });

  it('nadie puede borrar un marcaje (conservación obligatoria 4 años)', async () => {
    await conDatosDePrueba(async (db) => {
      await db.collection('marcajes').doc('profesorA_2026-01-05').set({
        empleadoId: 'profesorA',
        fecha: '2026-01-05',
        horaEntrada: new Date('2026-01-05T16:00:00').toISOString(),
        horaSalida: null,
      });
    });
    const direccion = testEnv.authenticatedContext('dir1').firestore();
    await assertFails(direccion.collection('marcajes').doc('profesorA_2026-01-05').delete());
  });

  it('un profesor no puede leer el marcaje de otro', async () => {
    await conDatosDePrueba(async (db) => {
      await db.collection('marcajes').doc('profesorB_2026-01-05').set({
        empleadoId: 'profesorB',
        fecha: '2026-01-05',
        horaEntrada: new Date('2026-01-05T16:00:00').toISOString(),
        horaSalida: null,
      });
    });
    const profesorA = testEnv.authenticatedContext('profesorA').firestore();
    await assertFails(profesorA.collection('marcajes').doc('profesorB_2026-01-05').get());
  });

  it('un profesor puede autoinformar un olvido de fichaje propio con entrada y salida completas', async () => {
    const profesorA = testEnv.authenticatedContext('profesorA').firestore();
    await assertSucceeds(
      profesorA
        .collection('marcajes')
        .doc('profesorA_2026-01-04')
        .set({
          empleadoId: 'profesorA',
          fecha: '2026-01-04',
          horaEntrada: new Date('2026-01-04T16:00:00').toISOString(),
          horaSalida: new Date('2026-01-04T20:00:00').toISOString(),
          pendienteValidacion: true,
        })
    );
  });

  it('un profesor NO puede autoinformar un olvido de fichaje de otro profesor', async () => {
    const profesorA = testEnv.authenticatedContext('profesorA').firestore();
    await assertFails(
      profesorA
        .collection('marcajes')
        .doc('profesorB_2026-01-04')
        .set({
          empleadoId: 'profesorB',
          fecha: '2026-01-04',
          horaEntrada: new Date('2026-01-04T16:00:00').toISOString(),
          horaSalida: new Date('2026-01-04T20:00:00').toISOString(),
          pendienteValidacion: true,
        })
    );
  });

  it('el fichaje normal (solo entrada, sin autoinforme) sigue funcionando tras añadir el autoinforme', async () => {
    const profesorA = testEnv.authenticatedContext('profesorA').firestore();
    await assertSucceeds(
      profesorA
        .collection('marcajes')
        .doc('profesorA_2026-01-06')
        .set({
          empleadoId: 'profesorA',
          fecha: '2026-01-06',
          horaEntrada: new Date().toISOString(),
          horaSalida: null,
          pendienteValidacion: false,
        })
    );
  });
});

describe('regresión: leer un documento que aún no existe no debe fallar', () => {
  // Bug real detectado en pruebas manuales: `resource.data.X` sobre un
  // `resource` null (doc inexistente) lanza un error de evaluación que
  // Firestore reporta como permission-denied, dejando la app con la
  // rueda de carga colgada para siempre. Las reglas deben comprobar
  // `resource == null` antes de acceder a resource.data.
  beforeEach(async () => {
    await conDatosDePrueba(async (db) => {
      await db.collection('usuarios').doc('profesorA').set({ permisos: ['profesor'] });
      await db.collection('usuarios').doc('alumno1').set({ permisos: ['alumno'] });
    });
  });

  it('leer un marcaje de hoy que todavía no existe no da permission-denied', async () => {
    const profesorA = testEnv.authenticatedContext('profesorA').firestore();
    const doc = await assertSucceeds(profesorA.collection('marcajes').doc('profesorA_2099-12-31').get());
    assert.equal(doc.exists, false);
  });

  it('leer una asistencia de un día sin marcar no da permission-denied', async () => {
    const profesorA = testEnv.authenticatedContext('profesorA').firestore();
    const doc = await assertSucceeds(
      profesorA.collection('asistencias').doc('alumno1_guitarra_2099-12-31').get()
    );
    assert.equal(doc.exists, false);
  });

  it('leer una matrícula inexistente no da permission-denied', async () => {
    const alumno = testEnv.authenticatedContext('alumno1').firestore();
    const doc = await assertSucceeds(alumno.collection('matriculas').doc('alumno1_inexistente').get());
    assert.equal(doc.exists, false);
  });
});
