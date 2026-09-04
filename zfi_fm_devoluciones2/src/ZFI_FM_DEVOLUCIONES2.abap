FUNCTION zfi_fm_devoluciones2.
*"----------------------------------------------------------------------
*"*"Interfaz local:
*"  IMPORTING
*"     VALUE(IV_SIMU) TYPE  ABAP_BOOL DEFAULT ABAP_FALSE
*"     VALUE(IT_KEYR1) TYPE  ZFI_T_KEYR1
*"  EXPORTING
*"     VALUE(ET_RESULTADO) TYPE  ZFI_T_KEYR1_RESULT
*"----------------------------------------------------------------------
* RU_03 (CDI_11) como servicio RFC. El DF pedía originalmente un
* "servicio" para el cierre/contabilización del lote de devoluciones;
* se decidió con Eva que no hacía falta (bastaba el report
* ZFI_R_DEVOLUCIONES2, con el lote indicado a mano). Más tarde se ha
* pedido igualmente un servicio - se mantienen los dos: el report para
* uso manual (equivalente a FP09) y este RFC para integración externa.
*
* En vez de duplicar la lógica ya probada de LCL_DEVOLUCIONES2, este
* módulo literalmente llama al propio ZFI_R_DEVOLUCIONES2 (SUBMIT ...
* WITH SELECTION-TABLE, construyendo S_KEYR1/P_SIMU a partir de
* IT_KEYR1/IV_SIMU) y después relee DFKKRK-STARS para devolver un
* resultado estructurado por lote - la misma fuente de verdad que usa
* el propio report para decidir qué hacer con cada lote (ver
* ZFI_R_DEVOLUCIONES2_CLS, CO_STARS_CLOSED/CO_STARS_POSTED).
*
* No se captura el listado de mensajes del report (ZXX_CL_MSG_LOGS) -
* el resultado que importa a un consumidor externo es el estado final
* de cada lote (ET_RESULTADO-STARS), no el texto de los mensajes
* intermedios. Si en el futuro hiciera falta el detalle textual,
* habría que capturar el listado con SUBMIT ... EXPORTING LIST TO
* MEMORY + LIST_FROM_MEMORY.

  DATA: lt_rspar TYPE STANDARD TABLE OF rsparams,
        ls_rspar TYPE rsparams.

  CLEAR et_resultado.

  CHECK it_keyr1 IS NOT INITIAL.

  LOOP AT it_keyr1 INTO DATA(ls_keyr1_in).
    CLEAR ls_rspar.
    ls_rspar-selname = 'S_KEYR1'.
    ls_rspar-kind    = 'S'.
    ls_rspar-sign    = 'I'.
    ls_rspar-option  = 'EQ'.
    ls_rspar-low     = ls_keyr1_in-keyr1.
    APPEND ls_rspar TO lt_rspar.
  ENDLOOP.

  CLEAR ls_rspar.
  ls_rspar-selname = 'P_SIMU'.
  ls_rspar-kind    = 'P'.
  ls_rspar-low     = COND #( WHEN iv_simu = abap_true THEN 'X' ELSE space ).
  APPEND ls_rspar TO lt_rspar.

  SUBMIT zfi_r_devoluciones2
    WITH SELECTION-TABLE lt_rspar
    AND RETURN.

  LOOP AT it_keyr1 INTO DATA(ls_keyr1_out).
    DATA(ls_resultado) = VALUE zfi_s_keyr1_result( keyr1 = ls_keyr1_out-keyr1 ).
    SELECT SINGLE stars FROM dfkkrk INTO ls_resultado-stars
      WHERE keyr1 = ls_keyr1_out-keyr1.
    APPEND ls_resultado TO et_resultado.
  ENDLOOP.

ENDFUNCTION.
