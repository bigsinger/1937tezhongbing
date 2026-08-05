[CmdletBinding()]
param(
    [string]$GodotExecutable = 'D:\Godot\Godot_v4.7.1-stable_win64_console.exe',

    [ValidateRange(1800, 3600)]
    [double]$DurationSeconds = 1800,

    [ValidateRange(2, 8)]
    [int]$Passes = 3,

    [string]$OutputDirectory = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$remakeRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $remakeRoot 'LocalAssets\qa\stability-soak'
}
$output = [IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Path $output -Force | Out-Null

$reportPath = Join-Path $output 'campaign-performance.json'
$logPath = Join-Path $output 'campaign-performance.log'
$controllerLogPath = Join-Path $output 'controller-output.log'
$summaryPath = Join-Path $output 'stability-summary.json'
$progressPath = Join-Path $output 'stability-progress.json'
# Reusing an output directory must never let a failed new process inherit a
# previous run's successful report. Only these known files are replaced; no
# recursive cleanup or caller-owned content is touched.
foreach ($staleOutput in @(
        $reportPath,
        $logPath,
        $controllerLogPath,
        $summaryPath,
        $progressPath)) {
    if (Test-Path -LiteralPath $staleOutput -PathType Leaf) {
        Remove-Item -LiteralPath $staleOutput -Force
    }
}
$gameDirectory = Join-Path $remakeRoot 'game'
$probeArguments = @(
    '--headless',
    '--max-fps', '60',
    '--path', $gameDirectory,
    '--log-file', $logPath,
    '--script', 'res://tests/campaign_performance_probe.gd',
    '--',
    "--output=$reportPath",
    "--duration-seconds=$DurationSeconds",
    "--passes=$Passes",
    '--max-p95-ms=100',
    '--max-p99-ms=100',
    '--max-ui-action-ms=100',
    '--max-cold-level-load-ms=6000',
    '--max-warm-level-load-ms=3500',
    '--min-per-level-p99-samples=600',
    '--max-over-50-per-level=1000',
    '--max-second-pass-growth-mib=8',
    '--profile-id=twelve-level-headless-30-minute-stability-v2',
    '--command-line-controls-display',
    '--stability-mode'
)
# Windows PowerShell promotes native stderr lines to ErrorRecord objects when
# ErrorActionPreference is Stop. A failed probe must still reach the report
# parser below so every failed threshold and the completed stability evidence
# are summarized instead of aborting on the first rendered ERROR line.
$previousErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
try {
    & $GodotExecutable @probeArguments *> $controllerLogPath
    $probeExitCode = $LASTEXITCODE
}
finally {
    $ErrorActionPreference = $previousErrorActionPreference
}
if (-not (Test-Path -LiteralPath $reportPath -PathType Leaf)) {
    throw "Stability report was not generated. Exit code: $probeExitCode"
}
$report = Get-Content -LiteralPath $reportPath -Raw -Encoding utf8 |
    ConvertFrom-Json
$failures = [Collections.Generic.List[string]]::new()
if ([int]$report.schema_version -ne 2) {
    $failures.Add('Performance report schema is not version 2.')
}
if (@($report.level_ids).Count -ne 12 -or @($report.levels).Count -ne 12) {
    $failures.Add('The stability run did not cover all twelve missions.')
}
if ([int]$report.pass_count -ne $Passes) {
    $failures.Add("Expected $Passes passes, found $($report.pass_count).")
}
if ([double]$report.requested_sample_seconds -lt $DurationSeconds) {
    $failures.Add('The requested stability duration was not recorded.')
}
if ([bool]$report.global_pointer_control) {
    $failures.Add('The stability probe reported global pointer control.')
}
if (-not [bool]$report.stability_mode -or
    [string]$report.runtime.display_backend -ne 'headless') {
    $failures.Add('The stability run did not use the non-interactive headless policy.')
}
if ([int]$report.stability_io.save_count -lt 1 -or
    [int]$report.stability_io.load_count -lt 1) {
    $failures.Add('The stability run did not exercise repeated save/load cycles.')
}
foreach ($level in @($report.levels)) {
    if (@($level.visits).Count -ne $Passes) {
        $failures.Add(
            "$($level.level_id) has $(@($level.visits).Count) visits; expected $Passes.")
    }
}
if (@($report.failures).Count -gt 0) {
    $failures.AddRange([string[]]@($report.failures))
}
if ($probeExitCode -ne 0) {
    $failures.Add("Godot stability probe exited with code $probeExitCode.")
}
if (-not (Test-Path -LiteralPath $logPath -PathType Leaf)) {
    $failures.Add('Godot stability log was not generated.')
}
else {
    $logText = Get-Content -LiteralPath $logPath -Raw -Encoding utf8
    $reportedGateFailures = @(
        @($report.failures) | ForEach-Object { [string]$_ }
    )
    $engineErrors = @(
        $logText -split "`r?`n" |
            Where-Object { $_ -match '^(SCRIPT ERROR|ERROR:)' } |
            Where-Object {
                # The probe uses push_error for an exceeded gate so failures are
                # visible during an interactive run. Those same messages are
                # already present in report.failures and must not be counted a
                # second time as unrelated engine errors.
                $normalized = $_ -replace '^(SCRIPT ERROR|ERROR:)\s*', ''
                $reportedGateFailures -notcontains $normalized
            }
    )
    if ($engineErrors.Count -gt 0) {
        $failures.Add(
            "Godot logged $($engineErrors.Count) engine/script errors during the soak.")
    }
}

$os = Get-CimInstance Win32_OperatingSystem
$processor = Get-CimInstance Win32_Processor | Select-Object -First 1
$videoAdapters = @(
    Get-CimInstance Win32_VideoController |
        ForEach-Object { [string]$_.Name } |
        Sort-Object -Unique
)
$allVisits = @($report.levels | ForEach-Object { @($_.visits) })
$coldVisits = @($allVisits | Where-Object { [int]$_.pass_index -eq 0 })
$warmVisits = @($allVisits | Where-Object { [int]$_.pass_index -gt 0 })
$maximumColdLoadMs = if ($coldVisits.Count -gt 0) {
    [double](($coldVisits | Measure-Object -Property load_ms -Maximum).Maximum)
} else { 0.0 }
$maximumWarmLoadMs = if ($warmVisits.Count -gt 0) {
    [double](($warmVisits | Measure-Object -Property load_ms -Maximum).Maximum)
} else { 0.0 }
$summary = [ordered]@{
    schema_version = 1
    status = if ($failures.Count -eq 0) { 'passed' } else { 'failed' }
    verified_at_utc = [DateTime]::UtcNow.ToString('o')
    profile_id = [string]$report.profile_id
    duration_seconds = [double]$report.sampled_wall_seconds
    passes = [int]$report.pass_count
    missions = @($report.level_ids).Count
    aggregate_p95_ms = [double]$report.aggregate_metrics.p95_ms
    aggregate_p99_ms = [double]$report.aggregate_metrics.p99_ms
    maximum_cold_level_load_ms = $maximumColdLoadMs
    maximum_warm_level_load_ms = $maximumWarmLoadMs
    first_action_latencies_ms = $report.first_action_latencies_ms
    second_pass_growth_mib = [Math]::Round(
        [double]$report.memory.second_pass_growth_bytes / 1MB,
        3)
    global_pointer_control = [bool]$report.global_pointer_control
    save_count = [int]$report.stability_io.save_count
    load_count = [int]$report.stability_io.load_count
    environment = [ordered]@{
        os = [string]$os.Caption
        os_version = [string]$os.Version
        cpu = [string]$processor.Name
        memory_gib = [Math]::Round([double]$os.TotalVisibleMemorySize / 1MB, 1)
        gpu = $videoAdapters
        godot = [string]$report.runtime.godot_version
        renderer = [string]$report.runtime.renderer
        backend = [string]$report.runtime.display_backend
        viewport = "$($report.runtime.viewport_width)x$($report.runtime.viewport_height)"
    }
    report_sha256 = (
        Get-FileHash -LiteralPath $reportPath -Algorithm SHA256).Hash.ToLowerInvariant()
    failures = [string[]]$failures
}
$summary | ConvertTo-Json -Depth 8 |
    Set-Content -LiteralPath $summaryPath -Encoding utf8

if ($failures.Count -gt 0) {
    throw "Stability soak failed:`n - $($failures -join "`n - ")"
}

[pscustomobject]@{
    Status = 'passed'
    DurationMinutes = [Math]::Round([double]$report.sampled_wall_seconds / 60.0, 2)
    Passes = [int]$report.pass_count
    Missions = @($report.level_ids).Count
    P95Ms = [Math]::Round([double]$report.aggregate_metrics.p95_ms, 3)
    P99Ms = [Math]::Round([double]$report.aggregate_metrics.p99_ms, 3)
    MaxColdLoadMs = [Math]::Round($maximumColdLoadMs, 1)
    MaxWarmLoadMs = [Math]::Round($maximumWarmLoadMs, 1)
    MemoryGrowthMiB = $summary.second_pass_growth_mib
    Summary = $summaryPath
}
