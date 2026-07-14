05.SkillsMachineUpdate support package.

This folder is generated from core under SyS\A_Tools\Update.
The canonical updater implementation remains:
- SyS\A_Tools\Update\Invoke-SkillsMachineUpdate.ps1
- SyS\A_Tools\Update\Test-SkillsMachineUpdate.ps1
- SyS\A_Tools\Update\README.SKILLSMACHINE.UPDATE.txt
- SyS\A_Tools\Update\SKILLSMACHINE.PROJECT.BASELINE.schema.json
- SyS\A_Tools\Update\SKILLSMACHINE.UPDATE.MANIFEST.schema.json

DocumentConsistencyAudit is a preflight consumer only.
It may block unresolved critical document conflicts, but it does not auto-run this updater from 03 or 04.

Upload and use the full 90.USECASE\05.SkillsMachineUpdate folder as one support package.
Do not treat this generated package as canon. If doctrine changes are needed, patch core and rebuild.
