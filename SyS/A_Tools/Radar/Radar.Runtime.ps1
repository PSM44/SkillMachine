# Radar.Runtime.ps1
# Shared RADAR classification and scan implementation. PS 5.1 compatible.
# Canonical entry remains RADAR.ps1. Do not execute a scan on dot-source.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:RadarWin32Ready = $false
$script:RadarWin32Warning = ''

function Initialize-RadarWin32 {
    if ($script:RadarWin32Ready) { return }
    if ('RadarWin32' -as [type]) {
        $script:RadarWin32Ready = $true
        return
    }
    $code = @'
using System;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

public class RadarFileIdResult {
    public bool Ok;
    public uint VolumeSerialNumber;
    public uint FileIndexHigh;
    public uint FileIndexLow;
    public uint NumberOfLinks;
    public string Warning;
}

public static class RadarWin32 {
    [StructLayout(LayoutKind.Sequential)]
    public struct BY_HANDLE_FILE_INFORMATION {
        public uint FileAttributes;
        public System.Runtime.InteropServices.ComTypes.FILETIME CreationTime;
        public System.Runtime.InteropServices.ComTypes.FILETIME LastAccessTime;
        public System.Runtime.InteropServices.ComTypes.FILETIME LastWriteTime;
        public uint VolumeSerialNumber;
        public uint FileSizeHigh;
        public uint FileSizeLow;
        public uint NumberOfLinks;
        public uint FileIndexHigh;
        public uint FileIndexLow;
    }

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern SafeFileHandle CreateFile(
        string lpFileName,
        uint dwDesiredAccess,
        uint dwShareMode,
        IntPtr lpSecurityAttributes,
        uint dwCreationDisposition,
        uint dwFlagsAndAttributes,
        IntPtr hTemplateFile);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool GetFileInformationByHandle(
        SafeFileHandle hFile,
        out BY_HANDLE_FILE_INFORMATION lpFileInformation);

    public static RadarFileIdResult GetId(string path) {
        RadarFileIdResult r = new RadarFileIdResult();
        r.Ok = false;
        r.Warning = "FILE_ID_UNAVAILABLE";
        const uint GENERIC_READ = 0x80000000;
        const uint FILE_SHARE = 7;
        const uint OPEN_EXISTING = 3;
        const uint FLAGS = 0x02000000 | 0x00200000;
        SafeFileHandle handle = null;
        try {
            handle = CreateFile(path, GENERIC_READ, FILE_SHARE, IntPtr.Zero, OPEN_EXISTING, FLAGS, IntPtr.Zero);
            if (handle.IsInvalid) { return r; }
            BY_HANDLE_FILE_INFORMATION info;
            if (!GetFileInformationByHandle(handle, out info)) { return r; }
            r.Ok = true;
            r.Warning = "";
            r.VolumeSerialNumber = info.VolumeSerialNumber;
            r.FileIndexHigh = info.FileIndexHigh;
            r.FileIndexLow = info.FileIndexLow;
            r.NumberOfLinks = info.NumberOfLinks;
            return r;
        }
        catch {
            return r;
        }
        finally {
            if (handle != null && !handle.IsClosed) { handle.Dispose(); }
        }
    }
}
'@
    try {
        Add-Type -TypeDefinition $code -ErrorAction Stop | Out-Null
        $script:RadarWin32Ready = $true
    }
    catch {
        $script:RadarWin32Warning = 'FILE_ID_UNAVAILABLE'
        $script:RadarWin32Ready = $false
    }
}

function Get-RadarFileIdentity {
    param([Parameter(Mandatory = $true)][string]$Path)

    Initialize-RadarWin32
    $result = [ordered]@{
        Ok = $false
        VolumeId = ''
        FileId = ''
        NumberOfLinks = [uint32]0
        Source = 'FALLBACK_PATH'
        Warning = ''
    }

    if (-not $script:RadarWin32Ready) {
        $result.Warning = 'FILE_ID_UNAVAILABLE'
        return [pscustomobject]$result
    }

    try {
        $info = [RadarWin32]::GetId($Path)
        if ($null -eq $info -or -not [bool]$info.Ok) {
            $result.Warning = 'FILE_ID_UNAVAILABLE'
            return [pscustomobject]$result
        }
        $fileId = ([uint64]$info.FileIndexHigh -shl 32) -bor [uint64]$info.FileIndexLow
        $result.Ok = $true
        $result.VolumeId = ('{0:X8}' -f [uint32]$info.VolumeSerialNumber)
        $result.FileId = ('{0:X16}' -f $fileId)
        $result.NumberOfLinks = [uint32]$info.NumberOfLinks
        $result.Source = 'VOLUME_ID+FILE_ID'
        $result.Warning = ''
        return [pscustomobject]$result
    }
    catch {
        $result.Warning = 'FILE_ID_UNAVAILABLE'
        return [pscustomobject]$result
    }
}

function Get-RadarIdentityKey {
    param($Identity, [string]$Path)
    if ($null -ne $Identity -and [bool]$Identity.Ok) {
        return ('{0}:{1}' -f [string]$Identity.VolumeId, [string]$Identity.FileId)
    }
    return ('PATH:' + [string]$Path.ToUpperInvariant())
}

function Test-RadarShouldStopCycle {
    param(
        [Parameter(Mandatory = $true)]$Visited,
        $Identity,
        [Parameter(Mandatory = $true)][string]$Path
    )
    $key = Get-RadarIdentityKey -Identity $Identity -Path $Path
    if ($Visited.ContainsKey($key)) { return $true }
    $Visited[$key] = $Path
    return $false
}

function Test-RadarReparseItem {
    param($Item)
    if ($null -eq $Item) { return $false }
    try {
        $attr = $Item.Attributes
        return ([bool]($attr -band [System.IO.FileAttributes]::ReparsePoint))
    }
    catch {
        return $false
    }
}

