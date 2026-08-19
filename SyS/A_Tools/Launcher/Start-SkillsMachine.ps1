param(
  [ValidateSet("help","status","radar-status","session-close-readiness","package-upload","build-usecase")]
  [string]$Action = "help",

  [switch]$RunBuild
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
  Write-Host "  pwsh -File SyS\A_Tools\Launcher\Start-SkillsMachine.ps1 -Action package-upload"
  Write-Host "  pwsh -File SyS\A_Tools\Launcher\Start-SkillsMachine.ps1 -Action build-usecase"
  Write-Host "  pwsh -File SyS\A_Tools\Launcher\Start-SkillsMachine.ps1 -Action build-usecase -RunBuild"
  Write-Host ""
  Write-Host "ACTIONS:"
  Write-Host "  help                    Show this help."
  Write-Host "  status                  Show repo and required artifact status."
  Write-Host "  radar-status            Show current RADAR output status without regenerating RADAR."
  Write-Host "  session-close-readiness Run deterministic session-close readiness check."
  Write-Host "  package-upload          Show and validate canonical IA upload package for session continuation."
  Write-Host "  build-usecase           Show build-usecase readiness. Use -RunBuild to execute the mutating build."
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
    "HUMAN\HUMAN.README.txt",
    "HUMAN\HUMAN.OPERATING.MODEL.txt",
    "SyS\00.0_BATON_SKILLMACHINE.txt",
    "90.USECASE\BUILD.ps1",
    "SyS\A_Tools\Context\Build-ToUploadToIA.ps1",
    "SyS\A_Tools\SessionClose\Test-SessionCloseReadiness.ps1",
    "SyS\A_Tools\Radar\radar.manifest.json",
    "SyS\A_Tools\Radar\radar.lite.txt",
    "SyS\A_Tools\Radar\radar.index.txt",
    "90.USECASE\03.SESSION_CONTINUE\README.UPLOAD_THIS_USECASE.txt",
    "90.USECASE\03.SESSION_CONTINUE\PROMPT.SESSION_CONTINUE.txt",
    "90.USECASE\03.SESSION_CONTINUE\USECASE.MANIFEST.json"
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

function Invoke-PackageUpload {
  $root = Get-RepoRoot
  Set-Location $root

  $packageRel = "90.USECASE\03.SESSION_CONTINUE"
  $packageAbs = Join-Path $root $packageRel

  $required = @(
    "README.UPLOAD_THIS_USECASE.txt",
    "PROMPT.SESSION_CONTINUE.txt",
    "00.BUNDLE.CORE.txt",
    "01.BUNDLE.CONTINUITY.txt",
    "02.BUNDLE.GOVERNANCE.txt",
    "00.SKILL.MENU.ACTIVE.txt",
    "SKILL_SET.MANIFEST.txt",
    "USECASE.MANIFEST.json"
  )

  Write-Host "========== SKILLSMACHINE PACKAGE UPLOAD =========="
  Write-Host "PROFILE..........: session-continue"
  Write-Host "UPLOAD_FOLDER....: $packageAbs"
  Write-Host "UPLOAD_RULE......: upload the full folder contents"

  if (-not (Test-Path -LiteralPath $packageAbs)) {
    Write-Host "WRAPPER_STATUS...: FAIL"
    Write-Host "ERROR............: canonical usecase folder not found"
    Write-Host "=================================================="
    exit 1
  }

  $missing = New-Object System.Collections.Generic.List[string]
  foreach ($file in $required) {
    $full = Join-Path $packageAbs $file
    $exists = Test-Path -LiteralPath $full
    Write-Host ("REQUIRED_FILE....: {0}={1}" -f $file, $exists)
    if (-not $exists) {
      [void]$missing.Add($file)
    }
  }

  $fileCount = @(Get-ChildItem -LiteralPath $packageAbs -File -ErrorAction SilentlyContinue).Count
  Write-Host "PACKAGE_FILES....: $fileCount"

  if ($missing.Count -gt 0) {
    Write-Host "WRAPPER_STATUS...: FAIL"
    Write-Host "MISSING_COUNT....: $($missing.Count)"
    Write-Host "MISSING_FILES....: $($missing -join '|')"
    Write-Host "=================================================="
    exit 1
  }

  Write-Host "WRAPPER_STATUS...: PASS"
  Write-Host "OUTPUT_ARTIFACT..: $packageAbs"
  Write-Host "NEXT_STEP........: upload this full folder to the IA session"
  Write-Host "=================================================="
  exit 0
}

function Invoke-BuildUsecase {
  param([switch]$RunBuild)

  $root = Get-RepoRoot
  Set-Location $root

  $buildScript = Join-Path $root "90.USECASE\BUILD.ps1"

  Write-Host "========== SKILLSMACHINE BUILD USECASE =========="
  Write-Host "ROOT.............: $root"
  Write-Host "BUILD_SCRIPT.....: $buildScript"
  Write-Host "MODE.............: $(if ($RunBuild) { 'RUN_BUILD' } else { 'READINESS_ONLY' })"

  if (-not (Test-Path -LiteralPath $buildScript)) {
    Write-Host "WRAPPER_STATUS...: FAIL"
    Write-Host "ERROR............: BUILD.ps1 not found"
    Write-Host "================================================="
    exit 1
  }

  Write-Host "BUILD_READY......: true"

  if (-not $RunBuild) {
    Write-Host "WRAPPER_STATUS...: PASS"
    Write-Host "NOTE.............: build not executed. Add -RunBuild to execute 90.USECASE\BUILD.ps1."
    Write-Host "COMMAND..........: pwsh -File SyS\A_Tools\Launcher\Start-SkillsMachine.ps1 -Action build-usecase -RunBuild"
    Write-Host "================================================="
    exit 0
  }

  Write-Host "RUNNING_BUILD....: true"
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $buildScript
  $code = $LASTEXITCODE
  Write-Host "BUILD_EXIT.......: $code"

  if ($code -eq 0) {
    Write-Host "WRAPPER_STATUS...: PASS"
    Write-Host "================================================="
    exit 0
  }

  Write-Host "WRAPPER_STATUS...: FAIL"
  Write-Host "================================================="
  exit 1
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

if ($Action -eq "package-upload") {
  Invoke-PackageUpload
  exit 0
}

if ($Action -eq "build-usecase") {
  Invoke-BuildUsecase -RunBuild:$RunBuild
  exit 0
}

Write-Host "ERROR: unsupported action: $Action"
exit 1
