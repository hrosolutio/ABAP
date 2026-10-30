# Decisiones funcionales recibidas

## Respuestas de Aleix (29/10/2026)

**Factura ATR y conceptos 1923/1924 (gas):**
- Cabecera en `/IDXGC/PRST_INHD`: el nº de factura ATR es
  `CODIGOFISCALFACTURA`.
- Conceptos en `/IDXGC/PRST_CHRG`: `CONCEPTOREPERCUTIBLE` = `1923` / `1924`.
- Unión por `PROC_REF` + `PROC_STEP_REF` (clave de las dos tablas).
  Importe en `IMPORTETOTALCONCEPTOREPERCUTIB` (texto).
- `/IDXGC/PRST_INHD` tiene el índice `ZCF` por `CODIGOFISCALFACTURA`.
- `PROC_REF` es el **PDoc** (documento de proceso); `PROC_STEP_REF`, el
  paso. El CUPS está en `/IDXGC/PRST_CHRG-EXT_UI`.

**Validaciones de integridad (descartes):**

| Validación | Origen |
|---|---|
| 2.1 Periodo migrado | `EVER-XVERA = 'X'` y fecha hasta < `EVER-EINZDAT_ALT` |
| 2.2 Exención de impuestos | Contrato en `ZFA_T_CIE` para las fechas (ab–bis) |
| 2.3 Derecho al olvido | Cliente en `ZCO_T_OFUSC_CLIE` |
| 2.4 Vulnerable / esencial | `EANL-ZZVITAL` ≠ `00`, filtrando por las fechas de inicio y fin de vital |
| 2.5 Bloqueo cuenta contrato | `DFKKLOCKS`, `LOTYP = '06'`, `LOOBJ1` = vkont + gpart |
| 2.5 Bloqueo contrato | `EVER-ABRSPERR` ≠ blanco |

**Códigos de resultado:** inventados por SAP. Eliza (29/10): les valen;
solo necesitan saber qué códigos indican factura emitida y cuáles no.

## Correo de Eliza (30/10/2026)

- Confirma la lista de modos de facturación (abajo).
- Lista de facturas emitidas por factura ATR, con nº de documento,
  nº oficial, fecha desde, fecha hasta, consumo e importe → es `ET_FACTURAS`.
- Parámetro de entrada para que la IA indique si SAP hace o no la
  facturación completa → `IV_SOLO_CALCULO`.

## Modo de facturación (Eliza, Teams 29/10/2026)

Valores que espera la IA en `EV_MODO_FACTURACION`:
- `FACTURACION TOTAL`
- `FACTURACION PARCIAL`
- `DESCARTE - DERECHO AL OLVIDO`
- `DESCARTE - EMPLEADO`
- `DESCARTE - VULNERABILIDAD`
- `DESCARTE - CADUCADO`
- `DESCARTE - REPOSICION`
- `DESCARTE - ANOMALIA TP`
- `DESCARTE - NO TITULAR`

Pendiente de aclarar con Eliza: qué es `PARCIAL`, `EMPLEADO`, `CADUCADO`
y `NO TITULAR`, y qué modo llevan nuestros descartes que no están en la
lista (migrado, exención, bloqueos, sin cálculo, varios cálculos).


## Tipo de factura ATR (correo de Eliza, 27/10/2026)

- **Luz:** `06` = anomalía, `11` = fraude.
- **Gas:** la factura ATR es siempre tipo `99` y se distingue por el tipo
  de complementaria. La IA envía en `IV_TIPO_FACTURA_ATR`: `AN` = anomalía,
  `FR` = fraude (propuesta de Eliza, aceptada en SAP).
- `ORIGDOC`: fraude (`11`/`FR`) → `40`; anomalía (`06`/`AN`) → `41`.
  Antes estaba al revés en la clase (se suponía 06 = fraude).

## Respuestas de Aleix a las dudas de Héctor (26/10/2026)

1. **Facturas bloqueadas:** "Si creas la factura debería salir
   contabilizada directamente, solo en el caso de que haya un bloqueo en
   cuenta contrato que lo impida."
   → Decisión: **la factura sale contabilizada**. Las que aparta `ZCICLO`
   (ciclo > 1 año) las libera la propia RFC.
2. **Si falla la facturación:** "Devolver error y anular el cálculo".
   → Hecho: se borra con `ISU_S_MANUBILL_DELETE` y se devuelve `2007`
   (o `2008` si no se puede borrar).
3. **Consumo ATR vs total:** lo controla la IA. SAP factura el consumo que
   le llega. → Validación 1.5 eliminada.
4. **Formulario:** "No toques el formulario" → fuera de alcance.

## Correo "Averías y fraude: DF" (Eliza Grosiak, 26/10/2026, reenviado por Aleix)

Lo acordado en la reunión con la parte de la IA:

1. **Interfaz:**
   - **Fuera** `IV_DESCARTE` e `IV_MARCA_TITULAR`.
   - **Nuevo**: indicador de **Forzado** (`X` o vacío) = **factura a 0**.
     Sustituye a los dos flags (confirmado por Héctor).
2. **Fechas:** la IA ya envía la intersección.
   - Desde = máx(inicio factura ATR, inicio expediente).
   - Hasta = mín(fin factura ATR, fin expediente).
3. **Consumos (total y P1-P6):** los calcula la IA, sin tener en cuenta
   precios.
   - Con detalle por ATR: el mínimo entre el consumo del ATR y el del
     expediente para ese ATR.
   - Con el expediente agregado de varios ATR:
     - si el consumo del expediente es ≥ que la suma de los ATR, el del ATR;
     - si no, reparte el del expediente por días del ATR (de mayor a menor
       peso; a igual peso, por fecha de inicio).
   
   → La validación 1.5 "consumo ATR vs consumo total" la resuelve la IA.
4. **PDoc:** hay que confirmar que **el servicio SAP actualiza el status
   del PDoc** de la factura ATR emitida. Alcance nuevo, falta definir.
5. **Anulaciones:** la IA no las trata. Las hace el BO a mano.

## Correo de Aleix (16/10/2026)

- Solo **"Happy Path"**. Los descartes se irán incorporando según el
  volumen de cálculos manuales. Lo que no sea happy path se sigue haciendo
  como ahora.
- **Mejoras en el formulario → kanban aparte**, fuera de este desarrollo.
- **Tarifa Plana y energía reactiva**, más adelante.
  - Tarifa Plana sigue como descarte (`0107`).
  - Reactiva: pendiente de negocio (¿descarte?).

## Pendiente de aclarar

- **Status del PDoc:**
  - qué PDoc es (cómo se llega desde nº factura ATR / ID proceso);
  - a qué status;
  - con qué FM o clase.
- **Reactiva:** si el ATR trae reactiva, ¿se descarta?
