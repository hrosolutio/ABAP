*&---------------------------------------------------------------------*
*& Include          ZFI_R_EXTORNOS_EVE
*&---------------------------------------------------------------------*

SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME TITLE TEXT-001.

  PARAMETERS: p_server RADIOBUTTON GROUP g1 USER-COMMAND user DEFAULT 'X',
              p_upload RADIOBUTTON GROUP g1.

SELECTION-SCREEN END OF BLOCK b1.


SELECTION-SCREEN BEGIN OF BLOCK b2 WITH FRAME TITLE TEXT-003.

  PARAMETERS:    p_path   TYPE string LOWER CASE.
  SELECT-OPTIONS s_fileid FOR zfi_t_file_log-file_id. "NO-DISPLAY .

SELECTION-SCREEN END OF BLOCK b2.


SELECTION-SCREEN BEGIN OF BLOCK b3.
  PARAMETERS: p_path1 TYPE string NO-DISPLAY LOWER CASE,
              p_path2 TYPE string NO-DISPLAY LOWER CASE.

SELECTION-SCREEN END OF BLOCK b3.

AT SELECTION-SCREEN OUTPUT.
  LOOP AT SCREEN.
* Campo ruta de archivo
    IF screen-name CS 'P_PATH'.
      IF p_upload = 'X'.          " Se debe visualizar el campo
        screen-active = '1'.
        screen-output = '1'.
        screen-input  = '1'.
      ELSE.                       " Se oculta el campo
        screen-active = '0'.
        screen-output = '0'.
        screen-input  = '0'.
      ENDIF.
    ENDIF.
* Campo ID Fichero
    IF screen-name CS 'S_FILEID'.
      IF p_upload IS INITIAL.     " Se debe visualizar el campo
        screen-active = '1'.
        screen-output = '1'.
        screen-input  = '1'.
      ELSE.                       " Se oculta el campo
        screen-active = '0'.
        screen-output = '0'.
        screen-input  = '0'.
      ENDIF.
    ENDIF.
    MODIFY SCREEN.
  ENDLOOP.
