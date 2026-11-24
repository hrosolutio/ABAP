# ZFI_FM_INVOICE_REPRINT — Duplicado de factura en SAP

Implementación del servicio RFC para `SAP_ATC_007` (Enviar duplicado de
factura), sin Diseño Funcional — según indicó Diego, para los servicios
de Ola 2 no hay DF: es exponer la transacción estándar tal cual, con la
entrada de la pantalla, devolviendo mensaje de SAP y código de retorno
en caso de error. **Decisión del usuario**: en el caso OK no se rellena
`ES_ERROR` (queda vacío) — aunque Diego habló en general de "mensaje y
código tanto en OK como en error" para los servicios de Ola 2, para
este desarrollo en concreto se ha decidido no informarlo en el OK.

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
| `ES_ERROR` | Export | `ZFI_DE_XX_WS_ERROR` (`CODE`, `DESCRIPTION`) | — | Mensaje de SAP y código, informado **solo en el caso NOK** (igual que en los otros dos desarrollos; decisión explícita del usuario de no rellenarlo en el OK) |

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
   impresora si no se le indica lo contrario), y proponiendo un
   dispositivo de salida (`X_PRINTPARAMS-TDDEST`, constante
   `gc_dispositivo_salida`, **valor solo de prueba**) porque sin él la
   función pide el dispositivo igualmente aunque `X_NO_DIALOG = 'X'`.
4. Determina el formulario a usar: `FORMKEY` de `EITERDK-FORMKEY`
   (directo) y `FORMCLASS` llamando a `EFG_DB_EFRM_SELECT` con ese
   `FORMKEY` (lógica localizada en la FORM `SET_PRINT_PARAMETERS` de
   `REAPRIN0`). Sin esto, `ISU_PRINT_EXPANDED` falla internamente
   (mensaje `EZ 823`).
5. Llama a `ISU_PRINT_EXPANDED` (módulo de función normal, verificado
   en SE37) con los parámetros de impresión generados, para generar de
   verdad el duplicado.
6. Cierra el spool con `EFG_PRINT_CLOSE` y hace `COMMIT WORK AND WAIT`.
7. Devuelve `E_RESULT = 'OK'`, sin rellenar `ES_ERROR`.

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

- **Pruebas reales en QA (23/11/2026)**, dos dumps encontrados y corregidos:
  1. `CALL_FUNCTION_CONFLICT_LENG` en `ISU_S_EITERDK_SELECT_ALL` — `XT_OPBEL`
     mal tipado (`RANGE OF opbel_kk` casero en vez de `ISU_RANGES`, el
     tipo real). Corregido, y de paso corregido también `XT_RANGES` de
     `ISU_PRINT_EXPANDED` (tipo real `EFG_RANGES`, distinto de
     `ISU_RANGES`).
  2. `CALL_FUNCTION_PARM_MISSING` en `ISU_PRINT_EXPANDED` (`XT_ADDRESSDATA`
     no informado) — la llamada a `ISU_GET_ACC_ADRESS_DATA` (identificada
     en la investigación inicial como parte de la cadena real) se quedó
     sin implementar en la primera versión. Añadida ahora.
  **Pendiente: volver a probar en QA**, no confirmado todavía que no
  queden más dumps.
- **"Error interno: No se puede repetir el mensaje" al fallar
  `ISU_PRINT_EXPANDED`** (QA, 23-24/11/2026): resultó ser un mensaje
  genérico (clase `55`, nº `405`) sin más información — hubo que
  depurar paso a paso dentro de `ISU_PRINT_EXPANDED` → `EFG_PRINT_EXPANDED`
  → `EFG_PRINT` para encontrar el error real: mensaje `EZ 823`,
  **"Parámetros X_PRINTPARAMS-FORMCLASS y X_PRINTPARAMS-FORMKEY son
  iniciales al llamar MF EFG_PRINT"** — no estábamos informando el
  formulario a usar. Corregido localizando la lógica real en la FORM
  `SET_PRINT_PARAMETERS` de `REAPRIN0` (su código, antes sin ver):
  `FORMKEY` sale de `EITERDK-FORMKEY` directamente, y `FORMCLASS` se
  obtiene llamando a `EFG_DB_EFRM_SELECT` con ese `FORMKEY`. Añadido
  también `LANGU` de `EITERDK-LANGU`, visto en la misma FORM.
  **Pendiente: volver a probar en QA.**
  De paso, sustituido en los 6 puntos del código que usaban
  `MESSAGE ID sy-msgid ... INTO ... WITH sy-msgv1...` (que "repite" un
  mensaje de SAP, y fallaba él mismo al intentar usarlo) por una
  construcción directa del texto a partir de `sy-msgid`/`sy-msgno`/
  `sy-msgty`, que no depende de ese mecanismo.
- **Popup "Seleccionar parámetro impresión" al llamar
  `EFG_GET_PRINT_PARAMETERS`** (probado en QA, 23/11/2026): los flags
  `X_NO_DIALOG`/`X_SUPPRESS_BCI_DIALOG`/`X_NO_ARCHIVE` no bastan si no
  hay un dispositivo de salida (`TDDEST`) determinable automáticamente
  — sin propuesta, la función abre el popup igualmente para pedirlo.
  Corregido pasando `X_PRINTPARAMS-TDDEST = 'LP01'` como propuesta
  (constante `gc_dispositivo_salida`). **Este valor es solo para
  pruebas** — pendiente de decisión de negocio real: el servicio
  debería despachar por el canal configurado del cliente (email/portal,
  según `SENDCONTROL` de `ISU_GET_ACC_ADRESS_DATA`), no imprimir en un
  dispositivo físico fijo. No llevar `LP01` a producción sin confirmar.
- **Códigos de error**: `ES_ERROR-CODE` es `NUM3`, no admite texto — las
  primeras versiones usaban códigos de texto (`PARAM_MISSING`,
  `DOC_NOT_FOUND`...), corregido a `'102'` (código de error genérico
  hacia Mulesoft, igual que los otros dos RFC del repo). El caso `OK`
  no rellena `ES_ERROR` (decisión del usuario), así que no aplica aquí.
- Confirmar que `X_NO_DIALOG` + `X_SUPPRESS_BCI_DIALOG` + `X_NO_ARCHIVE`
  evitan de verdad cualquier popup al llamar `EFG_GET_PRINT_PARAMETERS`.
- **Contenido de `XT_RANGES` de `ISU_PRINT_EXPANDED`**: el tipo ya está
  corregido (`EFG_RANGES`), pero el contenido sigue siendo una
  aproximación — en `REAPRIN0` lo construye la FORM
  `SET_PRINT_PARAMETERS`, cuyo código no se ha visto todavía. Aquí se
  ha aproximado con un rango de `OPBEL`, sin confirmar que sea el
  contenido correcto.
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
