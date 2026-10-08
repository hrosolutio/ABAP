# ZFA_FM_CALCULAR_FRAUDES — Facturación automática de averías y fraudes

Implementación del servicio RFC descrito en el Diseño Funcional
*"Automatización de averías y fraude"* (v1.0, ver [`docs/DF_resumen.md`](docs/DF_resumen.md)).

Recibe un expediente de fraude o avería ya resuelto por la distribuidora
(factura ATR 06/11), valida que se pueda facturar automáticamente y crea un
cálculo manual con los precios del cálculo original del cliente. Lo llama
desde fuera un proceso de IA.

Plazo: **final de noviembre de 2026**.

## Estado

Reescrito desde cero a partir de la versión inicial de Aleix (generada con
IA, no compilaba y tiraba de tablas y FM inexistentes). Se ha aprovechado el
flujo general y las validaciones de CUPS / contrato.

| Bloque | Estado |
|---|---|
| Interfaz RFC | Hecha (cambios respecto a la de partida, ver más abajo) |
| Validaciones de entrada 1.1-1.3 | Hechas |
| Validación 1.4 (factura ATR) | Tipo 06/11 hecho; existencia **TODO** |
| Validación 1.5 (consumo ATR) | **TODO**, pendiente de definir en el DF |
| Validaciones de integridad 2.1-2.5 | **TODO**, falta el origen de cada dato |
| Validación 2.6 (reposición) | Hecha, falta el operando |
| Validación 2.7 (Tarifa Plana) | Hecha: tipo de tarifa `E_PLANA` / `G_PLANA` en `EANLH` |
| Búsqueda del cálculo original | Hecha, campos de ERCH por verificar |
| Lectura de líneas del cálculo | Hecha: `DBERCHZ1..8` juntadas en `ERCHZ` |
| Cálculo luz (energía, prorrateo, descuentos, IEE, potencia) | Hecho, con ABAP Unit |
| Cálculo gas (TV, prorrateo, descuentos, hidrocarburos) | Hecho; conceptos 1923/1924 **TODO** |
| Factura a 0 (descarte / titular) | Hecho hasta la creación del cálculo |
| Creación del cálculo manual | Hecha con `ISU_S_MANUBILL_CREATE`, heredando las líneas originales; falta probar en el sistema y las líneas sin original (EREPOS/GREPOS, PGINTR/PGIRAP, mínimo IEE nuevo) |
| **Facturación del cálculo** (documento de impresión y oficial) | **TODO** |
| Log y control de expediente duplicado | Hecho |
| Mensaje en el formulario | Pendiente |

> ⚠️ Los TODO de validación devuelven "no bloquea" para poder probar el
> resto del flujo. **No pasar a QA hasta cerrarlos**: si no, se facturarían
> casos que deberían descartarse.

## Contenido

```
src/
  ZFA_FM_CALCULAR_FRAUDES.abap               Módulo de función RFC (solo traslada parámetros)
  ZCL_FA_CALCULO_FRAUDES.abap                Clase con toda la lógica
  ZCL_FA_CALCULO_FRAUDES.testclasses.abap    ABAP Unit de la parte de cálculo
  ZCX_FA_FRAUDES.abap                        Excepción con código y descripción de resultado
docs/
  DF_resumen.md                              Resumen del Diseño Funcional
```

## Interfaz del servicio

