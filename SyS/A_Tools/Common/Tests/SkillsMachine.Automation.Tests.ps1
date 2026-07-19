#Requires -Version 5.1
<#
.SYNOPSIS
    Pester tests for SkillsMachine.Automation.psm1.
    Compatible with Pester 3.4.x (uses Pester 3 assertion syntax).
    All tests use isolated temp directories/repos; PROJECT_ROOT is never mutated.
#>

# Guard: when run inside the runner (Pester already loaded), skip the import.
# Forcing a re-import with -Force would reset Pester's internal result counters to 0.
if ($null -eq (Get-Module Pester -ErrorAction SilentlyContinue)) {
    Import-Module Pester -MinimumVersion 3.0.0 -ErrorAction Stop
}

$ModulePath = Join-Path $PSScriptRoot '..\SkillsMachine.Automation.psm1'
Import-Module $ModulePath -Force -ErrorAction Stop

#region ── Helpers ────────────────────────────────────────────────────────────

function New-TempDir {
    $path = Join-Path $env:TEMP "SM_AutoTest_$(Get-Random)"
    New-Item -ItemType Directory -Path $path -Force | Out-Null
    return $path
}

function Initialize-TempGitRepo {
    [CmdletBinding()]
    param([string]$Path)
    Invoke-GitSafe -RepositoryRoot $Path -Arguments @('init') | Out-Null
    Invoke-GitSafe -RepositoryRoot $Path -Arguments @('config', 'user.email', 'test@local') | Out-Null
    Invoke-GitSafe -RepositoryRoot $Path -Arguments @('config', 'user.name', 'Test') | Out-Null
    $seedFile = Join-Path $Path 'seed.txt'
    [System.IO.File]::WriteAllText($seedFile, 'seed', [System.Text.UTF8Encoding]::new($false))
    Invoke-GitSafe -RepositoryRoot $Path -Arguments @('add', 'seed.txt') | Out-Null
    Invoke-GitSafe -RepositoryRoot $Path -Arguments @('commit', '-m', 'initial') | Out-Null
}

# Pester 3's Should Throw does not reliably catch module-level terminating errors.
# Use this helper for all exception-expectation tests.
function Invoke-ExpectingThrow {
    param([scriptblock]$Block)
    $threw = $false
    try { & $Block } catch { $threw = $true }
    return $threw
}

# Returns $true if the block completes without throwing.
function Invoke-ExpectingNoThrow {
    param([scriptblock]$Block)
    try { & $Block; return $true } catch { return $false }
}

#endregion

#region ── A. Test-ObjectProperty ─────────────────────────────────────────────

Describe 'A. Test-ObjectProperty' {

    It 'A1: null object returns false' {
        $result = Test-ObjectProperty -InputObject $null -Name 'Foo'
        $result | Should Be $false
    }

    It 'A2: absent property returns false under StrictMode' {
        Set-StrictMode -Version Latest
        $obj = [PSCustomObject]@{ Present = 1 }
        $result = Test-ObjectProperty -InputObject $obj -Name 'Absent'
        $result | Should Be $false
    }

    It 'A3: present property with null value returns true' {
        $obj = [PSCustomObject]@{ MyProp = $null }
        $result = Test-ObjectProperty -InputObject $obj -Name 'MyProp'
        $result | Should Be $true
    }

    It 'A4: present property with non-null value returns true' {
        $obj = [PSCustomObject]@{ MyProp = 'hello' }
        $result = Test-ObjectProperty -InputObject $obj -Name 'MyProp'
        $result | Should Be $true
    }
}

#endregion

#region ── B. Write-Utf8NoBom ────────────────────────────────────────────────

