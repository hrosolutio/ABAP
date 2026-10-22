******************************************************************
* INI FUNCIONALIDAD 1B.- Campos Z de cálculos manuales sin diálogo
*                        (RFC ZFA_FM_CALCULAR_FRAUDESV2)
******************************************************************
* Se pega en ZXBI1U01 justo DESPUÉS de "FIN FUNCIONALIDAD 1" y ANTES
* de "INI FUNCIONALIDAD 2". La funcionalidad 1 deja los campos Z con
* lo que trae X_OBJ-CUST, que en un cálculo manual va vacío, y la 2
* solo actúa en EA16/EA17 (popup). La RFC de fraudes y averías deja
* los valores en memoria justo antes de ISU_S_MANUBILL_CREATE y la
* libera al volver: si no hay nada en memoria, este bloque no hace nada.
  IF 1 = 1.
    DATA: lv_fra_origdoc    TYPE erch-origdoc,
          lv_fra_serie_nod  TYPE erch-zserie_nod,
          lv_fra_fecha_oper TYPE erch-zfecha_oper_calc.

    IMPORT origdoc          = lv_fra_origdoc
           zserie_nod       = lv_fra_serie_nod
           zfecha_oper_calc = lv_fra_fecha_oper
      FROM MEMORY ID 'ZFA_FRAUDES_ERCH'.
    IF sy-subrc = 0 AND lv_fra_serie_nod IS NOT INITIAL.
      xy_bill_doc-erch-origdoc          = lv_fra_origdoc.
      xy_bill_doc-erch-zserie_nod       = lv_fra_serie_nod.
      xy_bill_doc-erch-zfecha_oper_calc = lv_fra_fecha_oper.
      CLEAR: xy_bill_doc-erch-zrect_forzado,
             xy_bill_doc-erch-zorig_factura,
             xy_bill_doc-erch-zorig_fecha_oper.
    ENDIF.
  ENDIF. " 1 = 1.
******************************************************************
* FIN FUNCIONALIDAD 1B.- Campos Z de cálculos manuales sin diálogo
******************************************************************
