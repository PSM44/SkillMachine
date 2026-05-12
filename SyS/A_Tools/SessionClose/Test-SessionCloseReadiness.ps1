<#
NAME:
  Test-SessionCloseReadiness.ps1

PURPOSE:
  Produce a deterministic session-close readiness report for SkillMachine.

USAGE:
  From repository root:
    powershell -ExecutionPolicy Bypass -File ".\SyS\A_Tools\SessionClose\Test-SessionCloseReadiness.ps1"

OUTPUTS:
  SyS\A_Tools\SessionClose\SESSION_CLOSE.READINESS.ACTIVE.txt
  SyS\A_Tools\SessionClose\SESSION_CLOSE.READINESS.ACTIVE.json

CONTRACT:
  - OK only when Git is clean and Validate-System.ps1 exits 0.
  - WARN when validation passes but Git has pending changes.
  - FAIL when validation fails or repository/root artifacts are missing.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-RepoRoot {
  $candidate = Resolve-Path (Join-Path $PSScriptRoot "..\..\..")
  return $candidate.Path
}

function ConvertTo-ProcessArgumentString {
  param(
    [Parameter(Mandatory=$false)][string[]]$Arguments = @()
  )

  $quoted = New-Object System.Collections.Generic.List[string]

  foreach ($arg in $Arguments) {
    if ($null -eq $arg) {
      continue
    }

    $safeArg = [string]$arg

    if ($safeArg -match '[\s"]') {
      $safeArg = $safeArg.Replace('\', '\\').Replace('"', '\"')
      [void]$quoted.Add('"' + $safeArg + '"')
    } else {
      [void]$quoted.Add($safeArg)
    }
  }

  return (@($quoted) -join " ")
}

function Invoke-NativeText {
  param(
    [Parameter(Mandatory=$true)][string]$FilePath,
    [Parameter(Mandatory=$false)][string[]]$Arguments = @(),
    [Parameter(Mandatory=$true)][string]$WorkingDirectory
  )

  # Uses System.Diagnostics.Process instead of PowerShell native redirection.
  # Reason: Git warnings on stderr must be captured as text, not promoted to
  # NativeCommandError under $ErrorActionPreference = Stop.
  #
  # Compatibility note:
  # Windows PowerShell 5.1 / .NET Framework does not reliably expose
  # ProcessStartInfo.ArgumentList. Use ProcessStartInfo.Arguments instead.

  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $FilePath
  $psi.Arguments = ConvertTo-ProcessArgumentString -Arguments $Arguments
  $psi.WorkingDirectory = $WorkingDirectory
  $psi.UseShellExecute = $false
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.CreateNoWindow = $true

  $process = New-Object System.Diagnostics.Process
  $process.StartInfo = $psi

  [void]$process.Start()
  $stdout = $process.StandardOutput.ReadToEnd()
  $stderr = $process.StandardError.ReadToEnd()
  $process.WaitForExit()

  $lines = New-Object System.Collections.Generic.List[string]

  if (-not [string]::IsNullOrWhiteSpace($stdout)) {
    foreach ($line in ($stdout -split "`r?`n")) {
      if (-not [string]::IsNullOrWhiteSpace($line)) {
        [void]$lines.Add($line)
      }
    }
  }

  if (-not [string]::IsNullOrWhiteSpace($stderr)) {
    foreach ($line in ($stderr -split "`r?`n")) {
      if (-not [string]::IsNullOrWhiteSpace($line)) {
        [void]$lines.Add($line)
      }
    }
  }

  return [pscustomobject]@{
    exit_code = $process.ExitCode
    output    = @($lines)
  }
}
function Add-Line {
  param(
    [System.Collections.Generic.List[string]]$Lines,
    [string]$Text = ""
  )
  [void]$Lines.Add($Text)
}

$Root = Get-RepoRoot
$Now = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$OutDir = Join-Path $Root "SyS\A_Tools\SessionClose"
$TxtOut = Join-Path $OutDir "SESSION_CLOSE.READINESS.ACTIVE.txt"
$JsonOut = Join-Path $OutDir "SESSION_CLOSE.READINESS.ACTIVE.json"

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$ValidationPath = Join-Path $Root "SyS\A_Tools\Validation\Validate-System.ps1"
$RadarManifestPath = Join-Path $Root "SyS\A_Tools\Radar\radar.manifest.json"
$RadarLitePath = Join-Path $Root "SyS\A_Tools\Radar\radar.lite.txt"
$BatonPath = Join-Path $Root "SyS\00.0_BATON_SKILLMACHINE.txt"
$WhoamiPath = Join-Path $Root "SyS\01_WHOAMI_SKILLMACHINE.txt"

$branch = Invoke-NativeText -FilePath "git" -Arguments @("branch","--show-current") -WorkingDirectory $Root
$lastCommit = Invoke-NativeText -FilePath "git" -Arguments @("log","-1","--oneline") -WorkingDirectory $Root
$tagsAtHead = Invoke-NativeText -FilePath "git" -Arguments @("tag","--points-at","HEAD") -WorkingDirectory $Root
$statusShort = Invoke-NativeText -FilePath "git" -Arguments @("status","--short") -WorkingDirectory $Root
$diffStat = Invoke-NativeText -FilePath "git" -Arguments @("diff","--stat") -WorkingDirectory $Root
$cachedDiffStat = Invoke-NativeText -FilePath "git" -Arguments @("diff","--cached","--stat") -WorkingDirectory $Root
$untracked = Invoke-NativeText -FilePath "git" -Arguments @("ls-files","--others","--exclude-standard") -WorkingDirectory $Root

$validationExists = Test-Path -LiteralPath $ValidationPath
if ($validationExists) {
  $validation = Invoke-NativeText -FilePath "powershell" -Arguments @("-ExecutionPolicy","Bypass","-File",$ValidationPath) -WorkingDirectory $Root
} else {
  $validation = [pscustomobject]@{
    exit_code = 999
    output = @("FAIL: Validate-System.ps1 not found at $ValidationPath")
  }
}

$radarManifestExists = Test-Path -LiteralPath $RadarManifestPath
$radarLiteExists = Test-Path -LiteralPath $RadarLitePath
$batonExists = Test-Path -LiteralPath $BatonPath
$whoamiExists = Test-Path -LiteralPath $WhoamiPath

$radarManifest = $null
if ($radarManifestExists) {
  try {
    $radarManifest = Get-Content -LiteralPath $RadarManifestPath -Raw | ConvertFrom-Json
  } catch {
    $radarManifest = $null
  }
}

$gitDirty = (
  (@($statusShort.output).Count -gt 0 -and ((@($statusShort.output) -join "").Trim().Length -gt 0)) -or
  (@($diffStat.output).Count -gt 0 -and ((@($diffStat.output) -join "").Trim().Length -gt 0)) -or
  (@($cachedDiffStat.output).Count -gt 0 -and ((@($cachedDiffStat.output) -join "").Trim().Length -gt 0)) -or
  (@($untracked.output).Count -gt 0 -and ((@($untracked.output) -join "").Trim().Length -gt 0))
)

$status = "OK"
$issues = New-Object System.Collections.Generic.List[string]

if ($validation.exit_code -ne 0) {
  $status = "FAIL"
  [void]$issues.Add("Validate-System.ps1 failed or could not run.")
}

if (-not $radarManifestExists) {
  $status = "FAIL"
  [void]$issues.Add("RADAR manifest not found.")
}

if (-not $batonExists) {
  $status = "FAIL"
  [void]$issues.Add("BATON not found.")
}

if (-not $whoamiExists) {
  $status = "FAIL"
  [void]$issues.Add("WHOAMI not found.")
}

if ($gitDirty -and $status -eq "OK") {
  $status = "WARN"
  [void]$issues.Add("Git working tree is not clean.")
}

$artifactMeta = [pscustomobject]@{
  radar_manifest_exists = $radarManifestExists
  radar_manifest_path = $RadarManifestPath
  radar_generated_at = if ($radarManifest -and $radarManifest.generated_at) { $radarManifest.generated_at } else { "" }
  radar_total_file_count = if ($radarManifest -and $null -ne $radarManifest.total_file_count) { $radarManifest.total_file_count } else { "" }
  radar_core_file_count = if ($radarManifest -and $null -ne $radarManifest.core_file_count) { $radarManifest.core_file_count } else { "" }
  radar_skipped_too_large_count = if ($radarManifest -and $null -ne $radarManifest.skipped_too_large_count) { $radarManifest.skipped_too_large_count } else { "" }
  radar_lite_exists = $radarLiteExists
  baton_exists = $batonExists
  baton_path = $BatonPath
  baton_modified_at = if ($batonExists) { (Get-Item -LiteralPath $BatonPath).LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss") } else { "" }
  whoami_exists = $whoamiExists
  whoami_path = $WhoamiPath
  whoami_modified_at = if ($whoamiExists) { (Get-Item -LiteralPath $WhoamiPath).LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss") } else { "" }
}

$result = [pscustomobject]@{
  generated_at = $Now
  root = $Root
  readiness_status = $status
  issues = @($issues)
  git = [pscustomobject]@{
    branch = (@($branch.output) -join "`n").Trim()
    last_commit = (@($lastCommit.output) -join "`n").Trim()
    tags_at_head = @($tagsAtHead.output)
    status_short = @($statusShort.output)
    diff_stat = @($diffStat.output)
    staged_diff_stat = @($cachedDiffStat.output)
    untracked_files = @($untracked.output)
    git_dirty = $gitDirty
  }
  validation = [pscustomobject]@{
    validate_system_path = $ValidationPath
    exit_code = $validation.exit_code
    output = @($validation.output)
  }
  artifacts = $artifactMeta
}

$lines = New-Object System.Collections.Generic.List[string]

Add-Line $lines "=========="
Add-Line $lines "SESSION_CLOSE.READINESS.ACTIVE"
Add-Line $lines "=========="
Add-Line $lines ""
Add-Line $lines ("GENERATED_AT........: {0}" -f $Now)
Add-Line $lines ("ROOT................: {0}" -f $Root)
Add-Line $lines ("READINESS_STATUS....: {0}" -f $status)
Add-Line $lines ""

Add-Line $lines "=========="
Add-Line $lines "01.00_EXECUTIVE_STATUS"
Add-Line $lines "=========="
Add-Line $lines ("STATUS..............: {0}" -f $status)
if (@($issues).Count -eq 0) {
  Add-Line $lines "ISSUES..............: [NONE]"
} else {
  Add-Line $lines "ISSUES..............:"
  foreach ($issue in $issues) {
    Add-Line $lines ("- {0}" -f $issue)
  }
}
Add-Line $lines ""

Add-Line $lines "=========="
Add-Line $lines "02.00_GIT_EVIDENCE"
Add-Line $lines "=========="
Add-Line $lines ("BRANCH..............: {0}" -f $result.git.branch)
Add-Line $lines ("LAST_COMMIT.........: {0}" -f $result.git.last_commit)
Add-Line $lines "TAGS_AT_HEAD........:"
if (@($result.git.tags_at_head).Count -eq 0 -or ((@($result.git.tags_at_head) -join "").Trim().Length -eq 0)) {
  Add-Line $lines "- [NONE]"
} else {
  foreach ($tag in $result.git.tags_at_head) { Add-Line $lines ("- {0}" -f $tag) }
}
Add-Line $lines ("GIT_DIRTY...........: {0}" -f $result.git.git_dirty)
Add-Line $lines ""

Add-Line $lines "STATUS_SHORT........:"
if (@($result.git.status_short).Count -eq 0 -or ((@($result.git.status_short) -join "").Trim().Length -eq 0)) {
  Add-Line $lines "[CLEAN]"
} else {
  foreach ($line in $result.git.status_short) { Add-Line $lines $line }
}
Add-Line $lines ""

Add-Line $lines "DIFF_STAT...........:"
if (@($result.git.diff_stat).Count -eq 0 -or ((@($result.git.diff_stat) -join "").Trim().Length -eq 0)) {
  Add-Line $lines "[NONE]"
} else {
  foreach ($line in $result.git.diff_stat) { Add-Line $lines $line }
}
Add-Line $lines ""

Add-Line $lines "STAGED_DIFF_STAT....:"
if (@($result.git.staged_diff_stat).Count -eq 0 -or ((@($result.git.staged_diff_stat) -join "").Trim().Length -eq 0)) {
  Add-Line $lines "[NONE]"
} else {
  foreach ($line in $result.git.staged_diff_stat) { Add-Line $lines $line }
}
Add-Line $lines ""

Add-Line $lines "UNTRACKED_FILES.....:"
if (@($result.git.untracked_files).Count -eq 0 -or ((@($result.git.untracked_files) -join "").Trim().Length -eq 0)) {
  Add-Line $lines "[NONE]"
} else {
  foreach ($line in $result.git.untracked_files) { Add-Line $lines $line }
}
Add-Line $lines ""

Add-Line $lines "=========="
Add-Line $lines "03.00_VALIDATION_EVIDENCE"
Add-Line $lines "=========="
Add-Line $lines ("VALIDATE_SYSTEM_PATH: {0}" -f $ValidationPath)
Add-Line $lines ("EXIT_CODE...........: {0}" -f $validation.exit_code)
Add-Line $lines "OUTPUT..............:"
foreach ($line in $validation.output) { Add-Line $lines $line }
Add-Line $lines ""

Add-Line $lines "=========="
Add-Line $lines "04.00_CONTINUITY_ARTIFACTS"
Add-Line $lines "=========="
Add-Line $lines ("RADAR_MANIFEST_EXISTS......: {0}" -f $artifactMeta.radar_manifest_exists)
Add-Line $lines ("RADAR_MANIFEST_PATH........: {0}" -f $artifactMeta.radar_manifest_path)
Add-Line $lines ("RADAR_GENERATED_AT.........: {0}" -f $artifactMeta.radar_generated_at)
Add-Line $lines ("RADAR_TOTAL_FILE_COUNT.....: {0}" -f $artifactMeta.radar_total_file_count)
Add-Line $lines ("RADAR_CORE_FILE_COUNT......: {0}" -f $artifactMeta.radar_core_file_count)
Add-Line $lines ("RADAR_SKIPPED_TOO_LARGE....: {0}" -f $artifactMeta.radar_skipped_too_large_count)
Add-Line $lines ("BATON_EXISTS...............: {0}" -f $artifactMeta.baton_exists)
Add-Line $lines ("BATON_PATH.................: {0}" -f $artifactMeta.baton_path)
Add-Line $lines ("BATON_MODIFIED_AT..........: {0}" -f $artifactMeta.baton_modified_at)
Add-Line $lines ("WHOAMI_EXISTS..............: {0}" -f $artifactMeta.whoami_exists)
Add-Line $lines ("WHOAMI_PATH................: {0}" -f $artifactMeta.whoami_path)
Add-Line $lines ("WHOAMI_MODIFIED_AT.........: {0}" -f $artifactMeta.whoami_modified_at)
Add-Line $lines ""

Add-Line $lines "=========="
Add-Line $lines "05.00_NEXT_ACTION"
Add-Line $lines "=========="
if ($status -eq "OK") {
  Add-Line $lines "NEXT_ACTION.........: Session can be closed. Repository is clean and validation passed."
} elseif ($status -eq "WARN") {
  Add-Line $lines "NEXT_ACTION.........: Review pending Git changes before closing session."
} else {
  Add-Line $lines "NEXT_ACTION.........: Do not close session as clean. Fix FAIL issues first."
}
Add-Line $lines ""

Add-Line $lines "=========="
Add-Line $lines "FIN_DEL_DOCUMENTO"
Add-Line $lines "=========="

Set-Content -LiteralPath $TxtOut -Value $lines -Encoding UTF8
$result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $JsonOut -Encoding UTF8

Write-Host "SESSION CLOSE READINESS: $status"
Write-Host "TXT : $TxtOut"
Write-Host "JSON: $JsonOut"

if ($status -eq "FAIL") {
  exit 1
}

if ($status -eq "WARN") {
  exit 1
}

exit 0


