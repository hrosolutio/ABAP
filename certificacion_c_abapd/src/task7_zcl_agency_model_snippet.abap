"! Tarea 7 — Ajuste sobre el método GET_AGENCY de ZCL_####_AGENCY_MODEL (copia de
"! ZCL_AGENCY_MODEL). Adapta el SELECT existente al que ya tenga la clase copiada;
"! lo importante es añadir RAISING a la firma y el chequeo de sy-subrc.

"-------------------------------------------------------------
" Firma del método (Class Builder / editor de fuente):
"-------------------------------------------------------------
* METHODS get_agency
*   IMPORTING
*     i_agency        TYPE /dmo/agency_id
*   RETURNING
*     VALUE(r_agency) TYPE /dmo/agency
*   RAISING
*     zcx_####_no_agency.

"-------------------------------------------------------------
" Implementación:
"-------------------------------------------------------------
METHOD get_agency.

  SELECT SINGLE *
    FROM /dmo/agency
    WHERE agency_id = @i_agency
    INTO CORRESPONDING FIELDS OF @r_agency.

  IF sy-subrc <> 0.
    RAISE EXCEPTION TYPE zcx_####_no_agency
      EXPORTING
        agency = i_agency.
  ENDIF.

ENDMETHOD.
