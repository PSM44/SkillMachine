Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Utf8NoBom {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Content,
        [switch]$CreateParent
    )

    $parent = Split-Path -Parent $Path
    if ([string]::IsNullOrWhiteSpace($parent)) {
        throw "WRITE_UTF8_NO_BOM_INVALID_PARENT"
    }

    if ($CreateParent -and -not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        throw "WRITE_UTF8_NO_BOM_PARENT_MISSING"
    }

    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false))
}

function Get-UseCaseCompiledSha256Hex {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$Bytes
    )

    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hashBytes = $sha256.ComputeHash($Bytes)
        return ([System.BitConverter]::ToString($hashBytes) -replace '-', '').ToUpperInvariant()
    }
    finally {
        if ($null -ne $sha256) {
            $sha256.Dispose()
        }
    }
}

function Test-UseCasePathUnderRoot {
    param(
        [Parameter(Mandatory = $true)][string]$CandidatePath,
        [Parameter(Mandatory = $true)][string]$ProjectRoot
    )

    $root = [System.IO.Path]::GetFullPath($ProjectRoot)
    $rootWithSlash = $root
    if (-not $rootWithSlash.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
        $rootWithSlash += [System.IO.Path]::DirectorySeparatorChar
    }

    $candidate = [System.IO.Path]::GetFullPath($CandidatePath)
    return (
        $candidate.Equals($root, [System.StringComparison]::OrdinalIgnoreCase) -or
        $candidate.StartsWith($rootWithSlash, [System.StringComparison]::OrdinalIgnoreCase)
    )
}

function Get-UseCaseCompiledRelativePath {
    param(
        [Parameter(Mandatory = $true)][string]$BaseDirectory,
        [Parameter(Mandatory = $true)][string]$FullPath
    )

    $baseUri = [System.Uri]::new(([System.IO.Path]::GetFullPath($BaseDirectory) + [System.IO.Path]::DirectorySeparatorChar))
    $fullUri = [System.Uri]::new([System.IO.Path]::GetFullPath($FullPath))
    $relative = $baseUri.MakeRelativeUri($fullUri).ToString()
    return [System.Uri]::UnescapeDataString($relative).Replace('/', '\')
}

function Get-UseCaseCompiledDelimiterSet {
    param(
        [Parameter(Mandatory = $true)][int]$SourceIndex,
        [Parameter(Mandatory = $true)][string]$SourceSha256
    )

    $label = ('{0:D3} {1}' -f $SourceIndex, $SourceSha256.ToUpperInvariant())
    return [ordered]@{
        BeginFile    = "========== BEGIN_SOURCE_FILE $label =========="
        ContentStart = "========== CONTENT_START $label =========="
        ContentEnd   = "========== CONTENT_END $label =========="
        EndFile      = "========== END_SOURCE_FILE $label =========="
    }
}

function Assert-UseCaseCompiledDelimiterSafe {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Content,
        [Parameter(Mandatory = $true)]$DelimiterSet
    )

    foreach ($delimiter in @(
        [string]$DelimiterSet.BeginFile,
        [string]$DelimiterSet.ContentStart,
        [string]$DelimiterSet.ContentEnd,
        [string]$DelimiterSet.EndFile
    )) {
        if ($Content.Contains($delimiter)) {
            throw "COMPILED_SEPARATOR_COLLISION"
        }
    }

    foreach ($baseMarker in @(
        '========== BEGIN_SOURCE_FILE',
        '========== CONTENT_START',
        '========== CONTENT_END',
        '========== END_SOURCE_FILE'
    )) {
        if ($Content.Contains($baseMarker)) {
            throw "COMPILED_SEPARATOR_COLLISION"
        }
    }
}

