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
| `E_PDF` | Export | `XSTRING` | — | El documento (factura) en PDF, como binario. **Parámetro nuevo (24/11/2026)** — hay que añadirlo a mano en la pestaña Export de SE37, no existía en versiones anteriores |

## Lógica implementada

1. Valida que `I_OPBEL` esté informado.
2. Selecciona el documento de impresión con `ISU_S_EITERDK_SELECT_ALL`
   (módulo de función normal, verificado en SE37), filtrando por
   `I_OPBEL`. Asume `X_INVOICED = 'X'` (solo documentos reales, no
   simulaciones) — no verificado con un caso real.
3. Obtiene los datos de dirección/envío de la cuenta contrato con
   `ISU_GET_ACC_ADRESS_DATA`.
4. Genera los parámetros de impresión con `EFG_GET_PRINT_PARAMETERS`,
   usando `X_NO_DIALOG`, `X_SUPPRESS_BCI_DIALOG` y `X_NO_ARCHIVE` a
   `'X'` para evitar cualquier popup interactivo, y **`TDGETOTF = 'X'`**
   para que la cadena no despache a ningún sitio (ni imprima, ni
   visualice, ni envíe) y solo devuelva el documento como dato.
   **Probado en QA: `TDGETOTF` no evita el popup de dispositivo de
   salida** (sigue siendo obligatorio) — se usa `'LOCL'` (constante
   `gc_tddest_dummy`) como valor de relleno, ya que el documento nunca
   llega a despacharse de verdad.
5. Determina el formulario a usar: `FORMKEY` de `EITERDK-FORMKEY`
   (directo) y `FORMCLASS` llamando a `EFG_DB_EFRM_SELECT` con ese
   `FORMKEY` (lógica localizada en la FORM `SET_PRINT_PARAMETERS` de
   `REAPRIN0`). Sin esto, el motor de impresión falla internamente
   (mensaje `EZ 823`).
6. Llama a **`EFG_PRINT_EXPANDED`** (no a `ISU_PRINT_EXPANDED`, que no
   devuelve el documento generado — ver cabecera del `.abap`), una vez
   por cada destinatario de los datos de dirección, recogiendo
   `Y_PDF_RESULT` y `YT_OTF_DATA`.
7. Obtiene el PDF por uno de dos caminos, según si el formulario es
   PDF-based (Adobe Forms) o SAPscript/SmartForms clásico (no se sabe
   de antemano cuál es):
   - Si `Y_PDF_RESULT-STR_RESULT_FORM-PDF` viene relleno: se usa
     directamente (ya es el PDF en bruto).
   - Si no, y `YT_OTF_DATA` sí viene relleno: se convierte con los
     módulos estándar `CONVERT_OTF` + `SCMS_BINARY_TO_XSTRING`.
8. Devuelve `E_RESULT = 'OK'` y el PDF en `E_PDF`, sin rellenar
   `ES_ERROR`.

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
     `ZFI_DE_XX_WS_ERROR`, reutilizado de los otros desarrollos), y
     **`E_PDF`** tipo `XSTRING`.
   - Pestaña *Código fuente*: pegar `src/ZFI_FM_INVOICE_REPRINT.abap`.
4. Activar y probar contra un documento de factura real ya emitido.

## Pendiente / a definir con el cliente

- **CAMBIO DE DISEÑO (24/11/2026)**: tras varias vueltas intentando
  determinar un dispositivo de salida (constante fija, `GET PARAMETER
  ID 'PRI'`, tabla Z — los tres descartados), se cayó en la cuenta de
  que MuleSoft no tiene impresora al otro lado, necesita el **PDF como
  dato**. Rediseñado para llamar directamente a `EFG_PRINT_EXPANDED`
  con `TDGETOTF = 'X'`. **Probado en QA: `TDGETOTF` NO evita el popup
  de dispositivo de salida** — sigue siendo obligatorio igualmente,
  resuelto con `'LOCL'` (constante `gc_tddest_dummy`) como valor de
  usar y tirar (dispositivo estándar presente en cualquier sistema
  SAP, a diferencia de `'LP01'`, específico de QA).
- **Dump `CALL_FUNCTION_CONFLICT_TYPE`** al llamar `EFG_PRINT_EXPANDED`:
  `X_HEADER` se había tipado como `ISUACCADDRDATA` solo por ver
  `l_header = xt_addressdata` en `REAPRIN0` (un `MOVE` clásico entre
  tipos distintos, válido en tiempo de ejecución por compatibilidad de
  memoria, pero no implica que compartan tipo). Verificado en SE37:
  `X_HEADER` es en realidad `RFGEN-HEADER`. Corregido, manteniendo el
  mismo `MOVE`.
