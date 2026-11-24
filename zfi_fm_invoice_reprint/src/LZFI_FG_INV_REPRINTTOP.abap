*&---------------------------------------------------------------------*
*& Include LZFI_FG_INV_REPRINTTOP                                      *
*& Grupo de función: ZFI_FG_INV_REPRINT                                *
*& Datos globales del pool de funciones                                *
*&---------------------------------------------------------------------*
FUNCTION-POOL zfi_fg_inv_reprint.

* ES_ERROR usa la estructura DDIC estándar ZFI_DE_XX_WS_ERROR (CODE,
* DESCRIPTION), reutilizada de los desarrollos ZFI_FM_PAYLOT_REVERSE /
* ZFI_FM_PAYMENT_LOT_CLARIFY2. Igual que en esos dos, solo se informa
* en el caso NOK (decisión explícita del usuario: en el OK se deja
* vacío, aunque Diego habló en general de "mensaje y código tanto en
* OK como en error" para los servicios de Ola 2).

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

* El dispositivo de salida (X_PRINTPARAMS-TDDEST) ya NO es una
* constante fija (antes 'LP01', valor de QA que no tiene por qué
* existir en otros sistemas) - se lee en tiempo de ejecución con
* GET PARAMETER ID 'PRI' (parámetro estándar SAP de "impresora por
* defecto del usuario", configurado en SU01 para el usuario técnico
* de MuleSoft en cada sistema, sin tocar código). Ver el FM.
*
* PENDIENTE DE DECISIÓN DE NEGOCIO: el servicio debería despachar por
* el canal real del cliente (email/portal, según SENDCONTROL de
* ISU_GET_ACC_ADRESS_DATA), no necesariamente imprimir en un
* dispositivo físico fijo - esto sigue sin resolver.

