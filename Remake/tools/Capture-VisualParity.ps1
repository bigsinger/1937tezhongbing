[CmdletBinding()]
param(
    [string]$GodotExecutable = '',
    [int[]]$Levels = (1..12),
    [string]$OutputDirectory = '',
    [switch]$AllowMismatch,
    [switch]$KeepRuntime
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$remakeRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $remakeRoot '..'))
$gameRoot = Join-Path $remakeRoot 'game'
$modRoot = Join-Path $repositoryRoot 'Mod'
$probeBuildRoot = 'E:\1937\probe-build'
$temporaryRoot = [IO.Path]::GetFullPath('E:\1937\')
$runtimePrefix = 'mod-visual-parity-runtime-'

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $remakeRoot (
        'LocalAssets\qa\visual-parity-' +
        (Get-Date -Format 'yyyyMMdd-HHmmss'))
}
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
[IO.Directory]::CreateDirectory($OutputDirectory) | Out-Null

$Levels = @($Levels | Sort-Object -Unique)
if ($Levels.Count -eq 0) {
    throw 'At least one selector level is required.'
}
foreach ($level in $Levels) {
    if ($level -lt 1 -or $level -gt 12) {
        throw "Selector level is outside 1..12: $level"
    }
}

if ([string]::IsNullOrWhiteSpace($GodotExecutable) -and
    -not [string]::IsNullOrWhiteSpace($env:GODOT4)) {
    $GodotExecutable = $env:GODOT4
}
if ([string]::IsNullOrWhiteSpace($GodotExecutable)) {
    foreach ($candidate in @(
            'D:\Godot\Godot_v4.7.1-stable_win64_console.exe',
            'godot4',
            'godot')) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            $GodotExecutable = $candidate
            break
        }
        $command = Get-Command $candidate -ErrorAction SilentlyContinue
        if ($null -ne $command) {
            $GodotExecutable = $command.Source
            break
        }
    }
}
if ([string]::IsNullOrWhiteSpace($GodotExecutable)) {
    throw 'Godot was not found. Pass -GodotExecutable.'
}
$GodotExecutable = (Resolve-Path -LiteralPath $GodotExecutable).Path

