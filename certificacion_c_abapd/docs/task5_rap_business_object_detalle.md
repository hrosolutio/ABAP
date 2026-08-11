# Tarea 5 — RAP Business Object, paso a paso detallado en Eclipse

Esta es la tarea más larga del examen porque encadena varios wizards y un quick-fix. Sigue el
orden exacto; si te saltas un paso (sobre todo la activación), el `Preview` final fallará.

## 1. Localizar y copiar `ZABAPDTRAVEL`

La tabla `ZABAPDTRAVEL` no está en tu paquete, sino en `ZC_ABAPD_EXAM` — por eso en la Tarea 1
te pedían añadir ese paquete a **Favorite Packages**.

1. En **Project Explorer**, despliega `Favorite Packages > ZC_ABAPD_EXAM > Dictionary Objects >
   Database Tables` y localiza `ZABAPDTRAVEL`.
   - Alternativa rápida: `Ctrl+Shift+A` (Open ABAP Development Object) → escribe `ZABAPDTRAVEL`
     → esto la abre en el editor, pero para copiarla necesitas el nodo en el árbol del Project
     Explorer (clic derecho sobre el editor también ofrece "Copy" en versiones recientes de ADT).
2. Clic derecho sobre `ZABAPDTRAVEL` → **Copy**.
3. Clic derecho sobre tu paquete `ZABAP_####` (o directamente sobre `Dictionary Objects >
   Database Tables` dentro de tu proyecto) → **Paste**.
4. Se abre el wizard **Copy Database Table**:
   - Nombre destino: `ZZ####TRAVEL` (doble Z al inicio — es literal, no un typo).
   - Package: `ZABAP_####` (debería venir preseleccionado).
   - Transport Request: selecciona la orden creada en la Tarea 2 (`Select` → tu orden, no
     crees una nueva).
   - Description: cualquier texto sensato.
   - `Finish`.
5. La tabla se abre en el editor. Actívala: icono ✔ verde en la toolbar, o `Ctrl+F3`.

## 2. Generar los objetos RAP (`Generate ABAP Repository Objects`)

1. Clic derecho sobre `ZZ####TRAVEL` (ya en tu paquete) → **Generate ABAP Repository
   Objects...** (en algunas versiones aparece como submenú `ABAP Repository Object Generators`).
2. En la primera pantalla del wizard, elige el generador **"OData UI Service"** (no "CDS Data
   Model" a secas, ni "SAP Fiori elements" con draft si no aparece con ese nombre exacto —
   busca la opción cuyo texto mencione *OData UI Service*).
3. Pulsa **Next** en cada pantalla **sin tocar ninguno de los nombres propuestos**. El wizard
   generará automáticamente, encadenados a partir del nombre de tu tabla:
   - Vista CDS de interfaz (p.ej. `ZI_Z####TRAVEL`)
   - Vista CDS de proyección / consumo (p.ej. `ZC_Z####TRAVEL`)
   - Metadata Extension (anotaciones UI)
   - Behavior Definition raíz e Behavior Definition de proyección — **`ZR_Z####TRAVEL`** es la
     que menciona el enunciado
   - Clase de implementación de comportamiento (behavior pool), p.ej. `ZBP_ZZ####TRAVEL`
   - Service Definition
   - Service Binding — **`ZUI_Z####TRAVEL_O4`**, el que usarás para el `Preview` final
4. `Finish`. Eclipse crea todos los objetos como **inactivos** (verás el icono con el
   triángulo/asterisco rojo).

## 3. Editar la Behavior Definition `ZR_Z####TRAVEL`

