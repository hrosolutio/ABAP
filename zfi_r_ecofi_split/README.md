# ZFI_R_ECOFI_SPLIT — División del fichero bancario ECOFI (CDI_11)

Implementa **RU_01** del DF *"Procedimiento Gestión de extornos"* (CDI_11):
al llegar el fichero bancario de transferencias de ECOFI, lo divide en dos,
manteniendo el formato original — uno con las transferencias (`_TRF`) y otro
con los extornos (`_DEV`).

Es el desarrollo 1 de 3 del proyecto CDI_11 — ver
[`zfi_r_devoluciones2/`](../zfi_r_devoluciones2/README.md) para los otros dos
(creación del lote de devoluciones y cierre/contabilización).

Ver `docs/DF_resumen.md` para el detalle del formato de fichero (verificado
contra los 2 ficheros de prueba reales `YFRECAU_1239_260402.140017.txt` y
`YFRECAU_1239_260415.140018.txt`) y de la lógica implementada.

## Estado

**Lógica de división probada** (en local, con `python3`, replicando línea a
línea el algoritmo del código ABAP) contra los 2 ficheros de prueba: todas las
líneas se reparten correctamente entre `_TRF`/`_DEV` sin pérdidas, y la regla
de 24 dígitos coincide al 100% con el indicador `ANUP`/`TRRD` del propio
fichero en ambos casos.

**Pendiente de probar dentro de SAP** (SE38, ver más abajo) — el código ABAP
replica exactamente la lógica verificada, pero aún no se ha ejecutado en el
sistema.

Modo de ejecución: **local o servidor**, con radio buttons `p_server`/`p_upload`
(mismo comportamiento de pantalla que `ZFI_R_DEVOLUCIONES`: `P_PATH` se oculta
en modo servidor):
- **Upload** (local): pide un fichero (`P_PATH`, con F4), lo sube/descarga vía
  GUI. Para poder probarlo desde SE38 contra un fichero en tu PC.
- **Server**: no pide ningún fichero — **procesa automáticamente todos los
  ficheros** que haya en la carpeta de **entrada** (ruta física leída
  directamente de `ZFI_T_CONSTANTS`, ver "Configuración" más abajo —
  antes era la constante `co_logical_path` con `ZFICA_COBROS_ECOFI`
  hardcodeado e inventado, sin existir en ningún sistema), escribe
  `_TRF`/`_DEV` en una carpeta de **salida** distinta, y mueve cada
  original a una carpeta de **procesados** — también distinta, ya no una
  subcarpeta de la de entrada como antes — tras dividirlo, para no
  reprocesarlo en la siguiente ejecución. No usa `ZFI_T_FILE_LOG` ni el
  campo `S_FILEID` que tiene `ZFI_R_DEVOLUCIONES`: a diferencia de las
  devoluciones, el fichero ECOFI es el primer eslabón de la cadena y no
  está registrado en ningún sitio todavía, así que este programa escanea
  la carpeta directamente. **Aún no hay job ni disparo automático** — hay
  que lanzarlo a mano en SE38 — ver "Pendiente / a definir con el cliente"
  en `docs/DF_resumen.md`.

## Configuración (`ZFI_T_CONSTANTS`)

El modo Server necesita **tres** rutas físicas distintas, todas variables
(el modo Upload no necesita ninguna): la carpeta donde se **recoge** el
ECOFI (entrada), la carpeta donde se **dejan** `_TRF`/`_DEV` (salida) y la
carpeta donde se **mueve** el original ya dividido (procesados) no tienen
por qué coincidir — de hecho la de salida tiene que ser la carpeta que
`ZFI_R_DEVOLUCIONES_CREA` escanea buscando `_DEV`.

**`CONSTANT_VALUE` es la ruta física del servidor tal cual** (p.ej.
`/interfaces/cobros/transf_N43/in/`), **no** el nombre de una ruta lógica
de transacción `FILE`: el programa ya no pasa por
`ZXX_CL_FILE_UTILS=>GET_DIRECTORY` para resolver nada — lee el valor de
`ZFI_T_CONSTANTS` y lo usa directamente como carpeta (normalizando solo
la barra final). Decisión deliberada: el sistema de ficheros (las
carpetas físicas) ya existe antes que el programa, así que si algo hay
que adaptar para que encajen es el programa, no forzar de alta rutas
lógicas nuevas en `FILE` solo para una capa de indirección que
`ZFI_T_CONSTANTS` ya da (el valor cambia por sistema igualmente, fila a
fila, sin tocar código).

**Decisión**: las 3 filas viven bajo el **mismo `PROCESS_ID='DEVOL_CREA'`**
que ya usa `ZFI_R_DEVOLUCIONES_CREA` — deliberadamente no se da de alta un
`PROCESS_ID` propio (`ECOFI_SPLIT`) para no tener que registrar una fila
nueva en `ZFI_T_PROCESS`; los dos programas se tratan como el mismo
eslabón lógico del proceso `CDI_11`. Se distinguen solo por `CONSTANT_ID`:

