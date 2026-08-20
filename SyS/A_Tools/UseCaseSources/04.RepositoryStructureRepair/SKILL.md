# 04.REPOSITORY_STRUCTURE_REPAIR — Skill

## Purpose
Repository structure repair package:
snapshot -> target structure -> CIS migration plan -> apply -> validation.

## DocumentConsistencyAudit integration
- Run `SyS\A_Tools\DocumentConsistencyAudit\Invoke-DocumentConsistencyAudit.ps1` in `full` mode before proposing or applying repair.
- Use the current project `ProjectRoot`; never cross roots.
- Treat `HUMAN` as authority of intent, auditable against `HUMAN`, `BATON`, registries, manifests, scripts and documentation. A historical WhoAmI file, if present, is not authority. WHOAMI_ACTIVE_CANON=NO.
- Mark external references as `[REF_CRUZADA: <project>]`.
- If the audit returns `HARD_CONFLICT`, diagnosis may continue but destructive or mutating repair must remain blocked pending human approval.
- 04 may recommend `05.SKILLSMACHINE_UPDATE`, but must not execute it automatically.

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
PRIMARY_UPLOAD_MODEL=SINGLE_COMPILED_FILE
FOLDER_UPLOAD_REQUIRED=FALSE
The compiled usecase file is the operational upload unit.

ARCHIVO_A_SUBIR:
C:\01. GitHub\Skills\90.USECASE\04.REPOSITORY_STRUCTURE_REPAIR\USECASE.04.REPOSITORY_STRUCTURE_REPAIR.COMPILED.txt

REGLAS:
- Upload the compiled single-file artifact by default.
- Do not upload the entire usecase folder by default.
- Exact-path fallback only if the compiled file is missing, unreadable, truncated, or the IA requests a named missing source after reading it.
- No usar SyS\Temp\TO_UPLOAD_TO_IA.
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
- Use `SyS/Temp/TempScript.sh` as reusable local paste/edit script file.
- Copy to `/tmp`, normalize BOM/CRLF, then execute.
- Do not delete `SyS/Temp/TempScript.sh` by default.

==========
MB-GRC-033F_USECASE_UPLOAD_FOCUS_GATE
==========
CANONICAL_COPY_IN_PACKAGE: README.UPLOAD_THIS_USECASE.txt
Apply the upload focus-gate from that file. Do not duplicate the full block here.
==========
FIN_MB-GRC-033F_USECASE_UPLOAD_FOCUS_GATE
==========
