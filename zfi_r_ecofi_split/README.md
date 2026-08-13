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
  ficheros** que haya en la carpeta de la ruta lógica
  `lcl_ecofi_split=>co_logical_path` (`ZFICA_COBROS_ECOFI`, a crear en SAP,
  ver más abajo), y mueve cada original a la subcarpeta `procesados/` tras
  dividirlo, para no reprocesarlo en la siguiente ejecución. No usa
  `ZFI_T_FILE_LOG` ni el campo `S_FILEID` que tiene `ZFI_R_DEVOLUCIONES`: a
  diferencia de las devoluciones, el fichero ECOFI es el primer eslabón de la
  cadena y no está registrado en ningún sitio todavía, así que este programa
  escanea la carpeta directamente. **Aún no hay job ni disparo automático** —
  hay que lanzarlo a mano en SE38 — ver "Pendiente / a definir con el
  cliente" en `docs/DF_resumen.md`.

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
4. Solo para modo **Server**: crear en transacción **`FILE`** la ruta lógica
   **`ZFICA_COBROS_ECOFI`** apuntando a la ruta física del servidor donde
   llegan los ficheros ECOFI (p.ej. la misma ruta AL11
   `/interfaces/cobros/transf_N43/in` que menciona el comentario de EVA en el
   DF), y crear dentro de esa carpeta la subcarpeta **`procesados/`**.
5. Activar y ejecutar (F8).
   - Modo **Upload**: en `P_PATH`, seleccionar (F4) un fichero ECOFI real en
     tu PC (p.ej. uno de los dos ficheros de prueba). Los ficheros de salida
     se descargan a la misma carpeta local.
   - Modo **Server**: no hace falta indicar nada más — procesa todos los
     ficheros que haya en la carpeta de `ZFICA_COBROS_ECOFI` y mueve cada
     original a `procesados/` al terminar.
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
