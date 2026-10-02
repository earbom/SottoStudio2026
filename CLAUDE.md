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

17. **(HISTÓRICO — objetivo movido a `Asignatura` en el punto 72, no
    reintroducir `Curso.horasObjetivoMensual`.) Horas objetivo eran
    MENSUALES, por CURSO, no por asignatura ni por alumno.**
    `Curso.horasObjetivoMensual` (0 = sin objetivo, no se
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

45. **`DashboardProfesorScreen` (agrupada por curso) — RETIRADA, ver
    punto 46.** Existió brevemente agrupando las asignaturas del
    profesor por curso (mismo problema de origen que el punto 46:
    `Asignatura.nombre` repetido en varios cursos como documentos
    independientes). El piloto pidió invertir el orden de navegación
    —asignatura primero, curso dentro— para ambos roles, así que esta
    pantalla y su agrupación por curso quedaron obsoletas y se
    eliminaron por completo en el mismo cambio; no reintroducir un
    `DashboardProfesorScreen` aparte.

46. **Navegación principal invertida: asignatura primero, curso
    dentro** (reportado durante el piloto: "en la práctica hay clases
    de instrumento con alumnos de diferentes cursos", así que entrar
    primero por curso obligaba a recordar en cuál estaba cada alumno).
    `AsignaturasPorNombreScreen` (`lib/screens/comunes/`) es ahora el
    punto de entrada principal para dirección ("Cursos y asignaturas")
    y profesor ("Mis asignaturas"): agrupa las `Asignatura` por
    `nombre.trim().toLowerCase()` (coincidencia EXACTA, sin fuzzy
    matching — decisión deliberada, ver comentario en el propio
    archivo) y al tocar un grupo abre `AsignaturaNombreCursosScreen`,
    una lista de los cursos que ofrecen esa asignatura concreta. Viable
    sin tocar el modelo de datos porque `AsignaturaDetalleScreen` nunca
    dependió de cómo se llega a ella (solo recibe `{asignatura,
    perfil}`, nunca `curso`; resuelve el curso de forma perezosa vía
    `asignatura.cursoId` cuando lo necesita, igual que
    `RankingAsignaturaScreen`/`AlumnoEnAsignaturaScreen`). El nombre e
    icono mostrados de cada grupo salen de la asignatura con
    `createdAt` más antiguo de ese grupo (estable entre reconstrucciones
    aunque dos documentos tengan mayúsculas/espacios ligeramente
    distintos). **La gestión de cursos en sí (crear/editar/eliminar,
    nivel, número, objetivo de horas) NO se tocó** — sigue en
    `CursosScreen`, ahora accesible como entrada secundaria "Gestionar
    cursos" (solo dirección) en vez de punto de entrada principal.

47. **Marcar asistencia desde "Alumnos"**, para profesor (reportado
    durante el piloto: "sería mucho más ágil" que entrar en cada
    asignatura). `AlumnosScreen` (movida de `direccion/` a `comunes/`,
    ya no es exclusiva de dirección) es ahora permission-aware: para
    dirección se comporta igual que antes (listado completo, ficha con
    boletín PDF); para profesor, la fuente es
    `DbService.alumnosDeProfesorAgrupados()` y tocar un alumno abre la
    nueva `AlumnoAsistenciaHoyScreen`, que solo muestra las asignaturas
    de ESE alumno que ESE profesor imparte (o donde tiene sustitución
    activa hoy, ver punto 10) y que tienen clase programada hoy según
    `Matricula.diasSemana` — con los mismos botones rápidos de
    asistencia (verde/naranja/rojo) que `_FilaMatricula` en
    `asignatura_detalle_screen.dart`, incluida la suscripción en vivo a
    `asistenciaDelDiaStream` (nunca un `Future` puntual, ver punto 24).
    - **Trampa de reglas evitada**: la regla de lectura de `matriculas`
      para profesor depende de `resource.data.asignaturaId`
      (`esProfesorDeAsignatura`) — una consulta filtrada solo por
      `alumnoId` (como habría sido lo natural para "mis alumnos") NO
      es "provably compliant" y Firestore la rechaza ENTERA para
      profesor (mismo patrón que el punto 25). Por eso
      `alumnosDeProfesorAgrupados()` y la nueva
      `matriculasDeAlumnoImpartidasPorProfesor()` iteran por las
      asignaturas DEL PROFESOR (`asignaturasDeProfesor`, lectura
      abierta) y consultan `matriculasDeAsignatura` por cada una —
      **no** reutilizar `matriculasDeAlumno()` ni `cursosPorAlumno()`
      (esta última tiene el mismo problema: filtra `matriculas` solo
      por `cursoEscolar`+`activa`, ya documentado como dirección-only
      en el punto 42) para construir nada de cara a un profesor. Test
      de regresión en `firestore-tests/rules.test.js`
      ("matriculas: consulta por asignaturaId es la única forma
      segura para profesor") que falla a propósito con el patrón
      incorrecto, para que nadie lo reintroduzca "simplificando".

48. **Cuadrícula de notas por asignatura** (reportado durante el
    piloto: comparar alumnos de un vistazo, "como si fuera un excel").
    `NotasAsignaturaGridScreen`, nuevo icono en el `AppBar` de
    `AsignaturaDetalleScreen` (visible para profesor/dirección).
    Filas = alumnos matriculados (mismo criterio `esMio`/`profesorId`
    que `_FilaMatricula`); columnas = `criteriosDeAsignatura`; celdas =
    nueva `DbService.notasDeAsignatura(asignaturaId)`. Como el modelo
    permite varias notas por alumno+criterio a lo largo del tiempo (no
    hay un valor único garantizado), cada celda muestra la MÁS
    RECIENTE; si ya hay más de una, tocarla ofrece añadir otra o ver
    el histórico completo — para eso `AlumnoEnAsignaturaScreen` ganó
    un parámetro opcional `pestanaInicial` (0=Calendario, 1=Estadísticas,
    2=Notas, antes siempre arrancaba en Calendario) para poder abrir
    directamente en la pestaña de Notas. La validación 0-10 de
    `Nota.valor` (cliente y `firestore.rules`) no se ha tocado.
    **Verificado, no asumido**: la regla de lectura de `notas` para
    profesor/dirección (`esProfesorODireccion()`) NO depende de
    `resource.data` —a diferencia de `matriculas`/`asistencias`—, así
    que `notasDeAsignatura()` es "provably compliant" sin más
    condición aunque el profesor no tenga asignado a ese alumno
    (comportamiento de negocio ya existente, ver punto 25 para el caso
    contrario); test de regresión que confirma explícitamente esta
    lectura amplia en `firestore-tests/rules.test.js`.

49. **Colores de asistencia en el calendario del alumno** (verde =
    asistió, naranja = retraso, rojo = faltó, mismos colores que
    `_botonEstadoAsistencia`/`_botonAsistencia` ya existentes) — para
    ver de un vistazo el mes entero, no solo el día seleccionado.
    `_TabCalendarioState` (`alumno_en_asignatura_screen.dart`) carga
    ahora TODAS las asistencias del alumno en la asignatura de una vez
    (`asistenciasDeAlumnoEnAsignatura`, ya existía, ya "provably
    compliant") en `Map<String, Asistencia> _asistenciasPorFecha`
    indexado por `Asistencia.fecha` (ya viene en formato `'yyyy-MM-dd'`,
    no hace falta reformatear), y se recarga también al final de
    `_marcar()` — si no, el color del día recién marcado no se veía
    hasta salir y volver a entrar. El círculo "es día de clase
    programado" (`primaryContainer`) se mantiene como aspecto por
    defecto cuando no hay asistencia registrada ese día.

50. **Cuadro de honor: nombres en blanco de forma intermitente**
    (bug real, esta vez de agregación en cliente, no de reglas —
    aparecía ya con las reglas del punto 42 arregladas).
    `DbService.cuadroDeHonorMensual()` sobrescribía
    `nombrePorAlumno[alumnoId]` en CADA sesión del mes sin condición;
    si un alumno tenía varias sesiones y la última recorrida era
    anterior a que existiera la denormalización de `alumnoNombre`
    (sin ese campo), el nombre bueno de una sesión más reciente se
    borraba con `''` — mismo bug en `instrumentoPorAlumno`. Arreglado
    sin dejar que un valor vacío/ausente sobrescriba uno ya conocido
    (`putIfAbsent` solo para el caso "todavía no hay ninguno"). Puro
    bug de agregación en Dart, sin cambios de reglas ni de modelo.

51. **Permiso cruzado entre cursos por nombre de asignatura** (pedido
    en el piloto: "si hay varios profesores que dan piano a alumnos de
    cursos distintos, cualquiera de ellos debe poder puntuar/marcar
    asistencia de cualquier alumno de esa asignatura, sea cual sea el
    curso"). Antes el permiso de un profesor estaba atado a UN
    documento `Asignatura` concreto (`profesorIds`) y, dentro de ese
    documento, a un pin por alumno (`matriculas.profesorId`, ver punto
    10). Como las clases de instrumento con el mismo nombre ("Piano")
    suelen repartirse en documentos `Asignatura` distintos —uno por
    curso—, ese modelo no permitía a un profesor gestionar alumnos de
    OTRO documento aunque diera la misma materia.
    - **`Asignatura.nombreNormalizado`** (`nombre.trim().toLowerCase()`,
      denormalizado en `toMap()`, NO es un campo del modelo Dart —
      mismo patrón que `Nota.fechaDia`/`cursoEscolar`) agrupa todos
      los documentos `Asignatura` que comparten nombre, sin importar
      el curso.
    - **`gruposAsignatura/{nombreNormalizado}`**: `{ profesorIds: [...] }`,
      la UNIÓN de `profesorIds` de TODAS las asignaturas de ese
      nombre. Sin Cloud Functions desplegadas (ver punto 5), se
      mantiene en CLIENTE: `DbService._sincronizarGrupoAsignatura()`
      recalcula el grupo afectado tras `crearAsignatura`,
      `actualizarAsignatura` (si cambia `nombre` o `profesorIds`),
      `asignarProfesorAAsignatura` y `eliminarAsignatura`. Las
      asignaturas creadas antes de este cambio no tenían
      `nombreNormalizado` ni grupo — `DbService.migrarGruposAsignatura()`
      es una migración de un solo uso (botón "Recalcular grupos de
      asignatura", FAB pequeño solo-dirección en
      `AsignaturasPorNombreScreen`) que se ejecutó una vez tras
      desplegar este cambio; la sincronización normal ya corre sola
      desde entonces.
    - `firestore.rules`: `esProfesorDeAsignaturaPorNombre(asignaturaId)`
      sustituye a las antiguas `esProfesorDeAsignatura` y
      `esProfesorAsignadoAlAlumno` (ambas eliminadas) en las reglas de
      `notas` (create), `asistencias` (create/update) y `matriculas`
      (read): resuelve `asignaturaId → nombreNormalizado →
      gruposAsignatura/{clave}.profesorIds` con `.get(clave, default)`
      en cada paso, para fallar en `false` (nunca lanzar un error de
      evaluación, mismo criterio que el punto 16) si una asignatura
      todavía no está migrada o el grupo no existe.
    - **`matriculas.profesorId` pasa a ser puramente informativo** —
      ya NO es un permiso, solo indica a quién dirección considera "el
      profesor de referencia" de ese alumno (el desplegable de
      `_configurarMatricula` en `asignatura_detalle_screen.dart` deja
      esto explícito en su etiqueta). El roster de `_FilaMatricula` y
      de `NotasAsignaturaGridScreen` ya no se filtra por
      `profesorId == uid`: cualquier profesor con permiso ve a TODOS
      los matriculados de esa asignatura.
    - `DbService.asignaturasDeProfesorCrossCurso(profesorUid)` (usada
      por `AsignaturasPorNombreScreen` para que un profesor descubra
      TAMBIÉN los cursos de otros documentos con el mismo nombre, no
      solo aquel en el que dirección lo puso originalmente en
      `profesorIds`) sustituye a `asignaturasDeProfesor` como fuente
      para `alumnosDeProfesorAgrupados` y
      `matriculasDeAlumnoImpartidasPorProfesor` — ambas dejaron
      también de filtrar por `m.profesorId == profesorId`, por el
      mismo motivo. `asignaturasDeProfesor` (single-doc) se conserva
      tal cual para otros usos que sí son de un documento concreto.
    - Tests de regresión (incluida una consulta con datos "no
      migrados" que debe denegar sin lanzar error) en
      `firestore-tests/rules.test.js`, describe
      `'permiso cruzado entre cursos por nombre de asignatura (gruposAsignatura)'`.

52. **Objetivo de horas de estudio configurable POR ASIGNATURA**
    (pedido en el piloto: el objetivo de horas vivía solo en `Curso`
    —punto 17—, un nivel demasiado grueso para asignaturas concretas).
    `Asignatura.horasObjetivoSemanal`/`horasObjetivoMensual` (double, 0
    = sin objetivo, mismo criterio que `Curso.horasObjetivoMensual`,
    validado en `firestore.rules` con el mismo patrón `get(...,0) >= 0`
    que `cursos`). **`Curso.horasObjetivoMensual` NO desaparece** —
    sigue siendo la fuente de `informeDireccion()` y del ranking
    global por curso; el campo nuevo es un nivel más fino, aditivo.
    - Se edita desde una sección nueva y fija (no un
      `CriterioEvaluacion` más) en `CriteriosEvaluacionScreen`,
      justo encima de la lista de criterios: explícitamente NO cuenta
      para la nota ponderada.
    - Repuntadas a este campo las 3 vistas que antes usaban
      `Curso.horasObjetivoMensual` como aproximación provisional (ver
      punto 17 y la implementación del calendario de estudio del
      alumno de esta misma tanda de cambios):
      `AlumnoEnAsignaturaScreen._cargarHorasEstudio()` (semanal/diario),
      `_TabEstadisticas` (objetivo anual = mensual × 12) y
      `RankingAsignaturaScreen` (objetivo mensual de la fila).
    - `RankingAsignaturaScreen` de paso dejó de filtrar matriculados
      por `m.profesorId == perfil.uid` para un profesor — mismo motivo
      que el punto 51 (permiso cruzado entre cursos): un profesor de
      la asignatura ve a TODOS sus matriculados en el ranking, no solo
      a los que tenía pineados.

53. **Horas de estudio de TEORÍA registradas a mano por el profesor**
    (pedido en el piloto: en asignaturas no instrumentales —armonía,
    lenguaje musical...— el profesor recoge los cuadernos de los
    alumnos una vez a la semana y anota un total, no hay micrófono que
    grabar). `SesionEstudio.registradoPorProfesorId` (nullable, no
    forma parte de las sesiones grabadas por el propio alumno) marca
    estas sesiones como autoinformadas por un profesor concreto.
    - `DbService.registrarHorasManualesSemana()` crea una
      `SesionEstudio` con `tipo: TipoSesion.teorico`,
      `duracionTotalMs == duracionEfectivaMs` (es un total
      autoinformado, no una medición — no aplica la lógica de 3
      estados del punto 2) y `fechaInicio`/`fechaFin` fijados al
      lunes/domingo de la semana elegida. Reutiliza
      `DbService.guardarSesion()` (misma denormalización de
      `alumnoNombre` que las sesiones de instrumento).
    - UI: icono "Registrar horas de esta semana" en `_FilaMatricula`
      (`asignatura_detalle_screen.dart`), visible solo cuando
      `!asignatura.permiteGrabarEstudio` (asignaturas NO
      instrumentales — las de instrumento ya graban de verdad con
      micrófono) y el profesor puede gestionar esa fila (con el
      permiso cruzado entre cursos del punto 51, no depende de
      `matriculas.profesorId`).
    - `firestore.rules` (`sesionesEstudio`): nueva rama `create`/
      `update` para `esProfesor()` — exige `tipo == 'teorico'`,
      `registradoPorProfesorId == request.auth.uid` y
      `esProfesorDeAsignaturaPorNombre(asignaturaId)` (sin exigir
      `permiteGrabarEstudio`, que es justo la asignatura contraria a
      este caso de uso). La rama `update` fija alumno/asignatura/tipo/
      autor (mismo patrón de "no se puede reetiquetar" que
      `asistencias`).
    - **Lectura ampliada** (ver también punto 27): la excepción de
      lectura para alumno (visibilidad de sesiones de OTROS alumnos)
      pasó de `tipo == 'instrumento'` a `tipo in ['instrumento',
      'teorico']` — necesario para que el ranking por bloques del
      punto 54 sea visible también para alumnos en asignaturas no
      instrumentales. Sin condicionarlo a si la asignatura tiene
      objetivo configurado (eso es presentación, no seguridad, ver el
      propio comentario en `firestore.rules`).
    - Tests de regresión (incluidos los que antes afirmaban lo
      contrario, ahora volteados con comentario) en
      `firestore-tests/rules.test.js`, describe
      `'sesionesEstudio: registro manual de horas de teoría por el profesor'`.

54. **Cuadro de honor por bloques (curso → asignatura)**, cuarto modo
    del `SegmentedButton` de `CuadroDeHonorScreen` (junto a
    Global/Por curso/Por instrumento), visible para TODOS los
    permisos —incluidos alumnos— a diferencia del modo "Por curso"
    (dirección-only, porque necesita `cursosPorAlumno()`, que lee
    `matriculas` de todo el mundo). Es un SEGUNDO carve-out del punto
    14 (privacidad de nombres), distinto y más amplio que el del
    punto 27 (que solo cubría instrumento) — `HorasAsignaturaScreen`
    (antes `RankingAsignaturaScreen`, ver punto 55) NO se toca, sigue
    siendo solo profesor/dirección.
    - `DbService.horasPorAsignaturaMensual()`: agregación en cliente
      sobre `sesionesEstudio` (`tipo in ['instrumento', 'teorico']`,
      mismo criterio "provably compliant" que `cuadroDeHonorMensual()`
      — ver CLAUDE.md puntos 25/42), agrupando por
      `alumnoId`+`asignaturaId` en vez de solo por `alumnoId`. Reusa el
      mismo `alumnoNombre` denormalizado y el mismo patrón defensivo
      del punto 50 (un valor ausente nunca sobrescribe un nombre ya
      conocido).
    - `_ListaAgrupadaPorBloques`/`_BloqueAsignatura`
      (`cuadro_de_honor_screen.dart`) cruzan esas filas con
      `todasLasAsignaturas()`/`cursos()` (ambas de lectura abierta) para
      resolver nombre/curso/objetivo de cada bloque — **sin leer
      `matriculas`**, precisamente lo que permite que este modo sea
      visible para cualquier permiso. Cada bloque de asignatura se
      colorea verde/rojo contra su propio
      `Asignatura.horasObjetivoMensual` (punto 52; 0 = sin colorear).
    - Sin tests de reglas nuevos más allá de los del punto 53 (lectura
      `tipo in [...]`) — esta pantalla es agregación pura sobre un
      camino de lectura ya abierto, sin rama de seguridad propia.

55. **Perfil de profesor: notas pendientes, excepción de grabación por
    alumno, navegación por secciones y fusión Horas/Ranking** (pedido
    tras usar la app como profesor en el piloto).
    - **Notas pendientes visibles**: `_TabNotas`
      (`alumno_en_asignatura_screen.dart`) ya no lista solo las notas
      puestas — itera sobre TODOS los `criteriosEvaluacion` de la
      asignatura y agrupa las notas bajo su criterio; un criterio sin
      ninguna nota aparece como "Pendiente" con un botón de añadir
      rápido que preselecciona ese criterio en el diálogo de siempre
      (`_crearNota` ganó un parámetro opcional `preseleccionado`).
      Antes solo se veía como opción de un desplegable al pulsar "+",
      sin ninguna vista de qué pruebas existen en total.
    - **`Usuario.puedeGrabarEstudio` — REVERTIDO por completo, ver
      punto 59.** Dirección decidió que TODOS los alumnos con cuenta
      tengan acceso a grabar por defecto; la única discriminación
      sigue siendo por asignatura (`Asignatura.permiteGrabarEstudio`,
      punto 41), como antes de este sub-punto. No queda ni el campo en
      `Usuario`, ni el `SwitchListTile`, ni el pin en
      `firestore.rules` — el resto de esta entrada (notas pendientes
      visibles, navegación por secciones, fusión con el ranking) sigue
      vigente tal cual.
    - **Navegación por secciones para profesor puro** (no dirección):
      `AsignaturasPorNombreScreen` enruta a la nueva
      `SeccionesAsignaturaScreen` (Asistencias/Notas/Horas de estudio)
      ANTES de elegir curso, para CUALQUIER asignatura — no solo
      instrumento. `AsignaturaNombreCursosScreen` ganó un parámetro
      opcional `seccion`: con él fijado, elegir un curso lleva directo
      a la pantalla de esa sección (`AsistenciasAsignaturaScreen`
      nueva — solo asistencia de HOY, mismo patrón de 3 botones que
      `_FilaMatricula` pero sin edición de matrícula ni horas
      manuales—, `NotasAsignaturaGridScreen` sin cambios, o
      `HorasAsignaturaScreen`); con `seccion == null` (dirección, sin
      cambios) sigue yendo a `AsignaturaDetalleScreen` como siempre.
      Dirección (incluida dirección+profesor combinado) NO usa este
      menú nuevo — sigue necesitando matricular/editar matrícula/
      Criterios/Sustituciones, que no encajan en 3 secciones.
    - **`RankingAsignaturaScreen` eliminada, fusionada en
      `HorasAsignaturaScreen`**: mostraban esencialmente lo mismo
      (horas del mes por alumno, coloreadas contra
      `Asignatura.horasObjetivoMensual`) — un único sitio ahora. El
      icono de `AsignaturaDetalleScreen` que abría "Ranking" ahora abre
      esta pantalla. **`HorasAsignaturaScreen` se rediseñó de nuevo
      poco después como cuadrícula mensual editable — ver punto 59,
      ya no hay lista-ranking ni `mostrarDialogoRegistrarHorasManuales`.**
    - **Cuadro de Honor "Por bloques" personalizable — RETIRADO por
      completo, ver punto 59.** El icono de filtro por curso/asignatura
      de este sub-punto y los otros 3 modos (Global/Por curso/Por
      instrumento) del `SegmentedButton` ya no existen: "Por bloques"
      (curso → asignatura) pasó a ser el ÚNICO modo de
      `CuadroDeHonorScreen`, sin filtro, siempre visible.

56. **Curso escolar: volver a un año anterior y eliminarlo del
    historial** (dirección temía pulsar "avanzar" por error).
    `DbService.avanzarCursoEscolar` ya servía para volver atrás (no
    comprobaba que el nuevo año fuera cronológicamente posterior, solo
    el formato) pero no era un flujo explícito — ahora cada fila del
    historial que no es la activa tiene un botón "Marcar como activo"
    que llama al mismo método, sin tocar ningún dato (matrículas/
    notas/asistencias de ese año siguen intactas y vuelven a ser
    utilizables). Nuevo botón "Eliminar del historial"
    (`DbService.eliminarCursoEscolarDelHistorial`, `arrayRemove` sobre
    `historialCursosEscolares`) — **solo quita el año de la lista,
    nunca borra matrículas/notas/asistencias reales** (decisión
    deliberada: coherente con que en esta app nunca se borran
    registros académicos, ver `marcajes`). Antes de dejar borrar,
    `DbService.tieneDatosCursoEscolar` comprueba si el año tiene alguna
    matrícula y muestra un aviso si es así; en cualquier caso, una
    segunda confirmación con cuenta atrás de 5 segundos
    (`_DialogoConfirmarConCuentaAtras` en `curso_escolar_screen.dart`)
    antes de poder pulsar "Eliminar". Sin cambios de `firestore.rules`
    (`configuracion` ya permitía `update` a dirección sin más
    condición) ni de `firestore-tests`.

57. **Alumnos sin cuenta de acceso + importación masiva desde
    plantilla Excel** (para volcar de golpe los datos que el centro
    lleva hoy en hojas de Google Drive no homogéneas).
    - `Usuario.email` pasa a **nullable** y gana
      `Usuario.tieneCuenta` (bool, default `true`, marca explícita no
      inferida): un alumno puede existir en Firestore sin ninguna
      cuenta de Firebase Auth detrás — necesario para alumnos muy
      pequeños o que decidan no usar la app, que igualmente deben
      poder ser matriculados y puntuados por un profesor. Verificado
      que **no hace falta ningún cambio de `firestore.rules`**: la
      regla de creación de `usuarios` ya permite a dirección crear un
      documento con cualquier id (no necesariamente un uid real de
      Auth), y `matriculas`/`asistencias`/`notas`/`sesionesEstudio`
      tratan `alumnoId` como una cadena opaca sin comprobar que
      corresponda a una cuenta real.
    - `AuthService.crearAlumnoSinCuenta()`: a diferencia de
      `crearAlumno()`, no toca Firebase Auth en absoluto — escribe
      directamente en `usuarios` con un id autogenerado de Firestore
      (`_db.collection('usuarios').doc()`). `CrearAlumnoScreen` ganó
      un `SwitchListTile` para elegir qué camino usar (oculta el campo
      de email cuando está desactivado). `AlumnosScreen`/
      `AlumnoPerfilScreen` muestran "Sin acceso a la app" cuando
      `!tieneCuenta`. **Limitación conocida, no resuelta**: no hay
      forma de "convertir" después un alumno sin cuenta en uno con
      cuenta real (un uid de Auth no se puede fijar a mano) sin migrar
      a mano todas sus matrículas/notas/asistencias a un uid nuevo.
    - **Importación masiva**: plantilla FIJA de 2 hojas
      (`lib/utils/excel_plantilla_importacion.dart`,
      `generarPlantillaImportacion()`/`parsearPlantillaImportacion()`)
      — deliberadamente NO se intenta adivinar el formato de una hoja
      ya existente de dirección, se le pide copiar sus datos a este
      formato conocido una vez. Hoja "Cursos y asignaturas" (Curso,
      Asignatura, Instrumento Sí/No, objetivos semanal/mensual
      opcionales) y hoja "Alumnos y matrículas" (Nombre, Apellidos,
      Email opcional, Curso, Asignatura, Días de clase opcionales) —
      **una fila por combinación alumno+asignatura**, no listas
      separadas por comas. Nueva pantalla dirección-only
      `ImportarDatosScreen`: descarga la plantilla, sube el archivo
      relleno (`file_picker`, ya usado en el proyecto), valida que
      toda asignatura mencionada en la hoja de alumnos exista en la
      hoja de cursos (bloquea la importación si no), previsualiza
      recuentos, y al confirmar crea secuencialmente
      cursos→asignaturas→alumnos→matrículas (sin Cloud Functions, todo
      desde cliente). Cursos/asignaturas que YA existan con el mismo
      nombre (comparación recortada y en minúsculas) se REUTILIZAN, no
      se duplican — permite reimportar el mismo archivo actualizado.
      Un alumno ya existente solo se detecta por **email exacto**
      (`DbService.obtenerUsuarioPorEmail`, nuevo); dos alumnos sin
      email y mismo nombre+apellidos se crean como registros
      DISTINTOS — limitación conocida, visible en la previsualización
      antes de confirmar. Alumnos con email nuevo generan contraseña
      temporal (descargable en CSV al terminar, mismo patrón que
      `RegistroHorarioScreen`); alumnos sin email usan
      `crearAlumnoSinCuenta`.

58. **Modo desarrollador + apartado de incidencias** (Edgar necesita
    poder probar la app "como" cada rol sin mantener varias cuentas de
    prueba, y un sitio donde cualquiera reporte problemas/sugerencias).
    - **Por qué la simulación de rol tiene que narrear `Usuario.permisos`,
      no ser solo una etiqueta visual**: el modelo de permisos ya es
      combinable (una cuenta puede tener `{alumno, profesor, direccion}`
      a la vez) y `home_shell.dart` ya renderiza TODAS las secciones
      combinadas en el mismo drawer para una cuenta así — nunca una
      vista aislada de un rol. Además la navegación del punto 55
      depende de la combinación EXACTA de permisos
      (`perfil.esProfesor && !perfil.esDireccion`), no solo de su
      presencia. Por eso la cuenta de Edgar tiene los 4 permisos A LA
      VEZ en Firestore (`alumno`, `profesor`, `direccion`,
      `desarrollador` — este último fijado A MANO por consola,
      igual que ya es manual la creación de cuentas de dirección,
      nunca ofrecido en ninguna pantalla de alta de cuentas), y el
      "modo de vista" construye, SOLO en el cliente, una copia de
      `Usuario` con `permisos` reducido al rol simulado
      (`Usuario.copiarConPermisos`) — el documento real en Firestore
      no se toca, así que las reglas de seguridad (que evalúan
      siempre `usuarioActual().permisos` real) siguen concediendo todo
      lo que ese rol necesitaría de verdad.
    - Único punto de aplicación: `main.dart`,
      `_RaizAutenticacion.build()`, justo tras
      `authService.obtenerPerfil(uid)` — construye `perfilMostrado`
      (narrowed o no) y pasa TAMBIÉN `perfilReal` (el documento
      completo, sin tocar) a `HomeShell`. Todo el resto de la app
      sigue recibiendo `Usuario perfil` como siempre, sin cambios.
    - `VistaPruebaService` (`lib/services/vista_prueba_service.dart`,
      mismo patrón `ChangeNotifier`+`shared_preferences` que
      `AjustesService`): `Permiso? vistaSimulada`, persistido
      localmente por dispositivo (no por cuenta).
    - `HomeShell` gana el parámetro `perfilReal` — el nuevo bloque de
      drawer "Modo de vista"/"Incidencias" se gatea con
      `perfilReal.esDesarrollador` (nunca con `perfil`, para que se
      vea pase lo que pase esté simulando), colocado justo debajo de
      la cabecera. La entrada "Informar de un problema o sugerencia"
      (`ReportarIncidenciaScreen`) es visible para CUALQUIER usuario,
      sin gateo, en el bloque "Herramientas" ya existente.
    - `incidencias`: colección plana (sin subcolección, convención de
      todo el proyecto), `comentarios` como lista embebida. Cualquiera
      crea/lee/comenta las suyas; el desarrollador
      (`esDesarrollador()`, nueva función en `firestore.rules`) lee y
      gestiona TODAS. **El autor nunca puede resolver su propio
      ticket** — la regla de `update` solo permite a `esDesarrollador()`
      tocar `estado`; el autor solo puede añadir un comentario
      (`comentarios.size()` +0/+1). Límite aceptado y documentado en
      el propio `firestore.rules`: no se puede validar elemento a
      elemento que los comentarios previos no se alteraron al añadir
      uno nuevo (Firestore rules no tiene bucles/comparación de
      prefijos de lista) — mismo nivel de confianza ya asumido hoy,
      sin guardas, para `asignaturas.profesorIds` con `arrayUnion`.
    - **Sin adjuntar imágenes ni email automático** (decisión
      explícita): Firebase Storage exige plan Blaze desde finales de
      2024 para proyectos nuevos, y sin Cloud Functions tampoco se
      puede disparar un email real desde servidor — mismo motivo que
      los puntos 5/6/13. Todo se gestiona dentro de la app; revisar si
      se activa el plan Blaze más adelante.
    - **Cuenta de prueba usada para probar este modo**: el propio
      earbom@gmail.com, en la cuenta de prueba de dirección — Edgar la
      usará para probar mientras el centro no esté en producción (el
      perfil "real" de dirección del centro no lleva `desarrollador`).
      Activar el permiso en esa cuenta sigue siendo un paso MANUAL en
      la consola de Firebase (añadir `"desarrollador"` al array
      `permisos` de su documento `usuarios/{uid}`) — no hay ni se ha
      pedido un formulario para ello, igual que la creación de cuentas
      de dirección (punto 6).

59. **Reversión de `puedeGrabarEstudio`, cuadrícula mensual de horas,
    agrupación visual de alumnos/roster, notas pendientes solo de nota
    final, y Cuadro de Honor a un único criterio** (lote de ajustes
    tras seguir probando la app; incluye un bug real de dos escrituras
    sin `try/catch`).
    - **`Usuario.puedeGrabarEstudio` revertido por completo** (campo,
      `SwitchListTile` de `AlumnoPerfilScreen`, pin en
      `firestore.rules` de `usuarios`/`sesionesEstudio`, y los 3 tests
      de reglas que lo cubrían) — ver punto 55, ese sub-punto quedó
      anotado como histórico. Dirección decidió que la discriminación
      de acceso a grabar siga siendo únicamente por asignatura
      (`Asignatura.permiteGrabarEstudio`, punto 41): todos los alumnos
      con cuenta pueden grabar por defecto en cualquier asignatura que
      lo permita.
    - **Registro manual de horas: de semanal a MENSUAL, y de
      lista+diálogo a cuadrícula editable.** `DbService.registrarHorasManualesSemana`
      se sustituyó por `registrarHorasManualesMes` (mismo patrón de
      `SesionEstudio` con `tipo: teorico` y
      `duracionTotalMs == duracionEfectivaMs`, ver punto 53): busca
      primero si ya existe una entrada manual de ese
      alumno+asignatura+mes (consulta de dos igualdades ya "provably
      compliant" — `alumnoId`+`asignaturaId` — filtrando en cliente por
      mes y `registradoPorProfesorId` no nulo) y la actualiza en vez de
      duplicarla. `lib/widgets/dialogo_registrar_horas.dart` (el
      diálogo semanal, compartido entre `_FilaMatricula` y
      `HorasAsignaturaScreen`) se ha borrado — ya no hace falta
      compartirlo, el nuevo diálogo de edición es pequeño y vive
      directo en `HorasAsignaturaScreen`. `_FilaMatricula`
      (`asignatura_detalle_screen.dart`) perdió el icono "Registrar
      horas de esta semana": la única vía para editar horas es ahora la
      cuadrícula.
    - **`HorasAsignaturaScreen` rediseñada como cuadrícula** (mismo
      patrón `DataTable` que `NotasAsignaturaGridScreen`): filas =
      alumnos matriculados, columnas = los 12 meses del curso escolar
      mostrado (septiembre→agosto, vía `rangoDeCursoEscolar`), celda =
      horas efectivas de ESE alumno en ESE mes para esta asignatura.
      Celda coloreada verde/rojo contra `Asignatura.horasObjetivoMensual`
      (0 = sin colorear). Si `!asignatura.permiteGrabarEstudio` la
      celda es pulsable y abre un diálogo de horas que llama a
      `registrarHorasManualesMes` (pre-rellenado si ya hay un valor
      para editarlo in-place); si la asignatura SÍ permite grabar
      (instrumento, horas reales grabadas con micrófono) la celda es de
      solo lectura. Mantiene el `SelectorCursoEscolar` de siempre.
    - **`firestore.rules`, `sesionesEstudio` `allow update`**: la rama
      `esProfesor()` ya no exige que quien corrige sea EXACTAMENTE
      `registradoPorProfesorId` del documento original — ahora exige
      `esProfesorDeAsignaturaPorNombre(resource.data.asignaturaId)`
      (mismo permiso cruzado entre cursos que el `create`, punto 51),
      así que cualquier profesor de esa asignatura —de cualquier
      curso que comparta nombre— puede corregir un total equivocado,
      no solo quien lo introdujo. El update sigue fijando
      `registradoPorProfesorId == request.auth.uid` (deja constancia
      de quién corrigió por última vez) y sigue bloqueando reetiquetar
      alumno/asignatura/tipo. Tests de regresión en
      `firestore-tests/rules.test.js` (corrección propia, cross-curso,
      y de un profesor que no enseña esa asignatura).
    - **Bug real: dos escrituras "fire-and-forget" sin `try/catch`
      interrumpían la app** (reportado como "me saca al simulador y me
      manda al IDE") — asignar un profesor a una asignatura desde
      `ProfesorAsignaturasScreen` (`CheckboxListTile.onChanged`) y
      registrar/corregir horas manuales. Sin stack trace exacto, la
      causa concreta no se confirmó por lectura estática, pero CUALQUIER
      excepción no capturada en una llamada async fuera de un
      `try/catch` sale como no controlada, y en una sesión de debug
      interrumpe la ejecución. Mitigado envolviendo ambos puntos en
      `try/catch` + `SnackBar` de error: deja de interrumpir la app Y
      además muestra el mensaje real en pantalla si vuelve a fallar.
      **No confirmado como causa raíz** — si el problema reaparece con
      un mensaje de error visible en el `SnackBar`, ese texto es la
      pista a seguir.
    - **`AlumnosScreen`, agrupación por letra**: `_ListaAlfabetica` ya
      no es un `ListView.separated` plano — inserta una cabecera en
      negrita (`A`, `B`, `C`...) cada vez que cambia la primera letra
      de `_claveOrden` (apellido, o nombre de respaldo) en la lista ya
      ordenada, mismo patrón visual que la extinta
      `_ListaAgrupadaPorInstrumento` del Cuadro de Honor.
    - **Roster de `AsignaturaDetalleScreen`, agrupación por profesor**:
      nuevo `_ListaMatriculasPorProfesor` agrupa las filas por
      `matricula.profesorId` (resuelto a nombre vía `obtenerUsuario`,
      "Sin profesor asignado" siempre al final), con cabeceras
      ordenadas alfabéticamente por el nombre resuelto — a diferencia
      del listado de alumnos, aquí NO se desglosa además por letra
      (decisión explícita de dirección). `_FilaMatricula` en sí no se
      tocó.
    - **Notas pendientes: ya no se valida nota por nota.**
      `NotasPendientesScreen` pasó de listar `Nota` individuales (con
      selección múltiple) a agrupar `notasPendientesSupervision()` por
      `(alumnoId, asignaturaId)`; cada grupo solo se muestra cuando el
      alumno ya tiene una nota (de cualquier estado) para TODOS los
      `criteriosEvaluacion` de esa asignatura — mientras falte alguno,
      ese alumno·asignatura no aparece. Cuando está completo, se
      calcula la nota ponderada (`Σ valor × peso/100`, con la nota MÁS
      RECIENTE de cada criterio — mismo cálculo que `_TabNotas`) y se
      muestra una única fila con 2 botones que llaman a
      `actualizarEstadoNotas` sobre las notas PENDIENTES de ese grupo
      (ya existía, `WriteBatch`) — sin tocar el modelo `Nota` ni
      `firestore.rules`.
    - **Cuadro de Honor: un único criterio (curso → asignatura)** — ver
      también la anotación del punto 55.
      `_ModoCuadroHonor`/`SegmentedButton`/filtro/`_ListaPlana`/
      `_ListaAgrupadaPorInstrumento`/`_ListaAgrupadaPorCurso` se
      eliminaron; `DbService.cuadroDeHonorMensual()` (sin consumidores
      tras esto) también se eliminó —
      `DbService.horasPorAsignaturaMensual()` (agregación por
      asignatura, ya existente) queda como única fuente. El reporte de
      "no veo nombres en el ranking" se revisó: la agregación ya
      llevaba el blindaje anti-sobrescritura del punto 50, así que con
      toda probabilidad eran sesiones de ejemplo creadas a mano en la
      consola de Firestore (sin pasar por `guardarSesion`, que es quien
      denormaliza `alumnoNombre`), no un fallo de la app.

60. **Modo desarrollador: cambiar de vista simulada no tenía ningún
    efecto** (reportado tras probar la APK — al elegir Alumno/
    Profesor/Dirección en "Modo de vista", tanto el subtítulo como el
    menú se quedaban permanentemente en "Viendo con todos mis
    permisos", como si no se simulara nada). Dos causas superpuestas,
    la segunda es la que de verdad bloqueaba todo — el primer intento
    de arreglo (una `key` en `HomeShell`) era una mejora real pero NO
    la causa raíz, se comprobó con un test que reproducía el `Drawer`
    de verdad:
    - (Mejora real, no la causa raíz) `HomeShell` es un
      `StatefulWidget` cuyo `_HomeShellState` cachea la pantalla actual
      (`_cuerpo`) y el título — asignados SOLO en `initState()`. Sin
      una `key` que cambie con el rol simulado, Flutter reutiliza el
      mismo `State` en vez de crear uno nuevo al cambiar `perfil`.
      Arreglado dándole a `HomeShell` una `key: ValueKey(claveVista)`
      (`claveVista` = nombres de `permisos` del perfil mostrado,
      ordenados y unidos por comas) en `_RaizAutenticacion`
      (`main.dart`): fuerza un `State`/`initState` nuevo en cada
      cambio de combinación de permisos mostrada.
    - **Causa raíz real**: `_abrirSelectorDeVista` (antes en
      `home_shell.dart`) recibía como parámetro el `BuildContext` del
      propio `ListTile` que abre el selector — un widget que vive
      DENTRO del `Drawer`. Empezaba con `Navigator.pop(context)` para
      cerrar el drawer, y SOLO DESPUÉS mostraba el diálogo
      (`showDialog`) y esperaba a que el usuario eligiera. El problema:
      `DrawerControllerState`, en cuanto termina su animación de
      cierre (~250ms), sustituye TODO su contenido por
      `SizedBox.shrink()` — es decir, desmonta por completo el
      `ListTile` (y su `context`) del árbol de widgets. Como un
      usuario tarda bastante más de 250ms en mirar el diálogo y tocar
      una opción, para cuando `showDialog` se resolvía,
      `context.mounted` YA daba `false` — así que el
      `if (!context.mounted) return;` de después abortaba SIEMPRE, y
      `vistaPrueba.cambiarVista(elegida)` nunca llegaba a ejecutarse,
      por mucho que el usuario eligiera. Arreglado quitando el
      parámetro `context` de `_abrirSelectorDeVista` y usando en su
      lugar el `context`/`mounted` de la propia `_HomeShellState`
      (el del `Scaffold`, que vive mientras la pantalla esté abierta,
      no se desmonta al cerrar el drawer). **Lección para cualquier
      acción async iniciada desde un `ListTile`/callback DENTRO de un
      `Drawer` que cierre el drawer al empezar**: si esa acción tarda
      más que la animación de cierre en resolverse (un diálogo, un
      `await` a red...), no reutilizar el `context` del propio
      `ListTile` después de cerrar el drawer — usar el `context` de la
      pantalla contenedora (la State del `Scaffold`), que sigue
      montado. Diagnosticado con un test de widgets que reproducía el
      `Drawer` real (`Scaffold.openDrawer()` + cerrar + esperar a que
      la animación termine antes de "elegir" en el diálogo) — un test
      más simple sin `Drawer` real no lo detectaba, porque el bug
      depende específicamente de ese desmontaje.

61. **Quitar "Alumnos" para profesor + cuadrícula de iconos al elegir
    curso (profesor).** Pedido en una reunión con dirección
    (septiembre 2026, lote de 14 puntos — ver puntos 61-69): dirección
    pidió retirar la entrada "Alumnos" del menú de profesor —
    superflua ahora que existe la vista global (punto 63) para marcar
    asistencia sin entrar asignatura por asignatura. `AlumnosScreen`
    (`lib/screens/comunes/alumnos_screen.dart`) vuelve a ser
    dirección-only, como antes del punto 47; se eliminó por completo
    `AlumnoAsistenciaHoyScreen` y los métodos de `DbService`
    (`alumnosDeProfesorAgrupados`, `matriculasDeAlumnoImpartidasPorProfesor`)
    que solo ella usaba, sin dejar código muerto. De paso, dirección
    pidió también que profesor viera la misma cuadrícula de iconos que
    dirección al elegir curso dentro de una asignatura (antes lista de
    texto): `AsignaturaNombreCursosScreen` decide grid vs lista según
    `perfil.esProfesor && !perfil.esDireccion`.

62. **Cuadro de Honor a mes vencido, solo quien llegó al objetivo.**
    Pedido en la misma reunión: dejó de ser en tiempo real sobre el mes
    en curso —una clasificación que cambia bajo los pies mientras el
    mes sigue abierto no tenía sentido como reconocimiento— y pasa a
    mostrar el MES ANTERIOR ya cerrado. `DbService.horasPorAsignaturaMensual()`
    filtra ahora `fechaInicio` entre el 1 del mes anterior y el 1 del
    mes actual (antes solo tenía cota inferior = mes en curso).
    `CuadroDeHonorScreen` solo muestra asignaturas con
    `horasObjetivoMensual > 0` y, dentro de ellas, solo alumnos con
    `horasEfectivasMes >= objetivo` — dejó de ser un ranking
    rojo/verde de todos, es un reconocimiento de quien llegó (icono de
    trofeo en vez de posición numerada).

63. **Vista global de profesor + navegación reordenada
    Asignatura → Curso → Menú.** Dos cambios entrelazados, el segundo
    corrigiendo un problema de UX real del primero, reportado al
    probar la app.
    - `SeccionesAsignaturaScreen` gana una 4ª opción, "Vista global"
      (`VistaGlobalAsignaturaScreen`, nueva,
      `lib/screens/comunes/vista_global_asignatura_screen.dart`): apila
      Asistencia de hoy, Notas y Horas de estudio en una sola ventana
      con scroll, más una sección "Progreso del objetivo este mes"
      arriba del todo (solo si `horasObjetivoMensual > 0`) que colorea
      en verde "Objetivo cumplido" o en rojo "Faltan X.X h" por
      alumno, de un vistazo. Para no duplicar lógica,
      `AsistenciasAsignaturaScreen`/`NotasAsignaturaGridScreen`/`HorasAsignaturaScreen`
      separaron su cuerpo (sin `Scaffold`/`AppBar` propios) en un
      widget `Cuerpo*Asignatura` reutilizable, usado tanto por la
      pantalla individual como por la vista global.
    - **Reordenado el flujo de profesor**: antes era
      Asignatura → Menú (Asistencias/Notas/Horas/Vista global) → Curso,
      lo que con una asignatura de un solo curso se sentía como "me
      vuelve a preguntar qué asignatura" al elegir curso después del
      menú. Ahora es Asignatura → Curso → Menú, para cualquier número
      de cursos. `AsignaturaNombreCursosScreen` perdió el parámetro
      `seccion` que antes arrastraba — ahora decide sola, por rol
      (`esProfesor() && !esDireccion()`), si tras elegir curso toca
      `SeccionesAsignaturaScreen` (profesor) o `AsignaturaDetalleScreen`
      (dirección, sin cambios). `SeccionesAsignaturaScreen` pasó de
      recibir una lista de asignaturas + nombre de grupo a recibir una
      única `Asignatura` + `cursoEscolar` ya resueltos.

64. **Medallas y roscos semanales (alumno).** Sistema de horas
    pendientes SEMANALES por asignatura, distinto del mensual/anual ya
    existente (punto 17): un "rosco" (anillo de progreso,
    `_RoscoPainter`, un `CustomPainter` de un arco simple) se rellena
    con las horas efectivas de la SEMANA EN CURSO (lunes a domingo)
    hasta `Asignatura.horasObjetivoSemanal` (ya existía, punto 52); al
    completarse se sustituye por una medalla
    (`Icons.emoji_events`). Nueva pantalla
    `MedallasRoscosScreen` (`lib/screens/alumno/`), en el menú del
    alumno junto a "Mi estudio" — solo lista asignaturas matriculadas
    CON objetivo semanal configurado. Reutiliza
    `DbService.historialAlumno()` (ya existente, "provably compliant"
    para que un alumno lea sus propias sesiones) y agrega la semana en
    cliente dentro de la propia pantalla — sin método nuevo en
    `DbService` para esta parte.

65. **Retraso configurable en la visibilidad de una nota para el
    alumno.** `Asignatura.diasRetrasoVisibilidadNotas` (int, 0 =
    visible al momento): configurable con un icono nuevo (⏱, tooltip
    "Retraso de visibilidad para el alumno") en el `AppBar` de
    `NotasAsignaturaGridScreen`, disponible para profesor Y dirección
    (a diferencia de Criterios de evaluación, que sigue siendo
    dirección-only) — guarda con
    `DbService.actualizarAsignatura(id, {'diasRetrasoVisibilidadNotas': dias})`,
    sin método dedicado nuevo. El filtro es SOLO client-side, no es un
    límite de seguridad (la nota ya era legible por quien la pone; el
    retraso es puramente de presentación para el alumno) — sin cambios
    en `firestore.rules`. `_TabNotas`
    (`alumno_en_asignatura_screen.dart`) filtra las notas ANTES de
    calcular la ponderada y la agrupación por criterio, y solo cuando
    `!puedeGestionar` (profesor/dirección ven la nota al momento
    siempre, incluso mirando el detalle de un alumno); `MisNotasScreen`
    filtra sin condición de rol, porque esa pantalla es siempre el
    propio alumno mirando sus notas.

66. **Plus de horas por orquesta.** Nuevo modelo `PlusOrquesta`
    (`lib/models/plus_orquesta.dart`: `nombre` + `asignaturaDestinoId`
    + `horasSemana`), colección `plusesOrquesta`, catálogo gestionado
    por dirección en `PlusesOrquestaScreen`
    (`lib/screens/direccion/`, menú "Gestión del centro"). Se elige un
    plus (o ninguno) al matricular o editar una matrícula —
    `Matricula.plusOrquestaId`, dropdown en `_configurarMatricula`
    (`asignatura_detalle_screen.dart`) junto al profesor de
    referencia. El plus NO crea `sesionesEstudio` sintéticas — se suma
    como extra en tiempo de agregación vía
    `DbService.plusesOrquestaAplicablesDeAlumno()` (nuevo, devuelve
    también la `fechaAlta` de la matrícula que lo aplica, para no
    proyectarlo hacia meses anteriores a que existiera), en 3 sitios:
    rosco semanal (`MedallasRoscosScreen`, exacto — `horasSemana`
    directo), cuadrícula mensual (`CuerpoHorasAsignatura`) y progreso
    de mes en curso de Vista Global (`_ProgresoObjetivoAsignatura`) —
    estos dos últimos con la aproximación `horasSemana × 4`/mes, mismo
    criterio que el objetivo anual = mensual × 12 del punto 17.
    **Alcance NO cubierto todavía** (deliberado): Informe de dirección
    y Cuadro de Honor no reflejan el plus. `firestore.rules`: nueva
    colección `plusesOrquesta` (lectura abierta, escritura solo
    dirección, valida `horasSemana >= 0`) — `matriculas` no necesitó
    cambios de reglas (la escritura ya no tenía allowlist de campos).

67. **Horario real (hora inicio/fin), horario general de dirección y
    horario visible de alumno/profesor.** El más grande del lote de la
    reunión — MVP deliberadamente simplificado, confirmado con el
    usuario antes de construir: NO es un editor de arrastrar y soltar
    ni modela huecos libres/choques, es una VISUALIZACIÓN sobre datos
    de matrícula que reutiliza el flujo de matricular ya existente
    para añadir/editar/quitar, en vez de duplicar un editor aparte.
    - `Matricula.horaInicio`/`horaFin` (`'HH:mm'`, `''` = sin
      definir): la MISMA franja se aplica a todos los días de
      `diasSemana` de esa matrícula (una clase de instrumento dura lo
      mismo cada semana; para grupales, todo el grupo comparte
      franja). Campos aditivos, no rompen nada de lo que ya dependía
      de `diasSemana`. `_configurarMatricula` gana dos botones con
      `showTimePicker` para elegirlas; `DbService.actualizarHorarioMatricula`
      (nuevo) las guarda al editar, `DbService.matricular` al crear.
    - `HorarioGeneralScreen` (dirección, nueva,
      `lib/screens/direccion/horario_general_screen.dart`): tabla hora
      × día construida sobre `todasLasMatriculasActivas` (ya existía,
      dirección-only por diseño de reglas — ver punto 42), con filtros
      de capa (instrumento/teoría, vía `permiteGrabarEstudio`) y por
      profesor, y vistas de semana completa o un día concreto
      (`SegmentedButton`) — NO hay vista de "x días" configurable.
      Tocar una clase abre una ficha con botón "Editar matrícula" que
      lleva a `AsignaturaDetalleScreen` de siempre.
    - `HorarioScreen` (alumno/profesor, nueva,
      `lib/screens/comunes/horario_screen.dart`, `HorarioModo.alumno` /
      `.profesor`): agenda agrupada por día (no tabla — para una sola
      persona se lee mejor que una rejilla). El modo profesor usa
      `DbService.matriculasDeProfesor` (nuevo): itera las asignaturas
      del profesor cross-curso y consulta `matriculasDeAsignatura` por
      cada una — mismo patrón "provably compliant" ya establecido
      (punto 25/47), no filtra `matriculas` directo por `profesorId`.
    - **Propagación automática** (pedida explícitamente): sale gratis
      de que las 3 pantallas lean la misma `Matricula` vía
      stream/fetch bajo demanda — un cambio de horario desde dirección
      se ve al momento en todas partes, sin lógica de sincronización
      aparte.
    - Sin cambios de `firestore.rules` (la escritura de `matriculas`
      ya no tenía allowlist de campos).

68. **Marcar asistencia o retraso en instrumento suma horas de
    estudio automáticamente.** Pedido en la reunión, bloqueado hasta
    tener horario real (punto 67) para saber CUÁNTO dura la clase.
    `DbService.marcarAsistencia()` llama a
    `_sincronizarSesionDeAsistencia()` (nuevo) tras guardar la
    asistencia: si `asistio == true` (incluye retraso — llegar tarde
    sigue siendo clase) en una asignatura con `permiteGrabarEstudio ==
    true` y la matrícula tiene `horaInicio`/`horaFin` configurados,
    crea/actualiza una `SesionEstudio` sintética
    (`tipo: instrumento`) con duración `horaFin - horaInicio`, ID
    determinista `asistencia_{alumnoId}_{asignaturaId}_{fecha}`
    (mismo patrón que `asistencias`/`marcajes` — volver a marcar el
    mismo día no duplica horas). Se BORRA sola si se marca "faltó", si
    la asignatura no es de instrumento, o si la matrícula no tiene
    horario configurado todavía — `delete()` sobre un doc que no
    existe no falla, así que no hace falta comprobar antes. Al vivir
    en la MISMA colección `sesionesEstudio` que las sesiones reales
    grabadas con micrófono, se suma sola en TODOS los sitios que ya
    agregan horas (rosco semanal, cuadrícula mensual, progreso de
    vista global, Cuadro de Honor) sin tocar esas pantallas. Campos
    denormalizados `origenAsistencia`/`fechaDia` (no son parte del
    modelo Dart `SesionEstudio`, ver nomenclatura de colecciones).
    `firestore.rules`: nueva función `esGeneradaPorAsistencia(data)` +
    rama nueva en `create`/`update`/`delete` de `sesionesEstudio` para
    quien puede marcar asistencia (dirección, profesor de la
    asignatura, o sustituto ese día) — misma lista de actores que la
    propia regla de `asistencias`. Tests de regresión en
    `firestore-tests/rules.test.js`, describe `'sesionesEstudio:
    sesión sintética generada al marcar asistencia'`.

69. **Franjas horarias de GRUPO configurables desde la propia
    asignatura, varias por asignatura.** (Feedback tras probar el
    punto 67, en dos rondas: primero solo se pudo definir UNA franja
    por asignatura; la propia dirección hizo notar que una misma
    asignatura teórica puede impartirse en varios grupos a días/horas
    distintos —p. ej. "Lenguaje musical" L/X 17:00-18:00 para un grupo
    y M/J 18:00-19:00 para otro— así que se generalizó a una LISTA.
    Instrumento sigue sin cambios: cada alumno con su propio horario
    por matrícula.)
    - Nueva clase `FranjaHoraria` (`lib/models/asignatura.dart`): `id`
      (generado en cliente al crearla, estable), `diasSemana`,
      `horaInicio`, `horaFin`. `Asignatura.franjasHorario` (lista,
      vacía = sin franjas de grupo, rige el horario por alumno de
      siempre — caso normal para instrumento).
    - Se edita desde `CursoDetalleScreen._mostrarFormularioAsignatura`,
      en una sección que solo aparece cuando "Permite grabar estudio"
      está DESACTIVADO (instrumento y franjas de grupo son mutuamente
      excluyentes por diseño: activar el switch limpia la lista al
      guardar). La sección lista las franjas ya creadas (con
      editar/borrar) más un botón "Añadir franja horaria" que abre
      `_mostrarFormularioFranja`, un sub-diálogo con los mismos chips
      de días + `showTimePicker` que ya se usaban para una sola franja.
    - `Matricula.franjaHorarioId` ('' = ninguna) referencia a qué
      franja pertenece ESE alumno — `diasSemana`/`horaInicio`/`horaFin`
      de la matrícula (ver punto 67) se copian de la franja elegida al
      seleccionarla (`DbService.asignarFranjaMatricula`), para que el
      horario general/de alumno/profesor sigan leyendo siempre de
      `Matricula` sin distinguir casos. En `_configurarMatricula`
      (`asignatura_detalle_screen.dart`), cuando la asignatura tiene
      franjas, el diálogo deja de pedir días/hora sueltos y en su lugar
      ofrece un desplegable para ELEGIR una franja.
    - Editar o borrar una franja desde `CursoDetalleScreen` re-sincroniza
      las matrículas que ya la tenían asignada
      (`DbService.sincronizarFranjaHoraria` si se editó,
      `limpiarFranjaDeMatriculas` si se borró — esta última deja a esos
      alumnos sin horario hasta que dirección les asigne otra franja),
      comparando por `id` las franjas antes/después de guardar — así
      cambiarla más adelante también actualiza a los alumnos ya
      matriculados en ese grupo, no solo a los nuevos.
    - **Bug real detectado al probar** (reportado como "edito una
      franja y no veo el cambio en el horario general"): crear/editar
      una franja en una asignatura que YA tenía alumnos matriculados de
      antes no los vincula solos a esa franja —`franjaHorarioId` sigue
      vacío en sus matrículas—, así que la sincronización no tiene
      nada que actualizar y el horario general se queda sin esas
      clases. Solución: icono nuevo "Asignar franja horaria en bloque"
      en el `AppBar` de `AsignaturaDetalleScreen` (dirección, solo
      visible si la asignatura tiene alguna franja), que abre un
      diálogo con un desplegable de franja + checklist de los alumnos
      ya matriculados (todos marcados por defecto) y aplica
      `DbService.asignarFranjaAMatriculas` (nuevo, un solo
      `WriteBatch`) a los seleccionados de golpe — evita tener que
      editar matrícula por matrícula, que es justo lo que las franjas
      de grupo querían evitar.
    - Sin cambios de `firestore.rules` (ni `asignaturas` ni
      `matriculas` tenían allowlist de campos).

70. **Arrastrar y soltar en el Horario general.** Pedido explícitamente
    ("sería un cambio estupendo") tras evaluar alternativas: no hay
    ningún paquete libre maduro de calendario/horario con
    arrastrar-soltar para Flutter (los que están bien pulidos, como
    Syncfusion, son de pago/freemium) y de todos modos habría que
    programar a mano la lógica de este dominio (franjas, alumnos,
    profesores) porque ninguno la modela de fábrica — se construyó con
    `LongPressDraggable`/`DragTarget`, widgets nativos del SDK de
    Flutter, sin depender de nada externo.
    - `_TablaHorario` (`horario_general_screen.dart`) pasó de mostrar
      solo las horas que ya tenían clase a una rejilla de franjas de
      MEDIA HORA fijas (con un margen de una hora antes/después del
      rango real, `_franjasDeLaRejilla`) — necesario para tener huecos
      libres donde soltar, no solo casillas ya ocupadas.
    - Cada clase es un `LongPressDraggable` (pulsación larga para no
      chocar con el tap normal, que sigue abriendo la ficha de
      siempre); cada casilla (día × hora) es un `DragTarget` que
      acepta soltar ahí una clase, con resaltado visual mientras se
      arrastra encima.
    - `DbService.moverOcurrenciaHorario` (nuevo): cambia el día
      arrastrado por el de destino en `Matricula.diasSemana`
      (conservando el resto de días si el alumno tenía varios) y
      actualiza `horaInicio`/`horaFin` a los del destino, calculando la
      hora de fin para mantener la MISMA duración que tenía. Desvincula
      la matrícula de cualquier franja de grupo que tuviera
      (`franjaHorarioId` = ''), porque su horario ya puede no coincidir
      con el resto del grupo tras moverla a mano.
    - **MVP deliberado sin detección de conflictos**: soltar una clase
      sobre una casilla ya ocupada por otra simplemente añade una
      segunda ahí, sin avisar de un choque de horario ni de que un
      profesor/aula quede doblemente ocupado. Añadir/quitar un alumno
      entero de una asignatura sigue yendo por el enlace a
      `AsignaturaDetalleScreen` de siempre — arrastrar solo reubica una
      clase que YA existe.
    - Sin cambios de `firestore.rules` (mismo camino de escritura de
      `matriculas`, dirección-only, que ya existía).

71. **Botón del asistente de Claude — UI y transporte "dejados
    preparados", SIN backend todavía.** Dirección planea montar un
    servidor propio (una Orange Pi, decidido explícitamente para no
    depender del plan Blaze de Firebase, ver puntos 5/6/13) que
    guarde la clave de la API de Claude y traduzca comandos en
    lenguaje natural ("cambia a María de las 19:00 a las 20:00") en
    acciones. Lo construido aquí es SOLO el lado de la app —
    intencionadamente, la clave de la API de Anthropic NUNCA vive en
    el cliente, y hoy no existe ningún servidor real que ejecutar
    acciones contra Firestore.
    - `BotonAsistente` (`lib/widgets/asistente_chat.dart`): FAB fijo
      superpuesto en un `Stack` por encima de TODO el `Scaffold` de
      `HomeShell` (incluido el FAB propio de la pantalla activa, si
      tiene uno — por eso `HomeShell.build()` se dividió en un método
      `_cuerpoConAppBar` + el `Stack` que lo envuelve), esquina
      inferior derecha pero desplazado a `bottom: 88` para no
      solaparse con esos FABs. Solo `perfil.esDireccion` — son quienes
      efectúan gestiones del centro.
    - Al tocarlo se abre un `DraggableScrollableSheet` con una interfaz
      de chat clásica (burbujas usuario/asistente, campo de texto,
      historial solo en memoria — se pierde al cerrar el panel, no se
      guarda en ningún sitio).
    - `AsistenteService` (`lib/services/asistente_service.dart`): hace
      `POST` a la URL configurada por dirección en Ajustes
      (`AjustesService.asistenteUrl`, nuevo, persistido con
      `shared_preferences` como el resto de Ajustes) con
      `{mensaje, historial}` y espera `{respuesta: "..."}` — un
      contrato deliberadamente simple, a falta de diseñar el backend
      real. **No ejecuta ninguna acción contra `DbService` todavía** —
      hoy solo muestra el texto que devuelva el servidor. Diseñar el
      mapeo de acciones (qué herramientas expone Claude, cómo resolver
      "María" a un `alumnoId`, confirmación antes de ejecutar) es
      trabajo futuro, a la vez que se construya ese servidor.
    - Nueva dependencia `http` (paquete oficial de dart.dev): necesaria
      porque `dart:io.HttpClient` no funciona en Flutter web, y la app
      corre en web — sin alternativa viable sin dependencia.
    - **Nota para quien monte el servidor**: en la versión web de la
      app, el navegador exige que ESE servidor responda con cabeceras
      CORS (`Access-Control-Allow-Origin`) para el origen de Sotto
      Studio, o la petición fallará solo en web (no en Android/macOS).
    - Sin cambios de `firestore.rules` (esta tanda no toca Firestore en
      absoluto).

72. **Objetivo de horas: SOLO por asignatura (se quita el del curso) +
    plus de orquesta en MINUTOS + desambiguación por curso en el
    desplegable.** Tres bugs reportados juntos tras probar el punto 66
    (plus de orquesta) y 52 (objetivo por asignatura).
    - **`Curso.horasObjetivoMensual` eliminado por completo** (campo,
      formulario de `CursosScreen`, validación en `firestore.rules`).
    Antes coexistían dos objetivos (curso y asignatura, ver punto 52)
    y confundía cuál mandaba; dirección decidió una única fuente:
    `Asignatura.horasObjetivoMensual`, porque cada asignatura tiene su
    propia cantidad de horas (p. ej. una orquesta de guitarras no
    aporta las mismas horas que "suma" a una asignatura que otra). El
    informe de dirección y el ranking global, que antes resolvían el
    objetivo vía `Curso` (agregado por curso, deduplicado), ahora
    agregan directamente `Asignatura.horasObjetivoMensual` por cada
    `asignaturaId` distinto entre las matrículas activas del alumno —
    `DbService.informeDireccion()` ya no consulta `cursos` para esto.
    El resto de vistas (ranking por asignatura, vista global, rosco
    semanal, cuadro de honor) ya usaban el objetivo de la propia
    asignatura desde el punto 52 y no necesitaron cambios.
    - **`PlusOrquesta.minutosSemana`** (antes `horasSemana`, un
      `double`): el tiempo que aporta un plus suele ser más corto que
      una hora completa (15-20 min de ensayo), así que se introduce en
      minutos (entero) en vez de forzar fracciones de hora imprecisas.
      Todo punto que antes multiplicaba por `horasSemana` para
      aproximar horas/mes (`× 4`, mismo criterio que el objetivo anual
      = mensual × 12 del punto 17) ahora convierte explícitamente
      `minutosSemana × 4 / 60` —
      `HorasAsignaturaScreen`/`VistaGlobalAsignaturaScreen`. La
      agregación semanal exacta de `MedallasRoscosScreen` pasa por
      `DbService.horasPlusOrquestaSemanalDeAlumno()`, que mantiene su
      nombre/contrato (devuelve HORAS, `double`) pero convierte
      internamente (`minutosSemana / 60.0`) — esa pantalla no necesitó
      ningún cambio. `firestore.rules`
      (`plusesOrquesta.horasSemana >= 0` →
      `plusesOrquesta.minutosSemana >= 0`) y los tests de
      `firestore-tests/rules.test.js` actualizados igual.
    - **Desambiguación por curso en `PlusesOrquestaScreen`**: el
      desplegable de "asignatura a la que suma minutos" mostraba solo
      `Asignatura.nombre` — con varias asignaturas del mismo nombre en
      cursos distintos (p. ej. 4 "Armonía", una por curso) era
      imposible saber a cuál se estaba apuntando. Ahora resuelve
      también `cursos()` y muestra `"{nombre} · {curso.nombre}"` tanto
      en el desplegable como en el listado de pluses ya creados.

73. **Auditoría de usabilidad (octubre 2026): los 6 fallos críticos.**
    Dirección (dos personas de ~50 años, poco técnicas) decide si el
    centro implanta la app, así que se revisó la app tarea por tarea
    con su perfil, el de profesor y el de alumno. Se arreglaron primero
    los fallos que impedían completar una tarea o perdían datos:
    - **Dar de baja a un alumno de una asignatura**: `desmatricular()`
      existía en `DbService` pero ninguna pantalla lo usaba. Ahora cada
      fila de `AsignaturaDetalleScreen` (dirección) tiene un menú con
      texto: "Cambiar horario, grupo o profesor" / "Dar de baja de esta
      asignatura" (con confirmación; notas/asistencias/horas se
      conservan).
    - **Editar datos, restablecer contraseña y dar de baja del centro**
      a alumnos y profesores (`lib/widgets/acciones_usuario.dart`, menú
      ⋮ en `AlumnoPerfilScreen` y `ProfesorAsignaturasScreen`). El email
      de acceso NO se puede cambiar desde la app (Firebase Auth solo lo
      permite para otra cuenta con Admin SDK = Cloud Functions/Blaze);
      se explica en el propio diálogo. "Restablecer contraseña" envía el
      email estándar de Firebase (`sendPasswordResetEmail`).
      **Baja del centro = `usuarios.activo: false` + `bajaEn`**, nunca
      se borra el documento (mismo principio que `marcajes`): se
      desactivan todas sus matrículas activas, desaparece de los
      listados (`alumnosDelCentro`/`profesoresDelCentro` filtran en
      cliente, no con `where`, porque los documentos antiguos no tienen
      el campo), `main.dart` le muestra "cuenta dada de baja" en vez de
      entrar, y **`firestore.rules` le retira todo permiso de rol**
      (`tienePermiso` exige `activo != false`). El propio usuario no
      puede cambiar su `activo`. Sección plegable "Dados de baja (N)"
      con botón "Reactivar" al final de Alumnos y Profesorado; reactivar
      NO recupera las matrículas.
    - **El profesor sustituto no llegaba a la asignatura que cubría** si
      no daba ya una del mismo nombre: no aparecía en "Mis asignaturas"
      y, aunque hubiera llegado, las reglas no le dejaban leer la lista
      de alumnos ni la asistencia ya marcada. Ahora
      `DbService.asignaturasVisiblesParaProfesor()` añade las
      asignaturas con sustitución HOY, y `firestore.rules` permite al
      sustituto leer `matriculas` (`tieneSustitucion(asignaturaId,
      hoy())`, nueva función `hoy()` en UTC — entre las 00:00 y las
      01:00/02:00 peninsulares aún cuenta como el día anterior) y
      `asistencias` de ese día. Solo HOY, no días futuros.
    - **Notas**: un campo vacío guardaba un 0, y un valor fuera de 0-10
      fallaba sin avisar (las reglas lo rechazan y la excepción no se
      capturaba). `lib/utils/validacion_nota.dart` valida en ambos
      diálogos (cuadrícula y detalle del alumno), con mensaje de error
      en el campo, y el guardado muestra éxito o un error legible.
    - **Grabación de estudio** (`GrabadorEstudioWidget`): salir de la
      pantalla grabando perdía la sesión sin avisar. Ahora el botón atrás
      pide confirmación (`PopScope`) y, si la pantalla se cierra por
      otra vía (el botón flotante de volver al menú hace `popUntil` y se
      salta `PopScope`), `dispose` detiene y guarda igualmente. Además:
      mensaje "¡Sesión guardada! Has tocado X min", aviso claro si no
      hay permiso de micrófono, botón grande con color (antes gris, con
      aspecto de desactivado), instrucciones, y "Efectivo"/"Total"
      renombrados a "Tocando"/"Tiempo total" para niños (ARB es/ca).
    - **Objetivo de horas en el formulario de la asignatura** (pedido
      expreso, ver punto 72): el formulario de crear/editar asignatura
      se extrajo a `lib/screens/direccion/formulario_asignatura.dart`
      (`crearAsignaturaEnCurso`/`editarAsignatura`) e incluye "Horas
      por semana"/"Horas por mes"; se retiró de
      `CriteriosEvaluacionScreen` (un solo sitio). Dirección puede ahora
      **editar la asignatura desde su propia ficha**: las acciones de
      dirección de `AsignaturaDetalleScreen` pasaron de iconos sueltos a
      un menú ⋮ con texto (Editar asignatura / Criterios de evaluación /
      Sustituciones / Asignar grupo a varios alumnos). En el formulario,
      "Permite grabar estudio" pasa a llamarse "Es una asignatura de
      instrumento" y "franjas horarias" pasa a "grupos y horario de
      clase" (lenguaje de dirección, no técnico); quitar un grupo pide
      confirmación.
    - De paso: mensajes de éxito al matricular/editar matrícula/crear o
      editar asignatura, errores sin texto técnico (`$e`), y la lista
      del diálogo de matricular ordenada por apellidos.
    - Tests de regresión en `firestore-tests/rules.test.js`, describes
      `'bajas del centro (usuarios.activo == false)'` y
      `'sustituto de otra asignatura: lista de alumnos y asistencia del
      día'`.
    - El resto de la auditoría se hizo en el punto 74.

74. **Auditoría de usabilidad, segunda tanda (octubre 2026)**, más un
    arreglo de la gráfica de estadísticas.
    - **Gráfica "horas de estudio por semana"** (`_TabEstadisticas`,
      `alumno_en_asignatura_screen.dart`): el eje Y lo calculaba
      fl_chart solo y, con valores pequeños, generaba muchas etiquetas
      con decimales superpuestas. `_escalaEjeHoras()` fija siempre 3-4
      marcas "redondas" (múltiplos de 1, 2 o 5 × 10^n) a partir del
      máximo, y pasa a MINUTOS si todo queda por debajo de 1 h. El
      tooltip de cada barra muestra el valor exacto con su unidad.
    - **Inicio como centro de avisos** (`lib/widgets/panel_inicio.dart`):
      dirección ve "notas finales por validar", "clases sin pasar lista
      (7 días)" y "fichajes olvidados por validar", con un toque para ir
      a cada sección (`InicioScreen.irA` → `HomeShell._abrirSeccion`,
      así la sección se abre con su barra de título igual que desde el
      menú). Profesor ve **"Mis clases de hoy"**: los alumnos con clase
      hoy según `Matricula.diasSemana` (incluidas las asignaturas que
      cubre hoy como sustituto), ordenados por hora, con los botones de
      asistencia a la vista. Nueva entrada "Inicio" en el menú (antes no
      había forma de volver a Inicio sin reiniciar la app).
    - **Menú de dirección más corto**: lo de uso ocasional (Gestionar
      cursos, Registro horario, Curso escolar, Pluses de orquesta,
      Importar) va plegado en "Configuración del centro"
      (`ExpansionTile`).
    - **Una sola fuente de cálculo** para los avisos y sus pantallas:
      `DbService.notasFinalesPorValidar()` (lo usan Inicio y
      `NotasPendientesScreen`, que además muestra ahora la nota de cada
      criterio y cuántos alumnos quedan fuera por tener criterios sin
      nota) y `DbService.asistenciasSinMarcar()` (una consulta por rango
      de fecha en vez de una lectura por alumno·asignatura·día; la
      pantalla muestra también el profesor responsable).
    - **Botones de asistencia** (`FilaAsistenciaHoy`, ahora pública en
      `asistencias_asignatura_screen.dart`): con texto
      ("Asistió/Retraso/Faltó", no solo color — accesibilidad para
      daltónicos), 40 px de alto y mensaje si falla al guardar.
    - **Buscadores** (`lib/widgets/campo_busqueda.dart`, sin distinguir
      mayúsculas ni acentos) en Alumnos y en el diálogo de matricular.
    - "Nueva asignatura" directamente desde "Asignaturas" (pide primero
      el curso), además de desde Gestionar cursos.
    - Calendarios (`TableCalendar`) en el idioma de la app y empezando
      en lunes (`initializeDateFormatting()` en `main.dart`); fechas
      dd/mm/aaaa en Registro horario, Mis fichajes y Sustituciones;
      confirmación con la hora antes de fichar (el fichaje no se puede
      editar); confirmación al anular una sustitución; sin doble barra
      de título en Horario general; botón del asistente oculto mientras
      no haya URL configurada en Ajustes; "Recalcular grupos de
      asignatura" (migración de un solo uso) solo en modo desarrollador;
      textos de matrícula sin jerga ("Profesor habitual", "Grupo de
      clase").
    - **Validar nota final**: dirección decidió un único botón
      "Validar nota final" en `NotasPendientesScreen` (antes
      "supervisada"/"corregida" sin diferencia real). Se guarda como
      `EstadoNota.supervisada`; `corregida` queda solo por
      compatibilidad con notas antiguas. En pantalla el estado se
      muestra como "Pendiente de validar"/"Validada por dirección"
      (`EstadoNota.etiqueta`), nunca el nombre técnico del enum.
    - "Alumnos" va dentro de "Gestión del centro" en el menú de
      dirección (antes quedaba suelto encima).
    - **Selector de idioma: se mantiene visible a propósito** — antes de
      desplegar la versión final se traducirá TODO lo que falte (y a
      más idiomas); ver punto 34.

75. **Auditoría de usabilidad, tercera tanda (octubre 2026).**
    - **Matricular desde la ficha del alumno** (`AlumnoPerfilScreen`,
      botón "Matricular en una asignatura" con buscador de asignatura +
      curso): dirección piensa "por alumno". La lógica de configurar y
      guardar la matrícula es una sola, `configurarYMatricular()` en
      `asignatura_detalle_screen.dart`, usada desde ambos lados. La
      ficha lista sus asignaturas con curso, días y hora, y abre la
      ficha de cada una. Al crear un alumno, `CrearAlumnoScreen` ofrece
      "Matricular ahora" y lleva a su ficha (necesita `perfil`).
    - **Pasar lista** (`CuerpoAsistenciasAsignatura`): por defecto solo
      los alumnos con clase HOY según `Matricula.diasSemana`, con
      interruptor "Ver también a los que no tienen clase hoy".
    - **Corregir/borrar una nota mal puesta** (`_TabNotas`, icono de
      lápiz en cada nota; también se ve la fecha de la nota):
      dirección siempre; el profesor que la puso, mientras siga
      pendiente de validar. `firestore.rules` (`notas`): el autor puede
      borrar su nota pendiente, y al corregirla solo puede cambiar
      valor/comentario (no alumno, asignatura, criterio ni estado —
      antes la regla de update no fijaba esos campos). Tests en el
      describe `'notas: corregir o borrar una nota mal puesta'`.
    - **Sustituir a un profesor en todas sus clases**
      (`SustitucionProfesorScreen`, botón "Sustituir" en la ficha del
      profesor): sustituto + días + asignaturas (todas marcadas por
      defecto); crea los mismos documentos de `sustituciones` que
      `SustitucionesScreen`, uno por asignatura y día.
    - **Horario general**: texto que explica tocar/arrastrar, y
      "Deshacer" en el aviso tras mover una clase (restaura días, horas
      y grupo de la matrícula).
    - **Errores legibles**: `lib/utils/mensaje_error.dart`
      (`mensajeError(e, porDefecto:)`) sustituye a mostrar `$e` tal cual
      — traduce códigos de Firebase y deja pasar los `Exception('...')`
      propios. `lib/widgets/error_carga.dart` (`ErrorCarga`) en ~50
      listas que antes solo comprobaban `hasData` y se quedaban con la
      rueda girando si fallaba la carga — usarlo en cualquier
      `StreamBuilder`/`FutureBuilder` nuevo.
    - Detalles: leyenda de colores en el calendario del alumno
      (asistencia y estudio); textos de ayuda sobre qué casillas se
      pueden tocar en las cuadrículas de notas y horas; "Nota final" en
      vez de "Ponderada" (Mis notas); "Informe de horas de estudio" en
      vez de "efectivas"; icono propio (ojo) para "Cuándo ve el alumno
      sus notas"; plurales correctos; login con scroll (el teclado ya
      no tapa el botón en móviles pequeños); los botones de asistencia
      de la ficha de asignatura también llevan texto.
    - Lo que quedaba (contacto de la familia, ayuda) se hizo en el
      punto 76.

76. **Contacto de la familia y ayuda para usuarios nuevos** (cierre de
    la auditoría de usabilidad).
    - **`contactosAlumno/{alumnoId}`** (`ContactoAlumno`): tutor legal,
      teléfono, email de la familia, otro teléfono y observaciones.
      Colección APARTE de `usuarios` a propósito: `usuarios` lo lee
      cualquier profesor, y estos son datos personales de menores —
      `firestore.rules` solo deja leer/escribir a dirección (ni
      profesor ni el propio alumno) y nunca borrar. Sin datos de salud
      (el diálogo lo advierte). Se ve y edita en `AlumnoPerfilScreen`
      ("Contacto de la familia"). Criterio elegido por defecto sin
      confirmar con dirección: si se pide que el profesorado también lo
      vea, es cambiar la regla (y su test). Tests en el describe
      `'contactosAlumno: datos de la familia solo para dirección'`.
    - **Ayuda** (`AyudaScreen`, entrada "Ayuda" en el menú para todos):
      preguntas "¿Cómo hago...?" desplegables, solo las del perfil de la
      cuenta, con pasos que nombran los textos EXACTOS de menús y
      botones — **si se renombra un menú o botón, actualizar también
      `ayuda_screen.dart`**. En Inicio, tarjeta "¿Primera vez en Sotto
      Studio?" con "Ver la ayuda"/"Entendido"
      (`AjustesService.bienvenidaVista`, local por dispositivo).
    - En la cuadrícula de notas, el nombre del alumno abre su ficha en
      la pestaña Notas (antes el profesor no tenía un camino directo
      para corregir o borrar una nota).
    - Textos de 10-11 px subidos a 12 px.

## Nomenclatura de colecciones (fija, no renombrar sin avisar)

`usuarios`, `sesionesEstudio`, `modulos`, `ejercicios`,
`ejerciciosCompletados`, `notas`, `estadisticasAlumno`, `cursos`,
`asignaturas`, `matriculas`, `asistencias`, `criteriosEvaluacion`,
`sustituciones`, `horariosLaborales`, `marcajes`, `configuracion`,
`gruposAsignatura`, `incidencias`, `plusesOrquesta`, `contactosAlumno`.

- `usuarios.activo` (bool, default `true`) y `usuarios.bajaEn`
  (ISO8601): baja del centro sin borrar el documento — ver punto 73.
- `usuarios.email` (nullable) y `usuarios.tieneCuenta` (bool, default
  `true`) — un alumno sin cuenta de Firebase Auth (creado con
  `AuthService.crearAlumnoSinCuenta`) no tiene email ni uid real
  detrás — ver punto 57.
- `incidencias.autorNombre` (denormalizado al crear, mismo patrón que
  `sesionesEstudio.alumnoNombre`) y `incidencias.comentarios` (lista
  embebida, no subcolección) — ver punto 58, modo desarrollador.
- `asignaturas.nombreNormalizado` (`nombre.trim().toLowerCase()`,
  derivado, no es un campo del modelo `Asignatura` en Dart) y la
  colección `gruposAsignatura/{nombreNormalizado}`
  (`{ profesorIds: [...] }`, mantenida en cliente) — ver punto 51,
  permiso cruzado entre cursos.
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
- `sesionesEstudio.registradoPorProfesorId` (nullable, sí es un campo
  del modelo `SesionEstudio` en Dart, a diferencia de `alumnoNombre`):
  identifica una sesión de horas de teoría anotada a mano por un
  profesor, no grabada por el alumno — ver punto 53.
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
- `cursos.nivel`/`cursos.numeroCurso` y `cursos.iconoId` — ver puntos
  20 y 29. **`cursos.horasObjetivoMensual` existió entre los puntos 17
  y 71, retirado por completo en el punto 72** — el objetivo de horas
  vive SOLO en `Asignatura` ahora, no reintroducirlo en `Curso`.
- `asignaturas.horasObjetivoSemanal`/`horasObjetivoMensual` (double, 0
  = sin objetivo) — ÚNICA fuente de objetivo de horas de toda la app
  desde el punto 72 (antes coexistía con `cursos.horasObjetivoMensual`,
  ver punto 52 para el histórico).
- `asistencias.retraso` (bool, `false` por defecto) — ver punto 18.
- `marcajes.pendienteValidacion` (bool, `false` por defecto) — ver
  punto 32.
- `usuarios.ultimaVisita` (ISO8601, escrito por el propio usuario vía
  `DbService.registrarVisitaYObtenerAnterior`): no forma parte del
  modelo `Usuario` en Dart, solo se usa para calcular avisos in-app
  (ver punto 13).
- `usuarios.puedeGrabarEstudio` (bool, `true` por defecto, sí es un
  campo del modelo `Usuario` en Dart): permiso global por alumno para
  usar la grabación de estudio con micrófono — ver punto 55.
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
- `asignaturas.diasRetrasoVisibilidadNotas` (int, 0 = visible al
  momento) — ver punto 65.
- `matriculas.horaInicio`/`horaFin` (`'HH:mm'`, `''` = sin definir,
  misma franja para todos los días de `diasSemana`) y
  `matriculas.plusOrquestaId` (`''` = ninguno, referencia a
  `plusesOrquesta/{id}`) — ver puntos 66 y 67.
- `asignaturas.franjasHorario` (lista de `{ id, diasSemana, horaInicio,
  horaFin }`, ver `FranjaHoraria`): franjas horarias de GRUPO, solo
  para asignaturas que NO permiten grabar estudio — lista vacía = sin
  franjas de grupo, rige el horario individual por matrícula de
  siempre. `matriculas.franjaHorarioId` (`''` = ninguna) referencia a
  cuál de esas franjas pertenece cada alumno; sus días/hora se copian
  a `matriculas.diasSemana`/`horaInicio`/`horaFin` al elegirla y se
  re-sincronizan si la franja cambia después — ver punto 69.
- `plusesOrquesta`: `{ nombre, asignaturaDestinoId, minutosSemana,
  createdAt, createdBy }` (`minutosSemana`, int, antes `horasSemana`
  double — ver punto 72), dirección-only, catálogo elegido al
  matricular — ver punto 66.
- `sesionesEstudio.origenAsistencia` (bool, solo presente en sesiones
  sintéticas generadas al marcar asistencia) y
  `sesionesEstudio.fechaDia` (`'yyyy-MM-dd'`, derivado de
  `fechaInicio`, mismo patrón que `Nota.fechaDia`) — ninguno de los
  dos es campo del modelo Dart `SesionEstudio`, solo para que
  `firestore.rules` identifique y gestione estas sesiones — ver punto
  68.

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
  todas las plataformas (ver punto 44); navegación principal invertida
  a asignatura-primero-curso-dentro para dirección y profesor (ver
  punto 46, `AsignaturasPorNombreScreen`); marcar asistencia desde
  "Alumnos" para profesor, scope seguro por asignatura (ver punto 47 —
  **retirado en el punto 61**, `AlumnoAsistenciaHoyScreen` ya no
  existe, sustituida por la Vista global del punto 63); cuadrícula de
  notas por asignatura (ver
  punto 48, `NotasAsignaturaGridScreen`); colores de asistencia en el
  calendario del alumno (ver punto 49); bug de nombres en blanco del
  Cuadro de Honor arreglado (ver punto 50); alumnos en orden alfabético
  por apellidos sin agrupar por curso; permiso cruzado entre cursos
  por nombre de asignatura vía `gruposAsignatura` (ver punto 51);
  menú "Asignaturas" renombrado y tamaño de letra ampliado hasta 1.6×;
  objetivo de horas configurable por asignatura desde Criterios de
  evaluación (ver punto 52); registro manual de horas de teoría por el
  profesor (ver punto 53); Cuadro de Honor por bloques de curso y
  asignatura, visible para todos (ver punto 54); notas pendientes
  visibles por criterio, excepción de grabación por alumno,
  navegación por secciones (Asistencias/Notas/Horas) para profesor
  puro y fusión de Ranking en Horas de estudio con Cuadro de Honor por
  bloques personalizable (ver punto 55); volver a un curso escolar
  anterior y eliminarlo del historial con avisos (ver punto 56);
  alumnos sin cuenta de acceso e importación masiva desde plantilla
  Excel (ver punto 57, `ImportarDatosScreen`); modo desarrollador con
  simulación de rol y apartado de incidencias (ver punto 58); reversión
  del acceso a grabación por alumno (vuelve a ser solo por asignatura),
  cuadrícula mensual editable de horas de estudio, alumnos agrupados
  por letra inicial, roster de asignatura agrupado por profesor, notas
  pendientes reducidas a validar solo la nota final por criterios
  completos, y Cuadro de Honor con un único criterio (curso →
  asignatura) — ver punto 59; retirada de "Alumnos" para profesor y
  cuadrícula de iconos al elegir curso (ver punto 61); Cuadro de Honor
  a mes vencido, solo quien llegó al objetivo (ver punto 62); vista
  global de profesor (Asistencia+Notas+Horas+progreso del objetivo en
  una ventana) y navegación reordenada Asignatura→Curso→Menú (ver
  punto 63, `VistaGlobalAsignaturaScreen`); medallas y roscos
  semanales del alumno (ver punto 64, `MedallasRoscosScreen`); retraso
  configurable de visibilidad de notas (ver punto 65); plus de horas
  por orquesta (ver punto 66, `PlusesOrquestaScreen`); horario real
  (hora inicio/fin), horario general de dirección y horario visible de
  alumno/profesor con propagación automática (ver punto 67,
  `HorarioGeneralScreen` + `HorarioScreen`); asistencia en instrumento
  sumando horas de estudio automáticamente (ver punto 68); horario de
  grupo configurable desde la propia asignatura para asignaturas
  teóricas, propagado a todas sus matrículas (ver punto 69); arrastrar
  y soltar en el Horario general (ver punto 70); botón de asistente de
  Claude dejado preparado en UI/transporte, sin backend todavía (ver
  punto 71); objetivo de horas unificado solo en `Asignatura` (retirado
  de `Curso`), plus de orquesta en minutos y desambiguación por curso
  en su desplegable (ver punto 72).
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
