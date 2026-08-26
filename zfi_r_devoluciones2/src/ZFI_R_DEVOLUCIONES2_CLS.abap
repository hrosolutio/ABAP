*&---------------------------------------------------------------------*
*& Include          ZFI_R_DEVOLUCIONES2_CLS
*&---------------------------------------------------------------------*
* RU_03 (CDI_11): cierre y contabilizacion de lotes de devolucion de
* extornos ya creados por RU_02 (ZFI_R_DEVOLUCIONES_CREA). El DF no dice
* nada de un mecanismo automatico para saber que lotes hay pendientes -
* el lote (o lotes) a tratar se indica a mano en la pantalla de seleccion
* (S_KEYR1), igual que en FP09. Este programa no lee ningun fichero ni
* consulta ZFI_T_FILE_LOG (una version anterior lo hacia, era una
* invencion sin base en el DF, descartada).
*
* Cadena real (localizada depurando FP09 con breakpoints de modulo de
* funcion sobre lotes reales, ver docs/DF_resumen.md) - no RFKKKA00:
*   FKK_RLS_CLOSE    -> cierra el lote (solo con KEYR1)
*   FKK_RLS_POST_LOT -> contabiliza el lote (solo con KEYR1)
*
* DFKKRK-STARS es el estado real del lote y la fuente de verdad para
* decidir que hacer con cada uno:
*   (blanco) = abierto             -> hay que cerrar
*   1        = cerrado, sin contab.-> hay que contabilizar
*   5        = contabilizado       -> nada que hacer
*   2/3/4/6/9 = intermedio/incidencia -> no se toca, revision manual
*               (sin reintento automatico, igual que el resto del
*               proyecto no reintenta ni corrige nada solo)
*
* Mensajes vía ZXX_CL_MSG_LOGS (clase ZFI_MC_001), igual que
* ZFI_R_DEVOLUCIONES/ZFI_R_DEVOLUCIONES_CREA, en vez de WRITE con texto
* suelto:
*   178  E  Ningún lote indicado existe en DFKKRK
*   179  I  Lote &1: STARS=&2 (simulación, no se toca nada)
*   180  E  Lote &1: error en &2 (&3)
*   181  S  Lote &1: cerrado y contabilizado
*   182  S  Lote &1: ya estaba contabilizado, nada que hacer
*   183  I  Lote &1: STARS=&2, revisar a mano en FP09
CLASS lcl_devoluciones2 DEFINITION.
  PUBLIC SECTION.

    CONSTANTS:
      co_stars_closed TYPE dfkkrk-stars VALUE '1',
      co_stars_posted TYPE dfkkrk-stars VALUE '5'.

    TYPES: ty_r_keyr1 TYPE RANGE OF dfkkrk-keyr1.

    METHODS:
      constructor IMPORTING ir_keyr1 TYPE ty_r_keyr1
                            iv_simu  TYPE abap_bool DEFAULT abap_false,

      execute.

  PRIVATE SECTION.

    DATA: gr_keyr1    TYPE ty_r_keyr1,
          gv_simu     TYPE abap_bool,
          go_msg_logs TYPE REF TO zxx_cl_msg_logs.

    METHODS:
      process_lot IMPORTING iv_keyr1 TYPE dfkkrk-keyr1,

      show_log_msg.

ENDCLASS.

