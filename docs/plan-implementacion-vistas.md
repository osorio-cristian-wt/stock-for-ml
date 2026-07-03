# Plan de implementación — Front operativo (depósitos, compras, import ML, OCR, publicar)

> Estado: vivo. Inicio 2026-06-19, branch `feat/views`.
> Este documento es un **handoff autosuficiente**: si la sesión se corta, otro
> agente (u otra máquina) debe poder retomar leyendo SOLO esto + los archivos que
> se citan. Deriva de [requisitos.md](requisitos.md) y
> [diseno-stock-estados.md](diseno-stock-estados.md).

---

## 0. Cómo retomar (leer primero)

1. Leé este documento completo.
2. Leé el índice de memoria del proyecto si existe (`project-stock-for-ml`).
3. Mirá el **§7 Checklist de progreso** para saber en qué fase quedó.
4. Para cada fase pendiente, seguí su bloque (Leer → Hacer → Verificar).
5. Reglas de oro (no romper): **la app Flutter NUNCA habla con ML directo** (todo
   por Edge Functions); **la fuente de verdad del stock es la app/Supabase**, ML
   solo descuenta por venta; **anti-ciclo `origin`** (solo `user`/`system`
   empujan a ML).
6. Tras cada fase: `cd apps/mobile && flutter analyze` debe quedar limpio; correr
   tests si se tocó backend (ver §6). Commit por fase (no pushear salvo pedido).

**Cómo aplicar migraciones / probar:** los cambios de SQL requieren
`supabase db reset` (local) o `supabase db push` (cloud) para surtir efecto. Las
Edge Functions se sirven con `supabase functions serve` y se testean con Deno.

---

## 1. Arquitectura y convenciones (lo mínimo para tocar el código)

### Layout del monorepo (Pub Workspaces)
- `apps/mobile/` — app Flutter (Riverpod). Código en `lib/src/`.
  - `data/` — repositorios (acceso Supabase) + providers Riverpod
    (`supabase_providers.dart`, `queries.dart`).
  - `features/<area>/` — pantallas por área (auth, shell, home, products,
    stock_adjustment, sales, alerts, settings, scan, connect_ml, price_comparison).
  - `theme/app_colors.dart` + `app_theme.dart` — **Estilo B (oscuro · fintech)**,
    primario emerald `#10B981` sobre `#0D0F13/#161A20`.
  - `ui/widgets/app_widgets.dart` — `SurfaceCard`, `EmptyState`, `Loading`,
    `InlineError`, `SectionHeader`, `TagChip`, `ProductThumb`.
  - `ui/format.dart` — `Fmt.ars`, `Fmt.usd`, `Fmt.pct`, `Fmt.clock`, `Fmt.arsSigned`.
- `packages/core_models/` — modelos Dart puros (sin Flutter). Barrel:
  `lib/core_models.dart`. Helpers JSON en `lib/src/json.dart` (`asDouble`, `asInt`,
  `asBool`, `asDateTime`, `asIntOrNull`, `asDoubleOrNull`).
- `supabase/migrations/` — SQL versionado `YYYYMMDDHHMMSS_nombre.sql`. Última:
  `20260619120001_realtime_publication.sql`. **Las nuevas van con timestamp mayor.**
- `supabase/functions/` — Edge Functions Deno/TS. Compartido en `_shared/`.
- `supabase/tests/` — pgTAP. `supabase/functions/tests/` — Deno.
- `docs/` — diseño y requisitos.

### Patrón de modelo (core_models)
Clase `@immutable` con `fromJson` (snake_case → camelCase usando helpers de
`json.dart`) y `toInsert()` (omite campos gestionados por el server; incluye
`if (x != null)` para opcionales). Exportar en `lib/core_models.dart`. Ej:
[product.dart](../packages/core_models/lib/src/product.dart),
[warehouse.dart](../packages/core_models/lib/src/warehouse.dart) (ya tiene
`Warehouse` y `ProductStock`).

### Patrón de repositorio + provider
- Repo: clase que recibe `SupabaseClient`; métodos `Future`/`Stream`. RLS scopea
  por `profile_id = auth.uid()`, así que NO se filtra por profile en el cliente.
  Ej: [products_repository.dart](../apps/mobile/lib/src/data/products_repository.dart).
