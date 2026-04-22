param(
    [string]$RootPathOverride = "",
    [string]$OutputPathOverride = "",
    [string]$OldPathOverride = "",
    [switch]$EnableSha256,
    [int64]$CoreMaxFileSizeBytes = 2097152,
    [int64]$SegmentMaxBytes = 8388608
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ==============================
# 00.00 METADATA
# ==============================

$RADAR_SCRIPT_VERSION = "v0.6.2"
$RADAR_OUTPUT_SCHEMA = "v1.4"

# INDEX = inventario amplio
# CORE = solo archivos legibles
# FULL = INDEX + CORE + TREE_SIZE
# LITE = diff básico vs ejecución previa
# MANIFEST = metadata estructurada

# ==============================
# 01.00 PATH RESOLUTION
# ==============================

$ScriptDir = $PSScriptRoot
$ToolsDir = Split-Path -Path $ScriptDir -Parent
$SysDir = Split-Path -Path $ToolsDir -Parent
$ProjectRootCandidate = Split-Path -Path $SysDir -Parent

$AutoRootPath = $ProjectRootCandidate
$AutoOutputPath = $ScriptDir
$AutoOldPath = Join-Path -Path $AutoRootPath -ChildPath "old\radar"

$RootPath = if ([string]::IsNullOrWhiteSpace($RootPathOverride)) { $AutoRootPath } else { $RootPathOverride }
$OutputPath = if ([string]::IsNullOrWhiteSpace($OutputPathOverride)) { $AutoOutputPath } else { $OutputPathOverride }
$OldPath = if ([string]::IsNullOrWhiteSpace($OldPathOverride)) { $AutoOldPath } else { $OldPathOverride }

$RootPath = [System.IO.Path]::GetFullPath($RootPath)
$OutputPath = [System.IO.Path]::GetFullPath($OutputPath)
$OldPath = [System.IO.Path]::GetFullPath($OldPath)

$ExcludedPaths = @(
    (Join-Path -Path $RootPath -ChildPath "old"),
    $OutputPath
)

$CoreExtensions = @(".txt", ".md", ".ps1", ".json", ".yml", ".yaml", ".xml", ".csv", ".js", ".ts", ".sql", ".py")

$IndexFile = Join-Path -Path $OutputPath -ChildPath "radar.index.txt"
$CoreFile = Join-Path -Path $OutputPath -ChildPath "radar.core.txt"
$FullFile = Join-Path -Path $OutputPath -ChildPath "radar.full.txt"
$LiteFile = Join-Path -Path $OutputPath -ChildPath "radar.lite.txt"
$ManifestFile = Join-Path -Path $OutputPath -ChildPath "radar.manifest.json"

$CurrentOutputNames = @(
    "radar.index.txt",
    "radar.core.txt",
    "radar.full.txt",
    "radar.lite.txt",
    "radar.manifest.json"
)

$ArchivedFiles = [System.Collections.Generic.List[string]]::new()
$GeneratedSegments = [System.Collections.Generic.List[string]]::new()

# ==============================
# 02.00 HELPERS
# ==============================

function Ensure-Directory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        [void](New-Item -ItemType Directory -Path $Path -Force -ErrorAction Stop)
    }
}

function Convert-AnyToArray {
    param([AllowNull()][object]$InputObject)

    if ($null -eq $InputObject) { return ,@() }
    if ($InputObject -is [string]) { return ,@([string]$InputObject) }
    if ($InputObject -is [System.Array]) { return ,@($InputObject) }
    if ($InputObject -is [System.Collections.IEnumerable]) { return ,@($InputObject | ForEach-Object { $_ }) }

    return ,@($InputObject)
}

function Get-SortedStringArray {
    param([AllowNull()][object]$InputValues)

    $values = @(Convert-AnyToArray -InputObject $InputValues)
    if ($values.Count -eq 0) { return @() }

    return @($values | ForEach-Object { [string]$_ } | Sort-Object)
}

