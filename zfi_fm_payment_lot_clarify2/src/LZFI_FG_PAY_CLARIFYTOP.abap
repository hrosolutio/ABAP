*&---------------------------------------------------------------------*
*& Include LZFI_FG_PAY_CLARIFYTOP                                      *
*& Grupo de función: ZFI_FG_PAY_CLARIFY                                *
*& Datos globales del pool de funciones                                *
*&---------------------------------------------------------------------*
FUNCTION-POOL zfi_fg_pay_clarify.

* ES_ERROR usa la estructura DDIC estándar ZFI_DE_XX_WS_ERROR (CODE, DESCRIPTION)
* (misma estructura reutilizada del desarrollo ZFI_FM_PAYLOT_REVERSE)

* I_XBLNR (facturas de entrada, longitud variable) usa el tipo de tabla
* DDIC ZFI_T_XBLNR (creado en SE11, ver README), no un TYPES local: el
* Function Builder no admite TYPES de programa como tipo de referencia
* de parámetros de import/export.

* Cuenta provisional de transferencias pendientes de clarificar (según DF)
CONSTANTS gc_cuenta_provisional TYPE hkont VALUE '4305520150'.

* Valores observados por depuración en un I_FKKKO real de contabilización
* de lote de pagos (no confirmados como fijos/obligatorios para todos los
* casos, pero consistentes en la prueba realizada):
CONSTANTS:
  gc_applk_clarificacion TYPE applk_kk VALUE 'R',
  gc_blart_clarificacion TYPE blart    VALUE '2C',
  gc_herkf_clarificacion TYPE char2    VALUE '05'.  " FKKKO-HERKF; tipo exacto (elemento de datos) sin verificar

* Mapeo verificado en tabla de customizing TFK004 (Área R):
* tipo de selección 'X' (Número de documento oficial) -> campo FKKOP-XBLNR
CONSTANTS gc_selfn_xblnr TYPE selfn_kk VALUE 'XBLNR'.
