FUNCTION zfi_fm_devoluciones2.
*"----------------------------------------------------------------------
*"*"Interfaz local:
*"  IMPORTING
*"     VALUE(IT_KEYR1) TYPE  ZFI_T_KEYR1
*"  EXPORTING
*"     VALUE(E_RESULT) TYPE  CHAR3
*"     VALUE(ET_ERROR) TYPE  ZFI_T_XX_WS_ERROR
*"----------------------------------------------------------------------
* RU_03 (CDI_11) como servicio RFC. El DF pedía originalmente un
* "servicio" para el cierre/contabilización del lote de devoluciones;
* se decidió con Eva que no hacía falta (bastaba el report
* ZFI_R_DEVOLUCIONES2, con el lote indicado a mano). Más tarde se ha
* pedido igualmente un servicio - se mantienen los dos: el report para
* uso manual (equivalente a FP09) y este RFC para integración externa.
*
* En vez de duplicar la lógica ya probada de LCL_DEVOLUCIONES2, este
* módulo literalmente llama al propio ZFI_R_DEVOLUCIONES2 (SUBMIT ...
* WITH SELECTION-TABLE, construyendo S_KEYR1 a partir de IT_KEYR1) y
* después relee DFKKRK-STARS para decidir el resultado - la misma
* fuente de verdad que usa el propio report para decidir qué hacer con
* cada lote (ver ZFI_R_DEVOLUCIONES2_CLS, CO_STARS_POSTED).
*
* SIN parámetro de simulación: a diferencia del report (que sí tiene
* P_SIMU, para uso manual), esta RFC SIEMPRE se ejecuta en real - no
* se pasa ninguna fila P_SIMU en la tabla de seleccion, así que el
* report usa su propio valor por defecto (P_SIMU DEFAULT SPACE, ver
* ZFI_R_DEVOLUCIONES2_EVE). Decisión explícita: no viene del DF, se
* quita para no dar pie a que un consumidor externo dispare una
* llamada en modo simulación sin querer.
*
* E_RESULT/ET_ERROR siguen el mismo espiritu que ZFI_FM_PAYLOT_REVERSE/
* ZFI_FM_PAYMENT_LOT_CLARIFY2 (CHAR3 'OK'/'NOK' + estructura de error
* ZFI_DE_XX_WS_ERROR), pero aqui ET_ERROR es una TABLA (ZFI_T_XX_WS_ERROR,
* linea = ZFI_DE_XX_WS_ERROR) en vez de una unica estructura - IT_KEYR1
* admite varios lotes a la vez, y con el detalle de error tipo FP09 (ver
* mas abajo) puede haber muchos mensajes reales por lote, que no caben
* en el campo DESCRIPTION (CHAR75) de una unica estructura. Cada mensaje
* (el resumen del lote y cada linea de detalle FP09) es una fila propia,
* asi ninguno se trunca por ir concatenado con los demas. 'OK' solo si
* TODOS los lotes de IT_KEYR1 terminaron contabilizados (STARS =
* CO_STARS_POSTED) y ET_ERROR queda vacia; si no, 'NOK'.
*
* Detalle de error tipo FP09: además de STARS, ZFI_R_DEVOLUCIONES2_CLS
* captura (cuando FKK_RLS_POST_LOT falla) el mismo detalle de mensajes
* por documento que muestra la FP09 y lo deja en memoria ABAP
* (MEMORY ID 'ZFI_DEVOL2_ERRORS') al terminar su EXECUTE - pero SOLO si
* esta RFC se lo pide, vía la fila P_RFC = 'X' en la tabla de selección
* del SUBMIT de abajo (parámetro NO-DISPLAY de ZFI_R_DEVOLUCIONES2_EVE):
* así una ejecución manual del report en SE38 no exporta nada. Como el
* SUBMIT ... AND RETURN de abajo abre una sesión interna nueva, no
* podemos leer ahí los datos globales de SAPLFKKTRACE directamente
* (por eso el report hace el trabajo y nos deja el resultado ya
* montado en memoria ABAP, que sí cruza esa frontera) - lo importamos
* aquí y añadimos una fila a ET_ERROR por cada línea de detalle, junto
* al resumen de STARS de cada lote.
* TY_POST_ERROR se declara igual (misma estructura, no hace falta que
* sea el mismo tipo con nombre) que la de ZFI_R_DEVOLUCIONES2_CLS.
* El nombre 'GT_POST_ERRORS' en EXPORT/IMPORT es la clave del dato
* dentro de la memoria ABAP (no el nombre de la variable en cada lado,
* que puede ser distinto) - tiene que coincidir en ambos.
*
* OJO: DESCRIPTION sigue siendo CHAR75 por fila - un mensaje individual
* de FP09 mas largo que eso se truncaria igualmente, pero es un caso
* mucho mas raro que el problema original (perder TODO el detalle al
* concatenarlo en una unica fila).

  TYPES:
    BEGIN OF ty_post_error,
      keyr1   TYPE dfkkrk-keyr1,
      message TYPE string,
    END OF ty_post_error.

  DATA: lt_rspar       TYPE STANDARD TABLE OF rsparams,
        ls_rspar       TYPE rsparams,
        lv_stars       TYPE dfkkrk-stars,
        lt_post_errors TYPE STANDARD TABLE OF ty_post_error.

  CLEAR: e_result, et_error.

  IF it_keyr1 IS INITIAL.
    e_result = 'NOK'.
    APPEND VALUE #( code        = 'PARAM_MISSING'
                    description = 'IT_KEYR1 es obligatorio (al menos un lote)' ) TO et_error.
    RETURN.
  ENDIF.

  LOOP AT it_keyr1 INTO DATA(ls_keyr1_in).
    CLEAR ls_rspar.
    ls_rspar-selname = 'S_KEYR1'.
    ls_rspar-kind    = 'S'.
    ls_rspar-sign    = 'I'.
    ls_rspar-option  = 'EQ'.
    ls_rspar-low     = ls_keyr1_in-keyr1.
    APPEND ls_rspar TO lt_rspar.
  ENDLOOP.

  " P_RFC (NO-DISPLAY en ZFI_R_DEVOLUCIONES2_EVE): senal explicita de
  " que esta llamada viene de esta RFC, para que el report exporte el
  " detalle de errores a memoria ABAP (ver ZFI_R_DEVOLUCIONES2_CLS,
  " EXPORT_POST_ERRORS) - sin esto, una ejecucion manual del report en
  " SE38 no dejaria nada en memoria para nadie que lo necesite.
  CLEAR ls_rspar.
  ls_rspar-selname = 'P_RFC'.
  ls_rspar-kind    = 'P'.
  ls_rspar-sign    = 'I'.
  ls_rspar-option  = 'EQ'.
  ls_rspar-low     = abap_true.
  APPEND ls_rspar TO lt_rspar.

  SUBMIT zfi_r_devoluciones2
    WITH SELECTION-TABLE lt_rspar
    AND RETURN.

  IMPORT gt_post_errors = lt_post_errors FROM MEMORY ID 'ZFI_DEVOL2_ERRORS'.
  FREE MEMORY ID 'ZFI_DEVOL2_ERRORS'.

  LOOP AT it_keyr1 INTO DATA(ls_keyr1_out).

    CLEAR lv_stars.
    SELECT SINGLE stars FROM dfkkrk INTO lv_stars
      WHERE keyr1 = ls_keyr1_out-keyr1.

    IF sy-subrc <> 0.
      APPEND VALUE #( code        = 'LOTES_INCOMPLETOS'
                      description = |Lote { ls_keyr1_out-keyr1 }: no existe en DFKKRK.| ) TO et_error.
    ELSEIF lv_stars <> co_stars_posted.
      APPEND VALUE #( code        = 'LOTES_INCOMPLETOS'
                      description = |Lote { ls_keyr1_out-keyr1 }: STARS={ lv_stars } (no contabilizado).| ) TO et_error.

      " Una fila por cada linea de detalle FP09 de este lote - no se
      " concatenan entre si ni con el resumen de arriba, para que
      " ninguna se trunque (ver cabecera del include).
      LOOP AT lt_post_errors INTO DATA(ls_post_error) WHERE keyr1 = ls_keyr1_out-keyr1.
        APPEND VALUE #( code        = 'LOTES_INCOMPLETOS'
                        description = ls_post_error-message ) TO et_error.
      ENDLOOP.
    ENDIF.

  ENDLOOP.

  IF et_error IS INITIAL.
    e_result = 'OK'.
  ELSE.
    e_result = 'NOK'.
  ENDIF.

ENDFUNCTION.
