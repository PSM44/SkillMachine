# Validate-UsecaseRegistrySchema.ps1
# Purpose: Enforce minimal schema for 90.USECASE\USECASE.REGISTRY.json early (pre-commit).
# PS 5.1 compatible. Exit codes: 0 OK, 1 FAIL

$ErrorActionPreference = "Stop"

function Fail([string]$m){ Write-Host "FAIL: $m"; exit 1 }
function Warn([string]$m){ Write-Host "WARN: $m" }

Write-Host "VALIDATION: usecase registry schema"

$RepoRoot = [System.IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot "..\..\..")
)
$regPath = Join-Path $RepoRoot "90.USECASE\USECASE.REGISTRY.json"
if (-not (Test-Path -LiteralPath $regPath)) { Fail "Missing registry: $regPath" }

try {
  $registry = (Get-Content -LiteralPath $regPath -Raw -Encoding utf8) | ConvertFrom-Json
} catch {
  Fail ("Invalid JSON registry: " + $_.Exception.Message)
}

# build_policy required (your BUILD expects it)
if ($null -eq $registry.PSObject.Properties["build_policy"] -or $null -eq $registry.build_policy) {
  Fail "USECASE.REGISTRY.json missing build_policy"
}

$maxDelivery = $null
if ($registry.build_policy.PSObject.Properties["max_delivery_files_per_usecase"]) {
  $maxDelivery = [int]$registry.build_policy.max_delivery_files_per_usecase
}

if ($null -eq $registry.PSObject.Properties["usecases"] -or $null -eq $registry.usecases) {
  Fail "USECASE.REGISTRY.json missing usecases"
}

function SafeArray([object]$obj,[string]$prop){
  if ($null -eq $obj) { return @() }
  $p = $obj.PSObject.Properties[$prop]
  if ($null -eq $p) { return @() }
  if ($null -eq $obj.$prop) { return @() }
  # normalize to array
  if ($obj.$prop -is [System.Array]) { return @($obj.$prop) }
  return @($obj.$prop)
}

function HasProp([object]$obj,[string]$prop){
  return ($null -ne $obj -and $null -ne $obj.PSObject.Properties[$prop])
}

function Test-RelativeRegistryPath([string]$pathValue){
  if ([string]::IsNullOrWhiteSpace($pathValue)) { return $false }
  if ($pathValue -match '^[A-Za-z]:\\') { return $false }
  if ($pathValue -match '^\.\.?[\\/]') { return $false }
  if ($pathValue -match '[\\/]\.\.([\\/]|$)') { return $false }
  if ($pathValue -match '^\.\.($|[\\/])') { return $false }
  return $true
}