function Convert-SkippedItemToObject {
    param([Parameter(Mandatory = $true)][object]$Item)

    $relativePath = ''
    $fullPath = ''
    $sizeBytes = [int64]0
    $maxAllowedBytes = [int64]0

    if ($Item -is [System.Collections.IDictionary]) {
        if ($Item.Contains('relative_path')) { $relativePath = [string]$Item['relative_path'] }
        if ($Item.Contains('full_path')) { $fullPath = [string]$Item['full_path'] }
        if ($Item.Contains('size_bytes')) { $sizeBytes = [int64]$Item['size_bytes'] }
        if ($Item.Contains('max_allowed_bytes')) { $maxAllowedBytes = [int64]$Item['max_allowed_bytes'] }
    }
    else {
        if ($null -ne $Item.PSObject.Properties['relative_path']) { $relativePath = [string]$Item.relative_path }
        if ($null -ne $Item.PSObject.Properties['full_path']) { $fullPath = [string]$Item.full_path }
        if ($null -ne $Item.PSObject.Properties['size_bytes']) { $sizeBytes = [int64]$Item.size_bytes }
        if ($null -ne $Item.PSObject.Properties['max_allowed_bytes']) { $maxAllowedBytes = [int64]$Item.max_allowed_bytes }
    }

    return [pscustomobject]@{
        relative_path = $relativePath
        full_path = $fullPath
        size_bytes = $sizeBytes
        max_allowed_bytes = $maxAllowedBytes
    }
}

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

        return ($relativePath -replace '/', '\\')
    }
    catch {
        return $TargetPath
    }
}

function Get-LogicalType {
    param([System.IO.FileInfo]$File)

    switch ($File.Extension.ToLowerInvariant()) {
        ".txt" { return "text" }
        ".md" { return "markdown" }
        ".ps1" { return "powershell" }
        ".json" { return "json" }
        ".yml" { return "yaml" }
        ".yaml" { return "yaml" }
        ".xml" { return "xml" }
        ".csv" { return "csv" }
        ".js" { return "javascript" }
        ".ts" { return "typescript" }
        ".sql" { return "sql" }
        ".py" { return "python" }
        ".xlsx" { return "xlsx" }
        ".xlsm" { return "xlsx" }
        ".pdf" { return "pdf" }
        ".png" { return "image" }
        ".jpg" { return "image" }
        ".jpeg" { return "image" }
        ".gif" { return "image" }
        ".zip" { return "archive" }
        default {
            if ([string]::IsNullOrWhiteSpace($File.Extension)) { return "no_extension" }
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
        " - $(Join-Path -Path $RootPath -ChildPath 'old')"
        " - $OutputPath"
        "SHA256_ENABLED      : $($EnableSha256.IsPresent)"
        "CORE_MAX_FILE_SIZE  : $CoreMaxFileSizeBytes"
        "SEGMENT_MAX_BYTES   : $SegmentMaxBytes"
        ""
    ) | Out-File -FilePath $FilePath -Encoding utf8
}

function Read-PreviousManifest {
    param([string]$OldFolder)

    $candidate = Get-ChildItem -Path $OldFolder -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like "radar.manifest.*.json" } |
        Sort-Object -Property LastWriteTime -Descending |
        Select-Object -First 1

    if ($null -eq $candidate) { return $null }

    try {
        $raw = Get-Content -LiteralPath $candidate.FullName -Raw -Encoding utf8
        if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
        return ($raw | ConvertFrom-Json -ErrorAction Stop)
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
        $dirRel = Split-Path -Path $relative -Parent

        if ([string]::IsNullOrWhiteSpace($dirRel)) { $dirRel = "." }

        $segments = $dirRel -split '\\'
        $accum = @()

        if (-not $map.ContainsKey(".")) { $map["."] = [int64]0 }
        $map["."] += $file.Length

        if ($dirRel -ne ".") {
            foreach ($segment in $segments) {
                if ([string]::IsNullOrWhiteSpace($segment)) { continue }
                $accum += $segment
                $key = ($accum -join '\\')
                if (-not $map.ContainsKey($key)) { $map[$key] = [int64]0 }
                $map[$key] += $file.Length
            }
        }
    }

    return @(
        $map.GetEnumerator() |
            Sort-Object -Property Name |
            ForEach-Object {
                [pscustomobject]@{
                    folder = [string]$_.Name
                    size_bytes = [int64]$_.Value
                    size_kb = [double][math]::Round($_.Value / 1KB, 2)
                }
            }
    )
}

