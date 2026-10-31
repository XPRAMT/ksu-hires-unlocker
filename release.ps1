# Release every device in one GitHub release (tag vX.Y.Z from the VERSION file).
# usage: .\release.ps1 [-DryRun]
param([switch]$DryRun)
$ErrorActionPreference = 'Stop'
Push-Location $PSScriptRoot
try {
  $a = @('tools/release.py'); if ($DryRun) { $a += '--dry-run' }
  python @a
  if ($LASTEXITCODE) { exit $LASTEXITCODE }
} finally { Pop-Location }
