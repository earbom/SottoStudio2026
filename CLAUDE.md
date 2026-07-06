# Contexto del proyecto para Claude Code

Este archivo existe para que cualquier sesión de Claude Code en este repo
tenga el contexto de negocio sin que haya que repetirlo. Léelo antes de
proponer cambios de arquitectura o de modelo de datos.

## Qué es esto

Sotto Studio: app para que **Centre d'Estudis Musicals Haro** sepa cuánto
estudian de verdad sus alumnos en casa. Un año atrás el proyecto se hizo
en Java/Android + Room + MySQL (ver `entregafinal.pdf` si está en el
repo); se ha decidido migrar a **Flutter + Firebase** para cubrir
Android, iOS y macOS (el Mac lo usa dirección) con una sola base de
código, y porque los datos de un alumno deben llegar a su profesor y a
dirección — un almacén local en el centro no sirve.

## Reglas de negocio que NO deben romperse

1. **Nunca se guarda audio.** Solo se lee la amplitud del micrófono en
   tiempo real. El archivo temporal que exige la API de grabación se
   borra siempre al detener (ver `GrabadorEstudio.detener()`). Esto es
   innegociable por RGPD — hay menores de edad implicados.

2. **Lógica de 3 estados para el tiempo efectivo** (ya implementada en
   `lib/services/grabador_estudio.dart`, no reinventar):
   - Tocando (amplitud > umbral) → efectivo.
   - Silencio ≤ 4 segundos rodeado de música → efectivo (se recupera
     retroactivamente cuando el sonido vuelve).
   - Silencio > 4 segundos → no efectivo, pero sí cuenta en el tiempo
     total de la sesión.
   - Cada sesión guarda `duracionTotalMs` y `duracionEfectivaMs` por
     separado; nunca colapsarlos en un solo campo.

3. **`umbralDb` es un valor de partida, no definitivo.** Requiere
   calibración con instrumentos reales durante el piloto. Criterio de
   aceptación: debe funcionar razonablemente con al menos 3 tipos de
   instrumento distintos. Si se toca esta lógica, dejar el umbral como
   parámetro configurable, nunca hardcodeado sin más.

4. **Tres roles, permisos estrictos** (reflejados en `firestore.rules`,
   que es la fuente de verdad — si se cambia el modelo de datos, las
   reglas se actualizan en el mismo cambio, no después):
   - **Alumno**: solo lee/escribe sus propias sesiones y ejercicios
     completados; solo lee sus propias notas.
   - **Profesor**: gestiona módulos/ejercicios, escribe notas (quedan
     en estado `pendiente`), solo lectura de sesiones de alumnos.
   - **Dirección**: única que puede pasar una nota a `supervisada` o
     `corregida`; ve el informe de horas efectivas de todos los
     alumnos ordenado de mayor a menor (vista clave de dirección).

5. **`estadisticasAlumno` no se escribe nunca desde el cliente.** Debe
   actualizarse vía Cloud Function al crearse un documento en
   `sesionesEstudio`, para que nadie pueda inflar su propio ranking
   editando Firestore desde la app. La Cloud Function ya existe
   (`functions/index.js`) pero **no está desplegada**: requiere plan
   Blaze y se ha decidido no activarlo hasta que el centro contrate el
   servicio en producción. Mientras tanto, `informeDireccion()` en
   `db_service.dart` agrega `sesionesEstudio` en el cliente como
   solución temporal de piloto — no reintroducir la lectura de
   `estadisticasAlumno` ahí hasta que la función esté desplegada.

## Nomenclatura de colecciones (fija, no renombrar sin avisar)

`usuarios`, `sesionesEstudio`, `modulos`, `ejercicios`,
`ejerciciosCompletados`, `notas`, `estadisticasAlumno`.

Evitar el nombre "Historial de Sesiones" para nada relacionado con
estudio: en la documentación original ese nombre se usaba para
sesiones de login, no de práctica musical, y crea confusión si reaparece.

## Cosas explícitamente descartadas (no reintroducir)

- Guardar rutas de archivo de audio (`ruta_archivo`) en cualquier colección.
- Publicidad en banner como fuente de ingresos (RGPD + menores).
- Dictados con pentagrama / ejercicios de oído tipo Perfect Ear:
  aplazados a v2.0 por falta de librería de renderizado de partitura
  viable en Flutter.
- Reproductor de audio con control de velocidad: aplazado a v2.0.

## Backlog conocido

- Pantallas: registro, historial de sesiones del alumno, ejercicios,
  ranking, gestión de módulos por el profesor, formulario de nota,
  listado de profesorado para dirección.
- Cloud Function de agregación de `estadisticasAlumno`.
- Migrar metrónomo (BPM 20-240, compases 2/4 3/4 4/4 6/8, acento en
  primer pulso, reloj absoluto para no desviar tempo) y afinador
  (autocorrelación normalizada, 55-2000 Hz, La4=440Hz, umbral de
  confianza 0.85) desde la versión Java/Android existente.
- Registro manual de estudio teórico con recordatorio pop-up (ya
  modelado como `TipoSesion.teorico` en `SesionEstudio`, falta la UI).
- Logo de la app: ver `brief_logo_sotto_studio.md`. El logo del centro
  (marca "oh" + "HARO ESTUDIS MUSICALS") ya existe y no se toca.
