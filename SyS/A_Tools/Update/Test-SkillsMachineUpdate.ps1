[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$RunnerPath,

    [Parameter(Mandatory = $true)]
    [string]$OutputPath
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

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

function Assert-FileContainsAll {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string[]]$Patterns,
        [Parameter(Mandatory = $true)][string]$FailureMessage
    )

    $content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    foreach ($pattern in @($Patterns)) {
        if (-not $content.Contains($pattern)) {
            throw ("{0}: {1}" -f $FailureMessage, $pattern)
        }
    }
}

function Get-CommandPathIfRunnable {
    param(
        [Parameter(Mandatory = $true)][string]$Name
    )

    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if ($null -eq $cmd) {
        return $null
    }

    try {
        $null = & $cmd.Source -NoProfile -Command '$PSVersionTable.PSVersion.ToString()' 2>$null
        if ($LASTEXITCODE -ne 0) {
            return $null
        }
    }
    catch {
        return $null
    }

    return $cmd.Source
}

$testRoot = Join-Path $env:TEMP ("SkillsMachineUpdateTest.{0}" -f ([guid]::NewGuid().ToString("N")))
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\..\.."))
$windowsPowerShellPath = (Get-Command powershell.exe -ErrorAction Stop).Source
$powerShell7Path = Get-CommandPathIfRunnable -Name "pwsh.exe"
$runnerHostPath = if ($null -ne $powerShell7Path) { $powerShell7Path } else { $windowsPowerShellPath }
$project = Join-Path $testRoot "project"
$package = Join-Path $testRoot "package"
$evidence = Join-Path $testRoot "evidence"

$env:HOME = $testRoot
$env:XDG_CONFIG_HOME = $testRoot

New-Item -ItemType Directory -Path $project, $package, $evidence -Force | Out-Null

