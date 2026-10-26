# Extensiones Z que afectan al cálculo y la facturación

Ampliaciones del sistema que se meten en medio al crear un cálculo manual o
al facturarlo. Si algo falla en estos pasos con un mensaje Z, mirar aquí
primero.

| Objeto | Cuándo salta | Qué hace | Qué nos exige | Error si falta |
|---|---|---|---|---|
| `ZFI_FM_ISU_SAMPLE_TE760` | Al **grabar** el cálculo (derivación CO-PA) | Rellena `WW001`/`WW002`. Busca en `x_bill_doc-ierchz` la línea `BELZART` `EPROD`/`GPROD`/`SPROD` y con su `ZTEXT` lee `ZFA_T_RATECAT` (`producto_sf = ztext`) | Copiar la línea de producto (tipo `IN` en `ZFA_FRAUD_CONC`) del cálculo original, también en la factura a 0 | `ZFA_MC_001/002` "No se ha encontrado el código de Producto" |
| `ZFA_FM_ISU_SAMPLE_R400` | Al **facturar** (evento R400, EA19 o masiva) | Saca la clase de documento de `t_bill_doc-erch-zserie_nod(1)`: `F` → `FE` (facturación normal), `R` → `RE`, `A` → `AE`, `S` → `SE`. Exporta la clase a memoria (`ZFA_BLART`, `ZFA_BLART1`) para el evento 1190 | `ERCH-ZSERIE_NOD` relleno en la cabecera del cálculo (lo pone la exit `ZXBI1U01`, ver abajo) | "ERROR R400 - Campo ZSERIE_NOD Inválido en la cabecera …" (`ZFA_MC_001/002`) |
| Evento 1190 (FI-CA) | Al contabilizar la factura | Lee `ZFA_BLART`/`ZFA_BLART1` de memoria (los deja el R400) | Nada directo: depende de que el R400 haya ido bien | — |

## La serie: ZXBI1U01 (`EXIT_SAPLEA01_001`, ampliación `EBIA0001`)

Exit al final del cálculo, también del manual. Es la que manda en los
campos Z de `ERCH`:

1. **Funcionalidad 1:** copia siempre `X_OBJ-CUST` a los campos Z de
   `ERCH`. En un cálculo manual `CUST` va vacío, así que **pisa lo que le
   pasemos** en `BILL_DOC-ERCH`. Por eso los 550000002613/2614 salieron
   sin serie.
2. **Funcionalidad 2:** solo con `sy-tcode` = `EA16`/`EA17`. Un popup pide
   `ORIGDOC` (31-43) y la factura origen, y calcula:
   - serie: `40` fraude, `41` avería, `42` permuta → `F*`; 31 → `S*`;
     32 → `A*`; 33 → `R*`; 34 → `F*`
   - segunda letra según el `KOFIZ`: DP → E, DC → C, DE → I, DM → M
   - valida `KOFIZ` frente a la región de la dirección de suministro
     (`ZXX_FM_DIRECCION_SUMINISTRO`)
   - segundo popup con la fecha de operación (por defecto, hoy)
3. **Funcionalidad 3:** tabla passthrough `ZFA_T_PASSTHROGH`. No nos afecta.

**Solución:** la RFC calcula `ORIGDOC`, `ZSERIE_NOD` y `ZFECHA_OPER_CALC`
con la misma lógica y los deja en memoria (`ZFA_FRAUDES_ERCH`) alrededor de
`ISU_S_MANUBILL_CREATE`. Un bloque nuevo en la exit (funcionalidad 1B,
`src/ZXBI1U01_bloque_fraudes.abap`) los recoge después de la
funcionalidad 1. Sin nada en memoria no hace nada, así que el resto de
procesos no cambia.

**Probado en QA:** el cálculo 550000002616 sale con la serie y se factura
en EA19 (documento de impresión 620000001555).

## Descarte de la factura: validación ZCICLO (EA05)

Facturado en la EA19, el documento de impresión 620000001555 quedó
**apartado**: `ERDK-TOBRELEASD = X`, sin contabilizar en FI-CA y sin
nº oficial (`EXBEL` vacío). La EA19 lo da todo en verde.

- **Dónde se ve:** EA05 "Lista de documentos de cálculo y facturación
  apartados".
- **Motivo:** validación Z **`ZCICLO` "Factura ciclo>1año"**, parámetro
  365 días. El periodo facturado (2024) tiene más de un año.
