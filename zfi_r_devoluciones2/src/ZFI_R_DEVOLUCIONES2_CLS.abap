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
*   FKK_RLS_CLOSE          -> cierra el lote (solo con KEYR1)
*   FKK_RLS_LOCK/UNLOCK    -> bloquea y libera el lote antes de
*                             contabilizar, igual que FP09N (metodo
*                             SCHEDULE). Por si solos NO arreglan nada
*                             (confirmado por prueba real) - se dejan
*                             porque replican la estructura real de
*                             FP09N sin coste, pero la causa del bug de
*                             abajo esta en FKK_RLS_HDR_STARS_SET, no
*                             aqui.
*   FKK_RLS_HDR_STARS_SET  -> IMPRESCINDIBLE si STARS < '2' (causa REAL
*                             del falso "La devolucion ya ha sido
*                             contabilizada", encontrada depurando
*                             FKK_RLS_POST_LOT -> FKK_RLS_USABLE, no
*                             adivinada): FKK_RLS_USABLE solo acepta
*                             lotes con STARS en '2'/'3'/'4'
*                             (IF I_DFKKRK-STARS CA '234'); con STARS='1'
*                             (recien cerrado) da excepcion CLOSED, y el
*                             texto "ya contabilizada" que se ve en
*                             pantalla es un residuo de SY-MSGNO sin
*                             relacion con la causa real - ver
*                             docs/DF_resumen.md. I_XPLANNED='X' pone
*                             STARS=2 (planificado para contabilizar).
*   FKK_RLS_POST_LOT       -> contabiliza el lote (solo con KEYR1)
*
* DFKKRK-STARS es el estado real del lote y la fuente de verdad para
* decidir que hacer con cada uno:
*   (blanco)  = abierto              -> hay que cerrar
*   5         = contabilizado        -> nada que hacer
*   cualquier otro (1=cerrado sin contab., o 2/3/4/6/9=intermedio/
*   incidencia) -> se intenta contabilizar igual (FKK_RLS_POST_LOT
*   decide si el lote es valido o no; si no lo es, es el propio FM el
*   que devuelve el error estandar via sy-subrc/excepciones - no
*   filtramos nosotros por STARS de antemano, ver process_lot). Eso sí,
*   si STARS < '2' se llama antes a FKK_RLS_HDR_STARS_SET (ver arriba),
*   imprescindible para que FKK_RLS_POST_LOT no falle siempre.
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
* mensaje fijo de ZFI_MC_001) y, solo si nos ha llamado
* ZFI_FM_DEVOLUCIONES2 (senal P_RFC, ver ZFI_R_DEVOLUCIONES2_EVE), al
* final de EXECUTE se exporta a memoria ABAP (MEMORY ID
* 'ZFI_DEVOL2_ERRORS', ver EXPORT_POST_ERRORS) para que esa RFC (que
* llama a este report via SUBMIT...AND RETURN, una sesion interna
* distinta donde los datos globales de SAPLFKKTRACE ya no son
* alcanzables) pueda importarlo despues y montar ES_ERROR-DESCRIPTION
* con el detalle real, no solo con el STARS resultante.
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

    " FKK_RLS_LOCK antes de contabilizar - lo llama FP09N (metodo
    " SCHEDULE) y nosotros no lo haciamos. Real: sin esto, un lote
    " contabilizaba bien a mano en FP09N pero con nuestro codigo daba
    " "La devolucion ya ha sido contabilizada" (falso) en el primer
    " intento - repetible solo con nuestro programa (dos ejecuciones
    " seguidas, mismo error las dos), pero se "arreglaba" si antes se
    " habia intentado una vez por FP09N. I_POSRA=0/I_X_WRITELOCK='X'/
    " I_X_READLOCK=espacio son los valores por defecto de la propia FM
    " (interfaz real, ver SE37) - bloquea el lote entero, no hace falta
    " indicarlos.
    CALL FUNCTION 'FKK_RLS_LOCK'
      EXPORTING
        i_keyr1 = lv_keyr1
      EXCEPTIONS
        failure = 1
        OTHERS  = 2.
    IF sy-subrc <> 0.
      go_msg_logs->append_messages(
        iv_msg_type   = 'E'
        iv_msg_class  = 'ZFI_MC_001'
        iv_msg_number = '180'
        iv_param_v1   = CONV #( lv_keyr1 )
        iv_param_v2   = `FKK_RLS_LOCK`
        iv_param_v3   = |{ sy-subrc }| ).
      RETURN.
    ENDIF.

    " FKK_RLS_UNLOCK justo despues del LOCK, replicando el orden exacto
    " de FP09N (metodo SCHEDULE): LOCK -> ... -> UNLOCK -> ... -> POST_LOT.
    " Por si solo no arregla nada (el LOCK/UNLOCK sin nada real en medio
    " no deja huella en BD) - se deja porque replica la estructura real
    " sin coste, pero la causa real del bug esta en el bloque de abajo.
    CALL FUNCTION 'FKK_RLS_UNLOCK'
      EXPORTING
        i_keyr1 = lv_keyr1
      EXCEPTIONS
        OTHERS  = 0.

    " CAUSA REAL del falso "La devolucion ya ha sido contabilizada"
    " (encontrada depurando FKK_RLS_POST_LOT -> FKK_RLS_USABLE, no
    " adivinada): FKK_RLS_USABLE solo acepta lotes con STARS en '2'/'3'/
    " '4' (IF I_DFKKRK-STARS CA '234'). Con STARS='1' (recien cerrado,
    " sin contabilizar) da la excepcion CLOSED ("Stapel ist zwar
    " geschlossen, aber nicht geplant") - el mensaje que se ve en
    " pantalla ('ya contabilizada') es un texto residual sin relacion
    " con la causa real (SY-MSGNO de una comprobacion previa que no
    " coincide, ver docs/DF_resumen.md). El propio comentario del codigo
    " estandar de FKK_RLS_USABLE dice la solucion: "if you want to do
    " online posting set stars to the corresponding value via
    " FKK_RLS_HDR_STARS_SET" - FP09N (metodo SCHEDULE) lo hace
    " ("IF stars < 2. FKK_RLS_HDR_STARS_SET. ENDIF.") y nosotros no.
    " I_XPLANNED = "RLS ist eingeplant fuer Buchen" (planificado para
    " contabilizar, STARS=2) es el flag que corresponde a contabilizacion
    " online (interfaz real confirmada en SE37).
    IF lv_stars < '2'.
      CALL FUNCTION 'FKK_RLS_HDR_STARS_SET'
        EXPORTING
          i_keyr1    = lv_keyr1
          i_xplanned = abap_true
        EXCEPTIONS
          not_found  = 1
          OTHERS     = 2.
      IF sy-subrc <> 0.
        go_msg_logs->append_messages(
          iv_msg_type   = 'E'
          iv_msg_class  = 'ZFI_MC_001'
          iv_msg_number = '180'
          iv_param_v1   = CONV #( lv_keyr1 )
          iv_param_v2   = `FKK_RLS_HDR_STARS_SET`
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
    " Guardar SY-SUBRC ya: GET_POST_LOT_ERRORS hace MESSAGE...INTO por
    " cada linea capturada, y MESSAGE (con o sin INTO) pisa SY-SUBRC
    " como efecto colateral - si se lee despues de llamarlo, ya no es
    " el de FKK_RLS_POST_LOT.
    DATA(lv_subrc) = sy-subrc.
    IF lv_subrc <> 0.
      APPEND LINES OF get_post_lot_errors( lv_keyr1 ) TO gt_post_errors.
      go_msg_logs->append_messages(
        iv_msg_type   = 'E'
        iv_msg_class  = 'ZFI_MC_001'
        iv_msg_number = '180'
        iv_param_v1   = CONV #( lv_keyr1 )
        iv_param_v2   = `FKK_RLS_POST_LOT`
        iv_param_v3   = |{ lv_subrc }| ).
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

    " P_RFC (parametro NO-DISPLAY de la pantalla de seleccion, ver
    " ZFI_R_DEVOLUCIONES2_EVE) - solo lo rellena ZFI_FM_DEVOLUCIONES2 al
    " hacer su SUBMIT ... WITH SELECTION-TABLE. En ejecucion manual
    " (SE38) queda en blanco, y no exportamos nada - no hay ninguna RFC
    " esperando leerlo. SY-CALLD se probo antes y se descarto: no
    " distingue de forma fiable esta llamada de una ejecucion manual.
    CHECK p_rfc = abap_true.

    " Siempre que se llegue aqui (aunque este vacio), para que
    " ZFI_FM_DEVOLUCIONES2 no se encuentre datos residuales de una
    " llamada anterior en la misma sesion.
    EXPORT gt_post_errors = gt_post_errors TO MEMORY ID 'ZFI_DEVOL2_ERRORS'.

  ENDMETHOD.

  METHOD show_log_msg.

    DATA(lt_msg_logs) = go_msg_logs->get_messages( ).

    " Los WRITE solo tienen sentido si alguien va a ver la lista - en
    " ejecucion manual (SE38). Si llama ZFI_FM_DEVOLUCIONES2 (P_RFC='X'),
    " nadie va a leer nunca esta lista (es una llamada remota, sin
    " pantalla) y generarla es trabajo de mas.
    IF p_rfc IS INITIAL.
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
    ENDIF.

    go_msg_logs->clear_messages( ).

  ENDMETHOD.

ENDCLASS.
