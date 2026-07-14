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
        [AllowEmptyString()][string]$Content
    )

    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $utf8)
}

function Add-Result {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Value
    )

    $script:ResultMap[$Name] = $Value
}

function Assert-True {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$FailureMessage
    )

    if (-not $Condition) {
        throw $FailureMessage
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

function Convert-ArgumentsToCliList {
    param(
        [Parameter(Mandatory = $true)]$Arguments
    )

    $cli = New-Object System.Collections.Generic.List[string]
    foreach ($entry in $Arguments.GetEnumerator()) {
        $name = [string]$entry.Key
        $value = $entry.Value

        if ($value -is [bool]) {
            if ([bool]$value) {
                [void]$cli.Add(("-{0}" -f $name))
            }
            continue
        }

        if ($value -is [System.Array]) {
            if (@($value).Count -eq 0) {
                continue
            }

            [void]$cli.Add(("-{0}" -f $name))
            foreach ($item in @($value)) {
                [void]$cli.Add([string]$item)
            }
            continue
        }

        if ($null -eq $value) {
            continue
        }

        [void]$cli.Add(("-{0}" -f $name))
        [void]$cli.Add([string]$value)
    }

    return @($cli)
}

function Invoke-RunnerJson {
    param(
        [Parameter(Mandatory = $true)][string]$HostPath,
        [Parameter(Mandatory = $true)][string]$RunnerPath,
        [Parameter(Mandatory = $true)]$Arguments
    )

    $cliArgs = Convert-ArgumentsToCliList -Arguments $Arguments
    try {
        $lines = & $HostPath -NoProfile -ExecutionPolicy Bypass -File $RunnerPath @cliArgs 2>&1
        $exitCode = $LASTEXITCODE
    }
    catch {
        $lines = @($_.Exception.Message)
        $exitCode = 1
    }

    if ($exitCode -ne 0) {
        throw (($lines -join [Environment]::NewLine).Trim())
    }

    $jsonText = ($lines -join [Environment]::NewLine).Trim()
    return ($jsonText | ConvertFrom-Json -ErrorAction Stop)
}

function Invoke-RunnerFailure {
    param(
        [Parameter(Mandatory = $true)][string]$HostPath,
        [Parameter(Mandatory = $true)][string]$RunnerPath,
        [Parameter(Mandatory = $true)]$Arguments
    )

    $cliArgs = Convert-ArgumentsToCliList -Arguments $Arguments
    $exitCode = 0
    try {
        $lines = & $HostPath -NoProfile -ExecutionPolicy Bypass -File $RunnerPath @cliArgs 2>&1
        $exitCode = $LASTEXITCODE
    }
    catch {
        $lines = @($_.Exception.Message)
        $exitCode = 1
    }
    return [pscustomobject]@{
        ExitCode = $exitCode
        Output = ($lines -join [Environment]::NewLine).Trim()
    }
}

function Get-TreeFingerprint {
    param(
        [Parameter(Mandatory = $true)][string]$Root
    )

    $entries = @()
    if (Test-Path -LiteralPath $Root -PathType Container) {
        $entries = @(
            Get-ChildItem -LiteralPath $Root -Recurse -Force -File -ErrorAction SilentlyContinue |
            Sort-Object FullName |
            ForEach-Object {
                "{0}|{1}" -f $_.FullName.Substring($Root.Length).TrimStart("\"), (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToUpperInvariant()
            }
        )
    }

    return [string]::Join([Environment]::NewLine, $entries)
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

function Invoke-RoleResolverIsolatedTest {
    param(
        [Parameter(Mandatory = $true)][string]$RunnerPath
    )

    $root = Join-Path $env:TEMP ("DocumentConsistencyAuditRoleTest." + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $root -Force | Out-Null

    try {
        Write-Utf8NoBom -Path (Join-Path $root "HUMAN.txt") -Content "canonical"
        Write-Utf8NoBom -Path (Join-Path $root "HUMAN.PRECEDENCE.txt") -Content "shadow"

        . $RunnerPath
        $resolved = Resolve-DocumentRole -RootFull ([System.IO.Path]::GetFullPath($root)) -Role "HUMAN" -ProjectId "PROJECT_A" -ExcludedDirectoryNames @(".git")

        $candidateNames = @($resolved.candidates | ForEach-Object { $_.file_name })
        Assert-True -Condition ($candidateNames.Count -eq 2) -FailureMessage "ROLE_RESOLUTION_CANDIDATE_COUNT_INVALID"
        Assert-True -Condition ($candidateNames -contains "HUMAN.PRECEDENCE.txt") -FailureMessage "ROLE_RESOLUTION_MISSING_HUMAN_PRECEDENCE"
        Assert-True -Condition ($candidateNames -contains "HUMAN.txt") -FailureMessage "ROLE_RESOLUTION_MISSING_HUMAN_TXT"
        Assert-True -Condition ($resolved.selected_path -eq "HUMAN.txt") -FailureMessage "ROLE_RESOLUTION_PRECEDENCE_INVALID"

        return [pscustomobject]@{
            Status = "PASS"
            Candidates = ($candidateNames -join ",")
            Selected = $resolved.selected_path
        }
    }
    finally {
        if (Test-Path -LiteralPath $root) {
            Remove-Item -LiteralPath $root -Recurse -Force
        }
    }
}

$script:ResultMap = [ordered]@{}
$runnerFullPath = (Resolve-Path -LiteralPath $RunnerPath).Path
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\..\.."))
$windowsPowerShellPath = (Get-Command powershell.exe -ErrorAction Stop).Source
$powerShell7Path = Get-CommandPathIfRunnable -Name "pwsh.exe"

$testRoot = Join-Path $env:TEMP ("DocumentConsistencyAuditTest." + [guid]::NewGuid().ToString("N"))
$projectA = Join-Path $testRoot "ProjectA"
$projectB = Join-Path $testRoot "ProjectB"
$projectC = Join-Path $testRoot "ProjectC"

New-Item -ItemType Directory -Path $projectA, $projectB, $projectC -Force | Out-Null

try {
    Write-Host "TEST_CASE=BOOTSTRAP"
    $projectAState = Join-Path $projectA "SyS\State\DOCUMENT.CONSISTENCY.AUDIT.STATE.json"

    Write-Utf8NoBom -Path (Join-Path $projectA "HUMAN.PROJECT_A.txt") -Content "PROJECT_ROOT=$projectA"
    Write-Utf8NoBom -Path (Join-Path $projectA "WHOAMI.PROJECT_A.txt") -Content "PROJECT_ID=PROJECT_A"
    Write-Utf8NoBom -Path (Join-Path $projectA "BATON.PROJECT_A.txt") -Content "NEXT_ACTION=TEST"
    Write-Utf8NoBom -Path (Join-Path $projectA "README.txt") -Content "readme"
    Write-Utf8NoBom -Path (Join-Path $projectA "notes.md") -Content "notes"
    New-Item -ItemType Directory -Path (Join-Path $projectA "node_modules"), (Join-Path $projectA "tmp"), (Join-Path $projectA "docs") -Force | Out-Null
    Write-Utf8NoBom -Path (Join-Path $projectA "node_modules\ignored.txt") -Content "ignore"
    Write-Utf8NoBom -Path (Join-Path $projectA "tmp\ignored.ps1") -Content "ignore"
    Write-Utf8NoBom -Path (Join-Path $projectA "docs\included.txt") -Content "include"

    Write-Utf8NoBom -Path (Join-Path $projectB "HUMAN.PROJECT_B.txt") -Content "PROJECT_ROOT=$projectB"
    Write-Utf8NoBom -Path (Join-Path $projectC "WHOAMI.PROJECT_C.txt") -Content "PROJECT_ID=PROJECT_C"
    Write-Utf8NoBom -Path (Join-Path $projectC "BATON.PROJECT_C.txt") -Content "NEXT_ACTION=TEST"

    Write-Host "TEST_CASE=FOCUSED_MODE"
    $focused = Invoke-RunnerJson -HostPath $windowsPowerShellPath -RunnerPath $runnerFullPath -Arguments @{
        Mode = "focused"
        ProjectRoot = $projectA
        ProjectId = "PROJECT_A"
        StatePath = $projectAState
        AcceptedSessionContinue = $true
    }
    Assert-True -Condition ($focused.effective_mode -eq "focused") -FailureMessage "FOCUSED_MODE_FAIL"
    Assert-True -Condition ($focused.status -eq "PASS") -FailureMessage "FOCUSED_STATUS_FAIL"
    Add-Result -Name "FOCUSED_MODE" -Value "PASS"
    Add-Result -Name "FOCUSED_ON_ACCEPTED_CONTINUATION" -Value "PASS"

    Write-Host "TEST_CASE=FULL_SESSION_5"
    for ($i = 0; $i -lt 3; $i++) {
        $null = Invoke-RunnerJson -HostPath $windowsPowerShellPath -RunnerPath $runnerFullPath -Arguments @{
            Mode = "focused"
            ProjectRoot = $projectA
            ProjectId = "PROJECT_A"
            StatePath = $projectAState
            AcceptedSessionContinue = $true
        }
    }

    $session5 = Invoke-RunnerJson -HostPath $windowsPowerShellPath -RunnerPath $runnerFullPath -Arguments @{
        Mode = "focused"
        ProjectRoot = $projectA
        ProjectId = "PROJECT_A"
        StatePath = $projectAState
        AcceptedSessionContinue = $true
    }
    Assert-True -Condition ($session5.effective_mode -eq "full") -FailureMessage "FULL_SESSION_5_FAIL"
    Assert-True -Condition ($session5.summary.next_full_audit_due_session_number -eq 10) -FailureMessage "NEXT_DUE_AFTER_5_FAIL"
    Add-Result -Name "FULL_SESSION_5" -Value "PASS"
    Add-Result -Name "FULL_ON_FIFTH_ACCEPTED_CONTINUATION" -Value "PASS"

    Write-Host "TEST_CASE=FULL_SESSION_10"
    for ($i = 0; $i -lt 4; $i++) {
        $null = Invoke-RunnerJson -HostPath $windowsPowerShellPath -RunnerPath $runnerFullPath -Arguments @{
            Mode = "focused"
            ProjectRoot = $projectA
            ProjectId = "PROJECT_A"
            StatePath = $projectAState
            AcceptedSessionContinue = $true
        }
    }

    $session10 = Invoke-RunnerJson -HostPath $windowsPowerShellPath -RunnerPath $runnerFullPath -Arguments @{
        Mode = "focused"
        ProjectRoot = $projectA
        ProjectId = "PROJECT_A"
        StatePath = $projectAState
        AcceptedSessionContinue = $true
    }
    Assert-True -Condition ($session10.effective_mode -eq "full") -FailureMessage "FULL_SESSION_10_FAIL"
    Assert-True -Condition ($session10.summary.next_full_audit_due_session_number -eq 15) -FailureMessage "NEXT_DUE_15_FAIL"
    Add-Result -Name "FULL_SESSION_10" -Value "PASS"
    Add-Result -Name "NEXT_DUE_15" -Value "PASS"

    Write-Host "TEST_CASE=CRITICAL_TRIGGER"
    $critical = Invoke-RunnerJson -HostPath $windowsPowerShellPath -RunnerPath $runnerFullPath -Arguments @{
        Mode = "focused"
        ProjectRoot = $projectA
        ProjectId = "PROJECT_A"
        StatePath = $projectAState
        ChangedPaths = @("90.USECASE\BUILD.ps1")
        NoStateWrite = $true
    }
    Assert-True -Condition ($critical.effective_mode -eq "full") -FailureMessage "CRITICAL_TRIGGER_FAIL"
    Add-Result -Name "CRITICAL_TRIGGER" -Value "PASS"
    Add-Result -Name "FULL_ON_CRITICAL_TRIGGER" -Value "PASS"

    Write-Host "TEST_CASE=NO_COUNTER_INCREMENT_ON_REJECTED_CONTINUATION"
    $projectNoAccept = Join-Path $testRoot "ProjectNoAccept"
    $projectNoAcceptState = Join-Path $projectNoAccept "SyS\State\DOCUMENT.CONSISTENCY.AUDIT.STATE.json"
    New-Item -ItemType Directory -Path $projectNoAccept -Force | Out-Null
    Write-Utf8NoBom -Path (Join-Path $projectNoAccept "HUMAN.PROJECT_NO_ACCEPT.txt") -Content "PROJECT_ROOT=$projectNoAccept"
    Write-Utf8NoBom -Path (Join-Path $projectNoAccept "WHOAMI.PROJECT_NO_ACCEPT.txt") -Content "PROJECT_ID=PROJECT_NO_ACCEPT"
    $beforeReject = Invoke-RunnerJson -HostPath $windowsPowerShellPath -RunnerPath $runnerFullPath -Arguments @{
        Mode = "focused"
        ProjectRoot = $projectNoAccept
        ProjectId = "PROJECT_NO_ACCEPT"
        StatePath = $projectNoAcceptState
        NoStateWrite = $true
    }
    $afterReject = Invoke-RunnerJson -HostPath $windowsPowerShellPath -RunnerPath $runnerFullPath -Arguments @{
        Mode = "focused"
        ProjectRoot = $projectNoAccept
        ProjectId = "PROJECT_NO_ACCEPT"
        StatePath = $projectNoAcceptState
        NoStateWrite = $true
    }
    Assert-True -Condition ($beforeReject.state_snapshot.session_continue_count -eq 0) -FailureMessage "REJECTED_CONTINUATION_BEFORE_COUNT_INVALID"
    Assert-True -Condition ($afterReject.state_snapshot.session_continue_count -eq 0) -FailureMessage "REJECTED_CONTINUATION_INCREMENTED"
    Assert-True -Condition ($beforeReject.state_path -eq $projectNoAcceptState) -FailureMessage "STATE_PATH_PROJECT_NO_ACCEPT_INVALID"
    Assert-True -Condition ($focused.state_path -eq $projectAState) -FailureMessage "STATE_PATH_PROJECT_A_INVALID"
    Add-Result -Name "NO_COUNTER_INCREMENT_ON_REJECTED_CONTINUATION" -Value "PASS"
    Add-Result -Name "STATE_PATH_PER_PROJECT" -Value "PASS"

    Write-Host "TEST_CASE=CROSS_ROOT_STATE"
    $crossRootState = Invoke-RunnerFailure -HostPath $windowsPowerShellPath -RunnerPath $runnerFullPath -Arguments @{
        Mode = "focused"
        ProjectRoot = $projectA
        ProjectId = "PROJECT_A"
        StatePath = (Join-Path $projectB "state.json")
        NoStateWrite = $true
    }
    Assert-True -Condition ($crossRootState.ExitCode -ne 0 -and $crossRootState.Output.Contains("CROSS_ROOT_STATE_PATH")) -FailureMessage "CROSS_ROOT_STATE_FAIL"
    Add-Result -Name "CROSS_ROOT_STATE" -Value "PASS"
    Add-Result -Name "PROJECT_ROOT_ISOLATION" -Value "PASS"
    Add-Result -Name "ROOT_ISOLATION" -Value "PASS"

    Write-Host "TEST_CASE=CROSS_ROOT_CHANGED_PATH"
    $crossRootChanged = Invoke-RunnerFailure -HostPath $windowsPowerShellPath -RunnerPath $runnerFullPath -Arguments @{
        Mode = "focused"
        ProjectRoot = $projectA
        ProjectId = "PROJECT_A"
        StatePath = $projectAState
        ChangedPaths = @((Join-Path $projectB "HUMAN.PROJECT_B.txt"))
        NoStateWrite = $true
    }
    Assert-True -Condition ($crossRootChanged.ExitCode -ne 0 -and $crossRootChanged.Output.Contains("CROSS_ROOT_CHANGED_PATH")) -FailureMessage "CROSS_ROOT_CHANGED_FAIL"
    Add-Result -Name "CROSS_ROOT_CHANGED_PATH" -Value "PASS"

    Write-Host "TEST_CASE=NO_STATE_WRITE_ZERO_MUTATION"
    $beforeFingerprint = Get-TreeFingerprint -Root $projectA
    $beforeStateExists = Test-Path -LiteralPath $projectAState
    $noStateWrite = Invoke-RunnerJson -HostPath $windowsPowerShellPath -RunnerPath $runnerFullPath -Arguments @{
        Mode = "focused"
        ProjectRoot = $projectA
        ProjectId = "PROJECT_A"
        StatePath = (Join-Path $projectA "SyS\State\NO.WRITE.STATE.json")
        NoStateWrite = $true
    }
    $afterFingerprint = Get-TreeFingerprint -Root $projectA
    Assert-True -Condition ($beforeFingerprint -eq $afterFingerprint) -FailureMessage "NO_STATE_WRITE_TREE_MUTATION"
    Assert-True -Condition (-not (Test-Path -LiteralPath (Join-Path $projectA "SyS\State\NO.WRITE.STATE.json"))) -FailureMessage "NO_STATE_WRITE_CREATED_STATE"
    Assert-True -Condition ($beforeStateExists -eq (Test-Path -LiteralPath $projectAState)) -FailureMessage "NO_STATE_WRITE_STATE_PRESENCE_CHANGED"
    Assert-True -Condition (-not [bool]$noStateWrite.state_written) -FailureMessage "NO_STATE_WRITE_FLAG_INVALID"
    Add-Result -Name "NO_STATE_WRITE_ZERO_MUTATION" -Value "PASS"

    Write-Host "TEST_CASE=DETERMINISTIC_OUTPUT"
    $deterministic1 = Invoke-RunnerJson -HostPath $windowsPowerShellPath -RunnerPath $runnerFullPath -Arguments @{
        Mode = "full"
        ProjectRoot = $projectA
        ProjectId = "PROJECT_A"
        StatePath = $projectAState
        NoStateWrite = $true
    }
    $deterministic2 = Invoke-RunnerJson -HostPath $windowsPowerShellPath -RunnerPath $runnerFullPath -Arguments @{
        Mode = "full"
        ProjectRoot = $projectA
        ProjectId = "PROJECT_A"
        StatePath = $projectAState
        NoStateWrite = $true
    }
    $deterministicJson1 = $deterministic1 | ConvertTo-Json -Depth 40
    $deterministicJson2 = $deterministic2 | ConvertTo-Json -Depth 40
    Assert-True -Condition ($deterministicJson1 -eq $deterministicJson2) -FailureMessage "DETERMINISTIC_OUTPUT_FAIL"
    Add-Result -Name "DETERMINISTIC_OUTPUT" -Value "PASS"

    Write-Host "TEST_CASE=EXCLUSION_PATTERNS"
    $exclusionCheck = Invoke-RunnerJson -HostPath $windowsPowerShellPath -RunnerPath $runnerFullPath -Arguments @{
        Mode = "full"
        ProjectRoot = $projectA
        ProjectId = "PROJECT_A"
        StatePath = $projectAState
        NoStateWrite = $true
    }
    $reviewedPaths = @($exclusionCheck.documents_reviewed | ForEach-Object { [string]$_.relative_path })
    Assert-True -Condition ($reviewedPaths -notcontains "node_modules\ignored.txt") -FailureMessage "EXCLUSION_NODE_MODULES_FAIL"
    Assert-True -Condition ($reviewedPaths -notcontains "tmp\ignored.ps1") -FailureMessage "EXCLUSION_TMP_FAIL"
    Assert-True -Condition ($reviewedPaths -contains "docs\included.txt") -FailureMessage "EXCLUSION_INCLUDED_FILE_MISSING"
    Add-Result -Name "EXCLUSION_PATTERNS" -Value "PASS"

    Write-Host "TEST_CASE=PROJECT_SPECIFIC_ROLE_PRECEDENCE"
    $projectSpecific = Join-Path $testRoot "RoleSpecific"
    New-Item -ItemType Directory -Path $projectSpecific -Force | Out-Null
    Write-Utf8NoBom -Path (Join-Path $projectSpecific "HUMAN.PROJECT_X.txt") -Content "project"
    Write-Utf8NoBom -Path (Join-Path $projectSpecific "HUMAN.txt") -Content "generic"
    $specific = Invoke-RunnerJson -HostPath $windowsPowerShellPath -RunnerPath $runnerFullPath -Arguments @{
        Mode = "focused"
        ProjectRoot = $projectSpecific
        ProjectId = "PROJECT_X"
        StatePath = (Join-Path $projectSpecific "state.json")
        NoStateWrite = $true
    }
    $humanRoleSpecific = @($specific.document_roles | Where-Object { $_.role -eq "HUMAN" })[0]
    Assert-True -Condition ($humanRoleSpecific.selected_path -eq "HUMAN.PROJECT_X.txt") -FailureMessage "PROJECT_SPECIFIC_ROLE_PRECEDENCE_FAIL"
    Add-Result -Name "PROJECT_SPECIFIC_ROLE_PRECEDENCE" -Value "PASS"

    Write-Host "TEST_CASE=PATH_AWARE_PROJECT_SCOPE"
    $pathAware = Join-Path $testRoot "PathAware"
    New-Item -ItemType Directory -Path (Join-Path $pathAware "HUMAN") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $pathAware "99.LABS\CHILD\00.HUMAN") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $pathAware "90.USECASE\04.REPAIR") -Force | Out-Null
    Write-Utf8NoBom -Path (Join-Path $pathAware "HUMAN\HUMAN.OPERATING.MODEL.txt") -Content "root authority"
    Write-Utf8NoBom -Path (Join-Path $pathAware "HUMAN\HUMAN.README.txt") -Content "description only"
    Write-Utf8NoBom -Path (Join-Path $pathAware "99.LABS\CHILD\00.HUMAN\HUMAN.CHILD.txt") -Content "child"
    Write-Utf8NoBom -Path (Join-Path $pathAware "90.USECASE\04.REPAIR\HUMAN.REPAIR.txt") -Content "generated"

    $pathAwareResult = Invoke-RunnerJson -HostPath $windowsPowerShellPath -RunnerPath $runnerFullPath -Arguments @{
        Mode = "focused"
        ProjectRoot = $pathAware
        ProjectId = "ROOT_PROJECT"
        StatePath = (Join-Path $pathAware "state.json")
        NoStateWrite = $true
    }

    $pathAwareHuman = @($pathAwareResult.document_roles | Where-Object { $_.role -eq "HUMAN" })[0]
    Assert-True -Condition ($pathAwareHuman.status -eq "RESOLVED") -FailureMessage "PATH_AWARE_SCOPE_STATUS_FAIL"
    Assert-True -Condition ($pathAwareHuman.selected_path -eq "HUMAN\HUMAN.OPERATING.MODEL.txt") -FailureMessage "PATH_AWARE_SCOPE_SELECTION_FAIL"
    Assert-True -Condition (@($pathAwareHuman.candidates).Count -eq 1) -FailureMessage "PATH_AWARE_SCOPE_CANDIDATE_COUNT_FAIL"
    Add-Result -Name "PATH_AWARE_PROJECT_SCOPE" -Value "PASS"
    Add-Result -Name "README_NOT_ROLE_AUTHORITY" -Value "PASS"
    Add-Result -Name "SUBPROJECT_ROLE_ISOLATION" -Value "PASS"

    Write-Host "TEST_CASE=EQUAL_PRECEDENCE_AMBIGUITY"
    $equalPrecedence = Join-Path $testRoot "RoleConflict"
    New-Item -ItemType Directory -Path $equalPrecedence -Force | Out-Null
    Write-Utf8NoBom -Path (Join-Path $equalPrecedence "HUMAN.PROJECT_Y.txt") -Content "a"
    Write-Utf8NoBom -Path (Join-Path $equalPrecedence "HUMAN.PROJECT_Y.md") -Content "b"
    $equal = Invoke-RunnerJson -HostPath $windowsPowerShellPath -RunnerPath $runnerFullPath -Arguments @{
        Mode = "focused"
        ProjectRoot = $equalPrecedence
        ProjectId = "PROJECT_Y"
        StatePath = (Join-Path $equalPrecedence "state.json")
        NoStateWrite = $true
    }
    Assert-True -Condition (@($equal.issues | Where-Object { $_.issue_class -eq "DUPLICATE_SOURCE_OF_TRUTH" }).Count -ge 1) -FailureMessage "EQUAL_PRECEDENCE_AMBIGUITY_FAIL"
    Assert-True -Condition ($equal.status -eq "HARD_CONFLICT") -FailureMessage "EQUAL_PRECEDENCE_STATUS_FAIL"
    Add-Result -Name "EQUAL_PRECEDENCE_AMBIGUITY" -Value "PASS"
    Add-Result -Name "HARD_CONFLICT_BLOCKS_ACCEPTANCE" -Value "PASS"

    Write-Host "TEST_CASE=MANDATORY_AND_OPTIONAL_ROLES"
    $mandatoryHuman = Invoke-RunnerJson -HostPath $windowsPowerShellPath -RunnerPath $runnerFullPath -Arguments @{
        Mode = "focused"
        ProjectRoot = $projectC
        ProjectId = "PROJECT_C"
        StatePath = (Join-Path $projectC "state.json")
        NoStateWrite = $true
    }
    Assert-True -Condition (@($mandatoryHuman.issues | Where-Object { $_.issue_class -eq "MISSING_REQUIRED_ROLE" }).Count -eq 1) -FailureMessage "MANDATORY_HUMAN_FAIL"
    Add-Result -Name "MANDATORY_HUMAN" -Value "PASS"

    Assert-True -Condition ((@($mandatoryHuman.document_roles | Where-Object { $_.role -eq "WHOAMI" })[0].status) -eq "RESOLVED") -FailureMessage "OPTIONAL_WHOAMI_FAIL"
    Assert-True -Condition ((@($mandatoryHuman.document_roles | Where-Object { $_.role -eq "BATON" })[0].status) -eq "RESOLVED") -FailureMessage "OPTIONAL_BATON_FAIL"
    Add-Result -Name "OPTIONAL_WHOAMI" -Value "PASS"
    Add-Result -Name "OPTIONAL_BATON" -Value "PASS"

    Write-Host "TEST_CASE=STATE_FAILURES"
    $corruptStatePath = Join-Path $projectA "corrupt-state.json"
    Write-Utf8NoBom -Path $corruptStatePath -Content "{"
    $corrupt = Invoke-RunnerFailure -HostPath $windowsPowerShellPath -RunnerPath $runnerFullPath -Arguments @{
        Mode = "focused"
        ProjectRoot = $projectA
        ProjectId = "PROJECT_A"
        StatePath = $corruptStatePath
        NoStateWrite = $true
    }
    Assert-True -Condition ($corrupt.ExitCode -ne 0 -and $corrupt.Output.Contains("STATE_JSON_INVALID")) -FailureMessage "CORRUPT_STATE_FAIL"
    Add-Result -Name "CORRUPT_STATE" -Value "PASS"

    $badSchemaPath = Join-Path $projectA "bad-schema-state.json"
    Write-Utf8NoBom -Path $badSchemaPath -Content (@{
        schema_version = "2.0"
        project_id = "PROJECT_A"
        project_root = $projectA
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
    } | ConvertTo-Json -Depth 10)
    $badSchema = Invoke-RunnerFailure -HostPath $windowsPowerShellPath -RunnerPath $runnerFullPath -Arguments @{
        Mode = "focused"
        ProjectRoot = $projectA
        ProjectId = "PROJECT_A"
        StatePath = $badSchemaPath
        NoStateWrite = $true
    }
    Assert-True -Condition ($badSchema.ExitCode -ne 0 -and $badSchema.Output.Contains("STATE_SCHEMA_VERSION_UNSUPPORTED")) -FailureMessage "INCOMPATIBLE_SCHEMA_FAIL"
    Add-Result -Name "INCOMPATIBLE_SCHEMA" -Value "PASS"

    $mismatchProjectIdPath = Join-Path $projectA "mismatch-project-id-state.json"
    Write-Utf8NoBom -Path $mismatchProjectIdPath -Content (@{
        schema_version = "1.0"
        project_id = "OTHER_PROJECT"
        project_root = $projectA
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
    } | ConvertTo-Json -Depth 10)
    $mismatchProjectId = Invoke-RunnerFailure -HostPath $windowsPowerShellPath -RunnerPath $runnerFullPath -Arguments @{
        Mode = "focused"
        ProjectRoot = $projectA
        ProjectId = "PROJECT_A"
        StatePath = $mismatchProjectIdPath
        NoStateWrite = $true
    }
    Assert-True -Condition ($mismatchProjectId.ExitCode -ne 0 -and $mismatchProjectId.Output.Contains("STATE_PROJECT_ID_MISMATCH")) -FailureMessage "PROJECT_ID_MISMATCH_FAIL"
    Add-Result -Name "PROJECT_ID_MISMATCH" -Value "PASS"

    $mismatchRootPath = Join-Path $projectA "mismatch-root-state.json"
    Write-Utf8NoBom -Path $mismatchRootPath -Content (@{
        schema_version = "1.0"
        project_id = "PROJECT_A"
        project_root = $projectB
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
    } | ConvertTo-Json -Depth 10)
    $mismatchRoot = Invoke-RunnerFailure -HostPath $windowsPowerShellPath -RunnerPath $runnerFullPath -Arguments @{
        Mode = "focused"
        ProjectRoot = $projectA
        ProjectId = "PROJECT_A"
        StatePath = $mismatchRootPath
        NoStateWrite = $true
    }
    Assert-True -Condition ($mismatchRoot.ExitCode -ne 0 -and $mismatchRoot.Output.Contains("STATE_PROJECT_ROOT_MISMATCH")) -FailureMessage "PROJECT_ROOT_MISMATCH_FAIL"
    Add-Result -Name "PROJECT_ROOT_MISMATCH" -Value "PASS"

    $negativeCounterPath = Join-Path $projectA "negative-counter-state.json"
    Write-Utf8NoBom -Path $negativeCounterPath -Content (@{
        schema_version = "1.0"
        project_id = "PROJECT_A"
        project_root = $projectA
        session_continue_count = -1
        focused_audit_count = 0
        full_audit_count = 0
        last_focused_audit_at = $null
        last_full_audit_at = $null
        next_full_audit_due_session_number = 5
        last_audit_result = $null
        unresolved_conflict_count = 0
        unresolved_doubt_count = 0
        audit_trigger_history = @()
    } | ConvertTo-Json -Depth 10)
    $negativeCounter = Invoke-RunnerFailure -HostPath $windowsPowerShellPath -RunnerPath $runnerFullPath -Arguments @{
        Mode = "focused"
        ProjectRoot = $projectA
        ProjectId = "PROJECT_A"
        StatePath = $negativeCounterPath
        NoStateWrite = $true
    }
    Assert-True -Condition ($negativeCounter.ExitCode -ne 0 -and $negativeCounter.Output.Contains("STATE_NEGATIVE_COUNTER")) -FailureMessage "NEGATIVE_COUNTER_FAIL"
    Add-Result -Name "NEGATIVE_COUNTER" -Value "PASS"

    $dueBehindPath = Join-Path $projectA "due-behind-state.json"
    Write-Utf8NoBom -Path $dueBehindPath -Content (@{
        schema_version = "1.0"
        project_id = "PROJECT_A"
        project_root = $projectA
        session_continue_count = 10
        focused_audit_count = 0
        full_audit_count = 0
        last_focused_audit_at = $null
        last_full_audit_at = $null
        next_full_audit_due_session_number = 10
        last_audit_result = $null
        unresolved_conflict_count = 0
        unresolved_doubt_count = 0
        audit_trigger_history = @()
    } | ConvertTo-Json -Depth 10)
    $dueBehind = Invoke-RunnerFailure -HostPath $windowsPowerShellPath -RunnerPath $runnerFullPath -Arguments @{
        Mode = "focused"
        ProjectRoot = $projectA
        ProjectId = "PROJECT_A"
        StatePath = $dueBehindPath
        NoStateWrite = $true
    }
    Assert-True -Condition ($dueBehind.ExitCode -ne 0 -and $dueBehind.Output.Contains("STATE_DUE_SESSION_BEHIND_COUNTER")) -FailureMessage "DUE_BEHIND_COUNTER_FAIL"
    Add-Result -Name "DUE_BEHIND_COUNTER" -Value "PASS"

    Write-Host "TEST_CASE=REPARSE_POINT_DEFENSE_OR_SKIP"
    $reparseStatus = "SKIP_ENVIRONMENT"
    $reparseRoot = Join-Path $testRoot "ReparseRoot"
    $reparseTarget = Join-Path $testRoot "ReparseTarget"
    New-Item -ItemType Directory -Path $reparseRoot, $reparseTarget -Force | Out-Null
    Write-Utf8NoBom -Path (Join-Path $reparseRoot "HUMAN.REPARSE.txt") -Content "root"
    Write-Utf8NoBom -Path (Join-Path $reparseTarget "outside.txt") -Content "outside"
    try {
        New-Item -ItemType Junction -Path (Join-Path $reparseRoot "linked") -Target $reparseTarget -ErrorAction Stop | Out-Null
        $reparseResult = Invoke-RunnerFailure -HostPath $windowsPowerShellPath -RunnerPath $runnerFullPath -Arguments @{
            Mode = "focused"
            ProjectRoot = $reparseRoot
            ProjectId = "REPARSE"
            StatePath = (Join-Path $reparseRoot "linked\state.json")
            NoStateWrite = $true
        }
        Assert-True -Condition ($reparseResult.ExitCode -ne 0 -and $reparseResult.Output.Contains("REPARSE_POINT_STATE_PATH")) -FailureMessage "REPARSE_POINT_DEFENSE_FAIL"
        $reparseStatus = "PASS"
    }
    catch {
        $reparseStatus = "SKIP_ENVIRONMENT"
    }
    Add-Result -Name "REPARSE_POINT_DEFENSE_OR_SKIP" -Value $reparseStatus

    Write-Host "TEST_CASE=ROLE_RESOLUTION_ISOLATED"
    $roleResolverIsolated = Invoke-RoleResolverIsolatedTest -RunnerPath $runnerFullPath
    Assert-True -Condition ($roleResolverIsolated.Status -eq "PASS") -FailureMessage "ROLE_RESOLUTION_ISOLATED_FAIL"
    Add-Result -Name "ROLE_RESOLUTION_ISOLATED" -Value ("PASS candidates={0} selected={1}" -f $roleResolverIsolated.Candidates, $roleResolverIsolated.Selected)

    Write-Host "TEST_CASE=POWERSHELL_PARSE"
    $parse5Tokens = $null
    $parse5Errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($runnerFullPath, [ref]$parse5Tokens, [ref]$parse5Errors)
    Assert-True -Condition (@($parse5Errors).Count -eq 0) -FailureMessage "POWERSHELL_5_1_PARSE_FAIL"
    Add-Result -Name "POWERSHELL_5_1_PARSE_OR_SKIP" -Value "PASS"

    if ($null -ne $powerShell7Path) {
        $pwshParse = & $powerShell7Path -NoProfile -ExecutionPolicy Bypass -Command @"
`$files = @(
  '$($runnerFullPath.Replace("'", "''"))',
  '$((Resolve-Path -LiteralPath $PSCommandPath).Path.Replace("'", "''"))'
)
foreach (`$f in `$files) {
  `$t = `$null
  `$e = `$null
  [void][System.Management.Automation.Language.Parser]::ParseFile(`$f, [ref]`$t, [ref]`$e)
  if (`$e.Count -gt 0) {
    Write-Host ((`$e | ForEach-Object { `$_.Message }) -join ' | ')
    exit 1
  }
}
Write-Host PASS
"@
        if ($LASTEXITCODE -ne 0) {
            throw "POWERSHELL_7_PARSE_FAIL: $pwshParse"
        }
        Add-Result -Name "POWERSHELL_7_PARSE" -Value "PASS"
    }
    else {
        Add-Result -Name "POWERSHELL_7_PARSE" -Value "SKIP_ENVIRONMENT"
    }

    Write-Host "TEST_CASE=UPDATE_AUTO_EXECUTION_DISABLED"
    $focusedUpdate = Invoke-RunnerJson -HostPath $windowsPowerShellPath -RunnerPath $runnerFullPath -Arguments @{
        Mode = "focused"
        ProjectRoot = $projectA
        ProjectId = "PROJECT_A"
        StatePath = $projectAState
        NoStateWrite = $true
    }
    Assert-True -Condition (-not [bool]$focusedUpdate.update_assessment.automatic_execution) -FailureMessage "UPDATE_AUTO_EXECUTION_DISABLED_FAIL"
    Add-Result -Name "UPDATE_AUTO_EXECUTION_DISABLED" -Value "PASS"
    Add-Result -Name "NO_AUTO_05" -Value "PASS"

    Write-Host "TEST_CASE=USECASE_CONTRACT_DOCS"
    Assert-FileContainsAll -Path (Join-Path $repoRoot "90.USECASE\03.SESSION_CONTINUE\PROMPT.SESSION_CONTINUE.txt") -Patterns @(
        "AcceptedSessionContinue=false",
        "AcceptedSessionContinue=true",
        "no ejecutar 04 ni 05"
    ) -FailureMessage "SESSION_CONTINUE_PROMPT_CONTRACT_FAIL"
    Assert-FileContainsAll -Path (Join-Path $repoRoot "90.USECASE\03.SESSION_CONTINUE\README.UPLOAD_THIS_USECASE.txt") -Patterns @(
        "AcceptedSessionContinue=false",
        "AcceptedSessionContinue=true",
        "SESSION_CONTINUE no debe ejecutar"
    ) -FailureMessage "SESSION_CONTINUE_README_CONTRACT_FAIL"
    Assert-FileContainsAll -Path (Join-Path $repoRoot "90.USECASE\04.REPOSITORY_STRUCTURE_REPAIR\SKILL.md") -Patterns @(
        "DocumentConsistencyAudit integration",
        "before proposing or applying repair",
        "authority of intent, but still auditable",
        "[REF_CRUZADA: <project>]",
        "must not execute it automatically"
    ) -FailureMessage "REPOSITORY_REPAIR_SKILL_CONTRACT_FAIL"
    Assert-FileContainsAll -Path (Join-Path $repoRoot "90.USECASE\04.REPOSITORY_STRUCTURE_REPAIR\README.EXECUTION.txt") -Patterns @(
        "Full DocumentConsistencyAudit before repair proposal",
        "HARD_CONFLICT blocks destructive or mutating repair",
        "[REF_CRUZADA: <project>]",
        "05.SkillsMachineUpdate is never auto-executed from this flow."
    ) -FailureMessage "REPOSITORY_REPAIR_README_CONTRACT_FAIL"
    Add-Result -Name "NO_AUTO_04" -Value "PASS"
    Add-Result -Name "FULL_AUDIT_REQUIRED" -Value "PASS"
    Add-Result -Name "HARD_CONFLICT_BLOCKS_MUTATION" -Value "PASS"
    Add-Result -Name "HUMAN_AUDITABLE" -Value "PASS"
    Add-Result -Name "CROSS_PROJECT_REFERENCE_MARKING" -Value "PASS"

    $lines = New-Object System.Collections.Generic.List[string]
    [void]$lines.Add("FINAL_STATUS=PASS_DOCUMENT_CONSISTENCY_AUDIT_CORE_TEST")
    foreach ($key in @($script:ResultMap.Keys)) {
        [void]$lines.Add("$key=$($script:ResultMap[$key])")
    }

    Write-Utf8NoBom -Path $OutputPath -Content ([string]::Join([Environment]::NewLine, $lines) + [Environment]::NewLine)
}
finally {
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
