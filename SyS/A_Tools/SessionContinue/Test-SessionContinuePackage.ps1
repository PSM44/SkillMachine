#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$RepoRoot = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $here = $PSCommandPath
    if ([string]::IsNullOrWhiteSpace($here)) { $here = $MyInvocation.MyCommand.Path }
    if ([string]::IsNullOrWhiteSpace($here)) { throw 'Cannot resolve test script path' }
    $RepoRoot = (Resolve-Path (Join-Path (Split-Path -Parent $here) '..\..\..')).Path
}
$failed = 0
function Assert-True($cond, $msg) {
    if (-not $cond) { Write-Host "FAIL: $msg"; $script:failed++ } else { Write-Host "PASS: $msg" }
}

function Get-SessionContinuePackageSufficiency {
    param([Parameter(Mandatory = $true)][string]$Text)
    $hasSection = $Text.Contains('USER_WORKING_PROFILE_AND_C1_CONTINUITY')
    $project = ($Text -match '(?m)^PROJECT_CONTEXT_PRESENT=YES\s*$')
    $profile = ($Text -match '(?m)^USER_WORKING_PROFILE_PRESENT=YES\s*$')
    $c1 = ($Text -match '(?m)^C1_CONTINUITY_PRESENT=YES\s*$')
    $ops = ($Text -match '(?m)^OPERATIONAL_PREFERENCES_PRESENT=YES\s*$')
    $temp = ($Text -match '(?m)^TEMP_POLICY_PRESENT=YES\s*$')
    $auth = ($Text -match '(?m)^AUTHORITY_MODEL_PRESENT=YES\s*$')
    $noExtra = ($Text -match '(?m)^ADDITIONAL_PROMPT_REQUIRED_FOR_SESSION_START=NO\s*$')
    $all = $hasSection -and $project -and $profile -and $c1 -and $ops -and $temp -and $auth -and $noExtra
    return [pscustomobject]@{
        SECTION_PRESENT = $hasSection
        ALL_GATES_YES = $all
        PACKAGE_SUFFICIENCY_FOR_SESSION_START = $(if ($all) { 'PASS' } else { 'FAIL' })
    }
}

$sourcePrompt = Join-Path $RepoRoot 'SyS\A_Tools\UseCaseSources\03.SessionContinue\PROMPT.SESSION_CONTINUE.txt'
$generatedPrompt = Join-Path $RepoRoot '90.USECASE\03.SESSION_CONTINUE\PROMPT.SESSION_CONTINUE.txt'
$profilePath = Join-Path $RepoRoot 'SyS\A_Tools\SessionContinue\USER_WORKING_PROFILE_AND_C1_CONTINUITY.txt'
$collector = Join-Path $RepoRoot 'SyS\A_Tools\SessionContinue\New-SessionContinuePackage.ps1'

Assert-True (Test-Path -LiteralPath $profilePath) 'Canonical working profile exists'
Assert-True (Test-Path -LiteralPath $collector) 'Continuation collector exists'
$profileText = Get-Content -LiteralPath $profilePath -Raw -Encoding UTF8
Assert-True ($profileText.Contains('USER_WORKING_PROFILE_AND_C1_CONTINUITY')) 'Profile file has required section name'
Assert-True ($profileText -match 'DEFAULT_INTERACTION_LANGUAGE=English') 'Profile default English'
Assert-True ($profileText -match 'NOT_PRODUCT_DOCTRINE=YES') 'Profile declares it is not product doctrine'
Assert-True ($profileText -match 'ROLE=ORCHESTRATOR') 'Profile has ORCHESTRATOR role'
Assert-True ($profileText -match 'ROLE=EXECUTOR') 'Profile has EXECUTOR role'
Assert-True ($profileText -match 'T\.AI\.SkillMachine') 'Profile has temp policy'
Assert-True ($profileText -match 'human = final authority') 'Profile has authority model'
Assert-True ($profileText -match 'FIRST_LINE_MUST_BE_UNIQUE_ID_CODE') 'Profile requires unique prompt ID'
Assert-True ($profileText -match 'USE_MAXIMUM_PRACTICAL_NON_INTERFERING_LOOPS') 'Profile requires max safe loops'
Assert-True ($profileText -match 'MAX_ITERATIONS_PER_LOOP=6') 'Profile has max iterations per loop'
Assert-True ($profileText -match 'WBS-like numbered structure') 'Profile has WBS-like reporting preference'

foreach ($p in @($sourcePrompt, $generatedPrompt)) {
    Assert-True (Test-Path -LiteralPath $p) ("Prompt exists: " + $p)
    $pt = Get-Content -LiteralPath $p -Raw -Encoding UTF8
    Assert-True ($pt.Contains('USER_WORKING_PROFILE_AND_C1_CONTINUITY')) ("Prompt has working-profile section: " + $p)
    Assert-True ($pt -match 'PACKAGE_SUFFICIENCY_FOR_SESSION_START') ("Prompt has session-start gate: " + $p)
    Assert-True ($pt -match 'ADDITIONAL_PROMPT_REQUIRED_FOR_SESSION_START') ("Prompt has extra-prompt rule: " + $p)
    Assert-True ($pt -match 'GENERIC_CONTINUATION_RULE|durable user working-profile') ("Prompt has generic continuation rule: " + $p)
    Assert-True ($pt -notmatch 'explain something to me') ("Prompt does not inline operator C1 patterns: " + $p)
    Assert-True ($pt -notmatch 'CAMBRIDGE_C1_PREPARATION=YES') ("Prompt does not inline C1 product doctrine: " + $p)
}

