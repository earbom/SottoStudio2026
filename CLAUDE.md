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

4. **Permisos combinables, no roles excluyentes** (reflejados en
   `firestore.rules`, que es la fuente de verdad — si se cambia el
   modelo de datos, las reglas se actualizan en el mismo cambio, no
   después). `Usuario.permisos` es un conjunto (`Set<Permiso>` en
   Dart, `List<String>` en Firestore), no un valor único: una cuenta
   puede tener `{direccion, profesor}` a la vez (p. ej. una directora
   que también da clase). El helper de reglas es
   `tienePermiso(permiso)` (`permiso in usuarioActual().permisos`),
   no una igualdad de string. El campo antiguo `rol` (single-value) ya
   no se usa — no reintroducirlo ni mantener lectura de fallback para
   él, la migración de las cuentas existentes ya se hizo a mano.
   - **Alumno**: solo lee/escribe sus propias sesiones y ejercicios
     completados; solo lee sus propias notas; solo ve sus propias
     matrículas y asistencias.
   - **Profesor**: gestiona módulos/ejercicios; solo puede marcar
     asistencia y crear notas de los **alumnos que dirección le ha
     asignado explícitamente** (`matriculas.profesorId`, ver punto 10 —
     no todos los alumnos de una asignatura donde figure en
     `profesorIds`, porque puede haber varios profesores con alumnos
     distintos), salvo sustitución temporal activa ese día; solo
     lectura de sesiones de alumnos.
   - **Dirección**: control total sobre `cursos`/`asignaturas`
     (crear/editar/eliminar) y sobre `matriculas` (matricular/dar de
     baja); única que puede pasar una nota a `supervisada` o
     `corregida`; única que puede crear cuentas de alumno desde la app
     (ver punto 6); ve el informe de horas efectivas de todos los
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

6. **`AuthService.crearAlumno()`/`crearProfesor()` son un workaround
   temporal, no una Cloud Function.** Ambos comparten el helper
   privado `_crearUsuarioConPermiso()`. Dirección puede dar de alta un
   alumno o un profesor (nombre, email real, contraseña temporal
   autogenerada) sin cerrar su propia sesión gracias a una
   `FirebaseApp` secundaria efímera que solo se usa para el alta en
   Firebase Auth; el documento `usuarios/{uid}` se escribe con la app
   primaria (autenticada como dirección; las reglas permiten a
   dirección crear cualquier doc en `usuarios`, con cualquier
   `permisos`). Asignar un profesor a asignaturas (`profesorIds`, una
   asignatura puede tener varios) es un paso aparte, desde el listado
   de profesorado (`DbService.asignarProfesorAAsignatura`, un
   `arrayUnion`/`arrayRemove`). Mismo caveat que el punto 5: cuando el
   centro contrate el plan Blaze, migrar esto a una Cloud Function
   invocable con Admin SDK y retirar el truco de la app secundaria.
   Crear cuentas de **dirección** sigue siendo manual por consola (no
   se ha pedido un formulario ágil para eso).

7. **El horario semanal (`diasSemana`) va en la MATRÍCULA, no en la
   asignatura.** Las clases de instrumento son casi siempre
   individuales: cada alumno tiene su propio día de clase dentro de la
   misma asignatura (p. ej. "Guitarra" con un alumno los lunes y otro
   los miércoles), así que un único horario por asignatura no sirve.
   `matriculas.diasSemana` (1=lunes..7=domingo, sin excepciones ni
   festivos — igual que la lógica de tiempo efectivo del punto 2, no
   reinventar) se fija al matricular y se puede editar después
   (`DbService.actualizarDiasClaseMatricula`). Para una asignatura
   grupal (teoría, conjunto...), simplemente se repiten los mismos
   días en la matrícula de cada alumno del grupo — no hace falta un
   modelo de horario a nivel de asignatura.

8. **IDs deterministas en `matriculas` y `asistencias`.**
   `matriculas/{alumnoId}_{asignaturaId}` y
   `asistencias/{alumnoId}_{asignaturaId}_{fecha}` (fecha en
   `'yyyy-MM-dd'`) para que matricular/marcar asistencia sea un
   `set(merge:true)` idempotente. Listar todas las asistencias de un
   alumno en una asignatura usa un rango de prefijo sobre
   `FieldPath.documentId()` en vez de una consulta con dos igualdades
   + `orderBy` (que exigiría un índice compuesto adicional) — depende
   de que `_` nunca aparezca en un uid de Firebase Auth ni en un id
   autogenerado de Firestore; no cambiar el separador sin comprobarlo.

9. **El peso de una nota lo define `criteriosEvaluacion`, no la nota
   en sí.** Dirección configura, por asignatura, una lista de
   criterios (`nombre` + `peso` en %, p. ej. "Control 1r trimestre"
   10%) desde `CriteriosEvaluacionScreen` (botón de icono en la cabecera
   de `AsignaturaDetalleScreen`, solo visible para dirección). El
   profesor, al poner una nota, elige uno de esos criterios
   (`Nota.criterioId`) y solo introduce el valor (0-10); el peso no se
   vuelve a teclear. La "nota ponderada acumulada" que se ve en la
   pestaña de notas de un alumno es `Σ(valor × peso/100)` sobre sus
   notas de esa asignatura — no asume que los pesos sumen 100% (se
   avisa en `CriteriosEvaluacionScreen` si no cuadra, pero no se
   bloquea: dirección puede estar a mitad de configurar el curso).

10. **Asignación alumno↔profesor y sustituciones temporales.** Una
    asignatura puede tener varios profesores (p. ej. dos de guitarra),
    cada uno con SUS alumnos, no todos: `matriculas.profesorId` fija
    qué profesor concreto puede poner notas/marcar asistencia de ese
    alumno (se configura al matricular o después, editable desde
    `AsignaturaDetalleScreen` → icono de calendario en cada fila, ver
    `_configurarMatricula` en ese archivo). Un profesor sin alumnos
    asignados en una asignatura simplemente no ve a nadie en su vista
    de esa asignatura (salvo sustitución, ver abajo). Para bajas del
    profesor habitual: dirección da de alta una **sustitución** desde
    el icono ⇄ en `AsignaturaDetalleScreen` (`SustitucionesScreen`),
    eligiendo un profesor (no hace falta que esté ya en `profesorIds`
    de la asignatura) y uno o varios días en un calendario — cada día
    genera un documento en `sustituciones` con ID determinista
    `${asignaturaId}_${profesorId}_${fecha}` (mismo patrón que
    `asistencias`, ver punto 8). Mientras dura la sustitución, ese
    profesor ve y puede puntuar/marcar asistencia de TODOS los alumnos
    de la asignatura ese día concreto (cubre a un sustituto dando la
    clase completa, no solo a los alumnos de un profesor en concreto).
    `firestore.rules` comprueba esto con `esProfesorAsignadoAlAlumno()`
    (get() a la matrícula) y `tieneSustitucion()` (exists() al doc de
    sustitución) — por eso `Nota` guarda también `fechaDia`
    (`'yyyy-MM-dd'`, derivado de `fecha` en `toMap()`, no es un campo
    propio del modelo Dart): las reglas no pueden formatear fechas,
    así que necesitan ese string ya listo para comparar con
    `sustituciones`.

