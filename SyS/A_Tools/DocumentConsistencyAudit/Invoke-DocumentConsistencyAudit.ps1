[CmdletBinding()]
param(
    [string]$Mode,
    [string]$ProjectRoot,
    [string]$ProjectId,
    [string]$StatePath,
    [string[]]$ChangedPaths = @(),
    [switch]$AcceptedSessionContinue,
    [switch]$HumanRequestedFullAudit,
    [switch]$NoStateWrite,
    [string[]]$FullScanExcludeDirectories = @(
        ".git",
        "node_modules",
        ".venv",
        "venv",
        "dist",
        "build",
        "bin",
        "obj",
        "cache",
        "caches",
        "backup",
        "backups",
        "temp",
        "tmp"
    )
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Write-Utf8NoBom {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [AllowEmptyString()][string]$Content
    )

    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $utf8)
}

function ConvertTo-JsonStable {
    param(
        [Parameter(Mandatory = $true)]$InputObject
    )

    return ($InputObject | ConvertTo-Json -Depth 40)
}

function Get-Sha256Text {
    param(
        [Parameter(Mandatory = $true)][string]$Text
    )

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hashBytes = $sha.ComputeHash($bytes)
        return ([BitConverter]::ToString($hashBytes) -replace "-", "").ToUpperInvariant()
    }
    finally {
        if ($null -ne $sha) { $sha.Dispose() }
    }
}

function Get-Sha256File {
    param(
        [Parameter(Mandatory = $true)][string]$Path
    )

    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Get-NormalizedFullPath {
    param(
        [Parameter(Mandatory = $true)][string]$Path
    )

    return [System.IO.Path]::GetFullPath($Path)
}

function Get-NormalizedDirectoryPrefix {
    param(
        [Parameter(Mandatory = $true)][string]$Path
    )

    $full = Get-NormalizedFullPath -Path $Path
    if (-not $full.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
        $full += [System.IO.Path]::DirectorySeparatorChar
    }

    return $full
}

function Test-PathWithinRoot {
    param(
        [Parameter(Mandatory = $true)][string]$RootFull,
        [Parameter(Mandatory = $true)][string]$CandidateFull
    )

    $rootPrefix = Get-NormalizedDirectoryPrefix -Path $RootFull
    return (
        $CandidateFull.Equals($RootFull, [System.StringComparison]::OrdinalIgnoreCase) -or
        $CandidateFull.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)
    )
}

function Get-RelativePathSafe {
    param(
        [Parameter(Mandatory = $true)][string]$RootFull,
        [Parameter(Mandatory = $true)][string]$PathFull
    )

    $rootPrefix = Get-NormalizedDirectoryPrefix -Path $RootFull
    if ($PathFull.Equals($RootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
        return "."
    }

    if (-not $PathFull.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "RELATIVE_PATH_OUTSIDE_ROOT"
    }

    return $PathFull.Substring($rootPrefix.Length)
}

function Split-RelativeSegments {
    param(
        [Parameter(Mandatory = $true)][string]$RelativePath
    )

    return @(
        ($RelativePath -split '[\\/]') |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and $_ -ne "." }
    )
}

function Test-ReparseTraversal {
    param(
        [Parameter(Mandatory = $true)][string]$RootFull,
        [Parameter(Mandatory = $true)][string]$CandidateFull
    )

    $rootItem = Get-Item -LiteralPath $RootFull -Force
    if (($rootItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        return $true
    }

    $relative = Get-RelativePathSafe -RootFull $RootFull -PathFull $CandidateFull
    if ($relative -eq ".") {
        return $false
    }

    $current = $RootFull
    foreach ($segment in @(Split-RelativeSegments -RelativePath $relative)) {
        $current = Join-Path $current $segment
        if (-not (Test-Path -LiteralPath $current)) {
            break
        }

        $item = Get-Item -LiteralPath $current -Force
        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            return $true
        }
    }

    return $false
}

