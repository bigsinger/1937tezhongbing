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

Write-Host (
    'Original overlay visual baselines passed: F1, item inventory, weapon ' +
    'inventory, pause menu, failure menu and minimap; no original screenshots committed.')
