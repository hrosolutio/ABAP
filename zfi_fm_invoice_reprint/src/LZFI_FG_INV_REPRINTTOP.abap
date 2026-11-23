*&---------------------------------------------------------------------*
*& Include LZFI_FG_INV_REPRINTTOP                                      *
*& Grupo de función: ZFI_FG_INV_REPRINT                                *
*& Datos globales del pool de funciones                                *
*&---------------------------------------------------------------------*
FUNCTION-POOL zfi_fg_inv_reprint.

* ES_ERROR usa la estructura DDIC estándar ZFI_DE_XX_WS_ERROR (CODE,
* DESCRIPTION), reutilizada de los desarrollos ZFI_FM_PAYLOT_REVERSE /
* ZFI_FM_PAYMENT_LOT_CLARIFY2. A diferencia de esos dos, aquí se
* informa también en el caso OK (ver FM), por requisito de Diego:
* "hay que devolver el mensaje de SAP y el código de retorno, tanto
* en el OK como en el error".

* Localizado leyendo el programa REAPRIN0 (transacción EA60) SIN
* depurar (a diferencia de FP08/FPCPL, que sí hizo falta depurar para
* encontrar la cadena real). Valores observados/verificados en SE37:
CONSTANTS:
* Flags de EFG_GET_PRINT_PARAMETERS para que devuelva los parámetros
* de impresión sin abrir ningún popup (verificado en SE37: el
* parámetro X_NO_DIALOG existe con ese propósito exacto - "Kennzeichen:
* Kein Dialog"). X_SUPPRESS_BCI_DIALOG y X_NO_ARCHIVE añadidos por el
* mismo motivo (suprimir el popup de dirección de email/fax y no
* ofrecer archivado).
*
* PROBADO EN QA (23/11/2026): estos flags NO bastan por sí solos si no
* hay un dispositivo de salida (TDDEST) determinable - sin "propuesta"
* de dispositivo, EFG_GET_PRINT_PARAMETERS sigue abriendo el popup
* "Seleccionar parámetro impresión" pidiéndolo, aunque X_NO_DIALOG='X'.
  gc_true TYPE c VALUE 'X'.

* Dispositivo de salida usado como propuesta (X_PRINTPARAMS-TDDEST) al
* llamar EFG_GET_PRINT_PARAMETERS, para que no haga falta preguntarlo
* por pantalla. VALOR PROVISIONAL SOLO PARA PRUEBAS, visto disponible
* en el sistema QA - PENDIENTE DE DECISIÓN DE NEGOCIO: el servicio
* debería despachar por el canal real del cliente (email/portal, según
* SENDCONTROL de ISU_GET_ACC_ADRESS_DATA), no necesariamente imprimir
* en un dispositivo físico fijo. No usar este valor en producción sin
* confirmarlo.
CONSTANTS gc_dispositivo_salida TYPE rspopname VALUE 'LP01'.

