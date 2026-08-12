#Requires -Version 5.1
# Durable Project Registry — MB-SM-076A3

function Get-ProjectRegistryPath {
    param([string]$OpsRoot = (Get-ProjectOpsRoot))
    return (Join-Path (Get-ProjectOpsStateRoot -OpsRoot $OpsRoot) 'PROJECT.REGISTRY.json')
}

function New-EmptyProjectRegistry {
    return [pscustomobject]@{
        schema_version = '0.2.0'
        source = 'MB-SM-076A3'
        generated_at = (Get-ProjectOpsUtcNow)
        updated_at = (Get-ProjectOpsUtcNow)
        note = 'Durable SkillsMachine-owned project registry. Enrolment != autonomous mutation authority.'
        projects = @()
    }
}

function Test-ProjectRegistryObject {
    param([Parameter(Mandatory = $true)]$Registry)
    if ([string]$Registry.schema_version -notmatch '^0\.2\.') {
        throw 'PROJECT_REGISTRY_UNSUPPORTED_SCHEMA'
    }
    if ($null -eq $Registry.projects) {
        throw 'PROJECT_REGISTRY_MISSING_PROJECTS'
    }
    foreach ($p in @($Registry.projects)) {
        foreach ($req in @('PROJECT_ID', 'PROJECT_ROOT_IDENTITY', 'ENROLMENT_STATUS', 'IMPROVEMENT_FLOW_STATUS', 'PROJECT_SYNC_STATUS')) {
            if (-not ($p.PSObject.Properties.Name -contains $req) -or [string]::IsNullOrWhiteSpace([string]$p.$req)) {
                throw ("PROJECT_REGISTRY_FIELD_MISSING: {0}.{1}" -f [string]$p.PROJECT_ID, $req)
            }
        }
        $allowedEnrol = @('DISCOVERED', 'NOT_ENROLLED', 'ENROLMENT_PENDING', 'ENROLLED', 'SUSPENDED_OR_DISCONNECTED')
        if ($allowedEnrol -notcontains [string]$p.ENROLMENT_STATUS) {
            throw ("PROJECT_REGISTRY_INVALID_ENROLMENT_STATUS: {0}" -f [string]$p.ENROLMENT_STATUS)
        }
        if ([string]$p.PROJECT_SYNC_STATUS -eq 'CURRENT' -and [string]$p.ENROLMENT_STATUS -eq 'NOT_ENROLLED') {
            throw ("PROJECT_REGISTRY_FAKE_CURRENT: {0}" -f [string]$p.PROJECT_ID)
        }
    }
    return $true
}

function Read-ProjectRegistry {
    param([string]$OpsRoot = (Get-ProjectOpsRoot))
    $path = Get-ProjectRegistryPath -OpsRoot $OpsRoot
    if (-not (Test-Path -LiteralPath $path)) {
        $empty = New-EmptyProjectRegistry
        Save-ProjectRegistry -Registry $empty -OpsRoot $OpsRoot
        return $empty
    }
    $reg = Read-ProjectOpsJson -Path $path
    [void](Test-ProjectRegistryObject -Registry $reg)
    return $reg
}

function Save-ProjectRegistry {
    param(
        [Parameter(Mandatory = $true)]$Registry,
        [string]$OpsRoot = (Get-ProjectOpsRoot)
    )
    $Registry.updated_at = Get-ProjectOpsUtcNow
    [void](Test-ProjectRegistryObject -Registry $Registry)
    $path = Get-ProjectRegistryPath -OpsRoot $OpsRoot
    Write-ProjectOpsUtf8NoBom -Path $path -Content (ConvertTo-ProjectOpsJson -Object $Registry)
    return $path
}

function Get-ProjectRegistryEntry {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectId,
        [string]$OpsRoot = (Get-ProjectOpsRoot)
    )
    $reg = Read-ProjectRegistry -OpsRoot $OpsRoot
    $hit = @($reg.projects | Where-Object { [string]$_.PROJECT_ID -eq $ProjectId })
    if ($hit.Count -eq 0) { return $null }
    return $hit[0]
}

function Upsert-ProjectRegistryEntry {
    param(
        [Parameter(Mandatory = $true)]$Entry,
        [string]$OpsRoot = (Get-ProjectOpsRoot)
    )
    $reg = Read-ProjectRegistry -OpsRoot $OpsRoot
    $list = New-Object System.Collections.Generic.List[object]
    $replaced = $false
    foreach ($p in @($reg.projects)) {
        if ([string]$p.PROJECT_ID -eq [string]$Entry.PROJECT_ID) {
            [void]$list.Add($Entry)
            $replaced = $true
        }
        else {
            [void]$list.Add($p)
        }
    }
    if (-not $replaced) {
        [void]$list.Add($Entry)
    }
    $reg.projects = @($list.ToArray())
    [void](Save-ProjectRegistry -Registry $reg -OpsRoot $OpsRoot)
    return $Entry
}

function Get-ProjectHomeViewFromRegistry {
    param([string]$OpsRoot = (Get-ProjectOpsRoot))
    $reg = Read-ProjectRegistry -OpsRoot $OpsRoot
    $projects = New-Object System.Collections.Generic.List[object]
    $attention = New-Object System.Collections.Generic.List[object]
    foreach ($p in @($reg.projects)) {
        $sync = [string]$p.PROJECT_SYNC_STATUS
        if ([string]::IsNullOrWhiteSpace($sync)) { $sync = 'UNKNOWN' }
        $row = [pscustomobject]@{
            PROJECT = [string]$p.PROJECT_ID
            PROJECT_ID = [string]$p.PROJECT_ID
            ENROLMENT_STATUS = [string]$p.ENROLMENT_STATUS
            IMPROVEMENT_FLOW_STATUS = [string]$p.IMPROVEMENT_FLOW_STATUS
            PROJECT_SYNC_STATUS = $sync
            ATTENTION = [string]$p.ATTENTION
            LAST_OBSERVED_STATE = [string]$p.LAST_OBSERVED_AT
            PROJECT_CLASS = [string]$p.PROJECT_CLASS
            PROPOSAL_STATUS = $(if ($p.PSObject.Properties.Name -contains 'PROPOSAL_STATUS') { [string]$p.PROPOSAL_STATUS } else { $null })
        }
        [void]$projects.Add($row)
        if ([string]$p.ATTENTION -and [string]$p.ATTENTION -ne 'NONE') {
            [void]$attention.Add([pscustomobject]@{
                id = ("ATTN-{0}" -f [string]$p.PROJECT_ID)
                summary = ("{0}: {1}" -f [string]$p.PROJECT_ID, [string]$p.ATTENTION)
                source = 'DURABLE_PROJECT_REGISTRY'
            })
        }
        if ($p.PSObject.Properties.Name -contains 'PROPOSAL_STATUS' -and [string]$p.PROPOSAL_STATUS -eq 'READY_FOR_REVIEW') {
            [void]$attention.Add([pscustomobject]@{
                id = ("ATTN-ENROL-{0}" -f [string]$p.PROJECT_ID)
                summary = ("Enrolment proposal READY_FOR_REVIEW for {0}" -f [string]$p.PROJECT_ID)
                source = 'ENROLMENT_PROPOSAL'
            })
        }
    }
    return [pscustomobject]@{
        projects = @($projects.ToArray())
        needs_your_attention = @($attention.ToArray())
        registry_path = (Get-ProjectRegistryPath -OpsRoot $OpsRoot)
        schema_version = [string]$reg.schema_version
    }
}
