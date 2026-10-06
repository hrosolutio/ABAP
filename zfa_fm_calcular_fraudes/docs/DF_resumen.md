# Resumen del Diseño Funcional

**Documento origen:** DF_NC_Averias_y_fraude — "Automatización de averías y fraude" (v1.0, 24/08/2026, Aleix Casajuana)

## Objeto

Automatizar la generación de las facturas de fraude y averías a partir de
los expedientes de la distribuidora (factura ATR tipo 06 u 11), creando un
cálculo manual que reutiliza los precios del cálculo original del cliente.

- En esta primera fase solo se factura automáticamente lo que supera todas
  las validaciones.
- Los descartes que haya que facturar a 0 se hacen bajo petición, con un
  flag en el servicio. La IA decide cuándo llamar con el flag.
- Lo que no contempla el DF se sigue haciendo fuera del servicio.

## Servicio

RFC llamada desde fuera (confirmado por Aleix): `ZFA_FM_CALCULAR_FRAUDES`.

**Entrada:** CUPS, fecha desde/hasta, consumo P1-P6 (opcionales), consumo
total, nº y tipo de factura ATR, contrato SAP, ID de proceso de la factura
ATR, flag de descarte (opcional), marca de titular, ID de expediente.

**Salida:** resultado, descripción, modo de facturación y una tabla con
factura, consumo, importe, documento oficial y fechas desde/hasta.

## Validaciones de entrada (KO + código + descripción)

1. El CUPS existe.
2. El CUPS y el contrato son correctos.
3. El contrato está activo entre las fechas.
4. La factura ATR existe y es de tipo 06 u 11.
5. Consumo de la factura ATR vs consumo total — **pendiente de detallar en el DF**.

## Validaciones de integridad (OK + código + descripción = descarte)

1. Periodo migrado (contrato portado de Uptility o NI con ATR de una fecha
   facturada en el sistema antiguo).
2. Exención de impuestos.
3. Derecho al olvido.
4. Vulnerabilidad o esencialidad activa en las fechas.
5. Contrato y/o cuenta contrato bloqueados.
6. Operando de reposición activo entre las fechas.
7. Tarifa Plana en el periodo.

## Factura final

Con el contrato y las fechas se busca el cálculo existente para sacar los
precios. Si no hay cálculo, se descarta.

**Gas**
- Término variable con el precio del cálculo; si hay cambio de precio se
  prorratea el consumo por fracciones.
- Impuesto de hidrocarburos: precio a fecha de creación × consumo.
- Descuentos de término variable aplicados sobre el importe del TV.
- Si el ATR trae los conceptos 1923 o 1924, una posición PGINTR / PGIRAP
  con el importe del concepto.

**Luz**
- Energía activa: un único concepto (consumo agrupado) o uno por periodo,
  con prorrateo por fracciones si hay cambio de precio.
- IEE: factor a fecha de creación del cálculo sobre el importe de energía,
  frente al mínimo (consumo / 1000 × 1 €). Se factura el mayor, con el
  mismo concepto de IEE del original (diferencia por región) o su
  equivalente de mínimo comunitario.
- Descuentos de energía aplicados sobre el importe de energía activa.
- La posición de potencia mayor del cálculo original, con importe 0, para
  que la factura se pinte bien.

El cálculo manual usa las mismas operaciones y conceptos que el original
(salvo cuando haya que usar el mínimo comunitario).

## Descartes y marca de titular

Con el flag de descarte, o con la marca de titular errónea, se factura a
importe 0 contabilizando el consumo con la posición EREPOS / GREPOS, igual
que las reposiciones.

## Formulario

Mensaje nuevo en las facturas de fraude y averías, en castellano, catalán,
gallego, euskera e inglés: "Esta factura incluye un recálculo de tu
consumo, a raíz de una anomalía en tu contador detectada y corregida por tu
empresa distribuidora para la dirección de suministro con número de CUPS:
ESXXXX".

## Pendiente en el propio DF

- Validación consumo ATR vs consumo total.
- Premisas / dependencias / limitaciones: vacío.
- Plan de pruebas: "adjuntar fichero", sin adjunto.