Describe 'B. Write-Utf8NoBom' {

    BeforeAll {
        $script:bDir = New-TempDir
    }

    AfterAll {
        if ($script:bDir -and (Test-Path $script:bDir)) {
            Remove-Item $script:bDir -Recurse -Force
        }
    }

    It 'B1: output file has no BOM (first 3 bytes are not EF BB BF)' {
        $path = Join-Path $script:bDir 'nobom.txt'
        Write-Utf8NoBom -Path $path -Content 'hello'
        $bytes = [System.IO.File]::ReadAllBytes($path)
        ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) | Should Be $false
    }

    It 'B2: content round-trips exactly' {
        $path    = Join-Path $script:bDir 'roundtrip.txt'
        $content = "line1`r`nline2`r`n"
        Write-Utf8NoBom -Path $path -Content $content
        $read = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
        $read | Should Be $content
    }

    It 'B3: -CreateParent creates missing parent directories' {
        $path = Join-Path $script:bDir 'nested\deep\file.txt'
        Invoke-ExpectingNoThrow { Write-Utf8NoBom -Path $path -Content 'x' -CreateParent } | Should Be $true
        Test-Path $path | Should Be $true
    }

    It 'B4: missing parent without -CreateParent throws' {
        $path = Join-Path $script:bDir 'missing\parent\file.txt'
        Invoke-ExpectingThrow { Write-Utf8NoBom -Path $path -Content 'x' } | Should Be $true
    }
}

#endregion

#region ── C. Get-Sha256 ──────────────────────────────────────────────────────

Describe 'C. Get-Sha256' {

    BeforeAll {
        $script:cDir = New-TempDir

        # Known content: ASCII bytes for 'abc' = {0x61, 0x62, 0x63}
        $script:cKnownBytes   = [byte[]]@(0x61, 0x62, 0x63)
        $script:cKnownPath    = Join-Path $script:cDir 'known.txt'
        [System.IO.File]::WriteAllBytes($script:cKnownPath, $script:cKnownBytes)

        # Compute expected hash from the same bytes directly (avoids hardcoded value)
        $sha = [System.Security.Cryptography.SHA256]::Create()
        $script:cExpectedHash = ($sha.ComputeHash($script:cKnownBytes) | ForEach-Object { $_.ToString('x2') }) -join ''
        $sha.Dispose()
    }

    AfterAll {
        if ($script:cDir -and (Test-Path $script:cDir)) {
            Remove-Item $script:cDir -Recurse -Force
        }
    }

    It 'C1: known content returns expected lowercase SHA256 (64 hex chars)' {
        $actual = Get-Sha256 -Path $script:cKnownPath
        $actual | Should Be $script:cExpectedHash
        $actual.Length | Should Be 64
        $actual | Should Match '^[0-9a-f]{64}$'
    }

    It 'C2: missing file throws' {
        Invoke-ExpectingThrow { Get-Sha256 -Path (Join-Path $script:cDir 'noexist.txt') } | Should Be $true
    }
}

#endregion

#region ── D. Invoke-GitSafe ─────────────────────────────────────────────────

