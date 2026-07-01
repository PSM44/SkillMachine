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
- build-usecase

USAGE:
pwsh -File SyS\A_Tools\Launcher\Start-SkillsMachine.ps1 -Action help
pwsh -File SyS\A_Tools\Launcher\Start-SkillsMachine.ps1 -Action status
pwsh -File SyS\A_Tools\Launcher\Start-SkillsMachine.ps1 -Action radar-status
pwsh -File SyS\A_Tools\Launcher\Start-SkillsMachine.ps1 -Action session-close-readiness
pwsh -File SyS\A_Tools\Launcher\Start-SkillsMachine.ps1 -Action package-upload
pwsh -File SyS\A_Tools\Launcher\Start-SkillsMachine.ps1 -Action build-usecase
pwsh -File SyS\A_Tools\Launcher\Start-SkillsMachine.ps1 -Action build-usecase -RunBuild

PACKAGE UPLOAD:
The package-upload action validates the canonical self-contained usecase folder for session continuation.

Canonical upload folder:
90.USECASE\03.SESSION_CONTINUE

Upload rule:
Upload the full folder contents.

Do not use SyS\Temp\TO_UPLOAD_TO_IA as the default session-continuation package. That tool is for explicit IA-requested delta files, not the canonical usecase package.

BUILD USECASE:
The build-usecase action is safe by default.

Default mode:
pwsh -File SyS\A_Tools\Launcher\Start-SkillsMachine.ps1 -Action build-usecase

This validates build readiness and prints the explicit build command.

Execution mode:
pwsh -File SyS\A_Tools\Launcher\Start-SkillsMachine.ps1 -Action build-usecase -RunBuild

This executes:
90.USECASE\BUILD.ps1

Because BUILD.ps1 may regenerate usecase packages, execution requires the explicit -RunBuild flag.

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
It is not yet full Beta 0.1 until final demo/readme validation confirms a non-technical user can run the workflow without repo exploration.

BETA GATE:
Governed by GRCLake\01.CONTROLS\CONTROL.BETA_FUNCTIONALITY_GATE.txt.

AI TAIL:
Future MB scripts must follow GRCLake\01.CONTROLS\CONTROL.SCRIPT_OUTPUT_AI_TAIL.txt and SkillsLake\01.SKILLS\SKILL.SCRIPT_OUTPUT_AI_TAIL_CONTRACT.txt.

BETA 0.1 DEMO GUIDE:
HUMAN\SKILLSMACHINE.BETA_0_1.DEMO_GUIDE.txt

CURRENT DEMO ENTRYPOINT:
pwsh -File SyS\A_Tools\Launcher\Start-SkillsMachine.ps1 -Action help

CURRENT DEMO STATUS:
DEMO_READY=true
BETA_GATE=PARTIAL
