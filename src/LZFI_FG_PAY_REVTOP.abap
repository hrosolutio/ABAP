*&---------------------------------------------------------------------*
*& Include LZFI_FG_PAY_REVTOP                                          *
*& Grupo de función: ZFI_FG_PAY_REV                                    *
*& Datos globales del pool de funciones                                *
*&---------------------------------------------------------------------*
FUNCTION-POOL zfi_fg_pay_rev.

* Estructura de error de salida del servicio (ES_ERROR)
TYPES: BEGIN OF ty_s_error,
         code        TYPE char10,
         description TYPE char100,
       END OF ty_s_error.

* Constantes según nota técnica del DF (FKK_CTRACPAYMINC_REVERSE)
CONSTANTS:
  gc_doctype_anulacion   TYPE blart     VALUE 'ST',  " Clase de documento anulación
  gc_clearreas_anulacion TYPE augrd_kk  VALUE '05'.  " Motivo de compensación de anulación

* Identificador de proceso/subproceso por defecto (I_PROCESO)
CONSTANTS gc_proceso_default TYPE char20 VALUE 'CDI_11_03'.
