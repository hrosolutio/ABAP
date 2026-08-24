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
Grabar de `FP09` — no sobre `RFKKKA00` (enfoque anterior, descartado por
lectura incorrecta del DF; ver `docs/DF_resumen.md` para el detalle
completo de la depuración).

**Probado directamente vía los módulos de función** (Integración, 3
posiciones reales del `_DEV`): lote `260819CDI110` creado con éxito
("Se han grabado los datos"), confirmado en `DFKKRP` por `SE16N`.

**Probado el programa completo** (DES, modo Upload, `_DEV` real de 72
líneas): primera vuelta con lote `RL2026082103` (antes de calcular
`KEYR1` en la propia clase — ver "Nomenclatura del lote" más abajo), 72
posiciones confirmadas en `DFKKRP`/`DFKKRK` por `SE16N` (sin huecos ni
duplicados de `POSRA`, incluido el corte donde `FKK_RLS_ITEM_PREPARE` capa
a `MAX_LINES` — ver `docs/DF_resumen.md`). Repetido después con la
nomenclatura ya del DF: lote `260824CDI110` (`AAMMDDCDI11x`, primer
secuencial del día), también con éxito y 72 posiciones correctas.

**Corrección importante (encontrada depurando RU_03)**: el lote se
grababa pero no se podía cerrar/contabilizar (`FP09` → "Cerrar" daba
"No existen entradas para la remesa", mensaje `>2549`) porque
`DFKKRK-ANZPO` (nº de posiciones de la cabecera) se quedaba a `0` aunque
`DFKKRP` sí tuviera las 72 posiciones reales — no por `OPBEL` sin
resolver, como se pensó en un primer momento (ver "Validación de
posiciones y `ANZPO`" más abajo para el detalle completo, incluida la
hipótesis descartada).

**Pendiente**: confirmar con el funcional el secuencial de 1 dígito para
el nº de lote (ver más abajo), volver a probar el ciclo completo
crear→cerrar→contabilizar con el fix de `ANZPO` (todavía no probado), y
probar el modo **Server** (bloqueado hasta que exista una ruta lógica de
fichero real — ver `RUTA_LOGICA` en `ZFI_T_CONSTANTS` más abajo).

## Nomenclatura del lote

El DF exige que el lote se llame `AAMMDDCDI11xx`. Sin hacer nada, SAP
genera el `KEYR1` con su propio formato por defecto (`RL` + fecha +
secuencial, p.ej. `RL2026082103` — visto en la prueba de DES) porque
`FKK_RLS_HDR_PREPARE` solo genera un `KEYR1` cuando el campo llega vacío.

En vez de engancharnos al "soft-exit" del grupo de función `FKR2`
(`PROG_NAME`/`ZFKR2_POOL`, un mecanismo global para todo el sistema — se
valoró y se descartó por innecesariamente invasivo para algo que solo
necesita nuestro programa), `create_lot` calcula el `KEYR1` **él mismo**
(método `generate_keyr1`) y se lo pasa ya relleno a
`FKK_RLS_HDR_PREPARE` — exactamente igual que si se tecleara a mano en
`FP09`: si `KEYR1` no viene vacío, el FM no genera nada, solo comprueba
que no exista ya. Queda todo contenido en nuestra propia clase, sin tocar
nada compartido con el resto del sistema.

**Ojo con el límite de 12 caracteres** de `DFKKRK-KEYR1`: el DF pide
`AAMMDDCDI11xx` (13 caracteres, secuencial de 2 dígitos), pero no caben —
la implementación usa `AAMMDDCDI11x` (secuencial de 1 dígito, máximo 10
lotes/día — `generate_keyr1` calcula el siguiente con un `SELECT MAX(
KEYR1 )` sobre `DFKKRK` filtrando por el prefijo del día). Si se agotan
los 10 valores de un día, `generate_keyr1` devuelve vacío y
`FKK_RLS_HDR_PREPARE` cae a su generador estándar en vez de fallar.
**Confirmar con el funcional que esta desviación del DF (secuencial de 1
dígito, no 2) es aceptable.**

## Validación de posiciones y `ANZPO`

`SELT1`='B'/`SELW1`=nº de documento es solo un **criterio de búsqueda**,
no el documento resuelto. `create_lot` llama a `FKK_RLS_ITEM_VALIDATE`
por cada posición para comprobar que resuelve contra un documento de pago
real (mismo paso que hace `LCL_RLOT->COMPLETE_CHECK` antes de grabar en
`FP09`, confirmado viendo su código fuente) — si un documento no es
válido (excepción `NOT_VALID`, p.ej. no existe), se aborta. **Ojo:**
`OPBEL`, el campo que resuelve esta llamada, **no hace falta para nada
más** — ni siquiera el propio `COMPLETE_CHECK` de SAP lo guarda (llama a
la FM sobre una copia local y nunca hace `MODIFY` después); es solo una
comprobación de validez, no bloquea ni grabar ni cerrar el lote (una
hipótesis inicial de que sí hacía falta resolverlo resultó equivocada,
ver `docs/DF_resumen.md`).

Lo que **sí hace falta** es que `DFKKRK-ANZPO` (nº de posiciones que dice
tener la cabecera) quede con el valor correcto al grabar — si se queda a
`0` (aunque `DFKKRP` tenga las posiciones de verdad), `FP09` → "Cerrar" da
el error `>2549` ("No existen entradas para la remesa") aunque las
posiciones existan. Confirmado que **`FKK_RLS_ITEM_SAVE_MASS` no
actualiza `ANZPO` en BD** aunque se le pase relleno en `C_DFKKRK`
(probado: `ls_dfkkrk-anzpo` = 72 justo antes de la llamada, la tabla
queda con `0` después). Fix: `create_lot` vuelve a llamar a
`FKK_RLS_HDR_SAVE` (una segunda vez, ya con la cabecera existente y
`ANZPO` puesto al total real) justo después de `FKK_RLS_ITEM_SAVE_MASS` —
usando la propia API de SAP para persistirlo, no un `UPDATE` directo a la
tabla.

**Sobre abortar con `NOT_VALID`**: la cabecera ya está grabada en ese
punto (`FKK_RLS_HDR_SAVE` se llama justo después de `HDR_PREPARE`, ver
más abajo), así que un documento inválido deja un lote creado sin
posiciones (se puede borrar desde `FP09` → Remesa de devoluciones →
Borrar, como indica el propio mensaje `>2549`) — no es un abort 100%
limpio, pero es el mismo criterio de todo-o-nada (sin granularidad por
línea) que ya usan `ZFI_R_DEVOLUCIONES_CREA`/`ZFI_R_DEVOLUCIONES` a nivel
de fichero completo.

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
   pantalla el nº de lote creado (`AAMMDDCDI11x`, ver "Nomenclatura del
   lote" más abajo) y el nº de posiciones, o el error, si lo hay.
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

- Confirmar con el funcional el secuencial de 1 dígito del nº de lote
  (límite técnico de `KEYR1`, ver más arriba).
- Dar de alta las filas de `ZFI_T_CONSTANTS` en Integración (en DES ya
  están, probadas con éxito).
- La ruta lógica `ZFICA_COBROS_ECOFI` no existe en ningún sistema todavía
  (necesaria solo para el modo Server).
- Alta del objeto en el sistema de transporte correspondiente al proyecto.
