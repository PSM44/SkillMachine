#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..\..')).Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$failed = 0
function Assert-True($cond, $msg) {
    if (-not $cond) {
        Write-Host "FAIL: $msg"
        $script:failed++
    } else {
        Write-Host "PASS: $msg"
    }
}

$vsRoot = Join-Path $RepoRoot 'SyS\A_Tools\VerticalSlice\v0.1'
$runner = Join-Path $vsRoot 'Invoke-VerticalSlice.ps1'
$coreFiles = @(
    (Join-Path $vsRoot 'Core\Common.ps1'),
    (Join-Path $vsRoot 'Core\Status.ps1'),
    (Join-Path $vsRoot 'Core\Audit.ps1'),
    $runner
)

# Parser check on all modified scripts
foreach ($f in $coreFiles) {
    $tokens = $null; $errs = $null
    [System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$tokens, [ref]$errs) | Out-Null
    $errCount = 0
    if ($null -ne $errs) { $errCount = @($errs).Count }
    Assert-True ($errCount -eq 0) "PowerShell parser clean: $(Split-Path $f -Leaf)"
    # Variable-colon safety (exclude allowed scopes)
    $raw = Get-Content $f -Raw
    $risky = @(
        [regex]::Matches($raw, '\$[A-Za-z_][A-Za-z0-9_]*:') | Where-Object {
            $_.Value -notmatch '^\$env:$|^\$script:$|^\$global:$|^\$local:$|^\$private:$'
        }
    )
    Assert-True ($risky.Count -eq 0) "No unsafe variable-colon in $(Split-Path $f -Leaf)"
}

# Forbidden term in HUMAN patch
$human = Get-Content (Join-Path $RepoRoot 'HUMAN\HUMAN.OPERATING.MODEL.txt') -Raw
Assert-True ($human -match 'Improvement Flow') "HUMAN contains Improvement Flow"
Assert-True ($human -match 'Forbidden term:\s*"Learning Sync"|Forbidden term:\s*Learning Sync') "HUMAN forbids Learning Sync term"
Assert-True ($human -notmatch 'Learning Sync Status') "HUMAN does not use Learning Sync Status as indicator"
Assert-True ($human -match '00_SKILLSMACHINE') "HUMAN mentions 00_SKILLSMACHINE"
Assert-True ($human -match 'PROHIBITED') "HUMAN prohibits paid AI dependency language"
Assert-True ($human -match 'STATUS_VOCABULARY_V1') "HUMAN has status vocabulary"
Assert-True ($human -match 'BLOCKED\s*>\s*CRITICAL\s*>\s*ATTENTION\s*>\s*CURRENT') "HUMAN precedence order"

# Domain / contracts presence
Assert-True (Test-Path (Join-Path $vsRoot 'DOMAIN.MODEL.txt')) "DOMAIN.MODEL present"
Assert-True (Test-Path (Join-Path $vsRoot 'Contracts\CONTRACTS.V0.1.txt')) "CONTRACTS present"
$contracts = Get-Content (Join-Path $vsRoot 'Contracts\CONTRACTS.V0.1.txt') -Raw
Assert-True ($contracts -match 'MESSAGE_ID_UNIQUENESS') "Contracts declare message_id uniqueness"
Assert-True ($contracts -match 'PARTIAL_ACCEPTANCE') "Contracts declare partial acceptance"
Assert-True ($contracts -match 'DUPLICATE_SUBMISSION') "Contracts declare duplicate submission"
Assert-True ($contracts -match 'LAB_PUBLICATION') "Contracts distinguish LAB publication"

# Status matrix unit tests (pure)
. (Join-Path $vsRoot 'Core\Status.ps1')
. (Join-Path $vsRoot 'Core\Audit.ps1')

Assert-True ((Get-StatusRank 'BLOCKED') -gt (Get-StatusRank 'CRITICAL')) "Rank BLOCKED > CRITICAL"
Assert-True ((Get-StatusRank 'CRITICAL') -gt (Get-StatusRank 'ATTENTION')) "Rank CRITICAL > ATTENTION"
Assert-True ((Get-StatusRank 'ATTENTION') -gt (Get-StatusRank 'CURRENT')) "Rank ATTENTION > CURRENT"

