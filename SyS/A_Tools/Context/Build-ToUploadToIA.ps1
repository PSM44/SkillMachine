param(
    [string[]]$Include = @(),
    [string]$IncludeFile = "",
    [string]$OutputRel = "SyS/Temp/TO_UPLOAD_TO_IA",
    [switch]$AllowMissing
)

$ErrorActionPreference = "Stop"

$Root = (Resolve-Path ".").Path
$Out = Join-Path $Root $OutputRel

Write-Host "========== BUILD TO_UPLOAD_TO_IA / START =========="
Write-Host "ROOT.............: $Root"
Write-Host "OUTPUT...........: $Out"

$Requested = New-Object System.Collections.Generic.List[string]

if ($IncludeFile -and $IncludeFile.Trim().Length -gt 0) {
    $includeFilePath = Join-Path $Root $IncludeFile
    if (!(Test-Path $includeFilePath)) {
        Write-Host "ERROR............: IncludeFile not found: $IncludeFile"
        exit 1
    }

    Get-Content -Path $includeFilePath | ForEach-Object {
        $line = $_.Trim()
        if ($line.Length -gt 0 -and !$line.StartsWith("#")) {
            $Requested.Add($line)
        }
    }
}

foreach ($item in $Include) {
    if ($null -ne $item -and $item.Trim().Length -gt 0) {
        $Requested.Add($item.Trim())
    }
}

$Requested = @($Requested | Select-Object -Unique)

if ($Requested.Count -eq 0) {
    Write-Host "ERROR............: No files requested."
    Write-Host "USAGE............: Provide -Include or -IncludeFile."
    Write-Host "EXAMPLE..........: powershell.exe -NoProfile -ExecutionPolicy Bypass -File SyS\A_Tools\Context\Build-ToUploadToIA.ps1 -Include `"SkillsLake/01.SKILLS/28.SKILL.BASH.WSL2.txt`""
    Write-Host "NOTE.............: TO_UPLOAD_TO_IA is not a default context package. It is only for explicit IA-requested delta files."
    Write-Host "========== BUILD TO_UPLOAD_TO_IA / END =========="
    exit 1
}

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

foreach ($rel in $Requested) {
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
PURPOSE.............: Explicit IA-requested delta context files prepared for manual upload.

==========
01.00_RULES
==========

- This folder is temporary.
- This folder is not canon.
- This folder is not an initial context package.
- This folder contains only files explicitly requested by the IA or human.
- Upload the contents of this folder to the IA only when additional context is requested.
- Do not edit canonical files from this folder.
- If context is insufficient, regenerate with additional Include paths.

==========
02.00_REQUESTED_FILES
==========
$($Requested -join "`r`n")

==========
03.00_COPIED_FILES
==========
$($Copied -join "`r`n")

==========
04.00_MISSING_FILES
==========
$(if ($Missing.Count -eq 0) { "[NONE]" } else { $Missing -join "`r`n" })

==========
FIN
==========
"@ | Set-Content -Path $manifest -Encoding UTF8

@"
Upload this folder to IA only if the IA requested additional files:

$Out

Recommended upload order:
1. 00.UPLOAD.MANIFEST.txt
2. 10.SKILLS
3. 20.GRC
4. 30.CATALOG
5. 40.USECASE
6. 90.EXTRA

This is not the initial usecase package.
For initial work, upload the corresponding 90.USECASE output package first.
"@ | Set-Content -Path $readme -Encoding UTF8

Write-Host "REQUESTED_COUNT..: $($Requested.Count)"
Write-Host "COPIED_COUNT.....: $($Copied.Count)"
Write-Host "MISSING_COUNT....: $($Missing.Count)"
Write-Host "MANIFEST.........: $manifest"
Write-Host "README...........: $readme"

if ($Missing.Count -gt 0) {
    Write-Host "WARN_MISSING.....:"
    $Missing | ForEach-Object { Write-Host " - $_" }

    if (!$AllowMissing) {
        Write-Host "ERROR............: Missing files detected. Use -AllowMissing only if this is intentional."
        Write-Host "========== BUILD TO_UPLOAD_TO_IA / END =========="
        exit 2
    }
}

Write-Host "========== BUILD TO_UPLOAD_TO_IA / END =========="
