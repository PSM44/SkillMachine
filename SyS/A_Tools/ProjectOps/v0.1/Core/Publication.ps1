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

    return [pscustomobject]@{
        ok = $true
        manifest = $manifest
        package_dir = $dir
        PUBLICATION_STATUS = 'PREPARED'
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
