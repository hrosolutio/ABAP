*************************************************************************
* PROGRAM: ZFI_R_ECOFI_SPLIT                                            *
* DESCRIPTION: Division del fichero bancario ECOFI en transferencias    *
*              (_TRF) y extornos (_DEV) - CDI_11, RU_01                 *
* AUTHOR:                                                                *
* DATE: 11.08.2026                                                      *
* DEV ID (RICEFW/ENH/INC): CDI_11                                       *
*=======================================================================*
* MODIFICATION LOG                                                      *
*-----------------------------------------------------------------------*
* NO.MOD  | DATE       | NAME             | FUNC NAME           |DEV ID *
*-----------------------------------------------------------------------*
* 001     | 11.08.2026 |                  | Version inicial,      |CDI_11 *
*         |            |                  | modo local (upload/   |       *
*         |            |                  | download) para prueba |       *
*         |            |                  | con ficheros reales    |       *
*         |            |                  | (ver README)           |       *
*                                                                       *
*************************************************************************
REPORT zfi_r_ecofi_split LINE-SIZE 255.

INCLUDE zfi_r_ecofi_split_top.
INCLUDE zfi_r_ecofi_split_eve.
INCLUDE zfi_r_ecofi_split_cls.

START-OF-SELECTION.

  DATA(go_split) = NEW lcl_ecofi_split( iv_path = p_path ).
  go_split->execute( ).