function Resolve-GuardedPath {
    param(
        [Parameter(Mandatory = $true)][string]$RootFull,
        [Parameter(Mandatory = $true)][string]$Candidate,
        [Parameter(Mandatory = $true)][string]$CrossRootCode,
        [Parameter(Mandatory = $true)][string]$ReparseCode
    )

    $candidateFull = if ([System.IO.Path]::IsPathRooted($Candidate)) {
        Get-NormalizedFullPath -Path $Candidate
    }
    else {
        Get-NormalizedFullPath -Path (Join-Path $RootFull $Candidate)
    }

    if (-not (Test-PathWithinRoot -RootFull $RootFull -CandidateFull $candidateFull)) {
        throw $CrossRootCode
    }

    if (Test-ReparseTraversal -RootFull $RootFull -CandidateFull $candidateFull) {
        throw $ReparseCode
    }

    return $candidateFull
}

function Get-SafeChildFiles {
    param(
        [Parameter(Mandatory = $true)][string]$RootFull,
        [Parameter(Mandatory = $true)]$ExcludedDirectoryNames
    )

    $excluded = @{}
    foreach ($name in @($ExcludedDirectoryNames | ForEach-Object { [string]$_ })) {
        $excluded[$name.ToUpperInvariant()] = $true
    }

    $pending = New-Object System.Collections.Generic.Queue[string]
    $pending.Enqueue($RootFull)
    $files = New-Object System.Collections.Generic.List[object]

    while ($pending.Count -gt 0) {
        $current = $pending.Dequeue()
        foreach ($item in @(Get-ChildItem -LiteralPath $current -Force -ErrorAction SilentlyContinue)) {
            if ($item.PSIsContainer) {
                if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                    continue
                }

                $upper = $item.Name.ToUpperInvariant()
                if ($excluded.ContainsKey($upper)) {
                    continue
                }

                $pending.Enqueue($item.FullName)
                continue
            }

            if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                continue
            }

            [void]$files.Add($item)
        }
    }

    return @($files | Sort-Object FullName)
}

function Get-CandidatePrecedence {
    param(
        [Parameter(Mandatory = $true)][string]$Role,
        [Parameter(Mandatory = $true)][string]$ProjectId,
        [Parameter(Mandatory = $true)][string]$FileName
    )

    $roleUpper = $Role.ToUpperInvariant()
    $projectUpper = $ProjectId.ToUpperInvariant()
    $fileUpper = $FileName.ToUpperInvariant()

    if ($fileUpper -eq ("{0}.{1}.MD" -f $roleUpper, $projectUpper) -or
        $fileUpper -eq ("{0}.{1}.TXT" -f $roleUpper, $projectUpper)) {
        return 1
    }

    if ($fileUpper -eq ("{0}.MD" -f $roleUpper) -or
        $fileUpper -eq ("{0}.TXT" -f $roleUpper)) {
        return 2
    }

    if ($fileUpper -like ("{0}.*.MD" -f $roleUpper) -or
        $fileUpper -like ("{0}.*.TXT" -f $roleUpper)) {
        return 3
    }

    return 0
}

function Test-RoleCandidateInProjectScope {
    param(
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][ValidateSet("HUMAN", "WHOAMI", "BATON")][string]$Role
    )

    $normalized = $RelativePath.Replace("/", "\").TrimStart("\")
    $fileName = [System.IO.Path]::GetFileName($normalized)
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($fileName)

    if ($baseName -match '(?i)(^README$|\.README$|^README\.|\.README\.)') {
        return $false
    }

    $segments = @($normalized -split '\\' | Where-Object { $_ -ne "" })

    if ($segments.Count -eq 1) {
        return $true
    }

    $first = $segments[0].ToUpperInvariant()
    $roleUpper = $Role.ToUpperInvariant()

    if ($first -eq $roleUpper) {
        return $true
    }

    $allowedTopLevel = switch ($roleUpper) {
        "HUMAN" { @("00.HUMAN", "00_HUMAN", "01_HUMAN") }
        "WHOAMI" { @("00.STATE", "00_STATE", "01.CONTINUITY", "01_CONTINUITY") }
        "BATON" { @("00.STATE", "00_STATE", "01.CONTINUITY", "01_CONTINUITY") }
    }

    return ($allowedTopLevel -contains $first)
}

