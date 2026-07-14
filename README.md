# ZFI_FM_PAYLOT_REVERSE — Anulación de transferencias contabilizadas en SAP

Implementación del servicio RFC descrito en el Diseño Funcional
*"Anulación de transferencias contabilizadas en SAP con IA"* (sección A - SAP,
proceso subproceso `CDI_11_03`).

Replica el comportamiento de la transacción estándar **FP08** para anular,
desde un sistema externo (vía MuleSoft), un documento de pago generado en un
lote de pagos de transferencias.

## Contenido del repositorio

```
src/
  LZFI_FG_PAY_REVTOP.abap      Include TOP del grupo de función (tipos y constantes globales)
  ZFI_FM_PAYLOT_REVERSE.abap   Código fuente del módulo de función RFC
docs/
  DF_resumen.md                Resumen del Diseño Funcional (trazabilidad)
```

## Interfaz del servicio

| Parámetro | Dirección | Tipo | Obligatorio | Descripción |
|---|---|---|---|---|
| `I_DOCUMENTID` | Import | `OPBEL_KK` | Sí | Número de documento SAP a anular |
| `I_CANCELDATE` | Import | `BUDAT` | Sí | Fecha contable de anulación |
| `I_CANCELREASON` | Import | `CHAR40` | Sí | Motivo de anulación (recibido del sistema externo; no se traslada a `CLEARREAS`, ver nota técnica) |
| `I_PROCESO` | Import | `CHAR20`, default `CDI_11_03` | No | Identificador de proceso/subproceso |
| `E_RESULT` | Export | `CHAR3` | — | `OK` / `NOK` |
| `ES_ERROR` | Export | `ZFI_DE_XX_WS_ERROR` (`CODE`, `DESCRIPTION`) | — | Error de negocio o técnico |
| `E_CANCELLEDDOCUMENTID` | Export | `OPBEL_KK` | — | Documento de anulación generado |

## Lógica implementada

1. Valida que `I_DOCUMENTID`, `I_CANCELDATE` e `I_CANCELREASON` estén informados.
2. Verifica que el documento exista en un lote de pago (`DFKKZP`); si no,
   devuelve `E_RESULT = 'NOK'` (no se anulan documentos fuera de un lote).
3. Determina/crea la clave de reconciliación (`FIKEY`) llamando al FM estándar
   `FKK_CALL_EVENT_1113`.
4. Llama al FM estándar `FKK_CTRACPAYMINC_REVERSE` con:
   - `DOCUMENTNUMBER` = `I_DOCUMENTID`
   - `DOCTYPE` = `'ST'` (constante `GC_DOCTYPE_ANULACION`)
   - `CLEARREAS` = `'05'` (constante `GC_CLEARREAS_ANULACION`, fijo según nota técnica del DF)
   - `FIKEY` = clave determinada en el paso 3
   - `REVERSEDATE` = `I_CANCELDATE`
5. Si la anulación es correcta, hace `COMMIT WORK AND WAIT` y devuelve
   `E_RESULT = 'OK'` junto con el documento de anulación generado.
6. Cualquier error (validación, FIKEY o llamada al FM estándar) se devuelve
   en `ES_ERROR` (`CODE` / `DESCRIPTION`) con `E_RESULT = 'NOK'`, sin
   gestión adicional de errores (fuera de alcance según el DF).

El usuario que queda registrado en las anulaciones es el usuario técnico
con el que MuleSoft se conecta a SAP (actualmente `COMMUSER`).

## Instalación en SAP (SE80 / SE37)

1. Crear el grupo de función **`ZFI_FG_PAY_REV`** (SE80 → Grupo de función → Crear),
   descripción p.ej. *"Anulación transferencias SAP (IA)"*.
2. Sustituir el contenido del include TOP del grupo (`LZFI_FG_PAY_REVTOP`) por
   `src/LZFI_FG_PAY_REVTOP.abap`.
3. Crear el módulo de función **`ZFI_FM_PAYLOT_REVERSE`** dentro del grupo:
   - Atributos: marcar **"Módulo de función remoto"** (RFC).
   - Pestaña *Import*: `I_DOCUMENTID`, `I_CANCELDATE`, `I_CANCELREASON`
     (obligatorios) e `I_PROCESO` (opcional, valor propuesto `CDI_11_03`),
     con los tipos indicados en la tabla de interfaz.
   - Pestaña *Export*: `E_RESULT`, `ES_ERROR` (tipo DDIC `ZFI_DE_XX_WS_ERROR`),
     `E_CANCELLEDDOCUMENTID`.
   - Pestaña *Código fuente*: pegar `src/ZFI_FM_PAYLOT_REVERSE.abap`.
4. **Completar la llamada a `FKK_CTRACPAYMINC_REVERSE`** (paso 4 del código,
   bloque `IMPORTING` comentado): los parámetros de entrada
   (`DOCUMENTNUMBER`, `DOCTYPE`, `CLEARREAS`, `FIKEY`, `REVERSEDATE`) están
   tomados literalmente del DF, pero el parámetro de salida con el
   documento de anulación generado no está confirmado y hay que verificarlo
   en SE37.
   La llamada a `FKK_CALL_EVENT_1113` (paso 3) ya usa la firma real
   verificada en SE37 (`I_UNAME` como único import obligatorio); queda
   pendiente confirmar con negocio/FI-CA si el escenario de anulación
   manual requiere informar `I_HERKF`/`I_APPLK` (ver TODO en el código).
5. Activar y probar contra un documento de pago real incluido en un lote
   de transferencias (`DFKKZP`).

## Pendiente / a definir con el cliente

- Confirmar si procede informar `I_HERKF`/`I_APPLK` en la llamada a
  `FKK_CALL_EVENT_1113` para este escenario (ver TODO en
  `ZFI_FM_PAYLOT_REVERSE.abap`).
- Confirmar el parámetro de salida de `FKK_CTRACPAYMINC_REVERSE` que
  contiene el documento de anulación generado.
- Autorización RFC del usuario `COMMUSER` (o el que corresponda) sobre el
  grupo de función.
- Alta del objeto en el sistema de transporte correspondiente al proyecto.
