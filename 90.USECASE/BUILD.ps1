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

$SkillsRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$UseCaseRoot = Join-Path $SkillsRoot "90.USECASE"
$RegistryPath = Join-Path $UseCaseRoot "USECASE.REGISTRY.json"
$VersionRegistryPath = Join-Path $UseCaseRoot "GLOBAL.SKILL.VERSION.REGISTRY.json"
$UseCaseCompilerPath = Join-Path $SkillsRoot "SyS\A_Tools\UseCaseBuild\Compile-UseCaseSingleFile.ps1"

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

function Has-Property {
    param(
        [AllowNull()]$Object,
        [Parameter(Mandatory = $true)][string]$Name
    )

    return ($null -ne $Object -and $null -ne $Object.PSObject.Properties[$Name])
}

function Find-CanonicalFile {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$FileName,
        [Parameter(Mandatory = $true)]$ExcludedRoots
    )

    # MB-GRC-020E_RELATIVE_PATH_RESOLUTION
    # If the registry/manifest provides a path such as:
    #   SkillsLake/01.SKILLS/06.SKILL.WBS.txt
    # resolve it first as a path relative to repo root.
    # Only fall back to recursive filename search for bare filenames.
    $normalizedFileName = ([string]$FileName).Replace('/', [System.IO.Path]::DirectorySeparatorChar)
    $looksLikeRelativePath = ($normalizedFileName -match '[\\/]')

    if ($looksLikeRelativePath) {
        $candidatePath = Join-Path $Root $normalizedFileName

        if (Test-Path -LiteralPath $candidatePath -PathType Leaf) {
            return @(Get-Item -LiteralPath $candidatePath)
        }
    }
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

    $preserve = @(@(Normalize-ToArray $PreserveFiles))

    $toRemoveFiles = @(
        Get-ChildItem -Path $FolderPath -File -ErrorAction SilentlyContinue | Where-Object {
            $_.Name -notin $preserve
        }
    )

    $toRemoveDirs = @(
        Get-ChildItem -Path $FolderPath -Directory -Force -ErrorAction SilentlyContinue | Where-Object {
            $_.Name -notin $preserve
        }
    )

    if (@($toRemoveFiles).Count -gt 0) {
        @($toRemoveFiles) | Remove-Item -Force
    }

    if (@($toRemoveDirs).Count -gt 0) {
        @($toRemoveDirs) | Remove-Item -Recurse -Force
    }

    return @(@($toRemoveFiles) + @($toRemoveDirs))
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

function Validate-SupportPackageOutput {
    param(
        [Parameter(Mandatory = $true)][string]$TargetDir,
        [Parameter(Mandatory = $true)]$DeliveryFiles
    )

    $missing = @()

    foreach ($name in @(Normalize-ToArray $DeliveryFiles)) {
        if (!(Test-Path -LiteralPath (Join-Path $TargetDir ([string]$name)) -PathType Leaf)) {
            $missing += [string]$name
        }
    }

    return @($missing)
}

function Get-UseCaseSourceDirectoryPath {
    param(
        [Parameter(Mandatory = $true)]$UseCase,
        [Parameter(Mandatory = $true)][string]$SkillsRoot
    )

    $sourceDirectory = ""
    if (Has-Property $UseCase "source_directory") {
        $sourceDirectory = [string]$UseCase.source_directory
    }

    if ([string]::IsNullOrWhiteSpace($sourceDirectory)) {
        return $null
    }

    return (Join-Path $SkillsRoot $sourceDirectory)
}

function Resolve-DirectSourceEntries {
    param(
        [Parameter(Mandatory = $true)]$Package
    )

    $entries = @(Normalize-ToArray $(if ($Package.PSObject.Properties['source_entries']) { $Package.source_entries } else { @() }))
    if ($entries.Count -eq 0) {
        throw "Direct source_entries missing"
    }

    $normalized = @()
    foreach ($entry in @($entries)) {
        $path = [string]$entry.source_path
        $labels = @(Normalize-ToArray $entry.source_labels | ForEach-Object { [string]$_ })
        if ([string]::IsNullOrWhiteSpace($path)) {
            throw "Direct source entry path blank"
        }
        if ($labels.Count -eq 0) {
            throw "Direct source entry labels missing: $path"
        }
        $normalized += [ordered]@{
            source_path = $path
            source_labels = @($labels)
        }
    }

    return @($normalized)
}

function Get-UseCaseCopiedFiles {
    param(
        [Parameter(Mandatory = $true)]$UseCase
    )

    return @(Safe-GetArray $UseCase "copied_files" | ForEach-Object { [string]$_ })
}

