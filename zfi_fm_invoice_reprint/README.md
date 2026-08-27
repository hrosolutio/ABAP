# ZFI_FM_INVOICE_REPRINT — Duplicado de factura en SAP

Implementación del servicio RFC para `SAP_ATC_007` (Enviar duplicado de
factura), sin Diseño Funcional — según indicó Diego, para los servicios
de Ola 2 no hay DF: es exponer la transacción estándar tal cual, con la
entrada de la pantalla, devolviendo mensaje de SAP y código de retorno
tanto en OK como en NOK.

Replica el comportamiento de la transacción estándar **EA60** (con la
opción de reimprimir) para generar, desde un sistema externo (vía
MuleSoft), un duplicado de una factura ya emitida.

## Estado: PRIMERA VERSIÓN, sin probar

A diferencia de `ZFI_FM_PAYLOT_REVERSE` y `ZFI_FM_PAYMENT_LOT_CLARIFY2`,
la cadena de esta primera versión se ha localizado **leyendo el código
fuente directamente** (programa `REAPRIN0` de la transacción EA60), sin
necesidad de depurar — EA60 no es un módulo de diálogo como FP08/FPCPL,
es un report normal con pantalla de selección estándar. Ver el detalle
completo de lo verificado y lo pendiente en los comentarios del propio
`.abap` y en `docs/investigacion.md`.

**No probado todavía en SE37** — a diferencia de los otros dos
desarrollos, que sí tienen prueba real superada.

## Contenido del repositorio

```
src/
  LZFI_FG_INV_REPRINTTOP.abap   Include TOP del grupo de función (constantes globales)
  ZFI_FM_INVOICE_REPRINT.abap   Código fuente del módulo de función RFC
docs/
  investigacion.md              Traza de la investigación (no hay DF de origen)
```

## Interfaz del servicio

| Parámetro | Dirección | Tipo | Obligatorio | Descripción |
|---|---|---|---|---|
| `I_OPBEL` | Import | `OPBEL_KK` | Sí | Documento de factura a reimprimir/duplicar |
| `E_RESULT` | Export | `CHAR3` | — | `OK` / `NOK` |
| `ES_ERROR` | Export | `ZFI_DE_XX_WS_ERROR` (`CODE`, `DESCRIPTION`) | — | Mensaje de SAP y código, informado **tanto en OK como en NOK** (requisito de Diego, distinto del patrón de los otros dos desarrollos, que solo informan `ES_ERROR` en el caso de error) |

## Lógica implementada

1. Valida que `I_OPBEL` esté informado.
2. Selecciona el documento de impresión con `ISU_S_EITERDK_SELECT_ALL`
   (módulo de función normal, verificado en SE37), filtrando por
   `I_OPBEL`. Asume `X_INVOICED = 'X'` (solo documentos reales, no
   simulaciones) — no verificado con un caso real.
3. Genera los parámetros de impresión con `EFG_GET_PRINT_PARAMETERS`,
   usando `X_NO_DIALOG`, `X_SUPPRESS_BCI_DIALOG` y `X_NO_ARCHIVE` a
   `'X'` para evitar cualquier popup interactivo (el mismo módulo,
   llamado desde pantalla en `REAPRIN0`, abre el popup de selección de
   impresora si no se le indica lo contrario). Verificado en SE37 que
   el parámetro `X_NO_DIALOG` existe con ese propósito; **no
   verificado** que con estos tres flags baste para no abrir ningún
   diálogo en la práctica.
4. Llama a `ISU_PRINT_EXPANDED` (módulo de función normal, verificado
   en SE37) con los parámetros de impresión generados, para generar de
   verdad el duplicado.
5. Cierra el spool con `EFG_PRINT_CLOSE` y hace `COMMIT WORK AND WAIT`.
6. Devuelve `E_RESULT = 'OK'` y en `ES_ERROR` un mensaje de
   confirmación (el de SAP si alguno de los FM anteriores lo dejó
   informado en `sy-msgid`/`sy-msgno`, si no un texto fijo).

## Instalación en SAP (SE80 / SE37)

1. Crear el grupo de función **`ZFI_FG_INV_REPRINT`** (SE80 → Grupo de
   función → Crear).
2. Sustituir el contenido del include TOP del grupo
   (`LZFI_FG_INV_REPRINTTOP`) por `src/LZFI_FG_INV_REPRINTTOP.abap`.
3. Crear el módulo de función **`ZFI_FM_INVOICE_REPRINT`** dentro del
   grupo:
   - Atributos: marcar **"Módulo de función remoto"** (RFC).
   - Pestaña *Import*: `I_OPBEL` (obligatorio), tipo `OPBEL_KK`.
   - Pestaña *Export*: `E_RESULT`, `ES_ERROR` (tipo DDIC
     `ZFI_DE_XX_WS_ERROR`, reutilizado de los otros desarrollos).
   - Pestaña *Código fuente*: pegar `src/ZFI_FM_INVOICE_REPRINT.abap`.
4. Activar y probar contra un documento de factura real ya emitido.

## Pendiente / a definir con el cliente

- **Probar de principio a fin en SE37** — nada de esta cadena se ha
  ejecutado todavía contra el sistema real, solo se ha leído el código
  fuente de `REAPRIN0`.
- Confirmar que `X_NO_DIALOG` + `X_SUPPRESS_BCI_DIALOG` + `X_NO_ARCHIVE`
  evitan de verdad cualquier popup al llamar `EFG_GET_PRINT_PARAMETERS`.
- **`XT_RANGES` de `ISU_PRINT_EXPANDED`**: en `REAPRIN0` lo construye la
  FORM `SET_PRINT_PARAMETERS`, cuyo código no se ha visto todavía. Aquí
  se ha aproximado reutilizando el mismo rango de `OPBEL` de la
  selección — sin verificar que sea el contenido correcto.
- **No replicadas en esta primera versión** (código fuente no visto):
  `dpp_check` (interlocutor comercial bloqueado), `reversal_check`
  (documento ya anulado/reimpreso), bloqueos de cuenta/interlocutor
  (`enqueue_ca`/`enqueue_bupa`), y la actualización en BD tras imprimir
  (`print_updates`). Riesgo: se podría generar un duplicado sin alguna
  validación de negocio que sí aplica la transacción estándar.
- Confirmar si `XT_ERGRD` debe llevar algún filtro (en la pantalla EA60
  es obligatorio; aquí se ha dejado vacío, asumiendo que no hace falta
  al identificar el documento directamente por `OPBEL`).
- Autorización RFC del usuario técnico (`COMMUSER` u otro) sobre el
  grupo de función.
- Alta del objeto en el sistema de transporte correspondiente al
  proyecto.
