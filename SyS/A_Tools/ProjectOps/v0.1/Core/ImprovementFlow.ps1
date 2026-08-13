#Requires -Version 5.1
# Real-project Improvement Flow intake / receipt / accumulator / disposition — MB-SM-076A3

function Get-ImprovementFlowRoot {
    param([string]$OpsRoot = (Get-ProjectOpsRoot))
    return (Join-Path (Get-ProjectOpsStateRoot -OpsRoot $OpsRoot) 'ImprovementFlow')
}

function Get-IfSubmissionsDir { param([string]$OpsRoot = (Get-ProjectOpsRoot)) Join-Path (Get-ImprovementFlowRoot -OpsRoot $OpsRoot) 'Submissions' }
function Get-IfReceiptsDir { param([string]$OpsRoot = (Get-ProjectOpsRoot)) Join-Path (Get-ImprovementFlowRoot -OpsRoot $OpsRoot) 'Receipts' }
function Get-IfAccumulatorPath { param([string]$OpsRoot = (Get-ProjectOpsRoot)) Join-Path (Get-ImprovementFlowRoot -OpsRoot $OpsRoot) 'ACCUMULATOR.ACTIVE.json' }
function Get-IfArchiveDir { param([string]$OpsRoot = (Get-ProjectOpsRoot)) Join-Path (Get-ImprovementFlowRoot -OpsRoot $OpsRoot) 'Archive' }
function Get-IfDispositionsDir { param([string]$OpsRoot = (Get-ProjectOpsRoot)) Join-Path (Get-ImprovementFlowRoot -OpsRoot $OpsRoot) 'Dispositions' }

function Initialize-ImprovementFlowState {
    param([string]$OpsRoot = (Get-ProjectOpsRoot))
    foreach ($d in @(
            (Get-IfSubmissionsDir -OpsRoot $OpsRoot),
            (Get-IfReceiptsDir -OpsRoot $OpsRoot),
            (Get-IfArchiveDir -OpsRoot $OpsRoot),
            (Get-IfDispositionsDir -OpsRoot $OpsRoot)
        )) {
        if (-not (Test-Path -LiteralPath $d)) {
            New-Item -ItemType Directory -Path $d -Force | Out-Null
        }
    }
    $accPath = Get-IfAccumulatorPath -OpsRoot $OpsRoot
    if (-not (Test-Path -LiteralPath $accPath)) {
        $acc = [pscustomobject]@{
            schema_version = '0.2.0'
            ACCUMULATOR_ID = 'ACC-ACTIVE-001'
            status = 'ACTIVE'
            created_at = (Get-ProjectOpsUtcNow)
            updated_at = (Get-ProjectOpsUtcNow)
            last_receipt_id = $null
            opportunities = @()
        }
        Write-ProjectOpsUtf8NoBom -Path $accPath -Content (ConvertTo-ProjectOpsJson -Object $acc)
    }
}

function Test-SourceProjectEligibleForIf {
    param(
        [Parameter(Mandatory = $true)][string]$SourceProject,
        [string]$OpsRoot = (Get-ProjectOpsRoot)
    )
    $entry = Get-ProjectRegistryEntry -ProjectId $SourceProject -OpsRoot $OpsRoot
    if ($null -eq $entry) {
        return [pscustomobject]@{ Eligible = $false; Reason = 'UNKNOWN_SOURCE_PROJECT' }
    }
    if ([string]$entry.ENROLMENT_STATUS -ne 'ENROLLED') {
        return [pscustomobject]@{ Eligible = $false; Reason = 'SOURCE_NOT_ENROLLED' }
    }
    if (-not [bool]$entry.IMPROVEMENT_FLOW_ENABLED) {
        return [pscustomobject]@{ Eligible = $false; Reason = 'IMPROVEMENT_FLOW_DISABLED' }
    }
    return [pscustomobject]@{ Eligible = $true; Reason = 'ENROLLED_IF_ENABLED' }
}

