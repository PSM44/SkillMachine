# Test-RadarRuntime.ps1
# Deterministic expected-vs-actual tests against RADAR runtime. PS 5.1 compatible.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ValidationRoot = $PSScriptRoot
$RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $ValidationRoot '..\..\..'))
$RadarDir = Join-Path $RepoRoot 'SyS\A_Tools\Radar'
$RadarScript = Join-Path $RadarDir 'RADAR.ps1'
$RadarRuntime = Join-Path $RadarDir 'Radar.Runtime.ps1'

if (-not (Test-Path -LiteralPath $RadarRuntime)) { Write-Host 'FAIL: Radar.Runtime.ps1 missing'; exit 1 }
if (-not (Test-Path -LiteralPath $RadarScript)) { Write-Host 'FAIL: RADAR.ps1 missing'; exit 1 }

. $RadarRuntime

$script:Total = 0
$script:Pass = 0
$script:Fail = 0
$script:Skipped = 0
$script:Rows = New-Object System.Collections.Generic.List[string]

function Write-RadarTestRow {
    param([string]$Id, [string]$Fixture, [string]$Expected, [string]$Actual, [int]$ExitCode, [string]$Result)
    [void]$script:Rows.Add(('TEST_ID={0} INPUT_FIXTURE={1} RUNTIME_PATH={2} EXPECTED_RESULT={3} ACTUAL_RESULT={4} EXIT_CODE={5} PASS_FAIL={6}' -f $Id, $Fixture, $RadarScript, $Expected, $Actual, $ExitCode, $Result))
}

function Assert-RadarTest {
    param([string]$Id, [string]$Fixture, [string]$Expected, [string]$Actual, [int]$ExitCode = 0, [bool]$Ok)
    $script:Total++
    $pf = $(if ($Ok) { 'PASS' } else { 'FAIL' })
    if ($Ok) { $script:Pass++ } else { $script:Fail++ }
    Write-RadarTestRow -Id $Id -Fixture $Fixture -Expected $Expected -Actual $Actual -ExitCode $ExitCode -Result $pf
    if ($Ok) { Write-Host "PASS: $Id" } else { Write-Host "FAIL: $Id expected=$Expected actual=$Actual" }
}

function New-RadarTempRoot {
    $p = Join-Path $env:TEMP ('RadarRt_' + [guid]::NewGuid().ToString('N'))
    [void](New-Item -ItemType Directory -Path $p -Force)
    return $p
}

function Invoke-RadarExe {
    param(
        [string]$Root,
        [string]$Out,
        [string]$Old,
        [string[]]$UploadSelection = @('LITE', 'INDEX'),
        [int]$MaxFileCountWarning = 10000,
        [switch]$SimulateDiskFull
    )
    $sel = ($UploadSelection -join ',')
    $argList = @(
        '-NoProfile'
        '-ExecutionPolicy'
        'Bypass'
        '-File'
        $RadarScript
        '-RootPathOverride'
        $Root
        '-OutputPathOverride'
        $Out
        '-OldPathOverride'
        $Old
        '-UploadSelection'
        $sel
        '-MaxFileCountWarning'
        [string]$MaxFileCountWarning
    )
    if ($SimulateDiskFull) { $argList += '-SimulateDiskFull' }
    & powershell.exe @argList | Out-Null
    $code = 1
    if (Get-Variable -Name LASTEXITCODE -ErrorAction SilentlyContinue) {
        $code = [int]$LASTEXITCODE
    }
    return $code
}

Write-Host 'VALIDATION: RADAR runtime functional tests'

# 1 ASCII
$c1 = Get-RadarContentClassFromBytes -Bytes ([System.Text.Encoding]::ASCII.GetBytes('hello radar')) -Extension '.txt'
Assert-RadarTest -Id 'RT01_ASCII' -Fixture 'bytes:hello' -Expected 'TEXT' -Actual ([string]$c1.Class) -Ok ($c1.Class -eq 'TEXT' -and [bool]$c1.Inline)

