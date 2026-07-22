Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$script:SurfaceFiles = @(
    "COORD.CONTRACT.txt",
    "OUT.SIGNAL.txt",
    "IN.DIRECTIVE.txt",
    "COORD.STATE.txt"
)

$script:RequiredFields = @{
    "COORD_CONTRACT" = @(
        "SCHEMA_VERSION","DOCUMENT_TYPE","PROJECT_ID","RETURN_TARGET",
        "FORMAT_STATUS","LIFECYCLE_POLICY","RETENTION_POLICY"
    )
    "OUT_SIGNAL" = @(
        "SCHEMA_VERSION","DOCUMENT_TYPE","PROJECT_ID","SIGNAL_ID",
        "STATUS","RETURN_TARGET","CREATED_AT"
    )
    "IN_DIRECTIVE" = @(
        "SCHEMA_VERSION","DOCUMENT_TYPE","PROJECT_ID","DIRECTIVE_ID",
        "STATUS","RETURN_TARGET","CREATED_AT"
    )
    "COORD_STATE" = @(
        "SCHEMA_VERSION","DOCUMENT_TYPE","PROJECT_ID","LIFECYCLE_STATUS",
        "COORDINATION_ENABLED","ACTIVE_SIGNAL_ID","ACTIVE_DIRECTIVE_ID",
        "RETURN_TARGET","LAST_VALIDATED_AT"
    )
    "TOMBSTONE" = @(
        "SCHEMA_VERSION","DOCUMENT_TYPE","TOMBSTONE_ID","PROJECT_ID",
        "FINAL_STATUS","PURGED_AT","PURGE_REASON","SUCCESSOR_TYPE",
        "SUCCESSOR_ID","DECISION_RECORD_ID","FINAL_MANIFEST_HASH",
        "AUTHORIZED_BY","RETURN_TARGET"
    )
}

$script:AllowedFields = @{
    "COORD_CONTRACT" = @(
        "SCHEMA_VERSION","DOCUMENT_TYPE","PROJECT_ID","RETURN_TARGET",
        "FORMAT_STATUS","LIFECYCLE_POLICY","RETENTION_POLICY"
    )
    "OUT_SIGNAL" = @(
        "SCHEMA_VERSION","DOCUMENT_TYPE","PROJECT_ID","SIGNAL_ID",
        "STATUS","RETURN_TARGET","CREATED_AT"
    )
    "IN_DIRECTIVE" = @(
        "SCHEMA_VERSION","DOCUMENT_TYPE","PROJECT_ID","DIRECTIVE_ID",
        "STATUS","RETURN_TARGET","CREATED_AT"
    )
    "COORD_STATE" = @(
        "SCHEMA_VERSION","DOCUMENT_TYPE","PROJECT_ID","LIFECYCLE_STATUS",
        "COORDINATION_ENABLED","ACTIVE_SIGNAL_ID","ACTIVE_DIRECTIVE_ID",
        "RETURN_TARGET","LAST_VALIDATED_AT","SUCCESSOR_TYPE","SUCCESSOR_ID"
    )
    "TOMBSTONE" = @(
        "SCHEMA_VERSION","DOCUMENT_TYPE","TOMBSTONE_ID","PROJECT_ID",
        "FINAL_STATUS","PURGED_AT","PURGE_REASON","SUCCESSOR_TYPE",
        "SUCCESSOR_ID","DECISION_RECORD_ID","FINAL_MANIFEST_HASH",
        "AUTHORIZED_BY","RETURN_TARGET"
    )
}

$script:Transitions = @{
    "PROPOSED" = @("ACTIVE")
    "ACTIVE" = @("PAUSED","MERGING","SUPERSEDED","RETIREMENT_PROPOSED")
    "PAUSED" = @("ACTIVE","RETIREMENT_PROPOSED")
    "MERGING" = @("MERGED")
    "SUPERSEDED" = @("RETIRED")
    "RETIREMENT_PROPOSED" = @("RETIRED")
    "RETIRED" = @("ARCHIVED")
    "ARCHIVED" = @("DECOMMISSIONED")
    "DECOMMISSIONED" = @("PURGED_SIMULATED")
    "MERGED" = @()
    "PURGED_SIMULATED" = @()
}

