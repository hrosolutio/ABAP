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
hipótesis descartada). **Confirmado ya arreglado**: lote `260825CDI110`
creado y **cerrado con éxito** en `FP09` (`Status`: "Ya no se pueden
modificar devoluciones").

**Pendiente**: confirmar con el funcional el secuencial de 1 dígito para
el nº de lote (ver más abajo), probar **"Contabilizar"** sobre un lote
cerrado (siguiente paso de RU_03), y
probar el modo **Server** (bloqueado hasta que `RUTA_LOG_DEV` en
`ZFI_T_CONSTANTS` tenga una carpeta física real del servidor — ver
"Configuración" más abajo; ya no depende de dar de alta nada en
transacción `FILE`).

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

## Concepto de búsqueda (`DFKKRK-KEYR2`)

Pedido por Eva: para identificar fácilmente de qué fichero `_DEV` viene
cada lote, `create_lot` rellena `DFKKRK-KEYR2` (concepto de búsqueda,
`CHAR40`) con el **nombre del fichero** `_DEV` origen — en modo Server,
el nombre real del fichero procesado; en modo Upload, el nombre de
fichero extraído de `P_PATH`. Sin ningún criterio especial de recorte si
el nombre no cupiera en 40 caracteres (los nombres reales observados
caben enteros).

## Modo Server: el fichero SIEMPRE se mueve, se procese bien o mal

Pedido por Eva: para dejar la carpeta de entrada limpia de cara a la
siguiente ejecución, un `_DEV` procesado **siempre** acaba movido —
a `RUTA_PROC_DEV` si se creó el lote con éxito, o a `error/` (subcarpeta
de `RUTA_LOG_DEV`, sin cambios) en cualquier otro caso: no se pudo leer
el fichero, no tenía líneas de extorno reconocibles, no se pudo
registrar en `ZFI_T_FILE_LOG`, o falló la creación del lote. Antes
había casos (sobre todo el fallo de lectura y el fallo de registro en
`ZFI_T_FILE_LOG`) en los que el programa solo escribía un mensaje y
pasaba al siguiente fichero **sin moverlo**, dejándolo abandonado en la
carpeta de entrada — se reintentaba (y volvía a fallar) en cada
ejecución siguiente. `transport_files` ya no depende de que el registro
en `ZFI_T_FILE_LOG` haya funcionado (antes recibía toda la fila
`ZFI_T_FILE_LOG`, ahora solo el nombre de fichero), precisamente para
poder llamarse en el caso en que ese registro falla.

## Validación de duplicados (`ZFI_T_R3SEG_DEV`)

Pedido por Eva: replicar la validación que ya existe en el programa de
creación del lote de pagos (`LCL_GESTION_COBROS_TRANSF`, sobre
`ZFI_T_R3SEG`) para evitar procesar dos veces la misma posición — por si
viene repetida dentro del mismo `_DEV`, o si ya llegó en un fichero
anterior.

**Tabla propia `ZFI_T_R3SEG_DEV`** (copia de `ZFI_T_R3SEG` — decisión de
Eva: no compartir la tabla entre los dos procesos, aunque no hay riesgo
real de colisión de claves entre ellos). Clave: `MANDT`+`APUNT`+`ZUONR`+
`BUKRS`+`BELNR`+`GJAHR`.

La línea de 260 caracteres del `_DEV` (heredada tal cual del fichero
bancario original, solo el concepto lo reescribe `ZFI_R_ECOFI_SPLIT`)
resultó ser un **registro posicional real** (confirmado por depuración,
mismos offsets que `LS_BODY` en `LCL_GESTION_COBROS_TRANSF`), no texto
libre — así que `BUKRS`/`GJAHR`/`APUNT`/`ZUONR` se leen directos del
fichero (`PARSE_DEV_LINES`), no se inventan:

| Campo de la clave | Valor | Origen |
|---|---|---|
| `BUKRS` | `1239` (confirmado) | Real, offset 2 de la línea |
| `GJAHR` | año real del apunte bancario | Real, offset 74 de la línea |
| `APUNT` | constante en las pruebas vistas | Real, offset 256 de la línea |
| `ZUONR` | `ANUP` (indicador de extorno, siempre igual en un `_DEV`) | Real, offset 46 de la línea |
| `BELNR` | nº de documento SAP de 12 dígitos | **No** el nativo del offset 62 (eso es otra referencia del banco, no el documento) — es el `docnum` que ya extrae `PARSE_DEV_LINES` del concepto reescrito por `ZFI_R_ECOFI_SPLIT` |

`FILTER_DUPLICATES` (llamado en `PROCESS_DEV_FILE` y en `EXECUTE_UPLOAD`,
justo después de `PARSE_DEV_LINES`) descarta, por cada posición:
1. Si ya salió antes **en el mismo fichero** (`line_exists` contra una
   tabla en memoria que se va rellenando).
2. Si ya está en `ZFI_T_R3SEG_DEV` **de un fichero anterior** (`SELECT
   SINGLE COUNT(*)`).

Igual que el programa de pagos, **el `MODIFY ZFI_T_R3SEG_DEV` solo se
hace si el lote se llega a crear con éxito** — si `CREATE_LOT` falla, no
se graba nada, para no marcar como "ya procesadas" posiciones de un
fichero que al final no generó ningún lote.

Si **todas** las posiciones de un fichero resultan duplicadas, se
considera `PROCESADO` (no `ERROR`) y se mueve a la carpeta de
procesados — no hay nada nuevo que contabilizar, no es un fallo.

Mensajes nuevos en `ZFI_MC_001` (**hay que darlos de alta en `SE91`
antes de activar**, con `&1` como único parámetro):
- `184` (I): `Posición &1 duplicada en el propio fichero &2, se descarta`
- `185` (I): `Posición &1 ya registrada de un fichero anterior, se descarta`

(`&1` = número de documento, `&2` = nombre del fichero `_DEV` actual).

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
3. Crear en **`SE11`** la tabla **`ZFI_T_R3SEG_DEV`** (copia de
   `ZFI_T_R3SEG` — ver "Validación de duplicados" más abajo) y dar de
   alta en **`SE91`** los mensajes `184`/`185` de `ZFI_MC_001`.
4. Dar de alta en **`ZFI_T_CONSTANTS`** las 3 filas que necesita el
   programa (sociedad, motivo, cta. compensación) — ya no son constantes
   ABAP hardcodeadas, se leen en tiempo de ejecución con el método
   `get_constants` de `ZFI_R_DEVOLUCIONES_CREA_CLS`. Claves y valores en
   la sección "Configuración (`ZFI_T_CONSTANTS`)" más abajo — **el
   programa no arranca si faltan** (aborta con mensaje "Faltan constantes
   en ZFI_T_CONSTANTS...").
5. Activar.
6. **Primera prueba: modo Upload**, con un `_DEV` de prueba (el que ya
   generó `zfi_r_ecofi_split`). **Ojo: no es una simulación** — crea el
   lote de verdad en el sistema donde se ejecute. El programa escribe en
   pantalla el nº de lote creado (`AAMMDDCDI11x`, ver "Nomenclatura del
   lote" más abajo) y el nº de posiciones, o el error, si lo hay.
7. Solo cuando el paso 6 confirme que funciona bien end-to-end, probar el
   modo **Server** (escanea la carpeta física indicada en `RUTA_LOG_DEV` —
   ver "Pendiente" en `docs/DF_resumen.md`, la ruta física definitiva de
   producción todavía no está decidida/creada).

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
| `RUTA_LOG_DEV` | Ruta **física** del servidor (modo Server) donde se buscan los `_DEV` — es la ruta física tal cual (no una ruta lógica de transacción `FILE`), p.ej. `/interfaces/cobros/transf_N43/in/`. **⚠️ Antes se llamaba `RUTA_LOGICA`** — la fila ya creada en cada sistema (DES, Integración...) hay que renombrarla (solo el `CONSTANT_ID`, no el valor) a `RUTA_LOG_DEV`, o el programa deja de encontrarla. Renombrada por consistencia con `RUTA_LOG_ECOFI`/`RUTA_LOG_TRF`/`RUTA_LOG_PROC` de `ZFI_R_ECOFI_SPLIT`, que también lee esta misma fila | Ruta física real de producción — **aún no decidida/creada**; para probar, poner aquí cualquier carpeta física que ya exista en el sistema de prueba |
| `RUTA_PROC_DEV` | Carpeta donde se mueve el `_DEV` una vez usado para crear el lote — ruta física **propia**, ya no una subcarpeta `procesados/` de `RUTA_LOG_DEV` como antes (esa subcarpeta no existe en Integración — real, encontrado probando: error `>014` "No fue posible transportar el fichero..." justo después de crear el lote con éxito). Distinta de `RUTA_LOG_PROC` de `ZFI_R_ECOFI_SPLIT` (esa es para el ECOFI de entrada, esta es para el `_DEV` ya consumido) | Cualquier carpeta física que ya exista en el sistema de prueba |
| `MONEDA` | Moneda (`DFKKRK-WAERS`) y tag de moneda que identifica el importe dentro de la línea del `_DEV` | `EUR` |

Si falta cualquiera de las 6 filas (o `ACTIVE` no es `X`), el programa
aborta sin crear ningún lote.

`RUTA_LOG_DEV`, `RUTA_PROC_DEV` y `MONEDA` son, además de datos de
sistema, la vía para **probar sin depender de que las carpetas físicas
definitivas de producción existan o de que el fichero de prueba esté en
euros**: basta con cambiar el valor de esa fila en `ZFI_T_CONSTANTS`, sin
tocar ni reactivar código.

## Pendiente

Ver `docs/DF_resumen.md` para el detalle completo. Resumen:

- Confirmar con el funcional el secuencial de 1 dígito del nº de lote
  (límite técnico de `KEYR1`, ver más arriba).
- Dar de alta las filas de `ZFI_T_CONSTANTS` en Integración (en DES ya
  están, probadas con éxito).
- **Renombrar en cada sistema donde ya exista** (DES, Integración...) la
  fila `RUTA_LOGICA` a `RUTA_LOG_DEV` (mismo valor, solo cambia el
  `CONSTANT_ID`) — ver aviso en "Configuración" más arriba.
- **Dar de alta la fila nueva `RUTA_PROC_DEV`** en cada sistema, con una
  carpeta física real (en Integración, `procesados/` ya no existe como
  subcarpeta de `RUTA_LOG_DEV` — motivo de este cambio, ver
  "Configuración").
- La ruta física definitiva de producción para `RUTA_LOG_DEV`/
  `RUTA_PROC_DEV` (modo Server) todavía no está decidida/creada.
- **Crear `ZFI_T_R3SEG_DEV`** en `SE11` (copia de `ZFI_T_R3SEG`) y dar de
  alta los mensajes `184`/`185` en `SE91` — ver "Validación de
  duplicados" más arriba. Sin probar aún contra un `_DEV` real con
  posiciones repetidas.
- Alta del objeto en el sistema de transporte correspondiente al proyecto.
