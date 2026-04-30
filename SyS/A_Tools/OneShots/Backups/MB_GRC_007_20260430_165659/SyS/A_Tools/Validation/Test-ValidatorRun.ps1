# Test-ValidatorRun.ps1
# Purpose: Smoke run validators with safe defaults.
# Exit codes: 0 OK, 1 FAIL
#
# Notes:
# - This test runs validators sequentially.
# - If a validator is destructive or requires args, it should self-protect and/or be excluded.

$ErrorActionPreference = "Stop"

function Fail([string]$Message) {
  Write-Host "FAIL: $Message"
  exit 1
}

$dir = Split-Path -Parent $PSCommandPath
$validators = Get-ChildItem -LiteralPath $dir -Filter "Validate-*.ps1" -File

if (-not $validators) {
  Write-Host "OK: No Validate-*.ps1 files found"
  exit 0
}

$hadFail = $false

foreach ($v in $validators) {
  # Exclude the orchestrator itself to avoid recursion
  if ($v.Name -ieq "Validate-System.ps1") {
    Write-Host "SKIP: $($v.Name) (orchestrator)"
    continue
  }

  Write-Host "RUN : $($v.Name)"
  try {
    # Run in a new powershell process to avoid variable leakage
    $p = Start-Process -FilePath "powershell" -ArgumentList @(
      "-NoProfile",
      "-ExecutionPolicy","Bypass",
      "-File", $v.FullName
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
