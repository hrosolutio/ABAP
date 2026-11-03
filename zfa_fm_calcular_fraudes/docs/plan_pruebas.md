# Plan de pruebas en QA

Parámetros comunes, salvo que se indique otra cosa:

| | Luz | Gas |
|---|---|---|
| Contrato | 3000275907 | 3000027670 |
| CUPS | ES0022000005703570WV0F | (el del contrato, `EUIINSTLN` + `EUITRANS`) |
| Periodo | 13.08.2024 – 12.09.2024 | 21.06.2024 – 22.08.2024 |
| Consumo total | 100 | 100 |
| Cuenta contrato | 2000157509 | 2000016381 |

- `IV_NUM_FACTURA_ATR`: un `CODIGOFISCALFACTURA` real de
  `/IDXGC/PRST_INHD` (la RFC valida que exista).
- `IV_ID_EXPEDIENTE`: uno nuevo en cada prueba. Los que acaban en
  `0000`/`0001`/`0003` no se pueden repetir (`1006`).
- Después de cada prueba que factura, anular la factura en la EA13 antes
  de la siguiente del mismo contrato (si no, `0109`).

## Ya probado

| Expediente | Caso | Resultado |
|---|---|---|
| PRUEBA013 | Luz normal, apartada por `ZCICLO` y liberada | `0000` – 610000008701 / FE26390000002313, 14,62 € |
| PRUEBA014 | Luz a 0 (`IV_FORZADO`) | `0001` – 610000008705 / FE26390000002316 |
| PRUEBA015 | Gas a 0 (`IV_FORZADO`) | `0001` – 610000008717 / FE26390000002327 |
| PRUEBA016 | Gas normal | `0000` – 610000008719 / FE26390000002328, 10,82 € |

## Pendiente (código desde el 29/10)

| # | Caso | Entrada | Esperado | ✓ |
|---|---|---|---|---|
| 20 | Luz fraude | tipo `11` | `0000`, `FACTURACION TOTAL`, `ERCH-ORIGDOC = 40`, `ZSERIE_NOD = FE` | |
| 21 | Solo cálculo | tipo `11`, `IV_SOLO_CALCULO = X` | `0010`, `ET_LINEAS` con el detalle, `ET_FACTURAS` sin factura; nada nuevo en la EA22 | |
| 22 | Luz anomalía | tipo `06` | `0000`, `ORIGDOC = 41` | |
| 23 | Tipo de otra división | luz con tipo `FR` | `1004`, sin crear nada | |
| 24 | Factura ATR inexistente | `IV_NUM_FACTURA_ATR = PRUEBA` | `1004` | |
| 25 | Gas fraude | gas, tipo `FR` | `0000`, `ORIGDOC = 40` | |
| 26 | Solo cálculo a 0 | `IV_FORZADO = X`, `IV_SOLO_CALCULO = X` | `0010`, líneas `EREPOS` + `EPROD` a 0 | |
| 27 | Expediente repetido | repetir el de la prueba 20 | `1006` | |

## Descartes (con `IV_SOLO_CALCULO = X` para no grabar nada)

Hace falta un contrato de QA para cada caso y un cálculo que cubra el
periodo del expediente.

| # | Descarte | Cómo encontrar un contrato | Esperado |
|---|---|---|---|
| 30 | Migrado | `EVER-XVERA = X`, periodo anterior a `EINZDAT_ALT` | `0101` |
| 31 | Exención | Contrato en `ZFA_T_CIE` vigente en el periodo | `0102` |
| 32 | Olvido | Interlocutor en `ZCO_T_OFUSC_CLIE-PARTNER` | `0103`, `DESCARTE - DERECHO AL OLVIDO` |
| 33 | Vital / vulnerable | `EANL-ZZVITAL` o `ZZVULNERABLE` con fechas en el periodo | `0104`, `DESCARTE - VULNERABILIDAD` |
| 34 | Bloqueo contrato | `EVER-ABRSPERR` informado | `0105` |
| 35 | Bloqueo cuenta contrato | `DFKKLOCKS` `LOTYP 06` vigente en el periodo | `0105` |
| 36 | Tarifa Plana | `EANLH-TARIFTYP` `E_PLANA`/`G_PLANA` en el periodo | `0107`, `DESCARTE - ANOMALIA TP` |
| 37 | Sin cálculo original | Periodo sin cálculo del contrato | `0108` |

## Sin probar por falta de datos o de definición

- Gas con conceptos ATR 1923/1924 (`PGINTR`/`PGIRAP`): falta una factura
  ATR de gas con esos conceptos y un cálculo plantilla en STVARV.
- Descuentos (luz y gas) y prorrateo por cambio de precio: los cálculos
  de prueba no los tienen. Solo cubiertos por ABAP Unit.
- Reposición (`0106`): falta el operando.
