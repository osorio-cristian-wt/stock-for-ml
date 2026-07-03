# stock-for-ml

App mobile (Flutter) + backend Supabase para gestionar el **stock y la
rentabilidad** de productos vendidos en **MercadoLibre**: costos de compra,
comisiones de ML, % de ganancia (markup y margen), comparativa de precios,
descuento automático de stock al vender y alertas de stock bajo.

> Estado: en construcción. Monorepo público. Licencia [MIT](LICENSE).

## Stack

| Capa | Tecnología |
|------|------------|
| App | Flutter 3.32+, Dart 3.8+, Riverpod, supabase_flutter |
| Backend | Supabase (Postgres + RLS, Auth, Realtime, Storage, Edge Functions, pg_cron) |
| Integración ML | Cliente propio en TypeScript/Deno (los SDK oficiales de ML están deprecados) |
| Monorepo | Pub Workspaces (nativo de Dart) |

Decisiones de diseño y su justificación: [docs/research/](docs/research/).
Requisitos funcionales y no funcionales: [docs/requisitos.md](docs/requisitos.md).

## Arquitectura (regla de oro)

> La app Flutter **nunca** habla con MercadoLibre directamente. Todo lo
> autenticado (OAuth, tokens, webhooks, sincronización, cron) vive en **Supabase
> Edge Functions**. Flujo: `Flutter ⇄ Supabase ⇄ MercadoLibre`.

Supabase es la **fuente de verdad del stock**; los cambios se empujan a ML.

## Estructura del repo

```
stock-for-ml/
├─ apps/
│  └─ mobile/                # App Flutter (Riverpod) — UI completa en lib/src/
├─ packages/
│  └─ core_models/           # Modelos Dart compartidos (+ tests)
├─ supabase/
│  ├─ config.toml            # Puertos locales en el bloque 743x (ver abajo)
│  ├─ migrations/            # Schema, RLS, triggers, vistas, cron
│  ├─ functions/             # Edge Functions (Deno/TS) + _shared/meli-client
│  ├─ tests/                 # Tests pgTAP de la base
│  └─ seed.sql               # Datos de desarrollo
├─ docs/                     # Investigación + requisitos
├─ scripts/                  # app.ps1: run/build por entorno (ver docs/setup.md)
├─ pubspec.yaml              # Workspace raíz (Pub Workspaces)
└─ LICENSE                   # MIT
```

## Puertos locales de Supabase

El esquema solicitado fue `7432X`. Como un puerto TCP no puede superar **65535**,
los `743xx` de 5 dígitos no son válidos; por eso se ancló la **DB en `7432`** y se
agrupó todo el resto en el bloque `743x` (mismo último dígito que el default de
Supabase):

| Servicio | Puerto |
|----------|--------|
| Postgres (DB) | **7432** |
| API (Kong/PostgREST) | 7431 |
| Studio | 7433 |
| Inbucket (emails) | 7434 |
| Analytics | 7437 |
| Shadow DB | 7430 |
| Pooler | 7439 |

## Cómo arrancar (dev local)

Requisitos: Flutter 3.32+, Supabase CLI, Docker Desktop corriendo.

```bash
# 1) Backend
supabase start                 # levanta Postgres+API+Studio en los puertos 743x
supabase db reset              # aplica migraciones + seed
supabase test db               # corre los tests pgTAP

# 2) App
dart pub get                   # resuelve el workspace (root + members)
cd apps/mobile
flutter test                   # tests
flutter run                    # corre la app (placeholder hasta definir vistas)
```

Variables de entorno: copiar `.env.example` → `.env` y completar (ver más abajo).

## Conexión a Supabase Cloud y MercadoLibre

Pendiente de configuración por el dueño del proyecto:
1. Crear proyecto en Supabase Cloud y `supabase link`.
2. Crear app en https://developers.mercadolibre.com.ar (`client_id`,
   `client_secret`, `redirect_uri`).
3. Cargar secretos: `supabase secrets set ML_CLIENT_ID=... ML_CLIENT_SECRET=...`.

Detalle paso a paso en [docs/setup.md](docs/setup.md).
