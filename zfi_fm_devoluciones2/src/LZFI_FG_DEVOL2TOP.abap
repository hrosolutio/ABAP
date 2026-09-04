*&---------------------------------------------------------------------*
*& Include LZFI_FG_DEVOL2TOP                                           *
*& Grupo de función: ZFI_FG_DEVOL2                                     *
*& Datos globales del pool de funciones                                *
*&---------------------------------------------------------------------*
FUNCTION-POOL zfi_fg_devol2.

* IT_KEYR1 (lotes de entrada) y ET_RESULTADO (resultado por lote) usan
* tipos de tabla DDIC (creados en SE11, ver README) - el Function
* Builder no admite un TYPES de programa como tipo de referencia de un
* parámetro de import/export, tiene que ser un objeto DDIC real (mismo
* patrón ya usado en ZFI_T_XBLNR de ZFI_FM_PAYMENT_LOT_CLARIFY2):
*   ZFI_S_KEYR1        (estructura: KEYR1)
*   ZFI_T_KEYR1        (tabla estándar, línea ZFI_S_KEYR1)
*   ZFI_S_KEYR1_RESULT (estructura: KEYR1, STARS)
*   ZFI_T_KEYR1_RESULT (tabla estándar, línea ZFI_S_KEYR1_RESULT)
