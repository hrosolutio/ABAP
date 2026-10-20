*&---------------------------------------------------------------------*
*& Include          ZFI_R_DEVOLUCIONES2_EVE
*&---------------------------------------------------------------------*
* El DF no define ningun mecanismo automatico para saber que lotes hay
* pendientes de cerrar/contabilizar - se indican a mano aqui (S_KEYR1),
* igual que en FP09. P_SIMU: ver el STARS actual de cada lote indicado
* sin cerrar ni contabilizar nada de verdad.
*
* P_RFC (NO-DISPLAY, no sale en la pantalla de seleccion): senal
* explicita de que la llamada viene de ZFI_FM_DEVOLUCIONES2 via SUBMIT
* ... WITH SELECTION-TABLE (esa RFC rellena esta fila con 'X'). Sirve
* para exportar el detalle de errores a memoria ABAP (ver
* ZFI_R_DEVOLUCIONES2_CLS, EXPORT_POST_ERRORS) solo cuando hace falta -
* SY-CALLD se probo primero y se descarto: no distingue de forma
* fiable esta llamada de una ejecucion manual en SE38 (el propio
* "Ejecutar" de SE38 tambien lo deja a 'X').

SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME TITLE TEXT-001.

  SELECT-OPTIONS: s_keyr1 FOR dfkkrk-keyr1 OBLIGATORY.
  PARAMETERS:     p_simu AS CHECKBOX DEFAULT space.

SELECTION-SCREEN END OF BLOCK b1.

PARAMETERS: p_rfc TYPE char1 NO-DISPLAY.
