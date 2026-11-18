# Plan de pruebas en QA

Parámetros comunes, salvo que se indique otra cosa:

| | Luz | Gas |
|---|---|---|
| Contrato | 3000275907 | 3000027670 |
| CUPS | ES0022000005703570WV0F | ES0217010117900163LD |
| Instalación | 6100385724 | 6100010125 |
| Factura ATR (`IV_NUM_FACTURA_ATR`) | J424010929097 | C388643557 |
| Periodo | 13.08.2024 – 12.09.2024 | 21.06.2024 – 22.08.2024 |
| Consumo total | 100 | 100 |
| Cuenta contrato | 2000157509 | 2000016381 |

- `IV_ID_PROCESO_ATR` ya no existe (eliminado el 18/11).
- `IV_NUM_FACTURA_ATR`: un `CODIGOFISCALFACTURA` real de
  `/IDXGC/PRST_INHD` **de la misma instalación** (la RFC valida que exista
  y que `INHD-ANLAGE` sea la instalación del contrato). Para buscarla:
  SE16N `/IDXGC/PRST_INHD` con `ANLAGE` = instalación y
  `CODIGOFISCALFACTURA` informado.
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
| PRUEBA020 | Luz fraude (tipo `11`) con validaciones nuevas | `0000` – 610000008981 / FE26390000002524 (cálculo 550000002628), 14,62 € |
| PRUEBA022 | Luz anomalía (tipo `06`) | `0000` – 610000008997 / FE26390000002537 (cálculo 550000002629), 14,62 € |
| PRUEBA025 (solo cálculo) | Gas fraude (`C388643557`) | `0010` – TV 8,71 + IEH 0,23 = 8,94 + IVA `R1` 21 % 1,88 = 10,82 € (igual que PRUEBA016) |
| PRUEBA025 | Gas fraude facturando | `0000` – 610000008999 / FE26390000002538 (cálculo 550000002630), 10,82 € |
| PRUEBA026 | Solo cálculo a 0 (forzado) | `0010` – `EREPOS` (100, `R1`) y `EPROD` a 0, total 0 |
| PRUEBA039 | Caducado (`ANT_FR_ELEC` de Madrid a 12 en QA) | `0111`, `DESCARTE - CADUCADO` |
| PRUEBA040A | Caducidad parcial (`ANT_FR_ELEC` a 27) | `0112`, caducado antes del 17.08.2024 |
| PRUEBA040B | Periodicidad (`PER_AN_ELEC` a 0, tipo `06`) | `0112`, se podría facturar desde el 13.09.2024 |
| PRUEBA028 | PDoc a `01` (gas, ATR `DOMD202403285546`, contrato 3000051281, 08.10–13.11.2024) | `0000` – 610000009005 / FE26390000002539 (cálculo 550000002631), 10,06 €; PDoc `00000000060009789492` de `02` a `01` |
| PRUEBA041 | Tarifa Plana (gas, contrato 3000027739, 02.09–01.10.2024) | `0107`, `DESCARTE - ANOMALIA TP` |
| PRUEBA021 | Solo cálculo luz (`J424010929097`) | `0010` – sin factura; neto 12,08 + IVA `R1` 21 % 2,54 = 14,62 € (igual que PRUEBA013) |

## Pendiente (código desde el 29/10)

