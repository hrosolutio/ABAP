# ZFI_R_DEVOLUCIONES2 — Cierre y contabilización del lote de devolución de extornos (CDI_11)

**Estado: reescrito sobre `FKK_RLS_CLOSE`/`FKK_RLS_POST_LOT`, circuito probado en DES.**
Ya no es la copia de `ZFI_R_DEVOLUCIONES` — igual que pasó con el desarrollo 2
(`zfi_r_devoluciones_crea/`), la sugerencia original de EVA de reutilizar el
motor `RFKKKA00` resultó ser una lectura incorrecta del DF. Depurando `FP09`
sobre lotes reales creados por `ZFI_R_DEVOLUCIONES_CREA`, se confirmó que
"Cerrar"/"Contabilizar" llaman directamente a `FKK_RLS_CLOSE`/
`FKK_RLS_POST_LOT` (grupo de función `FKR2`, el mismo que usa el desarrollo
2) — ver `docs/DF_resumen.md` para las firmas exactas y las pruebas reales.

Es uno de los 3 desarrollos del proyecto CDI_11:
1. **División del fichero ECOFI** en transferencias/extornos → [`zfi_r_ecofi_split/`](../zfi_r_ecofi_split/README.md)
2. **Creación del lote de devoluciones** → [`zfi_r_devoluciones_crea/`](../zfi_r_devoluciones_crea/README.md), ya reescrito y probado con éxito.
3. **Cierre y contabilización del lote** → este programa (`ZFI_R_DEVOLUCIONES2`).

**Además**, este mismo RU_03 está expuesto también como servicio RFC →
[`zfi_fm_devoluciones2/`](../zfi_fm_devoluciones2/README.md) (ejecuta
este report con `SUBMIT`, sin duplicar su lógica — ver ese README para
el porqué de mantener las dos formas).

## Cómo funciona

El DF no define ningún mecanismo automático para que este programa se
entere de qué lotes hay pendientes de cerrar/contabilizar — el lote (o
lotes) a tratar se indica **a mano** en la pantalla de selección
(`S_KEYR1`, obligatorio), igual que se haría entrando a `FP09` con el nº
de lote. Este programa no lee ningún fichero ni consulta
`ZFI_T_FILE_LOG` (una versión anterior lo hacía — descubrimiento
automático vía esa tabla — pero era una invención sin base en el DF,
descartada).

Por cada `KEYR1` indicado que exista realmente en `DFKKRK`:

1. Lee `DFKKRK-STARS` del lote (estado real en FI-CA).
2. Si ya está contabilizado del todo (`STARS = 5`) → no se toca.
3. Si está abierto (`STARS` en blanco) → `FKK_RLS_CLOSE`.
4. Cualquier otro caso (recién cerrado en el paso anterior, ya estaba
   cerrado sin contabilizar, o cualquier estado intermedio/con
   incidencias) → se llama a `FKK_RLS_POST_LOT` igualmente — **no se
   filtra por `STARS` antes**, se deja que el propio FM decida si el
   lote es válido y devuelva su error estándar si no lo es (así ese
   error llega también al detalle capturado tipo FP09, ver más abajo) —
   **sin reintento ni corrección automática** en ningún caso.

Parámetros de selección: **`S_KEYR1`** (obligatorio — nº de lote(s) a
tratar) y **`P_SIMU`** (checkbox — si se marca, el programa solo escribe
el `STARS` actual de cada lote indicado, sin cerrar ni contabilizar nada
de verdad).

## Detalle de error tipo FP09 (para `ZFI_FM_DEVOLUCIONES2`)