$script:Retention = @{
    "R0_EPHEMERAL" = @{ Days = 30; Action = "PURGE_RAW_SIMULATION_ONLY" }
    "R2_OPERATIONAL" = @{ Days = -1; Action = "RETAIN_UNTIL_SUPERSEDED" }
    "R3_DECISION" = @{ Days = -1; Action = "RETAIN_INDEFINITE" }
    "R4_TOMBSTONE" = @{ Days = -1; Action = "RETAIN_INDEFINITE" }
}

function Read-W4CFile {
    param(
        [Parameter(Mandatory = $true)][string]$LiteralPath
    )

    $data = [ordered]@{}
    $contentLines = [System.Collections.Generic.List[string]]::new()
    $insideContent = $false

    Get-Content -LiteralPath $LiteralPath -Encoding UTF8 |
        ForEach-Object {
            $line = [string]$_
            if ($line -eq 'CONTENT_START') {
                if ($insideContent) {
                    throw 'W4C_CONTENT_START_DUPLICATED'
                }
                $insideContent = $true
                return
            }

            if ($line -eq 'CONTENT_END') {
                if (-not $insideContent) {
                    throw 'W4C_CONTENT_END_WITHOUT_START'
                }
                $insideContent = $false
                return
            }

            if ($insideContent) {
                [void]$contentLines.Add($line)
                return
            }

            if ([string]::IsNullOrWhiteSpace($line)) {
                return
            }

            if ($line -notmatch '^(?<key>[A-Z0-9_]+)=(?<value>.*)$') {
                throw ('W4C_INVALID_LINE={0}' -f $line)
            }

            $key = [string]$Matches['key']
            $value = [string]$Matches['value']

            if ($data.Contains($key)) {
                throw ('W4C_DUPLICATE_KEY={0}' -f $key)
            }

            $data[$key] = $value
        }

    if ($insideContent) {
        throw 'W4C_UNCLOSED_CONTENT_BLOCK'
    }

    return [pscustomobject]@{
        Data    = $data
        Content = @($contentLines)
    }
}

function Write-W4CFile {
    param(
        [Parameter(Mandatory = $true)][string]$LiteralPath,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Data,
        [string[]]$Content = @()
    )

    $lines = [System.Collections.Generic.List[string]]::new()
    $Data.Keys |
        ForEach-Object {
            [void]$lines.Add(('{0}={1}' -f $_, $Data[$_]))
        }

    if (@($Content).Count -gt 0) {
        [void]$lines.Add('')
        [void]$lines.Add('CONTENT_START')
        $Content | ForEach-Object { [void]$lines.Add([string]$_) }
        [void]$lines.Add('CONTENT_END')
    }

    $directoryPath = Split-Path -Parent $LiteralPath
    if (-not [System.IO.Directory]::Exists($directoryPath)) {
        [void][System.IO.Directory]::CreateDirectory($directoryPath)
    }

    [System.IO.File]::WriteAllText(
        $LiteralPath,
        (($lines -join "`r`n") + "`r`n"),
        [System.Text.UTF8Encoding]::new($false)
    )
}

