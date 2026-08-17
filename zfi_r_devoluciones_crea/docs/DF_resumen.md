# Resumen del Diseño Funcional — RU_02 (creación del lote de devoluciones)

**Documento origen:** CS_CDI_11_Procedimiento_Gestion_de_extornos (27/07/2026, con
comentarios de EVA). Ver también `../zfi_r_devoluciones2/docs/DF_resumen.md` para
el contexto completo de los 3 desarrollos.

## Requisito del DF

**RU_02 — Creación del lote de devoluciones** en SAP (FP09/`RFKKA00`) a partir del
fichero `_DEV`, con nomenclatura `AAMMDDCDI11xx`, sociedad `1239`, clase `DV`,
motivo `Z01`, cta. compensación `4305500150`, una posición por línea del fichero.

## Enfoque

Reutilizar `RFKKA00` (el mismo motor que usa `ZFI_R_DEVOLUCIONES`/`ZFI_R_DEVOLUCIONES2`),
pero generando nosotros mismos los ficheros multicash `AUSZUG`/`UMSATZ` a partir
del `_DEV`, en vez de convertir un XML SEPA (que es lo que hace
`RFKKSEPA_DD_RJCT`, y que aquí no aplica porque el `_DEV` no es XML).

Se descartó (de momento) buscar una cadena de FMs internos alternativa —como se
hizo para `ZFI_FM_PAYLOT_REVERSE`/`ZFI_FM_PAYMENT_LOT_CLARIFY2` depurando
`FP08`/`FPCPL`— porque esa investigación fue necesaria allí por ser transacciones
de **diálogo** no invocables por RFC; `RFKKA00` no tiene ese problema, ya se
somete hoy con `SUBMIT ... AND RETURN` sin pantalla de por medio.

## Formato AUSZUG/UMSATZ deducido de ejemplos reales

Sacado de 6 casos reales (`ZFI_T_FILE_LOG`, `STATUS = PROCESADO`, `BUSINESS_DESC = 'DEV'`,
carpeta `backup/` de la ruta lógica `ZFICA_COBROS_DEVOLUCIONES` en Integración),
de 4 bancos distintos: Santander (`STD0`), BBVA (`BBV0`), CaixaBank (`CAIV`) y
Unicaja (`UNC0`). Separador `;`, fin de línea `LF` (sin `CR`). Lo que se ve en
AL11 al listar la carpeta ("Verzeichnis:"/"Nombre:"/rayas) es decoración del
visor, no forma parte del fichero — el fichero real es solo la línea de datos.

### `AUSZUG` (cabecera del lote, 1 línea, 18 campos separados por `;`)

| # | Ejemplo | Campo | Origen en este programa |
|---|---|---|---|
| 1 | `00491600` | Entidad+oficina (8 díg.) | `co_bank_code` — **sin valor, pendiente** |
| 2 | `2413310701` | Cuenta (10 díg.) | `co_bank_account` — asunción: `4305500150` (cta. compensación del DF) |
| 3 | `00001` | Nº secuencia del extracto | fijo `00001` — **pendiente, ver abajo** |
| 4 | `02.01.26` | Fecha (con puntos) | `sy-datum` de hoy |
| 5 | `EUR` | Moneda | constante |
| 6 | `0.00` | Saldo inicial | constante `0.00` |
| 7 | `127.78-` | Movimiento total | suma de importes de las líneas del `_DEV` |
| 8 | `0.00` | Sin identificar (0.00 en los 4 ejemplos) | constante `0.00` |
| 9 | `127.78-` | Saldo final (= 6 + 7) | = campo 7 |
| 10-17 | (vacíos) | Reservados | un espacio cada uno |
| 18 | (vacío) | — | vacío (cierre del `;` final) |

### `UMSATZ` (posiciones, 1 línea por extorno, 38 campos separados por `;`)

| # | Ejemplo(s) | Campo | Origen en este programa |
|---|---|---|---|
| 1-3 | — | igual que `AUSZUG` 1-3 | igual |
| 4 | `13 11 25` / `01 12 25` | Fecha original (con espacios) | **pendiente**: se usa la fecha de hoy, el `_DEV` no expone la fecha real del extorno de forma directa |
| 5 | (vacío) | Reservado | vacío |
| 6 | `445000392136` (Santander/BBVA, 12 díg., patrón nº doc. SAP) vs. `043001375872000000000000000` (CaixaBank, 29 díg.) | Referencia | **nº de documento SAP** (12 díg.) que ya extrae `ZFI_R_ECOFI_SPLIT` en el `_DEV`. El formato varía por banco en los ejemplos reales (esos vienen del XML SEPA real); aquí siempre ponemos el nº de documento, tal como propone el DF para el `_DEV` |
| 7 | `MS02` / `MD01` / `AC06` | Motivo devolución (código ISO largo) | **vacío, pendiente** — no disponible en el `_DEV` |
| 8-10 | (vacíos) | Reservados | vacíos |
| 11 | `103.00-` | Importe | importe de la línea del `_DEV` (venía en céntimos sin separador, p.ej. `6049` → `60.49`) |
| 12 | `2` (MS02) / `4` (MD01, MD06) / `6` (AC06) | Categoría (parece derivar del motivo) | **vacío, pendiente** — depende del motivo, que tampoco tenemos |
| 13 | `0` | Constante en los 4 ejemplos | `'0'` fijo |
| 14 | `02 01 26` | Fecha (coincide con la 4 del `AUSZUG`) | igual que el campo 4 de `UMSATZ` |
| 15-31 | (vacíos) | Reservados (17 campos) | un espacio cada uno |
| 32 | `BSCHESMMXXX` | BIC deudor | **vacío, pendiente** — no disponible en el `_DEV` |
| 33 | `ES8500491938...` | IBAN deudor | **vacío, pendiente** — no disponible en el `_DEV` |
| 34 | `S02` / `D01` / `C06` | Motivo devolución (código corto = 7 sin la letra inicial) | se usa el motivo **fijo** del DF: `Z01` |
| 35-37 | (vacíos) | Reservados | vacíos |
| 38 | (vacío) | — | vacío (cierre del `;` final) |

