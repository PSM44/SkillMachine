==========
README.UPLOAD_THIS_USECASE
==========

USECASE............: 01.NEW_PROJECT
PURPOSE............: Abrir o inicializar un nuevo proyecto SkillMachine con contexto mínimo suficiente.
STATUS.............: ACTIVE
PACKAGE_MODEL......: SELF_CONTAINED_USECASE_FOLDER

==========
01.00_QUE_SUBIR_A_LA_IA
==========

Subir el contenido completo de esta carpeta:

C:\01. GitHub\Skills\90.USECASE\01.NEW_PROJECT

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
- No usar Temp\TO_UPLOAD_TO_IA.
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

C:\01. GitHub\Skills\90.USECASE\01.NEW_PROJECT

Objetivo:
Ejecutar el usecase 01.NEW_PROJECT.

Instrucciones:
1. Lee primero README.UPLOAD_THIS_USECASE.txt.
2. Lee USECASE.MANIFEST.json y SKILL_SET.MANIFEST.txt si existen.
3. Lee el prompt principal: PROMPT.NEW_PROJECT.txt.
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
If this usecase is used for an IT project, the IA must read and apply:
C:\01. GitHub\Skills\GRCLake\AA.CONSTITUTION

Minimum decisions before build:
- OUTPUT_TYPE: DEPLOY_DONE or DELIVERABLE_DONE
- FIRST_OUTPUT_CONTRACT
- MINIMUM_MOCKUP
- MUST_HAVE
- NO_SCOPE
- MAX_HOURS
- MAX_SESSIONS
- PLAN_B_TRIGGER
- PLAN_B_ACTION

Rule:
Do not expand platform, governance, architecture, tooling or future features before the first DEPLOY_DONE or DELIVERABLE_DONE unless it directly unblocks that output.
