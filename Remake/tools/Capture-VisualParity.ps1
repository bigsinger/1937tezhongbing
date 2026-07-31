[CmdletBinding()]
param(
    [string]$GodotExecutable = '',
    [int[]]$Levels = (1..12),
    [string]$OutputDirectory = '',
    [ValidateRange(640, 7680)]
    [int]$Width = 1024,
    [ValidateRange(480, 4320)]
    [int]$Height = 768,
    [switch]$ExpandedViewport,
    [switch]$TiledModernViewport,
    [switch]$IncludeUi,
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
$worldRegionTop = if ($IncludeUi) { 0 } else { 48 }
$thresholds = [pscustomobject][ordered]@{
    maximum_mean_absolute_error = 6.0
    minimum_near_match_ratio = 0.92
    minimum_edge_correlation = 0.94
    maximum_black_hole_ratio = 0.003
}

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $remakeRoot (
        "LocalAssets\qa\visual-parity-$($Width)x$($Height)-" +
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
if ($ExpandedViewport -and $TiledModernViewport) {
    throw 'ExpandedViewport and TiledModernViewport are mutually exclusive.'
}
if ($TiledModernViewport -and $IncludeUi) {
    throw 'TiledModernViewport compares world rendering only; omit IncludeUi.'
}
if ($TiledModernViewport -and ($Width -lt 1024 -or $Height -lt 708)) {
    throw 'TiledModernViewport requires at least 1024x708.'
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
$modLogicalWidth = if ($TiledModernViewport) { 1024 } else { $Width }
$modLogicalHeight = if ($TiledModernViewport) { 768 } else { $Height }
Set-IsolatedIniValue $runtimeIni 'mod' 'Enabled' '1'
Set-IsolatedIniValue $runtimeIni 'mod' 'Diagnostics' '1'
Set-IsolatedIniValue $runtimeIni 'mod' 'Telemetry' '0'
Set-IsolatedIniValue $runtimeIni 'mod' 'SystemCursorMapping' '0'
Set-IsolatedIniValue $runtimeIni 'mod' 'AutoStart' '0'
Set-IsolatedIniValue $runtimeIni 'mod' 'PreserveLegacyUI' '1'
$expandedViewportValue = if ($ExpandedViewport) { '1' } else { '0' }
Set-IsolatedIniValue $runtimeIni 'mod' 'ExpandedViewport' `
    $expandedViewportValue
Set-IsolatedIniValue $runtimeDdraw 'ddraw' 'fullscreen' 'false'
Set-IsolatedIniValue $runtimeDdraw 'ddraw' 'windowed' 'true'
Set-IsolatedIniValue $runtimeDdraw 'ddraw' 'width' `
    ([string]$modLogicalWidth)
Set-IsolatedIniValue $runtimeDdraw 'ddraw' 'height' `
    ([string]$modLogicalHeight)
Set-IsolatedIniValue $runtimeDdraw 'ddraw' 'renderer' 'gdi'
Set-IsolatedIniValue $runtimeDdraw 'ddraw' 'devmode' 'true'
Set-IsolatedIniValue $runtimeDdraw 'ddraw' 'no_dinput_hook' 'true'
Set-IsolatedIniValue $runtimeDdraw 'ddraw' 'adjmouse' 'false'
Set-IsolatedIniValue $runtimeDdraw 'ddraw' 'savesettings' '0'
Set-IsolatedIniValue $runtimeDdraw 'ddraw' 'noactivateapp' 'true'
Set-IsolatedIniValue $runtimeDdraw 'ddraw' 'posX' '3000'
Set-IsolatedIniValue $runtimeDdraw 'ddraw' 'posY' '100'

function Reset-IsolatedRuntimeState {
    Get-ChildItem -LiteralPath $runtime -File -Force |
        Where-Object {
            $_.Name -like '1937M*.SAV' -or
            $_.Name -like 'M1937.SI*' -or
            $_.Name -in @(
                'M1937Mod.log',
                'M1937Telemetry.jsonl')
        } |
        Remove-Item -Force
}

function Invoke-StableModVisualCapture {
    param(
        [Parameter(Mandatory)]
        [int]$SelectorLevel,
        [Parameter(Mandatory)]
        [string]$CaptureOutput,
        [int]$CameraWorldX = -1,
        [int]$CameraWorldY = -1
    )

    [IO.Directory]::CreateDirectory($CaptureOutput) | Out-Null
    $metadataPath = Join-Path $CaptureOutput 'visual-capture.json'
    $screenshotPath = Join-Path $CaptureOutput '02-gameplay-surface.png'
    $probeExitCode = -1
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        Reset-IsolatedRuntimeState
        foreach ($stalePath in @($metadataPath, $screenshotPath)) {
            if (Test-Path -LiteralPath $stalePath -PathType Leaf) {
                Remove-Item -LiteralPath $stalePath -Force
            }
        }
        $arguments = @(
            $runtime,
            $CaptureOutput,
            $SelectorLevel,
            30,
            '--visual-capture-only')
        if ($CameraWorldX -ge 0 -and $CameraWorldY -ge 0) {
            $arguments += "--visual-camera-x=$CameraWorldX"
            $arguments += "--visual-camera-y=$CameraWorldY"
        }
        & $modProbe $arguments | Out-Host
        $probeExitCode = $LASTEXITCODE
        if (
            $probeExitCode -eq 0 -and
            (Test-Path -LiteralPath $metadataPath -PathType Leaf)
        ) {
            $metadata = Get-Content -LiteralPath $metadataPath `
                -Raw -Encoding UTF8 | ConvertFrom-Json
            if (
                [bool]$metadata.passed -and
                (Test-Path -LiteralPath $screenshotPath -PathType Leaf)
            ) {
                return $metadata
            }
        }
        if ($attempt -lt 3) {
            Write-Warning (
                'Stable MOD gameplay surface was not ready for selector ' +
                "$SelectorLevel on attempt $attempt; retrying in a fresh " +
                'isolated process.')
        }
    }
    throw (
        'Stable MOD gameplay surface capture failed for selector ' +
        "$SelectorLevel after 3 attempts; last exit code: $probeExitCode.")
}