11. **Metrónomo y afinador no tocan Firestore — son herramientas
    locales.** No guardan nada en la base de datos ni dependen de
    sesión/permisos; están accesibles a cualquier usuario logueado
    desde "Herramientas" en el menú lateral.
    - **Metrónomo** (`metronomo_service.dart`): BPM 20-240, compases
      2/4, 3/4, 4/4, 6/8 (acento siempre en el primer pulso) y figura
      de subdivisión por pulso (negra/corchea/tresillo/semicorchea).
      Usa reloj absoluto: cada tick se reprograma contra la hora
      objetivo calculada desde el inicio (`_inicio + tickIndex ×
      intervalo`), no un `Timer.periodic` de intervalo fijo — así no
      se acumula deriva en sesiones largas. No reinventar este
      esquema de temporización. Los sonidos son WAV sintéticos en
      `assets/audio/` (no hay grabaciones reales), reproducidos con
      `audioplayers` en `PlayerMode.lowLatency`.
    - **Afinador** (`afinador_service.dart`): igual que
      `GrabadorEstudio`, nunca guarda audio — captura PCM16 en
      streaming (`record.startStream`) solo para analizarlo en
      memoria. Detecta la frecuencia por autocorrelación normalizada
      sobre una ventana de 4096 muestras a 44100 Hz, referencia La4
      (A4) = 440 Hz, y un umbral de confianza de 0.85
      (`AfinadorService.umbralConfianza`): por debajo no se informa
      ninguna nota, para evitar falsos positivos con ruido de fondo.
      No relajar ese umbral sin recalibrar con instrumentos reales
      (mismo criterio de aceptación que `umbralDb`, ver punto 3).
      `frecuenciaMin`/`frecuenciaMax` (antes constantes fijas 55-2000
      Hz) son ahora campos de instancia modificables en caliente desde
      `AfinadorScreen` según el instrumento elegido — ver punto 22.

12. **Rangos de `Nota.valor` (0-10) y `CriterioEvaluacion.peso` (0-100)
    se validan en `firestore.rules`, no solo en la UI.** Antes solo
    los limitaba el formulario; alguien con acceso directo a la API
    podía escribir un valor disparatado. Si se añade un campo numérico
    nuevo con un rango de negocio, validarlo también en las reglas,
    no confiar solo en el cliente.

13. **Avisos in-app no son notificaciones push reales.** Una
    notificación de sistema (que llegue con la app cerrada) necesita
    una Cloud Function server-side que la dispare — sigue bloqueado
    por el plan Blaze, mismo caveat que los puntos 5 y 6. Mientras
    tanto, `InicioScreen` calcula avisos en el propio cliente al
    abrir la app (notas nuevas desde `usuarios.ultimaVisita`, días sin
    estudiar desde `historialAlumno()`) — no reintroducir la idea de
    "notificación push" sin plan Blaze activo.

14. **El ranking por asignatura nunca expone nombres de alumnos a
    otros alumnos.** Hay menores de edad implicados (ver punto 1).
    `RankingAsignaturaScreen` solo es accesible desde
    `AsignaturaDetalleScreen`, que en la práctica nunca abre un
    alumno (solo profesor/dirección la navegan) — aun así, el icono
    de acceso comprueba explícitamente `esDireccion() || esProfesor()`
    por si cambia la navegación. Un profesor solo ve el ranking de
    SUS alumnos asignados (reutiliza el mismo filtro por
    `matriculas.profesorId` que el listado de la asignatura), nunca
    los de otro profesor. No añadir una vista de ranking con nombres
    accesible desde el lado alumno.

15. **Registro horario de trabajadores (Art. 34.9 del Estatuto de los
    Trabajadores, introducido por el RD-ley 8/2019).** Aplica a
    cualquier cuenta con permiso `profesor` o `direccion` (los
    "trabajadores" del centro; un alumno nunca ficha). Normativa
    vigente comprobada en agosto de 2026: registro obligatorio de
    hora exacta de entrada/salida, conservación 4 años, acceso
    garantizado al propio trabajador, sus representantes y la
    Inspección de Trabajo — **sin exigir un formato concreto** (papel,
    hoja de cálculo o digital son válidos hoy). Hay una reforma en
    trámite que obligaría a un sistema exclusivamente digital y con
    acceso en tiempo real para Inspección, pero **no está aprobada**
    a fecha de hoy (el Consejo de Estado la objetó en marzo de 2026;
    Trabajo y Economía acordaron reprocesarla en septiembre de 2026)
    — revisar su estado antes de relajar las garantías de integridad
    de `marcajes` si se retoma este punto más adelante.
    - `horariosLaborales/{empleadoId}`: el propio trabajador configura
      sus turnos (día + hora entrada/salida) y los minutos de aviso
      antes de fichar; dirección puede ver/editar los de cualquiera.
    - `marcajes/{empleadoId}_{fecha}` (ID determinista, mismo patrón
      que `asistencias`/`sustituciones`): al fichar entrada se crea
      con `horaSalida: null`; al fichar salida se actualiza una única
      vez. **No editable por el trabajador una vez fichado**
      (`horaEntrada` inmutable, `horaSalida` solo de `null` a un
      valor) — solo dirección puede corregir, y siempre queda
      registrado quién y cuándo (`corregidoPor`/`corregidoEn`, ver
      `DbService.corregirMarcaje`). **Nunca se borra** (`allow delete:
      if false` en las reglas): la ley obliga a conservar 4 años.
    - El aviso "fichar en X minutos" es una notificación LOCAL
      (`RecordatorioFichajeService`, paquete `flutter_local_notifications`),
      no push del servidor — el trabajador conoce su propio horario de
      antemano, así que no hace falta Cloud Function/Blaze. Fiable en
      Android/iOS; "best effort" en la versión web (depende del
      soporte de notificaciones en segundo plano del navegador).
    - Exportación a Excel (`RegistroHorarioScreen`, paquetes `excel` +
      `file_saver`) es un informe derivado para enseñar a un
      inspector, no el registro en sí — la fuente de verdad son
      siempre los documentos de `marcajes` en Firestore.

16. **En `allow read` de un doc por ID determinista, comprobar
    `resource == null` ANTES de acceder a `resource.data`.** Bug real
    detectado en pruebas manuales (agosto 2026): al consultar un
    fichaje/asistencia/matrícula que todavía no existe (`.doc(id).get()`
    de un día sin marcar, caso normal), Firestore evalúa la regla
    igualmente con `resource == null`; acceder a `resource.data.X` ahí
    lanza un error de evaluación que el cliente ve como
    `permission-denied` — no como "no existe" — y deja la UI con la
    rueda de carga colgada para siempre (le pasó a `marcajes`,
    `asistencias` y `matriculas`, ver esos `match` para el patrón:
    `(estaAutenticado() && resource == null) || ...`). Cualquier
    colección nueva con lectura de un doc por ID determinista que
    pueda no existir aún debe llevar este mismo chequeo desde el
    principio; hay tests de regresión en `firestore-tests/rules.test.js`
    ("leer un documento que aún no existe no debe fallar").

17. **Horas objetivo son MENSUALES, por CURSO, no por asignatura ni por
    alumno.** `Curso.horasObjetivoMensual` (0 = sin objetivo, no se
    colorea nada) se fija al crear/editar el curso
    (`cursos_screen.dart`) — YA NO vive en `Asignatura` (se movió
    aquí; ver punto 29 sobre la jerarquía de cursos). Como
    `Asignatura.cursoId` ata cada asignatura a un único curso, el
    objetivo "de una asignatura" es simplemente el de su curso:
    `(await db.curso(asignatura.cursoId))?.horasObjetivoMensual`. Todo
    el rojo/verde de la app sale de comparar horas efectivas contra
    este valor:
    - `RankingAsignaturaScreen`: horas efectivas del **mes en curso**
      (no el histórico total) de cada alumno en esa asignatura frente
      al objetivo del CURSO de esa asignatura (resuelto vía
      `DbService.curso()`).
    - `DbService.informeDireccion()`: horas efectivas del mes en curso
      por alumno, frente al objetivo COMBINADO del alumno = suma de
      `horasObjetivoMensual` de los CURSOS DISTINTOS entre sus
      matrículas activas (no de las asignaturas — si el alumno tiene
      dos asignaturas del mismo curso, ese objetivo cuenta una sola
      vez, nunca dos). Campo `horasEfectivasMes` (no
      `horasEfectivasTotales`, no es un histórico).
    - `_TabEstadisticas` en `alumno_en_asignatura_screen.dart`: objetivo
      ANUAL = objetivo del curso de esa asignatura `× 12` (no se
      modela un calendario lectivo con meses sin clase) frente a las
      horas efectivas del **año en curso** en esa asignatura concreta;
      es la única vista "anual" de la app, el resto son mensuales.
    - Si se toca cualquiera de estos cálculos, mantener la distinción
      mes/año explícita en el nombre de la variable — ya se confundió
      una vez el histórico total con el del mes durante el diseño.

