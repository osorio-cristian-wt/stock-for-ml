# Firebase (FCM) + push en iOS / TestFlight

## Aclaración importante (Firebase ≠ TestFlight)

**Firebase y TestFlight son cosas distintas y no se "conectan" entre sí:**

- **TestFlight** = distribución beta de la app (Apple). De eso se encarga el
  pipeline de [ci-cd.md](ci-cd.md).
- **Firebase Cloud Messaging (FCM)** = servicio para enviar **notificaciones
  push**. Es lo que usamos para "stock bajo" y "nueva venta".

El único punto de unión real es: **para que los push lleguen a un iPhone (incluida
una build instalada por TestFlight), Apple exige una APNs Authentication Key, que
se sube a Firebase.** Una build de TestFlight recibe push exactamente igual que
una de App Store. No hay un paso "conectar Firebase con TestFlight"; lo que se
configura es **Firebase ↔ APNs (Apple Push Notification service)**.

## Paso a paso

### 1. Crear el proyecto de Firebase
1. https://console.firebase.google.com → **Add project** → nombre `stock-for-ml`.
2. (Opcional) deshabilitar Google Analytics si no lo querés.

### 2. Registrar la app iOS en Firebase
1. En el proyecto → **Add app** → iOS.
2. **Bundle ID**: `com.stockforml.stockForMl` (el del proyecto; ver ci-cd.md si lo cambiás).
3. Descargar **`GoogleService-Info.plist`** y colocarlo en
   `apps/mobile/ios/Runner/GoogleService-Info.plist` (agregarlo al target Runner
   en Xcode). *(Para Android, más adelante: `google-services.json` en `apps/mobile/android/app/`.)*

### 3. Crear la APNs Authentication Key (Apple)
1. https://developer.apple.com → **Certificates, Identifiers & Profiles → Keys**.
2. **+** → nombre, marcar **Apple Push Notifications service (APNs)** → Continue → Register.
3. Descargar el archivo **`AuthKey_XXXXXX.p8`** (¡solo se descarga una vez!).
4. Anotar el **Key ID** y tu **Team ID**.

### 4. Subir la APNs key a Firebase
1. Firebase → **Project settings → Cloud Messaging → Apple app configuration**.
2. En **APNs Authentication Key** → Upload → subir el `.p8` + Key ID + Team ID.

### 5. Habilitar Push en el proyecto iOS
1. En Xcode (`apps/mobile/ios/Runner.xcworkspace`) → target Runner → **Signing &
   Capabilities** → **+ Capability** → **Push Notifications**.
2. Agregar también **Background Modes → Remote notifications** si querés push en background.
3. Verificar el entitlement `aps-environment` (lo maneja el perfil de match).

### 6. Integración en Flutter (etapa de implementación, no ahora)
Cuando lleguemos a notificaciones, se agregan los paquetes:
`firebase_core`, `firebase_messaging` (y `flutterfire configure` para generar
`firebase_options.dart`). El token FCM del dispositivo se guarda en Supabase y
las Edge Functions disparan los push.

## Credenciales que necesito de vos

Ver la sección consolidada en [setup.md](setup.md#credenciales-pendientes) o el
resumen que te paso por chat. En síntesis:

- **Archivo** `GoogleService-Info.plist` (de Firebase) → lo agrego al repo/app.
- Para CI de push/iOS (como **GitHub Secrets**, no por chat): App Store Connect
  API key (`.p8` + Key ID + Issuer ID), Team ID, y los de `match`
  (ver [ci-cd.md](ci-cd.md)).
- La **APNs `.p8`** se sube a Firebase (no hace falta en el repo).
