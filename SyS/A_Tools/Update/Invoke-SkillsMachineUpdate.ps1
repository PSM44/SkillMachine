[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("preflight", "dry-run", "apply", "rollback", "recover")]
    [string]$Action,

    [Parameter(Mandatory = $true)]
    [string]$ProjectRoot,

    [string]$UpdateManifest,

    [string]$BaselinePath,

    [Parameter(Mandatory = $true)]
    [string]$EvidencePath,

    [switch]$HumanApproved,

    [string]$ApprovedDryRunFingerprint,

    [string]$CheckpointManifest,

    [switch]$TestMode,

    [switch]$UseDocumentAuditPreflight,

    [string]$DocumentAuditStatePath
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$RunnerVersion = "0.1.0-MVP"
$RunStamp = Get-Date -Format "yyyyMMdd_HHmmss"

. (Join-Path $PSScriptRoot "Eligibility.ps1")

function Write-Utf8NoBom {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Content
    )
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $utf8)
}

function Get-Sha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function Get-CanonicalObjectHash {
    param([Parameter(Mandatory = $true)][object]$Value)
    $json = $Value | ConvertTo-Json -Depth 30 -Compress
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace("-", "")
    }
    finally {
        $sha.Dispose()
    }
}

function Resolve-SafeRelativePath {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$RelativePath
    )

    if ([System.IO.Path]::IsPathRooted($RelativePath)) {
        throw "ROOTED_PATH_NOT_ALLOWED: $RelativePath"
    }

    $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd("\", "/")
    $candidate = [System.IO.Path]::GetFullPath((Join-Path $rootFull $RelativePath))
    $prefix = $rootFull + [System.IO.Path]::DirectorySeparatorChar

    if ($candidate -ne $rootFull -and -not $candidate.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "PATH_ESCAPES_ROOT: $RelativePath"
    }

    return $candidate
}

function Test-GitClean {
    param([Parameter(Mandatory = $true)][string]$Root)

    if (-not (Test-Path -LiteralPath (Join-Path $Root ".git") -PathType Container)) {
        throw "PROJECT_GIT_REQUIRED"
    }

    $status = & git -C $Root status --short --untracked-files=all 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "PROJECT_GIT_STATUS_FAILED: $($status -join ' | ')"
    }

    $lines = @($status | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($lines.Count -gt 0) {
        throw "BLOCKED_DIRTY_WORKTREE: $($lines -join ' | ')"
    }
}

# MB-SM-065A-5B TRANSACTION HELPERS
function Get-UpdateTransactionPaths {
    param([Parameter(Mandatory = $true)][string]$Root)

    $transactionRoot = Join-Path $Root ".git\skillsmachine-update"
    return [ordered]@{
        root = $transactionRoot
        state = Join-Path $transactionRoot "UPDATE.TRANSACTION.STATE.json"
    }
}

function Get-ProjectMutexName {
    param([Parameter(Mandatory = $true)][string]$Root)

    $normalized = [System.IO.Path]::GetFullPath($Root).ToUpperInvariant()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($normalized)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hash = ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace("-", "")
    }
    finally {
        $sha.Dispose()
    }

    return "Local\SkillsMachine.Update.$hash"
}

function Enter-UpdateTransactionMutex {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$TransactionAction
    )

    $name = Get-ProjectMutexName -Root $Root
    $mutex = [System.Threading.Mutex]::new($false, $name)
    $acquired = $false

    try {
        $acquired = $mutex.WaitOne(0)
    }
    catch [System.Threading.AbandonedMutexException] {
        $acquired = $true
    }

    if (-not $acquired) {
        $mutex.Dispose()
        throw "BLOCKED_UPDATE_TRANSACTION_ACTIVE: action=$TransactionAction"
    }

    return $mutex
}

function Exit-UpdateTransactionMutex {
    param([System.Threading.Mutex]$Mutex)

    if ($null -eq $Mutex) {
        return
    }

    try {
        $Mutex.ReleaseMutex()
    }
    catch {
    }
    finally {
        $Mutex.Dispose()
    }
}

function Write-AtomicJson {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][object]$Value
    )

    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }

    $temporary = "$Path.tmp.$([guid]::NewGuid().ToString('N'))"
    try {
        Write-Utf8NoBom -Path $temporary -Content ($Value | ConvertTo-Json -Depth 30)
        Move-Item -LiteralPath $temporary -Destination $Path -Force
    }
    finally {
        if (Test-Path -LiteralPath $temporary) {
            Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
        }
    }
}

function Write-UpdateTransactionState {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Phase,
        [Parameter(Mandatory = $true)][string]$TransactionId,
        [Parameter(Mandatory = $true)][string]$TransactionAction,
        [string]$UpdateId,
        [string]$CheckpointManifestPath,
        [string]$LastOperationId,
        [string]$Failure
    )

    $state = [ordered]@{
        schema_version = "1.0"
        transaction_id = $TransactionId
        process_id = $PID
        host = [Environment]::MachineName
        action = $TransactionAction
        phase = $Phase
        update_id = $UpdateId
        checkpoint_manifest = $CheckpointManifestPath
        last_operation_id = $LastOperationId
        failure = $Failure
        updated_at = (Get-Date).ToUniversalTime().ToString("o")
    }

    Write-AtomicJson -Path $Path -Value $state
}

function Remove-UpdateTransactionState {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        Remove-Item -LiteralPath $Path -Force
    }
}

