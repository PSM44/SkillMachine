# Test-ProjectInformationArchitectureForward.ps1
# Functional expected-vs-actual evaluator for PIA fixtures. PS 5.1 compatible.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Write-Fail([string]$m) { Write-Host "FAIL: $m" }

function Convert-ToStringArray {
    param([AllowNull()]$Value)
    if ($null -eq $Value) { return @() }
    if ($Value -is [System.Array]) { return @($Value | ForEach-Object { [string]$_ }) }
    return @([string]$Value)
}

function Test-SetEqual {
    param([string[]]$Actual, [string[]]$Expected)
    $a = @($Actual | Where-Object { $_ } | Sort-Object -Unique)
    $e = @($Expected | Where-Object { $_ } | Sort-Object -Unique)
    if ($a.Count -ne $e.Count) { return $false }
    for ($i = 0; $i -lt $a.Count; $i++) {
        if ($a[$i] -ne $e[$i]) { return $false }
    }
    return $true
}

function Get-HardExceptions {
    return @(
        'authority_boundary'
        'security_boundary'
        'permissions_boundary'
        'operational_interface'
        'external_platform_requirement'
        'source_generated_separation'
        'independent_lifecycle'
        'independent_ownership'
        'exact_integration_contract'
        'mandatory_bootstrap_role'
    )
}

