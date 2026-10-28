"! Tarea 7 — Clase de excepción ZCX_####_NO_AGENCY
"! Mensaje 002 de la clase de mensajes ZC_ABAPD, placeholder &1 = agencia.
"! Genera el esqueleto con el wizard "ABAP Exception Class" indicando
"! ID de mensaje ZC_ABAPD / número 002, y completa como sigue.
CLASS zcx_####_no_agency DEFINITION
  PUBLIC
  INHERITING FROM cx_static_check
  FINAL
  CREATE PUBLIC .

  PUBLIC SECTION.
    INTERFACES if_t100_dyn_msg.
    INTERFACES if_t100_message.

    CONSTANTS:
      BEGIN OF no_agency,
        msgid TYPE symsgid     VALUE 'ZC_ABAPD',
        msgno TYPE symsgno     VALUE '002',
        attr1 TYPE scx_attrname VALUE 'AGENCY',
        attr2 TYPE scx_attrname VALUE '',
        attr3 TYPE scx_attrname VALUE '',
        attr4 TYPE scx_attrname VALUE '',
      END OF no_agency.

    DATA agency TYPE /dmo/agency_id.

    METHODS constructor
      IMPORTING
        textid   LIKE if_t100_message=>t100key OPTIONAL
        previous LIKE previous            OPTIONAL
        agency   TYPE /dmo/agency_id      OPTIONAL.

ENDCLASS.


CLASS zcx_####_no_agency IMPLEMENTATION.

  METHOD constructor ##ADT_SUPPRESS_GENERATION.
    super->constructor( previous = previous ).
    me->agency = agency.

    IF textid IS INITIAL.
      if_t100_message~t100key = no_agency.
    ELSE.
      if_t100_message~t100key = textid.
    ENDIF.
  ENDMETHOD.

ENDCLASS.
