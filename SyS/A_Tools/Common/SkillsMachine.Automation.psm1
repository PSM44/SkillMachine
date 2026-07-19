Set-StrictMode -Version Latest

#region ── Private Helpers ────────────────────────────────────────────────────

# Normalize any value to a non-null array.
# IMPORTANT: callers must assign with a null-guard because PowerShell pipelines unwrap
# empty @() to $null. Use the guard pattern shown below for each call site.
function ConvertTo-SafeArray {
    param($Value)
    if ($null -eq $Value) { return @() }
    if ($Value -is [System.Array]) { return $Value }
    return @($Value)
}

# Safe null-guard assignment: returns an array that is always non-null.
# Usage: $arr = Safe-Assign (someExpr)
function Safe-Assign {
    param($Value)
    # Direct assignment avoids pipeline unwrapping
    if ($null -eq $Value) { return @() }
    return $Value
}

function Resolve-NormalizedPath {
    param([string]$InputPath)
    return [System.IO.Path]::GetFullPath($InputPath.TrimEnd('\', '/'))
}

function ConvertTo-GitArgumentString {
    param([string[]]$ArgumentList)
    $parts = [System.Collections.Generic.List[string]]::new()
    foreach ($arg in $ArgumentList) {
        if ($arg -match '[\s"]') {
            $escaped = $arg.Replace('"', '\"')
            $parts.Add('"' + $escaped + '"') | Out-Null
        } else {
            $parts.Add($arg) | Out-Null
        }
    }
    return $parts -join ' '
}

function Invoke-NativeProcess {
    param(
        [string]$FileName,
        [string]$ArgumentString,
        [string]$WorkingDirectory
    )
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $FileName
    $psi.Arguments = $ArgumentString
    if (-not [string]::IsNullOrEmpty($WorkingDirectory)) {
        $psi.WorkingDirectory = $WorkingDirectory
    }
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.UseShellExecute        = $false
    $psi.CreateNoWindow         = $true

    $proc = [System.Diagnostics.Process]::new()
    $proc.StartInfo = $psi
    [void]$proc.Start()

    # Async reads prevent deadlock when both stdout and stderr are captured simultaneously
    $stdoutTask = $proc.StandardOutput.ReadToEndAsync()
    $stderrTask = $proc.StandardError.ReadToEndAsync()
    $proc.WaitForExit()
    $stdout   = $stdoutTask.Result
    $stderr   = $stderrTask.Result
    $exitCode = $proc.ExitCode   # capture before Dispose — ExitCode is unavailable after Dispose
    $proc.Dispose()

    return [PSCustomObject]@{
        ExitCode = $exitCode
        StdOut   = $stdout
        StdErr   = $stderr
    }
}

function Split-TextToLines {
    # Splits a string on CRLF/LF and returns a non-null string array.
    # Uses List to avoid PowerShell empty-array pipeline-unwrap issue.
    param([string]$Text)
    $list = [System.Collections.Generic.List[string]]::new()
    if (-not [string]::IsNullOrEmpty($Text)) {
        foreach ($line in ($Text -split "`r?`n")) {
            if ($null -ne $line) { $list.Add($line) | Out-Null }
        }
    }
    return [string[]]$list.ToArray()
}

function ConvertTo-NormalizedStatusPath {
    param([string]$RawPath)
    return $RawPath.Replace('/', '\').TrimStart('\')
}

#endregion

#region ── Public Functions ───────────────────────────────────────────────────

function Test-ObjectProperty {
    <#
    .SYNOPSIS
    Returns true if InputObject has the named property; safe under Set-StrictMode.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][AllowNull()][object]$InputObject,
        [Parameter(Mandatory)][string]$Name
    )
    if ($null -eq $InputObject) { return $false }
    if ($InputObject -is [System.Management.Automation.PSCustomObject]) {
        return ($null -ne $InputObject.PSObject.Properties[$Name])
    }
    $bindFlags = [System.Reflection.BindingFlags]::Public -bor [System.Reflection.BindingFlags]::Instance
    return ($null -ne $InputObject.GetType().GetProperty($Name, $bindFlags))
}

function Write-Utf8NoBom {
    <#
    .SYNOPSIS
    Writes a string to a file as UTF-8 without BOM.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Content,
        [switch]$CreateParent
    )
    $parent = [System.IO.Path]::GetDirectoryName([System.IO.Path]::GetFullPath($Path))
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        if ($CreateParent) {
            [void](New-Item -ItemType Directory -Path $parent -Force)
        } else {
            throw "Write-Utf8NoBom: parent directory does not exist: '$parent'. Use -CreateParent to create it."
        }
    }
    $enc = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($Path, $Content, $enc)
}

