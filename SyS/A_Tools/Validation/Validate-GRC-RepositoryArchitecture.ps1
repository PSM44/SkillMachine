# Validate-GRC-RepositoryArchitecture.ps1
# GRC Gate: validates mandatory repository architecture for SkillMachine (non-destructive).
# EXIT CODES: 0 OK, 1 FAIL

$ErrorActionPreference = "Stop"

function Fail([string]$Message) {
  Write-Host "FAIL: $Message"
  exit 1
}

function Warn([string]$Message) {
  Write-Host "WARN: $Message"
}

Write-Host "VALIDATION: GRC repository architecture (HUMAN > GRC > SKILLS > USECASES)"

function Assert-CompiledUsecaseTarget {
  param(
    [Parameter(Mandatory = $true)][string]$TargetDirectory,
    [Parameter(Mandatory = $true)][string]$ExpectedCompiledFile,
    [Parameter(Mandatory = $true)][string[]]$RequiredTokens,
    [Parameter(Mandatory = $true)][string]$Label
  )

  if (-not (Test-Path -LiteralPath $TargetDirectory)) {
    Fail "Missing usecase folder: $TargetDirectory"
  }

  $subdirectories = @(Get-ChildItem -LiteralPath $TargetDirectory -Directory -Force -ErrorAction Stop)
  if ($subdirectories.Count -ne 0) {
    $names = @($subdirectories | ForEach-Object { $_.Name }) -join ', '
    Fail "Unexpected subdirectories in ${Label} target folder: $TargetDirectory => $names"
  }

  $files = @(Get-ChildItem -LiteralPath $TargetDirectory -File -Force -ErrorAction Stop)
  if ($files.Count -ne 1) {
    $names = @($files | ForEach-Object { $_.Name }) -join ', '
    Fail "Target folder must contain exactly one compiled artifact for ${Label}: $TargetDirectory (found $($files.Count): $names)"
  }

  $compiled = $files[0]
  if ($compiled.Name -ne $ExpectedCompiledFile) {
    Fail "Unexpected compiled artifact for ${Label}: expected $ExpectedCompiledFile but found $($compiled.Name)"
  }

  $content = Get-Content -LiteralPath $compiled.FullName -Raw -ErrorAction Stop
  foreach ($token in $RequiredTokens) {
    if ($content -notmatch ("(?m)^" + [regex]::Escape($token))) {
      Fail "Compiled artifact missing required token for ${Label}: $token ($($compiled.FullName))"
    }
  }
}

# --- Mandatory root folders ---
$mandatory = @("HUMAN","GRCLAke","SkillsLake","SyS","90.USECASE")
foreach ($d in $mandatory) {
  if (-not (Test-Path -LiteralPath $d)) { Fail "Missing mandatory root folder: $d" }
}

# --- Recommended root folders ---
if (-not (Test-Path -LiteralPath "95.AI_MODULES")) {
  Warn "Missing recommended root folder: 95.AI_MODULES"
}

# --- Mandatory GRC template + policies ---
$mvp = "GRCLake\06.TEMPLATES\TEMPLATE.GRC.MVP.txt"
if (-not (Test-Path -LiteralPath $mvp)) { Fail "Missing GRC MVP template: $mvp" }

$polRepo = "GRCLake\00.POLICIES\POLICY.REPOSITORY.ARCHITECTURE.txt"
if (-not (Test-Path -LiteralPath $polRepo)) { Fail "Missing policy: $polRepo" }

$polName = "GRCLAke\00.POLICIES\POLICY.NAMING.PATH_ID.txt"
if (-not (Test-Path -LiteralPath $polName)) { Fail "Missing policy: $polName" }

# --- 90.USECASE generated distribution contract (Gate D single compiled artifact model) ---
$primaryUsecaseRequiredTokens = @(
  'SOURCE_FILE_COUNT=',
  'SOURCE_PROVENANCE_EMBEDDED=YES',
  'SEPARATE_TARGET_MANIFEST_REQUIRED=NO'
)

Assert-CompiledUsecaseTarget -TargetDirectory '90.USECASE\01.NEW_PROJECT' -ExpectedCompiledFile 'USECASE.01.NEW_PROJECT.COMPILED.txt' -RequiredTokens $primaryUsecaseRequiredTokens -Label '01.NEW_PROJECT'
Assert-CompiledUsecaseTarget -TargetDirectory '90.USECASE\02.SESSION_CLOSE' -ExpectedCompiledFile 'USECASE.02.SESSION_CLOSE.COMPILED.txt' -RequiredTokens $primaryUsecaseRequiredTokens -Label '02.SESSION_CLOSE'
Assert-CompiledUsecaseTarget -TargetDirectory '90.USECASE\03.SESSION_CONTINUE' -ExpectedCompiledFile 'USECASE.03.SESSION_CONTINUE.COMPILED.txt' -RequiredTokens $primaryUsecaseRequiredTokens -Label '03.SESSION_CONTINUE'
Assert-CompiledUsecaseTarget -TargetDirectory '90.USECASE\04.REPOSITORY_STRUCTURE_REPAIR' -ExpectedCompiledFile 'USECASE.04.REPOSITORY_STRUCTURE_REPAIR.COMPILED.txt' -RequiredTokens $primaryUsecaseRequiredTokens -Label '04.REPOSITORY_STRUCTURE_REPAIR'

$supportPackageRequiredTokens = @(
  'SOURCE_FILE_COUNT=',
  'SOURCE_PROVENANCE_EMBEDDED=YES',
  'SEPARATE_TARGET_MANIFEST_REQUIRED=NO',
  'PACKAGE_TYPE=SUPPORT_PACKAGE',
  'SKILLSMACHINE_RUNTIME_DEPENDENCY=NO'
)

Assert-CompiledUsecaseTarget -TargetDirectory '90.USECASE\05.SKILLSMACHINE_UPDATE' -ExpectedCompiledFile 'USECASE.05.SKILLSMACHINE_UPDATE.COMPILED.txt' -RequiredTokens $supportPackageRequiredTokens -Label '05.SKILLSMACHINE_UPDATE'

# --- CHECK_POLICY_COPY_HEADERS (MB-GRC-006) ---
$policyCopies = Get-ChildItem -LiteralPath "90.USECASE" -Recurse -File -ErrorAction SilentlyContinue |
  Where-Object { $_.Name -match '^POLICY\..+\.txt$' }

if ($policyCopies) {
  foreach ($pc in $policyCopies) {
    $content = Get-Content -LiteralPath $pc.FullName -Raw -ErrorAction SilentlyContinue
    $missing = @()
    foreach ($k in @("SOURCE_CANONICAL_PATH","SOURCE_VERSION","COPY_DATE","COPY_MODE","CANONICALITY")) {
      if ($content -notmatch ("(?im)^\s*" + [regex]::Escape($k) + "\.*\s*:")) { $missing += $k }
    }
    if ($missing.Count -gt 0) {
      Warn ("Policy copy missing header fields under 90.USECASE: " + $pc.FullName)
      Warn ("Missing: " + ($missing -join ", "))
    }
  }
}

Write-Host "OK: GRC repository architecture validation passed"
exit 0