- **`YT_OTF_DATA` vacía tras la llamada** (probado en QA, sin dump ni
  popup — la llamada en sí funciona): resultó ser que esta factura usa
  un SmartForm real, `ZFA_SF_FACT_ISU` (confirmado en la tabla `EFRM`:
  `FORMTYPE = SF`, `SMARTFORM = ZFA_SF_FACT_ISU` — el `FORMKEY`,
  `ZFA_AF_FACTURA_ISU`, no es un nombre de formulario, llevó a dos
  suposiciones erróneas antes de comprobarlo en `EFRM`). Depurado paso
  a paso: `SSF_FUNCTION_MODULE_NAME` resuelve bien el módulo generado
  real (`/1BCDWB/SF00000005`), y `EFG_PRINT` lo invoca (vía un segundo
  nivel de función generada, `/1PWB/...`) sin error — pero
  `YT_OTF_DATA` sigue vacía incluso en ese nivel. Hipótesis en curso
  (sin confirmar): falta `LS_PRINTPARAMS-LAST_DOC = 'Y'` (visto en
  `REAPRIN0`, con ese valor exacto) y la llamada a `EFG_PRINT_CLOSE`
  (quitada al rediseñar, pensando que solo cerraba el spool) — según
  el propio comentario de `REAPRIN0`, es `EFG_PRINT_CLOSE` quien de
  verdad cierra/finaliza el formulario cuando `LAST_DOC = 'Y'`. Añadidos
  los dos. **Pendiente de confirmar en QA si esto resuelve el volcado
  del OTF.**
  De paso, se mantiene el camino alternativo por si el formulario fuera
  PDF-based en vez de SmartForm: si `Y_PDF_RESULT-STR_RESULT_FORM-PDF`
  viene relleno se usa directamente, si no se sigue con `YT_OTF_DATA`
  → `CONVERT_OTF`.
- **Pruebas reales en QA (23/11/2026)**, dos dumps encontrados y corregidos:
  1. `CALL_FUNCTION_CONFLICT_LENG` en `ISU_S_EITERDK_SELECT_ALL` — `XT_OPBEL`
     mal tipado (`RANGE OF opbel_kk` casero en vez de `ISU_RANGES`, el
     tipo real). Corregido.
  2. `CALL_FUNCTION_PARM_MISSING` (`XT_ADDRESSDATA` no informado) — la
     llamada a `ISU_GET_ACC_ADRESS_DATA` (identificada en la
     investigación inicial como parte de la cadena real) se quedó sin
     implementar en la primera versión. Añadida ahora.
- **"Error interno: No se puede repetir el mensaje"**: resultó ser un
  mensaje genérico (clase `55`, nº `405`) sin más información — hubo
  que depurar paso a paso dentro de `ISU_PRINT_EXPANDED` → `EFG_PRINT_EXPANDED`
  → `EFG_PRINT` para encontrar el error real: mensaje `EZ 823`,
  **"Parámetros X_PRINTPARAMS-FORMCLASS y X_PRINTPARAMS-FORMKEY son
  iniciales al llamar MF EFG_PRINT"** — no estábamos informando el
  formulario a usar. Corregido localizando la lógica real en la FORM
  `SET_PRINT_PARAMETERS` de `REAPRIN0` (su código, antes sin ver):
  `FORMKEY` sale de `EITERDK-FORMKEY` directamente, y `FORMCLASS` se
  obtiene llamando a `EFG_DB_EFRM_SELECT` con ese `FORMKEY`. Añadido
  también `LANGU` de `EITERDK-LANGU`, visto en la misma FORM.
  De paso, sustituido en todos los puntos del código que usaban
  `MESSAGE ID sy-msgid ... INTO ... WITH sy-msgv1...` (que "repite" un
  mensaje de SAP, y fallaba él mismo al intentar usarlo) por una
  construcción directa del texto a partir de `sy-msgid`/`sy-msgno`/
  `sy-msgty`, que no depende de ese mecanismo.
- **Códigos de error**: `ES_ERROR-CODE` es `NUM3`, no admite texto — las
  primeras versiones usaban códigos de texto (`PARAM_MISSING`,
  `DOC_NOT_FOUND`...), corregido a `'102'` (código de error genérico
  hacia Mulesoft, igual que los otros dos RFC del repo). El caso `OK`
  no rellena `ES_ERROR` (decisión del usuario), así que no aplica aquí.
- **Nombres exactos de `CONVERT_OTF` y `SCMS_BINARY_TO_XSTRING`**: son
  módulos muy estándar y conocidos, pero no se han verificado en SE37
  contra este sistema en concreto.
- **Contenido de `XT_RANGES` de `EFG_PRINT_EXPANDED`**: el tipo está
  corregido (`EFG_RANGES`), pero el contenido sigue siendo una
  aproximación — en `REAPRIN0` lo construye la FORM
  `SET_PRINT_PARAMETERS`, cuyo código no se ha visto todavía (solo la
  parte de `FORMKEY`/`FORMCLASS`). Aquí se ha aproximado con un rango
  de `OPBEL`, sin confirmar que sea el contenido correcto.
- **`XT_RANGES1-9` y `XT_RECIPIENT` de `EFG_PRINT_EXPANDED`** se dejan
  vacíos, replicando lo que hace `ISU_PRINT_EXPANDED` internamente
  (tampoco los rellena) — asumido opcional, no confirmado.
- **No replicadas en esta primera versión** (código fuente no visto):
  `dpp_check` (interlocutor comercial bloqueado), `reversal_check`
  (documento ya anulado/reimpreso), bloqueos de cuenta/interlocutor
  (`enqueue_ca`/`enqueue_bupa`), y la actualización en BD tras imprimir
  (`print_updates`). Riesgo: se podría generar un duplicado sin alguna
  validación de negocio que sí aplica la transacción estándar. Con el
  cambio de diseño (ya no se contabiliza nada), este riesgo es menor
  que antes, pero sigue sin confirmarse.
- Confirmar si `XT_ERGRD` debe llevar algún filtro (en la pantalla EA60
  es obligatorio; aquí se ha dejado vacío, asumiendo que no hace falta
  al identificar el documento directamente por `OPBEL`).
- Autorización RFC del usuario técnico (`COMMUSER` u otro) sobre el
  grupo de función.
- Alta del objeto en el sistema de transporte correspondiente al
  proyecto.
