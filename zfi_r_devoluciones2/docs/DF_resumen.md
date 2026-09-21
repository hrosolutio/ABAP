# Resumen del Diseño Funcional

**Documento origen:** CS_CDI_11_Procedimiento_Gestion_de_extornos (27/07/2026, con
comentarios de EVA).

**Programa base (histórico, ver corrección más abajo):** copia literal de
`ZFI_R_DEVOLUCIONES` (COB-INT-006, autor Jose Ternero), que hoy gestiona
devoluciones bancarias SEPA recibidas en XML. Se partió de esta copia (sin
modificar) siguiendo la sugerencia de EVA en RU_03: en vez de exponer un
servicio RFC nuevo, reutilizar el motor estándar que ya crea, cierra y
contabiliza lotes de devolución (`RFKKKA00`, vía `SUBMIT ... WITH
p_xcre/p_xcls/p_xbu`).

> **Corrección (tras depurar RU_02 y probar RU_03 en `FP09`):** igual que
> pasó con RU_02 (el DF decía "FP09/RFKKA00" como si fueran equivalentes, y
> no lo son), el cierre/contabilización real **tampoco usa `RFKKKA00`** —
> `FP09` → "Cerrar"/"Contabilizar" llaman directamente a `FKK_RLS_CLOSE`/
> `FKK_RLS_POST_LOT` del grupo de función `FKR2` (el mismo que usa
> `ZFI_R_DEVOLUCIONES_CREA` para RU_02), confirmado con pruebas reales — ver
> "Cadena real confirmada" más abajo. **La copia de `ZFI_R_DEVOLUCIONES`
> deja de ser el punto de partida**; este programa habrá que reescribirlo
> sobre `FKK_RLS_*`, igual que se hizo con `ZFI_R_DEVOLUCIONES_CREA`.

## Objeto

Gestionar de forma automática los extornos que hoy llegan mezclados en el lote de
transferencias de ECOFI: separarlos (desarrollo 1), crear su lote de devoluciones
en SAP FI-CA (desarrollo 2) y cerrarlo/contabilizarlo (desarrollo 3, este programa),
sin intervención manual. Confirmado con negocio: son **3 desarrollos independientes**,
no uno solo.

## Requisitos del DF (CDI_11) y desarrollo que los cubre

- **RU_01 — División del fichero ECOFI** en transferencias (`_TRF`) y extornos
  (`_DEV`), detectando extorno por concepto de 24 dígitos.
  → Desarrollo 1: [`zfi_r_ecofi_split/`](../zfi_r_ecofi_split/README.md). *(Fuera de
  alcance de este programa.)*
- **RU_02 — Creación del lote de devoluciones** en SAP (`FP09`, vía
  `FKK_RLS_*` — no `RFKKKA00`, ver corrección arriba) a partir del fichero
  `_DEV`, con nomenclatura `AAMMDDCDI11xx`, sociedad `1239`, clase `DV`,
  motivo `Z01`, cta. compensación `4305500150`, una posición por línea del fichero.
  → Desarrollo 2: `zfi_r_devoluciones_crea/`, ya reescrito y probado con
  éxito. *(Fuera de alcance de
  este programa.)*
- **RU_03 — Cierre y contabilización** del lote de devoluciones ya creado.
  Comentario de EVA: no crear servicio nuevo, adaptar `ZFI_R_DEVOLUCIONES`.
  → Desarrollo 3: **este programa** (`ZFI_R_DEVOLUCIONES2`).

## Cadena real confirmada (grupo de función `FKR2`, no `RFKKKA00`)

Confirmado depurando `FP09` en DES sobre lotes reales creados por
`ZFI_R_DEVOLUCIONES_CREA` (mismo método que RU_02: breakpoint de módulo de
función puesto antes de pulsar el botón, para no depender de acertar el
momento exacto con `/h`). Ver `../zfi_r_devoluciones_crea/docs/DF_resumen.md`
para el contexto completo de RU_02 (nomenclatura de lote, `ANZPO`, etc. —
todo relevante aquí también porque este programa opera sobre esos mismos
lotes).

### Cerrar → `FKK_RLS_CLOSE`

```abap
CALL FUNCTION 'FKK_RLS_CLOSE'
     EXPORTING
          I_KEYR1          = rfkr1-keyr1
     EXCEPTIONS
          NOT_FOUND        = 1   " Schlüssel spezifiert unbekannten Stapel
          NO_AUTHORIZATION = 2   " keine Berechtigung für Schließen
          NOT_VALID        = 3   " Schließen nicht möglich, ungültige Daten
          OTHERS           = 4.
```

