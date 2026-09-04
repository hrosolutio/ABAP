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
`SUBMIT ... WITH SELECTION-TABLE`, construyendo por programa las mismas
entradas que se rellenarían a mano en su pantalla de selección
(`S_KEYR1` a partir de `IT_KEYR1`, `P_SIMU` a partir de `IV_SIMU`), y
después relee `DFKKRK-STARS` de cada lote para devolver un resultado
estructurado — la misma fuente de verdad que usa el propio report para
decidir qué hacer con cada lote.

Se decidió así (en vez de extraer la lógica a una clase global
compartida) para no tocar código ya probado en DES: el report se queda
exactamente igual, y este RFC es una capa fina por encima.

**No se captura el listado de mensajes** (`ZXX_CL_MSG_LOGS`) que ve quien
ejecuta el report a mano — lo que le interesa a un consumidor externo es
el estado final de cada lote (`ET_RESULTADO-STARS`), no el texto de los
mensajes intermedios. Si en el futuro hiciera falta también ese detalle,
habría que capturar el listado con `SUBMIT ... EXPORTING LIST TO MEMORY`
+ `LIST_FROM_MEMORY`.

## Interfaz del servicio

| Parámetro | Dirección | Tipo | Obligatorio | Descripción |
|---|---|---|---|---|
| `IV_SIMU` | Import | `ABAP_BOOL` | No (`DEFAULT ABAP_FALSE`) | Igual que `P_SIMU` del report: si es `X`, no cierra ni contabiliza nada, solo permite ver el `STARS` actual |
| `IT_KEYR1` | Import | `ZFI_T_KEYR1` (tipo de tabla DDIC, ver instalación) | Sí | Lote(s) a cerrar/contabilizar |
| `ET_RESULTADO` | Export | `ZFI_T_KEYR1_RESULT` (tipo de tabla DDIC, ver instalación) | — | Un registro por cada `KEYR1` de `IT_KEYR1`, con el `DFKKRK-STARS` tras la llamada (`5` = contabilizado; ver tabla de valores en el README del report) |

Si `IT_KEYR1` viene vacío, el módulo no hace nada y `ET_RESULTADO` sale
vacío (no es un error, simplemente no hay nada que procesar).

## Contenido del repositorio

```
src/
  LZFI_FG_DEVOL2TOP.abap        Include TOP del grupo de función
  ZFI_FM_DEVOLUCIONES2.abap     Código fuente del módulo de función RFC
docs/
  DF_resumen.md                  Resumen del Diseño Funcional (trazabilidad)
```

## Instalación en SAP (SE11 / SE80 / SE37)

1. **Crear en SE11 los tipos de tabla** (el Function Builder no admite un
   `TYPES` de programa como tipo de referencia de un parámetro de
   import/export, tiene que ser un objeto DDIC real — mismo patrón ya
   usado en `ZFI_T_XBLNR` de `ZFI_FM_PAYMENT_LOT_CLARIFY2`):
   - Estructura **`ZFI_S_KEYR1`**, con un único campo `KEYR1` tipo
     `DFKKRK-KEYR1`.
   - Tipo de tabla **`ZFI_T_KEYR1`**, `Category` = tabla estándar,
     `Line type` = `ZFI_S_KEYR1`.
   - Estructura **`ZFI_S_KEYR1_RESULT`**, con dos campos: `KEYR1` tipo
     `DFKKRK-KEYR1` y `STARS` tipo `DFKKRK-STARS`.
   - Tipo de tabla **`ZFI_T_KEYR1_RESULT`**, `Category` = tabla
     estándar, `Line type` = `ZFI_S_KEYR1_RESULT`.
2. Crear el grupo de función **`ZFI_FG_DEVOL2`** (SE80 → Grupo de
   función → Crear).
3. Sustituir el contenido del include TOP del grupo
   (`LZFI_FG_DEVOL2TOP`) por `src/LZFI_FG_DEVOL2TOP.abap`.
4. Crear el módulo de función **`ZFI_FM_DEVOLUCIONES2`** dentro del
   grupo:
   - Atributos: marcar **"Módulo de función remoto"** (RFC).
   - Pestaña *Import*: `IV_SIMU` (tipo `ABAP_BOOL`, `DEFAULT ABAP_FALSE`,
     opcional), `IT_KEYR1` (obligatorio, tipo de referencia
     `ZFI_T_KEYR1`).
   - Pestaña *Export*: `ET_RESULTADO` (tipo de referencia
     `ZFI_T_KEYR1_RESULT`).
   - Pestaña *Código fuente*: pegar `src/ZFI_FM_DEVOLUCIONES2.abap`.
5. Activar y probar en SE37 contra uno o varios lotes reales ya creados
   por `ZFI_R_DEVOLUCIONES_CREA`.

## Pendiente

- Probar en SE37 (aún no ejecutado).
- Confirmar si el consumidor del servicio necesita también el texto de
  los mensajes del report, o le basta con `ET_RESULTADO-STARS` (ver
  "Cómo funciona" más arriba).
- Autorización RFC del usuario técnico que vaya a llamar a este módulo
  sobre el grupo de función `ZFI_FG_DEVOL2`.
- Alta del objeto en el sistema de transporte correspondiente al
  proyecto.
