#Requires -Version 5.1
<#
.SYNOPSIS
  SkillsMachine ProjectOps runner (MB-SM-076A3)
.DESCRIPTION
  Durable registry, enrolment proposals, Improvement Flow intake, publication prep, AI access.
  Never mutates external projects.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet(
        'InitRegistry',
        'GenerateCloseReportProposal',
        'SubmitImprovement',
        'RotateAccumulator',
        'CreateDisposition',
        'PreparePublication',
        'PrepareProjectSync',
        'AiAccess',
        'ShowHomeView',
        'SelfTest',
        'ApproveEnrolment'
    )]
    [string]$Action,

    [string]$RepoRoot = '',
    [string]$OpsRoot = '',
    [hashtable]$Args = @{}
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$here = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($OpsRoot)) { $OpsRoot = $here }
if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $here '..\..\..\..'))
}

. (Join-Path $here 'Core\Common.ps1')
. (Join-Path $here 'Core\Registry.ps1')
. (Join-Path $here 'Core\Enrolment.ps1')
. (Join-Path $here 'Core\ImprovementFlow.ps1')
. (Join-Path $here 'Core\Publication.ps1')
. (Join-Path $here 'Core\ProjectSyncPrep.ps1')
. (Join-Path $here 'Core\AiAccess.ps1')

function Set-NoteProp {
    param($Object, [string]$Name, $Value)
    if ($Object.PSObject.Properties.Name -contains $Name) {
        $Object.$Name = $Value
    }
    else {
        $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
    }
}

function Test-NoteProp {
    param($Object, [string]$Name)
    return ($null -ne $Object -and ($Object.PSObject.Properties.Name -contains $Name))
}

function Get-NoteProp {
    param($Object, [string]$Name, $Default = $null)
    if (Test-NoteProp -Object $Object -Name $Name) { return $Object.$Name }
    return $Default
}

function Initialize-DefaultRegistry {
    param([string]$Root = $OpsRoot)
    $lab = [pscustomobject]@{
        PROJECT_ID = 'SM-LAB-004'
        PROJECT_ROOT_IDENTITY = '99.LABS/SM-LAB-004_SKILLS_IMPROVEMENT_VERTICAL_SLICE'
        PROJECT_TYPE = 'LAB'
        PROJECT_CLASS = 'ENROLLED_PROJECT'
        ENROLMENT_STATUS = 'ENROLLED'
        ENROLMENT_METHOD = 'NEW_PROJECT'
        ENROLLED_AT = '2026-08-07T00:00:00Z'
        CAPABILITY_BASELINE = 'SKILL.LAB.LONG_RUNNING_RUNNER_HEARTBEAT@1.1.0'
        IMPROVEMENT_FLOW_ENABLED = $true
        PROJECT_SYNC_ENABLED = $true
        LAST_OBSERVED_AT = 'LAB'
        LAST_SYNC_ID = 'LAB'
        LAST_RECEIPT_ID = $null
        AUTHORITY_MODEL = 'SKILLSMACHINE_PACKAGE_EXCHANGE_ONLY'
        IMPROVEMENT_FLOW_STATUS = 'NONE'
        PROJECT_SYNC_STATUS = 'CURRENT'
        ATTENTION = 'NONE'
        CREATED_BY_SKILLSMACHINE = $true
        EXPLICITLY_ENROLLED_IN_SKILLSMACHINE = $true
        RECEIVING_BOUNDARY_00_SKILLSMACHINE = 'PRESENT_LAB'
        PROPOSAL_STATUS = $null
        LATEST_PROPOSAL_ID = $null
        OBSERVED_HEAD = 'LAB'
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
        LAST_OBSERVED_AT = 'SEED'
        LAST_SYNC_ID = $null
        LAST_RECEIPT_ID = $null
        AUTHORITY_MODEL = 'PROJECT_LOCAL_MUTATION_REQUIRED'
        IMPROVEMENT_FLOW_STATUS = 'NONE'
        PROJECT_SYNC_STATUS = 'UNKNOWN'
        ATTENTION = 'ENROLMENT_REQUIRED'
        CREATED_BY_SKILLSMACHINE = $false
        EXPLICITLY_ENROLLED_IN_SKILLSMACHINE = $false
        RECEIVING_BOUNDARY_00_SKILLSMACHINE = 'ABSENT'
        PROPOSAL_STATUS = $null
        LATEST_PROPOSAL_ID = $null
        OBSERVED_HEAD = $null
    }
    $reg = New-EmptyProjectRegistry
    $reg.projects = @($lab, $cr)
    $path = Save-ProjectRegistry -Registry $reg -OpsRoot $Root
    Initialize-ImprovementFlowState -OpsRoot $Root
    return $path
}