$results = [Collections.Generic.List[object]]::new()
$completed = $false
$expandedEnvironmentNames = @(
    'M1937_UNSAFE_EXPANDED_VIEWPORT',
    'M1937_EXPANDED_VIEWPORT',
    'M1937_VIEWPORT_WIDTH',
    'M1937_VIEWPORT_HEIGHT')
$previousExpandedEnvironment = @{}
foreach ($name in $expandedEnvironmentNames) {
    $previousExpandedEnvironment[$name] = (
        [Environment]::GetEnvironmentVariable(
            $name,
            [EnvironmentVariableTarget]::Process))
}
if ($ExpandedViewport) {
    [Environment]::SetEnvironmentVariable(
        'M1937_UNSAFE_EXPANDED_VIEWPORT',
        '1',
        [EnvironmentVariableTarget]::Process)
    [Environment]::SetEnvironmentVariable(
        'M1937_EXPANDED_VIEWPORT',
        '1',
        [EnvironmentVariableTarget]::Process)
    [Environment]::SetEnvironmentVariable(
        'M1937_VIEWPORT_WIDTH',
        [string]$Width,
        [EnvironmentVariableTarget]::Process)
    [Environment]::SetEnvironmentVariable(
        'M1937_VIEWPORT_HEIGHT',
        [string]$Height,
        [EnvironmentVariableTarget]::Process)
}
try {
    foreach ($level in $Levels) {
        $levelId = 'm{0:D3}' -f ($level - 1)
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
        $initialModOutput = if ($TiledModernViewport) {
            Join-Path $modOutput 'initial'
        }
        else {
            $modOutput
        }
        $modMetadata = Invoke-StableModVisualCapture `
            -SelectorLevel $level `
            -CaptureOutput $initialModOutput
        $modImage = [IO.Path]::GetFullPath([string]$modMetadata.screenshot)
        $surfaceWidth = [int]$modMetadata.surface[0]
        $surfaceHeight = [int]$modMetadata.surface[1]
        $mapHeight = [int]$modMetadata.map_viewport[1]
        $cameraLeft = [int]$modMetadata.camera_left
        $cameraTop = [int]$modMetadata.camera_top
        $candidateWidth = $surfaceWidth
        $candidateHeight = $surfaceHeight
        if ($TiledModernViewport) {
            if ($surfaceWidth -ne 1024 -or $surfaceHeight -ne 768) {
                throw (
                    "Tiled reference for $levelId must retain the safe " +
                    '1024x768 stable-MOD surface.')
            }
            $levelManifestPath = Join-Path $remakeRoot (
                "LocalAssets\converted\levels\$levelId\level.json")
            if (-not (Test-Path -LiteralPath $levelManifestPath -PathType Leaf)) {
                throw "Converted level manifest is missing: $levelManifestPath"
            }
            $levelManifest = Get-Content -LiteralPath $levelManifestPath `
                -Raw -Encoding UTF8 | ConvertFrom-Json
            $worldWidth = [int]$levelManifest.world_size.width
            $worldHeight = [int]$levelManifest.world_size.height
            if ($worldWidth -lt $Width -or $worldHeight -lt $Height) {
                throw (
                    "$levelId world ${worldWidth}x${worldHeight} is smaller " +
                    "than requested viewport ${Width}x${Height}.")
            }
            $cameraLeft = [Math]::Max(
                0,
                [Math]::Min($cameraLeft, $worldWidth - $Width))
            $cameraTop = [Math]::Max(
                0,
                [Math]::Min($cameraTop, $worldHeight - $Height))
            $candidateWidth = $Width
            $candidateHeight = $Height
        }

        Write-Host (
            "Capturing Remake for {0} at original camera ({1},{2})..." -f
            $levelId, $cameraLeft, $cameraTop)
        $remakeImage = Join-Path $remakeOutput 'gameplay-world.png'
        $remakeMetadata = Join-Path $remakeOutput 'visual-capture.json'
        $godotLog = Join-Path $remakeOutput 'godot.log'
        $godotArguments = @(
            '--path',
            $gameRoot,
            '--windowed',
            '--resolution',
            "$($candidateWidth)x$($candidateHeight)",
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
            "--viewport-width=$candidateWidth",
            "--viewport-height=$candidateHeight",
            '--skip-briefing',
            '--skip-level-selector')
        if ($IncludeUi) {
            $godotArguments += '--include-ui'
        }
        & $GodotExecutable $godotArguments
        if ($LASTEXITCODE -ne 0) {
            throw "Remake visual probe failed for $levelId."
        }

        if ($TiledModernViewport) {
            $xOffsets = @(
                0,
                ($candidateWidth - $surfaceWidth)) |
                Sort-Object -Unique
            $yOffsets = @(
                0,
                ($candidateHeight - $mapHeight)) |
                Sort-Object -Unique
            $tileResults = [Collections.Generic.List[object]]::new()
            foreach ($offsetY in $yOffsets) {
                foreach ($offsetX in $xOffsets) {
                    $desiredCameraLeft = $cameraLeft + $offsetX
                    $desiredCameraTop = $cameraTop + $offsetY
                    $tileMetadata = $null
                    if (
                        $desiredCameraLeft -eq
                            [int]$modMetadata.camera_left -and
                        $desiredCameraTop -eq
                            [int]$modMetadata.camera_top
                    ) {
                        $tileMetadata = $modMetadata
                    }
                    else {
                        $tileOutput = Join-Path $modOutput (
                            "tile-$offsetX-$offsetY")
                        Write-Host (
                            (
                                'Capturing stable MOD tile for {0} at ' +
                                'camera ({1},{2})...'
                            ) -f
                            $levelId,
                            $desiredCameraLeft,
                            $desiredCameraTop)
                        $tileMetadata = Invoke-StableModVisualCapture `
                            -SelectorLevel $level `
                            -CaptureOutput $tileOutput `
                            -CameraWorldX (
                                $desiredCameraLeft +
                                [int]($surfaceWidth / 2)) `
                            -CameraWorldY (
                                $desiredCameraTop +
                                [int]($mapHeight / 2))
                    }
                    $actualCameraLeft =
                        [int]$tileMetadata.camera_left
                    $actualCameraTop =
                        [int]$tileMetadata.camera_top
                    # An out-of-range request can clamp back to the level's
                    # already-rendered startup camera. Reuse that pristine
                    # primary surface instead of asking the 2001 strip
                    # renderer to perform a no-op jump, which corrupts m009's
                    # non-zero viewport-origin cache.
                    if (
                        $actualCameraLeft -eq
                            [int]$modMetadata.camera_left -and
                        $actualCameraTop -eq
                            [int]$modMetadata.camera_top
                    ) {
                        $tileMetadata = $modMetadata
                    }
                    $actualOffsetX = $actualCameraLeft - $cameraLeft
                    $actualOffsetY = $actualCameraTop - $cameraTop
                    if (
                        $actualOffsetX -lt 0 -or
                        $actualOffsetY -lt 0 -or
                        $actualOffsetX + $surfaceWidth -gt
                            $candidateWidth -or
                        $actualOffsetY + $mapHeight -gt
                            $candidateHeight
                    ) {
                        throw (
                            "$levelId MOD tile camera " +
                            "$actualCameraLeft,$actualCameraTop cannot be " +
                            'mapped inside the Remake viewport rooted at ' +
                            "$cameraLeft,$cameraTop.")
                    }
                    $tileComparisonOutput = Join-Path $comparisonOutput (
                        "tile-$offsetX-$offsetY")
                    # The original overlays portraits/status text in the
                    # first 48 rows of the primary world surface. Remake
                    # world-only captures intentionally hide CanvasLayer UI,
                    # so compare only the shared map pixels.
                    $tileComparison = & (
                        Join-Path $PSScriptRoot 'Compare-VisualParity.ps1') `
                        -ReferenceImage (
                            [IO.Path]::GetFullPath(
                                [string]$tileMetadata.screenshot)) `
                        -CandidateImage $remakeImage `
                        -CandidateLeft $actualOffsetX `
                        -CandidateTop $actualOffsetY `
                        -OutputDirectory $tileComparisonOutput `
                        -RegionTop $worldRegionTop `
                        -RegionBottom $mapHeight `
                        -MaximumMeanAbsoluteError (
                            $thresholds.maximum_mean_absolute_error) `
                        -MinimumNearMatchRatio (
                            $thresholds.minimum_near_match_ratio) `
                        -MinimumEdgeCorrelation (
                            $thresholds.minimum_edge_correlation) `
                        -MaximumBlackHoleRatio (
                            $thresholds.maximum_black_hole_ratio) `
                        -AllowMismatch
                    $tileResults.Add([pscustomobject][ordered]@{
                        offset = @($actualOffsetX, $actualOffsetY)
                        requested_offset = @($offsetX, $offsetY)
                        camera = @(
                            $actualCameraLeft,
                            $actualCameraTop)
                        requested_camera = @(
                            $desiredCameraLeft,
                            $desiredCameraTop)
                        original_camera_clamped = (
                            $actualCameraLeft -ne $desiredCameraLeft -or
                            $actualCameraTop -ne $desiredCameraTop)
                        metrics = $tileComparison.metrics
                        mod_image = [string]$tileMetadata.screenshot
                        comparison = Join-Path `
                            $tileComparisonOutput 'visual-parity.json'
                        passed = [bool]$tileComparison.passed
                    })
                }
            }
            $metrics = [pscustomobject][ordered]@{
                mean_absolute_error = [double](
                    $tileResults.metrics.mean_absolute_error |
                    Measure-Object -Maximum).Maximum
                near_match_ratio = [double](
                    $tileResults.metrics.near_match_ratio |
                    Measure-Object -Minimum).Minimum
                edge_correlation = [double](
                    $tileResults.metrics.edge_correlation |
                    Measure-Object -Minimum).Minimum
                black_hole_ratio = [double](
                    $tileResults.metrics.black_hole_ratio |
                    Measure-Object -Maximum).Maximum
            }
            $levelPassed = @(
                $tileResults |
                Where-Object { -not $_.passed }).Count -eq 0
            $results.Add([pscustomobject][ordered]@{
                level_id = $levelId
                selector_level = $level
                camera = @($cameraLeft, $cameraTop)
                map_viewport = @($candidateWidth, $candidateHeight)
                metrics = $metrics
                tiles = @($tileResults)
                remake_image = $remakeImage
                passed = $levelPassed
            })
            continue
        }

        $comparisonBottom = if ($IncludeUi) {
            $surfaceHeight
        }
        else {
            $mapHeight
        }
        $comparison = & (
            Join-Path $PSScriptRoot 'Compare-VisualParity.ps1') `
            -ReferenceImage $modImage `
            -CandidateImage $remakeImage `
            -OutputDirectory $comparisonOutput `
            -RegionTop $worldRegionTop `
            -RegionBottom $comparisonBottom `
            -MaximumMeanAbsoluteError (
                $thresholds.maximum_mean_absolute_error) `
            -MinimumNearMatchRatio (
                $thresholds.minimum_near_match_ratio) `
            -MinimumEdgeCorrelation (
                $thresholds.minimum_edge_correlation) `
            -MaximumBlackHoleRatio (
                $thresholds.maximum_black_hole_ratio) `
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
    foreach ($name in $expandedEnvironmentNames) {
        [Environment]::SetEnvironmentVariable(
            $name,
            $previousExpandedEnvironment[$name],
            [EnvironmentVariableTarget]::Process)
    }
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
    requested_resolution = @($Width, $Height)
    expanded_viewport = [bool]$ExpandedViewport
    tiled_mod_reference = [bool]$TiledModernViewport
    includes_ui = [bool]$IncludeUi
    input_isolation = (
        'stable-mod-read-only-RGB565-surface; ' +
        'remake-offscreen-window; no global input')
    system_cursor_calls = 0
    global_focus_calls = 0
    comparison_region = [pscustomobject][ordered]@{
        top = $worldRegionTop
        bottom_policy = if ($IncludeUi) {
            'surface_height'
        }
        else {
            'stable_mod_map_viewport_height'
        }
    }
    thresholds = $thresholds
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
    "Requested profile: $($Width)x$($Height); expanded viewport: " +
    "$([bool]$ExpandedViewport); tiled MOD reference: " +
    "$([bool]$TiledModernViewport); UI included: $([bool]$IncludeUi).")
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
