# Alcance por fases (correo de David Villa, 16/11/2026)

Casuísticas fuera del "Happy Path" (1 ATR – 1 factura) que pide David y
cómo están hoy en la RFC.

## Descartes

| Casuística | Pide David | Hoy en la RFC | Fase |
|---|---|---|---|
| Vulnerable / esencial | Facturar a 0 | Detecta y devuelve `0104` sin facturar; la IA puede relanzar con `IV_FORZADO` → factura a 0 | 1 |
| Caducado | Facturar a 0 (forzado) | `0111` por `ZFA_T_CADUCIDAD` (provincia, sector, tipo); la IA relanza con `IV_FORZADO`. Parcial → `0112` | 1 (total) / 2 (parcial) |
| Empleado | Facturar a 0 | Detecta y devuelve `0110`; ídem con `IV_FORZADO` | 1 |
| Reposiciones | Facturar a 0 | Detecta y devuelve `0106`; ídem con `IV_FORZADO` | 1 |
| Fuera de vigencia de contrato | No se puede facturar | `1003` | 1 |
| Titular distinto | Factura a 0 | Lo detecta la IA → `IV_FORZADO` | 1 |
| Derecho al olvido | Facturar a 0 | Detecta y devuelve `0103`; ídem con `IV_FORZADO` | 1 |

Pendiente de decidir: en los descartes "a 0", ¿SAP factura a 0 directamente
al detectarlo, o devuelve el descarte y la IA relanza con `IV_FORZADO`?
Hoy funciona lo segundo sin desarrollo adicional.

## Parciales (dentro del periodo AN/FR)

Ninguno implementado (Aleix 12/11: solo totales). Hoy:
- Varios productos / tarifas en el periodo → varios cálculos → `0109`.
- El resto (parcialmente caducado, empleado, reposición, vigencia,
  varios titulares) → descarte del caso completo o lo resuelve la IA.
- Diferencia de consumo ATR vs expediente → la IA (Aleix 26/10). Facturar
  a 0 la diferencia es alcance nuevo.

Fase 2: partir el periodo y emitir varias facturas (o líneas a 0 por
tramo) en una misma llamada.

## Tratamiento manual / reintento

| Casuística | Pide David | Hoy |
|---|---|---|
| Periodos migrados | Manual | `0101` |
| Exención de impuestos | Manual | `0102` |
| Error no esperado | Manual | `2xxx` (cálculo borrado si no se factura) |
| Faltan cálculos del periodo | Reintentar | `0108` |
| Bloqueo cuenta o contrato | Reintentar | `0105` |

Cubierto en fase 1: cada caso tiene su código y la IA decide reintento o
manual.

## Comportamiento especial

| Casuística | Pide David | Hoy | Fase |
|---|---|---|---|
| Tarifa Plana | Facturar con precio del producto base, sin producto en factura | Descarte `0107` | 2 |
| Status del PDoc | Pasar a OK al facturar | `EIDESWTDOC` `02` → `01` (prueba 28 pendiente) | 1 |
| Conceptos ATR: intervención | Traspasar a la factura | Gas `1923`/`1924` programado, sin probar (falta ATR con esos conceptos y plantilla STVARV). Luz: sin definir | 1 gas / 2 luz |
| Conceptos ATR: reactiva | Traspasar a la factura | No implementado (nuevo) | 2 |