function Resolve-DocumentRole {
    param(
        [Parameter(Mandatory = $true)][string]$RootFull,
        [Parameter(Mandatory = $true)][ValidateSet("HUMAN", "WHOAMI", "BATON")][string]$Role,
        [Parameter(Mandatory = $true)][string]$ProjectId,
        [Parameter(Mandatory = $true)]$ExcludedDirectoryNames
    )

    $candidates = New-Object System.Collections.Generic.List[object]

    foreach ($file in @(Get-SafeChildFiles -RootFull $RootFull -ExcludedDirectoryNames $ExcludedDirectoryNames)) {
        $precedence = Get-CandidatePrecedence -Role $Role -ProjectId $ProjectId -FileName $file.Name
        if ($precedence -le 0) {
            continue
        }

        $full = Resolve-GuardedPath `
            -RootFull $RootFull `
            -Candidate $file.FullName `
            -CrossRootCode "CROSS_ROOT_ROLE_PATH" `
            -ReparseCode "REPARSE_POINT_ROLE_PATH"

        $relativePath = Get-RelativePathSafe -RootFull $RootFull -PathFull $full

        if (-not (Test-RoleCandidateInProjectScope -RelativePath $relativePath -Role $Role)) {
            continue
        }

        [void]$candidates.Add([pscustomobject][ordered]@{
            role = $Role
            relative_path = $relativePath
            file_name = $file.Name
            precedence_rank = $precedence
            sha256 = Get-Sha256File -Path $full
        })
    }

    $sortedCandidates = @(
        $candidates |
        Sort-Object @{ Expression = "precedence_rank"; Ascending = $true }, @{ Expression = "relative_path"; Ascending = $true }
    )

    if (@($sortedCandidates).Count -eq 0) {
        return [pscustomobject][ordered]@{
            role = $Role
            status = "NOT_FOUND"
            best_precedence_rank = $null
            selected_path = $null
            candidates = @()
        }
    }

    $bestRank = [int]$sortedCandidates[0].precedence_rank
    $bestCandidates = @($sortedCandidates | Where-Object { [int]$_.precedence_rank -eq $bestRank })

    if (@($bestCandidates).Count -gt 1) {
        return [pscustomobject][ordered]@{
            role = $Role
            status = "HARD_CONFLICT"
            best_precedence_rank = $bestRank
            selected_path = $null
            candidates = @($sortedCandidates)
        }
    }

    return [pscustomobject][ordered]@{
        role = $Role
        status = "RESOLVED"
        best_precedence_rank = $bestRank
        selected_path = [string]$bestCandidates[0].relative_path
        candidates = @($sortedCandidates)
    }
}

function New-Issue {
    param(
        [Parameter(Mandatory = $true)][string]$IssueClass,
        [Parameter(Mandatory = $true)][ValidateSet("INFO", "WARNING", "HARD_CONFLICT", "BLOCKER")][string]$Severity,
        [Parameter(Mandatory = $true)][string]$Title,
        [string]$DocumentPath = "",
        [string]$RelatedPath = "",
        [string]$ObservedValue = "",
        [string]$ExpectedValue = "",
        [string]$AuthorityLayer = ""
    )

    $fingerprint = @(
        $IssueClass,
        $Severity,
        $Title,
        $DocumentPath,
        $RelatedPath,
        $ObservedValue,
        $ExpectedValue,
        $AuthorityLayer
    ) -join "|"

    $issueId = "ISSUE-" + (Get-Sha256Text -Text $fingerprint).Substring(0, 16)

    return [pscustomobject][ordered]@{
        issue_id = $issueId
        issue_class = $IssueClass
        severity = $Severity
        status = "OPEN"
        title = $Title
        document_path = $DocumentPath
        related_path = $RelatedPath
        observed_value = $ObservedValue
        expected_value = $ExpectedValue
        authority_layer = $AuthorityLayer
    }
}

