#Requires -Version 5.1
# MB-SM-077D Slice B: fixture tests for INTERACTIVE_SAFETY section 23
# variable-colon parser class. In-memory fixtures only; does not scan Skill .txt
# documentation (those files may illustrate unsafe examples on purpose).
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Get-RiskyVariableColonMatches {
    param([Parameter(Mandatory = $true)][string]$Text)
    $pattern = '\$[A-Za-z_][A-Za-z0-9_]*:'
    $list = [System.Collections.Generic.List[object]]::new()
    foreach ($match in [regex]::Matches($Text, $pattern)) {
        if ($match.Value -notmatch '^\$env:$|^\$script:$|^\$global:$|^\$local:$|^\$private:$') {
            $list.Add($match) | Out-Null
        }
    }
    return [object[]]$list.ToArray()
}

$failed = 0
function Assert-True {
    param($Cond, $Msg)
    if (-not $Cond) {
        Write-Host "FAIL: $Msg"
        $script:failed++
    }
    else {
        Write-Host "PASS: $Msg"
    }
}

# Unsafe-positive: colon immediately after an unscoped variable.
$unsafeNameHits = @(Get-RiskyVariableColonMatches -Text '$name: value')
$unsafePathHits = @(Get-RiskyVariableColonMatches -Text '$path:$line')
Assert-True ($unsafeNameHits.Count -ge 1) 'Unsafe-positive $name: value is detected'
Assert-True ($unsafePathHits.Count -ge 1) 'Unsafe-positive $path:$line is detected'

# Safe-negative: explicit delimiters.
$safeBraceHits = @(Get-RiskyVariableColonMatches -Text '${name}: value')
$safeSubHits = @(Get-RiskyVariableColonMatches -Text '$($path):$line')
Assert-True ($safeBraceHits.Count -eq 0) 'Safe-negative ${name}: value is not flagged'
Assert-True ($safeSubHits.Count -eq 0) 'Safe-negative $($path):$line is not flagged'

# Allowed scoped / drive variables.
$allowedHits = @(Get-RiskyVariableColonMatches -Text '$env:TEMP $script:Foo $global:Bar $local:Baz $private:Qux')
Assert-True ($allowedHits.Count -eq 0) 'Allowed $env/$script/$global/$local/$private colons are not flagged'

# Ordinary colons that must not trigger.
$ordinaryHits = @(Get-RiskyVariableColonMatches -Text 'C:\Windows ratio 1:2 label: comment hashtable Name = value')
Assert-True ($ordinaryHits.Count -eq 0) 'Ordinary colons without a preceding variable are not flagged'

# PowerShell-specific: mixed line still flags only the unsafe token.
$mixedHits = @(Get-RiskyVariableColonMatches -Text 'Write-Host ${ok}: start; Write-Host $bad: end')
Assert-True ($mixedHits.Count -eq 1) 'Mixed line flags only the unscoped variable-colon'
if ($mixedHits.Count -ge 1) {
    Assert-True ($mixedHits[0].Value -eq '$bad:') 'Mixed-line hit is $bad:'
}

# Canon documents the blocker name after 077D absorption.
$skillPath = Join-Path $PSScriptRoot '..\..\..\SkillsLake\01.SKILLS\SKILL.POWERSHELL.INTERACTIVE_SAFETY.txt'
$skillPath = [System.IO.Path]::GetFullPath($skillPath)
Assert-True (Test-Path -LiteralPath $skillPath) 'INTERACTIVE_SAFETY skill file exists'
$skillText = Get-Content -LiteralPath $skillPath -Raw
Assert-True ($skillText -match 'POWERSHELL_RISKY_VARIABLE_COLON_PATTERN') 'Skill documents POWERSHELL_RISKY_VARIABLE_COLON_PATTERN'
Assert-True ($skillText -match 'VERSION\.*:\s*1\.4') 'Skill version is 1.4'
Assert-True ($skillText -match '22\.6 PARSER GATE') 'Existing ParseFile probe section 22.6 remains'

if ($failed -gt 0) {
    Write-Host "PARSER_TESTS=FAIL FAILED=$failed"
    exit 1
}
Write-Host 'PARSER_TESTS=PASS'
exit 0
