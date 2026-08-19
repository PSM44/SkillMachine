$ValidationRepoRoot = [System.IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot "..\..\..")
)
if (-not (Test-Path -LiteralPath (Join-Path $ValidationRepoRoot ".git") -PathType Container)) {
    throw "Validation repository root not found: $ValidationRepoRoot"
}
Set-Location -LiteralPath $ValidationRepoRoot
# Validate-System.ps1
# Runs non-destructive SkillMachine pre-commit validations.

$ErrorActionPreference = "Stop"
# MB-SM-076A6: INTERNAL_RUNTIME_SCRATCH for validation only.
# Not the external AI-exchange temp (C:\Users\aazcl\Downloads\T.AI.SkillMachine).
$ValidationTempRoot = Join-Path $env:TEMP 'SkillsMachine.Validation'
if (-not (Test-Path -LiteralPath $ValidationTempRoot -PathType Container)) {
    New-Item -ItemType Directory -Path $ValidationTempRoot -Force | Out-Null
}

Write-Host "VALIDATION: naming"

if ($env:SKILLS_DEV_TESTS -eq "1") {
  Write-Host "DEV TESTS: validator parse"
  powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "Test-ValidatorParse.ps1")
  if ($LASTEXITCODE -ne 0) { exit 1 }

  Write-Host "DEV TESTS: validator smoke run"
  powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "Test-ValidatorRun.ps1")
  if ($LASTEXITCODE -ne 0) { exit 1 }
}

powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "Validate-SkillMachineNaming.ps1")
if ($LASTEXITCODE -ne 0) { exit 1 }

Write-Host "VALIDATION: structure"
powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "Validate-Structure.ps1")
if ($LASTEXITCODE -ne 0) { exit 1 }

Write-Host "VALIDATION: consistency"
powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "Validate-Consistency.ps1")
if ($LASTEXITCODE -ne 0) { exit 1 }



Write-Host "VALIDATION: usecase registry schema"
powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "Validate-UsecaseRegistrySchema.ps1")
if ($LASTEXITCODE -ne 0) { exit 1 }
Write-Host "VALIDATION: GRC repository architecture"
powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "Validate-GRC-RepositoryArchitecture.ps1")
if ($LASTEXITCODE -ne 0) { exit 1 }

# MB-SM-044B_POWERSHELL_SYNTAX_GATE
Write-Host "VALIDATION: PowerShell syntax gate"
$PowerShellSyntaxValidator = Join-Path $PSScriptRoot "Test-PowerShellSyntax.ps1"
if (-not (Test-Path -LiteralPath $PowerShellSyntaxValidator -PathType Leaf)) {
    Write-Host "FAIL: missing PowerShell syntax validator: $PowerShellSyntaxValidator"
    exit 1
}
$PowerShellHost = Get-Command pwsh.exe -ErrorAction SilentlyContinue
if ($null -eq $PowerShellHost) {
    $PowerShellHost = Get-Command powershell.exe -ErrorAction SilentlyContinue
}
if ($null -eq $PowerShellHost) {
    Write-Host "FAIL: no PowerShell host available for syntax gate"
    exit 1
}
& $PowerShellHost.Source -NoProfile -ExecutionPolicy Bypass -File $PowerShellSyntaxValidator
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

# MB-SM-077D Slice B: INTERACTIVE_SAFETY variable-colon fixtures (not a repo-wide .ps1 scan)
Write-Host "VALIDATION: PowerShell variable-colon fixtures"
$VariableColonValidator = Join-Path $PSScriptRoot "Test-PowerShellVariableColon.ps1"
if (-not (Test-Path -LiteralPath $VariableColonValidator -PathType Leaf)) {
    Write-Host "FAIL: missing PowerShell variable-colon fixture test: $VariableColonValidator"
    exit 1
}
& $PowerShellHost.Source -NoProfile -ExecutionPolicy Bypass -File $VariableColonValidator
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

