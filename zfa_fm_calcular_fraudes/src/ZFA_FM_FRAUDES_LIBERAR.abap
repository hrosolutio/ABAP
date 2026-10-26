FUNCTION zfa_fm_fraudes_liberar.
*"----------------------------------------------------------------------
*"*"Interfase local
*"  IMPORTING
*"     VALUE(IV_OPBEL) TYPE  OPBEL_KK
*"  EXPORTING
*"     VALUE(EV_NEW_OPBEL) TYPE  OPBEL_KK
*"     VALUE(EV_SUBRC) TYPE  SYSUBRC
*"     VALUE(EV_MENSAJE) TYPE  BAPI_MSG
*"----------------------------------------------------------------------
* Libera una factura apartada (EA05) desde ZCL_FA_CALCULO_FRAUDES.
*
* Módulo de acceso remoto: la clase lo llama con DESTINATION 'NONE' para
* que la liberación vaya en una sesión nueva. En la misma sesión que la
* facturación, ISU_OUTSORT_INVOICE_RELEASE da SYSTEM_ERROR; en una sesión
* limpia (como la EA05 o la SE37) libera bien.
*----------------------------------------------------------------------*

  CLEAR: ev_new_opbel, ev_subrc, ev_mensaje.

  " Igual que la EA05 (FORM release_doc_inv): sin clave de reconciliación
  " ni fechas. Hace COMMIT él mismo.
  CALL FUNCTION 'ISU_OUTSORT_INVOICE_RELEASE'
    EXPORTING
      x_opbel       = iv_opbel
      x_create_log  = abap_true
    IMPORTING
      y_new_opbel   = ev_new_opbel
    EXCEPTIONS
      not_found     = 1
      foreign_lock  = 2
      system_error  = 3
      error_message = 4
      OTHERS        = 5.
  ev_subrc = sy-subrc.
  IF ev_subrc <> 0 AND sy-msgid IS NOT INITIAL.
    MESSAGE ID sy-msgid TYPE 'E' NUMBER sy-msgno
      WITH sy-msgv1 sy-msgv2 sy-msgv3 sy-msgv4 INTO ev_mensaje.
    ev_mensaje = |{ sy-msgid } { sy-msgno } { ev_mensaje }|.
  ENDIF.

ENDFUNCTION.
