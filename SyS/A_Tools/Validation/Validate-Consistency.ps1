# Validate-Consistency.ps1
# Validates cross-file SkillMachine consistency without modifying outputs.

$ErrorActionPreference = "Stop"

function Fail($Message) {
    Write-Host "FAIL: $Message"
    exit 1
}

function Read-Json($Path) {
    if (-not (Test-Path -LiteralPath $Path)) {
        Fail "JSON file not found: $Path"
    }

    try {
        $raw = Get-Content -LiteralPath $Path -Raw -Encoding utf8
        return ($raw | ConvertFrom-Json)
    }
    catch {
        Fail "Invalid JSON: $Path | $($_.Exception.Message)"
    }
}

function Normalize-ToArray($Value) {
    if ($null -eq $Value) { return @() }
    if ($Value -is [System.Array]) { return @($Value) }
    return @($Value)
}

function Get-FullPathSafe([string]$Path) {
    try {
        return [System.IO.Path]::GetFullPath($Path)
    }
    catch {
        return $Path
    }
}

Write-Host "VALIDATION: consistency"

$repoRoot = (Resolve-Path ".").Path
$usecaseRoot = Join-Path $repoRoot "90.USECASE"
$registryPath = Join-Path $usecaseRoot "USECASE.REGISTRY.json"
$globalRegistryPath = Join-Path $usecaseRoot "GLOBAL.SKILL.VERSION.REGISTRY.json"

$registry = Read-Json $registryPath
$globalRegistry = Read-Json $globalRegistryPath

$usecaseDirs = @(Get-ChildItem -LiteralPath $usecaseRoot -Directory | Where-Object { $_.Name -match '^\d{2}\.' })
if (@($usecaseDirs).Count -eq 0) {
    Fail "No usecase directories found under 90.USECASE"
}

if ($null -ne $registry.PSObject.Properties['usecases']) {
    $registryUsecases = @(Normalize-ToArray $registry.usecases)
}
elseif ($registry -is [System.Array]) {
    $registryUsecases = @($registry)
}
else {
    Fail "Unsupported usecase registry structure in $registryPath"
}

if (@($registryUsecases).Count -eq 0) {
    Fail "No usecases declared in $registryPath"
}

$folderUsecaseNames = @($usecaseDirs | ForEach-Object { [string]$_.Name })
$registryUsecaseNames = @($registryUsecases | ForEach-Object { [string]$_.name })

foreach ($folderName in $folderUsecaseNames) {
    if ($folderName -notin $registryUsecaseNames) {
        Fail "Usecase folder not declared in registry: $folderName"
    }
}

foreach ($usecaseName in $registryUsecaseNames) {
    if ($usecaseName -notin $folderUsecaseNames) {
        Fail "Usecase declared in registry has no folder: $usecaseName"
    }
}

if ($null -ne $globalRegistry.PSObject.Properties['skills']) {
    $globalSkills = @(Normalize-ToArray $globalRegistry.skills)
}
elseif ($globalRegistry -is [System.Array]) {
    $globalSkills = @($globalRegistry)
}
else {
    Fail "Unsupported global registry structure in $globalRegistryPath"
}

$globalSkillNames = @($globalSkills | ForEach-Object { [string]$_.file })

$allowList = @(
    "00.SKILL.MENU.ACTIVE.txt",
    "SKILL_SET.MANIFEST.txt"
)

