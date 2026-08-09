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

    # Keep the probe mostly outside the primary working area without using an
    # extreme coordinate. Some Windows virtual-display drivers crash Godot
    # while creating an OpenGL window at positions such as 30000,30000.
    [string]$WindowPosition = '1880,0',

    [ValidateRange(1, 100)]
    [double]$MaximumP95Ms = 20,

    [ValidateRange(1, 100)]
    [double]$MaximumPerLevelP95Ms = 20,

    [ValidateRange(1, 100)]
    [double]$MaximumP99Ms = 25,

    [ValidateRange(1, 100)]
    [double]$MaximumProcessP95Ms = 20,

    [ValidateRange(1, 100)]
    [double]$MaximumPhysicsP95Ms = 20,

    [ValidateRange(1, 100)]
    [double]$MaximumUiActionMs = 25,

    [ValidateRange(100, 60000)]
    [double]$MaximumColdLevelLoadMs = 6000,

    [ValidateRange(100, 60000)]
    [double]$MaximumWarmLevelLoadMs = 3500,

    [ValidateRange(1, 1000000)]
    [int]$MinimumPerLevelP99Samples = 600,

    [ValidateRange(0, 100)]
    [int]$MaximumOver50PerLevel = 0,

    [ValidateRange(0, 4096)]
    [double]$MaximumSecondPassGrowthMiB = 128,

    [string]$OutputDirectory = '',

    [string]$ProfileId = 'twelve-level-windowed-10-minute-v1',

    [string]$Levels = '',

    [switch]$ActorPhysicsProfile,

    [switch]$DiagnosticDisableReservations
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
foreach ($staleOutput in @($reportPath, $logPath)) {
    if (Test-Path -LiteralPath $staleOutput -PathType Leaf) {
        Remove-Item -LiteralPath $staleOutput -Force
    }
}

$probeArguments = @(
    "--output=$reportPath"
    "--duration-seconds=$DurationSeconds"
    "--passes=$Passes"
    "--max-p95-ms=$MaximumP95Ms"
    "--max-per-level-p95-ms=$MaximumPerLevelP95Ms"
    "--max-p99-ms=$MaximumP99Ms"
    "--max-process-p95-ms=$MaximumProcessP95Ms"
    "--max-physics-p95-ms=$MaximumPhysicsP95Ms"
    "--max-ui-action-ms=$MaximumUiActionMs"
    "--max-cold-level-load-ms=$MaximumColdLevelLoadMs"
    "--max-warm-level-load-ms=$MaximumWarmLevelLoadMs"
    "--min-per-level-p99-samples=$MinimumPerLevelP99Samples"
    "--max-over-50-per-level=$MaximumOver50PerLevel"
    "--max-second-pass-growth-mib=$MaximumSecondPassGrowthMiB"
    "--profile-id=$ProfileId"
    '--command-line-controls-display'
)
if (-not [string]::IsNullOrWhiteSpace($Levels)) {
    $probeArguments += "--levels=$Levels"
}
if ($ActorPhysicsProfile) {
    $probeArguments += '--profile-actor-physics'
}
if ($DiagnosticDisableReservations) {
    $probeArguments += '--diagnostic-disable-reservations'
}

& $GodotExecutable `
    --path $gameDirectory `
    --windowed `
    --resolution "$($Width)x$($Height)" `
    --position $WindowPosition `
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
    $coldVisit = @($level.visits | Where-Object { [int]$_.pass_index -eq 0 } |
        Select-Object -First 1)
    $warmVisits = @($level.visits | Where-Object { [int]$_.pass_index -gt 0 })
    [pscustomobject]@{
        Level = [string]$level.level_id
        Samples = [int]$level.metrics.sample_count
        P95Ms = [math]::Round([double]$level.metrics.p95_ms, 3)
        P99Ms = [math]::Round([double]$level.metrics.p99_ms, 3)
        MaxMs = [math]::Round([double]$level.metrics.maximum_ms, 3)
        Over50 = [int]$level.metrics.frames_over_50_ms
        MovedEnemies = [int]$level.moved_enemy_max
        InputEvents = [int]$level.viewport_input_events
        ColdLoadMs = if ($coldVisit.Count -gt 0) {
            [math]::Round([double]$coldVisit[0].load_ms, 1)
        } else { 0.0 }
        MaxWarmLoadMs = if ($warmVisits.Count -gt 0) {
            [math]::Round(
                [double](($warmVisits | Measure-Object -Property load_ms -Maximum).Maximum),
                1)
        } else { 0.0 }
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
    FrameCap = [int]$report.runtime.frame_cap_during_measurement
    FirstActionLatencyMs = ($report.first_action_latencies_ms | ConvertTo-Json -Compress)
    Report = $reportPath
} | Format-List

if ($exitCode -ne 0 -or @($report.failures).Count -ne 0) {
    throw "Campaign performance gate failed with exit code $exitCode."
}