$g1 = Get-SkillsMachineGlobalStatus -SkillsSync 'CURRENT' -ProjectSync 'CURRENT' -ImprovementFlow 'CURRENT' -SkillsProviders 'CURRENT' -AuditStatus 'CURRENT'
Assert-True ($g1 -eq 'CURRENT') "Matrix all CURRENT => CURRENT"

$g2 = Get-SkillsMachineGlobalStatus -SkillsSync 'CURRENT' -ProjectSync 'CURRENT' -ImprovementFlow 'CURRENT' -SkillsProviders 'ATTENTION' -AuditStatus 'CURRENT'
Assert-True ($g2 -eq 'ATTENTION') "Matrix providers ATTENTION => ATTENTION"

$g3 = Get-SkillsMachineGlobalStatus -SkillsSync 'CURRENT' -ProjectSync 'CURRENT' -ImprovementFlow 'CURRENT' -SkillsProviders 'ATTENTION' -AuditStatus 'CRITICAL'
Assert-True ($g3 -eq 'CRITICAL') "Matrix CRITICAL beats ATTENTION"

$g4 = Get-SkillsMachineGlobalStatus -SkillsSync 'CURRENT' -ProjectSync 'BLOCKED' -ImprovementFlow 'CRITICAL' -SkillsProviders 'ATTENTION' -AuditStatus 'CURRENT'
Assert-True ($g4 -eq 'BLOCKED') "Matrix BLOCKED beats CRITICAL"

$advOnly = Get-AuditStatusFromCounts -Critical 0 -Important 0 -Advisory 3
Assert-True ($advOnly -eq 'CURRENT') "Advisory-only audit => CURRENT (no ATTENTION)"

$impAudit = Get-AuditStatusFromCounts -Critical 0 -Important 1 -Advisory 5
Assert-True ($impAudit -eq 'ATTENTION') "IMPORTANT audit => ATTENTION"

$critAudit = Get-AuditStatusFromCounts -Critical 1 -Important 0 -Advisory 0
Assert-True ($critAudit -eq 'CRITICAL') "CRITICAL audit => CRITICAL"

Assert-True ((Get-SkillsProvidersStatus -ExternalCandidates 1) -eq 'ATTENTION') "External candidates => providers ATTENTION"
Assert-True ((Get-SkillsProvidersStatus -ExternalCandidates 0) -eq 'CURRENT') "No external candidates => CURRENT"
Assert-True ((Get-ProjectSyncStatus -InstalledVersion '1.1.0' -AvailableVersion '1.1.0') -eq 'CURRENT') "Synced project => CURRENT"
Assert-True ((Get-ProjectSyncStatus -InstalledVersion '1.0.0' -AvailableVersion '1.1.0') -eq 'ATTENTION') "Outdated project => ATTENTION"
Assert-True ((Get-ImprovementFlowStatus -MissingReceipt $true) -eq 'CRITICAL') "Missing receipt => CRITICAL IFLOW"
Assert-True ((Get-SkillsSyncStatus -CatalogVersion '1.1.0' -ActiveCapabilityVersion '1.1.0') -eq 'CURRENT') "Skills sync aligned => CURRENT"

# Home HTML sanity: no Start/Continue/Close AI Session; has required action labels
$homeHtml = Get-Content (Join-Path $vsRoot 'Home\index.html') -Raw
Assert-True ($homeHtml -notmatch 'Start AI Session|Continue AI Session|Close AI Session') "Home has no Start/Continue/Close AI Session"
Assert-True ($homeHtml -match 'Improvement Flow|IMPROVEMENT FLOW') "Home references Improvement Flow"
Assert-True ($homeHtml -match 'CRITICAL') "Home CSS knows CRITICAL"
Assert-True ($homeHtml -notmatch 'Learning Sync Status') "Home HTML no Learning Sync Status"
Assert-True ($homeHtml -match 'Needs Your Attention|needs_your_attention|nya') "Home has Needs Your Attention"
Assert-True ($homeHtml -match 'Projects|projects') "Home has Projects section"
Assert-True ($homeHtml -match 'Primary Actions|primary_actions') "Home has Primary Actions"