Describe 'D. Invoke-GitSafe' {

    BeforeAll {
        $script:dRepo = New-TempDir
        Initialize-TempGitRepo -Path $script:dRepo
    }

    AfterAll {
        if ($script:dRepo -and (Test-Path $script:dRepo)) {
            Remove-Item $script:dRepo -Recurse -Force
        }
    }

    It 'D1: returns exactly one PSCustomObject, not a collection' {
        $result = Invoke-GitSafe -RepositoryRoot $script:dRepo -Arguments @('rev-parse', 'HEAD')
        @($result).Count | Should Be 1
        $result.GetType().Name | Should Be 'PSCustomObject'
    }

    It 'D2: StdOutLines is always a string array (never null)' {
        $result = Invoke-GitSafe -RepositoryRoot $script:dRepo -Arguments @('rev-parse', 'HEAD')
        $result.StdOutLines | Should Not Be $null
        ($result.StdOutLines -is [System.Array]) | Should Be $true
    }

    It 'D3: StdErrLines is always a string array (never null)' {
        $result = Invoke-GitSafe -RepositoryRoot $script:dRepo -Arguments @('rev-parse', 'HEAD')
        $result.StdErrLines | Should Not Be $null
        ($result.StdErrLines -is [System.Array]) | Should Be $true
    }

    It 'D4: read-only git command succeeds and Succeeded=true' {
        $result = Invoke-GitSafe -RepositoryRoot $script:dRepo -Arguments @('status', '--porcelain')
        $result.Succeeded | Should Be $true
        $result.ExitCode  | Should Be 0
    }

    It 'D5: failing git command throws without -AllowFailure' {
        Invoke-ExpectingThrow {
            Invoke-GitSafe -RepositoryRoot $script:dRepo -Arguments @('rev-parse', 'refs/heads/no-such-branch-xyz')
        } | Should Be $true
    }

    It 'D6: argument containing spaces is preserved in output' {
        $result = Invoke-GitSafe -RepositoryRoot $script:dRepo `
            -Arguments @('log', '--pretty=format:%H %s', '--max-count=1')
        $result.Succeeded | Should Be $true
        # Output should contain a hash followed by a space and a message
        $result.StdOutText | Should Match '\w+ '
    }
}

#endregion

#region ── E. Get-GitStatus ──────────────────────────────────────────────────

Describe 'E. Get-GitStatus' {

    BeforeAll {
        $script:eRepoClean = New-TempDir
        Initialize-TempGitRepo -Path $script:eRepoClean
    }

    AfterAll {
        if ($script:eRepoClean -and (Test-Path $script:eRepoClean)) {
            Remove-Item $script:eRepoClean -Recurse -Force
        }
    }

    It 'E1: clean repo has IsClean=true and empty collections' {
        $status = Get-GitStatus -RepositoryRoot $script:eRepoClean
        $status.IsClean          | Should Be $true
        $status.Untracked.Count  | Should Be 0
        $status.Modified.Count   | Should Be 0
        $status.Staged.Count     | Should Be 0
    }

    It 'E2: modified tracked file appears in Modified' {
        $repo = New-TempDir
        Initialize-TempGitRepo -Path $repo
        [System.IO.File]::WriteAllText((Join-Path $repo 'seed.txt'), 'changed', [System.Text.UTF8Encoding]::new($false))
        $status = Get-GitStatus -RepositoryRoot $repo
        $status.IsClean        | Should Be $false
        $status.Modified.Count | Should BeGreaterThan 0
        Remove-Item $repo -Recurse -Force
    }

    It 'E3: staged new file appears in Staged' {
        $repo = New-TempDir
        Initialize-TempGitRepo -Path $repo
        [System.IO.File]::WriteAllText((Join-Path $repo 'staged.txt'), 'new', [System.Text.UTF8Encoding]::new($false))
        Invoke-GitSafe -RepositoryRoot $repo -Arguments @('add', 'staged.txt') | Out-Null
        $status = Get-GitStatus -RepositoryRoot $repo
        $status.IsClean      | Should Be $false
        $status.Staged.Count | Should BeGreaterThan 0
        Remove-Item $repo -Recurse -Force
    }

    It 'E4: untracked file appears in Untracked' {
        $repo = New-TempDir
        Initialize-TempGitRepo -Path $repo
        [System.IO.File]::WriteAllText((Join-Path $repo 'untracked.txt'), 'new', [System.Text.UTF8Encoding]::new($false))
        $status = Get-GitStatus -RepositoryRoot $repo
        $status.IsClean          | Should Be $false
        $status.Untracked.Count  | Should BeGreaterThan 0
        Remove-Item $repo -Recurse -Force
    }

    It 'E5: path containing spaces is captured in Untracked' {
        $repo = New-TempDir
        Initialize-TempGitRepo -Path $repo
        $spacedPath = Join-Path $repo 'file with spaces.txt'
        [System.IO.File]::WriteAllText($spacedPath, 'x', [System.Text.UTF8Encoding]::new($false))
        $status = Get-GitStatus -RepositoryRoot $repo
        $hasSpaced = @($status.Untracked | Where-Object { $_ -match 'spaces' })
        $hasSpaced.Count | Should BeGreaterThan 0
        Remove-Item $repo -Recurse -Force
    }

    It 'E6: all status collections are arrays even when empty' {
        $status = Get-GitStatus -RepositoryRoot $script:eRepoClean
        ($status.Staged     -is [System.Array]) | Should Be $true
        ($status.Modified   -is [System.Array]) | Should Be $true
        ($status.Deleted    -is [System.Array]) | Should Be $true
        ($status.Renamed    -is [System.Array]) | Should Be $true
        ($status.Untracked  -is [System.Array]) | Should Be $true
        ($status.Conflicted -is [System.Array]) | Should Be $true
        ($status.RawLines   -is [System.Array]) | Should Be $true
    }
}

#endregion

#region ── F. Get-RepoIdentity / Assert-ProjectContext ────────────────────────

Describe 'F. Get-RepoIdentity / Assert-ProjectContext' {

    BeforeAll {
        $script:fRepo = New-TempDir
        Initialize-TempGitRepo -Path $script:fRepo

        $brResult = Invoke-GitSafe -RepositoryRoot $script:fRepo `
            -Arguments @('rev-parse', '--abbrev-ref', 'HEAD') -AllowFailure
        $script:fBranch = $brResult.StdOutText.Trim()

        $hdResult = Invoke-GitSafe -RepositoryRoot $script:fRepo `
            -Arguments @('rev-parse', 'HEAD') -AllowFailure
        $script:fHead = $hdResult.StdOutText.Trim()

        # Create a local bare remote for origin/main testing
        $script:fBareDir = New-TempDir
        $script:fBare    = Join-Path $script:fBareDir 'bare.git'
        New-Item -ItemType Directory -Path $script:fBare -Force | Out-Null
        Invoke-GitSafe -RepositoryRoot $script:fBare -Arguments @('init', '--bare') | Out-Null
        Invoke-GitSafe -RepositoryRoot $script:fRepo -Arguments @('remote', 'add', 'origin', $script:fBare) | Out-Null
        Invoke-GitSafe -RepositoryRoot $script:fRepo -Arguments @('push', 'origin', "$($script:fBranch):main") | Out-Null
    }

    AfterAll {
        foreach ($d in @($script:fRepo, $script:fBareDir)) {
            if ($d -and (Test-Path $d)) { Remove-Item $d -Recurse -Force }
        }
    }

    It 'F1: correct root/branch/head passes Assert-ProjectContext' {
        Invoke-ExpectingNoThrow {
            Assert-ProjectContext `
                -ExpectedRoot   $script:fRepo `
                -ExpectedBranch $script:fBranch `
                -ExpectedHead   $script:fHead
        } | Should Be $true
    }

    It 'F2: wrong ExpectedRoot throws PROJECT_CONTEXT_MISMATCH' {
        $wrongRoot = New-TempDir
        Initialize-TempGitRepo -Path $wrongRoot
        $errorMsg = ''
        try {
            Assert-ProjectContext -ExpectedRoot $wrongRoot -ExpectedBranch $script:fBranch -ExpectedHead $script:fHead
        } catch {
            $errorMsg = $_.Exception.Message
        }
        Remove-Item $wrongRoot -Recurse -Force
        $errorMsg | Should Match 'PROJECT_CONTEXT_MISMATCH'
    }

    It 'F3: wrong ExpectedBranch throws PROJECT_CONTEXT_MISMATCH' {
        $errorMsg = ''
        try {
            Assert-ProjectContext -ExpectedRoot $script:fRepo -ExpectedBranch 'no-such-branch-xyz'
        } catch {
            $errorMsg = $_.Exception.Message
        }
        $errorMsg | Should Match 'PROJECT_CONTEXT_MISMATCH'
    }

    It 'F4: wrong ExpectedHead throws PROJECT_CONTEXT_MISMATCH' {
        $errorMsg = ''
        try {
            Assert-ProjectContext -ExpectedRoot $script:fRepo -ExpectedHead ('0' * 40)
        } catch {
            $errorMsg = $_.Exception.Message
        }
        $errorMsg | Should Match 'PROJECT_CONTEXT_MISMATCH'
    }

    It 'F5: Get-RepoIdentity detects origin/main after push to local bare remote' {
        $identity = Get-RepoIdentity -RepositoryRoot $script:fRepo
        $identity.OriginMain           | Should Not BeNullOrEmpty
        $identity.HeadEqualsOriginMain | Should Be $true
    }
}