function Validate-CompiledContract {
  param(
    [Parameter(Mandatory=$true)]$Item,
    [Parameter(Mandatory=$true)][string]$Name,
    [Parameter(Mandatory=$true)][AllowEmptyCollection()][string[]]$AllowedSourcePaths = @(),
    [Parameter(Mandatory=$true)][hashtable]$GlobalCompiledNames
  )

  foreach ($req in @('compiled_output_enabled','compiled_output_file','compiled_format_version','source_entries','upload_package_model')) {
    if (-not (HasProp $Item $req)) {
      $script:failCount++
      Write-Host ("FAIL: {0} missing compiled contract property: {1}" -f $Name,$req)
    }
  }

  if (-not (HasProp $Item 'compiled_output_enabled')) { return }
  if ($Item.compiled_output_enabled -isnot [bool]) {
    $script:failCount++
    Write-Host ("FAIL: {0} compiled_output_enabled must be boolean" -f $Name)
    return
  }
  if ([bool]$Item.compiled_output_enabled -ne $true) {
    $script:failCount++
    Write-Host ("FAIL: {0} compiled_output_enabled must be true for direct-source contract" -f $Name)
  }
  if (-not (HasProp $Item 'upload_package_model') -or [string]$Item.upload_package_model -ne 'SINGLE_COMPILED_FILE') {
    $script:failCount++
    Write-Host ("FAIL: {0} upload_package_model must be SINGLE_COMPILED_FILE" -f $Name)
  }

  $compiledOutputFile = ''
  if (HasProp $Item 'compiled_output_file') {
    $compiledOutputFile = [string]$Item.compiled_output_file
    if ([string]::IsNullOrWhiteSpace($compiledOutputFile) -or -not $compiledOutputFile.EndsWith('.COMPILED.txt')) {
      $script:failCount++
      Write-Host ("FAIL: {0} compiled_output_file must end with .COMPILED.txt" -f $Name)
    }
    if (-not (Test-RelativeRegistryPath $compiledOutputFile)) {
      $script:failCount++
      Write-Host ("FAIL: {0} compiled_output_file must be target-relative and traversal-free: {1}" -f $Name,$compiledOutputFile)
    }
  }

  if ((HasProp $Item 'compiled_format_version') -and (@('v1','v2') -notcontains ([string]$Item.compiled_format_version))) {
    $script:failCount++
    Write-Host ("FAIL: {0} compiled_format_version must be v1 or v2" -f $Name)
  }

  $sourceEntries = @(SafeArray $Item 'source_entries')
  if ($sourceEntries.Count -eq 0) {
    $script:failCount++
    Write-Host ("FAIL: {0} source_entries must be a non-empty array" -f $Name)
  }

  $sourcePaths = @($sourceEntries | ForEach-Object { [string]$_.source_path })
  $sourceDupes = @($sourcePaths | Group-Object | Where-Object { $_.Count -gt 1 })
  if ($sourceDupes.Count -gt 0) {
    $script:failCount++
    Write-Host ("FAIL: {0} source_entries contains duplicate source_path values: {1}" -f $Name, (($sourceDupes | ForEach-Object { $_.Name }) -join ', '))
  }

  foreach ($entry in @($sourceEntries)) {
    $sourcePath = [string]$entry.source_path
    if (-not (Test-RelativeRegistryPath $sourcePath)) {
      $script:failCount++
      Write-Host ("FAIL: {0} source_entries contains invalid relative path: {1}" -f $Name,$sourcePath)
      continue
    }
    if ($sourcePath -eq $compiledOutputFile) {
      $script:failCount++
      Write-Host ("FAIL: {0} source_entries must not include its own compiled output file" -f $Name)
    }
    if (-not (HasProp $entry 'source_labels') -or @($entry.source_labels).Count -eq 0) {
      $script:failCount++
      Write-Host ("FAIL: {0} source_entries item missing source_labels: {1}" -f $Name,$sourcePath)
    }
    if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot ($sourcePath -replace '/', '\')) -PathType Leaf)) {
      $script:failCount++
      Write-Host ("FAIL: {0} source_entries references missing source file: {1}" -f $Name,$sourcePath)
    }
    if ($AllowedSourcePaths.Count -gt 0 -and @($AllowedSourcePaths | Where-Object { $_ -eq $sourcePath }).Count -eq 0) {
      $script:failCount++
      Write-Host ("FAIL: {0} source_entries contains unsupported source path: {1}" -f $Name,$sourcePath)
    }
  }

  if (-not [string]::IsNullOrWhiteSpace($compiledOutputFile)) {
    $compiledKey = $compiledOutputFile.ToUpperInvariant()
    if ($GlobalCompiledNames.ContainsKey($compiledKey)) {
      $script:failCount++
      Write-Host ("FAIL: compiled_output_file must be globally unique: {0} shared by {1} and {2}" -f $compiledOutputFile,$GlobalCompiledNames[$compiledKey],$Name)
    }
    else {
      $GlobalCompiledNames[$compiledKey] = $Name
    }
  }
}

$script:failCount = 0
$warnCount = 0
$compiledOutputNames = @{}