function Get-Sha256 {
    <#
    .SYNOPSIS
    Returns the lowercase SHA256 hex digest of a file.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$Path
    )
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Get-Sha256: file not found: '$Path'"
    }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $stream = [System.IO.File]::OpenRead($Path)
        try {
            $bytes = $sha.ComputeHash($stream)
        } finally {
            $stream.Dispose()
        }
    } finally {
        $sha.Dispose()
    }
    $hexList = [System.Collections.Generic.List[string]]::new()
    foreach ($b in $bytes) { $hexList.Add($b.ToString('x2')) | Out-Null }
    return $hexList -join ''
}

function Invoke-GitSafe {
    <#
    .SYNOPSIS
    Invokes git with an explicit argument list; returns a structured result object.
    Uses System.Diagnostics.Process to preserve argument spaces and avoid shell injection.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string[]]$Arguments,
        [switch]$AllowFailure,
        [int[]]$ExpectedExitCodes = @(0)
    )

    $argString = ConvertTo-GitArgumentString -ArgumentList $Arguments
    $raw       = Invoke-NativeProcess -FileName 'git' -ArgumentString $argString -WorkingDirectory $RepositoryRoot

    # Inline line splitting via List.ToArray() — a direct .NET method call, not a PowerShell function,
    # so the result is never pipeline-unwrapped to $null even when the list is empty.
    $stdoutList = [System.Collections.Generic.List[string]]::new()
    foreach ($l in ($raw.StdOut -split "`r?`n")) { if ($null -ne $l) { $stdoutList.Add($l) | Out-Null } }
    $stdoutLines = [string[]]$stdoutList.ToArray()

    $stderrList = [System.Collections.Generic.List[string]]::new()
    foreach ($l in ($raw.StdErr -split "`r?`n")) { if ($null -ne $l) { $stderrList.Add($l) | Out-Null } }
    $stderrLines = [string[]]$stderrList.ToArray()

    # Determine whether the exit code is in the expected set
    $expectedCodes = @(0)
    if ($null -ne $ExpectedExitCodes -and $ExpectedExitCodes.Count -gt 0) {
        $expectedCodes = $ExpectedExitCodes
    }
    $succeeded = $raw.ExitCode -in $expectedCodes

    $result = [PSCustomObject]@{
        Command        = 'git'
        RepositoryRoot = $RepositoryRoot
        Arguments      = $Arguments
        ExitCode       = $raw.ExitCode
        StdOutLines    = $stdoutLines
        StdErrLines    = $stderrLines
        StdOutText     = $raw.StdOut.TrimEnd()
        StdErrText     = $raw.StdErr.TrimEnd()
        Succeeded      = $succeeded
    }

    if (-not $succeeded -and -not $AllowFailure) {
        $argDisp = $Arguments -join ' '
        throw "Invoke-GitSafe: 'git $argDisp' exited $($raw.ExitCode). Stderr: $($raw.StdErr.Trim())"
    }

    return $result
}

