# Validate-UsecaseRegistrySchema.ps1
# Purpose: Enforce minimal schema for 90.USECASE\USECASE.REGISTRY.json early (pre-commit).
# PS 5.1 compatible. Exit codes: 0 OK, 1 FAIL

$ErrorActionPreference = "Stop"

function Fail([string]$m){ Write-Host "FAIL: $m"; exit 1 }
function Warn([string]$m){ Write-Host "WARN: $m" }

Write-Host "VALIDATION: usecase registry schema"

$regPath = Join-Path (Resolve-Path ".").Path "90.USECASE\USECASE.REGISTRY.json"
if (-not (Test-Path -LiteralPath $regPath)) { Fail "Missing registry: $regPath" }

try {
  $registry = (Get-Content -LiteralPath $regPath -Raw -Encoding utf8) | ConvertFrom-Json
} catch {
  Fail ("Invalid JSON registry: " + $_.Exception.Message)
}

# build_policy required (your BUILD expects it)
if ($null -eq $registry.PSObject.Properties["build_policy"] -or $null -eq $registry.build_policy) {
  Fail "USECASE.REGISTRY.json missing build_policy"
}

$maxDelivery = $null
if ($registry.build_policy.PSObject.Properties["max_delivery_files_per_usecase"]) {
  $maxDelivery = [int]$registry.build_policy.max_delivery_files_per_usecase
}

if ($null -eq $registry.PSObject.Properties["usecases"] -or $null -eq $registry.usecases) {
  Fail "USECASE.REGISTRY.json missing usecases"
}

function SafeArray([object]$obj,[string]$prop){
  if ($null -eq $obj) { return @() }
  $p = $obj.PSObject.Properties[$prop]
  if ($null -eq $p) { return @() }
  if ($null -eq $obj.$prop) { return @() }
  # normalize to array
  if ($obj.$prop -is [System.Array]) { return @($obj.$prop) }
  return @($obj.$prop)
}

function HasProp([object]$obj,[string]$prop){
  return ($null -ne $obj -and $null -ne $obj.PSObject.Properties[$prop])
}

$failCount = 0
$warnCount = 0

foreach ($uc in @(SafeArray $registry "usecases")) {

  if (-not (HasProp $uc "name") -or -not [string]$uc.name) { $failCount++; Write-Host "FAIL: usecase missing name"; continue }
  $name = [string]$uc.name

  # required by BUILD strict reads (we already hardened some, but keep contract)
  foreach ($req in @("version","bundle_definitions","prompt_files","menu_files")) {
    if (-not (HasProp $uc $req)) {
      $failCount++
      Write-Host ("FAIL: {0} missing required property: {1}" -f $name,$req)
    } elseif ($null -eq $uc.$req) {
      $failCount++
      Write-Host ("FAIL: {0} has null required property: {1}" -f $name,$req)
    }
  }

  # array-ish fields must be arrays or scalars convertible, but not null
  foreach ($arr in @("prompt_files","menu_files")) {
    if (HasProp $uc $arr -and $null -ne $uc.$arr) {
      # ok, no further strict checks
    }
  }

  # bundle_definitions must exist (non-null). We don't assume exact shape; just presence.
  if (HasProp $uc "bundle_definitions" -and $null -ne $uc.bundle_definitions) {
    # ok
  }

  # optional arrays (Option B): if present, must not be null
  foreach ($opt in @("preserve_files","delivery_files_extra")) {
    if (HasProp $uc $opt -and $null -eq $uc.$opt) {
      $failCount++
      Write-Host ("FAIL: {0} has null optional array: {1} (must be [] if empty)" -f $name,$opt)
    }
  }

  # if delivery_files_extra present and maxDelivery known, enforce cap (defensive)
  if ($maxDelivery -ne $null -and (HasProp $uc "delivery_files_extra") -and $null -ne $uc.delivery_files_extra) {
    $cnt = @(SafeArray $uc "delivery_files_extra").Count
    # conservative rule: extras cannot exceed maxDelivery
    if ($cnt -gt $maxDelivery) {
      $failCount++
      Write-Host ("FAIL: {0} delivery_files_extra too large ({1} > {2})" -f $name,$cnt,$maxDelivery)
    }
  }

  # path hygiene for preserve/delivery extras (no absolute, no traversal)
  foreach ($pname in @("preserve_files","delivery_files_extra")) {
    if (HasProp $uc $pname -and $null -ne $uc.$pname) {
      foreach ($x in @(SafeArray $uc $pname)) {
        $s = [string]$x
        if ($s -match '^[A-Za-z]:\\') { $failCount++; Write-Host ("FAIL: {0} {1} contains absolute path: {2}" -f $name,$pname,$s) }
        if ($s -match '\.\.') { $failCount++; Write-Host ("FAIL: {0} {1} contains traversal '..': {2}" -f $name,$pname,$s) }
      }
    }
  }
}

if ($failCount -gt 0) { exit 1 }
Write-Host "OK: usecase registry schema validation passed"
exit 0