# Support package contract.
$supportNames = @{}
foreach ($sp in @(SafeArray $registry "support_packages")) {
  if (-not (HasProp $sp "name") -or [string]::IsNullOrWhiteSpace([string]$sp.name)) {
    $failCount++
    Write-Host "FAIL: support package missing name"
    continue
  }

  $spName = [string]$sp.name
  $key = $spName.ToUpperInvariant()
  if ($supportNames.ContainsKey($key)) {
    $failCount++
    Write-Host ("FAIL: duplicate support package name: {0}" -f $spName)
  } else {
    $supportNames[$key] = $true
  }

  foreach ($req in @("package_type","lifecycle_status","build_enabled","generated_output_target","primary_usecase","source_of_truth")) {
    if (-not (HasProp $sp $req)) {
      $failCount++
      Write-Host ("FAIL: support package {0} missing required property: {1}" -f $spName,$req)
    }
  }

  if ((HasProp $sp "package_type") -and [string]$sp.package_type -ne "SUPPORT_PACKAGE") {
    $failCount++
    Write-Host ("FAIL: support package {0} has invalid package_type: {1}" -f $spName,$sp.package_type)
  }

  if ((HasProp $sp "primary_usecase") -and [bool]$sp.primary_usecase -ne $false) {
    $failCount++
    Write-Host ("FAIL: support package {0} must have primary_usecase=false" -f $spName)
  }

  if ($spName -eq "05.SKILLSMACHINE_UPDATE") {
    if ((HasProp $sp "package_type") -and [string]$sp.package_type -ne "SUPPORT_PACKAGE") {
      $failCount++
      Write-Host ("FAIL: support package {0} must have package_type=SUPPORT_PACKAGE" -f $spName)
    }
    if ((HasProp $sp "build_enabled") -and [bool]$sp.build_enabled -ne $true) {
      $failCount++
      Write-Host ("FAIL: support package {0} must have build_enabled=true" -f $spName)
    }
    if ((HasProp $sp "generated_output_target") -and [bool]$sp.generated_output_target -ne $true) {
      $failCount++
      Write-Host ("FAIL: support package {0} must have generated_output_target=true" -f $spName)
    }
    if ((HasProp $sp "source_of_truth") -and [string]$sp.source_of_truth -ne "CORE_ONLY") {
      $failCount++
      Write-Host ("FAIL: support package {0} must have source_of_truth=CORE_ONLY" -f $spName)
    }
    if (-not (HasProp $sp "source_directory") -or [string]$sp.source_directory -ne "SyS/A_Tools/Update/SupportPackage") {
      $failCount++
      Write-Host ("FAIL: support package {0} must declare source_directory=SyS/A_Tools/Update/SupportPackage" -f $spName)
    }
    if (-not (HasProp $sp "target_directory") -or [string]$sp.target_directory -ne "90.USECASE/05.SKILLSMACHINE_UPDATE") {
      $failCount++
      Write-Host ("FAIL: support package {0} must declare target_directory=90.USECASE/05.SKILLSMACHINE_UPDATE" -f $spName)
    }

    if (HasProp $sp "copied_files") {
      $failCount++
      Write-Host ("FAIL: support package {0} must not use copied_files under single compiled contract" -f $spName)
    }
    if (HasProp $sp "delivery_files") {
      $failCount++
      Write-Host ("FAIL: support package {0} must not use delivery_files under single compiled contract" -f $spName)
    }
    if (HasProp $sp "bundle_definitions") {
      $failCount++
      Write-Host ("FAIL: support package {0} must not use bundle_definitions under single compiled contract" -f $spName)
    }
  }

  [string[]]$supportAllowedCompiledSources = @()
  Validate-CompiledContract -Item $sp -Name $spName -AllowedSourcePaths $supportAllowedCompiledSources -GlobalCompiledNames $compiledOutputNames
}
foreach ($uc in @(SafeArray $registry "usecases")) {

  if (-not (HasProp $uc "name") -or -not [string]$uc.name) { $failCount++; Write-Host "FAIL: usecase missing name"; continue }
  $name = [string]$uc.name

  # required by BUILD strict reads (we already hardened some, but keep contract)
  foreach ($req in @("version")) {
    if (-not (HasProp $uc $req)) {
      $failCount++
      Write-Host ("FAIL: {0} missing required property: {1}" -f $name,$req)
    } elseif ($null -eq $uc.$req) {
      $failCount++
      Write-Host ("FAIL: {0} has null required property: {1}" -f $name,$req)
    }
  }

  # array-ish fields must be arrays or scalars convertible, but not null
  foreach ($legacyProp in @("bundle_definitions","prompt_files","menu_files","preserve_files","delivery_files_extra","copied_files","delivery_files")) {
    if (HasProp $uc $legacyProp) {
      $failCount++
      Write-Host ("FAIL: {0} must not use legacy generated-target property under single compiled contract: {1}" -f $name,$legacyProp)
    }
  }

foreach ($opt in @()) {
  if (HasProp $uc $opt) {
    # If value is truly $null, SafeArray returns @() AND direct value equals $null.
    $val = $uc.$opt
    $arr = @(SafeArray $uc $opt)
    if ($null -eq $val) {
      $failCount++
      Write-Host ("FAIL: {0} has null optional array: {1} (must be [] if empty)" -f $name,$opt)
    }
  }
}

  # if delivery_files_extra present and maxDelivery known, enforce cap (defensive)
  foreach ($pname in @("source_entries")) {
    if (HasProp $uc $pname -and $null -ne $uc.$pname) {
      foreach ($x in @(SafeArray $uc $pname)) {
        $s = [string]$x.source_path
        if ($s -match '^[A-Za-z]:\\') { $failCount++; Write-Host ("FAIL: {0} {1} contains absolute path: {2}" -f $name,$pname,$s) }
        if ($s -match '\.\.') { $failCount++; Write-Host ("FAIL: {0} {1} contains traversal '..': {2}" -f $name,$pname,$s) }
      }
    }
  }

  if (HasProp $uc "source_directory") {
    $sourceDirectory = [string]$uc.source_directory
    if ([string]::IsNullOrWhiteSpace($sourceDirectory)) {
      $failCount++
      Write-Host ("FAIL: {0} source_directory must not be blank" -f $name)
    } else {
      if ($sourceDirectory -match '^[A-Za-z]:\\') { $failCount++; Write-Host ("FAIL: {0} source_directory contains absolute path: {1}" -f $name,$sourceDirectory) }
      if ($sourceDirectory -match '\.\.') { $failCount++; Write-Host ("FAIL: {0} source_directory contains traversal '..': {1}" -f $name,$sourceDirectory) }
    }
  }

  [string[]]$allowedCompiledSources = @()
  Validate-CompiledContract -Item $uc -Name $name -AllowedSourcePaths $allowedCompiledSources -GlobalCompiledNames $compiledOutputNames

  if ($name -eq "01.NEW_PROJECT") {
    if (-not (HasProp $uc "source_directory") -or [string]$uc.source_directory -ne "SyS/A_Tools/UseCaseSources/01.NewProject") {
      $failCount++
      Write-Host "FAIL: 01.NEW_PROJECT must declare source_directory=SyS/A_Tools/UseCaseSources/01.NewProject"
    }
    if (HasProp $uc "copied_files") {
      $failCount++
      Write-Host "FAIL: 01.NEW_PROJECT must not use copied_files under direct source contract"
    }
  }

  if ($name -eq "02.SESSION_CLOSE") {
    if (-not (HasProp $uc "source_directory") -or [string]$uc.source_directory -ne "SyS/A_Tools/UseCaseSources/02.SessionClose") {
      $failCount++
      Write-Host "FAIL: 02.SESSION_CLOSE must declare source_directory=SyS/A_Tools/UseCaseSources/02.SessionClose"
    }
    if (HasProp $uc "copied_files") {
      $failCount++
      Write-Host "FAIL: 02.SESSION_CLOSE must not use copied_files under direct source contract"
    }
  }

  if ($name -eq "03.SESSION_CONTINUE") {
    if (-not (HasProp $uc "source_directory") -or [string]$uc.source_directory -ne "SyS/A_Tools/UseCaseSources/03.SessionContinue") {
      $failCount++
      Write-Host "FAIL: 03.SESSION_CONTINUE must declare source_directory=SyS/A_Tools/UseCaseSources/03.SessionContinue"
    }
    if (HasProp $uc "copied_files") {
      $failCount++
      Write-Host "FAIL: 03.SESSION_CONTINUE must not use copied_files under direct source contract"
    }
  }

  if ($name -eq "04.REPOSITORY_STRUCTURE_REPAIR") {
    if (-not (HasProp $uc "source_directory") -or [string]$uc.source_directory -ne "SyS/A_Tools/UseCaseSources/04.RepositoryStructureRepair") {
      $failCount++
      Write-Host "FAIL: 04.REPOSITORY_STRUCTURE_REPAIR must declare source_directory=SyS/A_Tools/UseCaseSources/04.RepositoryStructureRepair"
    }
    if (HasProp $uc "copied_files") {
      $failCount++
      Write-Host "FAIL: 04.REPOSITORY_STRUCTURE_REPAIR must not use copied_files under direct source contract"
    }
    if (HasProp $uc "preserve_files" -or HasProp $uc "delivery_files_extra") {
      $failCount++
      Write-Host "FAIL: 04.REPOSITORY_STRUCTURE_REPAIR must not use preserve_files or delivery_files_extra under direct source contract"
    }
  }
}

