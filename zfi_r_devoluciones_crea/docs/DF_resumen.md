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
construyó sobre `RFKKA00`/`FPB17` por una lectura incorrecta del DF (se
escribió "FP09/RFKKA00" como si fueran equivalentes, sin comprobarlo). El DF
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

**Ventaja de este enfoque frente al de `RFKKA00`**: si funciona, no hace falta
ningún dato que no tengamos — no requiere `AUSZUG`/`UMSATZ`, ni banco/IBAN/BIC
del deudor, ni número de secuencia de extracto. Solo los datos fijos del DF
(sociedad, motivo, cta. compensación) y, por posición, el importe y el nº de
documento del `_DEV`.

## Progreso de la depuración de `FP09` (en curso)

Confirmado en pantalla real (`FP09` → Crear → "Devoluciones: Datos prefijados
y status tratar"):

- **Nomenclatura del lote**: SAP la genera solo, no se teclea a mano. Con
  fecha 20.08.2026 generó `260819CDI110` — **12 caracteres**, no 13. La
  nomenclatura real es `AAMMDDCDI11x` (un solo dígito de secuencial), no
  `AAMMDDCDI11xx` como decía el DF literalmente.
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

**Pendiente**: consultar en `SE37` la interfaz (parámetros) de
`FKK_RLS_HDR_PREPARE`, `FKK_RLS_ITEM_PREPARE`, `FKK_RLS_ITEM_VALIDATE` y
`FKK_RLS_ITEM_SAVE`/`FKK_RLS_ITEM_SAVE_MASS`, para poder escribir la
llamada real desde ABAP.

## Enfoque descartado: `RFKKA00`/multicash (no usar, referencia solamente)

Se dejó el trabajo hecho documentado por si resulta útil más adelante (p.ej.
si `FP09` resultara no ser viable), pero **no es el camino a seguir** salvo
que se decida lo contrario explícitamente.

Generaba a mano los ficheros multicash `AUSZUG`/`UMSATZ` que espera `RFKKA00`
(el original `ZFI_R_DEVOLUCIONES` los genera con `RFKKSEPA_DD_RJCT` a partir
de un XML SEPA real, que aquí no aplica porque el `_DEV` no es XML). El
formato se dedujo de 6 ejemplos reales (`ZFI_T_FILE_LOG`, 4 bancos distintos)
sacados de Integración — ver el detalle campo a campo en el historial de git
de este fichero si hiciera falta recuperarlo. Quedaban varios campos sin
resolver (cuenta bancaria de cobro, BIC/IBAN/motivo del deudor, número de
secuencia del extracto, encaje de la nomenclatura `AAMMDDCDI11x` con el
límite de 6 caracteres de `RUNIDBS_KK`) — nunca se llegó a confirmar contra
una ejecución real de `RFKKA00`.

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
