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
