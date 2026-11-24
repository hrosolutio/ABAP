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
* NO VERIFICADO / PENDIENTE (a diferencia de REAPRIN0, que hace mucho
* más de lo que replica esta primera versión):
* - Que X_PRINTPARAMS-TDGETOTF='X' realmente evite pedir un
*   dispositivo de salida (hipótesis razonada, no probada todavía).
* - Nombres exactos de parámetros de CONVERT_OTF y
*   SCMS_BINARY_TO_XSTRING: son módulos muy estándar y conocidos, pero
*   no se han verificado en SE37 contra este sistema en concreto.
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
        lt_otf_data  TYPE STANDARD TABLE OF itcoo,
        lt_pdf_lines TYPE STANDARD TABLE OF tline,
        lv_pdf_size  TYPE i,
        ls_pdf_result TYPE efg_strn_pdf_result.

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
*    PARAMETERS" más arriba). Con TDGETOTF='X' se le pide a la cadena
*    que NO despache a ningún sitio, solo que devuelva el documento
*    (OTF) como dato.
*
*    PROBADO EN QA (24/11/2026): TDGETOTF NO evita el popup de
*    selección de dispositivo de salida - sigue siendo obligatorio.
*    Como el documento nunca llega a despacharse de verdad (TDGETOTF
*    lo intercepta antes), se usa 'LOCL' (constante
*    gc_tddest_dummy, ver LZFI_FG_INV_REPRINTTOP) como valor de
*    usar y tirar, solo para que el campo no esté vacío.
*----------------------------------------------------------------------*
  CLEAR ls_printparams.
  ls_printparams-tdgetotf = gc_true.
  ls_printparams-tddest   = gc_tddest_dummy.

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
* 4. Generación del documento (OTF), llamando directamente a
*    EFG_PRINT_EXPANDED (no a ISU_PRINT_EXPANDED, ver nota de cabecera)
*    - un documento por cada dirección/destinatario de LT_ADDRESSDATA,
*    replicando el bucle que hace ISU_PRINT_EXPANDED internamente.
*    Normalmente una sola fila (un destinatario principal).
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
        y_pdf_result        = ls_pdf_result
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
        yt_otf_data         = lt_otf_data
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
* 5. Obtención del PDF. Dos caminos posibles, según si el formulario es
*    PDF-based (Adobe Forms) o SAPscript/SmartForms clásico - no se
*    sabe de antemano cuál es, así que se comprueban los dos:
*    - Si Y_PDF_RESULT-STR_RESULT_FORM-PDF viene relleno (formulario
*      PDF-based): se usa directamente, ya es el PDF en bruto
*      (verificado en SE11: FPFORMOUTPUT-PDF es FPCONTENT, un
*      RAWSTRING - compatible con XSTRING sin conversión).
*    - Si no, y YT_OTF_DATA sí viene relleno (formulario clásico): se
*      convierte con los módulos estándar CONVERT_OTF +
*      SCMS_BINARY_TO_XSTRING (muy conocidos, no verificados en SE37
*      contra este sistema en concreto).
*----------------------------------------------------------------------*
  IF ls_pdf_result-str_result_form-pdf IS NOT INITIAL.
    e_pdf = ls_pdf_result-str_result_form-pdf.
    e_result = 'OK'.
    RETURN.
  ENDIF.

  IF lt_otf_data IS INITIAL.
    e_result             = 'NOK'.
    es_error-code        = '102'.
    es_error-description = 'EFG_PRINT_EXPANDED no devolvió ni PDF ni OTF del documento'.
    RETURN.
  ENDIF.

  CALL FUNCTION 'CONVERT_OTF'
    EXPORTING
      format                = 'PDF'
    IMPORTING
      bin_filesize          = lv_pdf_size
    TABLES
      otf                   = lt_otf_data
      lines                 = lt_pdf_lines
    EXCEPTIONS
      err_max_linewidth     = 1
      err_format            = 2
      err_conv_not_possible = 3
      err_bad_otf           = 4
      OTHERS                = 5.

  IF sy-subrc <> 0.
    e_result             = 'NOK'.
    es_error-code        = |{ sy-subrc }|.
    es_error-description = |Error técnico en CONVERT_OTF (sy-subrc { sy-subrc })|.
    RETURN.
  ENDIF.

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

*----------------------------------------------------------------------*
* 6. Resultado OK. Decisión del usuario: en el caso OK no se rellena
*    ES_ERROR (queda vacío, ya limpiado al principio de la función).
*    Sin COMMIT WORK: con el cambio de diseño (generar PDF, no
*    despachar) esta llamada no contabiliza/actualiza nada en BD.
*----------------------------------------------------------------------*
  e_result = 'OK'.

ENDFUNCTION.
