param(
    [string]$UseCase = "03.SESSION_CONTINUE",
    [object[]]$IncludePath = @(),
    [switch]$Clean
)

$ErrorActionPreference = "Stop"

$ScriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$Root = (Resolve-Path (Join-Path $ScriptPath "..")).Path
$UploadRoot = Join-Path $Root "Temp\TO_UPLOAD_TO_IA"

function Write-Line {
    param([string]$Text = "")
    Write-Host $Text
}

function New-Dir {
    param([string]$Path)
    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path | Out-Null
    }
}

function Normalize-IncludePaths {
    param([object[]]$RawItems)

    $result = New-Object System.Collections.Generic.List[string]

    foreach ($item in $RawItems) {
        if ($null -eq $item) { continue }

        if ($item -is [array]) {
            foreach ($sub in $item) {
                if ($null -ne $sub) {
                    $s = [string]$sub
                    foreach ($part in ($s -split ",")) {
                        $trimmed = $part.Trim().Trim('"').Trim("'")
                        if (-not [string]::IsNullOrWhiteSpace($trimmed)) {
                            $result.Add($trimmed) | Out-Null
                        }
                    }
                }
            }
            continue
        }

        $raw = [string]$item
        foreach ($part in ($raw -split ",")) {
            $trimmed = $part.Trim().Trim('"').Trim("'")
            if (-not [string]::IsNullOrWhiteSpace($trimmed)) {
                $result.Add($trimmed) | Out-Null
            }
        }
    }

    return $result
}

function Get-BucketForPath {
    param([string]$RelativePath)

    $p = $RelativePath -replace "\\", "/"

    if ($p -like "SkillsLake/01.SKILLS/*" -or $p -like "SkillsLake/00.MENU/*") {
        return "10.SKILLS"
    }
    if ($p -like "GRCLake/*") {
        return "20.GRC"
    }
    if ($p -like "00.CATALOG/*") {
        return "30.CATALOG"
    }
    if ($p -like "90.USECASE/*") {
        return "40.USECASE"
    }
    return "90.EXTRA"
}

function Copy-ContextFile {
    param(
        [string]$RelativePath,
        [string]$Bucket,
        [System.Collections.Generic.List[string]]$Copied,
        [System.Collections.Generic.List[string]]$Missing
    )

    $normalized = $RelativePath -replace "\\", "/"
    $src = Join-Path $Root $normalized

    if (-not (Test-Path $src)) {
        $Missing.Add($normalized) | Out-Null
        return
    }

    $destDir = Join-Path $UploadRoot $Bucket
    New-Dir $destDir

    $safeRel = $normalized -replace "[:]", "" -replace "[\\/]", "__"
    $dest = Join-Path $destDir $safeRel

    Copy-Item -Path $src -Destination $dest -Force
    $Copied.Add("$normalized -> $Bucket\$safeRel") | Out-Null
}

Write-Line "========== PREPARE TO_UPLOAD_TO_IA / START =========="
Write-Line "ROOT.............: $Root"
Write-Line "USECASE..........: $UseCase"
Write-Line "UPLOAD_ROOT......: $UploadRoot"

if ($Clean -or -not (Test-Path $UploadRoot)) {
    if (Test-Path $UploadRoot) {
        Remove-Item -Path $UploadRoot -Recurse -Force
        Write-Line "CLEANED..........: $UploadRoot"
    }
}

New-Dir $UploadRoot
foreach ($dir in @("10.SKILLS","20.GRC","30.CATALOG","40.USECASE","90.EXTRA")) {
    New-Dir (Join-Path $UploadRoot $dir)
}

$copied = [System.Collections.Generic.List[string]]::new()
$missing = [System.Collections.Generic.List[string]]::new()
$normalizedIncludes = Normalize-IncludePaths -RawItems $IncludePath

Write-Line "INCLUDE_COUNT....: $($normalizedIncludes.Count)"
foreach ($inc in $normalizedIncludes) {
    Write-Line "INCLUDE..........: $inc"
}

# Always include canonical active menu.
Copy-ContextFile -RelativePath "SkillsLake/00.MENU/00.SKILL.MENU.ACTIVE.txt" -Bucket "10.SKILLS" -Copied $copied -Missing $missing

# Include selected usecase delivery package.
$UseCasePath = "90.USECASE/$UseCase"
$UseCaseAbs = Join-Path $Root $UseCasePath