function Get-CompiledOutputContract {
    param(
        [Parameter(Mandatory = $true)]$Package,
        [Parameter(Mandatory = $true)][string]$PackageName
    )

    $enabled = $false
    if (Has-Property $Package "compiled_output_enabled") {
        $enabled = [bool]$Package.compiled_output_enabled
    }

    $outputFile = ''
    if (Has-Property $Package "compiled_output_file") {
        $outputFile = [string]$Package.compiled_output_file
    }

    $formatVersion = ''
    if (Has-Property $Package "compiled_format_version") {
        $formatVersion = [string]$Package.compiled_format_version
    }

    $sourceEntries = @(Safe-GetArray $Package "source_entries")

    $uploadPackageModel = ''
    if (Has-Property $Package "upload_package_model") {
        $uploadPackageModel = [string]$Package.upload_package_model
    }

    if ($enabled) {
        if ([string]::IsNullOrWhiteSpace($outputFile)) {
            throw "Compiled output contract missing output file for '$PackageName'"
        }
        if ([string]::IsNullOrWhiteSpace($formatVersion)) {
            throw "Compiled output contract missing format version for '$PackageName'"
        }
        if (@($sourceEntries).Count -eq 0) {
            throw "Compiled output contract missing source_entries for '$PackageName'"
        }
    }

    return [pscustomobject]@{
        Enabled            = $enabled
        OutputFile         = $outputFile
        FormatVersion      = $formatVersion
        SourceEntryCount   = @($sourceEntries).Count
        UploadPackageModel = $uploadPackageModel
    }
}

function Test-IsSingleCompiledFromSourceEntries {
    param(
        [Parameter(Mandatory = $true)]$Package,
        [Parameter(Mandatory = $true)][string]$PackageName,
        [Parameter(Mandatory = $true)][string]$PackageKind
    )

    $contract = Get-CompiledOutputContract -Package $Package -PackageName $PackageName
    if ($contract.Enabled -ne $true) { return $false }
    if ([string]$contract.UploadPackageModel -ne 'SINGLE_COMPILED_FILE') { return $false }
    if ([int]$contract.SourceEntryCount -le 0) { return $false }
    if ([string]::IsNullOrWhiteSpace([string]$contract.OutputFile)) { return $false }

    if ($PackageKind -eq 'SUPPORT_PACKAGE') {
        return ([string]$PackageName -eq '05.SKILLSMACHINE_UPDATE')
    }

    return $true
}

