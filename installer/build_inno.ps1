$ErrorActionPreference = 'Stop'

# Never compile an installer from an old Release folder. Close Agenix first:
# Windows keeps the executable locked while it is running.
if (Get-Process -Name agenix -ErrorAction SilentlyContinue) {
    throw 'Agenix is running. Close it, then run this script again.'
}

$projectRoot = Split-Path -Parent $PSScriptRoot
$iscc = Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe'
if (-not (Test-Path $iscc)) {
    throw 'Inno Setup 6 was not found. Install it or set the ISCC path.'
}

Push-Location $projectRoot
try {
    flutter build windows --release
    & $iscc (Join-Path $PSScriptRoot 'Agenix.iss')
    if ($LASTEXITCODE -ne 0) { throw "Inno Setup failed with exit code $LASTEXITCODE." }
} finally {
    Pop-Location
}
