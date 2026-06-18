# Diseño — Estados de stock, sincronización con ML y clasificación

> Estado: propuesta de diseño. Fecha: 2026-06-18.
> Deriva de [requisitos.md](requisitos.md) y de las decisiones tomadas en este
> documento (§0). Cubre: dirección de sincronización (anti-ciclo ML↔stock),
> modelo de stock en dos fases por depósito, ciclo de vida de los estados,
> reconciliación idempotente de órdenes, categorías/marca y clasificación por LLM.

## 0. Decisiones tomadas (2026-06-18)

- **Contabilidad de stock → dos fases.** Se separan `on_hand` (físico en
  depósito) y `reserved` (vendido sin despachar). `available = on_hand − reserved`
  es lo que se publica en ML. La venta **reserva** (no toca el físico); el
  despacho descuenta el físico. Cada estado es un bucket real de stock.
- **Granularidad → por depósito.** Cada movimiento lleva `warehouse_id`; el stock
  se calcula por `(producto, depósito)`. Lo publicado en ML = suma de los
  depósitos vendibles. Las ventas de ML descuentan de un depósito de despacho por
  defecto.
- **Dirección de la verdad → Supabase manda** (ya estaba en
  [04-decisiones-pendientes.md](research/04-decisiones-pendientes.md) decisión A).
  ML es un canal que se sincroniza.
- **Carga de productos → barcode-first** (estilo supermercado). El clasificador
  primario es el catálogo de ML por GTIN; el LLM es el **último fallback** (ver §7).
- **Creación de catálogo en ML → no hay endpoint público estándar**; sin match se
  publica libre con el GTIN como atributo (ML cataloga luego por su moderación).

## 1. Principio rector: el ciclo ML → stock → ML

ML notifica al sistema ventas, cancelaciones y devoluciones. Esas notificaciones
**no deben volver a influir en ML**: cuando ML vende, ML ya descontó de su propio
`available_quantity`; volver a empujarle nuestro número cierra un ciclo
(ML → stock → ML) redundante y propenso a errores.

> **Regla de oro de sincronización:** lo único que dispara un `PUT /items` hacia
> ML son los **cambios originados por el usuario** (recibir compra, ajuste manual,
> retiro/pérdida, re-stock de una devolución inspeccionada). Los **eventos de ML**
> (venta, cancelación, devolución) ajustan solo el ledger interno y **nunca** se
> re-empujan.

### 1.1 Cómo se implementa: `origin` en cada movimiento

Cada `stock_movement` lleva un `origin`:

| `origin` | Quién lo genera | ¿Empuja a ML? |
|----------|-----------------|---------------|
| `ml`     | Webhooks/sync de órdenes y envíos | **No** (ML ya refleja el cambio) |
| `user`   | Acciones del usuario en la app    | **Sí** (`PUT /items`) |
| `system` | Sync inicial, ajustes automáticos | **Sí** (reconciliación a ML) |

El push a ML se centraliza en una sola función (`reconcile_listing_to_ml`) que se
invoca **solo** para movimientos `user`/`system`.

### 1.2 El bug actual

Hoy en [`supabase/functions/_shared/orders.ts`](../supabase/functions/_shared/orders.ts)
`processOrder()` descuenta stock y **además** hace `client.updateItemQuantity(...)`
tras una venta originada en ML (líneas 69–79). Eso es exactamente el ciclo a
eliminar: hay que quitar ese push y dejar que la venta solo ajuste el ledger.

### 1.3 Matiz: listings que comparten producto

Si varios `ml_listings` apuntan al mismo `product`, una venta en el listing A
**sí** obliga a empujar el nuevo `available` a los listings hermanos B/C: ML solo
descontó el listing A, pero nuestra verdad (el producto) bajó para todos. Esto
**no viola** la regla: no es eco del mismo listing, es reconciliar ML con la
verdad interna. Para el MVP single-listing-per-product es un no-op; queda
contemplado en `reconcile_listing_to_ml` (empuja a todos los listings activos del
producto **salvo** al que originó el evento de ML).