function Get-GitStatus {
    <#
    .SYNOPSIS
    Returns a structured object describing the current worktree state.
    All collections are always non-null string arrays.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot
    )

    $gitResult = Invoke-GitSafe -RepositoryRoot $RepositoryRoot `
        -Arguments @('status', '--porcelain=v1', '--untracked-files=all') `
        -AllowFailure

    # Collect non-empty lines; use List to guarantee non-null array (no pipeline unwrap issue)
    $rawLinesList = [System.Collections.Generic.List[string]]::new()
    foreach ($line in $gitResult.StdOutLines) {
        if (-not [string]::IsNullOrEmpty($line)) {
            $rawLinesList.Add($line) | Out-Null
        }
    }
    $rawLines = [string[]]$rawLinesList.ToArray()

    $staged     = [System.Collections.Generic.List[string]]::new()
    $modified   = [System.Collections.Generic.List[string]]::new()
    $deleted    = [System.Collections.Generic.List[string]]::new()
    $renamed    = [System.Collections.Generic.List[string]]::new()
    $untracked  = [System.Collections.Generic.List[string]]::new()
    $conflicted = [System.Collections.Generic.List[string]]::new()

    foreach ($line in $rawLines) {
        if ([string]::IsNullOrEmpty($line) -or $line.Length -lt 2) { continue }
        $x    = $line[0].ToString()
        $y    = $line[1].ToString()
        $path = if ($line.Length -gt 3) { $line.Substring(3) } else { $line.Substring(2).TrimStart() }

        if ($x -eq '?' -and $y -eq '?') {
            $untracked.Add($path) | Out-Null
            continue
        }

        # Conflict patterns
        if ($x -eq 'U' -or $y -eq 'U' -or
            ($x -eq 'A' -and $y -eq 'A') -or
            ($x -eq 'D' -and $y -eq 'D')) {
            $conflicted.Add($path) | Out-Null
            continue
        }

        # Index column (staged area)
        if ($x -ne ' ') {
            if ($x -eq 'R') {
                $renamed.Add($path) | Out-Null
            } elseif ($x -eq 'D') {
                $deleted.Add($path) | Out-Null
            } else {
                $staged.Add($path) | Out-Null
            }
        }

        # Working tree column
        if ($y -ne ' ' -and $y -ne '?') {
            if ($y -eq 'M') {
                $modified.Add($path) | Out-Null
            } elseif ($y -eq 'D') {
                if (-not $deleted.Contains($path)) { $deleted.Add($path) | Out-Null }
            }
        }
    }

    return [PSCustomObject]@{
        IsClean    = ($rawLines.Length -eq 0)
        RawLines   = $rawLines
        Staged     = [string[]]$staged.ToArray()
        Modified   = [string[]]$modified.ToArray()
        Deleted    = [string[]]$deleted.ToArray()
        Renamed    = [string[]]$renamed.ToArray()
        Untracked  = [string[]]$untracked.ToArray()
        Conflicted = [string[]]$conflicted.ToArray()
    }
}

function Get-RepoIdentity {
    <#
    .SYNOPSIS
    Returns repository identity information (top-level, branch, HEAD, origin/main).
    All Git operations are read-only.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot
    )

    $normalRoot = Resolve-NormalizedPath $RepositoryRoot
    $isGit      = Test-Path -LiteralPath (Join-Path $normalRoot '.git')

    $gitTopLevel         = ''
    $branch              = ''
    $head                = ''
    $originMain          = ''

    if ($isGit) {
        $r = Invoke-GitSafe -RepositoryRoot $normalRoot -Arguments @('rev-parse', '--show-toplevel') -AllowFailure
        if ($r.Succeeded -and $r.StdOutText -ne '') {
            $gitTopLevel = Resolve-NormalizedPath $r.StdOutText.Trim()
        }

        $r = Invoke-GitSafe -RepositoryRoot $normalRoot -Arguments @('rev-parse', '--abbrev-ref', 'HEAD') -AllowFailure
        if ($r.Succeeded) { $branch = $r.StdOutText.Trim() }

        $r = Invoke-GitSafe -RepositoryRoot $normalRoot -Arguments @('rev-parse', 'HEAD') -AllowFailure
        if ($r.Succeeded) { $head = $r.StdOutText.Trim() }

        $r = Invoke-GitSafe -RepositoryRoot $normalRoot -Arguments @('rev-parse', 'origin/main') -AllowFailure
        if ($r.Succeeded) { $originMain = $r.StdOutText.Trim() }
    }

    $headEqualsOriginMain = ($head -ne '' -and $originMain -ne '' -and $head -eq $originMain)

    return [PSCustomObject]@{
        RepositoryRoot       = $normalRoot
        GitTopLevel          = $gitTopLevel
        Branch               = $branch
        Head                 = $head
        OriginMain           = $originMain
        IsGitRepository      = $isGit
        HeadEqualsOriginMain = $headEqualsOriginMain
    }
}

