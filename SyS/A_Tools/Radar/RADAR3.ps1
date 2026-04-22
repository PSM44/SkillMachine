param(
    [string]$RootPathOverride = "",
    [string]$OutputPathOverride = "",
    [string]$OldPathOverride = ""
)

# ==============================
# 00.00 METADATA
# ==============================

$RADAR_SCRIPT_VERSION = "v0.5.0"
$RADAR_OUTPUT_SCHEMA  = "v1.2"

# INDEX = inventario amplio
# CORE  = solo archivos legibles
# FULL  = INDEX + CORE + TREE_SIZE
# LITE  = diff básico vs ejecución previa
# MANIFEST = metadata estructurada

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

$CoreExtensions = @(".txt", ".md", ".ps1", ".json", ".yml", ".yaml", ".xml", ".csv", ".js", ".ts", ".sql", ".py")

$IndexFile    = Join-Path $OutputPath "radar.index.txt"
$CoreFile     = Join-Path $OutputPath "radar.core.txt"
$FullFile     = Join-Path $OutputPath "radar.full.txt"
$LiteFile     = Join-Path $OutputPath "radar.lite.txt"
$ManifestFile = Join-Path $OutputPath "radar.manifest.json"

$CurrentOutputNames = @(
    "radar.index.txt",
    "radar.core.txt",
    "radar.full.txt",
    "radar.lite.txt",
    "radar.manifest.json"
)

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

        return ($relativePath -replace '/', '\')
    }
    catch {
        return $TargetPath
    }
}

function Get-LogicalType {
    param([System.IO.FileInfo]$File)

    switch ($File.Extension.ToLowerInvariant()) {
        ".txt"  { return "text" }
        ".md"   { return "markdown" }
        ".ps1"  { return "powershell" }
        ".json" { return "json" }
        ".yml"  { return "yaml" }
        ".yaml" { return "yaml" }
        ".xml"  { return "xml" }
        ".csv"  { return "csv" }
        ".js"   { return "javascript" }
        ".ts"   { return "typescript" }
        ".sql"  { return "sql" }
        ".py"   { return "python" }
        ".xlsx" { return "xlsx" }
        ".xlsm" { return "xlsx" }
        ".pdf"  { return "pdf" }
        ".png"  { return "image" }
        ".jpg"  { return "image" }
        ".jpeg" { return "image" }
        ".gif"  { return "image" }
        ".zip"  { return "archive" }
        default {
            if ([string]::IsNullOrWhiteSpace($File.Extension)) {
                return "no_extension"
            }
            return "other"
        }
    }
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

function Read-PreviousManifest {
    param([string]$OldFolder)

    $candidate = Get-ChildItem -Path $OldFolder -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like "radar.manifest.*.json" } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if (-not $candidate) {
        return $null
    }

    try {
        $raw = Get-Content $candidate.FullName -Raw -Encoding utf8
        if ([string]::IsNullOrWhiteSpace($raw)) {
            return $null
        }
        return ($raw | ConvertFrom-Json)
    }
    catch {
        return $null
    }
}

