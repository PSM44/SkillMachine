# Validate-System.ps1
# Runs non-destructive SkillMachine pre-commit validations.

$ErrorActionPreference = "Stop"

Write-Host "VALIDATION: naming"
powershell -ExecutionPolicy Bypass -File ".\SyS\A_Tools\Validation\Validate-SkillMachineNaming.ps1"
if ($LASTEXITCODE -ne 0) { exit 1 }

Write-Host "VALIDATION: structure"
powershell -ExecutionPolicy Bypass -File ".\SyS\A_Tools\Validation\Validate-Structure.ps1"
if ($LASTEXITCODE -ne 0) { exit 1 }

Write-Host "OK: system pre-commit validation passed"
exit 0
