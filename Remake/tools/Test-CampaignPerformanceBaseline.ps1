[CmdletBinding()]
param(
    [string]$BaselinePath = ''
)

$ErrorActionPreference = 'Stop'
$remakeRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($BaselinePath)) {
    $BaselinePath = Join-Path $remakeRoot (
        'validation\baselines\remake\' +
        'campaign-performance-1920x1080-v1.json')
}
$BaselinePath = [IO.Path]::GetFullPath($BaselinePath)
if (-not (Test-Path -LiteralPath $BaselinePath -PathType Leaf)) {
    throw "Campaign performance baseline was not found: $BaselinePath"
}

$script:checkCount = 0
function Assert-Baseline {
    param(
        [bool]$Condition,
        [string]$Description
    )

    $script:checkCount++
    if (-not $Condition) {
        throw "Campaign performance baseline check failed: $Description"
    }
}

$baseline = Get-Content -LiteralPath $BaselinePath -Raw -Encoding UTF8 |
    ConvertFrom-Json
$expectedLevels = @(
    'm000', 'm001', 'm002', 'm003', 'm004', 'm005',
    'm006', 'm007', 'm008', 'm009', 'm010', 'm011')
$actualLevels = @($baseline.levels | ForEach-Object {
        [string]$_.level_id
    })

Assert-Baseline ([int]$baseline.schema_version -eq 1) (
    'schema version is 1')
Assert-Baseline (
    [string]$baseline.content_profile -eq
        'repository-mod-12-level-20260729') (
    'content profile matches the repository MOD')
Assert-Baseline (
    ($actualLevels -join ',') -eq ($expectedLevels -join ',')) (
    'the exact twelve formal levels are present in order')
Assert-Baseline (
    [int]$baseline.measurement.requested_sample_seconds -ge 600) (
    'the reference workload covers at least 600 seconds')
Assert-Baseline ([int]$baseline.measurement.pass_count -ge 2) (
    'the reference workload has at least two passes')
Assert-Baseline (
    [int]$baseline.measurement.viewport_input_events -ge 1200) (
    'the reference workload contains substantial viewport input')
Assert-Baseline (
    -not [bool]$baseline.measurement.global_pointer_control) (
    'the reference workload never controls the desktop pointer')
Assert-Baseline (
    [int]$baseline.measurement.window.width -eq 1920 -and
    [int]$baseline.measurement.window.height -eq 1080) (
    'the reference viewport is 1920x1080')

$maximumP95 = [double]$baseline.thresholds.maximum_p95_ms
$maximumP99 = [double]$baseline.thresholds.maximum_p99_ms
$maximumOver50 = [int]$baseline.thresholds.maximum_over_50_per_level
$maximumGrowthBytes = [double](
    [double]$baseline.thresholds.maximum_second_pass_growth_mib *
    1024.0 * 1024.0)
Assert-Baseline (
    [double]$baseline.aggregate_metrics.p95_ms -le $maximumP95) (
    'aggregate P95 remains inside its declared threshold')
Assert-Baseline (
    [double]$baseline.aggregate_metrics.p99_ms -le $maximumP99) (
    'aggregate P99 remains inside its declared threshold')
Assert-Baseline (
    [int]$baseline.aggregate_metrics.frames_over_50_ms -eq 0) (
    'aggregate report contains no frame over 50 ms')
Assert-Baseline (
    [int]$baseline.memory.second_pass_growth_bytes -le
        $maximumGrowthBytes) (
    'second-pass memory growth remains inside its declared threshold')

foreach ($level in @($baseline.levels)) {
    $levelId = [string]$level.level_id
    Assert-Baseline ([int]$level.sample_count -ge 600) (
        "$levelId has enough samples for a P99 gate")
    Assert-Baseline ([double]$level.p95_ms -le $maximumP95) (
        "$levelId P95 remains inside its declared threshold")
    Assert-Baseline ([double]$level.p99_ms -le $maximumP99) (
        "$levelId P99 remains inside its declared threshold")
    Assert-Baseline (
        [int]$level.frames_over_50_ms -le $maximumOver50) (
        "$levelId has no unexplained frame over 50 ms")
    Assert-Baseline ([int]$level.moved_enemy_max -gt 0) (
        "$levelId proves live enemy movement")
}

$summaryTemplate = (
    'Campaign performance baseline passed ({0} checks, {1} levels, ' +
    'P95 {2:N3} / P99 {3:N3} ms).')
Write-Host ($summaryTemplate -f
    $script:checkCount,
    $actualLevels.Count,
    [double]$baseline.aggregate_metrics.p95_ms,
    [double]$baseline.aggregate_metrics.p99_ms)