function Sort-Issues {
    param(
        [Parameter(Mandatory = $true)]$Issues
    )

    $rank = @{
        "BLOCKER" = 0
        "HARD_CONFLICT" = 1
        "WARNING" = 2
        "INFO" = 3
    }

    return @(
        $Issues |
        Sort-Object `
            @{ Expression = { $rank[[string]$_.severity] }; Ascending = $true }, `
            @{ Expression = "issue_class"; Ascending = $true }, `
            @{ Expression = "document_path"; Ascending = $true }, `
            @{ Expression = "related_path"; Ascending = $true }, `
            @{ Expression = "title"; Ascending = $true }, `
            @{ Expression = "issue_id"; Ascending = $true }
    )
}

function Get-DefaultAuditState {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectId,
        [Parameter(Mandatory = $true)][string]$RootFull
    )

    return [ordered]@{
        schema_version = "1.0"
        project_id = $ProjectId
        project_root = $RootFull
        session_continue_count = 0
        focused_audit_count = 0
        full_audit_count = 0
        last_focused_audit_at = $null
        last_full_audit_at = $null
        next_full_audit_due_session_number = 5
        last_audit_result = $null
        unresolved_conflict_count = 0
        unresolved_doubt_count = 0
        audit_trigger_history = @()
    }
}

function Convert-ToIntOrThrowStateJsonInvalid {
    param(
        [AllowNull()]$Value
    )

    try {
        return [int]$Value
    }
    catch {
        throw "STATE_JSON_INVALID"
    }
}