# 2 UTF-8
$c2 = Get-RadarContentClassFromBytes -Bytes ([System.Text.Encoding]::UTF8.GetBytes("nino cafe")) -Extension '.txt'
Assert-RadarTest -Id 'RT02_UTF8' -Fixture 'bytes:utf8' -Expected 'TEXT/UTF-8' -Actual ([string]$c2.Encoding) -Ok ($c2.Class -eq 'TEXT' -and $c2.Encoding -eq 'UTF-8')

# 3 UTF-16LE BOM
$le = New-Object System.Collections.Generic.List[byte]
[void]$le.Add(0xFF); [void]$le.Add(0xFE)
$le.AddRange([System.Text.Encoding]::Unicode.GetBytes('utf16le'))
$c3 = Get-RadarContentClassFromBytes -Bytes ([byte[]]$le.ToArray()) -Extension '.txt'
Assert-RadarTest -Id 'RT03_UTF16LE' -Fixture 'bytes:utf16le-bom' -Expected 'BOM_UTF16LE' -Actual ([string]$c3.DetectionMethod) -Ok ($c3.Class -eq 'TEXT' -and $c3.DetectionMethod -eq 'BOM_UTF16LE')

# 4 UTF-16BE BOM
$be = New-Object System.Collections.Generic.List[byte]
[void]$be.Add(0xFE); [void]$be.Add(0xFF)
$be.AddRange([System.Text.Encoding]::BigEndianUnicode.GetBytes('utf16be'))
$c4 = Get-RadarContentClassFromBytes -Bytes ([byte[]]$be.ToArray()) -Extension '.txt'
Assert-RadarTest -Id 'RT04_UTF16BE' -Fixture 'bytes:utf16be-bom' -Expected 'BOM_UTF16BE' -Actual ([string]$c4.DetectionMethod) -Ok ($c4.Class -eq 'TEXT' -and $c4.DetectionMethod -eq 'BOM_UTF16BE')

# 5 PNG magic
$png = [byte[]](0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 1, 2, 3)
$c5 = Get-RadarContentClassFromBytes -Bytes $png -Extension '.png'
Assert-RadarTest -Id 'RT05_MAGIC_PNG' -Fixture 'bytes:png' -Expected 'BINARY/MAGIC_PNG' -Actual ([string]$c5.DetectionMethod) -Ok ($c5.Class -eq 'BINARY' -and $c5.DetectionMethod -eq 'MAGIC_PNG' -and -not [bool]$c5.Inline)

# 6 NUL
$nul = [byte[]](0x68, 0x69, 0x00, 0x21)
$c6 = Get-RadarContentClassFromBytes -Bytes $nul -Extension '.txt'
Assert-RadarTest -Id 'RT06_NUL' -Fixture 'bytes:nul' -Expected 'BINARY/NUL' -Actual ([string]$c6.DetectionMethod) -Ok ($c6.Class -eq 'BINARY' -and $c6.DetectionMethod -eq 'NUL' -and -not [bool]$c6.Inline)

# 7 misleading .txt with PNG
$c7 = Get-RadarContentClassFromBytes -Bytes $png -Extension '.txt'
Assert-RadarTest -Id 'RT07_TXT_IS_PNG' -Fixture 'bytes:png-as-txt' -Expected 'BINARY' -Actual ([string]$c7.Class) -Ok ($c7.Class -eq 'BINARY' -and -not [bool]$c7.Inline)

# 8 unreadable
$c8 = Get-RadarContentClassFromBytes -Bytes $null -Extension '.txt' -Unreadable $true
Assert-RadarTest -Id 'RT08_UNREADABLE' -Fixture 'flag:unreadable' -Expected 'UNREADABLE' -Actual ([string]$c8.Class) -Ok ($c8.Class -eq 'UNREADABLE' -and -not [bool]$c8.Inline)

# text with binary extension
$hello = [System.Text.Encoding]::UTF8.GetBytes('hello')
$c7b = Get-RadarContentClassFromBytes -Bytes $hello -Extension '.png'
Assert-RadarTest -Id 'RT07B_TEXT_BIN_EXT' -Fixture 'bytes:hello.png' -Expected 'TEXT_WITH_BINARY_EXTENSION/no-inline' -Actual ([string]$c7b.DetectionMethod) -Ok ($c7b.Class -eq 'TEXT' -and $c7b.DetectionMethod -eq 'TEXT_WITH_BINARY_EXTENSION' -and -not [bool]$c7b.Inline)

