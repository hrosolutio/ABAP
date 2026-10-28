# Certificación C_JSD_2610 — SAP Certified Associate: Joule Studio Developer

Apuntes de estudio estructurados a partir del curso oficial sobre **Joule Studio**, el entorno
de desarrollo de SAP Business AI para crear agentes, extensiones y flujos de trabajo. No hay
(todavía) un PDF de tareas de examen asociado — este documento recoge y organiza el contenido
de las 6 lecciones del curso para repaso.

## 1. La plataforma SAP Business AI — 3 pilares

SAP Business AI no es un LLM genérico: combina contexto de procesos, datos unificados y
gobernanza empresarial.

| Pilar | Qué cubre | Tecnologías clave |
|---|---|---|
| **Creación (Build)** | Crear y ampliar aplicaciones basadas en IA | **Joule Studio**, SAP Integration Suite |
| **Contexto y análisis (Context & Insight)** | Datos de alta calidad y relevantes para que la IA razone sobre procesos reales | **SAP Datasphere** (arquitectura de datos empresarial que unifica SAP + terceros) |
| **Gobernanza (Govern)** | Control del ciclo de vida de la IA: seguridad, transparencia, cumplimiento | **SAP AI Core**, **SAP AI Launchpad** |

## 2. Ecosistema Joule — quién hace qué

| Componente | Rol |
|---|---|
| **Joule** | Marca de IA de SAP (paraguas de todas las capacidades de IA del portfolio) |
| **Joule Work** | Espacio orientado al **usuario de negocio** — interactúa con funcionalidades de IA en lenguaje natural |
| **Asistentes de Joule** | Usan contexto de rol/negocio para coordinar agentes y procesos complejos |
| **Agentes de Joule** | Ejecutan tareas especializadas dentro de flujos de trabajo empresariales |
| **Joule Studio** | Entorno de **desarrollo** — donde developers crean/amplían agentes |

**Regla mnemotécnica:** Joule Work = consumir (negocio), Joule Studio = construir (desarrollo).

## 3. Tres principios de soluciones basadas en agentes confiables

1. **Contexto** — el agente necesita objetivos de negocio, conocimiento de dominio, datos,
   relaciones entre apps y procesos para interpretar correctamente la información.
2. **Abierto y de nivel empresarial (Open & Enterprise-grade)** — integración con arquitecturas
   existentes, estándares abiertos, arquitecturas extensibles, pruebas exhaustivas (incluyendo
   casos límite y excepciones, no solo el camino feliz).
3. **Gobernanza** — control de identidad/acceso, ejecución segura, trazabilidad de decisiones y
   acciones, visibilidad de rendimiento/coste/valor.

### Flujo "de la intención empresarial al valor repetible"
Entender necesidad → incorporar contexto (negocio/proceso/arquitectura) → componer/orquestar
agentes-apps-flujos → revisar con herramientas propias → implementar en entorno gestionado →
gobernanza y observabilidad continuas.

## 4. Fuentes de contexto empresarial en Joule Studio

| Fuente | Aporta |
|---|---|
| **SAP LeanIX** | Perspectiva de **arquitectura/landscape** (apps, dependencias, panorama tecnológico) |
| **SAP Signavio** | **Inteligencia de procesos** (rendimiento, cuellos de botella, oportunidades de mejora) |
| **SAP Knowledge Graph + SAP Domain Models** | **Contexto de aplicación** (objetos de negocio, estructuras de datos, relaciones/semántica) |
| **Mejores prácticas SAP** | Guías de desarrollo, principios arquitectónicos, patrones establecidos (seguridad/cumplimiento) |

> Truco de examen: si te preguntan "¿qué tecnología da información de **procesos**?" →
> Signavio. "¿Arquitectura/landscape?" → LeanIX. "¿Objetos/semántica de datos?" → Knowledge
> Graph / Domain Models.

## 5. Dos enfoques de desarrollo (nivel de clarificación de requisitos)

| Enfoque | Cuándo usarlo | Comportamiento |
|---|---|---|
| **Quick Create (Creación rápida)** | Requisitos ya claros | Omite preguntas de aclaración, genera directo |
| **Guía iterativa** | Escenarios complejos / requisitos ambiguos | Joule Studio hace preguntas específicas antes de generar |

Ambos producen artefactos usables en las fases siguientes (PRD, especificación, implementación).

## 6. Ciclo de vida de desarrollo de un agente (6 fases)