function Invoke-PiaEvaluate {
    param([object]$Fixture)

    $profiles = @(Convert-ToStringArray $Fixture.ACTIVE_PROFILES)
    $facts = $Fixture.INPUT_FACTS
    $maturity = [string]$Fixture.MATURITY
    $congestion = 12
    if ($null -ne $facts.PSObject.Properties['PARENT_CONGESTION_THRESHOLD']) {
        $congestion = [int]$facts.PARENT_CONGESTION_THRESHOLD
    }

    $has = {
        param([string]$p)
        return ($profiles -contains $p)
    }

    $sysIo = [bool](& $has 'SYSTEM_PRODUCT')
    $authority = 'HUMAN_AUTHORITY'
    $whoamiRequired = $false
    $accessIsSot = $false
    $constitutionReplacesHuman = $false

    $requiredRoles = [System.Collections.Generic.List[string]]::new()
    foreach ($r in @('HUMAN_AUTHORITY', 'BATON_HOME', 'RADAR_HOME')) { [void]$requiredRoles.Add($r) }

    $optionalRoles = [System.Collections.Generic.List[string]]::new()
    $forbidden = [System.Collections.Generic.List[string]]::new()
    $triggers = [System.Collections.Generic.List[string]]::new()

    [void]$triggers.Add('BOOTSTRAP_TRIAD')

    if ($sysIo) {
        [void]$requiredRoles.Add('SYS_INPUT')
        [void]$requiredRoles.Add('SYS_OUTPUT')
        [void]$triggers.Add('SYSTEM_PRODUCT_JOB')
    }
    else {
        [void]$forbidden.Add('SYS.INPUT')
        [void]$forbidden.Add('SYS.OUTPUT')
    }

    if (& $has 'SOFTWARE') { [void]$optionalRoles.Add('TESTS'); [void]$triggers.Add('SOFTWARE_TESTS_IF_JUSTIFIED') }
    if (& $has 'RESEARCH') { [void]$optionalRoles.Add('EVIDENCE'); [void]$triggers.Add('RESEARCH_EVIDENCE_IF_MATERIAL') }
    if (& $has 'LEARNING') { [void]$optionalRoles.Add('TESTS') }
    if (& $has 'KNOWLEDGE_MEMORY') { [void]$optionalRoles.Add('EVIDENCE') }
    if (& $has 'AUTOMATION') { [void]$optionalRoles.Add('TOOLS') }
    if (& $has 'INTEGRATION') { [void]$optionalRoles.Add('PRODUCT_MODULES'); [void]$triggers.Add('REAL_PRODUCT_BOUNDARY') }
    if (& $has 'CORPORATE') { [void]$optionalRoles.Add('GOVERNANCE') }
    if (& $has 'REGULATED') {
        [void]$requiredRoles.Add('EVIDENCE')
        [void]$requiredRoles.Add('QUALITY')
        [void]$optionalRoles.Add('GOVERNANCE')
        [void]$triggers.Add('REGULATED_HARD_BOUNDARY')
    }
    if (& $has 'MATERIAL_EVIDENCE') { [void]$requiredRoles.Add('EVIDENCE') }
    if (& $has 'PRODUCTION_OPERATIONS') { [void]$optionalRoles.Add('QUALITY') }

    if ($maturity -eq 'BIRTH' -or $maturity -eq 'MINIMUM') {
        [void]$forbidden.Add('EMPTY_LOGICAL_MAXIMUM')
        [void]$forbidden.Add('EMPTY_FUTURE_FOLDERS')
    }

    [void]$forbidden.Add('WHOAMI_ACTIVE_CANON')
    [void]$forbidden.Add('ACCESS_SOT_COPIES')
    [void]$forbidden.Add('FOLLOW_00_ACCESS_REPARSE')
    [void]$forbidden.Add('AUTO_COLLAPSE')

    $proposed = @()
    if ($null -ne $facts.PSObject.Properties['PROPOSED_DIRECTORIES']) {
        $proposed = @(Convert-ToStringArray $facts.PROPOSED_DIRECTORIES)
    }
    $artifactCounts = @{}
    if ($null -ne $facts.PSObject.Properties['ARTIFACT_COUNTS'] -and $null -ne $facts.ARTIFACT_COUNTS) {
        foreach ($p in $facts.ARTIFACT_COUNTS.PSObject.Properties) {
            $artifactCounts[$p.Name] = [int]$p.Value
        }
    }
    $hard = @{}
    if ($null -ne $facts.PSObject.Properties['HARD_EXCEPTIONS'] -and $null -ne $facts.HARD_EXCEPTIONS) {
        foreach ($p in $facts.HARD_EXCEPTIONS.PSObject.Properties) {
            $hard[$p.Name] = [string]$p.Value
        }
    }
    $parentCount = 0
    if ($null -ne $facts.PSObject.Properties['PARENT_FILE_COUNT']) {
        $parentCount = [int]$facts.PARENT_FILE_COUNT
    }

    $allowedDirs = [System.Collections.Generic.List[string]]::new()
    $deniedDirs = [System.Collections.Generic.List[string]]::new()
    $hardNames = Get-HardExceptions
    foreach ($dir in $proposed) {
        $count = 0
        if ($artifactCounts.ContainsKey($dir)) { $count = [int]$artifactCounts[$dir] }
        $exc = ''
        if ($hard.ContainsKey($dir)) { $exc = [string]$hard[$dir] }
        $hardOk = ($exc -ne '' -and ($hardNames -contains $exc))
        $threeOk = ($count -ge 3)
        $congOk = ($parentCount -ge $congestion)
        if ($hardOk -or $threeOk -or $congOk) {
            [void]$allowedDirs.Add($dir)
        }
        else {
            [void]$deniedDirs.Add($dir)
            [void]$forbidden.Add("MATERIALIZE:$dir")
        }
    }

    $minPhysical = @('HUMAN', 'BATON', 'RADAR_INDEX')
    if ($sysIo -and ($null -ne $facts.PSObject.Properties['JOB_ACTIVE']) -and [bool]$facts.JOB_ACTIVE) {
        $minPhysical += @('SYS.INPUT', 'SYS.OUTPUT')
    }

    $jobIdRequired = $false
    $lineageRequired = $false
    $intermediateDistinct = $false
    $rejectedDistinct = $false
    $deliverablesDistinct = $false
    if ($sysIo) {
        $jobIdRequired = $true
        $lineageRequired = $true
        $intermediateDistinct = $true
        $rejectedDistinct = $true
        $deliverablesDistinct = $true
    }

    $sessionUnder = '90_SESSIONS'
    $orchRoot = $false
    $skillsEqProduct = $false
    $followAccess = $false
    $hardlinkOnce = $true
    $radarSixFirstRun = $true
    $qualityEqTests = $false

    $security = [ordered]@{
        ACCESS = $true
        SECRETS = $true
        CLASSIFICATION = [bool]((& $has 'REGULATED') -or (& $has 'MATERIAL_EVIDENCE') -or $sysIo)
        PRIVACY = [bool]((& $has 'REGULATED') -or (& $has 'CORPORATE'))
        AI_UPLOAD = $true
        DO_NOT_UPLOAD = $true
        INCIDENTS = [bool](& $has 'REGULATED')
        FAIL_CLOSED_UPLOAD = $true
    }

    $evidenceRequired = [bool]((& $has 'REGULATED') -or (& $has 'MATERIAL_EVIDENCE') -or $sysIo)
    $testsRequired = $false
    if ((& $has 'SOFTWARE') -and $maturity -ne 'BIRTH' -and $maturity -ne 'MINIMUM') {
        $testsRequired = $false
    }

    $logicalKnown = @('ACCESS_LAYER', 'HUMAN_AUTHORITY', 'GOVERNANCE', 'PROJECT_IDENTITY', 'BACKLOGS', 'IDEAS', 'QUALITY', 'EVIDENCE', 'AI_COLLAB', 'PROJECT_SKILLS', 'SESSIONS', 'BATON_HOME', 'RADAR_HOME')

    return [pscustomobject]@{
        ACTIVE_PROFILES = @($profiles | Sort-Object)
        REQUIRED_ROLES = @($requiredRoles | Sort-Object -Unique)
        OPTIONAL_ROLES = @($optionalRoles | Sort-Object -Unique)
        FORBIDDEN_MATERIALIZATION = @($forbidden | Sort-Object -Unique)
        TRIGGERS = @($triggers | Sort-Object -Unique)
        AUTHORITY = $authority
        WHOAMI_REQUIRED = $whoamiRequired
        ACCESS_IS_SOT = $accessIsSot
        CONSTITUTION_REPLACES_HUMAN = $constitutionReplacesHuman
        SYS_INPUT_ACTIVE = $sysIo
        SYS_OUTPUT_ACTIVE = $sysIo
        JOB_ID_REQUIRED = $jobIdRequired
        LINEAGE_REQUIRED = $lineageRequired
        INTERMEDIATE_OUTPUTS_DISTINCT = $intermediateDistinct
        REJECTED_OUTPUTS_DISTINCT = $rejectedDistinct
        DELIVERABLES_DISTINCT_FROM_SYS_OUTPUT = $deliverablesDistinct
        MIN_PHYSICAL = @($minPhysical | Sort-Object -Unique)
        LOGICAL_KNOWN_ROLES = $logicalKnown
        ALLOWED_DIRECTORIES = @($allowedDirs | Sort-Object -Unique)
        DENIED_DIRECTORIES = @($deniedDirs | Sort-Object -Unique)
        SESSION_PARENT = $sessionUnder
        ORCHESTRATOR_IS_ROOT = $orchRoot
        SKILLS_EQUALS_PRODUCT_MODULE = $skillsEqProduct
        FOLLOW_00_ACCESS = $followAccess
        HARDLINK_COUNT_ONCE = $hardlinkOnce
        RADAR_SIX_OUTPUTS_FIRST_RUN = $radarSixFirstRun
        QUALITY_EQUALS_TESTS = $qualityEqTests
        SECURITY = $security
        EVIDENCE_REQUIRED = $evidenceRequired
        TESTS_REQUIRED = $testsRequired
        PARENT_CONGESTION_THRESHOLD = $congestion
        CONGESTION_TRIGGERED = [bool]($parentCount -ge $congestion)
        RETENTION_REQUIRED = [bool](& $has 'REGULATED')
        AUTO_COLLAPSE = $false
        EMPTY_MAX_TREE = $false
    }
}

