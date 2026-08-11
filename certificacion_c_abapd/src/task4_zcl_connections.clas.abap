"! Tarea 4 — Lista de conexiones de vuelo (1 escala máx., misma aerolínea, sin vuelos de vuelta)
"! Sustituye #### por tu número de grupo.
CLASS zcl_####_connections DEFINITION
  PUBLIC
  CREATE PUBLIC .

  PUBLIC SECTION.
    METHODS get_connections
      IMPORTING
        i_departure         TYPE /dmo/airport_from_id
      RETURNING
        VALUE(r_connections) TYPE zcert_connections.

  PROTECTED SECTION.
  PRIVATE SECTION.
ENDCLASS.


CLASS zcl_####_connections IMPLEMENTATION.

  METHOD get_connections.

    " 1) Vuelos directos desde el aeropuerto de salida
    SELECT carrier_id, airport_from_id, airport_to_id
      FROM /dmo/connection
      WHERE airport_from_id = @i_departure
      INTO TABLE @DATA(lt_direct).

    LOOP AT lt_direct INTO DATA(ls_direct).
      r_connections = VALUE #( BASE r_connections
        ( carrier_id      = ls_direct-carrier_id
          airport_from_id = ls_direct-airport_from_id
          airport_to_id   = ls_direct-airport_to_id
          airport_via_id  = '-' ) ).
    ENDLOOP.

    " 2) Conexiones con una escala, misma aerolínea, excluyendo vuelos de vuelta
    SELECT c1~carrier_id,
           c1~airport_to_id AS airport_via_id,
           c2~airport_to_id AS airport_to_id
      FROM /dmo/connection AS c1
      INNER JOIN /dmo/connection AS c2
        ON  c1~carrier_id     = c2~carrier_id
        AND c1~airport_to_id  = c2~airport_from_id
      WHERE c1~airport_from_id = @i_departure
        AND c2~airport_to_id  <> @i_departure
      INTO TABLE @DATA(lt_via).

    LOOP AT lt_via INTO DATA(ls_via).
      r_connections = VALUE #( BASE r_connections
        ( carrier_id      = ls_via-carrier_id
          airport_from_id = i_departure
          airport_to_id   = ls_via-airport_to_id
          airport_via_id  = ls_via-airport_via_id ) ).
    ENDLOOP.

  ENDMETHOD.

ENDCLASS.