function Assert-ProjectContext {
    <#
    .SYNOPSIS
    Verifies project root, branch, and HEAD match expectations.
    Throws PROJECT_CONTEXT_MISMATCH: on any mismatch.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)][string]$ExpectedRoot,
        [string]$ExpectedBranch      = '',
        [string]$ExpectedHead        = '',
        [switch]$RequireOriginHeadMatch
    )

    $normalExpected = Resolve-NormalizedPath $ExpectedRoot
    $identity = Get-RepoIdentity -RepositoryRoot $normalExpected

    $mismatches = [System.Collections.Generic.List[string]]::new()

    if ($identity.GitTopLevel -ne $normalExpected) {
        $mismatches.Add("GitTopLevel='$($identity.GitTopLevel)' expected '$normalExpected'") | Out-Null
    }
    if ($ExpectedBranch -ne '' -and $identity.Branch -ne $ExpectedBranch) {
        $mismatches.Add("Branch='$($identity.Branch)' expected '$ExpectedBranch'") | Out-Null
    }
    if ($ExpectedHead -ne '' -and $identity.Head -ne $ExpectedHead) {
        $mismatches.Add("Head='$($identity.Head)' expected '$ExpectedHead'") | Out-Null
    }
    if ($RequireOriginHeadMatch -and -not $identity.HeadEqualsOriginMain) {
        $mismatches.Add("Head='$($identity.Head)' != OriginMain='$($identity.OriginMain)'") | Out-Null
    }

    if ($mismatches.Count -gt 0) {
        throw "PROJECT_CONTEXT_MISMATCH: $($mismatches -join '; ')"
    }

    return $identity
}

function Assert-WorktreeClean {
    <#
    .SYNOPSIS
    Throws WORKTREE_NOT_CLEAN: if unexpected dirty paths exist.
    Optional AllowedPaths must be exact repo-relative paths (backslash-normalized).
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [string[]]$AllowedPaths = @()
    )

    $status = Get-GitStatus -RepositoryRoot $RepositoryRoot

    if ($status.IsClean) { return $status }

    $allDirtyList = [System.Collections.Generic.List[string]]::new()
    foreach ($col in @($status.Staged, $status.Modified, $status.Deleted, $status.Renamed, $status.Untracked, $status.Conflicted)) {
        if ($null -ne $col) {
            foreach ($p in $col) { $allDirtyList.Add($p) | Out-Null }
        }
    }

    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $normalizedAllowed = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($p in $AllowedPaths) { [void]$normalizedAllowed.Add((ConvertTo-NormalizedStatusPath $p)) }

    $unexpected = [System.Collections.Generic.List[string]]::new()
    foreach ($p in $allDirtyList) {
        $norm = ConvertTo-NormalizedStatusPath $p
        if ($seen.Contains($norm)) { continue }
        [void]$seen.Add($norm)
        if (-not $normalizedAllowed.Contains($norm)) {
            $unexpected.Add($norm) | Out-Null
        }
    }

    if ($unexpected.Count -gt 0) {
        throw "WORKTREE_NOT_CLEAN: unexpected paths: $($unexpected -join ', ')"
    }

    return $status
}

function Read-JsonSafe {
    <#
    .SYNOPSIS
    Reads a UTF-8 file and parses it as JSON; fails with a clear message on error.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)][string]$Path
    )
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Read-JsonSafe: file not found: '$Path'"
    }
    $text = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
    try {
        return $text | ConvertFrom-Json
    } catch {
        throw "Read-JsonSafe: JSON parse error in '$Path': $($_.Exception.Message)"
    }
}

