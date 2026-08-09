[CmdletBinding()]
param([string]$GodotExecutable, [switch]$Resume)
& (Join-Path $PSScriptRoot 'Invoke-RemakeGate.ps1') `
    -Tier Quick -GodotExecutable $GodotExecutable -Resume:$Resume
exit $LASTEXITCODE