function Test-W4CFile {
    param(
        [Parameter(Mandatory = $true)][string]$LiteralPath
    )

    $errors = [System.Collections.Generic.List[string]]::new()
    $parsed = $null

    try {
        $parsed = Read-W4CFile -LiteralPath $LiteralPath
    }
    catch {
        [void]$errors.Add($_.Exception.Message)
        return [pscustomobject]@{
            Valid  = $false
            Errors = @($errors)
            Parsed = $null
        }
    }

    $data = $parsed.Data
    $documentType = [string]$data['DOCUMENT_TYPE']

    if (-not $script:RequiredFields.ContainsKey($documentType)) {
        [void]$errors.Add('W4C_UNSUPPORTED_DOCUMENT_TYPE={0}' -f $documentType)
    }
    else {
        $script:RequiredFields[$documentType] |
            ForEach-Object {
                if (-not $data.Contains($_) -or [string]::IsNullOrWhiteSpace([string]$data[$_])) {
                    [void]$errors.Add('W4C_MISSING_FIELD={0}' -f $_)
                }
            }

        $data.Keys |
            ForEach-Object {
                if ($_ -notin $script:AllowedFields[$documentType]) {
                    [void]$errors.Add('W4C_UNKNOWN_FIELD={0}' -f $_)
                }
            }
    }

    if ($data.Contains('RETURN_TARGET') -and [string]$data['RETURN_TARGET'] -ne 'Wings4.0') {
        [void]$errors.Add('W4C_INVALID_RETURN_TARGET')
    }

    return [pscustomobject]@{
        Valid  = ($errors.Count -eq 0)
        Errors = @($errors)
        Parsed = $parsed
    }
}

function Test-W4CSurface {
    param(
        [Parameter(Mandatory = $true)][string]$Root
    )

    $coordRoot = Join-Path -Path $Root -ChildPath '00_WINGS4_COORD'
    $errors = [System.Collections.Generic.List[string]]::new()

    $script:SurfaceFiles |
        ForEach-Object {
            $filePath = Join-Path -Path $coordRoot -ChildPath $_
            if (-not (Test-Path -LiteralPath $filePath -PathType Leaf)) {
                [void]$errors.Add('W4C_MISSING_SURFACE_FILE={0}' -f $_)
                return
            }

            $validation = Test-W4CFile -LiteralPath $filePath
            $validation.Errors |
                ForEach-Object {
                    [void]$errors.Add(('{0}::{1}' -f $_, $_))
                }
        }

    if (Test-Path -LiteralPath $coordRoot -PathType Container) {
        Get-ChildItem -LiteralPath $coordRoot -File |
            ForEach-Object {
                if ($_.Name -notin $script:SurfaceFiles) {
                    [void]$errors.Add('W4C_UNEXPECTED_FILE={0}' -f $_.Name)
                }
            }
    }

    $totalBytes = 0L
    if (Test-Path -LiteralPath $coordRoot -PathType Container) {
        $totalBytes = [int64](
            (Get-ChildItem -LiteralPath $coordRoot -File | Measure-Object -Property Length -Sum).Sum
        )
    }

    if ($totalBytes -gt 1048576) {
        [void]$errors.Add('W4C_HARD_SIZE_LIMIT_EXCEEDED={0}' -f $totalBytes)
    }

    return [pscustomobject]@{
        Valid = ($errors.Count -eq 0)
        Errors = @($errors)
        Bytes = $totalBytes
    }
}

