# ZFI_FM_PAYMENT_LOT_CLARIFY2 — Clarificación de transferencias pendientes en SAP

Implementación del servicio RFC descrito en el Diseño Funcional
*"Aplicación de transferencias Pdtes Clarificar con IA"* (sección A - SAP).

Replica el comportamiento de la transacción estándar **FPCPL** para
clarificar, desde un sistema externo (vía MuleSoft), una posición de lote
de pago pendiente de clarificar, aplicando la(s) factura(s) recibida(s).

## Estado: prueba end-to-end real superada a través del propio RFC

Probado en SE37 contra una posición de lote real pendiente de clarificar:
`E_RESULT = 'OK'`, documento generado `E_OPBEL = 414500000010`. Confirma
que la cadena completa funciona llamada directamente desde este módulo
de función, no solo a través del flujo de pantalla de FPCPL.

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
| `ES_ERROR` | Export | `ZFI_DE_XX_WS_ERROR` (`CODE`, `DESCRIPTION`) | — | Error de negocio o técnico |
| `E_OPBEL` | Export | `OPBEL_KK` | — | Documento de clarificación generado |

## Lógica implementada

1. Valida que `I_KEYZ1`, `I_POSZA` e `I_XBLNR` estén informados.
2. Verifica que la posición del lote exista y esté pendiente de clarificar
   (`DFKKZP-XKLAE = 'X'`).
3. Para cada factura de `I_XBLNR`, busca las partidas abiertas
   coincidentes con `FKK_OPEN_ITEM_SELECT` (`SELFN='XBLNR'`) — búsqueda
   pura, sin contabilizar. Una factura puede devolver varias líneas (se
   comprobó con un caso real de 6 líneas). Se usa la presencia de **al
   menos una línea con el importe exacto** de la posición como criterio
   para elegir qué factura de `I_XBLNR` es la candidata correcta, pero
   al contabilizar se pasan **todas** las líneas encontradas de esa
   factura (no solo la que coincide) — probado con datos reales que el
   motor de compensación estándar aplica correctamente solo la parte
   que corresponde, sin que haga falta filtrar una única línea a mano
   (ver "Estado" más arriba).

   ⚠️ **Sin confirmar con negocio**: que "probar una a una hasta que
   alguna línea cuadre en importe" sea el comportamiento esperado para
   el caso de varias facturas en `I_XBLNR` (ver DF_resumen.md).
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
   por sí solo), y hace `COMMIT WORK AND WAIT`.

El usuario que queda registrado en las clarificaciones es el usuario
técnico con el que MuleSoft se conecta a SAP, en el campo `DFKKZP-AENAM`
(actualmente `COMMUSER`).

## Prueba end-to-end real: superada

Ejecutada en SE37 (F8) contra una posición de lote real pendiente de
clarificar, a través de este módulo de función (no simulada dentro de
FPCPL): `E_RESULT = 'OK'`, `E_OPBEL = 414500000010`.

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

- Confirmar con negocio el comportamiento esperado cuando `I_XBLNR` trae
  varias facturas (ver punto 3 de "Lógica implementada").
- Confirmar el origen correcto de `T_FKKOPK-HKONT`.
- Confirmar el valor correcto de `I_AUGVD` para
  `FKK_CREATE_DOC_MASS_AND_CLEAR`.
- Contemplar el caso de clarificaciones parciales/múltiples sobre la
  misma posición (tabla `DFKKZPT`), no cubierto en esta versión.
- Autorización RFC del usuario `COMMUSER` (o el que corresponda) sobre el
  grupo de función.
- Alta del objeto en el sistema de transporte correspondiente al proyecto.
