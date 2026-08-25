*&---------------------------------------------------------------------*
*& Include          ZFI_R_DEVOLUCIONES2_EVE
*&---------------------------------------------------------------------*
* RU_03 no lee ningun fichero (los lotes ya los crea RU_02,
* ZFI_R_DEVOLUCIONES_CREA) - no hace falta pantalla de seleccion de
* fichero/modo. S_KEYR1 opcional: en blanco procesa todos los lotes
* pendientes (uso normal, automatico); relleno, solo esos (pruebas o
* reproceso puntual de un lote concreto). P_SIMU: ver que haria el
* programa (estado real de cada lote en DFKKRK-STARS) sin cerrar ni
* contabilizar nada de verdad.

SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME TITLE TEXT-001.

  SELECT-OPTIONS: s_keyr1 FOR zfi_t_file_log-file_name_header.
  PARAMETERS:     p_simu AS CHECKBOX DEFAULT space.

SELECTION-SCREEN END OF BLOCK b1.
