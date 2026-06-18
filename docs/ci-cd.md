# CI/CD — stock-for-ml

## Workflows

| Workflow | Archivo | Cuándo corre | Qué hace |
|----------|---------|--------------|----------|
| **CI** | [.github/workflows/ci.yml](../.github/workflows/ci.yml) | push a `main`, PRs | `flutter analyze` + tests (core_models, app), tests Deno de Edge Functions, tests pgTAP de la base |
| **iOS · TestFlight** | [.github/workflows/ios-testflight.yml](../.github/workflows/ios-testflight.yml) | manual (`workflow_dispatch`) o push de tag `v*` | build del IPA firmado y subida a TestFlight con fastlane |

Arrancamos los deploys por **iOS**. Android se agrega después (Google Play
Internal Testing, mismo patrón con otra lane de fastlane).

## Pipeline de iOS (resumen)

```
tag v0.1.0 / run manual
      │
      ▼
macOS runner ──► flutter build ios (compila Dart, genera config) 
      │
      ▼
fastlane beta ──► match (trae certificados) ──► build_app (gym, firma) ──► upload_to_testflight
      │
      ▼
TestFlight (procesa el build) ──► testers internos
```

Firma de código vía **fastlane match**: los certificados y perfiles se guardan
cifrados en un **repo git privado** y el runner los baja en modo `readonly`.

## Secrets de GitHub requeridos

Configurar en **GitHub → Settings → Secrets and variables → Actions**:

| Secret | Qué es | De dónde sale |
|--------|--------|---------------|
| `APP_STORE_CONNECT_API_KEY_ID` | Key ID de la API key | App Store Connect → Users and Access → Integrations → App Store Connect API |
| `APP_STORE_CONNECT_API_ISSUER_ID` | Issuer ID | misma pantalla |
| `APP_STORE_CONNECT_API_KEY` | Contenido del `.p8` en **base64** | el archivo `.p8` que se descarga al crear la key (`base64 -i AuthKey_XXXX.p8`) |
| `APPLE_TEAM_ID` | Team ID (10 caracteres) | Apple Developer → Membership |
| `MATCH_GIT_URL` | URL del repo privado de certificados | repo git que creás para match |
| `MATCH_PASSWORD` | Passphrase de cifrado de match | la elegís vos al correr `match` la 1ª vez |
| `MATCH_GIT_BASIC_AUTHORIZATION` | Auth para clonar el repo de certs | `echo -n usuario:PAT \| base64` (PAT de GitHub con acceso al repo de certs) |

> La API key de App Store Connect es preferible a usar usuario/contraseña de
> Apple ID (evita 2FA en CI y es revocable).

## Setup inicial de firma (una sola vez, local, en una Mac)

```bash
cd apps/mobile/ios
bundle install
# crea el repo privado de certificados y genera cert + perfil de distribución
bundle exec fastlane match appstore --git_url <MATCH_GIT_URL>
```

Esto te pide la `MATCH_PASSWORD` y sube los certificados cifrados al repo. A
partir de ahí, el CI solo los consume.

## Probar el deploy

1. Cargar todos los secrets.
2. Hacer el setup de match (paso anterior).
3. `git tag v0.1.0 && git push origin v0.1.0` — o correr el workflow a mano desde
   la pestaña Actions.

## Notas

- El número de build de TestFlight = número de run de GitHub (`github.run_number`).
- El bundle id es `com.stockforml.stockForMl` (generado por Flutter). Si preferís
  uno más limpio (ej. `com.stockforml.app`), cambialo en Xcode **antes** del
  primer `match` y actualizá `Appfile`/`Matchfile`/`Fastfile`.
- Para push notifications en los builds de TestFlight, ver [firebase.md](firebase.md).
