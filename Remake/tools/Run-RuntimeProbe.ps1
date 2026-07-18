[CmdletBinding()]
param(
    [string]$GodotExecutable,
    [string]$OutputDirectory
)

$ErrorActionPreference = 'Stop'
$remakeRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$gameDirectory = Join-Path $remakeRoot 'game'
$levelManifest = Join-Path $remakeRoot 'LocalAssets\converted\levels\m000\level.json'

if (-not (Test-Path -LiteralPath $levelManifest -PathType Leaf)) {
    throw 'The m000 local asset import is missing. Run Import-OriginalAssets.cmd first.'
}

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $remakeRoot 'LocalAssets\qa\runtime-probe'
}
$OutputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)

if ([string]::IsNullOrWhiteSpace($GodotExecutable) -and
    -not [string]::IsNullOrWhiteSpace($env:GODOT4)) {
    $GodotExecutable = $env:GODOT4
}
if ([string]::IsNullOrWhiteSpace($GodotExecutable)) {
    $godotCommand = Get-Command godot -ErrorAction SilentlyContinue
    if ($null -eq $godotCommand) {
        $godotCommand = Get-Command godot4 -ErrorAction SilentlyContinue
    }
    if ($null -ne $godotCommand) {
        $GodotExecutable = $godotCommand.Source
    }
}
if ([string]::IsNullOrWhiteSpace($GodotExecutable)) {
    throw 'Godot was not found. Pass its executable path as -GodotExecutable.'
}

$GodotExecutable = (Resolve-Path -LiteralPath $GodotExecutable).Path
if (-not $GodotExecutable.EndsWith('_console.exe', [System.StringComparison]::OrdinalIgnoreCase)) {
    $consoleExecutable = Join-Path `
        ([System.IO.Path]::GetDirectoryName($GodotExecutable)) `
        (([System.IO.Path]::GetFileNameWithoutExtension($GodotExecutable)) + '_console.exe')
    if (Test-Path -LiteralPath $consoleExecutable -PathType Leaf) {
        $GodotExecutable = $consoleExecutable
    }
}

New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$logPath = Join-Path $OutputDirectory 'godot.log'
& $GodotExecutable `
    --path $gameDirectory `
    --windowed `
    --max-fps 60 `
    --disable-vsync `
    --log-file $logPath `
    --script 'res://tests/runtime_probe.gd' `
    -- `
    "--output-dir=$OutputDirectory"
if ($LASTEXITCODE -ne 0) {
    throw "Godot runtime probe failed with exit code $LASTEXITCODE."
}

Write-Host "Runtime probe output: $OutputDirectory"