# Enrolment / AI / real-project contracts (MB-SM-076A2)
$contractFiles = @(
    'PROJECT_ENROLMENT.V0.1.txt',
    'AI_ACCESS.V0.1.txt',
    'IMPROVEMENT_FLOW_REAL_PROJECT.V0.1.txt',
    'PROJECT_SYNC.V0.1.txt',
    'DESIRED_OBSERVED_STATE.V0.1.txt',
    'AUTHORITY_MATRIX.V0.1.txt',
    'HUMAN_JOURNEYS.V0.1.txt',
    'CLOSEREPORT_PILOT_MAPPING.V0.1.txt'
)
foreach ($cf in $contractFiles) {
    Assert-True (Test-Path (Join-Path $vsRoot ("Contracts\$cf"))) "Contract present: $cf"
}
$enrol = Get-Content (Join-Path $vsRoot 'Contracts\PROJECT_ENROLMENT.V0.1.txt') -Raw
Assert-True ($enrol -match 'EXISTING_PROJECT_ENROLMENT') "Enrolment defines existing project flow"
Assert-True ($enrol -match 'not autonomous mutation|≠ autonomous') "Enrolment not autonomous mutation"
$aiAccess = Get-Content (Join-Path $vsRoot 'Contracts\AI_ACCESS.V0.1.txt') -Raw
Assert-True ($aiAccess -match 'PROTOCOL_NEUTRAL') "AI access protocol-neutral"
Assert-True ($aiAccess -match 'must not depend on MCP|MCP not core') "AI access not MCP-core"
Assert-True ($aiAccess -notmatch 'Learning Sync') "AI contract has no Learning Sync"
$psContract = Get-Content (Join-Path $vsRoot 'Contracts\PROJECT_SYNC.V0.1.txt') -Raw
Assert-True ($psContract -match 'EXPLICITLY_ENROLLED_IN_SKILLSMACHINE') "Project Sync uses enrolment eligibility"
$domain = Get-Content (Join-Path $vsRoot 'DOMAIN.MODEL.txt') -Raw
Assert-True ($domain -match 'ENROLMENT_STATUS') "DOMAIN has enrolment"
Assert-True ($domain -match 'ONE_SKILLSMACHINE_CORE') "DOMAIN has one core access model"

$registryPath = Join-Path $vsRoot 'Fixtures\projects\PROJECT.REGISTRY.v0.1.json'
Assert-True (Test-Path $registryPath) "Project registry fixture present"
$reg = Get-Content $registryPath -Raw | ConvertFrom-Json
Assert-True (@($reg.projects).Count -ge 2) "Registry has LAB + CloseReport rows"
$cr = @($reg.projects | Where-Object { $_.PROJECT_ID -eq 'CloseReport' })[0]
Assert-True ($null -ne $cr) "CloseReport registry row exists"
Assert-True ($cr.ENROLMENT_STATUS -eq 'NOT_ENROLLED') "CloseReport NOT_ENROLLED"
Assert-True ($cr.PROJECT_SYNC_STATUS -eq 'UNKNOWN') "CloseReport sync UNKNOWN (not fabricated CURRENT)"