# MB-SM-067B-D1-R1_FAIL_CLOSED_GATE
Write-Host "VALIDATION: automation reliability foundation"

# A. Resolve exact required artifact paths relative to repository root
$AutomationCommon  = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\Common'))
$AutomationModule  = Join-Path $AutomationCommon 'SkillsMachine.Automation.psm1'
$AutomationTests   = Join-Path $AutomationCommon 'Tests\SkillsMachine.Automation.Tests.ps1'
$AutomationRunner  = Join-Path $AutomationCommon 'Invoke-SkillsMachineAutomationTests.ps1'

# B. Fail-closed artifact presence check — gate is never skipped
$automGateFail = $false
foreach ($automArtifact in @(
    [PSCustomObject]@{ Path = $AutomationModule; Label = 'SyS/A_Tools/Common/SkillsMachine.Automation.psm1' },
    [PSCustomObject]@{ Path = $AutomationTests;  Label = 'SyS/A_Tools/Common/Tests/SkillsMachine.Automation.Tests.ps1' },
    [PSCustomObject]@{ Path = $AutomationRunner; Label = 'SyS/A_Tools/Common/Invoke-SkillsMachineAutomationTests.ps1' }
)) {
    if (-not (Test-Path -LiteralPath $automArtifact.Path -PathType Leaf)) {
        Write-Host "ERROR: automation reliability foundation missing required artifact: $($automArtifact.Label)"
        $automGateFail = $true
    }
}
if ($automGateFail) {
    Write-Host "ERROR: automation reliability foundation failed"
    exit 1
}

