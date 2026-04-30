param()

function Safe-GetArray([object]$obj, [string]$propName) {
  if ($null -eq $obj) { return @() }
  $p = $obj.PSObject.Properties[$propName]
  if ($null -eq $p) { return @() }
  if ($null -eq $obj.$propName) { return @() }
  return @(Normalize-ToArray $obj.$propName)
}


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

function Read-JsonFileSafe {
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

function Read-JsonFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path
    )

    return (Read-JsonFileSafe -Path $Path)
}

function Normalize-ToArray {
    param(
        [AllowNull()]$Value
    )

    if ($null -eq $Value) { return @() }
    if ($Value -is [System.Array]) { return @($Value) }
    if ($Value -is [string]) { return @([string]$Value) }
    return @($Value)
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

    $hashCmd = Get-Command Get-FileHash -ErrorAction SilentlyContinue
    if ($null -ne $hashCmd) {
        return (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash.ToUpperInvariant()
    }

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $resolved = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
        $bytes = [System.IO.File]::ReadAllBytes($resolved)
        $hashBytes = $sha.ComputeHash($bytes)
        return ([BitConverter]::ToString($hashBytes) -replace "-", "").ToUpperInvariant()
    }
    finally {
        if ($null -ne $sha) { $sha.Dispose() }
    }
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

            foreach ($ex in @(Normalize-ToArray $ExcludedRoots)) {
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

    $items = @(Normalize-ToArray $VersionRegistry.skills | Where-Object { $_.file -eq $FileName })

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
        [Parameter(Mandatory = $true)]$PreserveFiles
    )

    $preserve = @(@(Normalize-ToArray $PreserveFiles) + @("USECASE.MANIFEST.json", "SKILL_SET.MANIFEST.txt"))

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
        [Parameter(Mandatory = $true)]$DeliveryFiles
    )

    $missing = @()

    foreach ($p in @(Normalize-ToArray $PromptFiles)) {
        if (!(Test-Path -LiteralPath (Join-Path $TargetDir $p) -PathType Leaf)) {
            $missing += $p
        }
    }

    foreach ($d in @(Normalize-ToArray $DeliveryFiles)) {
        if (!(Test-Path -LiteralPath (Join-Path $TargetDir $d) -PathType Leaf)) {
            $missing += $d
        }
    }

    return @($missing)
}

function New-BundleFile {
    param(
        [Parameter(Mandatory = $true)][string]$BundlePath,
        [Parameter(Mandatory = $true)][string]$BundleName,
        [Parameter(Mandatory = $true)]$SourceEntries
    )

    $lines = [System.Collections.Generic.List[string]]::new()
    $generatedAt = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")

    [void]$lines.Add("==============================")
    [void]$lines.Add("BUNDLE: $BundleName")
    [void]$lines.Add("GENERATED_AT: $generatedAt")
    [void]$lines.Add("==============================")
    [void]$lines.Add("")

    foreach ($entry in @(Normalize-ToArray $SourceEntries)) {
        [void]$lines.Add("--------------------------------------------------")
        [void]$lines.Add("SOURCE_FILE: $($entry.name)")
        [void]$lines.Add("SOURCE_PATH: $($entry.source_path)")
        [void]$lines.Add("VERSION    : $($entry.version)")
        [void]$lines.Add("SHA256     : $($entry.source_sha256)")
        [void]$lines.Add("--------------------------------------------------")

        $contentLines = @(Get-Content -LiteralPath $entry.source_path -Encoding utf8 -ErrorAction Stop)
        foreach ($line in $contentLines) {
            [void]$lines.Add([string]$line)
        }

        [void]$lines.Add("")
    }

    [System.IO.File]::WriteAllLines($BundlePath, $lines, [System.Text.UTF8Encoding]::new($false))
}

