FUNCTION zfi_fm_payment_lot_clarify2.
*"----------------------------------------------------------------------
*"*"Interfaz local:
*"  IMPORTING
*"     VALUE(I_KEYZ1) TYPE  KEYZ1_KK
*"     VALUE(I_POSZA) TYPE  POSZA_KK
*"     VALUE(I_XBLNR) TYPE  TY_T_XBLNR
*"  EXPORTING
*"     VALUE(E_RESULT) TYPE  CHAR3
*"     VALUE(ES_ERROR) TYPE  ZFI_DE_XX_WS_ERROR
*"     VALUE(E_OPBEL) TYPE  OPBEL_KK
*"----------------------------------------------------------------------
* Clarificación de transferencias pendientes de contabilizar en SAP
* (equivalente a FPCPL)
*
* ESTADO: ESQUELETO INCOMPLETO A PROPÓSITO.
*
* El DF advierte explícitamente que el módulo de función estándar
* FKK_PAYMENT_BATCH_CLARIFY_ITEM "no se puede utilizar directamente" y
* que no existe FM estándar ejecutable por RFC que clarifique posiciones
* de lote. La secuencia real de llamadas para clarificar una posición
* de lote (paso 3 de este código) todavía NO está verificada contra el
* sistema y NO debe implementarse por suposición: hay que depurar la
* transacción FPCPL (igual que se hizo con FP08 para el desarrollo de
* anulación de transferencias, ZFI_FM_PAYLOT_REVERSE) para localizar la
* forma real de aplicar la factura a la posición del lote.
*----------------------------------------------------------------------*

  CLEAR: e_result, es_error, e_opbel.

*----------------------------------------------------------------------*
* 1. Validación de parámetros obligatorios
*----------------------------------------------------------------------*
  IF i_keyz1 IS INITIAL.
    e_result             = 'NOK'.
    es_error-code        = 'PARAM_MISSING'.
    es_error-description = 'I_KEYZ1 es obligatorio'.
    RETURN.
  ENDIF.

  IF i_posza IS INITIAL.
    e_result             = 'NOK'.
    es_error-code        = 'PARAM_MISSING'.
    es_error-description = 'I_POSZA es obligatorio'.
    RETURN.
  ENDIF.

  IF i_xblnr IS INITIAL.
    e_result             = 'NOK'.
    es_error-code        = 'PARAM_MISSING'.
    es_error-description = 'I_XBLNR es obligatorio (al menos una factura)'.
    RETURN.
  ENDIF.

*----------------------------------------------------------------------*
* 2. La posición del lote debe existir y estar pendiente de clarificar
*    (DFKKZP-XKLAE = 'X')
*----------------------------------------------------------------------*
  SELECT SINGLE xklae
    FROM dfkkzp
    INTO @DATA(lv_xklae)
    WHERE keyz1 = @i_keyz1
      AND posza = @i_posza.

  IF sy-subrc <> 0.
    e_result             = 'NOK'.
    es_error-code        = 'POS_NOT_FOUND'.
    es_error-description = |No existe la posición { i_posza } del lote { i_keyz1 }|.
    RETURN.
  ENDIF.

  IF lv_xklae <> 'X'.
    e_result             = 'NOK'.
    es_error-code        = 'POS_NOT_PENDING'.
    es_error-description = |La posición { i_posza } del lote { i_keyz1 } no está pendiente de clarificar|.
    RETURN.
  ENDIF.

*----------------------------------------------------------------------*
* 3. TODO — PENDIENTE DE INVESTIGAR CON EL SISTEMA REAL:
*    Aplicar la(s) factura(s) de I_XBLNR a la posición del lote como
*    tipo de selección "X" (número de documento oficial) y contabilizar,
*    replicando el resultado de FPCPL. El DF descarta explícitamente
*    llamar directamente a FKK_PAYMENT_BATCH_CLARIFY_ITEM.
*
*    No implementar nada aquí sin verificarlo antes por depuración.
*----------------------------------------------------------------------*

  e_result             = 'NOK'.
  es_error-code        = 'NOT_IMPLEMENTED'.
  es_error-description = 'Lógica de clarificación pendiente de investigar (ver TODO paso 3)'.

ENDFUNCTION.