- **Liberación:** en la EA05, botón "Liberar documento". **El documento
  apartado desaparece de ERDK y se crea uno definitivo con número nuevo.**
  En QA:

  | Qué | Número |
  |---|---|
  | Impresión apartado (provisional, rango 62…) | 620000001555 |
  | Impresión definitivo `ERDK-OPBEL` (rango 61…) | 610000008573 |
  | Documento FI-CA (FPL9, clase FE) | 60000022223 |
  | Nº oficial `ERDK-EXBEL` | FE26390000002190 |
  | `ERDK-TOTAL_AMNT` (con IVA) | 14,62 (12,08 neto + 21 %) |
- **Para la RFC:** el número provisional no sirve de salida, porque cambia
  al liberar. Si la factura se aparta, la RFC solo puede devolver el
  cálculo y un estado de pendiente de liberar.
- **Consecuencia:** casi todos los fraudes regularizan periodos antiguos,
  así que se apartarán siempre. Decisión (Aleix): **tienen que salir
  contabilizadas → la RFC libera** con `ISU_OUTSORT_INVOICE_RELEASE`.
  - Lo usa el programa de la EA05 (`FORM release_doc_inv`).
  - Documento entero: `X_OPBEL` sin `X_OUTCNSO`.
  - Devuelve el número nuevo en `Y_NEW_OPBEL` y hace `COMMIT` él mismo.
  - Con `X_CREATE_LOG = 'X'` abre su propio log y no lanza el
    `MESSAGE i138`.
  - Si libera en fondo (`y_batch` interno), `Y_NEW_OPBEL` puede venir
    vacío.
  - **Solo se libera si todos los apartados pendientes son `ZCICLO`**
    (`ERDO`: `OPBEL`, `OUTCNSO`, `VALIDAT_IN` = validación, `MANOUTS_IN` =
    apartado manual, `FREI_AM` = fecha de liberación). Cualquier otro
    motivo se deja para revisar en la EA05.

## Customizing estándar que también hay que tener en cuenta

| Qué | Clave | Qué nos exige | Error si falta |
|---|---|---|---|
| Determinación de cuentas `R001` | `BUKRS`/`SPARTE`/`KOFIZ`/`HVORG`/`TVORG` | Cabecera de cálculo manual completa: `KOFIZ` (de `EVER`), `HVORG 0300`, `ABRVORG 06`, `BELEGART MN` | `>1 003`; con `x_no_message` se ve solo "Error al grabar" (`E9 063`) |
| Campo `KOFIZ` en cabecera | — | `ERCH-KOFIZ` de `EVER` y `ERCH-GPARTNER` de `FKKVKP` | "Indique un valor en el campo Caract.determin.ctas." |

## Campos Z de ERCH vistos en cálculos manuales de QA

| Campo | Valores vistos | Uso hoy |
|---|---|---|
| `ZSERIE_NOD` | `SE`, `AE`, `FE`, `RE` | `F` + letra del KOFIZ, vía memoria y exit |
| `ZRECT_FORZADO` | — | Vacío: no es rectificativa |
| `ZORIG_FACTURA` | — | Vacío |
| `ZFECHA_OPER_CALC` | — | Hoy, como propone el popup de la EA16 |
| `ZORIG_FECHA_OPER` | — | Vacío |
| `ORIGDOC` (estándar) | 31-34, 40-42 | `40` fraude, `41` avería (tipo ATR 11) |

## Truco para ver el error real

`ISU_S_MANUBILL_CREATE` llama a `ISU_O_MANUBILL_ACTION` con
`x_no_message = 'X'`, que tapa el mensaje real con `E9 063` "Error al
grabar". Para verlo: break dentro del estándar en la llamada de grabación,
entrar y dar F7 hasta que salte el mensaje de verdad.

## Borrar un cálculo manual de prueba

Un cálculo manual **sin facturar** (sin documento de impresión) no se anula
por EA13 ni EA15: esas dos trabajan por documento de impresión. Se **borra
en la EA16** (cálculo manual) con el nº de documento de cálculo. Así se
quitó el 550000002613 de QA.

Hay que hacerlo antes de repetir una prueba en el mismo contrato y periodo.
Si no, `buscar_calculo_original` también encuentra el cálculo manual y
devuelve 0109.

Un cálculo manual **ya facturado** no se puede borrar en la EA16 ("se está
utilizando"). Se anula con la **EA13** sobre su documento de impresión
definitivo. Anula la factura **y el cálculo**: queda `ERCH-STORNODAT`
relleno y `buscar_calculo_original` ya no lo tiene en cuenta. Así se anuló
en QA la 610000008573 / 550000002616.