## 2. Modelo de stock en dos fases por depósito

### 2.1 Conceptos

Por cada `(producto, depósito)` se llevan tres cantidades:

| Bucket     | Significado | Estado del usuario |
|------------|-------------|--------------------|
| `incoming` | Pedido al proveedor, aún no recibido | **pedido** |
| `on_hand`  | Físicamente en el depósito (incluye lo vendido sin despachar) | **en depósito** |
| `reserved` | Vendido y confirmado, sin despachar | **por despachar** |

Derivados:

- `available(producto)` = Σ sobre depósitos vendibles de `(on_hand − reserved)`.
  **Es el número que se publica en ML.**
- El despacho hace `on_hand −= qty` y `reserved −= qty` (la unidad sale del
  depósito y se libera la reserva); `available` queda igual porque ya había bajado
  al reservar.

### 2.2 Esquema (DDL ilustrativo)

```sql
-- Depósitos (depósitos físicos / ubicaciones)
create table public.warehouses (
  id          uuid primary key default gen_random_uuid(),
  profile_id  uuid not null references public.profiles(id) on delete cascade,
  code        text not null,
  name        text not null,
  is_default  boolean not null default false,  -- depósito de despacho por defecto
  is_sellable boolean not null default true,   -- cuenta para el available de ML
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (profile_id, code)
);

-- Buckets enum
create type public.stock_bucket as enum ('incoming', 'on_hand', 'reserved');

-- Origen del movimiento (gobierna el push a ML)
create type public.stock_origin as enum ('ml', 'user', 'system');

-- Ledger append-only (reemplaza el stock_movements actual)
create table public.stock_movements (
  id          uuid primary key default gen_random_uuid(),
  profile_id  uuid not null references public.profiles(id) on delete cascade,
  product_id  uuid not null references public.products(id) on delete cascade,
  warehouse_id uuid not null references public.warehouses(id),
  bucket      public.stock_bucket not null,
  delta       int not null,
  reason      public.stock_reason not null,
  origin      public.stock_origin not null default 'user',
  reference   text,    -- ml_order_id, purchase_id, etc.
  note        text,
  created_by  uuid references auth.users(id),
  created_at  timestamptz not null default now()
);

-- Stock denormalizado por (producto, depósito), mantenido por trigger
create table public.product_stock (
  product_id   uuid not null references public.products(id) on delete cascade,
  warehouse_id uuid not null references public.warehouses(id),
  incoming     int not null default 0,
  on_hand      int not null default 0,
  reserved     int not null default 0,
  updated_at   timestamptz not null default now(),
  primary key (product_id, warehouse_id)
);
```

- El trigger sobre `stock_movements` hace
  `update product_stock set <bucket> = <bucket> + new.delta`.
- `products.available_quantity` (denormalizado) = Σ vendibles `(on_hand − reserved)`,
  mantenido por trigger; es lo que `reconcile_listing_to_ml` empuja a ML.
- Se amplía el enum `stock_reason` con: `purchase_ordered`, `purchase_received`,
  `reserve`, `dispatch`, `cancellation`, `return`, `bounce`, `loss`, `transfer`.

### 2.3 Estados ↔ movimientos

| Estado | Disparador | Movimiento(s) | origin |
|--------|-----------|---------------|--------|
| **pedido** | Usuario crea orden de compra | `+incoming` | user |
| **en depósito A** | Llega la compra | `−incoming`, `+on_hand@A` | user → push ML |
| **por despachar** | ML confirma venta (`paid`) | `+reserved` | ml |
| **despachado** | Webhook `shipments` = shipped | `−on_hand`, `−reserved` | ml |
| **cancelado** (pre-despacho) | Orden `cancelled` | `−reserved` | ml |
| **rebotado** | Envío `not_delivered`/devuelto al remitente | (ver §4.2) | ml + user |
| **perdido** | Envío perdido en tránsito | marcar; `−on_hand` ya ocurrió al despachar | ml |

