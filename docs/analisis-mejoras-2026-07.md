# Análisis de mejoras — julio 2026

> Estado: **aprobado por el dueño (2026-07-08)** — aplican todas las fases en
> orden A → B → C → D. Origen: pedido del dueño (import robusto, estados ML,
> Full, costos de venta completos, stats, UX de costos/precios, borrado de
> datos). Complementa [requisitos.md](requisitos.md); RF nuevos: RF-36…RF-47.
>
> Decisiones tomadas en la revisión:
> - **Full**: espejo read-only, pero cuando se detecta mercadería nueva en Full
>   la app pide **atribuir el origen** (de qué depósito local salió) y registra
>   el descuento **solo local, sin push a ML** (ver §3.5).
> - **Desconectar ML** conserva el histórico (ventas y productos quedan).
> - Nuevos pedidos: **pantalla de actividad de sincronización** (RF-46) y
>   **prompt de reactivación de publicaciones** cuando un producto sale de 0
>   (RF-47).

## 1. Import de publicaciones: corte, progreso e idempotencia

**Qué pasa hoy.** La app llama a `sync-items` una sola vez con un diálogo
bloqueante ([import_prompt.dart](../apps/mobile/lib/src/features/connect_ml/import_prompt.dart)).
La Edge Function ([sync-items/index.ts](../supabase/functions/sync-items/index.ts))
recorre TODAS las publicaciones en serie; cada ítem hace 2–3 llamadas a ML
(`GET /items`, `listing_prices`) + varios upserts. Con ~100 publicaciones se
supera el límite de ejecución de la Edge Function (o el timeout del
`functions.invoke` del cliente) → el import "se corta" sin feedback y el
diálogo queda sin información de cuántos entraron.

**¿Es idempotente re-darle a Importar? Sí.** Verificado en
[_shared/items.ts](../supabase/functions/_shared/items.ts):

- `ml_listings` se upsertea por `(profile_id, ml_item_id)` — no duplica.
- El producto interno se dedupea por GTIN/SKU; si el listing ya existe se
  reutiliza su `product_id`.
- El stock solo se siembra (`initial_sync`, origin=ml) en productos **nuevos**;
  nunca pisa stock local existente.

Re-importar retoma lo que faltó. El problema es solo de **ejecución** (corte
por tiempo) y **UX** (sin progreso, bloqueante).

**Propuesta (RF-36).**

1. Tabla `import_jobs` (`id, ml_account_id, total, processed, failed, status
   [running|done|error], last_offset, started_at, finished_at, errors jsonb`).
2. `sync-items` pasa a procesar **lotes** (p. ej. 20 ítems por invocación):
   lee el job, procesa desde `last_offset`, actualiza contadores y, si falta,
   se **auto-reinvoca** (fire-and-forget HTTP a sí misma) o deja que el cron
   `process-events`/un cron corto drene el job. El `total` sale de
   `paging.total` de la primera página.
3. UI: el diálogo bloqueante se reemplaza por un banner/tarjeta con stream
   Realtime sobre `import_jobs`: "Importando 37/104…" + errores al final.
   Se puede navegar mientras corre (segundo plano real, server-side).
4. "Importar de nuevo" siempre visible en Ajustes → reanuda/re-sincroniza
   (ya idempotente).

## 2. Estado de la publicación (pausada, inactiva, etc.)

**Qué pasa hoy.** `upsertItem` guarda `status` en `ml_listings`, pero el
`statusMap` solo conoce `active/paused/closed/under_review` — todo lo demás
(`inactive`, `not_yet_active`, `payment_required`) cae a `"inactive"` y el
`sub_status` de ML (**`out_of_stock`, `paused_by_seller`, `deleted`,
`picture_download_pending`**) se descarta. Además **la app no muestra el
estado en ninguna pantalla** (ni tile, ni detalle, ni filtro).

