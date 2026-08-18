*&---------------------------------------------------------------------*
*& Include          ZFI_R_DEVOLUCIONES_CREA_CLS
*&---------------------------------------------------------------------*
* RU_02 (CDI_11): creacion del lote de devoluciones en FI-CA a partir del
* fichero _DEV (salida de ZFI_R_ECOFI_SPLIT / RU_01), reutilizando el
* motor estandar RFKKA00 (igual que ZFI_R_DEVOLUCIONES/ZFI_R_DEVOLUCIONES2,
* pero aqui SOLO se crea el lote -p_xcre-, nunca se cierra/contabiliza
* -p_xcls/p_xbu-, eso es RU_03/ZFI_R_DEVOLUCIONES2).
*
* El original (ZFI_R_DEVOLUCIONES) genera los ficheros multicash
* AUSZUG/UMSATZ que espera RFKKA00 llamando a RFKKSEPA_DD_RJCT sobre el
* XML SEPA de devolucion real. Nuestra entrada (_DEV) no es XML, asi que
* aqui esos dos ficheros se generan a mano, linea a linea, a partir del
* formato deducido de 6 ejemplos reales (4 bancos distintos) sacados de
* ZFI_T_FILE_LOG/AL11 en Integracion - ver docs/DF_resumen.md para el
* detalle campo a campo y, sobre todo, para la lista de asunciones SIN
* VALIDAR TODAVIA CONTRA UNA EJECUCION REAL DE RFKKA00 (varios campos de
* UMSATZ se dejan en blanco porque el _DEV no lleva IBAN/BIC/motivo de
* devolucion real - el ECOFI es un extracto propio de cobros de Naturgy,
* no el XML SEPA con el detalle bancario).
CLASS lcl_devoluciones_crea DEFINITION.
  PUBLIC SECTION.

    CONSTANTS:
      co_logical_path  TYPE pathintern           VALUE 'ZFICA_COBROS_ECOFI',
      co_processed_dir TYPE string                VALUE 'procesados/',
      co_error_dir     TYPE string                VALUE 'error/',
      co_tmp_dir       TYPE string                VALUE 'tmp/',
      co_suffix_dev    TYPE string                VALUE '_DEV',
      co_eur_tag       TYPE string                VALUE 'EUR',
      co_tcode_mc      TYPE syst_tcode             VALUE 'FPB17',
      co_key           TYPE string                VALUE 'Z_ID',
      co_job           TYPE string                VALUE 'Z_JOB',
      c_st_procesado   TYPE string                VALUE 'PROCESADO',
      c_st_error       TYPE string                VALUE 'ERROR',

      " --- Fijos segun el DF (RU_02) ---
      co_sociedad      TYPE bukrs                  VALUE '1239',
      co_motivo        TYPE string                 VALUE 'Z01',
      co_cta_comp      TYPE string                 VALUE '4305500150',

      " --- PENDIENTE DE CONFIRMAR (ver docs/DF_resumen.md) ---
      " Entidad+oficina (8 digitos) de la cuenta de cobro. En los ejemplos
      " reales cambia segun el banco (Santander=0049, BBVA=0182,
      " CaixaBank=2100, Unicaja=2103); para el flujo nuevo (ECOFI) no
      " sabemos si hay una unica cuenta fija o si depende del banco. Se
      " deja vacio a proposito - SIN este valor el generador no produce
      " un AUSZUG/UMSATZ valido.
      co_bank_code     TYPE string                 VALUE '',
      " Cuenta (10 digitos). Asuncion: mismo valor que la cta. de
      " compensacion del DF (coincide en longitud, 10 digitos) - sin
      " confirmar.
      co_bank_account  TYPE string                 VALUE '4305500150',
      " Proceso propio en ZFI_T_FILE_LOG (BUSINESS_DESC), distinto de
      " 'DEV' para no mezclar con las devoluciones bancarias reales.
      co_dev           TYPE string                 VALUE 'EXT'.

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
          gv_tmp_path    TYPE eseftappl,
          gv_backup_path TYPE eseftappl,
          gv_error_path  TYPE eseftappl,
          go_file_log    TYPE REF TO zfi_cl_update_file_log,
          go_msg_logs    TYPE REF TO zxx_cl_msg_logs.

    METHODS:
      execute_server RAISING zfi_cl_cx_load_file zfi_cl_cx_file,
      execute_upload RAISING zfi_cl_cx_load_file zfi_cl_cx_file,

      process_dev_file IMPORTING iv_filename TYPE string
                                  it_lines    TYPE string_table
                        RAISING   zfi_cl_cx_load_file zfi_cl_cx_file,

      get_directories,

      get_dev_files RETURNING VALUE(rt_files) TYPE string_table,

      read_server_file IMPORTING iv_path         TYPE string
                        RETURNING VALUE(rt_lines) TYPE string_table,

      write_server_file IMPORTING iv_path  TYPE string
                                   it_lines TYPE string_table,

      parse_dev_lines IMPORTING it_lines       TYPE string_table
                       RETURNING VALUE(rt_items) TYPE ty_t_item,

      format_amount IMPORTING iv_cent          TYPE i
                     RETURNING VALUE(rv_result) TYPE string,

      date_dots RETURNING VALUE(rv_result) TYPE string,

      date_spaces RETURNING VALUE(rv_result) TYPE string,

      build_auszug IMPORTING it_items         TYPE ty_t_item
                              iv_seq           TYPE string
                    RETURNING VALUE(rv_line)   TYPE string,

      build_umsatz IMPORTING it_items         TYPE ty_t_item
                              iv_seq           TYPE string
                    RETURNING VALUE(rt_lines)  TYPE string_table,

      submit_rfkkka00 IMPORTING iv_auszug_path TYPE eseftappl
                                 iv_umsatz_path TYPE eseftappl
                       EXPORTING ev_ok          TYPE flag
                       CHANGING  cs_file_log    TYPE zfi_t_file_log,

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

    IF gv_upload = abap_true.
      execute_upload( ).
    ELSE.
      execute_server( ).
    ENDIF.

    show_log_msg( ).

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

    " Prueba rapida sin AL11: sube un _DEV local y genera/somete el lote,
    " pero SIN traza en ZFI_T_FILE_LOG ni movimiento de ficheros (solo
    " para validar la generacion de AUSZUG/UMSATZ + la llamada a RFKKA00).
    get_directories( ).

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

    DATA(lv_auszug) = build_auszug( it_items = lt_items iv_seq = `00001` ).
    DATA(lt_umsatz) = build_umsatz( it_items = lt_items iv_seq = `00001` ).

    DATA(lv_auszug_path) = gv_tmp_path && 'AUSZUG_TEST.txt'.
    DATA(lv_umsatz_path) = gv_tmp_path && 'UMSATZ_TEST.txt'.

    write_server_file( iv_path = lv_auszug_path it_lines = VALUE #( ( lv_auszug ) ) ).
    write_server_file( iv_path = lv_umsatz_path it_lines = lt_umsatz ).

    WRITE: / 'AUSZUG generado:', lv_auszug_path.
    WRITE: / 'UMSATZ generado:', lv_umsatz_path, '(', lines( lt_umsatz ), 'líneas)'.
    WRITE: / 'Revisa los ficheros en el servidor antes de someter RFKKA00 a mano.'.

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
      ls_file_log-status = c_st_error.
      ls_file_log-fecha_processo = sy-datum.
      ls_file_log-hora_processo  = sy-uzeit.
      ls_file_log-usuario        = sy-uname.
      UPDATE zfi_t_file_log FROM ls_file_log.
      transport_files( is_file_log = ls_file_log iv_path = gv_error_path ).
      WRITE: / 'Sin líneas de extorno reconocibles:', iv_filename.
      RETURN.
    ENDIF.

    ls_file_log-nbr_lines_items = lines( lt_items ).
    ls_file_log-importe = REDUCE zfi_t_file_log-importe(
      INIT s = 0 FOR item IN lt_items NEXT s = s + item-importe_cent / 100 ).

    DATA(lv_seq) = `00001`. " PENDIENTE: numero de secuencia real del extracto, ver docs/DF_resumen.md

    DATA(lv_auszug) = build_auszug( it_items = lt_items iv_seq = lv_seq ).
    DATA(lt_umsatz) = build_umsatz( it_items = lt_items iv_seq = lv_seq ).

    " co_bank_code(4): mientras co_bank_code este vacio (pendiente de
    " confirmar, ver constante) esto no debe reventar por acceso fuera de
    " rango, solo dejar el trozo del nombre en blanco
    DATA(lv_bank_tag) = COND string( WHEN strlen( co_bank_code ) >= 4 THEN co_bank_code(4) ELSE co_bank_code ).
    DATA(lv_suffix) = |{ lv_bank_tag }_{ ls_file_log-file_id+1(6) }_{ sy-datum }|.
    DATA(lv_auszug_name) = |AUSZUG_{ co_dev }_{ lv_suffix }.txt|.
    DATA(lv_umsatz_name) = |UMSATZ_{ co_dev }_{ lv_suffix }.txt|.

    DATA(lv_auszug_path) = gv_tmp_path && lv_auszug_name.
    DATA(lv_umsatz_path) = gv_tmp_path && lv_umsatz_name.

    write_server_file( iv_path = lv_auszug_path it_lines = VALUE #( ( lv_auszug ) ) ).
    write_server_file( iv_path = lv_umsatz_path it_lines = lt_umsatz ).

    ls_file_log-file_name_header = lv_auszug_name.
    ls_file_log-file_name_items  = lv_umsatz_name.

    submit_rfkkka00( EXPORTING iv_auszug_path = CONV #( lv_auszug_path )
                                iv_umsatz_path = CONV #( lv_umsatz_path )
                      IMPORTING ev_ok          = DATA(lv_ok)
                      CHANGING  cs_file_log    = ls_file_log ).

    ls_file_log-fecha_processo = sy-datum.
    ls_file_log-hora_processo  = sy-uzeit.
    ls_file_log-usuario        = sy-uname.

    IF lv_ok = abap_true.
      ls_file_log-status = c_st_procesado.
      UPDATE zfi_t_file_log FROM ls_file_log.
      transport_files( is_file_log = ls_file_log iv_path = gv_backup_path ).
    ELSE.
      ls_file_log-status = c_st_error.
      UPDATE zfi_t_file_log FROM ls_file_log.
      transport_files( is_file_log = ls_file_log iv_path = gv_error_path ).
    ENDIF.

  ENDMETHOD.

  METHOD get_directories.

    DATA: lv_raw_dir TYPE rsfillst-dirname.

    TRY.
        zxx_cl_file_utils=>get_directory(
          EXPORTING i_logical_path = co_logical_path
          IMPORTING e_directory    = lv_raw_dir ).
      CATCH zfi_cl_cx_file.
        RETURN.
    ENDTRY.

    CONCATENATE lv_raw_dir '' INTO gv_root_path.
    REPLACE ALL OCCURRENCES OF '*' IN gv_root_path WITH ''.

    CONCATENATE gv_root_path co_tmp_dir       INTO gv_tmp_path.
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

  METHOD write_server_file.

    OPEN DATASET iv_path FOR OUTPUT IN TEXT MODE ENCODING DEFAULT.
    IF sy-subrc <> 0.
      MESSAGE |No se ha podido escribir { iv_path } en el servidor.| TYPE 'I'.
      RETURN.
    ENDIF.

    LOOP AT it_lines INTO DATA(lv_line).
      TRANSFER lv_line TO iv_path.
    ENDLOOP.

    CLOSE DATASET iv_path.

  ENDMETHOD.

  METHOD parse_dev_lines.

    LOOP AT it_lines INTO DATA(lv_line).

      " Primera linea = cabecera del fichero ECOFI, no es un extorno
      IF sy-tabix = 1.
        CONTINUE.
      ENDIF.

      FIND FIRST OCCURRENCE OF co_eur_tag IN lv_line MATCH OFFSET DATA(lv_eur_off).
      CHECK sy-subrc = 0.

      " Importe: bloque de digitos justo antes de "EUR" (en centimos)
      DATA(lv_before_eur) = substring( val = lv_line len = lv_eur_off ).
      FIND PCRE '(\d+)\s*$' IN lv_before_eur SUBMATCHES DATA(lv_digits).
      CHECK sy-subrc = 0.

      " Nº de documento SAP: 12 digitos justo despues de "EUR  " (ver
      " ZFI_R_ECOFI_SPLIT_CLS, metodo SPLIT_LINES, que es quien los escribe)
      DATA(lv_docnum) = substring( val = lv_line off = lv_eur_off + 3 + 2 len = 12 ).
      CHECK lv_docnum CO '0123456789'.

      APPEND VALUE #( docnum       = lv_docnum
                       importe_cent = lv_digits ) TO rt_items.

    ENDLOOP.

  ENDMETHOD.

  METHOD format_amount.

    DATA(lv_abs) = abs( iv_cent ).
    rv_result = |{ lv_abs / 100 DECIMALS = 2 }-|.
    CONDENSE rv_result.

  ENDMETHOD.

  METHOD date_dots.
    rv_result = |{ sy-datum+6(2) }.{ sy-datum+4(2) }.{ sy-datum+2(2) }|.
  ENDMETHOD.

  METHOD date_spaces.
    rv_result = |{ sy-datum+6(2) } { sy-datum+4(2) } { sy-datum+2(2) }|.
  ENDMETHOD.

  METHOD build_auszug.

    DATA(lv_total_cent) = REDUCE i( INIT s = 0 FOR item IN it_items NEXT s = s + item-importe_cent ).
    DATA(lv_total) = format_amount( lv_total_cent ).

    DATA(lt_fields) = VALUE string_table(
      ( co_bank_code )    "1  entidad+oficina
      ( co_bank_account ) "2  cuenta
      ( iv_seq )           "3  nº secuencia extracto
      ( date_dots( ) )      "4  fecha
      ( `EUR` )             "5  moneda
      ( `0.00` )            "6  saldo inicial
      ( lv_total )          "7  movimiento total
      ( `0.00` )            "8  (sin identificar, 0.00 en los ejemplos reales)
      ( lv_total )          "9  saldo final
      ( ` ` ) ( ` ` ) ( ` ` ) ( ` ` ) ( ` ` ) ( ` ` ) ( ` ` ) ( ` ` )  "10-17 reservados
      ( `` )                "18 (vacio final, replica el ';' de cierre)
    ).

    rv_line = concat_lines_of( table = lt_fields sep = ';' ).

  ENDMETHOD.

  METHOD build_umsatz.

    LOOP AT it_items INTO DATA(ls_item).

      DATA(lv_amount) = format_amount( ls_item-importe_cent ).

      DATA(lt_fields) = VALUE string_table(
        ( co_bank_code )    "1  entidad+oficina
        ( co_bank_account ) "2  cuenta
        ( iv_seq )           "3  nº secuencia extracto
        ( date_spaces( ) )    "4  fecha original - PENDIENTE: usamos hoy, no la fecha real del extorno (ver DF_resumen.md)
        ( ` ` )               "5  reservado
        ( ls_item-docnum )    "6  referencia = nº documento SAP a compensar
        ( ` ` )               "7  motivo devolucion (formato largo) - PENDIENTE, no disponible en el _DEV
        ( ` ` ) ( ` ` ) ( ` ` ) "8-10 reservados
        ( lv_amount )          "11 importe
        ( ` ` )                "12 categoria - PENDIENTE, no disponible en el _DEV
        ( `0` )                "13 constante en los ejemplos reales
        ( date_spaces( ) )     "14 fecha (coincide con la del AUSZUG)
        ( ` ` ) ( ` ` ) ( ` ` ) ( ` ` ) ( ` ` ) ( ` ` ) ( ` ` )
        ( ` ` ) ( ` ` ) ( ` ` ) ( ` ` ) ( ` ` ) ( ` ` ) ( ` ` )
        ( ` ` ) ( ` ` ) ( ` ` )  "15-31 reservados (17 campos)
        ( ` ` )                  "32 BIC deudor - PENDIENTE, no disponible en el _DEV
        ( ` ` )                  "33 IBAN deudor - PENDIENTE, no disponible en el _DEV
        ( co_motivo )            "34 motivo devolucion (formato corto) - se usa el motivo fijo del DF ('Z01')
        ( ` ` ) ( ` ` ) ( ` ` )  "35-37 reservados
        ( `` )                   "38 (vacio final)
      ).

      APPEND concat_lines_of( table = lt_fields sep = ';' ) TO rt_lines.

    ENDLOOP.

  ENDMETHOD.

  METHOD submit_rfkkka00.

    CLEAR ev_ok.

    DATA: lv_runid    TYPE runidbs_kk,
          lv_rundat    TYPE fkkbstmv-laufd,
          lv_progname  TYPE char20,
          lv_data_export TYPE REF TO data,
          lv_jobname   TYPE tbtco-jobname,
          lv_status    TYPE tbtco-status.

    " PENDIENTE: el DF pide nomenclatura AAMMDDCDI11xx, pero RUNIDBS_KK
    " (igual que en ZFI_R_DEVOLUCIONES/2) parece admitir solo 6
    " caracteres - hay que confirmar en SE11 y, si hace falta, ajustar
    " esto. De momento se reutiliza el patron del programa original
    " (file_id de ZFI_T_FILE_LOG).
    lv_runid  = cs_file_log-file_id+1(6).
    lv_rundat = sy-datum.

    lv_progname = sy-repid.
    CREATE DATA lv_data_export LIKE lv_progname.
    ASSIGN lv_data_export->* TO FIELD-SYMBOL(<fs_any>).
    <fs_any> = lv_progname.

    TRY.
        zxx_cl_generic_on_memory=>export_ref_to_memory( i_key  = co_key
                                                          i_data = lv_data_export ).
      CATCH zxx_cl_cx_generic_on_memory.
    ENDTRY.

    " Solo creacion del lote (p_xcre) - cerrar/contabilizar es RU_03 /
    " ZFI_R_DEVOLUCIONES2, no este programa.
    SUBMIT rfkkka00
      WITH p_rundat = lv_rundat
      WITH p_runid  = lv_runid
      WITH p_xrunn  = 'X'
      WITH p_auszf  = iv_auszug_path
      WITH p_umsf   = iv_umsatz_path
      WITH p_xnospl = 'X'
      WITH p_uc     = 'X'
      WITH p_xcre   = 'X'
      WITH p_xsof   = 'X'
      WITH p_tcode  = co_tcode_mc AND RETURN.            "#EC CI_SUBMIT

    TRY.
        DATA(l_import_job) = zxx_cl_generic_on_memory=>import_ref_from_memory( i_key = co_job
                                                                                 i_delete = 'X' ).
      CATCH zxx_cl_cx_generic_on_memory.
    ENDTRY.

    IF l_import_job IS INITIAL.
      go_msg_logs->append_messages(
        iv_msg_type   = 'E'
        iv_msg_class  = 'ZFI_MC_001'
        iv_msg_number = '130'
        iv_param_v1   = CONV #( cs_file_log-file_id )
        iv_param_v2   = CONV #( cs_file_log-file_name ) ).
      RETURN.
    ENDIF.

    ASSIGN l_import_job->* TO FIELD-SYMBOL(<fs_any_import>).
    lv_jobname = <fs_any_import>.

    DO.
      SELECT SINGLE status FROM tbtco INTO lv_status WHERE jobname EQ lv_jobname.
      IF sy-subrc <> 0 OR lv_status = 'A'.
        go_msg_logs->append_messages(
          iv_msg_type   = 'E'
          iv_msg_class  = 'ZFI_MC_001'
          iv_msg_number = '130'
          iv_param_v1   = CONV #( cs_file_log-file_id )
          iv_param_v2   = CONV #( cs_file_log-file_name ) ).
        EXIT.
      ELSEIF lv_status = 'R' OR lv_status = 'Y' OR lv_status = 'S'.
        WAIT UP TO 1 SECONDS.
        CONTINUE.
      ELSE.
        SELECT SINGLE rlerr FROM fkkbstmv INTO @DATA(lv_rlerr)
          WHERE laufd = @lv_rundat AND laufi = @lv_runid.
        IF sy-subrc = 0 AND lv_rlerr = 0.
          ev_ok = abap_true.
          go_msg_logs->append_messages(
            iv_msg_type   = 'S'
            iv_msg_class  = 'ZFI_MC_001'
            iv_msg_number = '016'
            iv_param_v1   = CONV #( cs_file_log-file_name(50) )
            iv_param_v2   = CONV #( cs_file_log-file_name+50(50) ) ).
        ELSE.
          go_msg_logs->append_messages(
            iv_msg_type   = 'E'
            iv_msg_class  = 'ZFI_MC_001'
            iv_msg_number = '131'
            iv_param_v1   = CONV #( lv_runid ) ).
        ENDIF.
        EXIT.
      ENDIF.
    ENDDO.

  ENDMETHOD.

  METHOD transport_files.

    TRY.
        zxx_cl_file_utils=>move_server_file(
          EXPORTING
            i_sourcepath = CONV #( gv_root_path )
            i_targetpath = iv_path
            i_filename   = CONV #( is_file_log-file_name ) ).

        IF is_file_log-file_name_header IS NOT INITIAL AND is_file_log-file_name_items IS NOT INITIAL.
          zxx_cl_file_utils=>move_server_file(
            EXPORTING
              i_sourcepath = gv_tmp_path
              i_targetpath = iv_path
              i_filename   = CONV #( is_file_log-file_name_header ) ).

          zxx_cl_file_utils=>move_server_file(
            EXPORTING
              i_sourcepath = gv_tmp_path
              i_targetpath = iv_path
              i_filename   = CONV #( is_file_log-file_name_items ) ).
        ENDIF.

      CATCH zfi_cl_cx_file.
        go_msg_logs->append_messages(
          iv_msg_type   = 'E'
          iv_msg_class  = 'ZFI_MC_001'
          iv_msg_number = '014'
          iv_param_v1   = condense( CONV symsgv( is_file_log-file_name(50) ) )
          iv_param_v2   = condense( CONV symsgv( is_file_log-file_name+50(50) ) ) ).
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
