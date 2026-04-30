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

# --- USECASE 04 baseline (bundle-first delivery) ---
$uc04 = "90.USECASE\04.REPOSITORY_STRUCTURE_REPAIR"
if (-not (Test-Path -LiteralPath $uc04)) { Fail "Missing usecase folder: $uc04" }

# UC04 is validated as an execution bundle package:
# it must ship bundle outputs + execution metadata, not legacy standalone continuity artifacts.
$ucFiles = @(
  "SKILL.md",
  "README.EXECUTION.txt",
  "USECASE.MANIFEST.json",
  "00.BUNDLE.CORE.txt",
  "01.BUNDLE.CONTINUITY.txt",
  "02.BUNDLE.GOVERNANCE.txt"
)

foreach ($f in $ucFiles) {
  $p = Join-Path $uc04 $f
  if (-not (Test-Path -LiteralPath $p)) { Fail "Missing required usecase file: $p" }
}

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



