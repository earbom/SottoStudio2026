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

  it('un alumno SÍ puede leer una sesión TEÓRICA de otro alumno (ranking por bloques, ampliación deliberada)', async () => {
    // Antes esto fallaba: la excepción de lectura para alumno solo
    // cubría tipo 'instrumento' (Cuadro de Honor de instrumento, ver
    // CLAUDE.md punto 27). Ampliada también a 'teorico' para el
    // ranking por bloques de asignatura (ver CLAUDE.md) — misma
    // decisión de privacidad para ambos tipos.
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
    await assertSucceeds(alumno.collection('sesionesEstudio').doc(sesionId).get());
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
        nombreNormalizado: 'guitarra',
        profesorIds: ['profesorA', 'profesorB'],
        createdAt: new Date().toISOString(),
        createdBy: 'dir1',
      });
      // Ver CLAUDE.md, permiso cruzado entre cursos: la regla de
      // creación de notas/asistencias ya no consulta profesorIds del
      // propio documento ni matriculas.profesorId, sino este grupo
      // agregado por nombre (mantenido en cliente, ver
      // DbService._sincronizarGrupoAsignatura).
      await db.collection('gruposAsignatura').doc('guitarra').set({
        profesorIds: ['profesorA', 'profesorB'],
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

  it('un profesor de la MISMA asignatura SÍ puede puntuar aunque matriculas.profesorId apunte a otro (permiso cruzado por asignatura, ya no un pin por alumno)', async () => {
    // Relajación deliberada (ver CLAUDE.md): matriculas.profesorId pasó
    // a ser informativo. Antes este test comprobaba lo contrario — no
    // volver a restringir esto "simplificando" el código sin releer
    // esa decisión.
    const profesorB = testEnv.authenticatedContext('profesorB').firestore();
    await assertSucceeds(
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

  it('un profesor puede leer TODAS las notas de una asignatura filtrando solo por asignaturaId, aunque no tenga a ese alumno asignado (cuadrícula de notas)', async () => {
    // La regla de lectura de `notas` para profesor/dirección
    // (esProfesorODireccion()) no depende de resource.data, así que
    // esta lectura amplia es una decisión de negocio deliberada, no
    // un descuido — ver CLAUDE.md punto 25 y DbService.notasDeAsignatura.
    await conDatosDePrueba(async (db) => {
      await db.collection('notas').add({ ...notaBase, profesorId: 'profesorA' });
    });
    const profesorB = testEnv.authenticatedContext('profesorB').firestore();
    await assertSucceeds(
      profesorB.collection('notas').where('asignaturaId', '==', 'guitarra').get()
    );
  });
});

describe('permiso cruzado entre cursos por nombre de asignatura (gruposAsignatura)', () => {
  // Dos documentos `Asignatura` distintos (cursos distintos) que
  // comparten nombre "Piano": profesorC solo figura en profesorIds del
  // doc de curso1, profesorD solo en el de curso2. Vía
  // gruposAsignatura/piano (mantenido en cliente, ver
  // DbService._sincronizarGrupoAsignatura) ambos deben poder
  // gestionar alumnos de CUALQUIERA de los dos documentos.
  beforeEach(async () => {
    await conDatosDePrueba(async (db) => {
      await db.collection('usuarios').doc('profesorC').set({ permisos: ['profesor'] });
      await db.collection('usuarios').doc('profesorD').set({ permisos: ['profesor'] });
      await db.collection('usuarios').doc('profesorE').set({ permisos: ['profesor'] });
      await db.collection('asignaturas').doc('piano_curso1').set({
        cursoId: 'curso1',
        nombre: 'Piano',
        nombreNormalizado: 'piano',
        profesorIds: ['profesorC'],
      });
      await db.collection('asignaturas').doc('piano_curso2').set({
        cursoId: 'curso2',
        nombre: 'Piano',
        nombreNormalizado: 'piano',
        profesorIds: ['profesorD'],
      });
      await db.collection('gruposAsignatura').doc('piano').set({
        profesorIds: ['profesorC', 'profesorD'],
      });
      await db.collection('asignaturas').doc('violin').set({
        cursoId: 'curso3',
        nombre: 'Violín',
        nombreNormalizado: 'violin',
        profesorIds: ['profesorE'],
      });
      await db.collection('gruposAsignatura').doc('violin').set({
        profesorIds: ['profesorE'],
      });
      // Asignatura creada ANTES de la migración: sin nombreNormalizado
      // (ver CLAUDE.md, DbService.migrarGruposAsignatura) y sin grupo.
      await db.collection('asignaturas').doc('canto_no_migrada').set({
        cursoId: 'curso4',
        nombre: 'Canto',
        profesorIds: ['profesorF'],
      });
      await db.collection('usuarios').doc('profesorF').set({ permisos: ['profesor'] });
      await db.collection('matriculas').doc('alumno3_piano_curso2_2026-2027').set({
        alumnoId: 'alumno3',
        asignaturaId: 'piano_curso2',
        cursoId: 'curso2',
        cursoEscolar: '2026-2027',
        activa: true,
        fechaAlta: new Date().toISOString(),
        diasSemana: [2],
        profesorId: '',
      });
    });
  });

  const notaPiano = {
    alumnoId: 'alumno3',
    asignaturaId: 'piano_curso2',
    criterioId: 'c1',
    valor: 8,
    comentario: '',
    fecha: new Date().toISOString(),
    fechaDia: '2026-01-01',
    cursoEscolar: '2026-2027',
    estado: 'pendiente',
  };

  it('un profesor de OTRO curso con el mismo NOMBRE de asignatura SÍ puede puntuar/marcar asistencia', async () => {
    const profesorC = testEnv.authenticatedContext('profesorC').firestore();
    await assertSucceeds(
      profesorC.collection('notas').add({ ...notaPiano, profesorId: 'profesorC' })
    );
    await assertSucceeds(
      profesorC.collection('asistencias').doc('alumno3_piano_curso2_2026-01-01').set({
        alumnoId: 'alumno3',
        asignaturaId: 'piano_curso2',
        fecha: '2026-01-01',
        cursoEscolar: '2026-2027',
        asistio: true,
        retraso: false,
        marcadaPor: 'profesorC',
      })
    );
  });

  it('un profesor de una asignatura con NOMBRE DISTINTO sigue sin poder puntuar (control negativo)', async () => {
    const profesorE = testEnv.authenticatedContext('profesorE').firestore();
    await assertFails(
      profesorE.collection('notas').add({ ...notaPiano, profesorId: 'profesorE' })
    );
  });

  it('una asignatura sin nombreNormalizado (no migrada) deniega sin lanzar error de evaluación', async () => {
    const profesorF = testEnv.authenticatedContext('profesorF').firestore();
    await assertFails(
      profesorF.collection('notas').add({
        ...notaPiano,
        asignaturaId: 'canto_no_migrada',
        profesorId: 'profesorF',
      })
    );
  });

  it('un profesor puede leer matriculas de un curso donde no está en profesorIds de ESE doc pero sí en el grupo por nombre', async () => {
    const profesorC = testEnv.authenticatedContext('profesorC').firestore();
    const doc = await assertSucceeds(
      profesorC.collection('matriculas').doc('alumno3_piano_curso2_2026-2027').get()
    );
    assert.equal(doc.exists, true);
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

describe('plusesOrquesta', () => {
  beforeEach(async () => {
    await conDatosDePrueba(async (db) => {
      await db.collection('usuarios').doc('dir1').set({ permisos: ['direccion'] });
      await db.collection('usuarios').doc('profesorA').set({ permisos: ['profesor'] });
      await db.collection('usuarios').doc('alumno1').set({ permisos: ['alumno'] });
    });
  });

  it('dirección puede crear un plus con horasSemana válidas', async () => {
    const direccion = testEnv.authenticatedContext('dir1').firestore();
    await assertSucceeds(
      direccion.collection('plusesOrquesta').add({
        nombre: 'Orquesta de guitarras',
        asignaturaDestinoId: 'guitarra',
        horasSemana: 0.5,
        createdAt: new Date().toISOString(),
        createdBy: 'dir1',
      })
    );
  });

  it('rechaza horasSemana negativas', async () => {
    const direccion = testEnv.authenticatedContext('dir1').firestore();
    await assertFails(
      direccion.collection('plusesOrquesta').add({
        nombre: 'Orquesta de guitarras',
        asignaturaDestinoId: 'guitarra',
        horasSemana: -1,
        createdAt: new Date().toISOString(),
        createdBy: 'dir1',
      })
    );
  });

  it('un profesor NO puede crear un plus de orquesta', async () => {
    const profesor = testEnv.authenticatedContext('profesorA').firestore();
    await assertFails(
      profesor.collection('plusesOrquesta').add({
        nombre: 'Orquesta de guitarras',
        asignaturaDestinoId: 'guitarra',
        horasSemana: 0.5,
        createdAt: new Date().toISOString(),
        createdBy: 'profesorA',
      })
    );
  });

  it('cualquier usuario autenticado puede leer el catálogo', async () => {
    await conDatosDePrueba(async (db) => {
      await db.collection('plusesOrquesta').doc('plus1').set({
        nombre: 'Orquesta de guitarras',
        asignaturaDestinoId: 'guitarra',
        horasSemana: 0.5,
        createdAt: new Date().toISOString(),
        createdBy: 'dir1',
      });
    });
    const alumno = testEnv.authenticatedContext('alumno1').firestore();
    const doc = await assertSucceeds(alumno.collection('plusesOrquesta').doc('plus1').get());
    assert.equal(doc.exists, true);
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

  it('dirección puede crear una asignatura con objetivo de horas válido', async () => {
    const direccion = testEnv.authenticatedContext('dir1').firestore();
    await assertSucceeds(
      direccion.collection('asignaturas').add({
        cursoId: 'curso1',
        nombre: 'Armonía',
        nombreNormalizado: 'armonía',
        profesorIds: [],
        createdAt: new Date().toISOString(),
        createdBy: 'dir1',
        horasObjetivoSemanal: 2,
        horasObjetivoMensual: 8,
      })
    );
  });

  it('rechaza horasObjetivoSemanal/Mensual negativo en asignaturas', async () => {
    const direccion = testEnv.authenticatedContext('dir1').firestore();
    await assertFails(
      direccion.collection('asignaturas').add({
        cursoId: 'curso1',
        nombre: 'Armonía',
        nombreNormalizado: 'armonía',
        profesorIds: [],
        createdAt: new Date().toISOString(),
        createdBy: 'dir1',
        horasObjetivoSemanal: -1,
        horasObjetivoMensual: 8,
      })
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

describe('matriculas: consulta por asignaturaId es la única forma segura para profesor', () => {
  // Documenta una trampa real (ver CLAUDE.md punto 25): la regla de
  // lectura de `matriculas` para profesor depende de
  // `resource.data.asignaturaId` (esProfesorDeAsignaturaPorNombre, la
  // generalización cross-curso de la antigua esProfesorDeAsignatura —
  // ver CLAUDE.md, permiso cruzado entre cursos). Una consulta que no
  // fije ese campo como igualdad exacta —por ejemplo, filtrando solo
  // por alumnoId, como parecería natural para "mis alumnos"— no es
  // "provably compliant" y Firestore la rechaza ENTERA, aunque cada
  // documento individual fuera legible por separado. Por eso
  // DbService.alumnosDeProfesorAgrupados /
  // matriculasDeAlumnoImpartidasPorProfesor iteran por asignaturas del
  // profesor en vez de consultar matriculas por alumnoId directamente
  // — este test evita que alguien "simplifique" ese código de vuelta a
  // la forma que rompe.
  beforeEach(async () => {
    await conDatosDePrueba(async (db) => {
      await db.collection('usuarios').doc('profesorA').set({ permisos: ['profesor'] });
      await db.collection('asignaturas').doc('guitarra').set({
        cursoId: 'curso1',
        nombre: 'Guitarra',
        nombreNormalizado: 'guitarra',
        profesorIds: ['profesorA'],
      });
      await db.collection('gruposAsignatura').doc('guitarra').set({
        profesorIds: ['profesorA'],
      });
      await db.collection('matriculas').doc('alumno1_guitarra_2025-2026').set({
        alumnoId: 'alumno1',
        asignaturaId: 'guitarra',
        cursoId: 'curso1',
        cursoEscolar: '2025-2026',
        activa: true,
        profesorId: 'profesorA',
        fechaAlta: new Date().toISOString(),
      });
    });
  });

  it('un profesor NO puede consultar matriculas filtrando solo por alumnoId', async () => {
    const profesorA = testEnv.authenticatedContext('profesorA').firestore();
    await assertFails(
      profesorA.collection('matriculas').where('alumnoId', '==', 'alumno1').get()
    );
  });

  it('un profesor SÍ puede consultar matriculas filtrando por asignaturaId', async () => {
    const profesorA = testEnv.authenticatedContext('profesorA').firestore();
    await assertSucceeds(
      profesorA
        .collection('matriculas')
        .where('asignaturaId', '==', 'guitarra')
        .where('cursoEscolar', '==', '2025-2026')
        .where('activa', '==', true)
        .get()
    );
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

  it('un alumno SÍ puede leer una sesión de estudio TEÓRICO de otro alumno (ranking por bloques)', async () => {
    // Relajación deliberada (ver CLAUDE.md): antes solo 'instrumento'
    // era legible por otros alumnos. Ampliado a 'teorico' para que el
    // ranking por bloques de asignatura (horas manuales de teoría)
    // también sea visible para todos, igual que el de instrumento —
    // no volver a restringir esto sin releer esa decisión.
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
    await assertSucceeds(alumno1.collection('sesionesEstudio').doc(sesionId).get());
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

  it('un alumno puede consultar filtrando tipo in [instrumento, teorico] (query real del ranking por bloques)', async () => {
    await conDatosDePrueba(async (db) => {
      await db.collection('sesionesEstudio').add({
        alumnoId: 'alumno2',
        tipo: 'teorico',
        fechaInicio: new Date().toISOString(),
        duracionTotalMs: 1000,
        duracionEfectivaMs: 800,
      });
    });
    const alumno1 = testEnv.authenticatedContext('alumno1').firestore();
    await assertSucceeds(
      alumno1.collection('sesionesEstudio').where('tipo', 'in', ['instrumento', 'teorico']).get()
    );
  });

  it('un alumno SIGUE pudiendo consultar filtrando solo tipo == instrumento tras ampliar la regla', async () => {
    // Regresión: comprueba que ampliar la regla de lectura a 'teorico'
    // no rompió el filtro más estrecho que ya usaba cuadroDeHonorMensual().
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
    await assertSucceeds(alumno1.collection('sesionesEstudio').where('tipo', '==', 'instrumento').get());
  });
});

describe('sesionesEstudio: registro manual de horas de teoría por el profesor', () => {
  beforeEach(async () => {
    await conDatosDePrueba(async (db) => {
      await db.collection('usuarios').doc('alumno1').set({ permisos: ['alumno'] });
      await db.collection('usuarios').doc('profesorA').set({ permisos: ['profesor'] });
      await db.collection('usuarios').doc('profesorB').set({ permisos: ['profesor'] });
      await db.collection('usuarios').doc('profesorC').set({ permisos: ['profesor'] });
      await db.collection('asignaturas').doc('armonia').set({
        cursoId: 'curso1',
        nombre: 'Armonía',
        nombreNormalizado: 'armonía',
        profesorIds: ['profesorA'],
        permiteGrabarEstudio: false,
      });
      // Mismo nombre de asignatura ("Armonía"), curso distinto:
      // profesorC solo figura aquí, no en 'armonia' — comprueba que la
      // corrección de un total mensual funciona cross-curso (mismo
      // criterio que el permiso de creación), no solo para quien creó
      // la entrada originalmente.
      await db.collection('asignaturas').doc('armonia_curso2').set({
        cursoId: 'curso2',
        nombre: 'Armonía',
        nombreNormalizado: 'armonía',
        profesorIds: ['profesorC'],
        permiteGrabarEstudio: false,
      });
      await db.collection('gruposAsignatura').doc('armonía').set({
        profesorIds: ['profesorA', 'profesorC'],
      });
      await db.collection('sesionesEstudio').doc('mensual_alumno1_armonia').set({
        ...semana,
        registradoPorProfesorId: 'profesorA',
      });
    });
  });

  const semana = {
    alumnoId: 'alumno1',
    tipo: 'teorico',
    asignaturaId: 'armonia',
    fechaInicio: new Date('2026-01-05').toISOString(),
    fechaFin: new Date('2026-01-11').toISOString(),
    duracionTotalMs: 10800000,
    duracionEfectivaMs: 10800000,
  };

  it('un profesor de la asignatura puede registrar horas manuales tipo teorico para un alumno (cross-curso incluido)', async () => {
    const profesorA = testEnv.authenticatedContext('profesorA').firestore();
    await assertSucceeds(
      profesorA.collection('sesionesEstudio').add({ ...semana, registradoPorProfesorId: 'profesorA' })
    );
  });

  it('un profesor NO puede registrar horas manuales marcando tipo instrumento', async () => {
    const profesorA = testEnv.authenticatedContext('profesorA').firestore();
    await assertFails(
      profesorA.collection('sesionesEstudio').add({
        ...semana,
        tipo: 'instrumento',
        registradoPorProfesorId: 'profesorA',
      })
    );
  });

  it('un profesor que NO enseña esa asignatura no puede registrar horas manuales', async () => {
    const profesorB = testEnv.authenticatedContext('profesorB').firestore();
    await assertFails(
      profesorB.collection('sesionesEstudio').add({ ...semana, registradoPorProfesorId: 'profesorB' })
    );
  });

  it('un alumno no puede usar el camino de registro manual (esa rama exige esProfesor())', async () => {
    const alumno = testEnv.authenticatedContext('alumno1').firestore();
    await assertFails(
      alumno.collection('sesionesEstudio').add({ ...semana, registradoPorProfesorId: 'profesorA' })
    );
  });

  it('el propio profesor que registró el total puede corregirlo', async () => {
    const profesorA = testEnv.authenticatedContext('profesorA').firestore();
    await assertSucceeds(
      profesorA.collection('sesionesEstudio').doc('mensual_alumno1_armonia').update({
        duracionTotalMs: 14400000,
        duracionEfectivaMs: 14400000,
        registradoPorProfesorId: 'profesorA',
      })
    );
  });

  it('otro profesor de la MISMA asignatura, en un curso distinto, también puede corregir el total (cross-curso)', async () => {
    const profesorC = testEnv.authenticatedContext('profesorC').firestore();
    await assertSucceeds(
      profesorC.collection('sesionesEstudio').doc('mensual_alumno1_armonia').update({
        duracionTotalMs: 18000000,
        duracionEfectivaMs: 18000000,
        registradoPorProfesorId: 'profesorC',
      })
    );
  });

  it('un profesor que NO enseña esa asignatura no puede corregir el total de otro', async () => {
    const profesorB = testEnv.authenticatedContext('profesorB').firestore();
    await assertFails(
      profesorB.collection('sesionesEstudio').doc('mensual_alumno1_armonia').update({
        duracionTotalMs: 18000000,
        duracionEfectivaMs: 18000000,
        registradoPorProfesorId: 'profesorB',
      })
    );
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

describe('incidencias (modo desarrollador)', () => {
  beforeEach(async () => {
    await conDatosDePrueba(async (db) => {
      await db.collection('usuarios').doc('alumno1').set({ permisos: ['alumno'] });
      await db.collection('usuarios').doc('alumno2').set({ permisos: ['alumno'] });
      await db.collection('usuarios').doc('dev1').set({ permisos: ['alumno', 'profesor', 'direccion', 'desarrollador'] });
    });
  });

  const incidenciaBase = {
    autorId: 'alumno1',
    autorNombre: 'Alumno Uno',
    tipo: 'problema',
    descripcion: 'Se cierra la app al grabar',
    estado: 'pendiente',
    fecha: new Date().toISOString(),
    comentarios: [],
  };

  it('un usuario autenticado puede crear su propia incidencia', async () => {
    const alumno = testEnv.authenticatedContext('alumno1').firestore();
    await assertSucceeds(alumno.collection('incidencias').add(incidenciaBase));
  });

  it('NO puede crearla ya con estado distinto de pendiente', async () => {
    const alumno = testEnv.authenticatedContext('alumno1').firestore();
    await assertFails(
      alumno.collection('incidencias').add({ ...incidenciaBase, estado: 'resuelto' })
    );
  });

  it('NO puede crearla con un tipo inválido', async () => {
    const alumno = testEnv.authenticatedContext('alumno1').firestore();
    await assertFails(
      alumno.collection('incidencias').add({ ...incidenciaBase, tipo: 'otra_cosa' })
    );
  });

  it('NO puede crearla suplantando a otro autorId', async () => {
    const alumno = testEnv.authenticatedContext('alumno1').firestore();
    await assertFails(
      alumno.collection('incidencias').add({ ...incidenciaBase, autorId: 'alumno2' })
    );
  });

  it('NO puede crearla con comentarios ya rellenos desde el inicio', async () => {
    const alumno = testEnv.authenticatedContext('alumno1').firestore();
    await assertFails(
      alumno.collection('incidencias').add({
        ...incidenciaBase,
        comentarios: [{ autorId: 'alumno1', autorNombre: 'Alumno Uno', texto: 'x', fecha: new Date().toISOString() }],
      })
    );
  });

  it('el autor puede leer su propia incidencia; otro alumno NO puede leerla', async () => {
    let id;
    await conDatosDePrueba(async (db) => {
      const ref = await db.collection('incidencias').add(incidenciaBase);
      id = ref.id;
    });
    const alumno1 = testEnv.authenticatedContext('alumno1').firestore();
    await assertSucceeds(alumno1.collection('incidencias').doc(id).get());
    const alumno2 = testEnv.authenticatedContext('alumno2').firestore();
    await assertFails(alumno2.collection('incidencias').doc(id).get());
  });

  it('el desarrollador puede leer la incidencia de cualquiera', async () => {
    let id;
    await conDatosDePrueba(async (db) => {
      const ref = await db.collection('incidencias').add(incidenciaBase);
      id = ref.id;
    });
    const dev = testEnv.authenticatedContext('dev1').firestore();
    await assertSucceeds(dev.collection('incidencias').doc(id).get());
  });

  it('el autor puede añadir un comentario sin tocar el estado', async () => {
    let id;
    await conDatosDePrueba(async (db) => {
      const ref = await db.collection('incidencias').add(incidenciaBase);
      id = ref.id;
    });
    const alumno1 = testEnv.authenticatedContext('alumno1').firestore();
    await assertSucceeds(
      alumno1.collection('incidencias').doc(id).update({
        comentarios: [{ autorId: 'alumno1', autorNombre: 'Alumno Uno', texto: 'una aclaración', fecha: new Date().toISOString() }],
      })
    );
  });

  it('el autor NO puede cambiar el estado de su propia incidencia (no autorresolverse)', async () => {
    let id;
    await conDatosDePrueba(async (db) => {
      const ref = await db.collection('incidencias').add(incidenciaBase);
      id = ref.id;
    });
    const alumno1 = testEnv.authenticatedContext('alumno1').firestore();
    await assertFails(
      alumno1.collection('incidencias').doc(id).update({ estado: 'resuelto' })
    );
  });

  it('el autor NO puede modificar tipo/descripcion/autorId tras crearla', async () => {
    let id;
    await conDatosDePrueba(async (db) => {
      const ref = await db.collection('incidencias').add(incidenciaBase);
      id = ref.id;
    });
    const alumno1 = testEnv.authenticatedContext('alumno1').firestore();
    await assertFails(
      alumno1.collection('incidencias').doc(id).update({ descripcion: 'otro texto' })
    );
  });

  it('el desarrollador puede cambiar el estado de la incidencia de otro a resuelto', async () => {
    let id;
    await conDatosDePrueba(async (db) => {
      const ref = await db.collection('incidencias').add(incidenciaBase);
      id = ref.id;
    });
    const dev = testEnv.authenticatedContext('dev1').firestore();
    await assertSucceeds(
      dev.collection('incidencias').doc(id).update({ estado: 'resuelto' })
    );
  });

  it('el desarrollador puede añadir un comentario a la incidencia de otro', async () => {
    let id;
    await conDatosDePrueba(async (db) => {
      const ref = await db.collection('incidencias').add(incidenciaBase);
      id = ref.id;
    });
    const dev = testEnv.authenticatedContext('dev1').firestore();
    await assertSucceeds(
      dev.collection('incidencias').doc(id).update({
        comentarios: [{ autorId: 'dev1', autorNombre: 'Desarrollador', texto: 'ya lo miro', fecha: new Date().toISOString() }],
      })
    );
  });

  it('el desarrollador NO puede escribir un estado inválido', async () => {
    let id;
    await conDatosDePrueba(async (db) => {
      const ref = await db.collection('incidencias').add(incidenciaBase);
      id = ref.id;
    });
    const dev = testEnv.authenticatedContext('dev1').firestore();
    await assertFails(
      dev.collection('incidencias').doc(id).update({ estado: 'en_curso' })
    );
  });

  it('un tercero que no es ni autor ni desarrollador NO puede actualizar', async () => {
    let id;
    await conDatosDePrueba(async (db) => {
      const ref = await db.collection('incidencias').add(incidenciaBase);
      id = ref.id;
    });
    const alumno2 = testEnv.authenticatedContext('alumno2').firestore();
    await assertFails(
      alumno2.collection('incidencias').doc(id).update({ estado: 'resuelto' })
    );
  });

  it('solo el desarrollador puede borrar una incidencia', async () => {
    let id;
    await conDatosDePrueba(async (db) => {
      const ref = await db.collection('incidencias').add(incidenciaBase);
      id = ref.id;
    });
    const alumno1 = testEnv.authenticatedContext('alumno1').firestore();
    await assertFails(alumno1.collection('incidencias').doc(id).delete());
    const dev = testEnv.authenticatedContext('dev1').firestore();
    await assertSucceeds(dev.collection('incidencias').doc(id).delete());
  });
});

describe('sesionesEstudio: sesión sintética generada al marcar asistencia', () => {
  beforeEach(async () => {
    await conDatosDePrueba(async (db) => {
      await db.collection('usuarios').doc('alumno1').set({ permisos: ['alumno'] });
      await db.collection('usuarios').doc('dir1').set({ permisos: ['direccion'] });
      await db.collection('usuarios').doc('profesorA').set({ permisos: ['profesor'] });
      await db.collection('usuarios').doc('profesorB').set({ permisos: ['profesor'] });
      await db.collection('asignaturas').doc('guitarra').set({
        cursoId: 'curso1',
        nombre: 'Guitarra',
        nombreNormalizado: 'guitarra',
        profesorIds: ['profesorA'],
        permiteGrabarEstudio: true,
      });
      await db.collection('gruposAsignatura').doc('guitarra').set({ profesorIds: ['profesorA'] });
    });
  });

  const sesion = {
    alumnoId: 'alumno1',
    tipo: 'instrumento',
    asignaturaId: 'guitarra',
    fechaInicio: new Date('2026-01-05').toISOString(),
    fechaFin: new Date('2026-01-05').toISOString(),
    duracionTotalMs: 1800000,
    duracionEfectivaMs: 1800000,
    origenAsistencia: true,
    fechaDia: '2026-01-05',
  };

  it('el profesor de la asignatura puede crear la sesión sintética', async () => {
    const profesorA = testEnv.authenticatedContext('profesorA').firestore();
    await assertSucceeds(
      profesorA.collection('sesionesEstudio').doc('asistencia_alumno1_guitarra_2026-01-05').set(sesion)
    );
  });

  it('dirección también puede crearla', async () => {
    const direccion = testEnv.authenticatedContext('dir1').firestore();
    await assertSucceeds(
      direccion.collection('sesionesEstudio').doc('asistencia_alumno1_guitarra_2026-01-05').set(sesion)
    );
  });

  it('un profesor que NO enseña esa asignatura no puede crearla', async () => {
    const profesorB = testEnv.authenticatedContext('profesorB').firestore();
    await assertFails(
      profesorB.collection('sesionesEstudio').doc('asistencia_alumno1_guitarra_2026-01-05').set(sesion)
    );
  });

  it('rechaza marcarla como origenAsistencia sobre una asignatura sin permiteGrabarEstudio', async () => {
    await conDatosDePrueba(async (db) => {
      await db.collection('asignaturas').doc('armonia').set({
        cursoId: 'curso1',
        nombre: 'Armonía',
        nombreNormalizado: 'armonía',
        profesorIds: ['profesorA'],
        permiteGrabarEstudio: false,
      });
      await db.collection('gruposAsignatura').doc('armonía').set({ profesorIds: ['profesorA'] });
    });
    const profesorA = testEnv.authenticatedContext('profesorA').firestore();
    await assertFails(
      profesorA.collection('sesionesEstudio').doc('asistencia_alumno1_armonia_2026-01-05').set({
        ...sesion,
        asignaturaId: 'armonia',
      })
    );
  });

  it('el profesor de la asignatura puede borrarla (p.ej. al marcar "faltó")', async () => {
    await conDatosDePrueba(async (db) => {
      await db.collection('sesionesEstudio').doc('asistencia_alumno1_guitarra_2026-01-05').set(sesion);
    });
    const profesorA = testEnv.authenticatedContext('profesorA').firestore();
    await assertSucceeds(
      profesorA.collection('sesionesEstudio').doc('asistencia_alumno1_guitarra_2026-01-05').delete()
    );
  });

  it('un alumno NO puede crear la sesión sintética de OTRO alumno', async () => {
    await conDatosDePrueba(async (db) => {
      await db.collection('usuarios').doc('alumno2').set({ permisos: ['alumno'] });
    });
    const alumno2 = testEnv.authenticatedContext('alumno2').firestore();
    await assertFails(
      alumno2.collection('sesionesEstudio').doc('asistencia_alumno1_guitarra_2026-01-05').set(sesion)
    );
  });
});