function Compare-ActualExpected {
    param($Actual, $Expected, [string]$ScenarioId)
    $state = @{
        Fails = New-Object 'System.Collections.Generic.List[string]'
        Pass = 0
        Total = 0
    }
    $assertEq = {
        param([string]$Name, $A, $E)
        $state.Total++
        if ([string]$A -eq [string]$E) { $state.Pass++; return }
        [void]$state.Fails.Add("$ScenarioId.$Name actual=$A expected=$E")
    }
    $assertSet = {
        param([string]$Name, $A, $E)
        $state.Total++
        $aa = @(Convert-ToStringArray $A)
        $ee = @(Convert-ToStringArray $E)
        if (Test-SetEqual -Actual $aa -Expected $ee) { $state.Pass++; return }
        [void]$state.Fails.Add("$ScenarioId.$Name actual=[$($aa -join ',')] expected=[$($ee -join ',')]")
    }

    & $assertSet 'ACTIVE_PROFILES' $Actual.ACTIVE_PROFILES $Expected.ACTIVE_PROFILES
    & $assertSet 'REQUIRED_ROLES' $Actual.REQUIRED_ROLES $Expected.REQUIRED_ROLES
    & $assertSet 'OPTIONAL_ROLES' $Actual.OPTIONAL_ROLES $Expected.OPTIONAL_ROLES
    & $assertSet 'FORBIDDEN_MATERIALIZATION' $Actual.FORBIDDEN_MATERIALIZATION $Expected.FORBIDDEN_MATERIALIZATION
    & $assertSet 'TRIGGERS' $Actual.TRIGGERS $Expected.TRIGGERS
    & $assertEq 'AUTHORITY' $Actual.AUTHORITY $Expected.AUTHORITY
    & $assertEq 'WHOAMI_REQUIRED' $Actual.WHOAMI_REQUIRED $Expected.WHOAMI_REQUIRED
    & $assertEq 'ACCESS_IS_SOT' $Actual.ACCESS_IS_SOT $Expected.ACCESS_IS_SOT
    & $assertEq 'CONSTITUTION_REPLACES_HUMAN' $Actual.CONSTITUTION_REPLACES_HUMAN $Expected.CONSTITUTION_REPLACES_HUMAN
    & $assertEq 'SYS_INPUT_ACTIVE' $Actual.SYS_INPUT_ACTIVE $Expected.SYS_INPUT_ACTIVE
    & $assertEq 'SYS_OUTPUT_ACTIVE' $Actual.SYS_OUTPUT_ACTIVE $Expected.SYS_OUTPUT_ACTIVE
    & $assertEq 'JOB_ID_REQUIRED' $Actual.JOB_ID_REQUIRED $Expected.JOB_ID_REQUIRED
    & $assertEq 'LINEAGE_REQUIRED' $Actual.LINEAGE_REQUIRED $Expected.LINEAGE_REQUIRED
    & $assertEq 'SESSION_PARENT' $Actual.SESSION_PARENT $Expected.SESSION_PARENT
    & $assertEq 'ORCHESTRATOR_IS_ROOT' $Actual.ORCHESTRATOR_IS_ROOT $Expected.ORCHESTRATOR_IS_ROOT
    & $assertEq 'SKILLS_EQUALS_PRODUCT_MODULE' $Actual.SKILLS_EQUALS_PRODUCT_MODULE $Expected.SKILLS_EQUALS_PRODUCT_MODULE
    & $assertEq 'FOLLOW_00_ACCESS' $Actual.FOLLOW_00_ACCESS $Expected.FOLLOW_00_ACCESS
    & $assertEq 'HARDLINK_COUNT_ONCE' $Actual.HARDLINK_COUNT_ONCE $Expected.HARDLINK_COUNT_ONCE
    & $assertEq 'RADAR_SIX_OUTPUTS_FIRST_RUN' $Actual.RADAR_SIX_OUTPUTS_FIRST_RUN $Expected.RADAR_SIX_OUTPUTS_FIRST_RUN
    & $assertEq 'QUALITY_EQUALS_TESTS' $Actual.QUALITY_EQUALS_TESTS $Expected.QUALITY_EQUALS_TESTS
    & $assertEq 'EVIDENCE_REQUIRED' $Actual.EVIDENCE_REQUIRED $Expected.EVIDENCE_REQUIRED
    & $assertEq 'TESTS_REQUIRED' $Actual.TESTS_REQUIRED $Expected.TESTS_REQUIRED
    & $assertEq 'RETENTION_REQUIRED' $Actual.RETENTION_REQUIRED $Expected.RETENTION_REQUIRED
    & $assertEq 'AUTO_COLLAPSE' $Actual.AUTO_COLLAPSE $Expected.AUTO_COLLAPSE
    & $assertEq 'EMPTY_MAX_TREE' $Actual.EMPTY_MAX_TREE $Expected.EMPTY_MAX_TREE
    & $assertSet 'MIN_PHYSICAL' $Actual.MIN_PHYSICAL $Expected.MIN_PHYSICAL
    & $assertSet 'DENIED_DIRECTORIES' $Actual.DENIED_DIRECTORIES $Expected.DENIED_DIRECTORIES
    & $assertSet 'ALLOWED_DIRECTORIES' $Actual.ALLOWED_DIRECTORIES $Expected.ALLOWED_DIRECTORIES
    & $assertEq 'CONGESTION_TRIGGERED' $Actual.CONGESTION_TRIGGERED $Expected.CONGESTION_TRIGGERED
    & $assertEq 'SECURITY.DO_NOT_UPLOAD' $Actual.SECURITY.DO_NOT_UPLOAD $Expected.SECURITY.DO_NOT_UPLOAD
    & $assertEq 'SECURITY.FAIL_CLOSED_UPLOAD' $Actual.SECURITY.FAIL_CLOSED_UPLOAD $Expected.SECURITY.FAIL_CLOSED_UPLOAD
    & $assertEq 'SECURITY.CLASSIFICATION' $Actual.SECURITY.CLASSIFICATION $Expected.SECURITY.CLASSIFICATION
    & $assertEq 'SECURITY.PRIVACY' $Actual.SECURITY.PRIVACY $Expected.SECURITY.PRIVACY
    & $assertEq 'SECURITY.INCIDENTS' $Actual.SECURITY.INCIDENTS $Expected.SECURITY.INCIDENTS

    if ($null -ne $Expected.PSObject.Properties['INTERMEDIATE_OUTPUTS_DISTINCT']) {
        & $assertEq 'INTERMEDIATE_OUTPUTS_DISTINCT' $Actual.INTERMEDIATE_OUTPUTS_DISTINCT $Expected.INTERMEDIATE_OUTPUTS_DISTINCT
        & $assertEq 'REJECTED_OUTPUTS_DISTINCT' $Actual.REJECTED_OUTPUTS_DISTINCT $Expected.REJECTED_OUTPUTS_DISTINCT
        & $assertEq 'DELIVERABLES_DISTINCT_FROM_SYS_OUTPUT' $Actual.DELIVERABLES_DISTINCT_FROM_SYS_OUTPUT $Expected.DELIVERABLES_DISTINCT_FROM_SYS_OUTPUT
    }

    return [pscustomobject]@{
        Fails = $state.Fails
        Pass = $state.Pass
        Total = $state.Total
    }
}

