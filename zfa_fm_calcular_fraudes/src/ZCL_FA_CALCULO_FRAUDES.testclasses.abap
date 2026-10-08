*----------------------------------------------------------------------*
* ABAP Unit de la parte de cálculo (sin acceso a BD).
* SE24 -> ZCL_FA_CALCULO_FRAUDES -> Clases de test locales.
*----------------------------------------------------------------------*
CLASS ltc_calculo DEFINITION DEFERRED.
CLASS zcl_fa_calculo_fraudes DEFINITION LOCAL FRIENDS ltc_calculo.

CLASS ltc_calculo DEFINITION FINAL
  FOR TESTING RISK LEVEL HARMLESS DURATION SHORT.

  PRIVATE SECTION.

    DATA mo_cut TYPE REF TO zcl_fa_calculo_fraudes.

    METHODS setup.

    METHODS prorrateo_un_precio      FOR TESTING RAISING cx_static_check.
    METHODS prorrateo_dos_precios    FOR TESTING RAISING cx_static_check.
    METHODS prorrateo_ventana_parcial FOR TESTING RAISING cx_static_check.
    METHODS prorrateo_sin_solape     FOR TESTING RAISING cx_static_check.
    METHODS iee_gana_porcentaje      FOR TESTING RAISING cx_static_check.
    METHODS iee_gana_minimo          FOR TESTING RAISING cx_static_check.
    METHODS iee_factor_derivado      FOR TESTING RAISING cx_static_check.
    METHODS descuento_proporcional   FOR TESTING RAISING cx_static_check.
    METHODS potencia_mayor_por_kw    FOR TESTING RAISING cx_static_check.

ENDCLASS.


