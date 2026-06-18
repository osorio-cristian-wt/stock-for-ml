# Requisitos — stock-for-ml

> Estado: vivo. Última actualización: 2026-06-18.
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
  compra en USD, foto, notas).
- **RF-05** Importar las publicaciones existentes de ML como productos/listings.
- **RF-06** Vincular un producto interno con una publicación de ML.
- **RF-07** Soportar variaciones de una publicación (talle/color/etc.) con stock
  por variación.

### Stock
- **RF-08** Ver el stock actual por producto.
- **RF-09** Registrar movimientos de stock (compra, venta, ajuste, devolución).
- **RF-10** Al confirmarse una venta en ML, descontar stock automáticamente.
- **RF-11** Empujar el stock actualizado a ML (`PUT /items`) cuando Supabase es
  la fuente de verdad.
- **RF-12** Alertar (push + in-app) cuando el stock cae por debajo de un umbral
  configurable; marcar como "sin stock" cuando llega a 0.

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
- **RF-19** Comparativa entre productos propios (rentabilidad, margen, rotación).
- **RF-20** Comparativa de precios contra la competencia **dentro de ML** (catálogo
  / `item_competition`). *(must-have del MVP)*

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
  precios en ML.
- **v0.2:** webhook de órdenes → descuento automático + push de stock a ML,
  alertas de stock bajo + push.
- **v0.3+:** comparativa entre productos, variaciones, dashboard de métricas,
  edición de publicaciones desde la app.