| Parámetro | Dirección | Tipo | Obligatorio | Descripción |
|---|---|---|---|---|
| `IV_CUPS` | Import | `EXT_UI` | Sí | CUPS |
| `IV_FECHA_DESDE` | Import | `DATS` | Sí | Inicio del periodo del expediente |
| `IV_FECHA_HASTA` | Import | `DATS` | Sí | Fin del periodo del expediente |
| `IV_CONSUMO_P1` … `P6` | Import | `MENGE_D` | No | Consumo por periodo (luz con energía por periodos) |
| `IV_CONSUMO_TOTAL` | Import | `MENGE_D` | Sí | Consumo total (kWh) |
| `IV_NUM_FACTURA_ATR` | Import | `ZLE_DE_FACTUR` | Sí | Nº de factura ATR |
| `IV_TIPO_FACTURA_ATR` | Import | `CHAR2` | Sí | `06` u `11` |
| `IV_CONTRATO_SAP` | Import | `VERTRAG` | Sí | Contrato |
| `IV_ID_PROCESO_ATR` | Import | `CHAR2` | Sí | ID de proceso de la factura ATR (tipo por confirmar) |
| `IV_DESCARTE` | Import | `XFELD` | No | Facturar a 0 un caso descartado |
| `IV_MARCA_TITULAR` | Import | `XFELD` | No | Titular erróneo: facturar a 0 |
| `IV_ID_EXPEDIENTE` | Import | `ZLE_DE_NUMEROEXPEDIENTE` | Sí | Nº de expediente |
| `EV_RESULTADO` | Export | `CHAR2` | — | `OK` / `KO` |
| `EV_CODIGO` | Export | `CHAR4` | — | Código numérico (tabla siguiente) |
| `EV_DESCRIPCION` | Export | `STRING` | — | Descripción del resultado |
| `EV_MODO_FACTURACION` | Export | `CHAR30` | — | `NORMAL`, `IMPORTE_CERO_DESCARTE`, `IMPORTE_CERO_TITULAR` o vacío |
| `ET_FACTURAS` | Export | `ZFA_T_FRAUDES_FACTURA` | — | Factura, cálculo, consumo, importe, documento oficial y fechas |

### Cambios respecto a la interfaz de partida

- `IV_CONSUMO_P1..P6`: opcionales, como dice el DF, y tipados con `MENGE_D`
  (antes `MENGE`, que es una cantidad de maestro de material).
- `IV_DESCARTE`: `XFELD` opcional (antes `CHAR2` obligatorio).
- `IV_MARCA_TITULAR`: nuevo, no existía.
- `EV_RESULTADO` pasa a ser `OK`/`KO` y el código va en `EV_CODIGO` (nuevo).
  Antes todo iba en un `CHAR4` y los descartes devolvían `0000`, igual que
  una factura creada, así que la IA no podía distinguirlos.
- `ET_FACTURAS`: nuevo, es la tabla de salida del DF.

## Códigos de resultado

| Código | Resultado | Significado |
|---|---|---|
| `0000` | OK | Factura creada |
| `0001` | OK | Factura a importe 0 creada (flag descarte) |
| `0002` | OK | Factura a importe 0 creada (titular erróneo) |
| `0101` | OK | Descarte: periodo migrado (Uptility / NI) |
| `0102` | OK | Descarte: exención de impuestos |
| `0103` | OK | Descarte: derecho al olvido |
| `0104` | OK | Descarte: vulnerable / esencial |
| `0105` | OK | Descarte: contrato o cuenta contrato bloqueados |
| `0106` | OK | Descarte: operando de reposición activo |
| `0107` | OK | Descarte: Tarifa Plana |
| `0108` | OK | Descarte: no hay cálculo para el periodo |
| `0109` | OK | Descarte: el periodo abarca varios cálculos |
| `1000` | KO | Falta un parámetro obligatorio |
| `1001` | KO | El CUPS no existe |
| `1002` | KO | El contrato no existe o no corresponde al CUPS |
| `1003` | KO | El contrato no está activo en el periodo |
| `1004` | KO | Factura ATR inexistente o de tipo distinto de 06/11 |
| `1005` | KO | El consumo no cuadra con la factura ATR |
| `1006` | KO | El expediente ya está facturado |
| `1007` | KO | Fecha desde posterior a fecha hasta |
| `1008` | KO | Contrato con energía por periodos sin consumos P1-P6 |
| `2001` | KO | El cálculo original no tiene conceptos configurados |
| `2002` | KO | Falta un dato para calcular (precio, concepto, factor IEE…) |
| `2003` | KO | Error creando el cálculo manual |
| `2005` | KO | Contrato bloqueado por otro proceso (`FOREIGN_LOCK`) |

Los códigos son una propuesta: **confirmarlos con Aleix**, que la IA tiene
que saber interpretarlos.

