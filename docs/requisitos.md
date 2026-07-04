# Requisitos — stock-for-ml

> Estado: vivo. Última actualización: 2026-07-02.
> Deriva de las decisiones en [research/04-decisiones-pendientes.md](research/04-decisiones-pendientes.md).
> Diseño detallado de estados de stock, sincronización con ML (anti-ciclo),
> reconciliación de órdenes y clasificación por LLM: ver
> [diseno-stock-estados.md](diseno-stock-estados.md).

## 1. Alcance y supuestos

- **Usuario:** un único dueño (single-user), con **una** cuenta de MercadoLibre.
  El modelo igual contempla `profile_id` para no cerrar la puerta a multi-tenant.
- **Sitio ML:** MLA (Argentina). Moneda de venta: ARS.
- **Costos de compra:** en USD. Conversión a ARS vía tipo de cambio automático
  (API del dólar) cacheado en Supabase.
- **Fuente de verdad del stock:** Supabase. ML es un canal que se sincroniza.
- **Catálogo:** productos publicados en ML **y** productos internos sin publicar.

## 2. Requisitos funcionales (RF)

### Autenticación y cuenta
- **RF-01** El usuario inicia sesión en la app (Supabase Auth, email/password).
- **RF-02** El usuario conecta su cuenta de ML vía OAuth 2.0 (con PKCE). Los
  tokens se guardan en el backend, nunca en el dispositivo.
- **RF-03** El sistema refresca automáticamente el `access_token` de ML antes de
  que expire (cada ≤6 h) rotando el `refresh_token`.

### Productos y catálogo
- **RF-04** Crear/editar/eliminar productos internos (SKU, título, costo de
  compra en USD, foto, notas). Carga **barcode-first**: el escáner distingue
  GTIN (EAN/UPC → rama catálogo) de SKU alfanumérico (alta manual).
- **RF-05** Importar las publicaciones existentes de ML como productos/listings,
  **sin duplicar y sin pisar el stock local**: match por GTIN/SKU; si el
  producto ya existe se vincula el listing y se empuja el stock local a ML; el
  stock de ML se siembra solo en productos nuevos (`initial_sync`, origin=ml).
- **RF-06** Vincular un producto interno con una publicación de ML (el título
  de la publicación queda desacoplado del título de stock).
- **RF-07** Soportar variaciones de una publicación (talle/color/etc.) con stock
  por variación. *Alcance actual:* la app **espeja** las variaciones y su stock
  ML (`listing_variations`) y las muestra en el detalle; el stock por variación
  se administra en ML (el push automático omite publicaciones con variaciones
  porque ML rechaza `available_quantity` a nivel ítem en esos casos).
- **RF-23** Clasificación asistida de productos en **cascada**: catálogo ML por
  GTIN → predictor de categoría de ML → LLM como último fallback
  (`classify-product`, Claude Haiku); categorías internas propias + marca.

### Stock
- **RF-08** Ver el stock actual por producto, con desglose por depósito y por
  bucket (`on_hand` / `reserved` / `incoming`; disponible = on_hand − reserved).
- **RF-09** Registrar movimientos de stock (compra, venta, ajuste, devolución)
  en un ledger append-only con `origin` (`ml`/`user`/`system`) anti-ciclo.
- **RF-10** Al confirmarse una venta en ML, descontar stock automáticamente
  (reconciliación idempotente por estado de orden + envío; la venta reserva,
  el despacho descuenta físico).
- **RF-11** Empujar el stock actualizado a ML (`PUT /items`) cuando Supabase es
  la fuente de verdad (solo movimientos `user`/`system`; cola con reintentos).
- **RF-12** Alertar (push + in-app) cuando el stock cae por debajo de un umbral
  configurable; marcar como "sin stock" cuando llega a 0.
- **RF-24** Gestionar **depósitos**: crear, marcar principal (= depósito de
  despacho, del que ML descuenta), toggle vendible; ML publica la suma de los
  depósitos vendibles.
