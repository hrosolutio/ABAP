# Traza de la investigación (no hay Diseño Funcional de origen)

A diferencia de `zfi_fm_paylot_reverse` y `zfi_fm_payment_lot_clarify2`,
que parten de un Diseño Funcional escrito, este desarrollo (`SAP_ATC_007`,
Ola 2) no tiene DF. Según confirmó Diego (mensaje directo, sin
documento): no hay documentación, son las transacciones estándar del
sistema las que hay que exponer; la entrada es la de la pantalla de la
transacción, y la salida debe llevar el mensaje de SAP y el código de
retorno, tanto en el caso OK como en el de error.

Este documento sustituye al "Resumen del Diseño Funcional" de los otros
dos desarrollos, dejando trazabilidad de por qué el código hace lo que
hace, ya que aquí no hay ningún documento de negocio del que partir.

## Transacción de origen

**EA60** — "Enviar duplicado de factura" (según nomenclatura de Eva en
el correo de Diego), con la opción de reimprimir.

## Pasos de la investigación

1. **SE93** sobre `EA60` → programa **`REAPRIN0`**, pantalla **1000**.
2. El nombre del programa **no lleva el prefijo `SAPL`** (a diferencia
   de `SAPLEA02` para EA00, o `SAPLFKZ0` para FPCPL) → no es el
   programa principal de un grupo de función con módulos de diálogo, es
   un **report independiente**. La pantalla 1000 de un report sin
   `SAPL` es, casi siempre, la pantalla de selección estándar generada
   automáticamente a partir de `PARAMETERS`/`SELECT-OPTIONS` — se
   confirmó leyendo el programa completo.
3. Al ser un report normal (no un módulo de diálogo), **no hizo falta
   depurar** para encontrar la cadena real: está directamente en
   `START-OF-SELECTION`, con llamadas explícitas a `CALL FUNCTION`.
4. Localizada la cadena real:
   - `ISU_S_EITERDK_SELECT_ALL` — selección de los documentos de
     impresión candidatos.
   - `EFG_GET_PRINT_PARAMETERS` — genera los parámetros de impresión
     (normalmente usado desde el botón "..." de la pantalla de
     selección, que abre un popup; tiene parámetros para suprimirlo).
   - `ISU_PRINT_EXPANDED` — motor real de impresión/envío.
   - `EFG_PRINT_CLOSE` — cierre del spool.
5. **SE37** sobre los 4 módulos anteriores:
   - Los 4 son **"Módulo de funciones normal"** (verificado en la
     pestaña Atributos) — no son de acceso remoto (RFC) ni de diálogo.
     Esto no es un problema: solo hace falta que el módulo RFC propio
     (`ZFI_FM_INVOICE_REPRINT`) sea RFC, no los módulos estándar que
     llama internamente (mismo patrón que los otros dos desarrollos).
   - `ISU_PRINT_EXPANDED`: de sus 4 parámetros de import, solo
     `X_PRINTPARAMS` es obligatorio.
   - `EFG_GET_PRINT_PARAMETERS`: tiene un parámetro `X_NO_DIALOG`
     ("Kennzeichen: Kein Dialog") pensado exactamente para evitar el
     popup de selección de impresora. También `X_SUPPRESS_BCI_DIALOG`
     (popup de email/fax) y `X_NO_ARCHIVE` (no ofrecer archivado). Sus
     4 parámetros de export (`Y_PRINTPARAMS`, `Y_ARCHIVE_INDEX`,
     `Y_ARCHIVE_PARAMS`, `Y_RECIPIENT`) encajan exactamente con los 4
     de import de `ISU_PRINT_EXPANDED`.

## Lo que NO se ha verificado todavía

- **Ejecución real**: nada de esta cadena se ha probado en SE37 contra
  el sistema — solo se ha leído el código fuente y comprobado la
  interfaz de los módulos en SE37, sin ejecutar ninguno.
- **`X_NO_DIALOG` + `X_SUPPRESS_BCI_DIALOG` + `X_NO_ARCHIVE` bastan de
  verdad** para que `EFG_GET_PRINT_PARAMETERS` no abra ningún diálogo:
  solo se ha comprobado que el parámetro existe con ese propósito
  declarado, no que el comportamiento real lo confirme.
- **Contenido de `XT_RANGES`** en `ISU_PRINT_EXPANDED`: en `REAPRIN0`
  lo construye la FORM `SET_PRINT_PARAMETERS`, cuyo código fuente no se
  ha leído todavía. Se ha aproximado en el RFC reutilizando el mismo
  rango de `OPBEL` de la selección, sin confirmar que sea correcto.
- **Lógica de negocio de `REAPRIN0` no replicada**: `dpp_check`
  (interlocutor bloqueado), `reversal_check` (documento ya
  anulado/reimpreso), bloqueos (`enqueue_ca`/`enqueue_bupa`) y
  actualización en BD tras imprimir (`print_updates`) — ninguna de
  estas FORMs se ha leído todavía, así que no están en la primera
  versión del RFC.
- **`X_INVOICED = 'X'`** en la selección: asumido para traer solo
  documentos de factura reales, no simulaciones — no verificado con un
  caso real.
- **`XT_ERGRD` vacío**: en la pantalla de EA60 el campo es obligatorio;
  aquí se asume que no hace falta al filtrar directamente por `OPBEL`
  — no verificado.

## Estimación de esfuerzo (para referencia interna)

Calibrado sobre el desarrollo de `ZFI_FM_PAYMENT_LOT_CLARIFY2` (~5 días
reales, con depuración incluida): al no haber hecho falta depurar aquí
(cadena encontrada leyendo código), la estimación se ajustó a 3 días.
Pendiente de confirmar con la prueba real en SE37 y con la lectura de
las FORMs pendientes listadas arriba.
