param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# ==========================================================
# 00.00 CONFIG
# ==========================================================

$UseCaseRoot = "C:\01. GitHub\Skills\90.USECASE"
$SkillsRoot = "C:\01. GitHub\Skills"
$RegistryPath = Join-Path $UseCaseRoot "USECASE.REGISTRY.json"
$VersionRegistryPath = Join-Path $UseCaseRoot "GLOBAL.SKILL.VERSION.REGISTRY.json"

# ==========================================================
# 01.00 HELPERS
# ==========================================================

function Read-JsonFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path
    )

    if (!(Test-Path -LiteralPath $Path)) {
        throw "Archivo JSON no encontrado: $Path"
    }

    try {
        return (Get-Content -LiteralPath $Path -Raw -Encoding utf8 | ConvertFrom-Json)
    }
    catch {
        throw "JSON inválido: $Path | $($_.Exception.Message)"
    }
}

function Get-NormalizedDirectoryPath {
    param(
        [Parameter(Mandatory = $true)][string]$Path
    )

    $full = [System.IO.Path]::GetFullPath($Path)
    if (-not $full.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
        $full += [System.IO.Path]::DirectorySeparatorChar
    }

    return $full
}

function Test-PathUnderRoot {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Root
    )

    $normalizedPath = [System.IO.Path]::GetFullPath($Path)
    $normalizedRoot = Get-NormalizedDirectoryPath -Path $Root

    return $normalizedPath.StartsWith($normalizedRoot, [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-Sha256Safe {
    param(
        [Parameter(Mandatory = $true)][string]$Path
    )

    if (!(Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "No se puede calcular hash; archivo no existe: $Path"
    }

    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash
}

function Find-CanonicalFile {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$FileName,
        [Parameter(Mandatory = $true)]$ExcludedRoots
    )

    $all = @(
        Get-ChildItem -Path $Root -Recurse -File | Where-Object {
            $full = $_.FullName
            $isExcluded = $false

            foreach ($ex in @($ExcludedRoots)) {
                if (Test-PathUnderRoot -Path $full -Root ([string]$ex)) {
                    $isExcluded = $true
                    break
                }
            }

            (-not $isExcluded) -and ($_.Name -eq $FileName)
        }
    )

    $matches = @($all)

    if ($matches.Count -eq 0) {
        throw "Archivo canónico no encontrado: $FileName"
    }

    if ($matches.Count -gt 1) {
        $paths = ($matches.FullName -join "`n")
        throw "Archivo canónico duplicado para '$FileName':`n$paths"
    }

    return @($matches[0])
}

function Get-TrackedSourceInfo {
    param(
        [Parameter(Mandatory = $true)]$VersionRegistry,
        [Parameter(Mandatory = $true)][string]$FileName
    )

    $items = @($VersionRegistry.skills | Where-Object { $_.file -eq $FileName })

    if ($items.Count -eq 0) {
        throw "Archivo requerido no registrado en GLOBAL.SKILL.VERSION.REGISTRY.json: $FileName"
    }

    if ($items.Count -gt 1) {
        throw "GLOBAL.SKILL.VERSION.REGISTRY.json tiene duplicado: $FileName"
    }

    return $items[0]
}

function Clear-GeneratedFiles {
    param(
        [Parameter(Mandatory = $true)][string]$FolderPath,
        [Parameter(Mandatory = $true)]$PromptFiles
    )

    $preserve = @(@($PromptFiles) + @("USECASE.MANIFEST.json", "SKILL_SET.MANIFEST.txt"))

    $toRemove = @(
        Get-ChildItem -Path $FolderPath -File -ErrorAction SilentlyContinue | Where-Object {
            $_.Name -notin $preserve
        }
    )

    if (@($toRemove).Count -gt 0) {
        @($toRemove) | Remove-Item -Force
    }

    return @($toRemove)
}

function Validate-UseCaseOutput {
    param(
        [Parameter(Mandatory = $true)][string]$TargetDir,
        [Parameter(Mandatory = $true)]$PromptFiles,
        [Parameter(Mandatory = $true)]$RequiredFiles
    )

    $missing = @()

    foreach ($p in @($PromptFiles)) {
        if (!(Test-Path -LiteralPath (Join-Path $TargetDir $p) -PathType Leaf)) {
            $missing += $p
        }
    }

    foreach ($r in @($RequiredFiles)) {
        if (!(Test-Path -LiteralPath (Join-Path $TargetDir $r) -PathType Leaf)) {
            $missing += $r
        }
    }

    return @($missing)
}

function Validate-ManifestIntegrity {
    param(
        [Parameter(Mandatory = $true)][string]$ManifestPath,
        [Parameter(Mandatory = $true)]$ManifestObject,
        [Parameter(Mandatory = $true)]$RequiredFiles,
        [Parameter(Mandatory = $true)][string]$TargetDir
    )

    if (!(Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
        throw "Manifest no fue generado: $ManifestPath"
    }

    $raw = Get-Content -LiteralPath $ManifestPath -Raw -Encoding utf8
    if ([string]::IsNullOrWhiteSpace($raw)) {
        throw "Manifest vacío: $ManifestPath"
    }

    $parsed = $raw | ConvertFrom-Json
    if ($null -eq $parsed) {
        throw "Manifest inválido: $ManifestPath"
    }

    $requiredNames = @($RequiredFiles | ForEach-Object { [string]$_ })
    $manifestNames = @($ManifestObject.files | ForEach-Object { [string]$_.name })

    foreach ($name in $requiredNames) {
        if ($name -notin $manifestNames) {
            throw "Manifest incompleto, falta archivo requerido: $name"
        }

        $destPath = Join-Path $TargetDir $name
        if (!(Test-Path -LiteralPath $destPath -PathType Leaf)) {
            throw "Archivo requerido no existe en destino durante validación final: $destPath"
        }
    }

    foreach ($entry in @($ManifestObject.files)) {
        if ([string]::IsNullOrWhiteSpace([string]$entry.source_sha256) -or [string]::IsNullOrWhiteSpace([string]$entry.dest_sha256)) {
            throw "Manifest con hash faltante para archivo: $($entry.name)"
        }

        if ([string]$entry.source_sha256 -ne [string]$entry.dest_sha256) {
            throw "Integridad FAIL por hash mismatch en archivo: $($entry.name)"
        }
    }
}

# ==========================================================
# 02.00 LOAD CONFIG
# ==========================================================

$registry = Read-JsonFile -Path $RegistryPath
$versionRegistry = Read-JsonFile -Path $VersionRegistryPath

if (-not $registry.usecases) {
    throw "USECASE.REGISTRY.json no contiene 'usecases'"
}

if (-not $registry.build_policy) {
    throw "USECASE.REGISTRY.json no contiene 'build_policy'"
}

$ExcludedRoots = @($registry.excluded_roots)

# ==========================================================
# 03.00 BUILD LOOP
# ==========================================================

$results = @()

foreach ($uc in @($registry.usecases)) {

    $UseCaseName = [string]$uc.name
    $UseCaseVersion = [string]$uc.version
    $TargetDir = Join-Path $UseCaseRoot $UseCaseName
    $PromptFiles = @($uc.prompt_files)
    $RequiredFiles = @($uc.required_files)

    if ($PromptFiles.Count -eq 1 -and [string]::IsNullOrWhiteSpace([string]$PromptFiles[0])) {
        $PromptFiles = @()
    }

    if ($RequiredFiles.Count -eq 1 -and [string]::IsNullOrWhiteSpace([string]$RequiredFiles[0])) {
        $RequiredFiles = @()
    }

    Write-Host ""
    Write-Host "=============================="
    Write-Host "BUILD USECASE: $UseCaseName"
    Write-Host "=============================="

    try {
        if (!(Test-Path -LiteralPath $TargetDir -PathType Container)) {
            throw "Carpeta de use case no existe: $TargetDir"
        }

        if (@($RequiredFiles).Count -eq 0) {
            throw "Use case '$UseCaseName' no define required_files válidos"
        }

        foreach ($p in @($PromptFiles)) {
            if (!(Test-Path -LiteralPath (Join-Path $TargetDir $p) -PathType Leaf)) {
                throw "Prompt faltante en use case: $p"
            }
        }

        if ($registry.build_policy.clean_generated_files_first -eq $true) {
            $removed = @(Clear-GeneratedFiles -FolderPath $TargetDir -PromptFiles $PromptFiles)
            Write-Host "LIMPIEZA: archivos eliminados = $(@($removed).Count)"
            foreach ($f in @($removed)) {
                Write-Host ("  - removed: {0}" -f $f.Name)
            }
        }

        $manifestFiles = @()
        $missingFiles = @()

        foreach ($file in @($RequiredFiles)) {
            $sourceMatches = @(Find-CanonicalFile -Root $SkillsRoot -FileName $file -ExcludedRoots $ExcludedRoots)
            $source = $sourceMatches[0]
            $dest = Join-Path $TargetDir $file

            Copy-Item -Path $source.FullName -Destination $dest -Force

            if (!(Test-Path -LiteralPath $dest -PathType Leaf)) {
                throw "Copy-Item no dejó archivo destino: $file -> $dest"
            }

            $tracked = Get-TrackedSourceInfo -VersionRegistry $versionRegistry -FileName $file

            $sourceHash = Get-Sha256Safe -Path $source.FullName
            $destHash = Get-Sha256Safe -Path $dest

            if ($sourceHash -ne $destHash) {
                throw "Hash mismatch post-copy para '$file'"
            }

            Write-Host ("COPIED: {0}" -f $file)

            $manifestFiles += [ordered]@{
                name = $file
                source_path = $source.FullName
                dest_path = $dest
                size_bytes = $source.Length
                modified_at = $source.LastWriteTime.ToString("yyyy-MM-ddTHH:mm:ss")
                version = [string]$tracked.version
                source_sha256 = [string]$sourceHash
                dest_sha256 = [string]$destHash
            }
        }

        $validationMissing = @(Validate-UseCaseOutput -TargetDir $TargetDir -PromptFiles $PromptFiles -RequiredFiles $RequiredFiles)

        if (@($validationMissing).Count -gt 0) {
            $missingFiles = @($missingFiles + $validationMissing)
        }

        $missingFiles = @($missingFiles)
        $manifestFiles = @($manifestFiles)

        $status = if ($missingFiles.Count -eq 0) { "OK" } else { "FAIL" }

        $manifest = [ordered]@{
            usecase = $UseCaseName
            usecase_version = $UseCaseVersion
            generated_at = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            source_root = $SkillsRoot
            files = $manifestFiles
            validation = [ordered]@{
                missing_files = @($missingFiles)
                status = $status
            }
        }

        $manifestPath = Join-Path $TargetDir "USECASE.MANIFEST.json"
        $manifest | ConvertTo-Json -Depth 10 | Set-Content -Path $manifestPath -Encoding utf8

        Validate-ManifestIntegrity -ManifestPath $manifestPath -ManifestObject $manifest -RequiredFiles $RequiredFiles -TargetDir $TargetDir

        if ($status -ne "OK") {
            throw "Validación final FAIL en $UseCaseName"
        }

        $results += [pscustomobject]@{
            usecase = $UseCaseName
            status = "OK"
            copied = @($RequiredFiles).Count
            error = ""
        }
        $results = @($results)

        Write-Host "OK - archivos copiados: $(@($RequiredFiles).Count)"
    }
    catch {
        $errMsg = $_.Exception.Message

        $results += [pscustomobject]@{
            usecase = $UseCaseName
            status = "FAIL"
            copied = 0
            error = $errMsg
        }
        $results = @($results)

        Write-Host "FAIL en $UseCaseName"
        Write-Host $errMsg
    }
}

# ==========================================================
# 04.00 SUMMARY
# ==========================================================

Write-Host ""
Write-Host "=============================="
Write-Host "RESUMEN FINAL"
Write-Host "=============================="

$results = @($results)
$okCount = @($results | Where-Object { $_.status -eq "OK" }).Count
$failCount = @($results | Where-Object { $_.status -eq "FAIL" }).Count

foreach ($r in @($results)) {
    Write-Host ("{0} | {1} | copied={2} | error={3}" -f $r.usecase, $r.status, $r.copied, $r.error)
}

Write-Host ""
Write-Host "TOTAL_OK   : $okCount"
Write-Host "TOTAL_FAIL : $failCount"

if ($failCount -gt 0) {
    exit 1
}

exit 0