function Restore-UpdateCheckpoint {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$BaselineFile,
        [Parameter(Mandatory = $true)][string]$CheckpointFile
    )

    $checkpoint = Read-JsonFile -Path $CheckpointFile
    $zipPath = [string]$checkpoint.checkpoint_zip
    if (-not (Test-Path -LiteralPath $zipPath -PathType Leaf)) {
        throw "CHECKPOINT_ZIP_NOT_FOUND"
    }

    $extractRoot = Join-Path $env:TEMP (
        "SkillsMachineCheckpointRestore.{0}" -f ([guid]::NewGuid().ToString("N"))
    )
    New-Item -ItemType Directory -Path $extractRoot -Force | Out-Null

    try {
        Expand-Archive -LiteralPath $zipPath -DestinationPath $extractRoot -Force

        foreach ($entry in @($checkpoint.entries)) {
            $targetFull = Resolve-SafeRelativePath `
                -Root $Root `
                -RelativePath ([string]$entry.target_path)

            if ([bool]$entry.pre_exists) {
                $backupFull = Join-Path $extractRoot ([string]$entry.backup_relative_path)
                if (-not (Test-Path -LiteralPath $backupFull -PathType Leaf)) {
                    throw "ROLLBACK_BACKUP_FILE_MISSING: $backupFull"
                }

                $parent = Split-Path -Parent $targetFull
                if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
                    New-Item -ItemType Directory -Path $parent -Force | Out-Null
                }

                Copy-Item -LiteralPath $backupFull -Destination $targetFull -Force
                if ((Get-Sha256 -Path $targetFull) -ne [string]$entry.pre_hash) {
                    throw "ROLLBACK_HASH_MISMATCH: $($entry.target_path)"
                }
            }
            elseif (Test-Path -LiteralPath $targetFull) {
                Remove-Item -LiteralPath $targetFull -Force
            }
        }

        $baselineBackup = Join-Path $extractRoot "__baseline.json"
        if (-not (Test-Path -LiteralPath $baselineBackup -PathType Leaf)) {
            throw "ROLLBACK_BASELINE_BACKUP_MISSING"
        }

        Copy-Item -LiteralPath $baselineBackup -Destination $BaselineFile -Force
        if ((Get-Sha256 -Path $BaselineFile) -ne [string]$checkpoint.baseline_pre_hash) {
            throw "ROLLBACK_BASELINE_HASH_MISMATCH"
        }

        return [ordered]@{
            checkpoint_manifest = $CheckpointFile
            checkpoint_zip = $zipPath
            restored_entries = @($checkpoint.entries).Count
            baseline_restored = $true
        }
    }
    finally {
        if (Test-Path -LiteralPath $extractRoot) {
            Remove-Item -LiteralPath $extractRoot -Recurse -Force
        }
    }
}

function ConvertTo-SemVer {
    param([Parameter(Mandatory = $true)][string]$Version)
    if ($Version -notmatch '^([0-9]+)\.([0-9]+)\.([0-9]+)$') {
        throw "INVALID_SEMVER: $Version"
    }
    return [version]$Version
}

function Test-VersionCompatible {
    param(
        [Parameter(Mandatory = $true)][string]$Current,
        [Parameter(Mandatory = $true)][string]$Minimum,
        [Parameter(Mandatory = $true)][string]$Maximum
    )

    $currentVersion = ConvertTo-SemVer -Version $Current
    $minimumVersion = ConvertTo-SemVer -Version $Minimum

    if ($currentVersion -lt $minimumVersion) {
        return $false
    }

    if ($Maximum -match '^([0-9]+)\.([0-9]+)\.x$') {
        return ($currentVersion.Major -eq [int]$Matches[1] -and $currentVersion.Minor -eq [int]$Matches[2])
    }

    $maximumVersion = ConvertTo-SemVer -Version $Maximum
    return ($currentVersion -le $maximumVersion)
}

function Read-JsonFile {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "JSON_FILE_NOT_FOUND: $Path"
    }
    return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop)
}

function Assert-ManifestContract {
    param([Parameter(Mandatory = $true)][object]$Manifest)

    if ([string]$Manifest.schema_version -ne "1.1") {
        throw "UNSUPPORTED_UPDATE_SCHEMA_VERSION"
    }
    if (-not [bool]$Manifest.reversible) {
        throw "IRREVERSIBLE_UPDATE_BLOCKED"
    }
    if (-not [bool]$Manifest.human_approval_required) {
        throw "HUMAN_APPROVAL_CONTRACT_REQUIRED"
    }

    $operations = @($Manifest.operations)
    if ($operations.Count -lt 1) {
        throw "UPDATE_REQUIRES_OPERATIONS"
    }

    $ids = @{}
    foreach ($operation in $operations) {
        $id = [string]$operation.operation_id
        if ([string]::IsNullOrWhiteSpace($id)) {
            throw "OPERATION_ID_REQUIRED"
        }
        if ($ids.ContainsKey($id)) {
            throw "DUPLICATE_OPERATION_ID: $id"
        }
        $ids[$id] = $true

        $action = [string]$operation.action
        if ($action -notin @("ADD", "REPLACE", "DELETE")) {
            throw "UNSUPPORTED_OPERATION_ACTION: $action"
        }
        if (-not [bool]$operation.reversible) {
            throw "IRREVERSIBLE_OPERATION_BLOCKED: $id"
        }

        $targetPath = [string]$operation.target_path
        if ([string]::IsNullOrWhiteSpace($targetPath)) {
            throw "TARGET_PATH_REQUIRED: $id"
        }

        if ($action -eq "ADD") {
            if ($null -ne $operation.expected_pre_hash) {
                throw "ADD_PRE_HASH_MUST_BE_NULL: $id"
            }
            if ([string]::IsNullOrWhiteSpace([string]$operation.expected_post_hash)) {
                throw "ADD_POST_HASH_REQUIRED: $id"
            }
            if ([string]::IsNullOrWhiteSpace([string]$operation.source_path)) {
                throw "ADD_SOURCE_REQUIRED: $id"
            }
        }

        if ($action -eq "REPLACE") {
            if ([string]::IsNullOrWhiteSpace([string]$operation.expected_pre_hash)) {
                throw "REPLACE_PRE_HASH_REQUIRED: $id"
            }
            if ([string]::IsNullOrWhiteSpace([string]$operation.expected_post_hash)) {
                throw "REPLACE_POST_HASH_REQUIRED: $id"
            }
            if ([string]::IsNullOrWhiteSpace([string]$operation.source_path)) {
                throw "REPLACE_SOURCE_REQUIRED: $id"
            }
            if (-not [bool]$operation.backup_required) {
                throw "REPLACE_BACKUP_REQUIRED: $id"
            }
        }

        if ($action -eq "DELETE") {
            if ([string]::IsNullOrWhiteSpace([string]$operation.expected_pre_hash)) {
                throw "DELETE_PRE_HASH_REQUIRED: $id"
            }
            if ($null -ne $operation.expected_post_hash) {
                throw "DELETE_POST_HASH_MUST_BE_NULL: $id"
            }
            if (-not [bool]$operation.backup_required) {
                throw "DELETE_BACKUP_REQUIRED: $id"
            }
        }
    }
}

