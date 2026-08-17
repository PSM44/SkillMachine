#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..\..')).Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$failed = 0
function Assert-True($cond, $msg) {
    if (-not $cond) { Write-Host "FAIL: $msg"; $script:failed++ } else { Write-Host "PASS: $msg" }
}

$ops = Join-Path $RepoRoot 'SyS\A_Tools\ProjectOps\v0.1'
$runner = Join-Path $ops 'Invoke-ProjectOps.ps1'
$core = @(
    'Common.ps1', 'Registry.ps1', 'Enrolment.ps1', 'ImprovementFlow.ps1',
    'Publication.ps1', 'ProjectSyncPrep.ps1', 'AiAccess.ps1'
) | ForEach-Object { Join-Path $ops "Core\$_" }

foreach ($f in @($core + $runner)) {
    $tokens = $null; $errs = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$tokens, [ref]$errs)
    $errCount = 0
    if ($null -ne $errs) { $errCount = @($errs).Count }
    Assert-True ($errCount -eq 0) "Parser clean: $(Split-Path $f -Leaf)"
    $raw = Get-Content $f -Raw
    $risky = @([regex]::Matches($raw, '\$[A-Za-z_][A-Za-z0-9_]*:') | Where-Object {
            $_.Value -notmatch '^\$env:$|^\$script:$|^\$global:$|^\$local:$|^\$private:$'
        })
    Assert-True ($risky.Count -eq 0) "No unsafe variable-colon: $(Split-Path $f -Leaf)"
}