# 9 hardlink
$fx9 = New-RadarTempRoot
Set-Content -LiteralPath (Join-Path $fx9 'orig.txt') -Value 'same-physical' -Encoding ASCII
$hl = Join-Path $fx9 'hard.txt'
cmd.exe /c ("mklink /H `"$hl`" `"$(Join-Path $fx9 'orig.txt')`"") | Out-Null
$enum9 = Invoke-RadarEnumerate -RootPath $fx9 -ExcludedPaths @() -CoreMaxFileSizeBytes 2097152
$ok9 = ($enum9.HardlinkPathsDiscovered -ge 2 -and $enum9.UniquePhysicalFilesCounted -eq 1)
if (-not $ok9) {
    # still require identity equality if mklink worked
    if (Test-Path -LiteralPath $hl) {
        $i1 = Get-RadarFileIdentity -Path (Join-Path $fx9 'orig.txt')
        $i2 = Get-RadarFileIdentity -Path $hl
        $ok9 = ([bool]$i1.Ok -and [bool]$i2.Ok -and [string]$i1.FileId -eq [string]$i2.FileId -and $enum9.UniquePhysicalFilesCounted -eq 1)
    }
}
Assert-RadarTest -Id 'RT09_HARDLINK' -Fixture $fx9 -Expected 'HARDLINK_PATHS_DISCOVERED>=2 UNIQUE=1' -Actual ("H=$($enum9.HardlinkPathsDiscovered);U=$($enum9.UniquePhysicalFilesCounted)") -Ok $ok9

# 10 symlink (real or metadata mock)
$fx10 = New-RadarTempRoot
Set-Content -LiteralPath (Join-Path $fx10 't.txt') -Value 'target' -Encoding ASCII
$sl = Join-Path $fx10 'link.txt'
$symOk = $false
try {
    New-Item -ItemType SymbolicLink -Path $sl -Target (Join-Path $fx10 't.txt') -ErrorAction Stop | Out-Null
    $symOk = $true
} catch { $symOk = $false }
if ($symOk) {
    $enum10 = Invoke-RadarEnumerate -RootPath $fx10 -ExcludedPaths @()
    $linkRec = @($enum10.Records | Where-Object { [string]$_.relative_path -eq 'link.txt' }) | Select-Object -First 1
    $ok10 = ($null -ne $linkRec -and -not [bool]$linkRec.follow -and [string]$linkRec.content_status -match 'LINK|BROKEN')
    Assert-RadarTest -Id 'RT10_SYMLINK' -Fixture $fx10 -Expected 'UNFOLLOWED' -Actual ([string]$linkRec.content_status) -Ok $ok10
}
else {
    $mock = [pscustomobject]@{ FullName = $sl; Extension = '.txt'; Attributes = [System.IO.FileAttributes]::ReparsePoint; LinkType = 'SymbolicLink'; Target = (Join-Path $fx10 't.txt'); PSIsContainer = $false; Length = 0; LastWriteTime = Get-Date }
    $info = Get-RadarLinkInfo -Item $mock -RootPath $fx10
    Assert-RadarTest -Id 'RT10_SYMLINK' -Fixture 'mock-symlink-metadata' -Expected 'FOLLOW=false' -Actual ("Follow=$($info.Follow);Type=$($info.LinkType)") -Ok (-not [bool]$info.Follow -and $info.IsReparse)
}

# 11 junction or mock
$fx11 = New-RadarTempRoot
$srcDir = Join-Path $fx11 'src'
$junc = Join-Path $fx11 'junc'
[void](New-Item -ItemType Directory -Path $srcDir -Force)
Set-Content -LiteralPath (Join-Path $srcDir 'in.txt') -Value 'inside' -Encoding ASCII
cmd.exe /c ("mklink /J `"$junc`" `"$srcDir`"") | Out-Null
if (Test-Path -LiteralPath $junc) {
    $enum11 = Invoke-RadarEnumerate -RootPath $fx11 -ExcludedPaths @()
    $jrec = @($enum11.Records | Where-Object { [string]$_.relative_path -eq 'junc' -or [string]$_.full_path -eq $junc }) | Select-Object -First 1
    $followedInsideTwice = @($enum11.Records | Where-Object { [string]$_.relative_path -match 'junc[\\/]in\.txt' }).Count
    $ok11 = ($followedInsideTwice -eq 0)
    Assert-RadarTest -Id 'RT11_JUNCTION' -Fixture $fx11 -Expected 'JUNCTION_NOT_FOLLOWED' -Actual ("nested=$followedInsideTwice") -Ok $ok11
}
else {
    $mockJ = [pscustomobject]@{ FullName = $junc; Extension = ''; Attributes = [System.IO.FileAttributes]::Directory -bor [System.IO.FileAttributes]::ReparsePoint; LinkType = 'Junction'; Target = $srcDir; PSIsContainer = $true; Length = 0; LastWriteTime = Get-Date }
    $infoJ = Get-RadarLinkInfo -Item $mockJ -RootPath $fx11
    Assert-RadarTest -Id 'RT11_JUNCTION' -Fixture 'mock-junction-metadata' -Expected 'FOLLOW=false' -Actual ("Follow=$($infoJ.Follow)") -Ok (-not [bool]$infoJ.Follow)
}

# 12 cycle
$visited = @{}
$idA = Get-RadarFileIdentity -Path $fx11
$stop1 = Test-RadarShouldStopCycle -Visited $visited -Identity $idA -Path $fx11
$stop2 = Test-RadarShouldStopCycle -Visited $visited -Identity $idA -Path (Join-Path $fx11 'alias')
Assert-RadarTest -Id 'RT12_CYCLE' -Fixture 'cycle-guard' -Expected 'first=false second=true' -Actual ("$stop1/$stop2") -Ok ((-not $stop1) -and $stop2)

# 13 broken link mock
$brokenItem = [pscustomobject]@{ FullName = (Join-Path $fx11 'missing-link'); Extension = '.txt'; Attributes = [System.IO.FileAttributes]::ReparsePoint; LinkType = 'SymbolicLink'; Target = (Join-Path $fx11 'no-such-target'); PSIsContainer = $false; Length = 0; LastWriteTime = Get-Date }
$brk = Get-RadarLinkInfo -Item $brokenItem -RootPath $fx11
Assert-RadarTest -Id 'RT13_BROKEN_LINK' -Fixture 'mock-broken' -Expected 'BROKEN+UNFOLLOWED' -Actual ("State=$($brk.TargetState);Follow=$($brk.Follow)") -Ok ([bool]$brk.IsBroken -and -not [bool]$brk.Follow)

# 14 00_ACCESS
$fx14 = New-RadarTempRoot
[void](New-Item -ItemType Directory -Path (Join-Path $fx14 '00_ACCESS') -Force)
Set-Content -LiteralPath (Join-Path $fx14 '00_ACCESS\hidden.txt') -Value 'should-not-follow' -Encoding ASCII
Set-Content -LiteralPath (Join-Path $fx14 'visible.txt') -Value 'ok' -Encoding ASCII
$enum14 = Invoke-RadarEnumerate -RootPath $fx14 -ExcludedPaths @()
$hidden = @($enum14.Records | Where-Object { [string]$_.relative_path -match 'hidden\.txt' }).Count
$accessListed = $enum14.AccessBlocked.Count
Assert-RadarTest -Id 'RT14_00_ACCESS' -Fixture $fx14 -Expected 'ACCESS_UNFOLLOWED hidden=0' -Actual ("hidden=$hidden access=$accessListed") -Ok ($hidden -eq 0 -and $accessListed -ge 1)

# 15 synthetic secret
$hits = @(Get-RadarSecretHits -Text 'token=sk_test_abcdefghijklmnopqrstuvwxyz')
$fpLeak = @($hits | Where-Object { [string]$_.Fingerprint -match 'sk_test_abcdefghijklmnopqrstuvwxyz' }).Count
Assert-RadarTest -Id 'RT15_SECRET' -Fixture 'synthetic-token' -Expected 'TOKEN hit, no raw secret in fingerprint' -Actual ("hits=$($hits.Count);leak=$fpLeak") -Ok ($hits.Count -ge 1 -and $fpLeak -eq 0)

# false positive controlled
$fp = @(Get-RadarSecretHits -Text 'The token economy is a concept without assignment.')
Assert-RadarTest -Id 'RT15B_FALSE_POSITIVE' -Fixture 'token-economy' -Expected '0 hits' -Actual ("hits=$($fp.Count)") -Ok ($fp.Count -eq 0)

# 16-21, 17-20, 23, 25 integration fixture
$fxI = New-RadarTempRoot
$outI = Join-Path $fxI '_out'
$oldI = Join-Path $fxI '_old'
[void](New-Item -ItemType Directory -Path $outI -Force)
[void](New-Item -ItemType Directory -Path $oldI -Force)
[void](New-Item -ItemType Directory -Path (Join-Path $fxI 'SkillsLake\01.SKILLS') -Force)
[void](New-Item -ItemType Directory -Path (Join-Path $fxI '00.SOURCE_DO_NOT_UPLOAD') -Force)
[void](New-Item -ItemType Directory -Path (Join-Path $fxI 'HUMAN') -Force)
Set-Content -LiteralPath (Join-Path $fxI 'ascii.txt') -Value 'plain ascii' -Encoding ASCII
Set-Content -LiteralPath (Join-Path $fxI 'SkillsLake\01.SKILLS\demo.txt') -Value 'skill text' -Encoding ASCII
Set-Content -LiteralPath (Join-Path $fxI 'HUMAN\note.txt') -Value 'human text' -Encoding ASCII
Set-Content -LiteralPath (Join-Path $fxI '00.SOURCE_DO_NOT_UPLOAD\sealed.txt') -Value 'sealed-body-xyz' -Encoding ASCII
Set-Content -LiteralPath (Join-Path $fxI 'marked.DO_NOT_UPLOAD.txt') -Value 'marked-body-xyz' -Encoding ASCII
Set-Content -LiteralPath (Join-Path $fxI 'secret.txt') -Value "token=sk_test_abcdefghijklmnopqrstuvwxyz`r`n-----BEGIN RSA PRIVATE KEY-----`r`nMIIFAKEINVALIDKEY`r`n-----END RSA PRIVATE KEY-----`r`nServer=localhost;Database=x;Password=FakePassword12345;" -Encoding ASCII
Set-Content -LiteralPath (Join-Path $fxI 'quote say.txt') -Value 'delim' -Encoding ASCII
[System.IO.File]::WriteAllBytes((Join-Path $fxI 'pic.png'), $png)

$codeI = Invoke-RadarExe -Root $fxI -Out $outI -Old $oldI -UploadSelection @('LITE', 'INDEX')
$six = @(
    'RADAR_INDEX.ACTIVE.txt'
    'RADAR_CORE.ACTIVE.txt'
    'RADAR_FULL.ACTIVE.txt'
    'RADAR_LITE.ACTIVE.txt'
    'RADAR_FULL.HUMAN.ACTIVE.txt'
    'RADAR_FULL.SKILLS.ACTIVE.txt'
)
$sixOk = $true
foreach ($n in $six) {
    if (-not (Test-Path -LiteralPath (Join-Path $outI $n))) { $sixOk = $false }
}
$manPath = Join-Path $outI 'radar.manifest.json'
$sixOk = $sixOk -and (Test-Path -LiteralPath $manPath)
Assert-RadarTest -Id 'RT18_FIRST_RUN' -Fixture $fxI -Expected 'exit0 FIRST_RUN six outputs' -Actual ("exit=$codeI six=$sixOk") -ExitCode $codeI -Ok ($codeI -eq 0 -and $sixOk)
Assert-RadarTest -Id 'RT19_SIX_OUTPUTS' -Fixture $fxI -Expected 'CORE FULL FULL.HUMAN FULL.SKILLS generated' -Actual ("six=$sixOk") -ExitCode $codeI -Ok $sixOk

$liteTxt = ''
$coreTxt = ''
$skillsTxt = ''
$idxTxt = ''
$man = $null
if ($sixOk) {
    $liteTxt = [System.IO.File]::ReadAllText((Join-Path $outI 'RADAR_LITE.ACTIVE.txt'))
    $coreTxt = [System.IO.File]::ReadAllText((Join-Path $outI 'RADAR_CORE.ACTIVE.txt'))
    $skillsTxt = [System.IO.File]::ReadAllText((Join-Path $outI 'RADAR_FULL.SKILLS.ACTIVE.txt'))
    $idxTxt = [System.IO.File]::ReadAllText((Join-Path $outI 'RADAR_INDEX.ACTIVE.txt'))
    $man = Get-Content -LiteralPath $manPath -Raw | ConvertFrom-Json
}

Assert-RadarTest -Id 'RT16_DO_NOT_UPLOAD' -Fixture $fxI -Expected 'sealed/marked bodies absent from CORE/SKILLS' -Actual 'checked' -Ok (
    ($coreTxt -notmatch 'sealed-body-xyz') -and ($skillsTxt -notmatch 'sealed-body-xyz') -and
    ($coreTxt -notmatch 'marked-body-xyz') -and ($skillsTxt -notmatch 'marked-body-xyz')
)
Assert-RadarTest -Id 'RT15C_SECRET_NOT_IN_BUNDLES' -Fixture $fxI -Expected 'synthetic secret absent' -Actual 'checked' -Ok (
    ($coreTxt -notmatch 'sk_test_abcdefghijklmnopqrstuvwxyz') -and
    ($skillsTxt -notmatch 'sk_test_abcdefghijklmnopqrstuvwxyz') -and
    ($coreTxt -notmatch 'FakePassword12345') -and
    ($skillsTxt -notmatch 'BEGIN RSA PRIVATE KEY')
)
Assert-RadarTest -Id 'RT17_FULL_SKILLS' -Fixture $fxI -Expected 'FAIL_CLOSED and demo.txt present or skipped safely' -Actual 'checked' -Ok (
    ($skillsTxt -match 'FAIL_CLOSED=YES') -and ($skillsTxt -notmatch 'sk_test_abcdefghijklmnopqrstuvwxyz')
)
Assert-RadarTest -Id 'RT20_DAILY_UPLOAD' -Fixture $fxI -Expected 'six generated AND upload LITE,INDEX' -Actual ([string]($man.upload_selection -join ',')) -Ok (
    $sixOk -and ($liteTxt -match 'NO_SUBIR != NO_GENERAR') -and ([string]$man.no_subir_equals_no_generar -eq 'False') -and
    ($man.upload_selection -contains 'LITE') -and ($man.upload_selection -contains 'INDEX')
)
Assert-RadarTest -Id 'RT24_ESCAPING' -Fixture $fxI -Expected 'PATH_JSON present' -Actual 'checked' -Ok ($coreTxt -match 'PATH_JSON=' -and $coreTxt -match 'RADAR_FILE_BEGIN')
Assert-RadarTest -Id 'RT25_SCHEMA' -Fixture $fxI -Expected 'six types + FILE_ID + first_run' -Actual 'checked' -Ok (
    ($idxTxt -match 'FILE_ID=') -and ($liteTxt -match 'FIRST_RUN=YES') -and ($liteTxt -match 'LITE_MODE=version_0') -and
    ($man.output_set.Count -ge 6) -and ([bool]$man.first_run) -and ($man.radar_output_schema -eq 'v1.5')
)

# 21 large repo warning
$fxL = New-RadarTempRoot
$outL = Join-Path $fxL '_out'
$oldL = Join-Path $fxL '_old'
[void](New-Item -ItemType Directory -Path $outL -Force)
[void](New-Item -ItemType Directory -Path $oldL -Force)
1..12 | ForEach-Object { Set-Content -LiteralPath (Join-Path $fxL ("f$_.txt")) -Value $_ -Encoding ASCII }
$codeL = Invoke-RadarExe -Root $fxL -Out $outL -Old $oldL -MaxFileCountWarning 5
$liteL = ''
if (Test-Path -LiteralPath (Join-Path $outL 'RADAR_LITE.ACTIVE.txt')) {
    $liteL = [System.IO.File]::ReadAllText((Join-Path $outL 'RADAR_LITE.ACTIVE.txt'))
}
Assert-RadarTest -Id 'RT21_LARGE_REPO' -Fixture $fxL -Expected 'SIZE_WARNING=YES still generated' -Actual $liteL.Substring(0, [Math]::Min(80, $liteL.Length)) -ExitCode $codeL -Ok ($codeL -eq 0 -and $liteL -match 'SIZE_WARNING=YES')

# 22 partial error: unreadable classification does not prevent TEXT neighbor
$fx22 = New-RadarTempRoot
Set-Content -LiteralPath (Join-Path $fx22 'ok.txt') -Value 'ok' -Encoding ASCII
[System.IO.File]::WriteAllBytes((Join-Path $fx22 'bad.bin'), [byte[]](0, 1, 2, 0, 9))
$enum22 = Invoke-RadarEnumerate -RootPath $fx22 -ExcludedPaths @()
$okRec = @($enum22.Records | Where-Object { $_.relative_path -eq 'ok.txt' -and $_.content_class -eq 'TEXT' }).Count
$badRec = @($enum22.Records | Where-Object { $_.relative_path -eq 'bad.bin' }).Count
Assert-RadarTest -Id 'RT22_PARTIAL' -Fixture $fx22 -Expected 'ok TEXT and bad present without abort' -Actual ("ok=$okRec bad=$badRec") -Ok ($okRec -eq 1 -and $badRec -eq 1)

# 23 atomicity
$fx23 = New-RadarTempRoot
$out23 = Join-Path $fx23 '_out'
$old23 = Join-Path $fx23 '_old'
[void](New-Item -ItemType Directory -Path $out23 -Force)
[void](New-Item -ItemType Directory -Path $old23 -Force)
Set-Content -LiteralPath (Join-Path $fx23 'a.txt') -Value 'x' -Encoding ASCII
$code23 = Invoke-RadarExe -Root $fx23 -Out $out23 -Old $old23 -SimulateDiskFull
$active23 = @(Get-ChildItem -LiteralPath $out23 -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -like 'RADAR_*.ACTIVE.txt' }).Count
Assert-RadarTest -Id 'RT23_ATOMICITY' -Fixture $fx23 -Expected 'fail and no ACTIVE outputs' -Actual ("exit=$code23 active=$active23") -ExitCode $code23 -Ok ($code23 -ne 0 -and $active23 -eq 0)

# outside-root target mock
$outItem = [pscustomobject]@{ FullName = (Join-Path $fx11 'outlink'); Extension = ''; Attributes = [System.IO.FileAttributes]::ReparsePoint; LinkType = 'SymbolicLink'; Target = 'C:\Windows'; PSIsContainer = $false; Length = 0; LastWriteTime = Get-Date }
$outInfo = Get-RadarLinkInfo -Item $outItem -RootPath $fx11
Assert-RadarTest -Id 'RT10B_OUTSIDE_ROOT' -Fixture 'mock-outside' -Expected 'OUTSIDE_ROOT unfollow' -Actual ([string]$outInfo.TargetScope) -Ok ($outInfo.OutsideRoot -and -not [bool]$outInfo.Follow)

foreach ($line in $script:Rows) { Write-Host $line }
Write-Host "RADAR_RUNTIME_TESTS_TOTAL=$($script:Total)"
Write-Host "RADAR_RUNTIME_TESTS_PASS=$($script:Pass)"
Write-Host "RADAR_RUNTIME_TESTS_FAIL=$($script:Fail)"
Write-Host "RADAR_RUNTIME_TESTS_SKIPPED=$($script:Skipped)"

if ($script:Fail -ne 0 -or $script:Skipped -ne 0) {
    Write-Host 'FAIL: RADAR runtime tests'
    exit 1
}
Write-Host 'OK: RADAR runtime tests passed'
exit 0
