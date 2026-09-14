# Resumen del Diseño Funcional

**Documento origen:** DF_Aplicación de Transferencias Pdtes Clarificar con IA (v1.0, 16/06/2026)

## Objeto

Implementar un nuevo proceso de clarificación de transferencias pendientes
de contabilizar en SAP ISU a partir de información recibida de un sistema
externo, en el módulo SAP FI-CA (Cuenta Corriente Contractual).

## Requisitos

- Automatizar la clarificación de transferencias en SAP.

## Fuera de alcance

- Gestión de errores en la ejecución del servicio: los errores obtenidos en
  SAP se devuelven como parámetro de salida (`ES_ERROR`) al sistema externo.
- Como parámetro de entrada solo se espera "número de factura" (`XBLNR`); no
  se contempla recibir otro tipo de identificadores.

## Proceso: Clarificación de transferencias en SAP

Nuevo servicio RFC `ZFI_FM_PAYMENT_LOT_CLARIFY2`, replica el funcionamiento
de la transacción estándar **FPCPL**.

### Parámetros de entrada

- `I_KEYZ1` (obligatorio): número de lote.
- `I_POSZA` (obligatorio): posición del lote.
- `I_XBLNR` (obligatorio): factura(s). El DF original lo limitaba a 1
  factura ("en fase de desarrollo se especificará si es posible indicar
  más de 1"), pero incluye una nota posterior indicando que debe permitir
  informar más de una factura (mínimo propuesto 5, idealmente número
  variable). **Decisión tomada con el cliente: tabla de longitud
  variable.**

### Parámetros de salida

- `E_RESULT`: resultado del servicio, `OK` / `NOK`.
- `ES_ERROR`: estructura de error (`CODE`, `DESCRIPTION`).
- `E_OPBEL`: documento contabilizado.

### Reglas de negocio

- FPCPL recoge las posiciones de lote pendientes de clarificar: posiciones
  para las que no se ha identificado la deuda a compensar, contabilizadas
  provisionalmente en la cuenta 4305520150. Indicador de pendiente
  clarificar: `DFKKZP-XKLAE = 'X'`.
- Para la posición seleccionada, se modifican manualmente los valores de
  selección para identificar la deuda correctamente y contabilizar.
- Tras la contabilización, la posición del lote deja de estar pendiente de
  clarificar y se informa el documento de clarificación generado que
  compensa la deuda identificada.
- El servicio recibe el código oficial de factura (tipo de selección =
  `"X"`, "Número de documento oficial") que hay que introducir en la
  posición de lote. El importe de la factura debe coincidir con el importe
  de la posición del lote de pago para garantizar la clarificación
  completa.
- Las clarificaciones quedan registradas con el usuario técnico usado por
  MuleSoft para conectarse a SAP, en el campo `DFKKZP-AENAM` (actualmente
  `COMMUSER`, igual que otros servicios OMEGA/SF).

### Nota técnica y limitación importante

El propio DF advierte explícitamente:

> Módulo de funciones estándar para clarificar posiciones de lote
> `FKK_PAYMENT_BATCH_CLARIFY_ITEM` **no se puede utilizar directamente**.

Y en la tabla de Premisas/Dependencias/Limitaciones:

> No existe módulo de funciones estándar de SAP ejecutable directamente
> desde RFC que clarifique posiciones de lote.

**Esto implica que la lógica central de este desarrollo no está resuelta
en el DF y requiere investigación** (previsiblemente depurando la
transacción FPCPL, igual que se hizo para el desarrollo de anulación de
transferencias) antes de poder implementarla. No se debe asumir ni
inventar una secuencia de llamadas alternativa sin verificarla contra el
sistema real.

## Premisas / Dependencias / Limitaciones

- **MULESOFT** (dependencia): encargado de invocar el nuevo servicio SAP.
- **Limitación**: no existe módulo de funciones estándar de SAP ejecutable
  directamente desde RFC que clarifique posiciones de lote.