function Get-RadarLinkInfo {
    param($Item, [string]$RootPath)

    $full = [string]$Item.FullName
    $isReparse = Test-RadarReparseItem -Item $Item
    $isShortcut = ([string]$Item.Extension -eq '.lnk')
    $linkType = 'NONE'
    $target = ''
    $targetState = ''
    $targetScope = ''
    $isBroken = $false
    $outsideRoot = $false

    if ($isShortcut) {
        $linkType = 'SHORTCUT'
        $targetState = 'REPORT_WITHOUT_FOLLOW'
        $targetScope = 'UNFOLLOWED'
    }
    elseif ($isReparse) {
        $linkType = 'REPARSE'
        try {
            $itemType = [string]$Item.LinkType
            if (-not [string]::IsNullOrWhiteSpace($itemType)) { $linkType = $itemType.ToUpperInvariant() }
        } catch {}
        try {
            if ($null -ne $Item.PSObject.Properties['Target'] -and $null -ne $Item.Target) {
                $t = $Item.Target
                if ($t -is [System.Array]) { $target = [string]$t[0] } else { $target = [string]$t }
            }
        } catch {}
        if ([string]::IsNullOrWhiteSpace($target)) {
            $targetState = 'INACCESSIBLE'
            $isBroken = $true
        }
        else {
            $resolved = $target
            try { $resolved = [System.IO.Path]::GetFullPath($target) } catch {}
            $rootFull = [System.IO.Path]::GetFullPath($RootPath).TrimEnd('\', '/')
            if ($resolved.StartsWith($rootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
                $targetScope = 'INSIDE_ROOT'
            }
            else {
                $targetScope = 'OUTSIDE_ROOT'
                $outsideRoot = $true
            }
            if (Test-Path -LiteralPath $resolved) {
                $targetState = 'VALID'
            }
            else {
                $targetState = 'BROKEN'
                $isBroken = $true
            }
        }
    }

    return [pscustomobject]@{
        IsReparse = $isReparse
        IsShortcut = $isShortcut
        Follow = $false
        LinkType = $linkType
        Target = $target
        TargetState = $targetState
        TargetScope = $targetScope
        IsBroken = $isBroken
        OutsideRoot = $outsideRoot
    }
}

function Test-RadarMagicPdf([byte[]]$Bytes) {
    if ($Bytes.Length -lt 4) { return $false }
    return ($Bytes[0] -eq 0x25 -and $Bytes[1] -eq 0x50 -and $Bytes[2] -eq 0x44 -and $Bytes[3] -eq 0x46)
}
function Test-RadarMagicPng([byte[]]$Bytes) {
    if ($Bytes.Length -lt 8) { return $false }
    return ($Bytes[0] -eq 0x89 -and $Bytes[1] -eq 0x50 -and $Bytes[2] -eq 0x4E -and $Bytes[3] -eq 0x47)
}
function Test-RadarMagicZip([byte[]]$Bytes) {
    if ($Bytes.Length -lt 4) { return $false }
    return ($Bytes[0] -eq 0x50 -and $Bytes[1] -eq 0x4B -and ($Bytes[2] -eq 0x03 -or $Bytes[2] -eq 0x05 -or $Bytes[2] -eq 0x07) -and ($Bytes[3] -eq 0x04 -or $Bytes[3] -eq 0x06 -or $Bytes[3] -eq 0x08))
}

function Test-RadarUtf8Strict([byte[]]$Bytes) {
    try {
        $enc = New-Object System.Text.UTF8Encoding $false, $true
        [void]$enc.GetString($Bytes)
        return $true
    }
    catch { return $false }
}

function Test-RadarUtf16([byte[]]$Bytes, [bool]$BigEndian) {
    if (($Bytes.Length % 2) -ne 0) { return $false }
    try {
        $enc = New-Object System.Text.UnicodeEncoding $BigEndian, $false, $true
        [void]$enc.GetString($Bytes)
        return $true
    }
    catch { return $false }
}

function Get-RadarControlRatio([byte[]]$Bytes) {
    if ($Bytes.Length -eq 0) { return 0.0 }
    $bad = 0
    foreach ($b in $Bytes) {
        if ($b -eq 9 -or $b -eq 10 -or $b -eq 13) { continue }
        if ($b -lt 32) { $bad++ }
    }
    return ([double]$bad / [double]$Bytes.Length)
}

function Get-RadarContentClassFromBytes {
    param(
        [AllowNull()][byte[]]$Bytes,
        [string]$Extension = '',
        [bool]$Unreadable = $false
    )

    $ext = ([string]$Extension).ToLowerInvariant()
    $textExt = @('.txt', '.md', '.ps1', '.json', '.yml', '.yaml', '.xml', '.csv', '.js', '.ts', '.sql', '.py')
    $binExt = @('.png', '.jpg', '.jpeg', '.gif', '.pdf', '.zip', '.exe', '.dll', '.bin', '.xlsx', '.xlsm')

    if ($Unreadable) {
        return [pscustomobject]@{ Class = 'UNREADABLE'; DetectionMethod = 'READ_ERROR'; Encoding = ''; Inline = $false }
    }
    if ($null -eq $Bytes -or $Bytes.Length -eq 0) {
        return [pscustomobject]@{ Class = 'TEXT'; DetectionMethod = 'EMPTY'; Encoding = 'EMPTY'; Inline = $true }
    }

    if (Test-RadarMagicPdf -Bytes $Bytes) {
        return [pscustomobject]@{ Class = 'BINARY'; DetectionMethod = 'MAGIC_PDF'; Encoding = ''; Inline = $false }
    }
    if (Test-RadarMagicPng -Bytes $Bytes) {
        return [pscustomobject]@{ Class = 'BINARY'; DetectionMethod = 'MAGIC_PNG'; Encoding = ''; Inline = $false }
    }
    if (Test-RadarMagicZip -Bytes $Bytes) {
        return [pscustomobject]@{ Class = 'BINARY'; DetectionMethod = 'MAGIC_ZIP'; Encoding = ''; Inline = $false }
    }

    $utf8Bom = ($Bytes.Length -ge 3 -and $Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF)
    $utf16LeBom = ($Bytes.Length -ge 2 -and $Bytes[0] -eq 0xFF -and $Bytes[1] -eq 0xFE)
    $utf16BeBom = ($Bytes.Length -ge 2 -and $Bytes[0] -eq 0xFE -and $Bytes[1] -eq 0xFF)

    if ($utf8Bom) {
        $rest = New-Object byte[] ($Bytes.Length - 3)
        [Array]::Copy($Bytes, 3, $rest, 0, $rest.Length)
        if ($rest.Length -eq 0 -or (Test-RadarUtf8Strict -Bytes $rest)) {
            return [pscustomobject]@{ Class = 'TEXT'; DetectionMethod = 'BOM_UTF8'; Encoding = 'UTF-8'; Inline = $true }
        }
    }
    if ($utf16LeBom) {
        return [pscustomobject]@{ Class = 'TEXT'; DetectionMethod = 'BOM_UTF16LE'; Encoding = 'UTF-16LE'; Inline = $true }
    }
    if ($utf16BeBom) {
        return [pscustomobject]@{ Class = 'TEXT'; DetectionMethod = 'BOM_UTF16BE'; Encoding = 'UTF-16BE'; Inline = $true }
    }

    $hasNul = $false
    foreach ($b in $Bytes) { if ($b -eq 0) { $hasNul = $true; break } }
    if ($hasNul) {
        return [pscustomobject]@{ Class = 'BINARY'; DetectionMethod = 'NUL'; Encoding = ''; Inline = $false }
    }

    if (Test-RadarUtf8Strict -Bytes $Bytes) {
        $cls = 'TEXT'
        $method = 'UTF8_STRICT'
        $inline = $true
        if ($binExt -contains $ext) {
            $method = 'TEXT_WITH_BINARY_EXTENSION'
            $inline = $false
        }
        return [pscustomobject]@{ Class = $cls; DetectionMethod = $method; Encoding = 'UTF-8'; Inline = $inline }
    }

    $ratio = Get-RadarControlRatio -Bytes $Bytes
    if ($ratio -gt 0.30) {
        return [pscustomobject]@{ Class = 'BINARY'; DetectionMethod = 'CONTROL_THRESHOLD'; Encoding = ''; Inline = $false }
    }

    if ($textExt -contains $ext) {
        return [pscustomobject]@{ Class = 'BINARY'; DetectionMethod = 'TEXT_EXT_NON_UTF8'; Encoding = ''; Inline = $false }
    }

    return [pscustomobject]@{ Class = 'UNKNOWN_FAIL_CLOSED'; DetectionMethod = 'UNCERTAIN'; Encoding = ''; Inline = $false }
}

function Get-RadarFingerprint {
    param([string]$Value)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $h = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes([string]$Value))
        return (([BitConverter]::ToString($h) -replace '-', '').Substring(0, 12))
    }
    finally { $sha.Dispose() }
}

