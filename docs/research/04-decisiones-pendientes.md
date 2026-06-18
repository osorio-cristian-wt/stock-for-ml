# Decisiones de diseño

> Necesito que definas estos puntos antes de pasar a implementación. Los marcados
> con ⭐ son los que más condicionan la arquitectura.

## ✅ Decisiones tomadas (2026-06-18)
- **A. Fuente de verdad del stock → Supabase manda.** La app es el sistema
  central; los cambios se empujan a ML con `PUT /items`. ML se trata como un
  canal de venta más, no como la verdad del inventario.
- **B. Alcance del catálogo → ML + stock interno.** Se manejan productos
  publicados en ML y también productos internos sin publicar (que luego se podrán
  publicar). El modelo separa `products` (interno) de `ml_listings` (publicación).
- **C. Sitio/país → MLA (Argentina).** Un solo sitio por ahora; no diseñar para
  multi-país (sí dejar `site_id` en el modelo por las dudas, sin sobre-ingeniería).
- **D. Usuarios → single-user, single-account.** Solo el dueño, una cuenta de ML.
  RLS simple; igual se modela `profile_id` para no cerrarse la puerta a futuro.

### Pendientes (E–L)

## ⭐ A. Fuente de verdad del stock
¿Quién "manda" sobre el stock?
- **Supabase manda** (la app es el sistema central, ML se sincroniza desde acá).
- **ML manda** (ML es la verdad, la app refleja/registra costos).
- **Bidireccional** (más complejo: hay que resolver conflictos).

## ⭐ B. Alcance del catálogo
¿La app maneja solo productos que están publicados en ML, o también productos
"internos" sin publicación (stock que todavía no subiste)?

## ⭐ C. Sitio/país de MercadoLibre
Asumimos **MLA (Argentina)**. ¿Es correcto? ¿Multi-país a futuro?

## D. Multi-usuario / multi-cuenta
- ¿Un solo usuario (vos) o varios usuarios con login propio?
- ¿Una cuenta de ML o varias por usuario?

## ✅ E. Moneda y costos → compra en **USD** (generalmente)
- Costo de compra se registra en **USD**. Precio de venta en ML es **ARS**.
- Implicancia: el modelo guarda `purchase_cost` con su `currency` (USD) y hace
  falta un **tipo de cambio** para calcular ganancia/margen en una moneda común.
- **TC: automático vía API del dólar.** Una Edge Function con `pg_cron` cachea la
  cotización en Supabase (ej. tabla `fx_rates`) y la app la consume. Candidatas:
  [dolarapi.com](https://dolarapi.com) o [bluelytics](https://bluelytics.com.ar).
  **Pendiente menor:** definir qué dólar usar (oficial / blue / MEP) — para un
  importador suele ser blue o MEP. Confirmar si el costo incluye impuestos/envío.

## ✅ F. Definición de "% de ganancia" → **ambos** (markup y margen)
- `markup` = ganancia_neta / purchase_cost (sobre el costo).
- `margen` = ganancia_neta / precio_venta (sobre la venta).
- `ganancia_neta` = precio_venta − comisión_ML − costo_envío − purchase_cost
  (todo llevado a una misma moneda vía TC, ver E).

## ✅ G. Comparativa de precios → **solo ML, must-have del MVP**
- Comparar contra competencia dentro de ML (no scraping externo). Vía catálogo
  ML (`/products`, búsqueda por categoría) y topic `item_competition`.
- Al ser must-have, entra en el alcance del MVP (replanificar v0.1).

## ✅ H. Monorepo → **Pub Workspaces** (nativo Dart, simple).

## ✅ I. Gestión de estado en Flutter → **Riverpod**
Async nativo (`AsyncValue`), type-safe, testeable. Ideal para una app async-heavy
contra Supabase/ML.

## ✅ J. Licencia → **MIT**
Permisiva y estándar de facto. Agregar `LICENSE` (MIT) en la raíz del repo.

## ✅ K. Notificaciones push → **Android + iOS** (FCM + APNs vía Supabase).

## ✅ L. Branding → mismo que el repo: **stock-for-ml**.