18. **`Asistencia.retraso`** (bool, `false` por defecto) solo tiene
    sentido cuando `asistio == true`: asistió pero llegó tarde. No es
    un tercer valor de `asistio` para no romper el resto de lógica
    (rankings, estadísticas, gráficas asistió/faltó) que ya asume
    booleano. Se marca con un tercer botón "Retraso" junto a
    "Asistió"/"Faltó", tanto en `_TabCalendario`
    (`alumno_en_asignatura_screen.dart`) como en los botones rápidos
    por fila de `_FilaMatricula` (`asignatura_detalle_screen.dart`).

19. **`Usuario` implementa igualdad por `uid`, no por identidad de
    objeto.** Imprescindible para cualquier
    `DropdownButtonFormField<Usuario>`/`DropdownButton<Usuario>` cuyos
    `items` vengan de un `StreamBuilder` en vivo (p. ej.
    `profesoresDelCentro()`): cada reemisión del stream crea instancias
    nuevas aunque los datos no cambien, y sin `==`/`hashCode` por `uid`
    Flutter no encuentra el valor seleccionado entre los nuevos
    `items` y lanza una excepción que tumbaba toda la pantalla (le
    pasó al selector de profesor sustituto en
    `SustitucionesScreen`). Si se añade otro modelo Dart mutable como
    valor de un dropdown alimentado por un stream, aplicar el mismo
    patrón desde el principio.

20. **Icono de asignatura: catálogo fijo en cliente, no texto libre.**
    `Asignatura.iconoId` (string, `''` = icono por defecto) es solo una
    clave hacia `iconosAsignaturaDisponibles`
    (`lib/utils/iconos_asignatura.dart`); el icono real
    (`FontAwesomeIcons`, paquete `font_awesome_flutter`) se resuelve
    siempre en cliente vía `iconoAsignaturaPorId()`, nunca se guarda un
    nombre de icono ad-hoc, para poder ampliar/reordenar el catálogo
    sin migrar documentos. Font Awesome Free no tiene glifos propios de
    viento ni de cuerda frotada (violín, trompeta...) — solo guitarra y
    batería entre instrumentos concretos — así que el resto del
    catálogo usa iconos musicales/de estudio genéricos a propósito, no
    es un olvido. Las asignaturas se muestran como cuadrícula de
    iconos tipo "escritorio" (`curso_detalle_screen.dart` para
    dirección, `dashboard_profesor_screen.dart` para profesor), no como
    lista.

21. **Pantalla de Ajustes (`ajustes_screen.dart` + `AjustesService`,
    mismo patrón `ChangeNotifier` + `shared_preferences` que
    `TemaService`).** Controla tamaño de letra (aplicado globalmente
    vía `TextScaler` en el `builder` de `MaterialApp`, `main.dart`) y
    tamaño de los iconos de asignatura (multiplicador que consumen las
    cuadrículas de `curso_detalle_screen.dart` y
    `dashboard_profesor_screen.dart`) — ambos persistidos localmente,
    no por cuenta de usuario ni sincronizados entre dispositivos. Si se
    añaden más preferencias de UI, van aquí, no en un servicio nuevo.

22. **Selector de instrumento y detección de cuerda en el afinador**
    (`lib/utils/instrumentos_afinador.dart` + `AfinadorScreen`). El
    catálogo (`instrumentosAfinador`) define, por instrumento, un rango
    `frecuenciaMin`/`frecuenciaMax` (acota `AfinadorService` a su
    tesitura real, mejora la detección y evita errores de octava) y
    una o varias `afinaciones` (cada una con su lista de notas
    objetivo). Cubre guitarra (con Drop D, media afinación, Open G,
    Open D y DADGAD además de la estándar), ukelele, violín, viola,
    violonchelo y contrabajo (con sus cuerdas reales) y, como nota de
    referencia habitual (no tienen "cuerdas"): flauta travesera, oboe,
    clarinete, fagot, trompa, trompeta, trombón, saxofón y tuba. La
    opción "Ninguno (cromático general)" mantiene el comportamiento
    anterior sin restricción de rango.
    - Todas las notas objetivo son de temperamento igual estándar (sin
      afinaciones microtonales/scordatura), así que identificar qué
      cuerda se está tocando NO requiere calcular cents contra una
      frecuencia objetivo aparte: basta con comparar la nota+octava ya
      detectada (`LecturaAfinador.nota`/`octava`) con la de cada
      `NotaObjetivo` de la afinación elegida (`_cuerdaCoincidente` en
      `afinador_screen.dart`) y reutilizar los `cents` que ya calcula
      `AfinadorService` respecto a la nota cromática más cercana. Si se
      añadiera alguna afinación no estándar (p. ej. un scordatura de
      violonchelo), este atajo dejaría de valer y sí haría falta
      calcular cents contra `NotaObjetivo.frecuencia`.

23. **La app de macOS se distribuye SIN App Sandbox, a propósito.**
    El centro no la publica en el Mac App Store (ver decisión de
    distribución: APK de Android colgado en un Drive compartido +
    PWA con icono en pantalla de inicio para iOS), así que
    `com.apple.security.app-sandbox` está a `false` en
    `macos/Runner/{DebugProfile,Release}.entitlements` — si estuviera
    a `true`, el acceso a una carpeta elegida por el usuario
    (`file_picker`) se revoca al reiniciar la app salvo que se
    implementen "security-scoped bookmarks" nativos, lo que rompería
    la exportación automática mensual descrita abajo. No reactivar el
    sandbox sin resolver antes ese mecanismo.
    - **Exportación automática de fichajes**
      (`ExportacionAutomaticaMarcajesService` +
      `lib/utils/excel_marcajes.dart`, este último también reutilizado
      por la exportación manual de `RegistroHorarioScreen`). Dirección
      elige una carpeta local desde Ajustes
      (`AjustesService.carpetaExportacionMarcajes`, guardada como ruta
      de texto plano — solo funciona porque el sandbox está
      desactivado, ver arriba). Al abrir la app (`HomeShell.initState`,
      solo si `esDireccion`), se comprueba si el mes anterior ya tiene
      Excel generado (`AjustesService.ultimaExportacionMarcajesMes`) y,
      si no, se genera con `dart:io` sin intervención del usuario. Es
      "best effort" (no hay tarea programada a nivel de sistema, ver
      alternativa de `launchd` descartada por complejidad): si dirección
      no abre la app justo tras cambiar de mes, se genera en cuanto la
      abra. No tiene efecto en web (`kIsWeb`) — la fuente de verdad
      sigue siempre siendo `marcajes` en Firestore (nunca se puede
      borrar, ver punto 15); esto es solo una copia de conveniencia.

24. **Cualquier estado de asistencia mostrado en pantalla debe venir de
    un stream, nunca de un fetch de un solo uso, si esa misma pantalla
    puede quedar montada debajo de otra que también lo modifique.**
    Bug real (agosto 2026): `_FilaMatricula` (fila de alumno en
    `AsignaturaDetalleScreen`) leía la asistencia de hoy una sola vez
    en `initState`; si se marcaba desde el calendario del detalle del
    alumno (`AlumnoEnAsignaturaScreen`, pantalla distinta pero la fila
    de abajo seguía viva en la pila de navegación) y se volvía atrás,
    la fila mostraba el valor antiguo indefinidamente. Arreglado con
    `DbService.asistenciaDelDiaStream()` (`.snapshots()` en vez de
    `.get()`) suscrito en `initState`/cancelado en `dispose`. Mismo
    principio que ya aplica al resto de la app vía `StreamBuilder`; el
    error fue usar un `Future` puntual en una fila que puede convivir
    con otra pantalla que escribe el mismo documento.
    - Bug relacionado, mismo caso: los tres botones de asistencia de
      `_TabCalendario` no reflejaban cuál era el estado activo —
      "Asistió" usaba `FilledButton` (aspecto "presionado" fijo,
      viniera o no de una selección real) y "Retraso"/"Faltó" usaban
      `OutlinedButton` (aspecto "sin marcar" fijo), así que el que
      parecía activo NO dependía en absoluto del estado real, solo
      del tipo de widget elegido para cada uno. El texto de arriba
      (`_textoAsistencia()`) sí era correcto — daba una falsa
      impresión de "bug de datos" cuando en realidad era puramente
      visual. Arreglado con `_botonEstadoAsistencia()`, que alterna
      `FilledButton`/`OutlinedButton` según el estado real (mismo
      patrón que `_botonAsistencia()` de `_FilaMatricula`). Si se
      añade un grupo de botones "elige uno de varios estados"
      en cualquier otra pantalla, ese estado activo debe decidirse
      así, nunca fijando el tipo de widget por posición.