# C. Parse module, tests, and runner before execution
foreach ($automFile in @($AutomationModule, $AutomationTests, $AutomationRunner)) {
    $automTokens = $null; $automErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($automFile, [ref]$automTokens, [ref]$automErrors) | Out-Null
    if ($automErrors -and $automErrors.Count -gt 0) {
        $automRel = $automFile.Replace($ValidationRepoRoot, '').TrimStart('\').TrimStart('/')
        Write-Host "ERROR: automation reliability foundation parser failed: $automRel"
        foreach ($automPe in $automErrors) {
            Write-Host ("  LINE={0} MSG={1}" -f $automPe.Extent.StartLineNumber, $automPe.Message)
        }
        Write-Host "ERROR: automation reliability foundation failed"
        exit 1
    }
}

# D/E. Invoke runner; capture parseable summary via repo-authorized temp root.
$automSummaryFile = Join-Path $ValidationTempRoot ("AUTOMATION_SUMMARY_{0}.txt" -f ([System.Guid]::NewGuid().ToString('N')))
$env:AUTOMATION_SUMMARY_FILE = $automSummaryFile
& $PowerShellHost.Source -NoProfile -ExecutionPolicy Bypass -File $AutomationRunner
$automRunnerExit = $LASTEXITCODE
$env:AUTOMATION_SUMMARY_FILE = $null

# F/G. Parse and validate summary fields
$automSummaryText = ''
if (Test-Path -LiteralPath $automSummaryFile -PathType Leaf) {
    $automSummaryText = [System.IO.File]::ReadAllText($automSummaryFile, [System.Text.Encoding]::UTF8)
    Remove-Item -LiteralPath $automSummaryFile -Force -ErrorAction SilentlyContinue
}

$automGateReason = ''
if ($automRunnerExit -ne 0) {
    $automGateReason = "runner exited $automRunnerExit"
} else {
    $automMTotal  = [regex]::Match($automSummaryText, '(?m)^TESTS_TOTAL=(\d+)')
    $automMPassed = [regex]::Match($automSummaryText, '(?m)^TESTS_PASSED=(\d+)')
    $automMFailed = [regex]::Match($automSummaryText, '(?m)^TESTS_FAILED=(\d+)')
    if (-not $automMTotal.Success -or -not $automMPassed.Success -or -not $automMFailed.Success) {
        $automGateReason = 'required summary fields missing (TESTS_TOTAL / TESTS_PASSED / TESTS_FAILED)'
    } else {
        $automGTotal  = [int]$automMTotal.Groups[1].Value
        $automGPassed = [int]$automMPassed.Groups[1].Value
        $automGFailed = [int]$automMFailed.Groups[1].Value
        if ($automGTotal -le 0) {
            $automGateReason = "TESTS_TOTAL=$automGTotal is not a positive integer"
        } elseif ($automGFailed -ne 0) {
            $automGateReason = "TESTS_FAILED=$automGFailed (expected 0)"
        } elseif ($automGPassed -ne $automGTotal) {
            $automGateReason = "TESTS_PASSED=$automGPassed != TESTS_TOTAL=$automGTotal"
        }
    }
}

# H/I. Report outcome
if ($automGateReason -ne '') {
    Write-Host "ERROR: automation reliability foundation failed ($automGateReason)"
    exit 1
}
$automNTests = [int]$automMPassed.Groups[1].Value
Write-Host "OK: automation reliability foundation passed ($automNTests tests)"

Write-Host "VALIDATION: single-file usecase compiler"
$CompilerScript = Join-Path $ValidationRepoRoot 'SyS\A_Tools\UseCaseBuild\Compile-UseCaseSingleFile.ps1'
if (-not (Test-Path -LiteralPath $CompilerScript -PathType Leaf)) {
    Write-Host "FAIL: compiled usecase compiler missing: $CompilerScript"
    exit 1
}

$compilerTokens = $null
$compilerErrors = $null
[System.Management.Automation.Language.Parser]::ParseFile($CompilerScript, [ref]$compilerTokens, [ref]$compilerErrors) | Out-Null
if ($compilerErrors -and $compilerErrors.Count -gt 0) {
    Write-Host "FAIL: compiled usecase compiler parser validation failed"
    foreach ($compilerError in $compilerErrors) {
        Write-Host ("  LINE={0} MSG={1}" -f $compilerError.Extent.StartLineNumber, $compilerError.Message)
    }
    exit 1
}

$importOutput = . $CompilerScript
if ($null -ne $importOutput -and @($importOutput).Count -gt 0) {
    Write-Host "FAIL: compiled usecase compiler import produced unexpected side effects"
    exit 1
}

if (-not (Get-Command Invoke-UseCaseCompiledFileSelfTests -ErrorAction SilentlyContinue)) {
    Write-Host "FAIL: compiled usecase compiler did not expose Invoke-UseCaseCompiledFileSelfTests"
    exit 1
}

$compilerTestSummary = Invoke-UseCaseCompiledFileSelfTests -ScratchRoot $ValidationTempRoot
foreach ($compilerTest in @($compilerTestSummary.Results)) {
    if ($compilerTest.Passed) {
        Write-Host (" [+] {0} {1}" -f $compilerTest.Name, $compilerTest.Detail)
    } else {
        Write-Host (" [-] {0} {1}" -f $compilerTest.Name, $compilerTest.Detail)
    }
}
Write-Host ("COMPILER_TESTS_TOTAL={0}" -f $compilerTestSummary.TestsTotal)
Write-Host ("COMPILER_TESTS_PASSED={0}" -f $compilerTestSummary.TestsPassed)
Write-Host ("COMPILER_TESTS_FAILED={0}" -f $compilerTestSummary.TestsFailed)
if ([int]$compilerTestSummary.TestsFailed -ne 0) {
    Write-Host "FAIL: single-file usecase compiler validation failed"
    exit 1
}

Write-Host "VALIDATION: project information architecture owner"
powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "Validate-ProjectInformationArchitecture.ps1")
if ($LASTEXITCODE -ne 0) { exit 1 }

Write-Host "VALIDATION: project information architecture functional forward tests"
powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "Test-ProjectInformationArchitectureForward.ps1")
if ($LASTEXITCODE -ne 0) { exit 1 }

Write-Host "OK: system pre-commit validation passed"
exit 0



