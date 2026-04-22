<#
==========
00.00_METADATOS_DEL_DOCUMENTO
==========

ID_UNICO..........: TL.RADAR.PS1.01.00
NOMBRE_SUGERIDO...: RADAR.ps1
VERSION...........: v1.0-DRAFT
FECHA.............: 2026-02-26
HORA..............: HH:MM (America/Santiago)
CIUDAD............: Maria Luisa, Chile
UBICACION_SISTEMA.: C:\Users\aazcl\OneDrive - KUMQUAT\02- TI\Skills\Radar\
AUTOR_HUMANO......: ADMIN (PABLO)
AUTOR_IA..........: GPT-5.2 Thinking

ALCANCE...........:
Genera RADAR en la carpeta Skills (o root indicado), cumpliendo el contrato:
- Outputs: RADAR_LITE, RADAR_INDEX, RADAR_CORE, RADAR_FULL
- Determinismo (orden estable por ruta relativa)
- Segmentación si ACTIVE > 8MB (archivos .seg.001..N)
- No "OK falso": OK solo si outputs existen y no hubo errores no controlados
- No modifica el proyecto (solo lectura), salvo escribir outputs y mover históricos

NO_CUBRE..........:
- No interpreta negocio (KPIs, conclusiones).
- No hace OCR ni lee binarios complejos (xlsx/pdf en CORE se omiten).
- No gestiona credenciales.

DEPENDENCIAS......:
- Skill RADAR INDEX/CORE/FULL/LITE (09.STANDAR.RADAR_INDEX_CORE_FULL.txt)
- Skill FILE_CONTENT (07.STANDAR.FILE_CONTENT.txt)
- Skill PROBLEM_TROUBLE_INCIDENTS (08.STANDAR.PROBLEM_TROUBLE_INCIDENTS.txt)

==========
00.10_COMO_EJECUTAR
==========

CASO TIPICO (desde la carpeta Radar):
PS> cd "C:\Users\aazcl\OneDrive - KUMQUAT\02- TI\Skills\Radar"
PS> .\RADAR.ps1

ESPECIFICAR ROOT (si quieres otro):
PS> .\RADAR.ps1 -RootPath "C:\Ruta\A\Tu\Proyecto"

OPCIONES:
-HashMode: None | Text | All   (default: Text)
-MaxCoreFileBytes: tamaño máximo para incluir archivo en CORE (default: 2097152 = 2MB)
-PathMode: Relative | Full     (default: Relative)

SALIDAS ACTIVAS (en OutputDir):
- RADAR_LITE.ACTIVE.txt
- RADAR_INDEX.ACTIVE.txt
- RADAR_CORE.ACTIVE.txt
- RADAR_FULL.ACTIVE.txt
+ Segmentos .seg.001 si > 8MB

HISTORICOS:
- Mueve previos ACTIVE a \old\<timestamp>\

ESTADO FINAL:
- Escribe "OK" solo si todo fue generado correctamente
- Exit 0 si OK, exit 1 si FAIL
#>

