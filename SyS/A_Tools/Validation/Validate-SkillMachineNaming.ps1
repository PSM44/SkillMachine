# Validate-SkillMachineNaming.ps1
# Fails if legacy STANDARD.* naming is found.

$ErrorActionPreference = "Stop"

$matches = git grep "STANDARD\." 2>$null

if ($LASTEXITCODE -eq 0 -and $matches) {
    Write-Host "FAIL: legacy STANDARD.* naming detected"
    Write-Host $matches
    exit 1
}

Write-Host "OK: no legacy STANDARD.* naming detected"
exit 0
