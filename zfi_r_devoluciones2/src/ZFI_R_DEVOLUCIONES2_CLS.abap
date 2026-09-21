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
*   (blanco)  = abierto              -> hay que cerrar
*   5         = contabilizado        -> nada que hacer
*   cualquier otro (1=cerrado sin contab., o 2/3/4/6/9=intermedio/
*   incidencia) -> se intenta contabilizar igual (FKK_RLS_POST_LOT
*   decide si el lote es valido o no; si no lo es, es el propio FM el
*   que devuelve el error estandar via sy-subrc/excepciones - no
*   filtramos nosotros por STARS de antemano, ver process_lot).
*
* Mensajes vía ZXX_CL_MSG_LOGS (clase ZFI_MC_001), igual que
* ZFI_R_DEVOLUCIONES/ZFI_R_DEVOLUCIONES_CREA, en vez de WRITE con texto
* suelto:
*   178  E  Ningún lote indicado existe en DFKKRK
*   179  I  Lote &1: STARS=&2 (simulación, no se toca nada)
*   180  E  Lote &1: error en &2 (&3)
*   181  S  Lote &1: cerrado y contabilizado
*   182  S  Lote &1: ya estaba contabilizado, nada que hacer
*
* Detalle de error tipo FP09 (RU_03, para ZFI_FM_DEVOLUCIONES2): cuando
* FKK_RLS_POST_LOT falla, se captura el mismo detalle de mensajes por
* documento que muestra la FP09 (LCL_MESSENGER/GDBG de SAPLFKKTRACE, via
* PERFORM retrieve_data IN PROGRAM + ASSIGN dinamico a
* T_MESSENGERDATA[] + MESSAGE...INTO por cada linea TY='E') y se deja en
* GT_POST_ERRORS; se muestra tambien en pantalla (SHOW_LOG_MSG, con
* WRITE directo - son mensajes dinamicos de FI-CA, no un numero de
* mensaje fijo de ZFI_MC_001) y al final de EXECUTE se exporta siempre
* a memoria ABAP (MEMORY ID 'ZFI_DEVOL2_ERRORS', ver EXPORT_POST_ERRORS)
* para que ZFI_FM_DEVOLUCIONES2 (que llama a este report via
* SUBMIT...AND RETURN, una sesion interna distinta donde los datos
* globales de SAPLFKKTRACE ya no son alcanzables) pueda importarlo
* despues y montar ES_ERROR-DESCRIPTION con el detalle real, no solo
* con el STARS resultante.
CLASS lcl_devoluciones2 DEFINITION.
  PUBLIC SECTION.

    CONSTANTS:
      co_stars_posted TYPE dfkkrk-stars VALUE '5'.

    TYPES: ty_r_keyr1 TYPE RANGE OF dfkkrk-keyr1.

    METHODS:
      constructor IMPORTING ir_keyr1 TYPE ty_r_keyr1
                            iv_simu  TYPE abap_bool DEFAULT abap_false,

      execute.

  PRIVATE SECTION.

    TYPES:
      BEGIN OF ty_post_error,
        keyr1   TYPE dfkkrk-keyr1,
        message TYPE string,
      END OF ty_post_error,
      tt_post_error TYPE STANDARD TABLE OF ty_post_error WITH EMPTY KEY.

    DATA: gr_keyr1       TYPE ty_r_keyr1,
          gv_simu        TYPE abap_bool,
          go_msg_logs    TYPE REF TO zxx_cl_msg_logs,
          gt_post_errors TYPE tt_post_error.

    METHODS:
      process_lot IMPORTING iv_keyr1 TYPE dfkkrk-keyr1,

      get_post_lot_errors IMPORTING iv_keyr1 TYPE dfkkrk-keyr1
                           RETURNING VALUE(rt_errors) TYPE tt_post_error,

      export_post_errors,

      show_log_msg.

ENDCLASS.

