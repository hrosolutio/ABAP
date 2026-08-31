# ZC_EIDESWTDOCSTEP — API de consumo de EIDESWTDOCSTEP (NAPAI)

Publica como servicio OData (vía CDS View) la tabla transparente
**`EIDESWTDOCSTEP`** ("Documento de cambio paso") para que el sistema
externo **NAPAI** pueda consultarla vía API en lugar de acceso directo a
base de datos.

> ⚠️ Este desarrollo **no parte de un Diseño Funcional formal** (no existe
> uno al momento de crearlo). Es una propuesta técnica basada únicamente en
> la definición DDIC de la tabla (SE11) — ver "Pendiente / a definir con el
> cliente" más abajo antes de transportar a productivo.

## Contenido del repositorio

```
src/
  ZI_EIDESWTDOCSTEP.ddls.asddls   CDS View básica (interfaz 1:1 sobre la tabla)
  ZC_EIDESWTDOCSTEP.ddls.asddls   CDS View de consumo, publicada como OData
docs/
  DF_resumen.md                   Resumen / supuestos del alcance (no hay DF origen)
```

## Estructura de la tabla EIDESWTDOCSTEP (SE11)

| Campo | Clave | Elem. datos | Tipo | Long. | Descripción |
|---|---|---|---|---|---|
| `MANDT` | Sí | `MANDT` | CLNT | 3 | Mandante |
| `SWITCHNUM` | Sí | `EIDESWTNUM` | CHAR | 20 | Número del documento de cambio |
| `STEPKEY` | Sí | `EIDESWTSTEPKEY` | CHAR | 22 | Paso del documento de cambio, clave unívoca |
| `TIMESTAMP` | No | `TIMESTAMPL` | DEC | 21,7 | Cronomarcador UTC (AAAAMMDDhhmmssmmmuuun) |
| `ACTIVITY` | No | `EIDESWTACT` | CHAR | 3 | Actividad en cambio de servicio |
| `STATUS` | No | `EIDESWTSTAT` | CHAR | 2 | Status del cambio de servicio |

`MANDT` no se proyecta en las CDS views (multi-mandante lo maneja el motor
CDS automáticamente).

## Diseño técnico

- **`ZI_EIDESWTDOCSTEP`**: vista CDS básica, selección 1:1 sobre la tabla,
  con nombres de campo orientados a negocio.
- **`ZC_EIDESWTDOCSTEP`**: vista de consumo (`root view entity`) sobre la
  básica, anotada `@OData.publish: true` para que el sistema genere y
  registre automáticamente un servicio OData V2 al activarla.
- Expuesta **solo lectura** (no se modela CRUD ni RAP behavior — no hay
  requisito de escritura conocido; si NAPAI necesitara crear/actualizar
  pasos, hay que modelar un Behavior Definition RAP en su lugar).

## Instalación en SAP (SE80 / Eclipse ADT)

1. Crear la vista CDS **`ZI_EIDESWTDOCSTEP`** (Eclipse ADT → New → Data
   Definition, o SE80) con el contenido de `src/ZI_EIDESWTDOCSTEP.ddls.asddls`.
   Activar.
2. Crear la vista CDS **`ZC_EIDESWTDOCSTEP`** con el contenido de
   `src/ZC_EIDESWTDOCSTEP.ddls.asddls`. Activar — esto dispara la
   generación automática del servicio OData (`@OData.publish: true`).
3. En **`/IWFND/MAINT_SERVICE`** (SAP Gateway), añadir el system alias
   correspondiente y **activar** el servicio generado
   (`ZC_EIDESWTDOCSTEP_CDS`, nombre exacto según el sistema).
4. Probar el endpoint (`.../sap/opu/odata/sap/ZC_EIDESWTDOCSTEP_CDS/`)
   con un cliente OData (Postman/Gateway Client) antes de habilitar el
   consumo desde NAPAI.
5. Dar de alta el objeto en el sistema de transporte correspondiente al
   proyecto.

## Pendiente / a definir con el cliente

- **Qué es NAPAI exactamente** y cómo consume el servicio (OData directo,
  a través de SAP API Management/API Business Hub, u otro gateway externo).
- **Release del sistema**: si es S/4HANA on-premise reciente, puede ser
  preferible modelar **Service Definition + Service Binding (OData V4 /
  RAP)** en vez de `@OData.publish` (que es el mecanismo clásico OData V2
  y está en desuso para desarrollos nuevos en releases recientes).
- **Autorizaciones**: rol/usuario técnico con el que NAPAI se autenticará
  contra el servicio, y objeto de autorización a usar en
  `@AccessControl.authorizationCheck`.
- **Filtros/volumetría**: si la tabla es de alto volumen, definir si el
  consumo debe ser incremental (filtro por `TIMESTAMP`) en vez de full,
  y si conviene exponer un `$filter` obligatorio.
- **Confirmar si el consumo es solo lectura** o si NAPAI también necesita
  crear/actualizar pasos (cambiaría el diseño a un Behavior Definition RAP).
- Nombre definitivo del servicio y paquete de transporte según convención
  del cliente.