Firma completa: `IMPORTING I_KEYR1 LIKE DFKKRK-KEYR1, I_XDIALOG TYPE CHAR1
DEFAULT SPACE, I_XCOMMIT TYPE XFELD DEFAULT 'X'` (comitea solo, no hace
falta `COMMIT WORK` aparte), `CHANGING C_DFKKRK LIKE DFKKRK` (opcional, no
hace falta pasarlo). **Probado con éxito real**: lote `260825CDI111`,
`sy-subrc = 0`, `FP09` mostró después "Ya no se pueden modificar
devoluciones" (cerrado).

### Contabilizar → `FKK_RLS_POST_LOT`

```abap
CALL FUNCTION 'FKK_RLS_POST_LOT'
     EXPORTING
          I_KEYR1              = ...
*         I_XFULL_TRACE        = '?'    (default)
*         I_XSIMU               = SPACE  (default - posteo real, no simulación)
*         I_XWRITE              = 'X'    (default)
*         I_REWORK              = SPACE  (default)
*         I_CALL_FROM_RTP       = SPACE  (default)
*         I_CLOSE               = SPACE  (default - el lote ya debe estar cerrado)
*     TABLES
*         IT_DFKKRP_REWORK      (opcional)
     EXCEPTIONS
          NOT_VALID             = 1   " RLS kann nicht validiert werden
          INVALID_KEY           = 2   " Zum Schlüssel gibt es keinen Stapel
          LOCK_FAILURE          = 3   " Sperren des Stapel war fehlerhaft
          NO_DATA               = 4   " keine Items im Stapel
          POSTINGS_INCOMPLETE   = 5   " Buchungen waren nicht vollständig
          OTHERS                = 6.
```

La llamada real en `FP09` solo pasa `I_KEYR1`, todo lo demás a los valores
por defecto de arriba. **Probado en DES**: `sy-subrc = 6` (`OTHERS`) sobre
el lote `260825CDI110` — no es un fallo del FM, es que la mayoría de los
72 documentos del `_DEV` de prueba **no existen de verdad en DES**
("El documento 491000011392 no existe. Corrija la entrada", mensaje `>0`
número `91`, uno por cada línea, contador `FKK RLS ASSIGN OPBEL`). Los 3
primeros de la lista son justo los mismos documentos que sí existían y
funcionaron en Integración al principio de la depuración de RU_02 —
confirma que es una limitación de datos de DES, no un problema de código.
Pendiente probar una contabilización real con éxito (en Integración, o
con documentos que sí existan en DES).

`FKK_RLS_POST_LOT` no devuelve el detalle de qué documentos fallaron por
parámetro (no hay `TABLES` de mensajes en la firma). **Esto se ha
resuelto** (petición posterior de Eva, para `ZFI_FM_DEVOLUCIONES2`) — ver
la sección "Detalle de error tipo FP09" más abajo para la investigación
completa y la técnica final. `ZFI_R_DEVOLUCIONES2_CLS` ya no se limita al
`sy-subrc`/nombre de la FM genérico: cuando `FKK_RLS_POST_LOT` falla,
captura el mismo desglose por documento que se ve en `FP09`.

## Detalle de error tipo FP09 (petición posterior de Eva, para `ZFI_FM_DEVOLUCIONES2`)