- **RF-25** **Transferencias entre depósitos** como control interno (par de
  movimientos balanceados; no altera el disponible → no empuja a ML).
- **RF-26** Historial por producto: línea de tiempo que une movimientos de
  stock (compras, ajustes, transferencias) y ventas de ML.

### Compras
- **RF-27** Registrar **compras a proveedor** (proveedores reutilizables):
  borrador → agregar items por búsqueda/escaneo de SKU (si no existe, alta y
  vuelta al flujo) → cerrar la compra impacta stock (un movimiento por línea,
  `reason=purchase`, referencia a la compra, depósito elegido).
- **RF-28** **OCR de factura**: foto → Edge Function `parse-invoice` (Claude
  Haiku, visión + salida estructurada) → borrador de líneas con match por
  SKU/GTIN → el usuario aprueba antes de crear los items. Nunca crea sin
  aprobación.

### Precios, comisiones y rentabilidad
- **RF-13** Mostrar precio de venta (ARS) de cada publicación.
- **RF-14** Estimar la comisión de ML por publicación (`/listing_prices`) y usar
  la comisión real (`sale_fee`) cuando hay una venta concreta.
- **RF-15** Calcular ganancia neta = precio − comisión − envío − costo_compra
  (todo en una moneda común vía TC).
- **RF-16** Mostrar **markup** (sobre costo) y **margen** (sobre venta).
- **RF-17** Mantener cacheado el tipo de cambio USD→ARS (actualización periódica).

### Ventas y comparativas
- **RF-18** Registrar ventas (órdenes) provenientes de ML con su detalle.
- **RF-29** Registrar **ventas fuera de ML** ("venta local"): el backend
  diferencia el canal de cada venta (`sales.channel = 'ml' | 'local'`); la
  venta local descuenta stock del depósito elegido y empuja el nuevo
  disponible a ML. Cliente **opcional**: se elige del padrón propio o queda
  "sin cliente".
- **RF-30** Padrón de **clientes** y **proveedores** asociados al usuario que
  los creó (RLS por `profile_id`): alta rápida solo con nombre; datos
  fiscales/contacto opcionales a futuro (razón social, CUIT/CUIL, teléfono,
  email). Compras admiten "proveedor no especificado".
- **RF-19** Comparativa entre productos propios (rentabilidad, margen, rotación).
- **RF-20** Comparativa de precios contra la competencia **dentro de ML** (catálogo
  / `item_competition`). *(must-have del MVP)*
- **RF-31** Venta local **multi-depósito** (depósito por línea) e **idempotente**
  (id generado por el cliente); despacho de órdenes ML repartido entre
  depósitos vendibles (principal primero). *(2026-07-03)*
- **RF-32** **Costeo por política** (FIFO / promedio ponderado / última compra /
  manual, elegible en Ajustes): la ganancia neta por venta y la rentabilidad
  por producto usan el costo de COMPRA real (`product_cost_ars`,
  `v_sale_profit`), no solo el costo manual del producto. *(2026-07-03)*
- **RF-33** **Errores visibles**: manejo centralizado en la app (mensaje claro +
  detalle técnico) y cola de push a ML visible con reintento desde el Inicio —
  nada falla en silencio. *(2026-07-03)*
- **RF-34** **Bloqueo biométrico** opcional (Face ID / huella) al volver a la
  app tras inactividad. *(2026-07-03)*
- **RF-35** **Operación sin conexión**: si una venta / transferencia / ajuste /
  cierre de compra se confirma sin red, queda en una **cola local persistente**
  (`pending_ops`, drift) con su id idempotente y se sube sola al reconectar
  (worker con connectivity_plus). Sección "Pendientes de subir" en Movimientos
  con reintento/descarte y detalle del rechazo diferido (ej. stock
  insuficiente al sincronizar). *(2026-07-03, etapa B1 de
  [analisis-cola-offline.md](analisis-cola-offline.md))*

### Notificaciones
- **RF-21** Recibir webhooks de ML (`orders_v2`, `items`, `items_prices`,
  `item_competition`) y procesarlos de forma asíncrona y confiable.