switch ($Action) {
    'InitRegistry' {
        $path = Initialize-DefaultRegistry
        Write-Host "REGISTRY_PATH=$path"
        Write-Host 'ACTION=InitRegistry STATUS=PASS'
    }
    'GenerateCloseReportProposal' {
        if (-not (Test-Path (Get-ProjectRegistryPath -OpsRoot $OpsRoot))) {
            [void](Initialize-DefaultRegistry)
        }
        $crRoot = 'C:\01. GitHub\CloseReport'
        if (-not (Test-Path -LiteralPath $crRoot)) {
            throw 'CLOSEREPORT_ROOT_NOT_FOUND'
        }
        Push-Location $crRoot
        try {
            $head = (& git rev-parse HEAD).Trim()
            $branch = (& git branch --show-current).Trim()
            $dirty = @(& git status --short --untracked-files=all).Count
        }
        finally {
            Pop-Location
        }
        $skillsPresent = Test-Path (Join-Path $crRoot '07.SKILLS')
        $surfacePresent = Test-Path (Join-Path $crRoot '00_SKILLSMACHINE')
        $discovery = @{
            observed_branch = $branch
            dirty_worktree_count = $dirty
            receiving_boundary_present = $surfacePresent
            local_skills_surface = $(if ($skillsPresent) { '07.SKILLS' } else { 'ABSENT' })
            fork_or_gap_summary = 'No 00_SKILLSMACHINE surface; project-local 07.SKILLS present; not enrolled in SkillsMachine'
            human_authority_doc = '000.HUMAN/HUMAN.CloseReport.txt'
            non_mutation = $true
            read_only_discovery = $true
        }
        $result = New-ExistingProjectEnrolmentProposal `
            -ProjectId 'CloseReport' `
            -ProjectRootIdentity $crRoot `
            -ObservedHead $head `
            -Discovery $discovery `
            -OpsRoot $OpsRoot `
            -ReadyForReview
        Write-Host ("PROPOSAL_ID={0}" -f $result.proposal.PROPOSAL_ID)
        Write-Host ("PROPOSAL_STATUS={0}" -f $result.proposal.PROPOSAL_STATUS)
        Write-Host ("PROPOSAL_PATH={0}" -f $result.proposal_path)
        Write-Host ("REGISTRY_ENROLMENT_STATUS={0}" -f $result.registry_enrolment_status)
        Write-Host ("AUTO_ENROLLED={0}" -f $result.auto_enrolled)
        Write-Host 'CLOSEREPORT_MUTATION=NO'
        Write-Host 'ACTION=GenerateCloseReportProposal STATUS=PASS'
    }
    'SubmitImprovement' {
        $r = New-ImprovementFlowSubmissionPackage `
            -SourceProject ([string]$Args['SourceProject']) `
            -OpportunityId ([string]$Args['OpportunityId']) `
            -EvidenceRefs @($Args['EvidenceRefs']) `
            -TargetSkillGrc ([string]$Args['TargetSkillGrc']) `
            -PayloadText ([string]$Args['PayloadText']) `
            -OpsRoot $OpsRoot
        Write-Host ("OK={0}" -f $r.ok)
        Write-Host ("STATUS={0}" -f $r.STATUS)
        $failState = Get-NoteProp -Object $r -Name 'FAILURE_STATE'
        if (-not [string]::IsNullOrWhiteSpace([string]$failState)) { Write-Host ("FAILURE_STATE={0}" -f $failState) }
        $receipt = Get-NoteProp -Object $r -Name 'receipt'
        if ($null -ne $receipt) { Write-Host ("RECEIPT_ID={0}" -f [string]$receipt.RECEIPT_ID) }
        Write-Host 'ACTION=SubmitImprovement STATUS=PASS'
    }
    'RotateAccumulator' {
        $r = Invoke-AccumulatorRotation -ReceiptId ([string]$Args['ReceiptId']) -OpsRoot $OpsRoot
        Write-Host ("ARCHIVED={0}" -f $r.archived)
        Write-Host ("NEW_ACC={0}" -f $r.active.ACCUMULATOR_ID)
        Write-Host 'ACTION=RotateAccumulator STATUS=PASS'
    }
    'CreateDisposition' {
        $humanConfirmed = $false
        if ($Args.ContainsKey('HumanConfirmed')) {
            $rawHc = $Args['HumanConfirmed']
            if ($rawHc -is [bool]) { $humanConfirmed = [bool]$rawHc }
            elseif ([string]$rawHc -in @('1', 'true', 'TRUE', 'True', 'YES')) { $humanConfirmed = $true }
        }
        $targetSkill = ''
        if ($Args.ContainsKey('TargetSkillGrc')) { $targetSkill = [string]$Args['TargetSkillGrc'] }
        $supersedes = ''
        if ($Args.ContainsKey('SupersedesDispositionId')) { $supersedes = [string]$Args['SupersedesDispositionId'] }
        $recommendedBy = 'SYSTEM'
        if ($Args.ContainsKey('RecommendedBy')) { $recommendedBy = [string]$Args['RecommendedBy'] }
        $d = New-ImprovementFlowDisposition `
            -OpportunityId ([string]$Args['OpportunityId']) `
            -SubmissionId ([string]$Args['SubmissionId']) `
            -Decision ([string]$Args['Decision']) `
            -Rationale ([string]$Args['Rationale']) `
            -RecommendedBy $recommendedBy `
            -TargetSkillGrc $targetSkill `
            -SupersedesDispositionId $supersedes `
            -HumanConfirmed:$humanConfirmed `
            -OpsRoot $OpsRoot
        Write-Host ("DISPOSITION_ID={0}" -f $d.DISPOSITION_ID)
        Write-Host ("DECISION={0}" -f $d.DECISION)
        Write-Host ("HUMAN_CONFIRMED={0}" -f [bool]$d.HUMAN_CONFIRMED)
        Write-Host ("TARGET_SKILL_GRC={0}" -f [string]$d.TARGET_SKILL_GRC)
        Write-Host ("SUPERSEDES_DISPOSITION_ID={0}" -f [string]$d.SUPERSEDES_DISPOSITION_ID)
        Write-Host 'ACTION=CreateDisposition STATUS=PASS'
    }
    'PreparePublication' {
        $p = New-ProductionPublicationPackage `
            -CapabilityId ([string]$Args['CapabilityId']) `
            -Version ([string]$Args['Version']) `
            -SourceDispositionId ([string]$Args['SourceDispositionId']) `
            -PackageBody ([string]$Args['PackageBody']) `
            -SourceOpportunityId $(if ($Args.ContainsKey('SourceOpportunityId')) { [string]$Args['SourceOpportunityId'] } else { '' }) `
            -ChangeRationale $(if ($Args.ContainsKey('ChangeRationale')) { [string]$Args['ChangeRationale'] } else { '' }) `
            -ReceiptId $(if ($Args.ContainsKey('ReceiptId')) { [string]$Args['ReceiptId'] } else { '' }) `
            -OpsRoot $OpsRoot
        Write-Host ("PACKAGE_ID={0}" -f $p.manifest.PACKAGE_ID)
        Write-Host ("PUBLICATION_STATUS={0}" -f $p.PUBLICATION_STATUS)
        Write-Host 'ACTION=PreparePublication STATUS=PASS'
    }
    'PrepareProjectSync' {
        $p = New-ProjectSyncDeliveryPreparation `
            -TargetProject ([string]$Args['TargetProject']) `
            -PackageId ([string]$Args['PackageId']) `
            -SourceOpportunityId $(if ($Args.ContainsKey('SourceOpportunityId')) { [string]$Args['SourceOpportunityId'] } else { '' }) `
            -SourceDispositionId $(if ($Args.ContainsKey('SourceDispositionId')) { [string]$Args['SourceDispositionId'] } else { '' }) `
            -ReceiptId $(if ($Args.ContainsKey('ReceiptId')) { [string]$Args['ReceiptId'] } else { '' }) `
            -OpsRoot $OpsRoot
        Write-Host ("OK={0}" -f $p.ok)
        $delivery = Get-NoteProp -Object $p -Name 'delivery'
        if ($null -ne $delivery) { Write-Host ("DELIVERY_ID={0}" -f [string]$delivery.DELIVERY_ID) }
        $reason = Get-NoteProp -Object $p -Name 'Reason'
        if (-not [string]::IsNullOrWhiteSpace([string]$reason)) { Write-Host ("REASON={0}" -f $reason) }
        Write-Host ("MUTATION_PERFORMED={0}" -f (Get-NoteProp -Object $p -Name 'MUTATION_PERFORMED' -Default $false))
        Write-Host 'ACTION=PrepareProjectSync STATUS=PASS'
    }
    'AiAccess' {
        $skillsRoot = Join-Path $RepoRoot 'SkillsLake\01.SKILLS'
        $r = Invoke-SkillsMachineAiAccess `
            -Operation ([string]$Args['Operation']) `
            -CallerType ([string]$Args['CallerType']) `
            -CallerProject ([string]$Args['CallerProject']) `
            -AuthorizationContext ([string]$Args['AuthorizationContext']) `
            -Args $Args `
            -OpsRoot $OpsRoot `
            -SkillsRoot $skillsRoot
        Write-Host ("OK={0}" -f $r.ok)
        Write-Host ("CLASSIFICATION={0}" -f $r.meta.classification)
        Write-Host 'ACTION=AiAccess STATUS=PASS'
    }
    'ShowHomeView' {
        $h = Get-ProjectHomeViewFromRegistry -OpsRoot $OpsRoot
        Write-Host ("PROJECTS={0}" -f $h.projects.Count)
        Write-Host ("ATTENTION={0}" -f $h.needs_your_attention.Count)
        Write-Host ("REGISTRY={0}" -f $h.registry_path)
        Write-Host 'ACTION=ShowHomeView STATUS=PASS'
    }
    'ApproveEnrolment' {
        $apply = $false
        if ($Args.ContainsKey('ApplySkillsMachineEnrolment')) {
            $apply = [bool]$Args['ApplySkillsMachineEnrolment']
        }
        $r = Approve-EnrolmentProposal `
            -ProposalId ([string]$Args['ProposalId']) `
            -HumanDecision ([string]$Args['HumanDecision']) `
            -AuthorizationSource ([string]$Args['AuthorizationSource']) `
            -ApprovedBy $(if ($Args.ContainsKey('ApprovedBy')) { [string]$Args['ApprovedBy'] } else { 'HUMAN' }) `
            -ApplySkillsMachineEnrolment:$apply `
            -OpsRoot $OpsRoot
        Write-Host ("PROPOSAL_ID={0}" -f [string]$Args['ProposalId'])
        Write-Host ("PROPOSAL_STATUS={0}" -f [string]$r.proposal.PROPOSAL_STATUS)
        Write-Host ("HUMAN_APPROVAL={0}" -f [string]$r.proposal.HUMAN_APPROVAL)
        Write-Host ("ENROLLED={0}" -f [bool]$r.enrolled)
        Write-Host ("ENROLMENT_STATUS={0}" -f [string]$r.enrolment_status)
        Write-Host 'EXTERNAL_PROJECT_MUTATION=NO'
        Write-Host 'ACTION=ApproveEnrolment STATUS=PASS'
    }
    'SelfTest' {
        Write-Host 'Use Tests\Test-ProjectOps.ps1'
        Write-Host 'ACTION=SelfTest STATUS=SKIP'
    }
}
