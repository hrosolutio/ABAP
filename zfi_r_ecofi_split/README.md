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

Modo de ejecución actual: **solo local** (`GUI_UPLOAD`/`GUI_DOWNLOAD`), pensado
para poder probarlo ya mismo en SE38 contra un fichero real descargado a tu
PC. El modo servidor (automático, contra la ruta AL11) está pendiente de
diseñar — ver "Pendiente / a definir con el cliente" en `docs/DF_resumen.md`.

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
3. Crear el elemento de texto **`TEXT-001`** (título del bloque de pantalla de
   selección, p.ej. "Fichero ECOFI a dividir").
4. Activar y ejecutar (F8). En `P_PATH`, seleccionar (F4) un fichero ECOFI
   real en tu PC (p.ej. uno de los dos ficheros de prueba).
5. El programa genera, en la misma carpeta del fichero de entrada, dos
   ficheros nuevos: `<nombre>_TRF.txt` y `<nombre>_DEV.txt`, y muestra en
   pantalla el recuento de líneas totales/transferencias/extornos.

## Pendiente / a definir con el cliente

Ver la sección completa en `docs/DF_resumen.md`. Los dos puntos más
relevantes:

- Formato exacto de la línea de extorno en `_DEV` (ancho fijo con relleno,
  como hace este programa, o formato más corto como el ejemplo del DF).
- Diseño del modo de ejecución en producción (servidor/AL11, disparo
  automático).
