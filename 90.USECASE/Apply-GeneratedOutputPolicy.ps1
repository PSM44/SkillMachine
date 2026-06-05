$ErrorActionPreference = "Stop"

$UsecaseRoot = $PSScriptRoot
$SourceRoot = (Resolve-Path (Join-Path $UsecaseRoot "..")).Path

$HeaderStart = "========== GENERATED_OUTPUT_POLICY =========="
$HeaderEnd   = "========== END_GENERATED_OUTPUT_POLICY =========="

function Get-GeneratedHeader {
    param(
        [string]$SourceOfTruth,
        [string]$GenerationMode
    )

@"
$HeaderStart
GENERATED_OUTPUT_ONLY.......: YES
DO_NOT_EDIT_MANUALLY........: YES
SOURCE_OF_TRUTH.............: $SourceOfTruth
GENERATION_MODE.............: $GenerationMode
REGENERATION_CONTRACT.......: Re-run 90.USECASE/BUILD.ps1 from C:\01. GitHub\Skills
HUMAN_OVERRIDE_REQUIRED.....: YES, if manual edit is intentional
$HeaderEnd

"@
}

function Remove-ExistingGeneratedHeader {
    param([string]$Text)

    $pattern = "(?s)^=+\s*GENERATED_OUTPUT_POLICY\s*=+.*?=+\s*END_GENERATED_OUTPUT_POLICY\s*=+\r?\n\r?\n?"
    return [regex]::Replace($Text, $pattern, "")
}

function Set-GeneratedTxtHeader {
    param(
        [string]$Path,
        [string]$SourceOfTruth,
        [string]$GenerationMode
    )

    if (-not (Test-Path $Path)) { return }

    $raw = Get-Content -Raw -Encoding UTF8 $Path
    $clean = Remove-ExistingGeneratedHeader -Text $raw
    $header = Get-GeneratedHeader -SourceOfTruth $SourceOfTruth -GenerationMode $GenerationMode

    Set-Content -Path $Path -Value ($header + $clean) -Encoding UTF8
    Write-Host "POLICY_HEADER_TXT.: $Path"
}

function Set-GeneratedJsonPolicy {
    param([string]$Path)

    if (-not (Test-Path $Path)) { return }

    $raw = Get-Content -Raw -Encoding UTF8 $Path
    $json = $raw | ConvertFrom-Json

    $json | Add-Member -NotePropertyName "generated_output_only" -NotePropertyValue $true -Force
    $json | Add-Member -NotePropertyName "do_not_edit_manually" -NotePropertyValue $true -Force
    $json | Add-Member -NotePropertyName "source_of_truth" -NotePropertyValue "90.USECASE/BUILD.ps1 + source registries/manifests" -Force
    $json | Add-Member -NotePropertyName "regeneration_contract" -NotePropertyValue "Re-run 90.USECASE/BUILD.ps1 from C:\01. GitHub\Skills" -Force

    $json | ConvertTo-Json -Depth 30 | Set-Content -Path $Path -Encoding UTF8
    Write-Host "POLICY_HEADER_JSON: $Path"
}

$UsecaseDirs = Get-ChildItem -Path $UsecaseRoot -Directory | Where-Object {
    $_.Name -match '^\d{2}\.'
}

foreach ($dir in $UsecaseDirs) {
    $uc = $dir.FullName

    Set-GeneratedTxtHeader `
        -Path (Join-Path $uc "00.BUNDLE.CORE.txt") `
        -SourceOfTruth "SkillsLake/01.SKILLS + 90.USECASE/USECASE.REGISTRY.json + 90.USECASE/GLOBAL.SKILL.VERSION.REGISTRY.json + 90.USECASE/BUILD.ps1" `
        -GenerationMode "BUILD_BUNDLE_CORE"

    Set-GeneratedTxtHeader `
        -Path (Join-Path $uc "01.BUNDLE.CONTINUITY.txt") `
        -SourceOfTruth "SkillsLake/01.SKILLS + 90.USECASE/USECASE.REGISTRY.json + 90.USECASE/GLOBAL.SKILL.VERSION.REGISTRY.json + 90.USECASE/BUILD.ps1" `
        -GenerationMode "BUILD_BUNDLE_CONTINUITY"

    Set-GeneratedTxtHeader `
        -Path (Join-Path $uc "02.BUNDLE.GOVERNANCE.txt") `
        -SourceOfTruth "SkillsLake/01.SKILLS + GRCLake + 90.USECASE/USECASE.REGISTRY.json + 90.USECASE/GLOBAL.SKILL.VERSION.REGISTRY.json + 90.USECASE/BUILD.ps1" `
        -GenerationMode "BUILD_BUNDLE_GOVERNANCE"

    Set-GeneratedTxtHeader `
        -Path (Join-Path $uc "00.SKILL.MENU.ACTIVE.txt") `
        -SourceOfTruth "SkillsLake/00.MENU/00.SKILL.MENU.ACTIVE.txt + 90.USECASE/BUILD.ps1" `
        -GenerationMode "BUILD_COPIED_MENU"

    Set-GeneratedJsonPolicy -Path (Join-Path $uc "USECASE.MANIFEST.json")
}

Write-Host "GENERATED_OUTPUT_POLICY_DONE"
