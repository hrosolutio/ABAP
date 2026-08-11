"! Tarea 3 — Subclase PASSENGER_FLIGHT
"! Sustituye #### por tu número de grupo. Superclass en el wizard: ZCL_####_FLIGHT.
CLASS zcl_####_passenger_flight DEFINITION
  PUBLIC
  INHERITING FROM zcl_####_flight
  CREATE PUBLIC .

  PUBLIC SECTION.
    METHODS constructor
      IMPORTING
        carrier_id    TYPE /dmo/carrier_id
        connection_id TYPE /dmo/connection_id
        plane_type    TYPE /dmo/plane_type_id
      RAISING
        zcx_c_abapd_no_connection.

  PROTECTED SECTION.
  PRIVATE SECTION.
    DATA seats_max TYPE /dmo/plane_seats_max.
ENDCLASS.


CLASS zcl_####_passenger_flight IMPLEMENTATION.

  METHOD constructor.
    super->constructor(
      carrier_id    = carrier_id
      connection_id = connection_id
      plane_type    = plane_type ).

    SELECT SINGLE MaximumSeats
      FROM zi_cabapd_passenger
      WHERE PlaneType = @plane_type
      INTO @seats_max.

    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE zcx_c_abapd_no_connection.
    ENDIF.
  ENDMETHOD.

ENDCLASS.
