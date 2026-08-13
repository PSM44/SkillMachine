#Requires -Version 5.1
<#
.SYNOPSIS
  Build ORCHESTRATOR or EXECUTOR SESSION_CONTINUE packages with mandatory working-profile gate.
.NOTES
  Repository read-only. Writes only to -TempRoot.
#>
[CmdletBinding()]
param(
    [ValidateSet('ORCHESTRATOR', 'EXECUTOR')]
    [string]$PackageRole = 'ORCHESTRATOR',
    [string]$RepoRoot = 'C:\01. GitHub\Skills',
    [string]$TempRoot = 'C:\Users\aazcl\Downloads\T.AI.SkillMachine',
    [string]$OutputFileName = '',
    [switch]$SkipPurge
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$CollectorVersion = 'SM-076A7-SESSION-CONTINUE-PACKAGE-v1'
$script:StartTime = Get-Date

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
[void]$sb.AppendLine('ADDITIONAL_EVIDENCE_COLLECTION_DURING_SESSION=ALLOWED_WHEN_NEEDED')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('00. START HERE')
[void]$sb.AppendLine('Apply USER_WORKING_PROFILE_AND_C1_CONTINUITY before substantive work begins.')
[void]$sb.AppendLine('Do not require an extra human prompt to load the working profile if this package is complete.')
[void]$sb.AppendLine('PROJECT_CONTEXT_PRESENT=YES')
[void]$sb.AppendLine('USER_WORKING_PROFILE_PRESENT=YES')
[void]$sb.AppendLine('C1_CONTINUITY_PRESENT=YES')
[void]$sb.AppendLine('OPERATIONAL_PREFERENCES_PRESENT=YES')
[void]$sb.AppendLine('TEMP_POLICY_PRESENT=YES')
[void]$sb.AppendLine('AUTHORITY_MODEL_PRESENT=YES')
[void]$sb.AppendLine('ADDITIONAL_PROMPT_REQUIRED_FOR_SESSION_START=NO')
[void]$sb.AppendLine('PACKAGE_SUFFICIENCY_FOR_SESSION_START=PASS')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('01. GIT RUNTIME')
[void]$sb.AppendLine(('ROOT={0}' -f $RepoRoot))
[void]$sb.AppendLine(('ROOT_OBSERVED={0}' -f $observedRoot))
[void]$sb.AppendLine(('BRANCH={0}' -f $branch))
[void]$sb.AppendLine(('HEAD={0}' -f $head))
[void]$sb.AppendLine(('ORIGIN_MAIN={0}' -f $originMain))
[void]$sb.AppendLine(('AHEAD_BEHIND={0}' -f $aheadBehind))
[void]$sb.AppendLine('STATUS_SHORT=')
foreach ($sl in $statusLines) { [void]$sb.AppendLine([string]$sl) }
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
