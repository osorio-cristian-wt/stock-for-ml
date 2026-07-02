# Guía técnica — app de MercadoLibre: crearla y cargar credenciales

> Para el técnico. La versión no técnica (para el dueño de la cuenta de ML) es
> [guia-cliente-mercadolibre.md](guia-cliente-mercadolibre.md). Complementa a
> [setup.md](setup.md).

**Conceptos clave:** la aplicación de ML se crea **una sola vez** y sirve para
todos los usuarios (como un "Sign in with Google"); cada vendedor que autoriza
genera sus propios tokens (`ml_accounts` + `ml_credentials`, refrescados por el
cron `ml-refresh-tokens`). El flujo es OAuth 2.0 + PKCE: la app Flutter nunca ve
el secret — todo pasa por las Edge Functions `oauth-url` y `oauth-callback`.

---

## 1. Crear la aplicación en el DevCenter de ML

1. Entrar a **https://developers.mercadolibre.com.ar** con la cuenta vendedora
   (la cuenta que la crea es solo la "dueña"; no limita quién puede autorizar).
2. **Mis aplicaciones → Crear aplicación**: nombre y descripción libres.
3. **Scopes**: activar `read` y `offline_access` (sin `offline_access` no hay
   refresh token y la conexión se cae cada ~6 h). `write` recién hace falta
   para publicar/editar desde la app (Fase 6, aún no implementado) — se puede
   activar desde ya sin costo.
4. **PKCE**: si el portal ofrece "Authorization code + PKCE", habilitarlo (el
   backend siempre manda `code_challenge` S256).
5. **Redirect URI** (exacta, carácter por carácter):
   - Cloud: `https://<PROJECT-REF>.supabase.co/functions/v1/oauth-callback`
   - Local vía túnel (ver §3): `https://<tunel>/functions/v1/oauth-callback`
   - Se pueden registrar varias a la vez.
6. **Notificaciones (webhook)**: URL `https://<PROJECT-REF>.supabase.co/functions/v1/ml-webhook`
   y tópicos `orders_v2` (imprescindible), `shipments`, `items`, `items_prices`,
   `claims`.
7. Copiar **App ID** (= `ML_CLIENT_ID`) y **Secret Key** (= `ML_CLIENT_SECRET`).

---

## 2. Cargar credenciales en LOCAL

Los secrets locales viven en `supabase/functions/.env` (gitignoreado; plantilla
en [.env.example](../supabase/functions/.env.example)):

```bash
cp supabase/functions/.env.example supabase/functions/.env   # si no existe
# completar:
#   ML_CLIENT_ID=<App ID>
#   ML_CLIENT_SECRET=<Secret>
#   ML_REDIRECT_URI=<la registrada en ML para este entorno>
```

Para que el runtime tome el archivo (o cualquier cambio de `config.toml`):

```bash
supabase stop && supabase start
# alternativa rápida solo para el .env, con logs en vivo:
supabase functions serve --env-file supabase/functions/.env
```

**Nota `verify_jwt`:** `oauth-callback` y `ml-webhook` están marcadas como
públicas en [config.toml](../supabase/config.toml) (`verify_jwt = false`),
porque las llama ML sin JWT de Supabase. Sin eso, el gateway devuelve 401 antes
de llegar a la función y el OAuth muere en el retorno.

### Límite del OAuth en local

El paso navegador→callback **no funciona contra `127.0.0.1`** desde el
emulador/teléfono (ahí `127.0.0.1` es el propio dispositivo) y ML espera URIs
https. Opciones:

- **Probar el OAuth contra el proyecto cloud** (recomendado, §4) y dejar local
  para todo lo demás (stock, compras, OCR, etc., que no dependen de ML).
- **Túnel https al stack local**: `ngrok http 7431` (o `cloudflared tunnel`),
  registrar `https://<tunel>/functions/v1/oauth-callback` como Redirect URI en
  ML y ponerla en `ML_REDIRECT_URI` del `.env`. El deep link de vuelta a la app
  (`stockforml://auth-callback`) funciona igual.

---

## 3. Cargar credenciales en Supabase CLOUD (secrets)

Estado actual: **el repo no tiene proyecto cloud linkeado**. Primera vez:

```bash
supabase login
supabase link --project-ref <PROJECT-REF>
supabase db push                  # aplica las migraciones al proyecto
```

Secrets (equivalente cloud del `.env` local):

```bash
supabase secrets set \
  ML_CLIENT_ID=<App ID> \
  ML_CLIENT_SECRET=<Secret> \
  ML_REDIRECT_URI=https://<PROJECT-REF>.supabase.co/functions/v1/oauth-callback \
  APP_BASE_URL=stockforml://auth-callback \
  FX_PROVIDER_URL=https://dolarapi.com/v1/dolares/blue \
  ANTHROPIC_API_KEY=<opcional: OCR/clasificación IA>
```

Deploy de funciones (toma los `verify_jwt` de `config.toml`):

```bash
supabase functions deploy
```

Cron jobs (refresh de tokens, FX, eventos, órdenes, push de stock) — una vez
por entorno, en el SQL Editor del proyecto:

```sql
insert into private.app_config values
  ('functions_base_url', 'https://<PROJECT-REF>.supabase.co/functions/v1'),
  ('service_role_key',   '<SERVICE-ROLE-KEY>')
on conflict (key) do update set value = excluded.value;
select private.register_ml_cron_jobs();
```

Correr la app contra cloud:

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://<PROJECT-REF>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<anon/publishable key>
```

(Sin dart-defines, la app apunta al stack local `127.0.0.1:7431` —
[env.dart](../apps/mobile/lib/src/config/env.dart).)

---

## 4. Verificar

1. **Función viva**: en la app, "Conectar con Mercado Libre" debe abrir el
   navegador en ML (si falla ahí, revisar secrets/logs de `oauth-url`).
2. **Ida y vuelta**: autorizar → ML redirige a `oauth-callback` → la app vuelve
   por deep link con el snackbar "✓ Cuenta de MercadoLibre conectada" y aparece
   la fila en `ml_accounts`.
3. **Cron**: `select jobname, schedule from cron.job;` debe listar
   `ml-refresh-tokens`, `ml-fx-rates`, `ml-process-events`, `ml-sync-orders`,
   `ml-push-stock`.
4. **Sin cuenta real**: ML permite crear **usuarios de prueba** vía API
   (`POST /users/test_user`) para ensayar el flujo completo.

## Estado actual (2026-07-02)

- Entorno de trabajo: **solo local** (`supabase start`, app con defaults a
  `127.0.0.1:7431`). No hay proyecto cloud linkeado.
- `supabase/functions/.env` creado desde la plantilla, **sin credenciales aún**
  (por eso la vista de conexión muestra "backend no disponible").
- Falta: crear la app en ML (§1) y cargar los valores (§2 y/o §3).
