# Preserve the original PowerShell entry point for the Windows setup script and callers.
param(
    [string]$OutputPath = "torus_trooper.exe",
    [switch]$Verify
)

$ErrorActionPreference = "Stop"
$BuildArguments = @('--output', $OutputPath)
if ($Verify) { $BuildArguments += '--verify' }
Push-Location (Split-Path -Parent $PSScriptRoot)
try {
    & v run (Join-Path $PSScriptRoot 'build_windows.vsh') @BuildArguments
    if ($LASTEXITCODE -ne 0) { throw "Windows build failed with status $LASTEXITCODE." }
} finally {
    Pop-Location
}
