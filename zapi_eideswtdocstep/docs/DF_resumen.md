# Resumen del alcance

**Documento origen:** ninguno — no existe Diseño Funcional para este
desarrollo al momento de su creación. Este resumen documenta los supuestos
tomados a partir de la petición verbal ("publicar la tabla EIDESWTDOCSTEP
para que se pueda consumir desde NAPAI") y de la definición DDIC de la
tabla (SE11).

## Objeto

Exponer como API (OData) la tabla `EIDESWTDOCSTEP` ("Documento de cambio
paso") para que el sistema externo **NAPAI** pueda consultarla sin acceso
directo a la base de datos SAP.

## Supuestos tomados (a validar)

- **NAPAI** consume vía **API HTTP/OData** (no RFC) — se infiere de la
  palabra "publicar", pero no está confirmado.
- El consumo es **solo lectura** (no se ha indicado necesidad de
  creación/actualización de registros desde NAPAI).
- Se exponen **todos los campos no técnicos** de la tabla (`SWITCHNUM`,
  `STEPKEY`, `TIMESTAMP`, `ACTIVITY`, `STATUS`); `MANDT` se omite por ser
  gestionado automáticamente por el motor CDS.
- No se han definido filtros de autorización específicos más allá del
  `@AccessControl.authorizationCheck: #CHECK` estándar.

## Fuera de alcance (por falta de información)

- Autenticación/autorización específica de NAPAI contra el servicio.
- Filtrado incremental o paginación más allá de lo estándar de OData.
- Cualquier operación de escritura (crear/modificar/borrar pasos).

## Proceso: publicación de EIDESWTDOCSTEP como API

Nuevas CDS Views `ZI_EIDESWTDOCSTEP` (básica) y `ZC_EIDESWTDOCSTEP`
(consumo, `@OData.publish: true`) — ver `README.md` para detalle técnico
y estructura de campos.

## Premisas / Dependencias / Limitaciones

- **NAPAI**: sistema externo que consumirá el servicio; no se tiene
  documentación de su lado (endpoint esperado, autenticación, formato).
- Este documento debe reemplazarse por el Diseño Funcional real en cuanto
  esté disponible, y este resumen debe revisarse contra él.
