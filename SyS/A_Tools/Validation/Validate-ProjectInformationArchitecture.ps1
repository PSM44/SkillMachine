# Validate-ProjectInformationArchitecture.ps1
# Deterministic owner/pointer/disposition checks. PS 5.1 compatible.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Fail([string]$m) { Write-Host "FAIL: $m"; exit 1 }

Write-Host 'VALIDATION: project information architecture owner'

$RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$SkillsDir = Join-Path $RepoRoot 'SkillsLake\01.SKILLS'
$OwnerFile = Join-Path $SkillsDir 'SKILL.PROJECT_INFORMATION_ARCHITECTURE.txt'
$BootstrapFile = Join-Path $SkillsDir '20.SKILL.PROJECT_BOOTSTRAP_POLICY.txt'
$RadarFile = Join-Path $SkillsDir '09.SKILL.RADAR.txt'

if (-not (Test-Path -LiteralPath $OwnerFile -PathType Leaf)) {
    Fail "missing owner skill: $OwnerFile"
}
if (-not (Test-Path -LiteralPath $BootstrapFile -PathType Leaf)) {
    Fail "missing bootstrap skill: $BootstrapFile"
}

$owner = [System.IO.File]::ReadAllText($OwnerFile)
$boot = [System.IO.File]::ReadAllText($BootstrapFile)
$radar = [System.IO.File]::ReadAllText($RadarFile)

if ($owner -notmatch 'STATUS\s*\.+:\s*DRAFT') { Fail 'owner skill STATUS is not DRAFT' }
if ($owner -notmatch 'SINGLE_OWNER=YES') { Fail 'owner skill missing SINGLE_OWNER=YES' }
if ($owner -notmatch 'DIRECTORY_ARCHITECTURE' -or $owner -notmatch 'ARTIFACT_ARCHITECTURE') {
    Fail 'owner skill missing DIRECTORY_ARCHITECTURE or ARTIFACT_ARCHITECTURE'
}
if ($owner -notmatch 'WHOAMI_ACTIVE_CANON=NO') { Fail 'owner skill WhoAmI disposition missing' }
if ($owner -notmatch 'ROLE_ID=HUMAN_AUTHORITY') { Fail 'owner skill missing HUMAN_AUTHORITY' }
if ($owner -match 'rename HUMAN to CONSTITUTION') { } else {
    if ($owner -notmatch 'Do not automatically rename HUMAN to CONSTITUTION') {
        Fail 'owner skill missing HUMAN/CONSTITUTION non-rename rule'
    }
}
if ($owner -notmatch 'CONSTITUTION' -or $owner -notmatch 'Subordinate') {
    Fail 'owner skill missing CONSTITUTION subordination'
}
if ($owner -notmatch 'THREE_ARTIFACT' -and $owner -notmatch 'three related') {
    Fail 'owner skill missing three-artifact rule'
}
if ($owner -notmatch 'PARENT_CONGESTION_THRESHOLD=12') { Fail 'owner missing PARENT_CONGESTION_THRESHOLD=12' }
if ($owner -notmatch '00_ACCESS' -or $owner -notmatch 'non-canonical') { Fail 'owner missing ACCESS layer' }
if ($owner -notmatch 'MUST NOT follow' -and $owner -notmatch 'FOLLOW reparse targets from 00_ACCESS: NO') {
    Fail 'owner missing reparse non-follow default'
}
if ($owner -notmatch 'SYS\.INPUT' -or $owner -notmatch 'SYSTEM_PRODUCT') { Fail 'owner missing SYS.INPUT profile gate' }
if ($owner -notmatch 'ORCHESTRATOR' -or $owner -notmatch '90_SESSIONS') { Fail 'owner missing session agent placement' }
if ($owner -notmatch '63_SKILLS' -or $owner -notmatch '81_PRODUCT_MODULES') { Fail 'owner missing skills/modules split' }
if ($owner -notmatch 'QUALITY' -or $owner -notmatch 'TESTS' -or $owner -notmatch 'SECURITY' -or $owner -notmatch 'EVIDENCE') {
    Fail 'owner missing quality/tests/security/evidence split'
}

# Skill 20 must not claim complete architecture ownership.
if ($boot -match 'OWNER_CONTRACT\s*\.+:\s*DIRECTORY_ARCHITECTURE') {
    Fail 'Skill 20 still claims OWNER_CONTRACT DIRECTORY_ARCHITECTURE'
}
if ($boot -notmatch 'SKILL\.PROJECT_INFORMATION_ARCHITECTURE\.txt') {
    Fail 'Skill 20 does not consume PIA owner'
}
if ($boot -match 'SINGLE_OWNER=YES') { Fail 'Skill 20 still declares SINGLE_OWNER=YES' }

# One owner file; no extra architecture skills by folder.
$extraOwners = @(Get-ChildItem -LiteralPath $SkillsDir -File | Where-Object {
        $_.Name -match 'DIRECTORY_ARCHITECTURE|FOLDER_ARCHITECTURE|PROJECT_INFORMATION_ARCHITECTURE' -and
        $_.Name -ne 'SKILL.PROJECT_INFORMATION_ARCHITECTURE.txt'
    })
if ($extraOwners.Count -gt 0) {
    Fail ("extra architecture skill files: " + (($extraOwners | ForEach-Object Name) -join ', '))
}

# Live RADAR pointer (historial may still mention Skill 20).
$radarHead = ($radar -split '16\.00_HISTORIAL_DE_CAMBIOS')[0]
if ($radarHead -notmatch 'SKILL\.PROJECT_INFORMATION_ARCHITECTURE\.txt') {
    Fail 'RADAR live body does not reference PIA owner'
}
if ($radarHead -match 'PENDIENTE:\s*ID/nombre de la SKILL de arquitectura') {
    Fail 'RADAR live body still has pending architecture dependency'
}
if ($radar -notmatch 'Agregada dependencia pendiente: skill de arquitectura') {
    Fail 'RADAR historical pending-dependency line was removed (must preserve history)'
}

# Live consumer pointers (not changelog-only).
$consumers = @(
    '06.SKILL.WBS.txt'
    '07.SKILL.FILE_CONTENT.txt'
    '10.SKILL.BATON.txt'
    '21.SKILL.OPERATIONAL_ARTIFACTS_POLICY.txt'
    '22.SKILL.PROJECT_LIFECYCLE_POLICY.txt'
    'SKILL.REPO.TEMP_ARTIFACT_MANAGEMENT.txt'
    'SKILL.MANIFEST.PATH_SEMANTICS.txt'
)
foreach ($c in $consumers) {
    $p = Join-Path $SkillsDir $c
    $t = [System.IO.File]::ReadAllText($p)
    if ($t -notmatch 'SKILL\.PROJECT_INFORMATION_ARCHITECTURE\.txt') {
        Fail "consumer missing PIA pointer: $c"
    }
}

# Declarative forward tests exist.
if ($owner -notmatch 'PARSERMAKERMACHINE' -or $owner -notmatch 'MIN_THEN_GROW') {
    Fail 'owner missing declarative forward-test scenarios'
}

Write-Host 'OK: project information architecture owner validation passed'
exit 0