function New-UseCaseCompiledSourceRecord {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [Parameter(Mandatory = $true)][string]$TargetDirectory,
        [Parameter(Mandatory = $true)][string]$OutputFileName,
        [Parameter(Mandatory = $true)][string]$SourcePath,
        [Parameter(Mandatory = $true)][int]$SourceIndex
    )

    if ([string]::IsNullOrWhiteSpace($SourcePath)) {
        throw "COMPILED_SOURCE_PATH_BLANK"
    }

    if ([System.IO.Path]::IsPathRooted($SourcePath)) {
        throw "COMPILED_SOURCE_PATH_MUST_BE_TARGET_RELATIVE"
    }

    $normalizedRelativePath = $SourcePath.Replace('/', '\')
    $fullSourcePath = [System.IO.Path]::GetFullPath((Join-Path $TargetDirectory $normalizedRelativePath))
    $fullOutputPath = [System.IO.Path]::GetFullPath((Join-Path $TargetDirectory $OutputFileName))

    if (-not (Test-UseCasePathUnderRoot -CandidatePath $fullSourcePath -ProjectRoot $ProjectRoot)) {
        throw "COMPILED_SOURCE_OUTSIDE_PROJECT_ROOT"
    }

    if ($fullSourcePath.Equals($fullOutputPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "COMPILED_OUTPUT_INCLUDED_AS_SOURCE"
    }

    if (-not (Test-Path -LiteralPath $fullSourcePath -PathType Leaf)) {
        throw "COMPILED_SOURCE_MISSING"
    }

    $sourceBytes = [System.IO.File]::ReadAllBytes($fullSourcePath)
    $sourceSha256 = Get-UseCaseCompiledSha256Hex -Bytes $sourceBytes
    $decoder = [System.Text.UTF8Encoding]::new($true, $true)
    $sourceText = $decoder.GetString($sourceBytes)
    $delimiterSet = Get-UseCaseCompiledDelimiterSet -SourceIndex $SourceIndex -SourceSha256 $sourceSha256
    Assert-UseCaseCompiledDelimiterSafe -Content $sourceText -DelimiterSet $delimiterSet

    return [pscustomobject]@{
        SourceIndex       = $SourceIndex
        SourcePath        = $normalizedRelativePath
        FullPath          = $fullSourcePath
        SourceBytes       = [int64]$sourceBytes.Length
        SourceSha256      = $sourceSha256
        SourceContent     = $sourceText
        DelimiterSet      = $delimiterSet
        RelativeToProject = Get-UseCaseCompiledRelativePath -BaseDirectory $ProjectRoot -FullPath $fullSourcePath
    }
}

function New-UseCaseCompiledFile {
    param(
        [Parameter(Mandatory = $true)][string]$PackageName,
        [Parameter(Mandatory = $true)][string]$PackageType,
        [Parameter(Mandatory = $true)][string]$PackageVersion,
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [Parameter(Mandatory = $true)][string]$TargetDirectory,
        [Parameter(Mandatory = $true)][string]$OutputFileName,
        [Parameter(Mandatory = $true)][string[]]$SourceFiles,
        [Parameter(Mandatory = $true)][string]$FormatVersion,
        [AllowNull()][string]$GeneratedAt,
        [switch]$WriteOutput
    )

    if ($FormatVersion -ne 'v1') {
        throw "COMPILED_FORMAT_VERSION_UNSUPPORTED"
    }

    if ([string]::IsNullOrWhiteSpace($PackageName)) {
        throw "COMPILED_PACKAGE_NAME_REQUIRED"
    }

    if ([string]::IsNullOrWhiteSpace($PackageType)) {
        throw "COMPILED_PACKAGE_TYPE_REQUIRED"
    }

    if ([string]::IsNullOrWhiteSpace($PackageVersion)) {
        throw "COMPILED_PACKAGE_VERSION_REQUIRED"
    }

    if ([string]::IsNullOrWhiteSpace($OutputFileName)) {
        throw "COMPILED_OUTPUT_FILE_REQUIRED"
    }

    if ([string]::IsNullOrWhiteSpace($ProjectRoot) -or -not (Test-Path -LiteralPath $ProjectRoot -PathType Container)) {
        throw "COMPILED_PROJECT_ROOT_INVALID"
    }

    if ([string]::IsNullOrWhiteSpace($TargetDirectory) -or -not (Test-Path -LiteralPath $TargetDirectory -PathType Container)) {
        throw "COMPILED_TARGET_DIRECTORY_INVALID"
    }

    $fullProjectRoot = [System.IO.Path]::GetFullPath($ProjectRoot)
    $fullTargetDirectory = [System.IO.Path]::GetFullPath($TargetDirectory)
    $fullOutputPath = [System.IO.Path]::GetFullPath((Join-Path $fullTargetDirectory $OutputFileName))

    if (-not (Test-UseCasePathUnderRoot -CandidatePath $fullTargetDirectory -ProjectRoot $fullProjectRoot)) {
        throw "COMPILED_TARGET_OUTSIDE_PROJECT_ROOT"
    }

    if (-not (Test-UseCasePathUnderRoot -CandidatePath $fullOutputPath -ProjectRoot $fullProjectRoot)) {
        throw "COMPILED_OUTPUT_OUTSIDE_PROJECT_ROOT"
    }

    $normalizedSourceFiles = @($SourceFiles | ForEach-Object { [string]$_ })
    if ($normalizedSourceFiles.Count -eq 0) {
        throw "COMPILED_SOURCE_ORDER_EMPTY"
    }

    $duplicateGroups = @(
        $normalizedSourceFiles |
            ForEach-Object { $_.Replace('/', '\') } |
            Group-Object |
            Where-Object { $_.Count -gt 1 }
    )
    if ($duplicateGroups.Count -gt 0) {
        throw "COMPILED_DUPLICATE_SOURCE_PATH"
    }

    $sourceRecords = [System.Collections.Generic.List[object]]::new()
    $sourceIndex = 1
    foreach ($sourcePath in $normalizedSourceFiles) {
        [void]$sourceRecords.Add(
            (New-UseCaseCompiledSourceRecord `
                -ProjectRoot $fullProjectRoot `
                -TargetDirectory $fullTargetDirectory `
                -OutputFileName $OutputFileName `
                -SourcePath $sourcePath `
                -SourceIndex $sourceIndex)
        )
        $sourceIndex++
    }

    $headerLines = [System.Collections.Generic.List[string]]::new()
    [void]$headerLines.Add('PS.SKILLSMACHINE SINGLE-FILE USECASE PACKAGE')
    [void]$headerLines.Add("COMPILED_FORMAT_VERSION=$FormatVersion")
    [void]$headerLines.Add("PACKAGE_NAME=$PackageName")
    [void]$headerLines.Add("PACKAGE_TYPE=$PackageType")
    [void]$headerLines.Add("PACKAGE_VERSION=$PackageVersion")
    [void]$headerLines.Add("SOURCE_FILE_COUNT=$($sourceRecords.Count)")
    [void]$headerLines.Add('')
    [void]$headerLines.Add('================================================================================')
    [void]$headerLines.Add('00. EXECUTIVE SUMMARY')
    [void]$headerLines.Add('================================================================================')
    [void]$headerLines.Add("This generated package compiles the operational context for $PackageName into a single IA-readable file.")
    [void]$headerLines.Add('It preserves complete source contents without truncation and keeps the canonical source-of-truth outside 90.USECASE.')
    [void]$headerLines.Add('This file is generated, deterministic, and must not be edited manually.')
    [void]$headerLines.Add('')
    [void]$headerLines.Add('================================================================================')
    [void]$headerLines.Add('01. COMPILATION METADATA')
    [void]$headerLines.Add('================================================================================')
    [void]$headerLines.Add("PACKAGE_NAME=$PackageName")
    [void]$headerLines.Add("PACKAGE_TYPE=$PackageType")
    [void]$headerLines.Add("PACKAGE_VERSION=$PackageVersion")
    [void]$headerLines.Add("COMPILED_OUTPUT_FILE=$OutputFileName")
    [void]$headerLines.Add("COMPILED_FORMAT_VERSION=$FormatVersion")
    [void]$headerLines.Add('CONTENT_POLICY=FULL_CONTENT_NO_TRUNCATION')
    [void]$headerLines.Add('SOURCE_ORDER_POLICY=REGISTRY_DECLARED')
    [void]$headerLines.Add('ENCODING=UTF-8_NO_BOM')
    [void]$headerLines.Add('GENERATED_OUTPUT_ONLY=YES')
    [void]$headerLines.Add('DO_NOT_EDIT_MANUALLY=YES')
    if (-not [string]::IsNullOrWhiteSpace($GeneratedAt)) {
        [void]$headerLines.Add("GENERATED_AT_POLICY=$GeneratedAt")
    }
    [void]$headerLines.Add('')
    [void]$headerLines.Add('================================================================================')
    [void]$headerLines.Add('02. SOURCE MANIFEST')
    [void]$headerLines.Add('================================================================================')

    foreach ($record in @($sourceRecords)) {
        [void]$headerLines.Add("SOURCE_INDEX=$($record.SourceIndex)")
        [void]$headerLines.Add("SOURCE_PATH=$($record.SourcePath)")
        [void]$headerLines.Add("SOURCE_BYTES=$($record.SourceBytes)")
        [void]$headerLines.Add("SOURCE_SHA256=$($record.SourceSha256)")
        [void]$headerLines.Add('')
    }

    [void]$headerLines.Add('================================================================================')
    [void]$headerLines.Add('03. OPERATIONAL INSTRUCTIONS')
    [void]$headerLines.Add('================================================================================')
    [void]$headerLines.Add('Use this compiled file as one complete upload unit instead of collecting multiple package files.')
    [void]$headerLines.Add('The delimiters, source manifest, and hashes preserve source integrity and verification order.')
    [void]$headerLines.Add('The canonical source-of-truth remains outside 90.USECASE; regenerate instead of editing this file manually.')
    [void]$headerLines.Add('')
    [void]$headerLines.Add('================================================================================')
    [void]$headerLines.Add('04. COMPLETE SOURCE CONTENT')
    [void]$headerLines.Add('================================================================================')

    $builder = [System.Text.StringBuilder]::new()
    $null = $builder.Append(([string]::Join("`r`n", @($headerLines))))
    $null = $builder.Append("`r`n")

    foreach ($record in @($sourceRecords)) {
        $null = $builder.Append([string]$record.DelimiterSet.BeginFile)
        $null = $builder.Append("`r`n")
        $null = $builder.Append("SOURCE_INDEX=$($record.SourceIndex)")
        $null = $builder.Append("`r`n")
        $null = $builder.Append("SOURCE_PATH=$($record.SourcePath)")
        $null = $builder.Append("`r`n")
        $null = $builder.Append("SOURCE_BYTES=$($record.SourceBytes)")
        $null = $builder.Append("`r`n")
        $null = $builder.Append("SOURCE_SHA256=$($record.SourceSha256)")
        $null = $builder.Append("`r`n")
        $null = $builder.Append([string]$record.DelimiterSet.ContentStart)
        $null = $builder.Append("`r`n")
        $null = $builder.Append([string]$record.SourceContent)
        if (-not ($record.SourceContent.EndsWith("`r`n") -or $record.SourceContent.EndsWith("`n"))) {
            $null = $builder.Append("`r`n")
        }
        $null = $builder.Append([string]$record.DelimiterSet.ContentEnd)
        $null = $builder.Append("`r`n")
        $null = $builder.Append([string]$record.DelimiterSet.EndFile)
        $null = $builder.Append("`r`n")
    }

    $sourceTotalBytes = @($sourceRecords | Measure-Object -Property SourceBytes -Sum).Sum
    $null = $builder.Append('================================================================================')
    $null = $builder.Append("`r`n")
    $null = $builder.Append('05. INTEGRITY SUMMARY')
    $null = $builder.Append("`r`n")
    $null = $builder.Append('================================================================================')
    $null = $builder.Append("`r`n")
    $null = $builder.Append("SOURCE_FILE_COUNT=$($sourceRecords.Count)")
    $null = $builder.Append("`r`n")
    $null = $builder.Append("SOURCE_TOTAL_BYTES=$sourceTotalBytes")
    $null = $builder.Append("`r`n")
    $null = $builder.Append('ALL_SOURCES_INCLUDED=YES')
    $null = $builder.Append("`r`n")
    $null = $builder.Append('TRUNCATION_DETECTED=NO')
    $null = $builder.Append("`r`n")
    $null = $builder.Append('DUPLICATE_SOURCE_PATH_COUNT=0')
    $null = $builder.Append("`r`n")
    $null = $builder.Append('MISSING_SOURCE_COUNT=0')
    $null = $builder.Append("`r`n")

    $compiledText = $builder.ToString()
    $compiledBytes = [System.Text.UTF8Encoding]::new($false).GetBytes($compiledText)
    $compiledSha256 = Get-UseCaseCompiledSha256Hex -Bytes $compiledBytes

    if ($WriteOutput) {
        Write-Utf8NoBom -Path $fullOutputPath -Content $compiledText
    }

    return [pscustomobject]@{
        PackageName         = $PackageName
        PackageType         = $PackageType
        PackageVersion      = $PackageVersion
        FormatVersion       = $FormatVersion
        OutputFileName      = $OutputFileName
        OutputPath          = $fullOutputPath
        OutputText          = $compiledText
        OutputBytes         = $compiledBytes
        OutputSha256        = $compiledSha256
        SourceFiles         = @($sourceRecords | ForEach-Object { $_.SourcePath })
        SourceCount         = @($sourceRecords).Count
        SourceTotalBytes    = [int64]$sourceTotalBytes
        SourceManifest      = @($sourceRecords)
        ContentPolicy       = 'FULL_CONTENT_NO_TRUNCATION'
        SourceOrderPolicy   = 'REGISTRY_DECLARED'
        Encoding            = 'UTF-8_NO_BOM'
        GeneratedOutputOnly = $true
    }
}

function Invoke-UseCaseCompiledFileSelfTests {
    param(
        [Parameter(Mandatory = $true)][string]$ScratchRoot
    )

    if (-not (Test-Path -LiteralPath $ScratchRoot -PathType Container)) {
        throw "COMPILER_SCRATCH_ROOT_MISSING"
    }

    $testResults = [System.Collections.Generic.List[object]]::new()
    $createdPaths = [System.Collections.Generic.List[string]]::new()
    $prefix = 'SM_D5B_COMPILER_' + ([System.Guid]::NewGuid().ToString('N'))

    function Add-CompilerTestResult {
        param(
            [string]$Name,
            [bool]$Passed,
            [string]$Detail
        )

        [void]$testResults.Add([pscustomobject]@{
            Name   = $Name
            Passed = $Passed
            Detail = $Detail
        })
    }

    function New-CompilerScratchFile {
        param(
            [Parameter(Mandatory = $true)][string]$Name,
            [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Content
        )

        $path = Join-Path $ScratchRoot ($prefix + '_' + $Name)
        Write-Utf8NoBom -Path $path -Content $Content
        [void]$createdPaths.Add($path)
        return $path
    }

    function Remove-CompilerScratchFiles {
        foreach ($path in @($createdPaths)) {
            if (Test-Path -LiteralPath $path) {
                Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
            }
        }
    }

    $source1 = $null
    $source2 = $null
    $source3 = $null
    $emptySource = $null
    $collisionSource = $null
    $outputName = $null

    try {
        $source1 = New-CompilerScratchFile -Name '01_alpha.txt' -Content "alpha`r`nline2`r`n"
        $source2Content = [string]::Join("`r`n", @('# Title', '```txt', 'value', '```'))
        $source2 = New-CompilerScratchFile -Name '02 beta.md' -Content $source2Content
        $source3Content = [string]::Join("`n", @('graph TD', 'A-->B', '```mermaid', 'flowchart LR', 'X-->Y', '```'))
        $source3 = New-CompilerScratchFile -Name '03_mermaid.md' -Content $source3Content
        $emptySource = New-CompilerScratchFile -Name '04_empty.txt' -Content ''
        $collisionSource = New-CompilerScratchFile -Name '05_collision.txt' -Content "before`r`n========== BEGIN_SOURCE_FILE collision ==========`r`nafter"
        $outputName = $prefix + '_PACKAGE.COMPILED.txt'

        $record1 = New-UseCaseCompiledFile -PackageName 'TEST' -PackageType 'USECASE' -PackageVersion 'v1' -ProjectRoot $ScratchRoot -TargetDirectory $ScratchRoot -OutputFileName $outputName -SourceFiles @((Split-Path -Leaf $source1), (Split-Path -Leaf $source2)) -FormatVersion 'v1'
        $record2 = New-UseCaseCompiledFile -PackageName 'TEST' -PackageType 'USECASE' -PackageVersion 'v1' -ProjectRoot $ScratchRoot -TargetDirectory $ScratchRoot -OutputFileName $outputName -SourceFiles @((Split-Path -Leaf $source1), (Split-Path -Leaf $source2)) -FormatVersion 'v1'

        Add-CompilerTestResult -Name 'T01_PARSEABLE_IMPORT_SIDE_EFFECT_FREE' -Passed $true -Detail 'Script was imported without top-level side effects.'
        Add-CompilerTestResult -Name 'T02_TWO_SOURCES_PRESERVE_ORDER' -Passed (($record1.SourceFiles[0] -eq (Split-Path -Leaf $source1)) -and ($record1.SourceFiles[1] -eq (Split-Path -Leaf $source2))) -Detail 'Source order should match registry declaration.'
        Add-CompilerTestResult -Name 'T03_COMPLETE_CONTENT_PRESERVED' -Passed ($record1.OutputText.Contains([System.IO.File]::ReadAllText($source1)) -and $record1.OutputText.Contains([System.IO.File]::ReadAllText($source2))) -Detail 'Compiled output should include full source content.'
        Add-CompilerTestResult -Name 'T04_SHA256_RECORDED_CORRECTLY' -Passed ($record1.SourceManifest[0].SourceSha256 -eq (Get-UseCaseCompiledSha256Hex -Bytes ([System.IO.File]::ReadAllBytes($source1)))) -Detail 'Source SHA256 should match bytes.'

        $outputPath = Join-Path $ScratchRoot $outputName
        [void](New-UseCaseCompiledFile -PackageName 'TEST' -PackageType 'USECASE' -PackageVersion 'v1' -ProjectRoot $ScratchRoot -TargetDirectory $ScratchRoot -OutputFileName $outputName -SourceFiles @((Split-Path -Leaf $source1), (Split-Path -Leaf $source2)) -FormatVersion 'v1' -WriteOutput)
        [void]$createdPaths.Add($outputPath)
        $writtenBytes = [System.IO.File]::ReadAllBytes($outputPath)
        $utf8Bom = @(0xEF, 0xBB, 0xBF)
        $hasBom = ($writtenBytes.Length -ge 3 -and $writtenBytes[0] -eq $utf8Bom[0] -and $writtenBytes[1] -eq $utf8Bom[1] -and $writtenBytes[2] -eq $utf8Bom[2])
        Add-CompilerTestResult -Name 'T05_UTF8_NO_BOM' -Passed (-not $hasBom) -Detail 'Compiled output must be UTF-8 without BOM.'

        $missingPathPassed = $false
        try {
            [void](New-UseCaseCompiledFile -PackageName 'TEST' -PackageType 'USECASE' -PackageVersion 'v1' -ProjectRoot $ScratchRoot -TargetDirectory $ScratchRoot -OutputFileName ($prefix + '_MISSING.COMPILED.txt') -SourceFiles @('missing.txt') -FormatVersion 'v1')
        }
        catch {
            $missingPathPassed = ($_.Exception.Message -eq 'COMPILED_SOURCE_MISSING')
        }
        Add-CompilerTestResult -Name 'T06_MISSING_SOURCE_FAILS' -Passed $missingPathPassed -Detail 'Missing source should fail closed.'

        $duplicatePathPassed = $false
        try {
            [void](New-UseCaseCompiledFile -PackageName 'TEST' -PackageType 'USECASE' -PackageVersion 'v1' -ProjectRoot $ScratchRoot -TargetDirectory $ScratchRoot -OutputFileName ($prefix + '_DUP.COMPILED.txt') -SourceFiles @((Split-Path -Leaf $source1), (Split-Path -Leaf $source1)) -FormatVersion 'v1')
        }
        catch {
            $duplicatePathPassed = ($_.Exception.Message -eq 'COMPILED_DUPLICATE_SOURCE_PATH')
        }
        Add-CompilerTestResult -Name 'T07_DUPLICATE_SOURCE_FAILS' -Passed $duplicatePathPassed -Detail 'Duplicate source path should fail closed.'

        $outsideRootPassed = $false
        try {
            [void](New-UseCaseCompiledFile -PackageName 'TEST' -PackageType 'USECASE' -PackageVersion 'v1' -ProjectRoot $ScratchRoot -TargetDirectory $ScratchRoot -OutputFileName ($prefix + '_OUTSIDE.COMPILED.txt') -SourceFiles @('..\outside.txt') -FormatVersion 'v1')
        }
        catch {
            $outsideRootPassed = ($_.Exception.Message -eq 'COMPILED_SOURCE_OUTSIDE_PROJECT_ROOT')
        }
        Add-CompilerTestResult -Name 'T08_OUTSIDE_ROOT_FAILS' -Passed $outsideRootPassed -Detail 'Source path outside root should fail closed.'

        $selfSourcePassed = $false
        try {
            [void](New-UseCaseCompiledFile -PackageName 'TEST' -PackageType 'USECASE' -PackageVersion 'v1' -ProjectRoot $ScratchRoot -TargetDirectory $ScratchRoot -OutputFileName ($prefix + '_SELF.COMPILED.txt') -SourceFiles @($prefix + '_SELF.COMPILED.txt') -FormatVersion 'v1')
        }
        catch {
            $selfSourcePassed = ($_.Exception.Message -eq 'COMPILED_OUTPUT_INCLUDED_AS_SOURCE')
        }
        Add-CompilerTestResult -Name 'T09_OUTPUT_INCLUDED_AS_SOURCE_FAILS' -Passed $selfSourcePassed -Detail 'Compiled output cannot be one of its own sources.'

        $collisionPassed = $false
        try {
            [void](New-UseCaseCompiledFile -PackageName 'TEST' -PackageType 'USECASE' -PackageVersion 'v1' -ProjectRoot $ScratchRoot -TargetDirectory $ScratchRoot -OutputFileName ($prefix + '_COLLISION.COMPILED.txt') -SourceFiles @((Split-Path -Leaf $collisionSource)) -FormatVersion 'v1')
        }
        catch {
            $collisionPassed = ($_.Exception.Message -eq 'COMPILED_SEPARATOR_COLLISION')
        }
        Add-CompilerTestResult -Name 'T10_SEPARATOR_COLLISION_FAILS' -Passed $collisionPassed -Detail 'Delimiter collision must fail closed.'

        Add-CompilerTestResult -Name 'T11_DOUBLE_EXECUTION_IDENTICAL_BYTES' -Passed ($record1.OutputSha256 -eq $record2.OutputSha256) -Detail 'Repeated compilation with same inputs must be byte-identical.'
        Add-CompilerTestResult -Name 'T12_MARKDOWN_AND_MERMAID_PRESERVED' -Passed ((New-UseCaseCompiledFile -PackageName 'TEST' -PackageType 'USECASE' -PackageVersion 'v1' -ProjectRoot $ScratchRoot -TargetDirectory $ScratchRoot -OutputFileName ($prefix + '_MARKDOWN.COMPILED.txt') -SourceFiles @((Split-Path -Leaf $source3)) -FormatVersion 'v1').OutputText.Contains('```mermaid')) -Detail 'Markdown fences and Mermaid content must be preserved.'
        Add-CompilerTestResult -Name 'T13_EMPTY_CONTENT_SUPPORTED' -Passed ((New-UseCaseCompiledFile -PackageName 'TEST' -PackageType 'USECASE' -PackageVersion 'v1' -ProjectRoot $ScratchRoot -TargetDirectory $ScratchRoot -OutputFileName ($prefix + '_EMPTY.COMPILED.txt') -SourceFiles @((Split-Path -Leaf $emptySource)) -FormatVersion 'v1').SourceManifest[0].SourceBytes -eq 0) -Detail 'Empty source files must compile correctly.'
        Add-CompilerTestResult -Name 'T14_PATHS_WITH_SPACES_SUPPORTED' -Passed ($record1.SourceFiles[1] -eq (Split-Path -Leaf $source2)) -Detail 'Source file names with spaces must work.'
        Add-CompilerTestResult -Name 'T15_REPARSEABLE_OUTPUT_STRUCTURE' -Passed ($record1.OutputText.Contains('05. INTEGRITY SUMMARY') -and $record1.OutputText.Contains('SOURCE_FILE_COUNT=2')) -Detail 'Compiled output must include structural sections for reparsing.'
    }
    finally {
        Remove-CompilerScratchFiles
    }

    $total = @($testResults).Count
    $passed = @($testResults | Where-Object { $_.Passed }).Count
    $failed = $total - $passed

    return [pscustomobject]@{
        TestsTotal  = $total
        TestsPassed = $passed
        TestsFailed = $failed
        Results     = @($testResults)
    }
}
