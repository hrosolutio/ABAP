*&---------------------------------------------------------------------*
*& Include          ZFI_R_ECOFI_SPLIT_EVE
*&---------------------------------------------------------------------*
* Mismo patron server/upload que ZFI_R_DEVOLUCIONES:
*   - p_server: procesa TODOS los ficheros que haya en la carpeta de la
*     ruta logica lcl_ecofi_split=>co_logical_path (a crear en SAP con
*     transaccion FILE, fisicamente la ruta AL11 correspondiente). No
*     hace falta indicar ningun fichero: P_PATH se oculta.
*   - p_upload: P_PATH es un fichero local, se sube/descarga via GUI
*     (para poder probar el programa desde tu PC).

SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME TITLE TEXT-002.

  PARAMETERS: p_server RADIOBUTTON GROUP g1 USER-COMMAND user DEFAULT 'X',
              p_upload RADIOBUTTON GROUP g1.

SELECTION-SCREEN END OF BLOCK b1.

SELECTION-SCREEN BEGIN OF BLOCK b2 WITH FRAME TITLE TEXT-001.

  PARAMETERS: p_path TYPE string LOWER CASE.

SELECTION-SCREEN END OF BLOCK b2.

AT SELECTION-SCREEN OUTPUT.
  LOOP AT SCREEN.
    IF screen-name CS 'P_PATH'.
      IF p_upload = 'X'.
        screen-active = '1'.
        screen-output = '1'.
        screen-input  = '1'.
      ELSE.
        screen-active = '0'.
        screen-output = '0'.
        screen-input  = '0'.
      ENDIF.
    ENDIF.
    MODIFY SCREEN.
  ENDLOOP.

AT SELECTION-SCREEN ON VALUE-REQUEST FOR p_path.

  CHECK p_upload = 'X'.

  DATA: lt_filetable TYPE filetable,
        lv_rc        TYPE i.

  cl_gui_frontend_services=>file_open_dialog(
    CHANGING file_table = lt_filetable
             rc         = lv_rc
    EXCEPTIONS OTHERS   = 5 ).

  IF sy-subrc = 0.
    p_path = VALUE #( lt_filetable[ 1 ]-filename OPTIONAL ).
  ENDIF.
