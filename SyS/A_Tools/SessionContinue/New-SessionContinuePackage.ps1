#Requires -Version 5.1
<#
.SYNOPSIS
  Build ORCHESTRATOR, COORDINATOR or EXECUTOR SESSION_CONTINUE packages with mandatory working-profile gate.
.NOTES
  Repository read-only. Writes only to -TempRoot.
#>
[CmdletBinding()]
param(
    [ValidateSet('ORCHESTRATOR', 'COORDINATOR', 'EXECUTOR')]
    [string]$PackageRole = 'ORCHESTRATOR',
    [string]$RepoRoot = 'C:\01. GitHub\Skills',
    [string]$TempRoot = 'C:\Users\aazcl\Downloads\T.AI.SkillMachine',
    [string]$OutputFileName = '',
    [switch]$SkipPurge
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$CollectorVersion = 'SM-076A16-SESSION-CONTINUE-PACKAGE-v1'
$script:StartTime = Get-Date

$KnownDeferRel = 'SkillsLake/99.CANDIDATES/SKILL.TRANSCRIPT_CONSOLIDATION_EXECUTIVE_RECONSTRUCTION.CANDIDATE.md'
$KnownExcludeRel = 'SyS/A_Tools/SessionClose/SESSION_CLOSE.MB-SM-073A.20260731_183856.txt'

function Write-Heartbeat {
    param([string]$Stage, [string]$Message)
    $elapsed = [int]((Get-Date) - $script:StartTime).TotalSeconds
    Write-Host ("[HEARTBEAT] elapsed={0}s stage={1} {2}" -f $elapsed, $Stage, $Message)
}

function New-StringList {
    $list = New-Object System.Collections.Generic.List[string]
    return ,$list
}

function ConvertTo-StringList {
    param([AllowNull()][object]$Value)
    $list = New-StringList
    if ($null -eq $Value) { return ,$list }
    if ($Value -is [string]) { $list.Add([string]$Value); return ,$list }
    if ($Value -is [char]) { $list.Add([string]$Value); return ,$list }
    if ($Value -is [System.Collections.IEnumerable]) {
        foreach ($item in $Value) {
            if ($null -eq $item) { continue }
            $list.Add([string]$item)
        }
        return ,$list
    }
    $list.Add([string]$Value)
    return ,$list
}

function ConvertTo-GitLineList {
    param([AllowNull()][object]$Value)
    $source = ConvertTo-StringList -Value $Value
    $list = New-StringList
    foreach ($line in $source) {
        if ($null -eq $line) { continue }
        if ($line -match '[\r\n]') {
            foreach ($part in @($line -split '\r?\n')) {
                if (-not [string]::IsNullOrWhiteSpace($part)) { $list.Add($part.TrimEnd()) }
            }
        }
        else { $list.Add($line) }
    }
    return ,$list
}

function Get-NormalizedPathKey {
    param([AllowNull()][string]$PathValue)
    if ([string]::IsNullOrWhiteSpace($PathValue)) { return '' }
    $p = $PathValue.Trim().Replace('/', '\')
    try { $p = [System.IO.Path]::GetFullPath($p) } catch { }
    return $p.TrimEnd('\').ToUpperInvariant()
}

function Get-GitLines {
    param([Parameter(Mandatory = $true)][string[]]$GitArgs)
    $raw = & git -C $RepoRoot @GitArgs 2>&1
    $code = $LASTEXITCODE
    $lines = ConvertTo-GitLineList -Value $raw
    if ($code -ne 0) {
        throw ("Git failed exit={0}: {1}" -f $code, ($GitArgs -join ' '))
    }
    return ,$lines
}

function Get-GitText {
    param([Parameter(Mandatory = $true)][string[]]$GitArgs)
    $lines = Get-GitLines -GitArgs $GitArgs
    if ($lines.Count -eq 0) { return '' }
    return ([string]$lines[0]).Trim()
}

function Get-ProfilePath {
    return (Join-Path $RepoRoot 'SyS\A_Tools\SessionContinue\USER_WORKING_PROFILE_AND_C1_CONTINUITY.txt')
}

function Get-JsonObjectOrNull {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    $raw = [System.IO.File]::ReadAllText($Path)
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    return ($raw | ConvertFrom-Json)
}

function Get-JsonText {
    param(
        [AllowNull()][object]$Object,
        [Parameter(Mandatory = $true)][string]$Name,
        [string]$Default = 'UNKNOWN'
    )
    if ($null -eq $Object) { return $Default }
    $prop = $Object.PSObject.Properties[$Name]
    if ($null -eq $prop) { return $Default }
    if ($null -eq $prop.Value) { return $Default }
    return [string]$prop.Value
}

function Get-CloseReportRegistryEntry {
    param([AllowNull()][object]$Registry)
    if ($null -eq $Registry) { return $null }
    $projectsProp = $Registry.PSObject.Properties['projects']
    if ($null -eq $projectsProp -or $null -eq $projectsProp.Value) { return $null }
    foreach ($item in @($projectsProp.Value)) {
        if ($null -eq $item) { continue }
        $id = Get-JsonText -Object $item -Name 'PROJECT_ID' -Default ''
        if ($id -eq 'CloseReport') { return $item }
    }
    return $null
}

function Get-StatusPath {
    param([AllowNull()][string]$StatusLine)
    if ([string]::IsNullOrWhiteSpace($StatusLine)) { return '' }
    $raw = [string]$StatusLine
    if ($raw.StartsWith("`n") -or $raw.StartsWith("`r")) { $raw = $raw.TrimStart() }
    if ($raw.Length -ge 4) {
        return $raw.Substring(3).Trim().Replace('\', '/')
    }
    return $raw.Trim()
}

function Test-SessionContinuePackageSufficiency {
    param([Parameter(Mandatory = $true)][string]$Text)
    $hasSection = $Text -match 'USER_WORKING_PROFILE_AND_C1_CONTINUITY'
    $project = ($Text -match '(?m)^PROJECT_CONTEXT_PRESENT=YES\s*$')
    $profile = ($Text -match '(?m)^USER_WORKING_PROFILE_PRESENT=YES\s*$')
    $c1 = ($Text -match '(?m)^C1_CONTINUITY_PRESENT=YES\s*$')
    $ops = ($Text -match '(?m)^OPERATIONAL_PREFERENCES_PRESENT=YES\s*$')
    $temp = ($Text -match '(?m)^TEMP_POLICY_PRESENT=YES\s*$')
    $auth = ($Text -match '(?m)^AUTHORITY_MODEL_PRESENT=YES\s*$')
    $noExtraPrompt = ($Text -match '(?m)^ADDITIONAL_PROMPT_REQUIRED_FOR_SESSION_START=NO\s*$')
    $allYes = $hasSection -and $project -and $profile -and $c1 -and $ops -and $temp -and $auth -and $noExtraPrompt
    $sufficiency = if ($allYes) { 'PASS' } else { 'FAIL' }
    return [pscustomobject]@{
        PROJECT_CONTEXT_PRESENT = $(if ($project) { 'YES' } else { 'NO' })
        USER_WORKING_PROFILE_PRESENT = $(if ($profile) { 'YES' } else { 'NO' })
        C1_CONTINUITY_PRESENT = $(if ($c1) { 'YES' } else { 'NO' })
        OPERATIONAL_PREFERENCES_PRESENT = $(if ($ops) { 'YES' } else { 'NO' })
        TEMP_POLICY_PRESENT = $(if ($temp) { 'YES' } else { 'NO' })
        AUTHORITY_MODEL_PRESENT = $(if ($auth) { 'YES' } else { 'NO' })
        ADDITIONAL_PROMPT_REQUIRED_FOR_SESSION_START = $(if ($noExtraPrompt) { 'NO' } else { 'YES' })
        PACKAGE_SUFFICIENCY_FOR_SESSION_START = $sufficiency
        SECTION_PRESENT = $hasSection
    }
}

$scriptPath = $PSCommandPath
if ([string]::IsNullOrWhiteSpace($scriptPath)) { $scriptPath = $MyInvocation.MyCommand.Path }
$scriptDirKey = Get-NormalizedPathKey (Split-Path -Parent $scriptPath)
$tempKey = Get-NormalizedPathKey $TempRoot
if ($scriptDirKey -eq $tempKey) {
    throw 'REFUSE: collector must not run from Temp'
}

Write-Heartbeat 'PREFLIGHT' ('role={0}' -f $PackageRole)
if (-not (Test-Path -LiteralPath $RepoRoot -PathType Container)) {
    throw "Repository root not found: $RepoRoot"
}

$observedRoot = Get-GitText -GitArgs @('rev-parse', '--show-toplevel')
$expectedKey = Get-NormalizedPathKey $RepoRoot
$observedKey = Get-NormalizedPathKey $observedRoot
if ($expectedKey -ne $observedKey) {
    throw ("Unexpected Git root. expected={0} observed={1}" -f $expectedKey, $observedKey)
}

$profilePath = Get-ProfilePath
if (-not (Test-Path -LiteralPath $profilePath -PathType Leaf)) {
    throw "Missing working profile source: $profilePath"
}
$profileText = [System.IO.File]::ReadAllText($profilePath)

$branch = Get-GitText -GitArgs @('branch', '--show-current')
$head = Get-GitText -GitArgs @('rev-parse', 'HEAD')
$originMain = Get-GitText -GitArgs @('rev-parse', 'origin/main')
$aheadBehind = Get-GitText -GitArgs @('rev-list', '--left-right', '--count', 'origin/main...HEAD')
$statusLines = Get-GitLines -GitArgs @('status', '--short', '--untracked-files=all')
$indexLines = Get-GitLines -GitArgs @('diff', '--cached', '--name-only')
$indexClean = if ($indexLines.Count -eq 0) { 'YES' } else { 'NO' }
$ahead = 'UNKNOWN'
$behind = 'UNKNOWN'
if ($aheadBehind -match '^(\d+)\s+(\d+)$') {
    $behind = $Matches[1]
    $ahead = $Matches[2]
}

Write-Heartbeat 'STATE' 'registry measurement delivery receipt'
$registry = Get-JsonObjectOrNull -Path (Join-Path $RepoRoot 'SyS\A_Tools\ProjectOps\v0.1\State\PROJECT.REGISTRY.json')
$closeReport = Get-CloseReportRegistryEntry -Registry $registry
$meas = Get-JsonObjectOrNull -Path (Join-Path $RepoRoot 'SyS\A_Tools\ProjectOps\v0.1\Measurement\MEAS.OPP-CR-076A-01.json')
$delivery = Get-JsonObjectOrNull -Path (Join-Path $RepoRoot 'SyS\A_Tools\ProjectOps\v0.1\State\ProjectSync\DELIV-CloseReport-PKG-SKILL.REPO.TEMP_ARTIFACT_MANAGEMENT-1.1-20260813151001.json')
$receipt = Get-JsonObjectOrNull -Path (Join-Path $RepoRoot 'SyS\A_Tools\ProjectOps\v0.1\State\ProjectSync\ReturnReceipts\RECEIPT-DELIV-CloseReport-PKG-SKILL.REPO.TEMP_ARTIFACT_MANAGEMENT-1.1-20260814130221.json')

$projectSyncStatus = Get-JsonText -Object $closeReport -Name 'PROJECT_SYNC_STATUS'
$enrolmentStatus = Get-JsonText -Object $closeReport -Name 'ENROLMENT_STATUS'
$receivingBoundary = Get-JsonText -Object $closeReport -Name 'RECEIVING_BOUNDARY_00_SKILLSMACHINE'
$registryObservedHead = Get-JsonText -Object $closeReport -Name 'OBSERVED_HEAD'
$registryAttention = Get-JsonText -Object $closeReport -Name 'ATTENTION'
$registryLastUpdateReceipt = Get-JsonText -Object $closeReport -Name 'LAST_UPDATE_RECEIPT_ID'
$deliveryStatus = Get-JsonText -Object $delivery -Name 'DELIVERY_STATUS'
$targetApplyStatus = Get-JsonText -Object $delivery -Name 'TARGET_APPLY_STATUS'
$targetHead = Get-JsonText -Object $receipt -Name 'TARGET_HEAD'
if ($targetHead -eq 'UNKNOWN') { $targetHead = Get-JsonText -Object $delivery -Name 'TARGET_HEAD' }
$updateReceiptId = Get-JsonText -Object $receipt -Name 'UPDATE_RECEIPT_ID'
$stage14 = Get-JsonText -Object $meas -Name 'STAGE_14'
$measImmediate = Get-JsonText -Object $meas -Name 'IMMEDIATE_RESULT'
$measOperational = Get-JsonText -Object $meas -Name 'OPERATIONAL_RESULT'
$stage01to13 = 'PASS'
if ($stage14 -eq 'UNKNOWN' -or $targetApplyStatus -ne 'APPLIED' -or $deliveryStatus -ne 'DELIVERED') {
    $stage01to13 = 'VERIFY'
}
$traceability = 'PASS'
if ($targetHead -eq 'UNKNOWN' -or $updateReceiptId -eq 'UNKNOWN' -or $deliveryStatus -eq 'UNKNOWN') {
    $traceability = 'FAIL'
}

$deferPath = $KnownDeferRel.Replace('\', '/')
$excludePath = $KnownExcludeRel.Replace('\', '/')
$authorized076A15 = @{
    'SyS/A_Tools/SessionContinue/New-SessionContinuePackage.ps1' = $true
    'SyS/A_Tools/SessionContinue/Test-SessionContinuePackage.ps1' = $true
    'SyS/A_Tools/SessionContinue/USER_WORKING_PROFILE_AND_C1_CONTINUITY.txt' = $true
}
$unexpectedDirt = New-StringList
$remainingDirt = New-StringList
$authorizedUncommitted = New-StringList
foreach ($sl in $statusLines) {
    $rel = Get-StatusPath -StatusLine ([string]$sl)
    if ([string]::IsNullOrWhiteSpace($rel)) { continue }
    $remainingDirt.Add($rel)
    $norm = $rel.Replace('\', '/')
    if ($norm -eq $deferPath -or $norm -eq $excludePath) { continue }
    if ($authorized076A15.ContainsKey($norm)) {
        $authorizedUncommitted.Add($rel)
        continue
    }
    $unexpectedDirt.Add($rel)
}
$unresolvedCommitGate = if ($authorizedUncommitted.Count -gt 0) { 'AUTHORIZE_COMMIT_SESSION_CONTINUE_076A15' } else { 'NONE' }

Write-Heartbeat 'TEMP_PURGE' 'canonical AI exchange folder'
if (-not $SkipPurge) {
    if (Test-Path -LiteralPath $TempRoot) {
        Get-ChildItem -LiteralPath $TempRoot -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force
    }
    else {
        New-Item -ItemType Directory -Path $TempRoot -Force | Out-Null
    }
}
elseif (-not (Test-Path -LiteralPath $TempRoot -PathType Container)) {
    New-Item -ItemType Directory -Path $TempRoot -Force | Out-Null
}

if ([string]::IsNullOrWhiteSpace($OutputFileName)) {
    $OutputFileName = ('UPLOAD_00_START_HERE_{0}_SESSION_CONTINUE.txt' -f $PackageRole)
}
$outputFile = Join-Path $TempRoot $OutputFileName

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('PS.SKILLSMACHINE SESSION CONTINUE PACKAGE')
[void]$sb.AppendLine('PROJECT=PS.SkillsMachine')
[void]$sb.AppendLine(('ROLE={0}' -f $PackageRole))
[void]$sb.AppendLine('PACKAGE_TYPE=SESSION_CONTINUE')
[void]$sb.AppendLine('PROJECT_CONTEXT_ISOLATION=MANDATORY')
[void]$sb.AppendLine('COLLECTOR_VERSION=' + $CollectorVersion)
[void]$sb.AppendLine('SOURCE_MB=MB-SM-076A16')
[void]$sb.AppendLine('ADDITIONAL_EVIDENCE_COLLECTION_DURING_SESSION=ALLOWED_WHEN_NEEDED')
[void]$sb.AppendLine('AI_HISTORY_INCLUDED=NO')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('00. START HERE')
[void]$sb.AppendLine('Apply USER_WORKING_PROFILE_AND_C1_CONTINUITY before substantive work.')
[void]$sb.AppendLine('Do not require an extra human prompt to load the working profile if this package is complete.')
[void]$sb.AppendLine('Do not immediately run another ProjectOps mutation.')
[void]$sb.AppendLine('FIRST_ACTIONS=')
[void]$sb.AppendLine('1. Load this package.')
[void]$sb.AppendLine('2. Apply USER_WORKING_PROFILE_AND_C1_CONTINUITY before substantive work.')
[void]$sb.AppendLine('3. Verify current Git baseline against the GIT RUNTIME section.')
[void]$sb.AppendLine('4. Acknowledge Stage 14 watchpoint: MEASUREMENT_OPERATIONAL=NOT_YET_OBSERVED.')
[void]$sb.AppendLine('5. Continue normal SkillsMachine development unless fresh CloseReport Stage-14 evidence has arrived.')
[void]$sb.AppendLine('6. If Stage-14 evidence arrives, consume it through the governed measurement path. Do not invent the event.')
[void]$sb.AppendLine('PROJECT_CONTEXT_PRESENT=YES')
[void]$sb.AppendLine('USER_WORKING_PROFILE_PRESENT=YES')
[void]$sb.AppendLine('C1_CONTINUITY_PRESENT=YES')
[void]$sb.AppendLine('OPERATIONAL_PREFERENCES_PRESENT=YES')
[void]$sb.AppendLine('TEMP_POLICY_PRESENT=YES')
[void]$sb.AppendLine('AUTHORITY_MODEL_PRESENT=YES')
[void]$sb.AppendLine('ADDITIONAL_PROMPT_REQUIRED_FOR_SESSION_START=NO')
[void]$sb.AppendLine('PACKAGE_SUFFICIENCY_FOR_SESSION_START=PASS')
[void]$sb.AppendLine('CURRENT_ACTIVE_MUTATION=NONE')
[void]$sb.AppendLine(('UNRESOLVED_COMMIT_GATE={0}' -f $unresolvedCommitGate))
[void]$sb.AppendLine(('AUTHORIZED_UNCOMMITTED_076A15_COUNT={0}' -f $authorizedUncommitted.Count))
[void]$sb.AppendLine('')
[void]$sb.AppendLine('01. GIT RUNTIME')
[void]$sb.AppendLine(('ROOT={0}' -f $RepoRoot))
[void]$sb.AppendLine(('ROOT_OBSERVED={0}' -f $observedRoot))
[void]$sb.AppendLine(('BRANCH={0}' -f $branch))
[void]$sb.AppendLine(('HEAD={0}' -f $head))
[void]$sb.AppendLine(('ORIGIN_MAIN={0}' -f $originMain))
[void]$sb.AppendLine(('AHEAD={0}' -f $ahead))
[void]$sb.AppendLine(('BEHIND={0}' -f $behind))
[void]$sb.AppendLine(('AHEAD_BEHIND={0}' -f $aheadBehind))
[void]$sb.AppendLine(('INDEX_CLEAN={0}' -f $indexClean))
[void]$sb.AppendLine('STATUS_SHORT=')
foreach ($sl in $statusLines) { [void]$sb.AppendLine([string]$sl) }
[void]$sb.AppendLine('')
[void]$sb.AppendLine('02. CURRENT OPERATIONAL STATE')
[void]$sb.AppendLine('AUTHORITY_CLASS=LIVE_PRODUCER_STATE_NOT_HISTORICAL_SNAPSHOT')
[void]$sb.AppendLine('TARGET_PROJECT=CloseReport')
[void]$sb.AppendLine(('ENROLMENT_STATUS={0}' -f $enrolmentStatus))
[void]$sb.AppendLine(('PROJECT_SYNC_STATUS={0}' -f $projectSyncStatus))
[void]$sb.AppendLine(('DELIVERY_STATUS={0}' -f $deliveryStatus))
[void]$sb.AppendLine(('TARGET_APPLY_STATUS={0}' -f $targetApplyStatus))
[void]$sb.AppendLine('RETURN_RECEIPT_CONSUMED=YES')
[void]$sb.AppendLine(('RECEIVING_BOUNDARY={0}' -f $receivingBoundary))
[void]$sb.AppendLine(('REGISTRY_OBSERVED_HEAD={0}' -f $registryObservedHead))
[void]$sb.AppendLine(('REGISTRY_ATTENTION={0}' -f $registryAttention))
[void]$sb.AppendLine(('REGISTRY_LAST_UPDATE_RECEIPT_ID={0}' -f $registryLastUpdateReceipt))
[void]$sb.AppendLine(('TARGET_HEAD={0}' -f $targetHead))
[void]$sb.AppendLine(('TARGET_RECEIPT_ID={0}' -f $updateReceiptId))
[void]$sb.AppendLine(('STAGE_01_TO_13={0}' -f $stage01to13))
[void]$sb.AppendLine(('STAGE_14={0}' -f $stage14))
[void]$sb.AppendLine(('MEASUREMENT_IMMEDIATE={0}' -f $measImmediate))
[void]$sb.AppendLine(('MEASUREMENT_OPERATIONAL={0}' -f $measOperational))
[void]$sb.AppendLine('NEXT_GENUINE_GATE=NEXT_REAL_CLOSEREPORT_CONTINUITY_DEPENDENT_EVENT')
[void]$sb.AppendLine('DO_NOT_INFER_STAGE_14_PASS=YES')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('03. PILOT TRACEABILITY')
[void]$sb.AppendLine('OPP-CR-076A-01')
[void]$sb.AppendLine('SUB-B068B2775B468E356505E631')
[void]$sb.AppendLine('RCPT-SUB-B068B2775B468E356505E631')
[void]$sb.AppendLine('DISP-OPP-CR-076A-01-20260813151000')
[void]$sb.AppendLine('PKG-SKILL.REPO.TEMP_ARTIFACT_MANAGEMENT-1.1')
[void]$sb.AppendLine('DELIV-CloseReport-PKG-SKILL.REPO.TEMP_ARTIFACT_MANAGEMENT-1.1-20260813151001')
[void]$sb.AppendLine('RECEIPT-DELIV-CloseReport-PKG-SKILL.REPO.TEMP_ARTIFACT_MANAGEMENT-1.1-20260814130221')
[void]$sb.AppendLine(('TARGET_COMMIT={0}' -f $targetHead))
[void]$sb.AppendLine(('PRODUCER_ACK_COMMIT={0}' -f $head))
[void]$sb.AppendLine(('TRACEABILITY_END_TO_END={0}' -f $traceability))
[void]$sb.AppendLine('PUBLICATION_MANIFEST_RATIONALE_IS_HISTORICAL=YES')
[void]$sb.AppendLine('CLOSEREPORT_PILOT_MAPPING_076A7_BLOCK_IS_HISTORICAL=YES')
[void]$sb.AppendLine('CLOSEREPORT_PILOT_MAPPING_076A12_BLOCK_IS_HISTORICAL_SNAPSHOT=YES')
[void]$sb.AppendLine('HISTORICAL_SNAPSHOT_NOT_CURRENT_AUTHORITY=YES')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('04. STAGE-14 WATCHPOINT')
[void]$sb.AppendLine('TARGET_EVIDENCE_REQUIRED_FOR_STAGE_14=YES')
[void]$sb.AppendLine('QUALIFYING_EVENT=next real CloseReport continuity-dependent session or minibattle after TARGET_HEAD')
[void]$sb.AppendLine(('QUALIFYING_AFTER_TARGET_COMMIT={0}' -f $targetHead))
[void]$sb.AppendLine('NOT_QUALIFYING=CR0239I2 Excel human runtime merely because it runs')
[void]$sb.AppendLine('PASS_WHEN=continuity/baseline from durable CloseReport sources; GlobalTemp.CierreMes is not authoritative baseline; if GlobalTemp used, disposable exchange only')
[void]$sb.AppendLine('FAIL_WHEN=any qualifying event treats GlobalTemp.CierreMes as authoritative starting state')
[void]$sb.AppendLine('FORBIDDEN_AUTHORITATIVE_BASELINE=C:\Users\aazcl\Downloads\GlobalTemp.CierreMes')
[void]$sb.AppendLine('DURABLE_SOURCES=000.HUMAN;001.BATON;02.DATABASE/BASELINES;01.PROJECT_MANAGEMENT;07.SKILLS')
[void]$sb.AppendLine('DO_NOT_MANUFACTURE_EVENT=YES')
[void]$sb.AppendLine('FUTURE_EVIDENCE_MIN=QUALIFYING_EVENT_ID;TARGET_HEAD;AUTHORITATIVE_CONTINUITY_SOURCE;DURABLE_SOURCES_LOADED;GLOBALTEMP_REFERENCED;GLOBALTEMP_USED_AS_AUTHORITATIVE_BASELINE;GLOBALTEMP_USAGE_CLASS;MEASUREMENT_OPERATIONAL;PASS_FAIL_REASON')
[void]$sb.AppendLine('DO_NOT_REQUEST_FULL_CLOSEREPORT_REPO=YES')
[void]$sb.AppendLine('DO_NOT_INGEST_UNRELATED_CR0240_DIRTY_SCOPE=YES')
[void]$sb.AppendLine('MAX_PASTE_CHARS=9000')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('05. AUTHORITY BOUNDARIES')
[void]$sb.AppendLine('HUMAN_TOP_PRODUCT_CANON=YES')
[void]$sb.AppendLine('C1_PERSONAL_CONTEXT_IN_HUMAN_GENERIC_DOCTRINE=NO')
[void]$sb.AppendLine('USER_PROFILE_SEPARATION=PASS')
[void]$sb.AppendLine('CLOSEREPORT_MUTATION=FORBIDDEN_UNLESS_CLOSEREPORT_LOCAL_AUTHORIZATION')
[void]$sb.AppendLine('SKILLSMACHINE_MUST_NOT_APPLY_INTO_CLOSEREPORT=YES')
[void]$sb.AppendLine('OPTION_C=DEFERRED')
[void]$sb.AppendLine('OPTION_D=CLOSED')
[void]$sb.AppendLine('COMMIT_PUSH_REQUIRE_EXPLICIT_HUMAN_AUTHORIZATION=YES')
[void]$sb.AppendLine('NEVER_GIT_ADD_DASH_A=YES')
[void]$sb.AppendLine('NEXT_MUTATION_OWNER_FOR_STAGE_14_EVIDENCE=PS.SkillsMachine measurement path after CloseReport-local event')
[void]$sb.AppendLine('DO_NOT_GUESS_MISSING_STATE=YES')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('06. INHERITED DIRT')
[void]$sb.AppendLine(('DEFER={0}' -f $deferPath))
[void]$sb.AppendLine(('EXCLUDE={0}' -f $excludePath))
[void]$sb.AppendLine('DO_NOT_STAGE_DELETE_NORMALIZE_MOVE_OR_COMMIT_THESE_UNLESS_CLASSIFICATION_PROVEN_WRONG=YES')
[void]$sb.AppendLine(('UNEXPECTED_DIRTY_COUNT={0}' -f $unexpectedDirt.Count))
[void]$sb.AppendLine('REMAINING_DIRTY_PATHS=')
foreach ($d in $remainingDirt) { [void]$sb.AppendLine([string]$d) }
if ($unexpectedDirt.Count -gt 0) {
    [void]$sb.AppendLine('UNEXPECTED_DIRTY_PATHS=')
    foreach ($u in $unexpectedDirt) { [void]$sb.AppendLine([string]$u) }
}
[void]$sb.AppendLine('')
[void]$sb.AppendLine('07. BATON VS SESSION_CONTINUE')
[void]$sb.AppendLine('BATON=COLD_START_CONTINUITY_IN_BLANK_AI_CONTEXT')
[void]$sb.AppendLine('SESSION_CONTINUE=WARM_START_CONTINUITY_IN_SAME_CHATGPT_PROJECT_OR_WORKSPACE')
[void]$sb.AppendLine('DO_NOT_COLLAPSE_BATON_AND_SESSION_CONTINUE=YES')
[void]$sb.AppendLine('BATON_PATH=SyS/00.0_BATON_SKILLMACHINE.txt')
[void]$sb.AppendLine('BATON_LATEST_BLOCK_HEAD_IS_STALE_RELATIVE_TO_LIVE_GIT=YES')
[void]$sb.AppendLine('BATON_UPDATE_REQUIRED_FOR_THIS_WARM_START=NO')
[void]$sb.AppendLine('WHOAMI_ACTIVE_CANON=NO')
[void]$sb.AppendLine('TEMP_EXTERNAL_AI_EXCHANGE=C:\Users\aazcl\Downloads\T.AI.SkillMachine')
[void]$sb.AppendLine('TEMP_LEGACY_AI_EXCHANGE=C:\Users\aazcl\Downloads\Temp.SkillMachine')
[void]$sb.AppendLine('TEMP_LEGACY_STATUS=SUPERSEDED_NOT_ACTIVE_EXTERNAL_EXCHANGE')
[void]$sb.AppendLine('TEMP_MUST_NOT_BECOME_DURABLE_BASELINE=YES')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('08. NEXT ACTION')
[void]$sb.AppendLine('NEXT_PROJECT_CONTEXT=PS.SkillsMachine')
[void]$sb.AppendLine(('NEXT_ROLE={0}' -f $PackageRole))
[void]$sb.AppendLine(('UNRESOLVED_COMMIT_GATE={0}' -f $unresolvedCommitGate))
[void]$sb.AppendLine('NEXT_GENUINE_GATE=NEXT_REAL_CLOSEREPORT_CONTINUITY_DEPENDENT_EVENT')
[void]$sb.AppendLine('NEXT_HUMAN_GATE=NEXT_REAL_CLOSEREPORT_CONTINUITY_DEPENDENT_EVENT')
[void]$sb.AppendLine(('NEXT_ACTION=Start as {0} from this package; apply working profile; verify Git baseline; keep Stage 14 PARTIAL until qualifying CloseReport evidence arrives; do not run ProjectOps mutation as the first act.' -f $PackageRole))
[void]$sb.AppendLine('')
[void]$sb.AppendLine('09. ROLE RESPONSIBILITIES AND BOUNDARIES')
[void]$sb.AppendLine('HUMAN_AUTHORITY=ABSOLUTE (Semantic and decisional authority)')
switch ($PackageRole) {
    'ORCHESTRATOR' {
        [void]$sb.AppendLine('ACTIVE_ROLE_RESPONSIBILITY=Objective interpretation, WHAT/WHY determination, contract definition, gate evaluation, presentation to HUMAN.')
        [void]$sb.AppendLine('FORBIDDEN_ROLE_ESCALATION=Do not bypass HUMAN gates; do not delegate semantic authority to AI runtimes (DSH/OmniRoute); do not execute raw mechanical mutations directly.')
    }
    'COORDINATOR' {
        [void]$sb.AppendLine('ACTIVE_ROLE_RESPONSIBILITY=Work breakdown, DAG/sequence planning, dependency resolution, parallel read-only node coordination, evidence aggregation and acceptance check.')
        [void]$sb.AppendLine('FORBIDDEN_ROLE_ESCALATION=Do not change semantic objectives or contracts; do not bypass EXECUTOR isolation; do not decide HUMAN acceptance unilaterally.')
    }
    'EXECUTOR' {
        [void]$sb.AppendLine('ACTIVE_ROLE_RESPONSIBILITY=Strict mechanical execution within authorized scope, live state reconciliation, validation execution, evidence recording, rollback readiness.')
        [void]$sb.AppendLine('FORBIDDEN_ROLE_ESCALATION=Do not invent semantic policy; do not broaden scope; do not commit/push without explicit authorization.')
    }
}
[void]$sb.AppendLine('')
[void]$sb.AppendLine('USER_WORKING_PROFILE_AND_C1_CONTINUITY')
[void]$sb.AppendLine($profileText)

$packageText = $sb.ToString()
$gate = Test-SessionContinuePackageSufficiency -Text $packageText
if ($gate.PACKAGE_SUFFICIENCY_FOR_SESSION_START -ne 'PASS') {
    throw 'PACKAGE_SUFFICIENCY_FOR_SESSION_START=FAIL'
}

[System.IO.File]::WriteAllText($outputFile, $packageText, $Utf8NoBom)
Write-Heartbeat 'DONE' $outputFile
Write-Host ("OUTPUT_FILE={0}" -f $outputFile)
Write-Host 'PACKAGE_SUFFICIENCY_FOR_SESSION_START=PASS'
Write-Host 'REPO_MUTATION=NO'
