#Requires -Version 5.1
# Project Sync delivery preparation — MB-SM-076A3
# Prepares delivery records only; never mutates target projects.

function Get-ProjectSyncPrepDir {
    param([string]$OpsRoot = (Get-ProjectOpsRoot))
    return (Join-Path (Get-ProjectOpsStateRoot -OpsRoot $OpsRoot) 'ProjectSync')
}

function Test-ProjectSyncDeliveryEligibility {
    param(
        [Parameter(Mandatory = $true)][string]$TargetProject,
        [Parameter(Mandatory = $true)][string]$PackageId,
        [string]$OpsRoot = (Get-ProjectOpsRoot)
    )

    $entry = Get-ProjectRegistryEntry -ProjectId $TargetProject -OpsRoot $OpsRoot
    if ($null -eq $entry) {
        return [pscustomobject]@{ Eligible = $false; Reason = 'UNKNOWN_TARGET_PROJECT' }
    }

    $createdBy = $false
    if ($entry.PSObject.Properties.Name -contains 'CREATED_BY_SKILLSMACHINE') {
        $createdBy = [bool]$entry.CREATED_BY_SKILLSMACHINE
    }
    $enrolled = ([string]$entry.ENROLMENT_STATUS -eq 'ENROLLED') -and (
        ($entry.PSObject.Properties.Name -contains 'EXPLICITLY_ENROLLED_IN_SKILLSMACHINE') -and [bool]$entry.EXPLICITLY_ENROLLED_IN_SKILLSMACHINE
    )
    if (-not ($createdBy -or $enrolled)) {
        return [pscustomobject]@{ Eligible = $false; Reason = 'TARGET_NOT_ELIGIBLE' }
    }
    if (-not [bool]$entry.PROJECT_SYNC_ENABLED) {
        return [pscustomobject]@{ Eligible = $false; Reason = 'PROJECT_SYNC_DISABLED' }
    }

    $pkg = Get-ProductionPublication -PackageId $PackageId -OpsRoot $OpsRoot
    if ($null -eq $pkg) {
        return [pscustomobject]@{ Eligible = $false; Reason = 'PACKAGE_NOT_FOUND' }
    }
    if ([string]$pkg.PUBLICATION_STATUS -notin @('PREPARED', 'PUBLISHED')) {
        return [pscustomobject]@{ Eligible = $false; Reason = 'PACKAGE_NOT_VALID' }
    }

    return [pscustomobject]@{
        Eligible = $true
        Reason = 'ELIGIBLE_PREPARE_ONLY'
        Authority = 'TARGET_PROJECT_CONTROLS_APPLY'
        HumanApprovedRequired = $true
        CleanWorktreeRequired = $true
    }
}

