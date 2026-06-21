# 04.REPOSITORY_STRUCTURE_REPAIR — Skill

## Purpose
Repository structure repair package:
snapshot -> target structure -> CIS migration plan -> apply -> validation.

## Delivery (policy compliant)
- 00.BUNDLE.CORE.txt
- 01.BUNDLE.CONTINUITY.txt
- 02.BUNDLE.GOVERNANCE.txt
- USECASE.MANIFEST.json
- SKILL.md (this file)

## Canonicality
HUMAN is canonical; this is an operational delivery artifact for the USECASE.




==========
MB-GRC-026I_USECASE_FOLDER_UPLOAD_PACKAGE
==========

REGLA:
La carpeta del usecase es el paquete operativo de subida a la IA.

CARPETA_A_SUBIR:
C:\01. GitHub\Skills\90.USECASE\04.REPOSITORY_STRUCTURE_REPAIR

REGLAS:
- Subir el contenido completo de la carpeta del usecase correspondiente.
- No usar Temp\TO_UPLOAD_TO_IA.
- No pedir el repo completo por defecto.
- Si falta contexto, pedir paths exactos adicionales desde SkillsLake, GRCLake, 00.CATALOG, SyS u otra ruta necesaria.
- Si se detecta oportunidad de crear o mejorar Skill/GRC, registrarla como candidato; no crear canon automáticamente.


## MB-GRC-027C_PROMPT_ENGINEERING_DISCOVERY_CHALLENGE

When repository structure repair requires creating, auditing, or improving prompts for IA execution, apply `30.SKILL.PROMPT_ENGINEERING_DISCOVERY_CHALLENGE.txt`.

Rules:
- Run discovery before final prompt generation.
- Challenge scope, inputs, outputs, restrictions, validation and hidden dependencies.
- Declare `PROMPT_READY` before producing final prompts.
- Use `DRAFT_NOT_READY` when relevant information is missing.
- Keep the pedagogical layer subordinate to the operational answer.
- Do not apply this skill to trivial edits where discovery cost exceeds operational value.

## MB-GRC-031B_IT_PROJECT_DELIVERY_CONSTITUTION

When repository structure repair supports an IT project, apply `GRCLake/AA.CONSTITUTION`.

Rules:
- Select whether the target output is `DEPLOY_DONE` or `DELIVERABLE_DONE`.
- Repair only what directly enables the first output unless the human explicitly approves broader repair.
- Register non-blocking repairs as backlog or technical debt.
- Do not let repository repair become portfolio sprawl, stop-loss avoidance, or governance theater.
- If repair exceeds the declared time/session budget, trigger Plan B.

## MB-GRC-031E_MARKDOWN_FILE_CREATION_SAFETY

When repository structure repair creates or modifies `.md` files, Mermaid diagrams, Markdown fences or long shell scripts, apply `31.SKILL.MARKDOWN_FILE_CREATION_SAFETY.txt`.

Rules:
- Use placeholder markers for Markdown-sensitive syntax.
- Do not deliver IA scripts containing literal triple backtick fences.
- Convert placeholders after file creation using character-code generation, for example chr(96) multiplied by 3.
- Use `Temp/TempScript.sh` as reusable local paste/edit script file.
- Copy to `/tmp`, normalize BOM/CRLF, then execute.
- Do not delete `Temp/TempScript.sh` by default.

==========
MB-GRC-033F_USECASE_UPLOAD_FOCUS_GATE
==========

STATUS............: ACTIVE
LAYER.............: USECASE_UPLOAD_PACKAGE_CONTROL
IMPORTANT.........:
This file is part of a 90.USECASE upload package. It is operational upload guidance for the IA.
It is not primary canon. If doctrine changes are needed, patch HUMAN, 00.CATALOG, SkillsLake,
GRCLake, registry/build sources, or an approved canonical source, then rebuild packages if applicable.

USECASE_FIRST_RULE:
Before proposing development, scripts, branches, commits, RADAR, Nightshift work, refactors,
or architecture changes, the IA must first identify and state the applicable usecase.

REQUIRED_INITIAL_RESPONSE:
The IA must start by declaring:

1. USECASE_DETECTED
2. USER_GOAL
3. CONFIRMED_CONTEXT
4. MISSING_CONTEXT
5. RECOMMENDED_UPLOADS
6. FOCUS_BOUNDARY
7. NEXT_ACTION

CONTEXT_RULE:
Do not request the full repository by default.
If context is missing, request exact paths or exact Skills/GRC/HUMAN/CATALOG/BATON/RADAR files.

ANTI_DRIFT_RULES:
- Do not treat 90.USECASE as primary canon.
- Do not create or modify canon automatically.
- Do not jump to technical execution before usecase framing.
- Do not use RADAR FULL by default.
- Do not confuse a lab/pilot workload with the central purpose of PS.SkillsMachine.
- Register Skill/GRC improvements as candidates unless the human explicitly approves a minibattle.

DONE_WHEN:
The IA can explain why the current request belongs to this usecase, what context is sufficient,
what context is missing, and the next minimal reversible action.

==========
FIN_MB-GRC-033F_USECASE_UPLOAD_FOCUS_GATE
==========