25. **Una consulta (`.where(...)`/rango de ID) que no incluya como
    igualdad exacta el campo del que depende una regla de permisos NO
    es "provably compliant" para Firestore, y la rechaza entera con
    `permission-denied`.** Bug real (agosto 2026):
    `asistenciasDeAlumnoEnAsignatura()` usaba un rango de prefijo sobre
    el ID del documento (`orderBy(FieldPath.documentId)` +
    `startAt`/`endAt`) para evitar un índice compuesto — pero la regla
    de lectura de `asistencias` para profesor depende de
    `resource.data.asignaturaId` (`esProfesorDeAsignatura`), y Firestore
    no puede demostrar en tiempo de planificación que un rango de ID
    garantiza esa condición sobre un campo. Para dirección (regla
    `esDireccion()`, no depende de `resource.data`) la misma consulta
    colaba sin problema, lo que hizo el fallo invisible hasta que un
    profesor abrió "Estadísticas" del detalle de un alumno — pantalla
    que se quedaba cargando para siempre porque el `FutureBuilder` solo
    comprobaba `snapshot.hasData`, no `snapshot.hasError` (añadir
    siempre esa comprobación en cualquier `FutureBuilder`/`StreamBuilder`
    que dependa de una consulta con reglas condicionadas por rol, para
    que un fallo similar se vea en pantalla en vez de colgarse en
    silencio). Arreglado sustituyendo el rango de prefijo por dos
    igualdades (`alumnoId` + `asignaturaId`, sin `orderBy` adicional —
    Firestore resuelve varias igualdades con sus índices automáticos de
    un solo campo, sin necesitar índice compuesto). Si se añade otra
    consulta por rango/prefijo para "ahorrarse" un índice, comprobar
    primero que el campo relevante para las reglas de cada rol no
    autorizado por una condición "siempre true" (como `esDireccion()`)
    aparece como igualdad explícita en el `where` de la consulta.

26. **Discriminación por curso escolar** (p.ej. "2025-2026"; formato con
    guion, no barra — una barra en `cursoEscolar` rompería los IDs
    deterministas de Firestore donde se usa, ver
    `lib/utils/curso_escolar.dart`). A partir del segundo año de uso del
    piloto, las asignaturas empiezan a acumular alumnos de cursos
    escolares distintos; hacía falta poder distinguirlos.
    - **`configuracion/centro`** (documento único): `cursoEscolarActivo`
      + `historialCursosEscolares` (array). Lectura abierta, solo
      dirección escribe, nunca se borra. `DbService.cursoEscolarActivo()`/
      `historialCursosEscolares()`/`avanzarCursoEscolar()`. Pantalla de
      gestión: `curso_escolar_screen.dart` (avanzar de curso no borra el
      anterior, solo lo archiva en el historial).
    - **`Matricula.idPara` pasa a `{alumnoId}_{asignaturaId}_{cursoEscolar}`**
      (antes solo `{alumnoId}_{asignaturaId}`, un único documento para
      siempre): permite que un alumno tenga una matrícula distinta de la
      misma asignatura en cada curso escolar, en vez de que el
      `set(merge:true)` del año siguiente reescriba la del anterior.
      Todos los métodos de matrícula en `DbService` (`matricular`,
      `actualizarDiasClaseMatricula`, `actualizarProfesorMatricula`,
      `desmatricular`, `matricula()`, `matriculasDeAlumno`,
      `matriculasDeAsignatura`, `todasLasMatriculasActivas`) llevan
      `cursoEscolar` como parámetro obligatorio.
    - **`Asistencia`/`Nota` llevan `cursoEscolar` denormalizado en
      `toMap()`** (igual que `Nota.fechaDia`), derivado automáticamente
      de su propia `fecha` vía `cursoEscolarDeFecha()` — NO se pasa como
      parámetro explícito ni se lee de vuelta en `fromMap` (no es un
      campo del modelo Dart, solo para que `firestore.rules` pueda
      construir el ID de matrícula correcto en
      `esProfesorAsignadoAlAlumno(alumnoId, asignaturaId, cursoEscolar)`
      sin depender de qué curso esté marcado como "activo" en ese
      instante). Más robusto que atarlo al curso activo: si dirección
      tarda en avanzar de curso, el registro sigue clasificado por su
      fecha real.
    - **Pantallas con selector de curso escolar** (activo por defecto,
      consulta de años anteriores en modo SOLO LECTURA — se ocultan
      matricular/editar matrícula/botones rápidos de asistencia cuando
      el curso mostrado no es el activo): `asignatura_detalle_screen.dart`,
      `ranking_asignatura_screen.dart`, `informe_direccion_screen.dart`.
      `dashboard_alumno_screen.dart` y `curso_detalle_screen.dart` (al
      matricular) SIEMPRE usan el curso activo, sin selector — un alumno
      ve su matrícula actual, no gestiona históricos.
    - **Alcance deliberadamente NO cubierto todavía**: las estadísticas
      de horas (mensual/anual, punto 17) siguen basándose en mes/año de
      calendario, no en el rango de curso escolar (septiembre-agosto).

27. **Cuadro de honor**: ranking GLOBAL (no por asignatura) de horas
    efectivas de estudio de INSTRUMENTO (no teórico) del mes en curso,
    con nombre del alumno — a diferencia del ranking por asignatura
    (punto 14, solo profesor/dirección por privacidad de menores), este
    es visible también para alumnos: **excepción deliberada y distinta**
    del punto 14, decidida explícitamente por dirección. Requiere
    ampliar la lectura de `sesionesEstudio` para que cualquier alumno
    pueda leer sesiones de tipo `'instrumento'` de OTROS alumnos (fecha
    y duración exactas, no la asignatura) — las de tipo `'teorico'`
    siguen siendo privadas. `DbService.cuadroDeHonorMensual()` (mismo
    patrón de agregación en cliente que `informeDireccion()`, temporal
    hasta Cloud Functions). Pantalla `cuadro_de_honor_screen.dart`,
    accesible a cualquier permiso desde "Herramientas".

28. **Boletín de notas en PDF** (paquetes `pdf` + `printing`, nuevos):
    solo accesible por dirección, desde su lista de Alumnos (antes no
    era pulsable) → `alumno_perfil_screen.dart` (asignaturas
    matriculadas en el curso escolar activo) → diálogo de checklist para
    elegir cuáles incluir → `lib/utils/boletin_pdf.dart` construye el
    PDF reutilizando el mismo cálculo de nota ponderada
    (Σ valor × peso/100) que `_TabNotas`, filtrando notas por su
    `fecha` dentro del rango del curso escolar elegido (no
    necesariamente el activo). Se muestra con `Printing.layoutPdf`
    (diálogo nativo de ver/imprimir/guardar).

29. **Jerarquía de cursos**: `Curso.nivel` (enum `NivelCurso`:
    `sensibilizacion`/`elemental`/`avanzado`/`libre`, en
    `lib/models/curso.dart`) + `numeroCurso` (`int?`; el desplegable de
    `cursos_screen.dart` se filtra con `nivel.numerosValidos` —
    sensibilización ofrece 2-4 sin el 1º, elemental/avanzado 1-4,
    libre no muestra el desplegable y deja `numeroCurso` en `null`) +
    `iconoId` (mismo catálogo que `Asignatura`, ver punto 30).
    `cursos_screen.dart` sugiere el nombre automáticamente al elegir
    nivel/número (p. ej. "2º Sensibilización") pero sigue siendo
    editable a mano — deja de re-sugerir en cuanto el usuario edita el
    campo Nombre directamente (flag `nombreAutomatico` interno al
    diálogo). `CursosScreen` pasa de lista a la misma cuadrícula de
    iconos que ya usaban las asignaturas (mismo
    `SliverGridDelegateWithMaxCrossAxisExtent`, reutiliza
    `escalaIconos` de `AjustesService`).

