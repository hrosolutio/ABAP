# ZFI_R_DEVOLUCIONES_CREA — Creación del lote de devoluciones (CDI_11)

Implementa **RU_02** del DF *"Procedimiento Gestión de extornos"* (CDI_11):
a partir del fichero `_DEV` (salida de [`zfi_r_ecofi_split/`](../zfi_r_ecofi_split/README.md),
desarrollo 1), crea el lote de devoluciones en FI-CA reutilizando el motor
estándar `RFKKA00` — misma idea que sugirió EVA en RU_03 para el desarrollo 3
(`ZFI_R_DEVOLUCIONES2`), aplicada aquí solo a la parte de **creación**
(`p_xcre`), nunca a cerrar/contabilizar (eso es RU_03).

Es el desarrollo 2 de 3 del proyecto CDI_11:
1. **División del fichero ECOFI** → [`zfi_r_ecofi_split/`](../zfi_r_ecofi_split/README.md)
2. **Creación del lote de devoluciones** → este programa.
3. **Cierre y contabilización del lote** → [`zfi_r_devoluciones2/`](../zfi_r_devoluciones2/README.md)

## Estado: reverse-engineering del formato hecho, SIN PROBAR contra RFKKA00

`ZFI_R_DEVOLUCIONES` (el original) genera los ficheros multicash
`AUSZUG`/`UMSATZ` que espera `RFKKA00` llamando a `RFKKSEPA_DD_RJCT` sobre el
XML SEPA de devolución real. El `_DEV` de extornos **no es XML**, así que
este programa genera esos dos ficheros **a mano**, campo a campo.

El formato se ha deducido de **6 ejemplos reales** (4 bancos distintos:
Santander, BBVA, CaixaBank, Unicaja) sacados de `ZFI_T_FILE_LOG`/AL11 en
Integración (carpeta `backup/` de `ZFICA_COBROS_DEVOLUCIONES`) — no es una
suposición a ciegas, pero **tampoco se ha probado nunca generándolo nosotros
mismos y pasándolo por `RFKKA00`**. Varios campos se dejan en blanco o con
valores por defecto porque el `_DEV` no lleva esa información (ver
"Pendiente" más abajo y `docs/DF_resumen.md` para el detalle campo a campo).

**Antes de dar esto por bueno hace falta una prueba real en Integración.**

Modo de ejecución: **servidor o upload**, mismo patrón que
`zfi_r_ecofi_split` — **norma acordada: el `AUSZUG`/`UMSATZ` se deja
siempre en la misma carpeta de donde se cargó el `_DEV`**, tanto en local
como en servidor (así hasta que se diga lo contrario):
- **Server**: escanea automáticamente todos los ficheros `*_DEV*` de la
  carpeta de la ruta lógica `ZFICA_COBROS_ECOFI` (la misma donde
  `ZFI_R_ECOFI_SPLIT` deja sus `_DEV`), genera `AUSZUG`/`UMSATZ` **en esa
  misma carpeta** (no en una subcarpeta `tmp/`), somete `RFKKA00` y traza
  en `ZFI_T_FILE_LOG`.
- **Upload**: prueba rápida con un `_DEV` local (`P_PATH`) — genera
  `AUSZUG`/`UMSATZ` y los descarga a la **misma carpeta local** de donde
  se subió el `_DEV`, sin depender de AL11 ni de la ruta lógica
  `ZFICA_COBROS_ECOFI` para nada de esto (precisamente porque
  `ZFICA_COBROS_ECOFI` **todavía no está creada en ningún sistema**, ver
  "Pendiente"). **Sin** traza en `ZFI_T_FILE_LOG` ni someter `RFKKA00`
  automáticamente, solo para validar la generación antes de someterlo a
  mano.

## Contenido del repositorio

```
src/
  ZFI_R_DEVOLUCIONES_CREA.abap        Programa principal (REPORT)
  ZFI_R_DEVOLUCIONES_CREA_TOP.abap    Include TOP
  ZFI_R_DEVOLUCIONES_CREA_EVE.abap    Include EVE (pantalla de selección)
  ZFI_R_DEVOLUCIONES_CREA_CLS.abap    Include CLS (clase lcl_devoluciones_crea)
docs/
  DF_resumen.md                        Resumen del Diseño Funcional + formato AUSZUG/UMSATZ deducido
```

## Cómo probarlo (SE38)

1. Crear el programa **`ZFI_R_DEVOLUCIONES_CREA`** (tipo *Report ejecutable*).
2. Crear los includes **`ZFI_R_DEVOLUCIONES_CREA_TOP`**, **`_EVE`**, **`_CLS`**
   con el contenido de `src/`, incluidos en ese orden.