#endregion

#region ── G. Assert-WorktreeClean ───────────────────────────────────────────

Describe 'G. Assert-WorktreeClean' {

    It 'G1: clean repo returns without throwing' {
        $repo = New-TempDir
        Initialize-TempGitRepo -Path $repo
        Invoke-ExpectingNoThrow { Assert-WorktreeClean -RepositoryRoot $repo } | Should Be $true
        Remove-Item $repo -Recurse -Force
    }

    It 'G2: dirty repo throws WORKTREE_NOT_CLEAN' {
        $repo = New-TempDir
        Initialize-TempGitRepo -Path $repo
        [System.IO.File]::WriteAllText((Join-Path $repo 'dirty.txt'), 'x', [System.Text.UTF8Encoding]::new($false))
        $errorMsg = ''
        try { Assert-WorktreeClean -RepositoryRoot $repo } catch { $errorMsg = $_.Exception.Message }
        Remove-Item $repo -Recurse -Force
        $errorMsg | Should Match 'WORKTREE_NOT_CLEAN'
    }

    It 'G3: exact allowed path does not trigger failure' {
        $repo = New-TempDir
        Initialize-TempGitRepo -Path $repo
        [System.IO.File]::WriteAllText((Join-Path $repo 'allowed.txt'), 'x', [System.Text.UTF8Encoding]::new($false))
        Invoke-ExpectingNoThrow {
            Assert-WorktreeClean -RepositoryRoot $repo -AllowedPaths @('allowed.txt')
        } | Should Be $true
        Remove-Item $repo -Recurse -Force
    }

    It 'G4: second dirty path outside AllowedPaths still fails' {
        $repo = New-TempDir
        Initialize-TempGitRepo -Path $repo
        [System.IO.File]::WriteAllText((Join-Path $repo 'allowed.txt'),    'x', [System.Text.UTF8Encoding]::new($false))
        [System.IO.File]::WriteAllText((Join-Path $repo 'unexpected.txt'), 'x', [System.Text.UTF8Encoding]::new($false))
        $errorMsg = ''
        try { Assert-WorktreeClean -RepositoryRoot $repo -AllowedPaths @('allowed.txt') }
        catch { $errorMsg = $_.Exception.Message }
        Remove-Item $repo -Recurse -Force
        $errorMsg | Should Match 'WORKTREE_NOT_CLEAN'
    }
}

