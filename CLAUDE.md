# Notas para desarrollo ABAP en este repositorio

Errores de sintaxis/activación que ya nos han salido en SE38 al escribir
código nuevo (no al copiar código existente), para no repetirlos.

## Literales de texto: comillas simples vs invertidas

- `'texto'` (comillas simples) es de tipo `C` (longitud fija = longitud del
  literal).
- `` `texto` `` (comillas invertidas) es de tipo `STRING`.

Esto revienta en dos sitios muy fáciles de escribir sin darte cuenta:

1. **`DATA(lv_x) = 'texto'.`** — `lv_x` se infiere como `C(n)`, no `STRING`.
   Si luego se pasa como parámetro actual a un `IMPORTING ... TYPE string`,
   el compilador lo marca como **"no es compatible con el tipo"**.
2. **Dentro de `VALUE string_table( ( 'texto' ) ... )`** (o cualquier
   `VALUE #()` de tabla/estructura cuyo tipo de línea sea `STRING`) — cada
   literal con comillas simples da el mismo error de tipo incompatible,
   aunque el `VALUE` ya declare el tipo de la tabla.

**Regla:** si el destino es (o puede ser) `TYPE string`, usar siempre
comillas invertidas para el literal, tanto en `DATA(x) = ` como dentro de
`VALUE #( ( ... ) )`.

## Los tipos de las clases Z reutilizadas no siempre son STRING

Clases como `zxx_cl_file_utils` o `zfi_cl_update_file_log` (reutilizadas en
varios desarrollos de este repo) tienen parámetros con tipos DDIC
concretos, no genéricos `string`:

- `zxx_cl_file_utils=>get_directory( ... IMPORTING e_directory = ... )` →
  `TYPE rsfillst-dirname`.
- `zxx_cl_file_utils=>move_server_file( i_sourcepath = ... i_targetpath =
  ... )` → `TYPE eseftappl`.
- `zfi_cl_update_file_log->create_log( iv_filename = ... )` → `TYPE
  zfi_t_file_log-file_name`.
- `zxx_cl_msg_logs->append_messages( iv_param_v1 = ... iv_param_v2 = ...
  )` → tampoco es `string` (error real de activación al pasar una
  variable `TYPE string` directa: "no es compatible con el tipo").

Si no se sabe el tipo exacto de un parámetro de este estilo, **envolver el
actual con `CONV #( ... )`** (sin indicar el tipo) para que se infiera del
parámetro formal, en vez de asumir `string` o adivinar el tipo DDIC exacto.
Para recibir un `IMPORTING`/`EXPORTING` (no se puede usar `CONV` ahí, hace
falta una variable), declarar una variable intermedia con el tipo DDIC real
(consultarlo en el código ya existente que use esa misma clase, como
`ZFI_R_DEVOLUCIONES2_CLS`) y convertir despues a `string` si hace falta con
`CONCATENATE lv_var '' INTO lv_string.` (que además recorta los espacios
finales propios de un campo de longitud fija, cosa que `&&` no hace).

Lo mismo aplica a **campos de tablas Z reutilizadas**, no solo a parámetros
de clase: `ZFI_T_CONSTANTS-CONSTANT_VALUE` (tabla de configuración
genérica usada en varios desarrollos para leer sociedad, rutas de
servidor, moneda, etc.) tampoco es `TYPE string` — error real de
activación: pasarlo directo a un `IMPORTING ... TYPE string` da **"no es
compatible con el tipo"**, igual que con los parámetros de clase. Mismo
fix: envolver con `CONV string( ... )` (aquí sí conviene indicar el tipo,
porque el destino es fijo) o pasar por una variable intermedia +
`CONCATENATE ... '' INTO ...` si hace falta recortar blancos de relleno.
Una asignación simple con `=` (`lv_x = ls_row-constant_value.`) sí es
válida sin conversión — el error solo salta al pasarlo como parámetro
actual de un método/función.

## `FIND REGEX` (POSIX) está obsoleto

Da un aviso ("el estándar POSIX está obsoleto"). Usar `FIND PCRE` en su
lugar — misma sintaxis de patrón para casos simples (`\d`, `\s`, anclas).

## `SELECT` con `@` (host expressions) exige "aritmética de punto fijo"

`SELECT ... INTO @DATA(lv_x) WHERE campo = @lv_variable.` (sintaxis Open SQL
moderna con `@`) solo compila si el programa tiene activo el atributo
**"Aritmética de punto fijo"**. Si no se quiere depender de ese atributo (o
no se sabe si estará activo), usar la sintaxis clásica sin `@`:

```abap
DATA: lv_x TYPE ...
SELECT SINGLE campo FROM tabla INTO lv_x WHERE campo2 = lv_variable.
```

## `CONV #()` redundante

