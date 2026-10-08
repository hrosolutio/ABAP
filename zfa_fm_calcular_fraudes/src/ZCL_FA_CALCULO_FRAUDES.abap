*----------------------------------------------------------------------*
* Facturación automática de averías y fraudes.
*
* Flujo (ver README para el detalle y los TODO pendientes):
*   1. Validaciones de entrada               -> KO 1xxx
*   2. Flag descarte / marca titular         -> factura a 0 (EREPOS/GREPOS)
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
        descarte         TYPE xfeld,
        marca_titular    TYPE xfeld,
        id_expediente    TYPE zle_de_numeroexpediente,
      END OF ty_entrada,

      BEGIN OF ty_resultado,
        resultado   TYPE char2,
        codigo      TYPE char4,
        descripcion TYPE string,
        modo        TYPE char30,
        facturas    TYPE zfa_t_fraudes_factura,
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

      BEGIN OF ty_concepto_atr,
        concepto TYPE char4,
        importe  TYPE ty_importe,
      END OF ty_concepto_atr,
      ty_t_concepto_atr TYPE STANDARD TABLE OF ty_concepto_atr WITH DEFAULT KEY,

      ty_t_conceptos TYPE STANDARD TABLE OF zfa_fraud_conc WITH DEFAULT KEY.

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

      " Conceptos fijos indicados en el DF
      gc_belzart_erepos     TYPE dberchz1-belzart VALUE 'EREPOS',
      gc_belzart_grepos     TYPE dberchz1-belzart VALUE 'GREPOS',
      gc_belzart_pgintr     TYPE dberchz1-belzart VALUE 'PGINTR',
      gc_belzart_pgirap     TYPE dberchz1-belzart VALUE 'PGIRAP',
      gc_concepto_atr_1923  TYPE char4 VALUE '1923',
      gc_concepto_atr_1924  TYPE char4 VALUE '1924',

      " IEE mínimo según DF: consumo (kWh) / 1000 * 1 EUR
      gc_iee_minimo_mwh     TYPE ty_precio VALUE '1',

      " TODO pedir a Aleix el operando de reposición. Mientras esté vacío
      " la validación no se hace.
      gc_operando_reposicion TYPE ettifn-operand VALUE '',

      " Tipos de tarifa de Tarifa Plana (vistos en ERCHZ-TARIFTYP de
      " cálculos reales). TODO confirmar con Aleix que no hay más
      gc_tariftyp_plana_luz  TYPE eanlh-tariftyp VALUE 'E_PLANA',
      gc_tariftyp_plana_gas  TYPE eanlh-tariftyp VALUE 'G_PLANA',

      gc_modo_normal        TYPE char30 VALUE 'NORMAL',
      gc_modo_cero_descarte TYPE char30 VALUE 'IMPORTE_CERO_DESCARTE',
      gc_modo_cero_titular  TYPE char30 VALUE 'IMPORTE_CERO_TITULAR'.

    DATA: ms_entrada   TYPE ty_entrada,
          mv_anlage    TYPE anlage,
          mv_vkonto    TYPE vkont_kk,
          mv_sparte    TYPE sparte,
          mv_bukrs     TYPE bukrs,
          mt_conceptos TYPE ty_t_conceptos,
          " Líneas del cálculo original tal cual (ERCHZ), para heredar
          " operación, tarifa, unidad, etc. en el cálculo manual
          mt_erchz_original TYPE STANDARD TABLE OF erchz WITH DEFAULT KEY.

    METHODS procesar
      RETURNING VALUE(rs_resultado) TYPE ty_resultado
      RAISING   zcx_fa_fraudes.

    METHODS validar_entrada
      RAISING zcx_fa_fraudes.

    METHODS validar_obligatorios
      RAISING zcx_fa_fraudes.

    METHODS existe_factura_atr
      RETURNING VALUE(rv_existe) TYPE abap_bool.

    METHODS consumo_atr_correcto
      RETURNING VALUE(rv_correcto) TYPE abap_bool.

    METHODS validar_integridad
      RAISING zcx_fa_fraudes.

    METHODS facturar_importe_cero
      RETURNING VALUE(rs_resultado) TYPE ty_resultado
      RAISING   zcx_fa_fraudes.

    METHODS buscar_calculo_original
      RETURNING VALUE(rs_calculo) TYPE ty_calculo
      RAISING   zcx_fa_fraudes.

    METHODS leer_lineas_calculo
      IMPORTING iv_belnr         TYPE erch-belnr
      RETURNING VALUE(rt_lineas) TYPE ty_t_linea
      RAISING   zcx_fa_fraudes.

    METHODS calcular_luz
      IMPORTING it_original      TYPE ty_t_linea
      RETURNING VALUE(rt_lineas) TYPE ty_t_linea
      RAISING   zcx_fa_fraudes.

    METHODS calcular_gas
      IMPORTING it_original      TYPE ty_t_linea
      RETURNING VALUE(rt_lineas) TYPE ty_t_linea
      RAISING   zcx_fa_fraudes.

    METHODS leer_conceptos_atr
      RETURNING VALUE(rt_conceptos) TYPE ty_t_concepto_atr.

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
      IMPORTING it_lineas          TYPE ty_t_linea
      RETURNING VALUE(rt_facturas) TYPE zfa_t_fraudes_factura
      RAISING   zcx_fa_fraudes.

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
        rs_resultado-descripcion = lx_fraudes->get_text( ).
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
          lt_lineas   TYPE ty_t_linea.

    validar_entrada( ).

    " Con el flag de descarte o la marca de titular errónea se factura a
    " 0 sin pasar por las validaciones de integridad: es la segunda
    " llamada que hace la IA sobre un caso ya descartado.
    " TODO confirmar con Aleix que el flag se salta las validaciones de
    " integridad (si no, nunca se podría facturar un descarte a 0).
    IF ms_entrada-descarte = abap_true OR ms_entrada-marca_titular = abap_true.
      rs_resultado = facturar_importe_cero( ).
      RETURN.
    ENDIF.

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

    rs_resultado-facturas    = crear_calculo_manual( lt_lineas ).
    rs_resultado-codigo      = '0000'.
    rs_resultado-descripcion = 'Factura creada correctamente'.
    rs_resultado-modo        = gc_modo_normal.

  ENDMETHOD.


  METHOD validar_entrada.

    DATA: lv_codigo TYPE char4,
          lv_int_ui TYPE int_ui,
          lv_anlage TYPE anlage.

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
        AND codigo        IN ( '0000', '0001', '0002' )
      INTO @lv_codigo.
    IF sy-subrc = 0.
      RAISE EXCEPTION TYPE zcx_fa_fraudes
        EXPORTING codigo = '1006'
                  texto  = |El expediente { ms_entrada-id_expediente } ya está facturado|.
    ENDIF.

    " 1.1 El CUPS existe
    SELECT int_ui
      FROM euitrans
      WHERE ext_ui    = @ms_entrada-cups
        AND datefrom <= @ms_entrada-fecha_hasta
        AND dateto   >= @ms_entrada-fecha_desde
      INTO @lv_int_ui
      UP TO 1 ROWS.
    ENDSELECT.
    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE zcx_fa_fraudes
        EXPORTING codigo = '1001'
                  texto  = |El CUPS { ms_entrada-cups } no existe en el sistema|.
    ENDIF.

    " 1.2 El contrato existe y su instalación es la del CUPS
    SELECT SINGLE anlage, vkonto, sparte, bukrs, einzdat, auszdat
      FROM ever
      WHERE vertrag = @ms_entrada-contrato
      INTO @DATA(ls_ever).
    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE zcx_fa_fraudes
        EXPORTING codigo = '1002'
                  texto  = |El contrato { ms_entrada-contrato } no existe|.
    ENDIF.

    SELECT anlage
      FROM euiinstln
      WHERE int_ui    = @lv_int_ui
        AND anlage    = @ls_ever-anlage
        AND datefrom <= @ms_entrada-fecha_hasta
        AND dateto   >= @ms_entrada-fecha_desde
      INTO @lv_anlage
      UP TO 1 ROWS.
    ENDSELECT.
    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE zcx_fa_fraudes
        EXPORTING codigo = '1002'
                  texto  = |El CUPS { ms_entrada-cups } no corresponde al contrato { ms_entrada-contrato }|.
    ENDIF.

    " 1.3 Contrato activo en todo el periodo
    IF ls_ever-einzdat > ms_entrada-fecha_desde OR ls_ever-auszdat < ms_entrada-fecha_hasta.
      RAISE EXCEPTION TYPE zcx_fa_fraudes
        EXPORTING codigo = '1003'
                  texto  = |El contrato { ms_entrada-contrato } no está activo en el periodo|.
    ENDIF.

    mv_anlage = ls_ever-anlage.
    mv_vkonto = ls_ever-vkonto.
    mv_sparte = ls_ever-sparte.
    mv_bukrs  = ls_ever-bukrs.

    " 1.4 Factura ATR de tipo 06 u 11 y existente
    IF ms_entrada-tipo_factura_atr <> '06' AND ms_entrada-tipo_factura_atr <> '11'.
      RAISE EXCEPTION TYPE zcx_fa_fraudes
        EXPORTING codigo = '1004'
                  texto  = |Tipo de factura ATR { ms_entrada-tipo_factura_atr } no válido (06 u 11)|.
    ENDIF.

    IF existe_factura_atr( ) = abap_false.
      RAISE EXCEPTION TYPE zcx_fa_fraudes
        EXPORTING codigo = '1004'
                  texto  = |La factura ATR { ms_entrada-num_factura_atr } no existe|.
    ENDIF.

    " 1.5 Consumo de la factura ATR vs consumo total
    IF consumo_atr_correcto( ) = abap_false.
      RAISE EXCEPTION TYPE zcx_fa_fraudes
        EXPORTING codigo = '1005'
                  texto  = 'El consumo total no cuadra con el de la factura ATR'.
    ENDIF.

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
    " TODO localizar dónde se guardan las facturas ATR (06/11). La
    " versión de partida usaba /IDXGC/PRST_INHD-CODIGOFISCALFACTURA:
    " comprobar en SE11 si existe; si no, buscar la tabla Z que usa el
    " elemento de datos ZLE_DE_FACTUR (where-used en SE11).
    rv_existe = abap_true.
  ENDMETHOD.


  METHOD consumo_atr_correcto.
    " TODO el DF tiene esta validación "pendiente de detallar". Cuando
    " Aleix la defina: leer el consumo de la factura ATR y compararlo con
    " ms_entrada-consumo_total con la regla que se acuerde.
    rv_correcto = abap_true.
  ENDMETHOD.


  METHOD validar_integridad.

    DATA lv_anlage TYPE anlage.

    " TODO 2.1 Periodo migrado (Uptility / NI): origen del dato pendiente
    "      de Aleix. Descarte -> '0101'.
    " TODO 2.2 Exención de impuestos: origen pendiente. Descarte -> '0102'.
    " TODO 2.3 Derecho al olvido: origen pendiente. Descarte -> '0103'.
    " TODO 2.4 Vulnerable / esencial en el periodo: origen pendiente.
    "      Descarte -> '0104'.
    " TODO 2.5 Bloqueo de contrato / cuenta contrato: confirmar qué
    "      bloqueo (facturación, cobro, ...). Descarte -> '0105'.

    " 2.6 Operando de reposición activo en el periodo
    IF gc_operando_reposicion IS NOT INITIAL.
      " TODO confirmar si basta con que exista el operando en el periodo
      " o hay que mirar su valor
      SELECT anlage
        FROM ettifn
        WHERE anlage  = @mv_anlage
          AND operand = @gc_operando_reposicion
          AND ab     <= @ms_entrada-fecha_hasta
          AND bis    >= @ms_entrada-fecha_desde
        INTO @lv_anlage
        UP TO 1 ROWS.
      ENDSELECT.
      IF sy-subrc = 0.
        RAISE EXCEPTION TYPE zcx_fa_fraudes
          EXPORTING codigo = '0106'
                    texto  = 'Descarte: operando de reposición activo en el periodo'.
      ENDIF.
    ENDIF.

    " 2.7 Tarifa Plana en el periodo: tipo de tarifa de la instalación
    SELECT anlage
      FROM eanlh
      WHERE anlage   = @mv_anlage
        AND tariftyp IN ( @gc_tariftyp_plana_luz, @gc_tariftyp_plana_gas )
        AND ab      <= @ms_entrada-fecha_hasta
        AND bis     >= @ms_entrada-fecha_desde
      INTO @lv_anlage
      UP TO 1 ROWS.
    ENDSELECT.
    IF sy-subrc = 0.
      RAISE EXCEPTION TYPE zcx_fa_fraudes
        EXPORTING codigo = '0107'
                  texto  = 'Descarte: cliente con Tarifa Plana en el periodo'.
    ENDIF.

  ENDMETHOD.


  METHOD facturar_importe_cero.

    DATA: ls_linea TYPE ty_linea,
          lt_linea TYPE ty_t_linea.

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
    APPEND ls_linea TO lt_linea.

    rs_resultado-facturas = crear_calculo_manual( lt_linea ).

    IF ms_entrada-descarte = abap_true.
      rs_resultado-codigo      = '0001'.
      rs_resultado-descripcion = 'Factura a importe 0 (descarte) creada correctamente'.
      rs_resultado-modo        = gc_modo_cero_descarte.
    ELSE.
      rs_resultado-codigo      = '0002'.
      rs_resultado-descripcion = 'Factura a importe 0 (titular erróneo) creada correctamente'.
      rs_resultado-modo        = gc_modo_cero_titular.
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


  METHOD leer_lineas_calculo.

    DATA: lr_tabla TYPE REF TO data,
          lv_tabla TYPE tabname,
          ls_linea TYPE ty_linea.

    FIELD-SYMBOLS: <lt_tabla>    TYPE STANDARD TABLE,
                   <ls_fila>     TYPE any,
                   <lv_belzeile> TYPE any,
                   <ls_erchz>    TYPE erchz.

    " Las líneas de cálculo (ERCHZ) se guardan repartidas en DBERCHZ1..8,
    " todas con clave BELNR + BELZEILE. Se juntan en una ERCHZ por línea.
    " TODO si aparece el FM estándar que lee el documento entero en
    " ISU2A_BILL_DOC, usarlo en lugar de esto.
    CLEAR mt_erchz_original.

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
        READ TABLE mt_erchz_original ASSIGNING <ls_erchz>
          WITH KEY belzeile = <lv_belzeile>.
        IF sy-subrc <> 0.
          APPEND INITIAL LINE TO mt_erchz_original ASSIGNING <ls_erchz>.
        ENDIF.
        MOVE-CORRESPONDING <ls_fila> TO <ls_erchz>.
      ENDLOOP.
    ENDDO.

    " Solo interesan las líneas cuyo concepto está en ZFA_FRAUD_CONC
    LOOP AT mt_erchz_original ASSIGNING <ls_erchz>.
      READ TABLE mt_conceptos INTO DATA(ls_concepto)
        WITH KEY belzart = <ls_erchz>-belzart.
      CHECK sy-subrc = 0.

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
    " TODO leer de la factura ATR (ms_entrada-num_factura_atr) los
    " conceptos 1923 y 1924 con su importe. Depende de dónde estén las
    " facturas ATR (ver existe_factura_atr).
    CLEAR rt_conceptos.
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

    DATA: lv_importe_pct TYPE ty_importe,
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

    " TODO verificar que el precio de la línea de IEE viene en % (p. ej.
    " 5,11269632) y no como factor (0,0511...)
    lv_importe_pct = iv_base * ls_iee-precio / 100.
    lv_importe_min = iv_consumo / 1000 * gc_iee_minimo_mwh.

    " Se factura el mayor, reutilizando el concepto del original (la región
    " va en el concepto) o su equivalente de mínimo comunitario
    IF lv_importe_pct >= lv_importe_min.
      rs_linea-belzeile = ls_iee-belzeile.
      rs_linea-belzart  = ls_iee-belzart.
      rs_linea-tipo     = gc_tipo_iee.
      rs_linea-precio   = ls_iee-precio.
      rs_linea-importe  = lv_importe_pct.
    ELSE.
      IF lv_hay_min = abap_true.
        rs_linea-belzeile = ls_iee_min-belzeile.
        rs_linea-belzart  = ls_iee_min-belzart.
      ELSE.
        rs_linea-belzart  = concepto_relacionado( ls_iee-belzart ).
      ENDIF.
      rs_linea-tipo     = gc_tipo_iee_min.
      rs_linea-cantidad = iv_consumo / 1000.
      rs_linea-precio   = gc_iee_minimo_mwh.
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
          ls_factura   TYPE zfa_s_fraudes_factura.

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
    ls_auto-bill_doc-erch-begabrpe = ms_entrada-fecha_desde.
    ls_auto-bill_doc-erch-endabrpe = ms_entrada-fecha_hasta.
    ls_auto-rea16-stichtag         = ms_entrada-fecha_hasta.

    LOOP AT it_lineas INTO DATA(ls_linea).
      " Se parte de la línea original (misma operación, tarifa, unidad,
      " impuesto...) y solo se cambian fechas, cantidad, precio e importe.
      " La cantidad tiene que ir en I_ABRMENGE: FILL_OBJ_REA16_DATA la pasa
      " a MENGE/ABRMENGE y toma la unidad de MASSBILL.
      CLEAR ls_erchz.
      IF ls_linea-belzeile IS NOT INITIAL.
        READ TABLE mt_erchz_original INTO ls_erchz
          WITH KEY belzeile = ls_linea-belzeile.
      ENDIF.
      " TODO líneas sin original (EREPOS/GREPOS, PGINTR/PGIRAP, mínimo
      " comunitario cuando el original llevaba IEE): copiar los datos de una
      " reposición real o de la línea de IEE (operación TVORG, MASSBILL,
      " MWSKZ, TWAERS...)
      CLEAR: ls_erchz-belnr.
      lv_belzeile = lv_belzeile + 1.
      ls_erchz-belzeile   = lv_belzeile.
      ls_erchz-belzart    = ls_linea-belzart.
      ls_erchz-ab         = ls_linea-ab.
      ls_erchz-bis        = ls_linea-bis.
      ls_erchz-i_abrmenge = ls_linea-cantidad.
      ls_erchz-preisbtr   = ls_linea-precio.
      ls_erchz-nettobtr   = ls_linea-importe.
      APPEND ls_erchz TO ls_auto-bill_doc-ierchz.
    ENDLOOP.

    " TODO confirmar la fecha clave (REA16-STICHTAG) que espera la
    " transacción para un cálculo manual
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

    IF sy-subrc <> 0 OR ls_new_doc-erch-belnr IS INITIAL.
      IF sy-msgid IS NOT INITIAL.
        MESSAGE ID sy-msgid TYPE 'E' NUMBER sy-msgno
          WITH sy-msgv1 sy-msgv2 sy-msgv3 sy-msgv4 INTO lv_mensaje.
      ENDIF.
      CASE sy-subrc.
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

    " El cálculo queda grabado (en update task: el COMMIT lo hace
    " registrar_log) y apuntado en EITR para facturar.
    " TODO facturar el cálculo al momento y devolver documento de
    " impresión (FACTURA) y documento oficial (DOC_OFICIAL).
    ls_factura-calculo     = ls_new_doc-erch-belnr.
    ls_factura-consumo     = ms_entrada-consumo_total.
    ls_factura-importe     = sumar_importes( it_lineas ).
    ls_factura-fecha_desde = ms_entrada-fecha_desde.
    ls_factura-fecha_hasta = ms_entrada-fecha_hasta.
    APPEND ls_factura TO rt_facturas.

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
