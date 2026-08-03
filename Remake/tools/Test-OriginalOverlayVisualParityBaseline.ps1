[CmdletBinding()]
param(
    [string]$BaselinePath = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$remakeRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if ([string]::IsNullOrWhiteSpace($BaselinePath)) {
    $BaselinePath = Join-Path $remakeRoot (
        'game\data\original_overlay_visual_parity_baselines.json')
}
$BaselinePath = (Resolve-Path -LiteralPath $BaselinePath).Path
$raw = Get-Content -LiteralPath $BaselinePath -Raw -Encoding UTF8
if ($raw -match '(?i)[A-Z]:[\\/]' -or
    $raw -match '(?i)\.(png|jpe?g|bmp|tga)"') {
    throw 'Original overlay visual baseline contains a local path or image name.'
}
$baseline = $raw | ConvertFrom-Json
if ([int]$baseline.schema_version -ne 1 -or
    [string]$baseline.content_profile -cne
        'repository-mod-12-level-20260729' -or
    [bool]$baseline.original_binary_images_committed -or
    -not [bool]$baseline.passed) {
    throw 'Original overlay visual baseline identity or completion is invalid.'
}
if ([string]$baseline.input_isolation -notmatch 'no global') {
    throw 'Original overlay visual baseline does not prove input isolation.'
}

$captureToolPath = Join-Path $PSScriptRoot 'Capture-ModernOverlayParity.ps1'
$probePath = Join-Path $remakeRoot 'game\tests\visual_parity_probe.gd'
if (-not (Test-Path -LiteralPath $captureToolPath -PathType Leaf) -or
    -not (Test-Path -LiteralPath $probePath -PathType Leaf)) {
    throw 'Modern overlay capture tool or target-viewport probe is missing.'
}
$captureToolSource = Get-Content -LiteralPath $captureToolPath `
    -Raw -Encoding UTF8
$probeSource = Get-Content -LiteralPath $probePath -Raw -Encoding UTF8
$forbiddenPointerApis = (
    '(?i)SetCursorPos|mouse_event|SendInput|ClipCursor|' +
    'SetForegroundWindow|Windows\.Forms\.Cursor|WScript\.Shell')
if ($captureToolSource -match $forbiddenPointerApis -or
    $probeSource -match $forbiddenPointerApis -or
    $captureToolSource -notmatch '--isolate-overlay' -or
    $probeSource -notmatch 'OverlayIsolationBackdrop' -or
    $probeSource -notmatch 'window_set_position\(Vector2i\(30000, 30000\)\)') {
    throw 'Modern overlay capture no longer proves offscreen pointer isolation.'
}

$expected = [ordered]@{
    help = @('full_surface', 1024, 768, 'world_or_full_overlay')
    items = @('native_overlay_crop', 276, 421, 'rgb565_original_inventory_overlay')
    weapons = @('native_overlay_crop', 276, 421, 'rgb565_original_inventory_overlay')
    pause = @('native_overlay_crop', 132, 318, 'world_or_full_overlay')
    failure = @('native_overlay_crop', 282, 94, 'rgb565_original_failure_dynamic_text')
    minimap = @('native_overlay_crop', 336, 166, 'world_or_full_overlay')
}
$samples = @($baseline.samples)
if ($samples.Count -ne $expected.Count) {
    throw 'Original overlay visual baseline must contain six samples.'
}
foreach ($entry in $expected.GetEnumerator()) {
    $matches = @($samples | Where-Object overlay -CEQ $entry.Key)
    if ($matches.Count -ne 1) {
        throw "Original overlay sample is missing or duplicated: $($entry.Key)"
    }
    $sample = $matches[0]
    if (-not [bool]$sample.passed -or
        [string]$sample.comparison_scope -cne [string]$entry.Value[0] -or
        [int]$sample.dimensions[0] -ne [int]$entry.Value[1] -or
        [int]$sample.dimensions[1] -ne [int]$entry.Value[2] -or
        [string]$sample.threshold_profile -cne [string]$entry.Value[3]) {
        throw "Original overlay sample geometry drifted: $($entry.Key)"
    }
    foreach ($hashName in @('stable_mod_sha256', 'remake_sha256')) {
        if ([string]$sample.$hashName -cnotmatch '^[0-9A-F]{64}$') {
            throw "$($entry.Key) has an invalid $hashName."
        }
    }
    $metrics = $sample.metrics
    $thresholds = $sample.thresholds
    if ([double]$metrics.mean_absolute_error -gt
            [double]$thresholds.maximum_mean_absolute_error -or
        [double]$metrics.near_match_ratio -lt
            [double]$thresholds.minimum_near_match_ratio -or
        [double]$metrics.edge_correlation -lt
            [double]$thresholds.minimum_edge_correlation -or
        [double]$metrics.black_hole_ratio -gt
            [double]$thresholds.maximum_black_hole_ratio) {
        throw "$($entry.Key) exceeds its versioned visual parity thresholds."
    }
}

$modern = $baseline.modern_viewport_calibration
if ($null -eq $modern -or
    [int]$modern.schema_version -ne 1 -or
    -not [bool]$modern.passed -or
    [bool]$modern.original_binary_images_committed -or
    [string]$modern.representative_level -cne 'm000' -or
    [string]$modern.input_isolation -notmatch 'no global' -or
    [string]$modern.input_isolation -notmatch 'no .*mission playthrough' -or
    [string]$modern.source_chain -notmatch 'stable-MOD') {
    throw 'Modern overlay viewport calibration identity is invalid.'
}
if (@($modern.reference_viewport).Count -ne 2 -or
    [int]$modern.reference_viewport[0] -ne 1024 -or
    [int]$modern.reference_viewport[1] -ne 768 -or
    @($modern.target_viewport).Count -ne 2 -or
    [int]$modern.target_viewport[0] -ne 1920 -or
    [int]$modern.target_viewport[1] -ne 1080) {
    throw 'Modern overlay calibration viewport identity drifted.'
}

$modernExpected = [ordered]@{
    items = @($true, 276, 421, 748, 285, 1644, 597,
        'exact_isolated_native_overlay')
    weapons = @($true, 276, 421, 748, 285, 1644, 597,
        'exact_isolated_native_overlay')
    minimap = @($false, 336, 166, 688, 540, 1584, 852,
        'modern_minimap_camera_extent')
    help = @($false, 640, 480, 192, 144, 640, 300,
        'exact_opaque_native_overlay')
    failure = @($true, 282, 94, 354, 325, 802, 481,
        'exact_isolated_native_overlay')
}
$modernSamples = @($modern.samples)
if ($modernSamples.Count -ne $modernExpected.Count) {
    throw 'Modern overlay calibration must contain five native samples.'
}
foreach ($entry in $modernExpected.GetEnumerator()) {
    $matches = @($modernSamples | Where-Object overlay -CEQ $entry.Key)
    if ($matches.Count -ne 1) {
        throw "Modern overlay sample is missing or duplicated: $($entry.Key)"
    }
    $sample = $matches[0]
    $shape = $entry.Value
    if (-not [bool]$sample.passed -or
        [bool]$sample.isolated_backdrop -ne [bool]$shape[0] -or
        [string]$sample.comparison_scope -cne 'native_overlay_crop' -or
        [int]$sample.dimensions[0] -ne [int]$shape[1] -or
        [int]$sample.dimensions[1] -ne [int]$shape[2] -or
        [int]$sample.reference_origin[0] -ne [int]$shape[3] -or
        [int]$sample.reference_origin[1] -ne [int]$shape[4] -or
        [int]$sample.target_origin[0] -ne [int]$shape[5] -or
        [int]$sample.target_origin[1] -ne [int]$shape[6] -or
        [string]$sample.threshold_profile -cne [string]$shape[7]) {
        throw "Modern overlay sample geometry drifted: $($entry.Key)"
    }
    foreach ($hashName in @('reference_sha256', 'target_sha256')) {
        if ([string]$sample.$hashName -cnotmatch '^[0-9A-F]{64}$') {
            throw "$($entry.Key) has an invalid modern $hashName."
        }
    }
    $metrics = $sample.metrics
    $thresholds = $sample.thresholds
    if ([double]$metrics.mean_absolute_error -gt
            [double]$thresholds.maximum_mean_absolute_error -or
        [double]$metrics.near_match_ratio -lt
            [double]$thresholds.minimum_near_match_ratio -or
        [double]$metrics.edge_correlation -lt
            [double]$thresholds.minimum_edge_correlation -or
        [double]$metrics.black_hole_ratio -gt
            [double]$thresholds.maximum_black_hole_ratio) {
        throw "$($entry.Key) exceeds modern viewport parity thresholds."
    }
    if ([string]$sample.threshold_profile -match '^exact_' -and
        ([string]$sample.reference_sha256 -cne [string]$sample.target_sha256 -or
            [double]$metrics.mean_absolute_error -ne 0.0 -or
            [double]$metrics.near_match_ratio -ne 1.0 -or
            [double]$metrics.edge_correlation -ne 1.0 -or
            [double]$metrics.black_hole_ratio -ne 0.0)) {
        throw "$($entry.Key) is not pixel-exact across native viewports."
    }
}

Write-Host (
    'Original overlay visual baselines passed: F1, item inventory, weapon ' +
    'inventory, pause menu, failure menu and minimap; 1920x1080 native ' +
    'overlay calibration passed; no original screenshots committed.')
