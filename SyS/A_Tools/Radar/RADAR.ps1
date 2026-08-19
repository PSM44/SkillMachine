param(
    [string]$RootPathOverride = "",
    [string]$OutputPathOverride = "",
    [string]$OldPathOverride = "",
    [switch]$EnableSha256,
    [int64]$CoreMaxFileSizeBytes = 2097152,
    [int64]$SegmentMaxBytes = 8388608,
    [string[]]$UploadSelection = @('LITE', 'INDEX'),
    [int]$MaxFileCountWarning = 10000,
    [int64]$SizeWarningBytes = 104857600,
    [switch]$SimulateDiskFull
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RADAR_SCRIPT_VERSION = 'v0.7.0'
$RADAR_OUTPUT_SCHEMA = 'v1.5'

. (Join-Path $PSScriptRoot 'Radar.Runtime.ps1')

$ScriptDir = $PSScriptRoot
$ToolsDir = Split-Path -Path $ScriptDir -Parent
$SysDir = Split-Path -Path $ToolsDir -Parent
$ProjectRootCandidate = Split-Path -Path $SysDir -Parent

$RootPath = if ([string]::IsNullOrWhiteSpace($RootPathOverride)) { $ProjectRootCandidate } else { $RootPathOverride }
$OutputPath = if ([string]::IsNullOrWhiteSpace($OutputPathOverride)) { $ScriptDir } else { $OutputPathOverride }
$OldPath = if ([string]::IsNullOrWhiteSpace($OldPathOverride)) { (Join-Path $ProjectRootCandidate 'old\radar') } else { $OldPathOverride }

$ScriptSucceeded = $false
try {
    [void](Invoke-RadarScan `
        -RootPath $RootPath `
        -OutputPath $OutputPath `
        -OldPath $OldPath `
        -EnableSha256:$EnableSha256 `
        -CoreMaxFileSizeBytes $CoreMaxFileSizeBytes `
        -SegmentMaxBytes $SegmentMaxBytes `
        -UploadSelection $UploadSelection `
        -MaxFileCountWarning $MaxFileCountWarning `
        -SizeWarningBytes $SizeWarningBytes `
        -SimulateDiskFull:$SimulateDiskFull `
        -ScriptVersion $RADAR_SCRIPT_VERSION `
        -Schema $RADAR_OUTPUT_SCHEMA)
    $ScriptSucceeded = $true
}
catch {
    $lineInfo = ''
    if ($_.InvocationInfo -and $_.InvocationInfo.ScriptLineNumber) {
        $lineInfo = ' (line {0})' -f $_.InvocationInfo.ScriptLineNumber
    }
    [Console]::Error.WriteLine('RADAR FAILED{0}: {1}' -f $lineInfo, $_.Exception.Message)
}
finally {
    if ($ScriptSucceeded) { exit 0 }
    exit 1
}
