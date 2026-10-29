*----------------------------------------------------------------------*
* Facturación automática de averías y fraudes.
*
* Flujo (ver README para el detalle y los TODO pendientes):
*   1. Validaciones de entrada               -> KO 1xxx
*   2. Indicador de forzado                  -> factura a 0 (EREPOS/GREPOS)
*   3. Validaciones de integridad            -> OK 01xx (descarte)
*   4. Cálculo original del periodo          -> OK 0108/0109 si no hay uno
*   5. Importes según luz / gas              -> KO 2002 si falta algo
*   6. Cálculo manual + factura              -> KO 2003/2004
*
* Los métodos de cálculo (prorratear, calcular_iee, aplicar_descuentos,
* potencia_mayor) no acceden a BD y tienen ABAP Unit en el include de
* test.
*----------------------------------------------------------------------*
CLASS zcl_fa_calculo_fraudes DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.

    TYPES:
      BEGIN OF ty_entrada,
        cups             TYPE ext_ui,
        fecha_desde      TYPE dats,
        fecha_hasta      TYPE dats,
        consumo_p1       TYPE menge_d,
        consumo_p2       TYPE menge_d,
        consumo_p3       TYPE menge_d,
        consumo_p4       TYPE menge_d,
        consumo_p5       TYPE menge_d,
        consumo_p6       TYPE menge_d,
        consumo_total    TYPE menge_d,
        num_factura_atr  TYPE zle_de_factur,
        tipo_factura_atr TYPE char2,
        contrato         TYPE vertrag,
        id_proceso_atr   TYPE char2,
        forzado          TYPE xfeld,
        solo_calculo     TYPE xfeld,
        id_expediente    TYPE zle_de_numeroexpediente,
      END OF ty_entrada,

      BEGIN OF ty_resultado,
        resultado   TYPE char2,
        codigo      TYPE char4,
        descripcion TYPE string,
        modo        TYPE char30,
        facturas    TYPE zfa_t_fraudes_factura,
        lineas      TYPE zfa_t_fraudes_linea,
      END OF ty_resultado.

    METHODS ejecutar
      IMPORTING is_entrada          TYPE ty_entrada
      RETURNING VALUE(rs_resultado) TYPE ty_resultado.

  PRIVATE SECTION.

    TYPES:
      ty_cantidad TYPE p LENGTH 15 DECIMALS 3,
      ty_precio   TYPE p LENGTH 16 DECIMALS 8,
      ty_importe  TYPE p LENGTH 15 DECIMALS 2,

      " Línea de cálculo: tanto las leídas del cálculo original como las
      " que se generan para el cálculo manual
      BEGIN OF ty_linea,
        belzeile TYPE dberchz1-belzeile,
        belzart  TYPE dberchz1-belzart,
        tipo     TYPE char2,
        periodo  TYPE char2,
        ab       TYPE dats,
        bis      TYPE dats,
        cantidad TYPE ty_cantidad,
        precio   TYPE ty_precio,
        importe  TYPE ty_importe,
      END OF ty_linea,
      ty_t_linea TYPE STANDARD TABLE OF ty_linea WITH DEFAULT KEY,

      BEGIN OF ty_calculo,
        belnr    TYPE erch-belnr,
        begabrpe TYPE erch-begabrpe,
        endabrpe TYPE erch-endabrpe,
      END OF ty_calculo,

      BEGIN OF ty_ever,
        anlage      TYPE ever-anlage,
        vkonto      TYPE ever-vkonto,
        sparte      TYPE ever-sparte,
        bukrs       TYPE ever-bukrs,
        kofiz       TYPE ever-kofiz,
        einzdat     TYPE ever-einzdat,
        auszdat     TYPE ever-auszdat,
        xvera       TYPE ever-xvera,
        einzdat_alt TYPE ever-einzdat_alt,
        abrsperr    TYPE ever-abrsperr,
      END OF ty_ever,

      BEGIN OF ty_factura,
        exbel       TYPE erdk-exbel,
        tobreleasd  TYPE erdk-tobreleasd,
        total_amnt  TYPE erdk-total_amnt,
        total_waer  TYPE erdk-total_waer,
      END OF ty_factura,

      BEGIN OF ty_concepto_atr,
        concepto TYPE char4,
        importe  TYPE ty_importe,
      END OF ty_concepto_atr,
      ty_t_concepto_atr TYPE STANDARD TABLE OF ty_concepto_atr WITH DEFAULT KEY,

      ty_t_conceptos TYPE STANDARD TABLE OF zfa_fraud_conc WITH DEFAULT KEY,

      ty_t_erchz     TYPE STANDARD TABLE OF erchz WITH DEFAULT KEY.

    CONSTANTS:
      gc_ok                 TYPE char2 VALUE 'OK',
      gc_ko                 TYPE char2 VALUE 'KO',

      " TODO verificar los valores de división del sistema
      gc_sparte_luz         TYPE sparte VALUE '01',
      gc_sparte_gas         TYPE sparte VALUE '02',

      " Tipos de concepto (ZFA_FRAUD_CONC-TIPO)
      gc_tipo_energia       TYPE char2 VALUE 'EN',
      gc_tipo_potencia      TYPE char2 VALUE 'PO',
      gc_tipo_iee           TYPE char2 VALUE 'IE',
      gc_tipo_iee_min       TYPE char2 VALUE 'IM',
      gc_tipo_descuento     TYPE char2 VALUE 'DE',
      gc_tipo_term_variable TYPE char2 VALUE 'TV',
      gc_tipo_hidrocarb     TYPE char2 VALUE 'IH',
      " Conceptos que, además de energía y potencia, forman la base del IEE
      " en el cálculo original (p. ej. EBONSO, financiación bono social)
      gc_tipo_base_iee      TYPE char2 VALUE 'BI',
      " Líneas informativas que se copian tal cual del cálculo original
      " (p. ej. EPROD/GPROD: la derivación CO-PA de ZFI_FM_ISU_SAMPLE_TE760
      " saca de ahí el producto y sin ella no se puede grabar)
      gc_tipo_informativa   TYPE char2 VALUE 'IN',

      " Conceptos fijos indicados en el DF
      gc_belzart_erepos     TYPE dberchz1-belzart VALUE 'EREPOS',
      gc_belzart_grepos     TYPE dberchz1-belzart VALUE 'GREPOS',
      gc_belzart_pgintr     TYPE dberchz1-belzart VALUE 'PGINTR',
      gc_belzart_pgirap     TYPE dberchz1-belzart VALUE 'PGIRAP',
      gc_concepto_atr_1923  TYPE char4 VALUE '1923',
      gc_concepto_atr_1924  TYPE char4 VALUE '1924',

      " IEE mínimo según DF: consumo / 1000 * 1 EUR, es decir 0,001 EUR/kWh
      " (mismo precio que la línea EMIC de los cálculos reales)
      gc_iee_minimo_kwh     TYPE ty_precio VALUE '0.001',

      " TODO pedir a Aleix el operando de reposición. Mientras esté vacío
      " la validación no se hace.
      gc_operando_reposicion TYPE ettifn-operand VALUE '',

      " Tipos de tarifa de Tarifa Plana (vistos en ERCHZ-TARIFTYP de
      " cálculos reales). TODO confirmar con Aleix que no hay más
      gc_tariftyp_plana_luz  TYPE eanlh-tariftyp VALUE 'E_PLANA',
      gc_tariftyp_plana_gas  TYPE eanlh-tariftyp VALUE 'G_PLANA',

      " Cabecera de los cálculos manuales (vistos en los ERCH con
      " MANBILLREL = X de calidad): tipo de cálculo 06, operación principal
      " 0300, clase de documento MN, motivo 01
      " TODO confirmar con Aleix el motivo (BERGRUND: 01 / 02)
      gc_abrvorg_manual     TYPE erch-abrvorg  VALUE '06',
      gc_hvorg_manual       TYPE erch-hvorg    VALUE '0300',
      gc_belegart_manual    TYPE erch-belegart VALUE 'MN',
      gc_bergrund_manual    TYPE erch-bergrund VALUE '01',
      " Campos Z de la cabecera. La exit ZXBI1U01 (EXIT_SAPLEA01_001) los
      " pisa siempre con X_OBJ-CUST, que en un cálculo manual va vacío, y
      " solo los rellena con el popup de EA16/EA17. Sin diálogo se los
      " pasamos por memoria (gc_memoria_erch) y la exit los recoge.
      " ORIGDOC 40 fraude / 41 avería -> serie F + letra del KOFIZ
      gc_memoria_erch       TYPE char30 VALUE 'ZFA_FRAUDES_ERCH',
      gc_origdoc_fraude     TYPE erch-origdoc VALUE '40',
      gc_origdoc_averia     TYPE erch-origdoc VALUE '41',
      " Tipo de factura ATR (correo de Eliza, 27/10): luz 06 anomalía y 11
      " fraude; gas va siempre con tipo 99 y la IA envía en su lugar el
      " tipo de complementaria, AN anomalía y FR fraude
      gc_tipo_atr_anomalia_luz TYPE char2 VALUE '06',
      gc_tipo_atr_fraude_luz   TYPE char2 VALUE '11',
      gc_tipo_atr_anomalia_gas TYPE char2 VALUE 'AN',
      gc_tipo_atr_fraude_gas   TYPE char2 VALUE 'FR',
      " Única validación de facturación cuyo apartado libera la RFC: los
      " fraudes casi siempre son de periodos de hace más de un año
      gc_validacion_ciclo   TYPE erdo-validat_in VALUE 'ZCICLO',

      gc_modo_normal        TYPE char30 VALUE 'NORMAL',
      gc_modo_cero          TYPE char30 VALUE 'IMPORTE_CERO'.

    DATA: ms_entrada   TYPE ty_entrada,
          mv_anlage    TYPE anlage,
          mv_vkonto    TYPE vkont_kk,
          mv_sparte    TYPE sparte,
          mv_bukrs     TYPE bukrs,
          mv_kofiz     TYPE ever-kofiz,
          mv_gpartner  TYPE erch-gpartner,
          mv_portion   TYPE erch-portion,
          mv_ableinh   TYPE erch-ableinh,
          " Datos del contrato para las validaciones de integridad
          ms_ever      TYPE ty_ever,
          " Factura ATR (paso de proceso de /IDXGC/PRST_INHD)
          mv_proc_ref      TYPE /idxgc/prst_inhd-proc_ref,
          mv_proc_step_ref TYPE /idxgc/prst_inhd-proc_step_ref,
          mt_conceptos TYPE ty_t_conceptos,
          " Líneas del cálculo original tal cual (ERCHZ), para heredar
          " operación, tarifa, unidad, etc. en el cálculo manual
          mt_erchz_original TYPE ty_t_erchz,
          " Cálculo y factura creados: se devuelven aunque luego falle algo,
          " porque el cálculo ya está grabado
          ms_factura   TYPE zfa_s_fraudes_factura,
          " Motivos por los que la factura queda apartada sin liberar
          mv_motivos_apartado TYPE string.

    METHODS procesar
      RETURNING VALUE(rs_resultado) TYPE ty_resultado
      RAISING   zcx_fa_fraudes.

    METHODS validar_entrada
      RAISING zcx_fa_fraudes.

    METHODS validar_obligatorios
      RAISING zcx_fa_fraudes.

    METHODS existe_factura_atr
      RETURNING VALUE(rv_existe) TYPE abap_bool.

    METHODS validar_integridad
      RAISING zcx_fa_fraudes.

    METHODS lineas_importe_cero
      RETURNING VALUE(rt_lineas) TYPE ty_t_linea
      RAISING   zcx_fa_fraudes.

    METHODS buscar_calculo_original
      RETURNING VALUE(rs_calculo) TYPE ty_calculo
      RAISING   zcx_fa_fraudes.

    METHODS leer_lineas_calculo
      IMPORTING iv_belnr         TYPE erch-belnr
      RETURNING VALUE(rt_lineas) TYPE ty_t_linea
      RAISING   zcx_fa_fraudes.

    METHODS leer_erchz
      IMPORTING iv_belnr        TYPE erch-belnr
      RETURNING VALUE(rt_erchz) TYPE ty_t_erchz.

    METHODS plantilla_linea
      IMPORTING iv_belzart      TYPE erchz-belzart
      RETURNING VALUE(rs_erchz) TYPE erchz.

    METHODS calcular_luz
      IMPORTING it_original      TYPE ty_t_linea
      RETURNING VALUE(rt_lineas) TYPE ty_t_linea
      RAISING   zcx_fa_fraudes.

    METHODS calcular_gas
      IMPORTING it_original      TYPE ty_t_linea
      RETURNING VALUE(rt_lineas) TYPE ty_t_linea
      RAISING   zcx_fa_fraudes.

    METHODS leer_conceptos_atr
      RETURNING VALUE(rt_conceptos) TYPE ty_t_concepto_atr
      RAISING   zcx_fa_fraudes.

    METHODS prorratear
      IMPORTING iv_consumo       TYPE ty_cantidad
                it_fracciones    TYPE ty_t_linea
      RETURNING VALUE(rt_lineas) TYPE ty_t_linea
      RAISING   zcx_fa_fraudes.

    METHODS dias_solape
      IMPORTING iv_ab          TYPE dats
                iv_bis         TYPE dats
      RETURNING VALUE(rv_dias) TYPE i.

    METHODS aplicar_descuentos
      IMPORTING it_descuentos    TYPE ty_t_linea
                iv_base_original TYPE ty_importe
                iv_base_nueva    TYPE ty_importe
      RETURNING VALUE(rt_lineas) TYPE ty_t_linea.

    METHODS calcular_iee
      IMPORTING it_original     TYPE ty_t_linea
                iv_base         TYPE ty_importe
                iv_consumo      TYPE ty_cantidad
      RETURNING VALUE(rs_linea) TYPE ty_linea
      RAISING   zcx_fa_fraudes.

    METHODS concepto_relacionado
      IMPORTING iv_belzart        TYPE dberchz1-belzart
      RETURNING VALUE(rv_belzart) TYPE dberchz1-belzart
      RAISING   zcx_fa_fraudes.

    METHODS potencia_mayor
      IMPORTING it_original      TYPE ty_t_linea
      RETURNING VALUE(rt_lineas) TYPE ty_t_linea.

    METHODS crear_calculo_manual
      IMPORTING it_lineas TYPE ty_t_linea
      RAISING   zcx_fa_fraudes.

    METHODS facturar
      RETURNING VALUE(rv_apartado) TYPE abap_bool
      RAISING   zcx_fa_fraudes.

    METHODS anular_calculo
      IMPORTING iv_motivo TYPE string
      RAISING   zcx_fa_fraudes.

    METHODS leer_factura
      IMPORTING iv_opbel          TYPE erdk-opbel
      RETURNING VALUE(rs_factura) TYPE ty_factura.

    METHODS registrar_log
      IMPORTING is_resultado TYPE ty_resultado.

    CLASS-METHODS lineas_tipo
      IMPORTING it_lineas        TYPE ty_t_linea
                iv_tipo          TYPE char2
      RETURNING VALUE(rt_lineas) TYPE ty_t_linea.

    CLASS-METHODS sumar_importes
      IMPORTING it_lineas         TYPE ty_t_linea
      RETURNING VALUE(rv_importe) TYPE ty_importe.

