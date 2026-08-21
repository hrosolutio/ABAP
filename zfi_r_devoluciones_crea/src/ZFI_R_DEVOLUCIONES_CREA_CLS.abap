*&---------------------------------------------------------------------*
*& Include          ZFI_R_DEVOLUCIONES_CREA_CLS
*&---------------------------------------------------------------------*
* RU_02 (CDI_11): creacion del lote de devoluciones en FI-CA a partir del
* fichero _DEV (salida de ZFI_R_ECOFI_SPLIT / RU_01), via transaccion FP09.
*
* FP09 es una transaccion de dialogo (LCL_RLOT, clase local del pool de
* funciones FKR2DLG, no invocable desde fuera). Depurando su boton Grabar
* se localizo la API publica real del grupo de funcion FKR2 ("RLS" =
* Ruecklaeuferstapel = lote de devoluciones):
*   FKK_RLS_HDR_PREPARE  -> prepara la cabecera (calcula KEYR1, el nº de
*                           lote AAMMDDCDI11x)
*   FKK_RLS_HDR_SAVE     -> graba la cabecera
*   FKK_RLS_ITEM_PREPARE -> pide N posiciones plantilla (KEYR1/POSRA ya
*                           calculados)
*   FKK_RLS_ITEM_SAVE_MASS -> graba todas las posiciones de una vez
*
* Probado con exito en Integracion (lote 260819CDI110, 3 posiciones
* reales del _DEV de zfi_r_ecofi_split) - ver docs/DF_resumen.md para el
* detalle completo de la depuracion y los campos confirmados.
*
* Campos minimos necesarios (confirmado con la prueba real, ver DF):
*   Cabecera (DFKKRK): BUKRS, RLGRD, RLSKO, WAERS.
*   Posicion (DFKKRP), por linea del _DEV: BETRR (importe, EN NEGATIVO -
*   confirmado con el error real >4703 al meterlo en positivo), SELT1 = 'B',
*   SELW1 = nº de documento SAP. El banco/IBAN del deudor (BANKL/BANKK/
*   BANKN/IBAN) y OPBEL se quedan vacios y el lote se graba igual - no
*   hacen falta para crear el lote (a diferencia del enfoque descartado
*   con RFKKA00/multicash, que si los necesitaba).
CLASS lcl_devoluciones_crea DEFINITION.
  PUBLIC SECTION.

    CONSTANTS:
      co_processed_dir TYPE string     VALUE 'procesados/',
      co_error_dir     TYPE string     VALUE 'error/',
      co_suffix_dev    TYPE string     VALUE '_DEV',

      " Proceso propio en ZFI_T_FILE_LOG (BUSINESS_DESC), distinto de
      " 'DEV' para no mezclar con las devoluciones bancarias reales.
      co_dev           TYPE string     VALUE 'EXT',

      " --- Claves en ZFI_T_CONSTANTS de los valores fijos del DF (RU_02):
      " sociedad, motivo de devolucion, cta. de compensacion, ruta logica
      " de fichero y moneda. Se leen en GET_CONSTANTS al principio de la
      " ejecucion (no son valores fijos en el codigo, cambian por sistema
      " o por prueba sin tocar ni reactivar ABAP - p.ej. la cta. de
      " compensacion es distinta en DES que en Integracion, y la ruta
      " logica puede apuntar a otra ya existente mientras ZFICA_COBROS_
      " ECOFI no se cree en ningun sistema, ver docs/DF_resumen.md).
      co_application_id  TYPE zfi_de_application_id VALUE 'CDI_11',
      co_process_id      TYPE zfi_de_process_id     VALUE 'DEVOL_CREA',
      co_sub_process_id  TYPE zfi_de_sub_process_id VALUE space,
      co_const_sociedad  TYPE zfi_de_constant_id    VALUE 'SOCIEDAD',
      co_const_motivo    TYPE zfi_de_constant_id    VALUE 'MOTIVO',
      co_const_cta_comp  TYPE zfi_de_constant_id    VALUE 'CTA_COMPENSACION',
      co_const_ruta_log  TYPE zfi_de_constant_id    VALUE 'RUTA_LOGICA',
      co_const_moneda    TYPE zfi_de_constant_id    VALUE 'MONEDA'.

    TYPES:
      BEGIN OF ty_s_item,
        docnum        TYPE string,
        importe_cent  TYPE i,
      END OF ty_s_item,
      ty_t_item TYPE STANDARD TABLE OF ty_s_item WITH EMPTY KEY.

    METHODS:
      constructor IMPORTING iv_path   TYPE string
                            iv_upload TYPE c,

      execute RAISING zfi_cl_cx_load_file zfi_cl_cx_file.

  PRIVATE SECTION.

    DATA: gv_path        TYPE string,
          gv_upload      TYPE c,
          gv_root_path   TYPE string,
          gv_backup_path TYPE eseftappl,
          gv_error_path  TYPE eseftappl,
          go_file_log    TYPE REF TO zfi_cl_update_file_log,
          go_msg_logs    TYPE REF TO zxx_cl_msg_logs,

      " Rellenas por GET_CONSTANTS a partir de ZFI_T_CONSTANTS - no son
      " constantes de programa, son datos de configuracion por sistema.
      gv_sociedad     TYPE dfkkrk-bukrs,
      gv_motivo       TYPE dfkkrk-rlgrd,
      gv_cta_comp     TYPE dfkkrk-rlsko,
      gv_logical_path TYPE pathintern,
      " STRING (no dfkkrk-waers) para que la busqueda del tag de moneda en
      " el fichero (FIND FIRST OCCURRENCE) no arrastre blancos de relleno
      " de un tipo de longitud fija - ver CLAUDE.md.
      gv_moneda       TYPE string.

    METHODS:
      get_constants RETURNING VALUE(rv_ok) TYPE flag,

      execute_server RAISING zfi_cl_cx_load_file zfi_cl_cx_file,
      execute_upload RAISING zfi_cl_cx_load_file zfi_cl_cx_file,

      process_dev_file IMPORTING iv_filename TYPE string
                                  it_lines    TYPE string_table
                        RAISING   zfi_cl_cx_load_file zfi_cl_cx_file,

      get_directories,

      get_dev_files RETURNING VALUE(rt_files) TYPE string_table,

      read_server_file IMPORTING iv_path         TYPE string
                        RETURNING VALUE(rt_lines) TYPE string_table,

      parse_dev_lines IMPORTING it_lines         TYPE string_table
                       RETURNING VALUE(rt_items) TYPE ty_t_item,

      cent_to_str IMPORTING iv_cent          TYPE i
                             iv_negative      TYPE abap_bool DEFAULT abap_false
                  RETURNING VALUE(rv_result) TYPE string,

      create_lot IMPORTING it_items TYPE ty_t_item
                 EXPORTING ev_keyr1 TYPE dfkkrk-keyr1
                           ev_ok    TYPE flag
                           ev_error TYPE string,

      transport_files IMPORTING is_file_log TYPE zfi_t_file_log
                                 iv_path     TYPE eseftappl,

      show_log_msg.

