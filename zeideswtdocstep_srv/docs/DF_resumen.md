# Resumen del alcance

**Documento origen:** ninguno — no existe Diseño Funcional para este
desarrollo. Este resumen documenta lo realmente implementado y los
supuestos tomados, a partir de la petición verbal ("publicar la tabla
EIDESWTDOCSTEP para que se pueda consumir desde NAPAI") y de un proyecto
SEGW existente en el sistema (`ZVBRP`) usado como referencia de patrón.

## Objeto

Exponer como API OData (SAP Gateway / SEGW) la tabla `EIDESWTDOCSTEP`
("Documento de cambio paso") para que el sistema externo **NAPAI** pueda
consultarla sin acceso directo a la base de datos SAP.

## Lo implementado

Servicio OData `ZEIDESWTDOCSTEP_SRV` (proyecto SEGW `ZEIDESWTDOCSTEP`),
con un único Entity Set de solo lectura (`EideswtdocstepFactsSet`) que
expone los 5 campos no técnicos de la tabla. Probado funcionalmente en
desarrollo con un registro de prueba (insertado y borrado por programa),
confirmando que el mapeo de campos es correcto. Ver `README.md` para el
detalle técnico completo y los pasos exactos seguidos en SEGW.

## Supuestos tomados (a validar)

- **NAPAI** consume vía **API HTTP/OData** — inferido de la palabra
  "publicar", nunca confirmado formalmente.
- El consumo es **solo lectura** (no se ha indicado necesidad de
  creación/actualización desde NAPAI).
- Se siguió el patrón de un desarrollo de extracción existente en el
  sistema (`ZVBRP`) por instrucción directa ("en SEGW hay varios
  proyectos de extracción de tablas, vamos a hacerlo igual"), en vez de
  CDS Views (que fue la propuesta técnica inicial, descartada).
- No se implementó el mecanismo de **delta** (extracción incremental)
  que sí tiene `ZVBRP` (entidades `FactsOf.../DeltaLinksOfFactsOf...`
  con token de última extracción) — no se confirmó si NAPAI lo necesita.

## Fuera de alcance (por falta de información)

- Autenticación/autorización específica de NAPAI contra el servicio.
- Extracción incremental (delta).
- Filtrado o paginación más allá de lo estándar de OData.
- Cualquier operación de escritura (crear/modificar/borrar pasos).
- Transporte a QA/Producción.

## Premisas / Dependencias / Limitaciones

- **NAPAI**: sistema externo que consumirá el servicio; no se tiene
  documentación de su lado (endpoint esperado, autenticación, formato).
- La tabla `EIDESWTDOCSTEP` estaba **vacía** en el sistema de desarrollo
  al momento de probar — no se ha validado con volumen de datos real.
- Este documento debe reemplazarse por el Diseño Funcional real en cuanto
  esté disponible, y revisarse contra él.