## Lógica implementada

1. **Validaciones de entrada**:
   - Obligatorios y coherencia de fechas.
   - Expediente no facturado ya (tabla de log).
   - CUPS en `EUITRANS` y contrato en `EVER`.
   - Instalación del contrato asociada al CUPS en `EUIINSTLN`. Las dos
     tablas dependen del tiempo, así que se filtra por el periodo.
   - Contrato activo en todo el periodo (`EINZDAT`/`AUSZDAT`).
   - Tipo de factura ATR 06/11.
2. **Flag de descarte o marca de titular**: se factura a 0 con
   `EREPOS`/`GREPOS` y el consumo total, **sin** pasar las validaciones de
   integridad. Si las pasara, el caso se volvería a descartar y nunca se
   podría facturar a 0 (fallo de la versión de partida). Pendiente de
   confirmar con Aleix.
3. **Validaciones de integridad**: cada descarte lanza su código `01xx`.
   Reposición (`ETTIFN` por instalación y operando) y Tarifa Plana (`EANLH`
   por tipo de tarifa) están hechas; el resto, TODO.
4. **Cálculo original**: `ERCH` del contrato que solapa con el periodo, sin
   anular ni simular. Si no hay ninguno, `0108`; si hay varios, `0109`
   (el DF no dice qué hacer).
5. **Líneas del cálculo**: cada línea `ERCHZ` está repartida en
   `DBERCHZ1..8` con clave `BELNR` + `BELZEILE`. Se leen de forma dinámica
   (la que no exista en el release se salta) y se juntan en una `ERCHZ` por
   línea. Se guardan enteras para heredarlas en el cálculo manual. Para
   calcular se usan `BELZART`, `AB`, `BIS`, `I_ABRMENGE` (cantidad),
   `PREISBTR` (precio) y `NETTOBTR` (importe). Solo cuentan las líneas cuyo
   concepto está en `ZFA_FRAUD_CONC`, que dice qué es cada concepto. Así no
   hay códigos de concepto inventados metidos en el código.
6. **Prorrateo** (luz y gas): el consumo se reparte entre las fracciones de
   precio del cálculo original según los días de cada fracción **que caen
   dentro del periodo del expediente**. El resto del redondeo va a la última
   fracción, para que la suma cuadre exactamente con el consumo.
7. **Luz**:
   - Energía agrupada si algún concepto de energía no tiene periodo; si no,
     por periodo con los consumos P1-P6.
   - Descuentos en la misma proporción descuento/base que en el original.
   - IEE: el % del original sobre la energía neta de descuentos, frente al
     mínimo (kWh / 1000 × 1 €); se queda el mayor. El concepto de mínimo
     sale del propio original o de `ZFA_FRAUD_CONC-BELZART_REL`.
   - La potencia mayor (por kW, no por importe) a importe 0.
8. **Gas**:
   - Término variable prorrateado.
   - Descuentos igual que en luz.
   - Hidrocarburos con el precio de la línea del original (es el vigente a
     su fecha de creación).
   - Conceptos 1923/1924 del ATR → `PGINTR`/`PGIRAP`.
