# Certificación C_ABAPD — SAP Certified Associate: Back-End Developer - ABAP Cloud

Guía paso a paso para resolver en **Eclipse / ABAP Development Tools (ADT)** las tareas del
examen basado en sistema (*C_ABAPD, Course Version 2601*). El PDF original de instrucciones
está en el chat que generó esta carpeta; aquí queda la chuleta operativa + plantillas de código
de referencia en [`src/`](src/).

> **Importante:** el propio examen indica en la página "Task 1: Context" que puedes usar
> ayudas como learning.sap.com, help.sap.com, la ayuda F1 (ABAP Keyword Documentation) y
> **se espera que uses Joule en ADT**. Es un examen "open-book" con IA permitida dentro de
> Eclipse — por eso esta guía tiene sentido como material de apoyo.

## Convenciones

- **`####`** = tu número de grupo/asiento de 4 dígitos (con ceros a la izquierda, ej. `0007`).
  Sustitúyelo **en todos los nombres de objetos** — mayúsculas/minúsculas y espacios exactos
  importan para la puntuación.
- Todos los objetos que crees deben **activarse** (excepto paquetes y clases de mensajes, que
  no se activan).
- Usa siempre la **misma orden de transporte** creada en la Tarea 2 para todos los objetos.

---

## 0. Preparación (antes de tocar Eclipse)

1. Comprueba versiones: **Eclipse 2025-12 o superior** y **ADT 3.56.0 o superior**
   (`Help > About Eclipse` / `Help > Installation Details` → busca "ABAP Development Tools").
   Si necesitas actualizar: `Help > Check for Updates` o instala el *update site* de ADT.
2. En el navegador, pulsa **Access Practice System**. Se abrirá una ventana con tu perfil.
3. **Número de grupo:** haz clic en el círculo con las iniciales (ej. "EL") arriba a la derecha
   → el número de 4 dígitos después de la "E" es tu `####` (ej. `E0007` → `0007`).
4. **Service URL:** en la barra de direcciones del navegador, copia la URL hasta el final de
   `hana.ondemand.com` (inclusive). La necesitarás para crear el proyecto ABAP Cloud.

## 1. Crear el proyecto ABAP Cloud en Eclipse

1. `File > New > ABAP Cloud Project`.
2. Pega la **Service URL** copiada en el paso anterior.
3. Eclipse abrirá el flujo de login SSO. Si te pide *Copy URL to Clipboard*, pégala en una
   ventana de **navegación privada / incógnito** (evita conflictos con sesiones guardadas).
   No te pedirá usuario/contraseña: el examen usa SSO.
4. Espera a que el proyecto termine de cargar en el **Project Explorer**.
5. **Favoritos:** clic derecho sobre el nodo del proyecto → `Favorite Packages` (o el ⭐ en la
   vista *Favorite Packages*) → añade el paquete `ZC_ABAPD_EXAM` (necesario para copiar objetos
   en tareas posteriores).

## 2. Tarea 2 — Crear el paquete

