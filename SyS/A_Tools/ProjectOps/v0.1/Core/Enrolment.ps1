#Requires -Version 5.1
# Enrolment Proposal Engine — MB-SM-076A3
# Proposal generation NEVER auto-approves or auto-enrols.

function Get-EnrolmentProposalDir {
    param([string]$OpsRoot = (Get-ProjectOpsRoot))
    return (Join-Path (Get-ProjectOpsStateRoot -OpsRoot $OpsRoot) 'EnrolmentProposals')
}

function New-EnrolmentProposalId {
    param([Parameter(Mandatory = $true)][string]$ProjectId)
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    return ('ENRPROP-{0}-{1}' -f $ProjectId.ToUpperInvariant(), $stamp)
}

function Test-EnrolmentProposalStatus {
    param([Parameter(Mandatory = $true)][string]$Status)
    $allowed = @('DRAFT', 'READY_FOR_REVIEW', 'APPROVED', 'REJECTED', 'EXPIRED', 'APPLIED')
    if ($allowed -notcontains $Status) {
        throw ("ENROLMENT_PROPOSAL_INVALID_STATUS: {0}" -f $Status)
    }
}

function Save-EnrolmentProposal {
    param(
        [Parameter(Mandatory = $true)]$Proposal,
        [string]$OpsRoot = (Get-ProjectOpsRoot)
    )
    Test-EnrolmentProposalStatus -Status ([string]$Proposal.PROPOSAL_STATUS)
    if ([string]$Proposal.PROPOSAL_STATUS -eq 'APPROVED' -and [string]$Proposal.HUMAN_APPROVAL -ne 'EXPLICIT') {
        throw 'ENROLMENT_APPROVED_REQUIRES_EXPLICIT_HUMAN_APPROVAL'
    }
    $dir = Get-EnrolmentProposalDir -OpsRoot $OpsRoot
    $path = Join-Path $dir ("{0}.json" -f [string]$Proposal.PROPOSAL_ID)
    Write-ProjectOpsUtf8NoBom -Path $path -Content (ConvertTo-ProjectOpsJson -Object $Proposal)
    return $path
}

function Get-EnrolmentProposal {
    param(
        [Parameter(Mandatory = $true)][string]$ProposalId,
        [string]$OpsRoot = (Get-ProjectOpsRoot)
    )
    $path = Join-Path (Get-EnrolmentProposalDir -OpsRoot $OpsRoot) ("{0}.json" -f $ProposalId)
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    return (Read-ProjectOpsJson -Path $path)
}

function Get-LatestEnrolmentProposalForProject {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectId,
        [string]$OpsRoot = (Get-ProjectOpsRoot)
    )
    $dir = Get-EnrolmentProposalDir -OpsRoot $OpsRoot
    if (-not (Test-Path -LiteralPath $dir)) { return $null }
    $files = @(Get-ChildItem -LiteralPath $dir -Filter ("ENRPROP-{0}-*.json" -f $ProjectId.ToUpperInvariant()) | Sort-Object Name -Descending)
    if ($files.Count -eq 0) {
        $files = @(Get-ChildItem -LiteralPath $dir -Filter '*.json' | Where-Object {
            try {
                $o = Get-Content $_.FullName -Raw | ConvertFrom-Json
                [string]$o.PROJECT_ID -eq $ProjectId
            } catch { $false }
        } | Sort-Object LastWriteTime -Descending)
    }
    if ($files.Count -eq 0) { return $null }
    return (Read-ProjectOpsJson -Path $files[0].FullName)
}

