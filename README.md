# ABAP

Repositorio de desarrollos ABAP/SAP. Cada carpeta de primer nivel es un
desarrollo independiente (normalmente derivado de un Diseño Funcional),
con su propio código fuente, documentación y README de instalación.

## Desarrollos

| Carpeta | Descripción |
|---|---|
| [`zfi_fm_paylot_reverse/`](zfi_fm_paylot_reverse/README.md) | RFC `ZFI_FM_PAYLOT_REVERSE`: anulación de transferencias contabilizadas en SAP (FI-CA), proceso `CDI_11_03` |
| [`zfi_fm_payment_lot_clarify2/`](zfi_fm_payment_lot_clarify2/README.md) | RFC `ZFI_FM_PAYMENT_LOT_CLARIFY2`: clarificación de transferencias pendientes en SAP (FI-CA) — **prueba end-to-end real superada** |
| [`zfi_r_ecofi_split/`](zfi_r_ecofi_split/README.md) | Report `ZFI_R_ECOFI_SPLIT`: división del fichero bancario ECOFI en transferencias/extornos, proceso `CDI_11` (1/3) — lógica de división probada contra ficheros reales |
| [`zfi_r_devoluciones_crea/`](zfi_r_devoluciones_crea/README.md) | Report `ZFI_R_DEVOLUCIONES_CREA`: creación del lote de devoluciones en FI-CA a partir del `_DEV`, proceso `CDI_11` (2/3) — **PARADO**: el código actual está sobre `RFKKA00`, pero el DF pide `FP09`; pendiente de depurar `FP09` antes de seguir |
| [`zfi_r_devoluciones2/`](zfi_r_devoluciones2/README.md) | Report `ZFI_R_DEVOLUCIONES2`: cierre y contabilización del lote de devolución de extornos, proceso `CDI_11` (3/3) — **copia base de `ZFI_R_DEVOLUCIONES` sin adaptar todavía** |