1. Ábrela con doble clic desde el Project Explorer (o `Ctrl+Shift+A` → `ZR_Z####TRAVEL`).
2. Verás un esqueleto generado parecido a esto (los nombres exactos de alias/etag pueden variar
   ligeramente según lo que haya propuesto el wizard — no los cambies, solo añade las dos
   líneas nuevas):

   ```abap
   managed implementation in class zbp_zz####travel unique;
   strict ( 2 );

   define behavior for ZZ####TRAVEL alias Z####Travel
   persistent table zz####travel
   lock master
   authorization master ( instance )
   {
     create;
     update;
     delete;

     field ( readonly ) Status;                     " <-- añade esta línea

     determination setInitialStatus on save { create; }   " <-- y esta

     mapping for zz####travel
     {
       // ... campos generados automáticamente
     }
   }
   ```

3. Guarda (`Ctrl+S`). Verás un **quick-fix** disponible (bombilla amarilla) sobre
   `setInitialStatus`, o un warning "Implementation missing".

## 4. Generar e implementar el método de la determinación

1. Coloca el cursor sobre `setInitialStatus` (en la línea de la determinación) y pulsa
   **`Ctrl+1`** (Quick Fix / Quick Assist).
2. Elige la opción **"Add determination implementation"** (el texto exacto puede variar según
   versión, busca la que menciona "implementation" / "local types"). Esto:
   - Crea (si no existe) una clase local `lhc_...` dentro del include *Local Types* de la clase
     de comportamiento `ZBP_ZZ####TRAVEL`.
   - Inserta el método `setInitialStatus` vacío, ya con la firma correcta (`IMPORTING keys FOR
     DETERMINE zz####travel~setInitialStatus`).
3. Completa el cuerpo del método. Plantilla de referencia:
   [`../src/task5_zbp_travel_determination.clas.abap`](../src/task5_zbp_travel_determination.clas.abap)
   — en resumen:

   ```abap
   METHOD setInitialStatus.

     DATA lt_update TYPE TABLE FOR UPDATE zz####travel.

     lt_update = VALUE #( FOR key IN keys
       ( %tky   = key-%tky
         Status = 'N' ) ).

     MODIFY ENTITIES OF zr_z####travel IN LOCAL MODE
       ENTITY zz####travel
         UPDATE FIELDS ( Status )
         WITH lt_update.

   ENDMETHOD.
   ```

   Si el nombre de la entidad/alias que usa tu behavior definition difiere (p.ej. usa el alias
   `Z####Travel` en vez de `zz####travel` como nombre de entidad en el `MODIFY ENTITIES`),
   ajusta ese identificador al que veas en tu propio editor — Eclipse te subrayará en rojo
   cualquier nombre incorrecto, así que el propio compilador te guía.

## 5. Activar todo en el orden correcto (o de una vez)

En vez de activar objeto por objeto en orden de dependencias, es más simple y seguro usar la
vista de objetos inactivos:

1. `Window > Show View > Other... > ABAP > ABAP Inactive Objects` (o icono de la barra con el
   triángulo naranja).
2. Verás listados todos los objetos que acabas de crear/tocar: tabla, vistas CDS, metadata
   extension, ambas behavior definitions, la clase de comportamiento, service definition y
   binding.
3. Selecciónalos todos (`Ctrl+A` dentro de esa vista) → botón **Activate** (✔). Eclipse resuelve
   automáticamente el orden de dependencias.
4. Si algo falla, revisa primero la clase de comportamiento (errores de sintaxis en el método
   `setInitialStatus` son la causa más común) y reintenta.

## 6. Probar el resultado

1. Abre el **Service Binding** `ZUI_Z####TRAVEL_O4` (doble clic).
2. Si aparece el botón **Publish**, púlsalo (deja el servicio activo en el runtime OData).
3. Selecciona la entidad expuesta (Travel) en la lista de la izquierda del editor del binding →
   botón **Preview**. Se abre una app Fiori Elements genérica en el navegador.
4. Crea un registro nuevo (`+ Create` o similar), rellena los campos obligatorios y guarda.
5. Verifica:
   - El campo **Status** no es editable en el formulario de creación/edición.
   - Tras guardar, el registro aparece con **Status = N**.

Si ambas condiciones se cumplen, la tarea está completa.