function Get-DeterministicSubmissionId {
    param(
        [Parameter(Mandatory = $true)][string]$SourceProject,
        [Parameter(Mandatory = $true)][string]$OpportunityId,
        [Parameter(Mandatory = $true)][string]$ContentSha256
    )
    $material = '{0}|{1}|{2}' -f $SourceProject, $OpportunityId, $ContentSha256.ToUpperInvariant()
    $hash = Get-ProjectOpsSha256Text -Text $material
    return ('SUB-{0}' -f $hash.Substring(0, 24))
}

function New-ImprovementFlowSubmissionPackage {
    param(
        [Parameter(Mandatory = $true)][string]$SourceProject,
        [Parameter(Mandatory = $true)][string]$OpportunityId,
        [Parameter(Mandatory = $true)][string[]]$EvidenceRefs,
        [Parameter(Mandatory = $true)][string]$TargetSkillGrc,
        [string]$CorrelationId = (New-ProjectOpsCorrelationId),
        [string]$PayloadText = '',
        [string]$OpsRoot = (Get-ProjectOpsRoot)
    )

    Initialize-ImprovementFlowState -OpsRoot $OpsRoot
    $elig = Test-SourceProjectEligibleForIf -SourceProject $SourceProject -OpsRoot $OpsRoot
    if (-not [bool]$elig.Eligible) {
        return [pscustomobject]@{
            ok = $false
            FAILURE_STATE = [string]$elig.Reason
            STATUS = 'INVALID_FORM'
        }
    }

    if ([string]::IsNullOrWhiteSpace($OpportunityId)) {
        return [pscustomobject]@{ ok = $false; FAILURE_STATE = 'INVALID_FORM'; STATUS = 'INVALID_FORM' }
    }
    if ($null -eq $EvidenceRefs -or @($EvidenceRefs).Count -eq 0) {
        return [pscustomobject]@{ ok = $false; FAILURE_STATE = 'MISSING_PROVENANCE'; STATUS = 'INVALID_FORM' }
    }

    $body = [ordered]@{
        source_project = $SourceProject
        opportunity_id = $OpportunityId
        evidence_refs = @($EvidenceRefs)
        target_skill_grc = $TargetSkillGrc
        payload_text = $PayloadText
    }
    $contentSha = Get-ProjectOpsSha256Text -Text (($body | ConvertTo-Json -Compress -Depth 10))
    $submissionId = Get-DeterministicSubmissionId -SourceProject $SourceProject -OpportunityId $OpportunityId -ContentSha256 $contentSha

    $submission = [pscustomobject]@{
        schema_version = '0.2.0'
        message_type = 'OPPORTUNITY_SUBMISSION'
        SUBMISSION_ID = $submissionId
        SOURCE_PROJECT = $SourceProject
        OPPORTUNITY_ID = $OpportunityId
        CORRELATION_ID = $CorrelationId
        EVIDENCE_REFS = @($EvidenceRefs)
        TARGET_SKILL_GRC = $TargetSkillGrc
        content_sha256 = $contentSha
        STATUS = 'SUBMITTED'
        created_at = (Get-ProjectOpsUtcNow)
        payload = [pscustomobject]@{
            source_project = $SourceProject
            opportunity_id = $OpportunityId
            evidence_refs = @($EvidenceRefs)
            target_skill_grc = $TargetSkillGrc
            correlation_id = $CorrelationId
            payload_text = $PayloadText
        }
    }

    $subPath = Join-Path (Get-IfSubmissionsDir -OpsRoot $OpsRoot) ("{0}.json" -f $submissionId)
    $existingReceipt = Get-ImprovementFlowReceipt -SubmissionId $submissionId -OpsRoot $OpsRoot
    if ($null -ne $existingReceipt -and [string]$existingReceipt.content_sha256 -eq $contentSha) {
        return [pscustomobject]@{
            ok = $true
            idempotent = $true
            submission = $submission
            receipt = $existingReceipt
            STATUS = 'RECEIVED'
            FAILURE_STATE = $null
        }
    }

    Write-ProjectOpsUtf8NoBom -Path $subPath -Content (ConvertTo-ProjectOpsJson -Object $submission)
    $receipt = New-ImprovementFlowReceipt -Submission $submission -OpsRoot $OpsRoot
    [void](Add-OpportunityToAccumulator -Submission $submission -Receipt $receipt -OpsRoot $OpsRoot)

    return [pscustomobject]@{
        ok = $true
        idempotent = $false
        submission = $submission
        receipt = $receipt
        STATUS = 'RECEIVED'
        FAILURE_STATE = $null
        submission_path = $subPath
    }
}

