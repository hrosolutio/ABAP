# Resumen del Diseño Funcional

**Documento origen:** DF_Anulación de transferencias contabilizadas en SAP con IA (v1.0, 04/06/2026)

## Objeto

Implementar un nuevo proceso de anulación de transferencias contabilizadas en
SAP ISU a partir de información recibida de un sistema externo, en el módulo
SAP FI-CA (Cuenta Corriente Contractual).

## Requisitos

- Automatizar la anulación de transferencias contabilizadas en SAP.

## Fuera de alcance

- Gestión de errores en la ejecución del servicio: los errores obtenidos en
  SAP se devuelven como parámetro de salida (`ES_ERROR`) al sistema externo.

## Proceso: Anulación de transferencias contabilizadas en SAP

Nuevo servicio RFC `ZFI_FM_PAYLOT_REVERSE`, replica el funcionamiento de la
transacción estándar **FP08**.

### Parámetros de entrada

- `I_DOCUMENTID` (obligatorio): número de documento SAP.
- `I_CANCELDATE` (obligatorio): fecha de anulación.
- `I_CANCELREASON` (obligatorio): motivo de anulación.
- `I_PROCESO` (`CHAR20`): identificador de proceso/subproceso `CDI_11_03`.

### Parámetros de salida

- `E_RESULT`: resultado del servicio, `OK` / `NOK`.
- `ES_ERROR`: estructura de error (`CODE`, `DESCRIPTION`).
- `E_CANCELLEDDOCUMENTID`: documento anulado.

### Reglas de negocio

- El documento recibido debe ser un documento de pago generado en un lote de
  pago de transferencias, es decir, debe existir en `DFKKZP`. No se anulan
  documentos fuera de un lote de pagos.
- Si el resultado es exitoso, se genera en SAP un documento de anulación
  (clase de documento `ST`) que compensa el documento de entrada. La
  posición afectada en el lote de pago queda anulada con el documento de
  anulación generado.
- Las anulaciones quedan registradas con el usuario técnico usado por
  MuleSoft para conectarse a SAP (actualmente `COMMUSER`, igual que otros
  servicios OMEGA/SF).

### Nota técnica (FM estándar a invocar en RFC)

`FKK_CTRACPAYMINC_REVERSE`, con los siguientes `IMPORT`:

- `DOCUMENTNUMBER = OPBEL` (documento de pago) ← recibido por el nuevo servicio.
- `DOCTYPE = BLART = 'ST'` (clase de documento de anulación).
- `CLEARREAS = AUGRD = '05'` (motivo de compensación de anulación).
- `FIKEY` (clave de reconciliación para anulación): proponer clave y, si no
  existe, crearla mediante el módulo de función `FKK_CALL_EVENT_1113`.
- `REVERSEDATE` (fecha contable de anulación) ← recibido por el nuevo servicio.

## Premisas / Dependencias / Limitaciones

- **MuleSoft**: encargado de invocar el nuevo servicio SAP.