function Get-TreeSizeRows {
    param(
        [System.IO.FileInfo[]]$Files,
        [string]$BasePath
    )

    $map = @{}

    foreach ($file in $Files) {
        $relative = Get-RelativePathSafe -BasePath $BasePath -TargetPath $file.FullName
        $dirRel = Split-Path $relative -Parent

        if ([string]::IsNullOrWhiteSpace($dirRel)) {
            $dirRel = "."
        }

        $segments = $dirRel -split '\\'
        $accum = @()

        if ($dirRel -eq ".") {
            if (-not $map.ContainsKey(".")) {
                $map["."] = [int64]0
            }
            $map["."] += $file.Length
        }
        else {
            if (-not $map.ContainsKey(".")) {
                $map["."] = [int64]0
            }
            $map["."] += $file.Length

            foreach ($segment in $segments) {
                if ([string]::IsNullOrWhiteSpace($segment)) { continue }
                $accum += $segment
                $key = ($accum -join '\')
                if (-not $map.ContainsKey($key)) {
                    $map[$key] = [int64]0
                }
                $map[$key] += $file.Length
            }
        }
    }

    return $map.GetEnumerator() |
        Sort-Object Name |
        ForEach-Object {
            [ordered]@{
                folder     = $_.Name
                size_bytes = $_.Value
                size_kb    = [math]::Round($_.Value / 1KB, 2)
            }
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
    $_.Name -in $CurrentOutputNames
} | ForEach-Object {
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $destName = "{0}.{1}{2}" -f $_.BaseName, $timestamp, $_.Extension
    $destPath = Join-Path $OldPath $destName

    Move-Item $_.FullName $destPath -Force
    $ArchivedFiles.Add($destPath) | Out-Null
}

$PreviousManifest = Read-PreviousManifest -OldFolder $OldPath

# ==============================
# 05.00 COLLECT FILES
# ==============================

$AllFiles = Get-ChildItem -Path $RootPath -Recurse -File | Where-Object {
    -not (Test-IsExcluded -Path $_.FullName)
} | Sort-Object FullName

$CoreFiles = $AllFiles | Where-Object {
    $_.Extension.ToLowerInvariant() -in $CoreExtensions
}

$GeneratedAt = Get-Date
$GeneratedAtText = $GeneratedAt.ToString("yyyy-MM-dd HH:mm:ss")

$AllFileRecords = @(
    $AllFiles | ForEach-Object {
        [ordered]@{
            relative_path = Get-RelativePathSafe -BasePath $RootPath -TargetPath $_.FullName
            full_path     = $_.FullName
            extension     = $_.Extension
            logical_type  = Get-LogicalType -File $_
            size_bytes    = $_.Length
            modified_at   = $_.LastWriteTime.ToString("yyyy-MM-ddTHH:mm:ss")
        }
    }
)

$CoreFileRecords = @(
    $CoreFiles | ForEach-Object {
        [ordered]@{
            relative_path = Get-RelativePathSafe -BasePath $RootPath -TargetPath $_.FullName
            full_path     = $_.FullName
            extension     = $_.Extension
            logical_type  = Get-LogicalType -File $_
            size_bytes    = $_.Length
            modified_at   = $_.LastWriteTime.ToString("yyyy-MM-ddTHH:mm:ss")
        }
    }
)

# ==============================
# 06.00 DIFF FOR LITE
# ==============================

$CurrentStateMap = @{}
foreach ($item in $AllFileRecords) {
    $CurrentStateMap[$item.relative_path] = $item
}

$PreviousStateMap = @{}
if ($PreviousManifest -and $PreviousManifest.scanned_files) {
    foreach ($item in $PreviousManifest.scanned_files) {
        $PreviousStateMap[$item.relative_path] = $item
    }
}

$NewFiles = New-Object System.Collections.Generic.List[string]
$ModifiedFiles = New-Object System.Collections.Generic.List[string]
$DeletedFiles = New-Object System.Collections.Generic.List[string]

foreach ($key in $CurrentStateMap.Keys) {
    if (-not $PreviousStateMap.ContainsKey($key)) {
        $NewFiles.Add($key) | Out-Null
        continue
    }

    $curr = $CurrentStateMap[$key]
    $prev = $PreviousStateMap[$key]

    if (($curr.size_bytes -ne $prev.size_bytes) -or ($curr.modified_at -ne $prev.modified_at)) {
        $ModifiedFiles.Add($key) | Out-Null
    }
}

foreach ($key in $PreviousStateMap.Keys) {
    if (-not $CurrentStateMap.ContainsKey($key)) {
        $DeletedFiles.Add($key) | Out-Null
    }
}

# ==============================
# 07.00 TREE SIZE
# ==============================

$TreeSizeRows = @(Get-TreeSizeRows -Files $AllFiles -BasePath $RootPath)

# ==============================
# 08.00 RADAR INDEX
# ==============================

Write-RadarHeader -FilePath $IndexFile -Title "RADAR INDEX" -OutputType "INDEX"

foreach ($item in $AllFileRecords) {
    "{0} | {1} bytes | {2} | {3} | {4}" -f `
        $item.relative_path, `
        $item.size_bytes, `
        $item.modified_at, `
        $item.extension, `
        $item.logical_type |
    Out-File $IndexFile -Append -Encoding utf8
}

# ==============================
# 09.00 RADAR CORE
# ==============================

Write-RadarHeader -FilePath $CoreFile -Title "RADAR CORE" -OutputType "CORE"

foreach ($file in $CoreFiles) {
    $relativePath = Get-RelativePathSafe -BasePath $RootPath -TargetPath $file.FullName

    "--------------------------------------------------" | Out-File $CoreFile -Append -Encoding utf8
    "FILE: $relativePath" | Out-File $CoreFile -Append -Encoding utf8
    "FULL_PATH: $($file.FullName)" | Out-File $CoreFile -Append -Encoding utf8
    "SIZE: $($file.Length) bytes" | Out-File $CoreFile -Append -Encoding utf8
    "MODIFIED: $($file.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))" | Out-File $CoreFile -Append -Encoding utf8
    "TYPE: $(Get-LogicalType -File $file)" | Out-File $CoreFile -Append -Encoding utf8
    "--------------------------------------------------" | Out-File $CoreFile -Append -Encoding utf8

    try {
        Get-Content $file.FullName -ErrorAction Stop | Out-File $CoreFile -Append -Encoding utf8
    }
    catch {
        "[UNREADABLE FILE]" | Out-File $CoreFile -Append -Encoding utf8
    }

    "" | Out-File $CoreFile -Append -Encoding utf8
}

# ==============================
# 10.00 RADAR FULL
# ==============================

Write-RadarHeader -FilePath $FullFile -Title "RADAR FULL" -OutputType "FULL"

"++++++++++" | Out-File $FullFile -Append -Encoding utf8
"FULL SECTION: INDEX" | Out-File $FullFile -Append -Encoding utf8
"++++++++++" | Out-File $FullFile -Append -Encoding utf8
"" | Out-File $FullFile -Append -Encoding utf8

Get-Content $IndexFile -Encoding utf8 | Out-File $FullFile -Append -Encoding utf8
"" | Out-File $FullFile -Append -Encoding utf8

"++++++++++" | Out-File $FullFile -Append -Encoding utf8
"FULL SECTION: CORE" | Out-File $FullFile -Append -Encoding utf8
"++++++++++" | Out-File $FullFile -Append -Encoding utf8
"" | Out-File $FullFile -Append -Encoding utf8

Get-Content $CoreFile -Encoding utf8 | Out-File $FullFile -Append -Encoding utf8
"" | Out-File $FullFile -Append -Encoding utf8

"++++++++++" | Out-File $FullFile -Append -Encoding utf8
"FULL SECTION: TREE_SIZE" | Out-File $FullFile -Append -Encoding utf8
"++++++++++" | Out-File $FullFile -Append -Encoding utf8
"" | Out-File $FullFile -Append -Encoding utf8

foreach ($row in $TreeSizeRows) {
    "{0} | {1} bytes | {2} KB" -f `
        $row.folder, `
        $row.size_bytes, `
        $row.size_kb |
    Out-File $FullFile -Append -Encoding utf8
}

# ==============================
# 11.00 RADAR LITE
# ==============================

Write-RadarHeader -FilePath $LiteFile -Title "RADAR LITE" -OutputType "LITE"

"TOTAL_FILES: $($AllFiles.Count)" | Out-File $LiteFile -Append -Encoding utf8
"CORE_FILES : $($CoreFiles.Count)" | Out-File $LiteFile -Append -Encoding utf8
"NEW_FILES_COUNT      : $($NewFiles.Count)" | Out-File $LiteFile -Append -Encoding utf8
"MODIFIED_FILES_COUNT : $($ModifiedFiles.Count)" | Out-File $LiteFile -Append -Encoding utf8
"DELETED_FILES_COUNT  : $($DeletedFiles.Count)" | Out-File $LiteFile -Append -Encoding utf8
"" | Out-File $LiteFile -Append -Encoding utf8

"INDEX_PATH   : $IndexFile" | Out-File $LiteFile -Append -Encoding utf8
"CORE_PATH    : $CoreFile" | Out-File $LiteFile -Append -Encoding utf8
"FULL_PATH    : $FullFile" | Out-File $LiteFile -Append -Encoding utf8
"MANIFEST_PATH: $ManifestFile" | Out-File $LiteFile -Append -Encoding utf8
"" | Out-File $LiteFile -Append -Encoding utf8

"++++++++++" | Out-File $LiteFile -Append -Encoding utf8
"NEW_FILES" | Out-File $LiteFile -Append -Encoding utf8
"++++++++++" | Out-File $LiteFile -Append -Encoding utf8
if ($NewFiles.Count -eq 0) {
    "[NONE]" | Out-File $LiteFile -Append -Encoding utf8
}
else {
    $NewFiles | Sort-Object | Out-File $LiteFile -Append -Encoding utf8
}
"" | Out-File $LiteFile -Append -Encoding utf8

"++++++++++" | Out-File $LiteFile -Append -Encoding utf8
"MODIFIED_FILES" | Out-File $LiteFile -Append -Encoding utf8
"++++++++++" | Out-File $LiteFile -Append -Encoding utf8
if ($ModifiedFiles.Count -eq 0) {
    "[NONE]" | Out-File $LiteFile -Append -Encoding utf8
}
else {
    $ModifiedFiles | Sort-Object | Out-File $LiteFile -Append -Encoding utf8
}
"" | Out-File $LiteFile -Append -Encoding utf8

"++++++++++" | Out-File $LiteFile -Append -Encoding utf8
"DELETED_FILES" | Out-File $LiteFile -Append -Encoding utf8
"++++++++++" | Out-File $LiteFile -Append -Encoding utf8
if ($DeletedFiles.Count -eq 0) {
    "[NONE]" | Out-File $LiteFile -Append -Encoding utf8
}
else {
    $DeletedFiles | Sort-Object | Out-File $LiteFile -Append -Encoding utf8
}
"" | Out-File $LiteFile -Append -Encoding utf8

# ==============================
# 12.00 RADAR MANIFEST
# ==============================

$Manifest = [ordered]@{
    radar_script_version = $RADAR_SCRIPT_VERSION
    radar_output_schema  = $RADAR_OUTPUT_SCHEMA
    generated_at         = $GeneratedAt.ToString("yyyy-MM-ddTHH:mm:ss")
    root_scanned         = $RootPath
    output_path          = $OutputPath
    old_path             = $OldPath
    excluded_paths       = $ExcludedPaths
    core_extensions      = $CoreExtensions
    total_file_count     = $AllFiles.Count
    core_file_count      = $CoreFiles.Count
    diff_summary         = [ordered]@{
        new_count      = $NewFiles.Count
        modified_count = $ModifiedFiles.Count
        deleted_count  = $DeletedFiles.Count
    }
    output_files         = @(
        [ordered]@{ type = "INDEX";    path = $IndexFile },
        [ordered]@{ type = "CORE";     path = $CoreFile },
        [ordered]@{ type = "FULL";     path = $FullFile },
        [ordered]@{ type = "LITE";     path = $LiteFile },
        [ordered]@{ type = "MANIFEST"; path = $ManifestFile }
    )
    archived_files       = @($ArchivedFiles)
    new_files            = @($NewFiles | Sort-Object)
    modified_files       = @($ModifiedFiles | Sort-Object)
    deleted_files        = @($DeletedFiles | Sort-Object)
    tree_size            = @($TreeSizeRows)
    scanned_files        = @($AllFileRecords)
}

$Manifest | ConvertTo-Json -Depth 8 | Out-File $ManifestFile -Encoding utf8

# ==============================
# 13.00 FINAL STATUS
# ==============================

Write-Host "OK"
Write-Host "GENERATED_AT: $GeneratedAtText"
Write-Host "INDEX   : $IndexFile"
Write-Host "CORE    : $CoreFile"
Write-Host "FULL    : $FullFile"
Write-Host "LITE    : $LiteFile"
Write-Host "MANIFEST: $ManifestFile"
Write-Host "FILES   : $($AllFiles.Count)"
Write-Host "NEW     : $($NewFiles.Count)"
Write-Host "MODIFIED: $($ModifiedFiles.Count)"
Write-Host "DELETED : $($DeletedFiles.Count)"