*&---------------------------------------------------------------------*
*& Include          ZFI_R_DEVOLUCIONES2_EVE
*&---------------------------------------------------------------------*
* El DF no define ningun mecanismo automatico para saber que lotes hay
* pendientes de cerrar/contabilizar - se indican a mano aqui (S_KEYR1),
* igual que en FP09. P_SIMU: ver el STARS actual de cada lote indicado
* sin cerrar ni contabilizar nada de verdad.

SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME TITLE TEXT-001.

  SELECT-OPTIONS: s_keyr1 FOR dfkkrk-keyr1 OBLIGATORY.
  PARAMETERS:     p_simu AS CHECKBOX DEFAULT space.

SELECTION-SCREEN END OF BLOCK b1.
