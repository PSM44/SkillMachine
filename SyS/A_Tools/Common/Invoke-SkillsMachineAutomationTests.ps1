#Requires -Version 5.1
<#
.SYNOPSIS
    Runs SkillsMachine.Automation.Tests.ps1 via Pester (3.x or 5.x) when available.
    Called by Validate-System.ps1 as the automation-reliability-foundation gate.
    Exits 0 only when every required test passes. Never mutates PROJECT_ROOT.

    If the environment variable AUTOMATION_SUMMARY_FILE is set to a file path,
    the runner writes the summary KEY=VALUE lines there so Validate-System can
    parse them independently of Write-Host output capture.
#>

$ErrorActionPreference = 'Stop'

$ModulePath  = Join-Path $PSScriptRoot 'SkillsMachine.Automation.psm1'
$TestPath    = Join-Path $PSScriptRoot 'Tests\SkillsMachine.Automation.Tests.ps1'

# ─── Step 1: syntax-gate all files before executing anything ─────────────────

$filesToCheck = @($ModulePath, $TestPath, $PSCommandPath)

foreach ($f in $filesToCheck) {
    $tokens = $null
    $errors  = $null
    [System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$tokens, [ref]$errors) | Out-Null
    if ($errors -and $errors.Count -gt 0) {
        Write-Host "PARSER_FAIL: $f"
        foreach ($e in $errors) {
            Write-Host ("  LINE={0} MSG={1}" -f $e.Extent.StartLineNumber, $e.Message)
        }
        Write-Host 'ERROR: automation reliability foundation failed (parser error)'
        exit 1
    }
}

Write-Host 'PARSER_PASS: module, tests, and runner all syntax-valid'

# ─── Step 2: check that Pester is available ──────────────────────────────────

$pesterModule = Get-Module -ListAvailable Pester -ErrorAction SilentlyContinue |
    Sort-Object Version -Descending |
    Select-Object -First 1

if ($null -eq $pesterModule) {
    Write-Host 'PESTER_AVAILABLE=NO'
    Write-Host 'ERROR: Pester is not installed. Install Pester 3.x or 5.x and retry.'
    exit 1
}

$pesterMajor = $pesterModule.Version.Major
Write-Host "PESTER_AVAILABLE=YES"
Write-Host "PESTER_VERSION=$($pesterModule.Version)"

# ─── Step 3: run tests through Pester ────────────────────────────────────────

Import-Module Pester -RequiredVersion $pesterModule.Version -Force -ErrorAction Stop

$results = $null

if ($pesterMajor -ge 5) {
    # Pester 5 API
    $config = New-PesterConfiguration
    $config.Run.Path = $TestPath
    $config.Run.PassThru = $true
    $config.Output.Verbosity = 'Normal'
    $results = Invoke-Pester -Configuration $config
    $passCount  = $results.PassedCount
    $failCount  = $results.FailedCount
    $totalCount = $results.TotalCount
} else {
    # Pester 3 / 4 API
    $results    = Invoke-Pester -Script $TestPath -PassThru -Quiet:$false
    $passCount  = $results.PassedCount
    $failCount  = $results.FailedCount
    $totalCount = $results.TotalCount

    # Pester 3.4 known issue: aggregate counts (TotalCount / PassedCount / FailedCount)
    # may report 0 even when tests ran. Fall back to counting from TestResult array.
    if ($totalCount -eq 0 -and $null -ne $results -and $null -ne $results.TestResult) {
        $tr = @($results.TestResult)
        if ($tr.Count -gt 0) {
            $totalCount = $tr.Count
            $passCount  = ($tr | Where-Object { $null -ne $_ -and $_.Passed -eq $true }).Count
            $failCount  = ($tr | Where-Object { $null -ne $_ -and ($_.Passed -ne $true) }).Count
        }
    }
}

Write-Host "TESTS_TOTAL=$totalCount"
Write-Host "TESTS_PASSED=$passCount"
Write-Host "TESTS_FAILED=$failCount"

# ─── Step 4: write summary to caller-provided file if requested ──────────────
# Validate-System sets AUTOMATION_SUMMARY_FILE to a temp file path so it can
# parse the summary without depending on pipeline capture of Write-Host output.

$automSummaryPath = $env:AUTOMATION_SUMMARY_FILE
if (-not [string]::IsNullOrEmpty($automSummaryPath)) {
    $enc     = [System.Text.UTF8Encoding]::new($false)
    $content = "TESTS_TOTAL=$totalCount`r`nTESTS_PASSED=$passCount`r`nTESTS_FAILED=$failCount`r`n"
    [System.IO.File]::WriteAllText($automSummaryPath, $content, $enc)
}

# ─── Step 5: exit based on fail count ────────────────────────────────────────

if ($failCount -gt 0) {
    Write-Host 'ERROR: automation reliability foundation failed'
    exit 1
}

Write-Host "OK: automation reliability foundation passed ($passCount tests)"
exit 0