# Eligibility unit checks
. (Join-Path $RepoRoot 'SyS\A_Tools\Update\Eligibility.ps1')
$eligCreated = Test-SkillsMachineProjectEligibility -Baseline ([pscustomobject]@{
    schema_version = '1.1'
    created_by_skillsmachine = $true
})
Assert-True ([bool]$eligCreated.Eligible) "1.1 created_by eligible"
$eligUnknown = Test-SkillsMachineProjectEligibility -Baseline ([pscustomobject]@{
    schema_version = '1.1'
    created_by_skillsmachine = $false
})
Assert-True (-not [bool]$eligUnknown.Eligible) "1.1 unknown blocked"
Assert-True ([string]$eligUnknown.Reason -eq 'BLOCKED_UNKNOWN_PROJECT') "1.1 unknown reason"
$eligEnrolled = Test-SkillsMachineProjectEligibility -Baseline ([pscustomobject]@{
    schema_version = '1.2'
    created_by_skillsmachine = $false
    explicitly_enrolled_in_skillsmachine = $true
    enrolment_status = 'ENROLLED'
})
Assert-True ([bool]$eligEnrolled.Eligible) "1.2 enrolled eligible"
$eligPending = Test-SkillsMachineProjectEligibility -Baseline ([pscustomobject]@{
    schema_version = '1.2'
    created_by_skillsmachine = $false
    explicitly_enrolled_in_skillsmachine = $false
    enrolment_status = 'NOT_ENROLLED'
})
Assert-True (-not [bool]$eligPending.Eligible) "1.2 not enrolled blocked"
Assert-True ([string]$eligPending.Reason -eq 'BLOCKED_PROJECT_NOT_ENROLLED') "1.2 not enrolled reason"

# HUMAN 076A2 enrolment doctrine
Assert-True ($human -match 'PROJECT_ENROLMENT|Enrolment = permission') "HUMAN has enrolment doctrine"
Assert-True ($human -match 'NEEDS_YOUR_ATTENTION|Needs Your Attention') "HUMAN mentions Needs Your Attention"
Assert-True ($human -match 'ONE_SKILLSMACHINE_CORE') "HUMAN one core model"

# Run vertical slice (clean LAB)
& $runner -RepoRoot $RepoRoot
Assert-True ($LASTEXITCODE -eq 0) "Vertical slice runner exit 0"

$evidence = Join-Path $RepoRoot '99.LABS\SM-LAB-004_SKILLS_IMPROVEMENT_VERTICAL_SLICE\evidence\VERTICAL_SLICE.RESULT.json'
Assert-True (Test-Path $evidence) "Evidence JSON exists"
$data = Get-Content $evidence -Raw | ConvertFrom-Json
Assert-True ($data.vertical_slice_status -eq 'PASS') "vertical_slice_status PASS"
Assert-True ($data.paid_ai_dependency -eq 'NO') "paid_ai_dependency NO"
Assert-True ($data.external_project_mutation -eq 'NO') "external_project_mutation NO"
Assert-True ($data.production_publication -eq 'NOT_TESTED') "production_publication NOT_TESTED"
Assert-True ($data.lab_publication -eq 'PASS') "lab_publication PASS"
Assert-True ($data.duplicate_submission_idempotent -eq 'PASS') "duplicate submission idempotent"
Assert-True ($data.receipt_vs_disposition_separated -eq 'PASS') "receipt vs disposition separated"
Assert-True ($null -ne $data.vertical_slice.LAB_PUBLICATION) "VS uses LAB_PUBLICATION key"
Assert-True (-not ($data.vertical_slice.PSObject.Properties.Name -contains 'PUBLICATION')) "VS does not use bare PUBLICATION key"

# Receipt before rotation evidence
$surface = Join-Path $RepoRoot '99.LABS\SM-LAB-004_SKILLS_IMPROVEMENT_VERTICAL_SLICE\00_SKILLSMACHINE'
Assert-True (Test-Path (Join-Path $surface 'RECEIPTS.log.txt')) "RECEIPTS.log exists"
Assert-True (Test-Path (Join-Path $surface 'ARCHIVE_INDEX.txt')) "ARCHIVE_INDEX exists after rotation"

