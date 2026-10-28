"! Tarea 3 — Clase base FLIGHT
"! Sustituye #### por tu número de grupo antes de crear la clase en ADT.
CLASS zcl_####_flight DEFINITION
  PUBLIC
  CREATE PUBLIC .

  PUBLIC SECTION.
    DATA carrier_id    TYPE /dmo/carrier_id READ-ONLY.
    DATA connection_id TYPE /dmo/connection_id READ-ONLY.
    DATA airport_from  TYPE /dmo/airport_from_id READ-ONLY.
    DATA airport_to    TYPE /dmo/airport_to_id READ-ONLY.

    METHODS constructor
      IMPORTING
        carrier_id    TYPE /dmo/carrier_id
        connection_id TYPE /dmo/connection_id
        plane_type    TYPE /dmo/plane_type_id
      RAISING
        zcx_c_abapd_no_connection.

  PROTECTED SECTION.
    DATA plane_type TYPE /dmo/plane_type_id.

  PRIVATE SECTION.
ENDCLASS.


CLASS zcl_####_flight IMPLEMENTATION.

  METHOD constructor.
    me->carrier_id    = carrier_id.
    me->connection_id = connection_id.
    me->plane_type    = plane_type.

    SELECT SINGLE airport_from_id, airport_to_id
      FROM /dmo/connection
      WHERE carrier_id    = @carrier_id
        AND connection_id = @connection_id
      INTO ( @me->airport_from, @me->airport_to ).

    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE zcx_c_abapd_no_connection.
    ENDIF.
  ENDMETHOD.

ENDCLASS.
