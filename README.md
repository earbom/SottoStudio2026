# Sotto Studio

App multiplataforma (Android · iOS · macOS · Web) para que un centro de
enseñanza musical sepa cuánto estudian de verdad sus alumnos en casa —
no solo en clase — y para gestionar el día a día del centro: cursos,
matrículas, asistencia, notas, ranking de horas de estudio, registro
horario del profesorado y herramientas de práctica (afinador y
metrónomo).

Desarrollada a medida para el **Centre d'Estudis Musicals Haro**, en
piloto real con alumnado, profesorado y dirección del centro.

## Descripción

La necesidad de partida es simple de enunciar y difícil de resolver
bien: un profesor de instrumento sabe cómo toca un alumno en clase,
pero no cuánto —ni cómo— practica en casa entre semana. Sotto Studio
cierra ese hueco midiendo el tiempo de práctica **efectiva** (no solo
que el móvil esté encendido: que se esté tocando de verdad) a partir
de la amplitud del micrófono en tiempo real, sin grabar ni guardar
nunca el audio — es una app usada por menores, así que la privacidad
no es negociable.

Sobre esa base de medición se construye el resto del centro: matrícula
por curso escolar, notas ponderadas por criterios de evaluación
configurables, asistencia con sustituciones de profesorado, un ranking
de horas de estudio, informe de horas efectivas para dirección, y el
registro horario legal del profesorado (fichajes de entrada/salida,
conforme al Art. 34.9 del Estatuto de los Trabajadores). Incluye
también un afinador y un metrónomo como herramientas de práctica
independientes.

## Stack técnico

**Origen del proyecto.** La primera versión se construyó en
**Java + Android SDK nativo**, con **Room** como capa de persistencia
local y **MySQL/MariaDB** como backend remoto. Esa arquitectura cubría
Android, pero el centro necesitaba llegar también a iOS (donde no hay
alternativa nativa sin duplicar por completo la base de código) y a
macOS (el equipo que usa dirección), y los datos de un alumno tienen
que llegar en tiempo real a su profesor y a dirección — un backend a
medida con almacenamiento puramente local no encajaba con ese
requisito.

**Versión actual: Flutter + Firebase.**

| Capa | Tecnología |
|---|---|
| UI multiplataforma | Flutter / Dart, una sola base de código para Android, iOS, macOS y Web |
| Autenticación | Firebase Authentication |
| Base de datos | Cloud Firestore (tiempo real, offline-first) |
| Reglas de acceso | `firestore.rules` — permisos por rol y por documento, no solo en el cliente |
| Backend serverless | Cloud Functions (Node.js) para agregados que no debe poder manipular el cliente |
| Gráficas | `fl_chart` |
| Calendario | `table_calendar` |
| Audio (metrónomo) | `audioplayers` |
| Notificaciones locales | `flutter_local_notifications` |
| Exportación | `pdf` / `printing` (boletines), `excel` (registro horario) |
| Internacionalización | `flutter_localizations` + ARB (castellano / català) |
| Distribución | APK firmado (Android), PWA instalable (iOS/Android), app nativa (macOS) |

## Funcionalidades principales

- **Medición de práctica efectiva sin grabar audio**: análisis de
  amplitud en tiempo real con una lógica de 3 estados (tocando →
  efectivo; silencio corto entre frases → sigue contando; silencio
  largo → deja de contar, pero se refleja en el tiempo total), pensada
  para no penalizar las pausas normales de un ensayo.
- **Permisos combinables por cuenta**: alumno, profesor y dirección no
  son roles excluyentes — una misma cuenta puede tener varios a la vez
  (p. ej. una directora que también da clase).
- **Gestión académica completa**: cursos organizados por nivel
  (sensibilización, elemental, avanzado, libre), asignaturas,
  matrícula por curso escolar (con histórico de cursos anteriores),
  asistencia con sustituciones temporales de profesorado, notas
  ponderadas por criterios de evaluación configurables, boletín en PDF.
- **Ranking de horas de estudio**: por asignatura (solo
  profesor/dirección, por privacidad de menores) y un "cuadro de
  honor" global de horas de instrumento, visible también para los
  alumnos como excepción deliberada.
- **Registro horario del profesorado**: fichaje de entrada/salida,
  autoinforme de un día olvidado con validación de dirección,
  exportación a Excel — conforme al Art. 34.9 del Estatuto de los
  Trabajadores.
- **Herramientas de práctica**: afinador (detección de frecuencia por
  autocorrelación, con catálogo de instrumentos y afinaciones
  alternativas) y metrónomo (reloj absoluto para que el tempo no se
  desvíe en sesiones largas), accesibles a cualquier usuario.
- **Bilingüe** (castellano / català) e instalable en cualquier
  dispositivo del centro.

## Decisiones técnicas destacadas

