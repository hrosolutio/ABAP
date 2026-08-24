*&---------------------------------------------------------------------*
*& Pool de subrutinas ZFKR2_POOL                                       *
*&---------------------------------------------------------------------*
* "Soft-exit" del grupo de funcion FKR2 (dominio RLS = lotes de
* devolucion/Rueckläuferstapel). FKK_RLS_HDR_PREPARE llama a
* GENERATE_RLS_KEY (via PERFORM ('GENERATE_RLS_KEY') IN PROGRAM
* (PROG_NAME) IF FOUND) para proponer el KEYR1 del lote en vez de usar
* su generador estandar (RL + fecha + secuencial de 2 digitos).
* PROG_NAME esta hardcodeado en el propio codigo estandar de SAP como
* 'ZFKR2_POOL' (confirmado por depuracion, no es customizing) - por eso
* el programa tiene que llamarse exactamente asi para que SAP lo
* encuentre, tanto llamando a FKK_RLS_HDR_PREPARE desde ZFI_R_
* DEVOLUCIONES_CREA como al crear un lote manualmente desde FP09.
*
* Tipo de programa: Pool de subrutinas (crear en SE38 con ese tipo).
*
* Nomenclatura pedida por el DF (CDI_11, RU_02): AAMMDDCDI11xx (13
* caracteres, secuencial de 2 digitos). El campo DFKKRK-KEYR1 solo tiene
* 12 caracteres - limite tecnico confirmado, no elegido por nosotros -
* asi que el secuencial se queda en 1 solo digito (AAMMDDCDI11x, 0-9,
* maximo 10 lotes/dia). Si se agotan los 10 valores del dia, se deja
* C_KEYR1 en blanco para que FKK_RLS_HDR_PREPARE caiga a su generador
* estandar (RL+fecha+secuencial) en vez de fallar - ver
* ../docs/DF_resumen.md para el detalle completo.

FORM generate_rls_key CHANGING c_keyr1 LIKE dfkkrk-keyr1.

  DATA: lv_prefix    TYPE c LENGTH 11,
        lv_seq       TYPE n LENGTH 1,
        lv_candidate LIKE dfkkrk-keyr1,
        lv_found     LIKE dfkkrk-keyr1.

  CONCATENATE sy-datum+2(6) 'CDI11' INTO lv_prefix.

  lv_seq = 0.
  DO 10 TIMES.
    CONCATENATE lv_prefix lv_seq INTO lv_candidate.

    CLEAR lv_found.
    SELECT SINGLE keyr1 FROM dfkkrk INTO lv_found WHERE keyr1 = lv_candidate.

    IF sy-subrc <> 0.
      c_keyr1 = lv_candidate.
      RETURN.
    ENDIF.

    lv_seq = lv_seq + 1.
  ENDDO.

  CLEAR c_keyr1.

ENDFORM.
