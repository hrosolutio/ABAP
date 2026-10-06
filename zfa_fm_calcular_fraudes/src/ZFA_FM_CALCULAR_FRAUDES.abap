FUNCTION zfa_fm_calcular_fraudes.
*"----------------------------------------------------------------------
*"*"Interfase local
*"  IMPORTING
*"     VALUE(IV_CUPS) TYPE  EXT_UI
*"     VALUE(IV_FECHA_DESDE) TYPE  DATS
*"     VALUE(IV_FECHA_HASTA) TYPE  DATS
*"     VALUE(IV_CONSUMO_P1) TYPE  MENGE_D OPTIONAL
*"     VALUE(IV_CONSUMO_P2) TYPE  MENGE_D OPTIONAL
*"     VALUE(IV_CONSUMO_P3) TYPE  MENGE_D OPTIONAL
*"     VALUE(IV_CONSUMO_P4) TYPE  MENGE_D OPTIONAL
*"     VALUE(IV_CONSUMO_P5) TYPE  MENGE_D OPTIONAL
*"     VALUE(IV_CONSUMO_P6) TYPE  MENGE_D OPTIONAL
*"     VALUE(IV_CONSUMO_TOTAL) TYPE  MENGE_D
*"     VALUE(IV_NUM_FACTURA_ATR) TYPE  ZLE_DE_FACTUR
*"     VALUE(IV_TIPO_FACTURA_ATR) TYPE  CHAR2
*"     VALUE(IV_CONTRATO_SAP) TYPE  VERTRAG
*"     VALUE(IV_ID_PROCESO_ATR) TYPE  CHAR2
*"     VALUE(IV_DESCARTE) TYPE  XFELD OPTIONAL
*"     VALUE(IV_MARCA_TITULAR) TYPE  XFELD OPTIONAL
*"     VALUE(IV_ID_EXPEDIENTE) TYPE  ZLE_DE_NUMEROEXPEDIENTE
*"  EXPORTING
*"     VALUE(EV_RESULTADO) TYPE  CHAR2
*"     VALUE(EV_CODIGO) TYPE  CHAR4
*"     VALUE(EV_DESCRIPCION) TYPE  STRING
*"     VALUE(EV_MODO_FACTURACION) TYPE  CHAR30
*"     VALUE(ET_FACTURAS) TYPE  ZFA_T_FRAUDES_FACTURA
*"----------------------------------------------------------------------
* Facturación automática de averías y fraudes (DF "Automatización de
* averías y fraude", v1.0). Toda la lógica está en
* ZCL_FA_CALCULO_FRAUDES; la RFC solo traslada parámetros.
*----------------------------------------------------------------------*

  DATA: ls_entrada   TYPE zcl_fa_calculo_fraudes=>ty_entrada,
        ls_resultado TYPE zcl_fa_calculo_fraudes=>ty_resultado.

  CLEAR: ev_resultado, ev_codigo, ev_descripcion, ev_modo_facturacion, et_facturas.

  ls_entrada = VALUE #( cups             = iv_cups
                        fecha_desde      = iv_fecha_desde
                        fecha_hasta      = iv_fecha_hasta
                        consumo_p1       = iv_consumo_p1
                        consumo_p2       = iv_consumo_p2
                        consumo_p3       = iv_consumo_p3
                        consumo_p4       = iv_consumo_p4
                        consumo_p5       = iv_consumo_p5
                        consumo_p6       = iv_consumo_p6
                        consumo_total    = iv_consumo_total
                        num_factura_atr  = iv_num_factura_atr
                        tipo_factura_atr = iv_tipo_factura_atr
                        contrato         = iv_contrato_sap
                        id_proceso_atr   = iv_id_proceso_atr
                        descarte         = iv_descarte
                        marca_titular    = iv_marca_titular
                        id_expediente    = iv_id_expediente ).

  ls_resultado = NEW zcl_fa_calculo_fraudes( )->ejecutar( ls_entrada ).

  ev_resultado         = ls_resultado-resultado.
  ev_codigo            = ls_resultado-codigo.
  ev_descripcion       = ls_resultado-descripcion.
  ev_modo_facturacion  = ls_resultado-modo.
  et_facturas          = ls_resultado-facturas.

ENDFUNCTION.