function Invoke-CompiledOutputBuild {
    param(
        [Parameter(Mandatory = $true)]$Package,
        [Parameter(Mandatory = $true)][string]$PackageName,
        [Parameter(Mandatory = $true)][string]$PackageType,
        [Parameter(Mandatory = $true)][string]$PackageVersion,
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [Parameter(Mandatory = $true)][string]$TargetDirectory,
        [Parameter(Mandatory = $true)][object[]]$DirectSourceEntries
    )

    $contract = Get-CompiledOutputContract -Package $Package -PackageName $PackageName
    if ($contract.Enabled -ne $true) {
        return $null
    }

    return (New-UseCaseCompiledFile `
        -PackageName $PackageName `
        -PackageType $PackageType `
        -PackageVersion $PackageVersion `
        -ProjectRoot $ProjectRoot `
        -TargetDirectory $TargetDirectory `
        -OutputFileName $contract.OutputFile `
        -SourceEntries @($DirectSourceEntries) `
        -FormatVersion $contract.FormatVersion `
        -WriteOutput)
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

    $bundleBodyRaw = [string]::Join([Environment]::NewLine, @($lines)) + [Environment]::NewLine

    $bundleKey = ([string]$BundleName).ToUpperInvariant()

    $policyContract = switch ($bundleKey) {

        "CORE" { [pscustomobject]@{ SourceOfTruth="SkillsLake/01.SKILLS + 90.USECASE/USECASE.REGISTRY.json + 90.USECASE/GLOBAL.SKILL.VERSION.REGISTRY.json + 90.USECASE/BUILD.ps1"; GenerationMode="BUILD_BUNDLE_CORE" } }

        "CONTINUITY" { [pscustomobject]@{ SourceOfTruth="SkillsLake/01.SKILLS + 90.USECASE/USECASE.REGISTRY.json + 90.USECASE/GLOBAL.SKILL.VERSION.REGISTRY.json + 90.USECASE/BUILD.ps1"; GenerationMode="BUILD_BUNDLE_CONTINUITY" } }

        "GOVERNANCE" { [pscustomobject]@{ SourceOfTruth="SkillsLake/01.SKILLS + GRCLake + 90.USECASE/USECASE.REGISTRY.json + 90.USECASE/GLOBAL.SKILL.VERSION.REGISTRY.json + 90.USECASE/BUILD.ps1"; GenerationMode="BUILD_BUNDLE_GOVERNANCE" } }

        "UPDATE_CONTEXT" { [pscustomobject]@{ SourceOfTruth="SyS/A_Tools/Update + 90.USECASE/USECASE.REGISTRY.json + 90.USECASE/BUILD.ps1"; GenerationMode="BUILD_UPDATE_CONTEXT" } }

        "UPDATE_METHOD" { [pscustomobject]@{ SourceOfTruth="SyS/A_Tools/Update + SkillsLake/01.SKILLS + 90.USECASE/BUILD.ps1"; GenerationMode="BUILD_UPDATE_METHOD" } }

        "UPDATE_GOVERNANCE" { [pscustomobject]@{ SourceOfTruth="SyS/A_Tools/Update + GRCLake + 90.USECASE/BUILD.ps1"; GenerationMode="BUILD_UPDATE_GOVERNANCE" } }

        default { throw "Unsupported bundle name for generated-output policy: $BundleName" }

    }

    $headerLines=@(

        "========== GENERATED_OUTPUT_POLICY ==========",

        "GENERATED_OUTPUT_ONLY.......: YES",

        "DO_NOT_EDIT_MANUALLY........: YES",

        "SOURCE_OF_TRUTH.............: $($policyContract.SourceOfTruth)",

        "GENERATION_MODE.............: $($policyContract.GenerationMode)",

        "REGENERATION_CONTRACT.......: Re-run 90.USECASE/BUILD.ps1 from C:\01. GitHub\Skills",

        "HUMAN_OVERRIDE_REQUIRED.....: YES, if manual edit is intentional",

        "========== END_GENERATED_OUTPUT_POLICY =========="

    )

    $headerLf=[string]::Join("`n",$headerLines)

    $bodyLf=($bundleBodyRaw-replace"`r`n","`n").TrimStart([char[]]"`r`n").TrimEnd([char[]]"`r`n")

    $newRawLf=($headerLf+"`n`n"+$bodyLf).TrimEnd([char[]]"`r`n")+"`n"

    $newRaw=$newRawLf-replace"`n",[Environment]::NewLine

    if (Test-Path -LiteralPath $BundlePath -PathType Leaf) {
        $existingRaw = Get-Content -LiteralPath $BundlePath -Raw -Encoding utf8
        $normalizeForCompare = {
            param([string]$raw)
            $normalized = $raw -replace "`r`n", "`n"
            $normalized = $normalized.TrimStart([char]0xFEFF)
            $normalized = [regex]::Replace(
                $normalized,
                "(?s)^(?:=+\s*GENERATED_OUTPUT_POLICY\s*=+.*?=+\s*END_GENERATED_OUTPUT_POLICY\s*=+\n\n?)+",
                ""
            )
            $normalized = $normalized -replace "(?m)^GENERATED_AT:\s.*$", "GENERATED_AT: __PRESERVED__"
            $normalized = $normalized.TrimEnd("`n")
            return $normalized
        }

        if ((& $normalizeForCompare $newRaw) -eq (& $normalizeForCompare $existingRaw)) {
            return
        }
    }

    [System.IO.File]::WriteAllText($BundlePath, $newRaw, [System.Text.UTF8Encoding]::new($false))
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

    if ($ManifestObject.PSObject.Properties["compiled_output_enabled"] -and [bool]$ManifestObject.compiled_output_enabled) {
        $compiledOutputFile = [string]$ManifestObject.compiled_output_file
        if ([string]::IsNullOrWhiteSpace($compiledOutputFile)) {
            throw "Compiled output file missing in manifest: $ManifestPath"
        }

        $compiledOutputPath = Join-Path $TargetDir $compiledOutputFile
        if (!(Test-Path -LiteralPath $compiledOutputPath -PathType Leaf)) {
            throw "Compiled output missing in manifest validation: $compiledOutputFile"
        }

        $actualCompiledHash = Get-Sha256Safe -Path $compiledOutputPath
        if ([string]$ManifestObject.compiled_output_sha256 -ne [string]$actualCompiledHash) {
            throw "Compiled output hash mismatch for manifest: $compiledOutputFile"
        }
    }
}

function ConvertTo-ManifestCanonicalNode {
    param([AllowNull()][object]$Value,[switch]$ExcludeGeneratedAt)

    if ($null -eq $Value) { return $null }

    if ($Value -is [string] -or $Value -is [char] -or $Value -is [bool] -or
        $Value -is [byte] -or $Value -is [sbyte] -or
        $Value -is [int16] -or $Value -is [uint16] -or
        $Value -is [int32] -or $Value -is [uint32] -or
        $Value -is [int64] -or $Value -is [uint64] -or
        $Value -is [single] -or $Value -is [double] -or
        $Value -is [decimal] -or $Value -is [datetime]) {
        return $Value
    }

    if ($Value -is [System.Collections.IDictionary]) {
        $o=[ordered]@{}
        foreach($ko in @($Value.Keys|Sort-Object {[string]$_})) {
            $k=[string]$ko
            if($ExcludeGeneratedAt -and $k -eq 'generated_at'){continue}
            $o[$k]=ConvertTo-ManifestCanonicalNode -Value $Value[$ko] -ExcludeGeneratedAt:$ExcludeGeneratedAt
        }
        return [pscustomobject]$o
    }

    if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) {
        $l=[Collections.Generic.List[object]]::new()
        foreach($item in $Value){
            [void]$l.Add((ConvertTo-ManifestCanonicalNode -Value $item -ExcludeGeneratedAt:$ExcludeGeneratedAt))
        }
        return @($l)
    }

    $props=@($Value.PSObject.Properties|Where-Object{$_.MemberType-match'Property'}|Sort-Object Name)
    if($props.Count){
        $o=[ordered]@{}
        foreach($prop in $props){
            if($ExcludeGeneratedAt -and $prop.Name -eq 'generated_at'){continue}
            $o[$prop.Name]=ConvertTo-ManifestCanonicalNode -Value $prop.Value -ExcludeGeneratedAt:$ExcludeGeneratedAt
        }
        return [pscustomobject]$o
    }

    return $Value
}