#endregion

#region ── H. Read-JsonSafe / Get-UseCaseRegistryModel ───────────────────────

Describe 'H. Read-JsonSafe and Get-UseCaseRegistryModel' {

    BeforeAll {
        $script:hDir = New-TempDir
    }

    AfterAll {
        if ($script:hDir -and (Test-Path $script:hDir)) {
            Remove-Item $script:hDir -Recurse -Force
        }
    }

    It 'H1: minimal valid schema resolves usecases and support_packages' {
        $json = '{"version":"v3.0-TEST","usecases":[{"name":"01.UC_A","bundle_definitions":[]}],"support_packages":[{"name":"05.PKG","package_type":"SUPPORT_PACKAGE"}]}'
        $path = Join-Path $script:hDir 'registry1.json'
        Write-Utf8NoBom -Path $path -Content $json
        $model = Get-UseCaseRegistryModel -RegistryPath $path
        $model.Version               | Should Be 'v3.0-TEST'
        $model.UseCases.Count        | Should Be 1
        $model.SupportPackages.Count | Should Be 1
        $model.ValidPackageCount     | Should Be 2
    }

    It 'H2: usecases and support_packages are arrays even with zero entries' {
        $json = '{"version":"v1","usecases":[]}'
        $path = Join-Path $script:hDir 'registry2.json'
        Write-Utf8NoBom -Path $path -Content $json
        $model = Get-UseCaseRegistryModel -RegistryPath $path
        ($model.UseCases        -is [System.Array]) | Should Be $true
        ($model.SupportPackages -is [System.Array]) | Should Be $true
        $model.UseCases.Count | Should Be 0
    }

    It 'H3: absent optional properties do not throw under StrictMode' {
        $json = '{"version":"v1","usecases":[]}'
        $path = Join-Path $script:hDir 'registry3.json'
        Write-Utf8NoBom -Path $path -Content $json
        Invoke-ExpectingNoThrow { Get-UseCaseRegistryModel -RegistryPath $path } | Should Be $true
    }

    It 'H4: missing required top-level property throws' {
        $json = '{"usecases":[]}'
        $path = Join-Path $script:hDir 'registry4.json'
        Write-Utf8NoBom -Path $path -Content $json
        Invoke-ExpectingThrow { Get-UseCaseRegistryModel -RegistryPath $path } | Should Be $true
    }

    It 'H5: malformed JSON throws with clear message' {
        $path = Join-Path $script:hDir 'registry5.json'
        Write-Utf8NoBom -Path $path -Content '{ not valid json }'
        Invoke-ExpectingThrow { Read-JsonSafe -Path $path } | Should Be $true
    }

    It 'H6: Get-UseCaseRegistryModel returns only registry-declared usecases (no filesystem scan)' {
        $json = '{"version":"v1","usecases":[{"name":"01.FAKE","bundle_definitions":[]}]}'
        $path = Join-Path $script:hDir 'registry6.json'
        Write-Utf8NoBom -Path $path -Content $json
        $model = Get-UseCaseRegistryModel -RegistryPath $path
        $model.UseCases.Count | Should Be 1
    }
}

