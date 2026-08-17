#Requires -Version 5.1
# Minimum production publication path — MB-SM-076A3
# Does NOT publish updates into external projects.

function Get-PublicationsDir {
    param([string]$OpsRoot = (Get-ProjectOpsRoot))
    return (Join-Path (Get-ProjectOpsStateRoot -OpsRoot $OpsRoot) 'Publications')
}

function New-ProductionPublicationPackage {
    param(
        [Parameter(Mandatory = $true)][string]$CapabilityId,
        [Parameter(Mandatory = $true)][string]$Version,
        [Parameter(Mandatory = $true)][string]$SourceDispositionId,
        [string[]]$Dependencies = @(),
        [string]$Compatibility = 'baseline_schema>=1.1',
        [string]$TargetEligibility = 'CREATED_BY_OR_ENROLLED',
        [string]$AuditResult = 'PENDING_HUMAN_REVIEW',
        [string]$PackageBody = '',
        [string]$SourceOpportunityId = '',
        [string]$ChangeRationale = '',
        [string]$ReceiptId = '',
        [string]$OpsRoot = (Get-ProjectOpsRoot)
    )

    if (-not (Test-Path -LiteralPath (Get-PublicationsDir -OpsRoot $OpsRoot))) {
        New-Item -ItemType Directory -Path (Get-PublicationsDir -OpsRoot $OpsRoot) -Force | Out-Null
    }

    $packageId = ('PKG-{0}-{1}' -f ($CapabilityId -replace '[^A-Za-z0-9_.-]', '_'), $Version)
    $bodyHash = Get-ProjectOpsSha256Text -Text $PackageBody
    $manifest = [pscustomobject]@{
        schema_version = '0.2.0'
        PACKAGE_ID = $packageId
        CAPABILITY_ID = $CapabilityId
        VERSION = $Version
        SOURCE_DISPOSITION = $SourceDispositionId
        SOURCE_OPPORTUNITY_ID = $SourceOpportunityId
        SOURCE_RECEIPT_ID = $ReceiptId
        CHANGE_RATIONALE = $ChangeRationale
        DEPENDENCIES = @($Dependencies)
        COMPATIBILITY = $Compatibility
        TARGET_ELIGIBILITY = $TargetEligibility
        AUDIT_RESULT = $AuditResult
        PUBLICATION_STATUS = 'PREPARED'
        content_sha256 = $bodyHash
        REVERSIBILITY_INFO = 'Package is reversible only via SkillsMachine updater checkpoint/rollback when applied under HumanApproved + clean worktree; target apply remains target-project controlled.'
        created_at = (Get-ProjectOpsUtcNow)
        LAB_PUBLICATION = $false
        PRODUCTION_PUBLICATION = 'PREPARED_NOT_DELIVERED'
        NOTE = 'Minimum production publication path. No external project mutation performed.'
    }

    $dir = Join-Path (Get-PublicationsDir -OpsRoot $OpsRoot) $packageId
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    Write-ProjectOpsUtf8NoBom -Path (Join-Path $dir 'PACKAGE.MANIFEST.json') -Content (ConvertTo-ProjectOpsJson -Object $manifest)
    Write-ProjectOpsUtf8NoBom -Path (Join-Path $dir 'PACKAGE.BODY.txt') -Content $PackageBody

    $lifecycle = Initialize-PublicationLifecycle -PackageId $packageId -OpsRoot $OpsRoot

    return [pscustomobject]@{
        ok = $true
        manifest = $manifest
        package_dir = $dir
        PUBLICATION_STATUS = 'PREPARED'
        LIFECYCLE_STATUS = [string]$lifecycle.LIFECYCLE_STATUS
        lifecycle = $lifecycle
        BLOCKER_FOR_EXTERNAL_DELIVERY = 'Requires enrolled eligible target + HumanApproved Project Sync apply under target authority'
    }
}

function Get-ProductionPublication {
    param(
        [Parameter(Mandatory = $true)][string]$PackageId,
        [string]$OpsRoot = (Get-ProjectOpsRoot)
    )
    $path = Join-Path (Get-PublicationsDir -OpsRoot $OpsRoot) (Join-Path $PackageId 'PACKAGE.MANIFEST.json')
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    return (Read-ProjectOpsJson -Path $path)
}

# Current publication lifecycle sidecar — MB-SM-077E CG1
# Historical PACKAGE.MANIFEST.json is never rewritten by these helpers.

function Get-AllowedPublicationLifecycleStatuses {
    return @('PREPARED', 'DELIVERY_PREPARED', 'TARGET_APPLIED', 'RETURN_RECEIPT_CONSUMED')
}

