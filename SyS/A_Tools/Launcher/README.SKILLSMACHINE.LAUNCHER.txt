# SkillsMachine Operator Launcher

ENTRYPOINT:
pwsh -File SyS\A_Tools\Launcher\Start-SkillsMachine.ps1 -Action help

PURPOSE:
Provide one visible user-facing entrypoint for SkillsMachine operator workflows.

CURRENT ACTIONS:
- help
- status
- radar-status
- session-close-readiness
- package-upload

USAGE:
pwsh -File SyS\A_Tools\Launcher\Start-SkillsMachine.ps1 -Action help
pwsh -File SyS\A_Tools\Launcher\Start-SkillsMachine.ps1 -Action status
pwsh -File SyS\A_Tools\Launcher\Start-SkillsMachine.ps1 -Action radar-status
pwsh -File SyS\A_Tools\Launcher\Start-SkillsMachine.ps1 -Action session-close-readiness
pwsh -File SyS\A_Tools\Launcher\Start-SkillsMachine.ps1 -Action package-upload

PACKAGE UPLOAD:
The package-upload action validates the canonical self-contained usecase folder for session continuation.

Canonical upload folder:
90.USECASE\03.SESSION_CONTINUE

Upload rule:
Upload the full folder contents.

Do not use Temp\TO_UPLOAD_TO_IA as the default session-continuation package. That tool is for explicit IA-requested delta files, not the canonical usecase package.

SESSION CLOSE READINESS:
The session-close-readiness action runs:
SyS\A_Tools\SessionClose\Test-SessionCloseReadiness.ps1

READINESS EXIT SEMANTICS:
The launcher distinguishes wrapper execution from readiness result.

- Wrapper exits 0 when the readiness script runs and produces outputs with readiness_status OK or WARN.
- Wrapper exits nonzero when the readiness script is missing, outputs are missing, JSON cannot be parsed, or readiness_status is FAIL.
- The readiness status remains visible in stdout as READINESS_STATUS.

BETA STATUS:
This is a functional launcher slice.
It is not yet full Beta 0.1 because build-usecase wrapper and final demo/readme validation are still pending.

BETA GATE:
Governed by GRCLake\01.CONTROLS\CONTROL.BETA_FUNCTIONALITY_GATE.txt.

AI TAIL:
Future MB scripts must follow GRCLake\01.CONTROLS\CONTROL.SCRIPT_OUTPUT_AI_TAIL.txt and SkillsLake\01.SKILLS\SKILL.SCRIPT_OUTPUT_AI_TAIL_CONTRACT.txt.
