# Install-PreCommitHook.ps1

$repoRoot = Resolve-Path "$PSScriptRoot\..\..\.."
Set-Location $repoRoot

$hookPath = ".git/hooks/pre-commit"

$hookContent = @'
#!/bin/sh
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "./SyS/A_Tools/Validation/Validate-System.ps1"
STATUS=$?

if [ -z "$STATUS" ]; then
  echo "ERROR: validation did not return status"
  exit 1
fi

if [ "$STATUS" -ne 0 ]; then
  echo "COMMIT BLOCKED: SkillMachine system validation failed."
  exit 1
fi

exit 0
'@

$hookContent = $hookContent -replace "`r`n", "`n"
[System.IO.File]::WriteAllText((Join-Path $repoRoot $hookPath), $hookContent, [System.Text.Encoding]::ASCII)

Write-Host "Pre-commit hook installed successfully"