function New-ExistingProjectEnrolmentProposal {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectId,
        [Parameter(Mandatory = $true)][string]$ProjectRootIdentity,
        [Parameter(Mandatory = $true)][string]$ObservedHead,
        [Parameter(Mandatory = $true)][hashtable]$Discovery,
        [string]$OpsRoot = (Get-ProjectOpsRoot),
        [switch]$ReadyForReview
    )

    $proposalId = New-EnrolmentProposalId -ProjectId $ProjectId
    $status = if ($ReadyForReview) { 'READY_FOR_REVIEW' } else { 'DRAFT' }

    $proposal = [pscustomobject]@{
        schema_version = '0.2.0'
        source = 'MB-SM-076A3'
        PROPOSAL_ID = $proposalId
        PROJECT_ID = $ProjectId
        PROJECT_CLASS = 'EXISTING_UNINTEGRATED_PROJECT'
        ENROLMENT_METHOD = 'EXISTING_PROJECT'
        PROPOSAL_STATUS = $status
        HUMAN_APPROVAL = 'REQUIRED_NOT_GRANTED'
        HUMAN_DECISION_REQUIRED = $true
        AUTO_ENROL = $false
        created_at = (Get-ProjectOpsUtcNow)
        updated_at = (Get-ProjectOpsUtcNow)
        PROJECT_ROOT_IDENTITY = $ProjectRootIdentity
        OBSERVED_HEAD = $ObservedHead
        CURRENT_INTEGRATION_STATUS = 'NOT_ENROLLED'
        DISCOVERY = $Discovery
        LOCAL_VS_CANONICAL = [pscustomobject]@{
            receiving_boundary_00_SKILLSMACHINE = $(if ($Discovery.ContainsKey('receiving_boundary_present')) { [bool]$Discovery['receiving_boundary_present'] } else { $false })
            local_skills_surface = $(if ($Discovery.ContainsKey('local_skills_surface')) { [string]$Discovery['local_skills_surface'] } else { 'UNKNOWN' })
            fork_or_gap_summary = $(if ($Discovery.ContainsKey('fork_or_gap_summary')) { [string]$Discovery['fork_or_gap_summary'] } else { 'NONE_REPORTED' })
        }
        PROPOSED_CAPABILITIES = @(
            'SKILL.REPO.TEMP_ARTIFACT_MANAGEMENT',
            'SKILL.COMPACT_UPLOAD_PACK_EXECUTION'
        )
        IMPROVEMENT_FLOW_ENABLED_PROPOSED = $true
        PROJECT_SYNC_ENABLED_PROPOSED = $true
        RECEIVING_BOUNDARY_REQUIREMENT = 'Create project-local 00_SKILLSMACHINE under target project authority (NOT performed by this proposal)'
        DIRTY_WORKTREE_CONSTRAINT = $(if ($Discovery.ContainsKey('dirty_worktree_count')) { [string]$Discovery['dirty_worktree_count'] } else { 'UNKNOWN' })
        REQUIRED_TARGET_PROJECT_AUTHORIZATION = 'Target project human must authorize enrolment acceptance and any local surface creation/apply'
        NON_MUTATION_STATEMENT = 'This proposal is SkillsMachine-side only. No target-project files were created, edited, staged, committed, or pushed.'
        AUTHORITY_MODEL = 'PROJECT_LOCAL_MUTATION_REQUIRED'
        FLOW = @('DISCOVERY', 'INVENTORY', 'LOCAL_CANONICAL_COMPARISON', 'FORK_GAP_DETECTION', 'PROPOSAL', 'HUMAN_DECISION_REQUIRED')
    }

    $path = Save-EnrolmentProposal -Proposal $proposal -OpsRoot $OpsRoot

    # Registry remains NOT_ENROLLED; attach proposal status only.
    $existing = Get-ProjectRegistryEntry -ProjectId $ProjectId -OpsRoot $OpsRoot
    if ($null -eq $existing) {
        $existing = [pscustomobject]@{
            PROJECT_ID = $ProjectId
            PROJECT_ROOT_IDENTITY = $ProjectRootIdentity
            PROJECT_TYPE = 'PRODUCT'
            PROJECT_CLASS = 'EXISTING_UNINTEGRATED_PROJECT'
            ENROLMENT_STATUS = 'NOT_ENROLLED'
            ENROLMENT_METHOD = $null
            ENROLLED_AT = $null
            CAPABILITY_BASELINE = 'UNKNOWN'
            IMPROVEMENT_FLOW_ENABLED = $false
            PROJECT_SYNC_ENABLED = $false
            LAST_OBSERVED_AT = (Get-ProjectOpsUtcNow)
            LAST_SYNC_ID = $null
            LAST_RECEIPT_ID = $null
            AUTHORITY_MODEL = 'PROJECT_LOCAL_MUTATION_REQUIRED'
            IMPROVEMENT_FLOW_STATUS = 'NONE'
            PROJECT_SYNC_STATUS = 'UNKNOWN'
            ATTENTION = 'ENROLMENT_PROPOSAL_READY'
            CREATED_BY_SKILLSMACHINE = $false
            EXPLICITLY_ENROLLED_IN_SKILLSMACHINE = $false
            RECEIVING_BOUNDARY_00_SKILLSMACHINE = 'ABSENT'
            PROPOSAL_STATUS = $status
            LATEST_PROPOSAL_ID = $proposalId
            OBSERVED_HEAD = $ObservedHead
        }
    }
    else {
        function Set-EProp([object]$O, [string]$N, $V) {
            if ($O.PSObject.Properties.Name -contains $N) { $O.$N = $V }
            else { $O | Add-Member -NotePropertyName $N -NotePropertyValue $V }
        }
        Set-EProp $existing 'ENROLMENT_STATUS' 'NOT_ENROLLED'
        Set-EProp $existing 'PROPOSAL_STATUS' $status
        Set-EProp $existing 'LATEST_PROPOSAL_ID' $proposalId
        Set-EProp $existing 'LAST_OBSERVED_AT' (Get-ProjectOpsUtcNow)
        Set-EProp $existing 'ATTENTION' 'ENROLMENT_PROPOSAL_READY'
        Set-EProp $existing 'PROJECT_SYNC_STATUS' 'UNKNOWN'
        Set-EProp $existing 'OBSERVED_HEAD' $ObservedHead
        Set-EProp $existing 'EXPLICITLY_ENROLLED_IN_SKILLSMACHINE' $false
        Set-EProp $existing 'PROJECT_ROOT_IDENTITY' $ProjectRootIdentity
    }
    [void](Upsert-ProjectRegistryEntry -Entry $existing -OpsRoot $OpsRoot)

    return [pscustomobject]@{
        proposal = $proposal
        proposal_path = $path
        registry_enrolment_status = 'NOT_ENROLLED'
        auto_enrolled = $false
    }
}

