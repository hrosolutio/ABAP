# Normas para este repositorio

Código ABAP de Héctor (IS-U / FI-CA). El código se escribe aquí y él lo pega
a mano en el sistema (SE24 / SE37 / SE38).

## Cómo trabajamos

- Español, informal y directo. Héctor es ABAP con experiencia: no explicar
  lo básico.
- Paso a paso: decir qué pegar, dónde y qué comprobar en el sistema.
- Flujo: se pega en DEV, orden de copias a QA y se prueba en QA (en DEV no
  hay datos).
- Cada desarrollo tiene su carpeta con `README.md` (estado, pendientes y
  preguntas para funcional) y `docs/`. Lo que se descubra del sistema
  (exits, tablas Z, trucos) se apunta en `docs/`.

## Normas de código

- **Nada de `SELECT … ENDSELECT`.**
  - Para comprobar existencia o leer un valor: `SELECT SINGLE`.
  - Para "el último" o "el primero" con `ORDER BY`:
    `INTO TABLE @DATA(lt_x) UP TO 1 ROWS` y leer `lt_x[ 1 ]`.
  - Para varias filas: `INTO TABLE` y `LOOP`.
- No usar llamadas a métodos funcionales directamente en `APPEND` / `LOOP AT`
  / `APPEND LINES OF`: pasar antes por una variable local, por la release.
- Sintaxis hasta 7.40 SP08 (SQL con `@` y `INTO` al final, `VALUE`, `COND`,
  `SWITCH` y declaraciones inline sí).
- Comentarios en español, los justos: el porqué, no el qué.
- Nada de tablas o FM inventados: si no se conoce el objeto real, se deja un
  `TODO` y se pregunta.
- Pasar abaplint antes de dar el código por bueno.
