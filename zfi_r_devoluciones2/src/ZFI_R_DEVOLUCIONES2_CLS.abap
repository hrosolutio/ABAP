*&---------------------------------------------------------------------*
*& Include          ZFI_R_DEVOLUCIONES2_CLS
*&---------------------------------------------------------------------*
CLASS lcl_devoluciones2 DEFINITION.
  PUBLIC SECTION.

    CONSTANTS: co_logical_path   TYPE pathintern          VALUE 'ZFICA_COBROS_DEVOLUCIONES',
               co_tcode_mc       TYPE syst_tcode          VALUE 'FPB17',
               co_dev            TYPE string              VALUE 'DEV',
               co_for            TYPE string              VALUE 'Z_CGI_FICA_XML_DD',
               co_tmp            TYPE string              VALUE 'tmp/',
               co_backup         TYPE string              VALUE 'backup/',
               co_error          TYPE string              VALUE 'error/',
               co_application_id TYPE zfi_de_application_id VALUE 'GENERAL',
               co_process_id     TYPE zfi_de_process_id     VALUE 'GENERAL',
               co_constant_id    TYPE zfi_de_constant_id    VALUE 'SOCIEDAD',
               co_key            TYPE string              VALUE 'Z_ID',
               co_job            TYPE string              VALUE 'Z_JOB',
               c_st_procesado    TYPE string              VALUE 'PROCESADO',
               c_st_pendiente    TYPE string              VALUE 'PENDIENTE',
               c_st_error        TYPE string              VALUE 'ERROR',
               c_st_duplicado    TYPE string              VALUE 'DUPLICADO',
               c_process         TYPE string              VALUE 'DEV'.

    TYPES: ty_r_file_id   TYPE RANGE OF zfi_t_file_log-file_id.

    DATA: gv_path        TYPE string, "localfile,
          gv_crear       TYPE c,
          gv_contab      TYPE c,
          gv_cerrar      TYPE c,
          gr_file_id     TYPE RANGE OF zfi_t_file_log-file_id,
          gv_upload      TYPE c,
          gv_tmp_path    TYPE eseftappl,
          gv_backup_path TYPE eseftappl,
          gv_error_path  TYPE eseftappl,
          go_file_log    TYPE REF TO zfi_cl_update_file_log,
          go_msg_logs    TYPE REF TO zxx_cl_msg_logs.

    METHODS:
      constructor IMPORTING iv_path    TYPE string
                            ir_file_id TYPE ty_r_file_id
                            iv_upload  TYPE c,

      execute     RAISING zfi_cl_cx_load_file zfi_cl_cx_file.

    CLASS-METHODS: f4_file RETURNING VALUE(rv_path) TYPE string.

  PRIVATE SECTION.

    METHODS:
      convert_multicash EXPORTING ev_auszug_path TYPE eseftappl
                                  ev_umsatz_path TYPE eseftappl
                                  ev_error       TYPE flag
                        CHANGING  is_file_log    TYPE zfi_t_file_log
                        RAISING   zfi_cl_cx_load_file zfi_cl_cx_file,

      transport_files   IMPORTING is_file_log TYPE zfi_t_file_log
                                  iv_path     TYPE eseftappl
                        RAISING   zfi_cl_cx_file,

      get_importe       IMPORTING iv_file_name TYPE eps2filnam
                        EXPORTING ev_importe   TYPE zfi_t_file_log-importe
                                  ev_nbr_lines TYPE zfi_t_file_log-nbr_lines_items
                                  ev_bank_name TYPE saepfad
                                  ev_sociedad  TYPE bukrs,

      get_upload_data   IMPORTING iv_path TYPE string "localfile,
                        EXPORTING ev_exit TYPE flag
                        RAISING   zfi_cl_cx_file,

      check_file_format IMPORTING iv_path          TYPE string
                        RETURNING VALUE(gv_format) TYPE  flag,

      check_file_processed  IMPORTING iv_path             TYPE string
                            RETURNING VALUE(gv_processed) TYPE  flag,

      submit_rfkkka00   IMPORTING iv_auszug_path TYPE eseftappl
                                  iv_umsatz_path TYPE eseftappl
                        EXPORTING ev_laufd       TYPE fkkbstmv-laufd
                        CHANGING  is_file_log    TYPE zfi_t_file_log
                        RAISING   zfi_cl_cx_load_file zfi_cl_cx_file,

      get_directories,

      show_log_msg.

ENDCLASS.

