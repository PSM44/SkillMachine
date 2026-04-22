param(
    [string]$RootPathOverride = "",
    [string]$OutputPathOverride = "",
    [string]$OldPathOverride = ""
)

# ==============================
# 00.00 METADATA
# ==============================

$RADAR_SCRIPT_VERSION = "v0.4.0"
$RADAR_OUTPUT_SCHEMA  = "v1.1"

# ==============================
# 01.00 PATH RESOLUTION
# ==============================

$ScriptDir = $PSScriptRoot
$ToolsDir  = Split-Path $ScriptDir -Parent
$AutoRootPath = Split-Path $ToolsDir -Parent
$AutoOutputPath = $ScriptDir
$AutoOldPath = Join-Path $AutoRootPath "old\radar"

$RootPath   = if ([string]::IsNullOrWhiteSpace($RootPathOverride)) { $AutoRootPath } else { $RootPathOverride }
$OutputPath = if ([string]::IsNullOrWhiteSpace($OutputPathOverride)) { $AutoOutputPath } else { $OutputPathOverride }
$OldPath    = if ([string]::IsNullOrWhiteSpace($OldPathOverride)) { $AutoOldPath } else { $OldPathOverride }

$ExcludedPaths = @(
    (Join-Path $RootPath "old"),
    $OutputPath
)

$AllowedExtensions = @(".txt", ".md", ".ps1", ".json")

$IndexFile    = Join-Path $OutputPath "radar.index.txt"
$FullFile     = Join-Path $OutputPath "radar.full.txt"
$ManifestFile = Join-Path $OutputPath "radar.manifest.json"

$ArchivedFiles = New-Object System.Collections.Generic.List[string]

# ==============================
# 02.00 HELPERS
# ==============================

