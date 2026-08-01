[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$remakeRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$baselinePath = Join-Path $remakeRoot (
    'game\data\original_crt_random_runtime_timing.json')
$startupPath = Join-Path $remakeRoot (
    'game\data\original_crt_random_startup_catalog.json')
$baseline = (
    [IO.File]::ReadAllText(
        $baselinePath,
        [Text.UTF8Encoding]::new($false)) |
        ConvertFrom-Json)
$startup = (
    [IO.File]::ReadAllText(
        $startupPath,
        [Text.UTF8Encoding]::new($false)) |
        ConvertFrom-Json)

if (
    [int]$baseline.schema_version -ne 1 -or
    [string]$baseline.baseline_id -ne (
        'original-crt-random-runtime-timing-v1') -or
    [string]$baseline.content_profile -ne (
        'repository-mod-12-level-20260729') -or
    [string]$baseline.executable_sha256 -ne (
        'F4DD1131DF6C993C01EA011F9439BC725E6DC6491B5FBBA47724D7D5B64DA3F3')
) {
    throw 'Unsupported original CRT runtime timing baseline.'
}
if (
    [string]$baseline.evidence.capture_mode -ne (
        'process-local-crt-rand-hook') -or
    [string]$baseline.evidence.hook_scope -ne (
        'test-only-environment-gated') -or
    [string]$baseline.evidence.input_scope -ne (
        'target-window-only') -or
    [string]$baseline.evidence.source_trace_sha256 -notmatch (
        '^[0-9A-F]{64}$') -or
    [string]$baseline.evidence.actor_snapshot_sha256 -notmatch (
        '^[0-9A-F]{64}$')
) {
    throw 'Runtime timing evidence provenance is incomplete.'
}

$levels = @($baseline.levels)
if ($levels.Count -ne 1 -or [string]$levels[0].id -ne 'm000') {
    throw 'The first runtime timing baseline must contain only m000.'
}
$level = $levels[0]
$startupLevel = @($startup.levels | Where-Object {
    [string]$_.id -eq 'm000'
})[0]
$expectedGateActors = @(
    $startupLevel.observation_gate_actor_indices |
        ForEach-Object { [int]$_ })
$expectedPrimaryActors = @(
    foreach ($outcome in
        $startupLevel.first_gameplay_update.actor_outcomes) {
        if (@($outcome.semantic_effects) -contains (
                'primary_candidate_scan')) {
            [int]$outcome.runtime_index
        }
    })
if (
    (@($level.observation_gate_actor_indices) -join ',') -ne
        ($expectedGateActors -join ',') -or
    (@($level.primary_candidate_scan_actor_indices) -join ',') -ne
        ($expectedPrimaryActors -join ',')
) {
    throw 'Runtime timing actor identities diverged from startup evidence.'
}

$rounds = [int]$level.actor_update_round_count
$gateActors = [int]$level.observation_gate_actor_count
$primaryActors = [int]$level.primary_candidate_scan_actor_count
if (
    $rounds -ne 710 -or
    [int]$level.first_gameplay_sequence -ne 8490 -or
    $gateActors -ne 54 -or
    $primaryActors -ne 2 -or
    [int]$level.observation_gate_draw_count -ne (
        $rounds * $gateActors) -or
    [int]$level.primary_candidate_scan_draw_count -ne (
        $rounds * $primaryActors)
) {
    throw 'Runtime timing round/draw totals are inconsistent.'
}
if (
    [int]$level.steady_interval_count -ne 707 -or
    [int]$level.excluded_zero_interval_count -ne 1 -or
    [int]$level.excluded_stall_interval_count -ne 1 -or
    [double]$level.steady_frequency_hz -lt 59.5 -or
    [double]$level.steady_frequency_hz -gt 60.5 -or
    [long]$level.steady_min_ms -lt 15 -or
    [long]$level.steady_p50_ms -ne 16 -or
    [long]$level.steady_p95_ms -gt 31 -or
    [long]$level.steady_max_ms -gt 31
) {
    throw 'Runtime timing sample no longer proves a stable 60 Hz cadence.'
}
foreach ($hashName in @(
        'gate_actor_order_sha256',
        'recurring_actor_call_order_sha256')) {
    if ([string]$level.$hashName -notmatch '^[0-9A-F]{64}$') {
        throw "Runtime timing hash is invalid: $hashName"
    }
}
$counts = @{}
foreach ($entry in $level.call_site_counts) {
    $counts[[string]$entry.call_site_rva] = [int]$entry.count
}
if (
    [int]$counts['0x0005C81C'] -ne 38340 -or
    [int]$counts['0x00055216'] -ne 1420 -or
    [int]$counts['0x00056105'] -ne 156 -or
    [int]$counts['0x00058946'] -ne 106 -or
    [int]$counts['0x0005D47E'] -ne 2680
) {
    throw 'Runtime timing call-site counts diverged.'
}

Write-Host (
    "Original CRT runtime timing baseline passed: " +
    "$rounds rounds, $gateActors observation actors, " +
    "$primaryActors primary candidates, " +
    "$([double]$level.steady_frequency_hz) Hz.")
