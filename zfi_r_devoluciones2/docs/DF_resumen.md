# Resumen del Diseño Funcional

**Documento origen:** CS_CDI_11_Procedimiento_Gestion_de_extornos (27/07/2026, con
comentarios de EVA).

**Programa base:** copia literal de `ZFI_R_DEVOLUCIONES` (COB-INT-006, autor Jose
Ternero), que hoy gestiona devoluciones bancarias SEPA recibidas en XML. Se parte de
esta copia (sin modificar aún) siguiendo la sugerencia de EVA en RU_03: en vez de
exponer un servicio RFC nuevo, reutilizar el motor estándar que ya crea, cierra y
contabiliza lotes de devolución (`RFKKA00`, vía `SUBMIT ... WITH p_xcre/p_xcls/p_xbu`),
adaptado para que la entrada sea el fichero de extornos (`_DEV`) derivado del fichero
bancario de transferencias, en vez de un XML de devolución SEPA.

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
- **RU_02 — Creación del lote de devoluciones** en SAP (FP09/RFKKA00) a partir del
  fichero `_DEV`, con nomenclatura `AAMMDDCDI11xx`, sociedad `1239`, clase `DV`,
  motivo `Z01`, cta. compensación `4305500150`, una posición por línea del fichero.
  → Desarrollo 2: programa aparte, pendiente de empezar. *(Fuera de alcance de
  este programa.)*
- **RU_03 — Cierre y contabilización** del lote de devoluciones ya creado.
  Comentario de EVA: no crear servicio nuevo, adaptar `ZFI_R_DEVOLUCIONES`.
  → Desarrollo 3: **este programa** (`ZFI_R_DEVOLUCIONES2`).

## Fuera de alcance (de este programa)

- **RU_01**: cubierto por `zfi_r_ecofi_split/`.
- **RU_02**: creación del lote — programa aparte (aún sin empezar). Este programa
  (`ZFI_R_DEVOLUCIONES2`) solo debe encargarse de **cerrar y contabilizar** un lote
  que ya existe; hay que revisar si el `convert_multicash`/`submit_rfkkka00`
  heredados de `ZFI_R_DEVOLUCIONES` (que crean el lote desde cero) tienen sentido
  aquí o si este programa debe simplificarse para operar solo sobre un lote/`runid`
  ya creado por el desarrollo 2 (ver punto 2 de "Diferencias pendientes").

## Diferencias pendientes de adaptar respecto a `ZFI_R_DEVOLUCIONES`

Esta copia es **idéntica en lógica** al programa original (solo se han renombrado
el report, los includes y la clase: `lcl_devoluciones` → `lcl_devoluciones2`). Para que
funcione con el fichero de extornos hace falta decidir/adaptar, como mínimo:

1. **Formato de entrada**: el original espera un XML SEPA `pain.002` (devolución
   bancaria real) y usa `get_importe` (método `SMUM_XML_PARSE`) para leerlo. El
   fichero `_DEV` de extornos es texto plano (líneas del fichero ECOFI con el
   concepto ya recortado al número de documento PG, según propone EVA en RU_01),
   no XML. Hace falta un método de lectura nuevo para este formato.
2. **Conversión a multicash (`convert_multicash`) y creación del lote**: el
   original convierte el XML a los ficheros `AUSZUG`/`UMSATZ` (formato multicash
   que espera `RFKKA00`) mediante `SUBMIT rfkksepa_dd_rjct`, y con esos ficheros
   **crea** el lote (`SUBMIT rfkkka00 ... WITH p_xcre = gv_crear`). Ahora que RU_02
   (crear el lote) es un desarrollo aparte, este paso probablemente **sobra en
   `ZFI_R_DEVOLUCIONES2`**: si el desarrollo 2 ya deja el lote creado, este
   programa solo necesitaría el tramo de `submit_rfkkka00` con `p_xcls`/`p_xbu`
   (cerrar/contabilizar) apuntando al lote/`runid` ya existente, sin volver a
   generar `AUSZUG`/`UMSATZ` ni volver a crear nada. **Pendiente de confirmar**:
   ¿`RFKKA00` permite cerrar/contabilizar un lote ya creado solo con
   `p_rundat`/`p_runid` (sin volver a pasarle `p_auszf`/`p_umsf`), o siempre
   necesita los ficheros de entrada aunque el lote ya exista? Necesito
   verificarlo en SE38 (F1 en los parámetros de `RFKKA00`) o depurando una
   ejecución real de cierre/contabilización de un lote de devolución existente.
3. **Nomenclatura del lote**: el DF pide `AAMMDDCDI11xx`; el original construye
   `lv_runid` a partir de `file_id` (`co_key = 'Z_ID'`). Falta confirmar si
   `RFKKA00`/`p_runid` permite fijar directamente esa nomenclatura o si el nombre
   de lote (`DFKKZK-KEYZ1`) lo asigna el propio motor estándar a partir de otro
   criterio.
4. **Sociedad/cuenta/motivo fijos**: `get_importe` calcula sociedad, banco y motivo
   leyendo el XML y la tabla `ZFI_T_COBRO_CONF`. El DF de extornos ya fija estos
   valores (sociedad `1239`, motivo `Z01`, cta. `4305500150`); falta decidir si se
   mantiene la consulta a `ZFI_T_COBRO_CONF` (dado de alta con estos valores para
   extornos) o se simplifica a constantes, y si aplica un `tipo_cobro` propio
   distinto de `DEV` (p.ej. `EXT`) para no interferir con la configuración de
   devoluciones bancarias reales.
5. **Traza en `ZFI_T_FILE_LOG`**: el original ya registra cada fichero procesado
   aquí (comentario de EVA en RU_02 pedía justo esto), así que se mantiene tal
   cual; falta decidir el valor de `co_dev`/proceso a usar para no mezclar los
   logs de extornos con los de devoluciones bancarias reales.
6. **Ruta lógica (`co_logical_path`)**: el original usa
   `ZFICA_COBROS_DEVOLUCIONES`. Falta confirmar si los ficheros `_DEV` de
   extornos se dejan en esa misma ruta lógica o en una nueva.
7. **Alta del objeto en el sistema de transporte** correspondiente al proyecto.

## Premisas / Dependencias

- Depende de que exista el fichero `_DEV` (RU_01), con el formato de línea que se
  acuerde (concepto reducido al nº de documento PG, según propone EVA).
- `ZFI_T_FILE_LOG`, `ZFI_T_COBRO_CONF`, `zfi_cl_update_file_log`,
  `zxx_cl_msg_logs`, `zxx_cl_file_utils`, `zxx_cl_generic_on_memory` se reutilizan
  tal cual del programa original (mismas clases/tablas ya existentes en el sistema).
