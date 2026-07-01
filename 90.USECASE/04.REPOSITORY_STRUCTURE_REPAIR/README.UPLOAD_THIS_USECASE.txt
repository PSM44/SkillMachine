==========
README.UPLOAD_THIS_USECASE
==========

USECASE............: 04.REPOSITORY_STRUCTURE_REPAIR
PURPOSE............: Reparar estructura de repositorio con governance, snapshot, CIS, validación y rollback.
STATUS.............: ACTIVE
PACKAGE_MODEL......: SELF_CONTAINED_USECASE_FOLDER

==========
01.00_QUE_SUBIR_A_LA_IA
==========

Subir el contenido completo de esta carpeta:

C:\01. GitHub\Skills\90.USECASE\04.REPOSITORY_STRUCTURE_REPAIR

Esto incluye, según corresponda:

- 00.SKILL.MENU.ACTIVE.txt
- 00.BUNDLE.CORE.txt
- 01.BUNDLE.CONTINUITY.txt
- 02.BUNDLE.GOVERNANCE.txt
- SKILL_SET.MANIFEST.txt
- USECASE.MANIFEST.json
- prompt/runbook/docs del usecase

==========
02.00_REGLAS
==========

- Esta carpeta es el paquete operativo de subida del usecase.
- No usar SyS\Temp\TO_UPLOAD_TO_IA.
- No pedir el repo completo por defecto.
- Si falta contexto, la IA debe pedir paths exactos adicionales.
- La IA debe distinguir estado confirmado, inferido y duda.
- La IA no debe crear o modificar canon automáticamente.
- Si detecta oportunidad de crear/mejorar Skill o GRC, debe registrarla como candidato.

==========
03.00_PROMPT_DE_ARRANQUE_SUGERIDO
==========

Hoy es [fecha/hora local], Santiago Chile.

Estoy trabajando con SkillsMachine.
Adjunto el contenido de:

C:\01. GitHub\Skills\90.USECASE\04.REPOSITORY_STRUCTURE_REPAIR

Objetivo:
Ejecutar el usecase 04.REPOSITORY_STRUCTURE_REPAIR.

Instrucciones:
1. Lee primero README.UPLOAD_THIS_USECASE.txt.
2. Lee USECASE.MANIFEST.json y SKILL_SET.MANIFEST.txt si existen.
3. Lee el prompt principal: SKILL.md.
4. Usa los bundles adjuntos como contexto operativo.
5. No asumas que tienes todo el repo.
6. Si falta contexto, pide paths exactos adicionales.
7. No pidas el repo completo.
8. No modifiques canon automáticamente.
9. Responde en formato WBS.

==========
04.00_DONE
==========

DONE when:
- IA understands the usecase.
- IA can identify whether context is sufficient.
- IA requests only exact missing paths if needed.
- IA does not request broad repository upload by default.

==========
05.00_IT_PROJECT_DELIVERY_CONSTITUTION
==========
If repository repair is part of an IT project, the IA must read and apply:
C:\01. GitHub\Skills\GRCLake\AA.CONSTITUTION

Repository repair must not become an excuse to delay DEPLOY_DONE or DELIVERABLE_DONE.

Allowed before first output:
- repair that directly unblocks deploy/deliverable;
- minimum structure required for execution, validation or continuity;
- rollback/safety needed to avoid damaging the repo.

Not allowed before first output unless explicitly justified:
- broad restructuring;
- aesthetic reorganization;
- governance expansion;
- non-critical architecture cleanup.

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