function New-ImprovementFlowReceipt {
    param(
        [Parameter(Mandatory = $true)]$Submission,
        [string]$OpsRoot = (Get-ProjectOpsRoot)
    )
    $receiptId = ('RCPT-{0}' -f [string]$Submission.SUBMISSION_ID)
    $receiptBody = [ordered]@{
        schema_version = '0.2.0'
        message_type = 'SUBMISSION_RECEIPT'
        RECEIPT_ID = $receiptId
        SUBMISSION_ID = [string]$Submission.SUBMISSION_ID
        SOURCE_PROJECT = [string]$Submission.SOURCE_PROJECT
        OPPORTUNITY_ID = [string]$Submission.OPPORTUNITY_ID
        CORRELATION_ID = [string]$Submission.CORRELATION_ID
        accepted_ids = @([string]$Submission.OPPORTUNITY_ID)
        form_rejects = @()
        partial_acceptance = 'NO'
        content_sha256 = [string]$Submission.content_sha256
        received_at = (Get-ProjectOpsUtcNow)
        STATUS = 'RECEIVED'
        NOTE = 'Receipt acknowledges form only; NOT a disposition'
    }
    $hashMaterial = ($receiptBody | ConvertTo-Json -Compress -Depth 10)
    $receiptBody['receipt_hash'] = Get-ProjectOpsSha256Text -Text $hashMaterial
    $receipt = [pscustomobject]$receiptBody
    $path = Join-Path (Get-IfReceiptsDir -OpsRoot $OpsRoot) ("{0}.json" -f $receiptId)
    Write-ProjectOpsUtf8NoBom -Path $path -Content (ConvertTo-ProjectOpsJson -Object $receipt)

    $entry = Get-ProjectRegistryEntry -ProjectId ([string]$Submission.SOURCE_PROJECT) -OpsRoot $OpsRoot
    if ($null -ne $entry) {
        $entry.LAST_RECEIPT_ID = $receiptId
        $entry.IMPROVEMENT_FLOW_STATUS = 'RECEIVED'
        $entry.LAST_OBSERVED_AT = Get-ProjectOpsUtcNow
        [void](Upsert-ProjectRegistryEntry -Entry $entry -OpsRoot $OpsRoot)
    }
    return $receipt
}

function Get-ImprovementFlowReceipt {
    param(
        [Parameter(Mandatory = $true)][string]$SubmissionId,
        [string]$OpsRoot = (Get-ProjectOpsRoot)
    )
    $receiptId = ('RCPT-{0}' -f $SubmissionId)
    $path = Join-Path (Get-IfReceiptsDir -OpsRoot $OpsRoot) ("{0}.json" -f $receiptId)
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    return (Read-ProjectOpsJson -Path $path)
}

function Read-ActiveAccumulator {
    param([string]$OpsRoot = (Get-ProjectOpsRoot))
    Initialize-ImprovementFlowState -OpsRoot $OpsRoot
    return (Read-ProjectOpsJson -Path (Get-IfAccumulatorPath -OpsRoot $OpsRoot))
}

