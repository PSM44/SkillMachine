# Install-PreCommitHook.ps1

$repoRoot = Resolve-Path "$PSScriptRoot\..\..\.."
Set-Location $repoRoot

$hookPath = ".git/hooks/pre-commit"

$hookContent = @'
#!/bin/sh
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "./SyS/A_Tools/Validation/Validate-SkillMachineNaming.ps1"
STATUS=$?

if [ $STATUS -ne 0 ]; then
  echo "COMMIT BLOCKED: SkillMachine naming validation failed."
  exit 1
fi

exit 0
'@

$hookContent = $hookContent -replace "
", "
"
$ascii = [System.Text.Encoding]::ASCII
[System.IO.File]::WriteAllText((Join-Path $repoRoot $hookPath), $hookContent, $ascii)

Write-Host "Pre-commit hook installed successfully"
