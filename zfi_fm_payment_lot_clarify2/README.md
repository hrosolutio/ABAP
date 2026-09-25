# ZFI_FM_PAYMENT_LOT_CLARIFY2 — Clarificación de transferencias pendientes en SAP

Implementación del servicio RFC descrito en el Diseño Funcional
*"Aplicación de transferencias Pdtes Clarificar con IA"* (sección A - SAP).

Replica el comportamiento de la transacción estándar **FPCPL** para
clarificar, desde un sistema externo (vía MuleSoft), una posición de lote
de pago pendiente de clarificar, aplicando la(s) factura(s) recibida(s).

## Estado: prueba end-to-end real superada a través del propio RFC, con 1 y con 2 facturas

Probado en SE37 contra una posición de lote real pendiente de clarificar:
`E_RESULT = 'OK'`, documento generado `E_OPBEL = 414500000010` (caso de 1
factura). Confirma que la cadena completa funciona llamada directamente
desde este módulo de función, no solo a través del flujo de pantalla de
FPCPL.

Probado también con éxito el caso de **2 facturas** cuya suma coincide
con el importe de la posición (ninguna línea individual coincidía por
separado) — requirió la corrección de la QUINTA VERSIÓN descrita más
abajo (validación por suma en vez de por línea suelta), pedida por la
consultora funcional tras detectar el fallo en esa prueba real. También
se corrigió en esa misma prueba el `BLART` del documento generado, que
debe ser `'2T'` (no `'2C'` como se había fijado inicialmente por
observación de depuración).

**SEXTA VERSIÓN**: la consultora funcional reportó que, tras clarificar
por el RFC, la posición seguía apareciendo en el listado de FPCPL (al
intentar clarificarla de nuevo por la transacción, SAP avisaba de que ya
estaba clarificada y entonces sí desaparecía — confirmando que
`DFKKZP-XKLAE` quedaba correcto, pero el listado no se refrescaba).
Localizado por **traza SQL (ST05)** sobre una clarificación real por
FPCPL: faltaban dos actualizaciones que el código no hacía. Ver el punto
8 de "Lógica implementada" para el detalle.

El propio DF advierte que el módulo de función estándar
`FKK_PAYMENT_BATCH_CLARIFY_ITEM` **no se puede utilizar directamente**.
Por depuración de la transacción FPCPL se confirmó el motivo: es un
módulo de diálogo (abre una pantalla interactiva, `CALL SCREEN 500`, y
espera acción del usuario) — no apto para RFC. Depurando más allá de esa
pantalla, hasta el `FORM BUCHG_ZAHLUNG_BUCHEN` (`SAPLFKZ0`), se localizó
la cadena real completa:

```
FKK_OPEN_ITEM_SELECT            → busca la factura (verificado con datos reales)
ISU_CLEARING_PROPOSAL_GEN_0110  → SOLO calcula la propuesta (no contabiliza)
  └ FKK_CLEARING_PROPOSAL_GEN_0110
      └ FKK_PAYMENT_ALLOC_AND_CLEARING
          └ PAYMENT_ON_ACCOUNT (FORM) → FKK_OPEN_PAYMENT_COMPLETE
FKK_CREATE_DOC_MASS_AND_CLEAR   → contabiliza de verdad la propuesta ya calculada, devuelve E_OPBEL
```

**Verificado por depuración, con datos reales:**
- El mapeo tipo de selección `X` → campo `FKKOP-XBLNR`, contra la tabla
  de customizing `TFK004` (Área `R`).
- `FKK_OPEN_ITEM_SELECT` con `T_SELTAB` (`SELFN='XBLNR'`) encuentra
  correctamente las partidas abiertas de una factura real.
- El patrón de relleno de `I_FKKKO`/`T_FKKOPK` a partir de los datos de
  la posición del lote, observado en una llamada real a
  `FKK_OPEN_PAYMENT_COMPLETE`.
- **`ISU_CLEARING_PROPOSAL_GEN_0110` no contabiliza**: tras llamarla,
  `T_FKKOP_NEW` seguía vacía y no se generaba ningún documento, aunque
  `E_DIFFB` diera 0 y `T_FKKCL` quedara con `AUGBW`/`XAKTP` marcados
  (la propuesta calculada). Es literalmente lo que dice su nombre:
  "genera la propuesta", no contabiliza.
- **La contabilización real la hace `FKK_CREATE_DOC_MASS_AND_CLEAR`**
  (localizada justo después, en `BUCHG_ZAHLUNG_BUCHEN`), tomando la
  propuesta ya calculada (`T_FKKCL`, `E_DIFFB`, `E_TOLGR_CLEAR` de la
  llamada anterior) y devolviendo `E_OPBEL`, el documento real.