- Provider del repo: en
  [supabase_providers.dart](../apps/mobile/lib/src/data/supabase_providers.dart).
- Provider de datos: en [queries.dart](../apps/mobile/lib/src/data/queries.dart).
  `StreamProvider` para listas reactivas (realtime), `FutureProvider` para lo
  derivado (se invalida con `ref.invalidate(...)` + pull-to-refresh).

### Reactividad (ya resuelto en Fase 1)
`.stream()` sólo entrega deltas si la tabla está en la publicación
`supabase_realtime`. La migración `20260619120001_realtime_publication.sql` agregó
products/product_stock/stock_movements/ml_listings/sales/alerts/product_categories
con `replica identity full`. **Toda tabla nueva que se vaya a `.stream()` debe
agregarse a esa publicación** (mismo patrón de DO block).

### Stock: cómo se mueve
RPC `apply_stock_movement(p_product_id, p_delta, p_reason, p_reference, p_note,
p_warehouse_id, p_bucket, p_origin)` (SECURITY INVOKER). Inserta en
`stock_movements`; un trigger AFTER mantiene `product_stock` (buckets por depósito)
y recalcula `products.current_stock` = Σ vendibles `(on_hand − reserved)`; si
`origin <> 'ml'` encola push a ML en `stock_push_queue`. Reason válidos: purchase,
sale, adjustment, return, initial_sync, purchase_ordered, purchase_received,
reserve, dispatch, cancellation, bounce, loss, transfer. Buckets: incoming,
on_hand, reserved. Origin: ml, user, system.