function New-W4CSurface {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$ProjectId
    )

    $coordRoot = Join-Path -Path $Root -ChildPath '00_WINGS4_COORD'
    if (-not [System.IO.Directory]::Exists($coordRoot)) {
        [void][System.IO.Directory]::CreateDirectory($coordRoot)
    }

    $now = Get-Date -Format 'yyyy-MM-ddTHH:mm:sszzz'
    $surface = [ordered]@{
        'COORD.CONTRACT.txt' = [ordered]@{
            SCHEMA_VERSION='1.0.0'
            DOCUMENT_TYPE='COORD_CONTRACT'
            PROJECT_ID=$ProjectId
            RETURN_TARGET='Wings4.0'
            FORMAT_STATUS='TXT_READY'
            LIFECYCLE_POLICY='W4C_RING0'
            RETENTION_POLICY='R0_EPHEMERAL'
        }
        'OUT.SIGNAL.txt' = [ordered]@{
            SCHEMA_VERSION='1.0.0'
            DOCUMENT_TYPE='OUT_SIGNAL'
            PROJECT_ID=$ProjectId
            SIGNAL_ID='NONE'
            STATUS='NONE'
            RETURN_TARGET='Wings4.0'
            CREATED_AT=$now
        }
        'IN.DIRECTIVE.txt' = [ordered]@{
            SCHEMA_VERSION='1.0.0'
            DOCUMENT_TYPE='IN_DIRECTIVE'
            PROJECT_ID=$ProjectId
            DIRECTIVE_ID='NONE'
            STATUS='NONE'
            RETURN_TARGET='Wings4.0'
            CREATED_AT=$now
        }
        'COORD.STATE.txt' = [ordered]@{
            SCHEMA_VERSION='1.0.0'
            DOCUMENT_TYPE='COORD_STATE'
            PROJECT_ID=$ProjectId
            LIFECYCLE_STATUS='PROPOSED'
            COORDINATION_ENABLED='NO'
            ACTIVE_SIGNAL_ID='NONE'
            ACTIVE_DIRECTIVE_ID='NONE'
            RETURN_TARGET='Wings4.0'
            LAST_VALIDATED_AT=$now
        }
    }

    $script:SurfaceFiles |
        ForEach-Object {
            $filePath = Join-Path -Path $coordRoot -ChildPath $_
            if (-not (Test-Path -LiteralPath $filePath -PathType Leaf)) {
                Write-W4CFile -LiteralPath $filePath -Data $surface[$_]
            }
        }

    return Test-W4CSurface -Root $Root
}

function Invoke-W4CTransition {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$To,
        [string]$SuccessorType = 'NONE',
        [string]$SuccessorId = 'NONE'
    )

    $statePath = Join-Path -Path $Root -ChildPath '00_WINGS4_COORD\COORD.STATE.txt'
    $validation = Test-W4CFile -LiteralPath $statePath
    if (-not $validation.Valid) {
        throw 'W4C_STATE_INVALID_BEFORE_TRANSITION'
    }

    $data = [ordered]@{}
    $validation.Parsed.Data.Keys |
        ForEach-Object {
            $data[$_] = $validation.Parsed.Data[$_]
        }

    $from = [string]$data['LIFECYCLE_STATUS']
    if (-not $script:Transitions.ContainsKey($from) -or $To -notin $script:Transitions[$from]) {
        throw ('W4C_INVALID_TRANSITION={0}>{1}' -f $from, $To)
    }

    if ($To -in @('MERGING', 'MERGED', 'SUPERSEDED') -and $SuccessorId -eq 'NONE') {
        throw 'W4C_SUCCESSOR_REQUIRED'
    }

    $data['LIFECYCLE_STATUS'] = $To
    $data['COORDINATION_ENABLED'] = if ($To -eq 'ACTIVE') { 'YES' } else { 'NO' }
    $data['LAST_VALIDATED_AT'] = Get-Date -Format 'yyyy-MM-ddTHH:mm:sszzz'
    if ($SuccessorType -ne 'NONE') {
        $data['SUCCESSOR_TYPE'] = $SuccessorType
    }
    if ($SuccessorId -ne 'NONE') {
        $data['SUCCESSOR_ID'] = $SuccessorId
    }

    Write-W4CFile -LiteralPath $statePath -Data $data -Content @($validation.Parsed.Content)
    return Test-W4CFile -LiteralPath $statePath
}

function Invoke-W4CRepair {
    param(
        [Parameter(Mandatory = $true)][string]$Root
    )

    $coordRoot = Join-Path -Path $Root -ChildPath '00_WINGS4_COORD'
    if (-not (Test-Path -LiteralPath $coordRoot -PathType Container)) {
        return New-W4CSurface -Root $Root -ProjectId 'RING0.REPAIRED'
    }

    $surface = Test-W4CSurface -Root $Root
    if ($surface.Valid) {
        return $surface
    }

    return New-W4CSurface -Root $Root -ProjectId 'RING0.REPAIRED'
}

