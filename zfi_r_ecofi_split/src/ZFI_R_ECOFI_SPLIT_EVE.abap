*&---------------------------------------------------------------------*
*& Include          ZFI_R_ECOFI_SPLIT_EVE
*&---------------------------------------------------------------------*
* Mismo patron server/upload que ZFI_R_DEVOLUCIONES:
*   - p_server: P_PATH es una ruta del servidor de aplicaciones
*     (OPEN DATASET). Pensado para la ejecucion automatica/por job
*     contra la ruta AL11 (ver README "Pendiente / a definir": aun no
*     hay job ni logica de disparo automatico, hay que indicar la ruta
*     a mano).
*   - p_upload: P_PATH es un fichero local, se sube/descarga via GUI
*     (para poder probar el programa desde tu PC).

SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME TITLE TEXT-002.

  PARAMETERS: p_server RADIOBUTTON GROUP g1 USER-COMMAND user DEFAULT 'X',
              p_upload RADIOBUTTON GROUP g1.

SELECTION-SCREEN END OF BLOCK b1.

SELECTION-SCREEN BEGIN OF BLOCK b2 WITH FRAME TITLE TEXT-001.

  PARAMETERS: p_path TYPE string LOWER CASE OBLIGATORY.

SELECTION-SCREEN END OF BLOCK b2.

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