function Get-FileSha256Safe {
    param([string]$Path)

    try {
        return (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash
    }
    catch {
        return ""
    }
}

function Remove-ExistingSegments {
    param([string]$BaseFilePath)

    $segmentPattern = "$BaseFilePath.seg.*"

    Get-ChildItem -Path $OutputPath -File -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -like $segmentPattern } |
        Remove-Item -Force -ErrorAction SilentlyContinue
}

function New-SegmentsFromTextFile {
    param(
        [string]$SourceFilePath,
        [int64]$MaxBytes
    )

    Remove-ExistingSegments -BaseFilePath $SourceFilePath

    $fileInfo = Get-Item -LiteralPath $SourceFilePath -ErrorAction Stop
    if ($fileInfo.Length -le $MaxBytes) { return @() }

    $segments = [System.Collections.Generic.List[string]]::new()
    $lines = Get-Content -LiteralPath $SourceFilePath -Encoding utf8 -ErrorAction Stop
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)

    $buffer = [System.Collections.Generic.List[string]]::new()
    $segmentIndex = 1

    function Flush-Segment {
        param(
            [System.Collections.Generic.List[string]]$SegmentBuffer,
            [int]$Index,
            [string]$SourcePath,
            [System.Text.UTF8Encoding]$EncodingNoBom
        )

        if ($SegmentBuffer.Count -eq 0) { return $null }

        $segmentPath = "{0}.seg.{1}" -f $SourcePath, $Index.ToString("000")
        [System.IO.File]::WriteAllLines($segmentPath, $SegmentBuffer, $EncodingNoBom)
        return $segmentPath
    }

    foreach ($line in $lines) {
        $candidate = [System.Collections.Generic.List[string]]::new()
        foreach ($existing in $buffer) { [void]$candidate.Add($existing) }
        [void]$candidate.Add([string]$line)

        $candidateText = [string]::Join([Environment]::NewLine, $candidate) + [Environment]::NewLine
        $candidateBytes = $utf8NoBom.GetByteCount($candidateText)

        if (($candidateBytes -gt $MaxBytes) -and ($buffer.Count -gt 0)) {
            $created = Flush-Segment -SegmentBuffer $buffer -Index $segmentIndex -SourcePath $SourceFilePath -EncodingNoBom $utf8NoBom
            if ($created) {
                [void]$segments.Add($created)
                [void]$GeneratedSegments.Add($created)
            }

            $segmentIndex++
            $buffer = [System.Collections.Generic.List[string]]::new()
            [void]$buffer.Add([string]$line)
        }
        else {
            $buffer = $candidate
        }
    }

    if ($buffer.Count -gt 0) {
        $created = Flush-Segment -SegmentBuffer $buffer -Index $segmentIndex -SourcePath $SourceFilePath -EncodingNoBom $utf8NoBom
        if ($created) {
            [void]$segments.Add($created)
            [void]$GeneratedSegments.Add($created)
        }
    }

    return (Convert-AnyToArray -InputObject $segments)
}

