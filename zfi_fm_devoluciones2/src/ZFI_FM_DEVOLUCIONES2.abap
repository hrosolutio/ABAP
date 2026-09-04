FUNCTION zfi_fm_devoluciones2.
*"----------------------------------------------------------------------
*"*"Interfaz local:
*"  IMPORTING
*"     VALUE(IV_SIMU) TYPE  ABAP_BOOL DEFAULT ABAP_FALSE
*"     VALUE(IT_KEYR1) TYPE  ZFI_T_KEYR1
*"  EXPORTING
*"     VALUE(E_RESULT) TYPE  CHAR3
*"     VALUE(ES_ERROR) TYPE  ZFI_DE_XX_WS_ERROR
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
* IT_KEYR1/IV_SIMU) y después relee DFKKRK-STARS para decidir el
* resultado - la misma fuente de verdad que usa el propio report para
* decidir qué hacer con cada lote (ver ZFI_R_DEVOLUCIONES2_CLS,
* CO_STARS_CLOSED/CO_STARS_POSTED).
*
* E_RESULT/ES_ERROR siguen el mismo patrón que ZFI_FM_PAYLOT_REVERSE/
* ZFI_FM_PAYMENT_LOT_CLARIFY2 (CHAR3 'OK'/'NOK' + ZFI_DE_XX_WS_ERROR).
* Como IT_KEYR1 admite varios lotes a la vez (a diferencia de esos dos
* RFCs, que procesan un único elemento), E_RESULT es un resultado
* GLOBAL de la llamada ('OK' solo si TODOS los lotes terminaron en el
* estado esperado) y ET_RESULTADO se mantiene además para poder ver
* lote a lote qué ha pasado - con varios lotes, "algo ha fallado" sin
* decir cuál no sería útil para el consumidor del servicio.
*
* "Estado esperado" depende de IV_SIMU: en modo real, que el lote quede
* contabilizado (STARS = CO_STARS_POSTED); en modo simulación (no se
* toca nada), que el lote exista en DFKKRK - no tiene sentido exigir
* STARS=contabilizado en una llamada que por diseño no contabiliza nada.
*
* No se captura el listado de mensajes del report (ZXX_CL_MSG_LOGS) -
* el detalle textual de qué ha pasado en cada lote se construye aquí a
* partir de DFKKRK-STARS, no parseando el texto de esos mensajes. Si en
* el futuro hiciera falta el texto tal cual del report, habría que
* capturar el listado con SUBMIT ... EXPORTING LIST TO MEMORY +
* LIST_FROM_MEMORY.

  DATA: lt_rspar      TYPE STANDARD TABLE OF rsparams,
        ls_rspar      TYPE rsparams,
        lv_fail_count TYPE i,
        lv_fail_desc  TYPE string.

  CLEAR: e_result, es_error, et_resultado.

  IF it_keyr1 IS INITIAL.
    e_result             = 'NOK'.
    es_error-code        = 'PARAM_MISSING'.
    es_error-description = 'IT_KEYR1 es obligatorio (al menos un lote)'.
    RETURN.
  ENDIF.

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

    IF sy-subrc <> 0.
      lv_fail_count = lv_fail_count + 1.
      lv_fail_desc  = lv_fail_desc && |Lote { ls_keyr1_out-keyr1 }: no existe en DFKKRK. |.
    ELSEIF iv_simu = abap_false AND ls_resultado-stars <> co_stars_posted.
      lv_fail_count = lv_fail_count + 1.
      lv_fail_desc  = lv_fail_desc && |Lote { ls_keyr1_out-keyr1 }: STARS={ ls_resultado-stars } (no contabilizado). |.
    ENDIF.

    APPEND ls_resultado TO et_resultado.

  ENDLOOP.

  IF lv_fail_count = 0.
    e_result = 'OK'.
  ELSE.
    e_result             = 'NOK'.
    es_error-code        = 'LOTES_INCOMPLETOS'.
    es_error-description = lv_fail_desc.
  ENDIF.

ENDFUNCTION.
