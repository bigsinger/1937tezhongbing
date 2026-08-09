[CmdletBinding()]
param([string]$GodotExecutable, [switch]$SkipWindowedChecks, [switch]$Resume)
& (Join-Path $PSScriptRoot 'Invoke-RemakeGate.ps1') `
    -Tier Release -GodotExecutable $GodotExecutable `
    -SkipWindowedChecks:$SkipWindowedChecks -Resume:$Resume
exit $LASTEXITCODE
