# SkillMachine

## README — arquitectura Cline + OmniRoute

Este repositorio usa una arquitectura por capas donde la autoridad humana, la gobernanza, la lógica de ejecución y los adaptadores de IA están separados.

En ese marco:

- **Cline** se entiende como la **interfaz/canal operativo** desde el IDE para trabajar con un agente de código.
- **OmniRoute** se entiende como la **capa de routing/orquestación de modelos** que decide cómo enviar una tarea al modelo, proveedor o adapter correcto.
- **SkillsMachine Core** sigue siendo el dueño de las reglas del sistema: intención humana, gobernanza, contexto, límites, trazabilidad y contratos.

Importante: este README describe una arquitectura objetivo compatible con el canon actual del repo. No convierte a Cline ni a OmniRoute en autoridad canónica del producto. Son mecanismos de acceso y ejecución.

---

## 1. Resumen ejecutivo

La arquitectura **Cline + OmniRoute** propone separar claramente cinco responsabilidades:

1. **HUMAN** define intención, autoridad y criterio final.
2. **GRCLake** define controles obligatorios y límites fail-closed.
3. **SkillsLake** define cómo operar: routing, ejecución, validación, sandbox, costo y trazabilidad.
4. **Cline** actúa como front-end operativo para planificar y ejecutar tareas desde el IDE.
5. **OmniRoute** actúa como backplane de routing para seleccionar modelo, proveedor, modo y contexto según el tipo de trabajo.

El resultado es un sistema donde el agente puede ser útil y rápido, pero sin mezclar:

- autoridad humana,
- decisiones de routing,
- mutación de archivos,
- y transportes/proveedores de IA.

---

## 2. Principio central

La idea principal es:

**Cline no debe ser la autoridad del sistema. OmniRoute tampoco.**

Ambos son capas operativas.

- **Cline** resuelve la interacción diaria con el usuario dentro del IDE.
- **OmniRoute** resuelve a qué modelo se manda una tarea, con qué contexto y bajo qué política.
- **SkillsMachine** conserva la semántica del producto y las reglas de operación.

Esto está alineado con la doctrina actual del repo:

- un solo core del producto,
- dos canales de acceso (`DIRECT_UI` y `AI_INTEGRATION`),
- integración AI solo como adapter/transport,
- y una única gobernanza válida para todo el sistema.

---

## 3. Capas de la arquitectura

### 3.1 HUMAN — capa de autoridad

Es la capa superior.

Responsabilidades:

- definir intención,
- autorizar cambios materiales,
- resolver ambigüedad,
- decidir aplicación canónica,
- y conservar el significado del sistema.

Nada en Cline u OmniRoute reemplaza esta capa.

---

### 3.2 GRCLake — capa de controles obligatorios

Aquí viven los controles que no se negocian durante la ejecución.

Ejemplos:

- validación de dirty scope,
- restricciones de commit/push/build,
- reglas de sandbox,
- límites de evidencia,
- hard stops,
- serialización de mutaciones,
- y controles de workflow.

OmniRoute puede enrutar una tarea, pero **no puede debilitar GRC**.

---

### 3.3 SkillsLake — capa de procedimiento operativo

Esta capa define el **how-to** reutilizable.

Aquí encajan especialmente:

- `02.SKILL.AGENT_EXECUTION_POLICY.txt`
- `05.SKILL.ROUTING_POLICY.txt`
- `27.SKILL.MODEL_ROUTING_POLICY.txt`
- `01.ARCH.AI_ORCHESTRATION.CORE.txt`

Desde esta perspectiva:

- **Cline** consume estas reglas para operar.
- **OmniRoute** implementa técnicamente el routing definido por estas reglas.

Es decir: el policy vive en Skills; la ejecución concreta puede vivir en adapters/herramientas.

---

### 3.4 Cline — capa de interfaz y ejecución asistida

Cline ocupa el rol de **agente operativo principal** dentro del IDE.

Funciones esperadas:

- recibir la tarea del usuario,
- producir un plan,
- pedir o reunir contexto,
- proponer cambios,
- aplicar cambios autorizados,
- ejecutar validaciones permitidas,
- y reportar evidencia.

En términos del workflow canónico del repo, Cline puede materializar partes de:

- **Orchestrator** en la interacción,
- **Coordinator** en el plan,
- y **Executor** en la aplicación controlada,

pero sin reclamar autoridad humana propia.

Regla clave:

**el runtime/motor no equivale a autoridad.**

---

### 3.5 OmniRoute — capa de routing/orquestación de modelos

OmniRoute se ubica entre el agente operativo y los modelos/proveedores.

Su función es abstraer decisiones como:

- qué modelo usar,
- cuándo usar modelo local vs cloud,
- cuándo operar en modo PLAN / ACT / VALIDATE,
- cuánto contexto entregar,
- cuándo escalar a un modelo más fuerte,
- y cómo mantener costo, latencia y calidad dentro de política.

En esta arquitectura, OmniRoute **no es el dueño de la política**, sino su ejecutor técnico.

La política fuente sigue estando en Skills/GRC/HUMAN.

---

### 3.6 95.AI_MODULES — capa de adapters / transportes

La carpeta `95.AI_MODULES` representa la capa de integración con motores o herramientas específicas, por ejemplo:

- `01.CODEX_DESKTOP`
- `02.CLAUDE_CODE`
- `03.OPENCODE`

Esta capa no define el producto. Define cómo conectarse con un canal o proveedor concreto.

