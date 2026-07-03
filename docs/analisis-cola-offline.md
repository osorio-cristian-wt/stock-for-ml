# Análisis: cola de subida idempotente para operar sin conexión

**Fecha:** 2026-07-03 · **Estado:** análisis (pedido del dueño; sin implementación aún)

## El problema

La app opera en un local con conectividad irregular. Hoy, si no hay internet en
el momento de confirmar, una venta/compra/movimiento **falla** y el usuario
debe reintentar a mano. Además, hasta este lote, los fallos del push de stock a
ML eran invisibles ("fallan silenciosamente si un producto no se subió por
conexión").

## Qué ya tenemos (después del lote 2026-07-03)

| Pieza | Estado |
|---|---|
| Push de stock a ML | Ya es una cola server-side (`stock_push_queue`) con reintentos (5) y cron cada minuto. Ahora **visible en la app** (banner en Inicio) con reintento manual (`retry_stock_push`). |
| Venta local | `create_local_sale` es **transaccional e idempotente** (`p_sale_id` generado en el cliente y reutilizado en reintentos). Un corte de red después del commit ya no duplica. |
| Errores | Manejo centralizado (`AppErrors` / `showAppError`): el usuario ve QUÉ falló y por qué, con detalle técnico expandible. |

Lo que **no** hay: si no hay conexión, la operación no se encola en el
dispositivo; simplemente falla y el carrito queda en pantalla.

## Opciones

### A. Reintento en pantalla (statu quo mejorado) — esfuerzo bajo
El carrito no se pierde (ya es así: la venta queda armada en pantalla y el
mismo `p_sale_id` hace el reintento seguro). Se puede sumar un auto-reintento
con `connectivity_plus` cuando vuelve la red, mientras la pantalla siga abierta.

- ✅ Sin estado persistente nuevo; la idempotencia ya está resuelta.
- ❌ Si el usuario cierra la app antes de que vuelva la red, pierde el carrito.

### B. Cola de operaciones persistente en el dispositivo — esfuerzo medio (recomendada)
Tabla local (`sqflite` o un archivo JSON con `shared_preferences` no alcanza
para colas; mejor `sqflite`/`drift` minimal) con operaciones pendientes:

```
pending_ops(id uuid, kind 'sale'|'purchase_close'|'transfer'|'adjust',
            payload jsonb, created_at, attempts, last_error)
```

- Al confirmar sin red: la operación se guarda con su **uuid definitivo**
  (el mismo `p_sale_id` idempotente) y la UI muestra "pendiente de subir".
- Un worker (al abrir la app + al recuperar conectividad) drena la cola en
  orden. Como cada RPC es idempotente por id, un reintento duplicado es no-op.
- Requisito backend: dar idempotencia equivalente a compras
  (`close_purchase` ya es naturalmente idempotente: una compra cerrada no se
  cierra dos veces) y a transferencias (aceptar un `p_reference` cliente).
- UI: sección "Pendientes de subir" en Movimientos (misma estética que los
  borradores) + badge.
- ❌ La validación de stock se hace recién al sincronizar → una venta
  encolada puede rechazarse horas después; hay que mostrar ese rechazo con el
  detalle (el manejo de errores centralizado ya lo permite).

### C. Offline-first completo (replicación local + merge) — esfuerzo alto
Base local espejo (PowerSync / Brick / ElectricSQL) con sync bidireccional.

- ✅ Todo funciona offline, lecturas incluidas.
- ❌ Complejidad alta (resolución de conflictos de stock es EL problema),
  dependencia estructural nueva, y el caso de uso real (un solo local, cortes
  breves) no lo justifica hoy.

## Recomendación

**B**, en dos etapas:
1. **B0 (ya cumplida en este lote):** idempotencia por id de cliente en ventas
   + visibilidad/reintento del push a ML + errores con detalle.
2. **B1 (próximo lote):** `pending_ops` local con `drift`, worker con
   `connectivity_plus`, `p_reference` idempotente en `transfer_stock`, y la
   sección "Pendientes de subir" en Movimientos.

C queda descartada salvo que aparezcan múltiples puntos de venta simultáneos.