- **El propio `DFKKZP` no se actualiza solo**: ninguna de las funciones
  del motor toca `DFKKZP-XKLAE`/`KLAEB`. Es el `FORM`
  `BUCHG_ZAHLUNGEN_BEARBEITEN` quien lo hace explícitamente (a mano)
  después de contabilizar.
- **Caso de éxito real completo**: se forzó por depuración (`T_SELTAB`
  con `SELFN='XBLNR'`) una clarificación a través del propio flujo de
  FPCPL, con una factura de 6 líneas (50,00 € en total) donde solo una
  línea era de 0,24 €, igual que la posición de prueba. Pasando **todas**
  las líneas encontradas (no solo la de 0,24 €) al motor de
  compensación, este aplicó correctamente solo la parte que
  correspondía, dejando `DFKKZP-XKLAE` vacío y `DFKKZP-KLAEB` con el
  documento generado. Por eso el código NO filtra a una única línea:
  pasa todas las líneas de la factura candidata y deja que el motor
  estándar decida.

**Confirmado con prueba real a través del propio RFC:**
- Llamando directamente a esta cadena completa desde **este RFC** (con
  `I_FKKKO`/`T_FKKOPK` construidos por nuestro propio código, sin pasar
  por la capa de pantalla/procesamiento en bloque de
  `FKK_PAYMENT_BATCH_POST`), se obtuvo un documento real contabilizado:
  `E_RESULT = 'OK'`, `E_OPBEL = 414500000010`.

**Pendiente de precisar / no verificado en detalle todavía:**
- El valor exacto de `T_FKKOPK-HKONT` (¿siempre `DFKKZP-KLAEH` si ya
  viene informado, o la cuenta provisional constante?).
- El valor de `I_AUGVD` para `FKK_CREATE_DOC_MASS_AND_CLEAR` (aquí
  aproximado con la fecha valor de la posición; en el flujo real se
  calcula con una rutina que no se ha inspeccionado en detalle).
- La actualización de `DFKKZP` (paso 7 del código) replica el caso
  simple de una primera clarificación completa; los casos de
  clarificaciones parciales/múltiples sobre la misma posición (que en
  el flujo real llevan lógica adicional con la tabla `DFKKZPT`) no
  están contemplados.

## Contenido del repositorio

```
src/
  LZFI_FG_PAY_CLARIFYTOP.abap        Include TOP del grupo de función (tipos y constantes globales)
  ZFI_FM_PAYMENT_LOT_CLARIFY2.abap   Código fuente del módulo de función RFC
docs/
  DF_resumen.md                      Resumen del Diseño Funcional (trazabilidad)
```

## Interfaz del servicio

| Parámetro | Dirección | Tipo | Obligatorio | Descripción |
|---|---|---|---|---|
| `I_KEYZ1` | Import | `KEYZ1_KK` | Sí | Número de lote |
| `I_POSZA` | Import | `POSZA_KK` | Sí | Posición del lote |
| `I_XBLNR` | Import | `ZFI_T_XBLNR` (tipo de tabla DDIC, ver instalación) | Sí | Factura(s) a aplicar. Decidido con el cliente: tabla de longitud variable (el DF tenía una indicación de factura única y una nota posterior pidiendo varias, mínimo 5 propuesto) |
| `E_RESULT` | Export | `CHAR3` | — | `OK` / `NOK` |
| `ES_ERROR` | Export | `ZFI_DE_XX_WS_ERROR` (`CODE`, `DESCRIPTION`) | — | Error de negocio o técnico. Códigos propios: `PARAM_MISSING`, `POS_NOT_FOUND`, `POS_NOT_PENDING`, `NO_MATCHING_INVOICE`, `MULTI_CLIENT_INVOICES` (facturas de `I_XBLNR` de clientes/cuentas contrato distintos) |
| `E_OPBEL` | Export | `OPBEL_KK` | — | Documento de clarificación generado |

## Lógica implementada

1. Valida que `I_KEYZ1`, `I_POSZA` e `I_XBLNR` estén informados.
2. Verifica que la posición del lote exista y esté pendiente de clarificar
   (`DFKKZP-XKLAE = 'X'`).
