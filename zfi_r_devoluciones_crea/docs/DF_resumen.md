# Resumen del Diseño Funcional — RU_02 (creación del lote de devoluciones)

**Documento origen:** CS_CDI_11_Procedimiento_Gestion_de_extornos (27/07/2026, con
comentarios de EVA). Ver también `../zfi_r_devoluciones2/docs/DF_resumen.md` para
el contexto completo de los 3 desarrollos.

## Requisito del DF

**RU_02 — Creación del lote de devoluciones** en SAP, transacción **`FP09`**, a
partir del fichero `_DEV`, con nomenclatura `AAMMDDCDI11x`, sociedad `1239`,
clase `DV`, motivo `Z01`, cta. compensación `4305500150`, una posición por línea
del fichero.

## Enfoque actual: pendiente de depurar `FP09`

El primer borrador de este programa (ver "Enfoque descartado" más abajo) se
construyó sobre `RFKKKA00`/`FPB17` por una lectura incorrecta del DF (se
escribió "FP09/RFKKKA00" como si fueran equivalentes, sin comprobarlo). El DF
pide **`FP09`**, que es la transacción de **alta manual de lote de pago**
(cabecera + posiciones una a una), no el motor de carga masiva de extractos
bancarios multicash que usa `ZFI_R_DEVOLUCIONES`.

Si `FP09` es una transacción de diálogo (pantalla interactiva, `CALL SCREEN`),
hace falta el mismo enfoque que ya funcionó para `ZFI_FM_PAYLOT_REVERSE`
(`FP08`) y `ZFI_FM_PAYMENT_LOT_CLARIFY2` (`FPCPL`): **depurarla para encontrar
la cadena real de módulos de función** que crea la cabecera del lote
(`DFKKZK`: sociedad `1239`, motivo `Z01`, cta. compensación `4305500150`) y
sus posiciones (`DFKKZP`: una por línea del `_DEV`, con el importe y el nº de
documento SAP que ya extrae `ZFI_R_ECOFI_SPLIT`).

**Pendiente, requiere depurar en SAP (no se puede hacer sin acceso al
sistema):**
- Localizar el `FORM`/cadena de FMs real detrás de `FP09`, siguiendo el mismo
  método documentado en `../zfi_fm_paylot_reverse/README.md` (depurar hasta
  encontrar dónde se contabiliza/crea de verdad, no solo dónde se calcula la
  propuesta).
- Confirmar la estructura exacta de `DFKKZK`/`DFKKZP` a rellenar y qué campos
  son obligatorios.

**Ventaja de este enfoque frente al de `RFKKKA00`**: si funciona, no hace falta
ningún dato que no tengamos — no requiere `AUSZUG`/`UMSATZ`, ni banco/IBAN/BIC
del deudor, ni número de secuencia de extracto. Solo los datos fijos del DF
(sociedad, motivo, cta. compensación) y, por posición, el importe y el nº de
documento del `_DEV`.

## Progreso de la depuración de `FP09` (en curso)