ENDCLASS.



CLASS zcl_fa_calculo_fraudes IMPLEMENTATION.

  METHOD ejecutar.

    ms_entrada = is_entrada.

    TRY.
        rs_resultado = procesar( ).
      CATCH zcx_fa_fraudes INTO DATA(lx_fraudes).
        ROLLBACK WORK.
        CLEAR rs_resultado.
        rs_resultado-codigo      = lx_fraudes->codigo.
        rs_resultado-descripcion = lx_fraudes->texto.
        IF ms_factura-calculo IS NOT INITIAL.
          APPEND ms_factura TO rs_resultado-facturas.
        ENDIF.
    ENDTRY.

    " 0xxx (factura creada o descarte) es OK; 1xxx y 2xxx son KO
    rs_resultado-resultado = COND #( WHEN rs_resultado-codigo(1) = '0' THEN gc_ok
                                     ELSE gc_ko ).

    " Graba el log y hace el COMMIT de todo lo anterior
    registrar_log( rs_resultado ).

  ENDMETHOD.


  METHOD procesar.

    DATA: ls_calculo  TYPE ty_calculo,
          lt_original TYPE ty_t_linea,
          lt_lineas   TYPE ty_t_linea,
          lv_waers    TYPE waers.

    validar_entrada( ).

    " Con el indicador de forzado (sustituye a los antiguos descarte y
    " titular erróneo) se factura a 0 sin pasar por las validaciones de
    " integridad: la IA ya ha decidido que el caso va a 0
    IF ms_entrada-forzado = abap_true.
      lt_lineas = lineas_importe_cero( ).
      rs_resultado-codigo      = '0001'.
      rs_resultado-descripcion = 'Factura a importe 0 (forzada) creada correctamente'.
      rs_resultado-modo        = gc_modo_cero.
    ELSE.
      validar_integridad( ).

      ls_calculo  = buscar_calculo_original( ).
      lt_original = leer_lineas_calculo( ls_calculo-belnr ).

      CASE mv_sparte.
        WHEN gc_sparte_luz.
          lt_lineas = calcular_luz( lt_original ).
        WHEN gc_sparte_gas.
          lt_lineas = calcular_gas( lt_original ).
        WHEN OTHERS.
          RAISE EXCEPTION TYPE zcx_fa_fraudes
            EXPORTING codigo = '2002'
                      texto  = |División { mv_sparte } no contemplada|.
      ENDCASE.

      rs_resultado-codigo      = '0000'.
      rs_resultado-descripcion = 'Factura creada correctamente'.
      rs_resultado-modo        = gc_modo_normal.
    ENDIF.

    lv_waers = VALUE #( mt_erchz_original[ 1 ]-twaers OPTIONAL ).

    " Solo cálculo: se devuelve el detalle sin grabar nada en SAP (ni
    " cálculo manual ni factura). Importe neto: los impuestos de la
    " factura (IVA) los calcula la facturación
    IF ms_entrada-solo_calculo = abap_true.
      rs_resultado-codigo      = '0010'.
      rs_resultado-descripcion = 'Cálculo realizado sin facturar (importe neto, sin IVA)'.
      rs_resultado-lineas      = VALUE #( FOR ls_linea IN lt_lineas
                                          ( belzart  = ls_linea-belzart
                                            tipo     = ls_linea-tipo
                                            desde    = COND #( WHEN ls_linea-ab IS NOT INITIAL THEN ls_linea-ab
                                                               ELSE ms_entrada-fecha_desde )
                                            hasta    = COND #( WHEN ls_linea-bis IS NOT INITIAL THEN ls_linea-bis
                                                               ELSE ms_entrada-fecha_hasta )
                                            cantidad = ls_linea-cantidad
                                            precio   = ls_linea-precio
                                            importe  = ls_linea-importe
                                            waers    = lv_waers ) ).
      rs_resultado-facturas    = VALUE #( ( consumo     = ms_entrada-consumo_total
                                            importe     = sumar_importes( lt_lineas )
                                            waers       = lv_waers
                                            fecha_desde = ms_entrada-fecha_desde
                                            fecha_hasta = ms_entrada-fecha_hasta ) ).
      RETURN.
    ENDIF.

    crear_calculo_manual( lt_lineas ).

    " Apartada y sin poder liberarla (EA05): el documento de impresión es
    " provisional y cambia al liberar, así que no se devuelve
    IF facturar( ) = abap_true.
      rs_resultado-codigo      = '0003'.
      rs_resultado-descripcion = |Factura creada pero apartada por{ mv_motivos_apartado }: revisar y liberar en EA05 (cálculo { ms_factura-calculo })|.
    ENDIF.
    rs_resultado-facturas = VALUE #( ( ms_factura ) ).

  ENDMETHOD.


  METHOD validar_entrada.

    DATA: lv_codigo  TYPE char4,
          lv_int_ui  TYPE int_ui,
          lv_anlage  TYPE anlage,
          lv_tipo_ok TYPE abap_bool.

    validar_obligatorios( ).

    IF ms_entrada-fecha_desde > ms_entrada-fecha_hasta.
      RAISE EXCEPTION TYPE zcx_fa_fraudes
        EXPORTING codigo = '1007'
                  texto  = 'La fecha desde es posterior a la fecha hasta'.
    ENDIF.

    " El mismo expediente no se factura dos veces
    SELECT SINGLE codigo
      FROM zfa_fraud_log
      WHERE id_expediente = @ms_entrada-id_expediente
        AND codigo        IN ( '0000', '0001', '0002', '0003' )
      INTO @lv_codigo.
    IF sy-subrc = 0.
      RAISE EXCEPTION TYPE zcx_fa_fraudes
        EXPORTING codigo = '1006'
                  texto  = |El expediente { ms_entrada-id_expediente } ya está facturado|.
    ENDIF.

    " 1.1 El CUPS existe
    SELECT SINGLE int_ui
      FROM euitrans
      WHERE ext_ui    = @ms_entrada-cups
        AND datefrom <= @ms_entrada-fecha_hasta
        AND dateto   >= @ms_entrada-fecha_desde
      INTO @lv_int_ui.
    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE zcx_fa_fraudes
        EXPORTING codigo = '1001'
                  texto  = |El CUPS { ms_entrada-cups } no existe en el sistema|.
    ENDIF.

    " 1.2 El contrato existe y su instalación es la del CUPS
    SELECT SINGLE anlage, vkonto, sparte, bukrs, kofiz, einzdat, auszdat,
                  xvera, einzdat_alt, abrsperr
      FROM ever
      WHERE vertrag = @ms_entrada-contrato
      INTO @ms_ever.
    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE zcx_fa_fraudes
        EXPORTING codigo = '1002'
                  texto  = |El contrato { ms_entrada-contrato } no existe|.
    ENDIF.

    SELECT SINGLE anlage
      FROM euiinstln
      WHERE int_ui    = @lv_int_ui
        AND anlage    = @ms_ever-anlage
        AND datefrom <= @ms_entrada-fecha_hasta
        AND dateto   >= @ms_entrada-fecha_desde
      INTO @lv_anlage.
    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE zcx_fa_fraudes
        EXPORTING codigo = '1002'
                  texto  = |El CUPS { ms_entrada-cups } no corresponde al contrato { ms_entrada-contrato }|.
    ENDIF.

    " 1.3 Contrato activo en todo el periodo
    IF ms_ever-einzdat > ms_entrada-fecha_desde OR ms_ever-auszdat < ms_entrada-fecha_hasta.
      RAISE EXCEPTION TYPE zcx_fa_fraudes
        EXPORTING codigo = '1003'
                  texto  = |El contrato { ms_entrada-contrato } no está activo en el periodo|.
    ENDIF.

    mv_anlage = ms_ever-anlage.
    mv_vkonto = ms_ever-vkonto.
    mv_sparte = ms_ever-sparte.
    mv_bukrs  = ms_ever-bukrs.
    mv_kofiz  = ms_ever-kofiz.

    " Interlocutor de la cuenta contrato (para la cabecera del cálculo)
    SELECT SINGLE gpart
      FROM fkkvkp
      WHERE vkont = @mv_vkonto
      INTO @mv_gpartner.

    " 1.4 Factura ATR de anomalía o fraude (según la división) y existente
    lv_tipo_ok = SWITCH #( mv_sparte
                   WHEN gc_sparte_luz THEN xsdbool( ms_entrada-tipo_factura_atr = gc_tipo_atr_anomalia_luz OR
                                                    ms_entrada-tipo_factura_atr = gc_tipo_atr_fraude_luz )
                   WHEN gc_sparte_gas THEN xsdbool( ms_entrada-tipo_factura_atr = gc_tipo_atr_anomalia_gas OR
                                                    ms_entrada-tipo_factura_atr = gc_tipo_atr_fraude_gas ) ).
    IF lv_tipo_ok = abap_false.
      RAISE EXCEPTION TYPE zcx_fa_fraudes
        EXPORTING codigo = '1004'
                  texto  = |Tipo de factura ATR { ms_entrada-tipo_factura_atr } no válido (luz 06/11, gas AN/FR)|.
    ENDIF.

    IF existe_factura_atr( ) = abap_false.
      RAISE EXCEPTION TYPE zcx_fa_fraudes
        EXPORTING codigo = '1004'
                  texto  = |La factura ATR { ms_entrada-num_factura_atr } no existe|.
    ENDIF.

    " 1.5 Consumo ATR vs consumo total: lo controla la IA, que envía ya el
    " consumo a facturar (correo de Eliza del 26/10, confirmado por Aleix)

    " Conceptos de facturación relevantes para la división del contrato
    SELECT *
      FROM zfa_fraud_conc
      WHERE sparte = @mv_sparte
      INTO TABLE @mt_conceptos.

  ENDMETHOD.


  METHOD validar_obligatorios.

    DATA lv_campo TYPE string.

    IF ms_entrada-cups IS INITIAL.
      lv_campo = 'IV_CUPS'.
    ELSEIF ms_entrada-fecha_desde IS INITIAL.
      lv_campo = 'IV_FECHA_DESDE'.
    ELSEIF ms_entrada-fecha_hasta IS INITIAL.
      lv_campo = 'IV_FECHA_HASTA'.
    ELSEIF ms_entrada-consumo_total IS INITIAL.
      lv_campo = 'IV_CONSUMO_TOTAL'.
    ELSEIF ms_entrada-num_factura_atr IS INITIAL.
      lv_campo = 'IV_NUM_FACTURA_ATR'.
    ELSEIF ms_entrada-tipo_factura_atr IS INITIAL.
      lv_campo = 'IV_TIPO_FACTURA_ATR'.
    ELSEIF ms_entrada-contrato IS INITIAL.
      lv_campo = 'IV_CONTRATO_SAP'.
    ELSEIF ms_entrada-id_proceso_atr IS INITIAL.
      lv_campo = 'IV_ID_PROCESO_ATR'.
    ELSEIF ms_entrada-id_expediente IS INITIAL.
      lv_campo = 'IV_ID_EXPEDIENTE'.
    ENDIF.

    IF lv_campo IS NOT INITIAL.
      RAISE EXCEPTION TYPE zcx_fa_fraudes
        EXPORTING codigo = '1000'
                  texto  = |El parámetro { lv_campo } es obligatorio|.
    ENDIF.

  ENDMETHOD.


  METHOD existe_factura_atr.
    " Cabecera de la factura ATR recibida (Aleix 29/10). Se guarda el paso
    " de proceso para leer luego sus conceptos en /IDXGC/PRST_CHRG
    " Por el índice ZCF (CODIGOFISCALFACTURA)
    SELECT proc_ref, proc_step_ref
      FROM /idxgc/prst_inhd
      WHERE codigofiscalfactura = @ms_entrada-num_factura_atr
      ORDER BY proc_ref DESCENDING
      INTO TABLE @DATA(lt_factura)
      UP TO 1 ROWS.
    IF lt_factura IS NOT INITIAL.
      mv_proc_ref      = lt_factura[ 1 ]-proc_ref.
      mv_proc_step_ref = lt_factura[ 1 ]-proc_step_ref.
      rv_existe = abap_true.
    ENDIF.
  ENDMETHOD.


  METHOD validar_integridad.

    DATA lv_anlage TYPE anlage.

    " Solo se comprueba si existe la fila
    DATA: lv_loobj1   TYPE dfkklocks-loobj1,
          lv_contrato TYPE vertrag ##NEEDED,
          lv_partner  TYPE bu_partner ##NEEDED,
          lv_bloqueo  TYPE dfkklocks-loobj1 ##NEEDED.

    " Orígenes de los datos: correo de Aleix del 29/10

    " 2.1 Periodo migrado: contrato traído de otro sistema y periodo
    " anterior a su alta en el sistema antiguo
    IF ms_ever-xvera = abap_true AND ms_entrada-fecha_hasta < ms_ever-einzdat_alt.
      RAISE EXCEPTION TYPE zcx_fa_fraudes
        EXPORTING codigo = '0101'
                  texto  = 'Descarte: periodo migrado (facturado en el sistema antiguo)'.
    ENDIF.

    " 2.2 Exención de impuestos: CIE del contrato vigente en el periodo
    SELECT SINGLE contrato
      FROM zfa_t_cie
      WHERE contrato = @ms_entrada-contrato
        AND ab      <= @ms_entrada-fecha_hasta
        AND bis     >= @ms_entrada-fecha_desde
      INTO @lv_contrato.
    IF sy-subrc = 0.
      RAISE EXCEPTION TYPE zcx_fa_fraudes
        EXPORTING codigo = '0102'
                  texto  = 'Descarte: contrato con exención de impuestos (CIE) en el periodo'.
    ENDIF.

    " 2.3 Derecho al olvido: cliente con solicitud de ofuscación
    " TODO confirmar si cuenta cualquier solicitud o solo las procesadas
    SELECT SINGLE partner
      FROM zco_t_ofusc_clie
      WHERE partner = @mv_gpartner
      INTO @lv_partner.
    IF sy-subrc = 0.
      RAISE EXCEPTION TYPE zcx_fa_fraudes
        EXPORTING codigo = '0103'
                  texto  = 'Descarte: cliente con derecho al olvido'.
    ENDIF.

    " 2.4 Esencialidad o vulnerabilidad (pobreza energética) en el periodo
    " TODO confirmar los valores de ZZVULNERABLE que cuentan
    SELECT SINGLE zzvital, zzinicio_vital, zzfin_vital,
                  zzvulnerable, zzinicio_vulner, zzfin_vulner
      FROM eanl
      WHERE anlage = @mv_anlage
      INTO @DATA(ls_eanl).
    IF ( ls_eanl-zzvital IS NOT INITIAL AND ls_eanl-zzvital <> '00'
         AND ls_eanl-zzinicio_vital <= ms_entrada-fecha_hasta
         AND ( ls_eanl-zzfin_vital >= ms_entrada-fecha_desde OR ls_eanl-zzfin_vital IS INITIAL ) )
    OR ( ls_eanl-zzvulnerable IS NOT INITIAL AND ls_eanl-zzvulnerable <> '00'
         AND ls_eanl-zzinicio_vulner <= ms_entrada-fecha_hasta
         AND ( ls_eanl-zzfin_vulner >= ms_entrada-fecha_desde OR ls_eanl-zzfin_vulner IS INITIAL ) ).
      RAISE EXCEPTION TYPE zcx_fa_fraudes
        EXPORTING codigo = '0104'
                  texto  = 'Descarte: cliente vulnerable o esencial en el periodo'.
    ENDIF.

    " 2.5 Bloqueos: cualquier bloqueo de la cuenta contrato vigente en el
    " periodo, o bloqueo de cálculo en el contrato
    IF ms_ever-abrsperr IS NOT INITIAL.
      RAISE EXCEPTION TYPE zcx_fa_fraudes
        EXPORTING codigo = '0105'
                  texto  = |Descarte: contrato con bloqueo de cálculo ({ ms_ever-abrsperr })|.
    ENDIF.

    lv_loobj1 = |{ mv_vkonto }{ mv_gpartner }|.
    SELECT SINGLE loobj1
      FROM dfkklocks
      WHERE lotyp  = '06'
        AND loobj1 = @lv_loobj1
        AND fdate <= @ms_entrada-fecha_hasta
        AND tdate >= @ms_entrada-fecha_desde
      INTO @lv_bloqueo.
    IF sy-subrc = 0.
      RAISE EXCEPTION TYPE zcx_fa_fraudes
        EXPORTING codigo = '0105'
                  texto  = 'Descarte: cuenta contrato bloqueada en el periodo'.
    ENDIF.


    " 2.6 Operando de reposición activo en el periodo
    IF gc_operando_reposicion IS NOT INITIAL.
      " TODO confirmar si basta con que exista el operando en el periodo
      " o hay que mirar su valor
      SELECT SINGLE anlage
        FROM ettifn
        WHERE anlage  = @mv_anlage
          AND operand = @gc_operando_reposicion
          AND ab     <= @ms_entrada-fecha_hasta
          AND bis    >= @ms_entrada-fecha_desde
        INTO @lv_anlage.
      IF sy-subrc = 0.
        RAISE EXCEPTION TYPE zcx_fa_fraudes
          EXPORTING codigo = '0106'
                    texto  = 'Descarte: operando de reposición activo en el periodo'.
      ENDIF.
    ENDIF.

    " 2.7 Tarifa Plana en el periodo: tipo de tarifa de la instalación
    SELECT SINGLE anlage
      FROM eanlh
      WHERE anlage   = @mv_anlage
        AND tariftyp IN ( @gc_tariftyp_plana_luz, @gc_tariftyp_plana_gas )
        AND ab      <= @ms_entrada-fecha_hasta
        AND bis     >= @ms_entrada-fecha_desde
      INTO @lv_anlage.
    IF sy-subrc = 0.
      RAISE EXCEPTION TYPE zcx_fa_fraudes
        EXPORTING codigo = '0107'
                  texto  = 'Descarte: cliente con Tarifa Plana en el periodo'.
    ENDIF.

  ENDMETHOD.


  METHOD lineas_importe_cero.

    DATA: ls_linea    TYPE ty_linea,
          lt_original TYPE ty_t_linea,
          lv_belnr    TYPE erch-belnr.

    " Mismo tratamiento que las reposiciones: se contabiliza el consumo
    " con EREPOS/GREPOS e importe 0
    CASE mv_sparte.
      WHEN gc_sparte_luz.
        ls_linea-belzart = gc_belzart_erepos.
      WHEN gc_sparte_gas.
        ls_linea-belzart = gc_belzart_grepos.
      WHEN OTHERS.
        RAISE EXCEPTION TYPE zcx_fa_fraudes
          EXPORTING codigo = '2002'
                    texto  = |División { mv_sparte } no contemplada|.
    ENDCASE.

    ls_linea-ab       = ms_entrada-fecha_desde.
    ls_linea-bis      = ms_entrada-fecha_hasta.
    ls_linea-cantidad = ms_entrada-consumo_total.
    APPEND ls_linea TO rt_lineas.

    " Las líneas informativas (producto, etc.) se toman del último cálculo
    " del contrato
    SELECT belnr
      FROM erch
      WHERE vertrag    = @ms_entrada-contrato
        AND stornodat  = '00000000'
        AND simulation = @space
      ORDER BY endabrpe DESCENDING
      INTO TABLE @DATA(lt_ultimo)
      UP TO 1 ROWS.
    IF lt_ultimo IS NOT INITIAL.
      lv_belnr = lt_ultimo[ 1 ]-belnr.
      lt_original = leer_lineas_calculo( lv_belnr ).
      lt_original = lineas_tipo( it_lineas = lt_original iv_tipo = gc_tipo_informativa ).
      APPEND LINES OF lt_original TO rt_lineas.
    ENDIF.

  ENDMETHOD.


  METHOD buscar_calculo_original.

    DATA lt_calculos TYPE STANDARD TABLE OF ty_calculo WITH DEFAULT KEY.

    " Cálculos reales (ni simulados ni anulados) que solapan con el periodo
    " TODO verificar en SE11 los campos de ERCH y si hay que filtrar por
    " tipo de cálculo (ABRVORG)
    SELECT belnr, begabrpe, endabrpe
      FROM erch
      WHERE vertrag     = @ms_entrada-contrato
        AND begabrpe   <= @ms_entrada-fecha_hasta
        AND endabrpe   >= @ms_entrada-fecha_desde
        AND stornodat   = '00000000'
        AND simulation  = @space
      INTO TABLE @lt_calculos.

    CASE lines( lt_calculos ).
      WHEN 0.
        RAISE EXCEPTION TYPE zcx_fa_fraudes
          EXPORTING codigo = '0108'
                    texto  = 'Descarte: no hay cálculo para el periodo'.
      WHEN 1.
        rs_calculo = lt_calculos[ 1 ].
      WHEN OTHERS.
        " TODO el DF no dice qué hacer si el periodo cruza varios
        " cálculos. De momento se descarta.
        RAISE EXCEPTION TYPE zcx_fa_fraudes
          EXPORTING codigo = '0109'
                    texto  = 'Descarte: el periodo abarca varios cálculos'.
    ENDCASE.

  ENDMETHOD.


  METHOD leer_erchz.

    DATA: lr_tabla TYPE REF TO data,
          lv_tabla TYPE tabname.

    FIELD-SYMBOLS: <lt_tabla>     TYPE STANDARD TABLE,
                   <ls_fila>      TYPE any,
                   <lv_belzeile>  TYPE any,
                   <lv_entero>    TYPE any,
                   <lv_decimales> TYPE any,
                   <ls_erchz>     TYPE erchz.

    " Las líneas de cálculo (ERCHZ) se guardan repartidas en DBERCHZ1..8,
    " todas con clave BELNR + BELZEILE. Se juntan en una ERCHZ por línea.
    " TODO si aparece el FM estándar que lee el documento entero en
    " ISU2A_BILL_DOC, usarlo en lugar de esto.
    DO 8 TIMES.
      lv_tabla = |DBERCHZ{ sy-index }|.
      TRY.
          CREATE DATA lr_tabla TYPE STANDARD TABLE OF (lv_tabla).
        CATCH cx_sy_create_data_error.
          " Esa DBERCHZn no existe en este release
          CONTINUE.
      ENDTRY.
      ASSIGN lr_tabla->* TO <lt_tabla>.

      SELECT *
        FROM (lv_tabla)
        WHERE belnr = @iv_belnr
        INTO TABLE @<lt_tabla>.

      LOOP AT <lt_tabla> ASSIGNING <ls_fila>.
        ASSIGN COMPONENT 'BELZEILE' OF STRUCTURE <ls_fila> TO <lv_belzeile>.
        READ TABLE rt_erchz ASSIGNING <ls_erchz>
          WITH KEY belzeile = <lv_belzeile>.
        IF sy-subrc <> 0.
          APPEND INITIAL LINE TO rt_erchz ASSIGNING <ls_erchz>.
        ENDIF.
        MOVE-CORRESPONDING <ls_fila> TO <ls_erchz>.

        " En BD la cantidad va partida en enteros (V_ABRMENGE) y decimales
        " (N_ABRMENGE); en ERCHZ va junta en I_ABRMENGE
        ASSIGN COMPONENT 'V_ABRMENGE' OF STRUCTURE <ls_fila> TO <lv_entero>.
        IF sy-subrc = 0.
          ASSIGN COMPONENT 'N_ABRMENGE' OF STRUCTURE <ls_fila> TO <lv_decimales>.
          <ls_erchz>-i_abrmenge = <lv_entero> + <lv_decimales>.
        ENDIF.
      ENDLOOP.
    ENDDO.

  ENDMETHOD.


  METHOD plantilla_linea.

    DATA: lv_belnr     TYPE erch-belnr,
          lv_parametro TYPE tvarvc-name.

    " Para las líneas que no están en el cálculo original (EREPOS/GREPOS,
    " mínimo del IEE...) se copia una línea real del concepto: operación,
    " tarifa, esquema, unidad, impuesto... El cálculo que sirve de
    " plantilla se configura en STVARV (ZFA_FRAUDES_PLANTILLA_<concepto>)
    " porque DBERCHZ1 no tiene índice por BELZART.
    lv_parametro = |ZFA_FRAUDES_PLANTILLA_{ iv_belzart }|.
    SELECT SINGLE low
      FROM tvarvc
      WHERE name = @lv_parametro
        AND type = 'P'
      INTO @lv_belnr.
    IF sy-subrc <> 0 OR lv_belnr IS INITIAL.
      RETURN.
    ENDIF.

    DATA(lt_erchz) = leer_erchz( lv_belnr ).
    READ TABLE lt_erchz INTO rs_erchz WITH KEY belzart = iv_belzart.

  ENDMETHOD.


  METHOD leer_lineas_calculo.

    DATA ls_linea TYPE ty_linea.

    FIELD-SYMBOLS <ls_erchz> TYPE erchz.

    mt_erchz_original = leer_erchz( iv_belnr ).

    " Solo interesan las líneas cuyo concepto está en ZFA_FRAUD_CONC.
    " Cantidad en I_ABRMENGE, precio unitario en PREISBTR e importe en
    " NETTOBTR (DBERCHZ3), comprobado con cálculos reales.
    LOOP AT mt_erchz_original ASSIGNING <ls_erchz>.
      READ TABLE mt_conceptos INTO DATA(ls_concepto)
        WITH KEY belzart = <ls_erchz>-belzart.
      CHECK sy-subrc = 0.

      " Las líneas de abono de una refacturación vienen con cantidad
      " negativa (operación 21xx): no son el cálculo que vale
      CHECK <ls_erchz>-i_abrmenge >= 0 OR ls_concepto-tipo = gc_tipo_descuento.

      ls_linea = VALUE #( belzeile = <ls_erchz>-belzeile
                          belzart  = <ls_erchz>-belzart
                          tipo     = ls_concepto-tipo
                          periodo  = ls_concepto-periodo
                          ab       = <ls_erchz>-ab
                          bis      = <ls_erchz>-bis
                          cantidad = <ls_erchz>-i_abrmenge
                          precio   = <ls_erchz>-preisbtr
                          importe  = <ls_erchz>-nettobtr ).
      APPEND ls_linea TO rt_lineas.
    ENDLOOP.

    IF rt_lineas IS INITIAL.
      RAISE EXCEPTION TYPE zcx_fa_fraudes
        EXPORTING codigo = '2001'
                  texto  = |El cálculo { iv_belnr } no tiene conceptos configurados en ZFA_FRAUD_CONC|.
    ENDIF.

  ENDMETHOD.


  METHOD calcular_luz.

    TYPES: BEGIN OF ty_consumo_periodo,
             periodo TYPE char2,
             consumo TYPE ty_cantidad,
           END OF ty_consumo_periodo.

    DATA: lt_energia   TYPE ty_t_linea,
          lt_fraccion  TYPE ty_t_linea,
          lt_consumos  TYPE STANDARD TABLE OF ty_consumo_periodo WITH DEFAULT KEY,
          lt_aux       TYPE ty_t_linea,
          ls_iee       TYPE ty_linea,
          lv_consumo   TYPE ty_cantidad,
          lv_base      TYPE ty_importe,
          lv_hay_datos TYPE abap_bool.

    lt_energia = lineas_tipo( it_lineas = it_original iv_tipo = gc_tipo_energia ).
    IF lt_energia IS INITIAL.
      RAISE EXCEPTION TYPE zcx_fa_fraudes
        EXPORTING codigo = '2002'
                  texto  = 'El cálculo original no tiene conceptos de energía activa'.
    ENDIF.

    lv_consumo = ms_entrada-consumo_total.

    " Energía activa: un único concepto (consumo agrupado) o uno por periodo
    READ TABLE lt_energia TRANSPORTING NO FIELDS WITH KEY periodo = space.
    IF sy-subrc = 0.
      rt_lineas = prorratear( iv_consumo    = lv_consumo
                              it_fracciones = lt_energia ).
    ELSE.
      lt_consumos = VALUE #( ( periodo = 'P1' consumo = ms_entrada-consumo_p1 )
                             ( periodo = 'P2' consumo = ms_entrada-consumo_p2 )
                             ( periodo = 'P3' consumo = ms_entrada-consumo_p3 )
                             ( periodo = 'P4' consumo = ms_entrada-consumo_p4 )
                             ( periodo = 'P5' consumo = ms_entrada-consumo_p5 )
                             ( periodo = 'P6' consumo = ms_entrada-consumo_p6 ) ).

      LOOP AT lt_consumos INTO DATA(ls_consumo) WHERE consumo > 0.
        lv_hay_datos = abap_true.
        lt_fraccion = VALUE #( FOR ls_energia IN lt_energia
                               WHERE ( periodo = ls_consumo-periodo ) ( ls_energia ) ).
        IF lt_fraccion IS INITIAL.
          RAISE EXCEPTION TYPE zcx_fa_fraudes
            EXPORTING codigo = '2002'
                      texto  = |El cálculo original no tiene energía para el periodo { ls_consumo-periodo }|.
        ENDIF.
        lt_aux = prorratear( iv_consumo    = ls_consumo-consumo
                             it_fracciones = lt_fraccion ).
        APPEND LINES OF lt_aux TO rt_lineas.
      ENDLOOP.

      IF lv_hay_datos = abap_false.
        RAISE EXCEPTION TYPE zcx_fa_fraudes
          EXPORTING codigo = '1008'
                    texto  = 'El contrato factura por periodos y no se han informado consumos P1-P6'.
      ENDIF.
    ENDIF.

    " Descuentos sobre la energía activa
    lt_aux = aplicar_descuentos(
               it_descuentos    = lineas_tipo( it_lineas = it_original iv_tipo = gc_tipo_descuento )
               iv_base_original = sumar_importes( lt_energia )
               iv_base_nueva    = sumar_importes( rt_lineas ) ).
    APPEND LINES OF lt_aux TO rt_lineas.

    " IEE sobre energía neta de descuentos
    " TODO confirmar con Aleix si la base del IEE va antes o después de
    " descuentos
    lv_base = sumar_importes( rt_lineas ).
    ls_iee  = calcular_iee( it_original = it_original
                            iv_base     = lv_base
                            iv_consumo  = lv_consumo ).
    APPEND ls_iee TO rt_lineas.

    " Líneas informativas del original (producto, etc.)
    lt_aux = lineas_tipo( it_lineas = it_original iv_tipo = gc_tipo_informativa ).
    APPEND LINES OF lt_aux TO rt_lineas.

    " Potencia mayor a importe 0, solo para que pinte bien la factura
    lt_aux = potencia_mayor( it_original ).
    APPEND LINES OF lt_aux TO rt_lineas.

  ENDMETHOD.


  METHOD calcular_gas.

    DATA: lt_term_variable TYPE ty_t_linea,
          lt_aux           TYPE ty_t_linea,
          lt_atr           TYPE ty_t_concepto_atr,
          lv_consumo       TYPE ty_cantidad,
          ls_linea         TYPE ty_linea.

    lt_term_variable = lineas_tipo( it_lineas = it_original iv_tipo = gc_tipo_term_variable ).
    IF lt_term_variable IS INITIAL.
      RAISE EXCEPTION TYPE zcx_fa_fraudes
        EXPORTING codigo = '2002'
                  texto  = 'El cálculo original no tiene término variable'.
    ENDIF.

    lv_consumo = ms_entrada-consumo_total.

    " Término variable, prorrateado si hay cambio de precio
    rt_lineas = prorratear( iv_consumo    = lv_consumo
                            it_fracciones = lt_term_variable ).

    " Descuentos sobre el término variable
    lt_aux = aplicar_descuentos(
               it_descuentos    = lineas_tipo( it_lineas = it_original iv_tipo = gc_tipo_descuento )
               iv_base_original = sumar_importes( lt_term_variable )
               iv_base_nueva    = sumar_importes( rt_lineas ) ).
    APPEND LINES OF lt_aux TO rt_lineas.

    " Impuesto de hidrocarburos: precio del propio cálculo original, que es
    " el vigente a su fecha de creación
    " TODO si el original no lo lleva, buscar el precio por fecha
    READ TABLE it_original INTO DATA(ls_hidrocarb) WITH KEY tipo = gc_tipo_hidrocarb.
    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE zcx_fa_fraudes
        EXPORTING codigo = '2002'
                  texto  = 'El cálculo original no tiene impuesto de hidrocarburos'.
    ENDIF.

    CLEAR ls_linea.
    ls_linea-belzeile = ls_hidrocarb-belzeile.
    ls_linea-belzart  = ls_hidrocarb-belzart.
    ls_linea-tipo     = gc_tipo_hidrocarb.
    ls_linea-cantidad = lv_consumo.
    ls_linea-precio   = ls_hidrocarb-precio.
    ls_linea-importe  = lv_consumo * ls_hidrocarb-precio.
    APPEND ls_linea TO rt_lineas.

    " Líneas informativas del original (producto, etc.)
    lt_aux = lineas_tipo( it_lineas = it_original iv_tipo = gc_tipo_informativa ).
    APPEND LINES OF lt_aux TO rt_lineas.

    " Conceptos 1923 / 1924 de la factura ATR -> PGINTR / PGIRAP
    lt_atr = leer_conceptos_atr( ).
    LOOP AT lt_atr INTO DATA(ls_atr).
      CLEAR ls_linea.
      ls_linea-belzart  = SWITCH #( ls_atr-concepto
                                    WHEN gc_concepto_atr_1923 THEN gc_belzart_pgintr
                                    WHEN gc_concepto_atr_1924 THEN gc_belzart_pgirap ).
      ls_linea-cantidad = 1.
      ls_linea-precio   = ls_atr-importe.
      ls_linea-importe  = ls_atr-importe.
      APPEND ls_linea TO rt_lineas.
    ENDLOOP.

  ENDMETHOD.


  METHOD leer_conceptos_atr.

    DATA: lv_texto   TYPE string,
          ls_importe TYPE ty_concepto_atr.

    " Conceptos repercutibles 1923 / 1924 de la factura ATR (Aleix 29/10).
    " El importe viene en texto (formato del fichero ATR)
    SELECT conceptorepercutible, importetotalconceptorepercutib
      FROM /idxgc/prst_chrg
      WHERE proc_ref             = @mv_proc_ref
        AND proc_step_ref        = @mv_proc_step_ref
        AND conceptorepercutible IN ( @gc_concepto_atr_1923, @gc_concepto_atr_1924 )
      INTO TABLE @DATA(lt_cargos).

    LOOP AT lt_cargos INTO DATA(ls_cargo).
      lv_texto = ls_cargo-importetotalconceptorepercutib.
      REPLACE ALL OCCURRENCES OF ',' IN lv_texto WITH '.'.
      CONDENSE lv_texto NO-GAPS.
      CLEAR ls_importe.
      ls_importe-concepto = ls_cargo-conceptorepercutible.
      TRY.
          ls_importe-importe = lv_texto.
        CATCH cx_sy_conversion_no_number.
          RAISE EXCEPTION TYPE zcx_fa_fraudes
            EXPORTING codigo = '2002'
                      texto  = |Importe no numérico en el concepto ATR { ls_cargo-conceptorepercutible }: { ls_cargo-importetotalconceptorepercutib }|.
      ENDTRY.
      APPEND ls_importe TO rt_conceptos.
    ENDLOOP.

  ENDMETHOD.


  METHOD prorratear.

    DATA: lt_fracciones TYPE ty_t_linea,
          lv_dias       TYPE i,
          lv_dias_total TYPE i,
          lv_asignado   TYPE ty_cantidad.

    FIELD-SYMBOLS <ls_linea> TYPE ty_linea.

    " El cálculo puede repetir la misma fracción (concepto + fechas) en
    " varias líneas; para prorratear cuenta una sola vez
    lt_fracciones = it_fracciones.
    SORT lt_fracciones BY belzart ab bis.
    DELETE ADJACENT DUPLICATES FROM lt_fracciones COMPARING belzart ab bis.

    " El consumo se reparte por los días de cada fracción que caen dentro
    " del periodo del expediente
    LOOP AT lt_fracciones INTO DATA(ls_fraccion).
      lv_dias_total = lv_dias_total + dias_solape( iv_ab  = ls_fraccion-ab
                                                   iv_bis = ls_fraccion-bis ).
    ENDLOOP.

    IF lv_dias_total <= 0.
      RAISE EXCEPTION TYPE zcx_fa_fraudes
        EXPORTING codigo = '2002'
                  texto  = 'Los precios del cálculo original no cubren el periodo del expediente'.
    ENDIF.

    LOOP AT lt_fracciones INTO ls_fraccion.
      lv_dias = dias_solape( iv_ab  = ls_fraccion-ab
                             iv_bis = ls_fraccion-bis ).
      CHECK lv_dias > 0.
      ls_fraccion-cantidad = iv_consumo * lv_dias / lv_dias_total.
      lv_asignado = lv_asignado + ls_fraccion-cantidad.
      APPEND ls_fraccion TO rt_lineas.
    ENDLOOP.

    " Lo que se pierda por redondeo va a la última fracción, para que la
    " suma cuadre exactamente con el consumo
    ASSIGN rt_lineas[ lines( rt_lineas ) ] TO <ls_linea>.
    <ls_linea>-cantidad = <ls_linea>-cantidad + iv_consumo - lv_asignado.

    LOOP AT rt_lineas ASSIGNING <ls_linea>.
      <ls_linea>-importe = <ls_linea>-cantidad * <ls_linea>-precio.
    ENDLOOP.

  ENDMETHOD.


  METHOD dias_solape.

    DATA: lv_desde TYPE dats,
          lv_hasta TYPE dats.

    lv_desde = COND #( WHEN iv_ab > ms_entrada-fecha_desde THEN iv_ab
                       ELSE ms_entrada-fecha_desde ).
    lv_hasta = COND #( WHEN iv_bis < ms_entrada-fecha_hasta THEN iv_bis
                       ELSE ms_entrada-fecha_hasta ).

    IF lv_hasta >= lv_desde.
      rv_dias = lv_hasta - lv_desde + 1.
    ENDIF.

  ENDMETHOD.


  METHOD aplicar_descuentos.

    DATA ls_linea TYPE ty_linea.

    " Se mantiene la misma proporción descuento / base que en el cálculo
    " original (vale para descuentos en %).
    " TODO revisar con un caso real si algún descuento es en EUR/kWh
    CHECK iv_base_original <> 0.

    LOOP AT it_descuentos INTO DATA(ls_descuento).
      ls_linea          = ls_descuento.
      ls_linea-importe  = iv_base_nueva * ls_descuento-importe / iv_base_original.
      ls_linea-cantidad = 1.
      ls_linea-precio   = ls_linea-importe.
      APPEND ls_linea TO rt_lineas.
    ENDLOOP.

  ENDMETHOD.


  METHOD calcular_iee.

    DATA: lv_factor      TYPE ty_precio,
          lv_base_orig   TYPE ty_importe,
          lv_importe_pct TYPE ty_importe,
          lv_importe_min TYPE ty_importe.

    READ TABLE it_original INTO DATA(ls_iee) WITH KEY tipo = gc_tipo_iee.
    DATA(lv_hay_iee) = xsdbool( sy-subrc = 0 ).
    READ TABLE it_original INTO DATA(ls_iee_min) WITH KEY tipo = gc_tipo_iee_min.
    DATA(lv_hay_min) = xsdbool( sy-subrc = 0 ).

    IF lv_hay_iee = abap_false AND lv_hay_min = abap_false.
      RAISE EXCEPTION TYPE zcx_fa_fraudes
        EXPORTING codigo = '2002'
                  texto  = 'El cálculo original no tiene impuesto eléctrico'.
    ENDIF.

    IF lv_hay_iee = abap_false.
      " TODO el original se facturó con el mínimo y no lleva el %: hay que
      " buscar el factor del IEE vigente a la fecha de creación del cálculo
      RAISE EXCEPTION TYPE zcx_fa_fraudes
        EXPORTING codigo = '2002'
                  texto  = 'Factor IEE no disponible (original facturado con mínimo)'.
    ENDIF.

    " Factor del IEE en %. La línea de IEE de los cálculos reales no trae
    " precio, solo importe: se saca del original como importe IEE / base,
    " con base = energía + potencia + conceptos BI (bono social).
    " TODO confirmar con Aleix de dónde sale el factor "a fecha de
    " creación del cálculo" (operando o precio) y leerlo de ahí: derivado
    " del importe redondeado puede variar en el último céntimo
    IF ls_iee-precio <> 0.
      lv_factor = ls_iee-precio.
    ELSE.
      lv_base_orig = sumar_importes( lineas_tipo( it_lineas = it_original iv_tipo = gc_tipo_energia ) )
                   + sumar_importes( lineas_tipo( it_lineas = it_original iv_tipo = gc_tipo_potencia ) )
                   + sumar_importes( lineas_tipo( it_lineas = it_original iv_tipo = gc_tipo_base_iee ) ).
      IF lv_base_orig = 0.
        RAISE EXCEPTION TYPE zcx_fa_fraudes
          EXPORTING codigo = '2002'
                    texto  = 'No se puede calcular el factor IEE: base del cálculo original a 0'.
      ENDIF.
      lv_factor = ls_iee-importe * 100 / lv_base_orig.
    ENDIF.

    lv_importe_pct = iv_base * lv_factor / 100.
    lv_importe_min = iv_consumo * gc_iee_minimo_kwh.

    " Se factura el mayor, reutilizando el concepto del original (la región
    " va en el concepto) o su equivalente de mínimo comunitario. Igual que
    " en los cálculos reales: la línea de IEE solo lleva importe y la de
    " mínimo lleva kWh x 0,001 EUR.
    IF lv_importe_pct >= lv_importe_min.
      rs_linea-belzeile = ls_iee-belzeile.
      rs_linea-belzart  = ls_iee-belzart.
      rs_linea-tipo     = gc_tipo_iee.
      rs_linea-importe  = lv_importe_pct.
    ELSE.
      IF lv_hay_min = abap_true.
        rs_linea-belzeile = ls_iee_min-belzeile.
        rs_linea-belzart  = ls_iee_min-belzart.
      ELSE.
        rs_linea-belzart  = concepto_relacionado( ls_iee-belzart ).
      ENDIF.
      rs_linea-tipo     = gc_tipo_iee_min.
      rs_linea-cantidad = iv_consumo.
      rs_linea-precio   = gc_iee_minimo_kwh.
      rs_linea-importe  = lv_importe_min.
    ENDIF.

  ENDMETHOD.


  METHOD concepto_relacionado.

    READ TABLE mt_conceptos INTO DATA(ls_concepto) WITH KEY belzart = iv_belzart.
    IF sy-subrc = 0.
      rv_belzart = ls_concepto-belzart_rel.
    ENDIF.

    IF rv_belzart IS INITIAL.
      RAISE EXCEPTION TYPE zcx_fa_fraudes
        EXPORTING codigo = '2002'
                  texto  = |Falta en ZFA_FRAUD_CONC el concepto de mínimo de { iv_belzart }|.
    ENDIF.

  ENDMETHOD.


  METHOD potencia_mayor.

    DATA ls_mayor TYPE ty_linea.

    LOOP AT it_original INTO DATA(ls_potencia) WHERE tipo = gc_tipo_potencia.
      IF ls_mayor IS INITIAL OR ls_potencia-cantidad > ls_mayor-cantidad.
        ls_mayor = ls_potencia.
      ENDIF.
    ENDLOOP.

    CHECK ls_mayor IS NOT INITIAL.

    " Se mantiene la potencia (kW) para que se imprima; importe a 0
    ls_mayor-precio  = 0.
    ls_mayor-importe = 0.
    APPEND ls_mayor TO rt_lineas.

  ENDMETHOD.


  METHOD crear_calculo_manual.

    DATA: ls_auto      TYPE isu20_manubill_auto,
          ls_erchz     TYPE erchz,
          ls_new_doc   TYPE isu2a_bill_doc,
          lv_db_update TYPE regen-db_update,
          lv_belzeile  TYPE erchz-belzeile,
          lv_codigo    TYPE char4,
          lv_mensaje   TYPE string,
          lt_lineas    TYPE ty_t_linea,
          lv_origdoc    TYPE erch-origdoc,
          lv_serie_nod  TYPE erch-zserie_nod,
          lv_fecha_oper TYPE erch-zfecha_oper_calc,
          lv_subrc      TYPE sy-subrc.

    FIELD-SYMBOLS <lv_campo> TYPE any.

    " Creación sin diálogo de ISU_S_MANUBILL_CREATE (grupo EA16): sin
    " BILL_DOC_USE no hace nada. Las líneas van en BILL_DOC-IERCHZ y cada
    " una se combina con la cabecera REA16 y se valida como si se
    " tecleara en pantalla (ISU_O_MANUBILL_INPUT).
    ls_auto-bill_doc_use = abap_true.

    " Cabecera. FILL_OBJ_REA16_DATA monta REA16 por cada línea así:
    " X_AUTO-REA16 -> línea ERCHZ -> BILL_DOC-ERCH, con MOVE-CORRESPONDING
    " y en ese orden. Los campos de cabecera (los de ERCH) tienen que ir en
    " BILL_DOC-ERCH: lo que se ponga en REA16 con nombre de ERCH se pisa,
    " aunque ERCH venga vacío. En REA16 solo lo que es propio de pantalla.
    " TODO comparar con un cálculo manual hecho a mano en EA20 (SE16 ERCH)
    " por si hace falta algún campo más de cabecera
    ls_auto-bill_doc-erch-vertrag  = ms_entrada-contrato.
    ls_auto-bill_doc-erch-bukrs    = mv_bukrs.
    ls_auto-bill_doc-erch-sparte   = mv_sparte.
    ls_auto-bill_doc-erch-vkont    = mv_vkonto.
    ls_auto-bill_doc-erch-kofiz    = mv_kofiz.
    ls_auto-bill_doc-erch-gpartner = mv_gpartner.

    " Porción y unidad de lectura: las del último cálculo del contrato
    SELECT portion, ableinh
      FROM erch
      WHERE vertrag   = @ms_entrada-contrato
        AND stornodat = '00000000'
      ORDER BY endabrpe DESCENDING
      INTO TABLE @DATA(lt_ultimo)
      UP TO 1 ROWS.
    IF lt_ultimo IS NOT INITIAL.
      mv_portion = lt_ultimo[ 1 ]-portion.
      mv_ableinh = lt_ultimo[ 1 ]-ableinh.
    ENDIF.

    ls_auto-bill_doc-erch-portion  = mv_portion.
    ls_auto-bill_doc-erch-ableinh  = mv_ableinh.
    ls_auto-bill_doc-erch-abrvorg  = gc_abrvorg_manual.
    ls_auto-bill_doc-erch-hvorg    = gc_hvorg_manual.
    ls_auto-bill_doc-erch-belegart = gc_belegart_manual.
    ls_auto-bill_doc-erch-bergrund = gc_bergrund_manual.
    " Campos Z (ver gc_memoria_erch): misma lógica que el popup de la
    " exit para un ORIGDOC 40-43: serie F + letra del KOFIZ, sin forzar
    " y fecha de operación la de hoy
    lv_origdoc = COND #( WHEN ms_entrada-tipo_factura_atr = gc_tipo_atr_fraude_luz OR
                              ms_entrada-tipo_factura_atr = gc_tipo_atr_fraude_gas
                         THEN gc_origdoc_fraude
                         ELSE gc_origdoc_averia ).
    lv_serie_nod = SWITCH #( mv_kofiz
                             WHEN 'DP' THEN 'FE'     " Península
                             WHEN 'DC' THEN 'FC'     " Canarias
                             WHEN 'DE' THEN 'FI'     " Ceuta
                             WHEN 'DM' THEN 'FM' ).  " Melilla
    IF lv_serie_nod IS INITIAL.
      RAISE EXCEPTION TYPE zcx_fa_fraudes
        EXPORTING codigo = '2006'
                  texto  = |KOFIZ { mv_kofiz } del contrato no válido para la serie del documento oficial|.
    ENDIF.
    lv_fecha_oper = sy-datum.
    ls_auto-bill_doc-erch-origdoc          = lv_origdoc.
    ls_auto-bill_doc-erch-zserie_nod       = lv_serie_nod.
    ls_auto-bill_doc-erch-zfecha_oper_calc = lv_fecha_oper.
    ls_auto-bill_doc-erch-abrdats  = sy-datum.
    ls_auto-bill_doc-erch-belegdat = sy-datum.
    ls_auto-bill_doc-erch-begabrpe = ms_entrada-fecha_desde.
    ls_auto-bill_doc-erch-endabrpe = ms_entrada-fecha_hasta.
    ls_auto-rea16-stichtag         = ms_entrada-fecha_hasta.

    " Las informativas (producto) primero, como las pone la EA20
    lt_lineas = VALUE #( FOR ls_inf IN it_lineas WHERE ( tipo = gc_tipo_informativa ) ( ls_inf ) ).
    lt_lineas = VALUE #( BASE lt_lineas
                         FOR ls_resto IN it_lineas WHERE ( tipo <> gc_tipo_informativa ) ( ls_resto ) ).

    LOOP AT lt_lineas INTO DATA(ls_linea).
      " Se parte de la línea original (misma operación, tarifa, unidad,
      " impuesto...) y solo se cambian fechas, cantidad, precio e importe.
      " La cantidad tiene que ir en I_ABRMENGE: FILL_OBJ_REA16_DATA la pasa
      " a MENGE/ABRMENGE y toma la unidad de MASSBILL.
      CLEAR ls_erchz.
      IF ls_linea-belzeile IS NOT INITIAL.
        READ TABLE mt_erchz_original INTO ls_erchz
          WITH KEY belzeile = ls_linea-belzeile.
      ELSE.
        " Línea sin original (EREPOS/GREPOS, mínimo del IEE...): plantilla
        " de una línea real del concepto, con el tipo de tarifa del contrato
        " TODO PGINTR/PGIRAP cuando se sepa de dónde salen
        ls_erchz = plantilla_linea( ls_linea-belzart ).
        READ TABLE mt_erchz_original INTO DATA(ls_contrato) INDEX 1.
        IF sy-subrc = 0.
          ls_erchz-tariftyp = ls_contrato-tariftyp.
        ENDIF.
      ENDIF.
      CLEAR: ls_erchz-belnr.
      lv_belzeile = lv_belzeile + 1.
      ls_erchz-belzeile   = lv_belzeile.
      ls_erchz-belzart    = ls_linea-belzart.
      " Las líneas calculadas sin fechas propias (IEE, mínimo comunitario,
      " conceptos ATR) van con el periodo del expediente
      ls_erchz-ab         = COND #( WHEN ls_linea-ab IS NOT INITIAL THEN ls_linea-ab
                                    ELSE ms_entrada-fecha_desde ).
      ls_erchz-bis        = COND #( WHEN ls_linea-bis IS NOT INITIAL THEN ls_linea-bis
                                    ELSE ms_entrada-fecha_hasta ).
      ls_erchz-i_abrmenge = ls_linea-cantidad.
      ls_erchz-preisbtr   = ls_linea-precio.
      ls_erchz-nettobtr   = ls_linea-importe.
      " Si la línea copiada trae también la cantidad partida (enteros y
      " decimales, formato de BD), se deja coherente con la nueva
      ASSIGN COMPONENT 'V_ABRMENGE' OF STRUCTURE ls_erchz TO <lv_campo>.
      IF sy-subrc = 0.
        <lv_campo> = trunc( ls_linea-cantidad ).
      ENDIF.
      ASSIGN COMPONENT 'N_ABRMENGE' OF STRUCTURE ls_erchz TO <lv_campo>.
      IF sy-subrc = 0.
        <lv_campo> = frac( ls_linea-cantidad ).
      ENDIF.
      APPEND ls_erchz TO ls_auto-bill_doc-ierchz.
    ENDLOOP.

    " TODO confirmar la fecha clave (REA16-STICHTAG) que espera la
    " transacción para un cálculo manual
    EXPORT origdoc          = lv_origdoc
           zserie_nod       = lv_serie_nod
           zfecha_oper_calc = lv_fecha_oper
      TO MEMORY ID gc_memoria_erch.

    CALL FUNCTION 'ISU_S_MANUBILL_CREATE'
      EXPORTING
        x_vertrag      = ms_entrada-contrato
        x_stichtag     = ms_entrada-fecha_hasta
        x_no_dialog    = abap_true
        x_auto         = ls_auto
      IMPORTING
        y_db_update    = lv_db_update
        y_new_bill_doc = ls_new_doc
      EXCEPTIONS
        foreign_lock   = 1
        input_error    = 2
        general_fault  = 3
        bill_lock      = 4
        error_message  = 5
        OTHERS         = 6.
    lv_subrc = sy-subrc.
    FREE MEMORY ID gc_memoria_erch.

    IF lv_subrc <> 0 OR ls_new_doc-erch-belnr IS INITIAL.
      IF sy-msgid IS NOT INITIAL.
        MESSAGE ID sy-msgid TYPE 'E' NUMBER sy-msgno
          WITH sy-msgv1 sy-msgv2 sy-msgv3 sy-msgv4 INTO lv_mensaje.
      ENDIF.
      CASE lv_subrc.
        WHEN 1.
          lv_codigo  = '2005'.
          lv_mensaje = |Contrato bloqueado por otro proceso. { lv_mensaje }|.
        WHEN 4.
          " Bloqueo de facturación del contrato: es el descarte 2.5 del DF
          lv_codigo  = '0105'.
          lv_mensaje = |Descarte: contrato con bloqueo de facturación. { lv_mensaje }|.
        WHEN OTHERS.
          lv_codigo  = '2003'.
          lv_mensaje = |Error creando el cálculo manual. { lv_mensaje }|.
      ENDCASE.
      RAISE EXCEPTION TYPE zcx_fa_fraudes
        EXPORTING codigo = lv_codigo
                  texto  = lv_mensaje.
    ENDIF.

    " El cálculo va en update task y la facturación hace sus propios
    " COMMIT y lee EITR: se graba ya
    COMMIT WORK AND WAIT.

    " IMPORTE es el total de la factura con impuestos: lo pone facturar
    ms_factura-calculo     = ls_new_doc-erch-belnr.
    ms_factura-consumo     = ms_entrada-consumo_total.
    ms_factura-waers       = VALUE #( ls_auto-bill_doc-ierchz[ 1 ]-twaers OPTIONAL ).
    ms_factura-fecha_desde = ms_entrada-fecha_desde.
    ms_factura-fecha_hasta = ms_entrada-fecha_hasta.

  ENDMETHOD.


  METHOD facturar.

    DATA: lt_eitr   TYPE STANDARD TABLE OF eitr WITH DEFAULT KEY,
          lt_opbel  TYPE STANDARD TABLE OF inv_opbel WITH DEFAULT KEY,
          ls_param  TYPE isu21_invoice_param,
          lv_handle TYPE emsg_gen-handle,
          lv_fikey  TYPE fikey_kk,
          lv_opbel  TYPE erdk-opbel,
          lv_nuevo  TYPE erdk-opbel,
          lv_subrc   TYPE sy-subrc,
          lv_mensaje TYPE bapi_msg,
          ls_erdk   TYPE ty_factura.

    " Solo nuestro cálculo: con XT_EITR informado el FM no selecciona lo
    " pendiente de la cuenta (es lo que hace el popup de la EA19)
    SELECT *
      FROM eitr
      WHERE belnr = @ms_factura-calculo
      INTO TABLE @lt_eitr.
    IF lt_eitr IS INITIAL.
      anular_calculo( |Cálculo { ms_factura-calculo } no pendiente de facturar (EITR)| ).
    ENDIF.

    " Clave de reconciliación del día con el formato que propone la EA19
    " (AAMMDD-001); sin diálogo el FM la abre si no existe
    " TODO confirmar la clave con Aleix / FI-CA
    lv_fikey = |{ sy-datum+2(6) }-001|.

    " Sin diálogo ni resultados: los errores salen por excepción y los
    " mensajes quedan en el log de aplicación que abre el propio FM
    CALL FUNCTION 'ISU_INV_SINGLE_PROCESSING'
      EXPORTING
        x_vkonto       = mv_vkonto
        x_fikey        = lv_fikey
        x_dialog       = space
        x_show_results = space
      TABLES
        xt_eitr        = lt_eitr
        yt_opbel       = lt_opbel
      CHANGING
        xy_param       = ls_param
        xy_handle      = lv_handle
      EXCEPTIONS
        iu_error       = 1
        system_error   = 2
        error_message  = 3
        OTHERS         = 4.
    IF sy-subrc = 0.
      lv_opbel = VALUE #( lt_opbel[ 1 ]-opbel OPTIONAL ).
    ENDIF.
    IF lv_opbel IS INITIAL.
      anular_calculo( |Error al facturar el cálculo { ms_factura-calculo } (ver log SLG1)| ).
    ENDIF.

    ls_erdk = leer_factura( lv_opbel ).

    " El total no cambia al liberar un apartado: se devuelve siempre
    ms_factura-importe = ls_erdk-total_amnt.
    ms_factura-waers   = ls_erdk-total_waer.

    " Apartada por una validación (ZCICLO: ciclo > 1 año, casi siempre en
    " fraudes): se libera ya, la factura tiene que salir contabilizada.
    " Al liberar se borra el documento provisional y se crea otro con
    " número nuevo, que es el que se devuelve (como el botón de la EA05)
    IF ls_erdk-tobreleasd IS NOT INITIAL.
      " Solo si todos los apartados pendientes son de ZCICLO: cualquier
      " otra validación o un apartado manual se deja para revisar en EA05
      SELECT validat_in, manouts_in
        FROM erdo
        WHERE opbel   = @lv_opbel
          AND frei_am = '00000000'
        INTO TABLE @DATA(lt_apartados).
      LOOP AT lt_apartados INTO DATA(ls_apartado)
           WHERE validat_in <> gc_validacion_ciclo OR manouts_in IS NOT INITIAL.
        mv_motivos_apartado = |{ mv_motivos_apartado } { ls_apartado-validat_in }{ ls_apartado-manouts_in }|.
      ENDLOOP.
      IF lt_apartados IS INITIAL.
        mv_motivos_apartado = ' motivo desconocido (sin ERDO)'.
      ENDIF.
      IF mv_motivos_apartado IS NOT INITIAL.
        rv_apartado = abap_true.
        RETURN.
      ENDIF.

      " En una sesión nueva (DESTINATION 'NONE'): en la misma sesión que
      " la facturación el FM estándar da SYSTEM_ERROR; en una sesión limpia
      " (EA05, SE37) libera bien. Antes se sueltan los bloqueos de esta
      " sesión (todo está ya grabado) para que no choquen con los suyos.
      CALL FUNCTION 'DEQUEUE_ALL'.
      CALL FUNCTION 'ZFA_FM_FRAUDES_LIBERAR'
        DESTINATION 'NONE'
        EXPORTING
          iv_opbel              = lv_opbel
        IMPORTING
          ev_new_opbel          = lv_nuevo
          ev_subrc              = lv_subrc
          ev_mensaje            = lv_mensaje
        EXCEPTIONS
          system_failure        = 1 MESSAGE lv_mensaje
          communication_failure = 2 MESSAGE lv_mensaje
          OTHERS                = 3.
      IF sy-subrc <> 0.
        lv_subrc = sy-subrc.
        lv_mensaje = |RFC: { lv_mensaje }|.
      ENDIF.
      " Si falla o se libera en fondo (sin número nuevo) queda apartada
      " para liberarla a mano en la EA05
      IF lv_subrc <> 0 OR lv_nuevo IS INITIAL.
        IF lv_subrc = 0.
          lv_mensaje = 'liberación en fondo, sin documento nuevo'.
        ENDIF.
        mv_motivos_apartado = | { gc_validacion_ciclo } (error al liberar, subrc { lv_subrc }: { lv_mensaje })|.
        rv_apartado = abap_true.
        RETURN.
      ENDIF.
      lv_opbel = lv_nuevo.
      ls_erdk  = leer_factura( lv_opbel ).
    ENDIF.

    ms_factura-factura     = lv_opbel.
    ms_factura-doc_oficial = ls_erdk-exbel.

  ENDMETHOD.


  METHOD anular_calculo.

    DATA lv_calculo TYPE erch-belnr.

    " Si no se puede facturar se borra el cálculo manual (Aleix: devolver
    " error y anular el cálculo): así un reintento del expediente no se
    " encuentra con dos cálculos en el periodo. Hace COMMIT él mismo y no
    " deja borrar un cálculo ya facturado.
    lv_calculo = ms_factura-calculo.
    CALL FUNCTION 'ISU_S_MANUBILL_DELETE'
      EXPORTING
        x_belnr       = lv_calculo
        x_stichtag    = ms_entrada-fecha_hasta
        x_no_dialog   = abap_true
      EXCEPTIONS
        not_found     = 1
        foreign_lock  = 2
        cancelled     = 3
        general_fault = 4
        error_message = 5
        OTHERS        = 6.
    IF sy-subrc = 0.
      CLEAR ms_factura.
      RAISE EXCEPTION TYPE zcx_fa_fraudes
        EXPORTING codigo = '2007'
                  texto  = |{ iv_motivo }. Cálculo { lv_calculo } borrado|.
    ENDIF.

    RAISE EXCEPTION TYPE zcx_fa_fraudes
      EXPORTING codigo = '2008'
                texto  = |{ iv_motivo }. No se ha podido borrar el cálculo { lv_calculo }: borrarlo en EA16|.

  ENDMETHOD.


  METHOD leer_factura.

    " La facturación y la liberación hacen COMMIT sin esperar a la
    " actualización: se reintenta unos segundos hasta que esté en BD
    DO 10 TIMES.
      SELECT SINGLE exbel, tobreleasd, total_amnt, total_waer
        FROM erdk
        WHERE opbel = @iv_opbel
        INTO CORRESPONDING FIELDS OF @rs_factura.
      IF sy-subrc = 0.
        RETURN.
      ENDIF.
      WAIT UP TO 1 SECONDS.
    ENDDO.

  ENDMETHOD.


  METHOD registrar_log.

    DATA ls_log TYPE zfa_fraud_log.

    GET TIME STAMP FIELD ls_log-tstamp.
    ls_log-id_expediente = ms_entrada-id_expediente.
    ls_log-cups          = ms_entrada-cups.
    ls_log-vertrag       = ms_entrada-contrato.
    ls_log-resultado     = is_resultado-resultado.
    ls_log-codigo        = is_resultado-codigo.
    ls_log-descripcion   = is_resultado-descripcion.
    ls_log-modo          = is_resultado-modo.
    ls_log-uname         = sy-uname.

    READ TABLE is_resultado-facturas INTO DATA(ls_factura) INDEX 1.
    IF sy-subrc = 0.
      ls_log-belnr = ls_factura-calculo.
      ls_log-opbel = ls_factura-factura.
    ENDIF.

    INSERT zfa_fraud_log FROM ls_log.
    COMMIT WORK AND WAIT.

  ENDMETHOD.


  METHOD lineas_tipo.
    rt_lineas = VALUE #( FOR ls_linea IN it_lineas WHERE ( tipo = iv_tipo ) ( ls_linea ) ).
  ENDMETHOD.


  METHOD sumar_importes.
    rv_importe = REDUCE #( INIT lv_suma TYPE ty_importe
                           FOR ls_linea IN it_lineas
                           NEXT lv_suma = lv_suma + ls_linea-importe ).
  ENDMETHOD.

ENDCLASS.
