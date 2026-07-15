# ZFI_FM_PAYMENT_LOT_CLARIFY2 — Clarificación de transferencias pendientes en SAP

Implementación del servicio RFC descrito en el Diseño Funcional
*"Aplicación de transferencias Pdtes Clarificar con IA"* (sección A - SAP).

Replica el comportamiento de la transacción estándar **FPCPL** para
clarificar, desde un sistema externo (vía MuleSoft), una posición de lote
de pago pendiente de clarificar, aplicando la(s) factura(s) recibida(s).

## Estado: EN DESARROLLO — lógica central no implementada

El propio DF advierte que el módulo de función estándar
`FKK_PAYMENT_BATCH_CLARIFY_ITEM` **no se puede utilizar directamente** y
que no existe FM estándar ejecutable por RFC para clarificar posiciones de
lote. La secuencia real de llamadas todavía no está verificada contra el
sistema — hay que depurar FPCPL para localizarla, igual que se hizo con
FP08 para el desarrollo de anulación de transferencias
(`ZFI_FM_PAYLOT_REVERSE`). El código actual valida la entrada y deja el
paso de clarificación marcado como `TODO` a propósito.

## Contenido del repositorio

```
src/
  LZFI_FG_PAY_CLARIFYTOP.abap        Include TOP del grupo de función (tipos y constantes globales)
  ZFI_FM_PAYMENT_LOT_CLARIFY2.abap   Código fuente del módulo de función RFC (esqueleto)
docs/
  DF_resumen.md                      Resumen del Diseño Funcional (trazabilidad)
```

## Interfaz del servicio

| Parámetro | Dirección | Tipo | Obligatorio | Descripción |
|---|---|---|---|---|
| `I_KEYZ1` | Import | `KEYZ1_KK` | Sí | Número de lote |
| `I_POSZA` | Import | `POSZA_KK` | Sí | Posición del lote |
| `I_XBLNR` | Import | `TY_T_XBLNR` (tabla de `XBLNR`) | Sí | Factura(s) a aplicar. Decidido con el cliente: tabla de longitud variable (el DF tenía una indicación de factura única y una nota posterior pidiendo varias, mínimo 5 propuesto) |
| `E_RESULT` | Export | `CHAR3` | — | `OK` / `NOK` |
| `ES_ERROR` | Export | `ZFI_DE_XX_WS_ERROR` (`CODE`, `DESCRIPTION`) | — | Error de negocio o técnico |
| `E_OPBEL` | Export | `OPBEL_KK` | — | Documento contabilizado |

## Lógica implementada hasta ahora

1. Valida que `I_KEYZ1`, `I_POSZA` e `I_XBLNR` estén informados.
2. Verifica que la posición del lote exista y esté pendiente de clarificar
   (`DFKKZP-XKLAE = 'X'`); si no, devuelve `E_RESULT = 'NOK'`.
3. **Pendiente**: aplicar la(s) factura(s) de `I_XBLNR` a la posición como
   tipo de selección `"X"` (número de documento oficial) y contabilizar,
   replicando FPCPL. De momento devuelve `E_RESULT = 'NOK'` con
   `ES_ERROR-CODE = 'NOT_IMPLEMENTED'`.

El usuario que queda registrado en las clarificaciones es el usuario
técnico con el que MuleSoft se conecta a SAP, en el campo `DFKKZP-AENAM`
(actualmente `COMMUSER`).

## Siguiente paso

Depurar la transacción **FPCPL** sobre una posición de lote real
pendiente de clarificar, aplicando manualmente una factura como tipo de
selección `X`, y localizar con el debugger la llamada/secuencia real que
efectúa la clarificación — mismo método que se usó para encontrar
`FKK_FIKEY_GET_FOR_EXT_CALL` en el desarrollo anterior.

## Pendiente / a definir con el cliente

- Localizar la secuencia real de clarificación (ver "Siguiente paso").
- Confirmar comportamiento si alguna de las facturas de `I_XBLNR` no
  encaja o el importe no cuadra exactamente con la posición del lote
  (el DF solo contempla el caso de coincidencia exacta para clarificación
  completa).
- Autorización RFC del usuario `COMMUSER` (o el que corresponda) sobre el
  grupo de función.
- Alta del objeto en el sistema de transporte correspondiente al proyecto.
