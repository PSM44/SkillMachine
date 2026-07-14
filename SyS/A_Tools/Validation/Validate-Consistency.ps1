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

function Assert-FileContentEqual([string]$PathA, [string]$PathB, [string]$Label) {
    if (-not (Test-Path -LiteralPath $PathA -PathType Leaf)) {
        Fail "$Label missing file: $PathA"
    }
    if (-not (Test-Path -LiteralPath $PathB -PathType Leaf)) {
        Fail "$Label missing file: $PathB"
    }

    $contentA = ((Get-Content -LiteralPath $PathA -Raw -Encoding UTF8) -replace "`r`n", "`n").TrimEnd("`n")
    $contentB = ((Get-Content -LiteralPath $PathB -Raw -Encoding UTF8) -replace "`r`n", "`n").TrimEnd("`n")
    if ($contentA -ne $contentB) {
        Fail "$Label mismatch: $PathA <> $PathB"
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

$primaryUsecaseDirs = @(
    $usecaseDirs |
    Where-Object { $_.Name -in $registryUsecaseNames }
)

foreach ($dir in $primaryUsecaseDirs) {
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

$expectedUseCaseSourceContracts = @(
    [pscustomobject]@{
        Name = "03.SESSION_CONTINUE"
        SourceDirectory = "SyS/A_Tools/UseCaseSources/03.SessionContinue"
        CopiedFiles = @(
            "PROMPT.SESSION_CONTINUE.txt",
            "README.UPLOAD_THIS_USECASE.txt",
            "SKILL_SET.MANIFEST.txt"
        )
    },
    [pscustomobject]@{
        Name = "04.REPOSITORY_STRUCTURE_REPAIR"
        SourceDirectory = "SyS/A_Tools/UseCaseSources/04.RepositoryStructureRepair"
        CopiedFiles = @(
            "HUMAN.REPOSITORY_STRUCTURE_REPAIR.txt",
            "README.EXECUTION.txt",
            "README.UPLOAD_THIS_USECASE.txt",
            "SKILL.md",
            "SKILL_SET.MANIFEST.txt",
            "WHOAMI.REPOSITORY_STRUCTURE_REPAIR.txt",
            "EXAMPLES/EXAMPLE.REPO_REPAIR.txt"
        )
    }
)

foreach ($contract in $expectedUseCaseSourceContracts) {
    $registryItem = @($registryUsecases | Where-Object { [string]$_.name -eq $contract.Name }) | Select-Object -First 1
    if ($null -eq $registryItem) {
        Fail "Usecase source contract missing in registry: $($contract.Name)"
    }

    if ([string]$registryItem.source_directory -ne $contract.SourceDirectory) {
        Fail "Usecase source_directory mismatch for $($contract.Name)"
    }

    $copiedFiles = @(
        Normalize-ToArray $registryItem.copied_files |
        ForEach-Object { [string]$_ } |
        Sort-Object
    )
    $expectedCopiedFiles = @($contract.CopiedFiles | Sort-Object)
    if (($copiedFiles -join "|") -ne ($expectedCopiedFiles -join "|")) {
        Fail "Usecase copied_files mismatch for $($contract.Name)"
    }

    if ($registryItem.PSObject.Properties['preserve_files']) {
        Fail "Usecase preserve_files source exception still present for $($contract.Name)"
    }

    $sourceDir = Join-Path $repoRoot $contract.SourceDirectory
    foreach ($copiedFile in $expectedCopiedFiles) {
        $sourcePath = Join-Path $sourceDir $copiedFile
        $outputPath = Join-Path (Join-Path $usecaseRoot $contract.Name) $copiedFile
        if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
            Fail "Usecase source file missing: $sourcePath"
        }
        if (Test-Path -LiteralPath $outputPath -PathType Leaf) {
            Assert-FileContentEqual -PathA $sourcePath -PathB $outputPath -Label ("CONTENT_PARITY_{0}" -f $contract.Name)
        }
    }
}

$buildScriptPath = Join-Path $usecaseRoot "BUILD.ps1"
$buildText = Get-Content -LiteralPath $buildScriptPath -Raw -Encoding UTF8
$requiredBuildTokens = @(
    "Get-UseCaseSourceDirectoryPath",
    "Get-UseCaseCopiedFiles",
    "PREFLIGHT: source_directory faltante",
    "PREFLIGHT: copied_file faltante",
    "COPIED SOURCE:"
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

Write-Host "OK: updater core consistency validated"

$supportPackage = @(
    $registrySupportPackages |
    Where-Object { [string]$_.name -eq "05.SkillsMachineUpdate" }
)
if (@($supportPackage).Count -ne 1) {
    throw "Support package 05.SkillsMachineUpdate must be declared exactly once"
}
$supportPackage = $supportPackage[0]
$supportTargetDir = Join-Path $usecaseRoot "05.SkillsMachineUpdate"
$supportManifestPath = Join-Path $supportTargetDir "SUPPORT_PACKAGE.MANIFEST.json"
$supportManifest = Read-Json $supportManifestPath
$supportSourceDir = Join-Path $repoRoot "SyS\A_Tools\Update\SupportPackage"

$expectedSupportDelivery = @(
    "00.BUNDLE.UPDATE_CONTEXT.txt",
    "01.BUNDLE.UPDATE_METHOD.txt",
    "02.BUNDLE.UPDATE_GOVERNANCE.txt",
    "PROMPT.SKILLSMACHINE_UPDATE.txt",
    "README.UPLOAD_THIS_PACKAGE.txt",
    "RUNBOOK.SKILLSMACHINE_UPDATE.txt",
    "SUPPORT_PACKAGE.MANIFEST.json",
    "UPDATE.EXAMPLE.MANIFEST.json"
) | Sort-Object
$actualSupportDelivery = @(
    $supportManifest.delivery_files |
    ForEach-Object { [string]$_ } |
    Sort-Object
)
if (($expectedSupportDelivery -join "|") -ne ($actualSupportDelivery -join "|")) {
    throw "Support package manifest delivery_files mismatch"
}

if ([string]$supportManifest.package_name -ne "05.SkillsMachineUpdate") {
    throw "Support package manifest package_name mismatch"
}
if ([string]$supportManifest.package_type -ne "SUPPORT_PACKAGE") {
    throw "Support package manifest package_type mismatch"
}
if ([bool]$supportManifest.primary_usecase -ne $false) {
    throw "Support package manifest primary_usecase must be false"
}
if ([string]$supportManifest.source_of_truth -ne "CORE_ONLY") {
    throw "Support package manifest source_of_truth must be CORE_ONLY"
}

$exampleManifestPath = Join-Path $supportTargetDir "UPDATE.EXAMPLE.MANIFEST.json"
$exampleManifest = Get-Content -LiteralPath $exampleManifestPath -Raw -Encoding UTF8 |
    ConvertFrom-Json -ErrorAction Stop
if ([string]$exampleManifest.schema_version -ne "1.1") {
    throw "Support package example manifest schema_version must be 1.1"
}
if ([bool]$exampleManifest.reversible -ne $true) {
    throw "Support package example manifest must be reversible"
}
if ([bool]$exampleManifest.human_approval_required -ne $true) {
    throw "Support package example manifest must require human approval"
}
if ([string]$exampleManifest.rollback_contract.mode -ne "CHECKPOINT_AND_INVERSE_PLAN") {
    throw "Support package example manifest rollback_contract.mode mismatch"
}

$supportReadmeSource = Join-Path $supportSourceDir "README.UPLOAD_THIS_PACKAGE.txt"
$supportReadmeOutput = Join-Path $supportTargetDir "README.UPLOAD_THIS_PACKAGE.txt"
$supportRunbookSource = Join-Path $supportSourceDir "RUNBOOK.SKILLSMACHINE_UPDATE.txt"
$supportRunbookOutput = Join-Path $supportTargetDir "RUNBOOK.SKILLSMACHINE_UPDATE.txt"
$supportPromptSource = Join-Path $supportSourceDir "PROMPT.SKILLSMACHINE_UPDATE.txt"
$supportPromptOutput = Join-Path $supportTargetDir "PROMPT.SKILLSMACHINE_UPDATE.txt"
$supportExampleSource = Join-Path $supportSourceDir "UPDATE.EXAMPLE.MANIFEST.json"

foreach ($pair in @(
    @{ Source = $supportReadmeSource; Output = $supportReadmeOutput; Label = "README" },
    @{ Source = $supportRunbookSource; Output = $supportRunbookOutput; Label = "RUNBOOK" },
    @{ Source = $supportPromptSource; Output = $supportPromptOutput; Label = "PROMPT" },
    @{ Source = $supportExampleSource; Output = $exampleManifestPath; Label = "EXAMPLE_MANIFEST" }
)) {
    $sourceHash = (Get-Sha256Hex -Path $pair.Source)
    $outputHash = (Get-Sha256Hex -Path $pair.Output)
    if ($sourceHash -ne $outputHash) {
        throw "Support package copied file drift detected: $($pair.Label)"
    }
}

$supportReadmeText = Get-Content -LiteralPath $supportReadmeOutput -Raw -Encoding UTF8
$supportRunbookText = Get-Content -LiteralPath $supportRunbookOutput -Raw -Encoding UTF8
$supportPromptText = Get-Content -LiteralPath $supportPromptOutput -Raw -Encoding UTF8

foreach ($token in @("SyS\A_Tools\Update", "generated from core", "Invoke-SkillsMachineUpdate.ps1")) {
    if (-not $supportReadmeText.Contains($token)) {
        throw "Support package README token missing: $token"
    }
}
foreach ($token in @("dry-run", "explicit human approval", "rollback", "baseline update")) {
    if (-not $supportRunbookText.Contains($token)) {
        throw "Support package runbook token missing: $token"
    }
}
foreach ($token in @("PROJECT_ROOT", "created_by_skillsmachine=true", "clean Git", "dry-run fingerprint")) {
    if (-not $supportPromptText.Contains($token)) {
        throw "Support package prompt token missing: $token"
    }
}

Write-Host "OK: support package consistency validated"


Write-Host "OK: consistency validation passed"
exit 0
