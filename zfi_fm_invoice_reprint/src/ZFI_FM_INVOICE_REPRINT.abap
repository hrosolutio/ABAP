FUNCTION zfi_fm_invoice_reprint.
*"----------------------------------------------------------------------
*"*"Interfaz local:
*"  IMPORTING
*"     VALUE(I_OPBEL) TYPE  OPBEL_KK
*"  EXPORTING
*"     VALUE(E_RESULT) TYPE  CHAR3
*"     VALUE(ES_ERROR) TYPE  ZFI_DE_XX_WS_ERROR
*"----------------------------------------------------------------------
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
*   ISU_PRINT_EXPANDED        -> motor real de impresión/envío.
*                                 Verificado en SE37: módulo de función
*                                 normal. De sus 4 parámetros de
*                                 import, solo X_PRINTPARAMS es
*                                 obligatorio; X_ARCHIVE_PARAMS,
*                                 X_ARCHIVE_INDEX y X_RECIPIENT son
*                                 opcionales - se pasan igualmente aquí
*                                 porque salen ya calculados de
*                                 EFG_GET_PRINT_PARAMETERS sin coste
*                                 extra.
*   EFG_PRINT_CLOSE           -> cierra el spool generado.
*
* NO VERIFICADO / PENDIENTE (a diferencia de REAPRIN0, que hace mucho
* más de lo que replica esta primera versión):
* - XT_RANGES de ISU_PRINT_EXPANDED: en REAPRIN0 lo construye la FORM
*   SET_PRINT_PARAMETERS, cuyo código fuente no se ha visto todavía.
*   Aquí se aproxima reutilizando el mismo rango de OPBEL usado para
*   la selección (mismo dato, no verificado que sea correcto para
*   ISU_PRINT_EXPANDED). REVISAR contra el código de SET_PRINT_PARAMETERS
*   o probando en SE37 si genera el duplicado del documento correcto.
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

  DATA: lt_opbel     TYPE RANGE OF opbel_kk,
        ls_opbel     LIKE LINE OF lt_opbel,
        lt_eiterdk   TYPE STANDARD TABLE OF eiterdk,
        ls_eiterdk   TYPE eiterdk,
        ls_printparams  TYPE eprintparams,
        ls_archive_index TYPE toa_dara,
        ls_archive_params TYPE arc_params,
        ls_recipient TYPE swotobjid.

  CLEAR: e_result, es_error.

*----------------------------------------------------------------------*
* 1. Validación de parámetros obligatorios
*----------------------------------------------------------------------*
  IF i_opbel IS INITIAL.
    e_result             = 'NOK'.
    es_error-code        = 'PARAM_MISSING'.
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
    es_error-code        = 'DOC_NOT_FOUND'.
    es_error-description = |No existe el documento de impresión { i_opbel }|.
    RETURN.
  ELSEIF sy-subrc <> 0.
    e_result             = 'NOK'.
    es_error-code        = |{ sy-subrc }|.
    MESSAGE ID sy-msgid TYPE sy-msgty NUMBER sy-msgno
      INTO es_error-description
      WITH sy-msgv1 sy-msgv2 sy-msgv3 sy-msgv4.
    RETURN.
  ENDIF.

  READ TABLE lt_eiterdk INTO ls_eiterdk INDEX 1.
  IF sy-subrc <> 0.
    e_result             = 'NOK'.
    es_error-code        = 'DOC_NOT_FOUND'.
    es_error-description = |No existe el documento de impresión { i_opbel }|.
    RETURN.
  ENDIF.

*----------------------------------------------------------------------*
* 3. Parámetros de impresión, sin diálogo (ver nota "EFG_GET_PRINT_
*    PARAMETERS" más arriba)
*----------------------------------------------------------------------*
  CALL FUNCTION 'EFG_GET_PRINT_PARAMETERS'
    EXPORTING
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
    MESSAGE ID sy-msgid TYPE sy-msgty NUMBER sy-msgno
      INTO es_error-description
      WITH sy-msgv1 sy-msgv2 sy-msgv3 sy-msgv4.
    RETURN.
  ENDIF.

*----------------------------------------------------------------------*
* 4. Reimpresión / envío del duplicado
*----------------------------------------------------------------------*
  CALL FUNCTION 'ISU_PRINT_EXPANDED'
    EXPORTING
      x_printparams    = ls_printparams
      x_archive_params = ls_archive_params
      x_archive_index  = ls_archive_index
      x_recipient      = ls_recipient
    TABLES
      xt_ranges        = lt_opbel
    EXCEPTIONS
      failed           = 1
      OTHERS           = 2.

  IF sy-subrc <> 0.
    e_result             = 'NOK'.
    es_error-code        = |{ sy-subrc }|.
    MESSAGE ID sy-msgid TYPE sy-msgty NUMBER sy-msgno
      INTO es_error-description
      WITH sy-msgv1 sy-msgv2 sy-msgv3 sy-msgv4.
    RETURN.
  ENDIF.

*----------------------------------------------------------------------*
* 5. Cerrar el spool generado
*----------------------------------------------------------------------*
  CALL FUNCTION 'EFG_PRINT_CLOSE'
    EXPORTING
      x_flg_output         = gc_true
      x_flg_finalize       = gc_true
      x_flg_clear_spoolids = gc_true
    EXCEPTIONS
      OTHERS               = 1.

  IF sy-subrc <> 0.
    e_result             = 'NOK'.
    es_error-code        = |{ sy-subrc }|.
    MESSAGE ID sy-msgid TYPE sy-msgty NUMBER sy-msgno
      INTO es_error-description
      WITH sy-msgv1 sy-msgv2 sy-msgv3 sy-msgv4.
    RETURN.
  ENDIF.

  COMMIT WORK AND WAIT.

*----------------------------------------------------------------------*
* 6. Resultado OK. Por requisito de Diego, se informa mensaje y código
*    también en el caso OK, no solo en el de error. PENDIENTE DE
*    VERIFICAR si alguno de los FM anteriores deja sy-msgid/sy-msgno
*    informados en el caso de éxito (no comprobado todavía); si no los
*    deja, se usa un texto fijo de confirmación.
*----------------------------------------------------------------------*
  e_result      = 'OK'.
  es_error-code = 'OK'.
  IF sy-msgid IS NOT INITIAL.
    MESSAGE ID sy-msgid TYPE sy-msgty NUMBER sy-msgno
      INTO es_error-description
      WITH sy-msgv1 sy-msgv2 sy-msgv3 sy-msgv4.
  ELSE.
    es_error-description = |Duplicado del documento { i_opbel } generado correctamente|.
  ENDIF.

ENDFUNCTION.