| `CONSTANT_ID` | Carpeta | ¿Fila nueva? |
|---|---|---|
| `RUTA_LOG_ECOFI` | Entrada (donde llega el ECOFI) | Sí |
| `RUTA_LOGICA` | Salida (`_TRF`/`_DEV`) | **No** — ya existe, es la misma fila que `ZFI_R_DEVOLUCIONES_CREA` usa como su propia entrada |
| `RUTA_LOG_PROC` | Procesados (donde se archiva el original) | Sí |

Las dos filas nuevas:

| Campo | Entrada | Procesados |
|---|---|---|
| `APPLICATION_ID` | `FICA` | `FICA` |
| `PROCESS_ID` | `DEVOL_CREA` | `DEVOL_CREA` |
| `SUB_PROCESS_ID` | (en blanco) | (en blanco) |
| `CONSTANT_ID` | `RUTA_LOG_ECOFI` | `RUTA_LOG_PROC` |
| `ACTIVE` | `X` | `X` |

La fila de salida (`RUTA_LOGICA`) no se toca — sigue siendo la misma que
ya usa `ZFI_R_DEVOLUCIONES_CREA`, documentada en su propio README. Así hay
una única fuente de verdad para esa carpeta compartida — no hay dos
valores que mantener sincronizados a mano, y por tanto no hay riesgo de
que se desincronicen.

## Contenido del repositorio

```
src/
  ZFI_R_ECOFI_SPLIT.abap        Programa principal (REPORT)
  ZFI_R_ECOFI_SPLIT_TOP.abap    Include TOP
  ZFI_R_ECOFI_SPLIT_EVE.abap    Include EVE (pantalla de selección)
  ZFI_R_ECOFI_SPLIT_CLS.abap    Include CLS (clase lcl_ecofi_split)
docs/
  DF_resumen.md                  Resumen del Diseño Funcional (trazabilidad)
```

## Cómo probarlo (SE38)

1. Crear el programa **`ZFI_R_ECOFI_SPLIT`** (tipo *Report ejecutable*).
2. Crear los includes **`ZFI_R_ECOFI_SPLIT_TOP`**, **`ZFI_R_ECOFI_SPLIT_EVE`**,
   **`ZFI_R_ECOFI_SPLIT_CLS`** con el contenido de `src/`, e incluirlos en el
   programa principal en ese orden.
3. Crear los elementos de texto **`TEXT-001`** (título del bloque `P_PATH`,
   p.ej. "Fichero a dividir") y **`TEXT-002`** (título del bloque de modo,
   p.ej. "Modo de ejecución"). Textos de selección sugeridos para los
   parámetros: `P_SERVER` = "Servidor de aplicaciones", `P_UPLOAD` = "Carga
   local (PC)", `P_PATH` = "Ruta del fichero".
4. Solo para modo **Server**: no hace falta transacción `FILE` — basta con
   dar de alta en `ZFI_T_CONSTANTS` las dos filas nuevas (`RUTA_LOG_ECOFI`
   y `RUTA_LOG_PROC`, ambas con `PROCESS_ID='DEVOL_CREA'` — no hace falta
   un `PROCESS_ID` propio) con la **ruta física real** del servidor como
   `CONSTANT_VALUE` (ver "Configuración" más abajo): la de entrada, p.ej.
   la misma ruta AL11 `/interfaces/cobros/transf_N43/in/` que menciona el
   comentario de EVA en el DF; la de procesados, una carpeta física
   distinta que ya exista (ya no hace falta que sea subcarpeta de la de
   entrada). La ruta de **salida** ya tiene que existir de antes — es la
   misma fila `RUTA_LOGICA` que ya usa `ZFI_R_DEVOLUCIONES_CREA` — no hay
   que crear nada nuevo para ella aquí.
5. Activar y ejecutar (F8).
   - Modo **Upload**: en `P_PATH`, seleccionar (F4) un fichero ECOFI real en
     tu PC (p.ej. uno de los dos ficheros de prueba). Los ficheros de salida
     se descargan a la misma carpeta local.
   - Modo **Server**: no hace falta indicar nada más — procesa todos los
     ficheros que haya en la carpeta de entrada, deja `_TRF`/`_DEV` en la
     carpeta de salida (la de `ZFI_R_DEVOLUCIONES_CREA`), y mueve cada
     original a la carpeta de procesados al terminar.
6. El programa genera, por cada fichero procesado, dos ficheros nuevos:
   `<nombre>_TRF.txt` y `<nombre>_DEV.txt`, y muestra en pantalla el recuento
   de líneas totales/transferencias/extornos.

## Pendiente / a definir con el cliente

Ver la sección completa en `docs/DF_resumen.md`. Los dos puntos más
relevantes:

- Formato exacto de la línea de extorno en `_DEV` (ancho fijo con relleno,
  como hace este programa, o formato más corto como el ejemplo del DF).
- Diseño del modo de ejecución en producción (servidor/AL11, disparo
  automático).