```
Análisis de intención de negocio
        ↓
PRD (Documento de Requisitos del Producto)
        ↓
Especificación técnica
        ↓
Código (implementación generada)
        ↓
Pruebas / Evaluación
        ↓
Despliegue (entorno de ejecución gestionado)
```

- **Intención de negocio**: describe el **qué** (problema, usuarios beneficiados, valor
  esperado), no el cómo técnico.
- **PRD**: traduce la intención a requisitos estructurados — problema, usuarios objetivo,
  requisitos funcionales, criterios de éxito. Revisión conjunta negocio + developers.
- **Especificación técnica**: el **cómo** — arquitectura, capacidades requeridas, puntos de
  integración, comportamiento esperado, restricciones.
- **Código**: artefactos de implementación generados a partir de la especificación + contexto
  SAP (Domain Models, Integration Suite, **n8n**). Código accesible y editable, no es caja
  negra. Gestionable con **Git**.
- **Pruebas**: dos niveles — **validación integral/end-to-end** (flujo completo, interacciones
  con herramientas) y **evaluación del comportamiento del agente** (calidad de resultados vs.
  requisitos). Resultados a nivel de componente ayudan a localizar fallos.
- **Despliegue**: al **entorno de ejecución gestionado por SAP** (identidad, seguridad,
  cumplimiento, controles operativos). Tras el despliegue: **observabilidad** (trazas, métricas,
  logs) y **gestión del ciclo de vida** vía **SAP AI Agent Hub** (descubrimiento y gestión
  centralizada de agentes en toda la empresa).

## 7. Extensión de agentes estándar SAP (sin tocar el agente original)

**Principio de núcleo limpio (clean core):** las extensiones son artefactos **independientes**
que amplían un agente SAP existente **sin modificar su implementación subyacente**. El código
fuente del agente original permanece inaccesible/sin cambios para quien hace la extensión.

### Tres puntos de extensión

| Punto de extensión | Qué permite | Ejemplo del curso |
|---|---|---|
| **Instrucciones (Instructions)** | Añadir contexto de escenario, reglas de negocio, medidas de seguridad | Directrices de negociación / políticas internas para un agente de compras |
| **Herramientas (Tools / MCP)** | Conectar sistemas/servicios externos vía **Model Context Protocol** | Acceso a info/servicios empresariales adicionales |
| **Hooks** | Lógica personalizada **antes o después** de la ejecución del agente | Notificar a un equipo cuando se marca una factura de cuentas por pagar |

- No todos los agentes SAP soportan todos los puntos de extensión — hay que revisar las
  capacidades del agente concreto en el **Catálogo de Agentes** antes de definir requisitos.
- Una vez desplegadas, las extensiones están disponibles cuando se invoca el agente estándar
  desde **Joule Work**.
- Gestión: los administradores controlan estado de implementación, historial, y pueden
  **desinstalar** extensiones. Al actualizarse el agente SAP base, hay que revisar la
  compatibilidad de sus extensiones.

## 8. Flujo paso a paso: crear una extensión de agente (ejemplo del curso)

Escenario: ampliar el **Agente de Negociación de Abastecimiento** (Sourcing Negotiation Agent)
para que añada un **resumen ejecutivo** (cumplimiento/auditoría, posicionamiento competitivo,
riesgos) a su análisis de ofertas de proveedores.

1. **Home de Joule Studio** → tipos de solución disponibles: **Agente, Flujo de trabajo n8n,
   Aplicación, Producto de datos, Extensión**. Elegir **Extensión**.
2. Pantalla "Crear una extensión de agente" → botón junto al campo **Agente** abre el
   **Catálogo de Agentes**.
3. **Catálogo de Agentes**: explorar/buscar/filtrar; cada agente muestra descripción + puntos de
   extensión soportados.
4. Vista de detalle del agente → revisar puntos de extensión → **"Seleccionar agente"**.
5. De vuelta en configuración: nombre descriptivo de la extensión + **Declaración de
   intención** (en lenguaje natural, describiendo el comportamiento deseado) + opción
   **Quick Create** (activarla si los requisitos ya están claros) → **Crear**.
6. Joule Studio genera los **requisitos** (muestra progreso/actividades en tiempo real).
7. Revisar el **PRD generado** (propósito, objetivos, métricas de éxito, requisitos
   funcionales) — comprobar que conserva la funcionalidad estándar del agente.