| # | Caso | Entrada | Esperado | ✓ |
|---|---|---|---|---|
| 20 | Luz fraude | tipo `11` | `0000`, `FACTURACION TOTAL`, `ERCH-ORIGDOC = 40`, `ZSERIE_NOD = FE` | ✓ |
| 21 | Solo cálculo | tipo `11`, `IV_SOLO_CALCULO = X` | `0010`, `ET_LINEAS` con el detalle y una línea `IV` (21 %), `ET_FACTURAS-IMPORTE` = el total de la prueba 20 (con IVA), sin factura; nada nuevo en la EA22 | ✓ |
| 22 | Luz anomalía | tipo `06` | `0000`, `ORIGDOC = 41` | ✓ |
| 23 | Tipo de otra división | luz con tipo `FR` | `1004`, sin crear nada | ✓ |
| 24 | Factura ATR inexistente | `IV_NUM_FACTURA_ATR = PRUEBA` | `1004` no existe | ✓ |
| 24b | Factura ATR de otro CUPS | Una factura real de otro CUPS | `1004` no es del CUPS | ✓ |
| 25 | Gas fraude | gas, tipo `FR` | `0000`, `ORIGDOC = 40` | ✓ |
| 26 | Solo cálculo a 0 | `IV_FORZADO = X`, `IV_SOLO_CALCULO = X` | `0010`, líneas `EREPOS` + `EPROD` a 0 | ✓ |
| 28 | PDoc a `01` | Gas: factura ATR `DOMD202403285171` (PDoc `00000000060009789418` en `02`), instalación 6100231740, 12.10.2024–13.11.2024, tipo `FR`, facturando. Reserva: `DOMD202403285546` / 6100038968 / 21.11–06.12.2024 | `0000` y `EIDESWTDOC-STATUS = 01`. Con las facturas de consumo (PDoc ya en `01`) no cambia nada | ✓ |
| 27 | Expediente repetido | repetir el de la prueba 20 | `1006` | ✓ |

## Descartes (con `IV_SOLO_CALCULO = X` para no grabar nada)

Hace falta un contrato de QA para cada caso y un cálculo que cubra el
periodo del expediente.

| # | Descarte | Cómo encontrar un contrato | Esperado |
|---|---|---|---|
| 30 | Migrado | `EVER-XVERA = X`, periodo anterior a `EINZDAT_ALT` | `0101` |
| 31 | Exención | Contrato en `ZFA_T_CIE` vigente en el periodo | `0102` |
| 32 | Olvido | Interlocutor en `ZCO_T_OFUSC_CLIE-PARTNER` | `0103`, `DESCARTE - DERECHO AL OLVIDO` |
| 33 | Vital / vulnerable | `FKKVKP-ZZVULNERABLE_CC` informado, o `EANL-ZZVITAL` ≠ 00 con fechas en el periodo | `0104`, `DESCARTE - VULNERABILIDAD` |
| 34 | Bloqueo contrato | `EVER-ABRSPERR` informado | `0105` |
| 35 | Bloqueo cuenta contrato | `DFKKLOCKS` `LOTYP 06` vigente en el periodo | `0105` |
| 35b | Reposición | `ETTIFN` con operando `E_REPOSICI`/`G_REPOSICI` en el periodo | `0106`, `DESCARTE - REPOSICION` |
| 36 | Tarifa Plana | `EANLH-TARIFTYP` `E_PLANA`/`G_PLANA` en el periodo | `0107`, `DESCARTE - ANOMALIA TP` | ✓ |
| 37 | Sin cálculo original | Periodo sin cálculo del contrato | `0108` |
| 39 | Caducado | Expediente con `fecha_hasta` de hace más de 60 meses (36 en Barcelona/Gerona), con cálculo en ese periodo | `0111`, `DESCARTE - CADUCADO` | ✓ |
| 40 | Caducidad parcial / periodicidad | Anomalía (`06`/`AN`) de más de 12 meses, o periodo que empieza antes del límite de antigüedad | `0112` | ✓ |
| 38 | Empleado | `EANLH-TARIFTYP` `E_EMPLE`/`G_EMPLE` en el periodo | `0110`, `DESCARTE - EMPLEADO` |

## Sin probar por falta de datos o de definición

- Gas con conceptos ATR 1923/1924 (`PGINTR`/`PGIRAP`): falta una factura
  ATR de gas con esos conceptos y un cálculo plantilla en STVARV.
- Descuentos (luz y gas) y prorrateo por cambio de precio: los cálculos
  de prueba no los tienen. Solo cubiertos por ABAP Unit.

## Notas sobre las facturas ATR de QA

- Las 286 con `MOTIVOFACTURACION = 11` (exportadas el 16/11) son de **gas**
  (`DOMD…`, Madrileña Red de Gas), todas con el PDoc en `02`.
- 244 no tienen instalación en `/IDXGC/PRST_INHD` ni `POD` en
  `EIDESWTDOC`: no están ligadas a ningún suministro, así que la RFC las
  rechaza con `1004` (no es del CUPS). Las 42 restantes sí tienen las dos.
