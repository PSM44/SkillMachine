$ErrorActionPreference = "Stop"

$Root = "C:\01. GitHub\Nightshift"
$ScriptPath = "Temp\TempScript.ps1"
$RunId = if ($args.Count -ge 1) { $args[0] } else { "RUN_TEMPSCRIPT" }
$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$LogDir = "Temp"
$LogPath = Join-Path $LogDir "$RunId.$Stamp.log"

Set-Location $Root
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

Write-Host "========== NIGHTSHIFT RUN_TEMPSCRIPT POWERSHELL / ACTIVATION =========="
Write-Host "LOCAL_TIME.......: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')"
Write-Host "ROOT_WIN.........: $Root"
Write-Host "SCRIPT_PATH......: $ScriptPath"
Write-Host "LOG_PATH.........: $LogPath"
Write-Host "RUN_ID...........: $RunId"
Write-Host "COPY_FROM_HERE...: YES"
Write-Host "======================================================================"

if (-not (Test-Path $ScriptPath)) {
    Write-Host "FAIL.............: Missing C:\01. GitHub\Nightshift\Temp\TempScript.ps1"
    Write-Host "ACTION...........: Save the full script in VS Code before running this tool."
    exit 1
}

$raw = Get-Content -Raw -Path $ScriptPath
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Resolve-Path $ScriptPath), $raw, $utf8NoBom)

$TmpScript = Join-Path $env:TEMP "nightshift_$RunId.$Stamp.ps1"
Copy-Item -Force $ScriptPath $TmpScript

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $TmpScript 2>&1 | Tee-Object -FilePath $LogPath

$ExitCode = $LASTEXITCODE
if ($null -eq $ExitCode) {
    $ExitCode = 0
}

Write-Host "======================================================================"
Write-Host "RUN_EXIT.........: $ExitCode"
Write-Host "LOG_SAVED........: $LogPath"
Write-Host "HEAD_AFTER.......: $(git log --oneline -1)"
Write-Host "STATUS_AFTER.....:"
git status --short
Write-Host "========== NIGHTSHIFT RUN_TEMPSCRIPT POWERSHELL / END =========="

exit $ExitCode
