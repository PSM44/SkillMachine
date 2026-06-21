# NS-PILOT-002 — YAML Task Scheduler

**Status:** SCAFFOLD_ONLY — no agent has run yet

## Propósito

Segundo piloto Nightshift. Compara Claude Code vs Codex Desktop ejecutando la
misma tarea de procesamiento de datos YAML desde cero, sin contexto compartido
entre agentes.

## Task

Construir un CLI Python (`cli.py`) que lea un archivo YAML con tareas y produzca
un reporte de texto filtrado y ordenado.

## Agentes futuros

| MB | Agente | Rama |
|----|--------|------|
| MB-NS-004A | Claude Code | `lab/ns-pilot-002-claude` |
| MB-NS-004B | Codex Desktop | `lab/ns-pilot-002-codex` |

Cada agente trabaja en su rama aislada. No mezclar outputs.

## Rutas permitidas (por agente)

Solo modificar archivos dentro de:

```
99.LABS/Nightshift/03_EXPERIMENTS/NS-PILOT-002_YAML_TASK_SCHEDULER/
```

No tocar canon SkillsMachine (`SkillsLake`, `GRCLake`, `90.USECASE`, `SyS`, `HUMAN`).

## Qué NO ejecutar todavía

- No crear ramas de agente hasta recibir instrucción explícita.
- No implementar `src/` ni `tests/` — están como `.gitkeep`.
- No enviar este prompt a Claude Code ni Codex todavía.

## Archivos del scaffold

| Archivo | Propósito |
|---------|-----------|
| `PILOT.SPEC.AI.txt` | Especificación canónica del task (dar a ambos agentes) |
| `AGENT_BRIEF.ClaudeCode.AI.txt` | Prompt operativo para Claude Code |
| `AGENT_BRIEF.Codex.AI.txt` | Prompt operativo para Codex Desktop |
| `TASKS.sample.yaml` | YAML de entrada para pruebas |
| `requirements.txt` | `pyyaml>=6.0` |
| `src/.gitkeep` | Placeholder — agentes implementan aquí |
| `tests/.gitkeep` | Placeholder — agentes implementan aquí |

## Evidencia

Los outputs de cada agente se registran en:

```
99.LABS/Nightshift/04_EVIDENCE/NS-PILOT-002_YAML_TASK_SCHEDULER/
```

## Próximos MBs

1. `MB-NS-004A_CLAUDE_CODE_RUN_001_NS_PILOT_002` — ejecutar Claude Code
2. `MB-NS-004B_CODEX_RUN_001_NS_PILOT_002` — ejecutar Codex Desktop
3. `MB-NS-005A_COMPARE_NS_PILOT_002` — comparar con rúbrica y documentar resultado