CLASS ltc_calculo IMPLEMENTATION.

  METHOD setup.
    mo_cut = NEW #( ).
    mo_cut->ms_entrada-fecha_desde = '20260101'.
    mo_cut->ms_entrada-fecha_hasta = '20260131'.
  ENDMETHOD.


  METHOD prorrateo_un_precio.

    DATA(lt_lineas) = mo_cut->prorratear(
      iv_consumo    = 1000
      it_fracciones = VALUE #( ( belzart = 'EN01' ab = '20260101' bis = '20260131' precio = '0.1' ) ) ).

    cl_abap_unit_assert=>assert_equals( act = lines( lt_lineas ) exp = 1 ).
    cl_abap_unit_assert=>assert_equals( act = lt_lineas[ 1 ]-cantidad exp = '1000.000' ).
    cl_abap_unit_assert=>assert_equals( act = lt_lineas[ 1 ]-importe  exp = '100.00' ).

  ENDMETHOD.


  METHOD prorrateo_dos_precios.

    " 10 días a 0,1 y 21 días a 0,2 sobre 31 días
    DATA(lt_lineas) = mo_cut->prorratear(
      iv_consumo    = 1000
      it_fracciones = VALUE #( ( belzart = 'EN01' ab = '20260101' bis = '20260110' precio = '0.1' )
                               ( belzart = 'EN01' ab = '20260111' bis = '20260131' precio = '0.2' ) ) ).

    cl_abap_unit_assert=>assert_equals( act = lines( lt_lineas ) exp = 2 ).
    cl_abap_unit_assert=>assert_equals( act = lt_lineas[ 1 ]-cantidad exp = '322.581' ).
    cl_abap_unit_assert=>assert_equals( act = lt_lineas[ 2 ]-cantidad exp = '677.419' ).
    cl_abap_unit_assert=>assert_equals( act = lt_lineas[ 1 ]-importe  exp = '32.26' ).
    cl_abap_unit_assert=>assert_equals( act = lt_lineas[ 2 ]-importe  exp = '135.48' ).

  ENDMETHOD.


  METHOD prorrateo_ventana_parcial.

    " De la primera fracción solo cuenta la parte de enero y la segunda
    " empieza después del expediente: todo el consumo va a la primera
    DATA(lt_lineas) = mo_cut->prorratear(
      iv_consumo    = 500
      it_fracciones = VALUE #( ( belzart = 'EN01' ab = '20251201' bis = '20260131' precio = '0.1' )
                               ( belzart = 'EN01' ab = '20260201' bis = '20260228' precio = '0.2' ) ) ).

    cl_abap_unit_assert=>assert_equals( act = lines( lt_lineas ) exp = 1 ).
    cl_abap_unit_assert=>assert_equals( act = lt_lineas[ 1 ]-cantidad exp = '500.000' ).
    cl_abap_unit_assert=>assert_equals( act = lt_lineas[ 1 ]-importe  exp = '50.00' ).

  ENDMETHOD.


  METHOD prorrateo_sin_solape.

    TRY.
        mo_cut->prorratear(
          iv_consumo    = 500
          it_fracciones = VALUE #( ( belzart = 'EN01' ab = '20250101' bis = '20250131' precio = '0.1' ) ) ).
        cl_abap_unit_assert=>fail( 'Debería fallar sin fracciones en el periodo' ).
      CATCH zcx_fa_fraudes INTO DATA(lx_fraudes).
        cl_abap_unit_assert=>assert_equals( act = lx_fraudes->codigo exp = '2002' ).
    ENDTRY.

  ENDMETHOD.


  METHOD iee_gana_porcentaje.

    " 100 * 5,11269632 % = 5,11 > 1000 kWh / 1000 * 1 = 1,00
    DATA(ls_iee) = mo_cut->calcular_iee(
      it_original = VALUE #( ( belzart = 'IEE01' tipo = 'IE' precio = '5.11269632' ) )
      iv_base     = 100
      iv_consumo  = 1000 ).

    cl_abap_unit_assert=>assert_equals( act = ls_iee-belzart exp = 'IEE01' ).
    cl_abap_unit_assert=>assert_equals( act = ls_iee-importe exp = '5.11' ).

  ENDMETHOD.


  METHOD iee_gana_minimo.

    " 10 * 5,11269632 % = 0,51 < 1,00: va el mínimo con su concepto
    mo_cut->mt_conceptos = VALUE #( ( belzart = 'IEE01' tipo = 'IE' belzart_rel = 'IEEMIN01' ) ).

    DATA(ls_iee) = mo_cut->calcular_iee(
      it_original = VALUE #( ( belzart = 'IEE01' tipo = 'IE' precio = '5.11269632' ) )
      iv_base     = 10
      iv_consumo  = 1000 ).

    cl_abap_unit_assert=>assert_equals( act = ls_iee-belzart  exp = 'IEEMIN01' ).
    cl_abap_unit_assert=>assert_equals( act = ls_iee-tipo     exp = 'IM' ).
    cl_abap_unit_assert=>assert_equals( act = ls_iee-cantidad exp = '1000.000' ).
    cl_abap_unit_assert=>assert_equals( act = ls_iee-precio   exp = '0.001' ).
    cl_abap_unit_assert=>assert_equals( act = ls_iee-importe  exp = '1.00' ).

  ENDMETHOD.


  METHOD iee_factor_derivado.

    " Cálculo real 510100377871: la línea EIEEGE solo trae importe (2,42)
    " sobre energía 33,09 + potencia 10,60 + 3,48 + bono social 0,19.
    " Factor 2,42 / 47,36 = 5,1098 %; sobre 100 EUR de energía -> 5,11
    DATA(ls_iee) = mo_cut->calcular_iee(
      it_original = VALUE #( ( belzart = 'EACTPS' tipo = 'EN' importe = '33.09' )
                             ( belzart = 'EPOTP1' tipo = 'PO' importe = '10.60' )
                             ( belzart = 'EPOTP2' tipo = 'PO' importe = '3.48' )
                             ( belzart = 'EBONSO' tipo = 'BI' importe = '0.19' )
                             ( belzart = 'EIEEGE' tipo = 'IE' importe = '2.42' ) )
      iv_base     = 100
      iv_consumo  = 288 ).

    cl_abap_unit_assert=>assert_equals( act = ls_iee-belzart exp = 'EIEEGE' ).
    cl_abap_unit_assert=>assert_equals( act = ls_iee-importe exp = '5.11' ).

  ENDMETHOD.


  METHOD descuento_proporcional.

    " Original: -20 sobre 200 (10 %). Nueva base 100 -> -10
    DATA(lt_lineas) = mo_cut->aplicar_descuentos(
      it_descuentos    = VALUE #( ( belzart = 'DTO01' tipo = 'DE' importe = '-20' ) )
      iv_base_original = 200
      iv_base_nueva    = 100 ).

    cl_abap_unit_assert=>assert_equals( act = lines( lt_lineas ) exp = 1 ).
    cl_abap_unit_assert=>assert_equals( act = lt_lineas[ 1 ]-importe exp = '-10.00' ).

  ENDMETHOD.


  METHOD potencia_mayor_por_kw.

    DATA(lt_lineas) = mo_cut->potencia_mayor(
      VALUE #( ( belzart = 'POT01' tipo = 'PO' cantidad = '3.450' importe = '50' )
               ( belzart = 'POT02' tipo = 'PO' cantidad = '5.750' importe = '20' )
               ( belzart = 'EN01'  tipo = 'EN' cantidad = '900'   importe = '90' ) ) ).

    cl_abap_unit_assert=>assert_equals( act = lines( lt_lineas ) exp = 1 ).
    cl_abap_unit_assert=>assert_equals( act = lt_lineas[ 1 ]-belzart  exp = 'POT02' ).
    cl_abap_unit_assert=>assert_equals( act = lt_lineas[ 1 ]-cantidad exp = '5.750' ).
    cl_abap_unit_assert=>assert_equals( act = lt_lineas[ 1 ]-importe  exp = '0.00' ).

  ENDMETHOD.

ENDCLASS.
