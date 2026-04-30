# Test-ValidatorRun.ps1
# Purpose: Smoke run validators with safe defaults.
# Exit codes: 0 OK, 1 FAIL
#
# Notes:
# - Runs Validate-*.ps1 sequentially.
# - Excludes Validate-System.ps1 to avoid recursion.
# - If any validator is destructive or requires args, it must self-protect or be allowlisted/excluded here.

$ErrorActionPreference = "Stop"

$dir = Split-Path -Parent $PSCommandPath
$validators = Get-ChildItem -LiteralPath $dir -Filter "Validate-*.ps1" -File

if (-not $validators) {
  Write-Host "OK: No Validate-*.ps1 files found"
  exit 0
}

$hadFail = $false

foreach ($v in $validators) {
  if ($v.Name -ieq "Validate-System.ps1") {
    Write-Host "SKIP: $($v.Name) (orchestrator)"
    continue
  }

  Write-Host "RUN : $($v.Name)"
  try {
    $p = Start-Process -FilePath "powershell" -ArgumentList @(
      "-NoProfile",
      "-ExecutionPolicy","Bypass",
      "-File",$v.FullName
    ) -Wait -PassThru -NoNewWindow

    if ($p.ExitCode -ne 0) {
      $hadFail = $true
      Write-Host "FAIL: $($v.Name) exit code $($p.ExitCode)"
    } else {
      Write-Host "OK: $($v.Name)"
    }
  } catch {
    $hadFail = $true
    Write-Host "FAIL: Exception running $($v.Name): $($_.Exception.Message)"
  }
}

if ($hadFail) { exit 1 }
Write-Host "OK: All validators smoke-ran successfully"
exit 0
