#Requires -Version 5.1
# VerticalSlice Core — Audit finding helpers (MB-SM-075B)
# Severities: CRITICAL | IMPORTANT | ADVISORY
# ADVISORY does not necessarily degrade Global Status (via AuditStatus CURRENT).

function New-AuditFindingList {
    # Comma operator prevents PowerShell from unwrapping/enumerating the empty List on return.
    return ,(New-Object System.Collections.Generic.List[object])
}

function Add-AuditFinding {
    param(
        [System.Collections.Generic.List[object]]$Findings,
        [string]$Severity,
        [string]$Rule,
        [string]$Scope,
        [string]$Refs,
        [string]$Remediation
    )
    $allowed = @('CRITICAL', 'IMPORTANT', 'ADVISORY')
    if ($allowed -notcontains $Severity) { throw "INVALID_FINDING_SEVERITY=$Severity" }
    $item = [ordered]@{}
    $item['finding_id'] = 'AF-' + $Findings.Count.ToString('000')
    $item['severity'] = $Severity
    $item['rule'] = $Rule
    $item['scope'] = $Scope
    $item['entity_refs'] = $Refs
    $item['remediation'] = $Remediation
    [void]$Findings.Add($item)
}

function Get-AuditFindingCounts([System.Collections.Generic.List[object]]$Findings) {
    $crit = @($Findings | Where-Object { $_['severity'] -eq 'CRITICAL' }).Count
    $imp = @($Findings | Where-Object { $_['severity'] -eq 'IMPORTANT' }).Count
    $adv = @($Findings | Where-Object { $_['severity'] -eq 'ADVISORY' }).Count
    return [ordered]@{
        CRITICAL = [int]$crit
        IMPORTANT = [int]$imp
        ADVISORY = [int]$adv
        TOTAL = [int]$Findings.Count
    }
}

function New-AuditReport {
    param(
        [System.Collections.Generic.List[object]]$Findings,
        [bool]$Blocked = $false
    )
    $counts = Get-AuditFindingCounts $Findings
    $status = Get-AuditStatusFromCounts -Critical $counts.CRITICAL -Important $counts.IMPORTANT -Advisory $counts.ADVISORY -Blocked $Blocked
    $report = [ordered]@{}
    $report['GLOBAL_AUDIT_STATUS'] = [string]$status
    $report['CRITICAL'] = [int]$counts.CRITICAL
    $report['IMPORTANT'] = [int]$counts.IMPORTANT
    $report['ADVISORY'] = [int]$counts.ADVISORY
    $report['TOTAL_FINDINGS'] = [int]$counts.TOTAL
    $report['findings'] = @($Findings.ToArray())
    $report['rule'] = 'ADVISORY_DOES_NOT_FORCE_ATTENTION'
    return $report
}
