# Test-ValidatorRun.ps1 (PS 5.1 compatible, robust quoting)
# Purpose: Smoke run validators with safe defaults.
# Exit codes: 0 OK, 1 FAIL
#
# Key point:
# - Start-Process -ArgumentList as ARRAY is unsafe with spaces (it may not quote correctly).
# - We pass ONE SINGLE STRING and explicitly quote the -File path.

$ErrorActionPreference = "Stop"

$dir = Split-Path -Parent $PSCommandPath
$validators = Get-ChildItem -LiteralPath $dir -Filter "Validate-*.ps1" -File

if (-not $validators) {
  Write-Host "OK: No Validate-*.ps1 files found"
  exit 0
}

# Choose shell (prefer pwsh if available)
$shell = $null
try {
  $cmd = Get-Command pwsh -ErrorAction SilentlyContinue
  if ($cmd -ne $null) { $shell = $cmd.Source }
} catch { $shell = $null }

if (-not $shell) { $shell = "powershell.exe" }

$hadFail = $false

foreach ($v in $validators) {
  if ($v.Name -ieq "Validate-System.ps1") {
    Write-Host "SKIP: $($v.Name) (orchestrator)"
    continue
  }

  Write-Host "RUN : $($v.Name)"
  try {
    # One-string argument list with quoted file path
    $arg = '-NoProfile -ExecutionPolicy Bypass -File "' + $v.FullName + '"'

    $p = Start-Process -FilePath $shell -ArgumentList $arg -WorkingDirectory $pwd.Path -Wait -PassThru -NoNewWindow

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
