# ZFI_FM_DEVOLUCIONES2 — Servicio RFC de cierre/contabilización de lotes de devolución (CDI_11)

Implementa como **servicio RFC** la misma funcionalidad de **RU_03** del DF
*"Procedimiento Gestión de extornos"* (CDI_11) que ya cubre el report
[`ZFI_R_DEVOLUCIONES2`](../zfi_r_devoluciones2/README.md).

## Por qué existe además del report

El DF original de RU_03 pedía crear un servicio para el cierre/
contabilización del lote de devoluciones. Al desarrollarlo se habló con
Eva y se decidió que no hacía falta — bastaba con el report
`ZFI_R_DEVOLUCIONES2`, indicando el lote a mano (igual que se haría en
`FP09`). Más tarde se ha pedido igualmente un servicio para esto mismo.
En vez de descartar uno de los dos, **se mantienen ambos**:

- `ZFI_R_DEVOLUCIONES2` — uso manual (SE38/lote a mano), ya probado en DES.
- `ZFI_FM_DEVOLUCIONES2` (este desarrollo) — mismo comportamiento, expuesto
  como RFC para integración externa.

## Cómo funciona (no duplica lógica)

Este módulo de función **no reimplementa nada** de `LCL_DEVOLUCIONES2`:
literalmente ejecuta el propio `ZFI_R_DEVOLUCIONES2` con
`SUBMIT ... WITH SELECTION-TABLE`, construyendo por programa `S_KEYR1` a
partir de `IT_KEYR1`, y después relee `DFKKRK-STARS` de cada lote para
decidir el resultado — la misma fuente de verdad que usa el propio
report para decidir qué hacer con cada lote.

**Esta RFC siempre se ejecuta en real** — a diferencia del report (que sí
tiene `P_SIMU` para uso manual), aquí no hay parámetro de simulación: no
se rellena ninguna fila `P_SIMU` en la tabla de selección, así que el
report usa su propio valor por defecto (real). Decisión explícita, no
viene del DF: para no dar pie a que un consumidor externo dispare sin
querer una llamada que no hace nada.

Se decidió así (en vez de extraer la lógica a una clase global
compartida) para no tocar código ya probado en DES: el report se queda
exactamente igual, y este RFC es una capa fina por encima.

