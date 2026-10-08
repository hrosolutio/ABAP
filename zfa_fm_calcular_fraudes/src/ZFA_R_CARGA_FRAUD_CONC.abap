*&---------------------------------------------------------------------*
*& Report ZFA_R_CARGA_FRAUD_CONC
*&---------------------------------------------------------------------*
*& Carga inicial de ZFA_FRAUD_CONC: qué es cada concepto (BELZART) del
*& cálculo original para la facturación de averías y fraudes.
*& Conceptos sacados de TE835T. Con P_TEST marcado solo lista.
*&---------------------------------------------------------------------*
REPORT zfa_r_carga_fraud_conc.

TYPES: BEGIN OF ty_par_iee,
         iee TYPE c LENGTH 4,
         min TYPE c LENGTH 4,
       END OF ty_par_iee.

DATA: lt_conc    TYPE STANDARD TABLE OF zfa_fraud_conc,
      lt_par_iee TYPE STANDARD TABLE OF ty_par_iee,
      lt_ieh     TYPE STANDARD TABLE OF char4,
      lt_region  TYPE STANDARD TABLE OF char2,
      lv_iee     TYPE zfa_fraud_conc-belzart,
      lv_min     TYPE zfa_fraud_conc-belzart.

" TODO confirmar los valores de división de luz y gas
PARAMETERS: p_luz  TYPE sparte OBLIGATORY DEFAULT '01',
            p_gas  TYPE sparte OBLIGATORY DEFAULT '02',
            p_test AS CHECKBOX DEFAULT 'X'.

START-OF-SELECTION.

  "--- Luz -------------------------------------------------------------
  " Energía activa: EACTPS agrupada; EACTP1-3 (2.0TD) y EACTF1-6 por periodo
  lt_conc = VALUE #( sparte = p_luz tipo = 'EN'
                     ( belzart = 'EACTPS' )
                     ( belzart = 'EACTP1' periodo = 'P1' )
                     ( belzart = 'EACTP2' periodo = 'P2' )
                     ( belzart = 'EACTP3' periodo = 'P3' )
                     ( belzart = 'EACTF1' periodo = 'P1' )
                     ( belzart = 'EACTF2' periodo = 'P2' )
                     ( belzart = 'EACTF3' periodo = 'P3' )
                     ( belzart = 'EACTF4' periodo = 'P4' )
                     ( belzart = 'EACTF5' periodo = 'P5' )
                     ( belzart = 'EACTF6' periodo = 'P6' ) ).

  " Potencia (solo para la posición de potencia mayor a importe 0)
  lt_conc = VALUE #( BASE lt_conc sparte = p_luz tipo = 'PO'
                     ( belzart = 'EPOTP1' )
                     ( belzart = 'EPOTP2' )
                     ( belzart = 'EPOTP3' )
                     ( belzart = 'EPOTP4' )
                     ( belzart = 'EPOTP5' )
                     ( belzart = 'EPOTP6' ) ).

  " Resto de la base del IEE (además de energía y potencia)
  lt_conc = VALUE #( BASE lt_conc sparte = p_luz tipo = 'BI'
                     ( belzart = 'EBONSO' ) ).

  " Descuentos sobre la energía activa
  lt_conc = VALUE #( BASE lt_conc sparte = p_luz tipo = 'DE'
                     ( belzart = 'EDACTS' )
                     ( belzart = 'EDEMPC' ) ).

  " IEE y su mínimo comunitario: prefijo + región, en parejas
  lt_region  = VALUE #( ( 'AL' ) ( 'GE' ) ( 'GU' ) ( 'NA' ) ( 'VI' ) ).
  lt_par_iee = VALUE #( ( iee = 'EIEE' min = 'EMIC' )     " normal
                        ( iee = 'EIER' min = 'EMIR' )     " reducido
                        ( iee = 'EIEX' min = 'EMIX' )     " exención
                        ( iee = 'EIED' min = 'EMID' )     " derecho a exención
                        ( iee = 'EIEM' min = 'EMIM' ) ).  " derecho a reducción

  LOOP AT lt_par_iee INTO DATA(ls_par).
    LOOP AT lt_region INTO DATA(lv_region).
      lv_iee = ls_par-iee && lv_region.
      lv_min = ls_par-min && lv_region.
      APPEND VALUE #( sparte = p_luz belzart = lv_iee tipo = 'IE' belzart_rel = lv_min ) TO lt_conc.
      APPEND VALUE #( sparte = p_luz belzart = lv_min tipo = 'IM' belzart_rel = lv_iee ) TO lt_conc.
    ENDLOOP.
  ENDLOOP.

  "--- Gas -------------------------------------------------------------
  lt_conc = VALUE #( BASE lt_conc sparte = p_gas
                     ( belzart = 'GTVARI' tipo = 'TV' )
                     " Descuentos sobre el término variable
                     ( belzart = 'GDTVAR' tipo = 'DE' )
                     ( belzart = 'GDEMPV' tipo = 'DE' )
                     ( belzart = 'GDEMPC' tipo = 'DE' ) ).

  " Impuesto de hidrocarburos (IEH) por región: normal, exención y
  " derecho a exención
  lt_ieh = VALUE #( ( 'GIEH' ) ( 'GIEX' ) ( 'GIED' ) ).
  LOOP AT lt_ieh INTO DATA(lv_ieh).
    LOOP AT lt_region INTO lv_region.
      lv_iee = lv_ieh && lv_region.
      APPEND VALUE #( sparte = p_gas belzart = lv_iee tipo = 'IH' ) TO lt_conc.
    ENDLOOP.
  ENDLOOP.

  "--- Grabación y listado ----------------------------------------------
  IF p_test = abap_false.
    MODIFY zfa_fraud_conc FROM TABLE lt_conc.
    COMMIT WORK.
    WRITE: / |{ lines( lt_conc ) } conceptos grabados en ZFA_FRAUD_CONC|.
  ELSE.
    WRITE: / |Modo test: { lines( lt_conc ) } conceptos (no se graba nada)|.
  ENDIF.
  ULINE.

  LOOP AT lt_conc INTO DATA(ls_conc).
    WRITE: / ls_conc-sparte, ls_conc-belzart, ls_conc-tipo,
             ls_conc-periodo, ls_conc-belzart_rel.
  ENDLOOP.
