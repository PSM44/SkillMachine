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

function Test-ExactLineToken {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Pattern
    )

    $lines = @(Get-Content -LiteralPath $Path -Encoding UTF8)
    foreach ($line in $lines) {
        if ($line -match $Pattern) {
            return $true
        }
    }

    return $false
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
    $files = @(Get-ChildItem -LiteralPath $dir.FullName -File -Force)
    $subdirs = @(Get-ChildItem -LiteralPath $dir.FullName -Directory -Force)
    if ($subdirs.Count -ne 0) {
        Fail "Usecase directory must be flat with no subdirectories: $($dir.FullName)"
    }
    if ($files.Count -ne 1) {
        Fail "Usecase directory must contain exactly one compiled file: $($dir.FullName)"
    }
    if ($files[0].Name -notmatch '^USECASE\..*\.COMPILED\.txt$') {
        Fail "Usecase directory single file must be compiled output: $($files[0].FullName)"
    }
    $compiled = Get-Content -Raw -LiteralPath $files[0].FullName -Encoding UTF8
    if (-not (Test-ExactLineToken -Path $files[0].FullName -Pattern '^SOURCE_FILE_COUNT=\d+$')) {
        Fail "Compiled package missing SOURCE_FILE_COUNT: $($files[0].FullName)"
    }
    if ($compiled -notmatch 'SOURCE_PROVENANCE_EMBEDDED=YES') {
        Fail "Compiled package missing SOURCE_PROVENANCE_EMBEDDED=YES: $($files[0].FullName)"
    }
    if ($compiled -notmatch 'SEPARATE_TARGET_MANIFEST_REQUIRED=NO') {
        Fail "Compiled package missing SEPARATE_TARGET_MANIFEST_REQUIRED=NO: $($files[0].FullName)"
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
            "SKILL_SET.MANIFEST.txt"
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
    "Eligibility.ps1",
    "Invoke-SkillsMachineUpdate.ps1",
    "README.SKILLSMACHINE.UPDATE.txt",
    "SKILLSMACHINE.PROJECT.BASELINE.1.2.schema.json",
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
if ($actualUpdaterCoreFiles.Count -ne 7) {
    throw "Updater core file count must be exactly 7; actual=$($actualUpdaterCoreFiles.Count)"
}

Write-Host "OK: updater core structure validated (7 files)"

$supportPackageName = "05.SKILLSMACHINE_UPDATE"
$supportDir = Join-Path "90.USECASE" $supportPackageName
$expectedSupportFiles = @(
    "USECASE.05.SKILLSMACHINE_UPDATE.COMPILED.txt"
) | Sort-Object

if (-not (Test-Path -LiteralPath $supportDir -PathType Container)) {
    throw "Support package folder missing: $supportDir"
}

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
if ($actualSupportFiles.Count -ne 1) {
    throw "Support package file count must be exactly 1; actual=$($actualSupportFiles.Count)"
}

$compiledSupport = Join-Path $supportDir 'USECASE.05.SKILLSMACHINE_UPDATE.COMPILED.txt'
$compiledSupportText = Get-Content -Raw -LiteralPath $compiledSupport -Encoding UTF8
foreach ($token in @('SOURCE_PROVENANCE_EMBEDDED=YES','SEPARATE_TARGET_MANIFEST_REQUIRED=NO','SKILLSMACHINE_RUNTIME_DEPENDENCY=NO')) {
    if (-not $compiledSupportText.Contains($token)) {
        throw "Support compiled package missing token: $token"
    }
}

Write-Host "OK: support package structure validated (1 file)"


Write-Host "OK: structure validation passed"
exit 0
