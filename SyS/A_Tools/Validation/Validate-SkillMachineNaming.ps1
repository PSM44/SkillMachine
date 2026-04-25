# Validate-SkillMachineNaming.ps1
# Fails if legacy naming is found outside validation tooling.

$ErrorActionPreference = "Stop"

$matches = git grep "STANDARD\." -- `
    ":(exclude)SyS/A_Tools/Validation/Validate-SkillMachineNaming.ps1" `
    ":(exclude).git" `
    2>$null

if ($LASTEXITCODE -eq 0 -and $matches) {
    Write-Host "FAIL: legacy naming detected"
    Write-Host $matches
    exit 1
}

Write-Host "OK: no legacy naming detected"
exit 0
