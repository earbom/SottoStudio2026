# Sotto Studio — Scaffold Flutter

App de gestión de práctica musical para **Centre d'Estudis Musicals Haro**.
Este scaffold sustituye la versión anterior en Java/Android + Room.

## 1. Requisitos previos

- Flutter SDK instalado (`flutter --version` para comprobar).
- VS Code con la extensión oficial **Flutter** (instala también Dart automáticamente).
- Extensión de **Claude Code** ya instalada en VS Code.
- Cuenta de Firebase (gratuita) y Firebase CLI: `npm install -g firebase-tools`.
- `dart pub global activate flutterfire_cli`.

## 2. Importar el proyecto en VS Code

1. Descomprime este proyecto en la carpeta donde trabajes habitualmente.
2. En VS Code: `Archivo → Abrir carpeta…` y selecciona la carpeta `sotto_studio`.
3. VS Code detectará el proyecto Flutter automáticamente (verás el selector de dispositivo en la barra inferior).
4. Abre una terminal integrada (`` Ctrl+` ``) y ejecuta:
   ```bash
   flutter pub get
   ```
   Esto descarga las dependencias listadas en `pubspec.yaml` (Firebase, `record`, `provider`, etc.).

## 3. Crear el proyecto Firebase y conectarlo

1. Ve a [console.firebase.google.com](https://console.firebase.google.com) y crea un proyecto nuevo (por ejemplo `sotto-studio`).
2. Activa **Authentication** → método Email/Contraseña.
3. Activa **Firestore Database** → modo producción (las reglas ya están preparadas en `firestore.rules`).
4. Desde la terminal, dentro de la carpeta del proyecto:
   ```bash
   firebase login
   flutterfire configure
   ```
   Esto genera automáticamente `lib/firebase_options.dart` (el `main.dart` ya lo importa) y registra las apps Android/iOS/macOS en tu proyecto Firebase.
5. Sube las reglas de seguridad:
   ```bash
   firebase deploy --only firestore:rules
   ```
   (requiere haber inicializado Firebase en la carpeta con `firebase init firestore` la primera vez, apuntando a este mismo `firestore.rules`).

## 4. Permisos de micrófono (necesarios para el detector de práctica)

- **Android**: añadir en `android/app/src/main/AndroidManifest.xml`:
  ```xml
  <uses-permission android:name="android.permission.RECORD_AUDIO" />
  ```
- **iOS**: añadir en `ios/Runner/Info.plist`:
  ```xml
  <key>NSMicrophoneUsageDescription</key>
  <string>Sotto Studio necesita el micrófono para medir tu tiempo de práctica.</string>
  ```
- **macOS**: en `macos/Runner/DebugProfile.entitlements` y `Release.entitlements`, añadir:
  ```xml
  <key>com.apple.security.device.audio-input</key>
  <true/>
  ```
  y en `Info.plist` el mismo `NSMicrophoneUsageDescription` que iOS.

## 5. Ejecutar

Con un dispositivo/emulador seleccionado en VS Code, pulsa F5 (o `flutter run` en terminal).

## 6. Estructura del proyecto

```
lib/
  models/          Usuario, SesionEstudio, Nota
  services/        AuthService, DbService, GrabadorEstudio (lógica de 3 estados)
  screens/
    comunes/       login
    alumno/        dashboard, grabar estudio
    profesor/      dashboard
    direccion/     informe de horas efectivas
  main.dart        enrutado según rol tras login
functions/          Cloud Function que agrega estadisticasAlumno
firestore.rules     reglas de seguridad (alumno/profesor/dirección)
firestore.indexes.json  índices compuestos que exigen las consultas de DbService
CLAUDE.md           contexto de negocio para trabajar con Claude Code
```

## 6bis. Cloud Function: `estadisticasAlumno`

> **Estado actual: escrita pero NO desplegada.** Desplegar Cloud
> Functions exige el plan Blaze (pago por uso) en el proyecto Firebase,
> y en esta fase de pruebas se ha decidido no activarlo — será el
> centro quien lo contrate si el proyecto sigue adelante. Mientras
> tanto, `DbService.informeDireccion()` calcula las horas efectivas
> agregando `sesionesEstudio` directamente en el cliente (ver el
> comentario en ese método). Cuando se active Blaze: desplegar esta
> función y volver a leer `estadisticasAlumno` en `informeDireccion()`
> en vez de agregar en el cliente.

`functions/index.js` define `actualizarEstadisticasAlumno`: un trigger
`onDocumentCreated` sobre `sesionesEstudio/{sesionId}` que sube (con
`FieldValue.increment`) los acumulados de `estadisticasAlumno/{alumnoId}`:
`msEfectivoTotal`, `msTotalAcumulado`, `horasEfectivasTotales`,
`horasTotalesTotales`, `numeroSesiones` y `ultimaSesionFecha`. Es la
única escritura permitida en esa colección (`firestore.rules` bloquea
la escritura del cliente), así ningún alumno puede inflar su ranking
editando Firestore directamente desde la app.

Primer despliegue (requiere el proyecto Firebase ya creado y
`firebase login` hecho):

```bash
cd functions && npm install && cd ..
firebase init firestore   # solo la primera vez, si no existía firebase.json
firebase deploy --only firestore:rules,firestore:indexes,functions
```

Para probarla en local sin tocar el proyecto real:

```bash
cd functions && npm install && cd ..
firebase emulators:start --only firestore,functions --project demo-sotto-studio
```

Desde la UI del emulador (puerto por defecto 4000) puedes crear a mano
un documento en `sesionesEstudio` con `alumnoId`, `duracionEfectivaMs`
y `duracionTotalMs`, y comprobar que aparece/crece el documento
correspondiente en `estadisticasAlumno`.

## 7. Pendiente (backlog conocido, ver CLAUDE.md para detalle)

- Pantallas de registro, historial, ejercicios, ranking, gestión de módulos, poner nota, listado de profesorado.
- Migrar metrónomo y afinador desde la versión Java/Android.
- Calibración real del umbral de silencio (`umbralDb` en `GrabadorEstudio`) con al menos 3 instrumentos distintos.
- Reconocimiento de compatibilidad de timbre con el instrumento del perfil (fase posterior, no v1).
- Logo de la app (ver `brief_logo_sotto_studio.md` si lo tienes en la misma carpeta de descargas).
