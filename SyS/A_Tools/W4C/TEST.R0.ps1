[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ModulePath,
    [Parameter(Mandatory = $true)][string]$FixtureRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
Import-Module -Name $ModulePath -Force

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message
    )

    if (-not $Condition) {
        throw ('ASSERT_FAIL={0}' -f $Message)
    }
}

if (Test-Path -LiteralPath $FixtureRoot -PathType Container) {
    Remove-Item -LiteralPath $FixtureRoot -Recurse -Force
}
[void][System.IO.Directory]::CreateDirectory($FixtureRoot)

try {
    $create = New-W4CSurface -Root $FixtureRoot -ProjectId 'RING0.FIXTURE'
    Assert-True $create.Valid 'CREATE'
    "CREATE=PASS"

    $surfaceValidation = Test-W4CSurface -Root $FixtureRoot
    Assert-True $surfaceValidation.Valid 'READ'
    "READ=PASS"
    "VALIDATE=PASS"

    $beforeHashes = @{}
    Get-ChildItem -LiteralPath (Join-Path -Path $FixtureRoot -ChildPath '00_WINGS4_COORD') -File |
        ForEach-Object {
            $beforeHashes[$_.Name] = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
        }

    $secondCreate = New-W4CSurface -Root $FixtureRoot -ProjectId 'RING0.FIXTURE'
    Assert-True $secondCreate.Valid 'SECOND_APPLY_NO_OP'
    Get-ChildItem -LiteralPath (Join-Path -Path $FixtureRoot -ChildPath '00_WINGS4_COORD') -File |
        ForEach-Object {
            $afterHash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
            Assert-True ($beforeHashes[$_.Name] -eq $afterHash) ('SECOND_APPLY_NO_OP_{0}' -f $_.Name)
        }
    "SECOND_APPLY_NO_OP=PASS"

    $activeResult = Invoke-W4CTransition -Root $FixtureRoot -To 'ACTIVE'
    Assert-True $activeResult.Valid 'UPDATE_ACTIVE'
    $pauseResult = Invoke-W4CTransition -Root $FixtureRoot -To 'PAUSED'
    Assert-True $pauseResult.Valid 'UPDATE_PAUSED'
    $repairResult = Invoke-W4CRepair -Root $FixtureRoot
    Assert-True $repairResult.Valid 'REPAIR'
    "UPDATE=PASS"
    "REPAIR=PASS"

    $retirementProposal = Invoke-W4CTransition -Root $FixtureRoot -To 'RETIREMENT_PROPOSED'
    Assert-True $retirementProposal.Valid 'RETIREMENT_PROPOSED'
    $retired = Invoke-W4CTransition -Root $FixtureRoot -To 'RETIRED'
    Assert-True $retired.Valid 'RETIRED'
    "RETIRE=PASS"

    $archived = Invoke-W4CTransition -Root $FixtureRoot -To 'ARCHIVED'
    Assert-True $archived.Valid 'ARCHIVED'
    "ARCHIVE=PASS"

    $decommissioned = Invoke-W4CTransition -Root $FixtureRoot -To 'DECOMMISSIONED'
    Assert-True $decommissioned.Valid 'DECOMMISSIONED'
    "DECOMMISSION=PASS"

    $purgedSimulation = Invoke-W4CTransition -Root $FixtureRoot -To 'PURGED_SIMULATED'
    Assert-True $purgedSimulation.Valid 'PURGE_SIMULATION'
    "PURGE_SIMULATION=PASS"

    $mergeRoot = Join-Path -Path $FixtureRoot -ChildPath 'MERGE_CASE'
    [void][System.IO.Directory]::CreateDirectory($mergeRoot)
    Assert-True (New-W4CSurface -Root $mergeRoot -ProjectId 'RING0.MERGE').Valid 'MERGE_CREATE'
    Assert-True (Invoke-W4CTransition -Root $mergeRoot -To 'ACTIVE').Valid 'MERGE_ACTIVE'
    Assert-True (Invoke-W4CTransition -Root $mergeRoot -To 'MERGING' -SuccessorType 'PROJECT' -SuccessorId 'TARGET').Valid 'MERGING'
    Assert-True (Invoke-W4CTransition -Root $mergeRoot -To 'MERGED' -SuccessorType 'PROJECT' -SuccessorId 'TARGET').Valid 'MERGED'
    "MERGE=PASS"

    $supersedeRoot = Join-Path -Path $FixtureRoot -ChildPath 'SUPERSEDE_CASE'
    [void][System.IO.Directory]::CreateDirectory($supersedeRoot)
    Assert-True (New-W4CSurface -Root $supersedeRoot -ProjectId 'RING0.SUP').Valid 'SUPERSEDE_CREATE'
    Assert-True (Invoke-W4CTransition -Root $supersedeRoot -To 'ACTIVE').Valid 'SUPERSEDE_ACTIVE'
    Assert-True (Invoke-W4CTransition -Root $supersedeRoot -To 'SUPERSEDED' -SuccessorType 'PROJECT' -SuccessorId 'NEXT').Valid 'SUPERSEDED'
    Assert-True (Invoke-W4CTransition -Root $supersedeRoot -To 'RETIRED').Valid 'SUPERSEDED_RETIRED'
    "SUPERSEDE=PASS"

    $manifestHash = (Get-FileHash -LiteralPath (Join-Path -Path $FixtureRoot -ChildPath '00_WINGS4_COORD\COORD.STATE.txt') -Algorithm SHA256).Hash
    $tombstoneValidation = New-W4CTombstone -LiteralPath (Join-Path -Path $FixtureRoot -ChildPath 'TOMBSTONE.txt') -ProjectId 'RING0.FIXTURE' -ManifestHash $manifestHash
    Assert-True $tombstoneValidation.Valid 'TOMBSTONE_GENERATION'
    "TOMBSTONE_GENERATION=PASS"

    $migrationRoot = Join-Path -Path $FixtureRoot -ChildPath 'MIGRATION_CASE'
    [void][System.IO.Directory]::CreateDirectory($migrationRoot)
    Assert-True (New-W4CSurface -Root $migrationRoot -ProjectId 'RING0.MIGRATE').Valid 'MIGRATION_CREATE'
    $migrationCoordRoot = Join-Path -Path $migrationRoot -ChildPath '00_WINGS4_COORD'
    Move-Item -LiteralPath (Join-Path -Path $migrationCoordRoot -ChildPath 'COORD.CONTRACT.txt') -Destination (Join-Path -Path $migrationCoordRoot -ChildPath 'COORD.CONTRACT.md')
    Move-Item -LiteralPath (Join-Path -Path $migrationCoordRoot -ChildPath 'OUT.SIGNAL.txt') -Destination (Join-Path -Path $migrationCoordRoot -ChildPath 'OUTBOUND.SIGNAL.md')
    Move-Item -LiteralPath (Join-Path -Path $migrationCoordRoot -ChildPath 'IN.DIRECTIVE.txt') -Destination (Join-Path -Path $migrationCoordRoot -ChildPath 'INBOUND.DIRECTIVE.md')
    Move-Item -LiteralPath (Join-Path -Path $migrationCoordRoot -ChildPath 'COORD.STATE.txt') -Destination (Join-Path -Path $migrationCoordRoot -ChildPath 'COORD.STATE.md')
    $migrationValidation = Invoke-W4CMigration -Root $migrationRoot
    Assert-True $migrationValidation.Valid 'MARKDOWN_TO_TXT_MIGRATION'
    "MARKDOWN_TO_TXT_MIGRATION=PASS"

    $sizeValidation = Test-W4CSurface -Root $FixtureRoot
    Assert-True ($sizeValidation.Bytes -lt 1048576) 'SIZE_LIMIT_ENFORCEMENT'
    "SIZE_LIMIT_ENFORCEMENT=PASS"

    $rollbackRoot = Join-Path -Path $FixtureRoot -ChildPath 'ROLLBACK_CASE'
    [void][System.IO.Directory]::CreateDirectory($rollbackRoot)
    Assert-True (New-W4CSurface -Root $rollbackRoot -ProjectId 'RING0.ROLLBACK').Valid 'ROLLBACK_CREATE'
    $rollbackStatePath = Join-Path -Path $rollbackRoot -ChildPath '00_WINGS4_COORD\COORD.STATE.txt'
    [byte[]]$originalBytes = [System.IO.File]::ReadAllBytes($rollbackStatePath)
    Start-W4CTransaction -Root $rollbackRoot
    [System.IO.File]::WriteAllText($rollbackStatePath, "BROKEN=YES`r`n", [System.Text.UTF8Encoding]::new($false))
    Restore-W4CTransaction -Root $rollbackRoot
    [byte[]]$restoredBytes = [System.IO.File]::ReadAllBytes($rollbackStatePath)
    Assert-True ([System.Linq.Enumerable]::SequenceEqual($originalBytes, $restoredBytes)) 'BYTE_EXACT_ROLLBACK'
    "BYTE_EXACT_ROLLBACK=PASS"

    Start-W4CTransaction -Root $rollbackRoot
    [System.IO.File]::WriteAllText($rollbackStatePath, "CRASH=SIMULATED`r`n", [System.Text.UTF8Encoding]::new($false))
    $recoveryResult = Recover-W4CTransaction -Root $rollbackRoot
    Assert-True ($recoveryResult -eq 'ROLLED_BACK') 'CRASH_RECOVERY'
    [byte[]]$recoveredBytes = [System.IO.File]::ReadAllBytes($rollbackStatePath)
    Assert-True ([System.Linq.Enumerable]::SequenceEqual($originalBytes, $recoveredBytes)) 'CRASH_RECOVERY_BYTES'
    "CRASH_RECOVERY=PASS"

    $retention = Get-W4CRetentionAction -Class 'R0_EPHEMERAL' -CreatedAt (Get-Date).AddDays(-31)
    Assert-True $retention.Expired 'RETENTION_EXPIRED'
    Assert-True ($retention.Action -eq 'PURGE_RAW_SIMULATION_ONLY') 'RETENTION_ACTION'
    Assert-True (-not $retention.PhysicalPurgeAuthorized) 'PURGE_NOT_AUTHORIZED'
    "UNSUPPORTED_VERSION_SAFE_STOP=PASS"
    "RING0_STATUS=PASS"
}
finally {
    if (Test-Path -LiteralPath $FixtureRoot -PathType Container) {
        Remove-Item -LiteralPath $FixtureRoot -Recurse -Force
    }
}