*************************************************************************
* PROGRAM: ZFI_R_DEVOLUCIONES_CREA                                      *
* DESCRIPTION: Creacion del lote de devoluciones en FI-CA a partir del  *
*              fichero _DEV de extornos (RU_02, CDI_11)                  *
* AUTHOR:                                                                *
* DATE: 17.08.2026                                                      *
* DEV ID (RICEFW/ENH/INC): CDI_11                                       *
*=======================================================================*
* MODIFICATION LOG                                                      *
*-----------------------------------------------------------------------*
* NO.MOD  | DATE       | NAME             | FUNC NAME           |DEV ID *
*-----------------------------------------------------------------------*
* 001     | 17.08.2026 |                  | Version inicial,      |CDI_11 *
*         |            |                  | generacion de          |       *
*         |            |                  | AUSZUG/UMSATZ desde     |       *
*         |            |                  | el _DEV + SUBMIT       |       *
*         |            |                  | RFKKA00 (solo crea,    |       *
*         |            |                  | ver README)             |       *
*                                                                       *
*************************************************************************
REPORT zfi_r_devoluciones_crea LINE-SIZE 255.

INCLUDE zfi_r_devoluciones_crea_top.
INCLUDE zfi_r_devoluciones_crea_eve.
INCLUDE zfi_r_devoluciones_crea_cls.

START-OF-SELECTION.

*En modo Upload se debe indicar el fichero local y la carpeta de salida
  IF p_upload EQ 'X' AND ( p_path IS INITIAL OR p_outdir IS INITIAL ).
    MESSAGE 'Para carga local se debe indicar el fichero y la carpeta de salida.' TYPE 'E'.
  ENDIF.

  TRY.
      DATA(go_devoluciones_crea) = NEW lcl_devoluciones_crea( iv_path   = p_path
                                                                iv_outdir = p_outdir
                                                                iv_upload = p_upload ).
      go_devoluciones_crea->execute( ).

    CATCH zfi_cl_cx_load_file INTO DATA(lo_zcx).
      lo_zcx->get_text( ).
    CATCH zfi_cl_cx_file.
  ENDTRY.
