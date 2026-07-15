*&---------------------------------------------------------------------*
*& Include LZFI_FG_PAY_CLARIFYTOP                                      *
*& Grupo de función: ZFI_FG_PAY_CLARIFY                                *
*& Datos globales del pool de funciones                                *
*&---------------------------------------------------------------------*
FUNCTION-POOL zfi_fg_pay_clarify.

* ES_ERROR usa la estructura DDIC estándar ZFI_DE_XX_WS_ERROR (CODE, DESCRIPTION)
* (misma estructura reutilizada del desarrollo ZFI_FM_PAYLOT_REVERSE)

* Tabla de facturas de entrada (I_XBLNR): el DF pide longitud variable,
* no un número fijo de posiciones.
TYPES: BEGIN OF ty_s_xblnr,
         xblnr TYPE xblnr,
       END OF ty_s_xblnr.
TYPES ty_t_xblnr TYPE STANDARD TABLE OF ty_s_xblnr WITH DEFAULT KEY.

* Cuenta provisional de transferencias pendientes de clarificar (según DF)
CONSTANTS gc_cuenta_provisional TYPE hkont VALUE '4305520150'.
