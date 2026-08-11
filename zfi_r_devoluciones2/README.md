# ZFI_R_DEVOLUCIONES2 — Cierre y contabilización del lote de devolución de extornos (CDI_11)

**Estado: copia base sin adaptar.** Es una copia literal de `ZFI_R_DEVOLUCIONES`
(solo renombrado: report, includes y clase `lcl_devoluciones` → `lcl_devoluciones2`),
punto de partida para el desarrollo 3 de 3 del proyecto CDI_11 (gestión de
extornos): **"Servicio para cerrar y contabilizar lotes de devoluciones"**,
siguiendo la sugerencia de EVA en RU_03 de reutilizar el motor de
`ZFI_R_DEVOLUCIONES` (vía `RFKKA00`) en vez de crear un servicio RFC nuevo.

Es uno de los 3 desarrollos del proyecto CDI_11:
1. **División del fichero ECOFI** en transferencias/extornos → [`zfi_r_ecofi_split/`](../zfi_r_ecofi_split/README.md)
2. **Creación del lote de devoluciones** → programa aparte, pendiente de empezar.
3. **Cierre y contabilización del lote** → este programa (`ZFI_R_DEVOLUCIONES2`).

Ver `docs/DF_resumen.md` para el detalle de qué falta adaptar (formato de
entrada, generación de `AUSZUG`/`UMSATZ`, nomenclatura de lote, etc.) antes de
que este programa funcione con el fichero de extornos.

## Contenido del repositorio

```
src/
  ZFI_R_DEVOLUCIONES2.abap        Programa principal (REPORT)
  ZFI_R_DEVOLUCIONES2_TOP.abap    Include TOP (tipos y datos globales)
  ZFI_R_DEVOLUCIONES2_EVE.abap    Include EVE (pantalla de selección)
  ZFI_R_DEVOLUCIONES2_CLS.abap    Include CLS (clase lcl_devoluciones2)
docs/
  DF_resumen.md               Resumen del Diseño Funcional (trazabilidad)
```

## Instalación en SAP (SE38/SE80)

1. Crear el programa **`ZFI_R_DEVOLUCIONES2`** (tipo *Report ejecutable*), atributos
   equivalentes a `ZFI_R_DEVOLUCIONES`.
2. Crear los includes **`ZFI_R_DEVOLUCIONES2_TOP`**, **`ZFI_R_DEVOLUCIONES2_EVE`**,
   **`ZFI_R_DEVOLUCIONES2_CLS`** con el contenido de `src/`, e incluirlos en el
   programa principal en ese orden (como hace `ZFI_R_DEVOLUCIONES`).
3. Copiar los **elementos de texto** (`TEXT-001`, `TEXT-002`, `TEXT-003`) del
   programa original — no forman parte del código fuente ABAP, hay que copiarlos
   aparte desde Goto → Elementos de texto en SE38.
4. Activar. En este punto el programa es funcionalmente idéntico al original
   (espera XML de devolución SEPA); **no procesará todavía el fichero de
   extornos** hasta aplicar las adaptaciones de `docs/DF_resumen.md`.

## Pendiente / a definir con el cliente

- Fichero de ejemplo `AUSZUG`/`UMSATZ` generado hoy por `ZFI_R_DEVOLUCIONES`,
  para fijar el layout exacto que espera `RFKKA00` y poder generarlo desde el
  fichero `_DEV` de extornos (que no es XML SEPA).
- Formato final acordado del fichero `_DEV` (RU_01): si el concepto se sustituye
  por el nº de documento PG (propuesta de EVA) o se mantiene la línea completa.
- Nomenclatura de lote `AAMMDDCDI11xx`: cómo se traslada a `RFKKA00`/`p_runid`.
- Sociedad/motivo/cuenta fijos del DF vs. consulta a `ZFI_T_COBRO_CONF` (y si
  aplica un `tipo_cobro` propio para extornos, distinto de `DEV`).
- Traza en `ZFI_T_FILE_LOG`: proceso/`co_dev` a usar para extornos.
- Ruta lógica de fichero (`co_logical_path`): reutilizar
  `ZFICA_COBROS_DEVOLUCIONES` o crear una nueva para extornos.
- Alta del objeto en el sistema de transporte correspondiente al proyecto.