#endregion

#region ── I. Test-PowerShellFileSyntax ──────────────────────────────────────

Describe 'I. Test-PowerShellFileSyntax' {

    BeforeAll {
        $script:iDir = New-TempDir

        $script:iValidPs1 = Join-Path $script:iDir 'valid.ps1'
        Write-Utf8NoBom -Path $script:iValidPs1 -Content 'Write-Host "hello"'

        $script:iInvalidPs1 = Join-Path $script:iDir 'invalid.ps1'
        Write-Utf8NoBom -Path $script:iInvalidPs1 -Content 'function {'   # syntax error: missing name

        $script:iSideEffectFlag = Join-Path $script:iDir 'side_effect_was_run.txt'
        $probeContent = 'New-Item -ItemType File -Path "' + $script:iSideEffectFlag + '" -Force'
        $script:iProbePs1 = Join-Path $script:iDir 'probe.ps1'
        Write-Utf8NoBom -Path $script:iProbePs1 -Content $probeContent
    }

    AfterAll {
        if ($script:iDir -and (Test-Path $script:iDir)) {
            Remove-Item $script:iDir -Recurse -Force
        }
    }

    It 'I1: valid PowerShell file returns IsValid=true with zero errors' {
        $result = Test-PowerShellFileSyntax -Path $script:iValidPs1
        $result.IsValid    | Should Be $true
        $result.ErrorCount | Should Be 0
    }

    It 'I2: invalid PowerShell file returns IsValid=false with at least one error' {
        $result = Test-PowerShellFileSyntax -Path $script:iInvalidPs1
        $result.IsValid    | Should Be $false
        $result.ErrorCount | Should BeGreaterThan 0
    }

    It 'I3: syntax check does not execute the file (no side effects produced)' {
        Test-PowerShellFileSyntax -Path $script:iProbePs1 | Out-Null
        Test-Path $script:iSideEffectFlag | Should Be $false
    }
}

#endregion

#region ── J. New-AiTail ──────────────────────────────────────────────────────

Describe 'J. New-AiTail' {

    It 'J1: output contains exactly one AI_TAIL_START and one AI_TAIL_END' {
        $fields = [ordered]@{ KEY1 = 'val1'; KEY2 = 'val2' }
        $tail   = New-AiTail -Fields $fields
        ($tail -split 'AI_TAIL_START').Count - 1 | Should Be 1
        ($tail -split 'AI_TAIL_END').Count   - 1 | Should Be 1
    }

    It 'J2: exactly five CRLF sequences precede the AI_TAIL_START delimiter' {
        $fields = [ordered]@{ X = 'y' }
        $tail   = New-AiTail -Fields $fields
        $before = ($tail -split '={10}')[0]   # text before the first ====... delimiter
        $crlfCount = ([regex]::Matches($before, "`r`n")).Count
        $crlfCount | Should Be 5
    }

    It 'J3: KEY=VALUE pairs appear in insertion order (ordered dictionary)' {
        $fields = [ordered]@{ FIRST = '1'; SECOND = '2'; THIRD = '3' }
        $tail   = New-AiTail -Fields $fields
        $iFirst  = $tail.IndexOf('FIRST=')
        $iSecond = $tail.IndexOf('SECOND=')
        $iThird  = $tail.IndexOf('THIRD=')
        ($iFirst  -lt $iSecond) | Should Be $true
        ($iSecond -lt $iThird)  | Should Be $true
    }

    It 'J4: null value is normalized to empty string in output' {
        $fields = [ordered]@{ NULL_KEY = $null }
        $tail   = New-AiTail -Fields $fields
        $tail | Should Match 'NULL_KEY='
    }

    It 'J5: key containing "=" throws' {
        $fields = [ordered]@{}
        $fields['BAD=KEY'] = 'val'
        Invoke-ExpectingThrow { New-AiTail -Fields $fields } | Should Be $true
    }
}

