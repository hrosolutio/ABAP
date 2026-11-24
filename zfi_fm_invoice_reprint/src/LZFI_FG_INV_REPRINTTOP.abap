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
  gc_true TYPE c VALUE 'X'.

* CAMBIO DE DISEÑO (24/11/2026): MuleSoft no tiene impresora al otro
* lado - lo que necesita es el PDF como dato, no que se despache a
* ningún sitio. Se usa X_PRINTPARAMS-TDGETOTF = 'X' ("devuélveme el
* OTF, sin imprimir/visualizar/enviar"), llamando directamente a
* EFG_PRINT_EXPANDED (no a ISU_PRINT_EXPANDED, que no devuelve el
* documento) y convirtiendo el OTF a PDF con CONVERT_OTF +
* SCMS_BINARY_TO_XSTRING. Ver el FM para el detalle completo.
*
* PROBADO EN QA (24/11/2026): TDGETOTF NO evita que
* EFG_GET_PRINT_PARAMETERS siga pidiendo un dispositivo de salida
* (TDDEST) por popup - sigue siendo obligatorio aunque no se vaya a
* usar para despachar de verdad. Como el documento nunca llega a
* despacharse (TDGETOTF lo intercepta antes), no hace falta que sea un
* dispositivo real ni correcto - solo que el campo no esté vacío. Se
* usa 'LOCL' ("impresora local"), que existe por defecto en cualquier
* instalación estándar de SAP (a diferencia de 'LP01', que era
* específico de QA) - es un valor de usar y tirar, nunca se imprime
* ahí de verdad.
  gc_tddest_dummy TYPE rspopname VALUE 'LOCL'.

* Historial descartado antes de llegar a esta solución (dispositivo de
* salida fijo para poder despachar de verdad): constante fija ('LP01'
* de QA, no portable), GET PARAMETER ID 'PRI' (probado en QA, no
* funciona), tabla de customizing Z propia (descartada por decisión
* del usuario).
