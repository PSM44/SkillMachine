param(
  [ValidateSet("help","status","radar-status","session-close-readiness")]
  [string]$Action = "help"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Get-RepoRoot {
  return (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
}

function Invoke-GitText {
  param(
    [Parameter(Mandatory=$true)][string[]]$Arguments,
    [Parameter(Mandatory=$true)][string]$WorkingDirectory
  )

  $output = & git @Arguments 2>&1
  return @($output)
}

function Test-File {
  param(
    [Parameter(Mandatory=$true)][string]$Root,
    [Parameter(Mandatory=$true)][string]$RelPath
  )

  $full = Join-Path $Root $RelPath
  return [pscustomobject]@{
    rel_path = $RelPath
    exists = Test-Path -LiteralPath $full
    full_path = $full
  }
}

function Show-Help {
  Write-Host "========== SKILLSMACHINE OPERATOR LAUNCHER =========="
  Write-Host "USAGE:"
  Write-Host "  pwsh -File SyS\A_Tools\Launcher\Start-SkillsMachine.ps1 -Action help"
  Write-Host "  pwsh -File SyS\A_Tools\Launcher\Start-SkillsMachine.ps1 -Action status"
  Write-Host "  pwsh -File SyS\A_Tools\Launcher\Start-SkillsMachine.ps1 -Action radar-status"
  Write-Host "  pwsh -File SyS\A_Tools\Launcher\Start-SkillsMachine.ps1 -Action session-close-readiness"
  Write-Host ""
  Write-Host "ACTIONS:"
  Write-Host "  help                    Show this help."
  Write-Host "  status                  Show repo and required artifact status."
  Write-Host "  radar-status            Show current RADAR output status without regenerating RADAR."
  Write-Host "  session-close-readiness Run deterministic session-close readiness check."
  Write-Host "====================================================="
}

function Show-Status {
  $root = Get-RepoRoot
  Set-Location $root

  $branch = ((Invoke-GitText -Arguments @("branch","--show-current") -WorkingDirectory $root) -join "`n").Trim()
  $head = ((Invoke-GitText -Arguments @("log","-1","--oneline") -WorkingDirectory $root) -join "`n").Trim()
  $status = @((Invoke-GitText -Arguments @("status","--short","-uall") -WorkingDirectory $root))
  $dirty = ($status.Count -gt 0 -and (($status -join "").Trim().Length -gt 0))

  $required = @(
    "GRCLake\01.CONTROLS\CONTROL.BETA_FUNCTIONALITY_GATE.txt",
    "GRCLake\01.CONTROLS\CONTROL.SCRIPT_OUTPUT_AI_TAIL.txt",
    "SkillsLake\01.SKILLS\SKILL.SCRIPT_OUTPUT_AI_TAIL_CONTRACT.txt",
    "SyS\00.0_BATON_SKILLMACHINE.txt",
    "SyS\01_WHOAMI_SKILLMACHINE.txt",
    "90.USECASE\BUILD.ps1",
    "SyS\A_Tools\Context\Build-ToUploadToIA.ps1",
    "SyS\A_Tools\SessionClose\Test-SessionCloseReadiness.ps1",
    "SyS\A_Tools\Radar\radar.manifest.json",
    "SyS\A_Tools\Radar\radar.lite.txt",
    "SyS\A_Tools\Radar\radar.index.txt"
  )

  Write-Host "========== SKILLSMACHINE STATUS =========="
  Write-Host "ROOT.............: $root"
  Write-Host "BRANCH...........: $branch"
  Write-Host "HEAD.............: $head"
  Write-Host "DIRTY............: $dirty"
  Write-Host ""
  Write-Host "REQUIRED_ARTIFACTS:"
  foreach ($rel in $required) {
    $check = Test-File -Root $root -RelPath $rel
    Write-Host ("{0}={1}" -f $rel.Replace("\","/"), $check.exists)
  }
  Write-Host "=========================================="
}

function Show-RadarStatus {
  $root = Get-RepoRoot
  $manifestPath = Join-Path $root "SyS\A_Tools\Radar\radar.manifest.json"
  $litePath = Join-Path $root "SyS\A_Tools\Radar\radar.lite.txt"
  $indexPath = Join-Path $root "SyS\A_Tools\Radar\radar.index.txt"

  Write-Host "========== SKILLSMACHINE RADAR STATUS =========="
  Write-Host "RADAR_MANIFEST_EXISTS.: $(Test-Path -LiteralPath $manifestPath)"
  Write-Host "RADAR_LITE_EXISTS.....: $(Test-Path -LiteralPath $litePath)"
  Write-Host "RADAR_INDEX_EXISTS....: $(Test-Path -LiteralPath $indexPath)"

  if (Test-Path -LiteralPath $manifestPath) {
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Write-Host "GENERATED_AT..........: $($manifest.generated_at)"
    Write-Host "ROOT_SCANNED..........: $($manifest.root_scanned)"
    Write-Host "TOTAL_FILES...........: $($manifest.total_file_count)"
    Write-Host "CORE_FILES............: $($manifest.core_file_count)"
    Write-Host "SKIPPED_TOO_LARGE.....: $($manifest.skipped_too_large_count)"
    Write-Host "NEW_FILES_COUNT.......: $($manifest.diff_summary.new_count)"
    Write-Host "MODIFIED_FILES_COUNT..: $($manifest.diff_summary.modified_count)"
    Write-Host "DELETED_FILES_COUNT...: $($manifest.diff_summary.deleted_count)"
  }

  Write-Host "================================================"
}

function Invoke-SessionCloseReadiness {
  $root = Get-RepoRoot
  Set-Location $root

  $scriptPath = Join-Path $root "SyS\A_Tools\SessionClose\Test-SessionCloseReadiness.ps1"
  $txtOut = Join-Path $root "SyS\A_Tools\SessionClose\SESSION_CLOSE.READINESS.ACTIVE.txt"
  $jsonOut = Join-Path $root "SyS\A_Tools\SessionClose\SESSION_CLOSE.READINESS.ACTIVE.json"

  Write-Host "========== SKILLSMACHINE SESSION CLOSE READINESS =========="
  Write-Host "ROOT..................: $root"
  Write-Host "SCRIPT................: $scriptPath"

  if (-not (Test-Path -LiteralPath $scriptPath)) {
    Write-Host "WRAPPER_STATUS........: FAIL"
    Write-Host "ERROR.................: readiness script not found"
    exit 1
  }

  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $scriptPath
  $readinessExit = $LASTEXITCODE

  $txtExists = Test-Path -LiteralPath $txtOut
  $jsonExists = Test-Path -LiteralPath $jsonOut

  Write-Host "READINESS_RAW_EXIT....: $readinessExit"
  Write-Host "TXT_EXISTS............: $txtExists"
  Write-Host "JSON_EXISTS...........: $jsonExists"
  Write-Host "TXT_PATH..............: $txtOut"
  Write-Host "JSON_PATH.............: $jsonOut"

  if (-not $txtExists -or -not $jsonExists) {
    Write-Host "WRAPPER_STATUS........: FAIL"
    Write-Host "ERROR.................: readiness outputs missing"
    exit 1
  }

  try {
    $json = Get-Content -LiteralPath $jsonOut -Raw -Encoding UTF8 | ConvertFrom-Json
    $status = [string]$json.readiness_status
    $issuesCount = @($json.issues).Count

    Write-Host "READINESS_STATUS......: $status"
    Write-Host "ISSUES_COUNT..........: $issuesCount"

    if ($status -eq "OK" -or $status -eq "WARN") {
      Write-Host "WRAPPER_STATUS........: PASS"
      Write-Host "WRAPPER_EXIT..........: 0"
      Write-Host "NOTE..................: readiness status is reported separately from wrapper execution"
      Write-Host "==========================================================="
      exit 0
    }

    Write-Host "WRAPPER_STATUS........: FAIL"
    Write-Host "WRAPPER_EXIT..........: 1"
    Write-Host "==========================================================="
    exit 1
  } catch {
    Write-Host "WRAPPER_STATUS........: FAIL"
    Write-Host "ERROR.................: readiness JSON parse failed"
    Write-Host "WRAPPER_EXIT..........: 1"
    Write-Host "==========================================================="
    exit 1
  }
}

if ($Action -eq "help") {
  Show-Help
  exit 0
}

if ($Action -eq "status") {
  Show-Status
  exit 0
}

if ($Action -eq "radar-status") {
  Show-RadarStatus
  exit 0
}

if ($Action -eq "session-close-readiness") {
  Invoke-SessionCloseReadiness
  exit 0
}

Write-Host "ERROR: unsupported action: $Action"
exit 1