function Get-UseCaseRegistryModel {
    <#
    .SYNOPSIS
    Parses USECASE.REGISTRY.json using the real v3.0-BUNDLES schema.
    Uses Test-ObjectProperty for all optional property access.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)][string]$RegistryPath
    )

    $json = Read-JsonSafe -Path $RegistryPath

    foreach ($req in @('version', 'usecases')) {
        if (-not (Test-ObjectProperty -InputObject $json -Name $req)) {
            throw "Get-UseCaseRegistryModel: required property '$req' absent in '$RegistryPath'"
        }
    }

    $version = $json.version

    $rootSkillsPath = ''
    if (Test-ObjectProperty -InputObject $json -Name 'root_skills_path') {
        $rootSkillsPath = $json.root_skills_path
    }

    # Build ExcludedRoots as a List to avoid pipeline empty-array unwrap
    $excludedRootsList = [System.Collections.Generic.List[string]]::new()
    if (Test-ObjectProperty -InputObject $json -Name 'excluded_roots') {
        $rawRoots = $json.excluded_roots
        if ($null -ne $rawRoots) {
            foreach ($r in @($rawRoots)) {
                if ($null -ne $r) { $excludedRootsList.Add($r.ToString()) | Out-Null }
            }
        }
    }
    $excludedRoots = [string[]]$excludedRootsList.ToArray()

    $buildPolicy = $null
    if (Test-ObjectProperty -InputObject $json -Name 'build_policy') {
        $buildPolicy = $json.build_policy
    }

    # Build UseCases as a List to avoid pipeline empty-array unwrap
    $useCasesList = [System.Collections.Generic.List[object]]::new()
    $rawUc = $json.usecases
    if ($null -ne $rawUc) {
        foreach ($uc in @($rawUc)) {
            if ($null -ne $uc) { $useCasesList.Add($uc) | Out-Null }
        }
    }
    $useCases = [object[]]$useCasesList.ToArray()

    # Build SupportPackages as a List
    $supportPkgsList = [System.Collections.Generic.List[object]]::new()
    if (Test-ObjectProperty -InputObject $json -Name 'support_packages') {
        $rawSp = $json.support_packages
        if ($null -ne $rawSp) {
            foreach ($sp in @($rawSp)) {
                if ($null -ne $sp) { $supportPkgsList.Add($sp) | Out-Null }
            }
        }
    }
    $supportPackages = [object[]]$supportPkgsList.ToArray()

    return [PSCustomObject]@{
        Version           = $version
        RootSkillsPath    = $rootSkillsPath
        ExcludedRoots     = $excludedRoots
        BuildPolicy       = $buildPolicy
        UseCases          = $useCases
        SupportPackages   = $supportPackages
        ValidPackageCount = ($useCases.Length + $supportPackages.Length)
    }
}

function Test-PowerShellFileSyntax {
    <#
    .SYNOPSIS
    Checks PowerShell syntax via AST parser. Never executes the file.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)][string]$Path
    )
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Test-PowerShellFileSyntax: file not found: '$Path'"
    }
    $tokens = $null
    $errors  = $null
    [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors) | Out-Null

    # Build error list using List to avoid empty-array pipeline-unwrap under StrictMode
    $errorList = [System.Collections.Generic.List[object]]::new()
    if ($null -ne $errors) {
        foreach ($e in $errors) {
            if ($null -ne $e) { $errorList.Add($e) | Out-Null }
        }
    }

    return [PSCustomObject]@{
        Path       = $Path
        IsValid    = ($errorList.Count -eq 0)
        ErrorCount = $errorList.Count
        Errors     = [object[]]$errorList.ToArray()
    }
}

function New-AiTail {
    <#
    .SYNOPSIS
    Produces the standard AI_TAIL block: five blank lines + START + KEY=VALUE pairs + END.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Fields,
        [string]$SchemaVersion = 'v2'
    )

    foreach ($key in $Fields.Keys) {
        $keyStr = $key.ToString()
        if ($keyStr -match '[\r\n=]') {
            throw "New-AiTail: key '$keyStr' contains invalid character (newline or '=')"
        }
    }

    $crlf = "`r`n"
    $sb   = [System.Text.StringBuilder]::new()

    # Five blank lines before the start marker
    [void]$sb.Append($crlf)
    [void]$sb.Append($crlf)
    [void]$sb.Append($crlf)
    [void]$sb.Append($crlf)
    [void]$sb.Append($crlf)

    [void]$sb.Append("========== AI_TAIL_START ==========$crlf")

    foreach ($key in $Fields.Keys) {
        $val = $Fields[$key]
        if ($null -eq $val) { $val = '' }
        [void]$sb.Append("$key=$val$crlf")
    }

    [void]$sb.Append("========== AI_TAIL_END ==========")

    return $sb.ToString()
}

#endregion

Export-ModuleMember -Function @(
    'Test-ObjectProperty',
    'Write-Utf8NoBom',
    'Get-Sha256',
    'Invoke-GitSafe',
    'Get-GitStatus',
    'Get-RepoIdentity',
    'Assert-ProjectContext',
    'Assert-WorktreeClean',
    'Read-JsonSafe',
    'Get-UseCaseRegistryModel',
    'Test-PowerShellFileSyntax',
    'New-AiTail'
)