function Get-RadarSecretHits {
    param([AllowNull()][string]$Text)
    $hits = @()
    if ([string]::IsNullOrEmpty($Text)) { return @() }

    $patterns = @(
        @{ Type = 'PRIVATE_KEY'; Pattern = '-----BEGIN (?:RSA |OPENSSH |EC )?PRIVATE KEY-----' },
        @{ Type = 'CONNECTION_STRING'; Pattern = '(?i)(?:Server|Data Source)\s*=\s*[^;]+;.*(?:Password|Pwd)\s*=\s*[^;]+' },
        @{ Type = 'TOKEN'; Pattern = '(?i)\b(?:api[_-]?key|secret|token)\s*[:=]\s*[A-Za-z0-9_\-]{16,}' },
        @{ Type = 'TOKEN'; Pattern = '\bghp_[A-Za-z0-9]{20,}' },
        @{ Type = 'TOKEN'; Pattern = '\bsk_test_[A-Za-z0-9]{8,}' }
    )

    foreach ($p in $patterns) {
        $matchesFound = [regex]::Matches($Text, [string]$p.Pattern)
        foreach ($m in $matchesFound) {
            if (-not $m.Success) { continue }
            $hits += [pscustomobject]@{
                Type = [string]$p.Type
                Fingerprint = Get-RadarFingerprint -Value ([string]$m.Value)
            }
        }
    }
    return $hits
}

function Test-RadarDoNotUploadPath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    if ($Path -match '(?i)[\\/]00\.SOURCE_DO_NOT_UPLOAD([\\/]|$)') { return $true }
    if ($Path -match '(?i)DO_NOT_UPLOAD') { return $true }
    return $false
}

function Test-RadarAccessPath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    return ($Path -match '(?i)[\\/]00_ACCESS([\\/]|$)')
}