function Test-IsExcluded {
    param([string]$Path)

    foreach ($ex in $ExcludedPaths) {
        if ($Path.StartsWith($ex, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }
    return $false
}

function Write-RadarHeader {
    param(
        [string]$FilePath,
        [string]$Title,
        [string]$OutputType
    )

    $now = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    @(
        "=============================="
        $Title
        "=============================="
        "RADAR_SCRIPT_VERSION: $RADAR_SCRIPT_VERSION"
        "RADAR_OUTPUT_SCHEMA : $RADAR_OUTPUT_SCHEMA"
        "OUTPUT_TYPE         : $OutputType"
        "GENERATED_AT        : $now"
        "ROOT_SCANNED        : $RootPath"
        "OUTPUT_PATH         : $OutputPath"
        "OLD_PATH            : $OldPath"
        "EXCLUDED_PATHS      :"
        " - $(Join-Path $RootPath 'old')"
        " - $OutputPath"
        ""
    ) | Out-File $FilePath -Encoding utf8
}

function Get-RelativePathSafe {
    param(
        [string]$BasePath,
        [string]$TargetPath
    )

    try {
        $base = [System.IO.Path]::GetFullPath($BasePath)
        if (-not $base.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
            $base += [System.IO.Path]::DirectorySeparatorChar
        }

        $target = [System.IO.Path]::GetFullPath($TargetPath)

        $baseUri = [System.Uri]$base
        $targetUri = [System.Uri]$target

        $relativeUri = $baseUri.MakeRelativeUri($targetUri)
        $relativePath = [System.Uri]::UnescapeDataString($relativeUri.ToString())

        return $relativePath -replace '/', '\'
    }
    catch {
        return $TargetPath
    }
}

# ==============================
# 03.00 PREP DIRECTORIES
# ==============================

foreach ($path in @($OutputPath, $OldPath)) {
    if (!(Test-Path $path)) {
        New-Item -ItemType Directory -Path $path -Force | Out-Null
    }
}

# ==============================
# 04.00 ARCHIVE PREVIOUS OUTPUTS
# ==============================

Get-ChildItem -Path $OutputPath -File -ErrorAction SilentlyContinue | Where-Object {
    $_.Name -in @("radar.index.txt", "radar.full.txt", "radar.manifest.json")
} | ForEach-Object {
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $destName = "{0}.{1}{2}" -f $_.BaseName, $timestamp, $_.Extension
    $destPath = Join-Path $OldPath $destName

    Move-Item $_.FullName $destPath -Force
    $ArchivedFiles.Add($destPath) | Out-Null
}

# ==============================
# 05.00 COLLECT FILES
# ==============================

$Files = Get-ChildItem -Path $RootPath -Recurse -File | Where-Object {
    $_.Extension -in $AllowedExtensions
} | Where-Object {
    -not (Test-IsExcluded -Path $_.FullName)
} | Sort-Object FullName

$GeneratedAt = Get-Date
$GeneratedAtText = $GeneratedAt.ToString("yyyy-MM-dd HH:mm:ss")

# ==============================
# 06.00 RADAR INDEX
# ==============================

Write-RadarHeader -FilePath $IndexFile -Title "RADAR INDEX" -OutputType "INDEX"

foreach ($file in $Files) {
    "{0} | {1} KB | {2}" -f `
        $file.FullName, `
        [math]::Round($file.Length / 1KB, 2), `
        $file.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss") |
    Out-File $IndexFile -Append -Encoding utf8
}

# ==============================
# 07.00 RADAR FULL
# ==============================

Write-RadarHeader -FilePath $FullFile -Title "RADAR FULL" -OutputType "FULL"

foreach ($file in $Files) {
    "--------------------------------------------------" | Out-File $FullFile -Append -Encoding utf8
    "FILE: $($file.FullName)" | Out-File $FullFile -Append -Encoding utf8
    "SIZE: $([math]::Round($file.Length / 1KB, 2)) KB" | Out-File $FullFile -Append -Encoding utf8
    "MODIFIED: $($file.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))" | Out-File $FullFile -Append -Encoding utf8
    "--------------------------------------------------" | Out-File $FullFile -Append -Encoding utf8

    try {
        Get-Content $file.FullName -ErrorAction Stop | Out-File $FullFile -Append -Encoding utf8
    }
    catch {
        "[UNREADABLE FILE]" | Out-File $FullFile -Append -Encoding utf8
    }

    "" | Out-File $FullFile -Append -Encoding utf8
}

# ==============================
# 08.00 RADAR MANIFEST
# ==============================

$Manifest = [ordered]@{
    radar_script_version = $RADAR_SCRIPT_VERSION
    radar_output_schema  = $RADAR_OUTPUT_SCHEMA
    generated_at         = $GeneratedAt.ToString("yyyy-MM-ddTHH:mm:ss")
    root_scanned         = $RootPath
    output_path          = $OutputPath
    old_path             = $OldPath
    excluded_paths       = $ExcludedPaths
    allowed_extensions   = $AllowedExtensions
    file_count           = $Files.Count
    output_files         = @(
        [ordered]@{
            type = "INDEX"
            path = $IndexFile
        },
        [ordered]@{
            type = "FULL"
            path = $FullFile
        },
        [ordered]@{
            type = "MANIFEST"
            path = $ManifestFile
        }
    )
    archived_files       = $ArchivedFiles
    scanned_files        = @(
        $Files | ForEach-Object {
            [ordered]@{
                relative_path = Get-RelativePathSafe -BasePath $RootPath -TargetPath $_.FullName
                full_path     = $_.FullName
                extension     = $_.Extension
                size_bytes    = $_.Length
                modified_at   = $_.LastWriteTime.ToString("yyyy-MM-ddTHH:mm:ss")
            }
        }
    )
}

$Manifest | ConvertTo-Json -Depth 6 | Out-File $ManifestFile -Encoding utf8

# ==============================
# 09.00 FINAL STATUS
# ==============================

Write-Host "OK"
Write-Host "GENERATED_AT: $GeneratedAtText"
Write-Host "INDEX   : $IndexFile"
Write-Host "FULL    : $FullFile"
Write-Host "MANIFEST: $ManifestFile"
Write-Host "FILES   : $($Files.Count)"