function Add-OpportunityToAccumulator {
    param(
        [Parameter(Mandatory = $true)]$Submission,
        [Parameter(Mandatory = $true)]$Receipt,
        [string]$OpsRoot = (Get-ProjectOpsRoot)
    )
    $acc = Read-ActiveAccumulator -OpsRoot $OpsRoot
    $opps = New-Object System.Collections.Generic.List[object]
    foreach ($o in @($acc.opportunities)) {
        if ([string]$o.OPPORTUNITY_ID -eq [string]$Submission.OPPORTUNITY_ID -and [string]$o.content_sha256 -eq [string]$Submission.content_sha256) {
            # duplicate content — keep existing, no second write
            return $acc
        }
        [void]$opps.Add($o)
    }
    [void]$opps.Add([pscustomobject]@{
            OPPORTUNITY_ID = [string]$Submission.OPPORTUNITY_ID
            SOURCE_PROJECT = [string]$Submission.SOURCE_PROJECT
            SUBMISSION_ID = [string]$Submission.SUBMISSION_ID
            RECEIPT_ID = [string]$Receipt.RECEIPT_ID
            CORRELATION_ID = [string]$Submission.CORRELATION_ID
            TARGET_SKILL_GRC = [string]$Submission.TARGET_SKILL_GRC
            content_sha256 = [string]$Submission.content_sha256
            EVIDENCE_REFS = @($Submission.EVIDENCE_REFS)
            STATUS = 'RECEIVED'
            DISPOSITION = $null
            added_at = (Get-ProjectOpsUtcNow)
        })
    $acc.opportunities = @($opps.ToArray())
    $acc.last_receipt_id = [string]$Receipt.RECEIPT_ID
    $acc.updated_at = Get-ProjectOpsUtcNow
    Write-ProjectOpsUtf8NoBom -Path (Get-IfAccumulatorPath -OpsRoot $OpsRoot) -Content (ConvertTo-ProjectOpsJson -Object $acc)
    return $acc
}

function Invoke-AccumulatorRotation {
    param(
        [Parameter(Mandatory = $true)][string]$ReceiptId,
        [string]$OpsRoot = (Get-ProjectOpsRoot)
    )
    $acc = Read-ActiveAccumulator -OpsRoot $OpsRoot
    if ([string]::IsNullOrWhiteSpace($ReceiptId)) {
        throw 'NO_ROTATION_WITHOUT_VALID_RECEIPT'
    }
    $receiptPath = Join-Path (Get-IfReceiptsDir -OpsRoot $OpsRoot) ("{0}.json" -f $ReceiptId)
    if (-not (Test-Path -LiteralPath $receiptPath)) {
        throw 'NO_ROTATION_WITHOUT_VALID_RECEIPT'
    }
    if ([string]$acc.last_receipt_id -ne $ReceiptId -and @($acc.opportunities | Where-Object { $_.RECEIPT_ID -eq $ReceiptId }).Count -eq 0) {
        throw 'NO_ROTATION_WITHOUT_VALID_RECEIPT'
    }

    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $archivePath = Join-Path (Get-IfArchiveDir -OpsRoot $OpsRoot) ("ACCUMULATOR.{0}.{1}.json" -f [string]$acc.ACCUMULATOR_ID, $stamp)
    Write-ProjectOpsUtf8NoBom -Path $archivePath -Content (ConvertTo-ProjectOpsJson -Object $acc)

    $newAcc = [pscustomobject]@{
        schema_version = '0.2.0'
        ACCUMULATOR_ID = ('ACC-ACTIVE-{0}' -f $stamp)
        status = 'ACTIVE'
        created_at = (Get-ProjectOpsUtcNow)
        updated_at = (Get-ProjectOpsUtcNow)
        last_receipt_id = $ReceiptId
        rotated_from = [string]$acc.ACCUMULATOR_ID
        rotation_receipt_id = $ReceiptId
        opportunities = @()
    }
    Write-ProjectOpsUtf8NoBom -Path (Get-IfAccumulatorPath -OpsRoot $OpsRoot) -Content (ConvertTo-ProjectOpsJson -Object $newAcc)
    return [pscustomobject]@{ archived = $archivePath; active = $newAcc }
}

