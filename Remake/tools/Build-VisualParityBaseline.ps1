[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string[]]$SummaryPath,

    [string]$OutputPath = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$remakeRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $remakeRoot (
        'game\data\visual_parity_baselines.json')
}
$OutputPath = [IO.Path]::GetFullPath($OutputPath)

function Copy-Metrics {
    param([Parameter(Mandatory)]$Metrics)

    return [pscustomobject][ordered]@{
        mean_absolute_error =
            [double]$Metrics.mean_absolute_error
        near_match_ratio =
            [double]$Metrics.near_match_ratio
        edge_correlation =
            [double]$Metrics.edge_correlation
        black_hole_ratio =
            [double]$Metrics.black_hole_ratio
    }
}

function Test-Metrics {
    param(
        [Parameter(Mandatory)]$Metrics,
        [Parameter(Mandatory)]$Thresholds,
        [Parameter(Mandatory)][string]$Context
    )

    if (
        [double]$Metrics.mean_absolute_error -gt
            [double]$Thresholds.maximum_mean_absolute_error -or
        [double]$Metrics.near_match_ratio -lt
            [double]$Thresholds.minimum_near_match_ratio -or
        [double]$Metrics.edge_correlation -lt
            [double]$Thresholds.minimum_edge_correlation -or
        [double]$Metrics.black_hole_ratio -gt
            [double]$Thresholds.maximum_black_hole_ratio
    ) {
        throw "$Context does not satisfy its visual parity thresholds."
    }
}