3. Crear el elemento de texto **`TEXT-001`** (título bloque `P_PATH`, p.ej.
   "Fichero `_DEV`") y **`TEXT-002`** (título bloque de modo), igual que en
   `zfi_r_ecofi_split`.
4. **Antes de nada**, rellenar en `ZFI_R_DEVOLUCIONES_CREA_CLS`, clase
   `lcl_devoluciones_crea`, la constante `co_bank_code` (hoy vacía a
   propósito) — sin ese valor no se genera un `AUSZUG`/`UMSATZ` válido. Ver
   "Pendiente" abajo.
5. Activar.
6. **Primera prueba: modo Upload.** Coge un `_DEV` de prueba (el que ya
   generó `zfi_r_ecofi_split` en modo Upload vale) y ejecuta en modo
   Upload. El programa descarga `AUSZUG_TEST.txt`/`UMSATZ_TEST.txt` a la
   misma carpeta local de donde subiste el `_DEV` — revísalos a mano
   contra los ejemplos de `docs/DF_resumen.md` antes de someter `RFKKA00`
   con ellos manualmente (`SE38` → `RFKKA00` → `p_auszf`/`p_umsf`
   apuntando a esos ficheros ya subidos al servidor por otra vía, p.ej.
   AL11 o CG3Z, `p_xcre = X`) para la primera validación real.
7. **El modo Server necesita antes que Basis/funcional den de alta la ruta
   lógica `ZFICA_COBROS_ECOFI`** (transacción `FILE`) — hoy **no existe en
   ningún sistema**, ni Integración ni DES (solo se ha probado
   `zfi_r_ecofi_split` en modo Upload). Dentro de esa carpeta física hay
   que crear además las subcarpetas `procesados/` y `error/` (`OPEN
   DATASET` no las crea solas; `AUSZUG`/`UMSATZ` se generan directamente en
   la carpeta raíz, junto al `_DEV`, no en una subcarpeta aparte). Solo
   cuando eso exista y el paso 6 haya confirmado que `RFKKA00` acepta el
   formato, probar el modo Server completo (genera, somete y traza
   automáticamente).

## Pendiente / a definir con el cliente

Ver el detalle completo en `docs/DF_resumen.md`. Resumen de lo más
importante:

- **`co_bank_code`** (entidad+oficina, 8 dígitos): vacío, sin dato. En los
  ejemplos reales cambia según el banco que originó el fichero — para el
  flujo ECOFI no sabemos si hay una única cuenta de cobro fija o si depende
  del banco.
- **`co_bank_account`**: se usa `4305500150` (la cta. de compensación del
  DF) por longitud coincidente (10 dígitos) — sin confirmar que sea
  realmente el mismo dato.
- **Campos de `UMSATZ` en blanco**: BIC (32), IBAN (33) y motivo en formato
  largo (7) del deudor — el `_DEV` no los lleva (el ECOFI es un extracto
  propio de cobros, no el XML SEPA con detalle bancario). El motivo en
  formato corto (34) sí se rellena con el fijo del DF (`Z01`).
  Categoría (12): tampoco disponible, en blanco.
- **Fecha del extorno (campo 4 de `UMSATZ`)**: se usa la fecha de hoy, no
  la fecha real del extorno (el `_DEV` no la expone tal cual todavía).
- **Nº de secuencia del extracto (campo 3)**: fijo a `00001`. En los
  ejemplos reales es un contador que sube — con `00001` fijo, un segundo
  fichero procesado para la misma cuenta probablemente choque. Falta un
  mecanismo de numeración real.
- **Nomenclatura de lote `AAMMDDCDI11xx`** (pedida por el DF): el código
  usa el patrón de `ZFI_R_DEVOLUCIONES` (`file_id`, 6 caracteres) porque
  `RUNIDBS_KK` parece admitir solo 6 — falta confirmar en SE11 y adaptar la
  nomenclatura del DF si no encaja.
- **Alternativa no explorada**: en vez de generar `AUSZUG`/`UMSATZ` y pasar
  por `RFKKA00`, podría existir una cadena de FMs internos más directa
  (como se hizo para `zfi_fm_paylot_reverse`/`zfi_fm_payment_lot_clarify2`
  depurando `FP08`/`FPCPL`). No se ha investigado porque `RFKKA00` ya es un
  informe de fondo (no de diálogo) y `ZFI_R_DEVOLUCIONES` ya demuestra que
  funciona por `SUBMIT ... AND RETURN`; se deja anotado por si `RFKKA00` da
  problemas reales en la prueba.
- Alta del objeto en el sistema de transporte correspondiente al proyecto.
