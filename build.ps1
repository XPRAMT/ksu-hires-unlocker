# Build every device zip into dist\ (or only the devices given as arguments).
# usage: .\build.ps1 [nx809j] [liuqin]
$ErrorActionPreference = 'Stop'
Push-Location $PSScriptRoot
try { python build.py @args; if ($LASTEXITCODE) { exit $LASTEXITCODE } } finally { Pop-Location }
