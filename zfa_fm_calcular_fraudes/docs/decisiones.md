# Decisiones funcionales recibidas

## Respuestas de Aleix a las dudas de Héctor (26/10/2026)

1. **Facturas bloqueadas:** "Si creas la factura debería salir
   contabilizada directamente, solo en el caso de que haya un bloqueo en
   cuenta contrato que lo impida."
   → Decisión: **la factura sale contabilizada**. Las que aparta `ZCICLO`
   (ciclo > 1 año) las libera la propia RFC.
2. **Si falla la facturación:** "Devolver error y anular el cálculo" (a
   confirmar con quien corresponda, pero es su propuesta).
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