$humanOp = Join-Path $RepoRoot 'HUMAN\HUMAN.OPERATING.MODEL.txt'
$humanReadme = Join-Path $RepoRoot 'HUMAN\HUMAN.README.txt'
$humanOpText = Get-Content -LiteralPath $humanOp -Raw -Encoding UTF8
$humanReadmeText = Get-Content -LiteralPath $humanReadme -Raw -Encoding UTF8
Assert-True ($humanOpText -match 'operator payload, not SkillsMachine product doctrine') 'HUMAN operating model isolates operator payload'
Assert-True ($humanOpText -notmatch 'English is the default interaction language') 'HUMAN does not hard-code English as product doctrine'
Assert-True ($humanReadmeText -match 'operator payload, not product doctrine') 'HUMAN README isolates C1 from product doctrine'
Assert-True ($humanReadmeText -notmatch 'must include USER_WORKING_PROFILE_AND_C1_CONTINUITY') 'HUMAN README does not treat C1 filename as product doctrine'

$neg = @"
PROJECT=PS.SkillsMachine
ROLE=ORCHESTRATOR
PACKAGE_TYPE=SESSION_CONTINUE
PROJECT_CONTEXT_PRESENT=YES
USER_WORKING_PROFILE_PRESENT=NO
C1_CONTINUITY_PRESENT=NO
OPERATIONAL_PREFERENCES_PRESENT=YES
TEMP_POLICY_PRESENT=YES
AUTHORITY_MODEL_PRESENT=YES
ADDITIONAL_PROMPT_REQUIRED_FOR_SESSION_START=YES
"@
$negGate = Get-SessionContinuePackageSufficiency -Text $neg
Assert-True ($negGate.PACKAGE_SUFFICIENCY_FOR_SESSION_START -eq 'FAIL') 'ORCHESTRATOR package omitting profile fails gate'

$negExec = $neg.Replace('ROLE=ORCHESTRATOR', 'ROLE=EXECUTOR')
$negExecGate = Get-SessionContinuePackageSufficiency -Text $negExec
Assert-True ($negExecGate.PACKAGE_SUFFICIENCY_FOR_SESSION_START -eq 'FAIL') 'EXECUTOR package omitting profile fails gate'

$negProfileOnly = @"
USER_WORKING_PROFILE_AND_C1_CONTINUITY
PROJECT_CONTEXT_PRESENT=YES
USER_WORKING_PROFILE_PRESENT=NO
C1_CONTINUITY_PRESENT=YES
OPERATIONAL_PREFERENCES_PRESENT=YES
TEMP_POLICY_PRESENT=YES
AUTHORITY_MODEL_PRESENT=YES
ADDITIONAL_PROMPT_REQUIRED_FOR_SESSION_START=NO
"@
Assert-True ((Get-SessionContinuePackageSufficiency -Text $negProfileOnly).PACKAGE_SUFFICIENCY_FOR_SESSION_START -eq 'FAIL') 'Omit user profile fails gate'

$negC1Only = @"
USER_WORKING_PROFILE_AND_C1_CONTINUITY
PROJECT_CONTEXT_PRESENT=YES
USER_WORKING_PROFILE_PRESENT=YES
C1_CONTINUITY_PRESENT=NO
OPERATIONAL_PREFERENCES_PRESENT=YES
TEMP_POLICY_PRESENT=YES
AUTHORITY_MODEL_PRESENT=YES
ADDITIONAL_PROMPT_REQUIRED_FOR_SESSION_START=NO
"@
Assert-True ((Get-SessionContinuePackageSufficiency -Text $negC1Only).PACKAGE_SUFFICIENCY_FOR_SESSION_START -eq 'FAIL') 'Omit C1 continuity fails gate'

$negAuthOnly = @"
USER_WORKING_PROFILE_AND_C1_CONTINUITY
PROJECT_CONTEXT_PRESENT=YES
USER_WORKING_PROFILE_PRESENT=YES
C1_CONTINUITY_PRESENT=YES
OPERATIONAL_PREFERENCES_PRESENT=YES
TEMP_POLICY_PRESENT=YES
AUTHORITY_MODEL_PRESENT=NO
ADDITIONAL_PROMPT_REQUIRED_FOR_SESSION_START=NO
"@
Assert-True ((Get-SessionContinuePackageSufficiency -Text $negAuthOnly).PACKAGE_SUFFICIENCY_FOR_SESSION_START -eq 'FAIL') 'Omit authority model fails gate'

