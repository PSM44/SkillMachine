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


READINESS EXIT SEMANTICS:
The launcher distinguishes wrapper execution from readiness result.

- Wrapper exits 0 when the readiness script runs and produces outputs with readiness_status OK or WARN.
- Wrapper exits nonzero when the readiness script is missing, outputs are missing, JSON cannot be parsed, or readiness_status is FAIL.
- The readiness status remains visible in stdout as READINESS_STATUS.
