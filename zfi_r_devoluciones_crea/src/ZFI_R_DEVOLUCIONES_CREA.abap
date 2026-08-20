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
* 001     | 17.08.2026 |                  | Version inicial (SIN  |CDI_11 *
*         |            |                  | USAR), generaba        |       *
*         |            |                  | AUSZUG/UMSATZ + SUBMIT |       *
*         |            |                  | RFKKA00 - enfoque      |       *
*         |            |                  | descartado, el DF pide |       *
*         |            |                  | FP09, no RFKKA00        |       *
* 002     | 20.08.2026 |                  | Reescrito sobre la    |CDI_11 *
*         |            |                  | API real de FP09        |       *
*         |            |                  | (FKK_RLS_HDR_PREPARE/  |       *
*         |            |                  | _SAVE, FKK_RLS_ITEM_    |       *
*         |            |                  | PREPARE/_SAVE_MASS),   |       *
*         |            |                  | localizada depurando   |       *
*         |            |                  | FP09 (ver DF_resumen)  |       *
*                                                                       *
*************************************************************************
REPORT zfi_r_devoluciones_crea LINE-SIZE 255.

INCLUDE zfi_r_devoluciones_crea_top.
INCLUDE zfi_r_devoluciones_crea_eve.
INCLUDE zfi_r_devoluciones_crea_cls.

START-OF-SELECTION.

*En modo Upload se debe indicar el fichero local
  IF p_upload EQ 'X' AND p_path IS INITIAL.
    MESSAGE 'Para carga local se debe indicar el fichero.' TYPE 'E'.
  ENDIF.

  TRY.
      DATA(go_devoluciones_crea) = NEW lcl_devoluciones_crea( iv_path   = p_path
                                                                iv_upload = p_upload ).
      go_devoluciones_crea->execute( ).

    CATCH zfi_cl_cx_load_file INTO DATA(lo_zcx).
      lo_zcx->get_text( ).
    CATCH zfi_cl_cx_file.
  ENDTRY.