if (Test-Path $UseCaseAbs) {
    Get-ChildItem -Path $UseCaseAbs -File | Sort-Object Name | ForEach-Object {
        $rel = "90.USECASE/$UseCase/$($_.Name)"
        Copy-ContextFile -RelativePath $rel -Bucket "40.USECASE\$UseCase" -Copied $copied -Missing $missing
    }
} else {
    $missing.Add($UseCasePath) | Out-Null
}

# Include explicit requested paths.
foreach ($p in $normalizedIncludes) {
    $bucket = Get-BucketForPath -RelativePath $p
    Copy-ContextFile -RelativePath $p -Bucket $bucket -Copied $copied -Missing $missing
}

$manifestPath = Join-Path $UploadRoot "00.UPLOAD.MANIFEST.txt"
$readmePath = Join-Path $UploadRoot "01.README.UPLOAD_INSTRUCTIONS.txt"
$now = Get-Date -Format "yyyy-MM-dd HH:mm:ss zzz"

$manifest = @()
$manifest += "=========="
$manifest += "00.UPLOAD.MANIFEST"
$manifest += "=========="
$manifest += ""
$manifest += "GENERATED_AT........: $now"
$manifest += "ROOT................: $Root"
$manifest += "USECASE.............: $UseCase"
$manifest += "UPLOAD_ROOT.........: $UploadRoot"
$manifest += "GENERATED_OUTPUT....: YES"
$manifest += "DO_NOT_EDIT_CANON...: YES"
$manifest += ""
$manifest += "=========="
$manifest += "01.00_COPIED_FILES"
$manifest += "=========="
if ($copied.Count -eq 0) {
    $manifest += "[NONE]"
} else {
    foreach ($c in $copied) { $manifest += "- $c" }
}
$manifest += ""
$manifest += "=========="
$manifest += "02.00_MISSING_FILES"
$manifest += "=========="
if ($missing.Count -eq 0) {
    $manifest += "[NONE]"
} else {
    foreach ($m in $missing) { $manifest += "- $m" }
}
$manifest += ""
$manifest += "=========="
$manifest += "03.00_UPLOAD_INSTRUCTION"
$manifest += "=========="
$manifest += "Upload the contents of Temp\TO_UPLOAD_TO_IA to the IA/chat."
$manifest += "Do not edit canonical files from this folder."
$manifest += "If context is insufficient, request additional source paths and regenerate."

Set-Content -Path $manifestPath -Value ($manifest -join "`r`n") -Encoding UTF8

$readme = @"
==========
01.README.UPLOAD_INSTRUCTIONS
==========

PURPOSE:
This folder contains a generated context package for upload to IA/chat.

WHAT TO UPLOAD:
Upload all files inside:

Temp\TO_UPLOAD_TO_IA

DO NOT:
- Do not edit canonical repo files from this folder.
- Do not commit Temp\TO_UPLOAD_TO_IA.
- Do not treat copied files here as source of truth.

SOURCE OF TRUTH:
- SkillsLake
- GRCLake
- 00.CATALOG
- 90.USECASE
- BUILD / registries / manifests

REGENERATION:
Run from C:\01. GitHub\Skills:

pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "90.USECASE\Prepare-ToUploadToIA.ps1" -UseCase "$UseCase" -Clean

OPTIONAL INCLUDE EXAMPLE:
pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "90.USECASE\Prepare-ToUploadToIA.ps1" -UseCase "03.SESSION_CONTINUE" -Clean -IncludePath "SkillsLake/01.SKILLS/28.SKILL.BASH.WSL2.txt","00.CATALOG/SESSION.LEARNING.REVIEW.ACTIVE.txt"
"@

Set-Content -Path $readmePath -Value $readme -Encoding UTF8

Write-Line ""
Write-Line "---------- RESULT ----------"
Write-Line "COPIED_COUNT.....: $($copied.Count)"
Write-Line "MISSING_COUNT....: $($missing.Count)"
Write-Line "MANIFEST.........: $manifestPath"
Write-Line "README...........: $readmePath"
Write-Line "UPLOAD_ROOT......: $UploadRoot"

if ($missing.Count -gt 0) {
    Write-Line "WARN.............: Missing files detected. Review manifest."
}

Write-Line "========== PREPARE TO_UPLOAD_TO_IA / END =========="
