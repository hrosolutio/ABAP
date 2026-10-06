*----------------------------------------------------------------------*
* Excepción del servicio de facturación de averías y fraudes.
*
* Lleva el código de resultado que se devuelve a la RFC (EV_CODIGO) y
* su descripción. Los códigos 0xxx son descartes (resultado OK), los
* 1xxx errores de validación de entrada y los 2xxx errores técnicos o
* de cálculo (resultado KO). Ver README.
*----------------------------------------------------------------------*
CLASS zcx_fa_fraudes DEFINITION
  PUBLIC
  INHERITING FROM cx_static_check
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.

    DATA codigo TYPE char4 READ-ONLY.
    DATA texto  TYPE string READ-ONLY.

    METHODS constructor
      IMPORTING
        textid   LIKE textid OPTIONAL
        previous LIKE previous OPTIONAL
        codigo   TYPE char4 OPTIONAL
        texto    TYPE string OPTIONAL.

    METHODS get_text REDEFINITION.

ENDCLASS.



CLASS zcx_fa_fraudes IMPLEMENTATION.

  METHOD constructor.
    super->constructor( textid = textid previous = previous ).
    me->codigo = codigo.
    me->texto  = texto.
  ENDMETHOD.


  METHOD get_text.
    result = texto.
  ENDMETHOD.

ENDCLASS.