El compilador avisa ("conversión redundante") si se envuelve con `CONV #()`
un valor que ya es del tipo que espera el parámetro — p.ej. un substring
`campo(50)` pasado a un parámetro de tipo genérico compatible. Es solo un
aviso, no bloquea la activación, pero conviene quitarlo cuando lo señale.

## División `/` entre dos `TYPE i` redondea, no da el decimal exacto

`lv_resultado = lv_entero_a / lv_entero_b.` (o dentro de un string template,
`|{ lv_entero_a / lv_entero_b DECIMALS = 2 }|`) con **los dos operandos
`TYPE i`** no calcula el cociente decimal real: redondea al entero más
cercano y solo entonces aplica el formato de decimales — activa sin error
ni aviso, así que no salta a la vista. Ejemplo real: convertir céntimos
(`TYPE i`) a euros con `lv_cent / 100` daba `1459 / 100` → `"15.00"` en vez
de `"14.59"`.

**Regla:** para dividir dos enteros y quedarte con el resultado decimal
exacto, no uses `/` a secas — separa la parte entera y el resto con `DIV` y
`MOD` (aritmética entera explícita) y compón el string a mano, o convierte
antes uno de los operandos a un tipo con decimales (`CONV p( ... )` con
`DECIMALS` explícitos, o un campo `TYPE p DECIMALS n` de verdad) antes de
dividir.

## Parámetro numérico (`sy-subrc`, etc.) pasado a un mensaje: usar string template, no `CONV #()`

Al pasar un valor numérico (`sy-subrc`, cualquier `TYPE i`/`TYPE n`) como
parámetro de un mensaje (`iv_param_v1`/`MESSAGE ... WITH ...`, o cualquier
método que reciba texto para sustituir `&1`/`&2`...), envolverlo con
`CONV #( sy-subrc )` deja el valor **justificado a la derecha** dentro del
campo del parámetro (relleno de espacios por delante, típicamente `CHAR50`
en las clases de log reutilizadas) — el mensaje sale con un hueco enorme
antes del número. Usar un string template (`|{ sy-subrc }|`) en su lugar:
da el valor limpio, justificado a la izquierda, sin relleno.

## Orden fijo de los parámetros en `CALL FUNCTION`

`CALL FUNCTION` exige las secciones en este orden exacto: `EXPORTING` →
`IMPORTING` → `TABLES` → `CHANGING` → `EXCEPTIONS`. No es una convención de
estilo, es sintaxis: poner `CHANGING` antes que `TABLES` (u otro orden
distinto al de arriba) da error de sintaxis al activar.

## Usar `TYPE`, no `LIKE`/`STRUCTURE`, para referenciar tipos del Diccionario

Al declarar una variable con el tipo de un campo/tabla/estructura del
Diccionario ABAP, usar siempre `TYPE` (`DATA: lv_x TYPE dfkkrk-keyr1.`), no
`LIKE` (`DATA: lv_x LIKE dfkkrk-keyr1.`) ni `STRUCTURE`. `LIKE` es sintaxis
antigua (pre-Diccionario ABAP unificado) y está desaconsejada en código
nuevo. Esto no aplica al operador SQL `LIKE` (`WHERE campo LIKE
lv_pattern.`), que es una cosa totalmente distinta y no hay que tocarlo.

## `CALL FUNCTION` a un parámetro tipado estricto: pasar `string` directo revienta en tiempo de ejecución, no al activar

Si el parámetro `EXPORTING` de un módulo de función (no una clase) está
declarado con un tipo DDIC concreto (p.ej. `EPS2_GET_DIRECTORY_LISTING`
con `IV_DIR_NAME TYPE EPS2FILNAM`, no genérico), pasarle directamente una
variable `TYPE string` **activa sin error** pero **revienta en tiempo de
ejecución** con un dump `CX_SY_DYN_CALL_ILLEGAL_TYPE` ("the function
module interface was defined in such a way that only fields of a
particular type can be specified...") — a diferencia de una llamada a
método, aquí el compilador no lo detecta en el chequeo de sintaxis.
**Regla:** igual que con las clases Z reutilizadas (ver más arriba),
envolver el actual con `CONV <tipo>( ... )` indicando el tipo DDIC exacto
del parámetro formal (consultar el interfaz real en `SE37`, que puede no
coincidir con ejemplos "de libro" — mismo módulo puede tener
parámetros/tipos distintos según el sistema/kernel).

## `PERFORM form(programa)` no vale dentro de una clase

La sintaxis corta para invocar un FORM de otro programa,
`PERFORM retrieve_data(saplfkktrace) USING ...`, da error de sintaxis
**dentro de un método de una clase** (contexto OO): *"PERFORM form(prog)"
is not supported in the OO context. Use "PERFORM form IN PROGRAM prog"*.
Fuera de una clase (programa clásico) sí sería válida.

**Regla:** en un método, usar siempre la forma larga:

```abap
PERFORM retrieve_data IN PROGRAM saplfkktrace
    USING 'X' 'X' 'X' 'X' 'X'.
```

## `EXPORT`/`IMPORT ... TO/FROM MEMORY` sin nombre no vale dentro de una clase

Igual que `PERFORM form(programa)` (ver arriba), la forma corta
`EXPORT variable TO MEMORY ID '...'` da error de sintaxis **dentro de un
método de una clase** (contexto OO): *"EXPORT var_1 ... var_n TO
memory" is not supported in the OO context. Use "EXPORT name_1 = var_1
... name_n = var_n TO memory" instead*. Fuera de una clase (programa o
módulo de función clásico) sí sería válida.

