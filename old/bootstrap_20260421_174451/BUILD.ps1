param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$UseCaseRoot = "C:\01. GitHub\Skills\90.USECASE"
$SkillsRoot  = "C:\01. GitHub\Skills"
$RegistryPath = Join-Path $UseCaseRoot "USECASE.REGISTRY.json"

function Find-CanonicalFile {
    param(
        [string]$Root,
        [string]$FileName
    )

    $matches = Get-ChildItem -Path $Root -Recurse -File | Where-Object {
        $_.FullName -notmatch '\\old\\' -and
        $_.FullName -notmatch '\\SyS\\' -and
        $_.FullName -notmatch '\\90\.USECASE\\' -and
        $_.Name -eq $FileName
    }

    if ($matches.Count -eq 0) {
        throw "Archivo no encontrado: $FileName"
    }

    if ($matches.Count -gt 1) {
        $paths = ($matches.FullName -join "`n")
        throw "Archivo duplicado detectado para '$FileName':`n$paths"
    }

    return $matches[0]
}

function Clear-UseCaseFolder {
    param(
        [string]$FolderPath
    )

    Get-ChildItem -Path $FolderPath -File -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -notlike "PROMPT.*.txt" -and
        $_.Name -ne "USECASE.MANIFEST.json"
    } | Remove-Item -Force
}

if (!(Test-Path $RegistryPath)) {
    Write-Error "USECASE.REGISTRY.json no encontrado: $RegistryPath"
    exit 1
}

try {
    $registry = Get-Content $RegistryPath -Raw | ConvertFrom-Json
}
catch {
    Write-Error "USECASE.REGISTRY.json inválido"
    Write-Error $_.Exception.Message
    exit 1
}

if (-not $registry.usecases) {
    Write-Error "USECASE.REGISTRY.json no contiene 'usecases'"
    exit 1
}

$results = @()

foreach ($usecase in $registry.usecases) {
    $name = $usecase.name
    $files = @($usecase.files)
    $targetDir = Join-Path $UseCaseRoot $name

    Write-Host ""
    Write-Host "=============================="
    Write-Host "BUILD USECASE: $name"
    Write-Host "=============================="

    if (!(Test-Path $targetDir)) {
        Write-Error "Carpeta de caso de uso no existe: $targetDir"
        $results += [pscustomobject]@{
            usecase = $name
            status  = "FAIL"
            copied  = 0
            error   = "Folder not found"
        }
        continue
    }

    try {
        Clear-UseCaseFolder -FolderPath $targetDir

        $copied = @()

        foreach ($file in $files) {
            $source = Find-CanonicalFile -Root $SkillsRoot -FileName $file
            $dest = Join-Path $targetDir $file

            Copy-Item -Path $source.FullName -Destination $dest -Force
            $copied += $file
        }

        $manifest = [ordered]@{
            usecase      = $name
            generated_at = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            copied_files = $copied
        }

        $manifest | ConvertTo-Json -Depth 5 | Set-Content -Path (Join-Path $targetDir "USECASE.MANIFEST.json") -Encoding utf8

        $results += [pscustomobject]@{
            usecase = $name
            status  = "OK"
            copied  = $copied.Count
            error   = ""
        }

        Write-Host "OK - archivos copiados: $($copied.Count)"
    }
    catch {
        $results += [pscustomobject]@{
            usecase = $name
            status  = "FAIL"
            copied  = 0
            error   = $_.Exception.Message
        }

        Write-Error "FAIL en $name"
        Write-Error $_.Exception.Message
    }
}

Write-Host ""
Write-Host "=============================="
Write-Host "RESUMEN FINAL"
Write-Host "=============================="

$okCount = ($results | Where-Object { $_.status -eq "OK" }).Count
$failCount = ($results | Where-Object { $_.status -eq "FAIL" }).Count

foreach ($r in $results) {
    Write-Host "$($r.usecase) | $($r.status) | copied=$($r.copied) | error=$($r.error)"
}

Write-Host ""
Write-Host "TOTAL_OK   : $okCount"
Write-Host "TOTAL_FAIL : $failCount"

if ($failCount -gt 0) {
    exit 1
}

exit 0