- **Las reglas de seguridad de Firestore son la fuente de verdad**,
  no una capa cosmética: cada permiso descrito arriba está también
  reforzado en `firestore.rules`, con más de 40 tests automatizados
  contra el emulador de Firestore (`firestore-tests/`) que verifican
  tanto lo que cada rol puede hacer como lo que explícitamente NO
  puede hacer.
- **Nunca se persiste audio**, por diseño — solo se procesa en memoria
  para leer su amplitud. Con menores de edad implicados, era una
  restricción de partida, no una optimización posterior.
- **IDs deterministas** (`{alumnoId}_{asignaturaId}_{cursoEscolar}`,
  etc.) para que operaciones como matricular o marcar asistencia sean
  idempotentes por diseño, sin lecturas previas para comprobar
  duplicados.
- **Reloj absoluto en el metrónomo** (cada tick se reprograma contra
  la hora objetivo desde el inicio, no contra un intervalo fijo
  repetido) para que no se acumule deriva en sesiones largas.

## Estructura del proyecto

```
lib/
  models/        Usuario, Curso, Asignatura, Matricula, Nota, SesionEstudio, Marcaje...
  services/      AuthService, DbService, GrabadorEstudio (3 estados), MetronomoService, AfinadorService...
  screens/
    comunes/     login, menú, ajustes, afinador, metrónomo, cuadro de honor...
    alumno/      dashboard, grabar estudio, historial, notas
    profesor/    dashboard agrupado por curso
    direccion/   cursos, alumnos, profesorado, informe de horas, registro horario...
  l10n/          traducciones (ARB, castellano/català)
  main.dart      enrutado según rol tras login
functions/       Cloud Function de agregación (estadisticasAlumno)
firestore.rules          reglas de seguridad por rol y por documento
firestore-tests/         tests automatizados de firestore.rules contra el emulador
CLAUDE.md                contexto de negocio y decisiones técnicas, mantenido junto al código
```

## Cómo ejecutar el proyecto

### Requisitos previos

- Flutter SDK instalado (`flutter --version` para comprobar).
- Cuenta de Firebase (gratuita) y Firebase CLI: `npm install -g firebase-tools`.
- `dart pub global activate flutterfire_cli`.

### 1. Instalar dependencias

```bash
flutter pub get
```

### 2. Crear el proyecto Firebase y conectarlo

1. Crea un proyecto en [console.firebase.google.com](https://console.firebase.google.com).
2. Activa **Authentication** → método Email/Contraseña.
3. Activa **Firestore Database** (las reglas ya están en `firestore.rules`).
4. Conecta el proyecto:
   ```bash
   firebase login
   flutterfire configure
   ```
   Esto genera `lib/firebase_options.dart` (deliberadamente fuera del
   repo, ver `.gitignore`) y registra las apps de cada plataforma.
5. Sube las reglas de seguridad:
   ```bash
   firebase deploy --only firestore:rules
   ```

### 3. Permisos de micrófono

Necesarios para el detector de práctica y el afinador:

- **Android**: `android.permission.RECORD_AUDIO` en `AndroidManifest.xml` (ya incluido).
- **iOS**: `NSMicrophoneUsageDescription` en `Info.plist`.
- **macOS**: `com.apple.security.device.audio-input` en los `.entitlements` + `NSMicrophoneUsageDescription` en `Info.plist`.

### 4. Ejecutar

```bash
flutter run
```

### Tests de las reglas de seguridad

```bash
cd firestore-tests
npm install   # solo la primera vez
npm test      # requiere el emulador de Firestore, se levanta solo
```

### Cloud Function `estadisticasAlumno` (opcional)

Escrita pero no desplegada — exige el plan Blaze del proyecto Firebase.
Mientras tanto, `DbService.informeDireccion()` agrega los datos en el
propio cliente. Detalle completo en `CLAUDE.md`.

## Roadmap / backlog conocido

El detalle completo de decisiones de producto, reglas de negocio y
qué queda pendiente se mantiene vivo en [`CLAUDE.md`](./CLAUDE.md).
A grandes rasgos, sigue pendiente:

- Registro público de alumno (hoy el alta la hace siempre dirección).
- Pantalla de gestión de ejercicios/módulos.
- Traducción al català del resto de la app (hoy solo las pantallas de
  mayor uso: login, menú, inicio, fichar, grabar estudio, ajustes).
- Desplegar la Cloud Function de `estadisticasAlumno` cuando el centro
  active el plan Blaze.

## Autoría

Proyecto diseñado y desarrollado en solitario —producto, modelo de
datos, reglas de seguridad, frontend Flutter y despliegue en las tres
plataformas— por:

**Edgar Arbó Marbá**
[LinkedIn](https://www.linkedin.com/in/edgar-arb%C3%B3-marb%C3%A1-6a4282332/) ·
[GitHub](https://github.com/earbom/SottoStudio2026) ·
[earbo@proton.me](mailto:earbo@proton.me)
