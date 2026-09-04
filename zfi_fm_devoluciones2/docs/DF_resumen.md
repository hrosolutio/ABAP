# Resumen del DF — ZFI_FM_DEVOLUCIONES2 (RU_03, servicio RFC)

## Trazabilidad con el DF

El DF *"Procedimiento Gestión de extornos"* (CDI_11), en RU_03, pedía
crear un servicio para el cierre/contabilización del lote de
devoluciones. Al desarrollarlo se habló con Eva y se decidió que no
hacía falta un servicio — bastaba con un report (`ZFI_R_DEVOLUCIONES2`)
con el lote indicado a mano, igual que se haría en `FP09`. Esa decisión
está documentada en `../zfi_r_devoluciones2/docs/DF_resumen.md`.

Más tarde se ha vuelto a pedir el servicio (razón de negocio no detallada
en este resumen). En vez de reabrir la discusión de si hacía falta o no,
se ha optado por **mantener las dos cosas**: el report ya probado en DES,
y este RFC como capa adicional para quien necesite invocarlo desde fuera
de SAP (o desde otro proceso SAP) sin pasar por SE38.

## Decisión de diseño: envolver el report, no reescribir la lógica

`LCL_DEVOLUCIONES2` (la clase local de `ZFI_R_DEVOLUCIONES2`) ya está
probada en DES (ver `../zfi_r_devoluciones2/docs/DF_resumen.md` para el
detalle completo de la cadena `FKK_RLS_CLOSE`/`FKK_RLS_POST_LOT` y las
pruebas reales). Dos opciones se valoraron para exponerla como RFC:

1. **Convertir `LCL_DEVOLUCIONES2` en una clase global** (p.ej.
   `ZCL_FI_DEVOLUCIONES2`) e instanciarla tanto desde el report como
   desde el RFC.
2. **Que el RFC ejecute el report con `SUBMIT`**, sin tocar ni mover
   nada de código ya probado.

Se eligió la opción 2: es la interpretación literal de "una RFC que
llame a `ZFI_R_DEVOLUCIONES2`" (no "una RFC que llame a la misma lógica
reorganizada"), evita el riesgo de introducir una regresión en código ya
validado en DES, y es coherente con el patrón de este proyecto de no
tocar nada que ya funcione sin necesidad concreta.

### Mecanismo: `SUBMIT ... WITH SELECTION-TABLE`

`SUBMIT` no acepta pasar varios valores a un `SELECT-OPTIONS` con la
sintaxis simple (`WITH s_keyr1 = ...` solo admite un valor). Para pasar
varios lotes (`IT_KEYR1`) a la vez, hace falta construir una tabla de
selección estándar (`RSPARAMS`: `SELNAME`/`KIND`/`SIGN`/`OPTION`/`LOW`/
`HIGH`) con una fila por cada `KEYR1` (`KIND = 'S'`, `SIGN = 'I'`,
`OPTION = 'EQ'`) más una fila para `P_SIMU` (`KIND = 'P'`), y llamar con
`SUBMIT zfi_r_devoluciones2 WITH SELECTION-TABLE lt_rspar AND RETURN.`
`RSPARAMS` es una estructura estándar de SAP, no hace falta crear nada
nuevo para esto.

### Cómo se determina el resultado

El report no expone ningún parámetro de salida (es un `REPORT`, no una
clase con `RETURNING`) — solo escribe mensajes con `WRITE`. En vez de
parsear ese texto (frágil: depende del wording exacto de los mensajes
`ZFI_MC_001`), el RFC relee directamente `DFKKRK-STARS` de cada
`KEYR1` después del `SUBMIT` — es el mismo campo que usa el propio
`LCL_DEVOLUCIONES2` internamente para decidir qué hacer con cada lote
(`CO_STARS_CLOSED = '1'`, `CO_STARS_POSTED = '5'`, ver el código de
`ZFI_R_DEVOLUCIONES2_CLS`), así que es una fuente de verdad ya validada,
no una interpretación nueva.

### `E_RESULT`/`ES_ERROR`: mismo patrón que los otros RFCs, adaptado a varios lotes

