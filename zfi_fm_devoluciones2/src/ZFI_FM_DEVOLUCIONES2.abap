FUNCTION zfi_fm_devoluciones2.
*"----------------------------------------------------------------------
*"*"Interfaz local:
*"  IMPORTING
*"     VALUE(IT_KEYR1) TYPE  ZFI_T_KEYR1
*"  EXPORTING
*"     VALUE(E_RESULT) TYPE  CHAR3
*"     VALUE(ES_ERROR) TYPE  ZFI_DE_XX_WS_ERROR
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
* WITH SELECTION-TABLE, construyendo S_KEYR1 a partir de IT_KEYR1) y
* después relee DFKKRK-STARS para decidir el resultado - la misma
* fuente de verdad que usa el propio report para decidir qué hacer con
* cada lote (ver ZFI_R_DEVOLUCIONES2_CLS, CO_STARS_POSTED).
*
* SIN parámetro de simulación: a diferencia del report (que sí tiene
* P_SIMU, para uso manual), esta RFC SIEMPRE se ejecuta en real - no
* se pasa ninguna fila P_SIMU en la tabla de seleccion, así que el
* report usa su propio valor por defecto (P_SIMU DEFAULT SPACE, ver
* ZFI_R_DEVOLUCIONES2_EVE). Decisión explícita: no viene del DF, se
* quita para no dar pie a que un consumidor externo dispare una
* llamada en modo simulación sin querer.
*
* E_RESULT/ES_ERROR siguen el mismo patrón que ZFI_FM_PAYLOT_REVERSE/
* ZFI_FM_PAYMENT_LOT_CLARIFY2 (CHAR3 'OK'/'NOK' + ZFI_DE_XX_WS_ERROR).
* Como IT_KEYR1 admite varios lotes a la vez (a diferencia de esos dos
* RFCs, que procesan un único elemento), E_RESULT es un resultado
* GLOBAL de la llamada: 'OK' solo si TODOS los lotes de IT_KEYR1
* terminaron contabilizados (STARS = CO_STARS_POSTED); si no, 'NOK' y
* ES_ERROR-DESCRIPTION lista qué lote(s) no llegaron a contabilizarse
* y por qué (no hace falta una tabla de resultado aparte: con E_RESULT
* = 'OK' ya se sabe que todo se contabilizó, y con 'NOK' el detalle
* está en ES_ERROR).
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
        lv_fail_desc  TYPE string,
        lv_stars      TYPE dfkkrk-stars.

  CLEAR: e_result, es_error.

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

  SUBMIT zfi_r_devoluciones2
    WITH SELECTION-TABLE lt_rspar
    AND RETURN.

  LOOP AT it_keyr1 INTO DATA(ls_keyr1_out).

    CLEAR lv_stars.
    SELECT SINGLE stars FROM dfkkrk INTO lv_stars
      WHERE keyr1 = ls_keyr1_out-keyr1.

    IF sy-subrc <> 0.
      lv_fail_count = lv_fail_count + 1.
      lv_fail_desc  = lv_fail_desc && |Lote { ls_keyr1_out-keyr1 }: no existe en DFKKRK. |.
    ELSEIF lv_stars <> co_stars_posted.
      lv_fail_count = lv_fail_count + 1.
      lv_fail_desc  = lv_fail_desc && |Lote { ls_keyr1_out-keyr1 }: STARS={ lv_stars } (no contabilizado). |.
    ENDIF.

  ENDLOOP.

  IF lv_fail_count = 0.
    e_result = 'OK'.
  ELSE.
    e_result             = 'NOK'.
    es_error-code        = 'LOTES_INCOMPLETOS'.
    es_error-description = lv_fail_desc.
  ENDIF.

ENDFUNCTION.
