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
parámetro (no hay `TABLES` de mensajes en la firma) — el desglose que se
ve en pantalla en `FP09` sale de algún sitio aparte (probablemente log de
aplicación, quizá vía métodos como `GET_ERR_ITEMS_TABLE`/`GET_LASTERROR`
de `LCL_RLOT`, sin confirmar). **Decisión de gestión de errores**: no
merece la pena perseguir el detalle — igual que el resto del código de
este proyecto (`ev_error` genérico con el nombre de la FM y `sy-subrc`),
si `FKK_RLS_POST_LOT` no devuelve `0` se marca `ERROR` sin más detalle;
quien necesite ver qué documento en concreto falló puede entrar a `FP09`
con el nº de lote.

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

1. **Qué lote cerrar/contabilizar**: no hay `_DEV` que leer aquí — RU_02
   (`ZFI_R_DEVOLUCIONES_CREA`) ya deja trazado el `KEYR1` del lote creado en
   `ZFI_T_FILE_LOG` (campo `file_name_header`, reutilizado por no haber uno
   dedicado — ver `zfi_r_devoluciones_crea/src/ZFI_R_DEVOLUCIONES_CREA_CLS.abap`).
   Este programa debería recorrer los registros de `ZFI_T_FILE_LOG` con
   lote creado (`status = 'PROCESADO'`) y pendientes de cerrar/contabilizar,
   no procesar ficheros.
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
6. **Traza en `ZFI_T_FILE_LOG`**: se usa para **localizar** los lotes
   pendientes (`SELECT` por `BUSINESS_DESC = 'EXT'` — mismo valor que usa
   `ZFI_R_DEVOLUCIONES_CREA` — y `STATUS = 'PROCESADO'`), pero **no** para
   marcar si ya se cerró/contabilizó: el dominio de `STATUS`
   (`PENDIENTE`/`MULTICASH`/`PROCESADO`/`ERROR`/`DUPLICADO`, fijo, sin
   valores libres) no tiene ningún estado para eso. La fuente de verdad
   es **`DFKKRK-STARS`** (ver sección siguiente) — se comprueba en cada
   ejecución, sin depender de actualizar `ZFI_T_FILE_LOG`.
7. **Sin ruta lógica de fichero**: al no leer ningún `_DEV`, no aplica
   `co_logical_path` aquí — el "modo Server" no tiene sentido para este
   desarrollo (no hay ficheros de entrada, solo lotes SAP pendientes).
8. **Alta del objeto en el sistema de transporte** correspondiente al
   proyecto.

### `DFKKRK-STARS`: la fuente de verdad del estado del lote

`ZFI_T_FILE_LOG-STATUS` no distingue "lote cerrado" de "lote
contabilizado" (dominio fijo, ver punto 6). En su lugar se usa
`DFKKRK-STARS` (estado real del lote en FI-CA), con ayuda de búsqueda
confirmada por `SE16N`:

| `STARS` | Significado | Acción |
|---|---|---|
| (blanco) | Aún se pueden añadir devoluciones (abierto) | `FKK_RLS_CLOSE` |
| `1` | Ya no se pueden modificar devoluciones (cerrado) | `FKK_RLS_POST_LOT` |
| `2` | Contabilizaciones planificadas | no se toca |
| `3` | Contabilizaciones incompletas | no se toca |
| `4` | Contabilizaciones realizadas: se requiere trabajo de repaso | no se toca |
| `5` | Contabilizaciones realizadas | no se toca (ya está hecho) |
| `6` | Creación automática cancelada | no se toca |
| `9` | Lote archivado | no se toca |

Confirmado con datos reales: `260825CDI110` (se intentó contabilizar y
falló para casi todos los documentos, DES) quedó con `STARS = 3`
("incompletas" — encaja). `260825CDI111` (solo se cerró, nunca se
contabilizó) quedó con `STARS = 1`.

**Implementado** en `ZFI_R_DEVOLUCIONES2_CLS` (`lcl_devoluciones2`):
método `execute` hace un único `SELECT` a `ZFI_T_FILE_LOG` (mismo patrón
que `get_constants` en `ZFI_R_DEVOLUCIONES_CREA_CLS` — sin `SELECT
SINGLE` en bucle), y `process_lot` decide la acción según `STARS` con la
tabla de arriba. Sin gestión de errores por detalle (ver antes) — `WRITE`
del `KEYR1` + el error genérico de la FM que falle. Parámetro `P_SIMU`
(pantalla de selección) para solo mostrar el `STARS` de cada lote
pendiente sin tocar nada.

**Pendiente de probar** — dos cosas antes de poder hacerlo:
1. Confirmar que `BUSINESS_DESC` es el campo real donde
   `zfi_cl_update_file_log` guarda `iv_process` (deducción de los campos
   de la tabla, no confirmada con un registro real).
2. Ahora mismo no hay ningún registro en `ZFI_T_FILE_LOG` para este
   proceso: las pruebas de `ZFI_R_DEVOLUCIONES_CREA` se han hecho en modo
   **Upload**, que a propósito no deja traza ahí (solo el modo Server, que
   sigue bloqueado por la ruta lógica `ZFICA_COBROS_ECOFI`). Para probar,
   insertar una fila a mano en `ZFI_T_FILE_LOG` apuntando a un lote real
   ya creado (p.ej. `260825CDI111`, `STARS = 1`).

## Premisas / Dependencias

- Depende de que exista el fichero `_DEV` (RU_01), con el formato de línea que se
  acuerde (concepto reducido al nº de documento PG, según propone EVA).
- `ZFI_T_FILE_LOG`, `ZFI_T_COBRO_CONF`, `zfi_cl_update_file_log`,
  `zxx_cl_msg_logs`, `zxx_cl_file_utils`, `zxx_cl_generic_on_memory` se reutilizan
  tal cual del programa original (mismas clases/tablas ya existentes en el sistema).