**Docs ML (verificado 2026-07-08).** Estados: `active`, `paused`, `closed`,
`under_review`, `inactive`, `not_yet_active`, `payment_required`; el detalle
del ítem trae además `sub_status[]`. Fuente:
[Sync and modify listings](https://developers.mercadolibre.com.mx/en_us/en_us/products-sync-listings),
[Moderation with pause](https://developers.mercadolibre.com.ar/en_us/moderations-paused).

**Propuesta (RF-37).** Ampliar `statusMap` a los 7 estados + columna
`sub_status text[]` en `ml_listings`; chip de estado en el tile y el detalle
del producto ("Pausada", "Sin stock", "En revisión"…) + filtro por estado en
Productos. El webhook `items` ya refresca vía `upsertItem`, así que el dato
queda vivo.

## 3. Depósitos Full de MercadoLibre

**Qué pasa hoy.** Full solo se usa para la comparativa de precios
(`logistic_type === "fulfillment"` en
[_shared/comparison.ts](../supabase/functions/_shared/comparison.ts)). Las
ventas Full **descuentan del depósito de despacho local** (reconciliación con
`p_warehouse_id: null` → default), o sea que si la mercadería estaba
físicamente en Full, el stock local queda mal.

**Docs ML (verificado 2026-07-08).** Argentina tiene **stock distribuido** en
producción: `GET /user-products/{USER_PRODUCT_ID}/stock` devuelve `locations[]`
con `type: selling_address | seller_warehouse | meli_facility` (Full) y
cantidad por ubicación. El stock `meli_facility` lo administra ML (entra por
envíos de mercadería a Full; no se "crea" por API). También existe
`GET /marketplace/inventories/{INVENTORY_ID}/stock/fulfillment` (vía
`inventory_id` del ítem) y webhooks `stock-locations` / `stock-fulfillment`.
Fuentes: [Stock distribuido](https://developers.mercadolibre.com.ar/es_ar/stock-distribuido),
[Full and Flex coexistence](https://developers.mercadolibre.com.ar/en_us/product-identifiers/full-and-flex-coexistence),
[Fulfillment stock](https://global-selling.mercadolibre.com/devsite/fulfillment-stock-gs).

**Propuesta (RF-38): espejo read-only.**

1. Depósito especial "Full (ML)" por cuenta ML: `is_ml_fulfillment = true`,
   **no vendible localmente, excluido del push a ML** y de transferencias
   manuales de salida (la verdad de Full la fija ML).
2. `sync-items` + webhook `stock-locations`/`stock-fulfillment` actualizan el
   stock de ese depósito (movimientos `origin=ml`, `reason=full_sync`).
3. Las órdenes con `logistic_type = fulfillment` reconcilian contra el
   depósito Full (hoy: contra el default) → el disponible local deja de
   corromperse.
4. Enviar mercadería a Full desde la app = **transferencia saliente a
   "Full (ML) — en tránsito"**; cuando ML confirma la recepción (el espejo
   sube), se concilia. La app nunca "empuja" stock a Full.
5. **Atribución de ingreso (decisión 2026-07-08):** cuando el espejo detecta
   un AUMENTO de stock en Full (mercadería nueva recibida), el delta queda
   como "ingreso a Full sin atribuir" y la app pregunta de qué depósito local
   salió. Al elegirlo se registra el par de movimientos local→Full con
   `reason=full_inbound_attribution`, que **descuenta solo localmente y NO
   encola push a ML** (ML ya contabilizó esa mercadería al recibirla).

## 4. Ventas: comisiones, impuestos y envíos incompletos

**Qué pasa hoy.** [_shared/orders.ts](../supabase/functions/_shared/orders.ts)
solo captura `order_items[].sale_fee`. La columna `sales.shipping_cost` existe
y `v_sale_profit` la descuenta… **pero nadie la llena en ventas ML** (queda 0).
Impuestos, descuentos y cargos financieros no se capturan.

**Docs ML (verificado 2026-07-08).** El costo real de una venta se compone de:

| Cargo | Fuente API |
|-------|-----------|
| Comisión por venta | `order_items[].sale_fee` (ya lo tenemos) |
| Fee de marketplace / financiación | `payments[].marketplace_fee`, cuotas |
| Costo de envío del vendedor | `GET /shipments/{id}/costs` → `senders[].cost` (envío gratis = lo paga el vendedor) |
| Impuestos de la orden | `order.taxes`, `payments[].taxes_amount` |
| Descuentos aplicados | `GET /orders/{order_id}/discounts` |
| Conciliación definitiva | Billing API (`/billing/integration/...`, cargos facturados por período) |

Fuentes: [Obtener una orden](https://developers.mercadolibre.com.ar/es_ar/gestiona-ventas),
[Shipments](https://global-selling.mercadolibre.com/devsite/manage-shipments),
[Billing data](https://global-selling.mercadolibre.com/devsite/gs-billing-data).

**Propuesta (RF-39): cargos tipados por venta** (el "implementado con
interfaces" del pedido).

1. Tabla `sale_charges` (`sale_id, kind [commission|shipping|tax|discount|
   financing|other], amount, currency_id, source [order|shipment|payment|
   billing], raw jsonb`) — un tipo de cargo nuevo = una fila nueva, sin tocar
   el schema.
2. `reconcileOrder` puebla: comisión (ya), envío (`shipments/{id}/costs`,
   que ya pedimos el shipment igual), impuestos (`order.taxes` / payments) y
   descuentos.
3. `v_sale_profit` v2: `gross − Σ sale_charges − COGS`. `sales.sale_fee` y
   `shipping_cost` quedan como columnas derivadas/legacy.
4. Fase posterior: job mensual contra Billing API para conciliar cargos
   facturados vs estimados.

## 5. Rentabilidad: productos sin costo contaminan las stats

**Qué pasa hoy.** `v_product_economics` hace
`coalesce(product_cost_ars, 0)` → un producto **sin costo** aparece con
ganancia = precio − comisión (inflada) en la vista de stats y la Comparativa.

**Propuesta (RF-40).**

1. `v_product_economics` expone `has_cost boolean`; `net_profit / markup_pct /
   margin_pct` pasan a `null` cuando no hay costo (en vez de números falsos).
2. Stats/Comparativa excluyen (o agrupan aparte) los sin costo.
3. **Vista dedicada "Completar costos"**: recorre uno a uno los productos sin
   costo (foto, título, precio ML de referencia) con carga rápida y "saltar".
4. Banner en la tab Productos: "N productos necesitan tu atención" (sin costo,
   sin precio local, push con error) → deep-link a esa vista (RF-33 ya dio el
   patrón con `pushIssues`).

## 6. Vincular publicación: buscador en vez de pegar el código

**Qué pasa hoy.** El sheet de vinculación pide pegar `MLA…` a mano
([product_detail_screen.dart:250-267](../apps/mobile/lib/src/features/products/product_detail_screen.dart)).

**Insight clave:** `sync-items` ya espeja **todas** las publicaciones del
vendedor en `ml_listings`. No hace falta ninguna búsqueda contra ML: el picker
puede buscar **sobre la base propia**.

**Propuesta (RF-41).** El sheet pasa a ser un buscador de publicaciones
espejadas (thumbnail, título, precio, estado), priorizando las **no
vinculadas** y con matcheo sugerido por similitud de título/SKU/GTIN con el
producto actual. El campo de código queda como fallback avanzado (publicación
recién creada aún no espejada) junto a un botón "actualizar desde ML".

## 7. Detalle de producto: precio ML y márgenes por canal

**Propuesta (RF-42).**

1. Mostrar el **precio de ML** (`ml_listings.price`, ya espejado) como campo
   read-only; al tocarlo, mensaje "El precio de la publicación se modifica
   desde MercadoLibre" con link al `permalink`. (Editarlo desde la app
   requiere scope de escritura — decisión pendiente de v0.4, no la bloquea.)
2. Bloque "Márgenes por canal":
   - **ML:** precio ML − comisión estimada (`est_sale_fee`) − envío estimado
     (cuando RF-39 dé el dato histórico promedio) − costo por política.
   - **Local:** precio local − costo por política.
   Ambos con margen % y markup %, y "—" si falta costo (RF-40) o precio local.

## 8. Precio local opcional al crear, obligatorio al vender

**Qué pasa hoy.** El formulario exige costo y precio de venta
([product_form_screen.dart:145-152](../apps/mobile/lib/src/features/products/product_form_screen.dart));
el modelo ya admite `sale_price` nulo.

**Propuesta (RF-43).** Al crear: solo título/SKU obligatorios (costo y precio
opcionales con nudge visual). En **venta local**: si la línea no tiene precio,
la venta exige cargarlo ahí mismo (y ofrece guardarlo en el producto).
Productos sin precio local entran al banner "necesitan atención" (RF-40.4).

## 9. Tab de estadísticas detalladas

**Propuesta (RF-44).** Quinta tab "Stats" (o reemplaza el dashboard del
Inicio, a definir): ganancia real por período (`v_sale_profit`), filtros por
rango de fechas / canal (ml|local) / categoría / depósito, top productos,
rotación, evolución mensual. Excluye ventas de productos sin costo del profit
(consistente con RF-40) mostrándolas como "sin costear".

## 10. Borrar datos y desconectar ML

**Qué pasa hoy.** Ajustes solo tiene sign-out. No hay forma de desconectar la
cuenta ML ni de borrar los datos.

**Propuesta (RF-45).** Sección "Zona peligrosa" en Ajustes:

1. **Desconectar MercadoLibre**: borra `ml_credentials`/`ml_accounts` (cascade
   a listings espejados… a decidir: conservar histórico de ventas), desregistra
   webhooks si aplica.
2. **Borrar todos los datos**: RPC `wipe_profile_data()` (transaccional, solo
   borra filas del `profile_id` propio) + limpieza de cache local (drift,
   `pending_ops`) + sign-out. Confirmación fuerte (escribir "BORRAR" +
   biometría si está activa, RF-34).

## 11. Actividad de sincronización con ML (nuevo, 2026-07-08)

**Propuesta (RF-46).** Pantalla "Actividad ML" (desde Ajustes o el Inicio):
línea de tiempo unificada de la sincronización — pushes de stock
(`stock_push_queue` con estado/reintentos/error), eventos recibidos
(`ml_events`: órdenes, cambios de ítems/precios), cambios de estado de
publicación detectados (activa→pausada, etc.) e imports (RF-36). Cierra el
🟡 de RNF-07 (`ml_events.error` hoy solo visible en base).

## 12. Reactivación de publicaciones al reponer stock (nuevo, 2026-07-08)

**Propuesta (RF-47).** Cuando un cierre de compra / ajuste / atribución saca
un producto de 0 a >0 y tiene publicaciones **pausadas**:

- Sub_status `out_of_stock`: el push de stock (`PUT available_quantity > 0`)
  ya las reactiva solo (documentado por ML) — solo se informa.
- Sub_status `paused_by_seller`: prompt resumen "¿Querés reactivar estas
  publicaciones?" con la lista; al aceptar, push explícito
  (`PUT /items/{id} {status: active}`) además del stock.

## Plan por fases (aprobado 2026-07-08)

| Fase | Contenido | Motivo |
|------|-----------|--------|
| **A — Números correctos** | RF-39 cargos de venta completos · RF-40 sin-costo fuera de stats · RF-38 Full (reconciliación + atribución de ingreso) | Hoy la ganancia mostrada está mal (envío/impuestos faltan, sin-costo inflado, Full corrompe stock). Todo lo demás se apoya en esto. |
| **B — Import y estados** | RF-36 import por lotes con progreso · RF-37 estados/sub_status visibles | Confianza en la sincronización; desbloquea al usuario con ~100 publicaciones. |
| **C — UX de catálogo** | RF-41 picker de vinculación · RF-42 precio ML + márgenes por canal · RF-43 precio local opcional · RF-40.3/40.4 vista de costos + banner | Fluidez diaria. |
| **D — Stats y control** | RF-44 tab de estadísticas · RF-45 borrar datos / desconectar ML (conserva histórico) · RF-46 actividad de sync · RF-47 reactivación | Se nutre de A (números ya confiables). |
