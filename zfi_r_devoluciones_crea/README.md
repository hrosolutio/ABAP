# ZFI_R_DEVOLUCIONES_CREA — Creación del lote de devoluciones (CDI_11)

Implementa **RU_02** del DF *"Procedimiento Gestión de extornos"* (CDI_11):
a partir del fichero `_DEV` (salida de [`zfi_r_ecofi_split/`](../zfi_r_ecofi_split/README.md),
desarrollo 1), crea el lote de devoluciones en FI-CA.

Es el desarrollo 2 de 3 del proyecto CDI_11:
1. **División del fichero ECOFI** → [`zfi_r_ecofi_split/`](../zfi_r_ecofi_split/README.md)
2. **Creación del lote de devoluciones** → este programa.
3. **Cierre y contabilización del lote** → [`zfi_r_devoluciones2/`](../zfi_r_devoluciones2/README.md)

## Estado: PARADO, pendiente de depurar `FP09`

El DF pide expresamente la transacción **`FP09`** (alta manual de lote de
pago) para RU_02. El código que hay hoy en `src/` está construido sobre
`RFKKA00`/`FPB17` (el motor de carga masiva de extractos bancarios) por una
lectura incorrecta del DF — **no es el camino a seguir**. Ver
`docs/DF_resumen.md` ("Enfoque actual" / "Enfoque descartado") para el
detalle completo.

**Antes de tocar más código hace falta depurar `FP09` en SAP** (mismo método
que ya funcionó para `zfi_fm_paylot_reverse`/`FP08` y
`zfi_fm_payment_lot_clarify2`/`FPCPL`) para encontrar la cadena real de
módulos de función que crea el lote — eso es trabajo que requiere acceso al
sistema y no se puede hacer desde aquí.

**Lo que sí sigue sirviendo** del código actual, independientemente del
motor de creación del lote:
- El parseo del `_DEV` (extraer nº de documento SAP e importe de cada línea
  de extorno) — en `ZFI_R_DEVOLUCIONES_CREA_CLS`, métodos `parse_dev_lines`/
  `format_amount`.
- El escaneo de ficheros `*_DEV*` en servidor y la traza en
  `ZFI_T_FILE_LOG` (`get_dev_files`, `get_directories`, `transport_files`).

**Lo que probablemente sobra** si se confirma la vía `FP09`: todo el
generador de `AUSZUG`/`UMSATZ` (`build_auszug`, `build_umsatz`,
`date_dots`/`date_spaces`) y la llamada a `RFKKA00` (`submit_rfkkka00`).

## Contenido del repositorio

```
src/
  ZFI_R_DEVOLUCIONES_CREA.abap        Programa principal (REPORT)
  ZFI_R_DEVOLUCIONES_CREA_TOP.abap    Include TOP
  ZFI_R_DEVOLUCIONES_CREA_EVE.abap    Include EVE (pantalla de selección)
  ZFI_R_DEVOLUCIONES_CREA_CLS.abap    Include CLS (clase lcl_devoluciones_crea) — construido sobre RFKKA00, pendiente de rehacer sobre FP09
docs/
  DF_resumen.md                        Resumen del Diseño Funcional, incluyendo por qué se descartó RFKKA00
```

## Próximo paso

1. Depurar `FP09` en SAP (Integración o DES) hasta localizar la cadena real
   de módulos de función que crea la cabecera del lote (`DFKKZK`) y sus
   posiciones (`DFKKZP`), siguiendo el método de
   `../zfi_fm_paylot_reverse/README.md`.
2. Con esa cadena localizada, reescribir `ZFI_R_DEVOLUCIONES_CREA_CLS` para
   llamarla directamente desde ABAP con los datos del `_DEV` (sociedad
   `1239`, motivo `Z01`, cta. compensación `4305500150`, una posición por
   línea con importe + nº de documento), sin generar ningún fichero
   intermedio.