function New-ImprovementFlowDisposition {
    param(
        [Parameter(Mandatory = $true)][string]$OpportunityId,
        [Parameter(Mandatory = $true)][string]$SubmissionId,
        [Parameter(Mandatory = $true)][ValidateSet('IMPROVE_EXISTING', 'MERGE', 'CREATE', 'REJECT', 'DEFER', 'PROJECT_LOCAL', 'NEEDS_HUMAN_DECISION')]
        [string]$Decision,
        [string]$Rationale = '',
        [string]$RecommendedBy = 'SYSTEM',
        [string]$TargetSkillGrc = '',
        [string]$SupersedesDispositionId = '',
        [switch]$HumanConfirmed,
        [string]$OpsRoot = (Get-ProjectOpsRoot)
    )

    if ($Decision -in @('IMPROVE_EXISTING', 'MERGE', 'CREATE') -and -not $HumanConfirmed) {
        # May recommend but not silently approve consequential path
        $Decision = 'NEEDS_HUMAN_DECISION'
        if ([string]::IsNullOrWhiteSpace($Rationale)) {
            $Rationale = 'Consequential disposition requires explicit human confirmation'
        }
    }

    $receipt = Get-ImprovementFlowReceipt -SubmissionId $SubmissionId -OpsRoot $OpsRoot
    if ($null -eq $receipt) {
        throw 'DISPOSITION_REQUIRES_RECEIPT'
    }

    $accLookup = Read-ActiveAccumulator -OpsRoot $OpsRoot
    if ([string]::IsNullOrWhiteSpace($TargetSkillGrc)) {
        $matchOpp = @($accLookup.opportunities | Where-Object { [string]$_.OPPORTUNITY_ID -eq $OpportunityId } | Select-Object -First 1)
        if ($matchOpp.Count -gt 0) {
            $candidate = $matchOpp[0]
            if ($candidate.PSObject.Properties.Name -contains 'TARGET_SKILL_GRC') {
                $TargetSkillGrc = [string]$candidate.TARGET_SKILL_GRC
            }
        }
    }

    $stamp = Get-Date -Format 'yyyyMMddHHmmss'
    $dispId = ('DISP-{0}-{1}' -f $OpportunityId, $stamp)
    $dispDir = Get-IfDispositionsDir -OpsRoot $OpsRoot
    $path = Join-Path $dispDir ("{0}.json" -f $dispId)
    $suffix = 0
    while (Test-Path -LiteralPath $path) {
        $suffix++
        $dispId = ('DISP-{0}-{1}-{2:D2}' -f $OpportunityId, $stamp, $suffix)
        $path = Join-Path $dispDir ("{0}.json" -f $dispId)
    }
    $disp = [pscustomobject]@{
        schema_version = '0.2.0'
        DISPOSITION_ID = $dispId
        OPPORTUNITY_ID = $OpportunityId
        SUBMISSION_ID = $SubmissionId
        RECEIPT_ID = [string]$receipt.RECEIPT_ID
        DECISION = $Decision
        TARGET_SKILL_GRC = $TargetSkillGrc
        SUPERSEDES_DISPOSITION_ID = $(if ([string]::IsNullOrWhiteSpace($SupersedesDispositionId)) { $null } else { $SupersedesDispositionId })
        RECOMMENDED_BY = $RecommendedBy
        HUMAN_CONFIRMED = [bool]$HumanConfirmed
        SILENT_APPROVAL = $false
        rationale = $Rationale
        decided_at = (Get-ProjectOpsUtcNow)
        NOTE = 'Disposition is separate from receipt; capability mutation remains separately governed. Prior disposition files are retained.'
    }
    Write-ProjectOpsUtf8NoBom -Path $path -Content (ConvertTo-ProjectOpsJson -Object $disp)

    $acc = Read-ActiveAccumulator -OpsRoot $OpsRoot
    $updated = @()
    foreach ($o in @($acc.opportunities)) {
        if ([string]$o.OPPORTUNITY_ID -eq $OpportunityId) {
            $o | Add-Member -NotePropertyName DISPOSITION -NotePropertyValue $Decision -Force
            $o | Add-Member -NotePropertyName STATUS -NotePropertyValue $(if ($Decision -eq 'NEEDS_HUMAN_DECISION') { 'NEEDS_DECISION' } else { 'UNDER_REVIEW' }) -Force
            $o | Add-Member -NotePropertyName LATEST_DISPOSITION_ID -NotePropertyValue $dispId -Force
            if (-not [string]::IsNullOrWhiteSpace($TargetSkillGrc)) {
                $o | Add-Member -NotePropertyName TARGET_SKILL_GRC -NotePropertyValue $TargetSkillGrc -Force
            }
        }
        $updated += $o
    }
    $acc.opportunities = $updated
    $acc.updated_at = Get-ProjectOpsUtcNow
    Write-ProjectOpsUtf8NoBom -Path (Get-IfAccumulatorPath -OpsRoot $OpsRoot) -Content (ConvertTo-ProjectOpsJson -Object $acc)

    return $disp
}