foreach ($dir in $usecaseDirs) {
    $usecaseName = [string]$dir.Name
    $manifestPath = Join-Path $dir.FullName "USECASE.MANIFEST.json"
    $manifest = Read-Json $manifestPath

    if ([string]::IsNullOrWhiteSpace([string]$manifest.usecase)) {
        Fail "Missing manifest.usecase: $manifestPath"
    }

    if ([string]$manifest.usecase -ne $usecaseName) {
        Fail "manifest.usecase mismatch in $manifestPath (expected $usecaseName, got $($manifest.usecase))"
    }

    $deliveryFiles = @(Normalize-ToArray $manifest.delivery_files)
    if (@($deliveryFiles).Count -eq 0) {
        Fail "Missing or empty delivery_files in: $manifestPath"
    }

    $bundles = @(Normalize-ToArray $manifest.bundles)
    if (@($bundles).Count -eq 0) {
        Fail "Missing or empty bundles in: $manifestPath"
    }

    $deliveryDuplicates = @($deliveryFiles | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name })
    if (@($deliveryDuplicates).Count -gt 0) {
        Fail "Duplicate delivery_files in ${manifestPath}: $($deliveryDuplicates -join ', ')"
    }

    $bundleNames = @($bundles | ForEach-Object { [string]$_.bundle_name })
    $bundleNameDuplicates = @($bundleNames | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name })
    if (@($bundleNameDuplicates).Count -gt 0) {
        Fail "Duplicate bundle_name in ${manifestPath}: $($bundleNameDuplicates -join ', ')"
    }

    $bundleDeliveryFiles = @($bundles | ForEach-Object { [string]$_.delivery_file })
    $bundleDeliveryDuplicates = @($bundleDeliveryFiles | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name })
    if (@($bundleDeliveryDuplicates).Count -gt 0) {
        Fail "Duplicate bundle.delivery_file in ${manifestPath}: $($bundleDeliveryDuplicates -join ', ')"
    }

    foreach ($df in $deliveryFiles) {
        $fullDeliveryPath = Join-Path $dir.FullName ([string]$df)
        if (-not (Test-Path -LiteralPath $fullDeliveryPath -PathType Leaf)) {
            Fail "Delivery file declared but missing: $fullDeliveryPath"
        }
    }

    foreach ($bundle in $bundles) {
        $bundleDelivery = [string]$bundle.delivery_file
        if ([string]::IsNullOrWhiteSpace($bundleDelivery)) {
            Fail "bundle.delivery_file missing in $manifestPath"
        }

        if ($bundleDelivery -notin $deliveryFiles) {
            Fail "bundle.delivery_file not declared in delivery_files: $bundleDelivery ($manifestPath)"
        }

        $bundleDeliveryPath = Join-Path $dir.FullName $bundleDelivery
        if (-not (Test-Path -LiteralPath $bundleDeliveryPath -PathType Leaf)) {
            Fail "Bundle delivery file missing: $bundleDeliveryPath"
        }

        $sourceFiles = @(Normalize-ToArray $bundle.source_files)
        if (@($sourceFiles).Count -eq 0) {
            Fail "Bundle source_files missing or empty: $($bundle.bundle_name) in $manifestPath"
        }

        foreach ($source in $sourceFiles) {
            $sourceName = [string]$source.name
            if ([string]::IsNullOrWhiteSpace($sourceName)) {
                Fail "source.name missing in bundle $($bundle.bundle_name) ($manifestPath)"
            }

            $sourceFromNamePath = Join-Path $repoRoot $sourceName
            if (-not (Test-Path -LiteralPath $sourceFromNamePath -PathType Leaf)) {
                Fail "Source name file missing in repo root: $sourceName"
            }

            if ($null -ne $source.PSObject.Properties['source_path'] -and -not [string]::IsNullOrWhiteSpace([string]$source.source_path)) {
                $sourcePath = [string]$source.source_path
                if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
                    Fail "source.source_path does not exist: $sourcePath"
                }

                $nameFull = Get-FullPathSafe $sourceFromNamePath
                $pathFull = Get-FullPathSafe $sourcePath
                if ($nameFull -ne $pathFull) {
                    Fail "source.name and source.source_path point to different files: $sourceName | $sourcePath"
                }
            }

            $ucPromptFiles = @()
            $registryItem = @($registryUsecases | Where-Object { [string]$_.name -eq $usecaseName }) | Select-Object -First 1
            if ($null -ne $registryItem) {
                $ucPromptFiles = @(Normalize-ToArray $registryItem.prompt_files)
            }

            if (($sourceName -notin $globalSkillNames) -and ($sourceName -notin $allowList) -and ($sourceName -notin $ucPromptFiles)) {
                Fail "Source file not registered in global registry: $sourceName"
            }
        }
    }
}

$legacy = git grep "STANDARD\." -- `
    ":(exclude)SyS/A_Tools/Validation" `
    ":(exclude).git" `
    2>$null

if ($LASTEXITCODE -eq 0 -and $legacy) {
    $filtered = $legacy | Where-Object { $_ -notmatch "Validate-" }
    if ($filtered) {
        Fail "Legacy naming token references detected"
    }
}

Write-Host "OK: consistency validation passed"
exit 0