CLASS lcl_devoluciones2 IMPLEMENTATION.

  METHOD constructor.
    gr_keyr1 = ir_keyr1.
    gv_simu  = iv_simu.
  ENDMETHOD.

  METHOD execute.

    go_msg_logs = NEW zxx_cl_msg_logs( ).

    DATA: lt_keyr1 TYPE STANDARD TABLE OF dfkkrk-keyr1.

    SELECT keyr1 FROM dfkkrk INTO TABLE lt_keyr1 WHERE keyr1 IN gr_keyr1.

    IF lt_keyr1 IS INITIAL.
      go_msg_logs->append_messages(
        iv_msg_type   = 'E'
        iv_msg_class  = 'ZFI_MC_001'
        iv_msg_number = '178' ).
      show_log_msg( ).
      RETURN.
    ENDIF.

    LOOP AT lt_keyr1 INTO DATA(lv_keyr1_loop).
      process_lot( lv_keyr1_loop ).
    ENDLOOP.

    show_log_msg( ).

  ENDMETHOD.

  METHOD process_lot.

    DATA(lv_keyr1) = iv_keyr1.
    DATA: lv_stars TYPE dfkkrk-stars.

    SELECT SINGLE stars FROM dfkkrk INTO lv_stars WHERE keyr1 = lv_keyr1.

    IF gv_simu = abap_true.
      go_msg_logs->append_messages(
        iv_msg_type   = 'I'
        iv_msg_class  = 'ZFI_MC_001'
        iv_msg_number = '179'
        iv_param_v1   = CONV #( lv_keyr1 )
        iv_param_v2   = CONV #( lv_stars ) ).
      RETURN.
    ENDIF.

    IF lv_stars IS INITIAL.
      CALL FUNCTION 'FKK_RLS_CLOSE'
        EXPORTING
          i_keyr1          = lv_keyr1
        EXCEPTIONS
          not_found        = 1
          no_authorization = 2
          not_valid        = 3
          OTHERS           = 4.
      IF sy-subrc <> 0.
        go_msg_logs->append_messages(
          iv_msg_type   = 'E'
          iv_msg_class  = 'ZFI_MC_001'
          iv_msg_number = '180'
          iv_param_v1   = CONV #( lv_keyr1 )
          iv_param_v2   = `FKK_RLS_CLOSE`
          iv_param_v3   = CONV #( sy-subrc ) ).
        RETURN.
      ENDIF.

      CLEAR lv_stars.
      SELECT SINGLE stars FROM dfkkrk INTO lv_stars WHERE keyr1 = lv_keyr1.
    ENDIF.

    IF lv_stars = co_stars_closed.

      CALL FUNCTION 'FKK_RLS_POST_LOT'
        EXPORTING
          i_keyr1             = lv_keyr1
        EXCEPTIONS
          not_valid           = 1
          invalid_key         = 2
          lock_failure        = 3
          no_data             = 4
          postings_incomplete = 5
          OTHERS              = 6.
      IF sy-subrc <> 0.
        go_msg_logs->append_messages(
          iv_msg_type   = 'E'
          iv_msg_class  = 'ZFI_MC_001'
          iv_msg_number = '180'
          iv_param_v1   = CONV #( lv_keyr1 )
          iv_param_v2   = `FKK_RLS_POST_LOT`
          iv_param_v3   = CONV #( sy-subrc ) ).
        RETURN.
      ENDIF.

      go_msg_logs->append_messages(
        iv_msg_type   = 'S'
        iv_msg_class  = 'ZFI_MC_001'
        iv_msg_number = '181'
        iv_param_v1   = CONV #( lv_keyr1 ) ).

    ELSEIF lv_stars = co_stars_posted.
      go_msg_logs->append_messages(
        iv_msg_type   = 'S'
        iv_msg_class  = 'ZFI_MC_001'
        iv_msg_number = '182'
        iv_param_v1   = CONV #( lv_keyr1 ) ).

    ELSE.
      go_msg_logs->append_messages(
        iv_msg_type   = 'I'
        iv_msg_class  = 'ZFI_MC_001'
        iv_msg_number = '183'
        iv_param_v1   = CONV #( lv_keyr1 )
        iv_param_v2   = CONV #( lv_stars ) ).
    ENDIF.

  ENDMETHOD.

  METHOD show_log_msg.

    DATA(lt_msg_logs) = go_msg_logs->get_messages( ).

    LOOP AT lt_msg_logs ASSIGNING FIELD-SYMBOL(<fs_log>).
      WRITE / <fs_log>-message.
    ENDLOOP.

    go_msg_logs->clear_messages( ).

  ENDMETHOD.

ENDCLASS.