**Detalle de error tipo FP09**: cuando algún lote no llega a
contabilizarse, además del `STARS` resultante, `ET_ERROR` incluye una
fila por cada mensaje del desglose por documento que muestra la FP09
(ej. *"El documento 484000019565 no existe. Corrija la entrada"*) — una
fila por mensaje, no todo concatenado en un único campo (ver "Interfaz
del servicio" más abajo, motivo real de por qué `ET_ERROR` es tabla).
Ese detalle lo captura `ZFI_R_DEVOLUCIONES2_CLS` en el momento de llamar a
`FKK_RLS_POST_LOT` (ver
[`zfi_r_devoluciones2/docs/DF_resumen.md`](../zfi_r_devoluciones2/docs/DF_resumen.md)
para la investigación completa y la técnica usada — sin tocar código
estándar) y lo deja en **memoria ABAP** al terminar (`MEMORY ID
'ZFI_DEVOL2_ERRORS'`); esta RFC lo importa justo después del
`SUBMIT ... AND RETURN` (memoria ABAP sí cruza esa frontera de sesión
interna, a diferencia de los datos globales de un grupo de función, que
es donde vive el detalle original y por lo que no se puede leer
directamente desde aquí).

## Interfaz del servicio

`E_RESULT` sigue el mismo patrón que
[`ZFI_FM_PAYLOT_REVERSE`](../zfi_fm_paylot_reverse/README.md) y
[`ZFI_FM_PAYMENT_LOT_CLARIFY2`](../zfi_fm_payment_lot_clarify2/README.md)
(`CHAR3` `OK`/`NOK`), pero **`ET_ERROR` es una tabla** (`ZFI_T_XX_WS_ERROR`,
línea = la misma estructura `ZFI_DE_XX_WS_ERROR` de esos dos RFCs —
`CODE`/`DESCRIPTION`), no una única estructura como en ellos. Dos motivos:
`IT_KEYR1` admite varios lotes a la vez (a diferencia de esos dos RFCs,
que procesan un único elemento), y con el detalle de error tipo FP09 (ver
arriba) puede haber **muchos** mensajes reales por lote — no caben
concatenados en el campo `DESCRIPTION` (`CHAR75`) de una única fila sin
truncarse. Cada mensaje (el resumen de `STARS` de cada lote, y cada línea
de detalle FP09) es su propia fila.

| Parámetro | Dirección | Tipo | Obligatorio | Descripción |
|---|---|---|---|---|
| `IT_KEYR1` | Import | `ZFI_T_KEYR1` (tipo de tabla DDIC, ver instalación) | Sí | Lote(s) a cerrar/contabilizar |
| `E_RESULT` | Export | `CHAR3` | — | `OK` solo si **todos** los lotes de `IT_KEYR1` terminaron contabilizados (`DFKKRK-STARS = '5'`) y `ET_ERROR` queda vacía; `NOK` si al menos uno no |
| `ET_ERROR` | Export | `ZFI_T_XX_WS_ERROR` (tabla, línea `CODE`/`DESCRIPTION`) | — | Vacía si `E_RESULT = OK`. Si `NOK`: una fila con `CODE = 'PARAM_MISSING'` (`IT_KEYR1` vacío), o varias filas con `CODE = 'LOTES_INCOMPLETOS'` — una por lote con el `STARS` actual (o que no existe en `DFKKRK`), más una fila adicional por cada línea de detalle tipo FP09 si `FKK_RLS_POST_LOT` llegó a fallar |

Si `IT_KEYR1` viene vacío, `E_RESULT = 'NOK'` con una fila
`CODE = 'PARAM_MISSING'` en `ET_ERROR` (no se hace ningún `SUBMIT`).

**Ojo**: `DESCRIPTION` sigue siendo `CHAR75` por fila — un único mensaje
de FP09 más largo que eso se truncaría igual, pero es un caso mucho más
raro que el problema original (perder todo el detalle al ir todo
concatenado en una sola fila).

## Contenido del repositorio

```
src/
  LZFI_FG_DEVOL2TOP.abap        Include TOP del grupo de función
  ZFI_FM_DEVOLUCIONES2.abap     Código fuente del módulo de función RFC
docs/
  DF_resumen.md                  Resumen del Diseño Funcional (trazabilidad)
```

## Instalación en SAP (SE11 / SE80 / SE37)

1. **Crear en SE11 el tipo de tabla para `IT_KEYR1`** (el Function
   Builder no admite un `TYPES` de programa como tipo de referencia de
   un parámetro de import/export, tiene que ser un objeto DDIC real —
   mismo patrón ya usado en `ZFI_T_XBLNR` de
   `ZFI_FM_PAYMENT_LOT_CLARIFY2`):
   - Estructura **`ZFI_S_KEYR1`**, con un único campo `KEYR1` tipo
     `DFKKRK-KEYR1`.
   - Tipo de tabla **`ZFI_T_KEYR1`**, `Category` = tabla estándar,
     `Line type` = `ZFI_S_KEYR1`.
2. **Crear en SE11 el tipo de tabla para `ET_ERROR`** — no hace falta
   estructura nueva, reutiliza la que ya existe:
   - Tipo de tabla **`ZFI_T_XX_WS_ERROR`**, `Category` = tabla estándar,
     `Line type` = `ZFI_DE_XX_WS_ERROR` (la misma estructura `CODE`/
     `DESCRIPTION` que ya usan `ZFI_FM_PAYLOT_REVERSE`/
     `ZFI_FM_PAYMENT_LOT_CLARIFY2` para su `ES_ERROR`).
3. Crear el grupo de función **`ZFI_FG_DEVOL2`** (SE80 → Grupo de
   función → Crear).
4. Sustituir el contenido del include TOP del grupo
   (`LZFI_FG_DEVOL2TOP`) por `src/LZFI_FG_DEVOL2TOP.abap`.
5. Crear el módulo de función **`ZFI_FM_DEVOLUCIONES2`** dentro del
   grupo:
   - Atributos: marcar **"Módulo de función remoto"** (RFC).
   - Pestaña *Import*: `IT_KEYR1` (obligatorio, tipo de referencia
     `ZFI_T_KEYR1`).
   - Pestaña *Export*: `E_RESULT` (tipo `CHAR3`), `ET_ERROR` (tipo DDIC
     `ZFI_T_XX_WS_ERROR`).
   - Pestaña *Código fuente*: pegar `src/ZFI_FM_DEVOLUCIONES2.abap`.
6. Activar y probar en SE37 contra uno o varios lotes reales ya creados
   por `ZFI_R_DEVOLUCIONES_CREA` — **ojo, no hay simulación: la llamada
   cierra/contabiliza de verdad**.

## Pendiente

- **Probado en SE37 (21/09/2026)**: `ES_ERROR-DESCRIPTION` devuelve el
  detalle real de FI-CA por documento/lote (lote de prueba
  `260921CDI110`), igual que se ve a mano en `FP09N` — el mecanismo vía
  memoria ABAP (`ZFI_R_DEVOLUCIONES2_CLS` → `ZFI_DEVOL2_ERRORS` →
  `ZFI_FM_DEVOLUCIONES2`) queda validado en real, no solo en debug.
- Autorización RFC del usuario técnico que vaya a llamar a este módulo
  sobre el grupo de función `ZFI_FG_DEVOL2`.
- Alta del objeto en el sistema de transporte correspondiente al
  proyecto.