Confirmado en pantalla real (`FP09` → Crear → "Devoluciones: Datos prefijados
y status tratar"):

- **Nomenclatura del lote**: `260819CDI110` (12 caracteres) fue en
  realidad **tecleado a mano** en la pantalla de `FP09` (un valor
  propuesto de 13 caracteres, `260819CDI1101`, que el campo cortó a 12) —
  corrección de una nota anterior de este documento que decía lo
  contrario sin base real. Probado después con el programa (`_R_
  DEVOLUCIONES_CREA` en DES): sin exit de cliente, `FKK_RLS_HDR_PREPARE`
  cae al formato estándar de SAP `RL`+fecha+secuencial (`RL2026082103`).
  El límite de **12 caracteres** de `KEYR1` sí es real y confirmado (el DF
  pide `AAMMDDCDI11xx`, 13 caracteres, que no caben).

### Nomenclatura real del lote: se calcula en la propia clase, sin exit

`FKK_RLS_HDR_PREPARE` (código fuente, ver más abajo) solo genera un
`KEYR1` cuando el campo llega vacío — si ya viene relleno, se limita a
comprobar que no exista:

```abap
IF C_DFKKRK-KEYR1 IS INITIAL.
  PERFORM ('GENERATE_RLS_KEY') IN PROGRAM (PROG_NAME) IF FOUND
                               CHANGING C_DFKKRK-KEYR1.
  IF C_DFKKRK-KEYR1 IS INITIAL.
    PERFORM SAMPLE_SP_GENERATE_RLS_KEY CHANGING C_DFKKRK-KEYR1.  " RL+fecha+secuencial
  ENDIF.
ELSE.
  SELECT SINGLE KEYR1 FROM DFKKRK ... WHERE KEYR1 = C_DFKKRK-KEYR1.
  IF SY-SUBRC = 0. MESSAGE E403 RAISING LOT_EXISTS. ENDIF.
  " ... y comprobación en DFKKRK_ARCKEY (archivados)
ENDIF.
```

`PROG_NAME` está hardcodeado en el propio código estándar de SAP como
`'ZFKR2_POOL'` (confirmado buscando la variable en todos los includes de
`SAPLFKR2` con `Ctrl+F` → "en todos los includes") — se valoró crear ese
programa de "soft-exit" para que generase `AAMMDDCDI11x` automáticamente,
pero se descartó: `PROG_NAME` es **global para todo el grupo de función
`FKR2`**, así que ese exit se dispararía para cualquier lote creado en el
sistema (`FP09` a mano por otro motivo, otro desarrollo Z), no solo desde
`CDI_11` — y aunque se puede acotar con una marca en memoria ABAP, es más
riesgo e indirección de la que hace falta para algo que solo necesita nuestro
programa.

En su lugar, `create_lot` calcula el `KEYR1` **él mismo** (método
`generate_keyr1`, `ZFI_R_DEVOLUCIONES_CREA_CLS`) y se lo pasa ya relleno a
`FKK_RLS_HDR_PREPARE`, tomando el camino del `ELSE` de arriba — el mismo
que se sigue cuando se teclea a mano en `FP09`. Construye
`AAMMDDCDI11x` (secuencial de 1 dígito por el límite de 12 caracteres de
`KEYR1` — ver arriba) con un único `SELECT MAX( KEYR1 )` contra `DFKKRK`
filtrando por el prefijo del día (`LIKE`, sin `@`, ver `CLAUDE.md`) en vez
de comprobar candidato a candidato; si se agotan los 10 posibles (0-9),
devuelve vacío y deja que `FKK_RLS_HDR_PREPARE` caiga al generador
estándar de SAP en vez de fallar. Queda todo contenido en la clase, sin
tocar nada compartido con el resto del sistema.

**Pendiente confirmar con el funcional**: el secuencial de 1 dígito (no 2
como pide el DF literalmente) es un límite técnico del campo, no una
decisión de diseño — hay que validar que sea aceptable (máx. 10
lotes/día).

**Probado con éxito** (DES, modo Upload, mismo `_DEV` de 72 líneas):
`generate_keyr1` propuso `260824CDI110` (primer lote del día con esta
nomenclatura), `FKK_RLS_HDR_PREPARE` lo aceptó tal cual (no generó nada,
solo comprobó que no existiera) y el lote se creó con las 72 posiciones
correctas.

- **Clase de documento**: ya viene `DV` por defecto — coincide con el DF.
- **Clave de reconciliación**: se autorrellena igual que el nº de lote.
- Campos de cabecera vistos: Sociedad, División, Clase de documento, Clave
  de reconciliación, Moneda, Motivo de devolución, Fecha de documento/
  contabilización/valor, Clase de contab. (dropdown, p.ej. "Anular pago"),
  Gestión devoluciones ampliada, indicadores de impuestos. La cta. de
  compensación está en una pestaña aparte ("Cta.compensación y gestión").
- Las posiciones se añaden con el botón **"Posiciones nuevas"**.
- **`Banco propio`/`ID de cuenta` se derivan automáticamente de
  `Cta.compensación devoluciones`** (customizing, no son datos
  independientes a rellenar a mano). **`4305500150` (la cuenta que pide el
  DF) no está configurada en DES** — al ponerla, esos dos campos quedan en
  blanco. Con `4305500250` sí deriva (`Banco propio = CXB01`, `ID de cuenta
  = CXB01`). **Pendiente real de configuración** (Basis/funcional): dar de
  alta `4305500150` en DES, o confirmar si ese sigue siendo el valor
  correcto. Para la depuración se sigue con `4305500250`, que sí funciona
  — la corrección del dato final es un asunto aparte que no bloquea
  encontrar la cadena de FMs.

Pendiente: rellenar con los datos de prueba (sociedad `1239`, moneda `EUR`,
motivo `Z01` si existe como valor válido, cta. `4305500150`), añadir 2-3
posiciones de prueba (ver tabla de nº documento/importe más abajo) y
depurar el botón final de grabar.

### Datos de prueba para depurar (reales, del `_DEV` de `zfi_r_ecofi_split`)

| Nº documento | Importe |
|---|---|
| `491000011392` | 60,49 € |
| `491000011455` | 30,34 € |
| `491000011482` | 14,59 € |

**Importante**: en una posición de devolución el importe hay que meterlo en
**negativo** (`-60,49`, no `60,49`) — probado en Integración con el primer
documento: en positivo SAP da el error `>4703` ("Existe una devolución para
un abono... verifique el signo"), porque en positivo lo interpreta como un
abono en la cuenta bancaria, no como una devolución.

**Nº de documento de prueba**: los nº de documento reales del `_DEV`
(sociedad `1239` de Integración) no existen en DES — para depurar en DES hay
que buscar uno real en la sociedad `1239` que sí exista (tabla `DFKKZP`,
campo `OPBEL` no vacío — esa tabla son posiciones de lote de pago, así que
cualquier `OPBEL` de ahí es, por definición, un documento de pago válido).
En DES había muy pocos registros (7) — la depuración final se hizo en
Integración en su lugar (mismo código, no afecta a la cadena de FMs).

### Cadena real encontrada (clase `LCL_RLOT`, pool de funciones `FKR2DLG`)

Depurando el botón "Grabar" de `FP09`: el objeto que gestiona el lote en
pantalla es `o_rlot`, una instancia de **`LCL_RLOT`**, clase **local** del
pool de funciones **`FKR2DLG`** (grupo de función `FKR2`) — **no se puede
instanciar/llamar desde fuera** (no está en `SE24`, es privada de ese
programa).

`o_rlot->save( )` hace, en este orden:

1. `COMPLETE_CHECK` (método interno, valida antes de grabar).
2. Si es lote nuevo: **`CALL FUNCTION 'FKK_RLS_HDR_SAVE'`** — `CHANGING
   C_DFKKRK = HEADER` (estructura `DFKKRK`, es la cabecera del lote). **Este
   FM sí es público** — se puede llamar directamente desde nuestro código
   para grabar la cabecera.
3. `SAVE_POSITIONS` (método interno) — **aquí NO hay ningún FM**: hace
   `INSERT DFKKRP FROM TABLE IT_DFKKRP.` e `INSERT DFKKRP3 FROM TABLE
   IT_DFKKRP3.` directos a tabla, seguido de `COMMIT WORK.`. `IT_DFKKRP` se
   monta con `MOVE-CORRESPONDING` desde una tabla interna `T_LINES`
   (estructura `TY_RLSLINE`) que ya viene con todos los campos calculados
   de antes (incluido `KEYR1`/`POSRA`/`LFDNR`) — esa parte del cálculo
   ocurre en otro punto de la clase que aún no se ha depurado (donde se
   procesa la rejilla "Posiciones nuevas" al teclear).
4. `UPDATE_STATS` (interno) + `FKK_RLS_PROPERTY_SET` (marca `DIALOG=X`,
   probablemente no aplica a un uso por programa).
5. Si no es lote nuevo: `FKK_RLS_HDR_EDIT` (edición) y, si cambió algo,
   otra vez `FKK_RLS_HDR_SAVE`.

**Corrección**: aunque `SAVE_POSITIONS` (el método interno de `LCL_RLOT`)
hace `INSERT` directo, **sí existe una API pública completa** para todo
esto en el grupo de función `FKR2` (dominio "Rückläuferstapel" = lote de
devoluciones/extornos — es literalmente nuestro caso). Se obtuvo el listado
completo de FMs del grupo por `SE80`; los relevantes:

**Para crear el lote (este programa, RU_02):**
- `FKK_RLS_HDR_PREPARE` — Vorbereiten des Headers für einen RLS (prepara la cabecera)
- `FKK_RLS_HDR_SAVE` — Sichern eines Rückläuferstapel-Headers (graba la cabecera; ya confirmado que es el que usa `FP09`)
- `FKK_RLS_ITEM_PREPARE` — Bereitet eine neue Position für Eingabe vor (prepara una posición nueva — candidato a calcular `KEYR1`/`POSRA`/`LFDNR`)
- `FKK_RLS_ITEM_VALIDATE` — Überprüft, ob eine Rückläuferzeile vernünftige Daten enthält (valida una posición)
- `FKK_RLS_ITEM_SAVE` — Speichern einer Rückläuferzeile (graba una posición)
- `FKK_RLS_ITEM_SAVE_MASS` — Massenspeicherung von Rückläufer-Zeilen (graba varias posiciones de golpe — probablemente el más adecuado para procesar todas las líneas del `_DEV` de una vez)

**Para cerrar/contabilizar (relevante para el programa 3, `ZFI_R_DEVOLUCIONES2`, no este):**
- `FKK_RLS_CLOSE` — Schließt einen Rückläuferstapel
- `FKK_RLS_POST_LOT` / `FKK_RLS_POST_ITEM` — Buchen eines Rückläuferstapels / einer einzelnen Position

**Otros del grupo que pueden hacer falta**: `FKK_RLS_EXISTS` (comprobar si
el lote ya existe), `FKK_RLS_LOCK`/`FKK_RLS_UNLOCK` (bloqueo del lote),
`FKK_RLS_ITEMS_READ` (releer posiciones), `FKK_RLS_ITEM_DELETE`.

### Interfaces confirmadas (`SE37`)

```
FKK_RLS_HDR_PREPARE
  CHANGING  C_DFKKRK  LIKE DFKKRK
  EXCEPTIONS NO_AUTHORIZATION, LOT_EXISTS, LOCKED, FAILURE

FKK_RLS_ITEM_PREPARE
  IMPORTING I_KEYR1       LIKE DFKKRK-KEYR1
            I_DFKKRK      LIKE DFKKRK
            I_LINE_COUNT  TYPE I DEFAULT 1
  EXPORTING E_DFKKRP      LIKE DFKKRP
  TABLES    T_DFKKRP      LIKE DFKKRP
  EXCEPTIONS FAILURE

FKK_RLS_ITEM_VALIDATE
  IMPORTING I_DFKKRK   LIKE DFKKRK
  CHANGING  C_DFKKRP   LIKE DFKKRP
  TABLES    T_DFKKRP3  LIKE DFKKRP3

FKK_RLS_ITEM_SAVE
  IMPORTING I_DFKKRP    LIKE DFKKRP
            I_DONTCHECK TYPE CHAR1 DEFAULT SPACE
  CHANGING  C_DFKKRK    LIKE DFKKRK
  TABLES    T_DFKKRP3   LIKE DFKKRP3
  EXCEPTIONS HEADER_UPDATE_FAILED, HEADER_NOT_FOUND, LOCK_FAILED, RP3CHECK_FAILED

FKK_RLS_ITEM_SAVE_MASS
  IMPORTING I_DONTCHECK   TYPE CHAR1 DEFAULT SPACE
  CHANGING  C_DFKKRK      LIKE DFKKRK
  TABLES    T_DFKKRP      LIKE DFKKRP
            T_DFKKRP_DEL  LIKE DFKKRP
            T_DFKKRP3     LIKE DFKKRP3
  EXCEPTIONS NO_ENTRIES, HEADER_UPDATE_FAILED, UPDATE_FAILED, DELETE_FAILED, INSERT_FAILED
```

**Flujo propuesto** para este programa (RU_02):

1. Montar `ls_dfkkrk` con lo que ya sabemos (sociedad `1239`, motivo `Z01`,
   cta. compensación, moneda `EUR`...).
2. `CALL FUNCTION 'FKK_RLS_HDR_PREPARE' CHANGING c_dfkkrk = ls_dfkkrk.`
   (deriva `KEYR1` y defaults, incluido banco propio/ID cuenta si es igual
   que en pantalla).
3. `CALL FUNCTION 'FKK_RLS_HDR_SAVE' CHANGING c_dfkkrk = ls_dfkkrk.`
4. `CALL FUNCTION 'FKK_RLS_ITEM_PREPARE'` con `i_line_count` = nº de líneas
   del `_DEV`, para obtener `lt_dfkkrp` con las plantillas ya numeradas.
5. Recorrer `lt_dfkkrp` y rellenar cada línea con el importe (**en
   negativo**, confirmado con el error `>4703`) y la referencia del
   documento del `_DEV`.
6. (Opcional) `FKK_RLS_ITEM_VALIDATE` línea a línea.
7. `CALL FUNCTION 'FKK_RLS_ITEM_SAVE_MASS'` con `t_dfkkrp` = todas las
   líneas, `t_dfkkrp_del`/`t_dfkkrp3` vacías.
8. `COMMIT WORK` (los FMs no parecen comitear ellos solos, a juzgar por
   cómo lo hace `LCL_RLOT->save()` a mano tras el `INSERT`).

### Campos confirmados (`SE11`)

**`DFKKRK`** (cabecera): `BUKRS`=sociedad (`1239`), `RLGRD`=motivo de
devolución (`Z01`), `RLSKO`=cta. bancaria de compensación para devolución
(`4305500150`/`4305500250` en DES), `WAERS`=moneda, `BLART`=clase doc.
(`DV`), `HBKID`/`HKTID`=banco propio/clave cuenta (se derivan solos de
`RLSKO`, confirmado en pantalla), `KEYR1`=lote (lo calcula
`FKK_RLS_HDR_PREPARE`, no se rellena a mano).

**`DFKKRP`** (posición): `BETRR`=importe de devolución (**en negativo**,
confirmado con el error `>4703`). Para el documento original hay dos
campos relacionados, sin confirmar aún cuál usar directamente en las
llamadas a los FM (en pantalla se usa el primero):
- `SELT1`/`SELW1` = tipo de selección / valor a buscar — es lo que ya
  probamos en pantalla (`T.`=`B`, `Val.selección`=nº documento), un
  mecanismo de búsqueda.
- `OPBEL` = "Doc.pago p.devoluciones" — pinta a ser el campo final donde
  queda el documento de pago que se devuelve, probablemente relleno tras
  resolver la búsqueda anterior.

También en `DFKKRP`: `BANKL`/`BANKK`/`BANKN`/`IBAN` (banco/IBAN del
deudor) — **si se derivan solos al indicar el documento de pago original**
(vía `SELT1`/`SELW1` u `OPBEL`), esto resolvería completamente el hueco que
teníamos con el enfoque `RFKKKA00` (el `_DEV` no lleva esos datos). Falta
confirmar completando el flujo en pantalla hasta Grabar de verdad.

`RLBEL`/`URBEL` en `DFKKRP` parecen campos de salida (nº del documento de
devolución/abono generado tras contabilizar), no de entrada.

**Confirmado con prueba real en Integración** (lote `260819CDI110`, 3
posiciones, grabado con éxito — "Se han grabado los datos. Se puede
proseguir el tratamiento"). Consultado `DFKKRP` por `SE16N`:

| KEYR1 | POSRA | BANKL/BANKK/BANKN/IBAN | OPBEL | HBKID/HKTID | SELT1 | RLGRD | BETRR | SELW1 |
|---|---|---|---|---|---|---|---|---|
| 260819CDI110 | 000001 | (vacíos) | (vacío) | CXB01/CXB01 | B | Z01 | 60,49- | 491000011392 |
| 260819CDI110 | 000002 | (vacíos) | (vacío) | CXB01/CXB01 | B | Z01 | 30,34- | 491000011455 |
| 260819CDI110 | 000003 | (vacíos) | (vacío) | CXB01/CXB01 | B | Z01 | 14,59- | 491000011482 |

**Conclusión**: `BANKL`/`BANKK`/`BANKN`/`IBAN`/`OPBEL` se quedan vacíos y
el lote se graba igualmente sin error — **no hacen falta para crear el
lote** (RU_02). Probablemente se resuelven en el cierre/contabilización
(RU_03, `ZFI_R_DEVOLUCIONES2`), no en la creación. Esto cierra el hueco de
datos que arrastrábamos desde el enfoque `RFKKKA00` (banco/IBAN del deudor
no disponibles en el `_DEV`) — **con el enfoque `FP09`/`FKK_RLS_*` no
hacen falta en absoluto**.

**Campos mínimos confirmados para crear el lote:**
- Cabecera (`DFKKRK`): `BUKRS`, `RLGRD`, `RLSKO`, `WAERS` (`BLART` ya viene
  `DV` por defecto).
- Posición (`DFKKRP`), por cada línea del `_DEV`: `BETRR` (importe, **en
  negativo**), `SELT1` = `B`, `SELW1` = nº de documento SAP.

Con esto ya se puede escribir el código ABAP real (ver
`../src/ZFI_R_DEVOLUCIONES_CREA_CLS.abap`).

### Primera prueba real del programa (DES): `FKK_RLS_ITEM_PREPARE` capa a `MAX_LINES`

Primera ejecución completa de `ZFI_R_DEVOLUCIONES_CREA` (modo Upload, DES,
tras dar de alta `ZFI_T_CONSTANTS`/`ZFI_T_PROCESS`) con un `_DEV` de 72
líneas: `FKK_RLS_ITEM_PREPARE` devolvió solo 50 posiciones de las 72
pedidas. Visto el código fuente del FM (`SE37`):

```abap
IF I_LINE_COUNT < 0. I_LINE_COUNT = 1. ENDIF.
IF I_LINE_COUNT > MAX_LINES. I_LINE_COUNT = MAX_LINES. ENDIF.
...
I = I_DFKKRK-ANZPO + 1.
DO I_LINE_COUNT TIMES.
  ...
  P_DFKKRP-POSRA = I.
  I = I + 1.
  ...
ENDDO.
```

`MAX_LINES` es una variable/constante global del grupo de función `FKR2`
que capa `I_LINE_COUNT` — con el `_DEV` de prueba, 50. La numeración de
`POSRA` (nº de posición) arranca en `I_DFKKRK-ANZPO + 1`, es decir,
depende del nº de posiciones que le digamos que ya tiene el lote
(`ANZPO`), no de ningún buffer interno oculto — por tanto es seguro llamar
al FM varias veces seguidas para completar el pedido: en cada vuelta se
actualiza `ls_dfkkrk-anzpo` con las posiciones ya conseguidas y se pide
solo lo que falta, hasta llegar al total de líneas del `_DEV`. Implementado
como bucle `DO` en `create_lot` (`ZFI_R_DEVOLUCIONES_CREA_CLS`).

### Depurando RU_03: el lote se crea pero no se puede cerrar (falta `OPBEL`)

Al empezar a depurar el cierre/contabilización del lote (RU_03,
`ZFI_R_DEVOLUCIONES2`) con un lote ya creado por este programa
(`260824CDI110`, 72 posiciones), `FP09` → "Cerrar" dio error:

```
No existen entradas para la remesa 260824CDI110
Nº mensaje: >2549
Diagnóstico: El cierre de una remesa de devoluciones sólo tiene sentido
si esta remesa también contiene entradas. Éste no es el caso.
```

`SELT1`='B'/`SELW1`=nº documento (lo único que rellena `create_lot`) es
solo un **criterio de búsqueda**, no el documento resuelto — `OPBEL`
("Doc.pago p.devoluciones") se queda vacío. Comprobado con `SE16N`: las
72 posiciones tienen `OPBEL` vacío; eso es lo que hace que ninguna cuente
como "entrada" para poder cerrar.

Depurando en `FP09` (`Tratar` → `Posiciones nuevas`, con una posición
nueva añadida a mano) con un **breakpoint de módulo de función** en
`FKK_RLS_ITEM_VALIDATE` (`SE37` → módulo de función → Set breakpoint, más
fiable que adivinar el momento exacto con `/h`): la llamada se dispara al
teclear la posición nueva (antes de Grabar), y confirma:

- `C_DFKKRP` **antes**: `OPBEL` vacío, `SELT1`='B', `SELW1`=nº documento
  tecleado.
- `C_DFKKRP` **después**: `OPBEL` = el mismo nº de documento (resuelto).
  `BANKL`/`BANKK`/`BANKN`/`IBAN` siguen vacíos (no hacen falta, ya lo
  sabíamos).
- `T_DFKKRP3` entra y sale **vacía** — no es lo que hace falta rellenar
  (no escribe nada en BD tampoco, seguro llamarla antes de persistir
  nada).
- Excepción `NOT_VALID` si el documento no existe/no es válido (probado
  con un nº de documento inventado).

**Fix aplicado a `create_lot`**: se añade un bucle llamando a
`FKK_RLS_ITEM_VALIDATE` para cada posición (`i_dfkkrk` = cabecera,
`c_dfkkrp` = la posición, `t_dfkkrp3` sin usar) **antes** de
`FKK_RLS_HDR_SAVE`/`FKK_RLS_ITEM_SAVE_MASS` — como ningún FM hasta ese
punto escribe en BD, si una posición da `NOT_VALID` se aborta todo el
lote sin haber tocado la base de datos, sin dejar nada a medias. Mismo
criterio de todo-o-nada que ya usan `ZFI_R_DEVOLUCIONES_CREA`/
`ZFI_R_DEVOLUCIONES` a nivel de fichero completo (ninguno de los 3
desarrollos tiene granularidad de error por línea).

### Segundo intento fallido: `ITEM_VALIDATE` necesita la cabecera ya en BD

Primera implementación del fix: `FKK_RLS_ITEM_VALIDATE` para todas las
posiciones **antes** de `FKK_RLS_HDR_SAVE` (para poder abortar sin haber
escrito nada en BD si un documento no era válido). Probado en DES: lote
`260824CDI111` creado sin error, pero `OPBEL` seguía **vacío** — puesto
un breakpoint justo después de la llamada dentro de nuestro propio
`create_lot` (en vez de en `FP09`), se confirma que `C_DFKKRP-OPBEL` no
se rellena ahí, sin ningún error (`sy-subrc` = 0 igualmente).

Diferencia con la prueba manual que sí funcionó: en `FP09` siempre se
probó sobre un lote **ya existente** (entrando en "Tratar" de un lote
creado en una transacción anterior, ya comiteado). Conclusión:
`FKK_RLS_ITEM_VALIDATE` necesita que la cabecera ya esté **persistida en
BD** (no solo preparada en memoria) para poder resolver el documento —
probablemente hace una lectura a BD por `KEYR1`/`FIKEY` en vez de usar
solo lo que se le pasa en `I_DFKKRK`.

**Fix corregido**: `FKK_RLS_HDR_SAVE` + `COMMIT WORK` se llaman ya justo
después de `FKK_RLS_HDR_PREPARE` (el `COMMIT WORK` es necesario porque
`HDR_SAVE` por sí sola solo deja el `INSERT` en tarea de actualización,
no persistido hasta el siguiente commit) — **antes** de `ITEM_PREPARE`/
`ITEM_VALIDATE`, no después. Coste: si una posición falla `NOT_VALID`, la
cabecera ya queda creada en BD sin posiciones (recuperable borrando el
lote vacío desde `FP09`, tal como indica el propio mensaje `>2549` de
SAP) — ya no es un abort 100% limpio como se pretendía, pero es el único
orden con el que `ITEM_VALIDATE` resuelve `OPBEL` de verdad.

**Pendiente**: repetir la prueba completa (crear lote con el fix
corregido → confirmar `OPBEL` relleno por `SE16N` → `FP09` → Cerrar →
Contabilizar) para confirmar que ya se puede cerrar, y seguir depurando
qué FMs reales usa "Cerrar"/"Contabilizar" para RU_03
(`ZFI_R_DEVOLUCIONES2`) — muy probablemente `FKK_RLS_CLOSE`/
`FKK_RLS_POST_LOT` del mismo grupo de función, no `RFKKKA00` (ver
`../zfi_r_devoluciones2/docs/DF_resumen.md`).

### Configuración vía `ZFI_T_CONSTANTS` (sin hardcode)

`BUKRS`/`RLGRD`/`RLSKO` (sociedad, motivo, cta. compensación) no van como
`CONSTANTS` en la clase — se leen de la tabla genérica `ZFI_T_CONSTANTS`
(reutilizada, ya existe en el sistema) con un único método `get_constants`
llamado al principio de `execute( )`, con un solo `SELECT * ... INTO
TABLE` (no `SELECT SINGLE` por constante) filtrando por las claves propias
de la tabla:

```
APPLICATION_ID = 'FICA'
PROCESS_ID     = 'DEVOL_CREA'
SUB_PROCESS_ID = <blanco>
ACTIVE         = 'X'
```

(`APPLICATION_ID` no es texto libre: `zfi_de_application_id` tiene una
tabla de verificación/valores fijos detrás. `'CDI_11'` — el nombre del
proyecto — no está dado de alta ahí; se usa `'FICA'`, que sí es un valor
válido.)

y un `LOOP` + `CASE` sobre `CONSTANT_ID` (`SOCIEDAD`, `MOTIVO`,
`CTA_COMPENSACION`) para rellenar `gv_sociedad`/`gv_motivo`/`gv_cta_comp`.
Si falta alguna, el programa aborta con mensaje antes de tocar `FKK_RLS_*`.

Motivo del cambio: los valores hardcodeados anteriores (`co_sociedad`,
`co_motivo`, `co_cta_comp`) obligaban a editar y reactivar la clase para
cambiar un dato de configuración entre sistemas (p.ej. la cta.
`4305500150` del DF frente a `4305500250`, la única que deriva banco/
cuenta en DES — ver más arriba). Con `ZFI_T_CONSTANTS` es una fila de
customizing por sistema, sin tocar código.

**Filas a dar de alta** (una vez por sistema, con el `CONSTANT_VALUE`
correcto en cada uno; en DES ya están dadas de alta y probadas con éxito —
ver más abajo):

| `CONSTANT_ID` | DES | Integración |
|---|---|---|
| `SOCIEDAD` | `1239` | `1239` |
| `MOTIVO` | `Z01` (confirmado válido, prueba real end-to-end en DES) | `Z01` |
| `CTA_COMPENSACION` | `4305500250` (la que deriva banco/cuenta en DES; `4305500150` del DF no está configurada) | `4305500150` (probado con éxito, ver tabla de test más abajo) |
| `RUTA_LOGICA` | `ZFICA_COBROS_ECOFI` (no existe todavía) o cualquier otra ruta lógica ya existente en DES, para poder probar el modo Server sin esperar a que se cree | igual |
| `MONEDA` | `EUR` | `EUR` |

Además, `APPLICATION_ID`/`PROCESS_ID` no son texto libre: `PROCESS_ID`
también valida contra una tabla de verificación propia (`ZFI_T_PROCESS`,
por `APPLICATION_ID`) — `DEVOL_CREA` tampoco estaba ahí, se dio de alta
como fila nueva (`APPLICATION_ID='FICA'`, `PROCESS_ID='DEVOL_CREA'`,
`ACTIVE='X'`), igual que ya hay `CONTRATAS`, `MIGRACION`, `VULNERABLE`,
etc. — es una tabla de mantenimiento del equipo, no un dominio fijo de SAP.

`RUTA_LOGICA` y `MONEDA` se añadieron por el mismo motivo que las tres
anteriores: eran `CONSTANTS` hardcodeadas en la clase
(`co_logical_path`/`co_eur_tag`) y, a diferencia de `co_processed_dir`/
`co_error_dir` (que son solo nombres de subcarpeta internos, no datos de
configuración), sí son valores que conviene poder cambiar sin tocar
código — en concreto para poder probar el modo Server apuntando a una
ruta lógica que ya exista (mientras `ZFICA_COBROS_ECOFI` no se cree en
ningún sistema), o repetir la prueba con un fichero en otra moneda sin
reactivar la clase. `MONEDA` se usa tanto para `DFKKRK-WAERS` (moneda del
lote) como para localizar el importe dentro de la línea del `_DEV`
(`parse_dev_lines` busca ese mismo tag en el texto).

## Enfoque descartado: `RFKKKA00`/multicash (no usar, referencia solamente)

Se dejó el trabajo hecho documentado por si resulta útil más adelante (p.ej.
si `FP09` resultara no ser viable), pero **no es el camino a seguir** salvo
que se decida lo contrario explícitamente.

Generaba a mano los ficheros multicash `AUSZUG`/`UMSATZ` que espera `RFKKKA00`
(el original `ZFI_R_DEVOLUCIONES` los genera con `RFKKSEPA_DD_RJCT` a partir
de un XML SEPA real, que aquí no aplica porque el `_DEV` no es XML). El
formato se dedujo de 6 ejemplos reales (`ZFI_T_FILE_LOG`, 4 bancos distintos)
sacados de Integración — ver el detalle campo a campo en el historial de git
de este fichero si hiciera falta recuperarlo. Quedaban varios campos sin
resolver (cuenta bancaria de cobro, BIC/IBAN/motivo del deudor, número de
secuencia del extracto, encaje de la nomenclatura `AAMMDDCDI11x` con el
límite de 6 caracteres de `RUNIDBS_KK`) — nunca se llegó a confirmar contra
una ejecución real de `RFKKKA00`.

## Premisas / Dependencias

- Depende de que exista el fichero `_DEV` (RU_01, `zfi_r_ecofi_split`), con el
  formato de línea ya validado contra 2 ficheros ECOFI reales (ver su propio
  `docs/DF_resumen.md`). El parseo de cada línea (nº de documento SAP +
  importe) ya está hecho y sirve igual con el enfoque `FP09` — es
  independiente de cómo se cree el lote después.
- `ZFI_T_FILE_LOG`, `zfi_cl_update_file_log`, `zxx_cl_msg_logs`,
  `zxx_cl_generic_on_memory`, `zxx_cl_file_utils` se reutilizan tal cual del
  programa original `ZFI_R_DEVOLUCIONES` (mismas clases ya existentes en el
  sistema) — siguen aplicando para la traza en `ZFI_T_FILE_LOG` y el
  escaneo de ficheros, independientemente del motor de creación del lote.
