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

$primaryUsecaseDirs = @()
foreach ($registryUsecase in @($registryUsecases)) {
    $usecaseName = [string]$registryUsecase.name
    if ([string]::IsNullOrWhiteSpace($usecaseName)) {
        Fail "Registry contains primary usecase without name"
    }

    $matchedDir = @($usecaseDirs | Where-Object { $_.Name -eq $usecaseName } | Select-Object -First 1)
    if (@($matchedDir).Count -eq 0 -or $null -eq $matchedDir[0]) {
        Fail "Primary usecase directory missing for registry entry: $usecaseName"
    }

    $primaryUsecaseDirs += $matchedDir[0]
}

$registrySupportPackages = @()
if ($null -ne $registry.PSObject.Properties['support_packages']) {
    $registrySupportPackages = @(Normalize-ToArray $registry.support_packages)
}
$registrySupportPackageNames = @(
    $registrySupportPackages |
    ForEach-Object { [string]$_.name } |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
)

$allRegisteredFolderNames = @(
    @($registryUsecaseNames) +
    @($registrySupportPackageNames)
)

$duplicateRegisteredNames = @(
    $allRegisteredFolderNames |
    Group-Object |
    Where-Object { $_.Count -gt 1 } |
    ForEach-Object { $_.Name }
)
if (@($duplicateRegisteredNames).Count -gt 0) {
    Fail "Duplicate names across usecases/support_packages: $($duplicateRegisteredNames -join ', ')"
}

foreach ($folderName in $folderUsecaseNames) {
    if ($folderName -notin $allRegisteredFolderNames) {
        Fail "Numbered folder not declared in registry usecases/support_packages: $folderName"
    }
}

function Assert-CompiledToken([string]$Path, [string]$Token, [string]$Label) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Fail "$Label missing compiled file: $Path"
    }
    $content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    if (-not $content.Contains($Token)) {
        Fail "$Label compiled token missing: $Token"
    }
}

foreach ($usecaseName in $registryUsecaseNames) {
    if ($usecaseName -notin $folderUsecaseNames) {
        Fail "Usecase declared in registry has no folder: $usecaseName"
    }
}

foreach ($supportPackage in $registrySupportPackages) {
    $supportName = [string]$supportPackage.name
    if ($supportName -notin $folderUsecaseNames) {
        Fail "Support package declared in registry has no folder: $supportName"
    }

    $buildEnabled = $false
    if ($supportPackage.PSObject.Properties['build_enabled']) {
        $buildEnabled = [bool]$supportPackage.build_enabled
    }

    $lifecycleStatus = ""
    if ($supportPackage.PSObject.Properties['lifecycle_status']) {
        $lifecycleStatus = [string]$supportPackage.lifecycle_status
    }

    if ($buildEnabled -eq $false -and $lifecycleStatus -eq "PLANNED") {
        Write-Host "OK: planned support package registered without primary-usecase manifest: $supportName"
    }
}

