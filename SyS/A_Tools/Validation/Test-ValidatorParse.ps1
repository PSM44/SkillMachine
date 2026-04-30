# Test-ValidatorParse.ps1
# Purpose: Parse/syntax check for validators (prevents broken scripts entering Validate-System).
# Exit codes: 0 OK, 1 FAIL

$ErrorActionPreference = "Stop"

function Fail([string]$Message) {
  Write-Host "FAIL: $Message"
  exit 1
}

$dir = Split-Path -Parent $PSCommandPath

$all = Get-ChildItem -LiteralPath $dir -Filter "*.ps1" -File |
  Where-Object { $_.Name -notmatch '^Test-Validator(Parse|Run)\.ps1$' }

if (-not $all) {
  Write-Host "OK: No validators found to parse"
  exit 0
}

$hadFail = $false

foreach ($v in $all) {
  try {
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($v.FullName, [ref]$tokens, [ref]$errors)

    if ($errors -and $errors.Count -gt 0) {
      $hadFail = $true
      Write-Host "FAIL: Parse errors in $($v.Name)"
      foreach ($e in $errors) {
        Write-Host ("FAIL:  {0} (line {1}, col {2})" -f $e.Message, $e.Extent.StartLineNumber, $e.Extent.StartColumnNumber)
      }
    } else {
      Write-Host "OK: Parse $($v.Name)"
    }
  } catch {
    $hadFail = $true
    Write-Host "FAIL: Exception parsing $($v.Name): $($_.Exception.Message)"
  }
}

if ($hadFail) { exit 1 }
Write-Host "OK: All validators parsed successfully"
exit 0