# Home data real
$homeDataPath = Join-Path $vsRoot 'Home\home.data.json'
Assert-True (Test-Path $homeDataPath) "home.data.json exists"
$hd = Get-Content $homeDataPath -Raw | ConvertFrom-Json
Assert-True ($null -ne $hd.status.GLOBAL_STATUS) "Home GLOBAL_STATUS present"
Assert-True ($hd.status.GLOBAL_STATUS -eq 'ATTENTION') "Expected GLOBAL ATTENTION due to providers"
Assert-True ($hd.status.SKILLS_SYNC -eq 'CURRENT') "Skills Sync CURRENT"
Assert-True ($hd.status.PROJECT_SYNC -eq 'CURRENT') "Project Sync CURRENT"
Assert-True ($hd.status.IMPROVEMENT_FLOW_STATUS -eq 'CURRENT') "Improvement Flow CURRENT"
Assert-True ($hd.status.SKILLS_PROVIDERS -eq 'ATTENTION') "Providers ATTENTION"
Assert-True ($hd.status.AUDIT_STATUS -eq 'CURRENT') "Audit CURRENT (advisory-only after sync)"
Assert-True ($hd.paid_ai_dependency -eq 'NO') "Home paid_ai NO"
Assert-True ($hd.actions.Count -eq 10) "10 actions"
Assert-True ($hd.actions -contains 'Integrate New Skills from Experience') "Integrate New Skills from Experience present"
Assert-True ($hd.actions -contains 'Audit SkillsMachine') "Audit SkillsMachine present"
Assert-True ($hd.actions -contains 'Improvement Flow') "Improvement Flow action present"
Assert-True (@($hd.actions | Where-Object { $_ -match 'Start AI Session|Continue AI Session|Close AI Session' }).Count -eq 0) "No AI Session actions"
Assert-True ($null -ne $hd.needs_your_attention) "Home needs_your_attention present"
Assert-True (@($hd.needs_your_attention).Count -ge 1) "Home attention has items"
Assert-True ($null -ne $hd.projects) "Home projects present"
Assert-True (@($hd.projects | Where-Object { $_.PROJECT_ID -eq 'CloseReport' -and $_.ENROLMENT_STATUS -eq 'NOT_ENROLLED' }).Count -eq 1) "Home shows CloseReport NOT_ENROLLED"
Assert-True ($hd.primary_actions.Count -eq 5) "5 primary actions"
Assert-True ($hd.secondary_actions.Count -eq 5) "5 secondary actions"
Assert-True ($hd.access_model.core -eq 'ONE_SKILLSMACHINE_CORE') "Home access model core"
Assert-True ($null -ne $hd.registry_source) "Home registry_source present"
Assert-True ($hd.registry_source -in @('DURABLE_PROJECTOPS','FIXTURE_FALLBACK')) "Home registry_source known"

# Negative: no Learning Sync Status misuse in home
$homeRaw = Get-Content $homeDataPath -Raw
Assert-True ($homeRaw -notmatch 'Learning Sync Status') "Home has no Learning Sync Status"
Assert-True ($hd.indicators -notcontains 'LEARNING SYNC') "Indicators exclude LEARNING SYNC"

# Audit file severity classification present
$audit = Get-Content (Join-Path $RepoRoot '99.LABS\SM-LAB-004_SKILLS_IMPROVEMENT_VERTICAL_SLICE\evidence\AUDIT.RESULT.json') -Raw | ConvertFrom-Json
Assert-True ($audit.GLOBAL_AUDIT_STATUS -eq 'CURRENT') "Final audit CURRENT"
Assert-True ($audit.ADVISORY -ge 1) "Advisory findings present"
Assert-True ($audit.CRITICAL -eq 0) "No critical findings"
Assert-True ($audit.IMPORTANT -eq 0) "No important findings post-sync"

# DCA and core harness not containing SMDI_EXT
$harness = Get-Content (Join-Path $RepoRoot 'SyS\A_Tools\Update\Test-SkillsMachineUpdate.ps1') -Raw
Assert-True ($harness -notmatch 'SMDI_EXT') "Core harness free of SMDI_EXT"

# Repeatability: second run also PASS with clean LAB reset
& $runner -RepoRoot $RepoRoot
Assert-True ($LASTEXITCODE -eq 0) "Vertical slice run 2 exit 0"
$data2 = Get-Content $evidence -Raw | ConvertFrom-Json
Assert-True ($data2.vertical_slice_status -eq 'PASS') "vertical_slice run 2 PASS"
Assert-True ($data2.lab_publication -eq 'PASS') "lab_publication run 2 PASS"

if ($failed -gt 0) {
    Write-Host "TEST_SUMMARY=FAIL count=$failed"
    exit 1
}
Write-Host "TEST_SUMMARY=PASS"
exit 0
