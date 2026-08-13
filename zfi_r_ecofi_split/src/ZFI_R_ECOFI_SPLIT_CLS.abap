*&---------------------------------------------------------------------*
*& Include          ZFI_R_ECOFI_SPLIT_CLS
*&---------------------------------------------------------------------*
* Regla de deteccion de extorno (verificada contra 2 ficheros ECOFI
* reales, YFRECAU_1239_260402.140017.txt y YFRECAU_1239_260415.140018.txt,
* 100% de coincidencia con el tag ANUP/TRRD del propio fichero):
*
*   - Cada linea de datos tiene 260 caracteres fijos. La primera linea
*     del fichero (cabecera) tiene 20 caracteres y se escribe tal cual
*     en ambos ficheros de salida.
*   - "EUR" aparece siempre en la misma posicion (columna 102, offset
*     101), seguido de 2 espacios y el concepto (154 caracteres, hasta
*     el final de la linea).
*   - Es extorno si el concepto empieza por 24 digitos. El numero de
*     documento SAP a clarificar son los digitos 13-24 de ese bloque
*     (los ultimos 12), igual que en el ejemplo del DF.
*
* Pendiente de confirmar con EVA (ver README): si la linea de extorno
* en el fichero _DEV debe mantener el ancho fijo de 260 caracteres
* (como hace este programa, rellenando con espacios tras el numero de
* documento) o un formato mas corto como el del ejemplo del DF.
*
* Modo servidor: escanea TODOS los ficheros de la carpeta de la ruta
* logica CO_LOGICAL_PATH (igual patron que ZFI_R_DEVOLUCIONES, que
* resuelve su ruta logica con ZXX_CL_FILE_UTILS=>GET_DIRECTORY), los
* divide uno a uno y mueve el original a la subcarpeta "procesados/"
* (con ZXX_CL_FILE_UTILS=>MOVE_SERVER_FILE, la misma utilidad que usa
* ZFI_R_DEVOLUCIONES para sus subcarpetas backup/error) para no
* reprocesarlo en la siguiente ejecucion. No usa ZFI_T_FILE_LOG: el
* fichero ECOFI es el primer eslabon de la cadena, no esta registrado
* en ningun sitio todavia (a diferencia de ZFI_R_DEVOLUCIONES, que ya
* recibe los ficheros pre-registrados por un paso anterior).
CLASS lcl_ecofi_split DEFINITION.
  PUBLIC SECTION.

    CONSTANTS: co_suffix_trf     TYPE string    VALUE '_TRF',
               co_suffix_dev     TYPE string    VALUE '_DEV',
               co_eur_tag        TYPE string    VALUE 'EUR',
               co_logical_path   TYPE pathintern VALUE 'ZFICA_COBROS_ECOFI',
               co_processed_dir  TYPE string    VALUE 'procesados/'.

    METHODS:
      constructor IMPORTING iv_path   TYPE string
                            iv_upload TYPE c,

      execute.

    CLASS-METHODS:
      split_lines IMPORTING it_lines TYPE string_table
                  EXPORTING et_trf   TYPE string_table
                            et_dev   TYPE string_table,

      get_doc_number IMPORTING iv_line          TYPE string
                      RETURNING VALUE(rv_docnum) TYPE string,

      build_output_filename IMPORTING iv_filename      TYPE string
                                       iv_suffix        TYPE string
                             RETURNING VALUE(rv_result) TYPE string.

  PRIVATE SECTION.

    DATA: gv_path   TYPE string,
          gv_upload TYPE c.

    METHODS:
      execute_local,

      execute_server,

      split_and_write_local IMPORTING it_lines TYPE string_table
                                       iv_name  TYPE string,

      split_and_write_server IMPORTING it_lines TYPE string_table
                                        iv_name  TYPE string
                                        iv_dir   TYPE string,

      get_filename_from_path IMPORTING iv_path            TYPE string
                              RETURNING VALUE(rv_filename) TYPE string,

      get_server_directory RETURNING VALUE(rv_directory) TYPE string,

      get_server_files IMPORTING iv_directory    TYPE string
                        RETURNING VALUE(rt_files) TYPE string_table,

      read_server_file IMPORTING iv_path         TYPE string
                        RETURNING VALUE(rt_lines) TYPE string_table,

      write_server_file IMPORTING iv_path  TYPE string
                                   it_lines TYPE string_table,

      upload_lines RETURNING VALUE(rt_lines) TYPE string_table,

      download_lines IMPORTING iv_filename TYPE string
                                it_lines    TYPE string_table.