ENDCLASS.

CLASS lcl_devoluciones_crea IMPLEMENTATION.

  METHOD constructor.
    gv_path   = iv_path.
    gv_upload = iv_upload.
  ENDMETHOD.

  METHOD execute.

    go_msg_logs = NEW zxx_cl_msg_logs( ).
    go_file_log = NEW zfi_cl_update_file_log( iv_process = co_dev ).

    IF get_constants( ) = abap_false.
      RETURN.
    ENDIF.

    IF gv_upload = abap_true.
      execute_upload( ).
    ELSE.
      execute_server( ).
    ENDIF.

    show_log_msg( ).

  ENDMETHOD.

  METHOD get_constants.

    CLEAR rv_ok.

    DATA: lt_constants TYPE TABLE OF zfi_t_constants.

    SELECT * FROM zfi_t_constants INTO TABLE lt_constants
      WHERE application_id = co_application_id
        AND process_id     = co_process_id
        AND sub_process_id = co_sub_process_id
        AND active         = abap_true.

    LOOP AT lt_constants INTO DATA(ls_constant).
      CASE ls_constant-constant_id.
        WHEN co_const_sociedad.
          gv_sociedad = ls_constant-constant_value.
        WHEN co_const_motivo.
          gv_motivo = ls_constant-constant_value.
        WHEN co_const_cta_comp.
          gv_cta_comp = ls_constant-constant_value.
        WHEN co_const_ruta_log.
          gv_logical_path = ls_constant-constant_value.
        WHEN co_const_moneda.
          gv_moneda = ls_constant-constant_value.
      ENDCASE.
    ENDLOOP.

    IF gv_sociedad IS INITIAL OR gv_motivo IS INITIAL OR gv_cta_comp IS INITIAL
       OR gv_logical_path IS INITIAL OR gv_moneda IS INITIAL.
      WRITE: / 'Faltan constantes en ZFI_T_CONSTANTS para', co_application_id, co_process_id.
      RETURN.
    ENDIF.

    rv_ok = abap_true.

  ENDMETHOD.

  METHOD execute_server.

    get_directories( ).

    IF gv_root_path IS INITIAL.
      MESSAGE 'No se ha podido resolver la ruta lógica del servidor.' TYPE 'E'.
      RETURN.
    ENDIF.

    DATA(lt_files) = get_dev_files( ).

    IF lt_files IS INITIAL.
      MESSAGE 'No hay ficheros _DEV para procesar en el servidor.' TYPE 'I'.
      RETURN.
    ENDIF.

    LOOP AT lt_files INTO DATA(lv_filename).

      DATA(lt_lines) = read_server_file( gv_root_path && lv_filename ).

      IF lt_lines IS INITIAL.
        WRITE: / 'No se ha podido leer:', lv_filename.
        CONTINUE.
      ENDIF.

      process_dev_file( iv_filename = lv_filename
                         it_lines    = lt_lines ).

    ENDLOOP.

  ENDMETHOD.

  METHOD execute_upload.

    " OJO: a diferencia del borrador anterior (que solo generaba ficheros
    " de prueba), este modo YA CREA EL LOTE DE VERDAD en el sistema donde
    " se ejecute - no es una simulacion. Pensado para probar rapido con un
    " _DEV local sin pasar por AL11. Sin traza en ZFI_T_FILE_LOG.
    DATA: lt_lines TYPE string_table.

    cl_gui_frontend_services=>gui_upload(
      EXPORTING filename                = gv_path
                filetype                = 'ASC'
      CHANGING  data_tab                = lt_lines
      EXCEPTIONS OTHERS                 = 1 ).

    IF sy-subrc <> 0 OR lt_lines IS INITIAL.
      MESSAGE 'No se ha podido leer el fichero indicado.' TYPE 'E'.
      RETURN.
    ENDIF.

    DATA(lt_items) = parse_dev_lines( lt_lines ).

    IF lt_items IS INITIAL.
      MESSAGE 'El fichero no contiene líneas de extorno reconocibles.' TYPE 'E'.
      RETURN.
    ENDIF.

    create_lot( EXPORTING it_items = lt_items
                IMPORTING ev_keyr1 = DATA(lv_keyr1)
                          ev_ok    = DATA(lv_ok)
                          ev_error = DATA(lv_error) ).

    IF lv_ok = abap_true.
      WRITE: / 'Lote creado:', lv_keyr1, '(', lines( lt_items ), 'posiciones)'.
    ELSE.
      WRITE: / 'Error al crear el lote:', lv_error.
    ENDIF.

  ENDMETHOD.

  METHOD process_dev_file.

    TRY.
        go_file_log->create_log( EXPORTING iv_filename = CONV #( iv_filename )
                                  IMPORTING es_file_log = DATA(ls_file_log) ).
      CATCH zfi_cl_cx.
        WRITE: / 'No se ha podido registrar en ZFI_T_FILE_LOG:', iv_filename.
        RETURN.
    ENDTRY.

    DATA(lt_items) = parse_dev_lines( it_lines ).

    IF lt_items IS INITIAL.
      ls_file_log-status = 'ERROR'.
      ls_file_log-fecha_processo = sy-datum.
      ls_file_log-hora_processo  = sy-uzeit.
      ls_file_log-usuario        = sy-uname.
      UPDATE zfi_t_file_log FROM ls_file_log.
      transport_files( is_file_log = ls_file_log iv_path = gv_error_path ).
      WRITE: / 'Sin líneas de extorno reconocibles:', iv_filename.
      RETURN.
    ENDIF.

    ls_file_log-nbr_lines_items = lines( lt_items ).
    DATA(lv_total_cent) = REDUCE i( INIT s = 0 FOR item IN lt_items NEXT s = s + item-importe_cent ).
    ls_file_log-importe = cent_to_str( lv_total_cent ).

    create_lot( EXPORTING it_items = lt_items
                IMPORTING ev_keyr1 = DATA(lv_keyr1)
                          ev_ok    = DATA(lv_ok)
                          ev_error = DATA(lv_error) ).

    ls_file_log-fecha_processo = sy-datum.
    ls_file_log-hora_processo  = sy-uzeit.
    ls_file_log-usuario        = sy-uname.

    IF lv_ok = abap_true.
      ls_file_log-status = 'PROCESADO'.
      " Reutilizamos este campo (no hay uno dedicado en ZFI_T_FILE_LOG)
      " para dejar trazado el nº de lote de devoluciones creado.
      ls_file_log-file_name_header = lv_keyr1.
      UPDATE zfi_t_file_log FROM ls_file_log.
      transport_files( is_file_log = ls_file_log iv_path = gv_backup_path ).
      WRITE: / iv_filename, '-> lote', lv_keyr1, '(', lines( lt_items ), 'posiciones)'.
    ELSE.
      ls_file_log-status = 'ERROR'.
      UPDATE zfi_t_file_log FROM ls_file_log.
      transport_files( is_file_log = ls_file_log iv_path = gv_error_path ).
      WRITE: / iv_filename, '-> ERROR:', lv_error.
    ENDIF.

  ENDMETHOD.

  METHOD get_directories.

    DATA: lv_raw_dir TYPE rsfillst-dirname.

    TRY.
        zxx_cl_file_utils=>get_directory(
          EXPORTING i_logical_path = gv_logical_path
          IMPORTING e_directory    = lv_raw_dir ).
      CATCH zfi_cl_cx_file.
        RETURN.
    ENDTRY.

    CONCATENATE lv_raw_dir '' INTO gv_root_path.
    REPLACE ALL OCCURRENCES OF '*' IN gv_root_path WITH ''.

    CONCATENATE gv_root_path co_processed_dir INTO gv_backup_path.
    CONCATENATE gv_root_path co_error_dir     INTO gv_error_path.

  ENDMETHOD.

  METHOD get_dev_files.

    DATA: lt_dir_list TYPE TABLE OF epsfili.

    CALL FUNCTION 'EPS2_GET_DIRECTORY_LISTING'
      EXPORTING
        dir_name               = gv_root_path
      TABLES
        dir_list                = lt_dir_list
      EXCEPTIONS
        invalid_eps_subdir      = 1
        sapgparam_failed        = 2
        build_directory_failed  = 3
        no_authorization        = 4
        read_directory_failed   = 5
        too_many_read_errors    = 6
        empty_directory_list    = 7
        OTHERS                  = 8.

    CHECK sy-subrc = 0.

    LOOP AT lt_dir_list INTO DATA(ls_dir).
      CHECK ls_dir-name IS NOT INITIAL.
      CHECK ls_dir-name CS co_suffix_dev.
      APPEND ls_dir-name TO rt_files.
    ENDLOOP.

  ENDMETHOD.

  METHOD read_server_file.

    OPEN DATASET iv_path FOR INPUT IN TEXT MODE ENCODING DEFAULT.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    DO.
      DATA(lv_line) = ``.
      READ DATASET iv_path INTO lv_line.
      IF sy-subrc <> 0.
        EXIT.
      ENDIF.
      APPEND lv_line TO rt_lines.
    ENDDO.

    CLOSE DATASET iv_path.

  ENDMETHOD.

  METHOD parse_dev_lines.

    LOOP AT it_lines INTO DATA(lv_line).

      " Primera linea = cabecera del fichero ECOFI, no es un extorno
      IF sy-tabix = 1.
        CONTINUE.
      ENDIF.

      FIND FIRST OCCURRENCE OF gv_moneda IN lv_line MATCH OFFSET DATA(lv_eur_off).
      CHECK sy-subrc = 0.

      " Importe: bloque de digitos justo antes de la moneda (en centimos)
      DATA(lv_before_eur) = substring( val = lv_line len = lv_eur_off ).
      FIND PCRE '(\d+)\s*$' IN lv_before_eur SUBMATCHES DATA(lv_digits).
      CHECK sy-subrc = 0.

      " Nº de documento SAP: 12 digitos justo despues de la moneda (ver
      " ZFI_R_ECOFI_SPLIT_CLS, metodo SPLIT_LINES, que es quien los escribe)
      DATA(lv_docnum) = substring( val = lv_line off = lv_eur_off + 3 + 2 len = 12 ).
      CHECK lv_docnum CO '0123456789'.

      APPEND VALUE #( docnum       = lv_docnum
                       importe_cent = lv_digits ) TO rt_items.

    ENDLOOP.

  ENDMETHOD.

  METHOD cent_to_str.

    " Aritmetica entera (DIV/MOD), sin usar "/" - con dos operandos TYPE i,
    " "/" no da el decimal exacto (ver CLAUDE.md). El resultado es un
    " string decimal estandar ("-60.49"), que se puede asignar tal cual a
    " un campo CURR (DFKKRP-BETRR) - la conversion string->CURR de ABAP no
    " tiene el problema de la division entera, es un parseo normal.
    DATA(lv_euros) = iv_cent DIV 100.
    DATA(lv_cents) = iv_cent MOD 100.

    DATA(lv_cents_str) = |{ lv_cents }|.
    IF strlen( lv_cents_str ) = 1.
      lv_cents_str = |0{ lv_cents_str }|.
    ENDIF.

    rv_result = COND #( WHEN iv_negative = abap_true THEN |-{ lv_euros }.{ lv_cents_str }|
                         ELSE |{ lv_euros }.{ lv_cents_str }| ).

  ENDMETHOD.

  METHOD create_lot.

    CLEAR: ev_keyr1, ev_ok, ev_error.

    DATA: ls_dfkkrk TYPE dfkkrk.

    ls_dfkkrk-bukrs = gv_sociedad.
    ls_dfkkrk-rlgrd = gv_motivo.
    ls_dfkkrk-rlsko = gv_cta_comp.
    ls_dfkkrk-waers = gv_moneda.
    ls_dfkkrk-blart = `DV`.

    CALL FUNCTION 'FKK_RLS_HDR_PREPARE'
      CHANGING
        c_dfkkrk         = ls_dfkkrk
      EXCEPTIONS
        no_authorization = 1
        lot_exists       = 2
        locked            = 3
        failure           = 4
        OTHERS            = 5.
    IF sy-subrc <> 0.
      ev_error = |FKK_RLS_HDR_PREPARE: error { sy-subrc }|.
      RETURN.
    ENDIF.

    CALL FUNCTION 'FKK_RLS_HDR_SAVE'
      CHANGING
        c_dfkkrk         = ls_dfkkrk
      EXCEPTIONS
        error_message    = 1
        lot_locked       = 2
        no_authorization = 3
        update_error     = 4
        not_valid        = 5
        OTHERS           = 6.
    IF sy-subrc <> 0.
      ev_error = |FKK_RLS_HDR_SAVE: error { sy-subrc }|.
      RETURN.
    ENDIF.

    DATA: lt_dfkkrp TYPE STANDARD TABLE OF dfkkrp.

    CALL FUNCTION 'FKK_RLS_ITEM_PREPARE'
      EXPORTING
        i_keyr1      = ls_dfkkrk-keyr1
        i_dfkkrk     = ls_dfkkrk
        i_line_count = lines( it_items )
      TABLES
        t_dfkkrp = lt_dfkkrp
      EXCEPTIONS
        failure  = 1
        OTHERS   = 2.
    IF sy-subrc <> 0.
      ev_error = |FKK_RLS_ITEM_PREPARE: error { sy-subrc }|.
      RETURN.
    ENDIF.

    IF lines( lt_dfkkrp ) <> lines( it_items ).
      ev_error = 'FKK_RLS_ITEM_PREPARE no ha devuelto tantas posiciones como se pidieron.'.
      RETURN.
    ENDIF.

    LOOP AT lt_dfkkrp ASSIGNING FIELD-SYMBOL(<fs_dfkkrp>).
      DATA(ls_item) = it_items[ sy-tabix ].
      <fs_dfkkrp>-betrr = cent_to_str( iv_cent = ls_item-importe_cent iv_negative = abap_true ).
      <fs_dfkkrp>-selt1 = `B`.
      <fs_dfkkrp>-selw1 = ls_item-docnum.
    ENDLOOP.

    DATA: lt_dfkkrp_del TYPE STANDARD TABLE OF dfkkrp,
          lt_dfkkrp3    TYPE STANDARD TABLE OF dfkkrp3.

    CALL FUNCTION 'FKK_RLS_ITEM_SAVE_MASS'
      EXPORTING
        i_dontcheck           = space
      TABLES
        t_dfkkrp              = lt_dfkkrp
        t_dfkkrp_del          = lt_dfkkrp_del
        t_dfkkrp3             = lt_dfkkrp3
      CHANGING
        c_dfkkrk              = ls_dfkkrk
      EXCEPTIONS
        no_entries            = 1
        header_update_failed  = 2
        update_failed         = 3
        delete_failed         = 4
        insert_failed         = 5
        OTHERS                = 6.
    IF sy-subrc <> 0.
      ev_error = |FKK_RLS_ITEM_SAVE_MASS: error { sy-subrc }|.
      RETURN.
    ENDIF.

    COMMIT WORK.

    ev_keyr1 = ls_dfkkrk-keyr1.
    ev_ok    = abap_true.

  ENDMETHOD.

  METHOD transport_files.

    TRY.
        zxx_cl_file_utils=>move_server_file(
          EXPORTING
            i_sourcepath = CONV #( gv_root_path )
            i_targetpath = iv_path
            i_filename   = CONV #( is_file_log-file_name ) ).

      CATCH zfi_cl_cx_file.
        go_msg_logs->append_messages(
          iv_msg_type   = 'E'
          iv_msg_class  = 'ZFI_MC_001'
          iv_msg_number = '014'
          iv_param_v1   = condense( is_file_log-file_name(50) )
          iv_param_v2   = condense( is_file_log-file_name+50(50) ) ).
    ENDTRY.

  ENDMETHOD.

  METHOD show_log_msg.

    DATA(lt_msg_logs) = go_msg_logs->get_messages( ).

    LOOP AT lt_msg_logs ASSIGNING FIELD-SYMBOL(<fs_log>).
      WRITE / <fs_log>-message.
    ENDLOOP.

    go_msg_logs->clear_messages( ).

  ENDMETHOD.

ENDCLASS.