function New-NewProjectEnrolmentProposal {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectId,
        [Parameter(Mandatory = $true)][string]$ProjectRootIdentity,
        [string]$OpsRoot = (Get-ProjectOpsRoot),
        [switch]$ReadyForReview
    )
    $proposalId = New-EnrolmentProposalId -ProjectId $ProjectId
    $status = if ($ReadyForReview) { 'READY_FOR_REVIEW' } else { 'DRAFT' }
    $proposal = [pscustomobject]@{
        schema_version = '0.2.0'
        source = 'MB-SM-076A3'
        PROPOSAL_ID = $proposalId
        PROJECT_ID = $ProjectId
        PROJECT_CLASS = 'NEW_PROJECT'
        ENROLMENT_METHOD = 'NEW_PROJECT'
        PROPOSAL_STATUS = $status
        HUMAN_APPROVAL = 'REQUIRED_NOT_GRANTED'
        HUMAN_DECISION_REQUIRED = $true
        AUTO_ENROL = $false
        created_at = (Get-ProjectOpsUtcNow)
        updated_at = (Get-ProjectOpsUtcNow)
        PROJECT_ROOT_IDENTITY = $ProjectRootIdentity
        NON_MUTATION_STATEMENT = 'Proposal only. Project surface creation requires separate human/target authorization.'
    }
    $path = Save-EnrolmentProposal -Proposal $proposal -OpsRoot $OpsRoot
    return [pscustomobject]@{ proposal = $proposal; proposal_path = $path; auto_enrolled = $false }
}

function Set-EnrolmentObjectProperty {
    param(
        [Parameter(Mandatory = $true)]$Object,
        [Parameter(Mandatory = $true)][string]$Name,
        $Value
    )
    if ($Object.PSObject.Properties.Name -contains $Name) {
        $Object.$Name = $Value
    }
    else {
        $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
    }
}