30. **Catálogo de iconos ampliado y compartido entre `Asignatura` y
    `Curso`** (`lib/utils/iconos_asignatura.dart`): añadidos 9 iconos
    pensados para conservatorio (interpretación, percusión corporal,
    historia de la música, técnica/producción, acústica/electrónica,
    clase colectiva, composición, análisis musical, dinámica) sobre
    los que ya había. El array `iconosAsignaturaDisponibles` es ahora
    también la fuente de `Curso.iconoId`, no solo de
    `Asignatura.iconoId` — un único catálogo, sin duplicar constantes.
    - **Icono de piano** (reportado durante el piloto: el icono
      `'teclado'` de entonces, `FontAwesomeIcons.solidKeyboard`, es un
      teclado de ORDENADOR, no un piano — Font Awesome Free no tiene
      un glifo de piano de verdad). Añadido `IconoAsignatura('piano',
      'Piano', FaIconData(Icons.piano))`: `Icons.piano` es un icono de
      Material (incluido en Flutter, sin dependencia nueva) envuelto
      en `FaIconData` para poder seguir usando `FaIcon` en todo el
      código sin cambios — `FaIcon` solo pinta el `IconData` que
      recibe (ver `FaIconData.data`/`FaIcon.build`), no exige que sea
      un glifo de Font Awesome, así que mezclar Material y Font
      Awesome en el mismo catálogo es válido. El antiguo `'teclado'`
      se mantiene tal cual (mismo `id`, no se ha migrado ningún dato)
      pero con la etiqueta corregida a solo "Teclado", ya que "Piano"
      ahora es una entrada aparte.

31. **Agrupación por curso en Cuadro de honor, Alumnos e Informe de
    horas.** Las tres vistas resuelven alumno→curso con el mismo
    helper compartido `DbService.cursosPorAlumno({required
    cursoEscolar})` (matrícula activa → `asignatura.cursoId` → `Curso`,
    devuelve `Map<alumnoId, List<Curso>>` porque un alumno puede tener
    asignaturas de varios cursos a la vez — aparece en CADA grupo
    correspondiente, no solo en el primero). Un alumno sin matrícula
    activa ese curso escolar cae en un grupo "Sin matricular" al
    final. Grupos ordenados por `nivel.index` y luego `numeroCurso`.
    - `CuadroDeHonorScreen` gana un `SegmentedButton` de 3 modos:
      Global (como antes), Por curso (usa el helper de arriba) y Por
      instrumento (agrupa en el propio widget por `Usuario.instrumento`,
      sin tocar `DbService`).
    - `AlumnosScreen` e `InformeDireccionScreen` agrupan del mismo
      modo. De paso, `InformeDireccionScreen` dejó de mostrar el
      `alumnoId` crudo (arrastraba un `// TODO: resolver nombre real`
      desde la tanda del piloto) y ahora resuelve el nombre real vía
      `DbService.obtenerUsuario`.

