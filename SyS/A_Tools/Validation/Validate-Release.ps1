# Validate-Release.ps1
# Runs release-level SkillMachine validations. May regenerate build outputs.

$ErrorActionPreference = "Stop"

Write-Host "VALIDATION: naming"
powershell -ExecutionPolicy Bypass -File ".\SyS\A_Tools\Validation\Validate-SkillMachineNaming.ps1"
if ($LASTEXITCODE -ne 0) { exit 1 }

Write-Host "VALIDATION: usecase build"
powershell -ExecutionPolicy Bypass -File ".\90.USECASE\BUILD.ps1"
if ($LASTEXITCODE -ne 0) {
    Write-Host "FAIL: BUILD.ps1 failed"
    exit 1
}

Write-Host "OK: release validation passed"
exit 0
