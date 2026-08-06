*************************************************************************
* PROGRAM: ZFI_R_EXTORNOS                                               *
* DESCRIPTION: Gestion de extornos bancarios (CDI_11)                   *
* AUTHOR: Copia de partida de ZFI_R_DEVOLUCIONES (Jose Ternero)         *
* DATE: 06.08.2026                                                      *
* DEV ID (RICEFW/ENH/INC): CDI_11                                       *
*=======================================================================*
* MODIFICATION LOG                                                      *
*-----------------------------------------------------------------------*
* NO.MOD  | DATE       | NAME             | FUNC NAME           |DEV ID *
*-----------------------------------------------------------------------*
* 001     | 06.08.2026 |                  | Copia base de        |CDI_11 *
*         |            |                  | ZFI_R_DEVOLUCIONES,  |       *
*         |            |                  | logica sin adaptar    |       *
*         |            |                  | todavia (ver README) |       *
*                                                                       *
*************************************************************************
REPORT zfi_r_extornos LINE-SIZE 255.

INCLUDE zfi_r_extornos_top.
INCLUDE zfi_r_extornos_eve.
INCLUDE zfi_r_extornos_cls.

AT SELECTION-SCREEN ON VALUE-REQUEST FOR p_path.
  p_path = lcl_extornos=>f4_file( ).

START-OF-SELECTION.

*Para Carga local se debe indicar ruta
  IF p_upload EQ 'X' AND p_path IS INITIAL.
    MESSAGE TEXT-002 TYPE 'E'.
  ENDIF.

  IF p_path IS NOT INITIAL.
    lv_path = p_path.
  ELSEIF p_path1 IS NOT INITIAL AND p_path2 IS NOT INITIAL.
    CONCATENATE p_path1 p_path2 INTO lv_path.
  ENDIF.

  TRY.
      DATA(go_extornos) = NEW lcl_extornos(
        iv_upload    = p_upload
        iv_path      = lv_path
        ir_file_id   = s_fileid[] ).

      go_extornos->execute( ).

    CATCH zfi_cl_cx_load_file INTO DATA(lo_zcx).
      lo_zcx->get_text( ).
    CATCH zfi_cl_cx_file.
  ENDTRY.