## 3. Movimientos por acción del usuario (empujan a ML)

- **Agregar stock** (recibir compra / ajuste +): `+on_hand`, `origin=user` →
  push `available` a ML.
- **Retirar stock** (pérdida/robo/ajuste −): `−on_hand`, `origin=user` → push.
- **Transferencia entre depósitos**: `−on_hand@A`, `+on_hand@B`, `origin=user`.
  Si ambos son vendibles, `available` total no cambia → push idempotente.
- **Re-stock de devolución inspeccionada**: `+on_hand`, `origin=user` → push.

Estos pasan por el RPC `apply_stock_movement(...)` (ya existe, se amplía con
`warehouse_id`, `bucket`, `origin`), que tras insertar invoca
`reconcile_listing_to_ml` si `origin ∈ {user, system}`.

## 4. Reconciliación idempotente de órdenes de ML

### 4.1 Por qué reconciliar y no aplicar deltas

Hoy `processOrder` siempre descuenta sin mirar el estado de la orden, y lo hace en
dos pasos (contar + insertar) → no es atómico y rompe ante desorden de
notificaciones. El fix: **calcular el efecto neto que la orden debe tener según su
estado actual** (leído fresco con `GET /orders/{id}` + `GET /shipments/{id}`) y
crear el movimiento compensatorio para llegar a ese estado, dentro de una función
Postgres atómica que toma lock por `ml_order_id`.

### 4.2 Efecto deseado por estado (dos dimensiones)

Para cada orden se mantiene el par `(Δreserved, Δon_hand)` que la orden aporta
respecto del baseline pre-venta:

| Estado orden/envío | Δreserved | Δon_hand | Estado usuario |
|--------------------|-----------|----------|----------------|
| `paid`, sin despachar | +qty | 0 | por despachar |
| `shipped`/`delivered` | 0 | −qty | despachado |
| `cancelled` (pre-despacho) | 0 | 0 | cancelado |
| `cancelled`/`refunded` (post-despacho) | 0 | 0 *(neto)* | rebotado/devuelto |
| `not_delivered` (vuelve al remitente) | 0 | 0 *(neto)* | rebotado |
| perdido en tránsito | 0 | −qty | perdido |

`movimiento_compensatorio(dim) = Δdeseado(dim) − Δactual(dim)`, donde `Δactual`
es la suma de los movimientos previos de esa `reference` en ese bucket. Todos los
compensatorios de eventos de ML son `origin=ml` (no empujan), **excepto** el
re-stock físico de un rebotado/devuelto, que es una acción del usuario (inspecciona
y decide si vuelve a estar disponible → `origin=user` → push a ML).

### 4.3 Tabla de escenarios (los 3 problemas + extras)

| Escenario | actual → deseado | acción | Resultado |
|-----------|------------------|--------|-----------|
| Venta normal (1ª vez) | reserved 0 → +1 | inserta `+reserved 1` | ✅ descuenta `available` |
| Doble notificación | reserved +1 → +1 | no-op | ✅ idempotente |
| Cancelada **antes** de descontar | reserved 0 → 0 | no-op | ✅ no descuenta |
| Cancelada **después** de descontar | reserved +1 → 0 | inserta `−reserved 1` | ✅ revierte |
| Despacho | reserved +1, on_hand 0 → reserved 0, on_hand −1 | `−reserved 1`, `−on_hand 1` | ✅ |
| Devolución post-envío | on_hand −1 → 0 | `+on_hand 1` (user) | ✅ restaura (con inspección) |
| Desorden (cancel y luego "paid" viejo) | lee estado fresco = cancelled → 0 | no-op | ✅ a prueba de orden |

### 4.4 Función e idempotencia

