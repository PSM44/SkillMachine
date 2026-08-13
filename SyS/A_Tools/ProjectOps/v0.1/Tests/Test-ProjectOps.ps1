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

    $syncCr = New-ProjectSyncDeliveryPreparation -TargetProject 'CloseReport' -PackageId ([string]$pub.manifest.PACKAGE_ID) -OpsRoot $testOps
    Assert-True (-not [bool]$syncCr.ok) 'Project Sync blocked for not enrolled CR'
    $syncLab = New-ProjectSyncDeliveryPreparation -TargetProject 'SM-LAB-004' -PackageId ([string]$pub.manifest.PACKAGE_ID) -OpsRoot $testOps
    Assert-True ([bool]$syncLab.ok) 'Project Sync prep ok for enrolled LAB'
    Assert-True (-not [bool]$syncLab.MUTATION_PERFORMED) 'Project Sync prep no mutation'

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
    $tempSkill = Get-Content (Join-Path $RepoRoot 'SkillsLake\01.SKILLS\SKILL.REPO.TEMP_ARTIFACT_MANAGEMENT.txt') -Raw
    Assert-True ($tempSkill -match 'OPP-CR-076A-01') 'Temp skill traces OPP-CR-076A-01'
    Assert-True ($tempSkill -match 'EXTERNAL_AI_EXCHANGE_TEMP') 'Temp skill classifies AI-exchange temp'
    Assert-True ($tempSkill -match 'NEVER an authoritative baseline') 'Temp skill forbids Temp as baseline'
    Assert-True ($tempSkill -match 'T\.AI\.SkillMachine') 'Temp skill uses current AI-exchange path'
    Assert-True ($tempSkill -match 'Temp\.SkillMachine is superseded') 'Temp skill records superseded name'
    $verReg = Get-Content (Join-Path $RepoRoot '90.USECASE\GLOBAL.SKILL.VERSION.REGISTRY.json') -Raw | ConvertFrom-Json
    $tempReg = @($verReg.skills | Where-Object { [string]$_.file -match 'SKILL\.REPO\.TEMP_ARTIFACT_MANAGEMENT' } | Select-Object -First 1)
    Assert-True ($tempReg.Count -eq 1) 'Version registry has temp skill entry'
    Assert-True ([string]$tempReg[0].version -match 'v?1\.1') 'Active version registry is 1.1'
    $grcCompact = Get-Content (Join-Path $RepoRoot 'GRCLake\01.CONTROLS\GRC.COMPACT_UPLOAD_PACK_ONLY.txt') -Raw
    Assert-True ($grcCompact -match 'T\.AI\.SkillMachine') 'Active compact-upload GRC names current AI-exchange Temp'
    Assert-True ($grcCompact -match 'superseded for AI exchange') 'Active compact-upload GRC records legacy name as superseded'
    $mapTxt = Get-Content (Join-Path $RepoRoot 'SyS\A_Tools\VerticalSlice\v0.1\Contracts\CLOSEREPORT_PILOT_MAPPING.V0.1.txt') -Raw
    Assert-True ($mapTxt -match 'SKILL_SOURCE_STATUS=CANON_SOURCE_WORKTREE_UPDATED') 'Mapping does not claim Git-published canon'
    Assert-True ($mapTxt -match 'GIT_COMMITTED=NO') 'Mapping records commit has not happened'
    Assert-True ($mapTxt -match 'PUBLICATION_STATUS=PREPARED_NOT_DELIVERED') 'Mapping publication is prepared not delivered'
    Assert-True ($mapTxt -match 'PROJECT_SYNC_APPLIED=NO') 'Mapping Project Sync not applied'
    Assert-True ($mapTxt -match 'TARGET_APPLY_STATUS=NOT_STARTED') 'Mapping target apply not started'

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
