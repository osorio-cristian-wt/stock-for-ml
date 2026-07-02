# Setup — stock-for-ml

Guía para levantar el proyecto en local y conectarlo a Supabase Cloud y a
MercadoLibre. Pasos marcados con 🔑 los hace el dueño del proyecto (requieren
credenciales reales).

## 1. Requisitos

- Flutter 3.32+ / Dart 3.8+
- Supabase CLI 2.78+
- Docker Desktop (corriendo)
- Node 18+ (opcional, tooling)

## 2. Backend local

```bash
supabase start          # contenedores en los puertos 743x (ver README)
supabase db reset       # aplica migrations/ + seed.sql
supabase test db        # tests pgTAP
supabase functions serve   # sirve las Edge Functions localmente
```

Studio: http://127.0.0.1:7433 — Postgres: `postgresql://postgres:postgres@127.0.0.1:7432/postgres`

Tras `supabase start`, copiar el `anon key` y la `API URL` que imprime la CLI a
`apps/mobile/.env` (ver `.env.example`).

## 3. Variables de entorno

### App (`apps/mobile/.env`)
```
SUPABASE_URL=http://127.0.0.1:7431
SUPABASE_ANON_KEY=<anon key local>
```

### Edge Functions (secretos del backend)
Local: crear `supabase/functions/.env` (NO se commitea).
Cloud: `supabase secrets set ...`.

```
ML_CLIENT_ID=...
ML_CLIENT_SECRET=...
ML_REDIRECT_URI=https://<project-ref>.supabase.co/functions/v1/oauth-callback
ML_SITE_ID=MLA
FX_PROVIDER_URL=https://dolarapi.com/v1/dolares/blue
APP_BASE_URL=stockforml://auth-callback
```

## 4. 🔑 Conexión a Supabase Cloud

```bash
supabase login
supabase link --project-ref <project-ref>
supabase db push                 # sube las migraciones
supabase functions deploy        # despliega todas las Edge Functions
supabase secrets set ML_CLIENT_ID=... ML_CLIENT_SECRET=... ML_REDIRECT_URI=...
```

## 5. 🔑 Configurar la app de MercadoLibre

> Paso a paso completo (crear la app, cargar credenciales en local y en cloud,
> límites del OAuth en local): [guia-tecnica-ml-app.md](guia-tecnica-ml-app.md).

1. Crear la aplicación en https://developers.mercadolibre.com.ar.
2. Scopes: `read`, `write`, `offline_access`.
3. `Redirect URI`: la URL pública de la Edge Function `oauth-callback`.
4. Activar las notificaciones (webhooks) apuntando a la Edge Function
   `ml-webhook`, con los topics: `orders_v2`, `items`, `items_prices`,
   `item_competition`.
5. Copiar `App ID` (client_id) y `Secret Key` a los secretos de Supabase.

## Credenciales pendientes

Lo que necesito que me pases / configures (los secretos **no** van por chat ni al
repo: cargalos como GitHub Secrets o `supabase secrets set`):

### MercadoLibre (backend)
- `ML_CLIENT_ID` y `ML_CLIENT_SECRET` (de developers.mercadolibre.com.ar).
- `ML_REDIRECT_URI` (URL pública de la Edge Function `oauth-callback`).

### Supabase Cloud
- `project-ref` del proyecto cloud (para `supabase link`).

### iOS / TestFlight (GitHub Secrets — ver [ci-cd.md](ci-cd.md))
- App Store Connect API key: `.p8` (base64), Key ID, Issuer ID.
- `APPLE_TEAM_ID`.
- `MATCH_GIT_URL`, `MATCH_PASSWORD`, `MATCH_GIT_BASIC_AUTHORIZATION`.

### Firebase (push) — ver [firebase.md](firebase.md)
- Archivo `GoogleService-Info.plist` (de Firebase, iOS) → va en `apps/mobile/ios/Runner/`.
- APNs Authentication Key `.p8` + Key ID + Team ID → se suben a Firebase (no al repo).

## 6. Cron jobs (pg_cron)

Tras desplegar las funciones y cargar secretos, habilitar los jobs programados
(refresh de tokens, FX, procesamiento de cola). Ver
`supabase/migrations/*_scheduled_jobs.sql` y completar los placeholders de URL /
service key según el entorno (ver comentarios en ese archivo).
