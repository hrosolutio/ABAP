# ZFI_R_DEVOLUCIONES2 — Cierre y contabilización del lote de devolución de extornos (CDI_11)

**Estado: reescrito sobre `FKK_RLS_CLOSE`/`FKK_RLS_POST_LOT`, pendiente de probar.**
Ya no es la copia de `ZFI_R_DEVOLUCIONES` — igual que pasó con el desarrollo 2
(`zfi_r_devoluciones_crea/`), la sugerencia original de EVA de reutilizar el
motor `RFKKKA00` resultó ser una lectura incorrecta del DF. Depurando `FP09`
sobre lotes reales creados por `ZFI_R_DEVOLUCIONES_CREA`, se confirmó que
"Cerrar"/"Contabilizar" llaman directamente a `FKK_RLS_CLOSE`/
`FKK_RLS_POST_LOT` (grupo de función `FKR2`, el mismo que usa el desarrollo
2) — ver `docs/DF_resumen.md` para las firmas exactas y las pruebas reales.

Es uno de los 3 desarrollos del proyecto CDI_11:
1. **División del fichero ECOFI** en transferencias/extornos → [`zfi_r_ecofi_split/`](../zfi_r_ecofi_split/README.md)
2. **Creación del lote de devoluciones** → [`zfi_r_devoluciones_crea/`](../zfi_r_devoluciones_crea/README.md), ya reescrito y probado con éxito.
3. **Cierre y contabilización del lote** → este programa (`ZFI_R_DEVOLUCIONES2`).

## Cómo funciona

Este programa **no lee ningún fichero** ni crea nada — opera sobre lotes que
ya existen (creados por `zfi_r_devoluciones_crea/` en modo **Server**, único
modo que deja traza en `ZFI_T_FILE_LOG` con el `KEYR1` del lote en
`FILE_NAME_HEADER`). Por cada registro pendiente
(`BUSINESS_DESC = 'EXT'`, `STATUS = 'PROCESADO'`):

1. Lee `DFKKRK-STARS` del lote (estado real en FI-CA — es la fuente de
   verdad, no `ZFI_T_FILE_LOG-STATUS`, cuyo dominio fijo no distingue
   "cerrado" de "contabilizado").
2. Si está abierto (`STARS` en blanco) → `FKK_RLS_CLOSE`.
3. Si está cerrado sin contabilizar (`STARS = 1`, incluido justo después
   de cerrarlo en el paso anterior) → `FKK_RLS_POST_LOT`.
4. Si ya está contabilizado del todo (`STARS = 5`) → no se toca.
5. Cualquier otro `STARS` (`2`/`3`/`4`/`6`/`9`, contabilización
   incompleta/con incidencias/archivado) → no se toca, se deja constancia
   en pantalla para revisión manual — **sin reintento ni corrección
   automática**.

Parámetro de selección único: **`P_SIMU`** (checkbox) — si se marca, el
programa solo escribe el `STARS` actual de cada lote pendiente, sin cerrar
ni contabilizar nada de verdad.

## Contenido del repositorio

```
src/
  ZFI_R_DEVOLUCIONES2.abap        Programa principal (REPORT)
  ZFI_R_DEVOLUCIONES2_TOP.abap    Include TOP (vacío)
  ZFI_R_DEVOLUCIONES2_EVE.abap    Include EVE (solo P_SIMU)
  ZFI_R_DEVOLUCIONES2_CLS.abap    Include CLS (clase lcl_devoluciones2) — sobre FKK_RLS_CLOSE/FKK_RLS_POST_LOT
docs/
  DF_resumen.md                   Resumen del Diseño Funcional + cadena real de FMs confirmada por depuración
```

## Pendiente de probar

- **Confirmar el campo `BUSINESS_DESC`** de `ZFI_T_FILE_LOG`: se asume que
  ahí es donde `zfi_cl_update_file_log` guarda el `iv_process` (`'EXT'`)
  que le pasa `ZFI_R_DEVOLUCIONES_CREA` — deducción razonable de los
  campos de la tabla, pero no confirmada con un registro real todavía.
- **No hay ningún registro de prueba disponible ahora mismo**: todas las
  pruebas de `ZFI_R_DEVOLUCIONES_CREA` se han hecho en modo **Upload**,
  que no deja traza en `ZFI_T_FILE_LOG` (a propósito, documentado así). Solo
  el modo **Server** (bloqueado por la ruta lógica `ZFICA_COBROS_ECOFI`,
  que no existe en ningún sistema) deja el `KEYR1` trazado. Para probar
  este programa ahora, hay que insertar una fila de prueba a mano en
  `ZFI_T_FILE_LOG` apuntando a un lote real ya creado (p.ej. `260825CDI111`,
  cerrado pero sin contabilizar — `STARS = 1`).
- Alta del objeto en el sistema de transporte correspondiente al proyecto.
