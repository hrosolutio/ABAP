# ZEIDESWTDOCSTEP_SRV — API OData de EIDESWTDOCSTEP para NAPAI

Servicio SAP Gateway (SEGW clásico), creado a partir de cero para publicar
la tabla transparente **`EIDESWTDOCSTEP`** ("Documento de cambio paso")
como API OData, para que el sistema externo **NAPAI** pueda consumirla.

> ⚠️ **No parte de un Diseño Funcional formal** — no existía uno al momento
> de crearlo. Se construyó por petición verbal, siguiendo como referencia
> un proyecto SEGW existente en el sistema (`ZVBRP`, de extracción de la
> tabla VBRP). Ver "Pendiente / a definir con el cliente" más abajo.
>
> **Sustituye** una propuesta técnica anterior (CDS View + `@OData.publish`)
> que se descartó sin llegar a implementarse en el sistema real — se optó
> por SEGW clásico siguiendo el patrón que ya usa el equipo para este tipo
> de extracciones.

## Contenido del repositorio

```
src/
  ZCL_ZEIDESWTDOCSTEP_DPC_EXT__GET_ENTITYSET.abap
      Único método con lógica custom: lee la tabla EIDESWTDOCSTEP y la
      devuelve como Entity Set. El resto de clases (MPC, MPC_EXT, DPC)
      son generadas automáticamente por SEGW al crear el proyecto —
      no tienen código propio, por eso no se versionan aquí.
docs/
  DF_resumen.md   Resumen del alcance y supuestos (no hay DF de origen)
```

## Objetos SAP creados

| Objeto | Nombre técnico |
|---|---|
| Proyecto SEGW | `ZEIDESWTDOCSTEP` |
| Entity Type | `EideswtdocstepFacts` |
| Entity Set | `EideswtdocstepFactsSet` |
| Modelo técnico | `ZEIDESWTDOCSTEP_MDL`, versión 1 |
| Servicio técnico | `ZEIDESWTDOCSTEP_SRV`, versión 1 |
| Model Provider Class | `ZCL_ZEIDESWTDOCSTEP_MPC` / `_MPC_EXT` (generadas) |
| Data Provider Class | `ZCL_ZEIDESWTDOCSTEP_DPC` / `_DPC_EXT` (`_DPC_EXT` tiene el código custom) |
| Paquete | `ZLE` |

## Estructura de la tabla EIDESWTDOCSTEP (SE11) y del Entity Type

| Campo tabla | Elem. datos | Tipo | Long. | Propiedad OData | Key | Descripción |
|---|---|---|---|---|---|---|
| `MANDT` | `MANDT` | CLNT | 3 | *(no expuesto)* | | Mandante |
| `SWITCHNUM` | `EIDESWTNUM` | CHAR | 20 | `Switchnum` | ✅ | Número del documento de cambio |
| `STEPKEY` | `EIDESWTSTEPKEY` | CHAR | 22 | `Stepkey` | ✅ | Paso del documento de cambio, clave unívoca |
| `TIMESTAMP` | `TIMESTAMPL` | DEC | 21,7 | `Timestamp` | | Cronomarcador UTC (AAAAMMDDhhmmssmmmuuun) |
| `ACTIVITY` | `EIDESWTACT` | CHAR | 3 | `Activity` | | Actividad en cambio de servicio |
| `STATUS` | `EIDESWTSTAT` | CHAR | 2 | `Status` | | Status del cambio de servicio |

Expuesto **solo lectura** (no se implementó Create/Update/Delete — SEGW
los deja generados con `RAISE EXCEPTION /iwbep/cx_mgw_not_impl_exc` por
defecto, sin tocar).

## Cómo se construyó (SEGW)

