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

Si no se sabe el tipo exacto de un parámetro de este estilo, **envolver el
actual con `CONV #( ... )`** (sin indicar el tipo) para que se infiera del
parámetro formal, en vez de asumir `string` o adivinar el tipo DDIC exacto.
Para recibir un `IMPORTING`/`EXPORTING` (no se puede usar `CONV` ahí, hace
falta una variable), declarar una variable intermedia con el tipo DDIC real
(consultarlo en el código ya existente que use esa misma clase, como
`ZFI_R_DEVOLUCIONES2_CLS`) y convertir despues a `string` si hace falta con
`CONCATENATE lv_var '' INTO lv_string.` (que además recorta los espacios
finales propios de un campo de longitud fija, cosa que `&&` no hace).

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

## Si GitHub falla

Si la web de GitHub da error (incidencia de su lado, no del repo — se
puede comprobar en githubstatus.com), no merece la pena depurar el motivo:
mandar el fichero directamente al usuario (`SendUserFile`) en vez de seguir
intentando que cargue la web.
