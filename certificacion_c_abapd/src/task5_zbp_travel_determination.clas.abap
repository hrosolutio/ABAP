"! Tarea 5 — Fragmentos de la Behavior Definition y de la clase de implementación
"! generadas por el wizard "Generate ABAP Repository Objects" sobre ZZ####TRAVEL.
"! Ajusta los nombres de entidad/alias exactamente a los que proponga el wizard en tu sistema.

"===============================================================
" Behavior Definition ZR_Z####TRAVEL (proyección) — añadir:
"===============================================================
* field ( readonly ) Status;
*
* determination setInitialStatus on save { create; }

"===============================================================
" Clase de implementación de comportamiento (behavior pool)
" — método generado por Eclipse (quick-fix Ctrl+1 sobre la determination)
"===============================================================
METHOD setInitialStatus.

  DATA lt_update TYPE TABLE FOR UPDATE zz####travel.

  lt_update = VALUE #( FOR key IN keys
    ( %tky   = key-%tky
      Status = 'N' ) ).

  MODIFY ENTITIES OF zr_z####travel IN LOCAL MODE
    ENTITY zz####travel
      UPDATE FIELDS ( Status )
      WITH lt_update.

ENDMETHOD.
