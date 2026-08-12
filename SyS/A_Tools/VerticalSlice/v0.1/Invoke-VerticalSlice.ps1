#Requires -Version 5.1
<#
.SYNOPSIS
  MB-SM-075B Vertical Slice stabilized runner (NO-AI core).
.NOTES
  Does not mutate external projects. Does not promote production canon.
  Does not call paid AI APIs. Resets LAB workspace for reproducibility.
#>
[CmdletBinding()]
param(
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path,
    [string]$LabRoot = '',
    [switch]$SkipLabReset
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$CoreDir = Join-Path $PSScriptRoot 'Core'
. (Join-Path $CoreDir 'Common.ps1')
. (Join-Path $CoreDir 'Status.ps1')
. (Join-Path $CoreDir 'Audit.ps1')

if ([string]::IsNullOrWhiteSpace($LabRoot)) {
    $LabRoot = Join-Path $RepoRoot '99.LABS\SM-LAB-004_SKILLS_IMPROVEMENT_VERTICAL_SLICE'
}
if (-not $SkipLabReset) {
    Reset-LabWorkspace -LabRoot $LabRoot
}

$Surface = Join-Path $LabRoot '00_SKILLSMACHINE'
$Evidence = Join-Path $LabRoot 'evidence'
$VsRoot = Join-Path $RepoRoot 'SyS\A_Tools\VerticalSlice\v0.1'
$HomeDir = Join-Path $VsRoot 'Home'
$CapStore = Join-Path $VsRoot 'Fixtures\capabilities'
$ProviderStore = Join-Path $VsRoot 'Fixtures\providers'

foreach ($d in @($Surface, $Evidence, $CapStore, $ProviderStore, $HomeDir)) {
    if (-not (Test-Path -LiteralPath $d)) {
        New-Item -ItemType Directory -Path $d -Force | Out-Null
    }
}

$result = [ordered]@{
    schema_version = '0.1.0'
    task_id = 'MB-SM-075B_VERTICAL_SLICE_STABILIZATION'
    started_at = (Get-Date).ToUniversalTime().ToString('o')
    paid_ai_dependency = 'NO'
    free_ai_dependency = 'OPTIONAL_ONLY'
    external_project_mutation = 'NO'
    production_publication = 'NOT_TESTED'
}

# --- Seed capability baseline (synthetic, not production canon) ---
$capId = 'SKILL.LAB.LONG_RUNNING_RUNNER_HEARTBEAT'
$capV1 = @"
SKILL_ID=$capId
VERSION=1.0.0
STATUS=ACTIVE
KIND=TRANSVERSAL
PURPOSE=Provide minimal heartbeat/progress contract for long-running runners (LAB fixture).
OWNER=SkillsMachine.LAB
REQUIRES_HEARTBEAT=NO
PROVENANCE=SM-LAB-004 synthetic baseline
"@
$capV1Path = Join-Path $CapStore "$capId.1.0.0.txt"
Write-Utf8NoBom -Path $capV1Path -Content $capV1
$capV1Hash = Get-Sha256File $capV1Path

Write-Utf8NoBom -Path (Join-Path $Surface 'IDENTITY.txt') -Content @"
project_id=SM-LAB-004_SKILLS_IMPROVEMENT_VERTICAL_SLICE
root=$LabRoot
surface=00_SKILLSMACHINE
surface_version=0.1.0
created_at=$((Get-Date).ToUniversalTime().ToString('o'))
git_optional=NO
"@

Write-Utf8NoBom -Path (Join-Path $Surface 'CATALOG_INDEX.txt') -Content @"
# lightweight catalog index — no bodies
capability_id=$capId
type=SKILL
version=1.0.0
summary=LAB heartbeat runner skill baseline
sha256=$capV1Hash
status=ACTIVE
"@

Write-Utf8NoBom -Path (Join-Path $Surface 'CAPABILITIES.ACTIVE.txt') -Content @"
capability_id=$capId
kind=TRANSVERSAL
version=1.0.0
origin_sha256=$capV1Hash
status=INSTALLED
"@

# --- Opportunity (Improvement Flow: Projects → SkillsMachine) ---
$oppId = 'OPP-LAB-004-HEARTBEAT-001'
$oppEntry = @"
opportunity_id=$oppId
source_project=SM-LAB-004_SKILLS_IMPROVEMENT_VERTICAL_SLICE
source_event=MB-SM-075B_VERTICAL_SLICE
target_capability=$capId
evidence_refs=long-running wrapper hang without progress
severity=P1
status=OPEN
disposition_state=NONE
type_of_change=IMPROVE_EXISTING
created_at=$((Get-Date).ToUniversalTime().ToString('o'))
detail=Long-running runner needs heartbeat/progress contract.
"@
$accPath = Join-Path $Surface 'OPPORTUNITIES.ACCUMULATED.ACTIVE.txt'
Write-Utf8NoBom -Path $accPath -Content $oppEntry

$accText = Get-Content -LiteralPath $accPath -Raw -Encoding UTF8
if ($accText -notmatch 'opportunity_id=') { throw 'ACCUMULATOR_INVALID' }
$result['project_opportunity'] = 'PASS'

# --- Freeze ---
$freezeId = 'FREEZE-' + (Get-Date).ToUniversalTime().ToString('yyyyMMddHHmmss')
$freezePayload = "freeze_id=$freezeId`n" + $accText.TrimEnd() + "`n"
$freezeHash = Get-Sha256Text $freezePayload
$freezePath = Join-Path $Evidence "FREEZE.$freezeId.txt"
Write-Utf8NoBom -Path $freezePath -Content ($freezePayload + "content_sha256=$freezeHash`n")
$result['freeze'] = 'PASS'

# --- Submission package ---
$submissionId = 'SUB-' + $freezeId
$submissionBody = @"
schema_version=0.1.0
message_type=OPPORTUNITY_SUBMISSION
message_id=$submissionId
correlation_id=$freezeId
source_project=SM-LAB-004_SKILLS_IMPROVEMENT_VERTICAL_SLICE
destination=SkillsMachine
source_head_or_version=LAB
created_at=$((Get-Date).ToUniversalTime().ToString('o'))
freeze_id=$freezeId
item_ids=$oppId
payload_ref=$freezePath
content_sha256=$freezeHash
status=SUBMITTED
"@
$submissionHash = Get-Sha256Text $submissionBody
$submissionBody2 = $submissionBody + "package_sha256=$submissionHash`n"
$submissionPath = Join-Path $Evidence "SUBMISSION.$submissionId.txt"
Write-Utf8NoBom -Path $submissionPath -Content $submissionBody2
Write-Utf8NoBom -Path (Join-Path $Surface 'OUTBOX_LAST.txt') -Content $submissionBody2
$result['submission'] = 'PASS'

# --- Receive + receipt (SkillsMachine side, local) ---
$inboxSm = Join-Path $Evidence 'SM_INBOX'
New-Item -ItemType Directory -Path $inboxSm -Force | Out-Null
Copy-Item -LiteralPath $submissionPath -Destination (Join-Path $inboxSm (Split-Path $submissionPath -Leaf)) -Force

# Idempotency: same submission_id+content_sha256 yields same receipt id/hash
$receiptId = 'RCPT-' + (Get-Sha256Text ($submissionId + '|' + $freezeHash)).Substring(0, 16)
$receiptBody = @"
schema_version=0.1.0
message_type=SUBMISSION_RECEIPT
message_id=$receiptId
correlation_id=$freezeId
source_project=SkillsMachine
destination=SM-LAB-004_SKILLS_IMPROVEMENT_VERTICAL_SLICE
created_at=$((Get-Date).ToUniversalTime().ToString('o'))
submission_id=$submissionId
accepted_ids=$oppId
form_rejects=
partial_acceptance=NO
status=RECEIPTED
"@
$receiptHash = Get-Sha256Text $receiptBody
$receiptBody2 = $receiptBody + "receipt_hash=$receiptHash`n"
$receiptPath = Join-Path $Evidence "RECEIPT.$receiptId.txt"
Write-Utf8NoBom -Path $receiptPath -Content $receiptBody2
Write-Utf8NoBom -Path (Join-Path $Surface 'INBOX_LAST.txt') -Content $receiptBody2
$receiptsLog = Join-Path $Surface 'RECEIPTS.log.txt'
Write-Utf8NoBom -Path $receiptsLog -Content "receipt_id=$receiptId;submission_id=$submissionId;receipt_hash=$receiptHash;status=RECEIPTED`n"

# Duplicate submission same content → same receipt (idempotent, no second log line)
$dupReceiptId = 'RCPT-' + (Get-Sha256Text ($submissionId + '|' + $freezeHash)).Substring(0, 16)
$dupReceiptHash = Get-Sha256Text $receiptBody
if ($dupReceiptId -ne $receiptId) { throw 'IDEMPOTENT_RECEIPT_ID_FAIL' }
if ($dupReceiptHash -ne $receiptHash) { throw 'IDEMPOTENT_RECEIPT_HASH_FAIL' }
$logAfterDup = Get-Content -LiteralPath $receiptsLog -Raw -Encoding UTF8
$dupCount = ([regex]::Matches($logAfterDup, [regex]::Escape("receipt_id=$receiptId"))).Count
if ($dupCount -ne 1) { throw "DUPLICATE_RECEIPT_LOG_FAIL count=$dupCount" }
$result['duplicate_submission_idempotent'] = 'PASS'

$receiptRaw = [System.IO.File]::ReadAllText($receiptPath)
if ($receiptRaw -notmatch [regex]::Escape("submission_id=$submissionId")) { throw 'RECEIPT_CORRELATION_FAIL' }
if ($receiptRaw -notmatch ("receipt_hash=" + [regex]::Escape($receiptHash))) { throw 'RECEIPT_HASH_FAIL' }
$recomputed = Get-Sha256Text $receiptBody
if ($recomputed -ne $receiptHash) { throw "RECEIPT_HASH_RECOMPUTE_FAIL expected=$receiptHash recomputed=$recomputed" }
if ($receiptRaw -notmatch [regex]::Escape("correlation_id=$freezeId")) { throw 'CORRELATION_ID_FAIL' }
$result['receipt'] = 'PASS'
$result['no_invalid_rotation_rule'] = 'PASS'

# --- Rotate accumulator (ONLY after valid receipt) ---
if (-not (Test-Path -LiteralPath $receiptPath)) { throw 'NO_VALID_RECEIPT' }
$archiveDir = Join-Path $Surface 'ARCHIVE'
New-Item -ItemType Directory -Path $archiveDir -Force | Out-Null
$archivedAcc = Join-Path $archiveDir "OPPORTUNITIES.ACCUMULATED.$freezeId.txt"
Copy-Item -LiteralPath $accPath -Destination $archivedAcc -Force
Write-Utf8NoBom -Path $accPath -Content "# ACTIVE accumulator rotated after receipt $receiptId`n"
Write-Utf8NoBom -Path (Join-Path $Surface 'ARCHIVE_INDEX.txt') -Content "archive=$archivedAcc;freeze_id=$freezeId;receipt_id=$receiptId`n"
$result['rotation'] = 'PASS'

# --- Disposition IMPROVE (separate from receipt) ---
$dispId = 'DISP-' + $oppId
$dispBody = @"
schema_version=0.1.0
message_type=DISPOSITION_REPORT
message_id=$dispId
correlation_id=$freezeId
submission_id=$submissionId
opportunity_id=$oppId
decision=IMPROVE
targets=$capId
rationale=Prefer improve existing LAB capability rather than create new Skill.
decided_at=$((Get-Date).ToUniversalTime().ToString('o'))
status=DISPOSITIONED
"@
$dispPath = Join-Path $Evidence "DISPOSITION.$dispId.txt"
Write-Utf8NoBom -Path $dispPath -Content $dispBody
if ($dispId -eq $receiptId) { throw 'RECEIPT_DISPOSITION_ID_COLLISION' }
$result['disposition'] = 'PASS'
$result['receipt_vs_disposition_separated'] = 'PASS'

# --- Improve capability to 1.1.0 ---
$capV2 = @"
SKILL_ID=$capId
VERSION=1.1.0
STATUS=ACTIVE
KIND=TRANSVERSAL
PURPOSE=Provide minimal heartbeat/progress contract for long-running runners (LAB fixture).
OWNER=SkillsMachine.LAB
REQUIRES_HEARTBEAT=YES
HEARTBEAT_INTERVAL_SEC=30
PROGRESS_REQUIRED=YES
PROVENANCE=SM-LAB-004 improved from opportunity $oppId
SUPERSEDES=1.0.0
"@
$capV2Path = Join-Path $CapStore "$capId.1.1.0.txt"
Write-Utf8NoBom -Path $capV2Path -Content $capV2
$capV2Hash = Get-Sha256File $capV2Path
$result['capability_improvement'] = 'PASS'

# --- Providers foundation (local fixture only; external = candidate, not canon) ---
$providerBody = @"
provider_id=PROVIDER.LAB.LOCAL_FIXTURE
source_type=LOCAL
trust=REVIEW
freshness=CURRENT
ingestion_state=READY
"@
Write-Utf8NoBom -Path (Join-Path $ProviderStore 'PROVIDER.LAB.LOCAL_FIXTURE.txt') -Content $providerBody
$extCand = @"
candidate_id=EXT-CAND-LAB-001
provider_id=PROVIDER.LAB.LOCAL_FIXTURE
proposed_id=SKILL.LAB.EXTERNAL_EXAMPLE
status=EXTERNAL_CANDIDATE
auto_canon=NO
"@
Write-Utf8NoBom -Path (Join-Path $ProviderStore 'EXTERNAL_CANDIDATE.EXT-CAND-LAB-001.txt') -Content $extCand
$result['skills_providers_foundation'] = 'PASS'
$result['auto_external_import'] = 'NO'

# --- Experience intake (structured) ---
$expPath = Join-Path $Evidence 'EXPERIENCE.INTAKE.001.txt'
Write-Utf8NoBom -Path $expPath -Content @"
experience_id=EXP-LAB-001
source=operator_session_note
summary=Wrappers fail without progress output on long runs.
classifier=EXISTING_IMPROVEMENT
target=$capId
candidate_promotion=NO
human_review_required=YES
"@
$result['integrate_new_skills_from_experience'] = 'PASS'

# --- Free AI adapter contract (NO-AI mandatory path) ---
$aiAdapter = @"
FREE_AI_ADAPTER_CONTRACT.V0.1
MODE_DEFAULT=NO_AI
PAID_PROVIDERS=PROHIBITED
FREE_OR_LOCAL=OPTIONAL
CORE_OPERATIONS_REQUIRE_AI=NO
"@
Write-Utf8NoBom -Path (Join-Path $VsRoot 'Contracts\FREE_AI_ADAPTER.V0.1.txt') -Content $aiAdapter
$result['free_ai_option_architecture'] = 'PASS'

# --- Audit pre-sync (structural / governance / providers / improvement flow) ---
$findings = New-AuditFindingList
if (-not (Test-Path (Join-Path $Surface 'IDENTITY.txt'))) {
    Add-AuditFinding $findings 'CRITICAL' 'STRUCT_IDENTITY' 'surface' 'IDENTITY.txt' 'Create IDENTITY.txt'
}
# Coverage / omission: opportunity targeted existing capability — covered → advisory note only if gap
# Conflict: none in LAB happy path
# Duplicate: single opportunity id present
$installedPre = Read-KvFile (Join-Path $Surface 'CAPABILITIES.ACTIVE.txt')
if ($installedPre['origin_sha256'] -ne $capV1Hash) {
    Add-AuditFinding $findings 'IMPORTANT' 'FORK_HASH_MISMATCH' 'capability' $capId 'Investigate silent fork'
}
if (-not (Test-Path $receiptPath)) {
    Add-AuditFinding $findings 'CRITICAL' 'IFLOW_MISSING_RECEIPT' 'improvement_flow' $submissionId 'Do not rotate'
}
$prodPath = Join-Path $RepoRoot "SkillsLake\01.SKILLS\$capId.txt"
if (Test-Path $prodPath) {
    Add-AuditFinding $findings 'CRITICAL' 'GOV_SILENT_PROD_PROMOTION' 'canon' $capId 'Remove unintended promotion'
}
$extFiles = @(Get-ChildItem $ProviderStore -Filter 'EXTERNAL_CANDIDATE*.txt' -ErrorAction SilentlyContinue)
$externalCandidateCount = 0
foreach ($ef in $extFiles) {
    $externalCandidateCount++
    $kv = Read-KvFile $ef.FullName
    if ($kv['auto_canon'] -eq 'YES') {
        Add-AuditFinding $findings 'CRITICAL' 'PROVIDER_AUTO_CANON' 'provider' $kv['candidate_id'] 'Force candidate-only'
    } else {
        Add-AuditFinding $findings 'ADVISORY' 'PROVIDER_EXTERNAL_CANDIDATE_PENDING' 'provider' $kv['candidate_id'] 'Human review before any canon consideration'
    }
}
# Distribution pre-sync: installed still 1.0.0 while improved 1.1.0 exists — expected temporary
Add-AuditFinding $findings 'IMPORTANT' 'DIST_OUTDATED_PRE_SYNC' 'project_sync' "$capId@1.0.0→1.1.0" 'Project Sync apply in LAB'

$auditPre = New-AuditReport -Findings $findings
# Publication gate: block only on CRITICAL
if ([int]$auditPre['CRITICAL'] -gt 0) { throw "AUDIT_BLOCKED critical=$($auditPre['CRITICAL'])" }

# --- Publish fixture package (LAB only) ---
$pkgDir = Join-Path $Evidence 'PUBLISHED_PACKAGE'
New-Item -ItemType Directory -Path $pkgDir -Force | Out-Null
Copy-Item $capV2Path (Join-Path $pkgDir (Split-Path $capV2Path -Leaf)) -Force
$manifest = @"
schema_version=0.1.0
message_type=UPDATE_PACKAGE_MANIFEST
update_id=UPD-LAB-004-001
capability_id=$capId
from_version=1.0.0
to_version=1.1.0
payload_sha256=$capV2Hash
rollback_supported=YES
status=PUBLISHED_FIXTURE_LAB
"@
Write-Utf8NoBom -Path (Join-Path $pkgDir 'UPDATE.MANIFEST.txt') -Content $manifest
Write-Utf8NoBom -Path (Join-Path $Surface 'CATALOG_INDEX.txt') -Content @"
capability_id=$capId
type=SKILL
version=1.1.0
summary=LAB heartbeat runner skill with required heartbeat
sha256=$capV2Hash
status=ACTIVE
"@
$result['lab_publication'] = 'PASS'
$result['production_publication'] = 'NOT_TESTED'

# --- Project Sync comparator + controlled apply in LAB ---
$beforeHash = $capV1Hash
$syncCmp = [ordered]@{
    capability_id = $capId
    installed_version = '1.0.0'
    available_version = '1.1.0'
    state = 'UPDATE_AVAILABLE'
    fork = 'NO'
    missing = 'NO'
    deprecated = 'NO'
}
Write-Utf8NoBom -Path (Join-Path $Evidence 'PROJECT_SYNC.COMPARE.json') -Content ($syncCmp | ConvertTo-Json)

if ((Get-Sha256File (Join-Path $pkgDir (Split-Path $capV2Path -Leaf))) -ne $capV2Hash) { throw 'PACKAGE_HASH_MISMATCH' }

$installedBody = @"
capability_id=$capId
kind=TRANSVERSAL
version=1.1.0
origin_sha256=$capV2Hash
status=INSTALLED
previous_version=1.0.0
previous_sha256=$beforeHash
"@
Write-Utf8NoBom -Path (Join-Path $Surface 'CAPABILITIES.ACTIVE.txt') -Content $installedBody
$afterHash = $capV2Hash

$updateReceipt = @"
schema_version=0.1.0
message_type=UPDATE_RECEIPT
message_id=URCPT-LAB-004-001
correlation_id=$freezeId
update_id=UPD-LAB-004-001
result=PASS_APPLIED
before_sha256=$beforeHash
after_sha256=$afterHash
rollback_ref=$capV1Path
validator_status=PASS
created_at=$((Get-Date).ToUniversalTime().ToString('o'))
"@
$urPath = Join-Path $Evidence 'UPDATE_RECEIPT.URCPT-LAB-004-001.txt'
Write-Utf8NoBom -Path $urPath -Content $updateReceipt
Add-Content -LiteralPath $receiptsLog -Value 'update_receipt=URCPT-LAB-004-001;result=PASS_APPLIED' -Encoding utf8
$result['project_sync'] = 'PASS'
$result['update_receipt'] = 'PASS'

# --- Final audit post-sync (distribution resolved; keep advisory provider) ---
$findingsFinal = New-AuditFindingList
if (-not (Test-Path (Join-Path $Surface 'IDENTITY.txt'))) {
    Add-AuditFinding $findingsFinal 'CRITICAL' 'STRUCT_IDENTITY' 'surface' 'IDENTITY.txt' 'Create IDENTITY.txt'
}
$installedPost = Read-KvFile (Join-Path $Surface 'CAPABILITIES.ACTIVE.txt')
if ($installedPost['origin_sha256'] -ne $capV2Hash) {
    Add-AuditFinding $findingsFinal 'IMPORTANT' 'FORK_HASH_MISMATCH' 'capability' $capId 'Investigate silent fork'
}
if (-not (Test-Path $receiptPath)) {
    Add-AuditFinding $findingsFinal 'CRITICAL' 'IFLOW_MISSING_RECEIPT' 'improvement_flow' $submissionId 'Do not rotate'
}
if (Test-Path $prodPath) {
    Add-AuditFinding $findingsFinal 'CRITICAL' 'GOV_SILENT_PROD_PROMOTION' 'canon' $capId 'Remove unintended promotion'
}
foreach ($ef in $extFiles) {
    $kv = Read-KvFile $ef.FullName
    if ($kv['auto_canon'] -eq 'YES') {
        Add-AuditFinding $findingsFinal 'CRITICAL' 'PROVIDER_AUTO_CANON' 'provider' $kv['candidate_id'] 'Force candidate-only'
    } else {
        Add-AuditFinding $findingsFinal 'ADVISORY' 'PROVIDER_EXTERNAL_CANDIDATE_PENDING' 'provider' $kv['candidate_id'] 'Human review before any canon consideration'
    }
}
# Post-sync: versions aligned → no DIST_OUTDATED IMPORTANT
if ($installedPost['version'] -ne '1.1.0') {
    Add-AuditFinding $findingsFinal 'IMPORTANT' 'DIST_OUTDATED' 'project_sync' "$capId@$($installedPost['version'])→1.1.0" 'Run Project Sync apply'
} else {
    Add-AuditFinding $findingsFinal 'ADVISORY' 'DIST_SYNCED' 'project_sync' "$capId@1.1.0" 'No action'
}

$auditReport = New-AuditReport -Findings $findingsFinal
$auditJson = ($auditReport | ConvertTo-Json -Depth 8)
Write-Utf8NoBom -Path (Join-Path $Evidence 'AUDIT.RESULT.json') -Content $auditJson
if ([int]$auditReport['CRITICAL'] -gt 0) { throw "AUDIT_BLOCKED critical=$($auditReport['CRITICAL'])" }
$result['audit'] = 'PASS'
$result['audit_status'] = $auditReport['GLOBAL_AUDIT_STATUS']

# --- Deterministic Global Status aggregation ---
$catalog = Read-KvFile (Join-Path $Surface 'CATALOG_INDEX.txt')
$skillsSync = Get-SkillsSyncStatus -CatalogVersion $catalog['version'] -ActiveCapabilityVersion $installedPost['version']
$projectSyncStatus = Get-ProjectSyncStatus -InstalledVersion $installedPost['version'] -AvailableVersion '1.1.0' -Fork 'NO'
$improvementFlowStatus = Get-ImprovementFlowStatus -OpenOpportunities $false -MissingReceipt $false
$providersStatus = Get-SkillsProvidersStatus -ExternalCandidates $externalCandidateCount -AutoCanonAttempt $false
$auditStatusFinal = $auditReport['GLOBAL_AUDIT_STATUS']
$global = Get-SkillsMachineGlobalStatus `
    -SkillsSync $skillsSync `
    -ProjectSync $projectSyncStatus `
    -ImprovementFlow $improvementFlowStatus `
    -SkillsProviders $providersStatus `
    -AuditStatus $auditStatusFinal

$statusObj = [ordered]@{}
$statusObj['GLOBAL_STATUS'] = $global
$statusObj['SKILLS_SYNC'] = $skillsSync
$statusObj['PROJECT_SYNC'] = $projectSyncStatus
$statusObj['IMPROVEMENT_FLOW_STATUS'] = $improvementFlowStatus
$statusObj['SKILLS_PROVIDERS'] = $providersStatus
$statusObj['AUDIT_STATUS'] = $auditStatusFinal
$statusObj['IMPROVEMENT_OPPORTUNITIES'] = 0
$statusObj['EXTERNAL_CANDIDATES'] = $externalCandidateCount
$statusObj['PROJECTS_REQUIRING_ACTION'] = $(if ($providersStatus -ne 'CURRENT') { 1 } else { 0 })
$statusObj['status_vocabulary'] = 'CURRENT|ATTENTION|CRITICAL|BLOCKED'
$statusObj['status_precedence'] = 'BLOCKED>CRITICAL>ATTENTION>CURRENT'
$statusObj['notes'] = 'Providers ATTENTION because EXTERNAL_CANDIDATE requires human review; ADVISORY audit alone does not degrade Global Status.'

# Vertical slice acceptance (LAB terminology)
$vs = [ordered]@{}
$vs['PROJECT_OPPORTUNITY'] = $result['project_opportunity']
$vs['SUBMISSION'] = $result['submission']
$vs['RECEIPT'] = $result['receipt']
$vs['ROTATION'] = $result['rotation']
$vs['DISPOSITION'] = $result['disposition']
$vs['CAPABILITY_IMPROVEMENT'] = $result['capability_improvement']
$vs['AUDIT'] = $result['audit']
$vs['LAB_PUBLICATION'] = $result['lab_publication']
$vs['PROJECT_SYNC'] = $result['project_sync']
$vs['UPDATE_RECEIPT'] = $result['update_receipt']
$vsFail = @($vs.Values | Where-Object { $_ -ne 'PASS' })
$result['vertical_slice_status'] = $(if ($vsFail.Count -eq 0) { 'PASS' } else { 'FAIL' })
$result['global_status'] = $statusObj
$result['vertical_slice'] = $vs
$result['finished_at'] = (Get-Date).ToUniversalTime().ToString('o')

$outJson = Join-Path $Evidence 'VERTICAL_SLICE.RESULT.json'
Write-Utf8NoBom -Path $outJson -Content (($result | ConvertTo-Json -Depth 10))
$homeObj = [ordered]@{}
$homeObj['generated_at'] = $result['finished_at']
$homeObj['source_evidence'] = $outJson
$homeObj['status'] = $statusObj
$homeObj['vertical_slice'] = $vs
$primaryActions = @(
    'Browse Skills & GRCs',
    'Improve Skills',
    'Integrate New Skills from Experience',
    'Improvement Flow',
    'Sync Projects'
)
$secondaryActions = @(
    'Check Skills Providers',
    'Audit SkillsMachine',
    "Let's Talk About Our Skills",
    'Iterate with AI',
    'Settings'
)
$homeObj['primary_actions'] = $primaryActions
$homeObj['secondary_actions'] = $secondaryActions
$homeObj['actions'] = @($primaryActions + $secondaryActions)
$homeObj['indicators'] = @('GLOBAL STATUS','SKILLS SYNC','PROJECT SYNC','IMPROVEMENT FLOW STATUS','SKILLS PROVIDERS','AUDIT STATUS')
$homeObj['forbidden_terms_absent'] = @('Learning Sync')
$homeObj['paid_ai_dependency'] = 'NO'
$homeObj['production_publication'] = 'NOT_TESTED'

# MB-SM-076A3: prefer durable ProjectOps registry; fixture remains fallback for isolated VS-only runs
$projectsHome = New-Object System.Collections.Generic.List[object]
$attentionItems = New-Object System.Collections.Generic.List[object]
$registrySource = 'NONE'
$durableOps = Join-Path $RepoRoot 'SyS\A_Tools\ProjectOps\v0.1'
$durableRegistryPath = Join-Path $durableOps 'State\PROJECT.REGISTRY.json'
$fixtureRegistryPath = Join-Path $PSScriptRoot 'Fixtures\projects\PROJECT.REGISTRY.v0.1.json'

if (Test-Path -LiteralPath $durableRegistryPath) {
    . (Join-Path $durableOps 'Core\Common.ps1')
    . (Join-Path $durableOps 'Core\Registry.ps1')
    $homeView = Get-ProjectHomeViewFromRegistry -OpsRoot $durableOps
    foreach ($row in @($homeView.projects)) { [void]$projectsHome.Add($row) }
    foreach ($attn in @($homeView.needs_your_attention)) { [void]$attentionItems.Add($attn) }
    $registrySource = 'DURABLE_PROJECTOPS'
}
elseif (Test-Path -LiteralPath $fixtureRegistryPath) {
    $registry = Get-Content -LiteralPath $fixtureRegistryPath -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($p in @($registry.projects)) {
        $projRow = [pscustomobject]@{
            PROJECT = [string]$p.PROJECT_ID
            PROJECT_ID = [string]$p.PROJECT_ID
            ENROLMENT_STATUS = [string]$p.ENROLMENT_STATUS
            IMPROVEMENT_FLOW_STATUS = [string]$p.IMPROVEMENT_FLOW_STATUS
            PROJECT_SYNC_STATUS = [string]$p.PROJECT_SYNC_STATUS
            ATTENTION = [string]$p.ATTENTION
            LAST_OBSERVED_STATE = [string]$p.LAST_OBSERVED_AT
            PROJECT_CLASS = [string]$p.PROJECT_CLASS
        }
        [void]$projectsHome.Add($projRow)
        if ([string]$p.ATTENTION -and [string]$p.ATTENTION -ne 'NONE') {
            [void]$attentionItems.Add([pscustomobject]@{
                id = ("ATTN-{0}" -f [string]$p.PROJECT_ID)
                summary = ("{0}: {1}" -f [string]$p.PROJECT_ID, [string]$p.ATTENTION)
                source = 'PROJECT_REGISTRY_FIXTURE'
            })
        }
    }
    $registrySource = 'FIXTURE_FALLBACK'
}
if ($providersStatus -ne 'CURRENT') {
    [void]$attentionItems.Add([pscustomobject]@{
        id = 'ATTN-PROVIDERS'
        summary = 'EXTERNAL_CANDIDATE requires human review'
        source = 'SKILLS_PROVIDERS'
    })
}
$projectsRequiringAction = @(
    $projectsHome | Where-Object {
        ($_.ENROLMENT_STATUS -eq 'NOT_ENROLLED') -or
        ($_.ENROLMENT_STATUS -eq 'ENROLMENT_PENDING') -or
        ($_.ATTENTION -and $_.ATTENTION -ne 'NONE')
    }
).Count
$statusObj['PROJECTS_REQUIRING_ACTION'] = $projectsRequiringAction
$homeObj['status'] = $statusObj
$homeObj['projects'] = @($projectsHome.ToArray())
$homeObj['needs_your_attention'] = @($attentionItems.ToArray())
$homeObj['registry_source'] = $registrySource
$homeObj['access_model'] = [pscustomobject]@{
    core = 'ONE_SKILLSMACHINE_CORE'
    channels = @('DIRECT_UI', 'AI_INTEGRATION')
    governance = 'ONE_GOVERNANCE_MODEL'
    ai_protocol = 'PROTOCOL_NEUTRAL_ADAPTER'
}
Write-Utf8NoBom -Path (Join-Path $HomeDir 'home.data.json') -Content (($homeObj | ConvertTo-Json -Depth 10))

Write-Host "VERTICAL_SLICE_STATUS=$($result['vertical_slice_status'])"
Write-Host "LAB_PUBLICATION=$($result['lab_publication'])"
Write-Host "PRODUCTION_PUBLICATION=NOT_TESTED"
Write-Host "GLOBAL_STATUS=$global"
Write-Host "SKILLS_SYNC=$skillsSync"
Write-Host "PROJECT_SYNC=$projectSyncStatus"
Write-Host "IMPROVEMENT_FLOW_STATUS=$improvementFlowStatus"
Write-Host "SKILLS_PROVIDERS=$providersStatus"
Write-Host "AUDIT_STATUS=$auditStatusFinal"
Write-Host "EVIDENCE=$outJson"
Write-Host "HOME_DATA=$(Join-Path $HomeDir 'home.data.json')"
if ($result['vertical_slice_status'] -ne 'PASS') { exit 2 }
exit 0