```sql
-- Pseudocódigo de la función atómica (SECURITY DEFINER)
create function public.reconcile_order_stock(
  p_profile_id uuid, p_order_id text, p_lines jsonb, p_desired jsonb
) returns void language plpgsql as $$
begin
  perform pg_advisory_xact_lock(hashtext(p_order_id));   -- 1 worker por orden
  -- por cada línea (product, warehouse, qty):
  --   para bucket in (reserved, on_hand):
  --     delta := desired(bucket) - coalesce(sum(movimientos de p_order_id, bucket), 0)
  --     if delta <> 0 then insert stock_movements(..., origin = 'ml');
end; $$;
```

- **Clave de idempotencia:** la suma de movimientos por `reference = ml_order_id`
  ya refleja lo aplicado; reconciliar hasta el deseado es naturalmente idempotente.
- **Atomicidad:** `pg_advisory_xact_lock` evita que `process-events` y
  `sync-orders` procesen la misma orden en paralelo.
- La tabla `sales` suma `fulfillment_status` (`reserved`/`shipped`/`delivered`/
  `cancelled`/`bounced`/`lost`) para visibilidad; la deriva el reconciliador.

## 5. Webhooks involucrados

| Topic ML | Para qué | Acción |
|----------|----------|--------|
| `orders_v2` | venta confirmada / cancelación | `GET /orders/{id}` → `reconcile_order_stock` |
| `shipments` | despachado / rebotado / no entregado | `GET /shipments/{id}` → actualizar `fulfillment_status` y reconciliar |
| `claims` | devoluciones / reclamos | marcar devolución pendiente de inspección (no auto-restock) |

`process-events` enruta por `topic` (ya lo hace para `orders`/`items`; se agrega
`shipments` y `claims`). Se mantiene el patrón ack-rápido + cola `ml_events`.

## 6. Categorías, marca y filtrado

```sql
create table public.product_categories (
  id         uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles(id) on delete cascade,
  parent_id  uuid references public.product_categories(id) on delete set null,
  name       text not null,
  slug       text not null,
  created_at timestamptz not null default now(),
  unique (profile_id, slug)
);

alter table public.products
  add column category_id uuid references public.product_categories(id) on delete set null,
  add column brand text,
  add column gtin  text;   -- código de barras global (EAN/UPC), distinto del sku interno

create index products_category_idx on public.products (profile_id, category_id);
create index products_brand_idx    on public.products (profile_id, brand);
create unique index products_gtin_uidx
  on public.products (profile_id, gtin) where gtin is not null;
```

- `category_id` es la **categoría interna** (distinta del `category_id` de ML que
  ya vive en `ml_listings`).
- `gtin` es el código de barras **global** (EAN/UPC); `sku` es el código **interno**
  (puede ser alfanumérico, ej. `TPSLI20281`). El `catalog_product_id` de ML se
  guarda en `ml_listings` (ver §7).
- Filtrado en la app por categoría y por marca (Riverpod + queries Supabase).

## 7. Carga de productos por código de barras (barcode-first)

El alta y la reposición de stock son **barcode-first** (estilo supermercado): se
escanea un código y el sistema autocompleta todo lo posible; el usuario solo
confirma. **El LLM es el último fallback, no el clasificador primario.**

### 7.1 Lector de código

- Librería Flutter: **`mobile_scanner`** (EAN-8/13, UPC-A/E, Code128, Code39, QR).
  Devuelve `value` + `symbology`.
- Clasificación del código escaneado:
  - **GTIN** (EAN-8/13, UPC-A/E) con **checksum GS1 válido** → código global de
    producto → rama de enriquecimiento (A).
  - **Alfanumérico** (Code128/39, QR-texto), ej. `TPSLI20281` → **SKU interno /
    modelo**, sin lookup universal → rama B.
- Normalización: UPC-A (12 díg.) → EAN-13 anteponiendo `0`; se valida checksum
  antes de tratar el código como GTIN.
- Ejemplos reales: `6937541239382` = EAN-13 válido (prefijo GS1 `693` = China) pero
  **sin datos en bases públicas** → cae a la cascada §7.4 (caso frecuente en
  importación). `TPSLI20281` = rama B (SKU interno).

