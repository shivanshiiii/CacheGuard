$ErrorActionPreference = 'Stop'
Push-Location (Split-Path $PSScriptRoot -Parent)
try {
    if (Get-Command py -ErrorAction SilentlyContinue) {
        & py -3 scripts/run.py @args
    } else {
        & python scripts/run.py @args
    }
    $code = $LASTEXITCODE
} finally {
    Pop-Location
}
exit $code
