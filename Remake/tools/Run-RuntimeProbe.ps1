[CmdletBinding()]
param(
    [string]$GodotExecutable,
    [string]$OutputDirectory
)

$ErrorActionPreference = 'Stop'
$remakeRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$gameDirectory = Join-Path $remakeRoot 'game'
$levelManifest = Join-Path $remakeRoot 'LocalAssets\converted\levels\m000\level.json'
$localOcrScript = Join-Path `
    ([System.IO.Path]::GetDirectoryName($remakeRoot)) `
    'Patch\analysis\tools\Invoke-LocalScreenshotOcr.ps1'

if (-not (Test-Path -LiteralPath $levelManifest -PathType Leaf)) {
    throw 'The m000 stable-MOD asset import is missing. Run Import-ModAssets.cmd first.'
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

$parityOutput = Join-Path $OutputDirectory 'parity'
New-Item -ItemType Directory -Force -Path $parityOutput | Out-Null
$parityLog = Join-Path $OutputDirectory 'parity.log'
& $GodotExecutable `
    --headless `
    --path $gameDirectory `
    --max-fps 60 `
    --disable-vsync `
    --log-file $parityLog `
    --script 'res://tests/parity_runtime_probe.gd' `
    -- `
    "--output-dir=$parityOutput"
if ($LASTEXITCODE -ne 0) {
    throw "Godot parity runtime probe failed with exit code $LASTEXITCODE."
}

& $GodotExecutable `
    --headless `
    --path $gameDirectory `
    --max-fps 60 `
    --disable-vsync `
    --log-file (Join-Path $OutputDirectory 'parity-obstacle.log') `
    --script 'res://tests/parity_runtime_probe.gd' `
    -- `
    "--output-dir=$parityOutput" `
    '--scenario-id=m000-obstacle-route-v1' `
    '--outbound-target=528,552' `
    '--return-target=304,136' `
    '--observation-seconds=0.75'
if ($LASTEXITCODE -ne 0) {
    throw "Godot obstacle-route parity probe failed with exit code $LASTEXITCODE."
}

$parityScenarios = @(
    'm000-basic-movement-v1',
    'm000-obstacle-route-v1'
)
foreach ($scenarioId in $parityScenarios) {
    $modBaseline = Join-Path $remakeRoot (
        'validation\baselines\mod\' + $scenarioId + '.json')
    $remakeTrace = Join-Path $parityOutput (
        'remake-' + $scenarioId + '.json')
    if (-not (Test-Path -LiteralPath $modBaseline -PathType Leaf)) {
        throw "The stable-MOD parity baseline is missing: $scenarioId"
    }
    & (Join-Path $PSScriptRoot 'Compare-RuntimeParityTrace.ps1') `
        -ReferenceTrace $modBaseline `
        -CandidateTrace $remakeTrace `
        -OutputJson (
            Join-Path $parityOutput ($scenarioId + '-comparison.json')) `
        -OutputMarkdown (
            Join-Path $parityOutput ($scenarioId + '-comparison.md')) |
        Out-Null
}

$productUiOutput = Join-Path $OutputDirectory 'product-ui'
New-Item -ItemType Directory -Force -Path $productUiOutput | Out-Null
$productUiLog = Join-Path $OutputDirectory 'product-ui.log'
& $GodotExecutable `
    --path $gameDirectory `
    --windowed `
    --max-fps 60 `
    --disable-vsync `
    --log-file $productUiLog `
    --script 'res://tests/product_ui_probe.gd' `
    -- `
    "--output-dir=$productUiOutput"
if ($LASTEXITCODE -ne 0) {
    throw "Godot product UI probe failed with exit code $LASTEXITCODE."
}

if (Test-Path -LiteralPath $localOcrScript -PathType Leaf) {
    Get-ChildItem -LiteralPath $OutputDirectory -Filter '*.jpg' -File -Recurse |
        ForEach-Object {
            & powershell.exe -NoProfile -ExecutionPolicy Bypass `
                -File $localOcrScript -ImagePath $_.FullName
            if ($LASTEXITCODE -ne 0) {
                Write-Warning "Local OCR was unavailable for $($_.Name)."
            }
        }
}

Write-Host "Runtime probe output: $OutputDirectory"
Write-Host "Compressed window captures and local OCR: $OutputDirectory"
