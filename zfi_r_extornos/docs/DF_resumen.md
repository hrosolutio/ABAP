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
transferencias de ECOFI, separándolos y creando/cerrando/contabilizando su propio
lote de devoluciones en SAP FI-CA, sin intervención manual.

## Requisitos del DF (CDI_11)

- **RU_01** — Dividir el fichero bancario de ECOFI en dos ficheros (transferencias
  `_TRF` y extornos `_DEV`) al llegar, detectando extorno por concepto de 24 dígitos.
  *(Cubierto por un desarrollo aparte, no por este programa — ver "Fuera de alcance".)*
- **RU_02** — Crear un lote de devoluciones en SAP (FP09/RFKKA00) a partir del
  fichero `_DEV`, con nomenclatura `AAMMDDCDI11xx`, sociedad `1239`, clase `DV`,
  motivo `Z01`, cta. compensación `4305500150`, una posición por línea del fichero.
- **RU_03** — Cerrar y contabilizar el lote de devoluciones generado.
  Comentario de EVA: no crear servicio nuevo, adaptar `ZFI_R_DEVOLUCIONES`.

## Fuera de alcance (de este programa)

- **RU_01**: la separación del fichero ECOFI en `_TRF`/`_DEV` es un desarrollo
  distinto (probablemente una modificación del proceso que hoy crea el lote de
  transferencias); este programa solo consume el fichero `_DEV` ya generado.

## Diferencias pendientes de adaptar respecto a `ZFI_R_DEVOLUCIONES`

Esta copia es **idéntica en lógica** al programa original (solo se han renombrado
el report, los includes y la clase: `lcl_devoluciones` → `lcl_extornos`). Para que
funcione con el fichero de extornos hace falta decidir/adaptar, como mínimo:

1. **Formato de entrada**: el original espera un XML SEPA `pain.002` (devolución
   bancaria real) y usa `get_importe` (método `SMUM_XML_PARSE`) para leerlo. El
   fichero `_DEV` de extornos es texto plano (líneas del fichero ECOFI con el
   concepto ya recortado al número de documento PG, según propone EVA en RU_01),
   no XML. Hace falta un método de lectura nuevo para este formato.
2. **Conversión a multicash (`convert_multicash`)**: el original convierte el XML a
   los ficheros `AUSZUG`/`UMSATZ` (formato multicash que espera `RFKKA00`) mediante
   `SUBMIT rfkksepa_dd_rjct` con el formato DMEE `Z_CGI_FICA_XML_DD`. Como el
   fichero `_DEV` no es un XML SEPA, no podemos reutilizar `rfkksepa_dd_rjct` tal
   cual: hay que generar `AUSZUG`/`UMSATZ` directamente desde las líneas del
   fichero `_DEV` (cabecera + una posición por línea, con el nº de documento a 12
   dígitos que indica el DF). **Necesito un fichero `AUSZUG`/`UMSATZ` de ejemplo
   generado hoy por el programa original**, para fijar el layout exacto
   (posiciones de columna) que espera `RFKKA00`.
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
7. **Objetos DDIC/nombres Z**: `ZFI_R_EXTORNOS` es un nombre provisional — decir si
   se mantiene o hay una convención de nombres distinta que seguir (transporte,
   catálogo de objetos del cliente).

## Premisas / Dependencias

- Depende de que exista el fichero `_DEV` (RU_01), con el formato de línea que se
  acuerde (concepto reducido al nº de documento PG, según propone EVA).
- `ZFI_T_FILE_LOG`, `ZFI_T_COBRO_CONF`, `zfi_cl_update_file_log`,
  `zxx_cl_msg_logs`, `zxx_cl_file_utils`, `zxx_cl_generic_on_memory` se reutilizan
  tal cual del programa original (mismas clases/tablas ya existentes en el sistema).