CLASS lcl_devoluciones2 IMPLEMENTATION.

  METHOD constructor.

    gv_upload     = iv_upload.
    gv_path       = iv_path.
    gr_file_id    = ir_file_id.

  ENDMETHOD.

  METHOD execute.

    DATA: lv_path        TYPE eseftappl,
          lv_source_path TYPE rsfillst-dirname,
          lt_path        TYPE TABLE OF string,
          lv_path_aux    TYPE string,
          lv_jobname     TYPE tbtco-jobname,
          lv_status      TYPE tbtco-status.

    go_msg_logs = NEW zxx_cl_msg_logs( ).
    go_file_log = NEW zfi_cl_update_file_log( iv_process = co_dev ).
    get_directories( ).

    IF gv_upload = abap_true.
* Get file from local upload
      TRY.
          lv_path_aux = gv_path.
          SPLIT lv_path_aux AT '\' INTO TABLE lt_path.
          DATA(lv_last_dir) = lt_path[ lines( lt_path ) ].
          DATA(lv_processed) = check_file_processed( iv_path = lv_last_dir ).
          DATA(lv_format) = check_file_format( iv_path = lv_last_dir ).

          IF lv_format = abap_true.
            MESSAGE e018(zfi_mc_001).  "Fichero &1 tiene un formato incorrecto.
            EXIT.
          ENDIF.

          IF lv_processed = abap_true.
            MESSAGE e071(zfi_mc_001).  "El fichero ya ha sido procesado.
            EXIT.
          ENDIF.

          get_upload_data( EXPORTING iv_path = lv_path_aux
                           IMPORTING ev_exit = DATA(lv_exit) ).

          IF lv_exit = 'X'.
            EXIT.
          ENDIF.

        CATCH zfi_cl_cx_file.
          EXIT.
      ENDTRY.
    ELSE.
* Get files from zfi_t_file_log from the range id (input)
      go_file_log->get_logs( ir_file_id = gr_file_id ).
    ENDIF.

    SORT go_file_log->gt_logs BY file_name.

    IF go_file_log->gt_logs IS NOT INITIAL.

      LOOP AT go_file_log->gt_logs ASSIGNING FIELD-SYMBOL(<fs_file_log>).
        CLEAR: lv_path_aux, lv_last_dir, lv_processed, lv_format, lv_status.

*Si el fichero se ha procesado, continuamos con el siguiente
        IF <fs_file_log>-status = c_st_procesado.
          CONTINUE.
        ENDIF.

*Si no es carga local validamos duplicidad y formato
        IF gv_upload IS INITIAL.
          CONCATENATE gv_path <fs_file_log>-file_name INTO lv_path_aux.
          SPLIT lv_path_aux AT '/' INTO TABLE lt_path.
          lv_last_dir = lt_path[ lines( lt_path ) ].
          lv_processed = check_file_processed( iv_path = lv_last_dir ).
          lv_format = check_file_format( iv_path = lv_last_dir ).
        ENDIF.

*Si es un fichero duplicado, status = DUPLICADO continuamos con el resto
        READ TABLE go_file_log->gt_logs INTO DATA(ls_logs_aux) WITH KEY file_name =  <fs_file_log>-file_name
                                                                           status = c_st_procesado.

        IF sy-subrc = 0 OR lv_processed = abap_true.
          <fs_file_log>-status = c_st_duplicado.
          <fs_file_log>-fecha_processo = sy-datum.
          <fs_file_log>-hora_processo = sy-uzeit.
          <fs_file_log>-usuario = sy-uname.

          transport_files( EXPORTING is_file_log = <fs_file_log>
                                     iv_path     = gv_error_path ).

          UPDATE zfi_t_file_log FROM <fs_file_log>.
          show_log_msg( ).
          CONTINUE.
        ENDIF.

*Si el fichero tiene formato incorrecto, status = ERROR y continuamos con el resto
        IF lv_format = abap_true.
          <fs_file_log>-status = c_st_error.
          <fs_file_log>-fecha_processo = sy-datum.
          <fs_file_log>-hora_processo = sy-uzeit.
          <fs_file_log>-usuario = sy-uname.

          transport_files( EXPORTING is_file_log = <fs_file_log>
                                     iv_path     = gv_error_path ).

          UPDATE zfi_t_file_log FROM <fs_file_log>.
          show_log_msg( ).
          CONTINUE.
        ENDIF.

        convert_multicash( IMPORTING ev_auszug_path = DATA(lv_auszug_path)
                                     ev_umsatz_path = DATA(lv_umsatz_path)
                                     ev_error       = DATA(lv_error)
                           CHANGING  is_file_log    = <fs_file_log> ).

