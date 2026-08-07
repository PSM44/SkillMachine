#Requires -Version 5.1
# VerticalSlice Core — Global Status aggregation (MB-SM-075B)
# Vocabulary: CURRENT | ATTENTION | CRITICAL | BLOCKED
# Precedence: BLOCKED > CRITICAL > ATTENTION > CURRENT
# ADVISORY-only audit MUST NOT force ATTENTION.

function Get-StatusRank([string]$Status) {
    switch ($Status) {
        'BLOCKED'   { return 4 }
        'CRITICAL'  { return 3 }
        'ATTENTION' { return 2 }
        'CURRENT'   { return 1 }
        default     { return 0 }
    }
}

function Resolve-WorstStatus([string[]]$Statuses) {
    $worst = 'CURRENT'
    $worstRank = 1
    foreach ($s in $Statuses) {
        if ([string]::IsNullOrWhiteSpace($s)) { continue }
        $r = Get-StatusRank $s
        if ($r -gt $worstRank) {
            $worstRank = $r
            $worst = $s
        }
    }
    return $worst
}

function Get-SkillsSyncStatus {
    param(
        [string]$CatalogVersion,
        [string]$ActiveCapabilityVersion,
        [bool]$MissingRequired = $false,
        [bool]$Blocked = $false
    )
    if ($Blocked) { return 'BLOCKED' }
    if ($MissingRequired) { return 'CRITICAL' }
    if ($CatalogVersion -ne $ActiveCapabilityVersion) { return 'ATTENTION' }
    return 'CURRENT'
}

function Get-ProjectSyncStatus {
    param(
        [string]$InstalledVersion,
        [string]$AvailableVersion,
        [string]$Fork = 'NO',
        [bool]$ApplyFailed = $false,
        [bool]$Blocked = $false
    )
    if ($Blocked) { return 'BLOCKED' }
    if ($ApplyFailed) { return 'CRITICAL' }
    if ($Fork -eq 'YES') { return 'ATTENTION' }
    if ($InstalledVersion -ne $AvailableVersion) { return 'ATTENTION' }
    return 'CURRENT'
}

function Get-ImprovementFlowStatus {
    param(
        [bool]$OpenOpportunities = $false,
        [bool]$MissingReceipt = $false,
        [bool]$Blocked = $false
    )
    if ($Blocked) { return 'BLOCKED' }
    if ($MissingReceipt) { return 'CRITICAL' }
    if ($OpenOpportunities) { return 'ATTENTION' }
    return 'CURRENT'
}

function Get-SkillsProvidersStatus {
    param(
        [int]$ExternalCandidates = 0,
        [bool]$AutoCanonAttempt = $false,
        [bool]$BlockedProvider = $false
    )
    if ($BlockedProvider) { return 'BLOCKED' }
    if ($AutoCanonAttempt) { return 'CRITICAL' }
    if ($ExternalCandidates -gt 0) { return 'ATTENTION' }
    return 'CURRENT'
}

function Get-AuditStatusFromCounts {
    param(
        [int]$Critical = 0,
        [int]$Important = 0,
        [int]$Advisory = 0,
        [bool]$Blocked = $false
    )
    # ADVISORY alone does not degrade.
    if ($Blocked) { return 'BLOCKED' }
    if ($Critical -gt 0) { return 'CRITICAL' }
    if ($Important -gt 0) { return 'ATTENTION' }
    return 'CURRENT'
}

function Get-SkillsMachineGlobalStatus {
    param(
        [string]$SkillsSync,
        [string]$ProjectSync,
        [string]$ImprovementFlow,
        [string]$SkillsProviders,
        [string]$AuditStatus
    )
    return (Resolve-WorstStatus @(
        $SkillsSync,
        $ProjectSync,
        $ImprovementFlow,
        $SkillsProviders,
        $AuditStatus
    ))
}