9. **Creación del cálculo manual**: `ISU_S_MANUBILL_CREATE` (grupo `EA16`)
   en modo sin diálogo:
   - `X_NO_DIALOG = 'X'` y `X_AUTO` (`ISU20_MANUBILL_AUTO`, type pool
     `ISU20`) con `BILL_DOC_USE = 'X'`. **Sin ese flag el FM no hace nada y
     no da error.**
   - Las líneas van en `X_AUTO-BILL_DOC-IERCHZ` (estructura `ERCHZ`). Cada
     una se combina con `X_AUTO-REA16` (`FILL_OBJ_REA16_DATA`) y se valida
     con `ISU_O_MANUBILL_INPUT`, como si se tecleara en EA20.
   - `FILL_OBJ_REA16_DATA` monta `REA16` con `MOVE-CORRESPONDING` en este
     orden: `X_AUTO-REA16`, después la línea `ERCHZ` y después
     `BILL_DOC-ERCH`. Por eso **la cabecera va en `BILL_DOC-ERCH`**:
     contrato, sociedad, división, cuenta contrato y periodo. Lo que se
     ponga en `REA16` con nombre de campo de `ERCH` se pisa aunque `ERCH`
     venga vacío. En `REA16` solo va lo propio de pantalla (`STICHTAG`).
   - La cantidad va en **`ERCHZ-I_ABRMENGE`**: el FORM la pasa a
     `MENGE`/`ABRMENGE` (con `ISU_METER_IDDATA_TRANSFORM`), fija
     `ABRFAKT = 1` y toma la unidad de `MASSBILL`.
   - Cada línea parte de la **línea original** (misma operación `TVORG`,
     tarifa, unidad, IVA, moneda…) y solo se cambian `BELZEILE`, `BELZART`,
     fechas, cantidad, precio e importe, como pide el DF.
   - Él mismo bloquea el contrato (`FOREIGN_LOCK` → `2005`). El bloqueo de
     facturación (`BILL_LOCK`) se trata como el descarte `0105`.
   - Marca `ERCH-MANBILLREL`, así que en principio queda liberado y no
     hace falta `ISU_S_MANUBILL_RELEASE` (confirmar en la prueba).
   - Graba `EITR` (pendiente de facturar). El `COMMIT` lo hace nuestro
     `registrar_log`. Solo hace `COMMIT` interno si `ERCH-NINVOICE` está
     marcado, que no es nuestro caso.
   - Devuelve el `BELNR` en `Y_NEW_BILL_DOC-ERCH-BELNR`.
10. **Transacción**: si algo falla se hace `ROLLBACK`. Siempre se graba una
    línea en `ZFA_FRAUD_LOG` y se hace el `COMMIT` al final.

## Objetos DDIC a crear (SE11)

**Estructura `ZFA_S_FRAUDES_FACTURA`** + tipo de tabla **`ZFA_T_FRAUDES_FACTURA`**:

| Campo | Tipo | Comentario |
|---|---|---|
| `FACTURA` | mismo elemento de datos que `ERDK-OPBEL` | Documento de impresión |
| `CALCULO` | mismo elemento de datos que `ERCH-BELNR` | Cálculo manual creado |
| `DOC_OFICIAL` | TODO | Nº de documento oficial; ver dónde se guarda en vuestro sistema |
| `CONSUMO` | `DEC 15,3` (tipo predefinido) | Evita el campo de referencia de unidad de un `QUAN` |
| `IMPORTE` | `BETRW_KK` | Referencia a `WAERS` |
| `WAERS` | `WAERS` | |
| `FECHA_DESDE` | `DATUM` | |
| `FECHA_HASTA` | `DATUM` | |

**Tabla `ZFA_FRAUD_CONC`** (customizing, mantenible con SM30): qué es cada
concepto del cálculo.

| Campo | Clave | Tipo | Comentario |
|---|---|---|---|
| `MANDT` | X | `MANDT` | |
| `SPARTE` | X | `SPARTE` | División |
| `BELZART` | X | mismo que `DBERCHZ1-BELZART` | Concepto |
| `TIPO` | | `CHAR2` | `EN` energía, `PO` potencia, `IE` IEE, `IM` IEE mínimo, `DE` descuento, `TV` término variable, `IH` hidrocarburos |
| `PERIODO` | | `CHAR2` | `P1`..`P6` para energía por periodos; vacío si es agrupada |
| `BELZART_REL` | | mismo que `DBERCHZ1-BELZART` | En los `IE`: su concepto de mínimo comunitario (misma región) |

**Tabla `ZFA_FRAUD_LOG`** (log de llamadas y control de duplicados):

