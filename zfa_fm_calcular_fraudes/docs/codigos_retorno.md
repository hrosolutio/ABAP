# Códigos de retorno de ZFA_FM_CALCULAR_FRAUDESV2

Para la IA. `EV_RESULTADO` = `OK` en los `0xxx` y `KO` en los `1xxx`/`2xxx`;
`EV_DESCRIPCION` trae el detalle de cada caso.

## Factura emitida (no volver a enviar el expediente)

| Código | Modo | Significado | Acción |
|---|---|---|---|
| `0000` | FACTURACION TOTAL | Factura emitida y contabilizada | — |
| `0001` | FACTURACION TOTAL | Factura a 0 emitida (`IV_FORZADO`) | — |
| `0003` | FACTURACION TOTAL | Factura creada pero apartada: no tiene nº oficial hasta que se libere | Revisar y liberar en SAP (EA05) |
| `0004` | FACTURACION TOTAL | Factura emitida, pero el PDoc no se ha podido pasar a OK | Actualizar el PDoc a mano |

## Sin factura

| Código | Modo | Significado | Acción |
|---|---|---|---|
| `0010` | FACTURACION TOTAL | Solo cálculo (`IV_SOLO_CALCULO`): detalle e importe con IVA, nada grabado | Enviar sin `IV_SOLO_CALCULO` para facturar |
| `0101` | — | Periodo migrado | Tratamiento manual |
| `0102` | — | Exención de impuestos | Tratamiento manual |
| `0103` | DESCARTE - DERECHO AL OLVIDO | Cliente con derecho al olvido | Reenviar con `IV_FORZADO` (factura a 0) |
| `0104` | DESCARTE - VULNERABILIDAD | Vulnerable o suministro esencial | Reenviar con `IV_FORZADO` |
| `0105` | — | Contrato o cuenta contrato bloqueados | Reintentar tras el desbloqueo |
| `0106` | DESCARTE - REPOSICION | Reposición en el periodo | Reenviar con `IV_FORZADO` |
| `0107` | DESCARTE - ANOMALIA TP | Tarifa Plana | Tratamiento manual (fase 2) |
| `0108` | — | No hay cálculo del periodo | Reintentar cuando exista |
| `0109` | — | El periodo abarca varios cálculos | Tratamiento manual (parciales, fase 2) |
| `0110` | DESCARTE - EMPLEADO | Contrato de empleado | Reenviar con `IV_FORZADO` |
| `0111` | DESCARTE - CADUCADO | Periodo totalmente caducado | Reenviar con `IV_FORZADO` |
| `0112` | — | Periodo caducado en parte o más largo que la periodicidad | Tratamiento manual (parciales, fase 2) |

## Errores en los datos de entrada

| Código | Significado | Acción |
|---|---|---|
| `1000` | Falta un parámetro obligatorio | Corregir y reenviar |
| `1001` | El CUPS no existe | Corregir y reenviar |
| `1002` | El contrato no existe o no es del CUPS | Corregir y reenviar |
| `1003` | Contrato no vigente en el periodo | No se puede facturar |
| `1004` | Factura ATR inexistente, de otro CUPS o tipo no válido (luz `06`/`11`, gas `AN`/`FR`) | Corregir y reenviar |
| `1006` | Expediente ya facturado | No reenviar |
| `1007` | Fecha desde posterior a fecha hasta | Corregir y reenviar |
| `1008` | Contrato con energía por periodos y sin consumos P1–P6 | Enviar P1–P6 |

## Errores técnicos en SAP

| Código | Significado | Acción |
|---|---|---|
| `2001` | El cálculo original no tiene conceptos configurados | Avisar a SAP |
| `2002` | Falta un dato para calcular (precio, concepto…) | Avisar a SAP |
| `2003` | Error al crear el cálculo | Avisar a SAP |
| `2005` | Contrato bloqueado por otro proceso | Reintentar más tarde |
| `2006` | Determinación de cuentas del contrato no válida para la serie | Avisar a SAP |
| `2007` | No se ha podido facturar; el cálculo se ha borrado | Reintentar; si se repite, avisar a SAP |
| `2008` | No se ha podido facturar ni borrar el cálculo | Avisar a SAP (borrado manual) |
| `2009` | Solo cálculo: no se ha podido calcular el IVA | Avisar a SAP |
| `2010` | Provincia del suministro no encontrada o sin parametrizar | Avisar a SAP |

Las acciones de "Reenviar con `IV_FORZADO`" están pendientes de confirmar
(alternativa: que SAP facture a 0 directamente).
