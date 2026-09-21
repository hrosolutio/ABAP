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
`OPTION = 'EQ'`), y llamar con
`SUBMIT zfi_r_devoluciones2 WITH SELECTION-TABLE lt_rspar AND RETURN.`
`RSPARAMS` es una estructura estándar de SAP, no hace falta crear nada
nuevo para esto.

**Sin fila `P_SIMU`, a propósito**: no se rellena ninguna fila para
`P_SIMU` en `lt_rspar`, así que el report toma su propio valor por
defecto (`P_SIMU DEFAULT SPACE`, real). Se decidió quitar el parámetro
de simulación de la RFC (no viene del DF, fue una adición nuestra):
esta RFC siempre cierra/contabiliza de verdad, para no dar pie a que un
consumidor externo dispare sin querer una llamada que no hace nada. El
report en sí conserva `P_SIMU` para uso manual.

### Cómo se determina el resultado

El report no expone ningún parámetro de salida (es un `REPORT`, no una
clase con `RETURNING`) — solo escribe mensajes con `WRITE`. En vez de
parsear ese texto (frágil: depende del wording exacto de los mensajes
`ZFI_MC_001`), el RFC relee directamente `DFKKRK-STARS` de cada
`KEYR1` después del `SUBMIT` — es el mismo campo que usa el propio
`LCL_DEVOLUCIONES2` internamente para decidir qué hacer con cada lote
(`CO_STARS_POSTED = '5'`, ver el código de `ZFI_R_DEVOLUCIONES2_CLS`),
así que es una fuente de verdad ya validada, no una interpretación nueva.

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
  solo si todos los lotes de `IT_KEYR1` terminaron contabilizados
  (`DFKKRK-STARS = '5'`, ya que esta RFC siempre se ejecuta en real —
  ver más arriba); `NOK` si al menos uno no.
- `ES_ERROR-DESCRIPTION`, cuando `E_RESULT = NOK` por lotes
  incompletos (`CODE = 'LOTES_INCOMPLETOS'`), concatena una línea por
  cada lote que falló (con su `KEYR1` y el motivo: `STARS` actual, o
  que no existe en `DFKKRK`) — no es un texto fijo como en los otros
  RFCs, porque aquí puede haber más de un fallo por llamada.

**Se descartó una tabla de resultado aparte** (`ET_RESULTADO`, con una
fila `KEYR1`/`STARS` por lote): con `E_RESULT`/`ES_ERROR` cubriendo el
global y el detalle de qué falló, esa tabla no aportaba nada que no
estuviera ya ahí — se quitó por redundante (con `'OK'` ya se sabe que
todo se contabilizó; con `'NOK'` el detalle está en
`ES_ERROR-DESCRIPTION`).

### Detalle de error tipo FP09 (petición posterior de Eva)

Petición explícita: que esta RFC "devuelva el error tal y como lo hace
la FP09" — el desglose por documento que se ve al pulsar "Contabilizar"
cuando el lote tiene errores, no solo "no llegó a `STARS=5`". Investigado
a fondo (ver
[`../zfi_r_devoluciones2/docs/DF_resumen.md`](../zfi_r_devoluciones2/docs/DF_resumen.md),
sección "Detalle de error tipo FP09") y resuelto sin tocar código
estándar ni reconstruir la validación por nuestra cuenta.

**No se captura vía `SUBMIT ... EXPORTING LIST TO MEMORY`** (la opción
que se había apuntado aquí originalmente, pensada para el texto de
`ZXX_CL_MSG_LOGS`) — la vía real usada es distinta y más rica: dentro de
`ZFI_R_DEVOLUCIONES2_CLS`, en el momento de llamar a `FKK_RLS_POST_LOT`,
se captura el detalle de mensajes por documento del propio FI-CA
(`LCL_MESSENGER`/`GDBG` de `SAPLFKKTRACE`, vía el FORM público
`RETRIEVE_DATA` + `ASSIGN` dinámico + `MESSAGE...INTO`) y se deja en
**memoria ABAP** (`EXPORT gt_post_errors = gt_post_errors TO MEMORY ID
'ZFI_DEVOL2_ERRORS'`) al terminar `EXECUTE` — pero solo si esta RFC se
lo pide (ver "Señal `P_RFC`" más abajo).