function Read-AuditState {
    param(
        [Parameter(Mandatory = $true)][string]$StateFull,
        [Parameter(Mandatory = $true)][string]$ProjectId,
        [Parameter(Mandatory = $true)][string]$RootFull
    )

    if (-not (Test-Path -LiteralPath $StateFull -PathType Leaf)) {
        return [pscustomobject](Get-DefaultAuditState -ProjectId $ProjectId -RootFull $RootFull)
    }

    try {
        $raw = Get-Content -LiteralPath $StateFull -Raw -Encoding UTF8
        $parsed = $raw | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "STATE_JSON_INVALID"
    }

    if ($null -eq $parsed) {
        throw "STATE_JSON_INVALID"
    }

    $requiredProps = @(
        "schema_version",
        "project_id",
        "project_root",
        "session_continue_count",
        "focused_audit_count",
        "full_audit_count",
        "next_full_audit_due_session_number",
        "unresolved_conflict_count",
        "unresolved_doubt_count",
        "audit_trigger_history"
    )

    foreach ($prop in $requiredProps) {
        if ($null -eq $parsed.PSObject.Properties[$prop]) {
            throw "STATE_JSON_INVALID"
        }
    }

    if ([string]$parsed.schema_version -ne "1.0") {
        throw "STATE_SCHEMA_VERSION_UNSUPPORTED"
    }

    if ([string]$parsed.project_id -ne $ProjectId) {
        throw "STATE_PROJECT_ID_MISMATCH"
    }

    $parsedRootFull = Get-NormalizedFullPath -Path ([string]$parsed.project_root)
    if (-not $parsedRootFull.Equals($RootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "STATE_PROJECT_ROOT_MISMATCH"
    }

    $sessionContinueCount = Convert-ToIntOrThrowStateJsonInvalid -Value $parsed.session_continue_count
    $focusedAuditCount = Convert-ToIntOrThrowStateJsonInvalid -Value $parsed.focused_audit_count
    $fullAuditCount = Convert-ToIntOrThrowStateJsonInvalid -Value $parsed.full_audit_count
    $nextDue = Convert-ToIntOrThrowStateJsonInvalid -Value $parsed.next_full_audit_due_session_number
    $unresolvedConflictCount = Convert-ToIntOrThrowStateJsonInvalid -Value $parsed.unresolved_conflict_count
    $unresolvedDoubtCount = Convert-ToIntOrThrowStateJsonInvalid -Value $parsed.unresolved_doubt_count

    if ($sessionContinueCount -lt 0 -or
        $focusedAuditCount -lt 0 -or
        $fullAuditCount -lt 0 -or
        $unresolvedConflictCount -lt 0 -or
        $unresolvedDoubtCount -lt 0) {
        throw "STATE_NEGATIVE_COUNTER"
    }

    if ($nextDue -le $sessionContinueCount) {
        throw "STATE_DUE_SESSION_BEHIND_COUNTER"
    }

    $history = @()
    try {
        $history = @($parsed.audit_trigger_history | ForEach-Object { [string]$_ })
    }
    catch {
        throw "STATE_JSON_INVALID"
    }

    return [pscustomobject][ordered]@{
        schema_version = "1.0"
        project_id = $ProjectId
        project_root = $RootFull
        session_continue_count = $sessionContinueCount
        focused_audit_count = $focusedAuditCount
        full_audit_count = $fullAuditCount
        last_focused_audit_at = $parsed.last_focused_audit_at
        last_full_audit_at = $parsed.last_full_audit_at
        next_full_audit_due_session_number = $nextDue
        last_audit_result = $parsed.last_audit_result
        unresolved_conflict_count = $unresolvedConflictCount
        unresolved_doubt_count = $unresolvedDoubtCount
        audit_trigger_history = @($history)
    }
}

function Get-CurrentUtcTimestamp {
    return (Get-Date).ToUniversalTime().ToString("o")
}

function Invoke-DocumentConsistencyAuditCore {
    $Context = $script:DocumentConsistencyAuditContext
    if ($null -eq $Context) {
        throw "RUNTIME_CONTEXT_MISSING"
    }

    $Mode = [string]$Context["Mode"]
    $ProjectRoot = [string]$Context["ProjectRoot"]
    $ProjectId = [string]$Context["ProjectId"]
    $StatePath = if ($Context.ContainsKey("StatePath")) { [string]$Context["StatePath"] } else { "" }
    $ChangedPaths = if ($Context.ContainsKey("ChangedPaths")) { [string[]]@($Context["ChangedPaths"]) } else { @() }
    $AcceptedSessionContinue = if ($Context.ContainsKey("AcceptedSessionContinue")) { [bool]$Context["AcceptedSessionContinue"] } else { $false }
    $HumanRequestedFullAudit = if ($Context.ContainsKey("HumanRequestedFullAudit")) { [bool]$Context["HumanRequestedFullAudit"] } else { $false }
    $NoStateWrite = if ($Context.ContainsKey("NoStateWrite")) { [bool]$Context["NoStateWrite"] } else { $false }
    $FullScanExcludeDirectories = if ($Context.ContainsKey("FullScanExcludeDirectories")) { [string[]]@($Context["FullScanExcludeDirectories"]) } else { @() }

    if ($Mode -notin @("focused", "full")) {
        throw "MODE_INVALID"
    }
    if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
        throw "PROJECT_ROOT_REQUIRED"
    }
    if ([string]::IsNullOrWhiteSpace($ProjectId)) {
        throw "PROJECT_ID_REQUIRED"
    }

    $rootFull = Get-NormalizedFullPath -Path $ProjectRoot
    if (-not (Test-Path -LiteralPath $rootFull -PathType Container)) {
        throw "PROJECT_ROOT_NOT_FOUND"
    }

    if (Test-ReparseTraversal -RootFull $rootFull -CandidateFull $rootFull) {
        throw "PROJECT_ROOT_REPARSE_POINT"
    }

    if ([string]::IsNullOrWhiteSpace($StatePath)) {
        $StatePath = Join-Path $rootFull "SyS\State\DOCUMENT.CONSISTENCY.AUDIT.STATE.json"
    }

    $stateFull = Resolve-GuardedPath `
        -RootFull $rootFull `
        -Candidate $StatePath `
        -CrossRootCode "CROSS_ROOT_STATE_PATH" `
        -ReparseCode "REPARSE_POINT_STATE_PATH"

    $validatedChangedPaths = New-Object System.Collections.Generic.List[object]
    foreach ($changedPath in @($ChangedPaths | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
        $changedFull = Resolve-GuardedPath `
            -RootFull $rootFull `
            -Candidate $changedPath `
            -CrossRootCode "CROSS_ROOT_CHANGED_PATH" `
            -ReparseCode "REPARSE_POINT_CHANGED_PATH"

        [void]$validatedChangedPaths.Add([pscustomobject][ordered]@{
            input_path = $changedPath
            full_path = $changedFull
            relative_path = Get-RelativePathSafe -RootFull $rootFull -PathFull $changedFull
        })
    }

    $state = Read-AuditState -StateFull $stateFull -ProjectId $ProjectId -RootFull $rootFull

    $triggerReasons = New-Object System.Collections.Generic.List[string]
    if ($HumanRequestedFullAudit) {
        [void]$triggerReasons.Add("EXPLICIT_HUMAN_REQUEST")
    }

    $criticalTokens = @(
        "HUMAN",
        "GRC",
        "SKILL",
        "BUILD.PS1",
        "REGISTRY",
        "VALIDATE-",
        "INVOKE-SKILLSMACHINEUPDATE",
        "SKILLSMACHINE.UPDATE",
        "SKILLSMACHINE.PROJECT.BASELINE"
    )

    $validatedChangedPathArray = $validatedChangedPaths.ToArray()
    foreach ($changed in $validatedChangedPathArray) {
        $pathToken = ([string]$changed.relative_path).ToUpperInvariant()
        foreach ($criticalToken in $criticalTokens) {
            if ($pathToken.Contains($criticalToken)) {
                [void]$triggerReasons.Add("CRITICAL_CHANGE:$($changed.relative_path)")
                break
            }
        }
    }

    if ($validatedChangedPathArray.Count -ge 20) {
        [void]$triggerReasons.Add("LARGE_DIFF_FILE_COUNT")
    }

    $projectedSessionContinueCount = [int]$state.session_continue_count
    if ($AcceptedSessionContinue) {
        $projectedSessionContinueCount += 1
    }

    $cadenceDue = ($projectedSessionContinueCount -eq [int]$state.next_full_audit_due_session_number)

    $effectiveMode = $Mode
    if ($Mode -eq "focused") {
        if ($cadenceDue) {
            $effectiveMode = "full"
            [void]$triggerReasons.Add("EVERY_FIFTH_ACCEPTED_SESSION")
        }
        elseif (@($triggerReasons).Count -gt 0) {
            $effectiveMode = "full"
        }
    }

    $roles = @(
        Resolve-DocumentRole -RootFull $rootFull -Role "HUMAN" -ProjectId $ProjectId -ExcludedDirectoryNames $FullScanExcludeDirectories
        Resolve-DocumentRole -RootFull $rootFull -Role "WHOAMI" -ProjectId $ProjectId -ExcludedDirectoryNames $FullScanExcludeDirectories
        Resolve-DocumentRole -RootFull $rootFull -Role "BATON" -ProjectId $ProjectId -ExcludedDirectoryNames $FullScanExcludeDirectories
    )

    $issues = New-Object System.Collections.Generic.List[object]
    foreach ($role in @($roles)) {
        if ($role.role -eq "HUMAN" -and $role.status -eq "NOT_FOUND") {
            [void]$issues.Add((New-Issue `
                -IssueClass "MISSING_REQUIRED_ROLE" `
                -Severity "BLOCKER" `
                -Title "HUMAN document is required" `
                -ExpectedValue "HUMAN.<PROJECT_ID>.md/.txt or HUMAN.md/.txt or other HUMAN.*.md/.txt" `
                -AuthorityLayer "HUMAN"))
            continue
        }

        if ($role.status -eq "HARD_CONFLICT") {
            [void]$issues.Add((New-Issue `
                -IssueClass "DUPLICATE_SOURCE_OF_TRUTH" `
                -Severity "HARD_CONFLICT" `
                -Title ("{0} role has equal-precedence ambiguity" -f $role.role) `
                -DocumentPath (@($role.candidates | ForEach-Object { $_.relative_path }) -join ";") `
                -ObservedValue ("candidates={0}" -f (@($role.candidates | Where-Object { $_.precedence_rank -eq $role.best_precedence_rank } | ForEach-Object { $_.file_name }) -join ",")) `
                -ExpectedValue "exactly one best-precedence candidate" `
                -AuthorityLayer $role.role))
        }
    }

    $documentsReviewed = New-Object System.Collections.Generic.List[object]
    $documentMap = @{}

    foreach ($role in @($roles)) {
        foreach ($candidate in @($role.candidates)) {
            if ($documentMap.ContainsKey([string]$candidate.relative_path)) {
                continue
            }

            $documentMap[[string]$candidate.relative_path] = $true
            [void]$documentsReviewed.Add([pscustomobject][ordered]@{
                relative_path = [string]$candidate.relative_path
                sha256 = [string]$candidate.sha256
                source = ("ROLE:{0}" -f $role.role)
            })
        }
    }

    if ($effectiveMode -eq "full") {
        $includeExtensions = @(".md", ".txt", ".json", ".ps1")
        foreach ($file in @(Get-SafeChildFiles -RootFull $rootFull -ExcludedDirectoryNames $FullScanExcludeDirectories)) {
            if ($includeExtensions -notcontains $file.Extension.ToLowerInvariant()) {
                continue
            }

            $relativePath = Get-RelativePathSafe -RootFull $rootFull -PathFull $file.FullName
            if ($documentMap.ContainsKey($relativePath)) {
                continue
            }

            $documentMap[$relativePath] = $true
            [void]$documentsReviewed.Add([pscustomobject][ordered]@{
                relative_path = $relativePath
                sha256 = Get-Sha256File -Path $file.FullName
                source = "FULL_SCAN"
            })
        }
    }

    $documentsReviewed = @(
        $documentsReviewed |
        Sort-Object @{ Expression = "relative_path"; Ascending = $true }, @{ Expression = "source"; Ascending = $true }
    )

    $updatedState = [ordered]@{
        schema_version = "1.0"
        project_id = $ProjectId
        project_root = $rootFull
        session_continue_count = $projectedSessionContinueCount
        focused_audit_count = [int]$state.focused_audit_count
        full_audit_count = [int]$state.full_audit_count
        last_focused_audit_at = $state.last_focused_audit_at
        last_full_audit_at = $state.last_full_audit_at
        next_full_audit_due_session_number = [int]$state.next_full_audit_due_session_number
        last_audit_result = $state.last_audit_result
        unresolved_conflict_count = 0
        unresolved_doubt_count = 0
        audit_trigger_history = @($state.audit_trigger_history)
    }

    if ($effectiveMode -eq "focused") {
        $updatedState.focused_audit_count = [int]$updatedState.focused_audit_count + 1
        if (-not $NoStateWrite) {
            $updatedState.last_focused_audit_at = Get-CurrentUtcTimestamp
        }
    }
    else {
        $updatedState.full_audit_count = [int]$updatedState.full_audit_count + 1
        if (-not $NoStateWrite) {
            $updatedState.last_full_audit_at = Get-CurrentUtcTimestamp
        }

        if ($cadenceDue) {
            $updatedState.next_full_audit_due_session_number = [int]$projectedSessionContinueCount + 5
        }
    }

    $sortedIssues = @(Sort-Issues -Issues $issues)
    $updatedState.unresolved_conflict_count = @($sortedIssues | Where-Object { $_.severity -in @("HARD_CONFLICT", "BLOCKER") }).Count
    $updatedState.unresolved_doubt_count = @($sortedIssues | Where-Object { $_.severity -eq "WARNING" }).Count
    $updatedState.last_audit_result = if (@($sortedIssues | Where-Object { $_.severity -eq "BLOCKER" }).Count -gt 0) {
        "BLOCKED"
    }
    elseif (@($sortedIssues | Where-Object { $_.severity -eq "HARD_CONFLICT" }).Count -gt 0) {
        "CONFLICTS_FOUND"
    }
    else {
        "PASS"
    }

    if (@($triggerReasons).Count -gt 0) {
        $updatedState.audit_trigger_history = @($updatedState.audit_trigger_history) + @($triggerReasons)
    }

    if (-not $NoStateWrite) {
        $stateParent = Split-Path -Parent $stateFull
        if (-not (Test-Path -LiteralPath $stateParent -PathType Container)) {
            New-Item -ItemType Directory -Path $stateParent -Force | Out-Null
        }

        Write-Utf8NoBom -Path $stateFull -Content (ConvertTo-JsonStable -InputObject ([pscustomobject]$updatedState))
    }

    $consumerStatus = if (@($sortedIssues | Where-Object { $_.severity -in @("HARD_CONFLICT", "BLOCKER") }).Count -gt 0) {
        "HARD_CONFLICT"
    }
    elseif (@($sortedIssues | Where-Object { $_.severity -eq "WARNING" }).Count -gt 0) {
        "WARNING"
    }
    else {
        "PASS"
    }

    return [ordered]@{
        schema_version = "1.0"
        status = $consumerStatus
        project_id = $ProjectId
        project_root = $rootFull
        requested_mode = $Mode
        effective_mode = $effectiveMode
        audit_trigger = @($triggerReasons | Sort-Object -Unique)
        full_scan_exclusions = @($FullScanExcludeDirectories | ForEach-Object { [string]$_ } | Sort-Object -Unique)
        documents_reviewed = @($documentsReviewed)
        document_roles = @($roles)
        issues = @($sortedIssues)
        summary = [ordered]@{
            conflicts_found = @($sortedIssues | Where-Object { $_.severity -in @("HARD_CONFLICT", "BLOCKER") }).Count
            warnings_found = @($sortedIssues | Where-Object { $_.severity -eq "WARNING" }).Count
            documents_reviewed_count = @($documentsReviewed).Count
            projected_session_continue_count = $projectedSessionContinueCount
            next_full_audit_due_session_number = [int]$updatedState.next_full_audit_due_session_number
            mandatory_human_status = [string](@($roles | Where-Object { $_.role -eq "HUMAN" })[0].status)
        }
        update_assessment = [ordered]@{
            recommended_support_package = "05.SKILLSMACHINE_UPDATE"
            automatic_execution = $false
            blocked_by_hard_conflict = (@($sortedIssues | Where-Object { $_.severity -in @("HARD_CONFLICT", "BLOCKER") }).Count -gt 0)
        }
        state_path = $stateFull
        state_written = (-not $NoStateWrite)
        state_snapshot = [ordered]@{
            session_continue_count = [int]$updatedState.session_continue_count
            focused_audit_count = [int]$updatedState.focused_audit_count
            full_audit_count = [int]$updatedState.full_audit_count
            next_full_audit_due_session_number = [int]$updatedState.next_full_audit_due_session_number
            unresolved_conflict_count = [int]$updatedState.unresolved_conflict_count
            unresolved_doubt_count = [int]$updatedState.unresolved_doubt_count
            last_audit_result = [string]$updatedState.last_audit_result
        }
    }
}

if ($MyInvocation.InvocationName -ne ".") {
    $invokeParams = @{
        Mode = $Mode
        ProjectRoot = $ProjectRoot
        ProjectId = $ProjectId
        ChangedPaths = [string[]]@($ChangedPaths)
        FullScanExcludeDirectories = [string[]]@($FullScanExcludeDirectories)
    }

    if (-not [string]::IsNullOrWhiteSpace($StatePath)) {
        $invokeParams.StatePath = $StatePath
    }
    if ($AcceptedSessionContinue) {
        $invokeParams.AcceptedSessionContinue = $true
    }
    if ($HumanRequestedFullAudit) {
        $invokeParams.HumanRequestedFullAudit = $true
    }
    if ($NoStateWrite) {
        $invokeParams.NoStateWrite = $true
    }

    $script:DocumentConsistencyAuditContext = $invokeParams
    try {
        $result = Invoke-DocumentConsistencyAuditCore
    }
    finally {
        Remove-Variable -Name DocumentConsistencyAuditContext -Scope Script -ErrorAction SilentlyContinue
    }

    $result | ConvertTo-Json -Depth 40
}
