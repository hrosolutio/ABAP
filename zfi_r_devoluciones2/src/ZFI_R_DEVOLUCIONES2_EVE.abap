*&---------------------------------------------------------------------*
*& Include          ZFI_R_DEVOLUCIONES2_EVE
*&---------------------------------------------------------------------*
* RU_03 no lee ningun fichero (los lotes ya los crea RU_02,
* ZFI_R_DEVOLUCIONES_CREA) - no hace falta pantalla de seleccion de
* fichero/modo. Unico parametro: simulacion, para poder ver que haria el
* programa (estado real de cada lote en DFKKRK-STARS) sin cerrar ni
* contabilizar nada de verdad.

SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME TITLE TEXT-001.

  PARAMETERS: p_simu AS CHECKBOX DEFAULT space.

SELECTION-SCREEN END OF BLOCK b1.