Write-Host 'VALIDATION: PIA functional forward tests'
$RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$FixtureDir = Join-Path $PSScriptRoot 'Fixtures\ProjectInformationArchitecture'
if (-not (Test-Path -LiteralPath $FixtureDir -PathType Container)) {
    Write-Fail "missing fixture directory: $FixtureDir"
    exit 1
}

$files = @(Get-ChildItem -LiteralPath $FixtureDir -Filter '*.json' -File | Sort-Object Name)
if ($files.Count -lt 10) {
    Write-Fail "expected at least 10 fixtures, found $($files.Count)"
    exit 1
}

$scenariosPass = 0
$scenariosFail = 0
$assertPass = 0
$assertTotal = 0
$failedNames = [System.Collections.Generic.List[string]]::new()

foreach ($f in $files) {
    $raw = [System.IO.File]::ReadAllText($f.FullName)
    $fx = $raw | ConvertFrom-Json
    $id = [string]$fx.SCENARIO_ID
    $requiredKeys = @(
        'SCENARIO_ID'
        'PROJECT_NATURE'
        'MATURITY'
        'ACTIVE_PROFILES'
        'INPUT_FACTS'
        'EXPECTED_REQUIRED_ROLES'
        'EXPECTED_OPTIONAL_ROLES'
        'EXPECTED_FORBIDDEN_MATERIALIZATION'
        'EXPECTED_TRIGGERS'
        'EXPECTED_AUTHORITY'
        'EXPECTED_SECURITY'
        'EXPECTED_EVIDENCE'
        'EXPECTED_RESULT'
    )
    $schemaOk = $true
    foreach ($k in $requiredKeys) {
        if ($null -eq $fx.PSObject.Properties[$k]) {
            $schemaOk = $false
            Write-Host "FAIL: $id missing fixture key $k"
        }
    }
    if (-not $schemaOk) {
        $scenariosFail++
        [void]$failedNames.Add($id)
        continue
    }
    $actual = Invoke-PiaEvaluate -Fixture $fx
    $cmp = Compare-ActualExpected -Actual $actual -Expected $fx.EXPECTED_RESULT -ScenarioId $id
    if (-not (Test-SetEqual -Actual (Convert-ToStringArray $actual.REQUIRED_ROLES) -Expected (Convert-ToStringArray $fx.EXPECTED_REQUIRED_ROLES))) {
        [void]$cmp.Fails.Add("$id.TOP.EXPECTED_REQUIRED_ROLES mismatch")
        $cmp.Total++
    } else { $cmp.Pass++; $cmp.Total++ }
    if (-not (Test-SetEqual -Actual (Convert-ToStringArray $actual.OPTIONAL_ROLES) -Expected (Convert-ToStringArray $fx.EXPECTED_OPTIONAL_ROLES))) {
        [void]$cmp.Fails.Add("$id.TOP.EXPECTED_OPTIONAL_ROLES mismatch")
        $cmp.Total++
    } else { $cmp.Pass++; $cmp.Total++ }
    if (-not (Test-SetEqual -Actual (Convert-ToStringArray $actual.FORBIDDEN_MATERIALIZATION) -Expected (Convert-ToStringArray $fx.EXPECTED_FORBIDDEN_MATERIALIZATION))) {
        [void]$cmp.Fails.Add("$id.TOP.EXPECTED_FORBIDDEN_MATERIALIZATION mismatch")
        $cmp.Total++
    } else { $cmp.Pass++; $cmp.Total++ }
    if (-not (Test-SetEqual -Actual (Convert-ToStringArray $actual.TRIGGERS) -Expected (Convert-ToStringArray $fx.EXPECTED_TRIGGERS))) {
        [void]$cmp.Fails.Add("$id.TOP.EXPECTED_TRIGGERS mismatch")
        $cmp.Total++
    } else { $cmp.Pass++; $cmp.Total++ }
    $cmp.Total++
    if ([string]$actual.AUTHORITY -eq [string]$fx.EXPECTED_AUTHORITY) { $cmp.Pass++ } else {
        [void]$cmp.Fails.Add("$id.TOP.EXPECTED_AUTHORITY mismatch")
    }
    $cmp.Total++
    if ([string]$actual.EVIDENCE_REQUIRED -eq [string]$fx.EXPECTED_EVIDENCE) { $cmp.Pass++ } else {
        [void]$cmp.Fails.Add("$id.TOP.EXPECTED_EVIDENCE mismatch")
    }
    $cmp.Total++
    if ([string]$actual.SECURITY.DO_NOT_UPLOAD -eq [string]$fx.EXPECTED_SECURITY.DO_NOT_UPLOAD -and
        [string]$actual.SECURITY.FAIL_CLOSED_UPLOAD -eq [string]$fx.EXPECTED_SECURITY.FAIL_CLOSED_UPLOAD) {
        $cmp.Pass++
    } else {
        [void]$cmp.Fails.Add("$id.TOP.EXPECTED_SECURITY mismatch")
    }
    $assertPass += [int]$cmp.Pass
    $assertTotal += [int]$cmp.Total
    if ($cmp.Fails.Count -eq 0) {
        $scenariosPass++
        Write-Host "PASS: $id assertions=$($cmp.Total)"
    }
    else {
        $scenariosFail++
        [void]$failedNames.Add($id)
        Write-Host "FAIL: $id"
        foreach ($x in $cmp.Fails) { Write-Host "  $x" }
    }
}

Write-Host "FORWARD_TEST_TYPE=FUNCTIONAL_DECLARATIVE"
Write-Host "SCENARIOS_TOTAL=$($files.Count)"
Write-Host "SCENARIOS_PASS=$scenariosPass"
Write-Host "SCENARIOS_FAIL=$scenariosFail"
Write-Host "ASSERTIONS_TOTAL=$assertTotal"
Write-Host "ASSERTIONS_PASS=$assertPass"
Write-Host "ASSERTIONS_FAIL=$($assertTotal - $assertPass)"
Write-Host "STRING_PRESENCE_ONLY=NO"

if ($scenariosFail -ne 0) {
    Write-Fail ("failed scenarios: " + ($failedNames -join ', '))
    exit 1
}
Write-Host 'OK: PIA functional forward tests passed'
exit 0
