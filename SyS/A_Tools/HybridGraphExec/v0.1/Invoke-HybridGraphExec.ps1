#Requires -Version 5.1
<#
.SYNOPSIS
  Hybrid Deterministic Graph Execution v0.1 runner wrapper.
.NOTES
  Workers propose only. This wrapper never commits, pushes, or mutates CloseReport.
#>
[CmdletBinding()]
param(
    [ValidateSet('Test', 'Validate')]
    [string]$Action = 'Test',
    [string]$GraphJson = '',
    [string]$RepoRoot = 'C:\01. GitHub\Skills'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptPath = $PSCommandPath
if ([string]::IsNullOrWhiteSpace($scriptPath)) { $scriptPath = $MyInvocation.MyCommand.Path }
$moduleRoot = Split-Path -Parent $scriptPath
$aiExchange = 'C:\Users\aazcl\Downloads\T.AI.SkillMachine'
if ($moduleRoot.StartsWith($aiExchange, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'REFUSE: HybridGraphExec must not run from AI-exchange Temp'
}

$python = Get-Command python.exe -ErrorAction SilentlyContinue
if ($null -eq $python) { throw 'python.exe not found' }
$env:PYTHONDONTWRITEBYTECODE = '1'

$exitCode = 1
if ($Action -eq 'Test') {
    $runner = Join-Path $moduleRoot 'Tests\run_all.py'
    & $python.Source $runner
    $exitCode = $LASTEXITCODE
}
elseif ($Action -eq 'Validate') {
    if ([string]::IsNullOrWhiteSpace($GraphJson)) { throw 'GraphJson is required for Validate' }
    $validator = Join-Path $moduleRoot 'Validators\GraphDeterministicValidator.v0.1.py'
    & $python.Source $validator --graph $GraphJson
    $exitCode = $LASTEXITCODE
}

Write-Host ''
Write-Host 'AI_TAIL_START'
Write-Host 'PROJECT=PS.SkillsMachine'
Write-Host 'MODULE=HybridGraphExec.v0.1'
Write-Host ('ACTION={0}' -f $Action)
Write-Host ('EXIT_CODE={0}' -f $exitCode)
Write-Host 'CANONICAL_MUTATION=FORBIDDEN'
Write-Host 'COMMIT=NO'
Write-Host 'PUSH=NO'
Write-Host 'AI_TAIL_END'
exit $exitCode