if ($failCount -gt 0) { exit 1 }
Write-Host "OK: usecase registry schema validation passed"
# BEGIN MB-SM-067B-D3R3 SOURCE DIRECTORY VALIDATION
$d3RequiredSources = @(
    [pscustomobject]@{
        Name = "01.NEW_PROJECT"
        SourceDirectory = "SyS/A_Tools/UseCaseSources/01.NewProject"
        RequiredFiles = @(
            "PROMPT.NEW_PROJECT.txt",
            "README.UPLOAD_THIS_USECASE.txt",
            "SKILL_SET.MANIFEST.txt"
        )
    },
    [pscustomobject]@{
        Name = "02.SESSION_CLOSE"
        SourceDirectory = "SyS/A_Tools/UseCaseSources/02.SessionClose"
        RequiredFiles = @(
            "PROMPT.SESSION_CLOSE.txt",
            "README.UPLOAD_THIS_USECASE.txt",
            "RUNBOOK.SESSION_CLOSE.HARDENED.txt",
            "SKILL_SET.MANIFEST.txt"
        )
    }
)

$d3Registry = Get-Content -LiteralPath $regPath -Raw | ConvertFrom-Json
$d3Usecases = @()

if ($d3Registry.PSObject.Properties["usecases"]) {
    $d3Usecases = @($d3Registry.usecases)
}
elseif ($d3Registry.PSObject.Properties["use_cases"]) {
    $d3Usecases = @($d3Registry.use_cases)
}
else {
    Write-Host "FAIL: D3R3 registry usecase collection not found"
    exit 1
}

