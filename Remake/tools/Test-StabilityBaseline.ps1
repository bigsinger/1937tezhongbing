[CmdletBinding()]
param(
    [string]$BaselinePath = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$remakeRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if ([string]::IsNullOrWhiteSpace($BaselinePath)) {
    $BaselinePath = Join-Path $remakeRoot (
        'validation\baselines\remake\stability-soak-30-minute-v1.json')
}
$baseline = [IO.Path]::GetFullPath($BaselinePath)
if (-not (Test-Path -LiteralPath $baseline -PathType Leaf)) {
    throw "Stability baseline was not found: $baseline"
}

$script:checkCount = 0
function Assert-StabilityBaseline {
    param(
        [bool]$Condition,
        [string]$Description
    )

    $script:checkCount++
    if (-not $Condition) {
        throw "Stability baseline check failed: $Description"
    }
}

$document = Get-Content -LiteralPath $baseline -Raw -Encoding UTF8 |
    ConvertFrom-Json
Assert-StabilityBaseline ([int]$document.schema_version -eq 1) (
    'schema version is 1')
Assert-StabilityBaseline ([string]$document.status -eq 'passed') (
    'the recorded run passed')
Assert-StabilityBaseline (
    [string]$document.profile_id -eq
        'twelve-level-headless-30-minute-stability-v2') (
    'the expected non-interactive stability profile was used')
Assert-StabilityBaseline ([bool]$document.simulation_only_world_visuals) (
    'the headless soak skips only immutable static-world rendering')
Assert-StabilityBaseline ([double]$document.duration_seconds -ge 1800.0) (
    'the run sampled at least thirty minutes')
Assert-StabilityBaseline ([int]$document.passes -ge 3) (
    'the run completed at least three campaign passes')
Assert-StabilityBaseline ([int]$document.missions -eq 12) (
    'all twelve formal missions were covered')
Assert-StabilityBaseline ([double]$document.aggregate_p95_ms -le 100.0) (
    'headless stability P95 stays within its diagnostic budget')
Assert-StabilityBaseline ([double]$document.aggregate_p99_ms -le 100.0) (
    'headless stability P99 stays within its diagnostic budget')
Assert-StabilityBaseline (
    [double]$document.maximum_cold_level_load_ms -le 6000.0) (
    'cold level reconstruction stays within the stability budget')
Assert-StabilityBaseline (
    [double]$document.maximum_warm_level_load_ms -le 3500.0) (
    'warm level reconstruction stays within the release budget')
Assert-StabilityBaseline ([double]$document.second_pass_growth_mib -le 8.0) (
    'repeated campaign passes have bounded static-memory growth')
Assert-StabilityBaseline (-not [bool]$document.global_pointer_control) (
    'the probe never controlled the desktop pointer')
Assert-StabilityBaseline ([int]$document.save_count -ge 36) (
    'every visit exercised a physical save cycle')
Assert-StabilityBaseline ([int]$document.load_count -ge 36) (
    'every visit exercised a physical load cycle')
Assert-StabilityBaseline (
    [string]$document.environment.backend -eq 'headless') (
    'the long run was non-interactive')
Assert-StabilityBaseline (
    [string]$document.report_sha256 -match '^[0-9a-f]{64}$') (
    'the ignored full report has a recorded SHA-256 identity')
Assert-StabilityBaseline (@($document.failures).Count -eq 0) (
    'the baseline contains no hidden failures')

Write-Host (
    'Stability baseline passed ({0} checks, {1:N2} minutes, {2} passes).' -f
        $script:checkCount,
        ([double]$document.duration_seconds / 60.0),
        [int]$document.passes)
