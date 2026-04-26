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

Write-Host "VALIDATION: structure"

$registryPath = "90.USECASE\USECASE.REGISTRY.json"
$globalRegistryPath = "90.USECASE\GLOBAL.SKILL.VERSION.REGISTRY.json"

Test-JsonFile $registryPath
Test-JsonFile $globalRegistryPath

$usecaseDirs = Get-ChildItem -LiteralPath "90.USECASE" -Directory |
    Where-Object { $_.Name -match '^\d{2}\.' }

if (-not $usecaseDirs) {
    Fail "No usecase directories found under 90.USECASE"
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

Write-Host "OK: structure validation passed"
exit 0