function New-ProjectSyncDeliveryPreparation {
    param(
        [Parameter(Mandatory = $true)][string]$TargetProject,
        [Parameter(Mandatory = $true)][string]$PackageId,
        [string]$SourceOpportunityId = '',
        [string]$SourceDispositionId = '',
        [string]$ReceiptId = '',
        [string]$OpsRoot = (Get-ProjectOpsRoot)
    )

    $check = Test-ProjectSyncDeliveryEligibility -TargetProject $TargetProject -PackageId $PackageId -OpsRoot $OpsRoot
    if (-not [bool]$check.Eligible) {
        return [pscustomobject]@{
            ok = $false
            DELIVERY_STATUS = 'REJECTED'
            Reason = [string]$check.Reason
            TARGET_APPLY_STATUS = 'NOT_STARTED'
            MUTATION_PERFORMED = $false
        }
    }

    if (-not (Test-Path -LiteralPath (Get-ProjectSyncPrepDir -OpsRoot $OpsRoot))) {
        New-Item -ItemType Directory -Path (Get-ProjectSyncPrepDir -OpsRoot $OpsRoot) -Force | Out-Null
    }

    $deliveryId = ('DELIV-{0}-{1}-{2}' -f $TargetProject, $PackageId, (Get-Date -Format 'yyyyMMddHHmmss'))
    $pkg = Get-ProductionPublication -PackageId $PackageId -OpsRoot $OpsRoot
    if ([string]::IsNullOrWhiteSpace($SourceOpportunityId) -and ($pkg.PSObject.Properties.Name -contains 'SOURCE_OPPORTUNITY_ID')) {
        $SourceOpportunityId = [string]$pkg.SOURCE_OPPORTUNITY_ID
    }
    if ([string]::IsNullOrWhiteSpace($SourceDispositionId) -and ($pkg.PSObject.Properties.Name -contains 'SOURCE_DISPOSITION')) {
        $SourceDispositionId = [string]$pkg.SOURCE_DISPOSITION
    }
    if ([string]::IsNullOrWhiteSpace($ReceiptId) -and ($pkg.PSObject.Properties.Name -contains 'SOURCE_RECEIPT_ID')) {
        $ReceiptId = [string]$pkg.SOURCE_RECEIPT_ID
    }
    $record = [pscustomobject]@{
        schema_version = '0.2.0'
        DELIVERY_ID = $deliveryId
        TARGET_PROJECT = $TargetProject
        PACKAGE_ID = $PackageId
        CAPABILITY_ID = [string]$pkg.CAPABILITY_ID
        SOURCE_OPPORTUNITY_ID = $SourceOpportunityId
        SOURCE_DISPOSITION_ID = $SourceDispositionId
        SOURCE_RECEIPT_ID = $ReceiptId
        FROM_VERSION = 'UNKNOWN'
        TO_VERSION = [string]$pkg.VERSION
        DELIVERY_STATUS = 'PREPARED'
        TARGET_APPLY_STATUS = 'NOT_STARTED'
        HUMAN_APPROVAL = 'REQUIRED'
        CLEAN_WORKTREE_REQUIRED = $true
        TARGET_AUTHORITY = 'TARGET_PROJECT_CONTROLS_APPLY'
        MUTATION_PERFORMED = $false
        created_at = (Get-ProjectOpsUtcNow)
        NOTE = 'Delivery preparation only. SkillsMachine must not apply into target project from this record.'
    }
    $path = Join-Path (Get-ProjectSyncPrepDir -OpsRoot $OpsRoot) ("{0}.json" -f $deliveryId)
    Write-ProjectOpsUtf8NoBom -Path $path -Content (ConvertTo-ProjectOpsJson -Object $record)

    $entry = Get-ProjectRegistryEntry -ProjectId $TargetProject -OpsRoot $OpsRoot
    if ($null -ne $entry) {
        $entry.PROJECT_SYNC_STATUS = 'DELIVERY_PENDING'
        $entry.LAST_SYNC_ID = $deliveryId
        $entry.LAST_OBSERVED_AT = Get-ProjectOpsUtcNow
        [void](Upsert-ProjectRegistryEntry -Entry $entry -OpsRoot $OpsRoot)
    }

    return [pscustomobject]@{
        ok = $true
        delivery = $record
        delivery_path = $path
        MUTATION_PERFORMED = $false
    }
}

function Get-ProjectSyncDeliveryPath {
    param(
        [Parameter(Mandatory = $true)][string]$DeliveryId,
        [string]$OpsRoot = (Get-ProjectOpsRoot)
    )
    return (Join-Path (Get-ProjectSyncPrepDir -OpsRoot $OpsRoot) ("{0}.json" -f $DeliveryId))
}

function Get-ProjectSyncReturnReceiptDir {
    param([string]$OpsRoot = (Get-ProjectOpsRoot))
    return (Join-Path (Get-ProjectSyncPrepDir -OpsRoot $OpsRoot) 'ReturnReceipts')
}

function Test-ProjectOpsGitCommitHash {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    return ([string]$Value -match '^[0-9a-fA-F]{40}$')
}