En una lectura arquitectónica:

- **Cline** puede ser un canal/agente principal de trabajo.
- **OmniRoute** puede decidir qué adapter usar.
- **95.AI_MODULES** contiene los detalles específicos de activación, prompts base y runbooks.

---

## 4. Flujo de extremo a extremo

El flujo recomendado sería el siguiente:

1. **Human** plantea una necesidad.
2. **Cline** transforma esa necesidad en una tarea operativa.
3. **OmniRoute** clasifica la tarea:
   - arquitectura,
   - code generation,
   - refactor,
   - debug,
   - documentación,
   - tooling,
   - o gobernanza.
4. **OmniRoute** selecciona:
   - modelo,
   - proveedor,
   - nivel de contexto,
   - modo de trabajo (`PLAN`, `ACT`, `VALIDATE`).
5. **Cline** ejecuta la secuencia autorizada:
   - inspección,
   - edición,
   - validación,
   - evidencia.
6. **GRC/Skills** restringen qué puede hacerse y cómo debe validarse.
7. **Human** acepta, corrige o bloquea.

---

## 5. Mapeo conceptual de responsabilidades

| Capa | Responsabilidad principal | No debe hacer |
|---|---|---|
| HUMAN | Intención, autoridad, aprobación | Delegar autoridad implícita al runtime |
| GRCLake | Controles obligatorios | Convertirse en motor de ejecución |
| SkillsLake | Procedimientos y policy | Reemplazar aprobación humana |
| Cline | Interacción y ejecución asistida | Inventar autoridad o saltarse GRC |
| OmniRoute | Routing de modelos y contexto | Reescribir policy canónica |
| 95.AI_MODULES | Adapters y transportes | Definir significado del producto |

---

## 6. Relación entre Cline y OmniRoute

La relación correcta no es “competencia”, sino **composición**:

- **Cline** = agente/canal operativo que conversa, inspecciona, edita y valida.
- **OmniRoute** = motor de decisión de routing que optimiza modelo, costo, contexto y proveedor.

Una forma simple de verlo:

```text
Usuario/HUMAN
   -> Cline
      -> OmniRoute
         -> Modelo / Provider / Adapter
      -> Herramientas locales / validadores / patching
   -> Evidencia / resultado
```

Si se invierte esta relación y Cline decide todo sin una capa clara de routing, aparecen problemas como:

- sobreuso del modelo caro,
- mezcla de PLAN y ACT,
- exceso de contexto,
- menor trazabilidad,
- y menor portabilidad entre proveedores.

---

## 7. Beneficios de esta arquitectura

### Beneficios funcionales

- mejor separación de roles,
- menor acoplamiento con un proveedor,
- routing explícito por tipo de tarea,
- reutilización del mismo core con distintos canales,
- y capacidad de escalar entre local/cloud.

### Beneficios operativos

- control de costo,
- trazabilidad más limpia,
- validación consistente,
- sandbox más fácil de gobernar,
- y mejor reemplazabilidad de adapters.

### Beneficios de producto

- el canon sigue en el repo, no en la herramienta,
- el workflow sobrevive a cambios de proveedor,
- y la arquitectura evita convertir un plugin o agente en “dueño del sistema”.

---

## 8. Riesgos y antipatrones

### Antipatrón 1 — Cline como autoridad

Error: asumir que porque Cline ejecuta, entonces puede decidir significado, prioridad o canon.

Corrección: la autoridad sigue en HUMAN + GRC + Skills.

### Antipatrón 2 — OmniRoute como policy owner

Error: mover las reglas de routing a código opaco sin reflejo canónico en Skills/GRC.

Corrección: OmniRoute implementa policy; no la inventa.

### Antipatrón 3 — Adapter = core

Error: hacer que un provider, MCP, plugin o gateway defina la arquitectura del producto.

Corrección: los adapters son transporte; el core sigue siendo provider-neutral.

### Antipatrón 4 — mezclar PLAN con APPLY

Error: usar el mismo flujo para pensar y para mutar canon sin gates claros.

Corrección: mantener separación explícita entre planificación, ejecución y validación.

---

## 9. Propuesta de diagrama simple

```text
HUMAN
  |
  v
Cline (IDE agent / operational interface)
  |
  +--> Skills policies (routing, execution, validation, sandbox)
  |
  +--> GRCLake controls (hard gates, authorization, fail-closed rules)
  |
  +--> OmniRoute (model/provider/context router)
          |
          +--> Local models
          +--> Cloud models
          +--> Provider adapters in 95.AI_MODULES
  |
  v
Workspace changes + evidence + validation results
```

---

## 10. Conclusión

La arquitectura **Cline + OmniRoute** funciona bien en este repositorio si se respeta esta premisa:

> **Cline opera, OmniRoute enruta, Skills definen el procedimiento, GRC restringe, y HUMAN manda.**

Ese diseño permite:

- aprovechar agentes modernos desde el IDE,
- cambiar de proveedor sin rehacer el producto,
- mantener control humano real,
- y sostener un workflow auditable y gobernado.

---

## Setup after clone

Install the local Git pre-commit hook:

    powershell -ExecutionPolicy Bypass -File "./SyS/A_Tools/Validation/Install-PreCommitHook.ps1"

Validate manually:

    powershell -ExecutionPolicy Bypass -File "./SyS/A_Tools/Validation/Validate-SkillMachineNaming.ps1"
