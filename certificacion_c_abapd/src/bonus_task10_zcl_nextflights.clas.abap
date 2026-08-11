"! Tarea 10 (Unit 2, no puntuable) — Próximo vuelo disponible por conexión
CLASS zcl_####_nextflights DEFINITION
  PUBLIC
  CREATE PUBLIC .

  PUBLIC SECTION.
    TYPES tt_flights TYPE STANDARD TABLE OF zcert_flight
            WITH NON-UNIQUE KEY carrier_id connection_id.

    METHODS get_next_flights
      RETURNING
        VALUE(r_flights) TYPE tt_flights.

  PROTECTED SECTION.
  PRIVATE SECTION.
ENDCLASS.


CLASS zcl_####_nextflights IMPLEMENTATION.

  METHOD get_next_flights.

    DATA(lv_today) = cl_abap_context_info=>get_system_date( ).

    SELECT carrier_id, connection_id, MIN( flight_date ) AS flight_date
      FROM /dmo/flight
      WHERE flight_date > @lv_today
      GROUP BY carrier_id, connection_id
      ORDER BY flight_date ASCENDING
      INTO CORRESPONDING FIELDS OF TABLE @r_flights.

  ENDMETHOD.

ENDCLASS.
