# SkillsMachine Operator Launcher

ENTRYPOINT:
pwsh -File SyS\A_Tools\Launcher\Start-SkillsMachine.ps1 -Action help

PURPOSE:
Provide one visible user-facing entrypoint for SkillsMachine operator workflows.

CURRENT ACTIONS:
- help
- status
- radar-status

BETA STATUS:
This is the first functional launcher slice.
It is not yet full Beta 0.1 because it does not yet execute session-close readiness, package upload, or usecase build wrappers.

NEXT ACTIONS:
- Add session-close-readiness wrapper.
- Add package-upload wrapper.
- Add build-usecase wrapper after safe contract confirmation.

BETA GATE:
Governed by GRCLake\01.CONTROLS\CONTROL.BETA_FUNCTIONALITY_GATE.txt.

AI TAIL:
Future MB scripts must follow GRCLake\01.CONTROLS\CONTROL.SCRIPT_OUTPUT_AI_TAIL.txt.

