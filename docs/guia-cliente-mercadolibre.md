# Guía: qué necesitás de MercadoLibre Developers

> Para vos (dueño de la cuenta de MercadoLibre). Esta guía explica **paso a paso**
> qué tenés que crear en MercadoLibre y qué datos pasarnos para conectar la app de
> stock con tu cuenta. No hace falta que sepas programar: seguí los pasos y al
> final tenés un checklist de lo que nos entregás.

## ¿Para qué es esto?

La app de stock se conecta a tu cuenta de MercadoLibre (ML) para: leer tus
publicaciones, descontar stock cuando vendés, avisarte de stock bajo y mantener el
stock sincronizado. Para eso, ML exige que crees una **"aplicación"** en su portal
de desarrolladores y nos pases **dos claves**. Es un trámite de una sola vez.

> 🔒 **Importante:** vos creás la aplicación y nos pasás las claves. Nosotros las
> guardamos **cifradas en el servidor**, nunca dentro del celular. Vos seguís siendo
> el dueño de la cuenta y podés revocar el acceso cuando quieras.

---

## Antes de empezar

- Tener tu **cuenta de MercadoLibre** (la misma con la que vendés) y poder iniciar
  sesión.
- Tener a mano **dos datos que te pasamos nosotros** (dependen del servidor):
  - **URL de redireccionamiento** (Redirect URI):
    `https://<TU-PROYECTO>.supabase.co/functions/v1/oauth-callback`
  - **URL de notificaciones** (Webhook):
    `https://<TU-PROYECTO>.supabase.co/functions/v1/ml-webhook`

  *(Te las enviamos ya completas; acá van como ejemplo.)*

---

## Paso 1 — Entrar al portal de desarrolladores

1. Andá a **https://developers.mercadolibre.com.ar**
2. Iniciá sesión con **tu cuenta de MercadoLibre** (la de vendedor).
3. Entrá a **"Mis aplicaciones"** / **DevCenter**.

## Paso 2 — Crear una aplicación nueva

1. Clic en **"Crear aplicación nueva"**.
2. Completá los datos básicos:
   - **Nombre** (ej.: "Stock for ML").
   - **Descripción corta** (ej.: "Gestión de stock e inventario").
   - **Logo** (opcional).
3. Guardá. ML te crea la aplicación.

## Paso 3 — Configurar los permisos (scopes)

En la configuración de la aplicación, activá estos **3 permisos**:

- **`read`** — leer publicaciones y órdenes.
- **`write`** — actualizar stock y precios.
- **`offline_access`** — mantener la conexión sin tener que volver a loguearte
  cada 6 horas.

> Si no ves "offline_access", asegurate de marcarlo: sin él, la app pierde la
> conexión seguido y deja de sincronizar.

## Paso 4 — Configurar la URL de redireccionamiento (Redirect URI)

1. Buscá el campo **"URI de redireccionamiento"** / **"Redirect URI"** /
   **"Callback URL"**.
2. Pegá **exactamente** la URL que te pasamos:
   `https://<TU-PROYECTO>.supabase.co/functions/v1/oauth-callback`
3. Guardá.

> Tiene que coincidir **carácter por carácter** con la que te damos, o la conexión
> falla.

## Paso 5 — Configurar las notificaciones (Webhook)

Para que la app se entere de tus ventas en el momento:

1. Buscá la sección **"Notificaciones"** / **"Webhooks"** / **"Topics"**.
2. En **URL de devolución de llamadas** pegá la que te pasamos:
   `https://<TU-PROYECTO>.supabase.co/functions/v1/ml-webhook`
3. **Activá estos tópicos** (marcá las casillas):
   - **`orders_v2`** — ventas confirmadas y cancelaciones *(imprescindible)*.
   - **`shipments`** — envíos (despachado, rebotado, no entregado).
   - **`items`** — cambios en tus publicaciones.
   - **`items_prices`** — cambios de precio.
   - **`claims`** — reclamos y devoluciones.
