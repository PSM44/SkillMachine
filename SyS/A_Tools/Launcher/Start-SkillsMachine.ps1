param(
  [ValidateSet("help","status","radar-status")]
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
  Write-Host ""
  Write-Host "ACTIONS:"
  Write-Host "  help         Show this help."
  Write-Host "  status       Show repo and required artifact status."
  Write-Host "  radar-status Show current RADAR output status without regenerating RADAR."
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

Write-Host "ERROR: unsupported action: $Action"
exit 1