* Si hay error actualizamos status y movemos fichero.
        IF lv_error = abap_true.

          <fs_file_log>-status = c_st_error.
          <fs_file_log>-fecha_processo  = sy-datum.
          <fs_file_log>-hora_processo   = sy-uzeit.
          <fs_file_log>-usuario         = sy-uname.
          lv_path = gv_error_path.

          transport_files( EXPORTING is_file_log = <fs_file_log>
                                     iv_path     = gv_error_path ).

          UPDATE zfi_t_file_log FROM <fs_file_log>.
          show_log_msg( ).
          CLEAR lv_error.
          CONTINUE.
        ENDIF.

        IF sy-subrc = 0 AND lv_auszug_path IS NOT INITIAL
                        AND lv_umsatz_path IS NOT INITIAL.

          submit_rfkkka00( EXPORTING iv_auszug_path = lv_auszug_path
                                     iv_umsatz_path = lv_umsatz_path
                           IMPORTING ev_laufd       = DATA(lv_laufd)
                           CHANGING  is_file_log    = <fs_file_log> ).

* Verificamos si el proceso de creaci�n de lote de devoluciones ha finalizado (RFKKKA01).
          TRY.
              DATA(l_import_job) = zxx_cl_generic_on_memory=>import_ref_from_memory( i_key = co_job
                                                                                     i_delete = 'X').
            CATCH zxx_cl_cx_generic_on_memory.
          ENDTRY.

          IF l_import_job IS NOT INITIAL.
            ASSIGN l_import_job->* TO FIELD-SYMBOL(<fs_any_import>).

            lv_jobname = <fs_any_import>.
* Comprobar jobs activos
            DO.
              SELECT SINGLE status
                     FROM tbtco
                     INTO lv_status
                     WHERE jobname EQ lv_jobname.
              IF sy-subrc <> 0 OR lv_status = 'A'.