function Get-OperationEvaluation {
    param(
        [Parameter(Mandatory = $true)][object]$Manifest,
        [Parameter(Mandatory = $true)][string]$ManifestDirectory,
        [Parameter(Mandatory = $true)][string]$Root
    )

    $evaluations = New-Object System.Collections.Generic.List[object]

    foreach ($operation in @($Manifest.operations)) {
        $action = [string]$operation.action
        $targetFull = Resolve-SafeRelativePath -Root $Root -RelativePath ([string]$operation.target_path)
        $targetExists = Test-Path -LiteralPath $targetFull -PathType Leaf
        $actualPreHash = if ($targetExists) { Get-Sha256 -Path $targetFull } else { $null }

        $sourceFull = $null
        $actualSourceHash = $null
        if ($action -in @("ADD", "REPLACE")) {
            $sourceFull = Resolve-SafeRelativePath -Root $ManifestDirectory -RelativePath ([string]$operation.source_path)
            if (-not (Test-Path -LiteralPath $sourceFull -PathType Leaf)) {
                throw "SOURCE_FILE_NOT_FOUND: $sourceFull"
            }
            $actualSourceHash = Get-Sha256 -Path $sourceFull
        }

        if ($action -eq "ADD") {
            if ($targetExists) {
                throw "ADD_TARGET_ALREADY_EXISTS: $targetFull"
            }
            if ($actualSourceHash -ne [string]$operation.expected_post_hash) {
                throw "ADD_SOURCE_HASH_MISMATCH: $($operation.operation_id)"
            }
        }

        if ($action -eq "REPLACE") {
            if (-not $targetExists) {
                throw "REPLACE_TARGET_MISSING: $targetFull"
            }
            if ($actualPreHash -ne [string]$operation.expected_pre_hash) {
                throw "REPLACE_PRE_HASH_MISMATCH: $($operation.operation_id)"
            }
            if ($actualSourceHash -ne [string]$operation.expected_post_hash) {
                throw "REPLACE_SOURCE_HASH_MISMATCH: $($operation.operation_id)"
            }
        }

        if ($action -eq "DELETE") {
            if (-not $targetExists) {
                throw "DELETE_TARGET_MISSING: $targetFull"
            }
            if ($actualPreHash -ne [string]$operation.expected_pre_hash) {
                throw "DELETE_PRE_HASH_MISMATCH: $($operation.operation_id)"
            }
        }

        [void]$evaluations.Add([ordered]@{
            operation_id = [string]$operation.operation_id
            action = $action
            source_path = if ($null -eq $operation.source_path) { $null } else { [string]$operation.source_path }
            target_path = [string]$operation.target_path
            expected_pre_hash = if ($null -eq $operation.expected_pre_hash) { $null } else { [string]$operation.expected_pre_hash }
            expected_post_hash = if ($null -eq $operation.expected_post_hash) { $null } else { [string]$operation.expected_post_hash }
            actual_pre_hash = $actualPreHash
            actual_source_hash = $actualSourceHash
            target_exists = $targetExists
        })
    }

    return $evaluations.ToArray()
}

function Get-DryRunState {
    param(
        [Parameter(Mandatory = $true)][object]$Baseline,
        [Parameter(Mandatory = $true)][object]$Manifest,
        [Parameter(Mandatory = $true)][object[]]$Evaluations
    )

    $state = [ordered]@{
        project_id = [string]$Baseline.project_id
        current_version = [string]$Baseline.skillsmachine_version
        target_version = [string]$Manifest.update_version
        update_id = [string]$Manifest.update_id
        source_commit = [string]$Manifest.source_commit
        operations = @($Evaluations | ForEach-Object {
            [ordered]@{
                operation_id = $_.operation_id
                action = $_.action
                source_path = $_.source_path
                target_path = $_.target_path
                expected_pre_hash = $_.expected_pre_hash
                expected_post_hash = $_.expected_post_hash
                actual_pre_hash = $_.actual_pre_hash
                actual_source_hash = $_.actual_source_hash
                target_exists = $_.target_exists
            }
        })
    }

    return [ordered]@{
        state = $state
        fingerprint = Get-CanonicalObjectHash -Value $state
    }
}

