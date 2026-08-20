# ZFI_R_DEVOLUCIONES_CREA — Creación del lote de devoluciones (CDI_11)

Implementa **RU_02** del DF *"Procedimiento Gestión de extornos"* (CDI_11):
a partir del fichero `_DEV` (salida de [`zfi_r_ecofi_split/`](../zfi_r_ecofi_split/README.md),
desarrollo 1), crea el lote de devoluciones en FI-CA vía la API real de
`FP09` (localizada por depuración — ver `docs/DF_resumen.md`).

Es el desarrollo 2 de 3 del proyecto CDI_11:
1. **División del fichero ECOFI** → [`zfi_r_ecofi_split/`](../zfi_r_ecofi_split/README.md)
2. **Creación del lote de devoluciones** → este programa.
3. **Cierre y contabilización del lote** → [`zfi_r_devoluciones2/`](../zfi_r_devoluciones2/README.md)

## Estado: probado con éxito en Integración, pendiente de probar en SE38

Reescrito sobre la API pública del grupo de función `FKR2` (dominio
"Rückläuferstapel" = lote de devoluciones), localizada depurando el botón
Grabar de `FP09` — no sobre `RFKKA00` (enfoque anterior, descartado por
lectura incorrecta del DF; ver `docs/DF_resumen.md` para el detalle
completo de la depuración).

**Ya probado directamente vía los módulos de función** (sin pasar aún por
este programa ABAP): en Integración, con 3 posiciones reales del `_DEV` de
`zfi_r_ecofi_split`, se creó el lote `260819CDI110` con éxito
("Se han grabado los datos"), confirmado en `DFKKRP` por `SE16N`.

**Pendiente**: activar `ZFI_R_DEVOLUCIONES_CREA_CLS` (reescrito) en SE38 y
probar el programa completo (modo Upload primero, con el `_DEV` de prueba).

## Contenido del repositorio

```
src/
  ZFI_R_DEVOLUCIONES_CREA.abap        Programa principal (REPORT)
  ZFI_R_DEVOLUCIONES_CREA_TOP.abap    Include TOP
  ZFI_R_DEVOLUCIONES_CREA_EVE.abap    Include EVE (pantalla de selección)
  ZFI_R_DEVOLUCIONES_CREA_CLS.abap    Include CLS (clase lcl_devoluciones_crea) — sobre FKK_RLS_HDR_PREPARE/_SAVE + FKK_RLS_ITEM_PREPARE/_SAVE_MASS
docs/
  DF_resumen.md                        Resumen del Diseño Funcional + historial completo de la depuración de FP09
```

## Cómo probarlo (SE38)

1. Crear/actualizar el programa **`ZFI_R_DEVOLUCIONES_CREA`** y sus 3
   includes (`_TOP`, `_EVE`, `_CLS`) con el contenido de `src/`.
2. Crear los elementos de texto **`TEXT-001`** (título bloque `P_PATH`,
   p.ej. "Fichero `_DEV`") y **`TEXT-002`** (título bloque de modo).
3. Revisar la constante `co_cta_comp` en `ZFI_R_DEVOLUCIONES_CREA_CLS` — el
   valor del DF (`4305500150`) no está configurado en DES (no deriva
   banco/cuenta); usar el que sí funcione en el sistema donde se pruebe
   (en Integración, `4305500150` si ya está bien, o el que se haya usado
   en las pruebas — ver `docs/DF_resumen.md`).
4. Activar.
5. **Primera prueba: modo Upload**, con un `_DEV` de prueba (el que ya
   generó `zfi_r_ecofi_split`). **Ojo: no es una simulación** — crea el
   lote de verdad en el sistema donde se ejecute. El programa escribe en
   pantalla el nº de lote creado (`AAMMDDCDI11x`) o el error, si lo hay.
6. Solo cuando el paso 5 confirme que funciona bien end-to-end, probar el
   modo **Server** (escanea la carpeta de `ZFICA_COBROS_ECOFI` — ver
   "Pendiente" en `docs/DF_resumen.md`, esa ruta lógica todavía no existe
   en ningún sistema).

## Pendiente

Ver `docs/DF_resumen.md` para el detalle completo. Resumen:

- `co_cta_comp` (`4305500150`) no está configurada en DES — confirmar con
  Basis/funcional el valor correcto por sistema.
- La ruta lógica `ZFICA_COBROS_ECOFI` no existe en ningún sistema todavía
  (necesaria solo para el modo Server).
- Confirmar si el motivo `Z01` existe como valor válido en el customizing
  de motivos de devolución.
- Alta del objeto en el sistema de transporte correspondiente al proyecto.
