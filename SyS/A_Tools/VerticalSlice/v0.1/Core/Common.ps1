#Requires -Version 5.1
# VerticalSlice Core — shared pure helpers (MB-SM-075B)

function Get-Sha256Text([string]$Text) {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    $hash = [System.Security.Cryptography.SHA256]::Create().ComputeHash($bytes)
    return ([System.BitConverter]::ToString($hash) -replace '-', '').ToUpperInvariant()
}

function Get-Sha256File([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Write-Utf8NoBom([string]$Path, [string]$Content) {
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false))
}

function Read-KvFile([string]$Path) {
    $map = [ordered]@{}
    if (-not (Test-Path -LiteralPath $Path)) { return $map }
    foreach ($line in Get-Content -LiteralPath $Path -Encoding UTF8) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line.StartsWith('#')) { continue }
        $i = $line.IndexOf('=')
        if ($i -lt 1) { continue }
        $k = $line.Substring(0, $i).Trim()
        $v = $line.Substring($i + 1).Trim()
        $map[$k] = $v
    }
    return $map
}

function Reset-LabWorkspace([string]$LabRoot) {
    if ([string]::IsNullOrWhiteSpace($LabRoot)) { throw 'LAB_ROOT_REQUIRED' }
    if ($LabRoot -notmatch 'SM-LAB-004_SKILLS_IMPROVEMENT_VERTICAL_SLICE') {
        throw "REFUSING_RESET_OUTSIDE_LAB path=$LabRoot"
    }
    if (Test-Path -LiteralPath $LabRoot) {
        Remove-Item -LiteralPath $LabRoot -Recurse -Force
    }
    New-Item -ItemType Directory -Path $LabRoot -Force | Out-Null
}
