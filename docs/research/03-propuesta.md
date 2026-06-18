# Propuesta de arquitectura y producto — stock-for-ml

> Estado: propuesta para revisión. Fecha: 2026-06-18.
> Basada en los hallazgos de [01-mercadolibre-api](01-mercadolibre-api.md) y
> [02-referencias-open-source](02-referencias-open-source.md).

## 1. Visión

App mobile (Flutter) para que un vendedor de MercadoLibre gestione su stock y
rentabilidad desde el celular: registrar costos de compra, ver comisiones de ML,
calcular % de ganancia, comparar productos, y mantener el stock sincronizado con
ML (descontar al vender, alertar por stock bajo, actualizar publicaciones).

## 2. Principio de arquitectura central

> **La app Flutter NUNCA habla con ML directamente para operaciones
> autenticadas.** Todo el secreto (client_secret, tokens) y la lógica de
> integración viven en **Supabase** (Edge Functions + Postgres). Flutter ⇄
> Supabase ⇄ MercadoLibre.

Motivos: el APK es decompilable (no se puede guardar el `client_secret`); los
webhooks de ML necesitan una URL pública estable (Edge Function); el refresh de
tokens y la sincronización deben correr aunque la app esté cerrada.

## 3. Diagrama lógico

```
┌─────────────┐        ┌──────────────────────────────────────┐        ┌───────────────┐
│  App Flutter│        │              Supabase                 │        │ MercadoLibre  │
│  (mobile)   │        │                                       │        │     API       │
│             │  HTTPS │  Auth (usuarios de la app)            │        │               │
│  - UI/UX    │◄──────►│  Postgres + RLS (productos, stock,    │        │               │
│  - realtime │ realtime│   ventas, costos, credenciales ML)   │        │               │
│  - push     │        │  Edge Functions:                      │        │               │
│             │        │   · oauth-callback   ─────────────────┼───────►│ /oauth/token  │
│             │        │   · ml-webhook (recibe notif.)  ◄─────┼────────┤ webhooks      │
│             │        │   · sync-items / sync-orders  ───────►┼───────►│ /items /orders│
│             │        │   · refresh-tokens (cron)             │        │ /listing_prices│
│             │        │  pg_cron + Queues (jobs async)        │        │               │
└─────────────┘        └──────────────────────────────────────┘        └───────────────┘
```

## 4. Stack propuesto

- **Frontend:** Flutter (3.27+), `supabase_flutter`, Riverpod (estado),
  go_router (navegación), notificaciones push (FCM/APNs vía Supabase).
- **Backend:** Supabase — Postgres + RLS, Auth, Realtime, Storage (imágenes),
  Edge Functions (Deno/TypeScript), pg_cron + pg_net, Queues, Vault (secretos).
- **Cliente ML:** package propio en TypeScript (`packages/meli-client`) usado por
  las Edge Functions; sin SDK oficial (deprecado).
- **Monorepo:** Pub Workspaces (nativo Dart) o Melos. Supabase CLI en la raíz.

## 5. Estructura del monorepo (propuesta)

```
stock-for-ml/
├─ apps/
│  └─ mobile/                 # app Flutter
├─ packages/
│  ├─ core_models/            # modelos Dart compartidos (Producto, Venta…)
│  └─ ml_client/              # (opcional) cliente Dart de solo-lectura
├─ supabase/
│  ├─ migrations/             # SQL (schema, RLS, triggers, cron)
│  ├─ functions/
│  │  ├─ oauth-callback/
│  │  ├─ ml-webhook/
│  │  ├─ sync-orders/
│  │  ├─ sync-items/
│  │  └─ refresh-tokens/
│  ├─ _shared/meli-client/    # cliente ML en TS reutilizado por functions
│  └─ config.toml
├─ docs/
│  └─ research/               # esta documentación
├─ melos.yaml / pubspec.yaml  # workspace
└─ README.md
```

## 6. Modelo de datos (borrador)

