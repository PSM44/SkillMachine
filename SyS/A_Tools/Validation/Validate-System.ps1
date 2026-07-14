$ValidationRepoRoot = [System.IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot "..\..\..")
)
if (-not (Test-Path -LiteralPath (Join-Path $ValidationRepoRoot ".git") -PathType Container)) {
    throw "Validation repository root not found: $ValidationRepoRoot"
}
Set-Location -LiteralPath $ValidationRepoRoot
# Validate-System.ps1
# Runs non-destructive SkillMachine pre-commit validations.

$ErrorActionPreference = "Stop"

Write-Host "VALIDATION: naming"

if ($env:SKILLS_DEV_TESTS -eq "1") {
  Write-Host "DEV TESTS: validator parse"
  powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "Test-ValidatorParse.ps1")
  if ($LASTEXITCODE -ne 0) { exit 1 }

  Write-Host "DEV TESTS: validator smoke run"
  powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "Test-ValidatorRun.ps1")
  if ($LASTEXITCODE -ne 0) { exit 1 }
}

powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "Validate-SkillMachineNaming.ps1")
if ($LASTEXITCODE -ne 0) { exit 1 }

Write-Host "VALIDATION: structure"
powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "Validate-Structure.ps1")
if ($LASTEXITCODE -ne 0) { exit 1 }

Write-Host "VALIDATION: consistency"
powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "Validate-Consistency.ps1")
if ($LASTEXITCODE -ne 0) { exit 1 }



Write-Host "VALIDATION: usecase registry schema"
powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "Validate-UsecaseRegistrySchema.ps1")
if ($LASTEXITCODE -ne 0) { exit 1 }
Write-Host "VALIDATION: GRC repository architecture"
powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "Validate-GRC-RepositoryArchitecture.ps1")
if ($LASTEXITCODE -ne 0) { exit 1 }

# MB-SM-044B_POWERSHELL_SYNTAX_GATE
Write-Host "VALIDATION: PowerShell syntax gate"
$PowerShellSyntaxValidator = Join-Path $PSScriptRoot "Test-PowerShellSyntax.ps1"
if (-not (Test-Path -LiteralPath $PowerShellSyntaxValidator -PathType Leaf)) {
    Write-Host "FAIL: missing PowerShell syntax validator: $PowerShellSyntaxValidator"
    exit 1
}
$PowerShellHost = Get-Command pwsh.exe -ErrorAction SilentlyContinue
if ($null -eq $PowerShellHost) {
    $PowerShellHost = Get-Command powershell.exe -ErrorAction SilentlyContinue
}
if ($null -eq $PowerShellHost) {
    Write-Host "FAIL: no PowerShell host available for syntax gate"
    exit 1
}
& $PowerShellHost.Source -NoProfile -ExecutionPolicy Bypass -File $PowerShellSyntaxValidator
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

Write-Host "OK: system pre-commit validation passed"
exit 0