function Test-OutputIntegrity {
    param(
        [string[]]$TextOutputs,
        [string]$ManifestPath,
        [object]$ManifestObject,
        [int]$AllCount,
        [int]$NewCount,
        [int]$ModifiedCount,
        [int]$DeletedCount
    )

    foreach ($path in $TextOutputs) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Required output file not found: $path"
        }

        $len = (Get-Item -LiteralPath $path -ErrorAction Stop).Length
        if ($len -le 0) {
            throw "Output file is empty: $path"
        }
    }

    if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
        throw "Manifest file not found: $ManifestPath"
    }

    $manifestRaw = Get-Content -LiteralPath $ManifestPath -Raw -Encoding utf8 -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($manifestRaw)) {
        throw "Manifest file is empty: $ManifestPath"
    }

    $manifestParsed = $manifestRaw | ConvertFrom-Json -ErrorAction Stop
    if (-not $manifestParsed) {
        throw "Manifest is not valid JSON object: $ManifestPath"
    }

    if ($AllCount -lt ($NewCount + $ModifiedCount + $DeletedCount) -and $AllCount -ne 0) {
        throw "Inconsistent diff counters detected."
    }

    if ($null -eq $ManifestObject.diff_summary) {
        throw "Manifest diff_summary is missing."
    }
}

$ScriptSucceeded = $false