**Por qué memoria ABAP y no otra cosa**: los datos globales de
`SAPLFKKTRACE` (`GDBG`/`T_MESSENGERDATA`) solo existen dentro de la
sesión interna donde se llamó a `FKK_RLS_POST_LOT` — que aquí es la
sesión interna abierta por el `SUBMIT ... AND RETURN`, no la de esta
RFC. Al volver del `SUBMIT`, esos datos ya no son alcanzables. Memoria
ABAP (`EXPORT`/`IMPORT ... MEMORY ID`), en cambio, está pensada
precisamente para cruzar esa frontera dentro de la misma sesión externa,
así que este RFC hace, justo después del `SUBMIT`:

```abap
IMPORT gt_post_errors = lt_post_errors FROM MEMORY ID 'ZFI_DEVOL2_ERRORS'.
FREE MEMORY ID 'ZFI_DEVOL2_ERRORS'.
```

y añade el texto de cada línea (`KEYR1` + mensaje) que corresponda a
cada lote fallido dentro de `ES_ERROR-DESCRIPTION`, a continuación del
`STARS` resultante. Nótese que el nombre `gt_post_errors` a la
izquierda del `=` es la **clave del dato** en memoria (tiene que
coincidir con el `EXPORT` del report), no el nombre de la variable
local `lt_post_errors` que recibe el valor aquí.

### Señal `P_RFC`: exportar solo cuando hace falta

Para no dejar datos en memoria ABAP cuando alguien ejecuta
`ZFI_R_DEVOLUCIONES2` a mano en SE38 (nadie va a leer esa memoria en ese
caso), el report solo exporta si detecta que la llamada viene de esta
RFC. Se probó primero con el campo de sistema `SY-CALLD` (se pone a
`'X'` cuando el programa se lanza con `SUBMIT`/`CALL TRANSACTION`) pero
se descartó: el propio "Ejecutar" de SE38 también lo deja a `'X'`, así
que no distinguía lo que hacía falta distinguir.

Solución final: un parámetro `P_RFC` (`NO-DISPLAY`, no aparece en la
pantalla de selección) en `ZFI_R_DEVOLUCIONES2_EVE`. Esta RFC añade una
fila explícita a `lt_rspar` para rellenarlo a `'X'`:

```abap
CLEAR ls_rspar.
ls_rspar-selname = 'P_RFC'.
ls_rspar-kind    = 'P'.
ls_rspar-sign    = 'I'.
ls_rspar-option  = 'EQ'.
ls_rspar-low     = abap_true.
APPEND ls_rspar TO lt_rspar.
```

En ejecución manual (SE38), `P_RFC` no se rellena y queda en blanco por
defecto, así que el report no exporta nada.

## Objetos DDIC nuevos

Mismo patrón ya usado en `ZFI_FM_PAYMENT_LOT_CLARIFY2` (`ZFI_T_XBLNR`):
el Function Builder no admite un `TYPES` de programa como tipo de
referencia de un parámetro de import/export de un módulo de función,
tiene que ser un objeto DDIC real. Se crean 2 objetos nuevos, triviales
(sin lógica de negocio propia):

| Objeto | Tipo | Campos |
|---|---|---|
| `ZFI_S_KEYR1` | Estructura | `KEYR1` (`DFKKRK-KEYR1`) |
| `ZFI_T_KEYR1` | Tabla estándar | Línea `ZFI_S_KEYR1` |

`ZFI_DE_XX_WS_ERROR` (`ES_ERROR`) **no es nuevo** — ya existe, reutilizado
de `ZFI_FM_PAYLOT_REVERSE`/`ZFI_FM_PAYMENT_LOT_CLARIFY2`.

## Pendiente / a definir con el cliente

- Probar en SE37 contra uno o varios lotes reales, ahora ya con el
  detalle tipo FP09 en `ES_ERROR-DESCRIPTION` (aún no ejecutado) —
  **ojo, no hay simulación: la llamada cierra/contabiliza de verdad**.
- Autorización RFC del usuario técnico sobre `ZFI_FG_DEVOL2`.
- Alta del objeto en el sistema de transporte correspondiente al
  proyecto (junto con los 2 objetos DDIC nuevos).