function ConvertTo-ManifestComparableJson {
    param([Parameter(Mandatory=$true)]$ManifestObject)
    $c=ConvertTo-ManifestCanonicalNode -Value $ManifestObject -ExcludeGeneratedAt
    return ($c|ConvertTo-Json -Depth 100 -Compress)
}

function Write-ManifestIfChanged {
    param(
        [Parameter(Mandatory=$true)][string]$ManifestPath,
        [Parameter(Mandatory=$true)]$ManifestObject
    )

    $finalManifest=($ManifestObject|ConvertTo-Json -Depth 100|ConvertFrom-Json)

    if(Test-Path -LiteralPath $ManifestPath -PathType Leaf){
        $existingRaw=Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8
        $existing=$existingRaw|ConvertFrom-Json -ErrorAction Stop
        $a=ConvertTo-ManifestComparableJson -ManifestObject $existing
        $b=ConvertTo-ManifestComparableJson -ManifestObject $finalManifest
        if($a -ceq $b){ return $existing }
    }

    $json=$finalManifest|ConvertTo-Json -Depth 100
    $canonical=$json.TrimEnd([char[]]"`r`n")+[Environment]::NewLine
    [IO.File]::WriteAllText($ManifestPath,$canonical,[Text.UTF8Encoding]::new($false))
    return $finalManifest
}