function Update-BaselineAfterApply {
    param(
        [Parameter(Mandatory = $true)][object]$Baseline,
        [Parameter(Mandatory = $true)][object]$Manifest
    )

    $inventory = New-Object System.Collections.Generic.List[object]
    foreach ($item in @($Baseline.component_inventory)) {
        [void]$inventory.Add([ordered]@{
            component_type = [string]$item.component_type
            relative_path = [string]$item.relative_path
            sha256 = [string]$item.sha256
            version = [string]$item.version
        })
    }

    foreach ($operation in @($Manifest.operations)) {
        $target = [string]$operation.target_path
        $remaining = @($inventory | Where-Object { $_.relative_path -ne $target })
        $inventory = New-Object System.Collections.Generic.List[object]
        foreach ($entry in $remaining) {
            [void]$inventory.Add($entry)
        }

        if ([string]$operation.action -ne "DELETE") {
            [void]$inventory.Add([ordered]@{
                component_type = "updated_file"
                relative_path = $target
                sha256 = [string]$operation.expected_post_hash
                version = [string]$Manifest.update_version
            })
        }
    }

    return New-SkillsMachineBaselineAfterApply `
        -Baseline $Baseline `
        -Manifest $Manifest `
        -Inventory $inventory.ToArray()
}

function Write-ActionEvidence {
    param(
        [Parameter(Mandatory = $true)][string]$Status,
        [Parameter(Mandatory = $true)][object]$Data
    )

    if (-not (Test-Path -LiteralPath $EvidencePath -PathType Container)) {
        New-Item -ItemType Directory -Path $EvidencePath -Force | Out-Null
    }

    $evidence = [ordered]@{
        runner_version = $RunnerVersion
        action = $Action
        status = $Status
        generated_at = (Get-Date).ToUniversalTime().ToString("o")
        data = $Data
    }

    $jsonPath = Join-Path $EvidencePath ("UPDATE.{0}.{1}.json" -f $Action.ToUpperInvariant(), $RunStamp)
    Write-Utf8NoBom -Path $jsonPath -Content ($evidence | ConvertTo-Json -Depth 30)

    Write-Host "EVIDENCE_PATH=$jsonPath"
    return $jsonPath
}

function Get-DocumentAuditRunnerPath {
    $candidate = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\DocumentConsistencyAudit\Invoke-DocumentConsistencyAudit.ps1"))
    if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
        throw "DOCUMENT_AUDIT_RUNNER_NOT_FOUND"
    }

    return $candidate
}

function Get-DocumentAuditChangedPaths {
    param([Parameter(Mandatory = $true)][object]$Manifest)

    return @(
        @($Manifest.operations | ForEach-Object { [string]$_.target_path }) |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Sort-Object -Unique
    )
}

function Get-DocumentAuditFailureClass {
    param([Parameter(Mandatory = $true)][string]$Message)

    if ($Message -like "STATE_*") {
        return "STATE_ERROR"
    }

    if (
        $Message -like "CROSS_ROOT_*" -or
        $Message -like "REPARSE_POINT_*" -or
        $Message -like "PATH_ESCAPES_ROOT*" -or
        $Message -like "ROOTED_PATH_NOT_ALLOWED*" -or
        $Message -eq "PROJECT_ROOT_REPARSE_POINT"
    ) {
        return "ROOT_SCOPE_VIOLATION"
    }

    return "AUDIT_FAILURE"
}

function Invoke-DocumentAuditPreflight {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][object]$Baseline,
        [Parameter(Mandatory = $true)][object]$Manifest
    )

    $auditRunner = Get-DocumentAuditRunnerPath
    $auditParams = @{
        Mode = "focused"
        ProjectRoot = $Root
        ProjectId = [string]$Baseline.project_id
        ChangedPaths = @(Get-DocumentAuditChangedPaths -Manifest $Manifest)
        NoStateWrite = $true
    }

    if (-not [string]::IsNullOrWhiteSpace($DocumentAuditStatePath)) {
        $auditParams.StatePath = $DocumentAuditStatePath
    }

    try {
        $auditOutput = & $auditRunner @auditParams 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw (($auditOutput | ForEach-Object { [string]$_ }) -join " | ")
        }

        $auditJson = (($auditOutput | ForEach-Object { [string]$_ }) -join [Environment]::NewLine)
        $audit = $auditJson | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        $auditMessage = $_.Exception.Message
        $failureClass = Get-DocumentAuditFailureClass -Message $auditMessage
        throw ("DOCUMENT_AUDIT_{0}: {1}" -f $failureClass, $auditMessage)
    }

    $auditStatus = [string]$audit.status
    if ($auditStatus -eq "HARD_CONFLICT") {
        $issueClasses = @($audit.issues | ForEach-Object { [string]$_.issue_class } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
        $blockMessage = ("DOCUMENT_AUDIT_HARD_CONFLICT_BLOCKED: {0}" -f (($issueClasses -join ",").Trim(",")))
        Write-Host $blockMessage
        throw $blockMessage
    }

    return [ordered]@{
        status = $auditStatus
        effective_mode = [string]$audit.effective_mode
        changed_paths = @(Get-DocumentAuditChangedPaths -Manifest $Manifest)
        conflicts_found = [int]$audit.summary.conflicts_found
        warnings_found = [int]$audit.summary.warnings_found
        blocked_by_hard_conflict = [bool]$audit.update_assessment.blocked_by_hard_conflict
        automatic_execution = [bool]$audit.update_assessment.automatic_execution
        recommended_support_package = [string]$audit.update_assessment.recommended_support_package
    }
}

$ProjectRoot = [System.IO.Path]::GetFullPath($ProjectRoot)
if (-not (Test-Path -LiteralPath $ProjectRoot -PathType Container)) {
    throw "PROJECT_ROOT_NOT_FOUND"
}

if ([string]::IsNullOrWhiteSpace($BaselinePath)) {
    $BaselinePath = Join-Path $ProjectRoot "SKILLSMACHINE.PROJECT.BASELINE.json"
}
else {
    $BaselinePath = [System.IO.Path]::GetFullPath($BaselinePath)
}

$transactionPaths = Get-UpdateTransactionPaths -Root $ProjectRoot
$transactionStatePath = [string]$transactionPaths.state
$transactionMutex = $null
$transactionId = [guid]::NewGuid().ToString("N")

if ($Action -eq "recover") {
    $transactionMutex = Enter-UpdateTransactionMutex `
        -Root $ProjectRoot `
        -TransactionAction "recover"

    try {
        if (-not (Test-Path -LiteralPath $transactionStatePath -PathType Leaf)) {
            Write-Host "FINAL_STATUS=NO_RECOVERY_REQUIRED"
            exit 0
        }

        $state = Read-JsonFile -Path $transactionStatePath
        $recoverablePhases = @(
            "CHECKPOINT_CREATED",
            "APPLYING",
            "ROLLING_BACK",
            "FAILED_ROLLBACK_FAIL"
        )

        if ([string]$state.phase -notin $recoverablePhases) {
            throw "TRANSACTION_STATE_NOT_RECOVERABLE: $($state.phase)"
        }
        if ([string]::IsNullOrWhiteSpace([string]$state.checkpoint_manifest)) {
            throw "TRANSACTION_CHECKPOINT_REQUIRED_FOR_RECOVERY"
        }

        Write-UpdateTransactionState `
            -Path $transactionStatePath `
            -Phase "ROLLING_BACK" `
            -TransactionId ([string]$state.transaction_id) `
            -TransactionAction "recover" `
            -UpdateId ([string]$state.update_id) `
            -CheckpointManifestPath ([string]$state.checkpoint_manifest) `
            -LastOperationId ([string]$state.last_operation_id)

        $data = Restore-UpdateCheckpoint `
            -Root $ProjectRoot `
            -BaselineFile $BaselinePath `
            -CheckpointFile ([string]$state.checkpoint_manifest)

        Write-UpdateTransactionState `
            -Path $transactionStatePath `
            -Phase "ROLLED_BACK" `
            -TransactionId ([string]$state.transaction_id) `
            -TransactionAction "recover" `
            -UpdateId ([string]$state.update_id) `
            -CheckpointManifestPath ([string]$state.checkpoint_manifest)

        [void](Write-ActionEvidence -Status "PASS_RECOVERY" -Data $data)
        Remove-UpdateTransactionState -Path $transactionStatePath

        Write-Host "RECOVERY_STATUS=PASS"
        Write-Host "FINAL_STATUS=PASS_RECOVERY"
        exit 0
    }
    finally {
        Exit-UpdateTransactionMutex -Mutex $transactionMutex
    }
}

if ($Action -eq "rollback") {
    $transactionMutex = Enter-UpdateTransactionMutex `
        -Root $ProjectRoot `
        -TransactionAction "rollback"

    try {
        if ([string]::IsNullOrWhiteSpace($CheckpointManifest)) {
            throw "CHECKPOINT_MANIFEST_REQUIRED"
        }

        Write-UpdateTransactionState `
            -Path $transactionStatePath `
            -Phase "ROLLING_BACK" `
            -TransactionId $transactionId `
            -TransactionAction "rollback" `
            -CheckpointManifestPath $CheckpointManifest

        $data = Restore-UpdateCheckpoint `
            -Root $ProjectRoot `
            -BaselineFile $BaselinePath `
            -CheckpointFile $CheckpointManifest

        Write-UpdateTransactionState `
            -Path $transactionStatePath `
            -Phase "ROLLED_BACK" `
            -TransactionId $transactionId `
            -TransactionAction "rollback" `
            -CheckpointManifestPath $CheckpointManifest

        [void](Write-ActionEvidence -Status "PASS" -Data $data)
        Remove-UpdateTransactionState -Path $transactionStatePath

        Write-Host "FINAL_STATUS=PASS_ROLLBACK"
        exit 0
    }
    finally {
        Exit-UpdateTransactionMutex -Mutex $transactionMutex
    }
}