ENDCLASS.

CLASS lcl_ecofi_split IMPLEMENTATION.

  METHOD constructor.
    gv_path   = iv_path.
    gv_upload = iv_upload.
  ENDMETHOD.

  METHOD execute.

    IF gv_upload = abap_true.
      execute_local( ).
    ELSE.
      execute_server( ).
    ENDIF.

  ENDMETHOD.

  METHOD execute_local.

    DATA(lt_lines) = upload_lines( ).

    IF lt_lines IS INITIAL.
      MESSAGE 'No se ha podido leer el fichero indicado.' TYPE 'E'.
      RETURN.
    ENDIF.

    split_and_write_local( it_lines = lt_lines
                            iv_name  = get_filename_from_path( gv_path ) ).

  ENDMETHOD.

  METHOD execute_server.

    DATA(lv_dir) = get_server_directory( ).

    IF lv_dir IS INITIAL.
      MESSAGE 'No se ha podido resolver la ruta lógica del servidor.' TYPE 'E'.
      RETURN.
    ENDIF.

    DATA(lt_files) = get_server_files( lv_dir ).

    IF lt_files IS INITIAL.
      MESSAGE 'No hay ficheros para procesar en el servidor.' TYPE 'I'.
      RETURN.
    ENDIF.

    LOOP AT lt_files INTO DATA(lv_filename).

      DATA(lt_lines) = read_server_file( lv_dir && lv_filename ).

      IF lt_lines IS INITIAL.
        WRITE: / 'No se ha podido leer:', lv_filename.
        CONTINUE.
      ENDIF.

      split_and_write_server( it_lines = lt_lines
                               iv_name  = lv_filename
                               iv_dir   = lv_dir ).

      " Se mueve el original para no reprocesarlo en la siguiente ejecucion
      TRY.
          zxx_cl_file_utils=>move_server_file(
            EXPORTING
              i_sourcepath = lv_dir
              i_targetpath = lv_dir && co_processed_dir
              i_filename   = lv_filename ).
        CATCH zfi_cl_cx_file.
          WRITE: / 'No se ha podido mover a procesados/:', lv_filename.
      ENDTRY.

    ENDLOOP.

  ENDMETHOD.

  METHOD split_and_write_local.

    split_lines( EXPORTING it_lines = it_lines
                 IMPORTING et_trf   = DATA(lt_trf)
                           et_dev   = DATA(lt_dev) ).

    download_lines( iv_filename = build_output_filename( iv_filename = iv_name
                                                           iv_suffix  = co_suffix_trf )
                     it_lines    = lt_trf ).

    download_lines( iv_filename = build_output_filename( iv_filename = iv_name
                                                           iv_suffix  = co_suffix_dev )
                     it_lines    = lt_dev ).

    " -1 por la linea de cabecera, que se cuenta en ambos ficheros
    DATA(lv_total) = lines( it_lines ) - 1.
    DATA(lv_trf)   = lines( lt_trf ) - 1.
    DATA(lv_dev)   = lines( lt_dev ) - 1.

    WRITE: / iv_name.
    WRITE: / '  Lineas totales:', lv_total.
    WRITE: / '  Transferencias (_TRF):', lv_trf.
    WRITE: / '  Extornos (_DEV):', lv_dev.

  ENDMETHOD.

  METHOD split_and_write_server.

    split_lines( EXPORTING it_lines = it_lines
                 IMPORTING et_trf   = DATA(lt_trf)
                           et_dev   = DATA(lt_dev) ).

    write_server_file( iv_path  = iv_dir && build_output_filename( iv_filename = iv_name
                                                                     iv_suffix  = co_suffix_trf )
                        it_lines = lt_trf ).

    write_server_file( iv_path  = iv_dir && build_output_filename( iv_filename = iv_name
                                                                     iv_suffix  = co_suffix_dev )
                        it_lines = lt_dev ).

    DATA(lv_total) = lines( it_lines ) - 1.
    DATA(lv_trf)   = lines( lt_trf ) - 1.
    DATA(lv_dev)   = lines( lt_dev ) - 1.

    WRITE: / iv_name.
    WRITE: / '  Lineas totales:', lv_total.
    WRITE: / '  Transferencias (_TRF):', lv_trf.
    WRITE: / '  Extornos (_DEV):', lv_dev.

  ENDMETHOD.

  METHOD split_lines.

    CLEAR: et_trf, et_dev.

    LOOP AT it_lines INTO DATA(lv_line).

      " Primera linea del fichero (cabecera): va en ambos ficheros tal cual
      IF sy-tabix = 1.
        APPEND lv_line TO et_trf.
        APPEND lv_line TO et_dev.
        CONTINUE.
      ENDIF.

      DATA(lv_docnum) = get_doc_number( lv_line ).

      IF lv_docnum IS NOT INITIAL.
        " Extorno: se reemplaza el concepto por el numero de documento,
        " manteniendo el ancho fijo de linea y el sufijo final original
        FIND FIRST OCCURRENCE OF co_eur_tag IN lv_line MATCH OFFSET DATA(lv_eur_off).
        DATA(lv_prefix) = substring( val = lv_line len = lv_eur_off + 3 ) && `  ` && lv_docnum.
        DATA(lv_suffix) = substring( val = lv_line off = strlen( lv_line ) - 4 len = 4 ).
        DATA(lv_pad)     = strlen( lv_line ) - strlen( lv_prefix ) - strlen( lv_suffix ).

        DATA(lv_new_line) = COND string( WHEN lv_pad > 0
                                          THEN lv_prefix && repeat( val = ` ` occ = lv_pad ) && lv_suffix
                                          ELSE lv_prefix && lv_suffix ).

        APPEND lv_new_line TO et_dev.
      ELSE.
        " No es extorno (o la linea no tiene el formato esperado): transferencia
        APPEND lv_line TO et_trf.
      ENDIF.

    ENDLOOP.

  ENDMETHOD.

  METHOD get_doc_number.

    FIND FIRST OCCURRENCE OF co_eur_tag IN iv_line MATCH OFFSET DATA(lv_eur_off).
    CHECK sy-subrc = 0.

    DATA(lv_concept) = substring( val = iv_line off = lv_eur_off + 3 ).
    SHIFT lv_concept LEFT DELETING LEADING space.

    CHECK strlen( lv_concept ) >= 24.

    DATA(lv_prefix24) = substring( val = lv_concept len = 24 ).

    CHECK lv_prefix24 CO '0123456789'.

    rv_docnum = substring( val = lv_prefix24 off = 12 len = 12 ).

  ENDMETHOD.

  METHOD build_output_filename.

    FIND ALL OCCURRENCES OF '.' IN iv_filename RESULTS DATA(lt_matches).

    IF lt_matches IS INITIAL.
      rv_result = iv_filename && iv_suffix.
      RETURN.
    ENDIF.

    DATA(lv_last_dot) = lt_matches[ lines( lt_matches ) ]-offset.

    rv_result = substring( val = iv_filename len = lv_last_dot ) &&
                iv_suffix &&
                substring( val = iv_filename off = lv_last_dot ).

  ENDMETHOD.

  METHOD get_filename_from_path.

    SPLIT iv_path AT '\' INTO TABLE DATA(lt_win).
    IF lines( lt_win ) > 1.
      rv_filename = lt_win[ lines( lt_win ) ].
      RETURN.
    ENDIF.

    SPLIT iv_path AT '/' INTO TABLE DATA(lt_unix).
    rv_filename = lt_unix[ lines( lt_unix ) ].

  ENDMETHOD.

  METHOD get_server_directory.

    TRY.
        zxx_cl_file_utils=>get_directory(
          EXPORTING i_logical_path = co_logical_path
          IMPORTING e_directory    = rv_directory ).

        REPLACE ALL OCCURRENCES OF '*' IN rv_directory WITH ''.

      CATCH zfi_cl_cx_file.
        CLEAR rv_directory.
    ENDTRY.

  ENDMETHOD.

  METHOD get_server_files.

    DATA: lt_dir_list TYPE TABLE OF epsfili.

    CALL FUNCTION 'EPS2_GET_DIRECTORY_LISTING'
      EXPORTING
        dir_name               = iv_directory
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

    " co_processed_dir es una subcarpeta (sin la barra final) dentro de
    " esta misma carpeta: se excluye para no intentar "procesarla" como
    " si fuese un fichero.
    DATA(lv_processed_name) = co_processed_dir.
    REPLACE '/' IN lv_processed_name WITH ''.

    LOOP AT lt_dir_list INTO DATA(ls_dir).
      CHECK ls_dir-name IS NOT INITIAL.
      CHECK ls_dir-name <> lv_processed_name.
      " Los ficheros _TRF/_DEV son la SALIDA de este mismo programa: si se
      " escanean como si fuesen ECOFI de entrada, se reprocesarian sin fin
      CHECK NOT ( ls_dir-name CS co_suffix_trf OR ls_dir-name CS co_suffix_dev ).
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

  METHOD upload_lines.

    cl_gui_frontend_services=>gui_upload(
      EXPORTING filename                = gv_path
                filetype                = 'ASC'
      CHANGING  data_tab                = rt_lines
      EXCEPTIONS file_open_error        = 1
                 file_read_error        = 2
                 no_batch               = 3
                 gui_refuse_filetransfer = 4
                 invalid_type           = 5
                 no_authority           = 6
                 unknown_error          = 7
                 bad_data_format        = 8
                 header_not_allowed     = 9
                 separator_not_allowed  = 10
                 header_too_long        = 11
                 unknown_dp_error       = 12
                 access_denied          = 13
                 dp_out_of_memory       = 14
                 disk_full              = 15
                 dp_timeout             = 16
                 not_supported_by_gui   = 17
                 error_no_gui           = 18
                 OTHERS                 = 19 ).

    IF sy-subrc <> 0.
      CLEAR rt_lines.
    ENDIF.

  ENDMETHOD.

  METHOD download_lines.

    " Sustituye el nombre de fichero de gv_path por iv_filename, manteniendo
    " la misma carpeta (sin usar REGEX, ver get_filename_from_path)
    DATA(lv_dir_len) = strlen( gv_path ) - strlen( get_filename_from_path( gv_path ) ).
    DATA(lv_target)  = substring( val = gv_path len = lv_dir_len ) && iv_filename.

    DATA(lt_lines) = it_lines.

    cl_gui_frontend_services=>gui_download(
      EXPORTING filename                = lv_target
                filetype                = 'ASC'
      CHANGING  data_tab                = lt_lines
      EXCEPTIONS file_write_error        = 1
                 no_batch                = 2
                 gui_refuse_filetransfer = 3
                 invalid_type            = 4
                 no_authority            = 5
                 unknown_error           = 6
                 header_not_allowed      = 7
                 separator_not_allowed   = 8
                 filesize_not_allowed    = 9
                 header_too_long         = 10
                 unknown_dp_error        = 11
                 access_denied           = 12
                 dp_out_of_memory        = 13
                 disk_full               = 14
                 dp_timeout              = 15
                 file_not_found          = 16
                 dataprovider_exception  = 17
                 control_flush_error     = 18
                 not_supported_by_gui    = 19
                 error_no_gui            = 20
                 OTHERS                  = 21 ).

    IF sy-subrc <> 0.
      MESSAGE |No se ha podido escribir { iv_filename }.| TYPE 'I'.
    ENDIF.

  ENDMETHOD.

ENDCLASS.