**Regla:** en un método, usar siempre la forma con nombre:

```abap
EXPORT gt_datos = gt_datos TO MEMORY ID 'MI_ID'.
```

El nombre (`gt_datos` a la izquierda del `=`) es la **clave del dato**
dentro de la memoria, no tiene por qué coincidir con el nombre de la
variable — pero si se lee desde otro programa/módulo de función con
`IMPORT`, ese nombre sí tiene que coincidir en los dos sitios (`IMPORT
gt_datos = lv_variable_local FROM MEMORY ID 'MI_ID'.`), aunque la
variable de destino se llame distinto.

## `ASSIGN` dinámico a una tabla con línea de cabecera: hace falta `[]`

`ASSIGN ('(PROGRAMA)NOMBRE_TABLA') TO <fs>` (con `<fs>` declarado `TYPE
STANDARD TABLE`) revienta en tiempo de ejecución con el dump
**`ASSIGN_TYPE_CONFLICT`** si `NOMBRE_TABLA` es una tabla interna **con
línea de cabecera** (declaración al estilo antiguo, `OCCURS n` o
similar — frecuente en programas estándar antiguos). Con línea de
cabecera, el nombre a secas se refiere a la **cabecera** (una estructura,
área de trabajo), no al cuerpo de la tabla — de ahí el choque de tipo
contra un `FIELD-SYMBOL` que espera una tabla.

**Regla:** para acceder al cuerpo de la tabla en un `ASSIGN` dinámico,
añadir `[]` al final del nombre:

```abap
ASSIGN ('(PROGRAMA)NOMBRE_TABLA[]') TO <fs>.
```

## `MESSAGE ... INTO` pisa `SY-SUBRC` como efecto colateral

Cualquier `MESSAGE` (con o sin `INTO`) actualiza los campos de sistema
del mensaje (`sy-msgid`/`sy-msgty`/`sy-msgno`/`sy-msgv1-4`) **y también
`sy-subrc`**. Si se usa `MESSAGE ... INTO lv_text.` dentro de una rutina
auxiliar (p.ej. para reconstruir el texto de mensajes capturados) que se
llama *después* de comprobar el `sy-subrc` de una llamada anterior pero
*antes* de usarlo (p.ej. para mostrarlo en otro mensaje de log), el
`sy-subrc` que se lea después ya no es el de la llamada original, sino
el que deja el último `MESSAGE`. Real: `sy-subrc` de un
`CALL FUNCTION` que fallaba salía como `0` en el mensaje de log porque,
entre medias, se llamaba a una rutina que hacía `MESSAGE ... INTO` por
cada línea de un detalle capturado.

**Regla:** guardar `sy-subrc` en una variable propia **inmediatamente**
después de la llamada cuyo resultado importa, antes de ejecutar
cualquier otra cosa (incluido cualquier `MESSAGE`) que pueda
sobrescribirlo.

## `SELECT SINGLE COUNT( * )` sin `INTO`: no fiarse de `SY-DBCNT` después

`SELECT SINGLE COUNT( * ) FROM tabla WHERE ...` sin cláusula `INTO`
**activa sin error** y no lanza ningún dump, pero el resultado del
conteo no se deja en ningún sitio fiable — comprobar después
`sy-dbcnt <> 0` para saber si había algún registro es una apuesta: si
antes de este `SELECT` hubo **cualquier otra operación de base de
datos** en el programa (otro `SELECT`, un `INSERT`/`UPDATE` de una clase
reutilizada, etc.), `sy-dbcnt` puede venir con el valor **residual de
esa otra operación**, no con el conteo real de esta consulta. Real: con
la tabla de verdad **vacía**, todas las líneas salían como "ya
registradas" porque `sy-dbcnt` arrastraba un `1` de un `INSERT` anterior
en el mismo método (`go_file_log->create_log`).

**Regla:** usar siempre un `INTO` explícito para el conteo:

```abap
DATA: lv_count TYPE i.
SELECT SINGLE COUNT( * ) FROM tabla INTO lv_count WHERE ...
IF lv_count <> 0.
```

## Si GitHub falla

Si la web de GitHub da error (incidencia de su lado, no del repo — se
puede comprobar en githubstatus.com), no merece la pena depurar el motivo:
mandar el fichero directamente al usuario (`SendUserFile`) en vez de seguir
intentando que cargue la web.