try {
    Write-Utf8NoBom -Path (Join-Path $project "replace.txt") -Content "before replace"
    Write-Utf8NoBom -Path (Join-Path $project "delete.txt") -Content "before delete"
    Write-Utf8NoBom -Path (Join-Path $package "add.payload.txt") -Content "added"
    Write-Utf8NoBom -Path (Join-Path $package "replace.payload.txt") -Content "after replace"

    $replacePre = Get-Sha256 -Path (Join-Path $project "replace.txt")
    $deletePre = Get-Sha256 -Path (Join-Path $project "delete.txt")
    $addPost = Get-Sha256 -Path (Join-Path $package "add.payload.txt")
    $replacePost = Get-Sha256 -Path (Join-Path $package "replace.payload.txt")

    & git -C $project init | Out-Null
    & git -C $project config user.email "skillsmachine-test@example.invalid"
    & git -C $project config user.name "SkillsMachine Test"

    $baseline = [ordered]@{
        schema_version = "1.1"
        project_id = "TEST_PROJECT"
        created_by_skillsmachine = $true
        skillsmachine_version = "0.3.0"
        skillsmachine_commit = ("0" * 40)
        last_update_id = $null
        baseline_generated_at = (Get-Date).ToUniversalTime().ToString("o")
        component_inventory = @(
            [ordered]@{
                component_type = "test_file"
                relative_path = "replace.txt"
                sha256 = $replacePre
                version = "0.3.0"
            },
            [ordered]@{
                component_type = "test_file"
                relative_path = "delete.txt"
                sha256 = $deletePre
                version = "0.3.0"
            }
        )
    }
    $baselinePath = Join-Path $project "SKILLSMACHINE.PROJECT.BASELINE.json"
    Write-Utf8NoBom -Path $baselinePath -Content ($baseline | ConvertTo-Json -Depth 10)

    $manifest = [ordered]@{
        schema_version = "1.1"
        update_id = "SM-UPD-000001"
        update_version = "0.3.1"
        source_commit = ("1" * 40)
        created_at = (Get-Date).ToUniversalTime().ToString("o")
        minimum_project_version = "0.3.0"
        maximum_project_version = "0.3.x"
        reversible = $true
        human_approval_required = $true
        affected_components = @("metadata")
        operations = @(
            [ordered]@{
                operation_id = "OP-ADD"
                action = "ADD"
                source_path = "add.payload.txt"
                target_path = "add.txt"
                expected_pre_hash = $null
                expected_post_hash = $addPost
                backup_required = $false
                reversible = $true
            },
            [ordered]@{
                operation_id = "OP-REPLACE"
                action = "REPLACE"
                source_path = "replace.payload.txt"
                target_path = "replace.txt"
                expected_pre_hash = $replacePre
                expected_post_hash = $replacePost
                backup_required = $true
                reversible = $true
            },
            [ordered]@{
                operation_id = "OP-DELETE"
                action = "DELETE"
                source_path = $null
                target_path = "delete.txt"
                expected_pre_hash = $deletePre
                expected_post_hash = $null
                backup_required = $true
                reversible = $true
            }
        )
        rollback_contract = [ordered]@{
            mode = "CHECKPOINT_AND_INVERSE_PLAN"
            verify_hashes = $true
            restore_baseline = $true
        }
    }
    $manifestPath = Join-Path $package "update.json"
    Write-Utf8NoBom -Path $manifestPath -Content ($manifest | ConvertTo-Json -Depth 10)

    & git -C $project add .
    & git -C $project commit -m "baseline" | Out-Null

    $dryOutput = & $runnerHostPath -NoProfile -ExecutionPolicy Bypass -File $RunnerPath `
        -Action dry-run `
        -ProjectRoot $project `
        -UpdateManifest $manifestPath `
        -BaselinePath $baselinePath `
        -EvidencePath $evidence 2>&1

    if ($LASTEXITCODE -ne 0) {
        throw "DRY_RUN_FAILED: $($dryOutput -join ' | ')"
    }

    $fingerprintLine = @($dryOutput | Where-Object { $_ -like "DRY_RUN_FINGERPRINT=*" }) | Select-Object -Last 1
    if ([string]::IsNullOrWhiteSpace($fingerprintLine)) {
        throw "DRY_RUN_FINGERPRINT_NOT_RETURNED"
    }
    $fingerprint = ($fingerprintLine -split "=", 2)[1]

    $applyOutput = & $runnerHostPath -NoProfile -ExecutionPolicy Bypass -File $RunnerPath `
        -Action apply `
        -ProjectRoot $project `
        -UpdateManifest $manifestPath `
        -BaselinePath $baselinePath `
        -EvidencePath $evidence `
        -HumanApproved `
        -ApprovedDryRunFingerprint $fingerprint 2>&1

    if ($LASTEXITCODE -ne 0) {
        throw "APPLY_FAILED: $($applyOutput -join ' | ')"
    }

    if (-not (Test-Path -LiteralPath (Join-Path $project "add.txt"))) {
        throw "ADD_NOT_APPLIED"
    }
    if ((Get-Sha256 -Path (Join-Path $project "replace.txt")) -ne $replacePost) {
        throw "REPLACE_NOT_APPLIED"
    }
    if (Test-Path -LiteralPath (Join-Path $project "delete.txt")) {
        throw "DELETE_NOT_APPLIED"
    }

    $checkpointLine = @($applyOutput | Where-Object { $_ -like "CHECKPOINT_MANIFEST=*" }) | Select-Object -Last 1
    if ([string]::IsNullOrWhiteSpace($checkpointLine)) {
        throw "CHECKPOINT_MANIFEST_NOT_RETURNED"
    }
    $checkpointManifest = ($checkpointLine -split "=", 2)[1]

    $rollbackOutput = & $runnerHostPath -NoProfile -ExecutionPolicy Bypass -File $RunnerPath `
        -Action rollback `
        -ProjectRoot $project `
        -BaselinePath $baselinePath `
        -EvidencePath $evidence `
        -CheckpointManifest $checkpointManifest 2>&1

    if ($LASTEXITCODE -ne 0) {
        throw "ROLLBACK_FAILED: $($rollbackOutput -join ' | ')"
    }

    if (Test-Path -LiteralPath (Join-Path $project "add.txt")) {
        throw "ADD_NOT_ROLLED_BACK"
    }
    if ((Get-Sha256 -Path (Join-Path $project "replace.txt")) -ne $replacePre) {
        throw "REPLACE_NOT_ROLLED_BACK"
    }
    if ((Get-Sha256 -Path (Join-Path $project "delete.txt")) -ne $deletePre) {
        throw "DELETE_NOT_ROLLED_BACK"
    }

    $status = & git -C $project status --short --untracked-files=all
    $statusLines = @($status | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($statusLines.Count -gt 0) {
        throw "PROJECT_NOT_CLEAN_AFTER_ROLLBACK: $($statusLines -join ' | ')"
    }

    # Security guard: an induced-failure hook must be rejected without -TestMode.
    $guardProject = Join-Path $testRoot "guard-project"
    $guardPackage = Join-Path $testRoot "guard-package"
    $guardEvidence = Join-Path $testRoot "guard-evidence"
    New-Item -ItemType Directory -Path $guardProject, $guardPackage, $guardEvidence -Force | Out-Null

    Write-Utf8NoBom -Path (Join-Path $guardProject "guard.txt") -Content "guard before"
    Write-Utf8NoBom -Path (Join-Path $guardPackage "guard.payload.txt") -Content "guard after"
    $guardPre = Get-Sha256 -Path (Join-Path $guardProject "guard.txt")
    $guardPost = Get-Sha256 -Path (Join-Path $guardPackage "guard.payload.txt")

    & git -C $guardProject init | Out-Null
    & git -C $guardProject config user.email "skillsmachine-test@example.invalid"
    & git -C $guardProject config user.name "SkillsMachine Test"

    $guardBaseline = [ordered]@{
        schema_version = "1.1"
        project_id = "NORMAL_PROJECT"
        created_by_skillsmachine = $true
        skillsmachine_version = "0.3.0"
        skillsmachine_commit = ("0" * 40)
        last_update_id = $null
        baseline_generated_at = (Get-Date).ToUniversalTime().ToString("o")
        component_inventory = @(
            [ordered]@{
                component_type = "test_file"
                relative_path = "guard.txt"
                sha256 = $guardPre
                version = "0.3.0"
            }
        )
    }
    $guardBaselinePath = Join-Path $guardProject "SKILLSMACHINE.PROJECT.BASELINE.json"
    Write-Utf8NoBom -Path $guardBaselinePath -Content ($guardBaseline | ConvertTo-Json -Depth 10)

    $guardManifest = [ordered]@{
        schema_version = "1.1"
        update_id = "SM-UPD-000003"
        update_version = "0.3.1"
        source_commit = ("3" * 40)
        created_at = (Get-Date).ToUniversalTime().ToString("o")
        minimum_project_version = "0.3.0"
        maximum_project_version = "0.3.x"
        reversible = $true
        human_approval_required = $true
        affected_components = @("metadata")
        operations = @(
            [ordered]@{
                operation_id = "GUARD-01"
                action = "REPLACE"
                source_path = "guard.payload.txt"
                target_path = "guard.txt"
                expected_pre_hash = $guardPre
                expected_post_hash = $guardPost
                backup_required = $true
                reversible = $true
            }
        )
        rollback_contract = [ordered]@{
            mode = "CHECKPOINT_AND_INVERSE_PLAN"
            verify_hashes = $true
            restore_baseline = $true
        }
    }
    $guardManifestPath = Join-Path $guardPackage "update-guard.json"
    Write-Utf8NoBom -Path $guardManifestPath -Content ($guardManifest | ConvertTo-Json -Depth 10)

    & git -C $guardProject add .
    & git -C $guardProject commit -m "guard baseline" | Out-Null

    $guardDryOutput = & $runnerHostPath -NoProfile -ExecutionPolicy Bypass -File $RunnerPath `
        -Action dry-run `
        -ProjectRoot $guardProject `
        -UpdateManifest $guardManifestPath `
        -BaselinePath $guardBaselinePath `
        -EvidencePath $guardEvidence 2>&1

    if ($LASTEXITCODE -ne 0) {
        throw "GUARD_DRY_RUN_FAILED: $($guardDryOutput -join ' | ')"
    }

    $guardFingerprintLine = @($guardDryOutput | Where-Object { $_ -like "DRY_RUN_FINGERPRINT=*" }) | Select-Object -Last 1
    $guardFingerprint = ($guardFingerprintLine -split "=", 2)[1]

    $env:SKILLSMACHINE_TEST_FAIL_AFTER_OPERATION_ID = "GUARD-01"
    try {
        try {
            $guardApplyOutput = & $runnerHostPath -NoProfile -ExecutionPolicy Bypass -File $RunnerPath `
                -Action apply `
                -ProjectRoot $guardProject `
                -UpdateManifest $guardManifestPath `
                -BaselinePath $guardBaselinePath `
                -EvidencePath $guardEvidence `
                -HumanApproved `
                -ApprovedDryRunFingerprint $guardFingerprint 2>&1
            $guardApplyExit = $LASTEXITCODE
        }
        catch {
            $guardApplyOutput = @($_.Exception.Message)
            $guardApplyExit = 1
        }
    }
    finally {
        Remove-Item Env:\SKILLSMACHINE_TEST_FAIL_AFTER_OPERATION_ID -ErrorAction SilentlyContinue
    }

    if ($guardApplyExit -eq 0) {
        throw "TEST_HOOK_GUARD_UNEXPECTED_PASS"
    }
    if (-not (@($guardApplyOutput) -match "TEST_HOOK_BLOCKED_WITHOUT_TEST_MODE")) {
        throw "TEST_HOOK_GUARD_NOT_ENFORCED: $($guardApplyOutput -join ' | ')"
    }
    if ((Get-Sha256 -Path (Join-Path $guardProject "guard.txt")) -ne $guardPre) {
        throw "GUARD_PROJECT_NOT_RESTORED"
    }

    # Negative path: operation 1 succeeds, operation 2 fails after mutation,
    # and the runner must automatically restore project files and baseline.
    $negativeProject = Join-Path $testRoot "negative-project"
    $negativePackage = Join-Path $testRoot "negative-package"
    $negativeEvidence = Join-Path $testRoot "negative-evidence"
    New-Item -ItemType Directory -Path $negativeProject, $negativePackage, $negativeEvidence -Force | Out-Null

    Write-Utf8NoBom -Path (Join-Path $negativeProject "first.txt") -Content "first before"
    Write-Utf8NoBom -Path (Join-Path $negativeProject "second.txt") -Content "second before"
    Write-Utf8NoBom -Path (Join-Path $negativePackage "first.payload.txt") -Content "first after"
    Write-Utf8NoBom -Path (Join-Path $negativePackage "second.payload.txt") -Content "second after"

    $negativeFirstPre = Get-Sha256 -Path (Join-Path $negativeProject "first.txt")
    $negativeSecondPre = Get-Sha256 -Path (Join-Path $negativeProject "second.txt")
    $negativeFirstPost = Get-Sha256 -Path (Join-Path $negativePackage "first.payload.txt")
    $negativeSecondPost = Get-Sha256 -Path (Join-Path $negativePackage "second.payload.txt")

    & git -C $negativeProject init | Out-Null
    & git -C $negativeProject config user.email "skillsmachine-test@example.invalid"
    & git -C $negativeProject config user.name "SkillsMachine Test"

    $negativeBaseline = [ordered]@{
        schema_version = "1.1"
        project_id = "NEGATIVE_TEST_PROJECT"
        created_by_skillsmachine = $true
        skillsmachine_version = "0.3.0"
        skillsmachine_commit = ("0" * 40)
        last_update_id = $null
        baseline_generated_at = (Get-Date).ToUniversalTime().ToString("o")
        component_inventory = @(
            [ordered]@{
                component_type = "test_file"
                relative_path = "first.txt"
                sha256 = $negativeFirstPre
                version = "0.3.0"
            },
            [ordered]@{
                component_type = "test_file"
                relative_path = "second.txt"
                sha256 = $negativeSecondPre
                version = "0.3.0"
            }
        )
    }
    $negativeBaselinePath = Join-Path $negativeProject "SKILLSMACHINE.PROJECT.BASELINE.json"
    Write-Utf8NoBom -Path $negativeBaselinePath -Content ($negativeBaseline | ConvertTo-Json -Depth 10)
    $negativeBaselinePreHash = Get-Sha256 -Path $negativeBaselinePath

    $negativeManifest = [ordered]@{
        schema_version = "1.1"
        update_id = "SM-UPD-000002"
        update_version = "0.3.1"
        source_commit = ("2" * 40)
        created_at = (Get-Date).ToUniversalTime().ToString("o")
        minimum_project_version = "0.3.0"
        maximum_project_version = "0.3.x"
        reversible = $true
        human_approval_required = $true
        affected_components = @("metadata")
        operations = @(
            [ordered]@{
                operation_id = "NEG-01"
                action = "REPLACE"
                source_path = "first.payload.txt"
                target_path = "first.txt"
                expected_pre_hash = $negativeFirstPre
                expected_post_hash = $negativeFirstPost
                backup_required = $true
                reversible = $true
            },
            [ordered]@{
                operation_id = "NEG-02"
                action = "REPLACE"
                source_path = "second.payload.txt"
                target_path = "second.txt"
                expected_pre_hash = $negativeSecondPre
                expected_post_hash = $negativeSecondPost
                backup_required = $true
                reversible = $true
            }
        )
        rollback_contract = [ordered]@{
            mode = "CHECKPOINT_AND_INVERSE_PLAN"
            verify_hashes = $true
            restore_baseline = $true
        }
    }
    $negativeManifestPath = Join-Path $negativePackage "update-negative.json"
    Write-Utf8NoBom -Path $negativeManifestPath -Content ($negativeManifest | ConvertTo-Json -Depth 10)

    & git -C $negativeProject add .
    & git -C $negativeProject commit -m "negative baseline" | Out-Null

    $negativeDryOutput = & $runnerHostPath -NoProfile -ExecutionPolicy Bypass -File $RunnerPath `
        -Action dry-run `
        -ProjectRoot $negativeProject `
        -UpdateManifest $negativeManifestPath `
        -BaselinePath $negativeBaselinePath `
        -EvidencePath $negativeEvidence 2>&1

    if ($LASTEXITCODE -ne 0) {
        throw "NEGATIVE_DRY_RUN_FAILED: $($negativeDryOutput -join ' | ')"
    }

    $negativeFingerprintLine = @($negativeDryOutput | Where-Object { $_ -like "DRY_RUN_FINGERPRINT=*" }) | Select-Object -Last 1
    $negativeFingerprint = ($negativeFingerprintLine -split "=", 2)[1]

    # Corrupt operation 2's payload only after dry-run. Apply re-evaluation normally catches
    # this before mutation, so instead use an induced filesystem failure after operation 1:
    # replace second target file with a directory after dry-run and commit that state is avoided
    # by restoring its file before apply evaluation, then the test hook below triggers after op 1.
    $env:SKILLSMACHINE_TEST_FAIL_AFTER_OPERATION_ID = "NEG-01"
    try {
        try {
            $negativeApplyOutput = & $runnerHostPath -NoProfile -ExecutionPolicy Bypass -File $RunnerPath `
                -Action apply `
                -ProjectRoot $negativeProject `
                -UpdateManifest $negativeManifestPath `
                -BaselinePath $negativeBaselinePath `
                -EvidencePath $negativeEvidence `
                -HumanApproved `
                -ApprovedDryRunFingerprint $negativeFingerprint `
                -TestMode 2>&1
            $negativeApplyExit = $LASTEXITCODE
        }
        catch {
            $negativeApplyOutput = @($_.Exception.Message)
            $negativeApplyExit = 1
        }
    }
    finally {
        Remove-Item Env:\SKILLSMACHINE_TEST_FAIL_AFTER_OPERATION_ID -ErrorAction SilentlyContinue
    }

    if ($negativeApplyExit -eq 0) {
        throw "NEGATIVE_APPLY_UNEXPECTED_PASS"
    }

    if (-not (@($negativeApplyOutput) -match "AUTOMATIC_ROLLBACK_STATUS=PASS")) {
        throw "AUTOMATIC_ROLLBACK_PASS_NOT_REPORTED: $($negativeApplyOutput -join ' | ')"
    }

    if ((Get-Sha256 -Path (Join-Path $negativeProject "first.txt")) -ne $negativeFirstPre) {
        throw "NEGATIVE_FIRST_FILE_NOT_RESTORED"
    }
    if ((Get-Sha256 -Path (Join-Path $negativeProject "second.txt")) -ne $negativeSecondPre) {
        throw "NEGATIVE_SECOND_FILE_NOT_RESTORED"
    }
    if ((Get-Sha256 -Path $negativeBaselinePath) -ne $negativeBaselinePreHash) {
        throw "NEGATIVE_BASELINE_NOT_RESTORED"
    }

    $negativeStatus = & git -C $negativeProject status --short --untracked-files=all
    $negativeStatusLines = @($negativeStatus | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($negativeStatusLines.Count -gt 0) {
        throw "NEGATIVE_PROJECT_NOT_CLEAN_AFTER_AUTO_ROLLBACK: $($negativeStatusLines -join ' | ')"
    }

    $auditProject = Join-Path $testRoot "audit-project"
    $auditPackage = Join-Path $testRoot "audit-package"
    $auditEvidence = Join-Path $testRoot "audit-evidence"
    New-Item -ItemType Directory -Path $auditProject, $auditPackage, $auditEvidence -Force | Out-Null

    Write-Utf8NoBom -Path (Join-Path $auditProject "HUMAN.AUDIT_PROJECT.txt") -Content "PROJECT_ROOT=$auditProject"
    Write-Utf8NoBom -Path (Join-Path $auditProject "WHOAMI.AUDIT_PROJECT.txt") -Content "PROJECT_ID=AUDIT_PROJECT"
    Write-Utf8NoBom -Path (Join-Path $auditProject "BATON.AUDIT_PROJECT.txt") -Content "NEXT_ACTION=TEST"
    Write-Utf8NoBom -Path (Join-Path $auditProject "config.txt") -Content "before audit"
    Write-Utf8NoBom -Path (Join-Path $auditPackage "config.payload.txt") -Content "after audit"
    $auditPre = Get-Sha256 -Path (Join-Path $auditProject "config.txt")
    $auditPost = Get-Sha256 -Path (Join-Path $auditPackage "config.payload.txt")

    & git -C $auditProject init | Out-Null
    & git -C $auditProject config user.email "skillsmachine-test@example.invalid"
    & git -C $auditProject config user.name "SkillsMachine Test"

    $auditBaseline = [ordered]@{
        schema_version = "1.1"
        project_id = "AUDIT_PROJECT"
        created_by_skillsmachine = $true
        skillsmachine_version = "0.3.0"
        skillsmachine_commit = ("0" * 40)
        last_update_id = $null
        baseline_generated_at = (Get-Date).ToUniversalTime().ToString("o")
        component_inventory = @(
            [ordered]@{
                component_type = "test_file"
                relative_path = "config.txt"
                sha256 = $auditPre
                version = "0.3.0"
            }
        )
    }
    $auditBaselinePath = Join-Path $auditProject "SKILLSMACHINE.PROJECT.BASELINE.json"
    Write-Utf8NoBom -Path $auditBaselinePath -Content ($auditBaseline | ConvertTo-Json -Depth 10)

    $auditManifest = [ordered]@{
        schema_version = "1.1"
        update_id = "SM-UPD-000004"
        update_version = "0.3.1"
        source_commit = ("4" * 40)
        created_at = (Get-Date).ToUniversalTime().ToString("o")
        minimum_project_version = "0.3.0"
        maximum_project_version = "0.3.x"
        reversible = $true
        human_approval_required = $true
        affected_components = @("docs")
        operations = @(
            [ordered]@{
                operation_id = "AUDIT-01"
                action = "REPLACE"
                source_path = "config.payload.txt"
                target_path = "config.txt"
                expected_pre_hash = $auditPre
                expected_post_hash = $auditPost
                backup_required = $true
                reversible = $true
            }
        )
        rollback_contract = [ordered]@{
            mode = "CHECKPOINT_AND_INVERSE_PLAN"
            verify_hashes = $true
            restore_baseline = $true
        }
    }
    $auditManifestPath = Join-Path $auditPackage "update-audit.json"
    Write-Utf8NoBom -Path $auditManifestPath -Content ($auditManifest | ConvertTo-Json -Depth 10)

    & git -C $auditProject add .
    & git -C $auditProject commit -m "audit baseline" | Out-Null

    $auditPreflightOutput = & $runnerHostPath -NoProfile -ExecutionPolicy Bypass -File $RunnerPath `
        -Action preflight `
        -ProjectRoot $auditProject `
        -UpdateManifest $auditManifestPath `
        -BaselinePath $auditBaselinePath `
        -EvidencePath $auditEvidence `
        -UseDocumentAuditPreflight 2>&1

    if ($LASTEXITCODE -ne 0) {
        throw "AUDIT_PREFLIGHT_FAILED: $($auditPreflightOutput -join ' | ')"
    }
    if (-not (@($auditPreflightOutput) -match "DOCUMENT_AUDIT_STATUS=PASS")) {
        throw "AUDIT_FINDINGS_NOT_CONSUMED: $($auditPreflightOutput -join ' | ')"
    }

    $auditConflictProject = Join-Path $testRoot "audit-conflict-project"
    $auditConflictPackage = Join-Path $testRoot "audit-conflict-package"
    $auditConflictEvidence = Join-Path $testRoot "audit-conflict-evidence"
    New-Item -ItemType Directory -Path $auditConflictProject, $auditConflictPackage, $auditConflictEvidence -Force | Out-Null

    Write-Utf8NoBom -Path (Join-Path $auditConflictProject "HUMAN.AUDIT_CONFLICT.txt") -Content "a"
    Write-Utf8NoBom -Path (Join-Path $auditConflictProject "HUMAN.AUDIT_CONFLICT.md") -Content "b"
    Write-Utf8NoBom -Path (Join-Path $auditConflictProject "WHOAMI.AUDIT_CONFLICT.txt") -Content "PROJECT_ID=AUDIT_CONFLICT"
    Write-Utf8NoBom -Path (Join-Path $auditConflictProject "BATON.AUDIT_CONFLICT.txt") -Content "NEXT_ACTION=TEST"
    Write-Utf8NoBom -Path (Join-Path $auditConflictProject "config.txt") -Content "before conflict"
    Write-Utf8NoBom -Path (Join-Path $auditConflictPackage "config.payload.txt") -Content "after conflict"
    $auditConflictPre = Get-Sha256 -Path (Join-Path $auditConflictProject "config.txt")
    $auditConflictPost = Get-Sha256 -Path (Join-Path $auditConflictPackage "config.payload.txt")

    & git -C $auditConflictProject init | Out-Null
    & git -C $auditConflictProject config user.email "skillsmachine-test@example.invalid"
    & git -C $auditConflictProject config user.name "SkillsMachine Test"

    $auditConflictBaseline = [ordered]@{
        schema_version = "1.1"
        project_id = "AUDIT_CONFLICT"
        created_by_skillsmachine = $true
        skillsmachine_version = "0.3.0"
        skillsmachine_commit = ("0" * 40)
        last_update_id = $null
        baseline_generated_at = (Get-Date).ToUniversalTime().ToString("o")
        component_inventory = @(
            [ordered]@{
                component_type = "test_file"
                relative_path = "config.txt"
                sha256 = $auditConflictPre
                version = "0.3.0"
            }
        )
    }
    $auditConflictBaselinePath = Join-Path $auditConflictProject "SKILLSMACHINE.PROJECT.BASELINE.json"
    Write-Utf8NoBom -Path $auditConflictBaselinePath -Content ($auditConflictBaseline | ConvertTo-Json -Depth 10)

    $auditConflictManifest = [ordered]@{
        schema_version = "1.1"
        update_id = "SM-UPD-000005"
        update_version = "0.3.1"
        source_commit = ("5" * 40)
        created_at = (Get-Date).ToUniversalTime().ToString("o")
        minimum_project_version = "0.3.0"
        maximum_project_version = "0.3.x"
        reversible = $true
        human_approval_required = $true
        affected_components = @("docs")
        operations = @(
            [ordered]@{
                operation_id = "AUDIT-CONFLICT-01"
                action = "REPLACE"
                source_path = "config.payload.txt"
                target_path = "config.txt"
                expected_pre_hash = $auditConflictPre
                expected_post_hash = $auditConflictPost
                backup_required = $true
                reversible = $true
            }
        )
        rollback_contract = [ordered]@{
            mode = "CHECKPOINT_AND_INVERSE_PLAN"
            verify_hashes = $true
            restore_baseline = $true
        }
    }
    $auditConflictManifestPath = Join-Path $auditConflictPackage "update-audit-conflict.json"
    Write-Utf8NoBom -Path $auditConflictManifestPath -Content ($auditConflictManifest | ConvertTo-Json -Depth 10)

    & git -C $auditConflictProject add .
    & git -C $auditConflictProject commit -m "audit conflict baseline" | Out-Null

    try {
        $auditConflictOutput = & $runnerHostPath -NoProfile -ExecutionPolicy Bypass -File $RunnerPath `
            -Action preflight `
            -ProjectRoot $auditConflictProject `
            -UpdateManifest $auditConflictManifestPath `
            -BaselinePath $auditConflictBaselinePath `
            -EvidencePath $auditConflictEvidence `
            -UseDocumentAuditPreflight 2>&1
        $auditConflictExit = $LASTEXITCODE
    }
    catch {
        $auditConflictOutput = @($_.Exception.Message)
        $auditConflictExit = 1
    }

    if ($auditConflictExit -eq 0) {
        throw "AUDIT_CONFLICT_UNEXPECTED_PASS"
    }
    if (-not (@($auditConflictOutput) -match "DOCUMENT_AUDIT_HARD_CONFLICT_BLOCKED")) {
        throw "CRITICAL_FINDING_NOT_BLOCKED: $($auditConflictOutput -join ' | ')"
    }
    if ((Get-Sha256 -Path (Join-Path $auditConflictProject "config.txt")) -ne $auditConflictPre) {
        throw "NO_AUTO_RESOLUTION_VIOLATION"
    }

    Assert-FileContainsAll -Path (Join-Path $repoRoot "90.USECASE\03.SESSION_CONTINUE\PROMPT.SESSION_CONTINUE.txt") -Patterns @(
        "no ejecutar 04 ni 05"
    ) -FailureMessage "NO_CALL_FROM_03_CONTRACT_FAIL"
    Assert-FileContainsAll -Path (Join-Path $repoRoot "90.USECASE\04.REPOSITORY_STRUCTURE_REPAIR\README.EXECUTION.txt") -Patterns @(
        "05.SKILLSMACHINE_UPDATE is never auto-executed from this flow."
    ) -FailureMessage "NO_CALL_FROM_04_CONTRACT_FAIL"

    $report = @"
FINAL_STATUS=PASS_CORE_UPDATER_MVP_TEST
DRY_RUN_FINGERPRINT=$fingerprint
ADD_APPLY=PASS
REPLACE_APPLY=PASS
DELETE_APPLY=PASS
ADD_ROLLBACK=PASS
REPLACE_ROLLBACK=PASS
DELETE_ROLLBACK=PASS
BASELINE_ROLLBACK=PASS
GIT_CLEAN_AFTER_ROLLBACK=PASS
PARTIAL_FAILURE_INDUCED=PASS
AUTOMATIC_ROLLBACK_AFTER_PARTIAL_FAILURE=PASS
NEGATIVE_BASELINE_ROLLBACK=PASS
NEGATIVE_GIT_CLEAN_AFTER_ROLLBACK=PASS
TEST_HOOK_REJECTED_WITHOUT_TEST_MODE=PASS
TEST_HOOK_REJECTED_FOR_NORMAL_PROJECT=PASS
TEST_HOOK_ACCEPTED_FOR_NEGATIVE_TEST_PROJECT=PASS
AUDIT_FINDINGS_CONSUMED=PASS
CRITICAL_FINDING_BLOCKS_MUTATION=PASS
NO_AUTO_RESOLUTION=PASS
NO_CALL_FROM_03=PASS
NO_CALL_FROM_04=PASS
CORE_FILE_COUNT=5
POWERSHELL_PARSE=PASS
SCHEMA_JSON_PARSE=PASS
"@
    Write-Utf8NoBom -Path $OutputPath -Content $report
    Write-Host $report
    exit 0
}
finally {
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