function New-W4CTombstone {
    param(
        [Parameter(Mandatory = $true)][string]$LiteralPath,
        [Parameter(Mandatory = $true)][string]$ProjectId,
        [Parameter(Mandatory = $true)][string]$ManifestHash
    )

    $data = [ordered]@{
        SCHEMA_VERSION='1.0.0'
        DOCUMENT_TYPE='TOMBSTONE'
        TOMBSTONE_ID=('TS-{0}-{1}' -f $ProjectId, (Get-Date -Format 'yyyyMMddHHmmss'))
        PROJECT_ID=$ProjectId
        FINAL_STATUS='PURGED_SIMULATED'
        PURGED_AT=(Get-Date -Format 'yyyy-MM-ddTHH:mm:sszzz')
        PURGE_REASON='RING0_SIMULATION'
        SUCCESSOR_TYPE='NONE'
        SUCCESSOR_ID='NONE'
        DECISION_RECORD_ID='RING0_DECISION'
        FINAL_MANIFEST_HASH=$ManifestHash
        AUTHORIZED_BY='RING0_TEST'
        RETURN_TARGET='Wings4.0'
    }

    Write-W4CFile -LiteralPath $LiteralPath -Data $data
    $validation = Test-W4CFile -LiteralPath $LiteralPath
    if ((Get-Item -LiteralPath $LiteralPath).Length -gt 16384) {
        throw 'W4C_TOMBSTONE_TOO_LARGE'
    }
    return $validation
}

function Invoke-W4CMigration {
    param(
        [Parameter(Mandatory = $true)][string]$Root
    )

    $coordRoot = Join-Path -Path $Root -ChildPath '00_WINGS4_COORD'
    $migrationMap = [ordered]@{
        'COORD.CONTRACT.md'='COORD.CONTRACT.txt'
        'OUTBOUND.SIGNAL.md'='OUT.SIGNAL.txt'
        'INBOUND.DIRECTIVE.md'='IN.DIRECTIVE.txt'
        'COORD.STATE.md'='COORD.STATE.txt'
    }

    $migrationMap.Keys |
        ForEach-Object {
            $sourcePath = Join-Path -Path $coordRoot -ChildPath $_
            $targetPath = Join-Path -Path $coordRoot -ChildPath $migrationMap[$_]
            if (Test-Path -LiteralPath $sourcePath -PathType Leaf) {
                if (Test-Path -LiteralPath $targetPath -PathType Leaf) {
                    throw ('W4C_MIGRATION_CONFLICT={0}' -f $_)
                }
                $parsed = Read-W4CFile -LiteralPath $sourcePath
                Write-W4CFile -LiteralPath $targetPath -Data $parsed.Data -Content @($parsed.Content)
                [System.IO.File]::Delete($sourcePath)
            }
        }

    return Test-W4CSurface -Root $Root
}

function Get-W4CRetentionAction {
    param(
        [Parameter(Mandatory = $true)][string]$Class,
        [Parameter(Mandatory = $true)][datetime]$CreatedAt,
        [datetime]$AsOf = (Get-Date)
    )

    if (-not $script:Retention.ContainsKey($Class)) {
        throw ('W4C_UNKNOWN_RETENTION_CLASS={0}' -f $Class)
    }

    $policy = $script:Retention[$Class]
    $expired = $false
    if ([int]$policy.Days -ge 0) {
        $expired = ($AsOf -ge $CreatedAt.AddDays([int]$policy.Days))
    }

    return [pscustomobject]@{
        Class = $Class
        Days = [int]$policy.Days
        Action = [string]$policy.Action
        Expired = $expired
        PhysicalPurgeAuthorized = $false
    }
}