Se pidió que este RFC devolviera `E_RESULT` (`CHAR3`, `OK`/`NOK`) y
`ES_ERROR` (`ZFI_DE_XX_WS_ERROR`, `CODE`/`DESCRIPTION`), igual que
`ZFI_FM_PAYLOT_REVERSE`/`ZFI_FM_PAYMENT_LOT_CLARIFY2`. Diferencia
importante: esos dos RFCs procesan un único elemento por llamada
(`I_DOCUMENTID`, o `I_KEYZ1`+`I_POSZA`), así que su `E_RESULT` es
directamente el resultado de ese único elemento. Este RFC acepta
`IT_KEYR1` con **varios** lotes a la vez (pedido explícitamente, ver
más abajo) — un único `E_RESULT`/`ES_ERROR` no puede decir "cuál" de
varios lotes falló, así que:

- `E_RESULT` pasa a ser el resultado **global** de la llamada: `OK`
  solo si todos los lotes de `IT_KEYR1` terminaron en el estado
  esperado; `NOK` si al menos uno no.
- `ES_ERROR-DESCRIPTION`, cuando `E_RESULT = NOK` por lotes
  incompletos (`CODE = 'LOTES_INCOMPLETOS'`), concatena una línea por
  cada lote que falló (con su `KEYR1` y el motivo: `STARS` actual, o
  que no existe en `DFKKRK`) — no es un texto fijo como en los otros
  RFCs, porque aquí puede haber más de un fallo por llamada.
- `ET_RESULTADO` (ya existía, ver más abajo) se mantiene además de
  `E_RESULT`/`ES_ERROR`, precisamente para que el consumidor pueda ver
  el detalle lote a lote sin tener que parsear `ES_ERROR-DESCRIPTION`.

"Estado esperado" depende de `IV_SIMU`: en modo real, `STARS = '5'`
(contabilizado); en modo simulación, que el `KEYR1` exista en
`DFKKRK` (la simulación por diseño no contabiliza nada, así que exigir
`STARS='5'` marcaría como `NOK` cualquier llamada de simulación sobre
un lote todavía no contabilizado, que es precisamente el caso de uso
normal de la simulación).

**Explícitamente fuera de esta versión**: el texto de los mensajes
(`ZXX_CL_MSG_LOGS`) que ve quien ejecuta el report a mano. Si un
consumidor del servicio necesitara ese detalle (p.ej. el motivo exacto
de un fallo en `FKK_RLS_POST_LOT`, no solo "no llegó a `STARS=5`"),
habría que capturar el listado del `SUBMIT` con `EXPORTING LIST TO
MEMORY` + `LIST_FROM_MEMORY` y devolverlo como texto adicional — no
implementado todavía porque no se ha confirmado que haga falta.

## Objetos DDIC nuevos

Mismo patrón ya usado en `ZFI_FM_PAYMENT_LOT_CLARIFY2` (`ZFI_T_XBLNR`):
el Function Builder no admite un `TYPES` de programa como tipo de
referencia de un parámetro de import/export de un módulo de función,
tiene que ser un objeto DDIC real. Se crean 4 objetos nuevos, todos
triviales (sin lógica de negocio propia):

| Objeto | Tipo | Campos |
|---|---|---|
| `ZFI_S_KEYR1` | Estructura | `KEYR1` (`DFKKRK-KEYR1`) |
| `ZFI_T_KEYR1` | Tabla estándar | Línea `ZFI_S_KEYR1` |
| `ZFI_S_KEYR1_RESULT` | Estructura | `KEYR1` (`DFKKRK-KEYR1`), `STARS` (`DFKKRK-STARS`) |
| `ZFI_T_KEYR1_RESULT` | Tabla estándar | Línea `ZFI_S_KEYR1_RESULT` |

`ZFI_DE_XX_WS_ERROR` (`ES_ERROR`) **no es nuevo** — ya existe, reutilizado
de `ZFI_FM_PAYLOT_REVERSE`/`ZFI_FM_PAYMENT_LOT_CLARIFY2`.

## Pendiente / a definir con el cliente

- Probar en SE37 contra uno o varios lotes reales (aún no ejecutado).
- Confirmar si el consumidor del servicio necesita el texto de los
  mensajes del report además de `STARS` (ver "Cómo se determina el
  resultado" más arriba).
- Autorización RFC del usuario técnico sobre `ZFI_FG_DEVOL2`.
- Alta del objeto en el sistema de transporte correspondiente al
  proyecto (junto con los 4 objetos DDIC nuevos).