$profiles = [Collections.Generic.List[object]]::new()
foreach ($path in $SummaryPath) {
    $resolved = (Resolve-Path -LiteralPath $path).Path
    $summary = Get-Content -LiteralPath $resolved -Raw -Encoding UTF8 |
        ConvertFrom-Json
    if (-not [bool]$summary.passed) {
        throw "Visual parity summary did not pass: $resolved"
    }
    if (
        [int]$summary.system_cursor_calls -ne 0 -or
        [int]$summary.global_focus_calls -ne 0
    ) {
        throw "Visual parity summary used global desktop input: $resolved"
    }
    $levels = @($summary.levels)
    if ($levels.Count -ne 12) {
        throw "Visual parity summary must contain 12 levels: $resolved"
    }

    $width = [int]$summary.requested_resolution[0]
    $height = [int]$summary.requested_resolution[1]
    $tiled = [bool]$summary.tiled_mod_reference
    $includesUi = [bool]$summary.includes_ui
    $profileId = if ($tiled -and -not $includesUi) {
        "modern_${width}x${height}_tiled_world"
    }
    elseif (-not $tiled -and -not $includesUi) {
        "legacy_${width}x${height}_world"
    }
    elseif ($includesUi) {
        "legacy_${width}x${height}_ui"
    }
    else {
        "visual_${width}x${height}"
    }
    if (@($profiles | Where-Object id -eq $profileId).Count -ne 0) {
        throw "Duplicate visual parity profile: $profileId"
    }

    $thresholds = if (
        $summary.PSObject.Properties.Name -contains 'thresholds'
    ) {
        $summary.thresholds
    }
    else {
        [pscustomobject]@{
            maximum_mean_absolute_error = 6.0
            minimum_near_match_ratio = 0.92
            minimum_edge_correlation = 0.94
            maximum_black_hole_ratio = 0.003
        }
    }
    $regionTop = if (
        $summary.PSObject.Properties.Name -contains 'comparison_region'
    ) {
        [int]$summary.comparison_region.top
    }
    elseif ($tiled) {
        48
    }
    else {
        48
    }
    $regionBottomPolicy = if (
        $summary.PSObject.Properties.Name -contains 'comparison_region'
    ) {
        [string]$summary.comparison_region.bottom_policy
    }
    elseif ($includesUi) {
        'surface_height'
    }
    else {
        'stable_mod_map_viewport_height'
    }

    $baselineLevels = [Collections.Generic.List[object]]::new()
    $sampleCount = 0
    foreach ($level in $levels) {
        $samples = [Collections.Generic.List[object]]::new()
        if ($level.PSObject.Properties.Name -contains 'tiles') {
            foreach ($tile in @($level.tiles)) {
                Test-Metrics $tile.metrics $thresholds (
                    "$profileId/$($level.level_id) tile")
                $samples.Add([pscustomobject][ordered]@{
                    requested_offset = @(
                        [int]$tile.requested_offset[0],
                        [int]$tile.requested_offset[1])
                    candidate_offset = @(
                        [int]$tile.offset[0],
                        [int]$tile.offset[1])
                    requested_camera = @(
                        [int]$tile.requested_camera[0],
                        [int]$tile.requested_camera[1])
                    reference_camera = @(
                        [int]$tile.camera[0],
                        [int]$tile.camera[1])
                    original_camera_clamped =
                        [bool]$tile.original_camera_clamped
                    metrics = Copy-Metrics $tile.metrics
                    passed = [bool]$tile.passed
                })
            }
        }
        else {
            Test-Metrics $level.metrics $thresholds (
                "$profileId/$($level.level_id)")
            $samples.Add([pscustomobject][ordered]@{
                requested_offset = @(0, 0)
                candidate_offset = @(0, 0)
                requested_camera = @(
                    [int]$level.camera[0],
                    [int]$level.camera[1])
                reference_camera = @(
                    [int]$level.camera[0],
                    [int]$level.camera[1])
                original_camera_clamped = $false
                metrics = Copy-Metrics $level.metrics
                passed = [bool]$level.passed
            })
        }
        $sampleCount += $samples.Count
        Test-Metrics $level.metrics $thresholds (
            "$profileId/$($level.level_id) aggregate")
        $baselineLevels.Add([pscustomobject][ordered]@{
            id = [string]$level.level_id
            selector_level = [int]$level.selector_level
            camera = @(
                [int]$level.camera[0],
                [int]$level.camera[1])
            viewport = @(
                [int]$level.map_viewport[0],
                [int]$level.map_viewport[1])
            aggregate = Copy-Metrics $level.metrics
            samples = @($samples)
            passed = [bool]$level.passed
        })
    }

    $aggregate = [pscustomobject][ordered]@{
        maximum_mean_absolute_error = [double](
            $baselineLevels.aggregate.mean_absolute_error |
            Measure-Object -Maximum).Maximum
        minimum_near_match_ratio = [double](
            $baselineLevels.aggregate.near_match_ratio |
            Measure-Object -Minimum).Minimum
        minimum_edge_correlation = [double](
            $baselineLevels.aggregate.edge_correlation |
            Measure-Object -Minimum).Minimum
        maximum_black_hole_ratio = [double](
            $baselineLevels.aggregate.black_hole_ratio |
            Measure-Object -Maximum).Maximum
    }
    $profiles.Add([pscustomobject][ordered]@{
        id = $profileId
        content_profile = [string]$summary.content_profile
        captured_utc = [string]$summary.generated_utc
        resolution = @($width, $height)
        expanded_viewport = [bool]$summary.expanded_viewport
        tiled_mod_reference = $tiled
        includes_ui = $includesUi
        comparison_region = [pscustomobject][ordered]@{
            top = $regionTop
            bottom_policy = $regionBottomPolicy
        }
        thresholds = [pscustomobject][ordered]@{
            maximum_mean_absolute_error =
                [double]$thresholds.maximum_mean_absolute_error
            minimum_near_match_ratio =
                [double]$thresholds.minimum_near_match_ratio
            minimum_edge_correlation =
                [double]$thresholds.minimum_edge_correlation
            maximum_black_hole_ratio =
                [double]$thresholds.maximum_black_hole_ratio
        }
        aggregate = $aggregate
        level_count = $baselineLevels.Count
        sample_count = $sampleCount
        levels = @($baselineLevels)
        passed = $true
    })
}

$document = [pscustomobject][ordered]@{
    schema_version = 1
    method = (
        'stable MOD cnc-ddraw RGB565 primary memory versus Remake ' +
        'offscreen viewport; no desktop capture or global input')
    original_binary_images_committed = $false
    profiles = @($profiles | Sort-Object id)
    passed = @($profiles).Count -gt 0
}
[IO.Directory]::CreateDirectory(
    [IO.Path]::GetDirectoryName($OutputPath)) | Out-Null
$document | ConvertTo-Json -Depth 12 -Compress |
    Set-Content -LiteralPath $OutputPath -Encoding UTF8
Write-Host (
    "Visual parity baseline written: $OutputPath " +
    "($($profiles.Count) profiles)")
