# Validate-Structure.ps1
# Validates SkillMachine structural consistency without regenerating outputs.

$ErrorActionPreference = "Stop"

function Fail($Message) {
    Write-Host "FAIL: $Message"
    exit 1
}

function Test-JsonFile($Path) {
    if (-not (Test-Path -LiteralPath $Path)) {
        Fail "JSON file not found: $Path"
    }

    try {
        Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json | Out-Null
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

Write-Host "VALIDATION: structure"

$registryPath = "90.USECASE\USECASE.REGISTRY.json"
$globalRegistryPath = "90.USECASE\GLOBAL.SKILL.VERSION.REGISTRY.json"

Test-JsonFile $registryPath
Test-JsonFile $globalRegistryPath

$registry = Get-Content -Raw -LiteralPath $registryPath | ConvertFrom-Json

if (-not $registry.usecases) {
    Fail "Registry does not declare primary usecases: $registryPath"
}

$usecaseDirs = @()
foreach ($uc in @($registry.usecases)) {
    $name = [string]$uc.name
    if ([string]::IsNullOrWhiteSpace($name)) {
        Fail "Registry contains primary usecase without name: $registryPath"
    }

    $dirPath = Join-Path "90.USECASE" $name
    if (-not (Test-Path -LiteralPath $dirPath -PathType Container)) {
        Fail "Declared primary usecase directory missing: $dirPath"
    }

    $usecaseDirs += Get-Item -LiteralPath $dirPath
}

$supportPackageNames = @()
if ($registry.PSObject.Properties["support_packages"] -and $registry.support_packages) {
    $supportPackageNames = @(
        $registry.support_packages |
        ForEach-Object { [string]$_.name } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
}

$registeredNames = @(
    @($registry.usecases | ForEach-Object { [string]$_.name }) +
    @($supportPackageNames)
)

$unregisteredNumberedDirs = @(
    Get-ChildItem -LiteralPath "90.USECASE" -Directory |
    Where-Object {
        $_.Name -match '^\d{2}\.' -and
        $registeredNames -notcontains $_.Name
    }
)

foreach ($dir in $unregisteredNumberedDirs) {
    Write-Host "WARN: unregistered numbered 90.USECASE directory: $($dir.FullName)"
}

foreach ($dir in $usecaseDirs) {
    $manifestPath = Join-Path $dir.FullName "USECASE.MANIFEST.json"
    Test-JsonFile $manifestPath

    $manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json

    if (-not $manifest.usecase) {
        Fail "Missing usecase field in manifest: $manifestPath"
    }

    if (-not $manifest.delivery_files) {
        Fail "Missing delivery_files in manifest: $manifestPath"
    }

    foreach ($file in $manifest.delivery_files) {
        $deliveryPath = Join-Path $dir.FullName $file
        if (-not (Test-Path -LiteralPath $deliveryPath)) {
            Fail "Declared delivery file missing: $deliveryPath"
        }
    }

    if (-not $manifest.bundles) {
        Fail "Missing bundles array in manifest: $manifestPath"
    }

    foreach ($bundle in $manifest.bundles) {
        if (-not $bundle.bundle_name) {
            Fail "Bundle missing bundle_name in: $manifestPath"
        }

        if (-not $bundle.delivery_file) {
            Fail "Bundle missing delivery_file in: $manifestPath"
        }

        $bundlePath = Join-Path $dir.FullName $bundle.delivery_file
        if (-not (Test-Path -LiteralPath $bundlePath)) {
            Fail "Bundle delivery file missing: $bundlePath"
        }

        if (-not $bundle.source_files) {
            Fail "Bundle missing source_files: $($bundle.bundle_name)"
        }

        foreach ($source in $bundle.source_files) {
            if (-not $source.name) {
                Fail "Source file missing name in bundle: $($bundle.bundle_name)"
            }

            $sourcePath = Join-Path (Resolve-Path ".") $source.name
            if (-not (Test-Path -LiteralPath $sourcePath)) {
                Fail "Source file referenced by manifest does not exist: $($source.name)"
            }
        }
    }
}

$useCaseSourceContracts = @(
    [pscustomobject]@{
        Name = "03.SESSION_CONTINUE"
        SourceDirectory = "SyS/A_Tools/UseCaseSources/03.SessionContinue"
        ExpectedFiles = @(
            "PROMPT.SESSION_CONTINUE.txt",
            "README.UPLOAD_THIS_USECASE.txt",
            "SKILL_SET.MANIFEST.txt"
        )
    },
    [pscustomobject]@{
        Name = "04.REPOSITORY_STRUCTURE_REPAIR"
        SourceDirectory = "SyS/A_Tools/UseCaseSources/04.RepositoryStructureRepair"
        ExpectedFiles = @(
            "HUMAN.REPOSITORY_STRUCTURE_REPAIR.txt",
            "README.EXECUTION.txt",
            "README.UPLOAD_THIS_USECASE.txt",
            "SKILL.md",
            "SKILL_SET.MANIFEST.txt",
            "WHOAMI.REPOSITORY_STRUCTURE_REPAIR.txt"
        )
    }
)

foreach ($contract in $useCaseSourceContracts) {
    $sourceDir = $contract.SourceDirectory
    if (-not (Test-Path -LiteralPath $sourceDir -PathType Container)) {
        Fail "Usecase source directory missing: $sourceDir"
    }

    $actualFiles = @(
        Get-ChildItem -LiteralPath $sourceDir -File -Force |
            Select-Object -ExpandProperty Name |
            Sort-Object
    )
    $expectedFiles = @($contract.ExpectedFiles | Sort-Object)
    $missingFiles = @($expectedFiles | Where-Object { $_ -notin $actualFiles })
    $unexpectedFiles = @($actualFiles | Where-Object { $_ -notin $expectedFiles })

    if ($missingFiles.Count -gt 0) {
        Fail "Usecase source files missing in ${sourceDir}: $($missingFiles -join ', ')"
    }
    if ($unexpectedFiles.Count -gt 0) {
        Fail "Unexpected usecase source files in ${sourceDir}: $($unexpectedFiles -join ', ')"
    }
}

$legacy = git grep "STANDARD\." -- `
    ":(exclude)SyS/A_Tools/Validation" `
    ":(exclude).git" `
    2>$null

if ($LASTEXITCODE -eq 0 -and $legacy) {
    $filtered = $legacy | Where-Object { $_ -notmatch "Validate-" }

    if ($filtered) {
        Fail "Legacy naming references detected"
    }
}
# MB-SM-062D-D: updater core structure validation
$skillsMachineRootForUpdater = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\..\.."))
$updaterCoreRoot = Join-Path $skillsMachineRootForUpdater "SyS\A_Tools\Update"
$expectedUpdaterCoreFiles = @(
    "Invoke-SkillsMachineUpdate.ps1",
    "README.SKILLSMACHINE.UPDATE.txt",
    "SKILLSMACHINE.PROJECT.BASELINE.schema.json",
    "SKILLSMACHINE.UPDATE.MANIFEST.schema.json",
    "Test-SkillsMachineUpdate.ps1"
)

if (-not (Test-Path -LiteralPath $updaterCoreRoot -PathType Container)) {
    throw "Updater core folder missing: $updaterCoreRoot"
}

$actualUpdaterCoreFiles = @(
    Get-ChildItem -LiteralPath $updaterCoreRoot -File -Force |
        Select-Object -ExpandProperty Name |
        Sort-Object
)
$expectedUpdaterCoreFilesSorted = @($expectedUpdaterCoreFiles | Sort-Object)

$missingUpdaterCoreFiles = @(
    $expectedUpdaterCoreFilesSorted |
        Where-Object { $_ -notin $actualUpdaterCoreFiles }
)
$unexpectedUpdaterCoreFiles = @(
    $actualUpdaterCoreFiles |
        Where-Object { $_ -notin $expectedUpdaterCoreFilesSorted }
)

if ($missingUpdaterCoreFiles.Count -gt 0) {
    throw "Updater core files missing: $($missingUpdaterCoreFiles -join ', ')"
}
if ($unexpectedUpdaterCoreFiles.Count -gt 0) {
    throw "Unexpected updater core files: $($unexpectedUpdaterCoreFiles -join ', ')"
}
if ($actualUpdaterCoreFiles.Count -ne 5) {
    throw "Updater core file count must be exactly 5; actual=$($actualUpdaterCoreFiles.Count)"
}

Write-Host "OK: updater core structure validated (5 files)"

$supportPackageName = "05.SKILLSMACHINE_UPDATE"
$supportDir = Join-Path "90.USECASE" $supportPackageName
$supportManifestPath = Join-Path $supportDir "SUPPORT_PACKAGE.MANIFEST.json"
$expectedSupportFiles = @(
    "00.BUNDLE.UPDATE_CONTEXT.txt",
    "01.BUNDLE.UPDATE_METHOD.txt",
    "02.BUNDLE.UPDATE_GOVERNANCE.txt",
    "PROMPT.SKILLSMACHINE_UPDATE.txt",
    "README.UPLOAD_THIS_PACKAGE.txt",
    "RUNBOOK.SKILLSMACHINE_UPDATE.txt",
    "SUPPORT_PACKAGE.MANIFEST.json",
    "UPDATE.EXAMPLE.MANIFEST.json"
) | Sort-Object

if (-not (Test-Path -LiteralPath $supportDir -PathType Container)) {
    throw "Support package folder missing: $supportDir"
}

Test-JsonFile $supportManifestPath
$supportManifest = Get-Content -Raw -LiteralPath $supportManifestPath | ConvertFrom-Json
$actualSupportFiles = @(
    Get-ChildItem -LiteralPath $supportDir -File -Force |
        Select-Object -ExpandProperty Name |
        Sort-Object
)

$missingSupportFiles = @($expectedSupportFiles | Where-Object { $_ -notin $actualSupportFiles })
$unexpectedSupportFiles = @($actualSupportFiles | Where-Object { $_ -notin $expectedSupportFiles })

if ($missingSupportFiles.Count -gt 0) {
    throw "Support package files missing: $($missingSupportFiles -join ', ')"
}
if ($unexpectedSupportFiles.Count -gt 0) {
    throw "Unexpected support package files: $($unexpectedSupportFiles -join ', ')"
}
if ($actualSupportFiles.Count -ne 8) {
    throw "Support package file count must be exactly 8; actual=$($actualSupportFiles.Count)"
}

$supportSourceRoot = Join-Path $skillsMachineRootForUpdater "SyS\A_Tools\Update\SupportPackage"
$expectedSupportSourceFiles = @(
    "PROMPT.SKILLSMACHINE_UPDATE.txt",
    "README.UPLOAD_THIS_PACKAGE.txt",
    "RUNBOOK.SKILLSMACHINE_UPDATE.txt",
    "UPDATE.EXAMPLE.MANIFEST.json"
) | Sort-Object
$actualSupportSourceFiles = @(
    Get-ChildItem -LiteralPath $supportSourceRoot -File -Force |
        Select-Object -ExpandProperty Name |
        Sort-Object
)
if (($expectedSupportSourceFiles -join "|") -ne ($actualSupportSourceFiles -join "|")) {
    throw "Support package source folder mismatch"
}

if (-not $supportManifest.delivery_files) {
    throw "Support package manifest missing delivery_files: $supportManifestPath"
}
$supportDeliveryFiles = @($supportManifest.delivery_files | ForEach-Object { [string]$_ } | Sort-Object)
if (($supportDeliveryFiles -join "|") -ne ($expectedSupportFiles -join "|")) {
    throw "Support package manifest delivery_files mismatch"
}

Write-Host "OK: support package structure validated (8 files)"


Write-Host "OK: structure validation passed"
exit 0
