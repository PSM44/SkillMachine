#Requires -Version 5.1
# Protocol-neutral AI access runtime — MB-SM-076A3

function Get-AiOperationClassification {
    param([Parameter(Mandatory = $true)][string]$Operation)
    switch ($Operation) {
        'GET_STATUS' { return 'READ_ONLY' }
        'LIST_PROJECTS' { return 'READ_ONLY' }
        'GET_PROJECT_STATUS' { return 'READ_ONLY' }
        'GET_ENROLMENT_PROPOSAL' { return 'READ_ONLY' }
        'LIST_ATTENTION_ITEMS' { return 'READ_ONLY' }
        'LIST_SKILLS' { return 'READ_ONLY' }
        'SEARCH_SKILLS' { return 'READ_ONLY' }
        'GET_SKILL' { return 'READ_ONLY' }
        'GET_IMPROVEMENT_FLOW_STATUS' { return 'READ_ONLY' }
        'REQUEST_PROJECT_SYNC_REVIEW' { return 'PROPOSAL' }
        'SUBMIT_IMPROVEMENT_OPPORTUNITY' { return 'STATE_CHANGE' }
        default { return 'UNKNOWN' }
    }
}

function Invoke-SkillsMachineAiAccess {
    param(
        [Parameter(Mandatory = $true)][string]$Operation,
        [Parameter(Mandatory = $true)][string]$CallerType,
        [string]$CallerProject = 'UNKNOWN',
        [string]$AuthorizationContext = 'NONE',
        [string]$CorrelationId = (New-ProjectOpsCorrelationId),
        [hashtable]$Args = @{},
        [string]$OpsRoot = (Get-ProjectOpsRoot),
        [string]$SkillsRoot = (Join-Path (Split-Path (Split-Path (Split-Path (Get-ProjectOpsRoot) -Parent) -Parent) -Parent) 'SkillsLake\01.SKILLS')
    )

    $class = Get-AiOperationClassification -Operation $Operation
    if ($class -eq 'UNKNOWN') {
        return [pscustomobject]@{ ok = $false; error = 'UNKNOWN_OPERATION'; classification = $class }
    }

    $meta = [pscustomobject]@{
        CALLER_TYPE = $CallerType
        CALLER_PROJECT = $CallerProject
        REQUESTED_ACTION = $Operation
        AUTHORIZATION_CONTEXT = $AuthorizationContext
        CORRELATION_ID = $CorrelationId
        classification = $class
        protocol = 'PROTOCOL_NEUTRAL'
    }

    switch ($Operation) {
        'GET_STATUS' {
            $home = Get-ProjectHomeViewFromRegistry -OpsRoot $OpsRoot
            return [pscustomobject]@{ ok = $true; meta = $meta; result = @{ projects = $home.projects.Count; attention = $home.needs_your_attention.Count } }
        }
        'LIST_PROJECTS' {
            $reg = Read-ProjectRegistry -OpsRoot $OpsRoot
            return [pscustomobject]@{ ok = $true; meta = $meta; result = @($reg.projects) }
        }
        'GET_PROJECT_STATUS' {
            $pid = [string]$Args['ProjectId']
            $entry = Get-ProjectRegistryEntry -ProjectId $pid -OpsRoot $OpsRoot
            return [pscustomobject]@{ ok = ($null -ne $entry); meta = $meta; result = $entry }
        }
        'GET_ENROLMENT_PROPOSAL' {
            $pid = [string]$Args['ProjectId']
            $prop = Get-LatestEnrolmentProposalForProject -ProjectId $pid -OpsRoot $OpsRoot
            return [pscustomobject]@{ ok = ($null -ne $prop); meta = $meta; result = $prop }
        }
        'LIST_ATTENTION_ITEMS' {
            $home = Get-ProjectHomeViewFromRegistry -OpsRoot $OpsRoot
            return [pscustomobject]@{ ok = $true; meta = $meta; result = $home.needs_your_attention }
        }
        'LIST_SKILLS' {
            $files = @()
            if (Test-Path -LiteralPath $SkillsRoot) {
                $files = @(Get-ChildItem -LiteralPath $SkillsRoot -Filter 'SKILL.*.txt' | Select-Object -ExpandProperty Name)
            }
            return [pscustomobject]@{ ok = $true; meta = $meta; result = $files }
        }
        'SEARCH_SKILLS' {
            $q = [string]$Args['Query']
            $files = @()
            if (Test-Path -LiteralPath $SkillsRoot) {
                $files = @(Get-ChildItem -LiteralPath $SkillsRoot -Filter 'SKILL.*.txt' | Where-Object { $_.Name -match [regex]::Escape($q) } | Select-Object -ExpandProperty Name)
            }
            return [pscustomobject]@{ ok = $true; meta = $meta; result = $files }
        }
        'GET_SKILL' {
            $name = [string]$Args['SkillFile']
            $path = Join-Path $SkillsRoot $name
            if (-not (Test-Path -LiteralPath $path)) {
                return [pscustomobject]@{ ok = $false; meta = $meta; error = 'SKILL_NOT_FOUND' }
            }
            $text = Get-Content -LiteralPath $path -Raw -Encoding UTF8
            return [pscustomobject]@{ ok = $true; meta = $meta; result = @{ path = $path; preview = $text.Substring(0, [Math]::Min(500, $text.Length)) } }
        }
        'GET_IMPROVEMENT_FLOW_STATUS' {
            $pid = [string]$Args['ProjectId']
            $entry = Get-ProjectRegistryEntry -ProjectId $pid -OpsRoot $OpsRoot
            $acc = $null
            try { $acc = Read-ActiveAccumulator -OpsRoot $OpsRoot } catch { }
            return [pscustomobject]@{
                ok = $true
                meta = $meta
                result = @{
                    project_status = $(if ($entry) { [string]$entry.IMPROVEMENT_FLOW_STATUS } else { 'UNKNOWN' })
                    accumulator_count = $(if ($acc) { @($acc.opportunities).Count } else { 0 })
                }
            }
        }
        'REQUEST_PROJECT_SYNC_REVIEW' {
            # PROPOSAL only — prepare eligibility check result, no apply
            $pid = [string]$Args['ProjectId']
            $pkg = [string]$Args['PackageId']
            $check = Test-ProjectSyncDeliveryEligibility -TargetProject $pid -PackageId $pkg -OpsRoot $OpsRoot
            return [pscustomobject]@{ ok = $true; meta = $meta; result = $check; HUMAN_APPROVAL_REQUIRED = $true }
        }
        'SUBMIT_IMPROVEMENT_OPPORTUNITY' {
            $result = New-ImprovementFlowSubmissionPackage `
                -SourceProject ([string]$Args['SourceProject']) `
                -OpportunityId ([string]$Args['OpportunityId']) `
                -EvidenceRefs @($Args['EvidenceRefs']) `
                -TargetSkillGrc ([string]$Args['TargetSkillGrc']) `
                -CorrelationId $CorrelationId `
                -PayloadText ([string]$Args['PayloadText']) `
                -OpsRoot $OpsRoot
            return [pscustomobject]@{ ok = [bool]$result.ok; meta = $meta; result = $result; classification_note = 'STATE_CHANGE; consequential canon mutation still HUMAN_APPROVAL_REQUIRED' }
        }
    }
}