$testOps = Join-Path $env:TEMP ("ProjectOpsTest.{0}" -f ([guid]::NewGuid().ToString('N')))
New-Item -ItemType Directory -Path $testOps -Force | Out-Null
try {
    # Point modules at test ops by copying core structure
    Copy-Item -Path (Join-Path $ops 'Core') -Destination (Join-Path $testOps 'Core') -Recurse
    Copy-Item -Path $runner -Destination (Join-Path $testOps 'Invoke-ProjectOps.ps1')
    New-Item -ItemType Directory -Path (Join-Path $testOps 'State') -Force | Out-Null

    . (Join-Path $testOps 'Core\Common.ps1')
    # Override Get-ProjectOpsRoot for test isolation
    function Get-ProjectOpsRoot { return $testOps }
    . (Join-Path $testOps 'Core\Registry.ps1')
    . (Join-Path $testOps 'Core\Enrolment.ps1')
    . (Join-Path $testOps 'Core\ImprovementFlow.ps1')
    . (Join-Path $testOps 'Core\Publication.ps1')
    . (Join-Path $testOps 'Core\ProjectSyncPrep.ps1')
    . (Join-Path $testOps 'Core\AiAccess.ps1')

    $reg = New-EmptyProjectRegistry
    $lab = [pscustomobject]@{
        PROJECT_ID = 'SM-LAB-004'
        PROJECT_ROOT_IDENTITY = 'LAB'
        PROJECT_TYPE = 'LAB'
        PROJECT_CLASS = 'ENROLLED_PROJECT'
        ENROLMENT_STATUS = 'ENROLLED'
        ENROLMENT_METHOD = 'NEW_PROJECT'
        ENROLLED_AT = '2026-08-07T00:00:00Z'
        CAPABILITY_BASELINE = 'LAB'
        IMPROVEMENT_FLOW_ENABLED = $true
        PROJECT_SYNC_ENABLED = $true
        LAST_OBSERVED_AT = 'TEST'
        LAST_SYNC_ID = $null
        LAST_RECEIPT_ID = $null
        AUTHORITY_MODEL = 'SKILLSMACHINE_PACKAGE_EXCHANGE_ONLY'
        IMPROVEMENT_FLOW_STATUS = 'NONE'
        PROJECT_SYNC_STATUS = 'CURRENT'
        ATTENTION = 'NONE'
        CREATED_BY_SKILLSMACHINE = $true
        EXPLICITLY_ENROLLED_IN_SKILLSMACHINE = $true
        RECEIVING_BOUNDARY_00_SKILLSMACHINE = 'PRESENT_LAB'
    }
    $cr = [pscustomobject]@{
        PROJECT_ID = 'CloseReport'
        PROJECT_ROOT_IDENTITY = 'C:\01. GitHub\CloseReport'
        PROJECT_TYPE = 'PRODUCT'
        PROJECT_CLASS = 'EXISTING_UNINTEGRATED_PROJECT'
        ENROLMENT_STATUS = 'NOT_ENROLLED'
        ENROLMENT_METHOD = $null
        ENROLLED_AT = $null
        CAPABILITY_BASELINE = 'UNKNOWN'
        IMPROVEMENT_FLOW_ENABLED = $false
        PROJECT_SYNC_ENABLED = $false
        LAST_OBSERVED_AT = 'TEST'
        LAST_SYNC_ID = $null
        LAST_RECEIPT_ID = $null
        AUTHORITY_MODEL = 'PROJECT_LOCAL_MUTATION_REQUIRED'
        IMPROVEMENT_FLOW_STATUS = 'NONE'
        PROJECT_SYNC_STATUS = 'UNKNOWN'
        ATTENTION = 'ENROLMENT_REQUIRED'
        CREATED_BY_SKILLSMACHINE = $false
        EXPLICITLY_ENROLLED_IN_SKILLSMACHINE = $false
        RECEIVING_BOUNDARY_00_SKILLSMACHINE = 'ABSENT'
    }
    $reg.projects = @($lab, $cr)
    [void](Save-ProjectRegistry -Registry $reg -OpsRoot $testOps)
    Assert-True (Test-Path (Get-ProjectRegistryPath -OpsRoot $testOps)) 'Durable registry saved'

    $fakeCurrent = $false
    try {
        $bad = Read-ProjectRegistry -OpsRoot $testOps
        $bad.projects[1].PROJECT_SYNC_STATUS = 'CURRENT'
        [void](Save-ProjectRegistry -Registry $bad -OpsRoot $testOps)
    } catch {
        $fakeCurrent = ($_.Exception.Message -match 'FAKE_CURRENT')
        # restore
        $reg.projects = @($lab, $cr)
        [void](Save-ProjectRegistry -Registry $reg -OpsRoot $testOps)
    }
    Assert-True $fakeCurrent 'Registry rejects fake CURRENT for NOT_ENROLLED'

    $prop = New-ExistingProjectEnrolmentProposal `
        -ProjectId 'CloseReport' `
        -ProjectRootIdentity 'C:\01. GitHub\CloseReport' `
        -ObservedHead ('a' * 40) `
        -Discovery @{ dirty_worktree_count = 1487; receiving_boundary_present = $false; local_skills_surface = '07.SKILLS'; fork_or_gap_summary = 'gap' } `
        -OpsRoot $testOps `
        -ReadyForReview
    Assert-True ($prop.proposal.PROPOSAL_STATUS -eq 'READY_FOR_REVIEW') 'Proposal READY_FOR_REVIEW'
    Assert-True ($prop.registry_enrolment_status -eq 'NOT_ENROLLED') 'Proposal does not enrol'
    Assert-True (-not [bool]$prop.auto_enrolled) 'No auto enrol'
    Assert-True ($prop.proposal.HUMAN_APPROVAL -eq 'REQUIRED_NOT_GRANTED') 'Human approval not granted'
    $crAfter = Get-ProjectRegistryEntry -ProjectId 'CloseReport' -OpsRoot $testOps
    Assert-True ($crAfter.ENROLMENT_STATUS -eq 'NOT_ENROLLED') 'CR remains NOT_ENROLLED'
    Assert-True ($crAfter.PROPOSAL_STATUS -eq 'READY_FOR_REVIEW') 'CR proposal status on registry'

    # IF reject not enrolled
    $rej = New-ImprovementFlowSubmissionPackage `
        -SourceProject 'CloseReport' `
        -OpportunityId 'OPP-X' `
        -EvidenceRefs @('e1') `
        -TargetSkillGrc 'SKILL.X' `
        -OpsRoot $testOps
    Assert-True (-not [bool]$rej.ok) 'IF rejects not enrolled'
    Assert-True ($rej.FAILURE_STATE -eq 'SOURCE_NOT_ENROLLED') 'IF failure SOURCE_NOT_ENROLLED'

    # IF accept enrolled + receipt + idempotency
    $sub1 = New-ImprovementFlowSubmissionPackage `
        -SourceProject 'SM-LAB-004' `
        -OpportunityId 'OPP-TEST-001' `
        -EvidenceRefs @('evidence/a.txt') `
        -TargetSkillGrc 'SKILL.LAB.LONG_RUNNING_RUNNER_HEARTBEAT' `
        -PayloadText 'hello' `
        -OpsRoot $testOps
    Assert-True ([bool]$sub1.ok) 'IF submit enrolled ok'
    Assert-True ($null -ne $sub1.receipt) 'Receipt created'
    Assert-True ($sub1.STATUS -eq 'RECEIVED') 'Status RECEIVED'
    $sub2 = New-ImprovementFlowSubmissionPackage `
        -SourceProject 'SM-LAB-004' `
        -OpportunityId 'OPP-TEST-001' `
        -EvidenceRefs @('evidence/a.txt') `
        -TargetSkillGrc 'SKILL.LAB.LONG_RUNNING_RUNNER_HEARTBEAT' `
        -PayloadText 'hello' `
        -OpsRoot $testOps
    Assert-True ([bool]$sub2.idempotent) 'IF idempotent duplicate'

    $rotFail = $false
    try { [void](Invoke-AccumulatorRotation -ReceiptId ' ' -OpsRoot $testOps) } catch { $rotFail = ($_.Exception.Message -match 'NO_ROTATION_WITHOUT_VALID_RECEIPT') }
    if (-not $rotFail) {
        try { [void](Invoke-AccumulatorRotation -ReceiptId 'RCPT-DOES-NOT-EXIST' -OpsRoot $testOps) } catch { $rotFail = ($_.Exception.Message -match 'NO_ROTATION_WITHOUT_VALID_RECEIPT') }
    }
    Assert-True $rotFail 'No rotation without receipt'

    $rot = Invoke-AccumulatorRotation -ReceiptId ([string]$sub1.receipt.RECEIPT_ID) -OpsRoot $testOps
    Assert-True (Test-Path $rot.archived) 'Accumulator archived'
    Assert-True (@((Read-ActiveAccumulator -OpsRoot $testOps).opportunities).Count -eq 0) 'Active accumulator empty after rotation'

    # re-submit for disposition tests
    $sub3 = New-ImprovementFlowSubmissionPackage `
        -SourceProject 'SM-LAB-004' `
        -OpportunityId 'OPP-TEST-002' `
        -EvidenceRefs @('evidence/b.txt') `
        -TargetSkillGrc 'SKILL.LAB.LONG_RUNNING_RUNNER_HEARTBEAT' `
        -PayloadText 'world' `
        -OpsRoot $testOps
    $dispSilent = New-ImprovementFlowDisposition `
        -OpportunityId 'OPP-TEST-002' `
        -SubmissionId ([string]$sub3.submission.SUBMISSION_ID) `
        -Decision 'IMPROVE_EXISTING' `
        -OpsRoot $testOps
    Assert-True ($dispSilent.DECISION -eq 'NEEDS_HUMAN_DECISION') 'Silent improve becomes NEEDS_HUMAN_DECISION'
    Assert-True ([bool]$dispSilent.HUMAN_CONFIRMED -eq $false) 'Silent path is not human-confirmed'
    $dispOk = New-ImprovementFlowDisposition `
        -OpportunityId 'OPP-TEST-002' `
        -SubmissionId ([string]$sub3.submission.SUBMISSION_ID) `
        -Decision 'IMPROVE_EXISTING' `
        -HumanConfirmed `
        -RecommendedBy 'HUMAN' `
        -TargetSkillGrc 'SKILL.LAB.LONG_RUNNING_RUNNER_HEARTBEAT' `
        -SupersedesDispositionId ([string]$dispSilent.DISPOSITION_ID) `
        -Rationale 'human ok' `
        -OpsRoot $testOps
    Assert-True ($dispOk.DECISION -eq 'IMPROVE_EXISTING') 'Human confirmed improve allowed'
    Assert-True ([bool]$dispOk.HUMAN_CONFIRMED) 'Confirmed flag true'
    Assert-True ([string]$dispOk.TARGET_SKILL_GRC -eq 'SKILL.LAB.LONG_RUNNING_RUNNER_HEARTBEAT') 'Target skill recorded'
    Assert-True ([string]$dispOk.SUPERSEDES_DISPOSITION_ID -eq [string]$dispSilent.DISPOSITION_ID) 'Confirmed disposition supersedes prior decision'
    Assert-True ([string]$dispOk.DISPOSITION_ID -ne [string]$dispSilent.DISPOSITION_ID) 'New disposition id does not overwrite prior'
    $priorPath = Join-Path (Get-IfDispositionsDir -OpsRoot $testOps) ("{0}.json" -f [string]$dispSilent.DISPOSITION_ID)
    $newPath = Join-Path (Get-IfDispositionsDir -OpsRoot $testOps) ("{0}.json" -f [string]$dispOk.DISPOSITION_ID)
    Assert-True (Test-Path -LiteralPath $priorPath) 'Prior NEEDS_HUMAN_DECISION file retained'
    Assert-True (Test-Path -LiteralPath $newPath) 'Confirmed disposition file written'
    $priorReload = Read-ProjectOpsJson -Path $priorPath
    Assert-True ([string]$priorReload.DECISION -eq 'NEEDS_HUMAN_DECISION') 'Prior decision remains auditable'

    $pub = New-ProductionPublicationPackage `
        -CapabilityId 'SKILL.REPO.TEMP_ARTIFACT_MANAGEMENT' `
        -Version '1.0.1' `
        -SourceDispositionId ([string]$dispOk.DISPOSITION_ID) `
        -PackageBody 'body' `
        -OpsRoot $testOps
    Assert-True ($pub.PUBLICATION_STATUS -eq 'PREPARED') 'Publication PREPARED'
    Assert-True ($pub.manifest.PRODUCTION_PUBLICATION -eq 'PREPARED_NOT_DELIVERED') 'Not delivered externally'
    $lcPath = Get-PublicationLifecyclePath -PackageId ([string]$pub.manifest.PACKAGE_ID) -OpsRoot $testOps
    Assert-True (Test-Path -LiteralPath $lcPath) 'T01 publication creates lifecycle sidecar'
    $lc0 = Get-PublicationLifecycle -PackageId ([string]$pub.manifest.PACKAGE_ID) -OpsRoot $testOps
    Assert-True ([string]$lc0.LIFECYCLE_STATUS -eq 'PREPARED') 'T02 initial sidecar status PREPARED'
    Assert-True ([string]$lc0.PACKAGE_ID -eq [string]$pub.manifest.PACKAGE_ID) 'Sidecar package identity matches'
    Assert-True ([bool]$lc0.HISTORICAL_MANIFEST_UNCHANGED) 'Sidecar records historical manifest unchanged'
    Assert-True (Test-HistoricalPublicationManifestUnchanged -PackageId ([string]$pub.manifest.PACKAGE_ID) -OpsRoot $testOps) 'T03 PACKAGE.MANIFEST historical status unchanged after publication'

    $syncCr = New-ProjectSyncDeliveryPreparation -TargetProject 'CloseReport' -PackageId ([string]$pub.manifest.PACKAGE_ID) -OpsRoot $testOps
    Assert-True (-not [bool]$syncCr.ok) 'Project Sync blocked for not enrolled CR'
    $syncLab = New-ProjectSyncDeliveryPreparation -TargetProject 'SM-LAB-004' -PackageId ([string]$pub.manifest.PACKAGE_ID) -OpsRoot $testOps
    Assert-True ([bool]$syncLab.ok) 'Project Sync prep ok for enrolled LAB'
    Assert-True (-not [bool]$syncLab.MUTATION_PERFORMED) 'Project Sync prep no mutation'
    Assert-True ([string]$syncLab.LIFECYCLE_STATUS -eq 'DELIVERY_PREPARED') 'T04 ProjectSyncPrep transition DELIVERY_PREPARED'
    $lc1 = Get-PublicationLifecycle -PackageId ([string]$pub.manifest.PACKAGE_ID) -OpsRoot $testOps
    Assert-True ([string]$lc1.LIFECYCLE_STATUS -eq 'DELIVERY_PREPARED') 'Sidecar after ProjectSync is DELIVERY_PREPARED'
    Assert-True (Test-HistoricalPublicationManifestUnchanged -PackageId ([string]$pub.manifest.PACKAGE_ID) -OpsRoot $testOps) 'T03 manifest unchanged after ProjectSyncPrep'
    $labAfterSync = Get-ProjectRegistryEntry -ProjectId 'SM-LAB-004' -OpsRoot $testOps
    Assert-True ([string]$labAfterSync.LAST_PUBLICATION_LIFECYCLE -eq 'DELIVERY_PREPARED') 'T13 registry optional LAST_PUBLICATION_LIFECYCLE set on prep'

    $runnerFailThrew = $false
    try {
        & $runner -Action PrepareProjectSync -OpsRoot $testOps -Args @{
            TargetProject = 'CloseReport'
            PackageId = [string]$pub.manifest.PACKAGE_ID
        } | Out-Null
    }
    catch { $runnerFailThrew = $true }
    Assert-True (-not $runnerFailThrew) 'Runner PrepareProjectSync failure shape does not throw under StrictMode'

    $runnerOkThrew = $false
    try {
        & $runner -Action PrepareProjectSync -OpsRoot $testOps -Args @{
            TargetProject = 'SM-LAB-004'
            PackageId = [string]$pub.manifest.PACKAGE_ID
        } | Out-Null
    }
    catch { $runnerOkThrew = $true }
    Assert-True (-not $runnerOkThrew) 'Runner PrepareProjectSync success shape does not throw under StrictMode'

    $homeView = Get-ProjectHomeViewFromRegistry -OpsRoot $testOps
    Assert-True (@($homeView.projects | Where-Object { $_.PROJECT_ID -eq 'CloseReport' -and $_.PROJECT_SYNC_STATUS -eq 'UNKNOWN' }).Count -eq 1) 'Home CR sync UNKNOWN'
    Assert-True (@($homeView.needs_your_attention).Count -ge 1) 'Home attention from registry'

    $ai = Invoke-SkillsMachineAiAccess -Operation 'LIST_PROJECTS' -CallerType 'GENERAL_AI' -CallerProject 'TEST' -OpsRoot $testOps -SkillsRoot (Join-Path $RepoRoot 'SkillsLake\01.SKILLS')
    Assert-True ([bool]$ai.ok) 'AI LIST_PROJECTS ok'
    Assert-True ($ai.meta.classification -eq 'READ_ONLY') 'AI classification READ_ONLY'
    Assert-True ((Get-AiOperationClassification -Operation 'SUBMIT_IMPROVEMENT_OPPORTUNITY') -eq 'STATE_CHANGE') 'Submit is STATE_CHANGE'
    Assert-True ((Get-AiOperationClassification -Operation 'REQUEST_PROJECT_SYNC_REVIEW') -eq 'PROPOSAL') 'Sync review is PROPOSAL'

    Assert-True (Test-Path (Join-Path $RepoRoot 'SyS\A_Tools\ProjectOps\v0.1\Measurement\MEAS.OPP-CR-076A-01.json')) 'Measurement contract present'
    $meas = Get-Content (Join-Path $RepoRoot 'SyS\A_Tools\ProjectOps\v0.1\Measurement\MEAS.OPP-CR-076A-01.json') -Raw | ConvertFrom-Json
    Assert-True ($meas.SUCCESS_THRESHOLD -eq 'HUMAN_DECISION_REQUIRED') 'Measurement threshold human'
    Assert-True ($meas.OPPORTUNITY_ID -eq 'OPP-CR-076A-01') 'Measurement opportunity id'
    Assert-True ([string]$meas.IMMEDIATE_RESULT -eq 'PASS') 'Measurement immediate PASS'
    Assert-True ([string]$meas.OPERATIONAL_RESULT -eq 'NOT_YET_OBSERVED') 'Measurement operational not yet observed'
    Assert-True ([string]$meas.OVERALL_RESULT -eq 'PARTIAL') 'Measurement overall PARTIAL'
    $tempSkill = Get-Content (Join-Path $RepoRoot 'SkillsLake\01.SKILLS\SKILL.REPO.TEMP_ARTIFACT_MANAGEMENT.txt') -Raw
    Assert-True ($tempSkill -match 'OPP-CR-076A-01') 'Temp skill traces OPP-CR-076A-01'
    Assert-True ($tempSkill -match 'EXTERNAL_AI_EXCHANGE_TEMP') 'Temp skill classifies AI-exchange temp'
    Assert-True ($tempSkill -match 'EXECUTION_SANDBOX_TEMP') 'Temp skill classifies execution sandbox temp'
    Assert-True ($tempSkill -match 'DURABLE_CANONICAL_STORAGE') 'Temp skill distinguishes durable canonical storage'
    Assert-True ($tempSkill -match 'NEVER an authoritative baseline') 'Temp skill forbids Temp as baseline'
    Assert-True ($tempSkill -match 'T\.AI\.SkillMachine') 'Temp skill uses current AI-exchange path'
    Assert-True ($tempSkill -match 'Temp\.SkillMachine is superseded') 'Temp skill records superseded name'
    Assert-True ($tempSkill -notmatch 'T\.AI\.SkillsMachineGrafos') 'Temp skill does not hard-code Graph sandbox path'
    $verReg = Get-Content (Join-Path $RepoRoot '90.USECASE\GLOBAL.SKILL.VERSION.REGISTRY.json') -Raw | ConvertFrom-Json
    $tempReg = @($verReg.skills | Where-Object { [string]$_.file -match 'SKILL\.REPO\.TEMP_ARTIFACT_MANAGEMENT' } | Select-Object -First 1)
    Assert-True ($tempReg.Count -eq 1) 'Version registry has temp skill entry'
    Assert-True ([string]$tempReg[0].version -match 'v?1\.2') 'Active version registry is 1.2'
    $grcCompact = Get-Content (Join-Path $RepoRoot 'GRCLake\01.CONTROLS\GRC.COMPACT_UPLOAD_PACK_ONLY.txt') -Raw
    Assert-True ($grcCompact -match 'T\.AI\.SkillMachine') 'Active compact-upload GRC names current AI-exchange Temp'
    Assert-True ($grcCompact -match 'superseded for AI exchange') 'Active compact-upload GRC records legacy name as superseded'
    $mapTxt = Get-Content (Join-Path $RepoRoot 'SyS\A_Tools\VerticalSlice\v0.1\Contracts\CLOSEREPORT_PILOT_MAPPING.V0.1.txt') -Raw
    Assert-True ($mapTxt -match 'MB-SM-076A7_CURRENT') 'Mapping retains 076A7 historical snapshot'
    Assert-True ($mapTxt -match 'GIT_COMMITTED=NO') 'Historical mapping snapshot still records pre-commit state'
    Assert-True ($mapTxt -match 'PUBLICATION_STATUS=PREPARED_NOT_DELIVERED') 'Historical mapping snapshot still records prepared publication'
    Assert-True ($mapTxt -match 'MB-SM-076A12_CURRENT') 'Mapping has 076A12 current lifecycle section'
    Assert-True ($mapTxt -match 'STAGE_13=PASS') 'Current mapping Stage 13 is PASS'
    Assert-True ($mapTxt -match 'STAGE_14=PARTIAL') 'Current mapping Stage 14 remains PARTIAL'
    Assert-True ($mapTxt -match 'TARGET_APPLY_STATUS=APPLIED') 'Current mapping target apply is APPLIED'
    Assert-True ($mapTxt -match 'PROJECT_SYNC_APPLIED=NO') 'Mapping still records SkillsMachine did not apply into target'

    $aiContract = Get-Content (Join-Path $RepoRoot 'SyS\A_Tools\VerticalSlice\v0.1\Contracts\AI_ACCESS.V0.1.txt') -Raw
    Assert-True ($aiContract -match 'GET_ENROLMENT_PROPOSAL') 'AI contract has GET_ENROLMENT_PROPOSAL'
    Assert-True ($aiContract -notmatch 'Learning Sync') 'AI contract no Learning Sync'

    $approvedOnly = Approve-EnrolmentProposal `
        -ProposalId ([string]$prop.proposal.PROPOSAL_ID) `
        -HumanDecision 'APPROVE' `
        -AuthorizationSource 'TEST-076A7' `
        -OpsRoot $testOps
    Assert-True ([string]$approvedOnly.proposal.HUMAN_APPROVAL -eq 'EXPLICIT') 'Approval records EXPLICIT'
    Assert-True ([string]$approvedOnly.proposal.PROPOSAL_STATUS -eq 'APPROVED') 'Approved without apply stays APPROVED'
    Assert-True (-not [bool]$approvedOnly.enrolled) 'Approve without apply does not enrol'
    $crApproved = Get-ProjectRegistryEntry -ProjectId 'CloseReport' -OpsRoot $testOps
    Assert-True ($crApproved.ENROLMENT_STATUS -eq 'NOT_ENROLLED') 'CR still NOT_ENROLLED until apply'

    $applied = Approve-EnrolmentProposal `
        -ProposalId ([string]$prop.proposal.PROPOSAL_ID) `
        -HumanDecision 'APPROVE' `
        -AuthorizationSource 'TEST-076A7' `
        -ApplySkillsMachineEnrolment `
        -OpsRoot $testOps
    Assert-True ([bool]$applied.enrolled) 'Apply enrols SM-side'
    Assert-True ([string]$applied.enrolment_status -eq 'ENROLLED') 'Enrolment status ENROLLED'
    Assert-True ([string]$applied.EXTERNAL_PROJECT_MUTATION -eq 'NO') 'Enrolment does not mutate external projects'
    $crEnrolled = Get-ProjectRegistryEntry -ProjectId 'CloseReport' -OpsRoot $testOps
    Assert-True ($crEnrolled.ENROLMENT_STATUS -eq 'ENROLLED') 'Registry ENROLLED'
    Assert-True ([bool]$crEnrolled.EXPLICITLY_ENROLLED_IN_SKILLSMACHINE) 'Explicitly enrolled flag'
    Assert-True ([bool]$crEnrolled.IMPROVEMENT_FLOW_ENABLED) 'IF enabled after apply'
    Assert-True ([string]$crEnrolled.RECEIVING_BOUNDARY_00_SKILLSMACHINE -eq 'ABSENT') 'Receiving boundary remains ABSENT'

    $ifAfterEnrol = New-ImprovementFlowSubmissionPackage `
        -SourceProject 'CloseReport' `
        -OpportunityId 'OPP-CR-TEST-ENROLLED' `
        -EvidenceRefs @('meas.json') `
        -TargetSkillGrc 'SKILL.REPO.TEMP_ARTIFACT_MANAGEMENT' `
        -PayloadText 'temp retention' `
        -OpsRoot $testOps
    Assert-True ([bool]$ifAfterEnrol.ok) 'IF accepts CloseReport after SM-side enrol'

    $syncCrEnrolled = New-ProjectSyncDeliveryPreparation -TargetProject 'CloseReport' -PackageId ([string]$pub.manifest.PACKAGE_ID) -OpsRoot $testOps
    Assert-True ([bool]$syncCrEnrolled.ok) 'Project Sync prep ok for enrolled CR'
    $delivId = [string]$syncCrEnrolled.delivery.DELIVERY_ID
    $headA = '5e298bcd132cf8d87832bb66bbc6875bf0b68c02'
    $headB = 'aba2e3441a1041a1e7e1f63df5190e53a4e0c48f'
    $receiptA = 'RECEIPT-DELIV-TEST-VALID-001'

    $rrMissing = Register-ProjectSyncTargetReturnReceipt `
        -DeliveryId $delivId -TargetProject 'CloseReport' -LocalReceiptId $receiptA -TargetHead 'not-a-hash' -OpsRoot $testOps
    Assert-True (-not [bool]$rrMissing.ok) 'Missing/invalid target HEAD is rejected'
    Assert-True ([string]$rrMissing.Reason -eq 'MISSING_APPLY_EVIDENCE') 'Invalid HEAD reason MISSING_APPLY_EVIDENCE'

    $rrWrongDeliv = Register-ProjectSyncTargetReturnReceipt `
        -DeliveryId 'DELIV-DOES-NOT-EXIST' -TargetProject 'CloseReport' -LocalReceiptId $receiptA -TargetHead $headA -OpsRoot $testOps
    Assert-True (-not [bool]$rrWrongDeliv.ok) 'Wrong delivery ID is rejected'
    Assert-True ([string]$rrWrongDeliv.Reason -eq 'DELIVERY_NOT_FOUND') 'Wrong delivery reason DELIVERY_NOT_FOUND'

    $rrWrongProj = Register-ProjectSyncTargetReturnReceipt `
        -DeliveryId $delivId -TargetProject 'SM-LAB-004' -LocalReceiptId $receiptA -TargetHead $headA -OpsRoot $testOps
    Assert-True (-not [bool]$rrWrongProj.ok) 'Wrong project is rejected'
    Assert-True ([string]$rrWrongProj.Reason -eq 'TARGET_PROJECT_MISMATCH') 'Wrong project reason TARGET_PROJECT_MISMATCH'

    $prepReload = Read-ProjectOpsJson -Path $syncCrEnrolled.delivery_path
    Assert-True ([string]$prepReload.DELIVERY_STATUS -eq 'PREPARED') 'PREPARED remains until valid consume'
    Assert-True ([string]$prepReload.TARGET_APPLY_STATUS -eq 'NOT_STARTED') 'NOT_STARTED remains until valid consume'

    $ifEarly = Advance-ImprovementFlowOpportunityOnReturnReceipt `
        -PackageId ([string]$pub.manifest.PACKAGE_ID) `
        -OpportunityId 'OPP-TEST-002' `
        -OpsRoot $testOps
    Assert-True (-not [bool]$ifEarly.ok) 'T09 missing receipt does not over-advance IF reconcile'
    Assert-True ([string]$ifEarly.Reason -eq 'MISSING_RECEIPT') 'T09 reason MISSING_RECEIPT'

    $ifMissingOpp = Advance-ImprovementFlowOpportunityOnReturnReceipt `
        -PackageId ([string]$pub.manifest.PACKAGE_ID) `
        -OpportunityId 'OPP-DOES-NOT-EXIST' `
        -OpsRoot $testOps
    Assert-True (-not [bool]$ifMissingOpp.ok) 'T10 missing accumulator evidence does not over-advance'
    Assert-True ([string]$ifMissingOpp.Reason -eq 'MISSING_ACCUMULATOR_EVIDENCE' -or [string]$ifMissingOpp.Reason -eq 'MISSING_RECEIPT') 'T10 refuses without accumulator or receipt'

    $rrOk = Register-ProjectSyncTargetReturnReceipt `
        -DeliveryId $delivId `
        -TargetProject 'CloseReport' `
        -LocalReceiptId $receiptA `
        -TargetHead $headA `
        -TargetOriginMain $headA `
        -TargetSkillVersion '1.1' `
        -TargetValidation 'PASS' `
        -TargetPushStatus 'PASS' `
        -TargetApplyEvidence 'APPLIED_LOCAL_COMMITTED_AND_PUSHED' `
        -ReceivingBoundaryStatus 'COMMITTED_MINIMAL_AND_PUSHED' `
        -OpsRoot $testOps
    Assert-True ([bool]$rrOk.ok) 'Valid target receipt is consumed'
    Assert-True ([string]$rrOk.TARGET_APPLY_STATUS -eq 'APPLIED') 'Contract TARGET_APPLY_STATUS is APPLIED'
    Assert-True ([string]$rrOk.DELIVERY_STATUS -eq 'DELIVERED') 'DELIVERY_STATUS becomes DELIVERED'
    Assert-True ([bool]$rrOk.RETURN_RECEIPT_RECORDED) 'Return receipt recorded'
    Assert-True (-not [bool]$rrOk.MUTATION_PERFORMED) 'Consume does not mutate target'
    $after = Read-ProjectOpsJson -Path $syncCrEnrolled.delivery_path
    Assert-True ([string]$after.ORIGINAL_DELIVERY_STATUS -eq 'PREPARED') 'Prepared delivery status preserved'
    Assert-True ([string]$after.ORIGINAL_TARGET_APPLY_STATUS -eq 'NOT_STARTED') 'Prepared apply status preserved'
    Assert-True ([string]$after.PROJECT_SYNC_APPLIED -eq 'NO') 'PROJECT_SYNC_APPLIED remains NO (SM did not apply)'
    Assert-True ([string]$after.UPDATE_RECEIPT_ID -eq $receiptA) 'UPDATE_RECEIPT_ID stored'
    Assert-True ([string]$after.TARGET_HEAD -eq $headA) 'TARGET_HEAD stored'
    Assert-True ([string]$after.TARGET_APPLY_EVIDENCE -eq 'APPLIED_LOCAL_COMMITTED_AND_PUSHED') 'Target-side apply evidence preserved'
    $rrFile = Join-Path (Get-ProjectSyncReturnReceiptDir -OpsRoot $testOps) ("{0}.json" -f $receiptA)
    Assert-True (Test-Path -LiteralPath $rrFile) 'Durable return receipt file written'
    $crAfterRr = Get-ProjectRegistryEntry -ProjectId 'CloseReport' -OpsRoot $testOps
    Assert-True ([string]$crAfterRr.PROJECT_SYNC_STATUS -eq 'CURRENT') 'Registry Project Sync becomes CURRENT'
    Assert-True ([string]$crAfterRr.LAST_UPDATE_RECEIPT_ID -eq $receiptA) 'Registry LAST_UPDATE_RECEIPT_ID set'
    Assert-True ([string]$crAfterRr.RECEIVING_BOUNDARY_00_SKILLSMACHINE -eq 'PRESENT') 'Registry receiving boundary PRESENT'
    Assert-True ([string]$crAfterRr.OBSERVED_HEAD -eq $headA) 'Registry observed HEAD updated'
    Assert-True ([string]$rrOk.LIFECYCLE_STATUS -eq 'RETURN_RECEIPT_CONSUMED') 'T05 receipt-consumption transition RETURN_RECEIPT_CONSUMED'
    $lc2 = Get-PublicationLifecycle -PackageId ([string]$pub.manifest.PACKAGE_ID) -OpsRoot $testOps
    Assert-True ([string]$lc2.LIFECYCLE_STATUS -eq 'RETURN_RECEIPT_CONSUMED') 'Sidecar after receipt is RETURN_RECEIPT_CONSUMED'
    Assert-True (Test-HistoricalPublicationManifestUnchanged -PackageId ([string]$pub.manifest.PACKAGE_ID) -OpsRoot $testOps) 'T03 manifest unchanged after receipt consume'
    Assert-True ([string]$crAfterRr.LAST_PUBLICATION_LIFECYCLE -eq 'RETURN_RECEIPT_CONSUMED') 'T13 registry LAST_PUBLICATION_LIFECYCLE after receipt'

    $ifMissingOppAfter = Advance-ImprovementFlowOpportunityOnReturnReceipt `
        -PackageId ([string]$pub.manifest.PACKAGE_ID) `
        -OpportunityId 'OPP-DOES-NOT-EXIST' `
        -OpsRoot $testOps
    Assert-True (-not [bool]$ifMissingOppAfter.ok) 'T10 missing accumulator evidence refuses after receipt'
    Assert-True ([string]$ifMissingOppAfter.Reason -eq 'MISSING_ACCUMULATOR_EVIDENCE') 'T10 reason MISSING_ACCUMULATOR_EVIDENCE'

    $ifOk = Advance-ImprovementFlowOpportunityOnReturnReceipt `
        -PackageId ([string]$pub.manifest.PACKAGE_ID) `
        -OpportunityId 'OPP-TEST-002' `
        -OpsRoot $testOps
    Assert-True ([bool]$ifOk.ok) 'T06 applied/receipt/accumulator transition ok'
    Assert-True ([string]$ifOk.ACCUMULATOR_STATUS -eq 'DELIVERED_APPLIED_RECEIPTED') 'T06 accumulator DELIVERED_APPLIED_RECEIPTED'
    Assert-True ([string]$ifOk.LIFECYCLE_STATUS -eq 'RETURN_RECEIPT_CONSUMED') 'T07 sidecar remains RETURN_RECEIPT_CONSUMED'
    Assert-True ([string]$ifOk.RECONCILIATION_STATUS -eq 'DELIVERED_APPLIED_RECEIPTED') 'T07 fully reconciled lifecycle status supported'
    $accAfter = Read-ActiveAccumulator -OpsRoot $testOps
    $opp002 = @($accAfter.opportunities | Where-Object { [string]$_.OPPORTUNITY_ID -eq 'OPP-TEST-002' } | Select-Object -First 1)
    Assert-True ([string]$opp002[0].STATUS -eq 'DELIVERED_APPLIED_RECEIPTED') 'Accumulator opportunity advanced without rewriting dispositions'
    $priorReloadAfterIf = Read-ProjectOpsJson -Path $priorPath
    Assert-True ([string]$priorReloadAfterIf.DECISION -eq 'NEEDS_HUMAN_DECISION') 'IF reconcile does not rewrite prior disposition JSON'
    Assert-True (Test-HistoricalPublicationManifestUnchanged -PackageId ([string]$pub.manifest.PACKAGE_ID) -OpsRoot $testOps) 'Manifest unchanged after IF reconcile'

    $ifReplay = Advance-ImprovementFlowOpportunityOnReturnReceipt `
        -PackageId ([string]$pub.manifest.PACKAGE_ID) `
        -OpportunityId 'OPP-TEST-002' `
        -OpsRoot $testOps
    Assert-True ([bool]$ifReplay.ok) 'T08 IF reconcile rerun ok'
    Assert-True ([bool]$ifReplay.MUTATION_PERFORMED -eq $false) 'T08 IF reconcile rerun is idempotent'

    $lcCorruptPkg = New-ProductionPublicationPackage `
        -CapabilityId 'SKILL.REPO.TEMP_ARTIFACT_MANAGEMENT' `
        -Version '9.9.8' `
        -SourceDispositionId ([string]$dispOk.DISPOSITION_ID) `
        -PackageBody 'identity-fail' `
        -OpsRoot $testOps
    $corrupt = Get-PublicationLifecycle -PackageId ([string]$lcCorruptPkg.manifest.PACKAGE_ID) -OpsRoot $testOps
    $corrupt.PACKAGE_ID = 'PKG-OTHER-IDENTITY'
    [void](Write-PublicationLifecycle -Lifecycle $corrupt -PackageId ([string]$lcCorruptPkg.manifest.PACKAGE_ID) -OpsRoot $testOps)
    $idFail = Set-PublicationLifecycleStatus `
        -PackageId ([string]$lcCorruptPkg.manifest.PACKAGE_ID) `
        -NewStatus 'DELIVERY_PREPARED' `
        -SourceEvent 'PROJECT_SYNC_PREPARED' `
        -OpsRoot $testOps
    Assert-True (-not [bool]$idFail.ok) 'T11 mismatched package identity refuses transition'
    Assert-True ([string]$idFail.Reason -eq 'PACKAGE_IDENTITY_MISMATCH') 'T11 reason PACKAGE_IDENTITY_MISMATCH'

    $runnerPubOut = & $runner -Action PreparePublication -OpsRoot $testOps -Args @{
        CapabilityId = 'SKILL.REPO.TEMP_ARTIFACT_MANAGEMENT'
        Version = '9.9.9'
        SourceDispositionId = [string]$dispOk.DISPOSITION_ID
        PackageBody = 'runner-lifecycle'
    } *>&1 | Out-String
    Assert-True ($runnerPubOut -match 'LIFECYCLE_STATUS=PREPARED') 'T12 Invoke-ProjectOps emits LIFECYCLE_STATUS'
    $runnerLc = Get-PublicationLifecycle -PackageId 'PKG-SKILL.REPO.TEMP_ARTIFACT_MANAGEMENT-9.9.9' -OpsRoot $testOps
    Assert-True ($null -ne $runnerLc -and [string]$runnerLc.LIFECYCLE_STATUS -eq 'PREPARED') 'T12 runner publication sidecar PREPARED'

    $rrReplay = Register-ProjectSyncTargetReturnReceipt `
        -DeliveryId $delivId -TargetProject 'CloseReport' -LocalReceiptId $receiptA -TargetHead $headA -OpsRoot $testOps
    Assert-True ([bool]$rrReplay.ok) 'Duplicate identical receipt is idempotent'
    Assert-True ([bool]$rrReplay.IDEMPOTENT_REPLAY) 'Replay flagged IDEMPOTENT_REPLAY'

    $rrDupHead = Register-ProjectSyncTargetReturnReceipt `
        -DeliveryId $delivId -TargetProject 'CloseReport' -LocalReceiptId $receiptA -TargetHead $headB -OpsRoot $testOps
    Assert-True (-not [bool]$rrDupHead.ok) 'Same receipt different HEAD is rejected'
    Assert-True ([string]$rrDupHead.Reason -eq 'TARGET_HEAD_MISMATCH') 'Different HEAD reason TARGET_HEAD_MISMATCH'

    $rrDupId = Register-ProjectSyncTargetReturnReceipt `
        -DeliveryId $delivId -TargetProject 'CloseReport' -LocalReceiptId 'RECEIPT-OTHER' -TargetHead $headA -OpsRoot $testOps
    Assert-True (-not [bool]$rrDupId.ok) 'Second receipt for same delivery is rejected'
    Assert-True ([string]$rrDupId.Reason -eq 'DUPLICATE_RECEIPT_CONFLICT') 'Different receipt reason DUPLICATE_RECEIPT_CONFLICT'

    $runnerRrThrew = $false
    try {
        & $runner -Action ConsumeTargetReturnReceipt -OpsRoot $testOps -Args @{
            DeliveryId = $delivId
            TargetProject = 'CloseReport'
            LocalReceiptId = $receiptA
            TargetHead = $headA
        } | Out-Null
    }
    catch { $runnerRrThrew = $true }
    Assert-True (-not $runnerRrThrew) 'Runner ConsumeTargetReturnReceipt idempotent shape does not throw under StrictMode'

    $runnerRrFailThrew = $false
    try {
        & $runner -Action ConsumeTargetReturnReceipt -OpsRoot $testOps -Args @{
            DeliveryId = 'DELIV-DOES-NOT-EXIST'
            TargetProject = 'CloseReport'
            LocalReceiptId = $receiptA
            TargetHead = $headA
        } | Out-Null
    }
    catch { $runnerRrFailThrew = $true }
    Assert-True (-not $runnerRrFailThrew) 'Runner ConsumeTargetReturnReceipt failure shape does not throw under StrictMode'
}
finally {
    if (Test-Path -LiteralPath $testOps) {
        Remove-Item -LiteralPath $testOps -Recurse -Force
    }
}

if ($failed -gt 0) {
    Write-Host "TEST_SUMMARY=FAIL count=$failed"
    exit 1
}
Write-Host 'TEST_SUMMARY=PASS'
exit 0