[CmdletBinding()]
param(
  [Parameter(Mandatory = $false)]
  [string] $RootPath,

  [Parameter(Mandatory = $false)]
  [string] $OutputDir = "C:\Users\aazcl\OneDrive - KUMQUAT\02- TI\Skills\Radar",

  [Parameter(Mandatory = $false)]
  [string] $OldDir = "C:\Users\aazcl\OneDrive - KUMQUAT\02- TI\Skills\Radar\old",

  [Parameter(Mandatory = $false)]
  [ValidateSet("None","Text","All")]
  [string] $HashMode = "Text",

  [Parameter(Mandatory = $false)]
  [ValidateSet("Relative","Full")]
  [string] $PathMode = "Relative",

  [Parameter(Mandatory = $false)]
  [int] $MaxCoreFileBytes = 2097152
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ============================
# 01.00_HELPERS (verbos aprobados)
# ============================

function Test-EnsureDirectory {
  param([Parameter(Mandatory=$true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) {
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
  }
}

function Get-NowStamp {
  # YYYYMMDD_HHMMSS
  return (Get-Date).ToString("yyyyMMdd_HHmmss")
}

function Get-ActivePaths {
  param([string]$Dir)
  return @{
    Lite  = Join-Path $Dir "RADAR_LITE.ACTIVE.txt"
    Index = Join-Path $Dir "RADAR_INDEX.ACTIVE.txt"
    Core  = Join-Path $Dir "RADAR_CORE.ACTIVE.txt"
    Full  = Join-Path $Dir "RADAR_FULL.ACTIVE.txt"
  }
}

function Get-SegmentPrefix {
  param([string]$ActivePath)
  return "$ActivePath.seg."
}

function Remove-ExistingSegments {
  param([string]$ActivePath)
  $prefix = Get-SegmentPrefix -ActivePath $ActivePath
  Get-ChildItem -LiteralPath (Split-Path $ActivePath -Parent) -File -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -like "$prefix*" } |
    ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue }
}

function Move-OldActiveFiles {
  param(
    [hashtable]$ActivePaths,
    [string]$OldRoot
  )
  $stamp = Get-NowStamp
  $dest = Join-Path $OldRoot $stamp
  Test-EnsureDirectory -Path $dest

  foreach ($k in $ActivePaths.Keys) {
    $p = $ActivePaths[$k]
    if (Test-Path -LiteralPath $p) {
      $name = Split-Path $p -Leaf
      Move-Item -LiteralPath $p -Destination (Join-Path $dest $name) -Force
    }
    Remove-ExistingSegments -ActivePath $p
  }
}

function Convert-ToRelativePath {
  param(
    [Parameter(Mandatory=$true)][string]$Root,
    [Parameter(Mandatory=$true)][string]$Full
  )
  $rootNorm = [System.IO.Path]::GetFullPath($Root).TrimEnd('\')
  $fullNorm = [System.IO.Path]::GetFullPath($Full)
  if ($fullNorm.StartsWith($rootNorm, [System.StringComparison]::OrdinalIgnoreCase)) {
    $rel = $fullNorm.Substring($rootNorm.Length)
    return $rel.TrimStart('\')
  }
  return $Full
}

function Get-LogicalType {
  param([string]$ExtLower)
  switch ($ExtLower) {
    ".txt" { "text" }
    ".md"  { "text" }
    ".ps1" { "code" }
    ".py"  { "code" }
    ".js"  { "code" }
    ".ts"  { "code" }
    ".json"{ "config" }
    ".yml" { "config" }
    ".yaml"{ "config" }
    ".xml" { "config" }
    ".csv" { "data" }
    ".ini" { "config" }
    ".log" { "text" }
    ".sql" { "code" }
    ".pdf" { "binary" }
    ".xlsx"{ "binary" }
    ".xls" { "binary" }
    ".png" { "media" }
    ".jpg" { "media" }
    ".jpeg"{ "media" }
    ".gif" { "media" }
    default { "binary" }
  }
}

function Test-IsCoreEligibleExt {
  param([string]$ExtLower)
  $allowed = @(
    ".txt",".md",".ps1",".py",".json",".yml",".yaml",".xml",".csv",".js",".ts",".ini",".log",".sql"
  )
  return $allowed -contains $ExtLower
}

function Get-Sha256Hex {
  param([Parameter(Mandatory=$true)][string]$Path)
  try {
    $h = Get-FileHash -Algorithm SHA256 -LiteralPath $Path
    return $h.Hash
  } catch {
    return "HASH_ERROR"
  }
}

function Split-IfOverSize {
  param(
    [Parameter(Mandatory=$true)][string]$ActivePath,
    [int] $MaxBytes = (8 * 1024 * 1024)
  )

  if (-not (Test-Path -LiteralPath $ActivePath)) { return }

  $len = (Get-Item -LiteralPath $ActivePath).Length
  if ($len -le $MaxBytes) { return }

  $prefix = Get-SegmentPrefix -ActivePath $ActivePath
  $lines = Get-Content -LiteralPath $ActivePath -Encoding UTF8

  $segIndex = 1
  $buffer = New-Object System.Collections.Generic.List[string]
  $bufferBytes = 0

  foreach ($line in $lines) {
    # Aproximación bytes UTF-8 para segmentación por líneas
    $lineBytes = [System.Text.Encoding]::UTF8.GetByteCount($line + "`n")
    if (($bufferBytes + $lineBytes) -gt $MaxBytes -and $buffer.Count -gt 0) {
      $segName = "{0}{1:000}" -f $prefix, $segIndex
      [System.IO.File]::WriteAllLines($segName, $buffer, [System.Text.Encoding]::UTF8)
      $segIndex++
      $buffer.Clear()
      $bufferBytes = 0
    }
    $buffer.Add($line)
    $bufferBytes += $lineBytes
  }

  if ($buffer.Count -gt 0) {
    $segName = "{0}{1:000}" -f $prefix, $segIndex
    [System.IO.File]::WriteAllLines($segName, $buffer, [System.Text.Encoding]::UTF8)
  }
}

function Test-ValidateOutputsExist {
  param([hashtable]$ActivePaths)

  foreach ($k in @("Lite","Index","Core","Full")) {
    $p = $ActivePaths[$k]
    if (-not (Test-Path -LiteralPath $p)) { return $false }
    if ((Get-Item -LiteralPath $p).Length -le 0) { return $false }
  }
  return $true
}

# ============================
# 02.00_INIT
# ============================

try {
  Test-EnsureDirectory -Path $OutputDir
  Test-EnsureDirectory -Path $OldDir

  # RootPath default: 1 nivel arriba de OutputDir (Skills)
  if ([string]::IsNullOrWhiteSpace($RootPath)) {
    $RootPath = Split-Path $OutputDir -Parent
  }

  if (-not (Test-Path -LiteralPath $RootPath)) {
    Write-Error "FAIL: RootPath no existe: $RootPath"
    exit 1
  }

  $rootFull = [System.IO.Path]::GetFullPath($RootPath)
  $active = Get-ActivePaths -Dir $OutputDir

  # Mover activos anteriores a old\<timestamp>\
  Move-OldActiveFiles -ActivePaths $active -OldRoot $OldDir

  # Exclusiones (carpetas) - mantener simple y determinista
  $excludedDirNames = @(".git","node_modules","dist","build",".venv","__pycache__","pycache","TEMP","temp","cache","old")
  $excludedPathsContains = @("\old\","\node_modules\","\.git\","\.venv\","\__pycache__\","\dist\","\build\")

  # ============================
  # 03.00_SCAN FS
  # ============================

  $items = Get-ChildItem -LiteralPath $rootFull -Recurse -Force -File -ErrorAction Stop

  $records = New-Object System.Collections.Generic.List[object]

  foreach ($f in $items) {
    $full = $f.FullName

    # Excluir por path contains
    $skip = $false
    foreach ($p in $excludedPathsContains) {
      if ($full -like "*$p*") { $skip = $true; break }
    }
    if ($skip) { continue }

    # Excluir por director name (último segmento del dir)
    $dirName = (Split-Path $full -Parent | Split-Path -Leaf)
    if ($excludedDirNames -contains $dirName) { continue }

    $ext = $f.Extension
    $extLower = $ext.ToLowerInvariant()

    $logicalType = Get-LogicalType -ExtLower $extLower

    $pathOut = if ($PathMode -eq "Relative") { Convert-ToRelativePath -Root $rootFull -Full $full } else { $full }

    $sha = ""
    if ($HashMode -eq "All") {
      $sha = Get-Sha256Hex -Path $full
    } elseif ($HashMode -eq "Text") {
      if (Test-IsCoreEligibleExt -ExtLower $extLower) {
        $sha = Get-Sha256Hex -Path $full
      } else {
        $sha = ""
      }
    } else {
      $sha = ""
    }

    $records.Add([pscustomobject]@{
      Path      = $pathOut
      FullPath  = $full
      SizeBytes = [int64]$f.Length
      Modified  = $f.LastWriteTimeUtc.ToString("yyyy-MM-dd HH:mm:ss 'UTC'")
      Ext       = $extLower
      Type      = $logicalType
      Sha256    = $sha
    }) | Out-Null
  }

  # Orden determinista por Path (relativo)
  $recordsSorted = $records | Sort-Object -Property Path

  # ============================
  # 04.00_WRITE INDEX
  # ============================

  $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
  $indexLines = New-Object System.Collections.Generic.List[string]
  $indexLines.Add("==========") | Out-Null
  $indexLines.Add("RADAR_INDEX.ACTIVE") | Out-Null
  $indexLines.Add("==========") | Out-Null
  $indexLines.Add("") | Out-Null
  $indexLines.Add("TIMESTAMP.........: $ts (America/Santiago)") | Out-Null
  $indexLines.Add("ROOT..............: $rootFull") | Out-Null
  $indexLines.Add("PATH_MODE.........: $PathMode") | Out-Null
  $indexLines.Add("HASH_MODE.........: $HashMode") | Out-Null
  $indexLines.Add("TOTAL_FILES.......: $($recordsSorted.Count)") | Out-Null
  $indexLines.Add("") | Out-Null
  $indexLines.Add("----------") | Out-Null
  $indexLines.Add("FILES") | Out-Null
  $indexLines.Add("----------") | Out-Null

  foreach ($r in $recordsSorted) {
    $indexLines.Add("PATH..............: $($r.Path)") | Out-Null
    $indexLines.Add("SIZE_BYTES........: $($r.SizeBytes)") | Out-Null
    $indexLines.Add("MODIFIED..........: $($r.Modified)") | Out-Null
    $indexLines.Add("EXT...............: $($r.Ext)") | Out-Null
    $indexLines.Add("TIPO_LOGICO.......: $($r.Type)") | Out-Null
    if (-not [string]::IsNullOrWhiteSpace($r.Sha256)) {
      $indexLines.Add("SHA256............: $($r.Sha256)") | Out-Null
    } else {
      $indexLines.Add("SHA256............: ") | Out-Null
    }
    $indexLines.Add("") | Out-Null
  }

  [System.IO.File]::WriteAllLines($active.Index, $indexLines, [System.Text.Encoding]::UTF8)

  # ============================
  # 05.00_WRITE CORE
  # ============================

  $coreLines = New-Object System.Collections.Generic.List[string]
  $coreLines.Add("==========") | Out-Null
  $coreLines.Add("RADAR_CORE.ACTIVE") | Out-Null
  $coreLines.Add("==========") | Out-Null
  $coreLines.Add("") | Out-Null
  $coreLines.Add("TIMESTAMP.........: $ts (America/Santiago)") | Out-Null
  $coreLines.Add("ROOT..............: $rootFull") | Out-Null
  $coreLines.Add("MAX_CORE_BYTES.....: $MaxCoreFileBytes") | Out-Null
  $coreLines.Add("") | Out-Null

  foreach ($r in $recordsSorted) {
    $extLower = $r.Ext
    $isEligible = Test-IsCoreEligibleExt -ExtLower $extLower

    $coreLines.Add("----------") | Out-Null
    $coreLines.Add("FILE_BEGIN") | Out-Null
    $coreLines.Add("----------") | Out-Null
    $coreLines.Add("PATH..............: $($r.Path)") | Out-Null
    $coreLines.Add("SIZE_BYTES........: $($r.SizeBytes)") | Out-Null
    $coreLines.Add("MODIFIED..........: $($r.Modified)") | Out-Null
    $coreLines.Add("EXT...............: $($r.Ext)") | Out-Null
    $coreLines.Add("TIPO_LOGICO.......: $($r.Type)") | Out-Null

    if (-not $isEligible) {
      $coreLines.Add("CORE_STATUS.......: SKIPPED_NOT_TEXT") | Out-Null
      $coreLines.Add("") | Out-Null
      continue
    }

    if ($r.SizeBytes -gt $MaxCoreFileBytes) {
      $coreLines.Add("CORE_STATUS.......: SKIPPED_TOO_LARGE") | Out-Null
      $coreLines.Add("") | Out-Null
      continue
    }

    # Lectura segura
    try {
      $coreLines.Add("CORE_STATUS.......: INCLUDED") | Out-Null
      $coreLines.Add("++++++++++") | Out-Null
      $coreLines.Add("CONTENT") | Out-Null
      $coreLines.Add("++++++++++") | Out-Null

      $content = Get-Content -LiteralPath $r.FullPath -Raw -ErrorAction Stop
      $coreLines.Add($content) | Out-Null
      $coreLines.Add("") | Out-Null
    } catch {
      $coreLines.Add("CORE_STATUS.......: READ_ERROR") | Out-Null
      $coreLines.Add("ERROR.............: $($_.Exception.Message)") | Out-Null
      $coreLines.Add("") | Out-Null
    }
  }

  [System.IO.File]::WriteAllText($active.Core, ($coreLines -join "`n"), [System.Text.Encoding]::UTF8)

  # ============================
  # 06.00_WRITE FULL (INDEX + CORE + TREE_SIZE)
  # ============================

  # TREE_SIZE (bytes totales por carpeta) - determinista por path
  $dirSizes = @{}
  foreach ($r in $recordsSorted) {
    $dir = Split-Path $r.Path -Parent
    if ([string]::IsNullOrWhiteSpace($dir)) { $dir = "." }
    if (-not $dirSizes.ContainsKey($dir)) { $dirSizes[$dir] = 0L }
    $dirSizes[$dir] = $dirSizes[$dir] + [int64]$r.SizeBytes
  }

  $treeLines = New-Object System.Collections.Generic.List[string]
  $treeLines.Add("==========") | Out-Null
  $treeLines.Add("TREE_SIZE") | Out-Null
  $treeLines.Add("==========") | Out-Null
  $treeLines.Add("") | Out-Null

  foreach ($k in ($dirSizes.Keys | Sort-Object)) {
    $treeLines.Add("DIR...............: $k") | Out-Null
    $treeLines.Add("SIZE_BYTES........: $($dirSizes[$k])") | Out-Null
    $treeLines.Add("") | Out-Null
  }

  $fullLines = New-Object System.Collections.Generic.List[string]
  $fullLines.Add("==========") | Out-Null
  $fullLines.Add("RADAR_FULL.ACTIVE") | Out-Null
  $fullLines.Add("==========") | Out-Null
  $fullLines.Add("") | Out-Null
  $fullLines.Add("TIMESTAMP.........: $ts (America/Santiago)") | Out-Null
  $fullLines.Add("ROOT..............: $rootFull") | Out-Null
  $fullLines.Add("") | Out-Null

  $fullLines.Add("==========") | Out-Null
  $fullLines.Add("INCLUDE: RADAR_INDEX.ACTIVE") | Out-Null
  $fullLines.Add("==========") | Out-Null
  $fullLines.Add("") | Out-Null
  $fullLines.AddRange([System.IO.File]::ReadAllLines($active.Index, [System.Text.Encoding]::UTF8)) | Out-Null
  $fullLines.Add("") | Out-Null

  $fullLines.Add("==========") | Out-Null
  $fullLines.Add("INCLUDE: RADAR_CORE.ACTIVE") | Out-Null
  $fullLines.Add("==========") | Out-Null
  $fullLines.Add("") | Out-Null
  $fullLines.AddRange([System.IO.File]::ReadAllLines($active.Core, [System.Text.Encoding]::UTF8)) | Out-Null
  $fullLines.Add("") | Out-Null

  $fullLines.AddRange($treeLines) | Out-Null

  [System.IO.File]::WriteAllText($active.Full, ($fullLines -join "`n"), [System.Text.Encoding]::UTF8)

  # ============================
  # 07.00_WRITE LITE (diff básico vs último INDEX en old)
  # ============================


  # Buscar el INDEX más reciente en OldDir (si existe) para diff de paths
  $prevIndex = $null

  # Fuerzo array real con @() para que siempre exista .Length (evita bug de .Count)
  $oldIndexCandidates = @(
    Get-ChildItem -LiteralPath $OldDir -Recurse -File -ErrorAction SilentlyContinue |
      Where-Object { $_.Name -eq "RADAR_INDEX.ACTIVE.txt" } |
      Sort-Object -Property LastWriteTimeUtc -Descending
  )

  if ($oldIndexCandidates.Length -gt 0) {
    $prevIndex = $oldIndexCandidates[0].FullName
  }

  $currentPaths = $recordsSorted | ForEach-Object { $_.Path }
    




  $prevPaths = @()
  if ($prevIndex) {
    try {
      # Parse simple: extraer líneas PATH..............:
      $prevLines = Get-Content -LiteralPath $prevIndex -Encoding UTF8 -ErrorAction Stop
      $prevPaths = $prevLines |
        Where-Object { $_ -like "PATH..............:*" } |
        ForEach-Object { ($_ -split "PATH..............:\s*",2)[1].Trim() } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    } catch {
      $prevPaths = @()
    }
  }

  # HashSet: en PowerShell, pasar un array al ctor puede expandirse como múltiples args.
  # Solución estable: instanciar vacío y agregar elementos.
  $setPrev = [System.Collections.Generic.HashSet[string]]::new()
  foreach ($p in @($prevPaths)) { [void]$setPrev.Add([string]$p) }

  $setCurr = [System.Collections.Generic.HashSet[string]]::new()
  foreach ($p in @($currentPaths)) { [void]$setCurr.Add([string]$p) }

  $newFiles = New-Object System.Collections.Generic.List[string]
  foreach ($p in $setCurr) { if (-not $setPrev.Contains($p)) { $newFiles.Add($p) | Out-Null } }
  $deletedFiles = New-Object System.Collections.Generic.List[string]
  foreach ($p in $setPrev) { if (-not $setCurr.Contains($p)) { $deletedFiles.Add($p) | Out-Null } }

  # Modified basado en metadata (size+modified) comparando contra prevIndex es complejo sin parse completo.
  # MVP: marcar MODIFIED como vacío y declarar limitación.
  $modifiedFiles = @()

  $liteLines = New-Object System.Collections.Generic.List[string]
  $liteLines.Add("==========") | Out-Null
  $liteLines.Add("RADAR_LITE.ACTIVE") | Out-Null
  $liteLines.Add("==========") | Out-Null
  $liteLines.Add("") | Out-Null
  $liteLines.Add("TIMESTAMP.........: $ts (America/Santiago)") | Out-Null
  $liteLines.Add("ROOT..............: $rootFull") | Out-Null
  $liteLines.Add("TOTAL_FILES.......: $($recordsSorted.Count)") | Out-Null
  $liteLines.Add("DIFF_BASE.........: $([string]::IsNullOrWhiteSpace($prevIndex) ? 'NONE' : $prevIndex)") | Out-Null
  $liteLines.Add("") | Out-Null
  $liteLines.Add("NOTA..............: MODIFIED_FILES (MVP) no se calcula en esta versión; solo NEW/DELETED por paths.") | Out-Null
  $liteLines.Add("POINTER_INDEX......: $($active.Index)") | Out-Null
  $liteLines.Add("POINTER_CORE.......: $($active.Core)") | Out-Null
  $liteLines.Add("POINTER_FULL.......: $($active.Full)") | Out-Null
  $liteLines.Add("") | Out-Null

  $liteLines.Add("----------") | Out-Null
  $liteLines.Add("NEW_FILES") | Out-Null
  $liteLines.Add("----------") | Out-Null
  foreach ($p in ($newFiles | Sort-Object)) { $liteLines.Add($p) | Out-Null }
  $liteLines.Add("") | Out-Null

  $liteLines.Add("----------") | Out-Null
  $liteLines.Add("MODIFIED_FILES") | Out-Null
  $liteLines.Add("----------") | Out-Null
  foreach ($p in $modifiedFiles) { $liteLines.Add($p) | Out-Null }
  $liteLines.Add("") | Out-Null

  $liteLines.Add("----------") | Out-Null
  $liteLines.Add("DELETED_FILES") | Out-Null
  $liteLines.Add("----------") | Out-Null
  foreach ($p in ($deletedFiles | Sort-Object)) { $liteLines.Add($p) | Out-Null }
  $liteLines.Add("") | Out-Null

  [System.IO.File]::WriteAllLines($active.Lite, $liteLines, [System.Text.Encoding]::UTF8)

  # ============================
  # 08.00_SEGMENTACION 8MB
  # ============================

  foreach ($p in @($active.Lite, $active.Index, $active.Core, $active.Full)) {
    Split-IfOverSize -ActivePath $p
  }

  # ============================
  # 09.00_FINAL VALIDATION (OK/FAIL real)
  # ============================

  if (-not (Test-ValidateOutputsExist -ActivePaths $active)) {
    Write-Error "FAIL: Outputs activos faltantes o vacíos."
    exit 1
  }

  Write-Output "OK: RADAR generado correctamente."
  Write-Output "OUTPUTS:"
  Write-Output " - $($active.Lite)"
  Write-Output " - $($active.Index)"
  Write-Output " - $($active.Core)"
  Write-Output " - $($active.Full)"
  exit 0

} catch {
  Write-Error ("FAIL: " + $_.Exception.Message)
  exit 1
}