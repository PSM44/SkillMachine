#Requires -Version 5.1
# ProjectOps Common — MB-SM-076A3

function Get-ProjectOpsRoot {
    return [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
}

function Get-ProjectOpsStateRoot {
    param([string]$OpsRoot = (Get-ProjectOpsRoot))
    return (Join-Path $OpsRoot 'State')
}

function Write-ProjectOpsUtf8NoBom {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Content
    )
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false))
}

function Get-ProjectOpsSha256Text {
    param([Parameter(Mandatory = $true)][string]$Text)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    $hash = [System.Security.Cryptography.SHA256]::Create().ComputeHash($bytes)
    return ([System.BitConverter]::ToString($hash) -replace '-', '').ToUpperInvariant()
}

function ConvertTo-ProjectOpsJson {
    param([Parameter(Mandatory = $true)]$Object, [int]$Depth = 20)
    return ($Object | ConvertTo-Json -Depth $Depth -Compress:$false)
}

function Read-ProjectOpsJson {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "PROJECTOPS_FILE_MISSING: $Path"
    }
    return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
}

function New-ProjectOpsCorrelationId {
    return ('CORR-{0}' -f ([guid]::NewGuid().ToString('N').Substring(0, 16).ToUpperInvariant()))
}

function Get-ProjectOpsUtcNow {
    return (Get-Date).ToUniversalTime().ToString('o')
}
