05.SKILLSMACHINE_UPDATE support package.

This folder is generated from core under SyS\A_Tools\Update.
The canonical updater implementation remains:
- SyS\A_Tools\Update\Invoke-SkillsMachineUpdate.ps1
- SyS\A_Tools\Update\Test-SkillsMachineUpdate.ps1
- SyS\A_Tools\Update\README.SKILLSMACHINE.UPDATE.txt
- SyS\A_Tools\Update\SKILLSMACHINE.PROJECT.BASELINE.schema.json
- SyS\A_Tools\Update\SKILLSMACHINE.UPDATE.MANIFEST.schema.json

DocumentConsistencyAudit is a preflight consumer only.
It may block unresolved critical document conflicts, but it does not auto-run this updater from 03 or 04.

PRIMARY_UPLOAD_MODEL: SINGLE_COMPILED_FILE
FOLDER_UPLOAD_REQUIRED: FALSE

Default: upload this compiled single-file artifact:

C:\01. GitHub\Skills\90.USECASE\05.SKILLSMACHINE_UPDATE\USECASE.05.SKILLSMACHINE_UPDATE.COMPILED.txt

Do not upload the entire 90.USECASE\05.SKILLSMACHINE_UPDATE folder by default.
Exact-path fallback only if the compiled file is missing, unreadable, truncated, or a named missing source is requested after reading it.

Do not treat this generated package as canon. If doctrine changes are needed, patch core and rebuild.
