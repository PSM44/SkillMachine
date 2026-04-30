# Validate-System.ps1
# Runs non-destructive SkillMachine pre-commit validations.

$ErrorActionPreference = "Stop"

Write-Host "VALIDATION: naming"

if ($env:SKILLS_DEV_TESTS -eq "1") {
  Write-Host "DEV TESTS: validator parse"
  powershell -ExecutionPolicy Bypass -File ".\SyS\A_Tools\Validation\Test-ValidatorParse.ps1"
  if ($LASTEXITCODE -ne 0) { exit 1 }

  Write-Host "DEV TESTS: validator smoke run"
  powershell -ExecutionPolicy Bypass -File ".\SyS\A_Tools\Validation\Test-ValidatorRun.ps1"
  if ($LASTEXITCODE -ne 0) { exit 1 }
}

powershell -ExecutionPolicy Bypass -File ".\SyS\A_Tools\Validation\Validate-SkillMachineNaming.ps1"
if ($LASTEXITCODE -ne 0) { exit 1 }

Write-Host "VALIDATION: structure"
powershell -ExecutionPolicy Bypass -File ".\SyS\A_Tools\Validation\Validate-Structure.ps1"
if ($LASTEXITCODE -ne 0) { exit 1 }

Write-Host "VALIDATION: consistency"
powershell -ExecutionPolicy Bypass -File ".\SyS\A_Tools\Validation\Validate-Consistency.ps1"
if ($LASTEXITCODE -ne 0) { exit 1 }


Write-Host "VALIDATION: GRC repository architecture"
powershell -ExecutionPolicy Bypass -File ".\SyS\A_Tools\Validation\Validate-GRC-RepositoryArchitecture.ps1"
if ($LASTEXITCODE -ne 0) { exit 1 }
Write-Host "OK: system pre-commit validation passed"
exit 0