try {
    if (-not (Test-Path -LiteralPath $RootPath -PathType Container)) {
        throw "Root path does not exist or is not a directory: $RootPath"
    }

    Ensure-Directory -Path $OutputPath
    Ensure-Directory -Path $OldPath

    # ==============================
    # 03.00 ARCHIVE PREVIOUS OUTPUTS
    # ==============================

    Get-ChildItem -Path $OutputPath -File -ErrorAction SilentlyContinue |
        Where-Object { ($_.Name -in $CurrentOutputNames) -or ($_.Name -like "radar.*.seg.*") } |
        ForEach-Object {
            $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
            $destName = "{0}.{1}{2}" -f $_.BaseName, $timestamp, $_.Extension
            $destPath = Join-Path -Path $OldPath -ChildPath $destName

            Move-Item -LiteralPath $_.FullName -Destination $destPath -Force -ErrorAction Stop
            [void]$ArchivedFiles.Add($destPath)
        }

    $PreviousManifest = Read-PreviousManifest -OldFolder $OldPath

    # ==============================
    # 04.00 COLLECT FILES
    # ==============================

    $AllFiles = @(
        Get-ChildItem -Path $RootPath -Recurse -File -ErrorAction Stop |
            Where-Object { -not (Test-IsExcluded -Path $_.FullName) } |
            Sort-Object -Property FullName
    )

    $CoreFiles = @($AllFiles | Where-Object { $_.Extension.ToLowerInvariant() -in $CoreExtensions })

    $GeneratedAt = Get-Date
    $GeneratedAtText = $GeneratedAt.ToString("yyyy-MM-dd HH:mm:ss")

    $AllFileRecords = @(
        $AllFiles | ForEach-Object {
            $sha256 = ""
            if ($EnableSha256.IsPresent) { $sha256 = Get-FileSha256Safe -Path $_.FullName }

            [pscustomobject]@{
                relative_path = Get-RelativePathSafe -BasePath $RootPath -TargetPath $_.FullName
                full_path = $_.FullName
                extension = $_.Extension
                logical_type = Get-LogicalType -File $_
                size_bytes = [int64]$_.Length
                modified_at = $_.LastWriteTime.ToString("yyyy-MM-ddTHH:mm:ss")
                sha256 = [string]$sha256
            }
        }
    )

    # ==============================
    # 05.00 DIFF FOR LITE
    # ==============================

    $CurrentStateMap = @{}
    foreach ($item in $AllFileRecords) {
        $CurrentStateMap[[string]$item.relative_path] = $item
    }

    $PreviousStateMap = @{}
    if ($PreviousManifest -and $PreviousManifest.scanned_files) {
        foreach ($item in (Convert-AnyToArray -InputObject $PreviousManifest.scanned_files)) {
            $PreviousStateMap[[string]$item.relative_path] = $item
        }
    }

    $NewFiles = [System.Collections.Generic.List[string]]::new()
    $ModifiedFiles = [System.Collections.Generic.List[string]]::new()
    $DeletedFiles = [System.Collections.Generic.List[string]]::new()

    foreach ($key in @($CurrentStateMap.Keys)) {
        if (-not $PreviousStateMap.ContainsKey($key)) {
            [void]$NewFiles.Add([string]$key)
            continue
        }

        $curr = $CurrentStateMap[$key]
        $prev = $PreviousStateMap[$key]

        $isModified = $false

        if (([int64]$curr.size_bytes -ne [int64]$prev.size_bytes) -or ([string]$curr.modified_at -ne [string]$prev.modified_at)) {
            $isModified = $true
        }

        if ($EnableSha256.IsPresent -and ($curr.sha256) -and ($prev.sha256) -and ([string]$curr.sha256 -ne [string]$prev.sha256)) {
            $isModified = $true
        }

        if ($isModified) {
            [void]$ModifiedFiles.Add([string]$key)
        }
    }

    foreach ($key in @($PreviousStateMap.Keys)) {
        if (-not $CurrentStateMap.ContainsKey($key)) {
            [void]$DeletedFiles.Add([string]$key)
        }
    }

    # ==============================
    # 06.00 TREE SIZE
    # ==============================

    $TreeSizeRows = @(Get-TreeSizeRows -Files $AllFiles -BasePath $RootPath)

    # ==============================
    # 07.00 RADAR INDEX
    # ==============================

    Write-RadarHeader -FilePath $IndexFile -Title "RADAR INDEX" -OutputType "INDEX"

    foreach ($item in $AllFileRecords) {
        "{0} | {1} bytes | {2} | {3} | {4} | SHA256: {5}" -f `
            $item.relative_path, `
            $item.size_bytes, `
            $item.modified_at, `
            $item.extension, `
            $item.logical_type, `
            $(if ([string]::IsNullOrWhiteSpace($item.sha256)) { "[DISABLED]" } else { $item.sha256 }) |
            Out-File -FilePath $IndexFile -Append -Encoding utf8
    }

    # ==============================
    # 08.00 RADAR CORE
    # ==============================

    Write-RadarHeader -FilePath $CoreFile -Title "RADAR CORE" -OutputType "CORE"

    $SkippedTooLarge = [System.Collections.Generic.List[object]]::new()

    foreach ($file in $CoreFiles) {
        $relativePath = Get-RelativePathSafe -BasePath $RootPath -TargetPath $file.FullName

        "--------------------------------------------------" | Out-File -FilePath $CoreFile -Append -Encoding utf8
        "FILE: $relativePath" | Out-File -FilePath $CoreFile -Append -Encoding utf8
        "FULL_PATH: $($file.FullName)" | Out-File -FilePath $CoreFile -Append -Encoding utf8
        "SIZE: $($file.Length) bytes" | Out-File -FilePath $CoreFile -Append -Encoding utf8
        "MODIFIED: $($file.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))" | Out-File -FilePath $CoreFile -Append -Encoding utf8
        "TYPE: $(Get-LogicalType -File $file)" | Out-File -FilePath $CoreFile -Append -Encoding utf8
        "--------------------------------------------------" | Out-File -FilePath $CoreFile -Append -Encoding utf8

        if ([int64]$file.Length -gt [int64]$CoreMaxFileSizeBytes) {
            "SKIPPED_TOO_LARGE" | Out-File -FilePath $CoreFile -Append -Encoding utf8
            "MAX_ALLOWED_BYTES: $CoreMaxFileSizeBytes" | Out-File -FilePath $CoreFile -Append -Encoding utf8

            [void]$SkippedTooLarge.Add([ordered]@{
                relative_path = $relativePath
                full_path = $file.FullName
                size_bytes = [int64]$file.Length
                max_allowed_bytes = [int64]$CoreMaxFileSizeBytes
            })

            "" | Out-File -FilePath $CoreFile -Append -Encoding utf8
            continue
        }

        Get-Content -LiteralPath $file.FullName -ErrorAction Stop | Out-File -FilePath $CoreFile -Append -Encoding utf8
        "" | Out-File -FilePath $CoreFile -Append -Encoding utf8
    }

    # ==============================
    # 09.00 RADAR FULL
    # ==============================

    Write-RadarHeader -FilePath $FullFile -Title "RADAR FULL" -OutputType "FULL"

    "++++++++++" | Out-File -FilePath $FullFile -Append -Encoding utf8
    "FULL SECTION: INDEX" | Out-File -FilePath $FullFile -Append -Encoding utf8
    "++++++++++" | Out-File -FilePath $FullFile -Append -Encoding utf8
    "" | Out-File -FilePath $FullFile -Append -Encoding utf8

    Get-Content -LiteralPath $IndexFile -Encoding utf8 | Out-File -FilePath $FullFile -Append -Encoding utf8
    "" | Out-File -FilePath $FullFile -Append -Encoding utf8

    "++++++++++" | Out-File -FilePath $FullFile -Append -Encoding utf8
    "FULL SECTION: CORE" | Out-File -FilePath $FullFile -Append -Encoding utf8
    "++++++++++" | Out-File -FilePath $FullFile -Append -Encoding utf8
    "" | Out-File -FilePath $FullFile -Append -Encoding utf8

    Get-Content -LiteralPath $CoreFile -Encoding utf8 | Out-File -FilePath $FullFile -Append -Encoding utf8
    "" | Out-File -FilePath $FullFile -Append -Encoding utf8

    "++++++++++" | Out-File -FilePath $FullFile -Append -Encoding utf8
    "FULL SECTION: TREE_SIZE" | Out-File -FilePath $FullFile -Append -Encoding utf8
    "++++++++++" | Out-File -FilePath $FullFile -Append -Encoding utf8
    "" | Out-File -FilePath $FullFile -Append -Encoding utf8

    foreach ($row in $TreeSizeRows) {
        "{0} | {1} bytes | {2} KB" -f $row.folder, $row.size_bytes, $row.size_kb |
            Out-File -FilePath $FullFile -Append -Encoding utf8
    }

    # ==============================
    # 10.00 RADAR LITE
    # ==============================

    Write-RadarHeader -FilePath $LiteFile -Title "RADAR LITE" -OutputType "LITE"

    "TOTAL_FILES: $($AllFiles.Count)" | Out-File -FilePath $LiteFile -Append -Encoding utf8
    "CORE_FILES : $($CoreFiles.Count)" | Out-File -FilePath $LiteFile -Append -Encoding utf8
    "SKIPPED_TOO_LARGE_COUNT : $($SkippedTooLarge.Count)" | Out-File -FilePath $LiteFile -Append -Encoding utf8
    "NEW_FILES_COUNT      : $($NewFiles.Count)" | Out-File -FilePath $LiteFile -Append -Encoding utf8
    "MODIFIED_FILES_COUNT : $($ModifiedFiles.Count)" | Out-File -FilePath $LiteFile -Append -Encoding utf8
    "DELETED_FILES_COUNT  : $($DeletedFiles.Count)" | Out-File -FilePath $LiteFile -Append -Encoding utf8
    "" | Out-File -FilePath $LiteFile -Append -Encoding utf8

    "INDEX_PATH   : $IndexFile" | Out-File -FilePath $LiteFile -Append -Encoding utf8
    "CORE_PATH    : $CoreFile" | Out-File -FilePath $LiteFile -Append -Encoding utf8
    "FULL_PATH    : $FullFile" | Out-File -FilePath $LiteFile -Append -Encoding utf8
    "MANIFEST_PATH: $ManifestFile" | Out-File -FilePath $LiteFile -Append -Encoding utf8
    "" | Out-File -FilePath $LiteFile -Append -Encoding utf8

    "++++++++++" | Out-File -FilePath $LiteFile -Append -Encoding utf8
    "NEW_FILES" | Out-File -FilePath $LiteFile -Append -Encoding utf8
    "++++++++++" | Out-File -FilePath $LiteFile -Append -Encoding utf8
    if ($NewFiles.Count -eq 0) { "[NONE]" | Out-File -FilePath $LiteFile -Append -Encoding utf8 }
    else { (Get-SortedStringArray -InputValues $NewFiles) | Out-File -FilePath $LiteFile -Append -Encoding utf8 }
    "" | Out-File -FilePath $LiteFile -Append -Encoding utf8

    "++++++++++" | Out-File -FilePath $LiteFile -Append -Encoding utf8
    "MODIFIED_FILES" | Out-File -FilePath $LiteFile -Append -Encoding utf8
    "++++++++++" | Out-File -FilePath $LiteFile -Append -Encoding utf8
    if ($ModifiedFiles.Count -eq 0) { "[NONE]" | Out-File -FilePath $LiteFile -Append -Encoding utf8 }
    else { (Get-SortedStringArray -InputValues $ModifiedFiles) | Out-File -FilePath $LiteFile -Append -Encoding utf8 }
    "" | Out-File -FilePath $LiteFile -Append -Encoding utf8

    "++++++++++" | Out-File -FilePath $LiteFile -Append -Encoding utf8
    "DELETED_FILES" | Out-File -FilePath $LiteFile -Append -Encoding utf8
    "++++++++++" | Out-File -FilePath $LiteFile -Append -Encoding utf8
    if ($DeletedFiles.Count -eq 0) { "[NONE]" | Out-File -FilePath $LiteFile -Append -Encoding utf8 }
    else { (Get-SortedStringArray -InputValues $DeletedFiles) | Out-File -FilePath $LiteFile -Append -Encoding utf8 }
    "" | Out-File -FilePath $LiteFile -Append -Encoding utf8

    "++++++++++" | Out-File -FilePath $LiteFile -Append -Encoding utf8
    "SKIPPED_TOO_LARGE" | Out-File -FilePath $LiteFile -Append -Encoding utf8
    "++++++++++" | Out-File -FilePath $LiteFile -Append -Encoding utf8
    if ($SkippedTooLarge.Count -eq 0) {
        "[NONE]" | Out-File -FilePath $LiteFile -Append -Encoding utf8
    }
    else {
        foreach ($item in (Convert-AnyToArray -InputObject $SkippedTooLarge)) {
            $safeSkipped = Convert-SkippedItemToObject -Item $item
            "{0} | {1} bytes | MAX: {2}" -f $safeSkipped.relative_path, $safeSkipped.size_bytes, $safeSkipped.max_allowed_bytes |
                Out-File -FilePath $LiteFile -Append -Encoding utf8
        }
    }
    "" | Out-File -FilePath $LiteFile -Append -Encoding utf8

    # ==============================
    # 11.00 SEGMENTATION
    # ==============================

    $SegmentMap = [ordered]@{}
    foreach ($targetFile in @($IndexFile, $CoreFile, $FullFile, $LiteFile)) {
        $segments = New-SegmentsFromTextFile -SourceFilePath $targetFile -MaxBytes $SegmentMaxBytes
        $SegmentMap[$targetFile] = Convert-AnyToArray -InputObject $segments
    }

    # ==============================
    # 12.00 RADAR MANIFEST
    # ==============================

    $NewFilesSorted = Get-SortedStringArray -InputValues $NewFiles
    $ModifiedFilesSorted = Get-SortedStringArray -InputValues $ModifiedFiles
    $DeletedFilesSorted = Get-SortedStringArray -InputValues $DeletedFiles
    $ArchivedFilesArray = Get-SortedStringArray -InputValues $ArchivedFiles
    $GeneratedSegmentsArray = Get-SortedStringArray -InputValues $GeneratedSegments

    $SkippedTooLargeArray = @(
        Convert-AnyToArray -InputObject $SkippedTooLarge |
            ForEach-Object { Convert-SkippedItemToObject -Item $_ }
    )

    $TreeSizeRowsArray = @(
        $TreeSizeRows | ForEach-Object {
            [pscustomobject]@{
                folder = [string]$_.folder
                size_bytes = [int64]$_.size_bytes
                size_kb = [double]$_.size_kb
            }
        }
    )

    $AllFileRecordsArray = @(
        $AllFileRecords | ForEach-Object {
            [pscustomobject]@{
                relative_path = [string]$_.relative_path
                full_path = [string]$_.full_path
                extension = [string]$_.extension
                logical_type = [string]$_.logical_type
                size_bytes = [int64]$_.size_bytes
                modified_at = [string]$_.modified_at
                sha256 = [string]$_.sha256
            }
        }
    )

    $Manifest = [ordered]@{
        radar_script_version = $RADAR_SCRIPT_VERSION
        radar_output_schema = $RADAR_OUTPUT_SCHEMA
        generated_at = $GeneratedAt.ToString("yyyy-MM-ddTHH:mm:ss")
        root_scanned = $RootPath
        output_path = $OutputPath
        old_path = $OldPath
        excluded_paths = @($ExcludedPaths)
        core_extensions = @($CoreExtensions)
        sha256_enabled = $EnableSha256.IsPresent
        core_max_file_size = [int64]$CoreMaxFileSizeBytes
        segment_max_bytes = [int64]$SegmentMaxBytes
        total_file_count = [int]$AllFiles.Count
        core_file_count = [int]$CoreFiles.Count
        skipped_too_large_count = [int]$SkippedTooLarge.Count
        diff_summary = [ordered]@{
            new_count = [int]$NewFiles.Count
            modified_count = [int]$ModifiedFiles.Count
            deleted_count = [int]$DeletedFiles.Count
        }
        output_files = @(
            [ordered]@{ type = "INDEX"; path = $IndexFile; segments = @($SegmentMap[$IndexFile]) },
            [ordered]@{ type = "CORE"; path = $CoreFile; segments = @($SegmentMap[$CoreFile]) },
            [ordered]@{ type = "FULL"; path = $FullFile; segments = @($SegmentMap[$FullFile]) },
            [ordered]@{ type = "LITE"; path = $LiteFile; segments = @($SegmentMap[$LiteFile]) },
            [ordered]@{ type = "MANIFEST"; path = $ManifestFile; segments = @() }
        )
        archived_files = $ArchivedFilesArray
        generated_segments = $GeneratedSegmentsArray
        new_files = $NewFilesSorted
        modified_files = $ModifiedFilesSorted
        deleted_files = $DeletedFilesSorted
        skipped_too_large = $SkippedTooLargeArray
        tree_size = $TreeSizeRowsArray
        scanned_files = $AllFileRecordsArray
    }

    $manifestJson = $Manifest | ConvertTo-Json -Depth 12 -ErrorAction Stop
    $manifestJson | Out-File -FilePath $ManifestFile -Encoding utf8

    Test-OutputIntegrity -TextOutputs @($IndexFile, $CoreFile, $FullFile, $LiteFile) -ManifestPath $ManifestFile -ManifestObject $Manifest -AllCount $AllFiles.Count -NewCount $NewFiles.Count -ModifiedCount $ModifiedFiles.Count -DeletedCount $DeletedFiles.Count

    $ScriptSucceeded = $true

    Write-Host "OK"
    Write-Host "GENERATED_AT: $GeneratedAtText"
    Write-Host "ROOT    : $RootPath"
    Write-Host "INDEX   : $IndexFile"
    Write-Host "CORE    : $CoreFile"
    Write-Host "FULL    : $FullFile"
    Write-Host "LITE    : $LiteFile"
    Write-Host "MANIFEST: $ManifestFile"
    Write-Host "FILES   : $($AllFiles.Count)"
    Write-Host "NEW     : $($NewFiles.Count)"
    Write-Host "MODIFIED: $($ModifiedFiles.Count)"
    Write-Host "DELETED : $($DeletedFiles.Count)"
    Write-Host "SKIPPED : $($SkippedTooLarge.Count)"
    Write-Host "SEGMENTS: $($GeneratedSegments.Count)"
}
catch {
    $lineInfo = ""
    if ($_.InvocationInfo -and $_.InvocationInfo.ScriptLineNumber) {
        $lineInfo = " (line {0})" -f $_.InvocationInfo.ScriptLineNumber
    }

    [Console]::Error.WriteLine("RADAR FAILED{0}: {1}" -f $lineInfo, $_.Exception.Message)
}
finally {
    if ($ScriptSucceeded) { exit 0 }
    exit 1
}
