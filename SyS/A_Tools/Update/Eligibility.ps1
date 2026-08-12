#Requires -Version 5.1
# SkillsMachine Project Sync eligibility (MB-SM-076A2)
# Eligible when: created by SkillsMachine OR explicitly enrolled.

function Test-SkillsMachineProjectEligibility {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Baseline
    )

    $schemaVersion = [string]$Baseline.schema_version
    $createdBy = $false
    if ($null -ne $Baseline.created_by_skillsmachine) {
        $createdBy = [bool]$Baseline.created_by_skillsmachine
    }

    if ($schemaVersion -eq '1.1') {
        if ($createdBy) {
            return [ordered]@{
                Eligible = $true
                Mode = 'CREATED_BY_SKILLSMACHINE'
                Reason = 'CREATED_BY_SKILLSMACHINE'
                SchemaVersion = $schemaVersion
            }
        }
        return [ordered]@{
            Eligible = $false
            Mode = 'CREATED_BY_REQUIRED'
            Reason = 'BLOCKED_UNKNOWN_PROJECT'
            SchemaVersion = $schemaVersion
        }
    }

    if ($schemaVersion -eq '1.2') {
        if ($createdBy) {
            return [ordered]@{
                Eligible = $true
                Mode = 'CREATED_BY_SKILLSMACHINE'
                Reason = 'CREATED_BY_SKILLSMACHINE'
                SchemaVersion = $schemaVersion
            }
        }

        $explicit = $false
        if ($null -ne $Baseline.explicitly_enrolled_in_skillsmachine) {
            $explicit = [bool]$Baseline.explicitly_enrolled_in_skillsmachine
        }
        $enrolmentStatus = [string]$Baseline.enrolment_status

        if ($explicit -and $enrolmentStatus -eq 'ENROLLED') {
            return [ordered]@{
                Eligible = $true
                Mode = 'EXPLICITLY_ENROLLED'
                Reason = 'EXPLICITLY_ENROLLED_IN_SKILLSMACHINE'
                SchemaVersion = $schemaVersion
            }
        }

        return [ordered]@{
            Eligible = $false
            Mode = 'ENROLMENT_REQUIRED'
            Reason = 'BLOCKED_PROJECT_NOT_ENROLLED'
            SchemaVersion = $schemaVersion
        }
    }

    return [ordered]@{
        Eligible = $false
        Mode = 'UNSUPPORTED'
        Reason = 'UNSUPPORTED_BASELINE_SCHEMA_VERSION'
        SchemaVersion = $schemaVersion
    }
}

function Assert-SkillsMachineProjectEligibility {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Baseline
    )

    $result = Test-SkillsMachineProjectEligibility -Baseline $Baseline
    if (-not [bool]$result.Eligible) {
        $reason = [string]$result.Reason
        Write-Host ("ELIGIBILITY_BLOCKED={0}" -f $reason)
        throw $reason
    }
    return $result
}

function New-SkillsMachineBaselineAfterApply {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Baseline,
        [Parameter(Mandatory = $true)][object]$Manifest,
        [Parameter(Mandatory = $true)][object[]]$Inventory
    )

    $schemaVersion = [string]$Baseline.schema_version
    if ([string]::IsNullOrWhiteSpace($schemaVersion)) {
        $schemaVersion = '1.1'
    }

    $out = [ordered]@{
        schema_version = $schemaVersion
        project_id = [string]$Baseline.project_id
        created_by_skillsmachine = [bool]$Baseline.created_by_skillsmachine
        skillsmachine_version = [string]$Manifest.update_version
        skillsmachine_commit = [string]$Manifest.source_commit
        last_update_id = [string]$Manifest.update_id
        baseline_generated_at = (Get-Date).ToUniversalTime().ToString('o')
        component_inventory = @($Inventory)
    }

    if ($schemaVersion -eq '1.2') {
        $explicit = $false
        if ($null -ne $Baseline.explicitly_enrolled_in_skillsmachine) {
            $explicit = [bool]$Baseline.explicitly_enrolled_in_skillsmachine
        }
        $out['explicitly_enrolled_in_skillsmachine'] = $explicit
        $out['enrolment_status'] = [string]$Baseline.enrolment_status
        if ($null -ne $Baseline.enrolment_id) {
            $out['enrolment_id'] = [string]$Baseline.enrolment_id
        }
        if ($null -ne $Baseline.enrolled_at) {
            $out['enrolled_at'] = [string]$Baseline.enrolled_at
        }
        if ($null -ne $Baseline.enrolment_method) {
            $out['enrolment_method'] = [string]$Baseline.enrolment_method
        }
    }

    return $out
}