function Validate-ManifestIntegrity {
    param(
        [Parameter(Mandatory = $true)][string]$ManifestPath,
        [Parameter(Mandatory = $true)]$ManifestObject,
        [Parameter(Mandatory = $true)]$DeliveryFiles,
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

    foreach ($name in @(Normalize-ToArray $DeliveryFiles)) {
        $path = Join-Path $TargetDir $name
        if (!(Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Delivery file faltante en validación final: $name"
        }
    }

    foreach ($bundle in @(Normalize-ToArray $ManifestObject.bundles)) {
        if (!(Test-Path -LiteralPath $bundle.delivery_path -PathType Leaf)) {
            throw "Bundle declarado no existe: $($bundle.delivery_path)"
        }

        $actualHash = Get-Sha256Safe -Path $bundle.delivery_path
        if ([string]$bundle.delivery_sha256 -ne [string]$actualHash) {
            throw "Hash delivery no coincide para bundle: $($bundle.bundle_name)"
        }

        foreach ($sourceEntry in @(Normalize-ToArray $bundle.source_files)) {
            if ([string]::IsNullOrWhiteSpace([string]$sourceEntry.source_sha256)) {
                throw "Source hash faltante en bundle '$($bundle.bundle_name)' archivo '$($sourceEntry.name)'"
            }
        }
    }
}

# ==========================================================
# 02.00 LOAD CONFIG
# ==========================================================

$registry = Read-JsonFileSafe -Path $RegistryPath
$versionRegistry = Read-JsonFileSafe -Path $VersionRegistryPath

if (-not $registry.usecases) {
    throw "USECASE.REGISTRY.json no contiene 'usecases'"
}

if (-not $registry.build_policy) {
    throw "USECASE.REGISTRY.json no contiene 'build_policy'"
}

$ExcludedRoots = @(Normalize-ToArray $registry.excluded_roots)

# ==========================================================
# 03.00 BUILD LOOP
# ==========================================================

$results = @()

foreach ($uc in @(Normalize-ToArray $registry.usecases)) {

    $UseCaseName = [string]$uc.name
    $UseCaseVersion = [string]$uc.version
    $TargetDir = Join-Path $UseCaseRoot $UseCaseName
    # Safe-get for optional usecase properties to avoid StrictMode property-not-found failures.
    $PromptFiles = @(Normalize-ToArray $(if ($uc.PSObject.Properties['prompt_files']) { $uc.prompt_files } else { @() }))
    $MenuFiles = @(Normalize-ToArray $(if ($uc.PSObject.Properties['menu_files']) { $uc.menu_files } else { @() }))
    $BundleDefinitions = @(Normalize-ToArray $(if ($uc.PSObject.Properties['bundle_definitions']) { $uc.bundle_definitions } else { @() }))

    if ($PromptFiles.Count -eq 1 -and [string]::IsNullOrWhiteSpace([string]$PromptFiles[0])) { $PromptFiles = @() }
    if ($MenuFiles.Count -eq 1 -and [string]::IsNullOrWhiteSpace([string]$MenuFiles[0])) { $MenuFiles = @() }

    Write-Host ""
    Write-Host "=============================="
    Write-Host "BUILD USECASE: $UseCaseName"
    Write-Host "=============================="

    try {
        if (!(Test-Path -LiteralPath $TargetDir -PathType Container)) {
            throw "Carpeta de use case no existe: $TargetDir"
        }

        if ($registry.build_policy.generate_bundles -ne $true) {
            throw "build_policy.generate_bundles debe ser true en BUILD v3"
        }

        if (@($BundleDefinitions).Count -eq 0) {
            throw "Use case '$UseCaseName' no define bundle_definitions"
        }

        foreach ($p in @($PromptFiles)) {
            if (!(Test-Path -LiteralPath (Join-Path $TargetDir $p) -PathType Leaf)) {
                throw "Prompt faltante en use case: $p"
            }
        }

        $preserveFiles = @($PromptFiles)

        if ($registry.build_policy.clean_generated_files_first -eq $true) {
            $removed = @(Clear-GeneratedFiles -FolderPath $TargetDir -PreserveFiles $preserveFiles)
            # OPTION_B_UC04_PRESERVE_EXCLUDE
            # Defensive: if preserve_files exist, do not count/remove them as cleanup targets.
            if ($PreserveFiles -and @($PreserveFiles).Count -gt 0 -and $removed) {
                $removed = @($removed | Where-Object { $PreserveFiles -notcontains $_ })
            }
            Write-Host "LIMPIEZA: archivos eliminados = $(@($removed).Count)"
            foreach ($f in @($removed)) {
                Write-Host ("  - removed: {0}" -f $f.Name)
            }
        }

        $deliveryFiles = @()
        # OPTION_B_DEFAULTS (avoid strict-mode uninitialized variables)
        # OPTION_B_UC04_READ_EXTRAS_FROM_REGISTRY
        # Populate extras from USECASE.REGISTRY when present (UC04), otherwise keep defaults.
        $PreserveFiles = @(Safe-GetArray $uc "preserve_files")
        $DeliveryFilesExtra = @(Safe-GetArray $uc "delivery_files_extra")
        $PreserveFiles = @()
        $DeliveryFilesExtra = @()
        # OPTION_B_UC04_DELIVERY_EXTRA
        # If registry provides delivery_files_extra, include them as delivery artifacts (rich usecase packaging).
        if ($DeliveryFilesExtra -and @($DeliveryFilesExtra).Count -gt 0) {
            $deliveryFiles += @($DeliveryFilesExtra)
        }
        $bundleManifest = @()

        foreach ($menuFile in @($MenuFiles)) {
            $menuMatches = @(Find-CanonicalFile -Root $SkillsRoot -FileName $menuFile -ExcludedRoots $ExcludedRoots)
            $menuSource = $menuMatches[0]
            $menuDest = Join-Path $TargetDir $menuFile
            Copy-Item -Path $menuSource.FullName -Destination $menuDest -Force

            if (!(Test-Path -LiteralPath $menuDest -PathType Leaf)) {
                throw "No se pudo copiar menu_file '$menuFile' a '$menuDest'"
            }

            Write-Host ("COPIED MENU: {0}" -f $menuFile)
            $deliveryFiles += $menuFile
        }

        foreach ($bundleDef in @($BundleDefinitions)) {
            $bundleName = [string]$bundleDef.name
            $bundleOutput = [string]$bundleDef.output_file
            $bundleSourceFiles = @(Normalize-ToArray $bundleDef.source_files)

            if ([string]::IsNullOrWhiteSpace($bundleName) -or [string]::IsNullOrWhiteSpace($bundleOutput)) {
                throw "bundle_definitions inválido en '$UseCaseName' (name/output_file requeridos)"
            }

            if (@($bundleSourceFiles).Count -eq 0) {
                throw "Bundle '$bundleName' en '$UseCaseName' no define source_files"
            }

            $sourceEntries = @()

            foreach ($sourceFile in @($bundleSourceFiles)) {
                $sourceMatches = @(Find-CanonicalFile -Root $SkillsRoot -FileName ([string]$sourceFile) -ExcludedRoots $ExcludedRoots)
                $source = $sourceMatches[0]
                $tracked = Get-TrackedSourceInfo -VersionRegistry $versionRegistry -FileName ([string]$sourceFile)
                $sourceHash = Get-Sha256Safe -Path $source.FullName

                $sourceEntries += [ordered]@{
                    name = [string]$sourceFile
                    source_path = $source.FullName
                    version = [string]$tracked.version
                    source_sha256 = [string]$sourceHash
                }
            }

            $bundlePath = Join-Path $TargetDir $bundleOutput
            New-BundleFile -BundlePath $bundlePath -BundleName $bundleName -SourceEntries $sourceEntries

            if (!(Test-Path -LiteralPath $bundlePath -PathType Leaf)) {
                throw "Bundle no fue generado: $bundlePath"
            }

            $bundleInfo = Get-Item -LiteralPath $bundlePath
            $bundleSizeKb = [math]::Round(([double]$bundleInfo.Length / 1KB), 2)

            if ($bundleSizeKb -gt [double]$registry.build_policy.max_bundle_size_kb) {
                throw "Bundle '$bundleOutput' excede max_bundle_size_kb ($bundleSizeKb KB > $($registry.build_policy.max_bundle_size_kb) KB)"
            }

            $bundleHash = Get-Sha256Safe -Path $bundlePath

            Write-Host ("BUNDLE GENERATED: {0} ({1} KB)" -f $bundleOutput, $bundleSizeKb)

            $bundleManifest += [ordered]@{
                bundle_name = $bundleName
                delivery_file = $bundleOutput
                delivery_path = $bundlePath
                delivery_size_bytes = [int64]$bundleInfo.Length
                delivery_size_kb = [double]$bundleSizeKb
                delivery_sha256 = [string]$bundleHash
                source_files = @($sourceEntries)
            }

            $deliveryFiles += $bundleOutput
        }

        foreach ($p in @($PromptFiles)) {
            $deliveryFiles += $p
        }

        # OPTION_B_UC04_DELIVERY_EXTRA_BEFORE_FINALIZE
        # DEBUG_UC04_DELIVERY_EXTRA (set env:SKILLS_DEBUG_UC04=1)
        if ($env:SKILLS_DEBUG_UC04 -eq "1") {
            try {
                if ($UseCaseName -eq "04.REPOSITORY_STRUCTURE_REPAIR") {
                    $hasProp = $false
                    if ($uc -and $uc.PSObject -and $uc.PSObject.Properties["delivery_files_extra"]) { $hasProp = $true }
                    Write-Host "DEBUG[UC04]: has uc.delivery_files_extra = $hasProp"
                    Write-Host ("DEBUG[UC04]: DeliveryFilesExtra.Count = {0}" -f @($DeliveryFilesExtra).Count)
                    if (@($DeliveryFilesExtra).Count -gt 0) {
                        $sample = @($DeliveryFilesExtra)[0..([Math]::Min(4,@($DeliveryFilesExtra).Count-1))]
                        Write-Host ("DEBUG[UC04]: DeliveryFilesExtra.sample = {0}" -f ($sample -join "; "))
                    }
                    Write-Host ("DEBUG[UC04]: deliveryFiles.Count(before finalize) = {0}" -f @($deliveryFiles).Count)
                }
            } catch {
                Write-Host ("DEBUG[UC04]: exception: {0}" -f $_.Exception.Message)
            }
        }
        # Ensure delivery_files_extra survive later rebuild/finalize of $deliveryFiles.
        if ($DeliveryFilesExtra -and @($DeliveryFilesExtra).Count -gt 0) {
            $deliveryFiles += @($DeliveryFilesExtra)
        }
        $deliveryFiles = @($deliveryFiles | ForEach-Object { [string]$_ } | Sort-Object -Unique)

        if (@($deliveryFiles).Count -gt [int]$registry.build_policy.max_delivery_files_per_usecase) {
            throw "Use case '$UseCaseName' excede max_delivery_files_per_usecase ($(@($deliveryFiles).Count) > $($registry.build_policy.max_delivery_files_per_usecase))"
        }

        $validationMissing = @(Validate-UseCaseOutput -TargetDir $TargetDir -PromptFiles $PromptFiles -DeliveryFiles $deliveryFiles)
        if (@($validationMissing).Count -gt 0) {
            throw "Validación de salida falló en '$UseCaseName'. Faltantes: $($validationMissing -join ', ')"
        }

        $manifest = [ordered]@{
            usecase = $UseCaseName
            usecase_version = $UseCaseVersion
            generated_at = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            source_root = $SkillsRoot
            delivery_files = @($deliveryFiles)
            bundles = @($bundleManifest)
            validation = [ordered]@{
                missing_files = @($validationMissing)
                delivery_file_count = @($deliveryFiles).Count
                max_delivery_files_allowed = [int]$registry.build_policy.max_delivery_files_per_usecase
                status = "OK"
            }
        }

        $manifestPath = Join-Path $TargetDir "USECASE.MANIFEST.json"
        $manifest | ConvertTo-Json -Depth 12 | Set-Content -Path $manifestPath -Encoding utf8

        Validate-ManifestIntegrity -ManifestPath $manifestPath -ManifestObject $manifest -DeliveryFiles $deliveryFiles -TargetDir $TargetDir

        $results += [pscustomobject]@{
            usecase = $UseCaseName
            status = "OK"
            copied = @($deliveryFiles).Count
            error = ""
        }
        $results = @($results)

        Write-Host "OK - delivery files: $(@($deliveryFiles).Count)"
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
    Write-Host ("{0} | {1} | delivery={2} | error={3}" -f $r.usecase, $r.status, $r.copied, $r.error)
}

Write-Host ""
Write-Host "TOTAL_OK   : $okCount"
Write-Host "TOTAL_FAIL : $failCount"

if ($failCount -gt 0) {
    exit 1
}

exit 0