function Start-W4CTransaction {
    param(
        [Parameter(Mandatory = $true)][string]$Root
    )

    $coordRoot = Join-Path -Path $Root -ChildPath '00_WINGS4_COORD'
    $backupRoot = Join-Path -Path $Root -ChildPath '.W4C.BACKUP'
    $journalPath = Join-Path -Path $Root -ChildPath '.W4C.JOURNAL.txt'

    if (Test-Path -LiteralPath $backupRoot -PathType Container) {
        throw 'W4C_BACKUP_ALREADY_EXISTS'
    }
    if (Test-Path -LiteralPath $journalPath -PathType Leaf) {
        throw 'W4C_JOURNAL_ALREADY_EXISTS'
    }
    if (-not (Test-Path -LiteralPath $coordRoot -PathType Container)) {
        throw 'W4C_COORD_ROOT_MISSING_FOR_TRANSACTION'
    }

    Copy-Item -LiteralPath $coordRoot -Destination $backupRoot -Recurse
    [System.IO.File]::WriteAllText(
        $journalPath,
        "STATE=OPEN`r`n",
        [System.Text.UTF8Encoding]::new($false)
    )
}

function Complete-W4CTransaction {
    param(
        [Parameter(Mandatory = $true)][string]$Root
    )

    $backupRoot = Join-Path -Path $Root -ChildPath '.W4C.BACKUP'
    $journalPath = Join-Path -Path $Root -ChildPath '.W4C.JOURNAL.txt'

    if (Test-Path -LiteralPath $backupRoot -PathType Container) {
        Remove-Item -LiteralPath $backupRoot -Recurse -Force
    }
    if (Test-Path -LiteralPath $journalPath -PathType Leaf) {
        Remove-Item -LiteralPath $journalPath -Force
    }
}

function Restore-W4CTransaction {
    param(
        [Parameter(Mandatory = $true)][string]$Root
    )

    $coordRoot = Join-Path -Path $Root -ChildPath '00_WINGS4_COORD'
    $backupRoot = Join-Path -Path $Root -ChildPath '.W4C.BACKUP'
    $journalPath = Join-Path -Path $Root -ChildPath '.W4C.JOURNAL.txt'

    if (-not (Test-Path -LiteralPath $backupRoot -PathType Container)) {
        throw 'W4C_BACKUP_MISSING_FOR_RESTORE'
    }

    if (Test-Path -LiteralPath $coordRoot -PathType Container) {
        Remove-Item -LiteralPath $coordRoot -Recurse -Force
    }

    Move-Item -LiteralPath $backupRoot -Destination $coordRoot
    if (Test-Path -LiteralPath $journalPath -PathType Leaf) {
        Remove-Item -LiteralPath $journalPath -Force
    }
}

function Recover-W4CTransaction {
    param(
        [Parameter(Mandatory = $true)][string]$Root
    )

    $backupRoot = Join-Path -Path $Root -ChildPath '.W4C.BACKUP'
    $journalPath = Join-Path -Path $Root -ChildPath '.W4C.JOURNAL.txt'

    if (Test-Path -LiteralPath $journalPath -PathType Leaf) {
        if (Test-Path -LiteralPath $backupRoot -PathType Container) {
            Restore-W4CTransaction -Root $Root
            return 'ROLLED_BACK'
        }
        throw 'W4C_JOURNAL_WITHOUT_BACKUP'
    }

    return 'NO_RECOVERY_REQUIRED'
}

Export-ModuleMember -Function @(
    'Read-W4CFile',
    'Write-W4CFile',
    'Test-W4CFile',
    'Test-W4CSurface',
    'New-W4CSurface',
    'Invoke-W4CTransition',
    'Invoke-W4CRepair',
    'New-W4CTombstone',
    'Invoke-W4CMigration',
    'Get-W4CRetentionAction',
    'Start-W4CTransaction',
    'Complete-W4CTransaction',
    'Restore-W4CTransaction',
    'Recover-W4CTransaction'
)