if ([string]::IsNullOrWhiteSpace($UpdateManifest)) {
    throw "UPDATE_MANIFEST_REQUIRED"
}

$UpdateManifest = [System.IO.Path]::GetFullPath($UpdateManifest)
$manifestDirectory = Split-Path -Parent $UpdateManifest
$manifest = Read-JsonFile -Path $UpdateManifest
$baseline = Read-JsonFile -Path $BaselinePath

Assert-ManifestContract -Manifest $manifest

$eligibility = Assert-SkillsMachineProjectEligibility -Baseline $baseline
Write-Host ("ELIGIBILITY_MODE={0}" -f [string]$eligibility.Mode)
Write-Host ("ELIGIBILITY_REASON={0}" -f [string]$eligibility.Reason)
if (-not (Test-VersionCompatible `
    -Current ([string]$baseline.skillsmachine_version) `
    -Minimum ([string]$manifest.minimum_project_version) `
    -Maximum ([string]$manifest.maximum_project_version))) {
    throw "BLOCKED_UNSUPPORTED_BASELINE"
}

# MB-SM-065A-3R IDEMPOTENCY GATE
# A project whose baseline already records this exact update and target version is
# already compliant. Return before operation evaluation so ADD/REPLACE/DELETE are
# not re-applied and no approval fingerprint or checkpoint is required.
$alreadyApplied = (
    [string]$baseline.last_update_id -eq [string]$manifest.update_id -and
    [string]$baseline.skillsmachine_version -eq [string]$manifest.update_version
)

if ($alreadyApplied -and $Action -in @("preflight", "dry-run", "apply")) {
    Test-GitClean -Root $ProjectRoot

    New-Item -ItemType Directory -Force -Path $EvidencePath | Out-Null
    $alreadyAppliedEvidence = [ordered]@{
        action = $Action
        project_id = [string]$baseline.project_id
        update_id = [string]$manifest.update_id
        current_version = [string]$baseline.skillsmachine_version
        target_version = [string]$manifest.update_version
        already_applied = $true
        mutation_performed = $false
        checked_at = (Get-Date).ToUniversalTime().ToString("o")
    }
    $alreadyAppliedEvidencePath = Join-Path $EvidencePath (
        "UPDATE.ALREADY_APPLIED.{0}.{1}.json" -f $manifest.update_id, $RunStamp
    )
    Write-Utf8NoBom -Path $alreadyAppliedEvidencePath -Content (
        $alreadyAppliedEvidence | ConvertTo-Json -Depth 10
    )

    Write-Host "ALREADY_APPLIED=True"
    Write-Host "UPDATE_ID=$($manifest.update_id)"
    Write-Host "CURRENT_VERSION=$($baseline.skillsmachine_version)"
    Write-Host "EVIDENCE_FILE=$alreadyAppliedEvidencePath"
    Write-Host "FINAL_STATUS=ALREADY_APPLIED"
    exit 0
}
if (
    $Action -eq "apply" -and
    (Test-Path -LiteralPath $transactionStatePath -PathType Leaf)
) {
    $pendingState = Read-JsonFile -Path $transactionStatePath
    if ([string]$pendingState.phase -in @(
        "CHECKPOINT_CREATED",
        "APPLYING",
        "ROLLING_BACK",
        "FAILED_ROLLBACK_FAIL"
    )) {
        throw "INTERRUPTED_UPDATE_RECOVERY_REQUIRED: phase=$($pendingState.phase)"
    }
}

Test-GitClean -Root $ProjectRoot
$evaluations = @(Get-OperationEvaluation -Manifest $manifest -ManifestDirectory $manifestDirectory -Root $ProjectRoot)
$dryRun = Get-DryRunState -Baseline $baseline -Manifest $manifest -Evaluations $evaluations
$documentAudit = $null
if ($UseDocumentAuditPreflight) {
    $documentAudit = Invoke-DocumentAuditPreflight -Root $ProjectRoot -Baseline $baseline -Manifest $manifest
    Write-Host "DOCUMENT_AUDIT_STATUS=$($documentAudit.status)"
    Write-Host "DOCUMENT_AUDIT_EFFECTIVE_MODE=$($documentAudit.effective_mode)"
}

if ($Action -eq "preflight") {
    $data = [ordered]@{
        project_id = [string]$baseline.project_id
        current_version = [string]$baseline.skillsmachine_version
        target_version = [string]$manifest.update_version
        compatibility_status = "COMPATIBLE"
        operation_count = $evaluations.Count
        reversible = $true
        human_approval_required = $true
        repository_mutation = $false
        document_audit = $documentAudit
    }
    [void](Write-ActionEvidence -Status "PASS" -Data $data)
    Write-Host "FINAL_STATUS=PASS_PREFLIGHT"
    exit 0
}

if ($Action -eq "dry-run") {
    $data = [ordered]@{
        project_id = [string]$baseline.project_id
        current_version = [string]$baseline.skillsmachine_version
        target_version = [string]$manifest.update_version
        update_id = [string]$manifest.update_id
        compatibility_status = "COMPATIBLE"
        dry_run_fingerprint = [string]$dryRun.fingerprint
        files_add = @($evaluations | Where-Object { $_.action -eq "ADD" }).Count
        files_modify = @($evaluations | Where-Object { $_.action -eq "REPLACE" }).Count
        files_delete = @($evaluations | Where-Object { $_.action -eq "DELETE" }).Count
        operations = @($dryRun.state.operations)
        repository_mutation = $false
        document_audit = $documentAudit
    }
    [void](Write-ActionEvidence -Status "PASS" -Data $data)
    Write-Host "DRY_RUN_FINGERPRINT=$($dryRun.fingerprint)"
    Write-Host "FINAL_STATUS=PASS_DRY_RUN"
    exit 0
}

if ($Action -eq "apply") {
    if (-not $HumanApproved) {
        throw "HUMAN_APPROVAL_REQUIRED"
    }
    if ([string]::IsNullOrWhiteSpace($ApprovedDryRunFingerprint)) {
        throw "APPROVED_DRY_RUN_FINGERPRINT_REQUIRED"
    }
    if ($ApprovedDryRunFingerprint -ne [string]$dryRun.fingerprint) {
        throw "DRY_RUN_FINGERPRINT_MISMATCH"
    }

    $transactionMutex = Enter-UpdateTransactionMutex `
        -Root $ProjectRoot `
        -TransactionAction "apply"

    Write-UpdateTransactionState `
        -Path $transactionStatePath `
        -Phase "PREPARED" `
        -TransactionId $transactionId `
        -TransactionAction "apply" `
        -UpdateId ([string]$manifest.update_id)

    if (
        $TestMode -and
        -not [string]::IsNullOrWhiteSpace($env:SKILLSMACHINE_TEST_HOLD_LOCK_SECONDS)
    ) {
        $testProjectId = [string]$baseline.project_id
        if (
            $testProjectId.StartsWith("TEST_", [System.StringComparison]::OrdinalIgnoreCase) -or
            $testProjectId.StartsWith("NEGATIVE_TEST_", [System.StringComparison]::OrdinalIgnoreCase)
        ) {
            Start-Sleep -Seconds ([int]$env:SKILLSMACHINE_TEST_HOLD_LOCK_SECONDS)
        }
    }

    $checkpointWork = Join-Path $env:TEMP ("SkillsMachineCheckpoint.{0}" -f ([guid]::NewGuid().ToString("N")))
    $checkpointManifestPath = $null
    $checkpointZip = $null
    New-Item -ItemType Directory -Path $checkpointWork -Force | Out-Null

    try {
        $checkpointEntries = New-Object System.Collections.Generic.List[object]

        foreach ($evaluation in $evaluations) {
            $targetFull = Resolve-SafeRelativePath -Root $ProjectRoot -RelativePath ([string]$evaluation.target_path)
            $backupRelative = $null

            if ([bool]$evaluation.target_exists) {
                $backupRelative = Join-Path "files" ([string]$evaluation.operation_id + ".bin")
                $backupFull = Join-Path $checkpointWork $backupRelative
                $backupParent = Split-Path -Parent $backupFull
                if (-not (Test-Path -LiteralPath $backupParent -PathType Container)) {
                    New-Item -ItemType Directory -Path $backupParent -Force | Out-Null
                }
                Copy-Item -LiteralPath $targetFull -Destination $backupFull -Force
            }

            [void]$checkpointEntries.Add([ordered]@{
                operation_id = [string]$evaluation.operation_id
                target_path = [string]$evaluation.target_path
                pre_exists = [bool]$evaluation.target_exists
                pre_hash = $evaluation.actual_pre_hash
                backup_relative_path = $backupRelative
            })
        }

        Copy-Item -LiteralPath $BaselinePath -Destination (Join-Path $checkpointWork "__baseline.json") -Force
        $baselinePreHash = Get-Sha256 -Path $BaselinePath

        $checkpointZip = Join-Path $EvidencePath ("UPDATE.CHECKPOINT.{0}.{1}.zip" -f $manifest.update_id, $RunStamp)
        if (-not (Test-Path -LiteralPath $EvidencePath -PathType Container)) {
            New-Item -ItemType Directory -Path $EvidencePath -Force | Out-Null
        }
        Compress-Archive -Path (Join-Path $checkpointWork "*") -DestinationPath $checkpointZip -Force

        $checkpointObject = [ordered]@{
            schema_version = "1.0"
            project_root = $ProjectRoot
            update_id = [string]$manifest.update_id
            dry_run_fingerprint = [string]$dryRun.fingerprint
            checkpoint_zip = $checkpointZip
            baseline_path = $BaselinePath
            baseline_pre_hash = $baselinePreHash
            entries = $checkpointEntries.ToArray()
        }
        $checkpointManifestPath = Join-Path $EvidencePath ("UPDATE.CHECKPOINT.{0}.{1}.json" -f $manifest.update_id, $RunStamp)
        Write-Utf8NoBom -Path $checkpointManifestPath -Content ($checkpointObject | ConvertTo-Json -Depth 20)

        Write-UpdateTransactionState `
            -Path $transactionStatePath `
            -Phase "CHECKPOINT_CREATED" `
            -TransactionId $transactionId `
            -TransactionAction "apply" `
            -UpdateId ([string]$manifest.update_id) `
            -CheckpointManifestPath $checkpointManifestPath

        Write-UpdateTransactionState `
            -Path $transactionStatePath `
            -Phase "APPLYING" `
            -TransactionId $transactionId `
            -TransactionAction "apply" `
            -UpdateId ([string]$manifest.update_id) `
            -CheckpointManifestPath $checkpointManifestPath

        foreach ($operation in @($manifest.operations)) {
            $targetFull = Resolve-SafeRelativePath -Root $ProjectRoot -RelativePath ([string]$operation.target_path)
            $actionName = [string]$operation.action

            if ($actionName -in @("ADD", "REPLACE")) {
                $sourceFull = Resolve-SafeRelativePath -Root $manifestDirectory -RelativePath ([string]$operation.source_path)
                $parent = Split-Path -Parent $targetFull
                if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
                    New-Item -ItemType Directory -Path $parent -Force | Out-Null
                }
                Copy-Item -LiteralPath $sourceFull -Destination $targetFull -Force
                if ((Get-Sha256 -Path $targetFull) -ne [string]$operation.expected_post_hash) {
                    throw "POST_APPLY_HASH_MISMATCH: $($operation.operation_id)"
                }
            }
            elseif ($actionName -eq "DELETE") {
                Remove-Item -LiteralPath $targetFull -Force
                if (Test-Path -LiteralPath $targetFull) {
                    throw "POST_DELETE_TARGET_STILL_EXISTS: $($operation.operation_id)"
                }
            }

            Write-UpdateTransactionState `
                -Path $transactionStatePath `
                -Phase "APPLYING" `
                -TransactionId $transactionId `
                -TransactionAction "apply" `
                -UpdateId ([string]$manifest.update_id) `
                -CheckpointManifestPath $checkpointManifestPath `
                -LastOperationId ([string]$operation.operation_id)

            if (
                -not [string]::IsNullOrWhiteSpace(
                    $env:SKILLSMACHINE_TEST_CRASH_AFTER_OPERATION_ID
                )
            ) {
                if (-not $TestMode) {
                    throw "TEST_CRASH_HOOK_BLOCKED_WITHOUT_TEST_MODE"
                }

                $testProjectId = [string]$baseline.project_id
                if (
                    -not $testProjectId.StartsWith(
                        "TEST_",
                        [System.StringComparison]::OrdinalIgnoreCase
                    ) -and
                    -not $testProjectId.StartsWith(
                        "NEGATIVE_TEST_",
                        [System.StringComparison]::OrdinalIgnoreCase
                    )
                ) {
                    throw "TEST_CRASH_HOOK_BLOCKED_FOR_NON_TEST_PROJECT: $testProjectId"
                }

                if (
                    $env:SKILLSMACHINE_TEST_CRASH_AFTER_OPERATION_ID -eq
                    [string]$operation.operation_id
                ) {
                    Stop-Process -Id $PID -Force
                }
            }

            if (-not [string]::IsNullOrWhiteSpace($env:SKILLSMACHINE_TEST_FAIL_AFTER_OPERATION_ID)) {
                if (-not $TestMode) {
                    throw "TEST_HOOK_BLOCKED_WITHOUT_TEST_MODE"
                }

                $testProjectId = [string]$baseline.project_id
                if (
                    -not $testProjectId.StartsWith("TEST_", [System.StringComparison]::OrdinalIgnoreCase) -and
                    -not $testProjectId.StartsWith("NEGATIVE_TEST_", [System.StringComparison]::OrdinalIgnoreCase)
                ) {
                    throw "TEST_HOOK_BLOCKED_FOR_NON_TEST_PROJECT: $testProjectId"
                }

                if ($env:SKILLSMACHINE_TEST_FAIL_AFTER_OPERATION_ID -eq [string]$operation.operation_id) {
                    Write-Host "TEST_MODE_ACTIVE=True"
                    throw "TEST_INDUCED_FAILURE_AFTER_OPERATION: $($operation.operation_id)"
                }
            }
        }

        $baselineAfter = Update-BaselineAfterApply -Baseline $baseline -Manifest $manifest
        Write-Utf8NoBom -Path $BaselinePath -Content ($baselineAfter | ConvertTo-Json -Depth 20)

        $data = [ordered]@{
            project_id = [string]$baseline.project_id
            update_id = [string]$manifest.update_id
            dry_run_fingerprint = [string]$dryRun.fingerprint
            approval_recorded = $true
            checkpoint_manifest = $checkpointManifestPath
            checkpoint_zip = $checkpointZip
            applied_operations = @($manifest.operations).Count
            baseline_updated = $true
            document_audit = $documentAudit
        }
        [void](Write-ActionEvidence -Status "PASS" -Data $data)

        Write-UpdateTransactionState `
            -Path $transactionStatePath `
            -Phase "APPLIED" `
            -TransactionId $transactionId `
            -TransactionAction "apply" `
            -UpdateId ([string]$manifest.update_id) `
            -CheckpointManifestPath $checkpointManifestPath

        Remove-UpdateTransactionState -Path $transactionStatePath

        Write-Host "CHECKPOINT_MANIFEST=$checkpointManifestPath"
        Write-Host "FINAL_STATUS=PASS_APPLY"
        exit 0
    }
    catch {
        $applyError = $_
        $rollbackStatus = "NOT_ATTEMPTED"
        $rollbackError = $null

        try {
            Write-UpdateTransactionState `
                -Path $transactionStatePath `
                -Phase "ROLLING_BACK" `
                -TransactionId $transactionId `
                -TransactionAction "apply" `
                -UpdateId ([string]$manifest.update_id) `
                -CheckpointManifestPath $checkpointManifestPath `
                -Failure $applyError.Exception.Message

            if ($null -eq $checkpointManifestPath -or -not (Test-Path -LiteralPath $checkpointManifestPath -PathType Leaf)) {
                throw "AUTOMATIC_ROLLBACK_CHECKPOINT_MANIFEST_UNAVAILABLE"
            }

            $checkpointForRollback = Read-JsonFile -Path $checkpointManifestPath
            $rollbackZip = [string]$checkpointForRollback.checkpoint_zip
            if (-not (Test-Path -LiteralPath $rollbackZip -PathType Leaf)) {
                throw "AUTOMATIC_ROLLBACK_CHECKPOINT_ZIP_UNAVAILABLE"
            }

            $rollbackExtractRoot = Join-Path $env:TEMP ("SkillsMachineAutoRollback.{0}" -f ([guid]::NewGuid().ToString("N")))
            New-Item -ItemType Directory -Path $rollbackExtractRoot -Force | Out-Null

            try {
                Expand-Archive -LiteralPath $rollbackZip -DestinationPath $rollbackExtractRoot -Force

                foreach ($entry in @($checkpointForRollback.entries)) {
                    $targetFull = Resolve-SafeRelativePath -Root $ProjectRoot -RelativePath ([string]$entry.target_path)

                    if ([bool]$entry.pre_exists) {
                        $backupFull = Join-Path $rollbackExtractRoot ([string]$entry.backup_relative_path)
                        if (-not (Test-Path -LiteralPath $backupFull -PathType Leaf)) {
                            throw "AUTOMATIC_ROLLBACK_BACKUP_MISSING: $($entry.target_path)"
                        }

                        $parent = Split-Path -Parent $targetFull
                        if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
                            New-Item -ItemType Directory -Path $parent -Force | Out-Null
                        }

                        Copy-Item -LiteralPath $backupFull -Destination $targetFull -Force
                        if ((Get-Sha256 -Path $targetFull) -ne [string]$entry.pre_hash) {
                            throw "AUTOMATIC_ROLLBACK_HASH_MISMATCH: $($entry.target_path)"
                        }
                    }
                    else {
                        if (Test-Path -LiteralPath $targetFull) {
                            Remove-Item -LiteralPath $targetFull -Force
                        }
                    }
                }

                $baselineBackup = Join-Path $rollbackExtractRoot "__baseline.json"
                if (-not (Test-Path -LiteralPath $baselineBackup -PathType Leaf)) {
                    throw "AUTOMATIC_ROLLBACK_BASELINE_BACKUP_MISSING"
                }

                Copy-Item -LiteralPath $baselineBackup -Destination $BaselinePath -Force
                if ((Get-Sha256 -Path $BaselinePath) -ne [string]$checkpointForRollback.baseline_pre_hash) {
                    throw "AUTOMATIC_ROLLBACK_BASELINE_HASH_MISMATCH"
                }

                $rollbackStatus = "PASS"

                Write-UpdateTransactionState `
                    -Path $transactionStatePath `
                    -Phase "ROLLED_BACK" `
                    -TransactionId $transactionId `
                    -TransactionAction "apply" `
                    -UpdateId ([string]$manifest.update_id) `
                    -CheckpointManifestPath $checkpointManifestPath `
                    -Failure $applyError.Exception.Message

                Remove-UpdateTransactionState -Path $transactionStatePath
            }
            finally {
                if (Test-Path -LiteralPath $rollbackExtractRoot) {
                    Remove-Item -LiteralPath $rollbackExtractRoot -Recurse -Force
                }
            }
        }
        catch {
            $rollbackStatus = "FAIL"
            $rollbackError = $_.Exception.Message

            Write-UpdateTransactionState `
                -Path $transactionStatePath `
                -Phase "FAILED_ROLLBACK_FAIL" `
                -TransactionId $transactionId `
                -TransactionAction "apply" `
                -UpdateId ([string]$manifest.update_id) `
                -CheckpointManifestPath $checkpointManifestPath `
                -Failure $rollbackError
        }

        $failureData = [ordered]@{
            project_id = [string]$baseline.project_id
            update_id = [string]$manifest.update_id
            dry_run_fingerprint = [string]$dryRun.fingerprint
            apply_error = $applyError.Exception.Message
            automatic_rollback_status = $rollbackStatus
            automatic_rollback_error = $rollbackError
            checkpoint_manifest = $checkpointManifestPath
            checkpoint_zip = $checkpointZip
            document_audit = $documentAudit
        }

        $failureStatus = if ($rollbackStatus -eq "PASS") {
            "APPLY_FAILED_ROLLBACK_PASS"
        }
        else {
            "APPLY_FAILED_ROLLBACK_FAIL"
        }

        [void](Write-ActionEvidence -Status $failureStatus -Data $failureData)
        Write-Host "AUTOMATIC_ROLLBACK_STATUS=$rollbackStatus"
        Write-Host "FINAL_STATUS=$failureStatus"
        Write-Host "APPLY_ERROR=$($applyError.Exception.Message)"
        exit 1
    }
    finally {
        if (Test-Path -LiteralPath $checkpointWork) {
            Remove-Item -LiteralPath $checkpointWork -Recurse -Force
        }

        Exit-UpdateTransactionMutex -Mutex $transactionMutex
    }
}

throw "UNREACHABLE_ACTION"
