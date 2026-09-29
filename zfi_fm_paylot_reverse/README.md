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
| `E_CANCELLEDDOCUMENTID` | Export | `OPBEL_KK` | — | Documento de anulación generado (se relee de `DFKKZP-RUEBL`, ver más abajo) |

## Lógica implementada

1. Valida que `I_DOCUMENTID`, `I_CANCELDATE` e `I_CANCELREASON` estén informados.
2. Verifica que el documento exista en un lote de pago (`DFKKZP`); si no,
   devuelve `E_RESULT = 'NOK'` (no se anulan documentos fuera de un lote).
3. Determina/crea la clave de reconciliación (`FIKEY`) llamando al FM estándar
   `FKK_FIKEY_GET_FOR_EXT_CALL` (localizado depurando `FP08`/`FKK_CTRACPAYMINC_REVERSE`
   hasta encontrar la comprobación real en `FKK_FIKEY_CHECK` contra la tabla
   `DFKKSUMC`; este FM es el wrapper público, pensado para llamadores
   externos, de la rutina interna que efectivamente reserva la clave), y
   hace `COMMIT WORK AND WAIT` para forzar que la clave quede persistida en
   BD (su creación por defecto ocurre vía tarea de actualización V1/V2;
   sin este commit, el paso siguiente falla con *"Clave de reconciliación
   XXX no creada aún"*).
4. Llama al FM estándar `FKK_CTRACPAYMINC_REVERSE` con:
   - `DOCUMENTNUMBER` = `I_DOCUMENTID`
   - `DOCTYPE` = `'ST'` (constante `GC_DOCTYPE_ANULACION`)
   - `CLEARREAS` = `'05'` (constante `GC_CLEARREAS_ANULACION`, fijo según nota técnica del DF)
   - `FIKEY` = clave determinada en el paso 3
   - `REVERSEDATE` = `I_CANCELDATE`
   - El único export de este FM es `RETURN` (`BAPIRET2`); se usa `RETURN-TYPE`
     para determinar éxito/error, ya que el FM no expone ningún parámetro con
     el documento de anulación generado.
5. Si `RETURN-TYPE` no es error/abort, hace `COMMIT WORK AND WAIT` y relee
   `DFKKZP-RUEBL` para el mismo `OPBEL` de entrada (verificado por
   depuración: es el campo que queda relleno con el documento de anulación
   tras la contabilización, columna "Nº doc.anul." en la búsqueda de pagos
   del lote), devolviéndolo en `E_CANCELLEDDOCUMENTID` junto con
   `E_RESULT = 'OK'`.
6. Cualquier error (validación, FIKEY o llamada al FM estándar) se devuelve
   en `ES_ERROR` (`CODE` / `DESCRIPTION`, tomados de `RETURN-NUMBER` /
   `RETURN-MESSAGE` en el caso del FM estándar) con `E_RESULT = 'NOK'`, sin
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
4. Las firmas de `FKK_FIKEY_GET_FOR_EXT_CALL` y `FKK_CTRACPAYMINC_REVERSE`
   están verificadas contra SE37 y reflejadas en el código, incluyendo la
   relectura de `DFKKZP-RUEBL` para obtener `E_CANCELLEDDOCUMENTID`.
5. Activar y probar contra un documento de pago real incluido en un lote
   de transferencias (`DFKKZP`).

## Pendiente / a definir con el cliente

- Confirmar si la clave de reconciliación generada por
  `FKK_FIKEY_GET_FOR_EXT_CALL` usa la fecha del sistema o `I_CANCELDATE`
  (no recibe parámetro de fecha); validar con una anulación de fecha
  contable distinta a la de hoy.
- Autorización RFC del usuario `COMMUSER` (o el que corresponda) sobre el
  grupo de función.
- Alta del objeto en el sistema de transporte correspondiente al proyecto.
