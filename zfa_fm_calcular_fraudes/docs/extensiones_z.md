# Extensiones Z que afectan al cálculo y la facturación

Ampliaciones del sistema que se meten en medio al crear un cálculo manual o
al facturarlo. Si algo falla en estos pasos con un mensaje Z, mirar aquí
primero.

| Objeto | Cuándo salta | Qué hace | Qué nos exige | Error si falta |
|---|---|---|---|---|
| `ZFI_FM_ISU_SAMPLE_TE760` | Al **grabar** el cálculo (derivación CO-PA) | Rellena `WW001`/`WW002`. Busca en `x_bill_doc-ierchz` la línea `BELZART` `EPROD`/`GPROD`/`SPROD` y con su `ZTEXT` lee `ZFA_T_RATECAT` (`producto_sf = ztext`) | Copiar la línea de producto (tipo `IN` en `ZFA_FRAUD_CONC`) del cálculo original, también en la factura a 0 | `ZFA_MC_001/002` "No se ha encontrado el código de Producto" |
| `ZFA_FM_ISU_SAMPLE_R400` | Al **facturar** (evento R400, EA19 o masiva) | Saca la clase de documento de `t_bill_doc-erch-zserie_nod(1)`: `F` → `FE` (facturación normal), `R` → `RE`, `A` → `AE`, `S` → `SE`. Exporta la clase a memoria (`ZFA_BLART`, `ZFA_BLART1`) para el evento 1190 | `ERCH-ZSERIE_NOD` relleno en la cabecera del cálculo (hoy `FE`, a confirmar con Aleix) | "ERROR R400 - Campo ZSERIE_NOD Inválido en la cabecera …" (`ZFA_MC_001/002`) |
| Evento 1190 (FI-CA) | Al contabilizar la factura | Lee `ZFA_BLART`/`ZFA_BLART1` de memoria (los deja el R400) | Nada directo: depende de que el R400 haya ido bien | — |

## Customizing estándar que también hay que tener en cuenta

| Qué | Clave | Qué nos exige | Error si falta |
|---|---|---|---|
| Determinación de cuentas `R001` | `BUKRS`/`SPARTE`/`KOFIZ`/`HVORG`/`TVORG` | Cabecera de cálculo manual completa: `KOFIZ` (de `EVER`), `HVORG 0300`, `ABRVORG 06`, `BELEGART MN` | `>1 003`; con `x_no_message` se ve solo "Error al grabar" (`E9 063`) |
| Campo `KOFIZ` en cabecera | — | `ERCH-KOFIZ` de `EVER` y `ERCH-GPARTNER` de `FKKVKP` | "Indique un valor en el campo Caract.determin.ctas." |

## Campos Z de ERCH vistos en cálculos manuales de QA

| Campo | Valores vistos | Uso hoy |
|---|---|---|
| `ZSERIE_NOD` | `SE`, `AE`, `FE`, `RE` | Lo rellenamos con `FE` (`gc_serie_nod`) |
| `ZRECT_FORZADO` | — | No se rellena; preguntar a Aleix |
| `ZORIG_FACTURA` | — | No se rellena; preguntar a Aleix |
| `ZFECHA_OPER_CALC` | — | No se rellena; preguntar a Aleix |
| `ZORIG_FECHA_OPER` | — | No se rellena; preguntar a Aleix |

## Truco para ver el error real

`ISU_S_MANUBILL_CREATE` llama a `ISU_O_MANUBILL_ACTION` con
`x_no_message = 'X'`, que tapa el mensaje real con `E9 063` "Error al
grabar". Para verlo: break dentro del estándar en la llamada de grabación,
entrar y dar F7 hasta que salte el mensaje de verdad.
