*************************************************************************
* PROGRAM: ZFI_R_DEVOLUCIONES2                                          *
* DESCRIPTION: Cierre y contabilizacion de lotes de devolucion de       *
*              extornos ya creados (RU_03, CDI_11)                      *
* AUTHOR:                                                                *
* DATE: 25.08.2026                                                      *
* DEV ID (RICEFW/ENH/INC): CDI_11                                       *
*=======================================================================*
* MODIFICATION LOG                                                      *
*-----------------------------------------------------------------------*
* NO.MOD  | DATE       | NAME             | FUNC NAME           |DEV ID *
*-----------------------------------------------------------------------*
* 001     | 06.08.2026 |                  | Copia base de         |CDI_11 *
*         |            |                  | ZFI_R_DEVOLUCIONES    |       *
*         |            |                  | (RFKKKA00) - enfoque  |       *
*         |            |                  | descartado             |       *
* 002     | 25.08.2026 |                  | Reescrito sobre       |CDI_11 *
*         |            |                  | FKK_RLS_CLOSE/         |       *
*         |            |                  | FKK_RLS_POST_LOT,      |       *
*         |            |                  | localizado depurando   |       *
*         |            |                  | FP09 (ver DF_resumen)  |       *
*                                                                       *
*************************************************************************
REPORT zfi_r_devoluciones2 LINE-SIZE 255.

INCLUDE zfi_r_devoluciones2_top.
INCLUDE zfi_r_devoluciones2_eve.
INCLUDE zfi_r_devoluciones2_cls.

START-OF-SELECTION.

  NEW lcl_devoluciones2( ir_keyr1 = s_keyr1[]
                         iv_simu  = p_simu )->execute( ).
