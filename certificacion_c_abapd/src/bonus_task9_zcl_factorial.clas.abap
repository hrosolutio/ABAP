"! Tarea 9 (Unit 2, no puntuable) — Factorial de un número
CLASS zcl_####_factorial DEFINITION
  PUBLIC
  CREATE PUBLIC .

  PUBLIC SECTION.
    METHODS calculate_factorial
      IMPORTING
        i_number          TYPE i
      RETURNING
        VALUE(r_factorial) TYPE i
      RAISING
        zcx_c_abapd_factorial_neg
        cx_sy_arithmetic_overflow.

  PROTECTED SECTION.
  PRIVATE SECTION.
ENDCLASS.


CLASS zcl_####_factorial IMPLEMENTATION.

  METHOD calculate_factorial.

    IF i_number < 0.
      RAISE EXCEPTION TYPE zcx_c_abapd_factorial_neg.
    ENDIF.

    r_factorial = 1.

    DO i_number TIMES.
      r_factorial = r_factorial * sy-index.
    ENDDO.

  ENDMETHOD.

ENDCLASS.