$negProjectOnly = @"
USER_WORKING_PROFILE_AND_C1_CONTINUITY
PROJECT_CONTEXT_PRESENT=NO
USER_WORKING_PROFILE_PRESENT=YES
C1_CONTINUITY_PRESENT=YES
OPERATIONAL_PREFERENCES_PRESENT=YES
TEMP_POLICY_PRESENT=YES
AUTHORITY_MODEL_PRESENT=YES
ADDITIONAL_PROMPT_REQUIRED_FOR_SESSION_START=NO
"@
Assert-True ((Get-SessionContinuePackageSufficiency -Text $negProjectOnly).PACKAGE_SUFFICIENCY_FOR_SESSION_START -eq 'FAIL') 'Omit project context fails gate'

$testTemp = Join-Path $env:TEMP ('SessionContinuePkg.{0}' -f ([guid]::NewGuid().ToString('N')))
New-Item -ItemType Directory -Path $testTemp -Force | Out-Null
try {
    foreach ($role in @('ORCHESTRATOR', 'EXECUTOR')) {
        $outName = ('TEST_{0}.txt' -f $role)
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $collector -PackageRole $role -RepoRoot $RepoRoot -TempRoot $testTemp -OutputFileName $outName -SkipPurge
        Assert-True ($LASTEXITCODE -eq 0) ("Collector exit 0 for " + $role)
        $outPath = Join-Path $testTemp $outName
        Assert-True (Test-Path -LiteralPath $outPath) ("Collector wrote " + $role)
        $built = Get-Content -LiteralPath $outPath -Raw -Encoding UTF8
        $gate = Get-SessionContinuePackageSufficiency -Text $built
        Assert-True ($gate.PACKAGE_SUFFICIENCY_FOR_SESSION_START -eq 'PASS') ("Built " + $role + " package passes session-start gate")
        Assert-True ($built -match ('ROLE={0}' -f $role)) ("Built package role " + $role)
        Assert-True ($built.Contains('explain something to me')) ("Built package preserves C1 patterns " + $role)
        Assert-True ($built -match '(?m)^STAGE_14=') ("Built package has STAGE_14 " + $role)
        Assert-True ($built -match 'NEXT_REAL_CLOSEREPORT_CONTINUITY_DEPENDENT_EVENT') ("Built package has Stage-14 gate " + $role)
        Assert-True ($built -match 'Do not immediately run another ProjectOps mutation') ("Built package has first-action contract " + $role)
        Assert-True ($built -match '(?m)^DEFER=') ("Built package classifies DEFER dirt " + $role)
        Assert-True ($built -match 'HISTORICAL_SNAPSHOT_NOT_CURRENT_AUTHORITY=YES') ("Built package distinguishes historical snapshots " + $role)
        Assert-True ($built -match 'BATON=COLD_START_CONTINUITY_IN_BLANK_AI_CONTEXT') ("Built package preserves BATON role " + $role)
        Assert-True ($built -match '(?m)^AI_HISTORY_INCLUDED=NO\s*$') ("Built package excludes AI_History " + $role)
        Assert-True ($built -match 'Apply USER_WORKING_PROFILE_AND_C1_CONTINUITY before substantive work') ("Built package START HERE applies profile " + $role)
        Assert-True ($built -notmatch '(?m)^yS/') ("Built package does not truncate git status paths " + $role)
        Assert-True ($built -match '(?m)^CURRENT_ACTIVE_MUTATION=NONE\s*$') ("Built package has no active mutation " + $role)
        Assert-True ($built -match '(?m)^UNRESOLVED_COMMIT_GATE=') ("Built package reports commit gate " + $role)
        Assert-True ($built -match '(?m)^NEXT_GENUINE_GATE=NEXT_REAL_CLOSEREPORT_CONTINUITY_DEPENDENT_EVENT\s*$') ("Built package has genuine Stage-14 gate " + $role)
    }
    $dirs = @(Get-ChildItem -LiteralPath $testTemp -Force -Directory)
    Assert-True ($dirs.Count -eq 0) 'Collector temp remains flat'
}
finally {
    if (Test-Path -LiteralPath $testTemp) {
        Remove-Item -LiteralPath $testTemp -Recurse -Force
    }
}

$tokens = $null; $errs = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($collector, [ref]$tokens, [ref]$errs)
$errCount = 0
if ($null -ne $errs) { $errCount = @($errs).Count }
Assert-True ($errCount -eq 0) 'Collector parse errors = 0'
$rawCol = Get-Content -LiteralPath $collector -Raw
$risky = @([regex]::Matches($rawCol, '\$[A-Za-z_][A-Za-z0-9_]*:') | Where-Object {
        $_.Value -notmatch '^\$env:$|^\$script:$|^\$global:$|^\$local:$|^\$private:$'
    })
Assert-True ($risky.Count -eq 0) 'Collector has no unsafe variable-colon'

if ($failed -gt 0) {
    Write-Host ("TEST_SUMMARY=FAIL count={0}" -f $failed)
    exit 1
}
Write-Host 'TEST_SUMMARY=PASS'
exit 0