* Error - Job RFKKKA01 para crear lote devoluciones no ha sido lanzado o se ha cancelado
                <fs_file_log>-status = c_st_error.
                <fs_file_log>-fecha_processo  = sy-datum.
                <fs_file_log>-hora_processo   = sy-uzeit.
                <fs_file_log>-usuario         = sy-uname.
                lv_path = gv_error_path.

                transport_files( EXPORTING is_file_log = <fs_file_log>
                                           iv_path     = gv_error_path ).

                go_msg_logs->append_messages(
                  EXPORTING
                   iv_msg_type   = 'E'
                   iv_msg_class  = 'ZFI_MC_001'
                   iv_msg_number = '130'
                   iv_param_v1   = CONV #( <fs_file_log>-file_id )
                   iv_param_v2   = CONV #( <fs_file_log>-file_name ) ).
                EXIT.
              ELSEIF ( lv_status = 'R' OR lv_status = 'Y' OR lv_status = 'S' ).
* Activo - Mientras job activo se queda en espera
                WAIT UP TO 1 SECONDS.
                CONTINUE.
              ELSE.
* Finalizado - Una vez finalizado el job hijo comprobamos su estado
                SELECT SINGLE rlerr FROM fkkbstmv INTO @DATA(lv_rlerr) WHERE  laufd = @lv_laufd
                                                                         AND  laufi = @<fs_file_log>-file_id+1(6).
                IF sy-subrc = 0 AND lv_rlerr = 0.
* El lote de devoluciones se ha creado correctamente
                  <fs_file_log>-status = c_st_procesado .
                  <fs_file_log>-fecha_processo  = sy-datum.
                  <fs_file_log>-hora_processo   = sy-uzeit.
                  <fs_file_log>-usuario         = sy-uname.
                  lv_path = gv_error_path.

                  transport_files( EXPORTING is_file_log = <fs_file_log>
                                             iv_path     = gv_backup_path ).

                  go_msg_logs->append_messages(
                    EXPORTING
                     iv_msg_type   = 'S'
                     iv_msg_class  = 'ZFI_MC_001'
                     iv_msg_number = '016'
                     iv_param_v1   = CONV #( <fs_file_log>-file_name(50) )
                     iv_param_v2   = CONV #( <fs_file_log>-file_name+50(50) ) ).
                ELSE.
                  <fs_file_log>-status = c_st_error.
                  <fs_file_log>-fecha_processo  = sy-datum.
                  <fs_file_log>-hora_processo   = sy-uzeit.
                  <fs_file_log>-usuario         = sy-uname.
                  lv_path = gv_error_path.

                  transport_files( EXPORTING is_file_log = <fs_file_log>
                                             iv_path     = gv_error_path ).

                  go_msg_logs->append_messages(
                    EXPORTING
                     iv_msg_type   = 'E'
                     iv_msg_class  = 'ZFI_MC_001'
                     iv_msg_number = '131'
                     iv_param_v1   = CONV #( <fs_file_log>-file_id+1(6) ) ).
                ENDIF.
                EXIT.
              ENDIF.
            ENDDO.

            UPDATE zfi_t_file_log FROM <fs_file_log>.

            show_log_msg( ).

          ELSE.
            <fs_file_log>-status = c_st_error.
            <fs_file_log>-fecha_processo  = sy-datum.
            <fs_file_log>-hora_processo   = sy-uzeit.
            <fs_file_log>-usuario         = sy-uname.
            lv_path = gv_error_path.

            transport_files( EXPORTING is_file_log = <fs_file_log>
                                       iv_path     = gv_error_path ).

            go_msg_logs->append_messages(
              EXPORTING
               iv_msg_type   = 'E'
               iv_msg_class  = 'ZFI_MC_001'
               iv_msg_number = '130'
               iv_param_v1   = CONV #( <fs_file_log>-file_id )
               iv_param_v2   = CONV #( <fs_file_log>-file_name ) ).

            UPDATE zfi_t_file_log FROM <fs_file_log>.

            show_log_msg( ).

          ENDIF.
        ENDIF.
      ENDLOOP.
    ELSE.
      MESSAGE e002(zfi_mc_001).     "No hay ficheros para procesar.
    ENDIF.

    UPDATE zfi_t_file_log FROM TABLE go_file_log->gt_logs.

    show_log_msg( ).

  ENDMETHOD.

  METHOD convert_multicash.

    DATA: lv_list          TYPE STANDARD TABLE OF abaplist,
          lv_txtlines      TYPE STANDARD TABLE OF string,
          lv_path          TYPE saepfad,
          lv_file_name     TYPE zfi_t_file_log-file_name,
          lv_file_name_len TYPE i,
          lv_file_id       TYPE runidbs_kk,
          lv_sociedad      TYPE bukrs.

* Remove type of file from main file format (xml file type tag)
    lv_file_name_len = strlen( is_file_log-file_name ).
    lv_file_name_len = lv_file_name_len - 4.
    lv_file_name = is_file_log-file_name+0(lv_file_name_len).

* Get the value of importe, nbr lines and bank name
    get_importe( EXPORTING  iv_file_name = CONV #( is_file_log-file_name )
                 IMPORTING  ev_importe   = is_file_log-importe
                            ev_nbr_lines = is_file_log-nbr_lines_items
                            ev_bank_name = DATA(lv_bank_name)
                            ev_sociedad  = lv_sociedad ).

* get errors created
    DATA(lt_file_error) = go_msg_logs->get_messages( ).

    DESCRIBE TABLE lt_file_error LINES DATA(lv_error_lines).

* if there are no previous errors reading the file, do multicash conversion
    IF lv_error_lines = 0.

      lv_file_id = is_file_log-file_id+3(4).

      CONCATENATE gv_tmp_path is_file_log-file_name INTO DATA(lv_fullpath).

      CONCATENATE gv_tmp_path 'AUSZUG_DEV_' lv_bank_name '_' lv_file_id '_'
        sy-datum '.txt' INTO ev_auszug_path.

      CONCATENATE gv_tmp_path 'UMSATZ_DEV_' lv_bank_name '_' lv_file_id '_'
        sy-datum '.txt' INTO ev_umsatz_path.

* Submit to multicash and create header and items files
      SUBMIT rfkksepa_dd_rjct
        WITH par_cc   = lv_sociedad
        WITH par_for  = co_for
        WITH par_apsr = lv_fullpath
        WITH par_ausz = ev_auszug_path
        WITH par_umsz = ev_umsatz_path
      EXPORTING LIST TO MEMORY
      AND RETURN.                                        "#EC CI_SUBMIT

      CALL FUNCTION 'LIST_FROM_MEMORY'
        TABLES
          listobject = lv_list
        EXCEPTIONS
          not_found  = 1
          OTHERS     = 2.

      IF sy-subrc <> 0.
        ev_error = 'X'.

        go_msg_logs->append_messages(
          iv_msg_type   = 'E'
          iv_msg_class  = 'ZFI_MC_001'
          iv_msg_number = '003'
          iv_param_v1   = CONV #( is_file_log-file_name ) ).

        transport_files( EXPORTING is_file_log = is_file_log
                                   iv_path     = gv_error_path ).

        show_log_msg( ).

        is_file_log-status = c_st_error.
        is_file_log-fecha_processo  = sy-datum.
        is_file_log-hora_processo   = sy-uzeit.
        is_file_log-usuario         = sy-uname.

        UPDATE zfi_t_file_log FROM is_file_log.

        RAISE EXCEPTION TYPE zfi_cl_cx_load_file.
      ENDIF.

      CALL FUNCTION 'WRITE_LIST'
        TABLES
          listobject = lv_list
        EXCEPTIONS
          OTHERS     = 0.

      CALL FUNCTION 'LIST_FREE_MEMORY'
        TABLES
          listobject = lv_list
        EXCEPTIONS
          OTHERS     = 1.

      IF sy-subrc <> 0.
        ev_error = 'X'.

        go_msg_logs->append_messages(
          iv_msg_type   = 'E'
          iv_msg_class  = 'ZFI_MC_001'
          iv_msg_number = '003'
          iv_param_v1   = CONV #( is_file_log-file_name ) ).

        transport_files( EXPORTING is_file_log = is_file_log
                                   iv_path     = gv_error_path ).

        show_log_msg( ).

        is_file_log-status = c_st_error.
        is_file_log-fecha_processo  = sy-datum.
        is_file_log-hora_processo   = sy-uzeit.
        is_file_log-usuario         = sy-uname.

        UPDATE zfi_t_file_log FROM is_file_log.

        RAISE EXCEPTION TYPE zfi_cl_cx_load_file.
      ENDIF.

* Update file log, and move file if error occurred
      IF ev_auszug_path IS NOT INITIAL AND ev_umsatz_path IS NOT INITIAL.
        SPLIT ev_auszug_path AT co_tmp INTO DATA(lv_dir) DATA(lv_name) .
        is_file_log-file_name_header = lv_name.

        CLEAR: lv_dir, lv_name.
        SPLIT ev_umsatz_path AT co_tmp INTO lv_dir lv_name .
        is_file_log-file_name_items = lv_name.
      ELSE.
        ev_error = 'X'.

        go_msg_logs->append_messages(
          iv_msg_type   = 'E'
          iv_msg_class  = 'ZFI_MC_001'
          iv_msg_number = '003'
          iv_param_v1   = CONV #( is_file_log-file_name ) ).

*        show_log_msg( ).
      ENDIF.

    ELSE.
* error in file before multicash, process not started
      ev_error = 'X'.

      go_msg_logs->append_messages(
        iv_msg_type   = 'E'
        iv_msg_class  = 'ZFI_MC_001'
        iv_msg_number = '017'
        iv_param_v1   = CONV #( is_file_log-file_name(50) )
        iv_param_v2   = CONV #( is_file_log-file_name+50(50) ) ).

*      show_log_msg( ).
    ENDIF.

*    is_file_log-fecha_processo  = sy-datum.
*    is_file_log-hora_processo   = sy-uzeit.
*    is_file_log-usuario         = sy-uname.
*
*    go_file_log->update_log( CHANGING is_file_log = is_file_log ).

  ENDMETHOD.

  METHOD transport_files.

    TRY.
        CALL METHOD zxx_cl_file_utils=>move_server_file(
          EXPORTING
            i_sourcepath = gv_tmp_path
            i_targetpath = iv_path
            i_filename   = CONV #( is_file_log-file_name ) ).

        IF     is_file_log-file_name_header IS NOT INITIAL
           AND is_file_log-file_name_items  IS NOT INITIAL.
          CALL METHOD zxx_cl_file_utils=>move_server_file(
            EXPORTING
              i_sourcepath = gv_tmp_path
              i_targetpath = iv_path
              i_filename   = CONV #( is_file_log-file_name_header ) ).

          CALL METHOD zxx_cl_file_utils=>move_server_file(
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

  METHOD get_importe.

    TYPES: BEGIN OF ty_xml,
             raw(2000) TYPE c,
           END OF ty_xml.

    DATA: lv_xml_xstring   TYPE xstring,
          g_str            TYPE string,
          lt_result_xml    TYPE TABLE OF smum_xmltb,
          wa_xml_tab       TYPE ty_xml,
          g_t_xml_tab      TYPE TABLE OF ty_xml INITIAL SIZE 0,
          lv_bankname_flag TYPE bool.

    DATA: lv_check_nbr_lines TYPE flag,
          lv_check_importe   TYPE flag.

    DATA: lt_endtoend       TYPE TABLE OF opbel_kk,
          lt_sociedad       TYPE TABLE OF bukrs,
          lt_motivo_externo TYPE TABLE OF rlhbk_kk,
          lv_acreedor       TYPE char16.

    CONCATENATE gv_tmp_path iv_file_name INTO DATA(lv_filename).

    "reading file
    OPEN DATASET lv_filename FOR INPUT IN BINARY MODE.
    IF sy-subrc NE 0. "file does not exist or error reading it
      go_msg_logs->append_messages( iv_msg_type   = 'E'
                                    iv_msg_class  = 'ZFI_MC_001'
                                    iv_msg_number = '020'
                                    iv_param_v1   = CONV #( lv_filename ) ).
      EXIT.
    ENDIF.
    READ DATASET lv_filename INTO lv_xml_xstring . "wa_xml_tab.
    CLOSE DATASET lv_filename .

    DATA lt_return TYPE TABLE OF bapiret2.

* Convert xstring data of xml file to internal table
    CALL FUNCTION 'SMUM_XML_PARSE'
      EXPORTING
        xml_input = lv_xml_xstring
      TABLES
        xml_table = lt_result_xml
        return    = lt_return.


    DATA(lv_next) = abap_false.
    DATA(lv_next_id_acreedor) = abap_false.
* get the values from the xml file
    LOOP AT lt_result_xml INTO DATA(ls_xml).
      CASE ls_xml-cname.
        WHEN 'OrgnlCtrlSum'.
          ev_importe = COND #( WHEN lv_check_importe EQ abap_false THEN ls_xml-cvalue
                               WHEN lv_check_importe EQ abap_true  THEN ev_importe ).
          lv_check_importe = abap_true.
        WHEN 'OrgnlNbOfTxs'.
          ev_nbr_lines = COND #( WHEN lv_check_nbr_lines EQ abap_false THEN ls_xml-cvalue
                                 WHEN lv_check_nbr_lines EQ abap_true  THEN ev_nbr_lines ).
          lv_check_nbr_lines = abap_true.
        WHEN 'BIC'.
          DATA(lv_swift) = ls_xml-cvalue.
        WHEN 'IBAN'.
          DATA(lv_iban) = ls_xml-cvalue.
        WHEN 'CdtrSchmeId'.
          " Para acreedor
          lv_next_id_acreedor = abap_true.
        WHEN 'Id'.
          IF lv_next_id_acreedor = abap_true AND ls_xml-type = 'V'.
            lv_acreedor = ls_xml-cvalue.
            lv_next_id_acreedor = abap_false.
          ENDIF.
        WHEN 'Rsn'.
          lv_next = abap_true.
        WHEN 'Cd'.
          IF lv_next = abap_true.
            APPEND ls_xml-cvalue TO lt_motivo_externo.
            lv_next = abap_false.
          ENDIF.
        WHEN OTHERS.
      ENDCASE.
    ENDLOOP.

    CONCATENATE 'ES' lv_acreedor+7 INTO DATA(lv_sociedad).

    SELECT SINGLE bukrs INTO ev_sociedad FROM t001 WHERE stceg = lv_sociedad.

    CHECK ev_sociedad IS NOT INITIAL.

    " update creation options with information from the table ZFI_T_COBRO_CONF
    SELECT bankl, bankn FROM tiban INTO @DATA(ls_tiban)
      WHERE iban = @lv_iban
      ORDER BY valid_from DESCENDING.
    ENDSELECT.
    IF sy-subrc <> 0.
      go_msg_logs->append_messages( iv_msg_type   = 'E'
                                    iv_msg_class  = 'ZFI_MC_001'
                                    iv_msg_number = '093'
                                    iv_param_v1   = CONV #( ls_tiban )
                                    ).
      EXIT.
    ENDIF.

    SELECT SINGLE hbkid FROM t012 INTO @DATA(lv_hbkid)
      WHERE bukrs = @ev_sociedad
      AND bankl = @ls_tiban-bankl.
    IF sy-subrc <> 0.
      go_msg_logs->append_messages( iv_msg_type   = 'E'
                                    iv_msg_class  = 'ZFI_MC_001'
                                    iv_msg_number = '092'
                                    iv_param_v1   = CONV #( ls_tiban-bankl )
                                    iv_param_v2   = CONV #( ev_sociedad )
                                    ).
      EXIT.
    ENDIF.

    ev_bank_name = lv_hbkid(4).

**      SELECT SINGLE rlgrd INTO @DATA(lv_motivo_interno)
**        FROM tfk045d
**        WHERE bukrs = @ev_sociedad
**        AND hbkid   = @lv_hbkid
**        AND rlhbk   = @lv_motivo_externo.
*
*    if sy-subrc = 0.
*    " check motivo devolucion
**      loop at lt_tfk045d into data(ls_tfk045d).
*        loop at lt_motivo_externo into data(ls_motivo_externo).
*          READ TABLE lt_tfk045d into data(lt_s) WITH KEY RLHBK = ls_motivo_externo.
*          if sy-subrc <> 0.
*            data(lv_motivo_externo) = ls_motivo_externo.
*          endif.
*        endloop.
*    ENDIF.
*    IF sy-subrc <> 0 or lv_motivo_externo is not INITIAL.
*     go_msg_logs->append_messages( iv_msg_type   = 'E'
*                                   iv_msg_class  = 'ZFI_MC_001'
*                                   iv_msg_number = '091'
*                                   iv_param_v1   = CONV #( lv_motivo_externo )
*                                   iv_param_v2   = CONV #( lv_hbkid )
*                                   iv_param_v3   = CONV #( ev_sociedad )
*                                   ).
*     EXIT.
*    ENDIF.

    SELECT contabilizar, cerrar INTO (@gv_contab, @gv_cerrar)
      FROM zfi_t_cobro_conf
      WHERE tipo_cobro = @co_dev
      AND opbuk = @ev_sociedad
      AND entid = @lv_hbkid
      AND id_cuenta IN ( SELECT hktid FROM t012k
                         WHERE bankn = @ls_tiban-bankn
                         AND hbkid = @lv_hbkid )       "#EC CI_BUFFSUBQ
      AND clave_banco = @ls_tiban-bankl.
    ENDSELECT.

* if no details are provided in ZFI_T_COBRO_CONF, pass create only.
    IF gv_contab IS INITIAL AND gv_cerrar IS INITIAL.
      gv_crear = abap_true.
    ELSEIF gv_contab IS NOT INITIAL AND gv_cerrar IS NOT INITIAL.
      gv_cerrar = abap_false.
    ENDIF.
  ENDMETHOD.

  METHOD submit_rfkkka00.

    DATA: lv_path  TYPE saepfad,
          lv_runid TYPE runidbs_kk.

    lv_runid = is_file_log-file_id+1(6).
    ev_laufd = sy-datum.

    DATA: lv_progname    TYPE char20,
          lv_data_export TYPE REF TO data.

* get current program name
    lv_progname = sy-repid.

    CREATE DATA lv_data_export LIKE lv_progname.
    ASSIGN lv_data_export->* TO FIELD-SYMBOL(<fs_any>).
    <fs_any> = lv_progname.

    TRY.
* export program name to memory
        zxx_cl_generic_on_memory=>export_ref_to_memory( i_key  = co_key
                                                        i_data = lv_data_export ) .
      CATCH zxx_cl_cx_generic_on_memory.
    ENDTRY.
* only pass 1 of these params, otherwise we get a dump.
* gv_contab does both things so only pass that one if it is selected.
    IF gv_contab EQ abap_true.
      CLEAR gv_cerrar.
    ENDIF.

    SUBMIT rfkkka00
      WITH p_rundat = ev_laufd
      WITH p_runid  = lv_runid
      WITH p_xrunn  = 'X'
      WITH p_auszf  = iv_auszug_path
      WITH p_umsf   = iv_umsatz_path
      WITH p_xnospl = 'X'
      WITH p_uc     = 'X'
      WITH p_xcre   = gv_crear
      WITH p_xcls   = gv_cerrar
      WITH p_xbu    = gv_contab
      WITH p_xsof   = 'X'
      WITH p_tcode  = co_tcode_mc AND RETURN.            "#EC CI_SUBMIT

  ENDMETHOD.

  METHOD get_upload_data.

    DATA: lt_file      TYPE STANDARD TABLE OF string,
          lv_arquivo   TYPE string,
          lv_file_name TYPE string,
          lv_filename  TYPE zfi_t_file_log-file_name,
          lt_path      TYPE TABLE OF string,
          lo_obj       TYPE REF TO zxx_cl_file_server,
          lv_path      TYPE string.

    SPLIT iv_path AT '\' INTO TABLE lt_path.
    lv_filename = lt_path[ lines( lt_path ) ].
    lv_file_name = lt_path[ lines( lt_path ) ].

    CONCATENATE gv_tmp_path lv_filename INTO DATA(lv_server_file).

    MOVE gv_tmp_path TO lv_path.

    cl_gui_frontend_services=>gui_upload(
      EXPORTING filename            = iv_path
*                filetype            = 'BIN'
*                has_field_separator = 'X'
      CHANGING  data_tab            = lt_file
      EXCEPTIONS OTHERS             = 1 ) .

    IF sy-subrc <> 0.
      ev_exit = 'X'.
      EXIT.
    ENDIF.

    CREATE OBJECT lo_obj TYPE zxx_cl_file_server.

    TRY.
        lo_obj ?= zxx_cl_file=>get_instance(
        EXPORTING
          i_path     = lv_path
          i_filename = lv_file_name
        ).

        lo_obj->write_data(
          EXPORTING
            it_data    =   lt_file              " Table of STRINGs
        ).

        lo_obj->remove_special_characters( ).
      CATCH zfi_cl_cx_file. " Clase de excepci�n para archivos
    ENDTRY.

    IF sy-subrc = 0.

      TRY.
          go_file_log->create_log( EXPORTING iv_filename = lv_filename
                                   IMPORTING es_file_log = DATA(ls_file_log) ).

        CATCH zfi_cl_cx.
      ENDTRY.
    ELSE.
      go_msg_logs->append_messages(
        iv_msg_type   = 'E'
        iv_msg_class  = 'ZFI_MC_001'
        iv_msg_number = '014'
        iv_param_v1   = condense( CONV symsgv( lv_server_file ) ) ).
    ENDIF.

  ENDMETHOD.

  METHOD check_file_format.

    SPLIT iv_path AT '.' INTO TABLE DATA(lt_name).

    DESCRIBE TABLE lt_name LINES DATA(lv_lines).
    IF lt_name[ lv_lines ] <> 'xml'.

      go_msg_logs->append_messages( EXPORTING iv_msg_type   = 'E'
                                             iv_msg_class  = 'ZFI_MC_001'
                                             iv_msg_number = '018'
                                             iv_param_v1   = condense( CONV symsgv( iv_path ) ) ).

      gv_format = abap_true.
    ENDIF.
  ENDMETHOD.

  METHOD check_file_processed.
    SELECT SINGLE *
          FROM zfi_t_file_log
          INTO @DATA(ls_zfi_t_file_log)
          WHERE file_name = @iv_path
          AND status = @c_st_procesado.

    IF sy-subrc = 0.
* El fichero ya ha sido procesado.
      go_msg_logs->append_messages( EXPORTING iv_msg_type   = 'E'
                                              iv_msg_class  = 'ZFI_MC_001'
                                              iv_msg_number = '071'
                                              iv_param_v1   = condense( CONV symsgv( iv_path ) ) ).
      gv_processed = abap_true.
    ENDIF.
  ENDMETHOD.

  METHOD get_directories.

    DATA: lv_source_path TYPE rsfillst-dirname,
          lt_path        TYPE TABLE OF string.

* Carga de fichero local o del servidor
    IF gv_upload IS NOT INITIAL OR
      ( gv_upload IS INITIAL AND gv_path IS INITIAL ).
      TRY.
          zxx_cl_file_utils=>get_directory(
            EXPORTING i_logical_path = co_logical_path
            IMPORTING e_directory    = lv_source_path ) .

          REPLACE ALL OCCURRENCES OF '*' IN lv_source_path WITH ''.

        CATCH zfi_cl_cx_file.
          go_msg_logs->append_messages( iv_msg_type   = 'E'
                                        iv_msg_class  = 'ZFI_MC_001'
                                        iv_msg_number = '013'
                                        iv_param_v1   = CONV #( co_dev ) ).
      ENDTRY.

      CONCATENATE lv_source_path co_backup INTO gv_backup_path.
      CONCATENATE lv_source_path co_tmp INTO gv_tmp_path.
      CONCATENATE lv_source_path co_error INTO gv_error_path.

*Si no es carga local hay que indicar la ruta a utilizar
      IF gv_path IS INITIAL.
        gv_path = gv_tmp_path.
      ENDIF.

    ELSE.
* Ruta del servidor indicada por el programa padre ZFI_R_LOAD_FILE
      gv_tmp_path = gv_path.

      SPLIT gv_tmp_path AT '/' INTO TABLE lt_path.
      DATA(lv_last_dir) = lt_path[ lines( lt_path ) ].

      SPLIT gv_tmp_path AT lv_last_dir INTO lv_source_path DATA(lv_string).

      CONCATENATE lv_source_path co_backup INTO gv_backup_path.
      CONCATENATE lv_source_path co_error  INTO gv_error_path.
    ENDIF.

  ENDMETHOD.

  METHOD f4_file.

    DATA: lt_filetable TYPE filetable,
          l_rcode      TYPE i.

    cl_gui_frontend_services=>file_open_dialog( CHANGING file_table = lt_filetable
                                                         rc         = l_rcode
                                                EXCEPTIONS OTHERS   = 5 ).

    IF sy-subrc = 0.
      "Guardando en el server (carpeta /tmp/)
      rv_path = VALUE #( lt_filetable[ 1 ] OPTIONAL ).
    ELSE.
      MESSAGE ID sy-msgid TYPE sy-msgty NUMBER sy-msgno
         WITH sy-msgv1 sy-msgv2 sy-msgv3 sy-msgv4.
    ENDIF.

  ENDMETHOD.

  METHOD show_log_msg.
    DATA(lt_msg_logs) = go_msg_logs->get_messages( ).

    IF lt_msg_logs IS NOT INITIAL.
      LOOP AT lt_msg_logs ASSIGNING FIELD-SYMBOL(<fs_log>).
        WRITE <fs_log>-message.
      ENDLOOP.
    ENDIF.

    go_msg_logs->clear_messages( ).
  ENDMETHOD.

ENDCLASS.