function Invoke-SupportPackagePreflight {
    param(
        [Parameter(Mandatory = $true)]$SupportPackage,
        [Parameter(Mandatory = $true)][string]$SkillsRoot,
        [Parameter(Mandatory = $true)]$VersionRegistry,
        [Parameter(Mandatory = $true)]$ExcludedRoots,
        [Parameter(Mandatory = $true)][int]$MaxDeliveryFiles
    )

    $name = [string]$SupportPackage.name
    $sourceDirectory = [string]$SupportPackage.source_directory
    $targetDirectory = [string]$SupportPackage.target_directory
    $copiedFiles = @(Safe-GetArray $SupportPackage "copied_files")
    $declaredDeliveryFiles = @(Safe-GetArray $SupportPackage "delivery_files")
    $bundleDefinitions = @(Safe-GetArray $SupportPackage "bundle_definitions")
    $compiledContract = Get-CompiledOutputContract -Package $SupportPackage -PackageName $name
    $isSingleCompiledFromSourceEntries = Test-IsSingleCompiledFromSourceEntries -Package $SupportPackage -PackageName $name -PackageKind 'SUPPORT_PACKAGE'

    if ([string]::IsNullOrWhiteSpace($sourceDirectory)) {
        throw "Support package '$name' missing source_directory"
    }
    if ([string]::IsNullOrWhiteSpace($targetDirectory)) {
        throw "Support package '$name' missing target_directory"
    }
    $sourceDir = Join-Path $SkillsRoot $sourceDirectory
    $targetDir = Join-Path $SkillsRoot $targetDirectory
    if (!(Test-Path -LiteralPath $sourceDir -PathType Container)) {
        throw "Support package source directory missing: $sourceDir"
    }
    if (!(Test-Path -LiteralPath $targetDir -PathType Container)) {
        throw "Support package target directory missing: $targetDir"
    }

    if ($isSingleCompiledFromSourceEntries) {
        $resolvedSourceEntries = @(Resolve-DirectSourceEntries -Package $SupportPackage)
        foreach ($entry in @($resolvedSourceEntries)) {
            $sourcePath = Join-Path $SkillsRoot (([string]$entry.source_path) -replace '/', '\\')
            if (!(Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
                throw "Support package direct source entry missing: $sourcePath"
            }
        }
    }

    else {
        if ($copiedFiles.Count -eq 0) {
            throw "Support package '$name' missing copied_files"
        }
        if ($bundleDefinitions.Count -eq 0) {
            throw "Support package '$name' missing bundle_definitions"
        }

        foreach ($fileName in @($copiedFiles)) {
            $sourcePath = Join-Path $sourceDir ([string]$fileName)
            if (!(Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
                throw "Support package copied file missing: $sourcePath"
            }
        }

        $expectedDeliveryFiles = @(
            @($copiedFiles | ForEach-Object { [string]$_ }) +
            @($bundleDefinitions | ForEach-Object { [string]$_.output_file }) +
            @($(if ($compiledContract.Enabled) { [string]$compiledContract.OutputFile } else { @() })) +
            @("SUPPORT_PACKAGE.MANIFEST.json")
        ) | Sort-Object -Unique

        if (@($expectedDeliveryFiles).Count -gt $MaxDeliveryFiles) {
            throw "Support package '$name' exceeds max delivery files ($(@($expectedDeliveryFiles).Count) > $MaxDeliveryFiles)"
        }

        $declaredSorted = @($declaredDeliveryFiles | ForEach-Object { [string]$_ } | Sort-Object -Unique)
        if (($expectedDeliveryFiles -join '|') -ne ($declaredSorted -join '|')) {
            throw "Support package '$name' delivery_files contract mismatch"
        }

        foreach ($bundleDef in @($bundleDefinitions)) {
            $sourceFiles = @(Normalize-ToArray $bundleDef.source_files)
            if ($sourceFiles.Count -eq 0) {
                throw "Support package '$name' bundle '$($bundleDef.name)' missing source_files"
            }

            foreach ($sourceFile in @($sourceFiles)) {
                [void](Find-CanonicalFile -Root $SkillsRoot -FileName ([string]$sourceFile) -ExcludedRoots $ExcludedRoots)
                [void](Get-TrackedSourceInfo -VersionRegistry $VersionRegistry -FileName ([string]$sourceFile))
            }
        }
    }
}

function Build-SupportPackageManifest {
    param(
        [Parameter(Mandatory = $true)]$SupportPackage,
        [Parameter(Mandatory = $true)][string]$SkillsRoot,
        [Parameter(Mandatory = $true)][string]$TargetDir,
        [Parameter(Mandatory = $true)]$DeliveryFiles,
        [Parameter(Mandatory = $true)]$BundleManifest,
        [AllowNull()]$CompiledOutputResult
    )

    $compiledEnabled = ($null -ne $CompiledOutputResult)
    $compiledOutputFile = ''
    $compiledOutputSha256 = ''
    $compiledSourceOrder = @()
    $compiledSourceCount = 0
    $compiledFormatVersion = ''
    $primaryUploadFile = 'README.UPLOAD_THIS_PACKAGE.txt'
    if ($compiledEnabled) {
        $compiledOutputFile = [string]$CompiledOutputResult.OutputFileName
        $compiledOutputSha256 = [string]$CompiledOutputResult.OutputSha256
        $compiledSourceOrder = @($CompiledOutputResult.SourceFiles)
        $compiledSourceCount = [int]$CompiledOutputResult.SourceCount
        $compiledFormatVersion = [string]$CompiledOutputResult.FormatVersion
        $primaryUploadFile = $compiledOutputFile
    }

    return [ordered]@{
        schema_version = "1.0"
        package_name = [string]$SupportPackage.name
        package_type = [string]$SupportPackage.package_type
        source_root = $SkillsRoot
        source_directory = [string]$SupportPackage.source_directory
        target_directory = [string]$SupportPackage.target_directory
        lifecycle_status = [string]$SupportPackage.lifecycle_status
        build_enabled = [bool]$SupportPackage.build_enabled
        generated_output_target = [bool]$SupportPackage.generated_output_target
        primary_usecase = [bool]$SupportPackage.primary_usecase
        source_of_truth = [string]$SupportPackage.source_of_truth
        generated_output_only = $true
        do_not_edit_manually = $true
        regeneration_contract = "Re-run 90.USECASE/BUILD.ps1 from C:\01. GitHub\Skills"
        delivery_files = @($DeliveryFiles)
        delivery_file_count = @($DeliveryFiles).Count
        upload_package_model = [string]$SupportPackage.upload_package_model
        upload_package_root = $TargetDir
        upload_instruction_file = "README.UPLOAD_THIS_PACKAGE.txt"
        upload_package_scope = "PRIMARY_SINGLE_FILE_WITH_COEXISTING_LEGACY_OUTPUTS"
        folder_upload_required = $false
        primary_upload_file = $primaryUploadFile
        compiled_output_enabled = $compiledEnabled
        compiled_output_file = $compiledOutputFile
        compiled_output_sha256 = $compiledOutputSha256
        compiled_source_order = @($compiledSourceOrder)
        compiled_source_count = $compiledSourceCount
        compiled_format_version = $compiledFormatVersion
        compiled_content_policy = "FULL_CONTENT_NO_TRUNCATION"
        bundles = @($BundleManifest)
        validation = [ordered]@{
            status = "OK"
            missing_files = @()
            max_delivery_files_allowed = [int]$registry.build_policy.max_delivery_files_per_usecase
        }
    }
}

function Start-UseCaseTransactionBackup {
    param(
        [Parameter(Mandatory = $true)][string]$UseCaseName,
        [Parameter(Mandatory = $true)][string]$TargetDir,
        [Parameter(Mandatory = $true)]$PreserveFiles,
        [Parameter(Mandatory = $true)][string]$TransactionRoot
    )

    $backupRoot = Join-Path $TransactionRoot $UseCaseName
    New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null

    $preserve = @(@(Normalize-ToArray $PreserveFiles) + @("USECASE.MANIFEST.json", "SKILL_SET.MANIFEST.txt", "README.UPLOAD_THIS_USECASE.txt"))
    $toBackup = @(
        Get-ChildItem -LiteralPath $TargetDir -File -ErrorAction SilentlyContinue | Where-Object {
            $_.Name -notin $preserve
        }
    )

    foreach ($f in @($toBackup)) {
        Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $backupRoot $f.Name) -Force
    }

    return [pscustomobject]@{
        BackupRoot = $backupRoot
        BackedUpFiles = @($toBackup | ForEach-Object { $_.Name })
    }
}

function Restore-UseCaseTransactionBackup {
    param(
        [Parameter(Mandatory = $true)][string]$TargetDir,
        [Parameter(Mandatory = $true)][string]$BackupRoot
    )

    if (!(Test-Path -LiteralPath $BackupRoot -PathType Container)) {
        return
    }

    $backupFiles = @(Get-ChildItem -LiteralPath $BackupRoot -File -ErrorAction SilentlyContinue)
    foreach ($f in @($backupFiles)) {
        Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $TargetDir $f.Name) -Force
    }
}