### 7.2 Flujo lógico (aprobado 2026-06-18)

```
ESCANEO (value + symbology)
 ├ [1] ¿GTIN válido?   sí → rama A   |   no (alfanumérico) → rama B
 ├ [2] ¿Ya existe en products (gtin/sku)?   sí → "SUMAR STOCK" (cant.+depósito) → FIN
 │     RAMA A (GTIN nuevo): [3] enriquecer en cascada (§7.4)
 │     RAMA B (SKU interno): guardar sku; alta manual; LLM sugiere clasificación
 ├ [4] ¿Publicar en ML? (opcional)   catálogo (si hubo match) | libre con GTIN
 └ [5] Stock inicial: +on_hand@depósito (origin=user) → push a ML
```

### 7.3 Enriquecimiento por GTIN contra ML (endpoints verificados 2026-06-18)

1. **Buscar en el catálogo de ML por GTIN:**
   `GET /products/search?status=active&site_id=MLA&product_identifier=<GTIN>`
   (ML valida el GTIN contra el checksum GS1). Respuesta: `results[]` con `id`
   (= `catalog_product_id`), `name`, `domain_id`, `attributes`, `status`.
   `status=active` ⇒ publicable en catálogo.
   - **Match** → autocompletar `title`, `brand`, categoría (mapear `domain_id`/
     atributos a categoría interna), imagen; guardar `gtin` + `catalog_product_id`
     (en `ml_listings`). El usuario confirma. *(Es el "ML saca el nombre" del pedido.)*
2. **Publicar contra catálogo** (si hubo match y el usuario decide publicar):
   `POST /items/catalog_listings` con `item_id` + `catalog_product_id`.
   `listing_strategy=catalog_required` marca categorías donde el catálogo es
   obligatorio.
3. **Sin match:** **no hay endpoint público para crear una ficha de catálogo nueva**
   (ML lo modera internamente). Fallback robusto: **publicar libre** (no-catálogo)
   con el GTIN como atributo (siempre posible); ML puede catalogarlo luego. Una
   publicación puede quedar moderada/pausada por no asociarse a catálogo a tiempo
   (se detecta por `cause`/`actionable` del ítem).

### 7.4 Clasificación en cascada (LLM = último fallback)

Orden para asignar **categoría interna** + **marca** (cada paso solo corre si el
anterior no resolvió):

1. **Catálogo ML por GTIN** (§7.3.1) — `name`, `domain_id`, `brand` de la ficha.
   Mejor fuente cuando hay match.
2. **Predictor de categoría de ML** (nativo, gratis) — desde el título:
   `GET /sites/MLA/domain_discovery/search?q=<título>`. Da `domain_id`/categoría
   sin LLM; es el **primario** cuando no hay match de catálogo.
3. **Bases GTIN externas** (best-effort; MVP solo gratis: Open Food Facts) — al
   menos un nombre.
4. **LLM (Claude Haiku 4.5)** — **último fallback**: cuando lo anterior no alcanza,
   sugiere categoría interna + marca con salida estructurada.

### 7.5 El LLM de fallback (`classify-product`)

- **Modelo: Claude Haiku 4.5** (`claude-haiku-4-5`) — el más barato/rápido,
  **$1 / $5 por MTok**, contexto 200K, soporta **structured outputs** (JSON válido
  garantizado). Intercambiable por `claude-sonnet-4-6`/`claude-opus-4-8`.
  `ANTHROPIC_API_KEY` vive **solo en el backend**.
- Entrada `{ product_id }`; carga `product_categories` del perfil y pide a la
  Messages API con `output_config.format` un `{ category_slug (enum), brand,
  confidence }`. Si `confidence ≥ umbral` persiste; si no, deja sugerencia.

