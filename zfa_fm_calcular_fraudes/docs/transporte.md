# Objetos para el transporte a producción

Lista para revisar que la orden lleva todo. Marcar al incluir.

## Workbench

| Objeto | Tipo | Notas | ✓ |
|---|---|---|---|
| `ZFA_FG_FRAUDES` | Grupo de funciones | Con sus dos FM | |
| `ZFA_FM_CALCULAR_FRAUDESV2` | Módulo de funciones (RFC) | Acceso remoto | |
| `ZFA_FM_FRAUDES_LIBERAR` | Módulo de funciones | **Acceso remoto** (se llama con `DESTINATION 'NONE'`) | |
| `ZCL_FA_CALCULO_FRAUDES` | Clase | Con su clase de test local | |
| `ZCX_FA_FRAUDES` | Clase de excepción | | |
| `ZFA_S_FRAUDES_FACTURA` | Estructura | | |
| `ZFA_T_FRAUDES_FACTURA` | Tipo de tabla | `ET_FACTURAS` | |
| `ZFA_S_FRAUDES_LINEA` | Estructura | | |
| `ZFA_TT_FRAUDES_LINEA` | Tipo de tabla | `ET_LINEAS` | |
| `ZFA_FRAUD_CONC` | Tabla de customizing | | |
| `ZFA_FG_FRAUD_CONC` | Grupo de funciones | Generador de actualización (SM30) | |
| `ZFA_FRAUD_LOG` | Tabla | Log por expediente | |
| `ZFA_R_CARGA_FRAUD_CONC` | Report | Carga inicial de `ZFA_FRAUD_CONC` | |
| `ZXBI1U01` | Include de la exit | **Compartido**: va solo el bloque 1B. Coordinar con quien lo tenga en otras órdenes | |

## Datos y configuración por sistema

| Qué | Cómo | ✓ |
|---|---|---|
| Contenido de `ZFA_FRAUD_CONC` | Ejecutar `ZFA_R_CARGA_FRAUD_CONC` en cada sistema (sin `P_TEST`) o transportar las entradas | |
| `ZFA_FRAUDES_PLANTILLA_EREPOS` | STVARV. Un cálculo real con línea `EREPOS` **de ese sistema** | |
| `ZFA_FRAUDES_PLANTILLA_GREPOS` | STVARV. Ídem con `GREPOS` | |
| `ZFA_FRAUDES_MWSKZ` | STVARV. Indicador de IVA (21 %) para el solo cálculo | |
| `ZFA_FRAUDES_PLANTILLA_PGINTR` / `_PGIRAP` | STVARV. Ídem, si se facturan conceptos ATR 1923/1924 en gas | |

## Antes de pasar

- [ ] ABAP Unit de `ZCL_FA_CALCULO_FRAUDES` en verde.
- [ ] Batería de `docs/plan_pruebas.md` pasada en QA.
- [ ] TODO pendientes de Aleix y Eliza revisados (README, "Pendiente").
- [ ] Avisar a la IA del nombre de la RFC y de la tabla de códigos.