foreach ($d3Required in $d3RequiredSources) {
    $d3Matches = @(
        $d3Usecases | Where-Object {
            (
                $_.PSObject.Properties["name"] -and
                [string]$_.name -eq $d3Required.Name
            ) -or (
                $_.PSObject.Properties["usecase"] -and
                [string]$_.usecase -eq $d3Required.Name
            ) -or (
                $_.PSObject.Properties["id"] -and
                [string]$_.id -eq $d3Required.Name
            )
        }
    )

    if ($d3Matches.Count -ne 1) {
        Write-Host "FAIL: D3R3 $($d3Required.Name) must exist exactly once"
        exit 1
    }

    $d3Usecase = $d3Matches[0]

    if (
        -not $d3Usecase.PSObject.Properties["source_directory"] -or
        [string]$d3Usecase.source_directory -ne $d3Required.SourceDirectory
    ) {
        Write-Host "FAIL: D3R3 $($d3Required.Name) must declare source_directory=$($d3Required.SourceDirectory)"
        exit 1
    }

    $d3SourcePath = Join-Path $RepoRoot (
        $d3Required.SourceDirectory -replace '/', '\'
    )

    if (-not (Test-Path -LiteralPath $d3SourcePath -PathType Container)) {
        Write-Host "FAIL: D3R3 canonical source directory missing: $($d3Required.SourceDirectory)"
        exit 1
    }

    foreach ($d3File in $d3Required.RequiredFiles) {
        $d3RequiredPath = Join-Path $d3SourcePath $d3File

        if (-not (Test-Path -LiteralPath $d3RequiredPath -PathType Leaf)) {
            Write-Host "FAIL: D3R3 canonical source file missing: $($d3Required.SourceDirectory)/$d3File"
            exit 1
        }
    }
}
# END MB-SM-067B-D3R3 SOURCE DIRECTORY VALIDATION

exit 0