| Campo | Clave | Tipo |
|---|---|---|
| `MANDT` | X | `MANDT` |
| `ID_EXPEDIENTE` | X | `ZLE_DE_NUMEROEXPEDIENTE` |
| `TSTAMP` | X | `TIMESTAMPL` |
| `CUPS` | | `EXT_UI` |
| `VERTRAG` | | `VERTRAG` |
| `RESULTADO` | | `CHAR2` |
| `CODIGO` | | `CHAR4` |
| `DESCRIPCION` | | `CHAR255` |
| `MODO` | | `CHAR30` |
| `BELNR` | | mismo que `ERCH-BELNR` |
| `OPBEL` | | mismo que `ERDK-OPBEL` |
| `UNAME` | | `SYUNAME` |

## Instalación

1. Crear en SE11 los objetos DDIC del apartado anterior.
2. SE24: crear `ZCX_FA_FRAUDES` (clase de excepción, hereda de
   `CX_STATIC_CHECK`, sin clase de mensajes) y pegar el código en el editor
   basado en fuente.
3. SE24: crear `ZCL_FA_CALCULO_FRAUDES` y pegar el código; en *Clases de
   test locales*, pegar `ZCL_FA_CALCULO_FRAUDES.testclasses.abap`.
4. SE37: en la `ZFA_FM_CALCULAR_FRAUDES` existente, ajustar la interfaz a la
   tabla de arriba y sustituir el código fuente (los FORMs de la versión de
   partida se borran).
5. Ejecutar el ABAP Unit de la clase (Ctrl+Shift+F10).

Comprobado con abaplint (sintaxis 7.40 SP08) sin los objetos DDIC; la
activación real en el sistema es la que vale.

## Pendiente

**A comprobar en el sistema (SE11 / SE37):**
- [ ] **Primera prueba en SE37** con un caso real: ver si
      `ISU_O_MANUBILL_INPUT` respeta precio e importe o los recalcula, y si
      `data_read` necesita más campos de cabecera en `BILL_DOC-ERCH`
      (comparar con un cálculo manual hecho a mano en EA20).
- [ ] Datos de las líneas sin original (EREPOS/GREPOS, PGINTR/PGIRAP,
      mínimo comunitario nuevo): mirar una reposición real en las DBERCHZ.
- [ ] Fecha clave (`X_STICHTAG`) correcta para el cálculo manual.
- [ ] Cómo facturar el cálculo al momento (en vez de esperar al job sobre
      `EITR`) y de dónde sale el documento oficial.
- [ ] Campos de `ERCH`: `BEGABRPE`, `ENDABRPE`, `STORNODAT`, `SIMULATION`.
      Ver también si hay que filtrar por `ABRVORG`.
- [ ] Si el precio de la línea de IEE viene en % (5,11…) o como factor.
- [ ] Valores de `SPARTE` para luz y gas (asumidos `01` / `02`).
- [ ] Dónde están las facturas ATR y sus conceptos 1923/1924 (¿existen
      `/IDXGC/PRST_INHD`…? Si no, buscar la tabla Z que usa `ZLE_DE_FACTUR`).
- [ ] Rellenar `ZFA_FRAUD_CONC` con los conceptos reales.

**A definir con Aleix:**
- [ ] Validación consumo ATR vs consumo total (pendiente en el DF).
- [ ] Origen de: periodo migrado, exención de impuestos, derecho al olvido,
      vulnerable/esencial y qué bloqueo de contrato o cuenta contrato.
- [ ] Operando de reposición (y si basta con que exista) y tipo(s) de
      tarifa de Tarifa Plana.
- [ ] Que el flag de descarte se salta las validaciones de integridad.
- [ ] Qué hacer si el periodo abarca varios cálculos (hoy se descarta).
- [ ] Base del IEE: antes o después de descuentos (hoy, después).
- [ ] Cómo son los descuentos (hoy se asume que son en %).
- [ ] Tipo real de `IV_ID_PROCESO_ATR`.
- [ ] Códigos de resultado y valores de `EV_MODO_FACTURACION`.
- [ ] Mínimo del IEE: el DF dice 1 €/MWh; hay casos de 0,5 €/MWh.
- [ ] Factor IEE cuando el cálculo original se facturó con el mínimo.

**Formulario:** mensaje en 5 idiomas para las facturas de fraude y averías.
Falta saber la tecnología del formulario y cómo se identifica una factura de
este tipo.
