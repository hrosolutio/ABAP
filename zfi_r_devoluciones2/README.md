# ZFI_R_DEVOLUCIONES2 — Cierre y contabilización del lote de devolución de extornos (CDI_11)

**Estado: cadena real de FMs confirmada por depuración, código pendiente de reescribir.**
El código fuente sigue siendo la copia literal de `ZFI_R_DEVOLUCIONES` (solo
renombrado: report, includes y clase `lcl_devoluciones` → `lcl_devoluciones2`),
pero **ya no es el punto de partida** — igual que pasó con el desarrollo 2
(`zfi_r_devoluciones_crea/`), la sugerencia original de EVA de reutilizar el
motor `RFKKKA00` de `ZFI_R_DEVOLUCIONES` resultó ser una lectura incorrecta
del DF. Depurando `FP09` sobre lotes reales creados por
`ZFI_R_DEVOLUCIONES_CREA`, se confirmó que "Cerrar"/"Contabilizar" llaman
directamente a `FKK_RLS_CLOSE`/`FKK_RLS_POST_LOT` (grupo de función `FKR2`,
el mismo que usa el desarrollo 2) — ver `docs/DF_resumen.md` para las firmas
exactas y las pruebas reales.

Es uno de los 3 desarrollos del proyecto CDI_11:
1. **División del fichero ECOFI** en transferencias/extornos → [`zfi_r_ecofi_split/`](../zfi_r_ecofi_split/README.md)
2. **Creación del lote de devoluciones** → [`zfi_r_devoluciones_crea/`](../zfi_r_devoluciones_crea/README.md), ya reescrito y probado con éxito.
3. **Cierre y contabilización del lote** → este programa (`ZFI_R_DEVOLUCIONES2`).

Ver `docs/DF_resumen.md` para el detalle completo: la cadena real de FMs
confirmada, y el plan de reescritura (todavía sin implementar).

## Contenido del repositorio

```
src/
  ZFI_R_DEVOLUCIONES2.abap        Programa principal (REPORT) - todavía copia sin adaptar
  ZFI_R_DEVOLUCIONES2_TOP.abap    Include TOP (tipos y datos globales)
  ZFI_R_DEVOLUCIONES2_EVE.abap    Include EVE (pantalla de selección)
  ZFI_R_DEVOLUCIONES2_CLS.abap    Include CLS (clase lcl_devoluciones2) - todavía copia sin adaptar
docs/
  DF_resumen.md               Resumen del Diseño Funcional + cadena real de FMs (FKK_RLS_CLOSE/FKK_RLS_POST_LOT)
```

## Plan (resumen — ver `docs/DF_resumen.md` para el detalle)

Este programa **no crea ningún lote** — opera sobre lotes que ya existen
(creados por `zfi_r_devoluciones_crea/`, con el `KEYR1` trazado en
`ZFI_T_FILE_LOG`). Por cada lote pendiente:

1. `CALL FUNCTION 'FKK_RLS_CLOSE' EXPORTING i_keyr1 = ...` (cerrar).
2. `CALL FUNCTION 'FKK_RLS_POST_LOT' EXPORTING i_keyr1 = ...` (contabilizar).
3. Si alguna de las dos falla (`sy-subrc <> 0`), marcar el registro de
   `ZFI_T_FILE_LOG` correspondiente como error (sin desglose por documento
   — quien lo necesite entra a `FP09` con el nº de lote) y seguir con el
   siguiente lote, sin reintentar ni corregir nada automáticamente.

No hace falta leer ningún `_DEV`, generar `AUSZUG`/`UMSATZ`, ni fijar
sociedad/motivo/cuenta (ya se fijaron al crear el lote) — todo eso
pertenece al motor `RFKKKA00`/`ZFI_R_DEVOLUCIONES` descartado.

## Pendiente

- Reescribir `ZFI_R_DEVOLUCIONES2_CLS` desde cero sobre este plan — sigue
  siendo la copia literal sin adaptar de `ZFI_R_DEVOLUCIONES`.
- Probar una contabilización real con éxito (en DES la mayoría de
  documentos del `_DEV` de prueba no existen — ver `docs/DF_resumen.md`;
  probar en Integración o con documentos reales de DES).
- Alta del objeto en el sistema de transporte correspondiente al proyecto.
