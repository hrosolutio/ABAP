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
* ESTADO: PRIMERA VERSIÓN, PENDIENTE DE PRUEBA END-TO-END REAL.
*
* El DF advierte que FKK_PAYMENT_BATCH_CLARIFY_ITEM "no se puede
* utilizar directamente" (es un módulo de diálogo: abre una pantalla
* interactiva y espera acción del usuario, no apto para RFC). Por
* depuración de FPCPL se ha localizado la cadena real de módulos
* estándar subyacente, evitando la capa de pantalla:
*
*   FKK_OPEN_ITEM_SELECT        -> busca la partida abierta (factura)
*                                   a partir de T_SELTAB. VERIFICADO
*                                   por depuración con SELFN='XBLNR' y
*                                   una factura real: encuentra
*                                   correctamente las líneas de FKKOP.
*   ISU_CLEARING_PROPOSAL_GEN_0110 -> genera la propuesta de
*                                   compensación y contabiliza
*                                   (variante ISU de
*                                   FKK_CLEARING_PROPOSAL_GEN_0110,
*                                   que a su vez llama a
*                                   FKK_PAYMENT_ALLOC_AND_CLEARING ->
*                                   PAYMENT_ON_ACCOUNT ->
*                                   FKK_OPEN_PAYMENT_COMPLETE).
*                                   Firma e interfaz verificadas por
*                                   depuración; la llamada directa
*                                   desde este RFC (sin pasar por la
*                                   capa de pantalla/lote en bloque)
*                                   es composición razonada, NO
*                                   probada de principio a fin todavía.
*
* El mapeo de tipo de selección 'X' -> campo FKKOP-XBLNR está
* verificado contra la tabla de customizing TFK004 (Área R).
*
* El documento de clarificación generado se relee de DFKKZP-KLAEB
* (verificado por depuración en el desarrollo de anulación con el
* campo análogo RUEBL, y confirmado aquí contra un caso real ya
* clarificado).
*
* TODO pendiente de confirmar con negocio: cuando I_XBLNR trae varias
* facturas, aquí se prueban una a una y se usa la primera cuyo importe
* total coincida exactamente con el importe de la posición (según el
* propio requisito del DF: "El importe de dicha factura debe coincidir
* con el importe de la posición... para garantizar la clarificación
* completa"). No hay confirmación de negocio de que este sea el
* comportamiento esperado para el caso de varias facturas.
*----------------------------------------------------------------------*

  DATA: ls_dfkkzp   TYPE dfkkzp,
        ls_seltab    TYPE iseltab,
        lt_seltab    TYPE STANDARD TABLE OF iseltab,
        lt_fkkcl_cand TYPE STANDARD TABLE OF fkkcl,
        lt_fkkcl     TYPE STANDARD TABLE OF fkkcl,
        ls_fkkcl     TYPE fkkcl,
        lv_sum       TYPE fkkop-betrw,
        lv_found     TYPE abap_bool,
        ls_fkkko     TYPE fkkko,
        ls_fkkopk    TYPE fkkopk,
        lt_fkkopk    TYPE STANDARD TABLE OF fkkopk,
        lt_fkkop     TYPE STANDARD TABLE OF fkkop,
        lt_fkkop_new TYPE STANDARD TABLE OF fkkop,
        lt_fkkopk_new TYPE STANDARD TABLE OF fkkopk,
        lt_fkkop_dp_new TYPE STANDARD TABLE OF dfkkop_dp,
        lv_klaeh     TYPE dfkkzp-klaeh,
        lv_diffb     TYPE rfkb4-diffb.

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
  SELECT SINGLE *
    FROM dfkkzp
    INTO ls_dfkkzp
    WHERE keyz1 = i_keyz1
      AND posza = i_posza.

  IF sy-subrc <> 0.
    e_result             = 'NOK'.
    es_error-code        = 'POS_NOT_FOUND'.
    es_error-description = |No existe la posición { i_posza } del lote { i_keyz1 }|.
    RETURN.
  ENDIF.

  IF ls_dfkkzp-xklae <> 'X'.
    e_result             = 'NOK'.
    es_error-code        = 'POS_NOT_PENDING'.
    es_error-description = |La posición { i_posza } del lote { i_keyz1 } no está pendiente de clarificar|.
    RETURN.
  ENDIF.

*----------------------------------------------------------------------*
* 3. Buscar, para cada factura de I_XBLNR, las partidas abiertas que
*    coinciden (FKK_OPEN_ITEM_SELECT con SELFN='XBLNR'). Solo se
*    considera válida la factura cuyo importe total de partidas
*    encontradas coincida exactamente con el importe de la posición.
*    Búsqueda pura (sin efectos secundarios de contabilización).
*----------------------------------------------------------------------*
  LOOP AT i_xblnr INTO DATA(ls_xblnr).

    CLEAR: lt_seltab, ls_seltab, lt_fkkcl_cand.
    ls_seltab-selnr = 1.
    ls_seltab-selfn = gc_selfn_xblnr.
    ls_seltab-selcu = ls_xblnr-xblnr.
    APPEND ls_seltab TO lt_seltab.

    CALL FUNCTION 'FKK_OPEN_ITEM_SELECT'
      EXPORTING
        i_applk             = gc_applk_clarificacion
        i_payment_date      = ls_dfkkzp-budat
        i_payment_curr      = ls_dfkkzp-waers
        i_payment_amount    = ls_dfkkzp-betrz
        i_enq_scope         = '1'
      TABLES
        t_seltab            = lt_seltab
        t_fkkcl             = lt_fkkcl_cand
      EXCEPTIONS
        concurrent_clearing = 1
        error_message       = 2
        OTHERS              = 3.

    CHECK sy-subrc = 0.
    CHECK lt_fkkcl_cand IS NOT INITIAL.

    CLEAR lv_sum.
    LOOP AT lt_fkkcl_cand INTO ls_fkkcl.
      lv_sum = lv_sum + ls_fkkcl-betrw.
    ENDLOOP.

    IF lv_sum = ls_dfkkzp-betrz.
      lt_fkkcl = lt_fkkcl_cand.
      lv_found = abap_true.
      EXIT.
    ENDIF.

  ENDLOOP.

  IF lv_found = abap_false.
    e_result             = 'NOK'.
    es_error-code        = 'NO_MATCHING_INVOICE'.
    es_error-description = 'Ninguna de las facturas indicadas coincide en importe con la posición'.
    RETURN.
  ENDIF.

*----------------------------------------------------------------------*
* 4. Construir cabecera de documento (I_FKKKO) y partida provisional
*    (T_FKKOPK) a partir de los datos de la posición del lote, según
*    el patrón observado por depuración en PAYMENT_ON_ACCOUNT.
*----------------------------------------------------------------------*
  CLEAR ls_fkkko.
  ls_fkkko-fikey       = i_keyz1.
  ls_fkkko-applk       = gc_applk_clarificacion.
  ls_fkkko-blart       = gc_blart_clarificacion.
  ls_fkkko-herkf       = gc_herkf_clarificacion.
  ls_fkkko-waers       = ls_dfkkzp-waers.
  ls_fkkko-bldat       = ls_dfkkzp-bldat.
  ls_fkkko-budat       = ls_dfkkzp-budat.
  ls_fkkko-wwert       = ls_dfkkzp-valut.
  ls_fkkko-wnper       = '00'.
  ls_fkkko-xsing       = 'X'.
  ls_fkkko-keypp       = '000'.
  ls_fkkko-closingstep = '000'.

* TODO: verificar si HKONT debe ser siempre DFKKZP-KLAEH (si ya viene
* informado) o la cuenta provisional constante; no probado con un caso
* real de éxito de principio a fin.
  CLEAR ls_fkkopk.
  ls_fkkopk-bukrs = ls_dfkkzp-bukrs.
  IF ls_dfkkzp-klaeh IS NOT INITIAL.
    ls_fkkopk-hkont = ls_dfkkzp-klaeh.
  ELSE.
    ls_fkkopk-hkont = gc_cuenta_provisional.
  ENDIF.
  ls_fkkopk-prctr = ls_dfkkzp-prctr.
  ls_fkkopk-valut = ls_dfkkzp-valut.
  ls_fkkopk-betrh = ls_dfkkzp-betrz.
  ls_fkkopk-betrw = ls_dfkkzp-betrz.
  ls_fkkopk-hbkid = ls_dfkkzp-hbkid.
  ls_fkkopk-hktid = ls_dfkkzp-hktid.
  ls_fkkopk-opupk = '0001'.
  APPEND ls_fkkopk TO lt_fkkopk.

*----------------------------------------------------------------------*
* 5. Generar la propuesta de compensación y contabilizar, replicando
*    la cadena real localizada por depuración (variante ISU, ya que el
*    sistema es SAP ISU). I_CLARIFICATION = 'X' porque este es
*    precisamente un escenario de clarificación.
*----------------------------------------------------------------------*
  CALL FUNCTION 'ISU_CLEARING_PROPOSAL_GEN_0110'
    EXPORTING
      i_fkkko         = ls_fkkko
      i_clarification = 'X'
    IMPORTING
      e_klaeh         = lv_klaeh
      e_diffb         = lv_diffb
    TABLES
      t_fkkop         = lt_fkkop
      t_fkkopk        = lt_fkkopk
      t_fkkcl         = lt_fkkcl
      t_fkkop_new     = lt_fkkop_new
      t_fkkopk_new    = lt_fkkopk_new
      t_fkkop_dp_new  = lt_fkkop_dp_new
      t_seltab        = lt_seltab
    EXCEPTIONS
      OTHERS          = 1.

  IF sy-subrc <> 0.
    e_result             = 'NOK'.
    es_error-code        = |{ sy-subrc }|.
    MESSAGE ID sy-msgid TYPE sy-msgty NUMBER sy-msgno
      INTO es_error-description
      WITH sy-msgv1 sy-msgv2 sy-msgv3 sy-msgv4.
    RETURN.
  ENDIF.

  COMMIT WORK AND WAIT.

*----------------------------------------------------------------------*
* 6. Verificar el resultado real releyendo DFKKZP (mismo patrón que en
*    ZFI_FM_PAYLOT_REVERSE con RUEBL): el documento de clarificación
*    generado queda en DFKKZP-KLAEB.
*----------------------------------------------------------------------*
  SELECT SINGLE xklae klaeb
    FROM dfkkzp
    INTO (@DATA(lv_xklae_final), @DATA(lv_klaeb_final))
    WHERE keyz1 = @i_keyz1
      AND posza = @i_posza.

  IF lv_klaeb_final IS NOT INITIAL AND lv_xklae_final <> 'X'.
    e_result = 'OK'.
    e_opbel  = lv_klaeb_final.
  ELSE.
    e_result             = 'NOK'.
    es_error-code        = 'CLARIFY_NOT_CONFIRMED'.
    es_error-description = 'La contabilización se ejecutó sin excepción pero la posición sigue sin documento de clarificación'.
  ENDIF.

ENDFUNCTION.
