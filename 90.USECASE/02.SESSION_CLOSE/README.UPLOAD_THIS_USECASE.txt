==========
README.UPLOAD_THIS_USECASE
==========

USECASE............: 02.SESSION_CLOSE
PURPOSE............: Cerrar sesión, consolidar continuidad, ejecutar learning review y preparar próximo handoff.
STATUS.............: ACTIVE
PACKAGE_MODEL......: SINGLE_COMPILED_FILE

==========
01.00_QUE_SUBIR_A_LA_IA
==========

PRIMARY_UPLOAD_MODEL: SINGLE_COMPILED_FILE
FOLDER_UPLOAD_REQUIRED: FALSE

Default: upload this compiled single-file artifact:

C:\01. GitHub\Skills\90.USECASE\02.SESSION_CLOSE\USECASE.02.SESSION_CLOSE.COMPILED.txt

That file already contains this README, the usecase prompt, skill-set, menu and bundles.

Do not upload the entire usecase folder by default.

Exact-path fallback (not default): if the compiled file is missing, unreadable, truncated, or the IA requests a named missing source after reading it, upload that exact path only. Whole-folder upload is not the normal procedure.

==========
02.00_REGLAS
==========

- The compiled single-file artifact is the operational upload unit.
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
Adjunto el archivo compilado:

C:\01. GitHub\Skills\90.USECASE\02.SESSION_CLOSE\USECASE.02.SESSION_CLOSE.COMPILED.txt

Objetivo:
Ejecutar el usecase 02.SESSION_CLOSE.

Instrucciones:
1. Treat the compiled file as the primary package.
2. Identify README, prompt, skill-set, menu and bundles inside it.
3. Lee el prompt principal: PROMPT.SESSION_CLOSE.txt (already included in the compiled file).
4. Usa los bundles incluidos como contexto operativo.
5. No asumas que tienes todo el repo.
6. Si falta contexto, pide paths exactos adicionales.
7. No pidas el repo completo ni la carpeta completa del usecase por defecto.
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
