param(
    [string[]]$Include = @(
        "SkillsLake/00.MENU/00.SKILL.MENU.ACTIVE.txt",
        "90.USECASE/GLOBAL.SKILL.VERSION.REGISTRY.json",
        "90.USECASE/USECASE.REGISTRY.json",
        "00.CATALOG/USECASE.COVERAGE.AUDIT.ACTIVE.txt",
        "00.CATALOG/DOMAIN.REGISTRY.ACTIVE.txt",
        "00.CATALOG/ARTIFACT.REGISTRY.ACTIVE.txt",
        "00.CATALOG/CONTEXT.COMPOSER.RULES.ACTIVE.txt"
    ),
    [string]$OutputRel = "Temp/TO_UPLOAD_TO_IA"
)

$ErrorActionPreference = "Stop"

$Root = (Resolve-Path ".").Path
$Out = Join-Path $Root $OutputRel

Write-Host "========== BUILD TO_UPLOAD_TO_IA / START =========="
Write-Host "ROOT.............: $Root"
Write-Host "OUTPUT...........: $Out"

if (Test-Path $Out) {
    Remove-Item -Path $Out -Recurse -Force
}

New-Item -ItemType Directory -Force -Path $Out | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $Out "10.SKILLS") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $Out "20.GRC") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $Out "30.CATALOG") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $Out "40.USECASE") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $Out "90.EXTRA") | Out-Null

$Copied = New-Object System.Collections.Generic.List[string]
$Missing = New-Object System.Collections.Generic.List[string]

foreach ($rel in $Include) {
    $src = Join-Path $Root $rel
    if (!(Test-Path $src)) {
        $Missing.Add($rel)
        continue
    }

    $bucket = "90.EXTRA"
    if ($rel -like "SkillsLake/01.SKILLS/*" -or $rel -like "SkillsLake\01.SKILLS\*") { $bucket = "10.SKILLS" }
    elseif ($rel -like "GRCLake/*" -or $rel -like "GRCLake\*") { $bucket = "20.GRC" }
    elseif ($rel -like "00.CATALOG/*" -or $rel -like "00.CATALOG\*") { $bucket = "30.CATALOG" }
    elseif ($rel -like "90.USECASE/*" -or $rel -like "90.USECASE\*") { $bucket = "40.USECASE" }

    $safeName = ($rel -replace '[\\/]', '__')
    $dest = Join-Path (Join-Path $Out $bucket) $safeName
    Copy-Item -Path $src -Destination $dest -Force
    $Copied.Add("$rel -> $bucket/$safeName")
}

$manifest = Join-Path $Out "00.UPLOAD.MANIFEST.txt"
$readme = Join-Path $Out "01.README.UPLOAD_INSTRUCTIONS.txt"

@"
==========
00.UPLOAD.MANIFEST
==========

GENERATED_AT........: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
ROOT................: $Root
OUTPUT..............: $Out
PURPOSE.............: Files prepared for manual upload to IA.

==========
01.00_RULES
==========

- This folder is temporary.
- This folder is not canon.
- Upload the contents of this folder to the IA when context is requested.
- Do not edit canonical files from this folder.
- If context is insufficient, regenerate with additional Include paths.

==========
02.00_COPIED_FILES
==========
$($Copied -join "`r`n")

==========
03.00_MISSING_FILES
==========
$(if ($Missing.Count -eq 0) { "[NONE]" } else { $Missing -join "`r`n" })

==========
FIN
==========
"@ | Set-Content -Path $manifest -Encoding UTF8

@"
Upload this folder to IA:

$Out

Recommended upload order:
1. 00.UPLOAD.MANIFEST.txt
2. 30.CATALOG
3. 40.USECASE
4. 10.SKILLS
5. 20.GRC
6. 90.EXTRA

If the IA asks for more context, add the requested files to the Include list and regenerate.
"@ | Set-Content -Path $readme -Encoding UTF8

Write-Host "COPIED_COUNT.....: $($Copied.Count)"
Write-Host "MISSING_COUNT....: $($Missing.Count)"
Write-Host "MANIFEST.........: $manifest"
Write-Host "README...........: $readme"

if ($Missing.Count -gt 0) {
    Write-Host "WARN_MISSING.....:"
    $Missing | ForEach-Object { Write-Host " - $_" }
}

Write-Host "========== BUILD TO_UPLOAD_TO_IA / END =========="