& (Join-Path $repositoryRoot 'Patch\analysis\tools\Build-Probes.ps1') `
    -OutputDirectory $probeBuildRoot | Out-Host
$modProbe = Join-Path $probeBuildRoot 'ModRegressionProbe.exe'
if (-not (Test-Path -LiteralPath $modProbe -PathType Leaf)) {
    throw "MOD regression probe was not built: $modProbe"
}

$runtime = Join-Path $temporaryRoot (
    $runtimePrefix + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($runtime) | Out-Null
Get-ChildItem -LiteralPath $modRoot -Force | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination $runtime -Recurse -Force
}

if (-not ('VisualParityIniV1' -as [type])) {
    Add-Type -TypeDefinition @'
using System.Runtime.InteropServices;
public static class VisualParityIniV1
{
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    public static extern bool WritePrivateProfileString(
        string section, string key, string value, string path);
}
'@
}

function Set-IsolatedIniValue {
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        [Parameter(Mandatory)]
        [string]$Section,
        [Parameter(Mandatory)]
        [string]$Key,
        [Parameter(Mandatory)]
        [string]$Value
    )

    if (-not [VisualParityIniV1]::WritePrivateProfileString(
            $Section, $Key, $Value, $Path)) {
        throw "Could not write isolated INI value [$Section] $Key."
    }
}

$runtimeIni = Join-Path $runtime 'rungame.ini'
$runtimeDdraw = Join-Path $runtime 'ddraw.ini'
Set-IsolatedIniValue $runtimeIni 'mod' 'Enabled' '1'
Set-IsolatedIniValue $runtimeIni 'mod' 'Diagnostics' '1'
Set-IsolatedIniValue $runtimeIni 'mod' 'Telemetry' '0'
Set-IsolatedIniValue $runtimeIni 'mod' 'SystemCursorMapping' '0'
Set-IsolatedIniValue $runtimeIni 'mod' 'AutoStart' '0'
Set-IsolatedIniValue $runtimeIni 'mod' 'PreserveLegacyUI' '1'
Set-IsolatedIniValue $runtimeIni 'mod' 'ExpandedViewport' '0'
Set-IsolatedIniValue $runtimeDdraw 'ddraw' 'fullscreen' 'false'
Set-IsolatedIniValue $runtimeDdraw 'ddraw' 'windowed' 'true'
Set-IsolatedIniValue $runtimeDdraw 'ddraw' 'width' '1024'
Set-IsolatedIniValue $runtimeDdraw 'ddraw' 'height' '768'
Set-IsolatedIniValue $runtimeDdraw 'ddraw' 'renderer' 'gdi'
Set-IsolatedIniValue $runtimeDdraw 'ddraw' 'devmode' 'true'
Set-IsolatedIniValue $runtimeDdraw 'ddraw' 'no_dinput_hook' 'true'
Set-IsolatedIniValue $runtimeDdraw 'ddraw' 'adjmouse' 'false'
Set-IsolatedIniValue $runtimeDdraw 'ddraw' 'savesettings' '0'
Set-IsolatedIniValue $runtimeDdraw 'ddraw' 'noactivateapp' 'true'
Set-IsolatedIniValue $runtimeDdraw 'ddraw' 'posX' '3000'
Set-IsolatedIniValue $runtimeDdraw 'ddraw' 'posY' '100'

$results = [Collections.Generic.List[object]]::new()
$completed = $false
try {
    foreach ($level in $Levels) {
        $levelId = 'm{0:D3}' -f ($level - 1)
        Get-ChildItem -LiteralPath $runtime -File -Force |
            Where-Object {
                $_.Name -like '1937M*.SAV' -or
                $_.Name -like 'M1937.SI*' -or
                $_.Name -in @(
                    'M1937Mod.log',
                    'M1937Telemetry.jsonl')
            } |
            Remove-Item -Force

        $modOutput = Join-Path $OutputDirectory "stable-mod\$levelId"
        $remakeOutput = Join-Path $OutputDirectory "remake\$levelId"
        $comparisonOutput = Join-Path $OutputDirectory "comparison\$levelId"
        foreach ($directory in @(
                $modOutput,
                $remakeOutput,
                $comparisonOutput)) {
            [IO.Directory]::CreateDirectory($directory) | Out-Null
        }

        Write-Host "Capturing stable MOD primary surface for $levelId..."
        & $modProbe @(
            $runtime,
            $modOutput,
            $level,
            30,
            '--visual-capture-only')
        if ($LASTEXITCODE -ne 0) {
            throw "Stable MOD visual probe failed for $levelId."
        }
        $modMetadataPath = Join-Path $modOutput 'visual-capture.json'
        if (-not (Test-Path -LiteralPath $modMetadataPath -PathType Leaf)) {
            throw "Stable MOD visual metadata is missing for $levelId."
        }
        $modMetadata = Get-Content -LiteralPath $modMetadataPath `
            -Raw -Encoding UTF8 | ConvertFrom-Json
        if (-not [bool]$modMetadata.passed) {
            throw "Stable MOD primary surface capture failed for $levelId."
        }
        $modImage = [IO.Path]::GetFullPath([string]$modMetadata.screenshot)
        $surfaceWidth = [int]$modMetadata.surface[0]
        $surfaceHeight = [int]$modMetadata.surface[1]
        $mapHeight = [int]$modMetadata.map_viewport[1]
        $cameraLeft = [int]$modMetadata.camera_left
        $cameraTop = [int]$modMetadata.camera_top

        Write-Host (
            "Capturing Remake for {0} at original camera ({1},{2})..." -f
            $levelId, $cameraLeft, $cameraTop)
        $remakeImage = Join-Path $remakeOutput 'gameplay-world.png'
        $remakeMetadata = Join-Path $remakeOutput 'visual-capture.json'
        $godotLog = Join-Path $remakeOutput 'godot.log'
        & $GodotExecutable @(
            '--path',
            $gameRoot,
            '--windowed',
            '--resolution',
            "$($surfaceWidth)x$($surfaceHeight)",
            '--position',
            '3000,100',
            '--max-fps',
            '60',
            '--disable-vsync',
            '--rendering-method',
            'gl_compatibility',
            '--log-file',
            $godotLog,
            '--script',
            'res://tests/visual_parity_probe.gd',
            '--',
            "--output=$($remakeImage.Replace('\', '/'))",
            "--metadata=$($remakeMetadata.Replace('\', '/'))",
            "--level=$levelId",
            "--level-id=$levelId",
            "--camera-left=$cameraLeft",
            "--camera-top=$cameraTop",
            "--viewport-width=$surfaceWidth",
            "--viewport-height=$surfaceHeight",
            '--skip-briefing',
            '--skip-level-selector')
        if ($LASTEXITCODE -ne 0) {
            throw "Remake visual probe failed for $levelId."
        }

        $comparison = & (
            Join-Path $PSScriptRoot 'Compare-VisualParity.ps1') `
            -ReferenceImage $modImage `
            -CandidateImage $remakeImage `
            -OutputDirectory $comparisonOutput `
            -RegionTop 0 `
            -RegionBottom $mapHeight `
            -MaximumMeanAbsoluteError 6.0 `
            -MinimumNearMatchRatio 0.92 `
            -MinimumEdgeCorrelation 0.94 `
            -MaximumBlackHoleRatio 0.003 `
            -AllowMismatch
        $results.Add([pscustomobject][ordered]@{
            level_id = $levelId
            selector_level = $level
            camera = @($cameraLeft, $cameraTop)
            map_viewport = @(
                [int]$modMetadata.map_viewport[0],
                $mapHeight)
            metrics = $comparison.metrics
            mod_image = $modImage
            remake_image = $remakeImage
            comparison = Join-Path $comparisonOutput 'visual-parity.json'
            passed = [bool]$comparison.passed
        })
    }
    $completed = $true
}
finally {
    if (-not $KeepRuntime) {
        $resolvedRuntime = [IO.Path]::GetFullPath($runtime)
        $expectedPrefix = [IO.Path]::GetFullPath(
            (Join-Path $temporaryRoot $runtimePrefix))
        if (-not $resolvedRuntime.StartsWith(
                $expectedPrefix,
                [StringComparison]::OrdinalIgnoreCase)) {
            throw (
                'Refusing to remove a visual runtime outside the validated ' +
                "E:\1937 prefix: $resolvedRuntime")
        }
        if (Test-Path -LiteralPath $resolvedRuntime) {
            for ($attempt = 0; $attempt -lt 8; $attempt++) {
                try {
                    Remove-Item -LiteralPath $resolvedRuntime `
                        -Recurse -Force -ErrorAction Stop
                    break
                }
                catch {
                    if ($attempt -eq 7) {
                        Write-Warning (
                            'The isolated visual runtime remains locked: ' +
                            $resolvedRuntime)
                    }
                    else {
                        Start-Sleep -Milliseconds 250
                    }
                }
            }
        }
    }
}

$allPassed = $completed -and @(
    $results | Where-Object { -not $_.passed }).Count -eq 0
$summary = [pscustomobject][ordered]@{
    schema_version = 1
    content_profile = 'repository-mod-12-level-20260729'
    generated_utc = [DateTime]::UtcNow.ToString('o')
    input_isolation = (
        'stable-mod-read-only-RGB565-surface; ' +
        'remake-offscreen-window; no global input')
    system_cursor_calls = 0
    global_focus_calls = 0
    levels = @($results)
    passed = $allPassed
}
$summaryJson = Join-Path $OutputDirectory 'summary.json'
$summary | ConvertTo-Json -Depth 10 |
    Set-Content -LiteralPath $summaryJson -Encoding UTF8

$markdown = [Collections.Generic.List[string]]::new()
$markdown.Add('# Twelve-level visual parity')
$markdown.Add('')
$markdown.Add(
    'The stable MOD reference comes directly from cnc-ddraw RGB565 primary ' +
    'surface memory. The probe does not capture the desktop and does not send ' +
    'global mouse, keyboard or focus input.')
$markdown.Add('')
$markdown.Add(
    '| Level | Camera | RGB MAE | Near match | Edge correlation | ' +
    'Black holes | Result |')
$markdown.Add('|---|---:|---:|---:|---:|---:|---|')
foreach ($result in $results) {
    $metrics = $result.metrics
    $markdown.Add(
        '| {0} | {1},{2} | {3:N3} | {4:P2} | {5:N4} | {6:P4} | {7} |' -f @(
            $result.level_id,
            $result.camera[0],
            $result.camera[1],
            [double]$metrics.mean_absolute_error,
            [double]$metrics.near_match_ratio,
            [double]$metrics.edge_correlation,
            [double]$metrics.black_hole_ratio,
            $(if ($result.passed) { 'pass' } else { 'fail' })))
}
$markdown.Add('')
$markdown.Add('Overall: ' + $(if ($allPassed) { 'pass' } else { 'fail' }))
$summaryMarkdown = Join-Path $OutputDirectory 'summary.md'
$markdown | Set-Content -LiteralPath $summaryMarkdown -Encoding UTF8

Write-Host "Visual parity summary: $summaryMarkdown"
if (-not $allPassed -and -not $AllowMismatch) {
    throw 'One or more visual parity comparisons failed.'
}
