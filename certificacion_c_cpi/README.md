# Certificación C_CPI — SAP Certified: Integration Developer

Guía paso a paso resuelta en **SAP Integration Suite** para el examen basado en sistema
(*C_CPI, Course Version 2601*). Igual que en `certificacion_c_abapd/`, el propio PDF de
instrucciones confirma explícitamente que es un examen open-book con uso permitido de
recursos externos, incluyendo **SAP Joule for Consultants**.

> Registro completo del intento resuelto: [`docs/intento_2026-08-23.md`](docs/intento_2026-08-23.md)
> — **resultado: 100%** ✅

## Resumen de las tareas

### Tarea 1 — Business Data Integration via SAP Integration Suite

Exponer el servicio OData `GWSAMPLE_BASIC` de un backend on-premise (conectado vía Cloud
Connector) en el Developer Hub:

1. **API Provider** (`Configure > APIs > API Providers`): tipo `On Premise`, con Host, Puerto,
   Location ID (derivado del número en la URL del sistema del examen, no del número de grupo),
   Basic Auth, Path Prefix y Service Collection URL para el catálogo OData.
2. **API Proxy** (`Configure > APIs > API Proxies > Create > API Provider > Discover`):
   localizar `GWSAMPLE_BASIC` en el catálogo del provider, importarlo, y **renombrar** Name/Title
   al valor pedido (el wizard los autorrellena con el nombre del servicio, hay que cambiarlos).
   **Desplegar** el proxy (paso obligatorio antes de poder publicar el producto).
3. **Product** (`Engage > Products > Create`): añadir el API Proxy ya desplegado, y **Publish**
   (el botón solo se habilita si el proxy está `Deployed`).

### Tarea 2 — Internal Data Processing Pipeline

iFlow independiente (sin esperar llamada externa) con mapeo y persistencia:

1. **Integration Package** + **Integration Flow** (`Design > Integrations and APIs`).
2. **Start Event → Timer** (clic en el icono del Start para desplegar la mini-paleta de tipos de
   evento). Configuración por defecto (`Schedule: On Deployment`, `Repeat: None`) ya cumple el
   requisito de ejecución independiente.
3. **Content Modifier**: `Message Body > Type: Constant`, con el XML del payload pegado. Es
   necesario además añadir un **Message Header** `Content-Type = application/xml` (Source Type:
   Constant) para que el Message Mapping reconozca el body como XML — si no, aparece un warning
   de diseño (no bloqueante, pero conviene resolverlo).
4. **Message Mapping**: se crea como recurso haciendo **doble clic directamente sobre el step**
   en el lienzo (no hay opción de "crear nuevo" en el diálogo "Select Resource" — ese diálogo
   solo lista recursos ya existentes). Subir los dos `.wsdl` como source/target vía "Add source
   message" / "Add target message". Mapeo directo `Product → Product`, y para aplanar la
   jerarquía (ignorar `MainCategory`/`Category`) se usa la función **`collapseContexts`**
   (categoría "Node Functions" en el panel de Functions) insertada entre ambos nodos — no existe
   un menú contextual de "Change Context" en esta versión del editor web.
5. **Write to Data Store** (`Data Store Name: CCPI_Datastore`), como último step antes del End.
6. Guardar, desplegar, y comprobar en **Monitor > Message Processing** que el mensaje termina en
   `Completed`.

## Notas para un futuro intento

- El **número de grupo** de la inscripción y el **número que aparece en la URL del sistema**
  (usado para el `Location ID`, formato `examXXX`) son datos **distintos** — no los confundas.
- La opción **"Manage APIs"** en un tenant trial nuevo puede tardar en aprovisionar aunque la
  "Capability" ya figure como añadida — si el tile no responde al clic, comprueba el estado real
  de la suscripción en *Instances and Subscriptions* del BTP Cockpit antes de asumir que algo
  está mal configurado.
- Verificar el contenido de una entrada de Data Store desde el Monitor puede dar un error de
  autorización (`"You are not authorized to perform this operation"`) en el tenant del examen —
  no es un fallo de la tarea, solo una restricción de permisos de lectura; basta con confirmar
  que la entrada existe y que el mensaje terminó en `Completed`.
