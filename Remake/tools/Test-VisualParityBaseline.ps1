[CmdletBinding()]
param(
    [string]$BaselinePath = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$remakeRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if ([string]::IsNullOrWhiteSpace($BaselinePath)) {
    $BaselinePath = Join-Path $remakeRoot (
        'game\data\visual_parity_baselines.json')
}
$BaselinePath = (Resolve-Path -LiteralPath $BaselinePath).Path
$raw = Get-Content -LiteralPath $BaselinePath -Raw -Encoding UTF8
if (
    $raw -match '(?i)[A-Z]:[\\/]' -or
    $raw -match '(?i)\.(png|jpe?g|bmp|tga)"'
) {
    throw 'Visual parity baseline contains a local path or binary image name.'
}
$baseline = $raw | ConvertFrom-Json
if ([int]$baseline.schema_version -ne 1 -or
    -not [bool]$baseline.passed) {
    throw 'Visual parity baseline schema or completion flag is invalid.'
}
if ([bool]$baseline.original_binary_images_committed) {
    throw 'Visual parity baseline must not commit original screenshots.'
}

$requiredProfiles = @{
    'legacy_1024x768_world' = 12
    'modern_1920x1080_tiled_world' = 48
}
$profiles = @($baseline.profiles)
foreach ($entry in $requiredProfiles.GetEnumerator()) {
    $matches = @($profiles | Where-Object id -eq $entry.Key)
    if ($matches.Count -ne 1) {
        throw "Visual parity profile is missing or duplicated: $($entry.Key)"
    }
    $profile = $matches[0]
    if (-not [bool]$profile.passed -or
        [int]$profile.level_count -ne 12 -or
        [int]$profile.sample_count -ne [int]$entry.Value) {
        throw "Visual parity profile counts are invalid: $($entry.Key)"
    }
    if ([int]$profile.comparison_region.top -ne 48 -or
        [string]$profile.comparison_region.bottom_policy -ne
            'stable_mod_map_viewport_height') {
        throw "Visual parity region policy drifted: $($entry.Key)"
    }

    $thresholds = $profile.thresholds
    $expectedIds = @(0..11 | ForEach-Object { 'm{0:D3}' -f $_ })
    $levels = @($profile.levels | Sort-Object selector_level)
    if (($levels.id -join ',') -ne ($expectedIds -join ',')) {
        throw "Visual parity level roster drifted: $($entry.Key)"
    }
    $observedSamples = 0
    foreach ($level in $levels) {
        if (-not [bool]$level.passed) {
            throw "$($entry.Key)/$($level.id) is not marked passed."
        }
        $samples = @($level.samples)
        $expectedPerLevel = if (
            [bool]$profile.tiled_mod_reference
        ) {
            4
        }
        else {
            1
        }
        if ($samples.Count -ne $expectedPerLevel) {
            throw (
                "$($entry.Key)/$($level.id) has $($samples.Count) " +
                "samples, expected $expectedPerLevel.")
        }
        $observedSamples += $samples.Count
        foreach ($sample in $samples) {
            if (-not [bool]$sample.passed) {
                throw "$($entry.Key)/$($level.id) has a failed sample."
            }
            $offsetX = [int]$sample.candidate_offset[0]
            $offsetY = [int]$sample.candidate_offset[1]
            if (
                [int]$sample.reference_camera[0] -ne
                    [int]$level.camera[0] + $offsetX -or
                [int]$sample.reference_camera[1] -ne
                    [int]$level.camera[1] + $offsetY
            ) {
                throw (
                    "$($entry.Key)/$($level.id) camera-to-crop mapping " +
                    'is inconsistent.')
            }
            $metrics = $sample.metrics
            if (
                [double]$metrics.mean_absolute_error -gt
                    [double]$thresholds.maximum_mean_absolute_error -or
                [double]$metrics.near_match_ratio -lt
                    [double]$thresholds.minimum_near_match_ratio -or
                [double]$metrics.edge_correlation -lt
                    [double]$thresholds.minimum_edge_correlation -or
                [double]$metrics.black_hole_ratio -gt
                    [double]$thresholds.maximum_black_hole_ratio
            ) {
                throw (
                    "$($entry.Key)/$($level.id) exceeds visual parity " +
                    'thresholds.')
            }
        }
    }
    if ($observedSamples -ne [int]$profile.sample_count) {
        throw "Visual parity sample total drifted: $($entry.Key)"
    }
}

Write-Host (
    'Visual parity baselines passed: 12 legacy samples and ' +
    '48 modern-viewport tiles; no original screenshots committed.')