function Get-PublicationLifecycleRank {
    param([Parameter(Mandatory = $true)][string]$Status)
    switch ($Status) {
        'PREPARED' { return 0 }
        'DELIVERY_PREPARED' { return 1 }
        'TARGET_APPLIED' { return 2 }
        'RETURN_RECEIPT_CONSUMED' { return 3 }
        default { return -1 }
    }
}

function Get-PublicationManifestPath {
    param(
        [Parameter(Mandatory = $true)][string]$PackageId,
        [string]$OpsRoot = (Get-ProjectOpsRoot)
    )
    return (Join-Path (Get-PublicationsDir -OpsRoot $OpsRoot) (Join-Path $PackageId 'PACKAGE.MANIFEST.json'))
}

function Get-PublicationLifecyclePath {
    param(
        [Parameter(Mandatory = $true)][string]$PackageId,
        [string]$OpsRoot = (Get-ProjectOpsRoot)
    )
    return (Join-Path (Get-PublicationsDir -OpsRoot $OpsRoot) (Join-Path $PackageId 'PACKAGE.LIFECYCLE.CURRENT.json'))
}

function Test-HistoricalPublicationManifestUnchanged {
    param(
        [Parameter(Mandatory = $true)][string]$PackageId,
        [string]$OpsRoot = (Get-ProjectOpsRoot)
    )
    $manifest = Get-ProductionPublication -PackageId $PackageId -OpsRoot $OpsRoot
    if ($null -eq $manifest) { return $false }
    return (
        [string]$manifest.PUBLICATION_STATUS -eq 'PREPARED' -and
        [string]$manifest.PRODUCTION_PUBLICATION -eq 'PREPARED_NOT_DELIVERED'
    )
}

function Get-PublicationLifecycle {
    param(
        [Parameter(Mandatory = $true)][string]$PackageId,
        [string]$OpsRoot = (Get-ProjectOpsRoot)
    )
    $path = Get-PublicationLifecyclePath -PackageId $PackageId -OpsRoot $OpsRoot
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    return (Read-ProjectOpsJson -Path $path)
}

function Write-PublicationLifecycle {
    param(
        [Parameter(Mandatory = $true)]$Lifecycle,
        [Parameter(Mandatory = $true)][string]$PackageId,
        [string]$OpsRoot = (Get-ProjectOpsRoot)
    )
    $path = Get-PublicationLifecyclePath -PackageId $PackageId -OpsRoot $OpsRoot
    Write-ProjectOpsUtf8NoBom -Path $path -Content (ConvertTo-ProjectOpsJson -Object $Lifecycle)
    return $path
}

function Initialize-PublicationLifecycle {
    param(
        [Parameter(Mandatory = $true)][string]$PackageId,
        [string]$OpsRoot = (Get-ProjectOpsRoot)
    )

    $existing = Get-PublicationLifecycle -PackageId $PackageId -OpsRoot $OpsRoot
    if ($null -ne $existing) {
        if ([string]$existing.PACKAGE_ID -ne $PackageId) {
            return [pscustomobject]@{
                ok = $false
                Reason = 'PACKAGE_IDENTITY_MISMATCH'
                LIFECYCLE_STATUS = [string]$existing.LIFECYCLE_STATUS
                lifecycle = $existing
                MUTATION_PERFORMED = $false
            }
        }
        if ([string]$existing.LIFECYCLE_STATUS -eq 'PREPARED') {
            return [pscustomobject]@{
                ok = $true
                Reason = 'IDEMPOTENT_REPLAY'
                LIFECYCLE_STATUS = 'PREPARED'
                lifecycle = $existing
                MUTATION_PERFORMED = $false
            }
        }
    }

    $lifecycle = [pscustomobject]@{
        schema_version = '0.3.0'
        PACKAGE_ID = $PackageId
        LIFECYCLE_STATUS = 'PREPARED'
        UPDATED_AT = (Get-ProjectOpsUtcNow)
        SOURCE_EVENT = 'PUBLICATION_PREPARED'
        HISTORICAL_MANIFEST_UNCHANGED = $true
        RECONCILIATION_STATUS = 'PENDING'
    }
    [void](Write-PublicationLifecycle -Lifecycle $lifecycle -PackageId $PackageId -OpsRoot $OpsRoot)
    return [pscustomobject]@{
        ok = $true
        Reason = 'LIFECYCLE_INITIALIZED'
        LIFECYCLE_STATUS = 'PREPARED'
        lifecycle = $lifecycle
        MUTATION_PERFORMED = $true
        PACKAGE_ID = $PackageId
        HISTORICAL_MANIFEST_UNCHANGED = $true
        RECONCILIATION_STATUS = 'PENDING'
        SOURCE_EVENT = 'PUBLICATION_PREPARED'
        UPDATED_AT = [string]$lifecycle.UPDATED_AT
    }
}