Cuando `FKK_RLS_POST_LOT` falla, este programa captura el **mismo
detalle de mensajes por documento que muestra la FP09** (el popup que
sale al pulsar "Contabilizar" cuando hay errores, ej. *"El documento
484000019565 no existe. Corrija la entrada"*) — sin tocar ni una línea
de código estándar ni reconstruir la validación por nuestra cuenta.

Técnica (confirmada por depuración real, ver `docs/DF_resumen.md`):
`FKK_RLS_POST_LOT` llama internamente al FM público `FKK_TRACE_INIT`,
que crea un objeto `LCL_MESSENGER` (clase local del programa estándar
`SAPLFKKTRACE`) donde se van acumulando todos los mensajes de
validación de cada documento. Ese objeto (`GDBG`) es invisible desde
fuera de `SAPLFKKTRACE`, pero ese mismo programa tiene un FORM público,
`RETRIEVE_DATA`, que sí podemos invocar desde fuera
(`PERFORM retrieve_data IN PROGRAM saplfkktrace USING ...`, dentro de la
misma sesión interna, justo después de `FKK_RLS_POST_LOT`) y que vuelca
el filtro de mensajes que le pidamos (aquí, solo errores) a la tabla
global `T_MESSENGERDATA` — de ahí se lee con `ASSIGN` dinámico
(`'(SAPLFKKTRACE)T_MESSENGERDATA[]'`, el `[]` porque es una tabla con
línea de cabecera) y, línea a línea, se reconstruye el texto final con
`MESSAGE ID ... TYPE ... NUMBER ... WITH ... INTO`, usando el
`ID`/`TY`/`NR`/`V1-V4` de cada línea (`TYPE dfkktracep`, estructura DDIC
real, no un tipo local invisible).

El resultado (`KEYR1` + texto) se deja en memoria ABAP
(`MEMORY ID 'ZFI_DEVOL2_ERRORS'`) al terminar `EXECUTE` — pero
**solo si `SY-CALLD = 'X'`** (el programa se ha lanzado con `SUBMIT`,
que es como lo llama `ZFI_FM_DEVOLUCIONES2`; en blanco si se ejecuta a
mano en SE38, para no dejar datos en memoria ABAP cuando no hay ninguna
RFC esperando leerlos). `ZFI_FM_DEVOLUCIONES2` lo importa después de su
`SUBMIT ... AND RETURN` (ver ese README) y lo añade a
`ES_ERROR-DESCRIPTION`.

## Mensajes (`ZFI_MC_001`)

Igual que `ZFI_R_DEVOLUCIONES`/`ZFI_R_DEVOLUCIONES_CREA`, los mensajes van
por `zxx_cl_msg_logs` con la clase `ZFI_MC_001` (dados de alta en `SE91`),
no `WRITE` con texto suelto:

| Nº | Tipo | Texto |
|---|---|---|
| `178` | E | Ningún lote indicado existe en DFKKRK |
| `179` | I | Lote &1: STARS=&2 (simulación, no se toca nada) |
| `180` | E | Lote &1: error en &2 (&3) |
| `181` | S | Lote &1: cerrado y contabilizado |
| `182` | S | Lote &1: ya estaba contabilizado, nada que hacer |

## Contenido del repositorio

```
src/
  ZFI_R_DEVOLUCIONES2.abap        Programa principal (REPORT)
  ZFI_R_DEVOLUCIONES2_TOP.abap    Include TOP (TABLES dfkkrk, para S_KEYR1)
  ZFI_R_DEVOLUCIONES2_EVE.abap    Include EVE (S_KEYR1 + P_SIMU)
  ZFI_R_DEVOLUCIONES2_CLS.abap    Include CLS (clase lcl_devoluciones2) — sobre FKK_RLS_CLOSE/FKK_RLS_POST_LOT
docs/
  DF_resumen.md                   Resumen del Diseño Funcional + cadena real de FMs confirmada por depuración
```

## Pendiente

- Probar una contabilización real con éxito — requiere un lote cuyos
  documentos existan de verdad (Integración, o documentos reales de DES).
  En DES, con el lote de prueba `260825CDI111`, el circuito completo
  funciona bien pero `FKK_RLS_POST_LOT` falla (`NOT_VALID`) porque los
  documentos del `_DEV` de prueba no existen — ver `docs/DF_resumen.md`.
- Alta del objeto en el sistema de transporte correspondiente al proyecto.
