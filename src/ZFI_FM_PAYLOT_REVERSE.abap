FUNCTION zfi_fm_paylot_reverse.
*"----------------------------------------------------------------------
*"*"Interfaz local:
*"  IMPORTING
*"     VALUE(I_DOCUMENTID) TYPE  OPBEL_KK
*"     VALUE(I_CANCELDATE) TYPE  BUDAT
*"     VALUE(I_CANCELREASON) TYPE  CHAR40
*"     VALUE(I_PROCESO) TYPE  CHAR20 DEFAULT 'CDI_11_03'
*"  EXPORTING
*"     VALUE(E_RESULT) TYPE  CHAR3
*"     VALUE(ES_ERROR) TYPE  ZFI_DE_XX_WS_ERROR
*"     VALUE(E_CANCELLEDDOCUMENTID) TYPE  OPBEL_KK
*"----------------------------------------------------------------------
* Anulación de transferencias contabilizadas en SAP (equivalente a FP08)
*
* Recibe un documento de pago generado en un lote de pago de
* transferencias y genera el documento de anulación correspondiente,
* llamando al módulo de función estándar FKK_CTRACPAYMINC_REVERSE.
*
* NOTA: interfaces de FKK_CALL_EVENT_1113 y FKK_CTRACPAYMINC_REVERSE
* verificadas contra SE37. FKK_CTRACPAYMINC_REVERSE NO devuelve el
* documento de anulación generado en ningún export (su único export es
* RETURN, tipo BAPIRET2) por lo que E_CANCELLEDDOCUMENTID queda
* pendiente de resolver (ver TODO en el paso 4).
*----------------------------------------------------------------------*

  DATA: lv_fikey  TYPE fkkko-fikey,
        ls_return TYPE bapiret2.

  CLEAR: e_result, es_error, e_cancelleddocumentid.

*----------------------------------------------------------------------*
* 1. Validación de parámetros obligatorios
*----------------------------------------------------------------------*
  IF i_documentid IS INITIAL.
    e_result              = 'NOK'.
    es_error-code         = 'PARAM_MISSING'.
    es_error-description  = 'I_DOCUMENTID es obligatorio'.
    RETURN.
  ENDIF.

  IF i_canceldate IS INITIAL.
    e_result              = 'NOK'.
    es_error-code         = 'PARAM_MISSING'.
    es_error-description  = 'I_CANCELDATE es obligatorio'.
    RETURN.
  ENDIF.

  IF i_cancelreason IS INITIAL.
    e_result              = 'NOK'.
    es_error-code         = 'PARAM_MISSING'.
    es_error-description  = 'I_CANCELREASON es obligatorio'.
    RETURN.
  ENDIF.

*----------------------------------------------------------------------*
* 2. El documento debe pertenecer a un lote de pago de transferencias
*    (no se anulan documentos que no estén incluidos en un lote, DFKKZP)
*----------------------------------------------------------------------*
  SELECT SINGLE opbel
    FROM dfkkzp
    INTO @DATA(lv_opbel_zp)
    WHERE opbel = @i_documentid.

  IF sy-subrc <> 0.
    e_result             = 'NOK'.
    es_error-code        = 'DOC_NOT_IN_PAYLOT'.
    es_error-description = |El documento { i_documentid } no está incluido en un lote de pago (DFKKZP)|.
    RETURN.
  ENDIF.

*----------------------------------------------------------------------*
* 3. Determinar/crear la clave de reconciliación (FIKEY) de la anulación
*    Se propone la clave y, si no existe, se crea mediante el módulo
*    de función estándar FKK_CALL_EVENT_1113 (según nota técnica del DF)
*
*    Firma verificada en SE37. I_UNAME es el único IMPORT obligatorio;
*    el resto (I_HERKF, I_APPLK, I_RESOB, I_RESKY, I_FIKEY, I_LAUFI,
*    I_LAUFD, I_PARALLEL_PROCESSING) es opcional.
*
*    TODO: confirmar con negocio/FI-CA si procede informar HERKF/APPLK
*    (origen del documento / área de aplicación) para este escenario de
*    anulación manual, según la configuración de eventos del cliente.
*----------------------------------------------------------------------*
  CALL FUNCTION 'FKK_CALL_EVENT_1113'
    EXPORTING
      i_uname = sy-uname
*     i_herkf = ''      " TODO: confirmar valor de configuración FI-CA
*     i_applk = ''      " TODO: confirmar valor de configuración FI-CA
    IMPORTING
      e_fikey = lv_fikey
    EXCEPTIONS
      OTHERS  = 1.

  IF sy-subrc <> 0 OR lv_fikey IS INITIAL.
    e_result             = 'NOK'.
    es_error-code        = 'FIKEY_ERROR'.
    es_error-description = 'No se ha podido determinar/crear la clave de reconciliación (FIKEY)'.
    RETURN.
  ENDIF.

* La creación de FIKEY se confirma en tareas de actualización (V1/V2) que
* solo se vuelcan a BD con COMMIT WORK. Sin este commit, FKK_CTRACPAYMINC_
* REVERSE falla con "Clave de reconciliación XXX no creada aún".
  COMMIT WORK AND WAIT.

*----------------------------------------------------------------------*
* 4. Anulación del documento contra el módulo de función estándar
*    CLEARREAS se informa siempre a '05' según nota técnica del DF,
*    con independencia del valor recibido en I_CANCELREASON.
*    Firma verificada en SE37: único export es RETURN (BAPIRET2), el
*    FM no devuelve el documento de anulación generado en ningún
*    parámetro de salida.
*----------------------------------------------------------------------*
  CALL FUNCTION 'FKK_CTRACPAYMINC_REVERSE'
    EXPORTING
      documentnumber = i_documentid
      doctype        = gc_doctype_anulacion
      clearreas      = gc_clearreas_anulacion
      fikey          = lv_fikey
      reversedate    = i_canceldate
    IMPORTING
      return         = ls_return.

  IF ls_return-type CA 'EA'.
    e_result             = 'NOK'.
    es_error-code        = ls_return-number.
    es_error-description = ls_return-message.
    RETURN.
  ENDIF.

  COMMIT WORK AND WAIT.

* TODO: FKK_CTRACPAYMINC_REVERSE no devuelve el documento de anulación
* generado. Pendiente de confirmar cómo obtenerlo, por ejemplo:
*  - si el número de documento viene en RETURN-MESSAGE_V1 (a comprobar
*    con una prueba real, viendo el mensaje de éxito que se genera), o
*  - releyendo DFKKZP/DFKKOP tras el COMMIT para el lote/posición de
*    I_DOCUMENTID y localizando el campo con el documento de anulación
*    (ver ejemplo del DF: columna "Nº doc.anul." en DFKKZP).
  e_result = 'OK'.

ENDFUNCTION.