1. `SEGW` → Create Project → `ZEIDESWTDOCSTEP`.
2. `Data Model` → **Import** (visible al seleccionar el nodo Data Model,
   no en el menú contextual de Entity Types) → *Import from DDIC Structure*:
   - Entity Type: `EideswtdocstepFacts`
   - ABAP Structure: `EIDESWTDOCSTEP`
   - Trae los 5 campos de negocio automáticamente (sin `MANDT`).
   - **El wizard no permitió marcar las keys** en el propio wizard (bug o
     limitación de esta versión) — si no se marca ninguna key, el sistema
     genera un *Complex Type* en vez de un *Entity Type* (error "Entity Set
     must define an entity type"). Solución: borrar lo generado y crear el
     Entity Type manualmente (`Entity Types → Create`, marcando "Create
     Related Entity Set"), y añadir las 5 propiedades a mano en
     `Properties` (con el icono de insertar fila ⊕) usando los tipos/
     longitudes de la tabla anterior — ahí sí se pudo marcar `Key` en
     `Switchnum` y `Stepkey`.
3. **Generate Runtime Objects** (no es "activar", en SEGW se llama
   "Generate") → aceptar los nombres de clase propuestos por defecto →
   genera `ZCL_ZEIDESWTDOCSTEP_MPC`/`_MPC_EXT`/`_DPC`/`_DPC_EXT` y registra
   modelo + servicio técnico.
4. **Implementar la lectura real**: `Service Implementation →
   EideswtdocstepFactsSet → GetEntitySet (Query)` → doble clic → abre
   SE24 en la clase `ZCL_ZEIDESWTDOCSTEP_DPC_EXT`. El método generado se
   llama `EIDESWTDOCSTEPFA_GET_ENTITYSET` (nombre truncado a 30
   caracteres). Contenido en `src/ZCL_ZEIDESWTDOCSTEP_DPC_EXT__GET_ENTITYSET.abap`.
   Activar la clase.
5. **Registrar el servicio**: `/IWFND/MAINT_SERVICE` (en este sistema, la
   transacción no arrancaba directamente — hubo que ejecutarla vía `SA38`
   con el programa `/IWFND/R_MGW_REGISTRATION`) → *Añadir servicio* →
   System Alias `LOCAL` → buscar `ZEIDESWTDOCSTEP*` → añadir → paquete
   `ZLE`.
6. **Probado con `/IWFND/GW_CLIENT`**: `GET
   .../ZEIDESWTDOCSTEP_SRV/EideswtdocstepFactsSet` → `200 OK`. La tabla
   estaba vacía en desarrollo; se insertó un registro de prueba por
   programa ABAP directo (`INSERT eideswtdocstep ...`, borrado después) y
   se confirmó que el servicio devuelve los 5 campos correctamente
   mapeados.

## Endpoint (sistema de desarrollo)

```
http://AWDS4HanaAP01.sapnewco-dev.adn.naturgy.com:8000/sap/opu/odata/sap/ZEIDESWTDOCSTEP_SRV/
```

Metadatos: añadir `$metadata` a la URL anterior.

## Pendiente / a definir con el cliente

- **Qué es NAPAI exactamente** y cómo consume el servicio — se asumió
  OData por la palabra "publicar", nunca se confirmó formalmente.
- **Autenticación**: el servicio no tiene OAuth activado; hace falta
  decidir un usuario técnico (equivalente a `COMMUSER`, el que usa
  MuleSoft en los otros desarrollos de este repo) y sus autorizaciones.
- **Transporte a QA/Producción**: todo lo anterior existe solo en
  desarrollo (`sapnewco-dev`). Falta transportar el proyecto SEGW y el
  registro del servicio a los siguientes sistemas.
- **Delta / extracción incremental**: no implementado. El proyecto
  `ZVBRP` (referencia) tiene un patrón de "Delta" (`DeltaLinksOfFactsOf...`)
  con token de última extracción — si NAPAI necesita traer solo cambios
  incrementales en vez de la tabla completa cada vez, hay que replicarlo.
  Pendiente de confirmar si es necesario.
- **Volumetría/filtros**: sin filtros de negocio implementados (trae toda
  la tabla). A revisar si hace falta paginar o filtrar por fecha una vez
  haya volumen real de datos.