**Por qué faltan BIC/IBAN/motivo real**: el `_DEV` viene del fichero ECOFI, que es
un extracto propio de cobros de Naturgy (transferencias + extornos mezclados),
**no** el XML SEPA de devolución con el detalle bancario del deudor. La regla de
extracción del `_DEV` (ver `zfi_r_ecofi_split`) sustituye el concepto original
por el nº de documento SAP, pero el ECOFI nunca llevaba IBAN/BIC/motivo SEPA en
primer lugar.

## Pendiente / a definir con el cliente

1. **`co_bank_code`** (entidad+oficina): sin dato. ¿Hay una única cuenta de cobro
   fija para el flujo ECOFI, o depende de qué banco originó el fichero (y en ese
   caso, de dónde se saca)?
2. **¿Son BIC/IBAN/motivo (campos 7, 12, 32, 33) realmente obligatorios para que
   `RFKKA00` acepte el lote?** Decisión tomada con el cliente: se dejan en
   blanco/con el motivo fijo (`Z01`) y se valida en la primera prueba real contra
   `RFKKA00` en Integración — si el lote no se crea o se crea mal, esto es lo
   primero a revisar.
3. **Nº de secuencia del extracto (campo 3)**: fijo a `00001` en este borrador.
   En los ejemplos reales es un contador que sube (`00001`, `00032`...) — con un
   valor fijo, procesar un segundo `_DEV` para la misma cuenta probablemente
   falle por número de extracto duplicado. Falta decidir de dónde sacar el
   siguiente número real (tabla de contador propia, consulta a FI-CA, o si
   `RFKKA00` lo asigna él solo y este campo es indiferente — pendiente de
   comprobar).
4. **Nomenclatura de lote `AAMMDDCDI11xx`**: el DF la pide explícitamente, pero
   `RUNIDBS_KK` (el campo `p_runid` de `RFKKA00`) parece admitir solo 6
   caracteres, a juzgar por cómo lo usa `ZFI_R_DEVOLUCIONES` (`file_id+1(6)`).
   `AAMMDDCDI11xx` tiene 13. Falta confirmar en SE11 el dominio real de
   `RUNIDBS_KK` y decidir cómo encajar (o no) la nomenclatura pedida.
5. **Fecha real del extorno** (campo 4/14 de `UMSATZ`): se usa la fecha de hoy.
   El bloque numérico del `_DEV` entre el tag `ANUP` y el importe
   (`182603385420262026040150` en el ejemplo de `zfi_r_ecofi_split`) probablemente
   codifica fechas reales, pero no se ha descifrado su estructura exacta — si
   `RFKKA00` necesita la fecha real (no la de hoy), hay que volver a esto.
6. **Traza en `ZFI_T_FILE_LOG`**: se usa `co_dev = 'EXT'` como valor de proceso
   distinto de `'DEV'` (que ya usan las devoluciones bancarias reales) — a
   confirmar que no choca con otro uso existente.
7. Alta del objeto en el sistema de transporte correspondiente al proyecto.

## Premisas / Dependencias

- Depende de que exista el fichero `_DEV` (RU_01, `zfi_r_ecofi_split`), con el
  formato de línea ya validado contra 2 ficheros ECOFI reales (ver su propio
  `docs/DF_resumen.md`).
- `ZFI_T_FILE_LOG`, `zfi_cl_update_file_log`, `zxx_cl_msg_logs`,
  `zxx_cl_generic_on_memory`, `zxx_cl_file_utils` se reutilizan tal cual del
  programa original `ZFI_R_DEVOLUCIONES` (mismas clases ya existentes en el
  sistema).
- **Nada de esto se ha probado todavía contra una ejecución real de `RFKKA00`.**
  Toda la sección de formato de `AUSZUG`/`UMSATZ` es reverse-engineering de
  ficheros de salida ya existentes, no una confirmación de qué acepta el
  programa de entrada.