Petición explícita: que la RFC `ZFI_FM_DEVOLUCIONES2` "devuelva el error
tal y como lo hace la FP09" — el desglose por documento que se ve al
pulsar "Contabilizar" cuando el lote tiene errores (ej. *"El documento
484000019565 no existe. Corrija la entrada"*, uno por línea). Con tres
restricciones explícitas del cliente: no reconstruir la validación por
nuestra cuenta (duplicar la lógica de `DFKKOP` sería frágil y quedaría
desincronizado de futuros cambios estándar), no modificar código
estándar (ni un solo parámetro), y no dejarlo como estaba (con solo
`sy-subrc` + nombre de la FM).

### Investigación (varias vías descartadas antes de encontrar la buena)

- **No es el Log de Aplicación estándar** (`SLG1`/`BAL_LOG_*`): un
  breakpoint en `BAL_LOG_MSG_ADD` nunca se disparó al reproducir el error
  en `FP09`.
- El mecanismo real es una **clase local** `LCL_MESSENGER` (programa
  `SAPLFKKTRACE`, grupo de función `FKKTRACE`), instanciada como objeto
  global `GDBG`. Va acumulando los mensajes de validación con un método
  `catch(...)` (parámetros por defecto `sy-msgid`/`sy-msgty`/`sy-msgno`/
  `sy-msgv1-4`, pensado para llamarse justo después de un `MESSAGE`).
  **`LCL_MESSENGER` es invisible fuera de `SAPLFKKTRACE`** — es una clase
  local de verdad, no hay forma soportada (reflexión, `CREATE OBJECT`
  dinámico...) de referenciarla desde otro programa. Crear una clase
  local propia con la misma pinta no sirve: nunca recibiría los datos
  reales, porque el código de SAP tiene el `GDBG` original cableado.
- `LCL_MESSENGER->store()` persiste a las tablas transparentes
  `DFKKTRACEK`/`DFKKTRACEP`, pero solo si `INIT` recibe
  `i_store_on_commit` no vacío — **confirmado por depuración que tanto en
  el "Contabilizar" manual de Eva en `FP09` como en nuestra propia llamada
  a `FKK_RLS_POST_LOT`, ese parámetro llega en blanco**, así que nunca se
  guarda ahí (solo había un registro antiguo, de julio 2024, sin relación).
- El FM público `FKK_TRACE_INIT` (el que crea `GDBG`) hace `FREE gdbg.
  CREATE OBJECT gdbg...` **incondicionalmente** al principio — y por
  depuración se confirmó que **`FKK_RLS_POST_LOT` lo llama internamente
  él solo**, con su propio `i_store_on_commit` en blanco, sea quien sea
  el llamador. Llamarlo nosotros antes con `i_store_on_commit = 'X'` no
  sirve de nada: en cuanto arranca `FKK_RLS_POST_LOT`, tira nuestro
  `GDBG` a la basura y crea uno nuevo desde cero, otra vez en blanco.
- Los 11 FMs del grupo `FKKTRACE` se revisaron uno a uno: ninguno exporta
  la tabla de mensajes en memoria como dato — `FKK_TRACE_SHOW`/
  `FKK_TRACE_LIST` solo hacen `CALL SCREEN` (popup interactivo), inútil
  para una RFC sin pantalla.

### La solución que sí funciona (confirmada por depuración, cero cambios en estándar)

El programa `SAPLFKKTRACE` (donde vive `GDBG`) tiene un **FORM público**,
`RETRIEVE_DATA`, que es el que rellena la pantalla 100 de
`FKK_TRACE_SHOW` — y ese FORM sí se puede invocar desde fuera:

1. **Llamar `FKK_RLS_POST_LOT`** como siempre (con `i_xfull_trace =
   abap_true`) — internamente arranca `FKK_TRACE_INIT`/`GDBG` y lo va
   rellenando con cada mensaje de validación.
2. **Justo después, en la misma sesión interna** (imprescindible — ver
   más abajo), invocar el FORM:
   ```abap
   PERFORM retrieve_data IN PROGRAM saplfkktrace
       USING abap_true space space space space.   " solo errores
   ```
   (dentro de un método de clase hace falta la forma larga
   `IN PROGRAM`, no `retrieve_data(saplfkktrace)` — ver `CLAUDE.md`).
   Esto ejecuta el código en el contexto de `SAPLFKKTRACE`, ve el `GDBG`
   real, llama a `gdbg->filter_messages` y deja el resultado filtrado en
   la tabla global `T_MESSENGERDATA`.
3. **Leer esa tabla global desde fuera** con `ASSIGN` dinámico. Tiene
   línea de cabecera, así que hace falta el `[]` para referirse al
   cuerpo, no a la cabecera (dump real `ASSIGN_TYPE_CONFLICT` sin el
   `[]` — ver `CLAUDE.md`):
   ```abap
   FIELD-SYMBOLS: <msgtab> TYPE STANDARD TABLE.
   ASSIGN ('(SAPLFKKTRACE)T_MESSENGERDATA[]') TO <msgtab>.
   ```
4. Cada línea trae un componente `DATA` **`TYPE dfkktracep`** — estructura
   DDIC real (no un tipo local invisible), con campos `ID`/`TY`/`NR`/
   `V1`-`V4` (el equivalente a `msgid`/`msgty`/`msgno`/`msgv1-4`) más
   `SRC`/`INF`. Para las líneas de error (`TY = 'E'`) `INF` viene vacío
   (solo lo trae relleno en líneas de traza/paso interno) — el texto hay
   que reconstruirlo con la sentencia clásica `MESSAGE ... INTO`:
   ```abap
   MESSAGE ID <ls_data>-id TYPE <ls_data>-ty NUMBER <ls_data>-nr
           WITH <ls_data>-v1 <ls_data>-v2 <ls_data>-v3 <ls_data>-v4
           INTO DATA(lv_text).
   ```
   **Verificado carácter a carácter contra la pantalla real de la FP09**
   (ej. `lv_text` = *"La diferencia del importe de 147,78 está fuera de
   la tolerancia 0,00 EUR"*, idéntico a la fila correspondiente del popup
   de Eva).

Implementado en `ZFI_R_DEVOLUCIONES2_CLS`, método privado
`get_post_lot_errors` (llamado desde `process_lot` cuando
`FKK_RLS_POST_LOT` falla) — la llamada a `retrieve_data` ya pide solo
errores (`i_error = abap_true`, el resto en blanco), así que no hace
falta filtrar `TY` otra vez en el bucle.

**Por qué esto no vale para la RFC directamente**: `ZFI_FM_DEVOLUCIONES2`
no llama a `FKK_RLS_POST_LOT` — hace `SUBMIT zfi_r_devoluciones2 ... AND
RETURN` (ver `../zfi_fm_devoluciones2/docs/DF_resumen.md`), y eso abre una
**sesión interna nueva**: los datos globales de un grupo de función (como
`GDBG`/`T_MESSENGERDATA`) no sobreviven al volver de esa sesión a la RFC.
Por eso la captura tiene que pasar aquí, dentro de este programa (en el
mismo momento en que se llama a `FKK_RLS_POST_LOT`), y el resultado se dejar
en **memoria ABAP** (`EXPORT ... TO MEMORY ID 'ZFI_DEVOL2_ERRORS'` al
final de `execute`, siempre, aunque esté vacía — para no arrastrar
resultados de una llamada anterior en la misma sesión) — memoria ABAP sí
cruza la frontera de `SUBMIT`/`CALL TRANSACTION`, a diferencia de los
datos globales de un grupo de función.

## Fuera de alcance (de este programa)

- **RU_01**: cubierto por `zfi_r_ecofi_split/`.
- **RU_02**: creación del lote — cubierto por `zfi_r_devoluciones_crea/`
  (`ZFI_R_DEVOLUCIONES_CREA`), ya reescrito sobre `FKK_RLS_*` y probado con
  éxito en DES (crea el lote, `AAMMDDCDI11x`). Este programa
  (`ZFI_R_DEVOLUCIONES2`) solo se encarga de **cerrar y contabilizar** un
  lote que ya existe — no crea nada.

## Plan de reescritura (sobre `FKK_RLS_*`, no sobre la copia de `ZFI_R_DEVOLUCIONES`)

La copia literal de `ZFI_R_DEVOLUCIONES` (XML SEPA + `convert_multicash` +
`submit_rfkkka00`) **ya no es el punto de partida** — todo ese motor
(`RFKKKA00`, `AUSZUG`/`UMSATZ`) pertenece al enfoque descartado, igual que
pasó con RU_02. Con la cadena real confirmada arriba, el programa se puede
simplificar mucho respecto al original:

1. **Qué lote cerrar/contabilizar**: el DF no define ningún mecanismo
   automático para esto — se indica **a mano** en la pantalla de
   selección (`S_KEYR1`, obligatorio), igual que se haría entrando a
   `FP09` con el nº de lote. (Una primera versión buscaba lotes pendientes
   automáticamente vía `ZFI_T_FILE_LOG` — fue una invención sin base en el
   DF, descartada tras revisarlo.)
2. **Cerrar**: `CALL FUNCTION 'FKK_RLS_CLOSE' EXPORTING i_keyr1 = ...` — ver
   firma y prueba real más arriba.
3. **Contabilizar**: `CALL FUNCTION 'FKK_RLS_POST_LOT' EXPORTING i_keyr1 =
   ...` — ver firma y prueba real más arriba. Si falla (`sy-subrc <> 0`),
   marcar error genérico (ver "Decisión de gestión de errores" más arriba)
   — no reintentar ni corregir nada automáticamente, es un flujo de
   corrección manual esperado por el propio SAP.
4. **Nomenclatura del lote**: ya resuelta en RU_02 (`AAMMDDCDI11x`,
   `generate_keyr1` en `ZFI_R_DEVOLUCIONES_CREA_CLS`) — este programa no
   genera ningún `KEYR1` nuevo, solo opera sobre los ya creados.
5. **Sociedad/cuenta/motivo**: no aplica aquí — ya fijados al crear el lote
   en RU_02 (vía `ZFI_T_CONSTANTS`). Cerrar/contabilizar no necesita estos
   datos, solo el `KEYR1`.
6. **Sin `ZFI_T_FILE_LOG`**: esa tabla es un registro de **ficheros
   procesados** (`ZFI_DE_FILE_NAME`, `ZFI_DE_STATUS_FILE`...) — este
   programa no procesa ningún fichero, así que no tiene sentido usarla
   aquí (ni para localizar lotes ni para nada). El estado del lote se
   consulta directamente en **`DFKKRK-STARS`** (ver sección siguiente),
   la fuente de verdad real en FI-CA.
7. **Sin ruta lógica de fichero**: al no leer ningún `_DEV`, no aplica
   `co_logical_path` aquí — el "modo Server" no tiene sentido para este
   desarrollo (no hay ficheros de entrada, solo lotes SAP pendientes).
8. **Alta del objeto en el sistema de transporte** correspondiente al
   proyecto.

### `DFKKRK-STARS`: la fuente de verdad del estado del lote

Estado real del lote en FI-CA, con ayuda de búsqueda confirmada por
`SE16N`:

| `STARS` | Significado | Acción |
|---|---|---|
| (blanco) | Aún se pueden añadir devoluciones (abierto) | `FKK_RLS_CLOSE`, y luego `FKK_RLS_POST_LOT` |
| `5` | Contabilizaciones realizadas | no se toca (ya está hecho) |
| `1` (cerrado) / `2`/`3`/`4`/`6`/`9` (intermedio o con incidencias) | cualquier otro estado | `FKK_RLS_POST_LOT` igualmente |

Confirmado con datos reales: `260825CDI110` (se intentó contabilizar y
falló para casi todos los documentos, DES) quedó con `STARS = 3`
("incompletas" — encaja). `260825CDI111` (solo se cerró, nunca se
contabilizó) quedó con `STARS = 1`.

**Decisión (revisada tras añadir el detalle tipo FP09, ver más abajo)**:
ya no se filtra por `STARS` antes de llamar a `FKK_RLS_POST_LOT` — antes,
los estados intermedios/con incidencias (`2`/`3`/`4`/`6`/`9`) se dejaban
sin tocar ("revisión manual"); ahora se intenta contabilizar igual en
todos los casos salvo `STARS = 5` (ya contabilizado), dejando que sea el
propio `FKK_RLS_POST_LOT` quien decida si el lote es válido — así su
error estándar (y el detalle por documento que capturamos) llega también
para esos casos, en vez de quedarse en un simple "revisar a mano".

**Implementado** en `ZFI_R_DEVOLUCIONES2_CLS` (`lcl_devoluciones2`):
`execute` resuelve `S_KEYR1` (obligatorio en pantalla) contra `DFKKRK`
(`SELECT keyr1 ... WHERE keyr1 IN gr_keyr1`, para quedarse solo con los
que existen de verdad) y `process_lot` decide la acción según la tabla de
arriba. Cuando `FKK_RLS_POST_LOT` falla, además del mensaje genérico
(`WRITE` del `KEYR1` + nombre de la FM + `sy-subrc`), captura el detalle
por documento tipo FP09 (ver sección siguiente). Parámetro `P_SIMU`
(pantalla de selección) para solo mostrar el `STARS` de cada lote
indicado sin tocar nada.

**Probado en DES** (`S_KEYR1 = 260825CDI111`, lote real ya cerrado):
- Con `P_SIMU`: `260825CDI111 -> STARS actual: 1 (simulación, no se toca
  nada)` — correcto, localiza el lote y lee `STARS` sin tocar nada.
- Sin `P_SIMU`: no vuelve a cerrar (ya estaba `STARS=1`), llama a
  `FKK_RLS_POST_LOT`, y salta la excepción `NOT_VALID` (`sy-subrc = 1`,
  distinta del `OTHERS` visto antes con `260825CDI110`, pero misma causa
  raíz: la mayoría de los 72 documentos del `_DEV` de prueba no existen en
  DES). El circuito completo del programa (localizar por `S_KEYR1`, leer
  `STARS`, decidir la acción, llamar al FM correcto, reportar el error)
  queda validado.

**Pendiente**: una contabilización real con éxito requiere un lote cuyos
documentos existan de verdad — probar en Integración, o con documentos
reales de DES.

## Premisas / Dependencias

- Depende de que exista un lote de devoluciones ya creado en `DFKKRK`
  (RU_02, `ZFI_R_DEVOLUCIONES_CREA`) — este programa no crea nada, solo
  cierra/contabiliza el `KEYR1` que se le indique en `S_KEYR1`.
- No depende de ningún fichero, tabla de trazabilidad (`ZFI_T_FILE_LOG`)
  ni clase reutilizada de `ZFI_R_DEVOLUCIONES` — todo ese motor
  (`RFKKKA00`, multicash, `ZFI_T_COBRO_CONF`) pertenece al enfoque
  descartado.