function Approve-EnrolmentProposal {
    param(
        [Parameter(Mandatory = $true)][string]$ProposalId,
        [Parameter(Mandatory = $true)][ValidateSet('APPROVE', 'REJECT')][string]$HumanDecision,
        [Parameter(Mandatory = $true)][string]$AuthorizationSource,
        [string]$ApprovedBy = 'HUMAN',
        [switch]$ApplySkillsMachineEnrolment,
        [string]$OpsRoot = (Get-ProjectOpsRoot)
    )

    $proposal = Get-EnrolmentProposal -ProposalId $ProposalId -OpsRoot $OpsRoot
    if ($null -eq $proposal) {
        throw ("ENROLMENT_PROPOSAL_NOT_FOUND: {0}" -f $ProposalId)
    }

    $currentStatus = [string]$proposal.PROPOSAL_STATUS
    if ($currentStatus -notin @('READY_FOR_REVIEW', 'APPROVED')) {
        throw ("ENROLMENT_PROPOSAL_NOT_APPROVABLE: {0}" -f $currentStatus)
    }

    if ($HumanDecision -eq 'REJECT') {
        Set-EnrolmentObjectProperty $proposal 'PROPOSAL_STATUS' 'REJECTED'
        Set-EnrolmentObjectProperty $proposal 'HUMAN_APPROVAL' 'EXPLICIT'
        Set-EnrolmentObjectProperty $proposal 'HUMAN_DECISION' 'REJECT'
        Set-EnrolmentObjectProperty $proposal 'HUMAN_APPROVER' $ApprovedBy
        Set-EnrolmentObjectProperty $proposal 'AUTHORIZATION_SOURCE' $AuthorizationSource
        Set-EnrolmentObjectProperty $proposal 'HUMAN_DECISION_REQUIRED' $false
        Set-EnrolmentObjectProperty $proposal 'updated_at' (Get-ProjectOpsUtcNow)
        $path = Save-EnrolmentProposal -Proposal $proposal -OpsRoot $OpsRoot
        $entry = Get-ProjectRegistryEntry -ProjectId ([string]$proposal.PROJECT_ID) -OpsRoot $OpsRoot
        if ($null -ne $entry) {
            Set-EnrolmentObjectProperty $entry 'PROPOSAL_STATUS' 'REJECTED'
            Set-EnrolmentObjectProperty $entry 'ATTENTION' 'ENROLMENT_REJECTED'
            [void](Upsert-ProjectRegistryEntry -Entry $entry -OpsRoot $OpsRoot)
        }
        return [pscustomobject]@{
            ok = $true
            proposal = $proposal
            proposal_path = $path
            enrolled = $false
            EXTERNAL_PROJECT_MUTATION = 'NO'
        }
    }

    Set-EnrolmentObjectProperty $proposal 'HUMAN_APPROVAL' 'EXPLICIT'
    Set-EnrolmentObjectProperty $proposal 'HUMAN_DECISION' 'APPROVE'
    Set-EnrolmentObjectProperty $proposal 'HUMAN_APPROVER' $ApprovedBy
    Set-EnrolmentObjectProperty $proposal 'AUTHORIZATION_SOURCE' $AuthorizationSource
    Set-EnrolmentObjectProperty $proposal 'HUMAN_DECISION_REQUIRED' $false
    Set-EnrolmentObjectProperty $proposal 'updated_at' (Get-ProjectOpsUtcNow)
    Set-EnrolmentObjectProperty $proposal 'PROPOSAL_STATUS' 'APPROVED'
    Set-EnrolmentObjectProperty $proposal 'EXTERNAL_PROJECT_MUTATION' 'NO'

    $path = Save-EnrolmentProposal -Proposal $proposal -OpsRoot $OpsRoot
    $enrolled = $false
    $entry = Get-ProjectRegistryEntry -ProjectId ([string]$proposal.PROJECT_ID) -OpsRoot $OpsRoot

    if ($ApplySkillsMachineEnrolment) {
        if ($null -eq $entry) {
            throw ("ENROLMENT_REGISTRY_ENTRY_MISSING: {0}" -f [string]$proposal.PROJECT_ID)
        }
        $caps = @()
        if ($proposal.PSObject.Properties.Name -contains 'PROPOSED_CAPABILITIES') {
            $caps = @($proposal.PROPOSED_CAPABILITIES)
        }
        $baseline = if ($caps.Count -gt 0) { ($caps -join '; ') } else { [string]$entry.CAPABILITY_BASELINE }
        $ifEnabled = $false
        if ($proposal.PSObject.Properties.Name -contains 'IMPROVEMENT_FLOW_ENABLED_PROPOSED') {
            $ifEnabled = [bool]$proposal.IMPROVEMENT_FLOW_ENABLED_PROPOSED
        }
        $psEnabled = $false
        if ($proposal.PSObject.Properties.Name -contains 'PROJECT_SYNC_ENABLED_PROPOSED') {
            $psEnabled = [bool]$proposal.PROJECT_SYNC_ENABLED_PROPOSED
        }

        Set-EnrolmentObjectProperty $entry 'ENROLMENT_STATUS' 'ENROLLED'
        Set-EnrolmentObjectProperty $entry 'ENROLMENT_METHOD' ([string]$proposal.ENROLMENT_METHOD)
        Set-EnrolmentObjectProperty $entry 'ENROLLED_AT' (Get-ProjectOpsUtcNow)
        Set-EnrolmentObjectProperty $entry 'EXPLICITLY_ENROLLED_IN_SKILLSMACHINE' $true
        Set-EnrolmentObjectProperty $entry 'IMPROVEMENT_FLOW_ENABLED' $ifEnabled
        Set-EnrolmentObjectProperty $entry 'PROJECT_SYNC_ENABLED' $psEnabled
        Set-EnrolmentObjectProperty $entry 'PROJECT_CLASS' 'ENROLLED_PROJECT'
        Set-EnrolmentObjectProperty $entry 'CAPABILITY_BASELINE' $baseline
        Set-EnrolmentObjectProperty $entry 'PROPOSAL_STATUS' 'APPLIED'
        Set-EnrolmentObjectProperty $entry 'LATEST_PROPOSAL_ID' ([string]$proposal.PROPOSAL_ID)
        Set-EnrolmentObjectProperty $entry 'LAST_OBSERVED_AT' (Get-ProjectOpsUtcNow)
        Set-EnrolmentObjectProperty $entry 'PROJECT_SYNC_STATUS' 'UNKNOWN'
        $surface = 'ABSENT'
        if ($entry.PSObject.Properties.Name -contains 'RECEIVING_BOUNDARY_00_SKILLSMACHINE') {
            $surface = [string]$entry.RECEIVING_BOUNDARY_00_SKILLSMACHINE
        }
        if ($surface -eq 'ABSENT') {
            Set-EnrolmentObjectProperty $entry 'ATTENTION' 'RECEIVING_BOUNDARY_ABSENT'
        }
        else {
            Set-EnrolmentObjectProperty $entry 'ATTENTION' 'NONE'
        }
        [void](Upsert-ProjectRegistryEntry -Entry $entry -OpsRoot $OpsRoot)

        Set-EnrolmentObjectProperty $proposal 'PROPOSAL_STATUS' 'APPLIED'
        Set-EnrolmentObjectProperty $proposal 'CURRENT_INTEGRATION_STATUS' 'ENROLLED'
        $flow = @()
        if ($proposal.PSObject.Properties.Name -contains 'FLOW') { $flow = @($proposal.FLOW) }
        if ($flow -notcontains 'HUMAN_APPROVED') { $flow += 'HUMAN_APPROVED' }
        if ($flow -notcontains 'SM_SIDE_ENROLLED') { $flow += 'SM_SIDE_ENROLLED' }
        Set-EnrolmentObjectProperty $proposal 'FLOW' $flow
        $path = Save-EnrolmentProposal -Proposal $proposal -OpsRoot $OpsRoot
        $enrolled = $true
    }
    elseif ($null -ne $entry) {
        Set-EnrolmentObjectProperty $entry 'PROPOSAL_STATUS' 'APPROVED'
        Set-EnrolmentObjectProperty $entry 'ATTENTION' 'ENROLMENT_APPROVED_NOT_APPLIED'
        [void](Upsert-ProjectRegistryEntry -Entry $entry -OpsRoot $OpsRoot)
    }

    return [pscustomobject]@{
        ok = $true
        proposal = $proposal
        proposal_path = $path
        enrolled = $enrolled
        enrolment_status = $(if ($enrolled) { 'ENROLLED' } else { 'NOT_ENROLLED' })
        EXTERNAL_PROJECT_MUTATION = 'NO'
    }
}
