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

# Mandatory root folders
$mandatory = @("HUMAN","GRCLake","SkillsLake","SyS","90.USECASE")
foreach ($d in $mandatory) {
  if (-not (Test-Path -LiteralPath $d)) { Fail "Missing mandatory root folder: $d" }
}

# Recommended root folders
if (-not (Test-Path -LiteralPath "95.AI_MODULES")) {
  Warn "Missing recommended root folder: 95.AI_MODULES"
}

# Mandatory GRC template + policies
$mvp = "GRCLake\06.TEMPLATES\TEMPLATE.GRC.MVP.txt"
if (-not (Test-Path -LiteralPath $mvp)) { Fail "Missing GRC MVP template: $mvp" }

$polRepo = "GRCLake\00.POLICIES\POLICY.REPOSITORY.ARCHITECTURE.txt"
if (-not (Test-Path -LiteralPath $polRepo)) { Fail "Missing policy: $polRepo" }

$polName = "GRCLake\00.POLICIES\POLICY.NAMING.PATH_ID.txt"
if (-not (Test-Path -LiteralPath $polName)) { Fail "Missing policy: $polName" }

# Usecase 04 baseline (this is now part of our current plan)
$uc04 = "90.USECASE\04.REPOSITORY_STRUCTURE_REPAIR"
if (-not (Test-Path -LiteralPath $uc04)) { Fail "Missing usecase folder: $uc04" }

$ucFiles = @(
  "SKILL.md",
  "README.EXECUTION.txt",
  "USECASE.MANIFEST.json",
  "HUMAN.REPOSITORY_STRUCTURE_REPAIR.txt",
  "WHOAMI.REPOSITORY_STRUCTURE_REPAIR.txt",
  "BATON.TEMPLATE.txt",
  "RADAR.SNAPSHOT.SPEC.txt",
  "TARGET.STRUCTURE.TEMPLATE.txt",
  "CIS.MIGRATION.PLAN.TEMPLATE.txt",
  "VALIDATION.CHECKLIST.txt"
)

foreach ($f in $ucFiles) {
  $p = Join-Path $uc04 $f
  if (-not (Test-Path -LiteralPath $p)) { Fail "Missing required usecase file: $p" }
}

# Soft check: prevent canon drift under 90.USECASE (warn-only for now)
$suspicious = Get-ChildItem -LiteralPath "90.USECASE" -Recurse -File -ErrorAction SilentlyContinue |
  Where-Object { $_.Name -match '^POLICY\..+\.txt$' }

if ($suspicious) {
  Warn "Policy-like files found under 90.USECASE (ensure these are operational copies, not canonical sources)."
  $suspicious | Select-Object -ExpandProperty FullName | ForEach-Object { Write-Host "WARN: " }
}

Write-Host "OK: GRC repository architecture validation passed"
exit 0