#endregion

#region ── L. Automation gate fail-closed behavior ──────────────────────────

# Helper: checks a dictionary of label→path mappings; returns list of missing labels.
# Mirrors the artifact-presence logic in Validate-System's fail-closed gate.
function Invoke-ArtifactPresenceCheck {
    param([System.Collections.IDictionary]$Artifacts)
    $missing = [System.Collections.Generic.List[string]]::new()
    foreach ($label in $Artifacts.Keys) {
        if (-not (Test-Path -LiteralPath $Artifacts[$label] -PathType Leaf)) {
            $missing.Add($label.ToString()) | Out-Null
        }
    }
    return $missing
}

# Helper: validates a runner summary text against the fail-closed gate rules.
# Returns a hashtable with Passed (bool) and Reason (string).
function Invoke-SummaryValidation {
    param([string]$SummaryText, [int]$ExitCode = 0)
    if ($ExitCode -ne 0) {
        return [PSCustomObject]@{ Passed = $false; Reason = "runner exit $ExitCode" }
    }
    $mTotal  = [regex]::Match($SummaryText, '(?m)^TESTS_TOTAL=(\d+)')
    $mPassed = [regex]::Match($SummaryText, '(?m)^TESTS_PASSED=(\d+)')
    $mFailed = [regex]::Match($SummaryText, '(?m)^TESTS_FAILED=(\d+)')
    if (-not $mTotal.Success -or -not $mPassed.Success -or -not $mFailed.Success) {
        return [PSCustomObject]@{ Passed = $false; Reason = 'missing summary fields' }
    }
    $gTotal  = [int]$mTotal.Groups[1].Value
    $gPassed = [int]$mPassed.Groups[1].Value
    $gFailed = [int]$mFailed.Groups[1].Value
    if ($gTotal -le 0) {
        return [PSCustomObject]@{ Passed = $false; Reason = "TESTS_TOTAL=$gTotal not positive" }
    }
    if ($gFailed -ne 0) {
        return [PSCustomObject]@{ Passed = $false; Reason = "TESTS_FAILED=$gFailed" }
    }
    if ($gPassed -ne $gTotal) {
        return [PSCustomObject]@{ Passed = $false; Reason = "TESTS_PASSED=$gPassed != TESTS_TOTAL=$gTotal" }
    }
    return [PSCustomObject]@{ Passed = $true; Reason = 'OK' }
}