$supportTargetDir = $null
$skillsMachineUpdatePackage = @($registrySupportPackages | Where-Object { [string]$_.name -eq '05.SKILLSMACHINE_UPDATE' } | Select-Object -First 1)
if ($null -ne $skillsMachineUpdatePackage) {
    $supportTargetRelative = ''
    if ($skillsMachineUpdatePackage.PSObject.Properties['target_directory']) {
        $supportTargetRelative = [string]$skillsMachineUpdatePackage.target_directory
    }

    if ([string]::IsNullOrWhiteSpace($supportTargetRelative)) {
        $supportTargetRelative = '90.USECASE/05.SKILLSMACHINE_UPDATE'
    }

    $supportTargetDirPath = Join-Path $repoRoot ($supportTargetRelative -replace '/', '\')
    if (-not (Test-Path -LiteralPath $supportTargetDirPath -PathType Container)) {
        Fail "Support package target directory missing: $supportTargetDirPath"
    }

    $supportTargetDir = Get-Item -LiteralPath $supportTargetDirPath
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

$allowList = @()
foreach ($dir in @($primaryUsecaseDirs)) {
    $usecaseName = [string]$dir.Name
    $files = @(Get-ChildItem -LiteralPath $dir.FullName -File -Force)
    $dirs = @(Get-ChildItem -LiteralPath $dir.FullName -Directory -Force)
    if ($dirs.Count -ne 0) {
        Fail "Usecase directory must be flat: $($dir.FullName)"
    }
    if ($files.Count -ne 1) {
        Fail "Usecase directory must contain exactly one file: $($dir.FullName)"
    }
    $compiledPath = $files[0].FullName
    Assert-CompiledToken -Path $compiledPath -Token 'SOURCE_PROVENANCE_EMBEDDED=YES' -Label $usecaseName
    Assert-CompiledToken -Path $compiledPath -Token 'SEPARATE_TARGET_MANIFEST_REQUIRED=NO' -Label $usecaseName
    Assert-CompiledToken -Path $compiledPath -Token 'SKILLSMACHINE_RUNTIME_DEPENDENCY=NO' -Label $usecaseName
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

$expectedUseCaseSourceContracts = @(
    [pscustomobject]@{ Name = "02.SESSION_CLOSE"; SourceDirectory = "SyS/A_Tools/UseCaseSources/02.SessionClose" },
    [pscustomobject]@{ Name = "03.SESSION_CONTINUE"; SourceDirectory = "SyS/A_Tools/UseCaseSources/03.SessionContinue" },
    [pscustomobject]@{ Name = "04.REPOSITORY_STRUCTURE_REPAIR"; SourceDirectory = "SyS/A_Tools/UseCaseSources/04.RepositoryStructureRepair" }
)

foreach ($contract in $expectedUseCaseSourceContracts) {
    $registryItem = @($registryUsecases | Where-Object { [string]$_.name -eq $contract.Name }) | Select-Object -First 1
    if ($null -eq $registryItem) {
        Fail "Usecase source contract missing in registry: $($contract.Name)"
    }

    if ([string]$registryItem.source_directory -ne $contract.SourceDirectory) {
        Fail "Usecase source_directory mismatch for $($contract.Name)"
    }

    foreach ($legacyProp in @('copied_files','preserve_files','delivery_files','bundle_definitions','prompt_files','menu_files','delivery_files_extra')) {
        if ($registryItem.PSObject.Properties[$legacyProp]) {
            Fail "Usecase legacy property still present for $($contract.Name): $legacyProp"
        }
    }

    $sourceEntries = @(
        Normalize-ToArray $registryItem.source_entries |
        ForEach-Object { [string]$_.source_path } |
        Sort-Object -Unique
    )
    if ($sourceEntries.Count -eq 0) {
        Fail "Usecase source_entries missing for $($contract.Name)"
    }
    foreach ($sourceEntry in $sourceEntries) {
        $sourcePath = Join-Path $repoRoot ($sourceEntry -replace '/', '\')
        if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
            Fail "Usecase source entry missing: $sourcePath"
        }
    }
}

$buildScriptPath = Join-Path $usecaseRoot "BUILD.ps1"
$buildText = Get-Content -LiteralPath $buildScriptPath -Raw -Encoding UTF8
$requiredBuildTokens = @(
    "Get-CompiledOutputContract",
    "source_entries",
    "upload_package_model",
    "New-UseCaseCompiledFile"
)
foreach ($token in $requiredBuildTokens) {
    if ($buildText -notmatch [regex]::Escape($token)) {
        Fail "BUILD missing usecase source migration token: $token"
    }
}
function Get-Sha256Hex {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $stream = [System.IO.File]::OpenRead($Path)
    try {
        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        try {
            $bytes = $sha256.ComputeHash($stream)
            return ([System.BitConverter]::ToString($bytes)).Replace("-", "")
        }
        finally {
            $sha256.Dispose()
        }
    }
    finally {
        $stream.Dispose()
    }
}
# MB-SM-062D-D: updater core consistency validation
$skillsMachineRootForUpdater = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\..\.."))
$updaterCoreRoot = Join-Path $skillsMachineRootForUpdater "SyS\A_Tools\Update"
$updaterRunner = Join-Path $updaterCoreRoot "Invoke-SkillsMachineUpdate.ps1"
$updaterTest = Join-Path $updaterCoreRoot "Test-SkillsMachineUpdate.ps1"
$updaterBaselineSchema = Join-Path $updaterCoreRoot "SKILLSMACHINE.PROJECT.BASELINE.schema.json"
$updaterManifestSchema = Join-Path $updaterCoreRoot "SKILLSMACHINE.UPDATE.MANIFEST.schema.json"
$updaterReadme = Join-Path $updaterCoreRoot "README.SKILLSMACHINE.UPDATE.txt"

foreach ($powerShellPath in @($updaterRunner, $updaterTest)) {
    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile(
        $powerShellPath,
        [ref]$tokens,
        [ref]$parseErrors
    )
    if (@($parseErrors).Count -gt 0) {
        $messages = @($parseErrors | ForEach-Object { $_.Message }) -join " | "
        throw "Updater PowerShell parse failed: $powerShellPath | $messages"
    }
}

$baselineSchemaObject = Get-Content -LiteralPath $updaterBaselineSchema -Raw -Encoding UTF8 |
    ConvertFrom-Json -ErrorAction Stop
$manifestSchemaObject = Get-Content -LiteralPath $updaterManifestSchema -Raw -Encoding UTF8 |
    ConvertFrom-Json -ErrorAction Stop

if ([string]$baselineSchemaObject.properties.schema_version.const -ne "1.1") {
    throw "Updater baseline schema version must be 1.1"
}
if ([string]$manifestSchemaObject.properties.schema_version.const -ne "1.1") {
    throw "Updater manifest schema version must be 1.1"
}

$actionEnum = @(
    $manifestSchemaObject.properties.operations.items.properties.action.enum |
        ForEach-Object { [string]$_ } |
        Sort-Object
)
$expectedActionEnum = @("ADD", "DELETE", "REPLACE")
if (($actionEnum -join "|") -ne ($expectedActionEnum -join "|")) {
    throw "Updater action enum must be exactly ADD, DELETE, REPLACE; actual=$($actionEnum -join ',')"
}

$runnerText = Get-Content -LiteralPath $updaterRunner -Raw -Encoding UTF8
$readmeText = Get-Content -LiteralPath $updaterReadme -Raw -Encoding UTF8
$testText = Get-Content -LiteralPath $updaterTest -Raw -Encoding UTF8

$requiredRunnerTokens = @(
    "APPLY_FAILED_ROLLBACK_PASS",
    "APPLY_FAILED_ROLLBACK_FAIL",
    "TEST_HOOK_BLOCKED_WITHOUT_TEST_MODE",
    "TEST_HOOK_BLOCKED_FOR_NON_TEST_PROJECT",
    "[switch]`$TestMode"
)
foreach ($token in $requiredRunnerTokens) {
    if (-not $runnerText.Contains($token)) {
        throw "Updater runner required contract token missing: $token"
    }
}

$requiredReadmeTokens = @(
    "PARTIAL-FAILURE CONTRACT",
    "TEST-ONLY FAILURE HOOK",
    "-TestMode",
    "NEGATIVE_TEST_"
)
foreach ($token in $requiredReadmeTokens) {
    if (-not $readmeText.Contains($token)) {
        throw "Updater README required contract token missing: $token"
    }
}

$requiredTestTokens = @(
    "AUTOMATIC_ROLLBACK_AFTER_PARTIAL_FAILURE=PASS",
    "TEST_HOOK_REJECTED_WITHOUT_TEST_MODE=PASS",
    "TEST_HOOK_REJECTED_FOR_NORMAL_PROJECT=PASS",
    "TEST_HOOK_ACCEPTED_FOR_NEGATIVE_TEST_PROJECT=PASS"
)
foreach ($token in $requiredTestTokens) {
    if (-not $testText.Contains($token)) {
        throw "Updater test required assertion missing: $token"
    }
}

$supportFiles = @(Get-ChildItem -LiteralPath $supportTargetDir -File -Force)
if ($supportFiles.Count -ne 1) {
    throw "Support package target must contain exactly one file"
}
$compiledSupportPath = $supportFiles[0].FullName
Assert-CompiledToken -Path $compiledSupportPath -Token 'SOURCE_PROVENANCE_EMBEDDED=YES' -Label 'SUPPORT_PACKAGE'
Assert-CompiledToken -Path $compiledSupportPath -Token 'SEPARATE_TARGET_MANIFEST_REQUIRED=NO' -Label 'SUPPORT_PACKAGE'
Assert-CompiledToken -Path $compiledSupportPath -Token 'SKILLSMACHINE_RUNTIME_DEPENDENCY=NO' -Label 'SUPPORT_PACKAGE'

Write-Host "OK: support package consistency validated"


Write-Host "OK: consistency validation passed"
exit 0