Desde Flutter:
`ProductsRepository.applyStockMovement({productId, delta, reason, reference, note,
warehouseId, bucket, origin})`
([products_repository.dart:55](../apps/mobile/lib/src/data/products_repository.dart#L55)).

### Edge Functions: patrón
- `import { handlePreflight, jsonResponse } from "../_shared/cors.ts";`
- Env: `../_shared/env.ts` → `anthropicConfig()` (`apiBase`, `apiKey`, `model`),
  `mlConfig()`, `supabaseConfig()`.
- Admin client (service_role, bypassa RLS): `../_shared/supabaseAdmin.ts` →
  `createAdminClient()`.
- ML: `../_shared/meli.ts` → `MeliClient`; token vía
  `../_shared/credentials.ts` → `getValidAccessToken(admin, accountId)`.
- LLM Anthropic: ver [classify-product/index.ts](../supabase/functions/classify-product/index.ts)
  — `POST {apiBase}/v1/messages`, headers `x-api-key` + `anthropic-version:
  2023-06-01`, body con `model`, `max_tokens`, `system`, `messages`, y
  **`output_config.format.json_schema`** para salida estructurada. Modelo de
  visión recomendado: **Claude Haiku 4.5** (`claude-haiku-4-5`).

### Navegación actual
`HomeShell` ([home_shell.dart](../apps/mobile/lib/src/features/shell/home_shell.dart))
= `IndexedStack` con bottom nav de 4 tabs: Inicio · Productos · Ventas · Ajustes.

---

## 2. Decisiones transversales (tomadas con el dueño, 2026-06-19)

- **Proveedor → tabla `suppliers` reutilizable** (no texto libre).
- **Transferencias entre depósitos = solo control interno.** Genera `−on_hand@A` /
  `+on_hand@B` (`origin=user`); balanceada entre vendibles deja `available` igual
  → push a ML no-op.
- **Depósito principal = depósito de despacho.** Es del que ML descuenta la venta
  (ya lo hace `reconcile_order_stock` vía `ensure_default_warehouse`). La UI debe
  permitir **cambiar cuál es el principal** (set `is_default`, atómico).
- **Import ML siembra stock SOLO en productos nuevos.** Si el producto ya existe
  (match por GTIN/SKU) → vincular listing y NO tocar stock (empujar el stock local
  a ML). Si es nuevo → sembrar con movimiento `initial_sync` (`origin=ml`).
- **OCR de factura → Claude Haiku (visión)** vía Edge Function, con aprobación del
  usuario en el front antes de crear la compra.
- **Título de publicación ML desacoplado del título de stock** (no se pisan).
- Libertad creativa para **rediseñar la interfaz** manteniendo el Estilo B.

---

## 3. Arquitectura de información propuesta (rediseño de navegación)

Las 4 tabs quedan cortas. Propuesta de bottom nav (5 ítems) — ajustable:

`Inicio · Productos · Compras · Ventas · Ajustes`

- **Compras** (tab nueva): historial de compras + botón "Nueva compra" (flujo
  escaneo) + entrada a OCR de factura.
- **Depósitos**: se gestionan desde **Ajustes → Depósitos** (no es tab; es
  configuración). El picker de depósito aparece contextualmente en ajuste de stock,
  compra y transferencia.
- **Detalle de producto**: agrega "Stock por depósito" (desglose) + "Historial"
  (timeline movimientos + ventas) + acciones "Transferir" y "Publicar/Vincular ML".

---

## 4. Estado base ya hecho

**Fase 1 — Reactividad + saneamiento (COMPLETA).**
- Migración `20260619120001_realtime_publication.sql` (realtime → arregla que el
  front no reflejaba create/edit/ajuste de stock).
- Toggle "Vincular a publicación de ML" en
  [product_form_screen.dart](../apps/mobile/lib/src/features/products/product_form_screen.dart)
  ahora se oculta sin cuenta ML. **Pendiente:** ese toggle es decorativo (`_save()`
  no lee `_linkMl`) — se cablea en Fase 6.
- Pull-to-refresh agregado a
  [products_screen.dart](../apps/mobile/lib/src/features/products/products_screen.dart).

---

## 5. Fases a implementar

> Patrón de trabajo por fase: **DB (migración) → modelos (core_models) → repos →
> providers → UI → verificar**. Mantener Estilo B y reutilizar `app_widgets.dart`.

### Fase 2 — Depósitos en el front

**Objetivo:** dar UI a los depósitos (backend ya completo): gestionar depósitos,
elegir el principal/despacho, elegir depósito al mover stock, transferir entre
depósitos y ver el stock desglosado por depósito.

**Leer:** `20260618130002_stock_states_tables.sql` (warehouses/product_stock),
`20260618130003_stock_states_functions.sql` (`ensure_default_warehouse`,
`apply_stock_movement`), [inventory_repository.dart](../apps/mobile/lib/src/data/inventory_repository.dart),
[warehouse.dart](../packages/core_models/lib/src/warehouse.dart),
[stock_adjustment_sheet.dart](../apps/mobile/lib/src/features/stock_adjustment/stock_adjustment_sheet.dart),
[product_detail_screen.dart](../apps/mobile/lib/src/features/products/product_detail_screen.dart),
[settings_screen.dart](../apps/mobile/lib/src/features/settings/settings_screen.dart).

**Hacer:**
1. **DB (migración nueva):**
   - RPC `set_default_warehouse(p_warehouse_id uuid)` SECURITY INVOKER: en una
     transacción, `update warehouses set is_default=false where profile_id=auth.uid()
     and is_default; update warehouses set is_default=true where id=p_warehouse_id`
     (evita choque con `warehouses_one_default_idx`).
   - RPC `transfer_stock(p_product_id, p_from uuid, p_to uuid, p_qty int, p_note text)`
     SECURITY INVOKER: dos `stock_movements` (`−on_hand@from`, `+on_hand@to`,
     `reason='transfer'`, `origin='user'`, mismo `reference` = gen_random_uuid()
     para parearlos). Validar `p_qty>0` y que from/to sean del perfil.
   - Asegurar que al primer uso exista el "Depósito principal": `ensure_default_
     warehouse` ya lo crea (code `PRINCIPAL`, name "Depósito principal"). Exponer
     un RPC `ensure_default_warehouse_self()` (sin args, usa auth.uid()) o llamarlo
     desde el repo al abrir la pantalla de depósitos.
2. **Repos:** ampliar `InventoryRepository`:
   - `Future<List<Warehouse>> warehouses()` (ya existe), `createWarehouse` (ya),
   - `setDefaultWarehouse(id)`, `transferStock(...)`,
   - `Stream<List<Warehouse>> watchWarehouses()` (realtime) — **agregar `warehouses`
     a la publicación realtime en la migración** (con `replica identity full`),
   - `Stream<List<ProductStock>> watchStockFor(productId)` (realtime; `product_stock`
     ya está en la publicación).
3. **Providers (queries.dart):** `warehousesStreamProvider`,
   `stockByWarehouseProvider(productId)` (family).
4. **UI:**
   - `features/warehouses/warehouses_screen.dart`: listar depósitos (chip "Principal"
     en el default, badge "Vendible"), crear (sheet), marcar principal (set default),
     toggle `is_sellable`. Entrada desde **Ajustes**.
   - `stock_adjustment_sheet.dart`: agregar **picker de depósito** (sólo si hay >1);
     pasar `warehouseId` al RPC. Default = principal.
   - `product_detail_screen.dart`: tarjeta "Stock por depósito" (lista de
     `ProductStock` con on_hand/reserved/incoming) + botón **"Transferir"**
     (`features/stock_adjustment/transfer_sheet.dart`: from/to/cantidad).

**Verificar:** crear 2 depósitos, transferir, ver el desglose actualizarse en vivo;
cambiar el principal; ajustar stock eligiendo depósito. `flutter analyze` limpio.

**Done:** UI de depósitos operativa; el ajuste y la transferencia escriben con
`warehouse_id`; el detalle muestra desglose reactivo.

### Fase 3 — Compras + proveedores + histórico

**Objetivo:** registrar compras a proveedor escaneando por SKU, cerrarlas para
impactar stock, y ver histórico general y por producto.

**Leer:** `20260618120002_tables.sql` (stock_movements, products),
`20260618130001_stock_states_types.sql` (reasons/buckets),
[scan_screen.dart](../apps/mobile/lib/src/features/scan/scan_screen.dart) +
[catalog_result_sheet.dart](../apps/mobile/lib/src/features/scan/catalog_result_sheet.dart)
(reusar el lector `mobile_scanner` y el flujo de alta),
[products_repository.dart](../apps/mobile/lib/src/data/products_repository.dart)
(`findByCode`).

**Hacer:**
1. **DB (migración nueva):**
   - `suppliers (id, profile_id, name, notes?, created_at, updated_at)`
     unique(profile_id, lower(name)); RLS owner; realtime + replica identity full.
   - `purchases (id, profile_id, supplier_id?, status enum 'draft'|'closed', note?,
     warehouse_id? , total numeric, currency text default 'USD', purchased_at
     timestamptz, created_at, updated_at)`. Enum `purchase_status`.
   - `purchase_items (id, purchase_id, product_id, quantity int, unit_cost numeric,
     currency text, created_at)`. Index por purchase_id.
   - RLS owner en todas; realtime para `purchases`/`purchase_items`.
   - RPC `close_purchase(p_purchase_id uuid)` SECURITY INVOKER/DEFINER: valida
     status=draft; por cada item inserta `stock_movement` (`reason='purchase'`,
     `bucket='on_hand'`, `origin='user'`, `reference=p_purchase_id`,
     `warehouse_id` = el de la compra o el principal); set status='closed',
     `purchased_at=now()`, recomputa `total`. Idempotente (si ya closed, no-op).
     Opcional: actualizar `products.purchase_cost` al último costo.
2. **Modelos:** `Supplier`, `Purchase`, `PurchaseItem` en core_models (+ barrel).
3. **Repos:** `PurchasesRepository` (CRUD compra borrador, addItem/updateItem/
   removeItem, closePurchase, list/watch), `SuppliersRepository` (list/create).
   `ProductsRepository.movementsFor(productId)` → `List<StockMovement>` (tabla
   `stock_movements` ya indexada por product_id).
4. **Providers:** `purchasesStreamProvider`, `suppliersProvider`,
   `productHistoryProvider(productId)` (combina movements + sales en timeline).
5. **UI:**
   - Tab **Compras** (`features/purchases/purchases_screen.dart`): lista de compras
     (proveedor, fecha, #items, total, estado) + FAB "Nueva compra".
   - **Nueva compra** (`purchase_edit_screen.dart`): elegir/crear proveedor →
     elegir depósito → **escanear por SKU**: por cada scan, `findByCode`; si existe
     → sheet "cantidad a sumar" y agrega item; si NO existe → navegar a
     `ProductFormScreen` (alta), al volver con el producto agregar item. Lista de
     items editable. Botón **"Cerrar compra"** → `close_purchase` → snackbar +
     pop. Entrada alterna desde scan_screen ("agregar a compra").
   - **Detalle de producto → Historial:** timeline uniendo compras y ventas, ej.
     "Venta ML x3 · 12-03", "Compra #NNN x5 · 10-03", "Transferencia · …",
     "Ajuste +2 · …". Render con `SectionHeader` por día/mes.

**Verificar:** crear compra con varios productos y cantidades, cerrarla, ver el
stock subir (reactivo) y la compra aparecer en histórico; el historial por producto
muestra compras y ventas mezcladas. `flutter analyze` limpio; agregar test pgTAP de
`close_purchase`.

**Done:** flujo completo compra→stock; histórico general y por producto.

### Fase 4 — Import ML con verdad-en-la-app

**Objetivo:** traer publicaciones de ML a stock SIN duplicar y sin pisar el stock
local.

**Leer:** [_shared/items.ts](../supabase/functions/_shared/items.ts) (`upsertItem`),
[sync-items/index.ts](../supabase/functions/sync-items/index.ts),
[connection_repository.dart](../apps/mobile/lib/src/data/connection_repository.dart)
(`triggerInitialSync`).

**Hacer:**
1. **`upsertItem` (refinar):**
   - Antes de crear producto, **buscar match**: por `gtin` (si el item lo trae en
     `attributes` GTIN/EAN) y por `sku` (= `item.id` o seller_custom_field). Si hay
     match → usar ese `product_id`, **no crear**, **no tocar stock**, y encolar push
     (`stock_push_queue`) para mandar el stock local a ML.
   - Si NO hay match → crear producto (como hoy) y **sembrar stock** sólo en este
     caso: insertar `stock_movement` (`reason='initial_sync'`, `bucket='on_hand'`,
     `origin='ml'`, delta = `item.available_quantity`, `warehouse_id` = principal).
     `origin='ml'` evita rebote a ML.
   - Setear `products.gtin` cuando el item lo traiga.
2. **UI de import selectivo** (opcional pero recomendado):
   `features/import_ml/import_ml_screen.dart` — listar publicaciones del vendedor
   (vía función que liste items con estado "ya vinculado / nuevo"), permitir elegir
   cuáles importar. Si es mucho, dejar el `sync-items` masivo + un botón
   "Importar de ML" en Productos.

**Verificar:** importar con un producto ya existente (no duplica, no cambia su
stock) y con uno nuevo (lo crea con el stock de ML). Deno test de `upsertItem`.

**Done:** import idempotente respetando que la app es la verdad del stock.

### Fase 5 — OCR de factura (Claude Haiku visión)

**Objetivo:** subir foto de factura → extraer líneas → aprobar → crear compra.

**Leer:** [classify-product/index.ts](../supabase/functions/classify-product/index.ts)
(patrón Anthropic + structured output), `_shared/env.ts` (`anthropicConfig`),
**la skill `claude-api`** del harness antes de tocar el modelo (verificar modelo/
parámetros de visión vigentes).

**Hacer:**
1. **Edge Function `parse-invoice`:** auth del usuario (Bearer JWT, igual que
   classify-product). Recibe `{ image_base64, mime }` (o una URL de Storage).
   Llama a `/v1/messages` con `model: claude-haiku-4-5`, contenido multimodal
   (bloque `image` + `text`), `output_config.format.json_schema` =
   `{ supplier?, date?, currency?, items: [{ description, quantity, unit_cost,
   sku? }] }`. Devuelve el JSON.
2. **UI:** en "Nueva compra", botón "Escanear factura" → tomar/elegir foto
   (`image_picker`) → llamar `parse-invoice` → mostrar **borrador editable** de
   items (con match por SKU sugerido) → el usuario corrige/aprueba → se crean los
   `purchase_items`. Nunca crear sin aprobación.

**Verificar:** una factura de prueba produce líneas razonables; el usuario puede
editar antes de confirmar.

**Done:** OCR asistido con aprobación humana, integrado al flujo de compra.

### Fase 6 — Publicar / editar en ML

**Objetivo:** desde un producto interno, crear borrador en ML o vincular una
publicación existente, y editar la "parte bonita" sin tocar el título de stock.

**Leer:** [diseno-stock-estados.md](diseno-stock-estados.md) §7.3 (endpoints:
`GET /products/search` por GTIN, `POST /items/catalog_listings`, publicación libre),
`_shared/meli.ts` (`MeliClient` — ver métodos disponibles y agregar los que falten),
`ml_listings` (tabla) y `ml_listing.dart` (modelo).

**Hacer:**
1. **DB:** asegurar que `ml_listings.title` (título de la publi) es independiente de
   `products.title` (ya lo es; la vista de economics usa `coalesce(p.title, l.title)`
   — revisar que mostrar el título de publi donde corresponde no pise stock).
2. **Edge Function `publish-item`** (requiere scope de **escritura** ML — confirmar
   con el dueño): crea borrador (`POST /items`, status pausado/inactivo) o vincula
   un `ml_item_id` existente a un `product_id`. Encola push de stock.
3. **UI:** en el detalle de producto, acción "Publicar/Vincular en ML":
   - Vincular existente: pegar/elegir `MLAxxxx` → set `ml_listings.product_id`.
   - Crear borrador: form de la "parte bonita" (título de publi, precio, fotos,
     categoría ML) separado del stock. Cablear el toggle decorativo de Fase 1.

**Verificar:** vincular existente actualiza economics; crear borrador deja la publi
en ML pausada para revisión. **Confirmar scopes OAuth con el dueño antes.**

**Done:** publicar/vincular desde la app con título desacoplado.

---

## 6. Verificación y tests
- Flutter: `cd apps/mobile && flutter analyze` (debe quedar limpio); `flutter test`.
- core_models: `cd packages/core_models && dart test`.
- Postgres: `supabase test db` (pgTAP) — `close_purchase`, `add_purchase_item`,
  `transfer_stock` y `set_default_warehouse` cubiertos en
  `supabase/tests/02_warehouses_purchases_test.sql`.
- Deno: `deno test` en `supabase/functions/tests/` — cubre comparación,
  economics, meli/PKCE/fx y helpers de items (`variationRows`, `pgrestQuote`).
  La lógica de `upsertItem`/`parse-invoice` que toca la red/DB no tiene test
  unitario (se extraen helpers puros cuando se necesita cubrir algo).
- Commit por fase (mensaje convencional; co-author Claude). No pushear salvo pedido.

## 7. Checklist de progreso

- [x] Fase 1 — Reactividad realtime + toggle ML gateado + pull-to-refresh.
- [x] Fase 2 — Depósitos en el front. Hecho: migración
      `20260619120002_warehouses_rpcs.sql` (RPCs `ensure_default_warehouse_self`,
      `set_default_warehouse`, `transfer_stock` + warehouses en realtime);
      `InventoryRepository` ampliado; providers `warehousesStreamProvider` /
      `stockByWarehouseProvider`; `features/warehouses/warehouses_screen.dart`
      (gestión + set principal + toggle vendible + alta); picker de depósito en
      `stock_adjustment_sheet.dart`; `transfer_sheet.dart`; desglose por depósito
      en `product_detail_screen.dart`; entrada en Ajustes → Inventario.
      `flutter analyze` limpio. Tests pgTAP de los RPCs en
      `supabase/tests/02_warehouses_purchases_test.sql` (2026-07-02).
- [x] Fase 3 — Compras + proveedores + histórico. Hecho: migración
      `20260619120003_purchases.sql` (tablas suppliers/purchases/purchase_items,
      RPCs `add_purchase_item` y `close_purchase`, RLS + realtime); modelos
      `Supplier`/`Purchase`/`PurchaseItem`; `PurchasesRepository` +
      `SuppliersRepository`; `ProductsRepository.movementsFor`; providers
      (`purchasesStreamProvider`, `purchaseItemsProvider`, `suppliersProvider`,
      `productHistoryProvider`); tab **Compras** (bottom nav → 5 ítems);
      `purchases_screen.dart` (lista) + `purchase_edit_screen.dart` (proveedor,
      depósito, agregar por SKU buscando/escribiendo, qty+costo, cerrar→stock,
      descartar); historial por producto en `product_detail_screen.dart`.
      `flutter analyze` limpio. Pendientes menores cerrados el 2026-07-02:
      (a) escáner en vivo embebido para el alta por SKU — chrome del escáner
      extraído a `features/scan/scanner_chrome.dart`, nueva
      `features/scan/code_scanner_screen.dart` ("leer un código y volver") y
      botón de cámara en el buscador de `purchase_edit_screen.dart` (match
      exacto por SKU/GTIN → sheet de cantidad; sin match → queda cargado para
      crear el producto); (b) el historial ahora es reactivo —
      `ProductsRepository.watchMovementsFor` (realtime) +
      `productMovementsProvider`, del que deriva `productHistoryProvider`;
      (c) tests pgTAP de `add_purchase_item`/`close_purchase` en
      `supabase/tests/02_warehouses_purchases_test.sql`.
- [x] Fase 4 — Import ML sin duplicar. Hecho: `_shared/items.ts` `upsertItem`
      refinado (dedup por GTIN/SKU; si el producto ya existe → vincular + encolar
      push del stock local a ML; si es nuevo → crear + sembrar stock con
      `initial_sync` origin=ml); `MeliItem` ampliado con `seller_custom_field` y
      `attributes`; botón "Importar publicaciones" en Ajustes (invoca `sync-items`).
      Deno check OK. **Pendiente menor:** UI de import selectivo (hoy importa todo).
- [x] Fase 5 — OCR de factura (Haiku visión) — **completa**. Backend: Edge
      Function `parse-invoice` (Claude Haiku 4.5, visión base64 + structured output
      `{supplier,date,currency,items[]}`); `PurchasesRepository.parseInvoice`.
      UI: dep `image_picker`; botón "Escanear factura" (AppBar) en
      `purchase_edit_screen.dart` → cámara/galería → base64 → `parseInvoice` →
      `_InvoiceReviewSheet` (match por SKU/GTIN contra productos vivos; el usuario
      tilda las líneas con coincidencia → `addItem`; las sin match se marcan para
      crear a mano). iOS: `NSPhotoLibraryUsageDescription` agregado al Info.plist.
      `flutter analyze` + `deno check` limpios.
- [x] Fase 6 — **Vincular publicación ML existente** (sin scope nuevo). Hecho:
      `upsertItem` acepta `forceProductId`; Edge Function `link-ml-listing`
      (lectura GET /items, vincula `ml_listings.product_id` + encola push del stock
      local); `ConnectionRepository.linkListing`; acción "Vincular publicación de
      ML" en el detalle del producto (solo si ML conectado y no publicado); se quitó
      el toggle decorativo del alta (ahora un hint que apunta al detalle).
      **Pendiente:** crear BORRADOR en ML (`POST /items`) — requiere CONFIRMAR los
      scopes OAuth de **escritura** con el dueño y manejar los campos obligatorios
      de ML; recién entonces se construye `publish-item` + el form de la parte
      "bonita" (título de publi desacoplado del de stock).

> Al completar una fase: marcar el check, actualizar §4/§7 con lo realmente hecho y
> cualquier desvío del plan, y dejar el `flutter analyze` limpio.

**Estado al 2026-07-02:** todas las fases completas y pendientes menores
cerrados (`flutter analyze` + `flutter test` + `supabase test db` en verde).
Quedan solo dos ítems fuera de alcance por decisión: la UI de import selectivo
de ML (opcional; el import masivo desde Ajustes ya cubre el caso) y **crear
borrador en ML** (`publish-item`), bloqueado hasta confirmar con el dueño los
scopes OAuth de escritura.

**Addendum auditoría 2026-07-02 (RF-07 + RF-19 + fixes):**
- **RF-07 variaciones (espejo):** `upsertItem` ahora refleja las variaciones del
  item en `listing_variations` (upsert + poda de las que ML ya no reporta;
  helper puro `variationRows` con test Deno). Migración
  `20260702130000_listing_variations_realtime.sql` (realtime + replica identity).
  Modelo `ListingVariation` en core_models (label "Rojo · XL");
  `ConnectionRepository.watchListingVariations` + `listingVariationsProvider`;
  tarjeta "Variaciones (ML)" en el detalle de producto. El stock por variación
  se sigue administrando en ML.
- **Fix push-stock × variaciones:** ML rechaza `available_quantity` a nivel ítem
  cuando la publicación tiene variaciones → `push-stock` ahora omite esas
  publicaciones (nota informativa en `stock_push_queue.error`) en vez de entrar
  en el loop de reintentos.
- **Fix filtro `or` de dedup:** los valores GTIN/SKU se citan con `pgrestQuote`
  para que `,`/`(`/`)` dentro de un SKU no rompan la sintaxis de PostgREST.
- **RF-19 comparativa entre productos:** `productComparisonProvider` (economics
  + rotación 30 días desde ventas) y `product_comparison_screen.dart`
  (orden por margen/markup/ganancia/rotación; internos sin economics al final);
  entrada con ícono en el header de Productos.
- Requisitos actualizados en [requisitos.md](requisitos.md) §6 (matriz de
  estado): lo único abierto es RF-22 (push FCM, bloqueado por credenciales),
  RNF-05/07 parciales y los dos ítems por decisión de arriba.

**Addendum 2026-07-02 (2): vista por depósito + desglose siempre visible.**
- Detalle de producto: "Stock por depósito" ahora lista **todos** los depósitos
  (0 si no hay stock) con chips **Reservado**/**En camino** (antes texto chico
  y filas ocultas si todo era 0).
- Nueva `features/warehouses/warehouse_detail_screen.dart` (tap en un depósito
  desde Ajustes → Depósitos): chips de rol, totales por bucket, productos con
  stock en ese depósito (tap → detalle; botón **transferir con origen
  preseleccionado** — `TransferSheet` acepta `fromWarehouseId`) y **historial
  del depósito** (ledger completo, incluye reservas/despachos ML, con bucket).
- Repos/providers nuevos: `watchStockInWarehouse`, `watchAllStock`,
  `watchMovementsInWarehouse` en InventoryRepository;
  `stockInWarehouseProvider`, `allStockStreamProvider`,
  `warehouseTotalsProvider` (línea "N productos · M disp." en la lista),
  `warehouseMovementsProvider`.
- Nota: vender fuera de ML hoy = ajuste con motivo "Venta" (descuenta y
  empuja a ML) pero sin registro comercial (importe/canal no van a `sales`);
  flujo de venta local queda como candidato a fase nueva.

**Addendum 2026-07-03: venta local + clientes/proveedores + flujos operativos.**
- **Venta local (RF-29):** migración `20260703120000_local_sales_customers.sql`
  — enum `sale_channel` ('ml'|'local') en `sales` (ml_order_id pasa a nullable
  con check por canal), `customer_id` opcional, tabla `customers` (RLS owner +
  realtime) y RPC `create_local_sale` (inserta la venta y descuenta on_hand
  vía `apply_stock_movement` origin=user → push a ML). pgTAP en
  `03_local_sales_customers_test.sql` (18 asserts). En el front:
  `LocalSaleSheet` (botón **Vender** en el detalle; cantidad, precio, cliente
  opcional con alta rápida, depósito), chips **ML/Local** en Ventas (con
  nombre del cliente en las locales), dedup en el historial (la venta local no
  duplica su movimiento) y modelos `Customer`/`Sale.channel`.
- **Proveedores (RF-30 + fix):** el picker de la compra ahora observa
  `suppliersProvider` en vivo (antes recibía un snapshot que podía llegar
  vacío → "no aparece nada"), suma **"Proveedor no especificado"**
  (`updateHeader(clearSupplier: true)`) y datos extra opcionales (razón
  social, CUIT/CUIL, teléfono) tanto en proveedores como en clientes.
- **Escaneo continuo en compras:** `purchase_scan_screen.dart` — la cámara
  queda abierta; código conocido → sheet cantidad/costo y vuelve a la cámara;
  código nuevo → alta de producto (GTIN/SKU prellenado) → cantidad → cámara;
  botón "Finalizar carga · N líneas". `QtyCostSheet` extraído a archivo
  compartido. El FAB de la compra abre el escaneo continuo; la búsqueda manual
  quedó como "Buscar" junto al header.
- **Tab Movimientos** (bottom nav ahora 6): `movements_screen.dart` —
  origen→destino explícito con swap, lista del stock del origen con stepper
  (filas con movimiento ≠ 0 resaltadas), escaneo para sumar +1, confirmación
  con **detalle de lo movido** y manejo de error parcial.
- **Onboarding import:** tras conectar ML (deep-link o "Ya autoricé"),
  `offerInitialImport` ofrece importar las publicaciones ahí mismo con
  progreso bloqueante e invalidación de products/economics.