Describe 'L. Automation gate fail-closed behavior' {

    BeforeAll {
        $script:lDir = New-TempDir
        # Placeholder file content — content irrelevant, existence is what matters
        $script:lDummy = '# placeholder'
        $script:lEnc   = [System.Text.UTF8Encoding]::new($false)
    }

    AfterAll {
        if ($script:lDir -and (Test-Path $script:lDir)) {
            Remove-Item $script:lDir -Recurse -Force
        }
    }

    It 'L1: missing module is rejected' {
        $modPath    = Join-Path $script:lDir 'l1_module.psm1'     # intentionally absent
        $testsPath  = Join-Path $script:lDir 'l1_tests.ps1'
        $runnerPath = Join-Path $script:lDir 'l1_runner.ps1'
        [System.IO.File]::WriteAllText($testsPath,  $script:lDummy, $script:lEnc)
        [System.IO.File]::WriteAllText($runnerPath, $script:lDummy, $script:lEnc)
        $artifacts = [ordered]@{ module = $modPath; tests = $testsPath; runner = $runnerPath }
        $missing = Invoke-ArtifactPresenceCheck -Artifacts $artifacts
        $missing.Count | Should BeGreaterThan 0
        $missing -contains 'module' | Should Be $true
    }

    It 'L2: missing tests file is rejected' {
        $modPath    = Join-Path $script:lDir 'l2_module.psm1'
        $testsPath  = Join-Path $script:lDir 'l2_tests.ps1'       # intentionally absent
        $runnerPath = Join-Path $script:lDir 'l2_runner.ps1'
        [System.IO.File]::WriteAllText($modPath,    $script:lDummy, $script:lEnc)
        [System.IO.File]::WriteAllText($runnerPath, $script:lDummy, $script:lEnc)
        $artifacts = [ordered]@{ module = $modPath; tests = $testsPath; runner = $runnerPath }
        $missing = Invoke-ArtifactPresenceCheck -Artifacts $artifacts
        $missing.Count | Should BeGreaterThan 0
        $missing -contains 'tests' | Should Be $true
    }

    It 'L3: missing runner is rejected' {
        $modPath    = Join-Path $script:lDir 'l3_module.psm1'
        $testsPath  = Join-Path $script:lDir 'l3_tests.ps1'
        $runnerPath = Join-Path $script:lDir 'l3_runner.ps1'       # intentionally absent
        [System.IO.File]::WriteAllText($modPath,   $script:lDummy, $script:lEnc)
        [System.IO.File]::WriteAllText($testsPath, $script:lDummy, $script:lEnc)
        $artifacts = [ordered]@{ module = $modPath; tests = $testsPath; runner = $runnerPath }
        $missing = Invoke-ArtifactPresenceCheck -Artifacts $artifacts
        $missing.Count | Should BeGreaterThan 0
        $missing -contains 'runner' | Should Be $true
    }

    It 'L4: malformed summary (no fields) is rejected' {
        $result = Invoke-SummaryValidation -SummaryText 'GARBAGE OUTPUT NO KEY=VALUE LINES' -ExitCode 0
        $result.Passed | Should Be $false
    }

    It 'L5: TESTS_FAILED > 0 is rejected' {
        $summary = "TESTS_TOTAL=5`r`nTESTS_PASSED=4`r`nTESTS_FAILED=1`r`n"
        $result  = Invoke-SummaryValidation -SummaryText $summary -ExitCode 0
        $result.Passed | Should Be $false
        $result.Reason | Should Match 'TESTS_FAILED'
    }

    It 'L6: TESTS_PASSED != TESTS_TOTAL is rejected' {
        $summary = "TESTS_TOTAL=5`r`nTESTS_PASSED=3`r`nTESTS_FAILED=0`r`n"
        $result  = Invoke-SummaryValidation -SummaryText $summary -ExitCode 0
        $result.Passed | Should Be $false
        $result.Reason | Should Match 'TESTS_PASSED'
    }

    It 'L7: valid 39/39 summary passes' {
        $summary = "TESTS_TOTAL=39`r`nTESTS_PASSED=39`r`nTESTS_FAILED=0`r`n"
        $result  = Invoke-SummaryValidation -SummaryText $summary -ExitCode 0
        $result.Passed | Should Be $true
    }
}

#endregion

#region ── K. Regression – three incidents ───────────────────────────────────

Describe 'K. Regression tests for the three incidents' {

    BeforeAll {
        $script:kModuleSource = [System.IO.File]::ReadAllText($ModulePath, [System.Text.Encoding]::UTF8)
    }

    It 'K1: module source does not use inline if-expression as format operator argument' {
        $script:kModuleSource | Should Not Match '-f\s*\(\s*if\b'
        $script:kModuleSource | Should Not Match '-f\s*\$\(\s*if\b'
    }

    It 'K2: module source does not wrap Invoke-* calls in @() then access .Property' {
        $script:kModuleSource | Should Not Match '@\s*\(\s*Invoke-[^)]+\)\.'
    }

    It 'K3: Get-UseCaseRegistryModel does not access .Name without property guard (behavioral)' {
        # If incident 3 were present, accessing .Name on a usecase without "name" field
        # would throw under StrictMode. Verify no throw.
        $tmpDir = New-TempDir
        $json = '{"version":"v1","usecases":[{"bundle_definitions":[]}]}'
        $path = Join-Path $tmpDir 'noname.json'
        Write-Utf8NoBom -Path $path -Content $json
        Invoke-ExpectingNoThrow { Get-UseCaseRegistryModel -RegistryPath $path } | Should Be $true
        Remove-Item $tmpDir -Recurse -Force
    }

    It 'K4: module and test files both pass AST parser syntax validation' {
        $testFilePath = $PSCommandPath
        $modResult  = Test-PowerShellFileSyntax -Path $ModulePath
        $testResult = Test-PowerShellFileSyntax -Path $testFilePath
        $modResult.IsValid  | Should Be $true
        $testResult.IsValid | Should Be $true
    }
}

#endregion
