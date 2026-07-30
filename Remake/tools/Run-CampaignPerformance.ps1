[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$GodotExecutable,

    [ValidateRange(24, 3600)]
    [double]$DurationSeconds = 600,

    [ValidateRange(1, 8)]
    [int]$Passes = 2,

    [ValidateRange(800, 7680)]
    [int]$Width = 1920,

    [ValidateRange(600, 4320)]
    [int]$Height = 1080,

    [ValidateRange(1, 100)]
    [double]$MaximumP95Ms = 20,

    [ValidateRange(1, 100)]
    [double]$MaximumP99Ms = 25,

    [ValidateRange(1, 1000000)]
    [int]$MinimumPerLevelP99Samples = 600,

    [ValidateRange(0, 100)]
    [int]$MaximumOver50PerLevel = 0,

    [ValidateRange(0, 4096)]
    [double]$MaximumSecondPassGrowthMiB = 128,

    [string]$OutputDirectory = '',

    [string]$ProfileId = 'twelve-level-windowed-10-minute-v1',

    [string]$Levels = ''
)

$ErrorActionPreference = 'Stop'
$remakeRoot = Split-Path -Parent $PSScriptRoot
$gameDirectory = Join-Path $remakeRoot 'game'
if (-not (Test-Path -LiteralPath $GodotExecutable -PathType Leaf)) {
    throw "Godot executable was not found: $GodotExecutable"
}
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $remakeRoot (
        'LocalAssets\qa\campaign-performance')
}
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$reportPath = Join-Path $OutputDirectory 'campaign-performance.json'
$logPath = Join-Path $OutputDirectory 'campaign-performance.log'

$probeArguments = @(
    "--output=$reportPath"
    "--duration-seconds=$DurationSeconds"
    "--passes=$Passes"
    "--max-p95-ms=$MaximumP95Ms"
    "--max-p99-ms=$MaximumP99Ms"
    "--min-per-level-p99-samples=$MinimumPerLevelP99Samples"
    "--max-over-50-per-level=$MaximumOver50PerLevel"
    "--max-second-pass-growth-mib=$MaximumSecondPassGrowthMiB"
    "--profile-id=$ProfileId"
    '--command-line-controls-display'
)
if (-not [string]::IsNullOrWhiteSpace($Levels)) {
    $probeArguments += "--levels=$Levels"
}

& $GodotExecutable `
    --path $gameDirectory `
    --windowed `
    --resolution "$($Width)x$($Height)" `
    --max-fps 60 `
    --disable-vsync `
    --log-file $logPath `
    --script 'res://tests/campaign_performance_probe.gd' `
    -- `
    @probeArguments
$exitCode = $LASTEXITCODE
if (-not (Test-Path -LiteralPath $reportPath -PathType Leaf)) {
    throw "Campaign performance report was not generated. Exit code: $exitCode"
}
$report = Get-Content -LiteralPath $reportPath -Raw -Encoding UTF8 |
    ConvertFrom-Json

$rows = foreach ($level in @($report.levels)) {
    [pscustomobject]@{
        Level = [string]$level.level_id
        Samples = [int]$level.metrics.sample_count
        P95Ms = [math]::Round([double]$level.metrics.p95_ms, 3)
        P99Ms = [math]::Round([double]$level.metrics.p99_ms, 3)
        MaxMs = [math]::Round([double]$level.metrics.maximum_ms, 3)
        Over50 = [int]$level.metrics.frames_over_50_ms
        MovedEnemies = [int]$level.moved_enemy_max
        InputEvents = [int]$level.viewport_input_events
    }
}
$rows | Format-Table -AutoSize
[pscustomobject]@{
    Profile = [string]$report.profile_id
    RequestedSeconds = [double]$report.requested_sample_seconds
    Samples = [int]$report.aggregate_metrics.sample_count
    P95Ms = [math]::Round([double]$report.aggregate_metrics.p95_ms, 3)
    P99Ms = [math]::Round([double]$report.aggregate_metrics.p99_ms, 3)
    InputEvents = [int]$report.viewport_input_events
    GlobalPointerControl = [bool]$report.global_pointer_control
    Report = $reportPath
} | Format-List

if ($exitCode -ne 0 -or @($report.failures).Count -ne 0) {
    throw "Campaign performance gate failed with exit code $exitCode."
}