```
profiles            (id, ...)                      -- usuario de la app (Supabase Auth)
ml_accounts         (id, profile_id, ml_user_id, nickname, site_id)
ml_credentials      (ml_account_id, access_token*, refresh_token*, expires_at)  -- *cifrado/Vault, RLS dura
products            (id, profile_id, sku, title, purchase_cost, currency, notes, image_url)
ml_listings         (id, product_id, ml_item_id, listing_type, category_id, price,
                     available_quantity, status, permalink)
listing_variations  (id, ml_listing_id, ml_variation_id, attrs, available_quantity, price)
stock_movements     (id, product_id, delta, reason[purchase|sale|adjust|return], ref_order_id, created_at)
sales               (id, ml_order_id, product_id, qty, unit_price, sale_fee, shipping_cost, net, sold_at)
fee_estimates       (id, category_id, listing_type, price, sale_fee_amount, cached_at)
ml_events           (id, topic, resource, payload, status[pending|done|error], received_at)  -- cola de webhooks
alerts              (id, profile_id, type[low_stock|...], product_id, threshold, created_at, read_at)
```

Cálculos derivados (vista o columnas calculadas):
- `comisión` = `sale_fee` (real de la orden) o estimado de `listing_prices`.
- `ganancia_neta` = `precio_venta − comisión − costo_envío − purchase_cost`.
- `% ganancia` = `ganancia_neta / purchase_cost`.
- `margen` = `ganancia_neta / precio_venta`.

## 7. Flujos clave

**A. Conexión de cuenta ML (OAuth)**
1. App abre WebView/navegador → URL de autorización ML (PKCE).
2. ML redirige a Edge Function `oauth-callback` con el `code`.
3. Function intercambia `code`→tokens, los guarda cifrados, registra `ml_account`.
4. Dispara `sync-items` inicial (importa publicaciones existentes).

**B. Venta → descuento de stock (automático)**
1. ML envía webhook `orders_v2` a `ml-webhook`.
2. Function valida, inserta en `ml_events` (cola), responde 200 rápido.
3. Worker (cron/queue) hace `GET /orders/{id}`, registra `sale`, descuenta
   `stock_movements`, recalcula stock y opcionalmente `PUT /items` para
   sincronizar `available_quantity` en ML.
4. Realtime empuja el cambio a la app.

**C. Stock bajo → notificación**
- Trigger en Postgres al bajar stock: si `available_quantity <= threshold`,
  inserta `alert` → push notification (FCM) + badge en la app.

**D. Refresh de tokens (cron)**
- `pg_cron` cada ~5 h invoca `refresh-tokens`, rota `refresh_token`.

**E. Comisiones / rentabilidad**
- Al importar/editar un producto, `GET /listing_prices` cachea el fee estimado.
- Al concretarse la venta, se usa el `sale_fee` real de la orden.

## 8. Features (priorizadas)

### MVP (v0.1)
- Login en la app (Supabase Auth) + conectar cuenta ML (OAuth).
- Importar publicaciones de ML (read-only) y listarlas.
- Soportar productos internos (sin publicar) además de los de ML.
- Registrar costo de compra en **USD**; TC automático (API dólar) para llevar a ARS.
- Cálculo de comisión (estimada), ganancia, **markup y margen** por producto.
- Ver stock actual; ajuste manual de stock (Supabase como fuente de verdad).
- **Comparativa de precios dentro de ML** (competencia por categoría/catálogo).

### v0.2
- Webhook de órdenes → descuento automático de stock.
- Sincronización de stock hacia ML (`PUT /items`).
- Alertas de stock bajo + push notifications.
- Historial de movimientos de stock y ventas.

### v0.3+
- Comparativa entre productos (rentabilidad, rotación, margen).
- Comparativa de precios vs. competencia (`item_competition`).
- Manejo de variaciones.
- Edición de precio/publicación desde la app.
- Dashboard de métricas (ventas, ganancia acumulada, top productos).
- Multi-cuenta ML.

## 9. Riesgos / cosas a vigilar
- **Secretos en cliente:** mitigado por diseño (todo en Supabase).
- **Rate limit ML (1500/min):** batch + cache + cola; evitar polling agresivo,
  preferir webhooks.
- **Refresh token de un solo uso:** si se pierde la rotación, el usuario debe
  reconectar. Manejar con transacción y reintentos.
- **SDKs ML deprecados:** mantenemos cliente propio.
- **Disponibilidad de topics por país:** confirmar topics para MLA.
- **Consistencia de stock** entre app y ML (doble fuente de verdad): definir cuál
  manda (ver decisiones).

## 10. Próximos pasos sugeridos
1. Que el usuario responda las **decisiones pendientes** (doc 04).
2. Crear app en developers.mercadolibre y registrar `redirect_uri`.
3. Scaffold del monorepo + proyecto Supabase + app Flutter base.
4. Implementar flujo OAuth end-to-end (primer hito vertical).
