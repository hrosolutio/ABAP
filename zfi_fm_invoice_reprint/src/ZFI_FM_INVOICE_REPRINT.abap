FUNCTION zfi_fm_invoice_reprint.
*"----------------------------------------------------------------------
*"*"Interfaz local:
*"  IMPORTING
*"     VALUE(I_OPBEL) TYPE  OPBEL_KK
*"  EXPORTING
*"     VALUE(E_RESULT) TYPE  CHAR3
*"     VALUE(ES_ERROR) TYPE  ZFI_DE_XX_WS_ERROR
*"     VALUE(E_PDF) TYPE  XSTRING
*"----------------------------------------------------------------------
* NOTA: E_PDF es un parámetro NUEVO (24/11/2026) - hay que añadirlo a
* mano en la pestaña Export de SE37, este comentario no lo crea solo.
* Reimpresión / envío de duplicado de factura en SAP (equivalente a
* EA60, con la opción de reimprimir).
*
* ESTADO: PRIMERA VERSIÓN. A diferencia de FP08 y FPCPL, aquí NO ha
* hecho falta depurar para localizar la cadena real: se ha encontrado
* leyendo directamente el código fuente de EA60 (programa REAPRIN0,
* MODULE PAI_100 no aplica porque no es módulo de diálogo -> es un
* report normal con pantalla de selección estándar, START-OF-SELECTION).
* PENDIENTE DE PROBAR de principio a fin en SE37 (no probado todavía
* ni un solo paso de esta cadena contra el sistema real, a diferencia
* de FP08/FPCPL que sí tienen prueba real).
*
* Cadena localizada en REAPRIN0 (verificada leyendo el código, sin
* depurar):
*
*   ISU_S_EITERDK_SELECT_ALL  -> selecciona el/los documento(s) de
*                                 impresión candidatos (por OPBEL).
*                                 Verificado en SE37: módulo de
*                                 función normal (no RFC, no diálogo).
*   EFG_GET_PRINT_PARAMETERS  -> genera los parámetros de impresión
*                                 (Y_PRINTPARAMS/Y_ARCHIVE_INDEX/
*                                 Y_ARCHIVE_PARAMS/Y_RECIPIENT) sin
*                                 rellenarlos a mano. Tiene un
*                                 parámetro X_NO_DIALOG ("Kennzeichen:
*                                 Kein Dialog") pensado exactamente
*                                 para evitar el popup de selección de
*                                 impresora que abre en su uso normal
*                                 desde pantalla (botón "..." de
*                                 REAPRIN0). Añadidos también
*                                 X_SUPPRESS_BCI_DIALOG (popup de
*                                 email/fax) y X_NO_ARCHIVE (no ofrecer
*                                 archivado) por el mismo motivo.
*                                 PENDIENTE DE PROBAR que con estos
*                                 tres flags no salta ningún diálogo
*                                 con un caso real (solo verificado que
*                                 el parámetro existe, no que basta).
*   EFG_PRINT_EXPANDED        -> motor real de impresión/envío. NO
*                                 llamamos a ISU_PRINT_EXPANDED (que es
*                                 quien la llama normalmente) porque
*                                 ISU_PRINT_EXPANDED no devuelve el
*                                 documento generado (verificado en
*                                 SE37: su Export/Tablas solo repiten
*                                 los parámetros de entrada) - está
*                                 pensado para despachar a un
*                                 dispositivo/canal, no para devolver
*                                 datos. CAMBIO DE DISEÑO (24/11/2026):
*                                 MuleSoft no tiene impresora al otro
*                                 lado, necesita el PDF como dato, así
*                                 que llamamos directamente a
*                                 EFG_PRINT_EXPANDED (un nivel más
*                                 abajo en la cadena, confirmado por
*                                 depuración en QA), que sí expone
*                                 YT_OTF_DATA. Con X_PRINTPARAMS-
*                                 TDGETOTF = 'X' se le pide que no
*                                 imprima/envíe/visualice, solo que
*                                 devuelva el OTF - lo que además evita
*                                 el problema del dispositivo de salida
*                                 (no hace falta ninguno si no se va a
*                                 despachar). El OTF se convierte a PDF
*                                 con el conversor estándar CONVERT_OTF
*                                 + SCMS_BINARY_TO_XSTRING.
*
* CAMBIO DE DISEÑO (25/11/2026): el planteamiento de TDGETOTF de arriba
* se descartó tras depurar en QA toda la cadena real (EFG_PRINT ->
* función generada /1PWB/... -> SmartForm real /1BCDWB/SF00000005):
* GETOTF sí llega correctamente hasta el motor SmartForms y el
* formulario SÍ se genera (1 página), pero el resultado nunca se
* vuelca porque la tabla EFRM tiene OCL_CONTROL='X' (cierre diferido
* del formulario, para imprimir muchas facturas seguidas sin reabrir
* sesión) combinado con que EFG_GET_PRINT_PARAMETERS y
* EFG_PRINT_EXPANDED fuerzan siempre el dispositivo a PRINTER (ignoran
* cualquier otro valor) - esto hace que EFG_PRINT fuerce
* NO_CLOSE_FORM='X' en la llamada real, así que el CLOSE_FORM (quien
* vuelca el OTF) nunca se ejecuta. Y EFG_PRINT_CLOSE (pensado para
* ese cierre diferido) tampoco sirve para recuperarlo: su código
* fuente confirma que el resultado del cierre son variables locales
* sin ningún parámetro de export que las devuelva. Solución final:
* dejar que imprima de verdad a un spool (aunque sea a un dispositivo
* sin impresora física real, 'LOCL') y leer ESE spool con el conversor
* estándar CONVERT_ABAPSPOOLJOB_2_PDF - ver detalle en los pasos 3 y 5
* del código.
*
* NO VERIFICADO / PENDIENTE (a diferencia de REAPRIN0, que hace mucho
* más de lo que replica esta primera versión):
* - CONVERT_ABAPSPOOLJOB_2_PDF: interfaz verificada en SE37 (ver
*   comentario del paso 5), pero su comportamiento real no se ha
*   probado todavía contra este sistema en concreto.
* - XT_RANGES de EFG_PRINT_EXPANDED: tipo EFG_RANGES (verificado en
*   SE37). El CONTENIDO sigue siendo una aproximación: en REAPRIN0 lo
*   construye la FORM SET_PRINT_PARAMETERS, cuyo código fuente no se
*   ha visto todavía. Aquí se aproxima con un rango de OPBEL, sin
*   confirmar que sea el contenido correcto.
* - XT_RANGES1-9 y XT_RECIPIENT de EFG_PRINT_EXPANDED se dejan vacíos,
*   replicando lo que hace ISU_PRINT_EXPANDED internamente (no los
*   rellena tampoco) - asumido opcional, no confirmado.
* - dpp_check (bloqueo de interlocutor comercial), reversal_check
*   (documento ya anulado/reimpreso), enqueue_ca/enqueue_bupa
*   (bloqueos de cuenta/interlocutor) y print_updates (actualización en
*   BD tras imprimir) de REAPRIN0 NO están replicados en esta primera
*   versión - no se ha visto el código fuente de esas FORMs. Riesgo:
*   podría generarse un duplicado sin las validaciones de negocio que
*   sí aplica la transacción estándar (p.ej. interlocutor bloqueado).
* - X_INVOICED = 'X' en ISU_S_EITERDK_SELECT_ALL: asumido para
*   seleccionar solo documentos de factura reales (no simulaciones),
*   no verificado con un caso real.
* - XT_ERGRD se deja vacío (sin filtro): en la pantalla de EA60 el
*   campo ERGRD (Erstellungsgrund/motivo de creación) es obligatorio,
*   pero aquí se asume que, al identificar el documento por OPBEL
*   directamente, no hace falta como filtro adicional. No verificado.
*----------------------------------------------------------------------*

  DATA: lt_opbel     TYPE STANDARD TABLE OF isu_ranges,
        ls_opbel     TYPE isu_ranges,
        lt_efg_ranges TYPE STANDARD TABLE OF efg_ranges,
        ls_efg_ranges TYPE efg_ranges,
        lt_addressdata TYPE STANDARD TABLE OF isuaccaddrdata,
        ls_efrm      TYPE efrm,
        lt_eiterdk   TYPE STANDARD TABLE OF eiterdk,
        ls_eiterdk   TYPE eiterdk,
        ls_printparams  TYPE eprintparams,
        ls_archive_index TYPE toa_dara,
        ls_archive_params TYPE arc_params,
        ls_recipient TYPE swotobjid,
        ls_addressdata TYPE isuaccaddrdata,
        ls_header    TYPE rfgen-header,
        lt_efg_ranges_empty TYPE STANDARD TABLE OF efg_ranges,
        lt_pdf_lines TYPE STANDARD TABLE OF tline,
        lv_pdf_size  TYPE i,
        lt_spoolid   TYPE tsfspoolid,
        lv_spoolid   TYPE tsp01-rqident.

  CLEAR: e_result, es_error.

*----------------------------------------------------------------------*
* 1. Validación de parámetros obligatorios
*----------------------------------------------------------------------*
  IF i_opbel IS INITIAL.
    e_result             = 'NOK'.
    es_error-code        = '102'.
    es_error-description = 'I_OPBEL es obligatorio'.
    RETURN.
  ENDIF.

*----------------------------------------------------------------------*
* 2. Selección del documento de impresión (equivalente a la selección
*    de REAPRIN0, acotada a un único OPBEL)
*----------------------------------------------------------------------*
  CLEAR ls_opbel.
  ls_opbel-sign   = 'I'.
  ls_opbel-option = 'EQ'.
  ls_opbel-low    = i_opbel.
  APPEND ls_opbel TO lt_opbel.

  CALL FUNCTION 'ISU_S_EITERDK_SELECT_ALL'
    EXPORTING
      x_invoiced    = gc_true
    TABLES
      xt_opbel      = lt_opbel
      yt_eiterdk    = lt_eiterdk
    EXCEPTIONS
      not_found     = 1
      system_error  = 2
      not_qualified = 3
      OTHERS        = 4.

  IF sy-subrc = 1.
    e_result             = 'NOK'.
    es_error-code        = '102'.
    es_error-description = |No existe el documento de impresión { i_opbel }|.
    RETURN.
  ELSEIF sy-subrc <> 0.
    e_result             = 'NOK'.
    es_error-code        = |{ sy-subrc }|.
    IF sy-msgid IS NOT INITIAL.
      es_error-description = |Error SAP { sy-msgid } { sy-msgno } (tipo { sy-msgty })|.
    ELSE.
      es_error-description = |Error técnico en ISU_S_EITERDK_SELECT_ALL (sy-subrc { sy-subrc })|.
    ENDIF.
    RETURN.
  ENDIF.

  READ TABLE lt_eiterdk INTO ls_eiterdk INDEX 1.
  IF sy-subrc <> 0.
    e_result             = 'NOK'.
    es_error-code        = '102'.
    es_error-description = |No existe el documento de impresión { i_opbel }|.
    RETURN.
  ENDIF.

*----------------------------------------------------------------------*
* 2b. Control de dirección/envío de la cuenta contrato. Olvidado en la
*     primera versión (identificado en la investigación inicial de
*     REAPRIN0 como parte de la cadena real, pero no se llegó a
*     implementar) - causaba CALL_FUNCTION_PARM_MISSING en
*     ISU_PRINT_EXPANDED (XT_ADDRESSDATA) al faltar este paso.
*----------------------------------------------------------------------*
  CALL FUNCTION 'ISU_GET_ACC_ADRESS_DATA'
    EXPORTING
      x_doc_type     = '1'
      x_vkont        = ls_eiterdk-vkont
    TABLES
      yt_addressdata = lt_addressdata
    EXCEPTIONS
      not_found      = 1
      OTHERS         = 4.

  IF sy-subrc = 1.
    e_result             = 'NOK'.
    es_error-code        = '102'.
    IF sy-msgid IS NOT INITIAL.
      es_error-description = |Error SAP { sy-msgid } { sy-msgno } (tipo { sy-msgty })|.
    ELSE.
      es_error-description = |No se encontraron datos de dirección para la cuenta { ls_eiterdk-vkont }|.
    ENDIF.
    RETURN.
  ENDIF.
* sy-subrc = 4 (OTHERS) se ignora y se continúa, igual que en REAPRIN0
* (ahí solo deja un mensaje informativo, mac_msg_others, y no corta el
* proceso) - no se replica ese mensaje informativo aquí.

*----------------------------------------------------------------------*
* 3. Parámetros de impresión, sin diálogo (ver nota "EFG_GET_PRINT_
*    PARAMETERS" más arriba).
*
*    Ya NO se usa TDGETOTF (ver "CAMBIO DE DISEÑO 25/11/2026" en la
*    cabecera): dejamos que imprima de verdad a un spool. 'LOCL'
*    (constante gc_tddest_dummy, ver LZFI_FG_INV_REPRINTTOP) es un
*    dispositivo de usar y tirar, sin impresora física real detrás -
*    el spool se guarda en BD igualmente aunque el despacho físico no
*    llegue a ningún sitio.
*
*    TDNEWID='X' para asegurar que se genera un número de spool nuevo
*    y propio de esta llamada, no que se reutilice uno anterior.
*
*    LAST_DOC = 'Y' (ese valor exacto, visto en REAPRIN0, no 'X'):
*    señala que este es el último/único documento de la "tanda" -
*    sigue haciendo falta para que EFG_PRINT_CLOSE cierre/finalice de
*    verdad el spool (aunque, como se descubrió depurando, esa función
*    no sirve para recuperar el PDF en sí - solo para esto).
*----------------------------------------------------------------------*
  CLEAR ls_printparams.
  ls_printparams-tddest   = gc_tddest_dummy.
  ls_printparams-tdnewid  = gc_true.
  ls_printparams-last_doc = 'Y'.

  CALL FUNCTION 'EFG_GET_PRINT_PARAMETERS'
    EXPORTING
      x_printparams          = ls_printparams
      x_no_dialog            = gc_true
      x_suppress_bci_dialog  = gc_true
      x_no_archive           = gc_true
    IMPORTING
      y_printparams          = ls_printparams
      y_archive_index        = ls_archive_index
      y_archive_params       = ls_archive_params
      y_recipient            = ls_recipient
    EXCEPTIONS
      OTHERS                 = 1.

  IF sy-subrc <> 0.
    e_result             = 'NOK'.
    es_error-code        = |{ sy-subrc }|.
    IF sy-msgid IS NOT INITIAL.
      es_error-description = |Error SAP { sy-msgid } { sy-msgno } (tipo { sy-msgty })|.
    ELSE.
      es_error-description = |Error técnico en EFG_GET_PRINT_PARAMETERS (sy-subrc { sy-subrc })|.
    ENDIF.
    RETURN.
  ENDIF.

*----------------------------------------------------------------------*
* 3b. Formulario a usar. EFG_GET_PRINT_PARAMETERS no lo resuelve (es
*     específico del documento, no un dato genérico de impresión) -
*     causaba el mensaje EZ 823 "Parámetros X_PRINTPARAMS-FORMCLASS y
*     X_PRINTPARAMS-FORMKEY son iniciales al llamar MF EFG_PRINT" al
*     fallar más adentro, en EFG_PRINT (vía ISU_PRINT_EXPANDED ->
*     EFG_PRINT_EXPANDED -> EFG_PRINT). Localizado leyendo la FORM
*     SET_PRINT_PARAMETERS de REAPRIN0 (antes sin ver su código):
*     FORMKEY sale directo de EITERDK-FORMKEY, y FORMCLASS se obtiene
*     llamando a EFG_DB_EFRM_SELECT con ese FORMKEY.
*----------------------------------------------------------------------*
  ls_printparams-formkey = ls_eiterdk-formkey.
  ls_printparams-langu   = ls_eiterdk-langu.

  CALL FUNCTION 'EFG_DB_EFRM_SELECT'
    EXPORTING
      x_formkey     = ls_eiterdk-formkey
    IMPORTING
      y_efrm        = ls_efrm
    EXCEPTIONS
      not_found     = 1
      not_qualified = 4
      OTHERS        = 5.

  IF sy-subrc <> 0.
    e_result             = 'NOK'.
    es_error-code        = |{ sy-subrc }|.
    IF sy-msgid IS NOT INITIAL.
      es_error-description = |Error SAP { sy-msgid } { sy-msgno } (tipo { sy-msgty })|.
    ELSE.
      es_error-description = |No se determinó formulario, FORMKEY { ls_eiterdk-formkey }|.
    ENDIF.
    RETURN.
  ENDIF.

  ls_printparams-formclass = ls_efrm-formclass.

*----------------------------------------------------------------------*
* 4. Impresión del documento, llamando directamente a
*    EFG_PRINT_EXPANDED (no a ISU_PRINT_EXPANDED, ver nota de cabecera)
*    - un documento por cada dirección/destinatario de LT_ADDRESSDATA,
*    replicando el bucle que hace ISU_PRINT_EXPANDED internamente.
*    Normalmente una sola fila (un destinatario principal). Ya no se
*    recoge Y_PDF_RESULT/Y_SF_RESULT/YT_OTF_DATA aquí (ver "CAMBIO DE
*    DISEÑO 25/11/2026" en la cabecera) - el documento se recupera
*    después, en el paso 5, a partir del spool generado.
*
*    XT_RANGES usa el tipo EFG_RANGES (estructura SIGN/OPTION/LOW/HIGH,
*    LOW y HIGH tipo TVARV_VAL), distinto de ISU_RANGES usado en la
*    selección del paso 2 - verificado en SE37. XT_RANGES1-9 y
*    XT_RECIPIENT se dejan vacíos (ver nota de cabecera, no
*    verificado).
*
*    X_HEADER es RFGEN-HEADER (verificado en SE37, dump real
*    CALL_FUNCTION_CONFLICT_TYPE al asumir antes que era ISUACCADDRDATA
*    solo por ver "l_header = xt_addressdata" en REAPRIN0 - ese era un
*    MOVE clásico entre tipos distintos por compatibilidad de memoria,
*    no implica que compartan tipo). Se replica el mismo MOVE (mismo
*    volcado de bytes que REAPRIN0), ahora con el tipo correcto
*    declarado para que la interfaz tipada de la función lo acepte.
*----------------------------------------------------------------------*
  CLEAR ls_efg_ranges.
  ls_efg_ranges-sign   = 'I'.
  ls_efg_ranges-option = 'EQ'.
  ls_efg_ranges-low    = i_opbel.
  APPEND ls_efg_ranges TO lt_efg_ranges.

  LOOP AT lt_addressdata INTO ls_addressdata.
    ls_header = ls_addressdata.

    CALL FUNCTION 'EFG_PRINT_EXPANDED'
      EXPORTING
        x_header            = ls_header
        x_sendcontrol       = ls_addressdata-sendcontrol
        x_rec_addr          = ls_addressdata-addrnumber
        x_rec_persnumber    = ls_addressdata-persnumber
        x_printparams       = ls_printparams
        x_archive_params    = ls_archive_params
        x_archive_index     = ls_archive_index
        x_recipient         = ls_recipient
      IMPORTING
        y_printparams       = ls_printparams
      TABLES
        xt_ranges           = lt_efg_ranges
        xt_ranges1          = lt_efg_ranges_empty
        xt_ranges2          = lt_efg_ranges_empty
        xt_ranges3          = lt_efg_ranges_empty
        xt_ranges4          = lt_efg_ranges_empty
        xt_ranges5          = lt_efg_ranges_empty
        xt_ranges6          = lt_efg_ranges_empty
        xt_ranges7          = lt_efg_ranges_empty
        xt_ranges8          = lt_efg_ranges_empty
        xt_ranges9          = lt_efg_ranges_empty
      EXCEPTIONS
        not_qualified       = 1
        print_failed        = 3
        cancelled           = 4
        rec_addr_not_found  = 5
        send_addr_not_found = 6
        OTHERS              = 7.

    IF sy-subrc <> 0.
      e_result             = 'NOK'.
      es_error-code        = |{ sy-subrc }|.
      IF sy-msgid IS NOT INITIAL.
        es_error-description = |Error SAP { sy-msgid } { sy-msgno } (tipo { sy-msgty })|.
      ELSE.
        es_error-description = |Error técnico en EFG_PRINT_EXPANDED (sy-subrc { sy-subrc })|.
      ENDIF.
      RETURN.
    ENDIF.
  ENDLOOP.

*----------------------------------------------------------------------*
* 4b. Cerrar/finalizar el formulario y el spool. Necesario (ver "CAMBIO
*     DE DISEÑO 25/11/2026" en la cabecera): el formulario tiene
*     OCL_CONTROL='X' en EFRM, que difiere el cierre real del spool -
*     sin esta llamada, el spool podría quedar sin finalizar.
*
*     A diferencia del intento anterior (que ignoraba todo lo que
*     devolvía esta función, pensando que no exponía nada útil), ahora
*     SÍ recogemos Y_TAB_SPOOLID: confirmado en su código fuente que
*     EFG_PRINT_CLOSE nunca devuelve el documento en sí (sus
*     variables de resultado son locales, sin parámetro de export),
*     pero sí la lista de números de spool generados - que es lo que
*     necesitamos para el paso 5.
*
*     X_FLG_OUTPUT = space (no gc_true): no queremos que espere a que
*     termine un despacho físico real, solo que finalice/cierre el
*     spool - no verificado que este sea el valor correcto para eso.
*----------------------------------------------------------------------*
  CALL FUNCTION 'EFG_PRINT_CLOSE'
    EXPORTING
      x_flg_output         = space
      x_flg_finalize       = gc_true
      x_flg_clear_spoolids = gc_true
    IMPORTING
      y_tab_spoolid        = lt_spoolid
    EXCEPTIONS
      OTHERS               = 1.

  IF sy-subrc <> 0.
    e_result             = 'NOK'.
    es_error-code        = |{ sy-subrc }|.
    IF sy-msgid IS NOT INITIAL.
      es_error-description = |Error SAP { sy-msgid } { sy-msgno } (tipo { sy-msgty })|.
    ELSE.
      es_error-description = |Error técnico en EFG_PRINT_CLOSE (sy-subrc { sy-subrc })|.
    ENDIF.
    RETURN.
  ENDIF.

  READ TABLE lt_spoolid INTO lv_spoolid INDEX 1.
  IF sy-subrc <> 0.
    e_result             = 'NOK'.
    es_error-code        = '102'.
    es_error-description = 'EFG_PRINT_CLOSE no generó ningún spool para el documento'.
    RETURN.
  ENDIF.

*----------------------------------------------------------------------*
* 5. Obtención del PDF a partir del spool ya cerrado (ver "CAMBIO DE
*    DISEÑO 25/11/2026" en la cabecera). CONVERT_ABAPSPOOLJOB_2_PDF es
*    el conversor estándar de spool a PDF - no depende de nada de la
*    cadena EFG_PRINT/SmartForm en sí, solo lee el spool ya cerrado.
*    BIN_FILE devuelve directamente un XSTRING (verificado en SE37);
*    si viniera vacío, se recurre a la tabla PDF (líneas binarias,
*    TLINE) con el mismo conversor SCMS_BINARY_TO_XSTRING ya usado en
*    el camino OTF anterior (ahora descartado).
*----------------------------------------------------------------------*
  CALL FUNCTION 'CONVERT_ABAPSPOOLJOB_2_PDF'
    EXPORTING
      src_spoolid              = lv_spoolid
      no_dialog                = gc_true
    IMPORTING
      pdf_bytecount             = lv_pdf_size
      bin_file                  = e_pdf
    TABLES
      pdf                       = lt_pdf_lines
    EXCEPTIONS
      err_no_abap_spooljob      = 1
      err_no_spooljob           = 2
      err_no_permission         = 3
      err_conv_not_possible     = 4
      err_bad_destdevice        = 5
      user_cancelled            = 6
      err_spoolerror            = 7
      err_temseerror            = 8
      err_btcjob_open_failed    = 9
      err_btcjob_submit_failed  = 10
      err_btcjob_close_failed   = 11
      OTHERS                    = 99.

  IF sy-subrc <> 0.
    e_result             = 'NOK'.
    es_error-code        = |{ sy-subrc }|.
    IF sy-msgid IS NOT INITIAL.
      es_error-description = |Error SAP { sy-msgid } { sy-msgno } (tipo { sy-msgty })|.
    ELSE.
      es_error-description = |Error técnico en CONVERT_ABAPSPOOLJOB_2_PDF (sy-subrc { sy-subrc })|.
    ENDIF.
    RETURN.
  ENDIF.

  IF e_pdf IS INITIAL AND lt_pdf_lines IS NOT INITIAL.
    CALL FUNCTION 'SCMS_BINARY_TO_XSTRING'
      EXPORTING
        input_length = lv_pdf_size
      IMPORTING
        buffer       = e_pdf
      TABLES
        binary_tab   = lt_pdf_lines
      EXCEPTIONS
        failed       = 1
        OTHERS       = 2.

    IF sy-subrc <> 0.
      e_result             = 'NOK'.
      es_error-code        = |{ sy-subrc }|.
      es_error-description = |Error técnico en SCMS_BINARY_TO_XSTRING (sy-subrc { sy-subrc })|.
      RETURN.
    ENDIF.
  ENDIF.

  IF e_pdf IS INITIAL.
    e_result             = 'NOK'.
    es_error-code        = '102'.
    es_error-description = 'No se pudo obtener el contenido del PDF del spool'.
    RETURN.
  ENDIF.

*----------------------------------------------------------------------*
* 6. Resultado OK. Decisión del usuario: en el caso OK no se rellena
*    ES_ERROR (queda vacío, ya limpiado al principio de la función).
*    Sin COMMIT WORK: con el cambio de diseño (generar PDF, no
*    despachar) esta llamada no contabiliza/actualiza nada en BD.
*----------------------------------------------------------------------*
  e_result = 'OK'.

ENDFUNCTION.