function Invoke-BuildPreflight {
    param(
        [Parameter(Mandatory = $true)]$Registry,
        [Parameter(Mandatory = $true)]$VersionRegistry,
        [Parameter(Mandatory = $true)][string]$UseCaseRoot,
        [Parameter(Mandatory = $true)][string]$SkillsRoot,
        [Parameter(Mandatory = $true)]$ExcludedRoots
    )

    foreach ($uc in @(Normalize-ToArray $Registry.usecases)) {
        $useCaseName = [string]$uc.name
        $targetDir = Join-Path $UseCaseRoot $useCaseName
        $sourceDir = Get-UseCaseSourceDirectoryPath -UseCase $uc -SkillsRoot $SkillsRoot
        $copiedFiles = @(Get-UseCaseCopiedFiles -UseCase $uc)
        $compiledContract = Get-CompiledOutputContract -Package $uc -PackageName $useCaseName
        $isSingleCompiledFromSourceEntries = Test-IsSingleCompiledFromSourceEntries -Package $uc -PackageName $useCaseName -PackageKind 'USECASE'
        if (!(Test-Path -LiteralPath $targetDir -PathType Container)) {
            throw "PREFLIGHT: carpeta de use case no existe: $targetDir"
        }

        $promptFiles = @(Safe-GetArray $uc "prompt_files")
        $menuFiles = @(Safe-GetArray $uc "menu_files")
        $bundleDefinitions = @(Safe-GetArray $uc "bundle_definitions")

        if ($null -ne $sourceDir) {
            if (!(Test-Path -LiteralPath $sourceDir -PathType Container)) {
                throw "PREFLIGHT: source_directory faltante en '$useCaseName': $sourceDir"
            }

            if ($isSingleCompiledFromSourceEntries) {
                if ([string]::IsNullOrWhiteSpace([string]$compiledContract.OutputFile)) {
                    throw "PREFLIGHT: compiled_output_file faltante en '$useCaseName'"
                }

                $resolvedSourceEntries = @(Resolve-DirectSourceEntries -Package $uc)
                foreach ($entry in @($resolvedSourceEntries)) {
                    $directSourcePath = Join-Path $SkillsRoot (([string]$entry.source_path) -replace '/', '\')
                    if (!(Test-Path -LiteralPath $directSourcePath -PathType Leaf)) {
                        throw "PREFLIGHT: source_entry faltante en '$useCaseName': $directSourcePath"
                    }
                }
            }
            else {
                if ($copiedFiles.Count -eq 0) {
                    throw "PREFLIGHT: copied_files faltante en '$useCaseName'"
                }

                foreach ($copiedFile in @($copiedFiles)) {
                    $copiedSourcePath = Join-Path $sourceDir $copiedFile
                    if (!(Test-Path -LiteralPath $copiedSourcePath -PathType Leaf)) {
                        throw "PREFLIGHT: copied_file faltante en '$useCaseName': $copiedSourcePath"
                    }
                }
            }
        }

        foreach ($p in @($promptFiles)) {
            if ([string]::IsNullOrWhiteSpace([string]$p)) { continue }
            $promptName = [string]$p
            if (($null -ne $sourceDir) -and ($promptName -in $copiedFiles)) {
                if (!(Test-Path -LiteralPath (Join-Path $sourceDir $promptName) -PathType Leaf)) {
                    throw "PREFLIGHT: prompt source faltante en '$useCaseName': $promptName"
                }
            }
            elseif (!(Test-Path -LiteralPath (Join-Path $targetDir $promptName) -PathType Leaf)) {
                throw "PREFLIGHT: prompt faltante en '$useCaseName': $promptName"
            }
        }

        foreach ($menuFile in @($menuFiles)) {
            if ([string]::IsNullOrWhiteSpace([string]$menuFile)) { continue }
            [void](Find-CanonicalFile -Root $SkillsRoot -FileName ([string]$menuFile) -ExcludedRoots $ExcludedRoots)
        }

        foreach ($bundleDef in @($bundleDefinitions)) {
            $sources = @(Normalize-ToArray $bundleDef.source_files)
            foreach ($sourceFile in @($sources)) {
                [void](Find-CanonicalFile -Root $SkillsRoot -FileName ([string]$sourceFile) -ExcludedRoots $ExcludedRoots)
                [void](Get-TrackedSourceInfo -VersionRegistry $VersionRegistry -FileName ([string]$sourceFile))
            }
        }
    }

    foreach ($sp in @(Normalize-ToArray $Registry.support_packages)) {
        $buildEnabled = $false
        if (Has-Property $sp "build_enabled") {
            $buildEnabled = [bool]$sp.build_enabled
        }

        if ($buildEnabled -ne $true) {
            continue
        }

        $supportPackageName = [string]$sp.name
        $isSingleCompiledFromSourceEntries = Test-IsSingleCompiledFromSourceEntries -Package $sp -PackageName $supportPackageName -PackageKind 'SUPPORT_PACKAGE'
        $maxDeliveryFiles = 0
        if ($Registry.build_policy.PSObject.Properties['max_delivery_files_per_usecase']) {
            $maxDeliveryFiles = [int]$Registry.build_policy.max_delivery_files_per_usecase
        }
        elseif ($isSingleCompiledFromSourceEntries -ne $true) {
            throw "PREFLIGHT: build_policy.max_delivery_files_per_usecase faltante para soporte legacy '$supportPackageName'"
        }

        Invoke-SupportPackagePreflight `
            -SupportPackage $sp `
            -SkillsRoot $SkillsRoot `
            -VersionRegistry $VersionRegistry `
            -ExcludedRoots $ExcludedRoots `
            -MaxDeliveryFiles $maxDeliveryFiles
    }
}

# ==========================================================
# 02.00 LOAD CONFIG
# ==========================================================

$registry = Read-JsonFileSafe -Path $RegistryPath
$versionRegistry = Read-JsonFileSafe -Path $VersionRegistryPath

if (!(Test-Path -LiteralPath $UseCaseCompilerPath -PathType Leaf)) {
    throw "Compiled usecase compiler missing: $UseCaseCompilerPath"
}
. $UseCaseCompilerPath
if (-not (Get-Command New-UseCaseCompiledFile -ErrorAction SilentlyContinue)) {
    throw "Compiled usecase compiler did not expose New-UseCaseCompiledFile"
}

if (-not $registry.usecases) {
    throw "USECASE.REGISTRY.json no contiene 'usecases'"
}

if (-not $registry.build_policy) {
    throw "USECASE.REGISTRY.json no contiene 'build_policy'"
}

$ExcludedRoots = @(Normalize-ToArray $registry.excluded_roots)
$BuildTxnRoot = Join-Path $env:TEMP ("SkillMachine_BUILD_TRANSACTION_{0}" -f (Get-Date).ToString("yyyyMMdd_HHmmss"))

Write-Host "BUILD PREFLIGHT"
try {
    Invoke-BuildPreflight -Registry $registry -VersionRegistry $versionRegistry -UseCaseRoot $UseCaseRoot -SkillsRoot $SkillsRoot -ExcludedRoots $ExcludedRoots
    Write-Host "OK: preflight passed"
}
catch {
    Write-Host "FAIL: preflight"
    Write-Host $_.Exception.Message
    exit 1
}

# ==========================================================
# 03.00 BUILD LOOP
# ==========================================================

$results = @()

foreach ($uc in @(Normalize-ToArray $registry.usecases)) {
    # UC04_CAPTURE_EXTRAS_EARLY (Option B)
    # Capture rich-usecase arrays early; later code may project/override $uc.
    $UC_PreserveFiles = @(Safe-GetArray $uc "preserve_files")
    $UC_DeliveryFilesExtra = @(Safe-GetArray $uc "delivery_files_extra")
    $SourceDir = Get-UseCaseSourceDirectoryPath -UseCase $uc -SkillsRoot $SkillsRoot
    $CopiedFiles = @(Get-UseCaseCopiedFiles -UseCase $uc)

    $UseCaseName = [string]$uc.name
    $UseCaseVersion = [string]$uc.version
    $TargetDir = Join-Path $UseCaseRoot $UseCaseName
    # Safe-get for optional usecase properties to avoid StrictMode property-not-found failures.
    $PromptFiles = @(Normalize-ToArray $(if ($uc.PSObject.Properties['prompt_files']) { $uc.prompt_files } else { @() }))
    $MenuFiles = @(Normalize-ToArray $(if ($uc.PSObject.Properties['menu_files']) { $uc.menu_files } else { @() }))
    $BundleDefinitions = @(Normalize-ToArray $(if ($uc.PSObject.Properties['bundle_definitions']) { $uc.bundle_definitions } else { @() }))
    $CompiledContract = Get-CompiledOutputContract -Package $uc -PackageName $UseCaseName

    if ($PromptFiles.Count -eq 1 -and [string]::IsNullOrWhiteSpace([string]$PromptFiles[0])) { $PromptFiles = @() }
    if ($MenuFiles.Count -eq 1 -and [string]::IsNullOrWhiteSpace([string]$MenuFiles[0])) { $MenuFiles = @() }

    Write-Host ""
    Write-Host "=============================="
    Write-Host "BUILD USECASE: $UseCaseName"
    Write-Host "=============================="

    $txnBackupRoot = $null
    $txnBackedUpFiles = @()

    try {
        if (!(Test-Path -LiteralPath $TargetDir -PathType Container)) {
            throw "Carpeta de use case no existe: $TargetDir"
        }

        if ([string]$registry.build_policy.output_model -ne 'SINGLE_COMPILED_FILE') {
            throw "build_policy.output_model debe ser SINGLE_COMPILED_FILE"
        }

        if (-not $uc.PSObject.Properties['source_entries'] -or @($uc.source_entries).Count -eq 0) {
            throw "Use case '$UseCaseName' no define source_entries"
        }

        $preserveFiles = @()
        if ($CompiledContract.Enabled) { $preserveFiles += [string]$CompiledContract.OutputFile }

        if ($registry.build_policy.clean_generated_files_first -eq $true) {
            $preserveFiles = @($preserveFiles)
            $preserveFiles = @($preserveFiles | ForEach-Object { [string]$_ } | Sort-Object -Unique)
            $txn = Start-UseCaseTransactionBackup -UseCaseName $UseCaseName -TargetDir $TargetDir -PreserveFiles $preserveFiles -TransactionRoot $BuildTxnRoot
            $txnBackupRoot = [string]$txn.BackupRoot
            $txnBackedUpFiles = @(Normalize-ToArray $txn.BackedUpFiles)
            $removed = @(Clear-GeneratedFiles -FolderPath $TargetDir -PreserveFiles $preserveFiles)
            Write-Host "LIMPIEZA: archivos eliminados = $(@($removed).Count)"
            foreach ($f in @($removed)) {
                Write-Host ("  - removed: {0}" -f $f.Name)
            }
        }

        $deliveryFiles = @()
        $bundleManifest = @()

        $compiledOutputResult = Invoke-CompiledOutputBuild `
            -Package $uc `
            -PackageName $UseCaseName `
            -PackageType "USECASE" `
            -PackageVersion $UseCaseVersion `
            -ProjectRoot $SkillsRoot `
            -TargetDirectory $TargetDir `
            -DirectSourceEntries (Resolve-DirectSourceEntries -Package $uc)
        if ($null -ne $compiledOutputResult) {
            $deliveryFiles += [string]$compiledOutputResult.OutputFileName
        }
        $deliveryFiles = @($deliveryFiles | ForEach-Object { [string]$_ } | Sort-Object -Unique)

        $validationMissing = @(Validate-UseCaseOutput -TargetDir $TargetDir -PromptFiles @() -DeliveryFiles $deliveryFiles)
        if (@($validationMissing).Count -gt 0) {
            throw "Validación de salida falló en '$UseCaseName'. Faltantes: $($validationMissing -join ', ')"
        }

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
        if ($txnBackupRoot -and (Test-Path -LiteralPath $txnBackupRoot -PathType Container)) {
            Restore-UseCaseTransactionBackup -TargetDir $TargetDir -BackupRoot $txnBackupRoot
            Write-Host ("RESTORED TRANSACTION BACKUP for {0} ({1} files)" -f $UseCaseName, @($txnBackedUpFiles).Count)
        }

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

foreach ($sp in @(Normalize-ToArray $registry.support_packages)) {
    $buildEnabled = $false
    if (Has-Property $sp "build_enabled") {
        $buildEnabled = [bool]$sp.build_enabled
    }

    if ($buildEnabled -ne $true) {
        continue
    }

    $SupportPackageName = [string]$sp.name
    $SourceDir = Join-Path $SkillsRoot ([string]$sp.source_directory)
    $TargetDir = Join-Path $SkillsRoot ([string]$sp.target_directory)
    $DeclaredDeliveryFiles = @()
    $BundleDefinitions = @()
    $CompiledContract = Get-CompiledOutputContract -Package $sp -PackageName $SupportPackageName

    Write-Host ""
    Write-Host "=============================="
    Write-Host "BUILD SUPPORT PACKAGE: $SupportPackageName"
    Write-Host "=============================="

    try {
        $preserveFiles = @(
            @($(if ($CompiledContract.Enabled) { [string]$CompiledContract.OutputFile } else { @() }))
        ) | Sort-Object -Unique
        $bundleManifest = @()

        if ($registry.build_policy.clean_generated_files_first -eq $true) {
            $removed = @(Clear-GeneratedFiles -FolderPath $TargetDir -PreserveFiles $preserveFiles)
            Write-Host "LIMPIEZA: archivos eliminados = $(@($removed).Count)"
            foreach ($f in @($removed)) {
                Write-Host ("  - removed: {0}" -f $f.Name)
            }
        }

        $compiledOutputResult = Invoke-CompiledOutputBuild `
            -Package $sp `
            -PackageName $SupportPackageName `
            -PackageType "SUPPORT_PACKAGE" `
            -PackageVersion ([string]$sp.lifecycle_status) `
            -ProjectRoot $SkillsRoot `
            -TargetDirectory $TargetDir `
            -DirectSourceEntries (Resolve-DirectSourceEntries -Package $sp)

        $deliveryFiles = @([string]$compiledOutputResult.OutputFileName)
        $validationMissing = @(Validate-SupportPackageOutput -TargetDir $TargetDir -DeliveryFiles $deliveryFiles)
        if (@($validationMissing).Count -gt 0) {
            throw "Validación de salida falló en '$SupportPackageName'. Faltantes: $($validationMissing -join ', ')"
        }

        $results += [pscustomobject]@{
            usecase = $SupportPackageName
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
            usecase = $SupportPackageName
            status = "FAIL"
            copied = 0
            error = $errMsg
        }
        $results = @($results)
        Write-Host "FAIL en $SupportPackageName"
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

# MB-GRC-026F2_GENERATED_OUTPUT_POLICY
# Post-process generated delivery artifacts so humans/IA do not edit generated outputs manually.
$GeneratedOutputPolicyScript = Join-Path $PSScriptRoot "Apply-GeneratedOutputPolicy.ps1"
if (Test-Path $GeneratedOutputPolicyScript) {
    Write-Host "=============================="
    Write-Host "APPLY GENERATED OUTPUT POLICY"
    Write-Host "=============================="
    & $GeneratedOutputPolicyScript
}
# END_MB-GRC-026F2_GENERATED_OUTPUT_POLICY
exit 0
