* Clase:  ZCL_ZEIDESWTDOCSTEP_DPC_EXT
* Método: EIDESWTDOCSTEPFA_GET_ENTITYSET
*         (redefinición de GetEntitySet para el entity set
*         EideswtdocstepFactsSet, generada por SEGW)

method EIDESWTDOCSTEPFA_GET_ENTITYSET.

  TYPES: BEGIN OF ty_eideswtdocstep,
           switchnum TYPE eideswtdocstep-switchnum,
           stepkey   TYPE eideswtdocstep-stepkey,
           timestamp TYPE eideswtdocstep-timestamp,
           activity  TYPE eideswtdocstep-activity,
           status    TYPE eideswtdocstep-status,
         END OF ty_eideswtdocstep.

  DATA: lt_data TYPE STANDARD TABLE OF ty_eideswtdocstep.

  SELECT switchnum, stepkey, timestamp, activity, status
    FROM eideswtdocstep
    INTO TABLE @lt_data.

  LOOP AT lt_data INTO DATA(ls_data).
    APPEND INITIAL LINE TO et_entityset ASSIGNING FIELD-SYMBOL(<ls_entity>).
    MOVE-CORRESPONDING ls_data TO <ls_entity>.
  ENDLOOP.

endmethod.
