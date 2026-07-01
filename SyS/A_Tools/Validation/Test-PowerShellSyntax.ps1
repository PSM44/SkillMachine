$ErrorActionPreference = "Stop"
$env:GIT_PAGER = "cat"
$env:PAGER = "cat"

$Root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..\..")).Path

function Get-RelPath {
    param([string]$FullPath)
    return $FullPath.Substring($Root.Length).TrimStart("\")
}

function Test-InScopePowerShellFile {
    param([System.IO.FileInfo]$File)

    $rel = Get-RelPath -FullPath $File.FullName
    $p = $rel -replace "\\", "/"

    if ($p -match "^\.git(/|$)") { return $false }
    if ($p -match "^SyS/Temp(/|$)") { return $false }
    if ($p -match "^IA\.History(/|$)") { return $false }

    if ($File.Extension.ToLowerInvariant() -in @(".ps1", ".psm1", ".psd1")) {
        return $true
    }

    return $false
}

Write-Host "VALIDATION: PowerShell syntax"

$files = @(Get-ChildItem -LiteralPath $Root -Recurse -Force -File |
    Where-Object { Test-InScopePowerShellFile -File $_ } |
    Sort-Object FullName)

$total = [Math]::Max($files.Count, 1)
$index = 0
$failures = New-Object System.Collections.Generic.List[object]

foreach ($file in $files) {
    $index += 1
    $pct = [Math]::Min(100, [Math]::Floor(($index / $total) * 100))
    Write-Progress -Activity "Validate PowerShell syntax" -Status "Parsing $index of $total" -PercentComplete $pct

    $tokens = $null
    $errors = $null

    [System.Management.Automation.Language.Parser]::ParseFile(
        $file.FullName,
        [ref]$tokens,
        [ref]$errors
    ) | Out-Null

    if ($errors -and $errors.Count -gt 0) {
        $rel = Get-RelPath -FullPath $file.FullName
        foreach ($err in $errors) {
            $failures.Add([pscustomobject]@{
                REL_PATH = $rel
                LINE = $err.Extent.StartLineNumber
                COLUMN = $err.Extent.StartColumnNumber
                MESSAGE = $err.Message
                TEXT = $err.Extent.Text
            }) | Out-Null
        }
    }
}

Write-Progress -Activity "Validate PowerShell syntax" -Completed

if ($failures.Count -gt 0) {
    Write-Host "FAIL: PowerShell syntax validation failed"
    foreach ($f in $failures) {
        Write-Host ("FILE={0} LINE={1} COLUMN={2} MESSAGE={3}" -f $f.REL_PATH, $f.LINE, $f.COLUMN, $f.MESSAGE)
    }
    exit 1
}

Write-Host ("OK: PowerShell syntax validation passed ({0} files)" -f $files.Count)
exit 0