4. Guardá.

## Paso 6 — Copiar tus dos claves y pasárnoslas

En la pantalla de tu aplicación vas a ver:

- **App ID** (también llamado **Client ID** o **número de aplicación**) — es un
  número largo.
- **Clave secreta** (**Secret Key** / **Client Secret**) — es un texto largo.

👉 **Pasanos esos dos valores.** Con eso conectamos la app.

> 🔒 **Seguridad:** mandá la **Clave secreta** por un canal seguro (no por un mail
> público ni un grupo de WhatsApp abierto). Si alguna vez se filtra, desde el portal
> podés **regenerarla** y nos pasás la nueva.

## Paso 7 — Autorizar la conexión (una vez, desde la app)

Cuando ya cargamos tus claves:

1. Abrís la app de stock.
2. Tocás **"Conectar MercadoLibre"**.
3. Te lleva a la pantalla de ML, iniciás sesión y tocás **"Permitir"**.
4. Listo: la app queda conectada y empieza a sincronizar.

> Esto autoriza a *tu* aplicación a *tu* cuenta. Lo hacés vos; nosotros no
> necesitamos tu usuario ni contraseña de MercadoLibre.

---

## (Opcional) Catálogo de productos

Si querés que la app pueda **crear fichas de catálogo** en ML para productos que
todavía no están catalogados (además de publicarlos): la creación de catálogo en
ML es **moderada** y depende de los permisos de tu cuenta y de la categoría.

- **Verificá** en tu cuenta si tenés habilitada la creación/edición de productos de
  catálogo (suele requerir cierta reputación o estar en categorías que lo permiten).
- Si no está habilitado, **no es bloqueante**: igual podemos cargar el stock y
  publicar de forma libre usando el código de barras. Avisanos qué ves en tu cuenta
  y lo ajustamos.

---

## Checklist de lo que nos entregás

- [ ] **App ID / Client ID** (el número de la aplicación).
- [ ] **Clave secreta / Client Secret** (por canal seguro).
- [ ] Confirmación de que pegaste **nuestra Redirect URI** en la app de ML.
- [ ] Confirmación de que pegaste **nuestra Webhook URL** y activaste los tópicos
      (`orders_v2`, `shipments`, `items`, `items_prices`, `claims`).
- [ ] Confirmación de que activaste los permisos **`read`, `write`, `offline_access`**.
- [ ] *(Opcional)* Qué ves sobre **permisos de catálogo** en tu cuenta.

Con eso, del lado nuestro completamos la configuración y te pasamos la app lista
para conectar.

---

## (Opcional) Clasificación automática por IA

La app puede sugerir **categoría y marca** de un producto automáticamente cuando el
código de barras no trae datos. Eso usa un servicio de IA (Claude/Anthropic) y es
**opcional y aparte de MercadoLibre**. Si lo querés activar, hace falta una clave de
ese servicio (la gestionamos nosotros o la ponés vos); decinos y lo coordinamos. Sin
esto, la carga por código de barras y la carga manual funcionan igual.

---

## Glosario rápido

| Término | Qué es |
|---|---|
| **Aplicación** | El "permiso" que creás en ML para que la app acceda a tu cuenta. |
| **App ID / Client ID** | El identificador (número) de esa aplicación. |
| **Clave secreta / Client Secret** | La contraseña de la aplicación. **No compartir en público.** |
| **Redirect URI** | La dirección a la que ML "vuelve" después de que autorizás. Te la damos nosotros. |
| **Webhook / Notificaciones** | La dirección donde ML nos avisa de tus ventas. Te la damos nosotros. |
| **Scopes / Permisos** | Qué puede hacer la app: leer (`read`), escribir (`write`), seguir conectada (`offline_access`). |
| **Tópicos** | Los tipos de aviso que activás (ventas, envíos, precios, reclamos). |
| **GTIN / EAN** | El código de barras numérico estándar de un producto (ej.: `6937541239382`). |
