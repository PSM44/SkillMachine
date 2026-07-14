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

    $normalized = $Text
    if ($null -eq $normalized) {
        return $Text
    }

    $normalized = $normalized.TrimStart([char]0xFEFF)
    $pattern = "(?s)^(?:=+\s*GENERATED_OUTPUT_POLICY\s*=+.*?=+\s*END_GENERATED_OUTPUT_POLICY\s*=+\r?\n\r?\n?)+"
    return [regex]::Replace($normalized, $pattern, "")
}

function Set-GeneratedTxtHeader {
    param([string]$Path,[string]$SourceOfTruth,[string]$GenerationMode)
    if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){return}
    $raw=Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    $clean=Remove-ExistingGeneratedHeader -Text $raw
    $header=Get-GeneratedHeader -SourceOfTruth $SourceOfTruth -GenerationMode $GenerationMode
    $h=($header-replace"`r`n","`n").TrimEnd([char[]]"`r`n")
    $c=($clean-replace"`r`n","`n").TrimStart([char[]]"`r`n").TrimEnd([char[]]"`r`n")
    $lf=if([string]::IsNullOrEmpty($c)){$h+"`n"}else{$h+"`n`n"+$c+"`n"}
    $canonical=$lf-replace"`n",[Environment]::NewLine
    if($raw-ceq$canonical){Write-Host "POLICY_HEADER_TXT_UNCHANGED: $Path";return}
    [IO.File]::WriteAllText($Path,$canonical,[Text.UTF8Encoding]::new($false))
    Write-Host "POLICY_HEADER_TXT_UPDATED: $Path"
}

function Set-GeneratedJsonPolicy {
    param([string]$Path)
    if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){return}
    $raw=Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    $json=$raw|ConvertFrom-Json -ErrorAction Stop
    $json|Add-Member generated_output_only $true -Force
    $json|Add-Member do_not_edit_manually $true -Force
    if(-not$json.PSObject.Properties["source_of_truth"]-or[string]::IsNullOrWhiteSpace([string]$json.source_of_truth)){
        $json|Add-Member source_of_truth "90.USECASE/BUILD.ps1 + source registries/manifests" -Force
    }
    if(-not$json.PSObject.Properties["regeneration_contract"]-or[string]::IsNullOrWhiteSpace([string]$json.regeneration_contract)){
        $json|Add-Member regeneration_contract "Re-run 90.USECASE/BUILD.ps1 from C:\01. GitHub\Skills" -Force
    }
    $canonical=($json|ConvertTo-Json -Depth 100).TrimEnd([char[]]"`r`n")+[Environment]::NewLine
    if($raw-ceq$canonical){Write-Host "POLICY_HEADER_JSON_UNCHANGED: $Path";return}
    [IO.File]::WriteAllText($Path,$canonical,[Text.UTF8Encoding]::new($false))
    Write-Host "POLICY_HEADER_JSON_UPDATED: $Path"
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
    Set-GeneratedJsonPolicy -Path (Join-Path $uc "SUPPORT_PACKAGE.MANIFEST.json")
}

Write-Host "GENERATED_OUTPUT_POLICY_DONE"
