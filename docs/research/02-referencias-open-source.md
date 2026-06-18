# Investigación: referencias open source

> Estado: investigación. Fecha: 2026-06-18.

## 1. Apps de inventario / stock con Flutter

| Repo | Stack | Qué tomar de referencia | Limitación |
|------|-------|--------------------------|------------|
| [URSFR/Supabase-Open-Source-Ecommerce-Multivendor](https://github.com/URSFR/Supabase-Open-Source-Ecommerce-Multivendor) | **Flutter + Supabase** | El match más directo: auth, storage, RLS, realtime con Supabase desde Flutter. Patrón de e-commerce multivendor. | Es e-commerce, no inventario puro; revisar calidad/mantenimiento. |
| [hemanta212/Flutter-Inventory-App](https://github.com/hemanta212/Flutter-Inventory-App) | Flutter + Firebase (realtime) | UX optimizada para **carga rápida de ventas y stock** desde el celular. Justo el caso de uso "práctico y cómodo". | Backend Firebase, no Supabase. |
| [Wubishet-Asbegiorggis/Flutter-Firebase-Inventory-Management-App](https://github.com/Wubishet-Asbegiorggis/Flutter-Firebase-Inventory-Management-App) | Flutter + Firebase | Gestión de productos, updates en tiempo real, stats, auth. | Firebase. |
| [Shubhamsahu1101/InventoryManagementApp](https://github.com/Shubhamsahu1101/InventoryManagementApp) | Flutter | Update de niveles de stock en tiempo real, registro de usuarios. | Simple, didáctico. |

### Referencias de inventario con Supabase (no-Flutter, sirven para el modelo de datos / SQL)
| Repo | Stack | Qué tomar |
|------|-------|-----------|
| [BoviliusMeidi/inventory-management](https://github.com/BoviliusMeidi/inventory-management) | Next.js + TS + Supabase | Modelo de datos: stock, **proveedores, purchase orders, sales performance**. Buen schema SQL de referencia. |
| [robavelii/Stockflow-Inventory](https://github.com/robavelii/Stockflow-Inventory) | React + TS + Supabase | Arquitectura modular, testing, "production-ready". |
| [anandureghu/canman](https://github.com/anandureghu/canman) | React Native + Supabase | Tracking de inventario centralizado + entregas. Lógica de tipos de cliente. |

## 2. Wrappers / SDKs de MercadoLibre

> ⚠️ ML **dejó de mantener sus SDKs oficiales (~abril 2021)**. El SDK oficial de
> Python tiene dependencias desactualizadas. **No** adoptar un SDK oficial como
> dependencia; usarlos como **referencia de endpoints y flujo OAuth** y hablar
> con la REST API directo (o portar la lógica a TypeScript/Deno para Edge Functions).

| Repo | Lenguaje | Uso como referencia |
|------|----------|---------------------|
| [mercadolibre/python-sdk](https://github.com/mercadolibre/python-sdk) | Python (oficial, sin mantención) | Flujo OAuth canónico, refresh token. |
| [GearPlug/mercadolibre-python](https://github.com/GearPlug/mercadolibre-python) | Python | Wrapper comunitario, métodos por recurso (items, orders). |
| [martinzugnoni/mercadolibre.py](https://github.com/martinzugnoni/mercadolibre.py) | Python | Cliente limpio para la API. |
| [JoaquinOrbe/meli-python-sdk](https://github.com/JoaquinOrbe/meli-python-sdk) | Python | Alternativa comunitaria actualizada. |

> No se encontró un SDK Node/Deno mantenido de referencia fuerte. Conviene
> implementar un **cliente propio liviano en TypeScript** dentro del monorepo
> (`packages/meli-client` o dentro de las Edge Functions), guiándonos por los
> wrappers Python. Para OAuth en Node existe `passport-mercadolibre-2` y el
> provider de [Arctic](https://arcticjs.dev/providers/mercadolibre) como referencia.

## 3. Infra Supabase: patrones de sincronización con APIs externas

- **pg_cron + pg_net + Edge Functions**: cron en Postgres que invoca Edge
  Functions periódicamente para sincronizar (refresh de tokens, pull de órdenes,
  reconciliación de stock). Configurable desde Dashboard → Integrations → Cron.
- **Edge Functions + Cron + Queues** para jobs grandes: el cron descubre trabajo
  y lo encola; workers especializados procesan. Encaja perfecto con el patrón
  "webhook recibe → encola → procesa async" del doc 01.

## 4. Monorepo Flutter + Supabase

- Separar `apps/` (aplicaciones) de `packages/` (código compartido). Regla: las
  apps dependen de packages, los packages **nunca** dependen de apps.
- **Dart 3.6+ / Flutter 3.27+** tienen soporte nativo de monorepo vía **Pub
  Workspaces**. Alternativa madura: **Melos** (Invertase) para orquestar.
- Para Supabase: la CLI usa `supabase/` (migrations, functions, config) en la
  raíz del repo. Conviven bien Flutter + Supabase CLI en el mismo repo.

## Fuentes
- [Topic Flutter+Supabase (Dart)](https://github.com/topics/supabase?l=dart)
- [Scheduling Edge Functions | Supabase Docs](https://supabase.com/docs/guides/functions/schedule-functions)
- [Processing large jobs with Edge Functions, Cron, and Queues](https://supabase.com/blog/processing-large-jobs-with-edge-functions)
- [Dart & Flutter Monorepos: Pub Workspaces and Melos](https://lazebny.io/dart-flutter-workspaces/)
- [How to manage your Flutter monorepos | Codemagic](https://blog.codemagic.io/flutter-monorepos/)