3. Para cada factura de `I_XBLNR`, busca las partidas abiertas
   coincidentes con `FKK_OPEN_ITEM_SELECT` (`SELFN='XBLNR'`) — búsqueda
   pura, sin contabilizar. Una factura puede devolver varias líneas (se
   comprobó con un caso real de 6 líneas). **Desde la cuarta versión**,
   ya no se usa solo la primera factura que cuadra en importe: se
   recorren todas las facturas de `I_XBLNR`, se comprueba que todas las
   que devuelven partidas comparten cliente/cuenta contrato
   (`GPART`/`VKONT`) y se acumulan sus partidas. Al contabilizar se
   pasan **todas** las líneas encontradas de todas las facturas válidas
   (no solo la que coincide) — probado con datos reales, para el caso
   de una única factura, que el motor de compensación estándar aplica
   correctamente solo la parte que corresponde, sin que haga falta
   filtrar una única línea a mano (ver "Estado" más arriba).

   **Desde la quinta versión**, sobre ese conjunto combinado se exige la
   regla del DF ("el importe debe coincidir con el de la posición")
   comprobada como la **suma de todas las líneas combinadas**, no como
   la existencia de una única línea suelta con el importe exacto.
   Corregido tras una prueba real con 2 facturas: la suma de ambas
   coincidía con la posición, pero ninguna línea individual coincidía
   por separado, y la versión anterior rechazaba el caso con
   `NO_MATCHING_INVOICE`. Para una única factura con una sola línea (caso
   ya probado end-to-end) el comportamiento es idéntico, porque la suma
   de una única línea es esa misma línea.

   Motivado por evidencia real encontrada en el sistema de integración
   (tabla `DFKKOP`, documentos `BLART = '2T'` agrupados por `AUGBL`):
   existen casos reales donde un mismo documento de compensación
   aplica partidas de varias facturas distintas, siempre dentro del
   mismo `GPART`/`VKONT`. Si las facturas de `I_XBLNR` resultan ser de
   clientes distintos, el servicio devuelve `ES_ERROR-CODE =
   'MULTI_CLIENT_INVOICES'` en vez de decidir cuál aplicar.

   ⚠️ **Sin confirmar formalmente con negocio**: la agrupación por mismo
   cliente/cuenta contrato (`GPART`/`VKONT`) se basa en evidencia real
   encontrada en datos de producción/integración, no en una confirmación
   funcional explícita (ver DF_resumen.md). Campos `GPART`/`VKONT` de la
   estructura `FKKCL` asumidos por convención estándar de FI-CA, sin
   verificar en SE11.
4. Construye `I_FKKKO` (cabecera) y `T_FKKOPK` (partida provisional) a
   partir de los datos de la posición del lote.
5. Llama a `ISU_CLEARING_PROPOSAL_GEN_0110` (`I_CLARIFICATION = 'X'`)
   para generar la propuesta de compensación (no contabiliza todavía).
6. Informa el motivo de compensación (`AUGRD`) en todas las líneas de
   `T_FKKCL` con `DFKKZP-AUGRD`, y llama a `FKK_CREATE_DOC_MASS_START` /
   `FKK_CREATE_DOC_MASS_AND_CLEAR` / `FKK_CREATE_DOC_MASS_STOP` para
   contabilizar de verdad la propuesta calculada y obtener el documento
   real (`E_OPBEL`). `START`/`STOP` son de llamada obligatoria para la
   familia "MASS" de contabilización (verificado: error `>0340` al
   omitirlas); `STOP` se llama tanto si la contabilización sale bien
   como si falla. El `AUGRD` es igualmente obligatorio (verificado:
   error `>0545` "Falta motivo de compensación" al omitirlo), localizado
   en `BUCHG_ZAHLUNG_BUCHEN` justo antes de contabilizar (ahí se toma de
   `UFKKZP-AUGRD`, con `DFKKZK-AUGRD` de cabecera de lote como reserva;
   aquí se usa directamente `DFKKZP-AUGRD` de la posición).
7. Actualiza `DFKKZP` (`XKLAE`/`KLAEB`) a mano, replicando lo que hace
   `BUCHG_ZAHLUNGEN_BEARBEITEN` en el flujo real (el motor no lo hace
   por sí solo).
