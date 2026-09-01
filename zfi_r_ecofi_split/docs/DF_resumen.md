# Resumen del Diseño Funcional

**Documento origen:** CS_CDI_11_Procedimiento_Gestion_de_extornos (27/07/2026, con
comentarios de EVA), requisito **RU_01**.

Es el desarrollo 1 de 3 del proyecto CDI_11 (gestión de extornos):
1. **División del fichero ECOFI** en transferencias/extornos → este programa.
2. Creación del lote de devoluciones → [`zfi_r_devoluciones2/`](../zfi_r_devoluciones2/README.md) *(pendiente, aún no empezado como programa independiente)*.
3. Cierre y contabilización del lote → [`zfi_r_devoluciones2/`](../zfi_r_devoluciones2/README.md).

## Objeto

Al llegar el fichero bancario de transferencias de ECOFI, generar dos ficheros a
partir de este: uno con las transferencias y otro con los extornos, ambos
manteniendo el formato del fichero original. El proceso debe garantizar que
todas las líneas se escriben en uno u otro fichero.

## Formato del fichero de entrada (verificado contra 2 ficheros reales)

Analizados `YFRECAU_1239_260402.140017.txt` (378 líneas) y
`YFRECAU_1239_260415.140018.txt` (148 líneas):

- **Primera línea** (cabecera): 20 caracteres, formato numérico
  (`01` + sociedad `1239` + fecha `ddmmaaaa` + `mmaaaa`), sin información de
  ninguna transferencia. Va **igual en ambos ficheros de salida**.
- **Resto de líneas**: 260 caracteres fijos cada una.
  - La cadena `EUR` aparece siempre en la **misma posición** (columna 102,
    offset 101 en las 260 líneas de datos de ambos ficheros — 100% constante).
  - Tras `EUR` y 2 espacios empieza el **concepto** (154 caracteres, hasta el
    final de la línea).
- **Regla de extorno** (verificada, sin excepciones en ninguno de los dos
  ficheros): el concepto **empieza por 24 dígitos** → es extorno. Coincide al
  100% con el indicador de 4 letras que trae el propio fichero en la zona de
  cabecera de línea (`ANUP` = extorno, `TRRD` = transferencia normal) — se usa
  como doble verificación, no como regla, porque el DF especifica la regla de
  los 24 dígitos.
  - Fichero 260402: 72 extornos (`ANUP`) / 305 transferencias (`TRRD`) sobre 377
    líneas de datos.
  - Fichero 260415: 57 extornos (`ANUP`) / 90 transferencias (`TRRD`) sobre 147
    líneas de datos.
- **Número de documento SAP a clarificar**: dígitos 13-24 del bloque de 24
  dígitos del concepto (los últimos 12), igual que en el ejemplo del DF
  (`000000051378481000009815` → `481000009815`). El ejemplo del propio DF
  coincide literalmente con la línea 73 de `YFRECAU_1239_260402.140017.txt`.

## Lógica implementada (`lcl_ecofi_split=>split_lines`)

- Línea 1 (cabecera) → se escribe en ambos ficheros de salida.
- Resto de líneas: se busca `EUR` (dinámicamente, no por columna fija, por si
  algún fichero futuro no respeta el offset 101) y se comprueban los 24
  caracteres siguientes (tras 2 espacios) del concepto.
  - Si son 24 dígitos → **extorno**: en el fichero `_DEV` se sustituye el
    concepto completo por los dígitos 13-24 (número de documento), manteniendo
    el ancho fijo de línea original (relleno de espacios) y el sufijo final de
    4 caracteres (`0020` en ambos ficheros de prueba).
  - Si no → **transferencia**: se escribe la línea completa, sin modificar, en
    el fichero `_TRF`.
- No se pierde ninguna línea: en las pruebas locales, `_TRF` + `_DEV` (sin
  contar la cabecera duplicada) siempre suma el total de líneas de datos del
  fichero original.
- Nomenclatura de fichero de salida: se inserta `_TRF`/`_DEV` antes de la
  **última** extensión del nombre original (ej.
  `YFRECAU_1239_260402.140017_TRF.txt`), igual que el ejemplo del DF.

