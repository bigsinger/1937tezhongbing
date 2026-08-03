[CmdletBinding()]
param(
    [string]$GodotExecutable = '',
    [string]$OutputDirectory = '',
    [switch]$ReuseCaptures
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$remakeRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$gameRoot = Join-Path $remakeRoot 'game'
$assetBaselinePath = Join-Path $gameRoot (
    'data\original_overlay_asset_baseline.json')
$assetBaseline = Get-Content -LiteralPath $assetBaselinePath `
    -Raw -Encoding UTF8 | ConvertFrom-Json

if ([string]::IsNullOrWhiteSpace($GodotExecutable) -and
    -not [string]::IsNullOrWhiteSpace($env:GODOT4)) {
    $GodotExecutable = $env:GODOT4
}
if ([string]::IsNullOrWhiteSpace($GodotExecutable)) {
    $candidates = @(
        'D:\Godot\Godot_v4.7.1-stable_win64_console.exe',
        'D:\Godot\Godot_v4.7.1-stable_win64.exe'
    )
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            $GodotExecutable = $candidate
            break
        }
    }
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
    throw 'Godot was not found. Pass -GodotExecutable.'
}
$GodotExecutable = (Resolve-Path -LiteralPath $GodotExecutable).Path
if (-not $GodotExecutable.EndsWith(
        '_console.exe', [StringComparison]::OrdinalIgnoreCase)) {
    $consoleExecutable = Join-Path `
        ([IO.Path]::GetDirectoryName($GodotExecutable)) `
        (([IO.Path]::GetFileNameWithoutExtension($GodotExecutable)) +
            '_console.exe')
    if (Test-Path -LiteralPath $consoleExecutable -PathType Leaf) {
        $GodotExecutable = $consoleExecutable
    }
}

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $OutputDirectory = Join-Path $remakeRoot (
        "LocalAssets\qa\modern-overlay-parity-$stamp")
}
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
[IO.Directory]::CreateDirectory($OutputDirectory) | Out-Null

$convertedLevel = Join-Path $remakeRoot (
    'LocalAssets\converted\levels\m000\level.json')
if (-not (Test-Path -LiteralPath $convertedLevel -PathType Leaf)) {
    throw (
        'The real converted m000 assets are missing. Run Import-OriginalAssets.ps1 ' +
        'before this local-only calibration.')
}

if (-not ('Mission1937ModernOverlayCropV1' -as [type])) {
    Add-Type -ReferencedAssemblies @(
        'System.dll',
        'System.Drawing.dll'
    ) -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Imaging;

public static class Mission1937ModernOverlayCropV1
{
    public static void Save(
        string sourcePath,
        string outputPath,
        int x,
        int y,
        int width,
        int height)
    {
        using (var source = new Bitmap(sourcePath))
        {
            var bounds = new Rectangle(x, y, width, height);
            if (x < 0 || y < 0 || bounds.Right > source.Width ||
                bounds.Bottom > source.Height)
                throw new InvalidOperationException(
                    "Overlay crop lies outside the captured viewport.");
            using (var crop = source.Clone(bounds, PixelFormat.Format24bppRgb))
                crop.Save(outputPath, ImageFormat.Png);
        }
    }
}
'@
}

$referenceViewport = @($assetBaseline.viewports | Where-Object {
    [int]$_.width -eq 1024 -and [int]$_.height -eq 768
})
$modernViewport = @($assetBaseline.viewports | Where-Object {
    [int]$_.width -eq 1920 -and [int]$_.height -eq 1080
})
if ($referenceViewport.Count -ne 1 -or $modernViewport.Count -ne 1) {
    throw 'Overlay geometry baseline lacks the 1024x768 or 1920x1080 viewport.'
}

$specifications = @(
    [pscustomobject][ordered]@{
        overlay = 'items'
        isolated = $true
        rect_property = 'inventory_rect'
        threshold_profile = 'exact_isolated_native_overlay'
        maximum_mean_absolute_error = 0.0
        minimum_near_match_ratio = 1.0
        minimum_edge_correlation = 1.0
        maximum_black_hole_ratio = 0.0
    },
    [pscustomobject][ordered]@{
        overlay = 'weapons'
        isolated = $true
        rect_property = 'inventory_rect'
        threshold_profile = 'exact_isolated_native_overlay'
        maximum_mean_absolute_error = 0.0
        minimum_near_match_ratio = 1.0
        minimum_edge_correlation = 1.0
        maximum_black_hole_ratio = 0.0
    },
    [pscustomobject][ordered]@{
        overlay = 'minimap'
        isolated = $false
        rect_property = ''
        threshold_profile = 'modern_minimap_camera_extent'
        maximum_mean_absolute_error = 1.25
        minimum_near_match_ratio = 0.99
        minimum_edge_correlation = 0.95
        maximum_black_hole_ratio = 0.0001
    },
    [pscustomobject][ordered]@{
        overlay = 'help'
        isolated = $false
        rect_property = 'help_rect'
        threshold_profile = 'exact_opaque_native_overlay'
        maximum_mean_absolute_error = 0.0
        minimum_near_match_ratio = 1.0
        minimum_edge_correlation = 1.0
        maximum_black_hole_ratio = 0.0
    },
    [pscustomobject][ordered]@{
        overlay = 'failure'
        isolated = $true
        rect_property = 'failure_menu_rect'
        threshold_profile = 'exact_isolated_native_overlay'
        maximum_mean_absolute_error = 0.0
        minimum_near_match_ratio = 1.0
        minimum_edge_correlation = 1.0
        maximum_black_hole_ratio = 0.0
    }
)

function Get-OverlayRect {
    param(
        [Parameter(Mandatory)]$Specification,
        [Parameter(Mandatory)]$Viewport
    )
    if ([string]$Specification.overlay -eq 'minimap') {
        $map = @($assetBaseline.minimaps | Where-Object {
            [string]$_.level_id -ceq 'm000'
        })
        if ($map.Count -ne 1) {
            throw 'The m000 minimap geometry is missing or duplicated.'
        }
        $width = [int]($map[0].width)
        $height = [int]($map[0].height)
        $left = [int]($Viewport.width) - $width
        $top = [int]($Viewport.height) - 62 - $height
        return @($left, $top, $width, $height)
    }
    $propertyName = [string]$Specification.rect_property
    return @($Viewport.$propertyName)
}

function Invoke-OverlayCapture {
    param(
        [Parameter(Mandatory)]$Specification,
        [Parameter(Mandatory)]$Viewport
    )
    $width = [int]($Viewport.width)
    $height = [int]($Viewport.height)
    $viewportDirectory = Join-Path $OutputDirectory (
        '{0}x{1}' -f $width, $height)
    [IO.Directory]::CreateDirectory($viewportDirectory) | Out-Null
    $suffix = if ([bool]$Specification.isolated) { '-isolated' } else { '' }
    $stem = [string]$Specification.overlay + $suffix
    $imagePath = Join-Path $viewportDirectory ($stem + '.png')
    $metadataPath = Join-Path $viewportDirectory ($stem + '.json')
    $logPath = Join-Path $viewportDirectory ($stem + '.log')
    if ($ReuseCaptures -and
        (Test-Path -LiteralPath $imagePath -PathType Leaf) -and
        (Test-Path -LiteralPath $metadataPath -PathType Leaf)) {
        $existingMetadata = Get-Content -LiteralPath $metadataPath `
            -Raw -Encoding UTF8 | ConvertFrom-Json
        if ([bool]$existingMetadata.passed -and
            [string]$existingMetadata.overlay -ceq
                [string]$Specification.overlay -and
            [bool]$existingMetadata.isolated_backdrop -eq
                [bool]$Specification.isolated -and
            [int]($existingMetadata.viewport[0]) -eq $width -and
            [int]($existingMetadata.viewport[1]) -eq $height) {
            Write-Host (
                'Reusing {0} at {1}x{2}...' -f
                $Specification.overlay, $width, $height)
            return $imagePath
        }
    }
    $arguments = @(
        '--path',
        $gameRoot,
        '--windowed',
        '--resolution',
        "${width}x${height}",
        '--position',
        '3000,100',
        '--max-fps',
        '60',
        '--disable-vsync',
        '--rendering-method',
        'gl_compatibility',
        '--log-file',
        $logPath,
        '--script',
        'res://tests/visual_parity_probe.gd',
        '--',
        "--output=$($imagePath.Replace('\', '/'))",
        "--metadata=$($metadataPath.Replace('\', '/'))",
        '--level-id=m000',
        '--camera-left=0',
        '--camera-top=0',
        "--viewport-width=$width",
        "--viewport-height=$height",
        "--overlay=$([string]$Specification.overlay)",
        '--skip-briefing',
        '--skip-level-selector'
    )
    if ([bool]$Specification.isolated) {
        $arguments += '--isolate-overlay'
    }
    Write-Host (
        'Capturing {0} at {1}x{2} (isolated={3})...' -f
        $Specification.overlay, $width, $height,
        [bool]$Specification.isolated)
    & $GodotExecutable $arguments | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw (
            "Godot overlay capture failed: $($Specification.overlay) " +
            "${width}x${height}.")
    }
    $metadata = Get-Content -LiteralPath $metadataPath `
        -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not [bool]$metadata.passed -or
        [bool]$metadata.isolated_backdrop -ne [bool]$Specification.isolated) {
        throw "Overlay capture metadata is invalid: $metadataPath"
    }
    return $imagePath
}

$results = [Collections.Generic.List[object]]::new()
$cropsDirectory = Join-Path $OutputDirectory 'crops'
[IO.Directory]::CreateDirectory($cropsDirectory) | Out-Null
foreach ($specification in $specifications) {
    $referenceImage = Invoke-OverlayCapture `
        -Specification $specification -Viewport ($referenceViewport[0])
    $modernImage = Invoke-OverlayCapture `
        -Specification $specification -Viewport ($modernViewport[0])
    $referenceRect = @(Get-OverlayRect `
        -Specification $specification -Viewport ($referenceViewport[0]))
    $modernRect = @(Get-OverlayRect `
        -Specification $specification -Viewport ($modernViewport[0]))
    if ([int]($referenceRect[2]) -ne [int]($modernRect[2]) -or
        [int]($referenceRect[3]) -ne [int]($modernRect[3])) {
        throw "Overlay dimensions drifted: $($specification.overlay)."
    }
    $referenceCrop = Join-Path $cropsDirectory (
        "$($specification.overlay)-1024x768.png")
    $modernCrop = Join-Path $cropsDirectory (
        "$($specification.overlay)-1920x1080.png")
    [Mission1937ModernOverlayCropV1]::Save(
        $referenceImage,
        $referenceCrop,
        [int]($referenceRect[0]),
        [int]($referenceRect[1]),
        [int]($referenceRect[2]),
        [int]($referenceRect[3]))
    [Mission1937ModernOverlayCropV1]::Save(
        $modernImage,
        $modernCrop,
        [int]($modernRect[0]),
        [int]($modernRect[1]),
        [int]($modernRect[2]),
        [int]($modernRect[3]))
    $comparisonDirectory = Join-Path $OutputDirectory (
        "comparison-$($specification.overlay)")
    $comparison = & (Join-Path $PSScriptRoot 'Compare-VisualParity.ps1') `
        -ReferenceImage $referenceCrop `
        -CandidateImage $modernCrop `
        -OutputDirectory $comparisonDirectory `
        -RegionTop 0 `
        -RegionBottom ([int]($referenceRect[3])) `
        -MaximumMeanAbsoluteError (
            [double]$specification.maximum_mean_absolute_error) `
        -MinimumNearMatchRatio (
            [double]$specification.minimum_near_match_ratio) `
        -MinimumEdgeCorrelation (
            [double]$specification.minimum_edge_correlation) `
        -MaximumBlackHoleRatio (
            [double]$specification.maximum_black_hole_ratio) `
        -AllowMismatch
    $results.Add([pscustomobject][ordered]@{
        overlay = [string]$specification.overlay
        isolated_backdrop = [bool]$specification.isolated
        comparison_scope = 'native_overlay_crop'
        dimensions = @([int]($referenceRect[2]), [int]($referenceRect[3]))
        reference_origin = @([int]($referenceRect[0]), [int]($referenceRect[1]))
        target_origin = @([int]($modernRect[0]), [int]($modernRect[1]))
        threshold_profile = [string]$specification.threshold_profile
        metrics = $comparison.metrics
        thresholds = $comparison.thresholds
        reference_sha256 = (Get-FileHash -LiteralPath $referenceCrop `
            -Algorithm SHA256).Hash
        target_sha256 = (Get-FileHash -LiteralPath $modernCrop `
            -Algorithm SHA256).Hash
        passed = [bool]$comparison.passed
    })
}

$passed = @($results | Where-Object { -not [bool]$_.passed }).Count -eq 0
$report = [pscustomobject][ordered]@{
    schema_version = 1
    runtime = 'remake'
    level_id = 'm000'
    reference_viewport = @(1024, 768)
    target_viewport = @(1920, 1080)
    input_isolation = (
        'target viewport texture only; no desktop capture; no global mouse, ' +
        'keyboard, focus, pointer capture or mission playthrough')
    original_binary_images_committed = $false
    samples = @($results)
    passed = $passed
}
$reportPath = Join-Path $OutputDirectory 'modern-overlay-parity.json'
$report | ConvertTo-Json -Depth 10 |
    Set-Content -LiteralPath $reportPath -Encoding UTF8
Write-Host "Modern overlay parity report: $reportPath"
if (-not $passed) {
    throw 'One or more modern overlay parity thresholds were not met.'
}
$report
