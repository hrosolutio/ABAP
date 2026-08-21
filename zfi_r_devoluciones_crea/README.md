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
3. Dar de alta en **`ZFI_T_CONSTANTS`** las 3 filas que necesita el
   programa (sociedad, motivo, cta. compensación) — ya no son constantes
   ABAP hardcodeadas, se leen en tiempo de ejecución con el método
   `get_constants` de `ZFI_R_DEVOLUCIONES_CREA_CLS`. Claves y valores en
   la sección "Configuración (`ZFI_T_CONSTANTS`)" más abajo — **el
   programa no arranca si faltan** (aborta con mensaje "Faltan constantes
   en ZFI_T_CONSTANTS...").
4. Activar.
5. **Primera prueba: modo Upload**, con un `_DEV` de prueba (el que ya
   generó `zfi_r_ecofi_split`). **Ojo: no es una simulación** — crea el
   lote de verdad en el sistema donde se ejecute. El programa escribe en
   pantalla el nº de lote creado (`AAMMDDCDI11x`) o el error, si lo hay.
6. Solo cuando el paso 5 confirme que funciona bien end-to-end, probar el
   modo **Server** (escanea la carpeta de `ZFICA_COBROS_ECOFI` — ver
   "Pendiente" en `docs/DF_resumen.md`, esa ruta lógica todavía no existe
   en ningún sistema).

## Configuración (`ZFI_T_CONSTANTS`)

El programa lee sus valores de negocio (antes hardcodeados en la clase) de
la tabla `ZFI_T_CONSTANTS`, con esta clave:

| Campo | Valor |
|---|---|
| `APPLICATION_ID` | `CDI_11` |
| `PROCESS_ID` | `DEVOL_CREA` |
| `SUB_PROCESS_ID` | (en blanco) |
| `ACTIVE` | `X` |

Y una fila por cada `CONSTANT_ID` necesario, con el `CONSTANT_VALUE` que
corresponda **en cada sistema** (DES/Integración pueden tener valores
distintos, p.ej. la cta. de compensación — ver `docs/DF_resumen.md`):

| `CONSTANT_ID` | Significado | Valor de referencia (DF) |
|---|---|---|
| `SOCIEDAD` | Sociedad (`DFKKRK-BUKRS`) | `1239` |
| `MOTIVO` | Motivo de devolución (`DFKKRK-RLGRD`) | `Z01` |
| `CTA_COMPENSACION` | Cta. compensación devoluciones (`DFKKRK-RLSKO`) | `4305500150` (DF) — no configurada en DES, ahí usar `4305500250` (ver `docs/DF_resumen.md`) |

Si falta cualquiera de las 3 filas (o `ACTIVE` no es `X`), el programa
aborta sin crear ningún lote.

## Pendiente

Ver `docs/DF_resumen.md` para el detalle completo. Resumen:

- Dar de alta las filas de `ZFI_T_CONSTANTS` de la tabla anterior en cada
  sistema (DES, Integración) con el valor de `CTA_COMPENSACION` correcto
  en cada uno.
- La ruta lógica `ZFICA_COBROS_ECOFI` no existe en ningún sistema todavía
  (necesaria solo para el modo Server).
- Confirmar si el motivo `Z01` existe como valor válido en el customizing
  de motivos de devolución.
- Alta del objeto en el sistema de transporte correspondiente al proyecto.
