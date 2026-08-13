#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
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