8. **Explorador de archivos**: artefactos generados —
   - `solution.yaml` (define la solución y referencia sus recursos)
   - recurso de extensión del agente
   - en este ejemplo, un **flujo de trabajo post-hook** (`executive-summary-post-hook`) que
     añade el resumen ejecutivo al resultado del agente.
9. Cambiar de vista **Develop → Manage**: página **Overview** con detalles de creación,
   producto SAP asociado, descripción, estado de implementación (inicialmente "no desplegado").
10. Botón **Implementar (Deploy)** → revisar estado → continuar con validación.

## 9. Flujos de trabajo n8n en Joule Studio

**n8n** = herramienta de automatización de flujos de trabajo de bajo código integrada en Joule
Studio, para coordinar agentes/automatizaciones SAP y de terceros.

### Flujo de creación (gestionado por el "Tablero de Ideas" / Idea Board)

1. Home → tile **"Flujo de trabajo n8n"** → **Crear**.
2. Configuración inicial: **Solución** (existente o nueva), **Nombre**, **Declaración de
   intención** (en lenguaje natural) + opción **Quick Create**.
3. **Idea Board**, etapas:
   - **Intención**: IA genera documento formal de intención (problema, objetivos, contexto).
   - **Requisito**: genera **PRD** (propuesta de valor, necesidades, objetivos específicos — ej.
     "automatizar ingesta de órdenes de compra vía API OData").
   - **Especificación**: detalles técnicos — directorios de recursos, pasos de implementación;
     Joule Studio prepara el entorno (descarga specs de API, configura estructura).
   - **Solución**: se configuran los componentes núcleo del agente del flujo —
     - **Mensaje del sistema** (rol/comportamiento del agente IA)
     - **Configuración LLM** (modelo, ej. Claude 3.5 Sonnet, y parámetros como temperatura)
4. **Lienzo n8n**: construcción visual conectando **nodos** (webhook trigger, clasificación IA,
   transformación de datos, integración con sistemas SAP como **SAP Task Center**). Soporta
   ramificación (branching), manejo de errores, orquestación multi-herramienta.
5. **Pruebas**: pruebas automatizadas de estructura, disponibilidad de servidor, lógica del
   agente; revisión de resultados y cobertura.
6. **Despliegue**: elegir entorno destino (ej. **Desarrollo**) → Joule Studio empaqueta y
   despliega.

### Ejemplo del curso
Flujo de trabajo que conecta con **SAP S/4HANA Private Cloud** para obtener nuevas órdenes de
compra y las envía a **SAP Task Center** para aprobación.

## 10. Glosario rápido para el examen

| Término | Definición corta |
|---|---|
| **PRD** | Product Requirements Document — requisitos estructurados derivados de la intención de negocio |
| **MCP** | Model Context Protocol — estándar abierto para que agentes usen herramientas/sistemas externos |
| **A2A** | Agent-to-Agent — protocolo de comunicación/interoperabilidad entre agentes |
| **Clean core** | Principio de extender sin modificar el núcleo/implementación original del agente SAP |
| **SAP AI Agent Hub** | Gestión centralizada: descubrimiento, gobernanza y ciclo de vida de agentes |
| **SAP AI Core / AI Launchpad** | Infraestructura de gobernanza del ciclo de vida de IA (pilar "Gobernanza") |
| **Entorno de ejecución gestionado por SAP** | Runtime donde se despliegan y ejecutan agentes/apps/flujos con identidad, seguridad y cumplimiento empresarial |
| **Idea Board** | Interfaz que guía Intención → Requisito (PRD) → Especificación → Solución en la creación de flujos n8n |

## Enlaces de profundización mencionados en el curso

- [Explorando el pilar de gobernanza de SAP Business AI Platform](https://learning.sap.com/courses/exploring-sap-business-ai-platform-architecture/exploring-the-govern-pillar-of-sap-business-ai-platform_bf774289-5b2b-4f21-8be6-3b72e0f919d0)
- [Facilitando la interoperabilidad para agentes de IA (A2A, MCP)](https://learning.sap.com/courses/boosting-ai-driven-business-transformation-with-joule-agents/enabling-interoperability-for-ai-agents)
- [Gestión de agentes de IA mediante AI Agent Hub](https://learning.sap.com/courses/boosting-ai-driven-business-transformation-with-joule-agents/managing-ai-agents-using-ai-agent-hub)