32. **Fichaje olvidado: autoinforme del trabajador + validación de
    dirección.** Antes solo dirección podía arreglar un día sin
    fichar (`corregirMarcaje`, ver punto 15). Ahora el propio
    trabajador puede autoinformar un día PASADO sin ningún marcaje
    (`DbService.reportarOlvidoMarcaje`, botón "¿Olvidaste fichar otro
    día?" en `FichajesScreen`): crea el doc con `pendienteValidacion:
    true` y entrada+salida ya puestas de una vez — falla si ya existe
    un marcaje ese día, aunque sea parcial, porque un marcaje ya
    fichado sigue siendo inmutable para el propio trabajador (mismo
    principio del punto 15, no una excepción). Dirección lo revisa
    desde `RegistroHorarioScreen` (filas con `pendienteValidacion`
    resaltadas en naranja con icono de reloj de arena, acción "Revisar
    y validar" en vez de "Corregir" en el mismo diálogo de siempre) y
    llama a `DbService.validarMarcaje()`, que apaga
    `pendienteValidacion` y deja igualmente registrado
    `corregidoPor`/`corregidoEn` (misma trazabilidad que una
    corrección normal — nunca se sobrescribe en silencio). En
    `firestore.rules`, `allow create` de `marcajes` gana una segunda
    rama para este caso (`pendienteValidacion == true && horaSalida !=
    null`), junto a la ya existente del fichaje normal (`horaSalida ==
    null`) — tests de regresión en `firestore-tests/rules.test.js`
    ("un profesor puede autoinformar...", "...NO puede autoinformar de
    otro", fichaje normal sigue funcionando).

33. **Navegación: botón flotante "volver al menú" centralizado.**
    Reportado como "a veces no se puede volver al menú principal, hay
    que ir pulsando atrás". `lib/services/navegacion_observer.dart`
    (`NavegacionObserver extends NavigatorObserver`) trackea la
    profundidad de navegación de TODA la app en un
    `ValueNotifier<int>` — la app usa un único `Navigator` raíz, sin
    Navigators anidados, así que un solo observer basta.
    `previousRoute == null` identifica el push inicial de la ruta
    "home" al arrancar (no cuenta como profundidad). `main.dart`
    registra el observer + un `GlobalKey<NavigatorState>` en el
    `MaterialApp` y superpone, vía su `builder:`, un
    `FloatingActionButton.small` en la esquina inferior IZQUIERDA
    (para no chocar con los FABs ya existentes de cada pantalla) que
    solo aparece cuando la profundidad es > 0 y hace
    `popUntil((r) => r.isFirst)` al pulsarlo. Cambio centralizado en
    un solo sitio — no se ha tocado el AppBar de cada pantalla
    individual.

34. **Idioma: infraestructura completa, traducción PARCIAL a
    propósito.** `flutter_localizations` (SDK) + ARB
    (`lib/l10n/app_es.arb` plantilla / `app_ca.arb`, `l10n.yaml` en la
    raíz, `flutter gen-l10n` genera `lib/l10n/app_localizations*.dart`
    — **no editar esos generados a mano, tocar los `.arb` y
    regenerar**). `AjustesService.idioma` (`Locale` persistida en
    `shared_preferences`, default `es`) + selector `SegmentedButton`
    en `AjustesScreen`; `main.dart` conecta `locale`/
    `supportedLocales`/`localizationsDelegates` al `MaterialApp`.
    **Solo están traducidas 6 pantallas** (decisión deliberada,
    confirmada con el usuario — no un olvido, no las traduzcas todas
    de golpe sin que te lo pidan): `login_screen.dart`, el menú
    lateral completo de `home_shell.dart`, `inicio_screen.dart`,
    `fichajes_screen.dart` (incluida la configuración de horario y el
    autoinforme de olvido del punto 32), `grabar_estudio_screen.dart`
    y `ajustes_screen.dart` (incluido el propio selector de idioma).
    El resto de la app se ve siempre en castellano sea cual sea
    `idioma` — queda pendiente de traducir en una tanda futura, no
    intentar "completarlo" sin que se pida explícitamente. Los nombres
    de alumnos/profesores nunca pasan por `AppLocalizations` (son
    datos interpolados como parámetro, p. ej. `inicioSaludo({nombre})`,
    no texto de UI); "Sotto Studio" y "Haro Estudis Musicals" tampoco
    se traducen (nombres propios).

35. **`curso_escolar_screen.dart`: el texto "Curso escolar activo" se
    cambió a "Activo actualmente"** porque, junto al `AppBar` que ya
    dice "Curso escolar" justo encima, se leía como duplicado. No era
    un bug de renderizado ni de datos (no había ninguna marquesina
    repetida de verdad) — solo redacción.

36. **Cursos ordenados, no en orden de inserción.**
    `DbService.cursos()` ordena por `nivel.index` y luego
    `numeroCurso` (sensibilización → elemental → avanzado → libre); a
    igualdad, por nombre. `DbService.asignaturasDeCurso()` ordena por
    nombre (una asignatura no tiene nivel/número propio — todas las de
    ese stream comparten el mismo curso). El orden se fija en
    `DbService`, no en cada pantalla, para que cualquier consumidor
    del stream (la cuadrícula de `CursosScreen`, la de
    `CursoDetalleScreen`, etc.) lo herede automáticamente.

37. **Bloqueo de cursos duplicados.** `CursosScreen` no dejaba crear
    dos veces "el mismo" curso — reportado tras probar la app.
    `_esCursoDuplicado()` (privado a `cursos_screen.dart`) considera
    duplicado un curso si coincide nivel+número con otro ya existente
    (dos "2º Elemental" no tienen sentido — para nivel `libre`, que no
    tiene número, se compara por nombre) o si el nombre coincide
    literalmente (por si se ha editado a mano). Es una validación de
    UX en el cliente, no en `firestore.rules`: `cursos` usa IDs
    autogenerados, así que las reglas no pueden comprobar "¿ya existe
    un doc con este nombre?" sin conocer su ID de antemano — no
    reintroducir esa idea en las reglas. Al editar, el propio curso se
    excluye de la comprobación (`idExcluido`).

38. **Marca "oh" del centro como logo de la app** (ver
    `brief_logo_sotto_studio.md`): dos assets de fondo sólido —
    `assets/images/logo_oh_fondo_blanco.png` (blanco/letras negras) y
    `logo_oh_fondo_negro.png` (negro/letras blancas) — envueltos en el
    widget compartido `LogoOh` (`lib/widgets/logo_oh.dart`,
    `sobreFondoOscuro` elige el asset, esquinas redondeadas vía
    `ClipRRect` para que lea como icono de app). A diferencia del
    wordmark completo (`cropped-Haro-...png`, fondo transparente +
    `ColorFiltered` en `InicioScreen`), aquí no hace falta recolorear:
    los dos assets ya vienen resueltos. Colocado en los sitios
    habituales para un logo de marca en este tipo de apps: pantalla de
    login (encima del texto "Sotto Studio", variante según
    `Theme.of(context).brightness`), y en `home_shell.dart` — cabecera
    del Drawer y `AppBar` principal, ambos con fondo
    `colorScheme.primary` (burdeos). Ahí se usa la variante
    `fondo_blanco` (por defecto, `sobreFondoOscuro: false`) a
    propósito y no la de fondo negro: el resto de iconos/texto de esa
    barra ya son blancos sobre burdeos (`onPrimary`), así que un
    badge blanco combina con ese lenguaje visual — un badge negro
    desentonaría como el único elemento oscuro de la barra. Si cambia
    el color de marca (`colorMarca` en `lib/tema.dart`) y deja de ser
    oscuro, reconsiderar qué variante combina mejor en esos dos sitios.

39. **Build de Android (`flutter build apk --release`): dos ajustes
    necesarios que no venían de fábrica**, descubiertos al generar el
    primer APK real para probar en los móviles del piloto (antes solo
    se había verificado web/macOS).
    - `android/app/build.gradle.kts` necesita
      `compileOptions.isCoreLibraryDesugaringEnabled = true` +
      `dependencies { coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4") }`:
      lo exige `flutter_local_notifications` (recordatorio de fichaje,
      punto 15) en Android; sin esto, `checkReleaseAarMetadata` falla
      con "requires core library desugaring to be enabled".
    - `file_picker` está **pinnado a `10.3.10`** en `pubspec.yaml`
      (NO `^11.x`), y `ajustes_screen.dart` usa
      `FilePicker.platform.getDirectoryPath(...)` (instancia, no
      estático — la API cambió entre 10.x y 11.x). Versiones 11.0.0 a
      11.0.3 (la última en pub.dev a fecha de este cambio) tienen un
      bug conocido: el propio módulo Android del paquete no aplica el
      plugin de Kotlin, así que `GeneratedPluginRegistrant.java` no
      encuentra `FilePickerPlugin` al compilar en modo release
      ("cannot find symbol" — ver
      github.com/miguelpruivo/flutter_file_picker/issues/1973, sin
      fix publicado todavía). Añadir `id("org.jetbrains.kotlin.android")`
      al `build.gradle.kts` de la propia app NO lo arregla (Flutter
      avisa explícitamente en contra de eso, "Built-in Kotlin") — la
      única solución que funcionó fue bajar de versión. Antes de
      volver a subir `file_picker`, comprobar que el issue de arriba
      esté cerrado con una versión publicada.

40. **Metrónomo: sonido silencioso en Android** (reportado durante el
    piloto — el pulso visual funcionaba pero no sonaba nada, sin
    ningún error). Causa: `PlayerMode.lowLatency` (SoundPool) de
    `audioplayers` tiene un bug conocido y recurrente en Android con
    `AssetSource` — no suena y no lanza excepción (ver
    github.com/bluefireteam/audioplayers/issues/1193, sigue
    reproduciéndose en audioplayers 6.8.1, versión ya reciente).
    `metronomo_service.dart` (`_PoolSonido.preparar`) usa
    `PlayerMode.mediaPlayer` específicamente en Android
    (`defaultTargetPlatform == TargetPlatform.android`, comprobado con
    `!kIsWeb` antes para no acceder a esa constante en web) y mantiene
    `lowLatency` en el resto de plataformas, donde sí funciona sin
    problemas — no relajar esto a "mediaPlayer en todas partes" porque
    el pool rotatorio de reproductores (ver comentario en el propio
    archivo) existe precisamente para poder usar `lowLatency` con
    tempos altos donde sí está disponible.
    - **Segunda vuelta** (probado en un móvil Android real tras el
      cambio anterior): sonaban "algunos bips sueltos" en vez de
      silencio total, pero seguía sin sonar como debía. Causa
      adicional: a diferencia de SoundPool, `resume()` sobre un
      `AudioPlayer` en modo `mediaPlayer` NO reinicia el clip a 0 si
      ya había terminado de sonar — retoma desde donde se quedó, es
      decir, desde el final (silencio), así que solo sonaba la
      primera vez que cada reproductor del pool rotatorio se usaba.
      Arreglado añadiendo `seek(Duration.zero)` antes de cada
      `resume()`, pero SOLO en Android (`_PoolSonido._esAndroid`): en
      el resto de plataformas, intercalar `seek()` reintroduce la
      condición de carrera en el backend web ("Bad state: No
      element") que el pool rotatorio ya evita sin necesidad de
      `seek()` — ver el comentario de la clase `_PoolSonido`, no
      quitar esa distinción por plataforma.

41. **Grabar estudio: solo en asignaturas de instrumento, nunca
    "libre".** Antes cualquier asignatura matriculada (incluida una
    teórica como Armonía) dejaba grabar sesiones de estudio, y además
    existía un botón "Grabar estudio libre" sin asignatura — ambos
    reportados como incorrectos durante el piloto: las horas
    registradas deben corresponder estrictamente a una asignatura de
    instrumento concreta.
    - `Asignatura.permiteGrabarEstudio` (bool, `false` por defecto):
      lo activa dirección por asignatura desde
      `curso_detalle_screen.dart` (`SwitchListTile` en el formulario
      de crear/editar asignatura) — pensado para instrumento, pero es
      dirección quien decide, no una detección automática. **Las
      asignaturas creadas antes de este cambio no tienen el campo, así
      que se quedan sin permiso** hasta que dirección entre a
      editarlas y active el switch una por una — no es un bug nuevo,
      es la migración esperada.
    - `dashboard_alumno_screen.dart`: el botón "Grabar estudio" de
      cada tarjeta de asignatura solo aparece si
      `asignatura.permiteGrabarEstudio`; se ha eliminado por completo
      el ListTile "Grabar estudio libre" (práctica sin asignatura).
    - `GrabarEstudioScreen.asignaturaId` pasa de opcional a
      **obligatorio** — ya no hay ningún punto de entrada que grabe
      sin asignatura.
    - `firestore.rules` (`sesionesEstudio`, `allow create`): además de
      `alumnoId == request.auth.uid`, ahora exige
      `asignaturaId` presente y que
      `get(.../asignaturas/$(asignaturaId)).data.permiteGrabarEstudio == true`
      — refuerzo en servidor, no solo ocultar el botón en el cliente
      (mismo criterio que CLAUDE.md punto 12). Las sesiones antiguas
      con `asignaturaId == null` (antes de este cambio) no se tocan,
      la condición solo aplica a creaciones nuevas — sigue siendo
      válido leerlas (ver nomenclatura de colecciones). Tests de
      regresión en `firestore-tests/rules.test.js`.

42. **Cuadro de honor: colgado indefinidamente para un alumno**
    (reportado durante el piloto probando como alumno por primera vez
    — hasta entonces solo se había probado como profesor/dirección).
    Dos bugs de reglas superpuestos, mismo patrón de fondo que CLAUDE.md
    punto 25 ("un rol sin condición enmascara el fallo de un rol con
    condición"):
    - `DbService.cuadroDeHonorMensual()` consultaba
      `sesionesEstudio` SIN `where('tipo', isEqualTo: 'instrumento')`
      (el filtro se aplicaba después, en Dart, con un `continue`). La
      regla de lectura para alumno exige esa condición sobre
      `resource.data.tipo`; una consulta que no la incluye como
      igualdad explícita no es "provably compliant" y Firestore la
      rechaza ENTERA con `permission-denied` para alumno (aunque cada
      documento individual sí fuera legible) — para profesor/dirección
      la regla no depende de esa condición, así que nunca se detectó
      antes. Arreglado moviendo el filtro al propio `.where()` de la
      consulta.
    - Aun con eso arreglado, la función resolvía el nombre de cada
      alumno del ranking con `obtenerUsuario()` — pero un alumno NO
      puede leer el documento `usuarios` de OTRO alumno (esa regla
      sigue restringida a `esPropioUsuario() || esProfesorODireccion()`,
      no se ha relajado). Arreglado denormalizando `alumnoNombre` en
      el propio documento de `sesionesEstudio` al grabarlo
      (`DbService.guardarSesion`, mismo patrón que
      `Nota.fechaDia`/`cursoEscolar`): `cuadroDeHonorMensual()` ya no
      necesita leer `usuarios` de nadie más. El tipo de retorno pasó
      de `List<({Usuario alumno, ...})>` a un record con
      `alumnoId`/`alumnoNombre`/`instrumento` planos (este último
      también ya venía en la sesión, no hizo falta denormalizar nada
      nuevo para el modo "Por instrumento").
    - El modo "Por curso" del `SegmentedButton` de
      `CuadroDeHonorScreen` usa `DbService.cursosPorAlumno()`, que lee
      `matriculas` de TODOS los alumnos — acceso que las reglas solo
      dan sin condición a `esDireccion()` (ver punto 31, las otras
      pantallas que usan ese helper ya estaban gateadas a dirección en
      el menú). Ese modo se oculta ahora del `SegmentedButton` salvo
      que `perfil.esDireccion` — `CuadroDeHonorScreen` pasó a requerir
      `perfil` (antes no lo recibía). Tests de regresión (incluida una
      consulta real sin filtro que debe fallar, para que el bug no
      reaparezca en silencio) en `firestore-tests/rules.test.js`.

43. **Calendario de asignatura: el aviso de "no es día de clase" no
    debe sonar a "no se registra estudio ese día".** `_TabCalendario`
    en `alumno_en_asignatura_screen.dart` ya mostraba las horas de
    estudio del día seleccionado sin restricción alguna (el
    `_esDiaDeClase` solo condiciona la sección de ASISTENCIA, nunca
    ocultó las horas) — pero el aviso "Este día no corresponde a un
    día de clase de esta asignatura" en días fuera de
    `matriculas.diasSemana` se leía como si tampoco se pudiera
    estudiar ese día, cuando el estudio en casa es válido cualquier
    día de la semana (solo la asistencia presencial está atada al
    horario de clase). Se reformuló el texto para dejar explícito que
    solo afecta a marcar asistencia. No fue necesario tocar ninguna
    lógica de datos, era puramente de redacción — mismo tipo de falso
    positivo que el punto 35 (marquesina "duplicada" de curso escolar).

44. **Icono de la app en todas las plataformas: marca "oh", variante
    fondo negro/letras blancas.** Generado con el paquete
    `flutter_launcher_icons` (dev dependency) desde
    `assets/icon/app_icon.png` — una versión CUADRADA de
    `assets/images/logo_oh_fondo_negro.png` (el original es 1122×804,
    no cuadrado; se rellenó a 1122×1122 con `sips -p ... --padColor
    000000`, relleno negro seamless porque el fondo del logo ya es
    negro sólido, sin recortar ni deformar el glifo). Configurado en
    `pubspec.yaml` (`flutter_launcher_icons:`) para Android, iOS
    (`remove_alpha_ios: true`, la App Store no admite icono con canal
    alpha), macOS, web (`background_color`/`theme_color` del
    `manifest.json` a negro también, para la barra del navegador al
    añadir a pantalla de inicio en iOS/Android) y Windows. Tras
    cambiar la imagen fuente, regenerar con
    `dart run flutter_launcher_icons` — no editar a mano los archivos
    generados en `android/app/src/main/res/mipmap-*`,
    `ios/Runner/Assets.xcassets/AppIcon.appiconset`,
    `macos/Runner/Assets.xcassets/AppIcon.appiconset`, ni `web/icons`.

45. **`DashboardProfesorScreen` agrupada por curso.** Un profesor puede
    dar la "misma" asignatura (mismo nombre, p. ej. "Armonía") en
    varios cursos distintos — son documentos `Asignatura` independientes
    con el mismo `nombre` pero distinto `cursoId`, así que sin agrupar
    aparecían varias tarjetas idénticas sin forma de distinguir a qué
    curso pertenecía cada una (reportado durante el piloto). Resuelve
    `cursoId → Curso` con `db.cursos().first` (un solo fetch, no un
    stream — la lista de cursos no cambia mientras se ve esta pantalla)
    y agrupa igual que el resto de vistas agrupadas por curso (puntos
    31 y 36): secciones ordenadas por `nivel.index`/`numeroCurso`, cada
    una con su propio `GridView` (`shrinkWrap: true` +
    `NeverScrollableScrollPhysics`, anidado dentro del `ListView`
    exterior de secciones).

## Nomenclatura de colecciones (fija, no renombrar sin avisar)

`usuarios`, `sesionesEstudio`, `modulos`, `ejercicios`,
`ejerciciosCompletados`, `notas`, `estadisticasAlumno`, `cursos`,
`asignaturas`, `matriculas`, `asistencias`, `criteriosEvaluacion`,
`sustituciones`, `horariosLaborales`, `marcajes`, `configuracion`.

- `sesionesEstudio.asignaturaId` (nullable): a qué asignatura
  pertenece la sesión; `null` solo aparece en sesiones antiguas de
  antes del punto 41 (práctica libre, ya retirada) — una sesión nueva
  siempre lo lleva y además debe apuntar a una asignatura con
  `permiteGrabarEstudio == true` (reforzado en `firestore.rules`).
- `sesionesEstudio.alumnoNombre` (denormalizado en `DbService.guardarSesion`,
  no es un campo del modelo `SesionEstudio` en Dart): para que el
  Cuadro de Honor pueda mostrar el nombre de OTROS alumnos sin que
  cada uno necesite permiso de lectura sobre el `usuarios` ajeno — ver
  punto 42.
- `asignaturas.permiteGrabarEstudio` (bool, `false` por defecto) — ver
  punto 41.
- `notas.asignaturaId` (antes `notas.asignatura`, texto libre): ahora
  es una referencia real a `asignaturas/{id}`, no texto libre.
- `notas.criterioId`: referencia a `criteriosEvaluacion/{id}`, de ahí
  sale el peso (%) de esa nota — ver punto 9.
- `notas.fechaDia` (`'yyyy-MM-dd'`, derivado de `fecha`, no es un
  campo del modelo `Nota` en Dart): solo para que `firestore.rules`
  pueda comprobar sustituciones sin parsear fechas — ver punto 10.
- `matriculas.profesorId`: profesor responsable de ese alumno en esa
  asignatura (`''` = sin asignar) — ver punto 10.
- `cursos.horasObjetivoMensual` (double, 0 = sin objetivo),
  `cursos.nivel`/`cursos.numeroCurso` y `cursos.iconoId` — ver puntos
  17, 20 y 29. `asignaturas.iconoId` (string, `''` = icono por
  defecto) sigue viviendo en `Asignatura` — solo el objetivo de horas
  se movió a `Curso`, el icono no.
- `asistencias.retraso` (bool, `false` por defecto) — ver punto 18.
- `marcajes.pendienteValidacion` (bool, `false` por defecto) — ver
  punto 32.
- `usuarios.ultimaVisita` (ISO8601, escrito por el propio usuario vía
  `DbService.registrarVisitaYObtenerAnterior`): no forma parte del
  modelo `Usuario` en Dart, solo se usa para calcular avisos in-app
  (ver punto 13).
- Sin `centroId` en `cursos`/`asignaturas`: piloto de un solo centro.
  Si se onboardea un segundo centro, añadir `centroId` y filtrar
  `alumnosDelCentro()`/`profesoresDelCentro()` en `db_service.dart`
  (hoy usan un único filtro `arrayContains` sobre `permisos`, sin
  `centroId`, a propósito para evitar un índice compuesto).
- `matriculas.cursoEscolar` (string, p.ej. "2025-2026", forma parte del
  ID determinista) y `asistencias.cursoEscolar`/`notas.cursoEscolar`
  (derivados de su propia `fecha`, no son campos del modelo Dart) — ver
  punto 26. `configuracion/centro`: documento único con
  `cursoEscolarActivo` + `historialCursosEscolares` — ver mismo punto.

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
- "Grabar estudio libre" (sesión sin asignatura): retirado explícitamente
  en el punto 41 — todas las horas deben corresponder a una asignatura
  de instrumento concreta con `permiteGrabarEstudio == true`.

## Backlog conocido

- Ya construido: menú lateral por permisos (`home_shell.dart`),
  gestión de cursos/asignaturas/alumnos/profesorado y matriculación por
  dirección (`profesorado_screen.dart` + `profesor_asignaturas_screen.dart`
  para asignar profesores, que pueden ser varios, a una asignatura),
  calendario de asistencia + estadísticas (tabla y gráficas de barras
  y quesito con `fl_chart`) y notas por asignatura ponderadas por
  criterios de evaluación configurables por dirección (ver punto 9,
  `criterios_evaluacion_screen.dart` + `alumno_en_asignatura_screen.dart`);
  asignación de alumno a un profesor concreto dentro de una asignatura
  con varios profesores, y sustituciones temporales por día (ver punto
  10, `sustituciones_screen.dart` + `_configurarMatricula` en
  `asignatura_detalle_screen.dart`); metrónomo (`metronomo_service.dart`
  + `metronomo_screen.dart`) y afinador (`afinador_service.dart` +
  `afinador_screen.dart`), accesibles desde "Herramientas" en el menú
  lateral para cualquier permiso — ver detalle técnico más abajo, ya
  no están en el backlog de migración; historial general de estudio
  del alumno (`historial_estudio_screen.dart`) y notas consolidadas de
  todas sus asignaturas (`mis_notas_screen.dart`); editar/eliminar
  cursos y asignaturas (bloqueado si tienen asignaturas/matriculados,
  ver `DbService.eliminarCurso`/`eliminarAsignatura`); aviso a
  dirección de asistencia sin marcar en los últimos 7 días
  (`asistencia_pendiente_screen.dart`); ranking por asignatura
  (`ranking_asignatura_screen.dart`, ver punto 14); avisos in-app en
  la pantalla de inicio (ver punto 13); tests de `firestore.rules`
  contra el emulador en `firestore-tests/` (`npm test` desde esa
  carpeta, requiere `npm install` una vez); registro horario de
  trabajadores con fichaje, horario configurable, recordatorio local
  y exportación a Excel (ver punto 15, `fichajes_screen.dart` +
  `registro_horario_screen.dart`); tema claro/oscuro (`lib/tema.dart`,
  ambos derivados del mismo color de marca) con selector persistente
  en el menú lateral (`TemaService`, paquete `shared_preferences`);
  horas objetivo mensuales/anuales con aviso rojo/verde en ranking,
  informe de dirección y estadísticas del alumno (ver punto 17); botón
  de retraso en asistencia y botones rápidos de asistencia por fila en
  `AsignaturaDetalleScreen` sin entrar en el detalle de cada alumno
  (ver punto 18, `_FilaMatricula`); asignaturas como cuadrícula de
  iconos personalizables (ver punto 20); nombre italiano del tempo
  (larghissimo-prestissimo) y más compases en el metrónomo
  (`metronomo_service.dart`); pantalla de Ajustes con tamaño de letra e
  iconos (ver punto 21); selector de instrumento y afinación en el
  afinador, con detección de qué cuerda se está tocando (ver punto 22,
  `lib/utils/instrumentos_afinador.dart`); selección múltiple en Notas
  pendientes para aprobar/corregir varias notas de golpe
  (`NotasPendientesScreen`, `DbService.actualizarEstadoNotas` con
  `WriteBatch`); exportación automática mensual de fichajes a una
  carpeta local elegida por dirección (ver punto 23,
  `ExportacionAutomaticaMarcajesService`); discriminación por curso
  escolar en matrículas/roster/ranking/informe (ver punto 26,
  `curso_escolar_screen.dart`); Cuadro de honor global visible para
  todos los permisos (ver punto 27, `cuadro_de_honor_screen.dart`);
  boletín de notas en PDF desde la ficha de alumno de dirección (ver
  punto 28, `alumno_perfil_screen.dart` + `lib/utils/boletin_pdf.dart`);
  jerarquía de cursos (nivel/número/icono) y objetivo de horas movido a
  `Curso`, con `CursosScreen` como cuadrícula de iconos (ver puntos 17
  y 29); catálogo de iconos ampliado para conservatorio (ver punto 30);
  agrupación por curso en Cuadro de honor (además de por instrumento),
  Alumnos e Informe de horas (ver punto 31,
  `DbService.cursosPorAlumno`); autoinforme de fichaje olvidado con
  validación de dirección (ver punto 32, `reportarOlvidoMarcaje` +
  `validarMarcaje`); botón flotante centralizado para volver siempre al
  menú principal (ver punto 33, `navegacion_observer.dart`);
  infraestructura de idioma (castellano/català) con 6 pantallas
  traducidas — login, menú, inicio, fichar, grabar estudio, ajustes
  (ver punto 34, `lib/l10n/`); cursos ordenados por nivel/número en vez
  de por orden de inserción y bloqueo de cursos duplicados (ver puntos
  36 y 37); logo "oh" de la app integrado como badge (`LogoOh`) en
  login, cabecera del Drawer y AppBar principal (ver punto 38,
  `lib/widgets/logo_oh.dart`) — el wordmark completo del centro
  (`cropped-Haro-...png`) ya estaba, no se ha tocado; build de Android
  funcionando de extremo a extremo (ver punto 39); metrónomo con
  sonido fiable en Android (ver punto 40); grabar estudio restringido
  a asignaturas de instrumento marcadas explícitamente por dirección,
  sin práctica libre (ver punto 41); Cuadro de Honor funcionando para
  el rol alumno (ver punto 42); icono de la app con la marca "oh" en
  todas las plataformas (ver punto 44).
- Pantallas pendientes: registro público de alumno (hoy solo dirección
  da de alta, ver punto 6), ejercicios.
- Creación de cuentas de **dirección** sigue siendo manual por consola
  de Firebase — no hay formulario ágil para ello (alumnos y profesores
  sí lo tienen, ver punto 6).
- `centroId` en `cursos`/`asignaturas` para soporte multi-centro (hoy
  global, piloto de un solo centro — ver nomenclatura de colecciones).
- Cloud Function de agregación de `estadisticasAlumno`.
- Registro manual de estudio teórico con recordatorio pop-up (ya
  modelado como `TipoSesion.teorico` en `SesionEstudio`, falta la UI).