8. **Desde la sexta versión**: actualiza también `DFKKCFZST-STATE = '03'`
   y `DFKKZK-STAZS/AENAM/AEDAT/AETIM`, y hace `COMMIT WORK AND WAIT`.
   Localizado por traza SQL (ST05) sobre una clarificación real por
   FPCPL (no se hacía antes, por eso la posición seguía apareciendo en
   el listado de FPCPL pese a que `DFKKZP` quedaba correcta):
   - `DFKKCFZST` es la tabla de estado del worklist de FPCPL. Su
     `SELECT` de listado excluye explícitamente `STATE <> '03'`
     (verificado en la traza). La progresión real observada es `'02'`
     (posición bloqueada en edición) → `'01'` (guardada) → `'03'`
     (clarificada de verdad, momento en que desaparece del listado).
     Como el RFC no pasa por edición interactiva, se pone directamente
     a `'03'`.
   - `DFKKZK` (cabecera del lote): se localizó el `UPDATE` real
     (`STAZS = '4'`, `AENAM`/`AEDAT`/`AETIM` = usuario/fecha/hora
     actuales), ejecutado tras contabilizar cada posición,
     independientemente de si el lote queda completo del todo.
     Replicado literalmente — `STAZS` se vio siempre a `'4'` en la
     traza, no se ha verificado qué significan otros valores posibles
     de ese campo.

El usuario que queda registrado en las clarificaciones es el usuario
técnico con el que MuleSoft se conecta a SAP, en el campo `DFKKZP-AENAM`
(actualmente `COMMUSER`).

## Prueba end-to-end real: superada (1 y 2 facturas)

Ejecutada en SE37 (F8) contra una posición de lote real pendiente de
clarificar, a través de este módulo de función (no simulada dentro de
FPCPL): `E_RESULT = 'OK'`, `E_OPBEL = 414500000010` (caso de 1 factura).
Repetida con éxito con 2 facturas cuya suma coincide con la posición,
tras la corrección de la quinta versión.

## Instalación en SAP (SE11 / SE80 / SE37)

1. **Crear en SE11 el tipo de tabla para `I_XBLNR`** (el Function Builder
   no admite un `TYPES` de programa como tipo de referencia de un
   parámetro de import/export, tiene que ser un objeto DDIC real):
   - Estructura **`ZFI_S_XBLNR`**, con un único campo `XBLNR` tipo
     `XBLNR`.
   - Tipo de tabla **`ZFI_T_XBLNR`**, `Category` = tabla estándar,
     `Line type` = `ZFI_S_XBLNR`.
2. Crear el grupo de función **`ZFI_FG_PAY_CLARIFY`** (SE80 → Grupo de
   función → Crear).
3. Sustituir el contenido del include TOP del grupo
   (`LZFI_FG_PAY_CLARIFYTOP`) por `src/LZFI_FG_PAY_CLARIFYTOP.abap`.
4. Crear el módulo de función **`ZFI_FM_PAYMENT_LOT_CLARIFY2`** dentro
   del grupo:
   - Atributos: marcar **"Módulo de función remoto"** (RFC).
   - Pestaña *Import*: `I_KEYZ1`, `I_POSZA`, `I_XBLNR` (obligatorios),
     con los tipos indicados en la tabla de interfaz (`I_XBLNR` con tipo
     de referencia `ZFI_T_XBLNR`).
   - Pestaña *Export*: `E_RESULT`, `ES_ERROR` (tipo DDIC
     `ZFI_DE_XX_WS_ERROR`), `E_OPBEL`.
   - Pestaña *Código fuente*: pegar `src/ZFI_FM_PAYMENT_LOT_CLARIFY2.abap`.
5. Activar y probar (ver "Prueba end-to-end real" arriba).

## Pendiente / a definir con el cliente

- Confirmar formalmente con negocio el comportamiento implementado en la
  cuarta versión para `I_XBLNR` con varias facturas (agrupar por
  `GPART`/`VKONT`, rechazar si son de clientes distintos) — hoy se basa
  en evidencia real de datos de integración, no en una confirmación
  funcional explícita (ver punto 3 de "Lógica implementada").
- Verificar en SE11 que la estructura `FKKCL` expone los campos
  `GPART`/`VKONT` con esos nombres (asumido por convención estándar de
  FI-CA, no comprobado directamente).
- Confirmar el origen correcto de `T_FKKOPK-HKONT`.
- Confirmar el valor correcto de `I_AUGVD` para
  `FKK_CREATE_DOC_MASS_AND_CLEAR`.
- Contemplar el caso de clarificaciones parciales/múltiples sobre la
  misma posición (tabla `DFKKZPT`), no cubierto en esta versión.
- Confirmar el significado de `DFKKZK-STAZS` y si `'4'` es siempre el
  valor correcto — en la traza SQL usada para la sexta versión solo se
  vio ese valor (incluida la clarificación de la última posición de un
  lote), pero no se ha probado un caso donde clarificar la posición deje
  el lote entero como "completado" para saber si `STAZS` cambiaría a
  otro valor en ese caso.
- Autorización RFC del usuario `COMMUSER` (o el que corresponda) sobre el
  grupo de función.
- Alta del objeto en el sistema de transporte correspondiente al proyecto.