function Set-ProjectOpsNoteProperty {
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

function Get-ProjectOpsNoteProperty {
    param(
        [Parameter(Mandatory = $true)]$Object,
        [Parameter(Mandatory = $true)][string]$Name,
        $Default = $null
    )
    if ($null -eq $Object) { return $Default }
    if ($Object.PSObject.Properties.Name -contains $Name) { return $Object.$Name }
    return $Default
}

function Register-ProjectSyncTargetReturnReceipt {
    param(
        [Parameter(Mandatory = $true)][string]$DeliveryId,
        [Parameter(Mandatory = $true)][string]$TargetProject,
        [Parameter(Mandatory = $true)][string]$LocalReceiptId,
        [Parameter(Mandatory = $true)][string]$TargetHead,
        [string]$TargetOriginMain = '',
        [string]$TargetSkillVersion = '',
        [string]$TargetValidation = '',
        [string]$TargetPushStatus = '',
        [string]$TargetApplyEvidence = '',
        [string]$ReceivingBoundaryStatus = '',
        [string]$OpsRoot = (Get-ProjectOpsRoot)
    )

    $fail = {
        param([string]$Reason)
        return [pscustomobject]@{
            ok = $false
            Reason = $Reason
            DELIVERY_ID = $DeliveryId
            TARGET_APPLY_STATUS = 'NOT_STARTED'
            RETURN_RECEIPT_RECORDED = $false
            IDEMPOTENT_REPLAY = $false
            MUTATION_PERFORMED = $false
        }
    }

    if ([string]::IsNullOrWhiteSpace($DeliveryId)) { return & $fail 'DELIVERY_ID_REQUIRED' }
    if ([string]::IsNullOrWhiteSpace($TargetProject)) { return & $fail 'TARGET_PROJECT_REQUIRED' }
    if ([string]::IsNullOrWhiteSpace($LocalReceiptId)) { return & $fail 'MISSING_APPLY_EVIDENCE' }
    if (-not (Test-ProjectOpsGitCommitHash -Value $TargetHead)) { return & $fail 'MISSING_APPLY_EVIDENCE' }

    $path = Get-ProjectSyncDeliveryPath -DeliveryId $DeliveryId -OpsRoot $OpsRoot
    if (-not (Test-Path -LiteralPath $path)) { return & $fail 'DELIVERY_NOT_FOUND' }

    $delivery = Read-ProjectOpsJson -Path $path
    $deliveryProject = [string](Get-ProjectOpsNoteProperty -Object $delivery -Name 'TARGET_PROJECT' -Default '')
    if ($deliveryProject -ne $TargetProject) { return & $fail 'TARGET_PROJECT_MISMATCH' }

    $pkgId = [string](Get-ProjectOpsNoteProperty -Object $delivery -Name 'PACKAGE_ID' -Default '')
    $pkg = Get-ProductionPublication -PackageId $pkgId -OpsRoot $OpsRoot
    if ($null -eq $pkg) { return & $fail 'PACKAGE_NOT_FOUND' }

    $entry = Get-ProjectRegistryEntry -ProjectId $TargetProject -OpsRoot $OpsRoot
    if ($null -eq $entry) { return & $fail 'UNKNOWN_TARGET_PROJECT' }
    $check = Test-ProjectSyncDeliveryEligibility -TargetProject $TargetProject -PackageId $pkgId -OpsRoot $OpsRoot
    if (-not [bool]$check.Eligible) { return & $fail ([string]$check.Reason) }

    $deliveryStatus = [string](Get-ProjectOpsNoteProperty -Object $delivery -Name 'DELIVERY_STATUS' -Default '')
    if ($deliveryStatus -in @('REJECTED', 'SUPERSEDED')) { return & $fail 'DELIVERY_NOT_ACCEPTING_RECEIPT' }

    $currentApply = [string](Get-ProjectOpsNoteProperty -Object $delivery -Name 'TARGET_APPLY_STATUS' -Default 'NOT_STARTED')
    $existingReceipt = [string](Get-ProjectOpsNoteProperty -Object $delivery -Name 'UPDATE_RECEIPT_ID' -Default '')
    $existingHead = [string](Get-ProjectOpsNoteProperty -Object $delivery -Name 'TARGET_HEAD' -Default '')
    $alreadyRecorded = [bool](Get-ProjectOpsNoteProperty -Object $delivery -Name 'RETURN_RECEIPT_RECORDED' -Default $false)

    if ($alreadyRecorded -or ($currentApply -eq 'APPLIED' -and -not [string]::IsNullOrWhiteSpace($existingReceipt))) {
        if ($existingReceipt -eq $LocalReceiptId -and $existingHead -eq $TargetHead) {
            return [pscustomobject]@{
                ok = $true
                Reason = 'IDEMPOTENT_REPLAY'
                delivery = $delivery
                delivery_path = $path
                DELIVERY_STATUS = [string](Get-ProjectOpsNoteProperty -Object $delivery -Name 'DELIVERY_STATUS' -Default 'DELIVERED')
                TARGET_APPLY_STATUS = 'APPLIED'
                UPDATE_RECEIPT_ID = $existingReceipt
                RETURN_RECEIPT_RECORDED = $true
                IDEMPOTENT_REPLAY = $true
                MUTATION_PERFORMED = $false
            }
        }
        if ($existingReceipt -ne $LocalReceiptId -and -not [string]::IsNullOrWhiteSpace($existingReceipt)) {
            return & $fail 'DUPLICATE_RECEIPT_CONFLICT'
        }
        if ($existingHead -ne $TargetHead -and -not [string]::IsNullOrWhiteSpace($existingHead)) {
            return & $fail 'TARGET_HEAD_MISMATCH'
        }
        return & $fail 'DUPLICATE_RECEIPT_CONFLICT'
    }

    if ($currentApply -notin @('NOT_STARTED', 'APPLYING')) {
        return & $fail 'TARGET_APPLY_STATUS_NOT_ACCEPTING'
    }

    $recordedAt = Get-ProjectOpsUtcNow
    if ($null -eq (Get-ProjectOpsNoteProperty -Object $delivery -Name 'ORIGINAL_DELIVERY_STATUS' -Default $null)) {
        Set-ProjectOpsNoteProperty -Object $delivery -Name 'ORIGINAL_DELIVERY_STATUS' -Value $deliveryStatus
    }
    if ($null -eq (Get-ProjectOpsNoteProperty -Object $delivery -Name 'ORIGINAL_TARGET_APPLY_STATUS' -Default $null)) {
        Set-ProjectOpsNoteProperty -Object $delivery -Name 'ORIGINAL_TARGET_APPLY_STATUS' -Value $currentApply
    }

    Set-ProjectOpsNoteProperty -Object $delivery -Name 'DELIVERY_STATUS' -Value 'DELIVERED'
    Set-ProjectOpsNoteProperty -Object $delivery -Name 'TARGET_APPLY_STATUS' -Value 'APPLIED'
    $evidence = $TargetApplyEvidence
    if ([string]::IsNullOrWhiteSpace($evidence)) { $evidence = 'APPLIED' }
    Set-ProjectOpsNoteProperty -Object $delivery -Name 'TARGET_APPLY_EVIDENCE' -Value $evidence
    Set-ProjectOpsNoteProperty -Object $delivery -Name 'UPDATE_RECEIPT_ID' -Value $LocalReceiptId
    Set-ProjectOpsNoteProperty -Object $delivery -Name 'TARGET_HEAD' -Value $TargetHead
    Set-ProjectOpsNoteProperty -Object $delivery -Name 'TARGET_ORIGIN_MAIN' -Value $(if ([string]::IsNullOrWhiteSpace($TargetOriginMain)) { $TargetHead } else { $TargetOriginMain })
    Set-ProjectOpsNoteProperty -Object $delivery -Name 'TARGET_SKILL_VERSION' -Value $TargetSkillVersion
    Set-ProjectOpsNoteProperty -Object $delivery -Name 'VALIDATION_RESULT' -Value $(if ([string]::IsNullOrWhiteSpace($TargetValidation)) { 'PASS' } else { $TargetValidation })
    Set-ProjectOpsNoteProperty -Object $delivery -Name 'TARGET_PUSH_STATUS' -Value $TargetPushStatus
    Set-ProjectOpsNoteProperty -Object $delivery -Name 'RETURN_RECEIPT_RECORDED' -Value $true
    Set-ProjectOpsNoteProperty -Object $delivery -Name 'RETURN_RECEIPT_RECORDED_AT' -Value $recordedAt
    Set-ProjectOpsNoteProperty -Object $delivery -Name 'PROJECT_SYNC_APPLIED' -Value 'NO'
    Set-ProjectOpsNoteProperty -Object $delivery -Name 'MUTATION_PERFORMED' -Value $false
    Set-ProjectOpsNoteProperty -Object $delivery -Name 'NOTE' -Value 'Target apply acknowledged from target-emitted return receipt. SkillsMachine did not mutate the target project.'

    $updateReceipt = [pscustomobject]@{
        schema_version = '0.2.0'
        message_type = 'TARGET_UPDATE_RECEIPT'
        UPDATE_RECEIPT_ID = $LocalReceiptId
        DELIVERY_ID = $DeliveryId
        TARGET_PROJECT = $TargetProject
        PACKAGE_ID = $pkgId
        TARGET_HEAD = $TargetHead
        TARGET_ORIGIN_MAIN = $(if ([string]::IsNullOrWhiteSpace($TargetOriginMain)) { $TargetHead } else { $TargetOriginMain })
        TARGET_SKILL_VERSION = $TargetSkillVersion
        TARGET_VALIDATION = $(if ([string]::IsNullOrWhiteSpace($TargetValidation)) { 'PASS' } else { $TargetValidation })
        TARGET_PUSH_STATUS = $TargetPushStatus
        TARGET_APPLY_STATUS = 'APPLIED'
        TARGET_APPLY_EVIDENCE = $evidence
        RECEIVING_BOUNDARY_STATUS = $ReceivingBoundaryStatus
        SOURCE_OPPORTUNITY_ID = [string](Get-ProjectOpsNoteProperty -Object $delivery -Name 'SOURCE_OPPORTUNITY_ID' -Default '')
        SOURCE_DISPOSITION_ID = [string](Get-ProjectOpsNoteProperty -Object $delivery -Name 'SOURCE_DISPOSITION_ID' -Default '')
        SOURCE_RECEIPT_ID = [string](Get-ProjectOpsNoteProperty -Object $delivery -Name 'SOURCE_RECEIPT_ID' -Default '')
        recorded_at = $recordedAt
        SKILLSMACHINE_MUTATION = 'NO'
    }
    Set-ProjectOpsNoteProperty -Object $delivery -Name 'UPDATE_RECEIPT' -Value $updateReceipt

    $rrDir = Get-ProjectSyncReturnReceiptDir -OpsRoot $OpsRoot
    if (-not (Test-Path -LiteralPath $rrDir)) {
        New-Item -ItemType Directory -Path $rrDir -Force | Out-Null
    }
    $rrPath = Join-Path $rrDir ("{0}.json" -f $LocalReceiptId)
    Write-ProjectOpsUtf8NoBom -Path $rrPath -Content (ConvertTo-ProjectOpsJson -Object $updateReceipt)
    Write-ProjectOpsUtf8NoBom -Path $path -Content (ConvertTo-ProjectOpsJson -Object $delivery)

    $boundaryRegistry = [string](Get-ProjectOpsNoteProperty -Object $entry -Name 'RECEIVING_BOUNDARY_00_SKILLSMACHINE' -Default 'ABSENT')
    if (-not [string]::IsNullOrWhiteSpace($ReceivingBoundaryStatus) -and $ReceivingBoundaryStatus -ne 'ABSENT') {
        $boundaryRegistry = 'PRESENT'
    }
    Set-ProjectOpsNoteProperty -Object $entry -Name 'PROJECT_SYNC_STATUS' -Value 'CURRENT'
    Set-ProjectOpsNoteProperty -Object $entry -Name 'LAST_SYNC_ID' -Value $DeliveryId
    Set-ProjectOpsNoteProperty -Object $entry -Name 'LAST_UPDATE_RECEIPT_ID' -Value $LocalReceiptId
    Set-ProjectOpsNoteProperty -Object $entry -Name 'OBSERVED_HEAD' -Value $TargetHead
    Set-ProjectOpsNoteProperty -Object $entry -Name 'LAST_OBSERVED_AT' -Value $recordedAt
    Set-ProjectOpsNoteProperty -Object $entry -Name 'RECEIVING_BOUNDARY_00_SKILLSMACHINE' -Value $boundaryRegistry
    if ([string](Get-ProjectOpsNoteProperty -Object $entry -Name 'ATTENTION' -Default '') -eq 'RECEIVING_BOUNDARY_ABSENT' -and $boundaryRegistry -eq 'PRESENT') {
        Set-ProjectOpsNoteProperty -Object $entry -Name 'ATTENTION' -Value 'NONE'
    }
    [void](Upsert-ProjectRegistryEntry -Entry $entry -OpsRoot $OpsRoot)

    return [pscustomobject]@{
        ok = $true
        Reason = 'RETURN_RECEIPT_RECORDED'
        delivery = $delivery
        delivery_path = $path
        return_receipt_path = $rrPath
        DELIVERY_STATUS = 'DELIVERED'
        TARGET_APPLY_STATUS = 'APPLIED'
        UPDATE_RECEIPT_ID = $LocalReceiptId
        RETURN_RECEIPT_RECORDED = $true
        IDEMPOTENT_REPLAY = $false
        MUTATION_PERFORMED = $false
    }
}
