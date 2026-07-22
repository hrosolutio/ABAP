FUNCTION zfi_fm_payment_lot_clarify2.
*"----------------------------------------------------------------------
*"*"Interfaz local:
*"  IMPORTING
*"     VALUE(I_KEYZ1) TYPE  KEYZ1_KK
*"     VALUE(I_POSZA) TYPE  POSZA_KK
*"     VALUE(I_XBLNR) TYPE  ZFI_T_XBLNR
*"  EXPORTING
*"     VALUE(E_RESULT) TYPE  CHAR3
*"     VALUE(ES_ERROR) TYPE  ZFI_DE_XX_WS_ERROR
*"     VALUE(E_OPBEL) TYPE  OPBEL_KK
*"----------------------------------------------------------------------
* Clarificación de transferencias pendientes de contabilizar en SAP
* (equivalente a FPCPL)
*
* ESTADO: TERCERA VERSIÓN. Cadena completa localizada por depuración,
* incluyendo el paso de contabilización real que faltaba. Pendiente de
* probar de principio a fin activando este módulo en SE37 (las pruebas
* hasta ahora se hicieron forzando variables por depuración dentro del
* flujo real de FPCPL, no todavía a través de este RFC).
*
* El DF advierte que FKK_PAYMENT_BATCH_CLARIFY_ITEM "no se puede
* utilizar directamente" (es un módulo de diálogo: abre una pantalla
* interactiva y espera acción del usuario, no apto para RFC). Por
* depuración de FPCPL (hasta BUCHG_ZAHLUNG_BUCHEN, SAPLFKZ0) se ha
* localizado la cadena real completa, evitando la capa de pantalla:
*
*   FKK_OPEN_ITEM_SELECT             -> busca la partida abierta
*                                        (factura) a partir de
*                                        T_SELTAB. VERIFICADO por
*                                        depuración con SELFN='XBLNR'
*                                        y una factura real.
*   ISU_CLEARING_PROPOSAL_GEN_0110   -> SOLO calcula la propuesta de
*                                        compensación (marca
*                                        T_FKKCL-AUGBW/XAKTP), NO
*                                        contabiliza (verificado: tras
*                                        llamarla, T_FKKOP_NEW seguía
*                                        vacía y no se generaba
*                                        documento). Es la variante
*                                        ISU de
*                                        FKK_CLEARING_PROPOSAL_GEN_0110
*                                        -> FKK_PAYMENT_ALLOC_AND_CLEARING
*                                        -> PAYMENT_ON_ACCOUNT ->
*                                        FKK_OPEN_PAYMENT_COMPLETE.
*   FKK_CREATE_DOC_MASS_AND_CLEAR    -> ESTA es quien contabiliza de
*                                        verdad, usando la propuesta ya
*                                        calculada. Localizada
*                                        depurando BUCHG_ZAHLUNG_BUCHEN
*                                        justo después de la llamada
*                                        anterior. Devuelve E_OPBEL, el
*                                        documento real.
*
* PROBADO CON ÉXITO REAL (a través del flujo propio de FPCPL, con
* T_SELTAB forzado por depuración a SELFN='XBLNR'): una factura de 6
* líneas (importe total 50,00 €), con solo una línea de 0,24 €, se
* pasó completa (las 6 líneas) al motor de compensación, y este aplicó
* correctamente solo la parte que correspondía a la posición (0,24 €),
* dejando DFKKZP-XKLAE vacío y DFKKZP-KLAEB con el documento generado.
* Por eso este código pasa TODAS las líneas encontradas de la factura
* candidata al motor, sin filtrar a una sola línea nosotros mismos.
*
* NO verificado todavía: la llamada directa a esta cadena desde ESTE
* RFC con I_FKKKO/T_FKKOPK construidos por nuestro propio código (en
* vez de los que construye BUCHG_ZAHLUNG_BUCHEN internamente), y el
* valor de I_AUGVD (aproximado aquí con la fecha valor de la posición,
* sin verificar contra PERFORM augvd_determine del flujo real).
*
* También localizado por depuración: el propio FORM
* BUCHG_ZAHLUNGEN_BEARBEITEN actualiza DFKKZP (XKLAE/KLAEB) a mano
* tras contabilizar — ninguna función del motor lo hace por sí sola.
* Este código replica esa actualización (paso 7) para el caso simple
* de una primera clarificación completa; los casos de clarificaciones
* parciales/múltiples sobre la misma posición (que en BUCHG_ZAHLUNG_
* BUCHEN llevan lógica adicional con DFKKZPT) no están contemplados.
*
* El mapeo de tipo de selección 'X' -> campo FKKOP-XBLNR está
* verificado contra la tabla de customizing TFK004 (Área R).
*
* TODO pendiente de confirmar con negocio: cuando I_XBLNR trae varias
* facturas, aquí se prueban una a una y se usa la primera que tenga
* alguna línea cuyo importe coincida exactamente con el importe de la
* posición (según el propio requisito del DF: "El importe de dicha
* factura debe coincidir con el importe de la posición... para
* garantizar la clarificación completa"). No hay confirmación de
* negocio de que este sea el comportamiento esperado para el caso de
* varias facturas.
*----------------------------------------------------------------------*

  DATA: ls_dfkkzp   TYPE dfkkzp,
        ls_seltab    TYPE iseltab,
        lt_seltab    TYPE STANDARD TABLE OF iseltab,
        lt_fkkcl_cand TYPE STANDARD TABLE OF fkkcl,
        lt_fkkcl     TYPE STANDARD TABLE OF fkkcl,
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
*    coinciden (FKK_OPEN_ITEM_SELECT con SELFN='XBLNR'). Una factura
*    puede devolver varias líneas (verificado con un caso real de 6
*    líneas, solo una de importe 0,24). Se usa la presencia de al
*    menos una línea con el importe exacto de la posición como criterio
*    para elegir QUÉ factura de I_XBLNR es la candidata correcta
*    (búsqueda pura, sin contabilizar), pero al contabilizar se pasan
*    TODAS las líneas encontradas de esa factura, no solo la que
*    coincide: probado con datos reales que el propio motor de
*    compensación estándar (FKK_PAYMENT_ALLOC_AND_CLEARING /
*    FKK_OPEN_PAYMENT_COMPLETE) aplica correctamente solo la parte que
*    corresponde al importe de la posición, sin que haga falta
*    filtrar nosotros una única línea a mano.
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

    READ TABLE lt_fkkcl_cand TRANSPORTING NO FIELDS
      WITH KEY betrw = ls_dfkkzp-betrz.
    IF sy-subrc = 0.
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
* 5. Generar la propuesta de compensación, replicando la cadena real
*    localizada por depuración (variante ISU, ya que el sistema es
*    SAP ISU). I_CLARIFICATION = 'X' porque este es precisamente un
*    escenario de clarificación.
*
*    IMPORTANTE (verificado por depuración de BUCHG_ZAHLUNG_BUCHEN,
*    SAPLFKZ0): esta función SOLO calcula la propuesta (marca
*    T_FKKCL-AUGBW/XAKTP), NO contabiliza nada. El propio FORM protege
*    T_FKKOPK de cambios durante esta llamada (guarda y restaura la
*    tabla alrededor de la llamada); replicamos esa protección aquí.
*----------------------------------------------------------------------*
  DATA: lt_fkkopk_save TYPE STANDARD TABLE OF fkkopk,
        lv_tolgr_clear TYPE tolgr_clear_gen,
        lv_comrq       TYPE flag,
        lv_opbel_new   TYPE opbel_kk,
        lv_budat_new   LIKE ls_dfkkzp-budat.

  lt_fkkopk_save = lt_fkkopk.

  CALL FUNCTION 'ISU_CLEARING_PROPOSAL_GEN_0110'
    EXPORTING
      i_fkkko         = ls_fkkko
      i_clarification = 'X'
    IMPORTING
      e_klaeh         = lv_klaeh
      e_diffb         = lv_diffb
      e_tolgr_clear   = lv_tolgr_clear
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

  lt_fkkopk = lt_fkkopk_save.

*----------------------------------------------------------------------*
* 6. Contabilizar de verdad la propuesta ya calculada. Localizado por
*    depuración en BUCHG_ZAHLUNG_BUCHEN (SAPLFKZ0), justo después de la
*    llamada anterior: FKK_CREATE_DOC_MASS_AND_CLEAR es quien crea el
*    documento real (FKK_CREATE_DOC_AND_CLEAR en el caso poco frecuente
*    de contabilización individual, no aplicable aquí). I_AUGVD se
*    aproxima con la fecha valor de la posición; en el flujo real se
*    calcula con PERFORM augvd_determine, no verificado en detalle.
*----------------------------------------------------------------------*
  CALL FUNCTION 'FKK_CREATE_DOC_MASS_AND_CLEAR'
    EXPORTING
      i_fkkko       = ls_fkkko
      i_diffb       = lv_diffb
      i_tolgr_clear = lv_tolgr_clear
      i_augvd       = ls_dfkkzp-valut
    IMPORTING
      e_comrq       = lv_comrq
      e_opbel       = lv_opbel_new
      e_budat       = lv_budat_new
    TABLES
      t_fkkop       = lt_fkkop_new
      t_fkkop_dp    = lt_fkkop_dp_new
      t_fkkopk      = lt_fkkopk
      t_fkkcl       = lt_fkkcl
    EXCEPTIONS
      OTHERS        = 1.

  IF sy-subrc <> 0 OR lv_opbel_new IS INITIAL.
    e_result             = 'NOK'.
    es_error-code        = |{ sy-subrc }|.
    MESSAGE ID sy-msgid TYPE sy-msgty NUMBER sy-msgno
      INTO es_error-description
      WITH sy-msgv1 sy-msgv2 sy-msgv3 sy-msgv4.
    RETURN.
  ENDIF.

*----------------------------------------------------------------------*
* 7. Actualizar la posición del lote (DFKKZP), replicando lo que hace
*    BUCHG_ZAHLUNGEN_BEARBEITEN a mano tras contabilizar (el motor
*    estándar no lo hace por sí solo): marcar como ya no pendiente y
*    anotar el documento de clarificación generado.
*----------------------------------------------------------------------*
  UPDATE dfkkzp
    SET xklae = space
        klaeb = lv_opbel_new
        klaed = lv_budat_new
    WHERE keyz1 = i_keyz1
      AND posza = i_posza.

  COMMIT WORK AND WAIT.

  e_result = 'OK'.
  e_opbel  = lv_opbel_new.

ENDFUNCTION.
