# Certificación C_CPE — SAP Certified: Backend Developer - SAP Cloud Application Programming Model

Guía paso a paso para resolver el examen basado en sistema (*C_CPE, Course Version 2601*) en
**SAP Business Application Studio (BAS)**, usando el framework **CAP Node.js**. Plantillas de
código de referencia en [`src/`](src/).

> ⚠️ **A diferencia de C_ABAPD y C_CPI**, el PDF de instrucciones de este examen **no incluye**
> la cláusula que autoriza explícitamente el uso de recursos externos / SAP Joule durante la
> evaluación. Antes de pedir ayuda en tiempo real el día del examen real, hay que comprobar si
> esa autorización aparece en otra sección (overview page, FAQs) — si no aparece, el enfoque
> debe ser distinto al de los otros dos exámenes (repaso previo sí, respuestas en directo no,
> salvo confirmación explícita).

## Escenario

Sistema de gestión logística: cálculo dinámico de tarifas de envío según peso total de paquetes
y modo de transporte. La base de datos solo guarda datos "en crudo"; `totalWeight` y
`shippingFee` se calculan al vuelo al leer vía OData (campos virtuales + handler).

## 0. Prerrequisitos / preparación del entorno

1. Accede a **SAP Business Application Studio**.
2. Crea y abre un **dev space** de tipo **"Full Stack Cloud Application"**. Espera a que arranque
   (puede tardar un par de minutos la primera vez).
3. Abre una terminal (`Terminal > New Terminal`) y clona la plantilla de examen:
   ```bash
   git clone https://github.com/sap-samples/btp-developer-training-exam
   cd btp-developer-training-exam
   ```
4. Instala dependencias con instalación limpia:
   ```bash
   npm ci
   ```
   (`npm ci` es el equivalente exacto de "clean-install" que pide el enunciado — usa el
   `package-lock.json` tal cual, sin resolver versiones nuevas.)

## 1. Tarea 1 — Modelado de datos (`db/schema.cds`)

1. Crea (o edita) el archivo `db/schema.cds`.
2. Copia el contenido de [`src/db/schema.cds`](src/db/schema.cds) — respeta el **orden exacto**
   de campos que pide el enunciado (`ID, customer, mode, totalWeight, shippingFee, packages` en
   `Shipments`; `ID, contents, weight, parent` en `Packages`), ya que lo pide explícitamente.
3. Puntos clave del modelo:
   - `namespace exam.logistics;`
   - `type TransportMode : String enum { Air = 'A'; Sea = 'S'; Rail = 'R'; }`
   - `totalWeight` y `shippingFee` van marcados como **`virtual`** (no se persisten en BD, se
     calculan en el handler de la Tarea 2).
   - La composición `packages : Composition of many Packages on packages.parent = $self;` crea
     automáticamente la clave foránea `parent_ID` en la tabla `Packages`.

### Datos mock

4. Crea la carpeta `db/data/` si no existe.
5. Crea los dos ficheros CSV siguiendo la convención CAP `<namespace>-<Entity>.csv`:
   - [`src/db/data/exam.logistics-Shipments.csv`](src/db/data/exam.logistics-Shipments.csv)
   - [`src/db/data/exam.logistics-Packages.csv`](src/db/data/exam.logistics-Packages.csv)
     (ojo a la columna `parent_ID`, que es la FK generada por la composición — sin ella los
     paquetes no quedarán vinculados a su envío).

### Verificación rápida

```bash
cds watch
```
Abre el enlace a `/$metadata` o a la consola SQLite (`cds repl` → `cds.env` o
`http://localhost:4004/logistics/Shipments`) y comprueba que carga los dos envíos con sus
paquetes asociados.

## 2. Tarea 2 — Exposición del servicio (`srv/`)

1. Crea `srv/logistics-service.cds` con el contenido de
   [`src/srv/logistics-service.cds`](src/srv/logistics-service.cds):
   - Servicio `LogisticsService` con `@(path: '/logistics')`.
   - `Shipments` expuesta completa; `Packages` con `@readonly`.
2. Crea el handler `srv/logistics-service.js` (mismo nombre base que el `.cds`, es la convención
   CAP para que se cargue automáticamente) con el contenido de
   [`src/srv/logistics-service.js`](src/srv/logistics-service.js):
   - Handler `after('READ', Shipments, ...)` que calcula `totalWeight` (suma de pesos) y
     `shippingFee` (`totalWeight * tarifa según mode`, tarifas: A=15, S=5, R=8).
   - Contempla el hint del enunciado: si `packages` no viene expandido en la respuesta, hace un
     `SELECT` explícito a `Packages` filtrando por `parent_ID`.

### Prueba

```bash
cds watch
```
- `GET /logistics/Shipments` → deben aparecer `totalWeight`/`shippingFee` calculados aunque no
  pidas `$expand=packages`.
- `GET /logistics/Shipments?$expand=packages` → mismo resultado, usando los packages ya
  expandidos en vez de la query adicional.
- `POST /logistics/Packages` (o cualquier método de escritura) → debe devolver error 405/403,
  confirmando que `Packages` es de solo lectura.

## 3. Tarea 3 — Preparación para producción y despliegue

### 3.1 Configuración HANA

```bash
cds add hana
```
Esto añade las dependencias (`@sap/hana-client`/`hdb`, `@cap-js/hana`) y la configuración de
`requires.db.kind: hana` para producción en `package.json`, manteniendo SQLite para desarrollo
local (perfil `[development]`).

### 3.2 Empaquetado MTA

```bash
cds add mta
```
Genera `mta.yaml` con un módulo `<app>-srv` (Node.js) y un módulo `<app>-db-deployer` (HDI
container). **Verifica que no se haya añadido XSUAA** (el enunciado pide explícitamente sin
XSUAA — dado que `auth: none`, no debería generarse ese resource; si aparece, elimínalo).

### 3.3 Sobrescribir la ruta de la aplicación

Abre `mta.yaml`, localiza el módulo `<service>-srv` (el nombre exacto depende de cómo se llame
tu `package.json` → `name`), y **sustituye por completo** su bloque `parameters:` por el que
pide el enunciado — plantilla exacta en
[`src/mta_parameters_snippet.yaml`](src/mta_parameters_snippet.yaml):

```yaml
    parameters:
      instances: 1
      buildpack: nodejs_buildpack
      app-name: ${space}-c_cpe_submission-srv
      routes:
        - route: ${org}-cpe-submission.${default-domain}
```

### 3.4 Build y Deploy

```bash
# Build del artefacto MTA
mbt build

# Login en Cloud Foundry (subaccount/space proporcionados en el examen)
cf login -a <api-endpoint> -o <org> -s SUBMISSION

# Deploy del .mtar generado
cf deploy mta_archives/<nombre-generado>.mtar
```

### 3.5 Verificación final

```bash
cf apps
cf app <space>-c_cpe_submission-srv
```
Confirma que el módulo `-srv` aparece en estado **`started`** y que la ruta configurada
(`${org}-cpe-submission.${default-domain}`) responde. Con eso, ya puedes confirmar el examen.
