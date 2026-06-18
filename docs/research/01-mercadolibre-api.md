# Investigación: API de MercadoLibre (MELI)

> Estado: investigación. Fecha: 2026-06-18.
> Sitio objetivo asumido: **MLA (Argentina)**. Confirmar con el usuario.

## 1. Resumen ejecutivo

La API de MercadoLibre es REST (`https://api.mercadolibre.com`), con OAuth 2.0
(Authorization Code Grant, server-side) y notificaciones vía webhooks. Cubre
todo lo que el proyecto necesita: gestión de publicaciones, stock, precios,
comisiones, órdenes de venta y notificaciones en tiempo real.

**Punto crítico de diseño:** el `client_secret` y los tokens de ML **no pueden
vivir en la app Flutter** (cualquiera puede decompilar el APK). El intercambio
OAuth y todas las llamadas con `access_token` deben hacerse desde un backend de
confianza → **Supabase Edge Functions**. La app habla con Supabase, nunca con
ML directamente para operaciones autenticadas.

## 2. Autenticación y autorización (OAuth 2.0)

- Protocolo: **Authorization Code Grant Type (server-side)**. Soporta **PKCE**.
- Crear la aplicación en https://developers.mercadolibre.com.ar con scopes:
  `read`, `write`, `offline_access`.
- Flujo:
  1. Redirigir al usuario a la URL de autorización de ML con `client_id` +
     `redirect_uri` (+ `code_challenge` si PKCE).
  2. ML redirige a `redirect_uri` con un `code`.
  3. Intercambiar `code` por tokens: `POST https://api.mercadolibre.com/oauth/token`.
- **Tokens:**
  - `access_token`: válido **6 horas**.
  - `refresh_token`: **un solo uso**; cada refresh devuelve uno nuevo. Hay que
    persistirlo y rotarlo. Requiere scope `offline_access`.
  - Refresh: `POST /oauth/token` con `grant_type=refresh_token`, `client_id`,
    `client_secret`, `refresh_token`.
- Todas las llamadas usan header `Authorization: Bearer <access_token>`.

**Implicancia de arquitectura:** los tokens se guardan cifrados en Supabase
(tabla `ml_credentials`, RLS estricta, idealmente con Vault). Una Edge Function
programada refresca tokens antes de que expiren (cada ~5 h).

## 3. Endpoints clave

Base: `https://api.mercadolibre.com`

| Área | Endpoint | Uso |
|------|----------|-----|
| Usuario | `GET /users/me` | Datos del seller, `seller_id` |
| Publicaciones | `GET /users/{id}/items/search` | Listar IDs de items del seller |
| Publicaciones | `GET /items/{item_id}` | Detalle de una publicación |
| Stock | `PUT /items/{item_id}` body `{"available_quantity": N}` | Actualizar stock |
| Precio | `PUT /items/{item_id}` body `{"price": N}` | Actualizar precio |
| Variaciones | `PUT /items/{item_id}` con `variations[]` | Stock/precio por variación |
| Comisiones | `GET /sites/MLA/listing_prices?price=5000&category_id=MLAxxxx` | Fees por categoría/tipo |
| Órdenes | `GET /orders/search?seller={id}` | Ventas confirmadas |
| Órdenes | `GET /orders/{order_id}` | Detalle de una venta |
| Categorías | `GET /sites/MLA/categories` y `/categories/{id}` | Árbol de categorías |
| Límites | `GET /marketplace/users/cap` | Cupo de publicaciones |

### Reglas de stock importantes
- `PUT available_quantity = 0` → la publicación pasa a `paused` con substatus
  `out_of_stock`.
- `PUT available_quantity > 0` sobre una publicación pausada por out_of_stock →
  vuelve a `active`.
- Items con variaciones: hay que enviar **todas** las `variation_id` con su
  cantidad; el stock es por variación.

### Comisiones / costos por vender
- `listing_prices` es **read-only** y devuelve el costo de publicar según
  `site`, `category_id`, `currency`, `listing_type` y `quantity`.
- Campos de respuesta relevantes: `sale_fee_amount` y `sale_fee_details`
  (`fixed_fee`, `gross_amount`, `percentage_fee`, `meli_percentage_fee`,
  `financing_add_on_fee`).
- La **comisión real** de una venta (`sale_fee`) se calcula al **acreditarse el
  pago**, no al crear la orden. El valor definitivo viene en el detalle de la
  orden / del pago. Para estimaciones previas usamos `listing_prices`.

## 4. Webhooks / Notificaciones

ML hace `POST` a una URL pública nuestra (una Edge Function) cuando hay cambios.
Topics relevantes para el proyecto:

- **`items`** → cambios en publicaciones (alta, edición, pausa).
- **`orders_v2`** → creación y cambios de ventas confirmadas. **Clave para
  descontar stock automáticamente.**
- **`items_prices`** → cambios de precio.
- **`stock_locations`** / **`stock-fulfillment`** → stock en depósitos / full.
- **`payments`** → estado de pagos (para confirmar comisión real).
- Otros: `questions`, `messages`, `shipments`, `claims`, `item_competition`
  (competencia de precios → útil para comparativas).

Notas:
- La disponibilidad de topics **varía por país/marketplace**.
- Las notificaciones traen IDs, no el recurso completo → hay que hacer un GET de
  follow-up al recurso.
- ML espera **HTTP 200 en pocos segundos**; si no, reintenta. Patrón recomendado:
  la Edge Function valida y **encola** (Supabase Queues / tabla `ml_events`) y
  procesa async. ML tiene simulador de notificaciones para testear.
- Validar autenticidad de la notificación (firma/secret).

## 5. Límites y restricciones

- **Rate limit: 1500 req/min por seller**. Exceso → HTTP 429 con body vacío.
- Cantidad de publicaciones activas: 1.000 a 50.000 según reputación del seller.
- ML **dejó de mantener sus SDKs oficiales en abril 2021** (ver doc 02). Hay que
  hablar con la REST API directamente o usar wrappers comunitarios como
  referencia.

## 6. Mapa a nuestras features

| Feature del proyecto | Cómo se resuelve con ML |
|----------------------|--------------------------|
| Actualizar publicaciones al llegar productos | `PUT /items/{id}` (stock/precio) |
| Descontar stock al comprar | webhook `orders_v2` → descuenta en Supabase y `PUT` a ML |
| Notificación por stock bajo | trigger en Supabase sobre tabla de stock |
| Comisiones de ML | `listing_prices` (estimado) + `orders/{id}` (real) |
| % de ganancia | (precio_venta − comisión − costo_compra) / costo_compra, en Supabase |
| Comparativa de precios | `item_competition` + scraping/búsqueda de catálogo |

## Fuentes
- [API Docs – MercadoLibre](https://global-selling.mercadolibre.com/devsite/api-docs)
- [Authentication and Authorization](https://developers.mercadolivre.com.br/en_us/authentication-and-authorization)
- [Actualizando Inventario en MercadoLibre — API (Medium)](https://medium.com/@lopezlucas/actualizando-inventario-en-mercadolibre-api-be08c72cc9df)
- [Fees for listing](https://developers.mercadolibre.com.ar/en_us/fees-for-listing)
- [Listing prices endpoint](https://api.mercadolibre.com/sites/MLA/listing_prices?price=5000&category_id=MLA1744)
- [Mercado Libre API Essential Guide – Rollout](https://rollout.com/integration-guides/mercado-libre/api-essentials)
- [Gestiona ventas / órdenes](https://developers.mercadolibre.com.ar/es_ar/gestiona-ventas)