1. Clic derecho en tu proyecto → `New > ABAP Package`.
2. Nombre: `ZABAP_####`. Descripción: cualquier texto sensato (ej. "Package examen C_ABAPD
   grupo ####").
3. **Superpackage:** `ZSTUDENTS`.
4. Software Component / Application Component: deja los valores propuestos por defecto.
5. En el diálogo de **Transport Request**, crea una nueva orden (`Create new request`) con una
   descripción sensata. **Anota el número de la orden** — la reutilizarás en todas las tareas
   siguientes cuando Eclipse te pida transporte.
6. Los paquetes no se activan (no hace falta `Ctrl+F3`).

## 3. Tarea 3 — Jerarquía de clases (`ZCL_####_FLIGHT` / `ZCL_####_PASSENGER_FLIGHT`)

1. Clic derecho en `ZABAP_####` → `New > ABAP Class`.
2. Nombre: `ZCL_####_FLIGHT`. Elige tu orden de transporte.
3. En el editor de la clase, define:
   - Atributos **públicos de solo lectura externa** (`READ-ONLY` en `PUBLIC SECTION`):
     `carrier_id`, `connection_id`, `airport_from`, `airport_to`.
   - Atributo **protegido** (accesible solo por la clase y subclases): `plane_type`.
   - Método `CONSTRUCTOR` con los parámetros de entrada y la excepción, y su implementación.
4. Código de referencia completo: [`src/task3_zcl_flight.clas.abap`](src/task3_zcl_flight.clas.abap).
5. Repite el proceso para `ZCL_####_PASSENGER_FLIGHT`:
   - `New > ABAP Class`, en el wizard indica **Superclass** = `ZCL_####_FLIGHT`.
   - Atributo `seats_max` en `PRIVATE SECTION` (solo la propia clase accede).
   - `CONSTRUCTOR` que llama a `super->constructor( ... )` y lee `ZI_CABAPD_PASSENGER`.
   - Código de referencia: [`src/task3_zcl_passenger_flight.clas.abap`](src/task3_zcl_passenger_flight.clas.abap).
6. **Activa ambas clases** (`Ctrl+F3` o el icono ✔ verde). Puedes probarlas con `F9` (Run As >
   ABAP Application) usando un pequeño `IF_OO_ADT_CLASSRUN` de prueba, o con el botón "Run" en
   una clase de test ABAP Unit — no es obligatorio para la tarea, pero ayuda a verificar.
   Tipos de avión de prueba sugeridos: `A320-200`, `737-800`, `747-400`.

## 4. Tarea 4 — `ZCL_####_CONNECTIONS`

1. `New > ABAP Class` → `ZCL_####_CONNECTIONS` en `ZABAP_####`.
2. Método público de instancia `GET_CONNECTIONS`:
   - Importing `I_DEPARTURE TYPE /dmo/airport_from_id`.
   - Returning `R_CONNECTIONS TYPE zcert_connections`.
3. Implementa la lógica con `SELECT`/`SELECT ... JOIN` sobre `/dmo/connection` (ver ejemplo
   comentado en el enunciado con EDI). Plantilla completa:
   [`src/task4_zcl_connections.clas.abap`](src/task4_zcl_connections.clas.abap).
4. Activa la clase. Puedes probarla rápido con un breakpoint + `F9` o ABAP Unit, pasando
   `I_DEPARTURE = 'EDI'` (u otro aeropuerto de `/LRN/AIRPORT`) y comprobando el resultado.

## 5. Tarea 5 — RAP Business Object (`ZZ####TRAVEL`)

> 📖 **Guía ampliada, clic a clic:** [`docs/task5_rap_business_object_detalle.md`](docs/task5_rap_business_object_detalle.md)
> — cubre dónde encontrar `ZABAPDTRAVEL`, todas las pantallas del wizard de generación, el
> quick-fix (`Ctrl+1`) para generar el método de la determinación, cómo activar todos los
> objetos generados en el orden correcto, y cómo probar con `Preview`. Lo que sigue aquí es el
> resumen rápido.

1. **Copiar la tabla:** en el Project Explorer, localiza `ZABAPDTRAVEL` (`Dictionary Objects >
   Database Tables`, o `Ctrl+Shift+A` para buscarla). Clic derecho → `Copy`, luego clic derecho
   sobre `ZABAP_####` → `Paste`. Nombre destino: `ZZ####TRAVEL` (¡doble Z inicial!). Confirma
   paquete `ZABAP_####` y tu orden de transporte.
2. Activa la tabla (`Ctrl+F3`).
3. Clic derecho sobre `ZZ####TRAVEL` → `Generate ABAP Repository Objects` (u `Other ABAP
   Repository Object Generators`). Elige el generador **OData UI Service**. Avanza el wizard
   **sin cambiar ninguna propuesta de nombre** (te generará automáticamente CDS de
   interfaz/proyección, `ZR_Z####TRAVEL` behavior definition, service definition/binding
   `ZUI_Z####TRAVEL_O4`, etc.).
4. Abre la **behavior definition** `ZR_Z####TRAVEL` (proyección). Añade el control de campo de
   solo lectura sobre `Status`:
   ```abap
   field ( readonly ) Status;
   ```
5. Declara la determinación en el mismo behavior definition:
   ```abap
   determination setInitialStatus on save { create; }
   ```
6. Eclipse ofrecerá (icono de bombilla / quick-fix `Ctrl+1`) generar el método en la clase de
   implementación de comportamiento. Acepta y completa el código — plantilla de referencia:
   [`src/task5_zbp_travel_determination.clas.abap`](src/task5_zbp_travel_determination.clas.abap).
7. Activa **todos** los objetos generados/modificados (tabla, CDS, behavior definition, clase
   de implementación, service definition, service binding).
8. **Probar:** abre `ZUI_Z####TRAVEL_O4` (Service Binding) → botón `Publish` → selecciona la
   entidad → `Preview`. Crea un registro nuevo y guarda: el campo `Status` debe quedar en `N`
   y no debe ser editable.

## 6. Tarea 6 — CDS Access Control (`Z####_AGENCY`)

1. Busca `ZC_ABAPD_AGENCY` (`Ctrl+Shift+A`) → clic derecho `Copy` → pega en `ZABAP_####` →
   nombre `Z####_AGENCY`. Activa la vista.
2. Clic derecho sobre `ZABAP_####` → `New > Other ABAP Repository Object` → busca **"Access
   Control"** (CDS Access Control / DCL). Nombre `Z####_AGENCY`, vista de referencia
   `Z####_AGENCY`.
3. Completa el cuerpo con el objeto de autorización `/LRN/AGCY`, campo `agency_id` y actividad
   `03` (Display). Plantilla: [`src/task6_z_agency_access_control.dcls.txt`](src/task6_z_agency_access_control.dcls.txt).
4. Activa el control de acceso.

## 7. Tarea 7 — Manejo de excepciones (`ZCL_####_AGENCY_MODEL`)

1. Copia la clase `ZCL_AGENCY_MODEL` → pega en `ZABAP_####` como `ZCL_####_AGENCY_MODEL`.
   Activa.
2. `New > Other ABAP Repository Object > ABAP Exception Class` → nombre
   `ZCX_####_NO_AGENCY`. En el wizard marca **"Inherit from"** = `CX_STATIC_CHECK` (o el tipo
   que corresponda a un error esperado/manejable) y activa la opción de generar el texto de
   mensaje con **ID de mensaje** `ZC_ABAPD`, número `002`.
3. Completa la clase de excepción: constante de mensaje (`&1` = agencia) y un atributo público
   `agency` que se pase en el constructor. Plantilla:
   [`src/task7_zcx_no_agency.clas.abap`](src/task7_zcx_no_agency.clas.abap).
4. En `ZCL_####_AGENCY_MODEL->GET_AGENCY`, añade `RAISING zcx_####_no_agency` a la firma del
   método y, tras el `SELECT`, comprueba `sy-subrc <> 0` para elevar la excepción pasando la
   agencia. Ejemplo: [`src/task7_zcl_agency_model_snippet.abap`](src/task7_zcl_agency_model_snippet.abap).
5. Activa ambas clases.

## 8. Tarea 8 — Tipos de diccionario ABAP

1. **Estructura:** `ZABAP_####` → `New > Other ABAP Repository Object > Structure`. Nombre
   `Z####_CUSTOMER`. En el editor de componentes añade `CUSTOMER_ID`, `FIRST_NAME`,
   `LAST_NAME`, `STREET`, `POSTAL_CODE`, `CITY`, `COUNTRY_CODE`, usando como tipo (`Data
   element`) el mismo elemento de dato que el campo homónimo en `/DMO/CUSTOMER` (consulta la
   tabla con `Ctrl+Shift+A` si tienes dudas de qué data element usa cada campo).
2. En la pestaña/propiedades de la estructura, fija **Enhancement Category** =
   `Can Be Enhanced (Character-Type or Numeric)` (`#EXTENSIBLE_CHARACTER_NUMERIC`). Activa.
3. **Tipo tabla:** `New > Other ABAP Repository Object > Table Type`. Nombre `Z####_T_CUST`.
   - Line Type: `Z####_CUSTOMER`.
   - Access Type: **Hashed**.
   - Key: **Unique**, campo clave `CUSTOMER_ID` (es el único campo garantizado único, según el
     enunciado — una tabla hashed exige clave única).
4. Activa el tipo tabla.

## 9. Enviar el examen (Unit 1)

- Vuelve a la pestaña del navegador donde accediste al examen y pulsa **Confirm completion**.
- Espera hasta 15 minutos para la validación.
- Resultado visible en **learning.sap.com > My Certifications**.

---

## Unit 2 — Tareas no usadas (práctica opcional)

El propio documento las marca como *"Unused Tasks"*: no forman parte de la evaluación
puntuable, pero son buen material de práctica adicional con el mismo escenario de datos.
Plantillas en `src/`:

- **Tarea 9** — Factorial (`ZCL_####_FACTORIAL`, excepciones `ZCX_C_ABAPD_FACTORIAL_NEG` /
  `CX_SY_ARITHMETIC_OVERFLOW`): [`src/bonus_task9_zcl_factorial.clas.abap`](src/bonus_task9_zcl_factorial.clas.abap).
- **Tarea 10** — `ZCL_####_NEXTFLIGHTS` con tipo público `TT_FLIGHTS` y agregación `MIN` sobre
  `/dmo/flight`: [`src/bonus_task10_zcl_nextflights.clas.abap`](src/bonus_task10_zcl_nextflights.clas.abap).
- **Tarea 11** — CDS view `Z_####_FLIGHTS` con conversión de divisa a USD:
  [`src/bonus_task11_z_flights_cds.txt`](src/bonus_task11_z_flights_cds.txt).

---

## Recordatorios de puntuación (de la Tarea 1: Context)

- Nombres de objetos **exactamente** como se piden (mayúsculas/espacios/guiones).
- Usa los **tipos exactos** indicados para variables/parámetros cuando se especifiquen.
- **Activa todo** lo que crees (excepto paquetes y clases de mensajes).
- Tienes **3 horas** en el examen real — practica el flujo de wizards antes para ir rápido.