```ts
const res = await anthropic.messages.create({
  model: "claude-haiku-4-5",
  max_tokens: 256,
  system: "Clasificás productos de e-commerce (MLA). Elegí la categoría más " +
          "adecuada de la lista y extraé la marca; si ninguna encaja, 'otros'.",
  messages: [{ role: "user", content: `Título: ${title}\nDescripción: ${desc ?? "-"}` }],
  output_config: { format: { type: "json_schema", schema: {
    type: "object",
    properties: {
      category_slug: { type: "string", enum: [...categorySlugs, "otros"] },
      brand:         { type: "string" },
      confidence:    { type: "number" },
    },
    required: ["category_slug", "brand", "confidence"],
    additionalProperties: false,
  } } },
});
```

> Haiku 4.5 **no** acepta `effort` ni necesita `thinking` para esto. `max_tokens`
> chico (256) porque la salida es un objeto pequeño.

### 7.6 Disparo y MVP

- **Disparo:** la cascada §7.4 corre al escanear/crear/importar, asíncrona y
  best-effort (no bloquea el alta); reintentable. El LLM solo se invoca si los
  pasos 1–3 no resolvieron.
- **MVP:** categorías planas del perfil; marca por catálogo/título. Sin embeddings
  ni fine-tuning.
- **Override:** la UI muestra la sugerencia (fuente + `confidence`); el usuario
  confirma/corrige. Las correcciones quedan como verdad.

## 8. Plan de implementación por fases

1. **Fase 1 — Núcleo de sincronización (mayor valor, arregla los ❌).**
   - `origin` en `stock_movements`; quitar el push-back de `processOrder`.
   - Función `reconcile_order_stock` + `reconcile_listing_to_ml`.
   - Reescribir `process-events`/`sync-orders` para reconciliar por estado.
   - Tests pgTAP de los 6 escenarios de §4.3.
2. **Fase 2 — Dos fases + depósitos.**
   - `warehouses`, `product_stock`, buckets en el ledger, triggers.
   - Webhook `shipments`; `fulfillment_status` en `sales`; lifecycle completo.
3. **Fase 3 — Compras / incoming.**
   - Flujo `pedido → en depósito` (orden de compra liviana), bucket `incoming`.
4. **Fase 4 — Carga por código de barras, catálogo y clasificación.**
   - Campo `products.gtin`; lector `mobile_scanner`; flujo barcode-first (§7.2).
   - Enriquecimiento por GTIN: `GET /products/search`; publicación de catálogo
     `POST /items/catalog_listings`; fallback publicación libre con GTIN.
   - Clasificación en cascada: catálogo ML → predictor de categoría ML → LLM
     (`classify-product`, Haiku 4.5) como último fallback.
   - `product_categories`, `brand`, filtros en la app; UI de sugerencia/override.

## 9. Cambios por archivo (resumen)

| Archivo | Cambio |
|---------|--------|
| `migrations/*_init_extensions_types.sql` | enums `stock_bucket`, `stock_origin`; ampliar `stock_reason` |
| `migrations/*_tables.sql` | `warehouses`, `product_stock`; columnas en `stock_movements`, `sales`, `products` (`gtin`/`category_id`/`brand`); `product_categories` |
| `migrations/*_functions_triggers.sql` | trigger de buckets; `reconcile_order_stock`; `reconcile_listing_to_ml`; ampliar `apply_stock_movement` |
| `functions/_shared/orders.ts` | reconciliación por estado; quitar push-back; sin echo a ML |
| `functions/_shared/shipments.ts` (nuevo) | manejo de `shipments` |
| `functions/process-events/index.ts` | enrutar `shipments`/`claims` |
| `functions/_shared/catalog.ts` (nuevo) | búsqueda `/products/search` por GTIN + publicación `catalog_listings` + predictor de categoría |
| `functions/classify-product/index.ts` (nuevo) | clasificador LLM (último fallback) |
| `apps/mobile/lib/src/...` (scanner) | `mobile_scanner` + pantalla de carga barcode-first |
| `packages/core_models/lib/src/*` | `StockBucket`, `StockOrigin`, `Warehouse`, `ProductCategory`; `gtin` en `Product`; `fulfillment_status` en `Sale` |
