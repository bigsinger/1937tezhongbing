[CmdletBinding()]
param(
    [string]$BaselinePath = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$remakeRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if ([string]::IsNullOrWhiteSpace($BaselinePath)) {
    $BaselinePath = Join-Path $remakeRoot (
        'game\data\original_hud_visual_parity_baselines.json')
}
$BaselinePath = (Resolve-Path -LiteralPath $BaselinePath).Path
$raw = Get-Content -LiteralPath $BaselinePath -Raw -Encoding UTF8
if ($raw -match '(?i)[A-Z]:[\\/]' -or
    $raw -match '(?i)\.(png|jpe?g|bmp|tga)"') {
    throw 'Original HUD visual baseline contains a local path or image name.'
}
$baseline = $raw | ConvertFrom-Json
if ([int]$baseline.schema_version -ne 1 -or
    [string]$baseline.baseline_id -cne
        'stable-mod-original-hud-visual-parity-v1' -or
    [string]$baseline.content_profile -cne
        'repository-mod-12-level-20260729' -or
    [bool]$baseline.original_binary_images_committed -or
    -not [bool]$baseline.passed) {
    throw 'Original HUD visual baseline identity or completion is invalid.'
}
if ([string]$baseline.input_isolation -notmatch 'no global') {
    throw 'Original HUD visual baseline does not prove input isolation.'
}

$expected = [ordered]@{
    top_m000_idle = @('native_status_crop', 50, 20)
    top_m001_ammo = @('native_status_crop', 150, 20)
    bottom_1024_full = @('complete_bottom_bar', 1024, 62)
    bottom_1920_left = @(
        'native_left_island_after_width_extension', 512, 62)
    bottom_1920_actions = @(
        'native_right_action_island_after_width_extension', 150, 50)
}
$samples = @($baseline.samples)
if ($samples.Count -ne $expected.Count) {
    throw 'Original HUD visual baseline must contain five samples.'
}
foreach ($entry in $expected.GetEnumerator()) {
    $matches = @($samples | Where-Object sample -CEQ $entry.Key)
    if ($matches.Count -ne 1) {
        throw "Original HUD sample is missing or duplicated: $($entry.Key)"
    }
    $sample = $matches[0]
    if (-not [bool]$sample.passed -or
        [string]$sample.comparison_scope -cne [string]$entry.Value[0] -or
        [int]$sample.dimensions[0] -ne [int]$entry.Value[1] -or
        [int]$sample.dimensions[1] -ne [int]$entry.Value[2]) {
        throw "Original HUD sample geometry drifted: $($entry.Key)"
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
    'Original HUD visual baselines passed: top ammo cells, complete 1024 ' +
    'bottom bar and native 1920 control islands; no original screenshots committed.')