## Fuera de alcance (de este programa)

- **RU_02/RU_03**: la creación, cierre y contabilización del lote de
  devoluciones son desarrollos aparte (`zfi_r_devoluciones2/`), este programa
  solo genera el fichero `_DEV` que consumirán.
- Integración con el proceso actual que crea el lote de transferencias
  (filtrar por `_TRF` vs. mover ficheros a otras carpetas, comentario de EVA en
  RU_01) — no forma parte de este programa, es una decisión operativa sobre
  el proceso existente.

## Pendiente / a definir con el cliente

- **Formato de la línea de extorno en `_DEV`**: este programa mantiene el
  ancho fijo de 260 caracteres (concepto sustituido por el nº de documento +
  relleno de espacios + sufijo `0020` original). El ejemplo del DF muestra una
  línea más corta (sin relleno) — confirmar si el ancho fijo importa para el
  desarrollo 2 (creación del lote) o si es indiferente.
- **Modo de ejecución en producción**: el programa ya tiene modo servidor —
  radio button `p_server`, sin pedir ruta (a diferencia del upload): escanea
  automáticamente **todos** los ficheros de la carpeta de **entrada**
  (`EPS2_GET_DIRECTORY_LISTING` + `OPEN DATASET`), deja `_TRF`/`_DEV` en una
  carpeta de **salida** distinta, y mueve cada original a una carpeta de
  **procesados** — también distinta — tras dividirlo (`ZXX_CL_FILE_UTILS=>
  MOVE_SERVER_FILE`, la misma utilidad que ya usa `ZFI_R_DEVOLUCIONES`), para
  no reprocesarlo. Las 3 rutas se leen de `ZFI_T_CONSTANTS`, todo variable
  (ya no hay ninguna ruta lógica hardcodeada en el código — la constante
  `co_logical_path` con `ZFICA_COBROS_ECOFI` inventada sin existir en ningún
  sistema, primer intento de este punto, fue corregida). Decisión: las 3
  filas viven bajo el **mismo `PROCESS_ID='DEVOL_CREA'`** que ya usa
  `ZFI_R_DEVOLUCIONES_CREA` — deliberadamente no se da de alta un
  `PROCESS_ID` propio (`ECOFI_SPLIT`) en `ZFI_T_PROCESS`, tratando los dos
  programas como el mismo eslabón lógico del proceso. Se distinguen solo
  por `CONSTANT_ID`: entrada tiene fila nueva (`CONSTANT_ID='RUTA_LOG_ECOFI'`)
  y procesados también (`CONSTANT_ID='RUTA_LOG_PROC'`); la de salida **no
  tiene fila propia**, se lee directamente de la fila que ya usa
  `ZFI_R_DEVOLUCIONES_CREA` (`CONSTANT_ID='RUTA_LOGICA'`, mismo
  `PROCESS_ID='DEVOL_CREA'`), que es quien escanea esa misma carpeta
  buscando los `_DEV` — una única fuente de verdad para la carpeta
  compartida, ver `README.md`. **Sin probar aún dentro de SAP** y sin
  disparo automático: hoy hay que ejecutarlo a mano en SE38. Falta:
  - Crear las rutas lógicas de entrada y de procesados (transacción `FILE`)
    apuntando a sus rutas físicas reales (la de entrada, ¿la misma AL11
    `/interfaces/cobros/transf_N43/in` que menciona el comentario de EVA, o
    una carpeta de staging distinta?; la de procesados, cualquier otra
    carpeta — ya no tiene que ser subcarpeta de la de entrada) y dar de alta
    sus filas en `ZFI_T_CONSTANTS`.
  - Decidir cómo se dispara en producción: job propio programado, o
    integrado en el job que hoy crea el lote de transferencias.
- Si la moneda puede ser distinta de `EUR` en algún caso (el programa localiza
  el concepto buscando la primera ocurrencia de `EUR` en la línea).
- Alta del objeto en el sistema de transporte correspondiente al proyecto.
