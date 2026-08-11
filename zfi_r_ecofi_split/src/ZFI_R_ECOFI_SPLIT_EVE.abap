*&---------------------------------------------------------------------*
*& Include          ZFI_R_ECOFI_SPLIT_EVE
*&---------------------------------------------------------------------*
* Modo local (GUI upload/download), para poder probar el programa
* directamente en SE38 contra un fichero ECOFI real. El modo servidor
* (lectura/escritura en la ruta AL11 de forma automatica) esta pendiente
* de disenar con el cliente - ver README "Pendiente / a definir".

SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME TITLE TEXT-001.

  PARAMETERS: p_path TYPE string LOWER CASE OBLIGATORY.

SELECTION-SCREEN END OF BLOCK b1.

AT SELECTION-SCREEN ON VALUE-REQUEST FOR p_path.

  DATA: lt_filetable TYPE filetable,
        lv_rc        TYPE i.

  cl_gui_frontend_services=>file_open_dialog(
    CHANGING file_table = lt_filetable
             rc         = lv_rc
    EXCEPTIONS OTHERS   = 5 ).

  IF sy-subrc = 0.
    p_path = VALUE #( lt_filetable[ 1 ]-filename OPTIONAL ).
  ENDIF.
