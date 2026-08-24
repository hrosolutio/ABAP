# ZFI_R_DEVOLUCIONES_CREA — Creación del lote de devoluciones (CDI_11)

Implementa **RU_02** del DF *"Procedimiento Gestión de extornos"* (CDI_11):
a partir del fichero `_DEV` (salida de [`zfi_r_ecofi_split/`](../zfi_r_ecofi_split/README.md),
desarrollo 1), crea el lote de devoluciones en FI-CA vía la API real de
`FP09` (localizada por depuración — ver `docs/DF_resumen.md`).

Es el desarrollo 2 de 3 del proyecto CDI_11:
1. **División del fichero ECOFI** → [`zfi_r_ecofi_split/`](../zfi_r_ecofi_split/README.md)
2. **Creación del lote de devoluciones** → este programa.
3. **Cierre y contabilización del lote** → [`zfi_r_devoluciones2/`](../zfi_r_devoluciones2/README.md)

## Estado: probado con éxito end-to-end en DES (modo Upload)

Reescrito sobre la API pública del grupo de función `FKR2` (dominio
"Rückläuferstapel" = lote de devoluciones), localizada depurando el botón
Grabar de `FP09` — no sobre `RFKKA00` (enfoque anterior, descartado por
lectura incorrecta del DF; ver `docs/DF_resumen.md` para el detalle
completo de la depuración).

**Probado directamente vía los módulos de función** (Integración, 3
posiciones reales del `_DEV`): lote `260819CDI110` creado con éxito
("Se han grabado los datos"), confirmado en `DFKKRP` por `SE16N`.

**Probado el programa completo** (DES, modo Upload, `_DEV` real de 72
líneas): lote `RL2026082103` creado con éxito, las 72 posiciones
confirmadas en `DFKKRP`/`DFKKRK` por `SE16N` (sin huecos ni duplicados de
`POSRA`, incluido el corte donde `FKK_RLS_ITEM_PREPARE` capa a `MAX_LINES`
— ver `docs/DF_resumen.md`).

**Pendiente**: dar de alta `ZFKR2_POOL` (ver más abajo) para que el nº de
lote siga la nomenclatura `AAMMDDCDI11x` del DF, y probar el modo **Server**
(bloqueado hasta que exista una ruta lógica de fichero real — ver
`RUTA_LOGICA` en `ZFI_T_CONSTANTS` más abajo).

## Nomenclatura del lote (`ZFKR2_POOL`)

El DF exige que el lote se llame `AAMMDDCDI11xx`. Sin nada más, SAP genera
el `KEYR1` con su propio formato por defecto (`RL` + fecha + secuencial,
p.ej. `RL2026082103` — visto en la prueba de DES), porque
`FKK_RLS_HDR_PREPARE` solo usa la nomenclatura del proyecto si existe un
programa de "soft-exit" llamado **exactamente `ZFKR2_POOL`** (nombre
hardcodeado en el código estándar de SAP, no es customizing) con una
`FORM GENERATE_RLS_KEY`.

Se ha creado ese programa: **`src/ZFKR2_POOL.abap`** — dar de alta en
`SE38` como **Pool de subrutinas** (no `REPORT`), nombre exacto
`ZFKR2_POOL`, y activar. En cuanto exista, tanto `ZFI_R_DEVOLUCIONES_CREA`
como la creación manual desde `FP09` usarán la nomenclatura del proyecto
automáticamente, sin más cambios.

**Ojo con el límite de 12 caracteres** de `DFKKRK-KEYR1`: el DF pide
`AAMMDDCDI11xx` (13 caracteres, secuencial de 2 dígitos), pero no caben —
la implementación usa `AAMMDDCDI11x` (secuencial de 1 dígito, máximo 10
lotes/día). Si se agotan los 10 valores de un día, cae al generador
estándar de SAP en vez de fallar. **Confirmar con el funcional que esta
desviación del DF (secuencial de 1 dígito, no 2) es aceptable.**

## Contenido del repositorio

```
src/
  ZFI_R_DEVOLUCIONES_CREA.abap        Programa principal (REPORT)
  ZFI_R_DEVOLUCIONES_CREA_TOP.abap    Include TOP
  ZFI_R_DEVOLUCIONES_CREA_EVE.abap    Include EVE (pantalla de selección)
  ZFI_R_DEVOLUCIONES_CREA_CLS.abap    Include CLS (clase lcl_devoluciones_crea) — sobre FKK_RLS_HDR_PREPARE/_SAVE + FKK_RLS_ITEM_PREPARE/_SAVE_MASS
  ZFKR2_POOL.abap                     Pool de subrutinas (soft-exit de FKR2, nombre fijo) — nomenclatura AAMMDDCDI11x del lote
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
   pantalla el nº de lote creado y el nº de posiciones, o el error, si lo
   hay. El formato del nº de lote lo decide el número de rango configurado
   en cada sistema (en DES ha salido `RL2026082103`, no `AAMMDDCDI11x` como
   en la prueba manual de Integración — es customizing, no afecta a que el
   lote sea válido).
6. Solo cuando el paso 5 confirme que funciona bien end-to-end, probar el
   modo **Server** (escanea la carpeta de `ZFICA_COBROS_ECOFI` — ver
   "Pendiente" en `docs/DF_resumen.md`, esa ruta lógica todavía no existe
   en ningún sistema).

## Configuración (`ZFI_T_CONSTANTS`)

El programa lee sus valores de negocio (antes hardcodeados en la clase) de
la tabla `ZFI_T_CONSTANTS`, con esta clave:

| Campo | Valor |
|---|---|
| `APPLICATION_ID` | `FICA` (`CDI_11` no está registrado como valor válido — hay una tabla de verificación/valores fijos detrás de `APPLICATION_ID`) |
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
| `RUTA_LOGICA` | Ruta lógica de fichero (modo Server) donde se buscan los `_DEV` | `ZFICA_COBROS_ECOFI` — **no existe en ningún sistema todavía**; para probar, poner aquí otra ruta lógica que sí exista en el sistema de prueba |
| `MONEDA` | Moneda (`DFKKRK-WAERS`) y tag de moneda que identifica el importe dentro de la línea del `_DEV` | `EUR` |

Si falta cualquiera de las 5 filas (o `ACTIVE` no es `X`), el programa
aborta sin crear ningún lote.

`RUTA_LOGICA` y `MONEDA` son, además de datos de sistema, la vía para
**probar sin depender de que `ZFICA_COBROS_ECOFI` exista o de que el
fichero de prueba esté en euros**: basta con cambiar el valor de esa fila
en `ZFI_T_CONSTANTS`, sin tocar ni reactivar código.

## Pendiente

Ver `docs/DF_resumen.md` para el detalle completo. Resumen:

- Dar de alta `ZFKR2_POOL` (pool de subrutinas) para la nomenclatura de
  lote del DF, y confirmar con el funcional el secuencial de 1 dígito
  (límite técnico de `KEYR1`, ver más arriba).
- Dar de alta las filas de `ZFI_T_CONSTANTS` en Integración (en DES ya
  están, probadas con éxito).
- La ruta lógica `ZFICA_COBROS_ECOFI` no existe en ningún sistema todavía
  (necesaria solo para el modo Server).
- Alta del objeto en el sistema de transporte correspondiente al proyecto.