function Test-PublicationLifecycleTransitionAllowed {
    param(
        [Parameter(Mandatory = $true)][string]$FromStatus,
        [Parameter(Mandatory = $true)][string]$ToStatus
    )
    if ($FromStatus -eq $ToStatus) { return $true }
    $fromRank = Get-PublicationLifecycleRank -Status $FromStatus
    $toRank = Get-PublicationLifecycleRank -Status $ToStatus
    if ($fromRank -lt 0 -or $toRank -lt 0) { return $false }
    if ($toRank -lt $fromRank) { return $false }
    # Skip TARGET_APPLIED only: DELIVERY_PREPARED -> RETURN_RECEIPT_CONSUMED (receipt implies apply).
    if ($FromStatus -eq 'PREPARED' -and $ToStatus -eq 'DELIVERY_PREPARED') { return $true }
    if ($FromStatus -eq 'DELIVERY_PREPARED' -and $ToStatus -eq 'TARGET_APPLIED') { return $true }
    if ($FromStatus -eq 'DELIVERY_PREPARED' -and $ToStatus -eq 'RETURN_RECEIPT_CONSUMED') { return $true }
    if ($FromStatus -eq 'TARGET_APPLIED' -and $ToStatus -eq 'RETURN_RECEIPT_CONSUMED') { return $true }
    return $false
}

function Set-PublicationLifecycleStatus {
    param(
        [Parameter(Mandatory = $true)][string]$PackageId,
        [Parameter(Mandatory = $true)][string]$NewStatus,
        [Parameter(Mandatory = $true)][string]$SourceEvent,
        [string]$OpsRoot = (Get-ProjectOpsRoot)
    )

    $allowed = Get-AllowedPublicationLifecycleStatuses
    if ($allowed -notcontains $NewStatus) {
        return [pscustomobject]@{
            ok = $false
            Reason = 'INVALID_LIFECYCLE_STATUS'
            LIFECYCLE_STATUS = $null
            MUTATION_PERFORMED = $false
        }
    }

    $lifecycle = Get-PublicationLifecycle -PackageId $PackageId -OpsRoot $OpsRoot
    if ($null -eq $lifecycle) {
        return [pscustomobject]@{
            ok = $false
            Reason = 'LIFECYCLE_PACKAGE_MISSING'
            LIFECYCLE_STATUS = $null
            MUTATION_PERFORMED = $false
        }
    }
    if ([string]$lifecycle.PACKAGE_ID -ne $PackageId) {
        return [pscustomobject]@{
            ok = $false
            Reason = 'PACKAGE_IDENTITY_MISMATCH'
            LIFECYCLE_STATUS = [string]$lifecycle.LIFECYCLE_STATUS
            MUTATION_PERFORMED = $false
        }
    }

    $current = [string]$lifecycle.LIFECYCLE_STATUS
    if ($current -eq $NewStatus) {
        return [pscustomobject]@{
            ok = $true
            Reason = 'IDEMPOTENT_REPLAY'
            LIFECYCLE_STATUS = $current
            lifecycle = $lifecycle
            MUTATION_PERFORMED = $false
            HISTORICAL_MANIFEST_UNCHANGED = [bool]$lifecycle.HISTORICAL_MANIFEST_UNCHANGED
        }
    }
    if (-not (Test-PublicationLifecycleTransitionAllowed -FromStatus $current -ToStatus $NewStatus)) {
        return [pscustomobject]@{
            ok = $false
            Reason = 'INVALID_LIFECYCLE_TRANSITION'
            LIFECYCLE_STATUS = $current
            MUTATION_PERFORMED = $false
        }
    }

    $lifecycle.LIFECYCLE_STATUS = $NewStatus
    $lifecycle.UPDATED_AT = Get-ProjectOpsUtcNow
    $lifecycle.SOURCE_EVENT = $SourceEvent
    $lifecycle.HISTORICAL_MANIFEST_UNCHANGED = $true
    [void](Write-PublicationLifecycle -Lifecycle $lifecycle -PackageId $PackageId -OpsRoot $OpsRoot)

    return [pscustomobject]@{
        ok = $true
        Reason = 'LIFECYCLE_ADVANCED'
        LIFECYCLE_STATUS = $NewStatus
        lifecycle = $lifecycle
        MUTATION_PERFORMED = $true
        HISTORICAL_MANIFEST_UNCHANGED = $true
    }
}