CLASS lcl_devoluciones2 IMPLEMENTATION.

  METHOD constructor.
    gr_keyr1 = ir_keyr1.
    gv_simu  = iv_simu.
  ENDMETHOD.

  METHOD execute.

    go_msg_logs = NEW zxx_cl_msg_logs( ).
    CLEAR gt_post_errors.

    DATA: lt_keyr1 TYPE STANDARD TABLE OF dfkkrk-keyr1.

    SELECT keyr1 FROM dfkkrk INTO TABLE lt_keyr1 WHERE keyr1 IN gr_keyr1.

    IF lt_keyr1 IS INITIAL.
      go_msg_logs->append_messages(
        iv_msg_type   = 'E'
        iv_msg_class  = 'ZFI_MC_001'
        iv_msg_number = '178' ).
      show_log_msg( ).
      export_post_errors( ).
      RETURN.
    ENDIF.

    LOOP AT lt_keyr1 INTO DATA(lv_keyr1_loop).
      process_lot( lv_keyr1_loop ).
    ENDLOOP.

    show_log_msg( ).
    export_post_errors( ).

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

    IF lv_stars = co_stars_posted.
      go_msg_logs->append_messages(
        iv_msg_type   = 'S'
        iv_msg_class  = 'ZFI_MC_001'
        iv_msg_number = '182'
        iv_param_v1   = CONV #( lv_keyr1 ) ).
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
          iv_param_v3   = |{ sy-subrc }| ).
        RETURN.
      ENDIF.
    ENDIF.

    " No se filtra por STARS antes de contabilizar (cerrado o no): se
    " deja que FKK_RLS_POST_LOT decida si el lote es valido y devuelva
    " su propio error estandar si no lo es - ver cabecera del include.
    CALL FUNCTION 'FKK_RLS_POST_LOT'
      EXPORTING
        i_keyr1             = lv_keyr1
        i_xfull_trace       = abap_true
      EXCEPTIONS
        not_valid           = 1
        invalid_key         = 2
        lock_failure        = 3
        no_data             = 4
        postings_incomplete = 5
        OTHERS              = 6.
    IF sy-subrc <> 0.
      APPEND LINES OF get_post_lot_errors( lv_keyr1 ) TO gt_post_errors.
      go_msg_logs->append_messages(
        iv_msg_type   = 'E'
        iv_msg_class  = 'ZFI_MC_001'
        iv_msg_number = '180'
        iv_param_v1   = CONV #( lv_keyr1 )
        iv_param_v2   = `FKK_RLS_POST_LOT`
        iv_param_v3   = |{ sy-subrc }| ).
      RETURN.
    ENDIF.

    go_msg_logs->append_messages(
      iv_msg_type   = 'S'
      iv_msg_class  = 'ZFI_MC_001'
      iv_msg_number = '181'
      iv_param_v1   = CONV #( lv_keyr1 ) ).

  ENDMETHOD.

  METHOD get_post_lot_errors.

    " Mismo mecanismo probado en debug contra FP09 (ver docs/DF_resumen.md):
    " RETRIEVE_DATA es un FORM publico de SAPLFKKTRACE (el programa que
    " contiene LCL_MESSENGER/GDBG) que, llamado justo despues de
    " FKK_RLS_POST_LOT (misma sesion interna: SAPLFKKTRACE ya esta
    " cargado porque FKK_RLS_POST_LOT llama a FKK_TRACE_INIT
    " internamente), rellena la tabla global T_MESSENGERDATA con el
    " filtro de mensajes que le pidamos - aqui solo errores.
    PERFORM retrieve_data IN PROGRAM saplfkktrace
        USING abap_true space space space space.

    FIELD-SYMBOLS: <msgtab>  TYPE STANDARD TABLE,
                   <linea>   TYPE any,
                   <ls_data> TYPE dfkktracep.

    " T_MESSENGERDATA tiene linea de cabecera: hace falta el [] para
    " referirse al cuerpo de la tabla, no a la cabecera (ver CLAUDE.md).
    ASSIGN ('(SAPLFKKTRACE)T_MESSENGERDATA[]') TO <msgtab>.
    CHECK <msgtab> IS ASSIGNED.

    LOOP AT <msgtab> ASSIGNING <linea>.
      ASSIGN COMPONENT 'DATA' OF STRUCTURE <linea> TO <ls_data>.

      MESSAGE ID <ls_data>-id TYPE <ls_data>-ty NUMBER <ls_data>-nr
              WITH <ls_data>-v1 <ls_data>-v2 <ls_data>-v3 <ls_data>-v4
              INTO DATA(lv_text).

      APPEND VALUE #( keyr1 = iv_keyr1 message = lv_text ) TO rt_errors.
    ENDLOOP.

  ENDMETHOD.

  METHOD export_post_errors.

    " SY-CALLD no distingue de forma fiable "llamado por SUBMIT desde
    " ZFI_FM_DEVOLUCIONES2" de "ejecutado a mano en SE38" (el propio
    " "Ejecutar" de SE38 tambien lo deja a 'X') - se exporta siempre.
    " Siempre (aunque este vacio), para que ZFI_FM_DEVOLUCIONES2 no se
    " encuentre datos residuales de una llamada anterior en la misma
    " sesion. En ejecucion manual esta clave de memoria simplemente no
    " la lee nadie, no hace falta filtrar.
    EXPORT gt_post_errors = gt_post_errors TO MEMORY ID 'ZFI_DEVOL2_ERRORS'.

  ENDMETHOD.

  METHOD show_log_msg.

    DATA(lt_msg_logs) = go_msg_logs->get_messages( ).

    LOOP AT lt_msg_logs ASSIGNING FIELD-SYMBOL(<fs_log>).
      WRITE / <fs_log>-message.
    ENDLOOP.

    " Detalle de error tipo FP09 (ver GET_POST_LOT_ERRORS): son mensajes
    " dinamicos de FI-CA reconstruidos con MESSAGE...INTO, no mensajes
    " propios via ZFI_MC_001 (no hay un numero de mensaje fijo posible
    " para "cualquier texto que devuelva FKK_RLS_POST_LOT"), por eso van
    " con WRITE directo en vez de por GO_MSG_LOGS.
    LOOP AT gt_post_errors ASSIGNING FIELD-SYMBOL(<fs_post_error>).
      WRITE / |{ <fs_post_error>-keyr1 }: { <fs_post_error>-message }|.
    ENDLOOP.

    go_msg_logs->clear_messages( ).

  ENDMETHOD.

ENDCLASS.
