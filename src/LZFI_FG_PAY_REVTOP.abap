*&---------------------------------------------------------------------*
*& Include LZFI_FG_PAY_REVTOP                                          *
*& Grupo de función: ZFI_FG_PAY_REV                                    *
*& Datos globales del pool de funciones                                *
*&---------------------------------------------------------------------*
FUNCTION-POOL zfi_fg_pay_rev.

* ES_ERROR usa la estructura DDIC estándar ZFI_DE_XX_WS_ERROR (CODE, DESCRIPTION)

* Constantes según nota técnica del DF (FKK_CTRACPAYMINC_REVERSE)
CONSTANTS:
  gc_doctype_anulacion   TYPE blart     VALUE 'ST',  " Clase de documento anulación
  gc_clearreas_anulacion TYPE augrd_kk  VALUE '05'.  " Motivo de compensación de anulación

* Identificador de proceso/subproceso por defecto (I_PROCESO)
CONSTANTS gc_proceso_default TYPE char20 VALUE 'CDI_11_03'.