function Test-RadarExcludedScanPath {
    param(
        [string]$Path,
        [string[]]$ExcludedPaths
    )
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    $candidate = $Path
    try { $candidate = [System.IO.Path]::GetFullPath($candidate) } catch {}
    $candidate = $candidate.TrimEnd('\', '/')
    foreach ($ex in @($ExcludedPaths)) {
        if ([string]::IsNullOrWhiteSpace($ex)) { continue }
        $ef = $ex
        try { $ef = [System.IO.Path]::GetFullPath($ef) } catch {}
        $ef = $ef.TrimEnd('\', '/')
        if ($candidate.Equals($ef, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
        if ($candidate.StartsWith($ef + '\', [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
        if ($candidate.StartsWith($ef + '/', [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    if ($candidate -match '(?i)[\\/]ImproveOp([\\/]|$)') { return $true }
    return $false
}

function Convert-RadarBytesToText {
    param([byte[]]$Bytes, [string]$EncodingName)
    if ($null -eq $Bytes -or $Bytes.Length -eq 0) { return '' }
    switch ([string]$EncodingName) {
        'UTF-16LE' { return [System.Text.Encoding]::Unicode.GetString($Bytes) }
        'UTF-16BE' { return [System.Text.Encoding]::BigEndianUnicode.GetString($Bytes) }
        'EMPTY' { return '' }
        default {
            $enc = New-Object System.Text.UTF8Encoding $false, $false
            return $enc.GetString($Bytes)
        }
    }
}

function Get-RadarLogicalTypeFromClass {
    param([string]$Class, [string]$Extension)
    if ($Class -eq 'BINARY') {
        switch ($Extension.ToLowerInvariant()) {
            '.pdf' { return 'pdf' }
            '.png' { return 'image' }
            '.jpg' { return 'image' }
            '.jpeg' { return 'image' }
            '.zip' { return 'archive' }
            default { return 'binary' }
        }
    }
    switch ($Extension.ToLowerInvariant()) {
        '.txt' { return 'text' }
        '.md' { return 'markdown' }
        '.ps1' { return 'powershell' }
        '.json' { return 'json' }
        default {
            if ([string]::IsNullOrWhiteSpace($Extension)) { return 'no_extension' }
            return 'other'
        }
    }
}

function Invoke-RadarEnumerate {
    param(
        [Parameter(Mandatory = $true)][string]$RootPath,
        [string[]]$ExcludedPaths,
        [int64]$CoreMaxFileSizeBytes = 2097152
    )

    $rootFull = [System.IO.Path]::GetFullPath($RootPath)
    $visitedDirs = @{}
    $seenContent = @{}
    $records = New-Object System.Collections.Generic.List[object]
    $cycles = New-Object System.Collections.Generic.List[string]
    $broken = New-Object System.Collections.Generic.List[string]
    $accessBlocked = New-Object System.Collections.Generic.List[string]
    $warnings = New-Object System.Collections.Generic.List[string]
    $hardlinkPaths = 0
    $uniquePhysical = 0
    $fileIdUnavailable = 0

    $queue = New-Object System.Collections.Generic.Queue[string]
    $queue.Enqueue($rootFull)

    while ($queue.Count -gt 0) {
        $dir = $queue.Dequeue()
        $dirId = Get-RadarFileIdentity -Path $dir
        if (Test-RadarShouldStopCycle -Visited $visitedDirs -Identity $dirId -Path $dir) {
            [void]$cycles.Add($dir)
            [void]$warnings.Add('CYCLE_STOP_AND_REPORT')
            continue
        }
        if (-not [bool]$dirId.Ok -and [string]$dirId.Warning -eq 'FILE_ID_UNAVAILABLE') {
            $fileIdUnavailable++
            [void]$warnings.Add('FILE_ID_UNAVAILABLE')
        }

        $items = @()
        try {
            $items = @(Get-ChildItem -LiteralPath $dir -Force -ErrorAction Stop)
        }
        catch {
            [void]$warnings.Add('DIR_UNREADABLE')
            continue
        }

        foreach ($item in $items) {
            $full = [string]$item.FullName
            if (Test-RadarExcludedScanPath -Path $full -ExcludedPaths $ExcludedPaths) { continue }

            $isDir = $false
            try { $isDir = [bool]$item.PSIsContainer } catch { $isDir = $false }

            $link = Get-RadarLinkInfo -Item $item -RootPath $rootFull
            if ($isDir -and (Test-RadarAccessPath -Path $full)) {
                [void]$accessBlocked.Add($full)
                $rec = [pscustomobject]@{
                    relative_path = ''
                    full_path = $full
                    extension = ''
                    logical_type = 'access_unfollowed'
                    size_bytes = [int64]0
                    modified_at = ''
                    sha256 = ''
                    content_class = 'EXCLUDED'
                    detection_method = '00_ACCESS'
                    encoding = ''
                    inline = $false
                    content_status = 'EXCLUDED_ACCESS'
                    file_id = ''
                    volume_id = ''
                    duplicate_of = ''
                    link_type = [string]$link.LinkType
                    target_ruta = [string]$link.Target
                    target_estado = 'UNFOLLOWED'
                    follow = $false
                    secret_types = @()
                    bytes = $null
                    text = ''
                    is_directory = $true
                }
                $rec.relative_path = $full.Substring($rootFull.Length).TrimStart('\', '/')
                [void]$records.Add($rec)
                continue
            }

            if ($link.IsReparse -or $link.IsShortcut) {
                if ([bool]$link.IsBroken) { [void]$broken.Add($full) }
                $id = Get-RadarFileIdentity -Path $full
                $rec = [pscustomobject]@{
                    relative_path = $full.Substring($rootFull.Length).TrimStart('\', '/')
                    full_path = $full
                    extension = [string]$item.Extension
                    logical_type = 'symlink'
                    size_bytes = [int64]0
                    modified_at = ''
                    sha256 = ''
                    content_class = 'EXCLUDED'
                    detection_method = 'REPARSE_UNFOLLOWED'
                    encoding = ''
                    inline = $false
                    content_status = $(if ([bool]$link.IsBroken) { 'BROKEN_LINK' } else { 'LINK_UNFOLLOWED' })
                    file_id = $(if ([bool]$id.Ok) { [string]$id.FileId } else { '' })
                    volume_id = $(if ([bool]$id.Ok) { [string]$id.VolumeId } else { '' })
                    duplicate_of = ''
                    link_type = [string]$link.LinkType
                    target_ruta = [string]$link.Target
                    target_estado = [string]$link.TargetState
                    follow = $false
                    secret_types = @()
                    bytes = $null
                    text = ''
                    is_directory = $isDir
                }
                try { $rec.size_bytes = [int64]$item.Length } catch {}
                try { $rec.modified_at = $item.LastWriteTime.ToString('yyyy-MM-ddTHH:mm:ss') } catch {}
                [void]$records.Add($rec)
                continue
            }

            if ($isDir) {
                $queue.Enqueue($full)
                continue
            }

            $identity = Get-RadarFileIdentity -Path $full
            $ikey = Get-RadarIdentityKey -Identity $identity -Path $full
            $duplicateOf = ''
            $countContent = $true
            if ([bool]$identity.Ok) {
                if ($seenContent.ContainsKey($ikey)) {
                    $duplicateOf = [string]$seenContent[$ikey]
                    $countContent = $false
                    $hardlinkPaths++
                }
                else {
                    $seenContent[$ikey] = $full
                    $uniquePhysical++
                    if ([uint32]$identity.NumberOfLinks -gt 1) { $hardlinkPaths++ }
                }
            }
            else {
                $fileIdUnavailable++
                $uniquePhysical++
                [void]$warnings.Add('FILE_ID_UNAVAILABLE')
            }

            $bytes = $null
            $unreadable = $false
            try {
                $bytes = [System.IO.File]::ReadAllBytes($full)
            }
            catch {
                $unreadable = $true
                $bytes = [byte[]]@()
            }

            $cls = Get-RadarContentClassFromBytes -Bytes $bytes -Extension ([string]$item.Extension) -Unreadable $unreadable
            $text = ''
            $secretHits = @()
            $contentStatus = [string]$cls.Class
            $inline = [bool]$cls.Inline

            if (Test-RadarDoNotUploadPath -Path $full) {
                $inline = $false
                $contentStatus = 'EXCLUDED_DO_NOT_UPLOAD'
                $cls = [pscustomobject]@{ Class = 'EXCLUDED'; DetectionMethod = 'DO_NOT_UPLOAD'; Encoding = ''; Inline = $false }
            }
            elseif ([bool]$cls.Inline -and $countContent) {
                $text = Convert-RadarBytesToText -Bytes $bytes -EncodingName ([string]$cls.Encoding)
                $secretHits = @(Get-RadarSecretHits -Text $text)
                if ($secretHits.Count -gt 0) {
                    $inline = $false
                    $text = ''
                    $contentStatus = 'SKIPPED_SECRET_RISK'
                }
                elseif ([int64]$item.Length -gt [int64]$CoreMaxFileSizeBytes) {
                    $inline = $false
                    $contentStatus = 'SKIPPED_TOO_LARGE'
                }
                else {
                    $contentStatus = 'TEXT'
                }
            }
            elseif ([string]$cls.Class -eq 'BINARY') { $contentStatus = 'BINARY' }
            elseif ([string]$cls.Class -eq 'UNREADABLE') { $contentStatus = 'UNREADABLE' }
            elseif ([string]$cls.Class -eq 'UNKNOWN_FAIL_CLOSED') { $contentStatus = 'UNKNOWN_FAIL_CLOSED' }

            if (-not $countContent) {
                $inline = $false
                $text = ''
                $bytes = $null
                if ($contentStatus -eq 'TEXT') { $contentStatus = 'HARDLINK_DEDUPED' }
            }

            $sha = ''
            if ($null -ne $bytes -and $bytes.Length -gt 0) {
                try { $sha = (Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash } catch { $sha = '' }
            }

            $rec = [pscustomobject]@{
                relative_path = $full.Substring($rootFull.Length).TrimStart('\', '/')
                full_path = $full
                extension = [string]$item.Extension
                logical_type = Get-RadarLogicalTypeFromClass -Class ([string]$cls.Class) -Extension ([string]$item.Extension)
                size_bytes = [int64]$item.Length
                modified_at = $item.LastWriteTime.ToString('yyyy-MM-ddTHH:mm:ss')
                sha256 = $sha
                content_class = [string]$cls.Class
                detection_method = [string]$cls.DetectionMethod
                encoding = [string]$cls.Encoding
                inline = $inline
                content_status = $contentStatus
                file_id = $(if ([bool]$identity.Ok) { [string]$identity.FileId } else { '' })
                volume_id = $(if ([bool]$identity.Ok) { [string]$identity.VolumeId } else { '' })
                duplicate_of = $duplicateOf
                link_type = 'NONE'
                target_ruta = ''
                target_estado = ''
                follow = $false
                secret_types = @($secretHits | ForEach-Object { $_.Type })
                secret_fingerprints = @($secretHits | ForEach-Object { $_.Fingerprint })
                bytes = $(if ($inline) { $bytes } else { $null })
                text = $text
                is_directory = $false
            }
            [void]$records.Add($rec)
        }
    }

    $uniqueWarnings = @()
    foreach ($w in $warnings) {
        if ($uniqueWarnings -notcontains [string]$w) { $uniqueWarnings += [string]$w }
    }
    $recArr = @()
    foreach ($r in $records) { $recArr += $r }
    $cycArr = @()
    foreach ($c in $cycles) { $cycArr += $c }
    $brkArr = @()
    foreach ($b in $broken) { $brkArr += $b }
    $accArr = @()
    foreach ($a in $accessBlocked) { $accArr += $a }
    return [pscustomobject]@{
        Records = $recArr
        Cycles = $cycArr
        BrokenLinks = $brkArr
        AccessBlocked = $accArr
        Warnings = $uniqueWarnings
        HardlinkPathsDiscovered = [int]$hardlinkPaths
        UniquePhysicalFilesCounted = [int]$uniquePhysical
        FileIdUnavailableCount = [int]$fileIdUnavailable
    }
}

function Convert-RadarPathJson {
    param([string]$Path)
    return (ConvertTo-Json -InputObject ([string]$Path) -Compress)
}

function Write-RadarUtf8NoBom {
    param([string]$Path, [string[]]$Lines)
    $enc = New-Object System.Text.UTF8Encoding $false
    $text = [string]::Join("`r`n", $Lines)
    if ($Lines.Count -gt 0) { $text = $text + "`r`n" }
    [System.IO.File]::WriteAllText($Path, $text, $enc)
}

function New-RadarHeaderLines {
    param(
        [string]$Title,
        [string]$OutputType,
        [string]$ScriptVersion,
        [string]$Schema,
        [string]$RootPath,
        [string]$OutputPath,
        [string]$OldPath,
        [string[]]$ExcludedPaths,
        [bool]$Sha256,
        [int64]$CoreMax,
        [int64]$SegMax,
        [string]$GeneratedAt
    )
    $lines = New-Object System.Collections.Generic.List[string]
    [void]$lines.Add('==============================')
    [void]$lines.Add($Title)
    [void]$lines.Add('==============================')
    [void]$lines.Add("RADAR_SCRIPT_VERSION: $ScriptVersion")
    [void]$lines.Add("RADAR_OUTPUT_SCHEMA : $Schema")
    [void]$lines.Add("OUTPUT_TYPE         : $OutputType")
    [void]$lines.Add("GENERATED_AT        : $GeneratedAt")
    [void]$lines.Add("ROOT_SCANNED        : $RootPath")
    [void]$lines.Add("OUTPUT_PATH         : $OutputPath")
    [void]$lines.Add("OLD_PATH            : $OldPath")
    [void]$lines.Add('FOLLOW_REPARSE_TARGETS_DEFAULT=NO')
    [void]$lines.Add('FOLLOW_00_ACCESS_TARGETS=NO')
    [void]$lines.Add('HARDLINK_CONTENT_COUNT=ONCE_PER_FILE_ID')
    [void]$lines.Add('BROKEN_LINKS=REPORT_WITHOUT_FOLLOW')
    [void]$lines.Add('CYCLES=STOP_AND_REPORT')
    [void]$lines.Add('NO_SUBIR != NO_GENERAR')
    [void]$lines.Add('EXCLUDED_PATHS      :')
    foreach ($ex in @($ExcludedPaths)) { [void]$lines.Add(" - $ex") }
    [void]$lines.Add("SHA256_ENABLED      : $Sha256")
    [void]$lines.Add("CORE_MAX_FILE_SIZE  : $CoreMax")
    [void]$lines.Add("SEGMENT_MAX_BYTES   : $SegMax")
    [void]$lines.Add('')
    return @($lines)
}

function Get-RadarInlineBlockLines {
    param($Record)
    $sha = [string]$Record.sha256
    if ([string]::IsNullOrWhiteSpace($sha)) { $sha = 'NONE' }
    $lines = New-Object System.Collections.Generic.List[string]
    [void]$lines.Add('=== RADAR_FILE_BEGIN ===')
    [void]$lines.Add(('PATH_JSON=' + (Convert-RadarPathJson -Path ([string]$Record.relative_path))))
    [void]$lines.Add(('SIZE_BYTES=' + [string]$Record.size_bytes))
    [void]$lines.Add(('SHA256=' + $sha))
    [void]$lines.Add(('ENCODING=' + [string]$Record.encoding))
    [void]$lines.Add(('CONTENT_STATUS=' + [string]$Record.content_status))
    [void]$lines.Add(('DETECTION_METHOD=' + [string]$Record.detection_method))
    [void]$lines.Add(('FILE_ID=' + [string]$Record.file_id))
    [void]$lines.Add(('VOLUME_ID=' + [string]$Record.volume_id))
    [void]$lines.Add(('DUPLICATE_OF=' + [string]$Record.duplicate_of))
    $content = [string]$Record.text
    $len = [System.Text.Encoding]::UTF8.GetByteCount($content)
    [void]$lines.Add(('CONTENT_LENGTH_BYTES=' + [string]$len))
    [void]$lines.Add(('--- RADAR_CONTENT_BEGIN:' + $sha + ' ---'))
    if ([bool]$Record.inline) {
        foreach ($ln in @($content -split "`r?`n", [System.StringSplitOptions]::None)) {
            [void]$lines.Add([string]$ln)
        }
    }
    [void]$lines.Add(('--- RADAR_CONTENT_END:' + $sha + ' ---'))
    [void]$lines.Add('=== RADAR_FILE_END ===')
    [void]$lines.Add('')
    return @($lines)
}

function Invoke-RadarScan {
    param(
        [Parameter(Mandatory = $true)][string]$RootPath,
        [Parameter(Mandatory = $true)][string]$OutputPath,
        [Parameter(Mandatory = $true)][string]$OldPath,
        [switch]$EnableSha256,
        [int64]$CoreMaxFileSizeBytes = 2097152,
        [int64]$SegmentMaxBytes = 8388608,
        [string[]]$UploadSelection = @('LITE', 'INDEX'),
        [int]$MaxFileCountWarning = 10000,
        [int64]$SizeWarningBytes = 104857600,
        [switch]$SimulateDiskFull,
        [string]$ScriptVersion = 'v0.7.0',
        [string]$Schema = 'v1.5'
    )

    $selNorm = New-Object System.Collections.Generic.List[string]
    foreach ($u in @($UploadSelection)) {
        foreach ($part in @(([string]$u -split ','))) {
            $p = $part.Trim()
            if (-not [string]::IsNullOrWhiteSpace($p)) { [void]$selNorm.Add($p) }
        }
    }
    if ($selNorm.Count -eq 0) {
        [void]$selNorm.Add('LITE')
        [void]$selNorm.Add('INDEX')
    }
    $UploadSelection = @($selNorm)

    $RootPath = [System.IO.Path]::GetFullPath($RootPath)
    $OutputPath = [System.IO.Path]::GetFullPath($OutputPath)
    $OldPath = [System.IO.Path]::GetFullPath($OldPath)

    if (-not (Test-Path -LiteralPath $RootPath -PathType Container)) {
        throw "Root path does not exist or is not a directory: $RootPath"
    }

    $excludedRaw = @(
        $OldPath
        $OutputPath
        (Join-Path $RootPath 'SyS\A_Tools\Radar')
        (Join-Path $RootPath 'SyS\A_Tools\OneShots\Backups')
        (Join-Path $RootPath 'IA.History')
    )
    $excluded = @()
    $seenEx = @{}
    foreach ($ex in $excludedRaw) {
        if ([string]::IsNullOrWhiteSpace([string]$ex)) { continue }
        $resolved = [string]$ex
        try { $resolved = [System.IO.Path]::GetFullPath($resolved) } catch {}
        $resolved = $resolved.TrimEnd('\', '/')
        $key = $resolved.ToUpperInvariant()
        if (-not $seenEx.ContainsKey($key)) {
            $seenEx[$key] = $true
            $excluded += $resolved
        }
    }

    if (-not (Test-Path -LiteralPath $OutputPath -PathType Container)) {
        [void](New-Item -ItemType Directory -Path $OutputPath -Force)
    }
    if (-not (Test-Path -LiteralPath $OldPath -PathType Container)) {
        [void](New-Item -ItemType Directory -Path $OldPath -Force)
    }

    $currentNames = @(
        'RADAR_INDEX.ACTIVE.txt'
        'RADAR_CORE.ACTIVE.txt'
        'RADAR_FULL.ACTIVE.txt'
        'RADAR_LITE.ACTIVE.txt'
        'RADAR_FULL.HUMAN.ACTIVE.txt'
        'RADAR_FULL.SKILLS.ACTIVE.txt'
        'radar.manifest.json'
    )

    $archived = New-Object System.Collections.Generic.List[string]
    Get-ChildItem -Path $OutputPath -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -in $currentNames } |
        ForEach-Object {
            $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
            $destName = '{0}.{1}{2}' -f $_.BaseName, $timestamp, $_.Extension
            $destPath = Join-Path $OldPath $destName
            Move-Item -LiteralPath $_.FullName -Destination $destPath -Force
            [void]$archived.Add($destPath)
        }

    $previousManifest = $null
    $prevFile = Get-ChildItem -Path $OldPath -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like 'radar.manifest.*.json' } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if ($null -ne $prevFile) {
        try {
            $previousManifest = (Get-Content -LiteralPath $prevFile.FullName -Raw -Encoding utf8) | ConvertFrom-Json
        } catch { $previousManifest = $null }
    }
    $firstRun = ($null -eq $previousManifest)

    $enum = Invoke-RadarEnumerate -RootPath $RootPath -ExcludedPaths $excluded -CoreMaxFileSizeBytes $CoreMaxFileSizeBytes
    $records = @($enum.Records | Where-Object { -not [bool]$_.is_directory } | Sort-Object relative_path)
    $allRecords = @($enum.Records | Sort-Object relative_path)

    if ([int]$records.Count -gt [int]$MaxFileCountWarning) {
        $enum.Warnings = @($enum.Warnings + 'SIZE_WARNING_FILE_COUNT')
    }
    $totalBytes = [int64]0
    foreach ($r in $records) {
        if ([string]::IsNullOrWhiteSpace([string]$r.duplicate_of)) { $totalBytes += [int64]$r.size_bytes }
    }
    if ($totalBytes -gt $SizeWarningBytes) {
        $enum.Warnings = @($enum.Warnings + 'SIZE_WARNING_BYTES')
    }

    $staging = Join-Path $OutputPath ('.radar_staging_' + [guid]::NewGuid().ToString('N'))
    [void](New-Item -ItemType Directory -Path $staging -Force)

    $indexFile = Join-Path $staging 'RADAR_INDEX.ACTIVE.txt'
    $coreFile = Join-Path $staging 'RADAR_CORE.ACTIVE.txt'
    $fullFile = Join-Path $staging 'RADAR_FULL.ACTIVE.txt'
    $liteFile = Join-Path $staging 'RADAR_LITE.ACTIVE.txt'
    $humanFile = Join-Path $staging 'RADAR_FULL.HUMAN.ACTIVE.txt'
    $skillsFile = Join-Path $staging 'RADAR_FULL.SKILLS.ACTIVE.txt'
    $manifestFile = Join-Path $staging 'radar.manifest.json'

    $now = Get-Date
    $nowText = $now.ToString('yyyy-MM-dd HH:mm:ss')
    $hdrArgs = @{
        ScriptVersion = $ScriptVersion
        Schema = $Schema
        RootPath = $RootPath
        OutputPath = $OutputPath
        OldPath = $OldPath
        ExcludedPaths = $excluded
        Sha256 = [bool]$EnableSha256
        CoreMax = $CoreMaxFileSizeBytes
        SegMax = $SegmentMaxBytes
        GeneratedAt = $nowText
    }

    $safeForUpload = $true
    foreach ($r in $records) {
        if ([string]$r.content_status -in @('SKIPPED_SECRET_RISK', 'UNREADABLE', 'UNKNOWN_FAIL_CLOSED', 'EXCLUDED_DO_NOT_UPLOAD')) {
            $safeForUpload = $false
        }
    }

    try {
        if ($SimulateDiskFull) { throw 'DISK_FULL_SIMULATED' }

        $indexLines = New-Object System.Collections.Generic.List[string]
        foreach ($l in (New-RadarHeaderLines -Title 'RADAR INDEX' -OutputType 'INDEX' @hdrArgs)) { [void]$indexLines.Add($l) }
        foreach ($r in $allRecords) {
            $line = '{0} | {1} bytes | {2} | {3} | {4} | CLASS={5} | STATUS={6} | METHOD={7} | FILE_ID={8} | VOLUME_ID={9} | DUP={10} | LINK={11} | TARGET={12} | TSTATE={13} | SHA256={14}' -f `
                [string]$r.relative_path, [string]$r.size_bytes, [string]$r.modified_at, [string]$r.extension, [string]$r.logical_type, `
                [string]$r.content_class, [string]$r.content_status, [string]$r.detection_method, [string]$r.file_id, [string]$r.volume_id, `
                [string]$r.duplicate_of, [string]$r.link_type, [string]$r.target_ruta, [string]$r.target_estado, `
                $(if ([string]::IsNullOrWhiteSpace([string]$r.sha256)) { '[DISABLED]' } else { [string]$r.sha256 })
            [void]$indexLines.Add($line)
        }
        Write-RadarUtf8NoBom -Path $indexFile -Lines @($indexLines)

        $coreLines = New-Object System.Collections.Generic.List[string]
        foreach ($l in (New-RadarHeaderLines -Title 'RADAR CORE' -OutputType 'CORE' @hdrArgs)) { [void]$coreLines.Add($l) }
        foreach ($r in $records) {
            if ([bool]$r.inline) {
                foreach ($bl in (Get-RadarInlineBlockLines -Record $r)) { [void]$coreLines.Add($bl) }
            }
            else {
                [void]$coreLines.Add(('SKIPPED path=' + [string]$r.relative_path + ' STATUS=' + [string]$r.content_status + ' METHOD=' + [string]$r.detection_method))
            }
        }
        Write-RadarUtf8NoBom -Path $coreFile -Lines @($coreLines)

        function Write-RadarSubset([string]$Path, [string]$Title, [string]$Type, $Pred) {
            $lines = New-Object System.Collections.Generic.List[string]
            foreach ($l in (New-RadarHeaderLines -Title $Title -OutputType $Type @hdrArgs)) { [void]$lines.Add($l) }
            $subset = @($records | Where-Object { & $Pred $_ })
            [void]$lines.Add('SAFE_FOR_UPLOAD=' + $(if ($Type -eq 'FULL.SKILLS' -and -not $safeForUpload) { 'NO' } else { 'NOT_AUTOMATIC' }))
            [void]$lines.Add('FAIL_CLOSED=' + $(if ($Type -eq 'FULL.SKILLS') { 'YES' } else { 'N/A' }))
            [void]$lines.Add('')
            foreach ($r in $subset) {
                $allow = [bool]$r.inline
                if ($Type -eq 'FULL.SKILLS') {
                    if ([string]$r.content_status -in @('SKIPPED_SECRET_RISK', 'EXCLUDED_DO_NOT_UPLOAD', 'UNREADABLE', 'UNKNOWN_FAIL_CLOSED', 'BINARY', 'HARDLINK_DEDUPED')) {
                        $allow = $false
                    }
                    if (Test-RadarDoNotUploadPath -Path ([string]$r.full_path)) { $allow = $false }
                    if (Test-RadarAccessPath -Path ([string]$r.full_path)) { $allow = $false }
                }
                if ($allow) {
                    foreach ($bl in (Get-RadarInlineBlockLines -Record $r)) { [void]$lines.Add($bl) }
                }
                else {
                    [void]$lines.Add(('SKIPPED path=' + [string]$r.relative_path + ' STATUS=' + [string]$r.content_status))
                }
            }
            Write-RadarUtf8NoBom -Path $Path -Lines @($lines)
        }

        Write-RadarSubset -Path $humanFile -Title 'RADAR FULL HUMAN' -Type 'FULL.HUMAN' -Pred {
            param($r)
            $rp = [string]$r.relative_path
            return (($rp -match '(^|[\\/])HUMAN([\\/._-]|$)') -or ([IO.Path]::GetFileName($rp) -match 'HUMAN'))
        }
        Write-RadarSubset -Path $skillsFile -Title 'RADAR FULL SKILLS' -Type 'FULL.SKILLS' -Pred {
            param($r)
            $rp = [string]$r.relative_path
            return ($rp -match '^(SkillsLake|GRCLake|90\.USECASE|00\.CATALOG)([\\/]|$)')
        }

        $fullLines = New-Object System.Collections.Generic.List[string]
        foreach ($l in (New-RadarHeaderLines -Title 'RADAR FULL' -OutputType 'FULL' @hdrArgs)) { [void]$fullLines.Add($l) }
        [void]$fullLines.Add('++++++++++')
        [void]$fullLines.Add('FULL SECTION: INDEX')
        [void]$fullLines.Add('++++++++++')
        foreach ($l in @($indexLines)) { [void]$fullLines.Add($l) }
        [void]$fullLines.Add('++++++++++')
        [void]$fullLines.Add('FULL SECTION: CORE')
        [void]$fullLines.Add('++++++++++')
        foreach ($l in @($coreLines)) { [void]$fullLines.Add($l) }
        Write-RadarUtf8NoBom -Path $fullFile -Lines @($fullLines)

        $liteLines = New-Object System.Collections.Generic.List[string]
        foreach ($l in (New-RadarHeaderLines -Title 'RADAR LITE' -OutputType 'LITE' @hdrArgs)) { [void]$liteLines.Add($l) }
        if ($firstRun) {
            [void]$liteLines.Add('FIRST_RUN=YES')
            [void]$liteLines.Add('LITE_MODE=version_0')
            [void]$liteLines.Add('DIFFS=NOT_CALCULATED')
        }
        else {
            [void]$liteLines.Add('FIRST_RUN=NO')
            [void]$liteLines.Add('LITE_MODE=diff')
        }
        [void]$liteLines.Add('OUTPUT_SET=INDEX,CORE,FULL,LITE,FULL.HUMAN,FULL.SKILLS,MANIFEST')
        [void]$liteLines.Add(('UPLOAD_SELECTION=' + ($UploadSelection -join ',')))
        [void]$liteLines.Add('NO_SUBIR != NO_GENERAR')
        [void]$liteLines.Add(('TOTAL_FILES=' + [string]$records.Count))
        [void]$liteLines.Add(('UNIQUE_PHYSICAL_FILES_COUNTED=' + [string]$enum.UniquePhysicalFilesCounted))
        [void]$liteLines.Add(('HARDLINK_PATHS_DISCOVERED=' + [string]$enum.HardlinkPathsDiscovered))
        [void]$liteLines.Add(('CYCLES=' + [string]$enum.Cycles.Count))
        [void]$liteLines.Add(('BROKEN_LINKS=' + [string]$enum.BrokenLinks.Count))
        [void]$liteLines.Add(('ACCESS_UNFOLLOWED=' + [string]$enum.AccessBlocked.Count))
        [void]$liteLines.Add(('WARNINGS=' + (($enum.Warnings) -join ',')))
        [void]$liteLines.Add(('SIZE_WARNING=' + $(if ($enum.Warnings -contains 'SIZE_WARNING_FILE_COUNT' -or $enum.Warnings -contains 'SIZE_WARNING_BYTES') { 'YES' } else { 'NO' })))
        [void]$liteLines.Add('CORE_GENERATED=YES')
        [void]$liteLines.Add('FULL_GENERATED=YES')
        [void]$liteLines.Add('FULL.HUMAN_GENERATED=YES')
        [void]$liteLines.Add('FULL.SKILLS_GENERATED=YES')
        Write-RadarUtf8NoBom -Path $liteFile -Lines @($liteLines)

        $manifest = [ordered]@{
            radar_script_version = $ScriptVersion
            radar_output_schema = $Schema
            generated_at = $now.ToString('yyyy-MM-ddTHH:mm:ss')
            root_scanned = $RootPath
            first_run = [bool]$firstRun
            output_set = @('INDEX', 'CORE', 'FULL', 'LITE', 'FULL.HUMAN', 'FULL.SKILLS', 'MANIFEST')
            upload_selection = @($UploadSelection)
            no_subir_equals_no_generar = $false
            safe_for_upload = [bool]$safeForUpload
            fail_closed_full_skills = $true
            follow_reparse_targets_default = $false
            follow_00_access_targets = $false
            hardlink_paths_discovered = [int]$enum.HardlinkPathsDiscovered
            unique_physical_files_counted = [int]$enum.UniquePhysicalFilesCounted
            cycles = @($enum.Cycles)
            broken_links = @($enum.BrokenLinks)
            access_unfollowed = @($enum.AccessBlocked)
            warnings = @($enum.Warnings)
            total_file_count = [int]$records.Count
            diff_summary = [ordered]@{ new_count = 0; modified_count = 0; deleted_count = 0 }
            output_files = @(
                [ordered]@{ type = 'INDEX'; path = (Join-Path $OutputPath 'RADAR_INDEX.ACTIVE.txt') },
                [ordered]@{ type = 'CORE'; path = (Join-Path $OutputPath 'RADAR_CORE.ACTIVE.txt') },
                [ordered]@{ type = 'FULL'; path = (Join-Path $OutputPath 'RADAR_FULL.ACTIVE.txt') },
                [ordered]@{ type = 'LITE'; path = (Join-Path $OutputPath 'RADAR_LITE.ACTIVE.txt') },
                [ordered]@{ type = 'FULL.HUMAN'; path = (Join-Path $OutputPath 'RADAR_FULL.HUMAN.ACTIVE.txt') },
                [ordered]@{ type = 'FULL.SKILLS'; path = (Join-Path $OutputPath 'RADAR_FULL.SKILLS.ACTIVE.txt') },
                [ordered]@{ type = 'MANIFEST'; path = (Join-Path $OutputPath 'radar.manifest.json') }
            )
        }
        $json = $manifest | ConvertTo-Json -Depth 8
        $enc = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText($manifestFile, $json, $enc)

        foreach ($name in $currentNames) {
            $src = Join-Path $staging $name
            $dst = Join-Path $OutputPath $name
            Move-Item -LiteralPath $src -Destination $dst -Force
        }
    }
    catch {
        if (Test-Path -LiteralPath $staging) {
            Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
        }
        throw
    }
    finally {
        if (Test-Path -LiteralPath $staging) {
            Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Write-Host 'OK'
    Write-Host "GENERATED_AT: $nowText"
    Write-Host "ROOT    : $RootPath"
    Write-Host "INDEX   : $(Join-Path $OutputPath 'RADAR_INDEX.ACTIVE.txt')"
    Write-Host "CORE    : $(Join-Path $OutputPath 'RADAR_CORE.ACTIVE.txt')"
    Write-Host "FULL    : $(Join-Path $OutputPath 'RADAR_FULL.ACTIVE.txt')"
    Write-Host "LITE    : $(Join-Path $OutputPath 'RADAR_LITE.ACTIVE.txt')"
    Write-Host "FULL_HUMAN : $(Join-Path $OutputPath 'RADAR_FULL.HUMAN.ACTIVE.txt')"
    Write-Host "FULL_SKILLS: $(Join-Path $OutputPath 'RADAR_FULL.SKILLS.ACTIVE.txt')"
    Write-Host "MANIFEST   : $(Join-Path $OutputPath 'radar.manifest.json')"
    Write-Host "FILES   : $($records.Count)"
    Write-Host "UNIQUE_PHYSICAL_FILES_COUNTED=$($enum.UniquePhysicalFilesCounted)"
    Write-Host "HARDLINK_PATHS_DISCOVERED=$($enum.HardlinkPathsDiscovered)"
    Write-Host "FIRST_RUN=$firstRun"
    Write-Host 'CORE=GENERATED'
    Write-Host 'FULL=GENERATED'
    Write-Host 'FULL.HUMAN=GENERATED'
    Write-Host 'FULL.SKILLS=GENERATED'
    return $true
}