- **RF-22** Notificaciones push a Android e iOS (stock bajo, nueva venta).

## 3. Requisitos no funcionales (RNF)

- **RNF-01 Seguridad:** `client_secret` y tokens de ML solo en el backend. RLS en
  todas las tablas; las credenciales de ML solo accesibles por `service_role`.
- **RNF-02 Multiplataforma:** Android e iOS desde un único código Flutter.
- **RNF-03 Resiliencia de webhooks:** responder 200 en < 3 s; procesar vía cola
  (`ml_events`) con reintentos; idempotencia por `ml_order_id`/recurso.
- **RNF-04 Rate limiting:** respetar el límite de ML (1500 req/min); preferir
  webhooks sobre polling; cachear comisiones y TC.
- **RNF-05 Offline-friendly (deseable):** lectura de datos con Realtime y cache
  local; las escrituras críticas requieren conexión.
- **RNF-06 Testeo:** tests de base (pgTAP) para RLS/triggers/vistas y tests
  unitarios en Flutter para modelos y lógica.
- **RNF-07 Observabilidad:** registrar errores de sincronización y eventos
  fallidos para diagnóstico.
- **RNF-08 Portabilidad de entorno:** dev local (puertos 743x) reproducible vía
  `supabase start` + migraciones; cloud vía `supabase link`/`db push`.

## 4. Fuera de alcance (por ahora)

- Multi-país / multi-marketplace.
- Multi-usuario / SaaS con planes.
- Integración con otros canales (Shopify, Tienda Nube, etc.).
- Facturación electrónica / AFIP.
- Scraping de precios fuera de MercadoLibre.

## 5. Roadmap (resumen)

- **v0.1 (MVP):** Auth + OAuth ML, importar publicaciones + productos internos,
  costo USD + TC, comisión/ganancia/markup/margen, stock manual, comparativa de
  precios en ML. ✅
- **v0.2:** webhook de órdenes → descuento automático + push de stock a ML,
  alertas de stock bajo in-app. ✅ (push FCM pendiente de credenciales)
- **v0.3:** depósitos + transferencias, compras + OCR de factura, historial,
  comparativa entre productos, variaciones (espejo), dashboard. ✅
- **v0.4+:** push FCM (RF-22), publicar borrador en ML desde la app
  (`publish-item`, requiere scope de escritura), stock por variación
  gestionado desde la app, import selectivo de publicaciones.

## 6. Estado de implementación (auditoría 2026-07-02)

| Requisito | Estado |
|-----------|--------|
| RF-01…RF-06, RF-08…RF-18, RF-20, RF-21, RF-23…RF-35 | ✅ Implementado (tests en verde: pgTAP 148, Deno 12, core_models 24, Flutter 4) |
| RF-07 variaciones | 🟡 Parcial: espejo `listing_variations` + UI en detalle; push por variación no soportado (se omite con nota en la cola) |
| RF-19 comparativa entre productos | ✅ Pantalla "Comparativa" (margen/markup/ganancia/rotación 30d) desde Productos |
| RF-22 push FCM | ⏸ Bloqueado por credenciales Firebase/APNs del dueño ([firebase.md](firebase.md)) |
| RNF-01…04, RNF-06, RNF-08 | ✅ (RLS, colas idempotentes, rate-friendly, tests, entornos 743x + [setup.md](setup.md)) |
| RNF-05 offline | ✅ Cola local persistente `pending_ops` (RF-35): confirmar sin red encola y sube solo al reconectar ([analisis-cola-offline.md](analisis-cola-offline.md)); las LECTURAS siguen requiriendo conexión |
| RNF-07 observabilidad | 🟡 `stock_push_queue` ahora visible en la app (banner + reintento); `ml_events.error` sigue solo en base |

Fuera de requisitos pero decidido con el dueño: crear borrador en ML
(`publish-item`) espera confirmación de scopes OAuth de escritura; el import
selectivo de ML es opcional (el masivo desde Ajustes cubre el caso).
