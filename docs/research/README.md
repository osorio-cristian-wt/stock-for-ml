# Investigación — stock-for-ml

Documentación de la etapa de investigación para una app mobile (Flutter +
Supabase) de gestión de stock integrada con la API de MercadoLibre.

## Índice
1. [API de MercadoLibre](01-mercadolibre-api.md) — auth, endpoints, stock,
   comisiones, webhooks, límites.
2. [Referencias open source](02-referencias-open-source.md) — apps de inventario,
   wrappers de ML, patrones Supabase y monorepo.
3. [Propuesta](03-propuesta.md) — arquitectura, stack, modelo de datos, flujos,
   features priorizadas.
4. [Decisiones pendientes](04-decisiones-pendientes.md) — qué necesito que
   definas antes de implementar.

## TL;DR
- Stack confirmado: **Flutter + Supabase**, monorepo público en GitHub.
- **Regla de oro:** la app nunca habla con ML directo; todo lo autenticado pasa
  por Supabase Edge Functions (secretos + webhooks + sync + cron).
- ML cubre todo lo necesario (items, stock, precios, órdenes, comisiones,
  webhooks) pero **sus SDKs están deprecados** → cliente propio en TS.
- Próximo paso: definir las [decisiones pendientes](04-decisiones-pendientes.md).
