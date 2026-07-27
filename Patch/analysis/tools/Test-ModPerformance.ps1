param(
    [ValidateRange(60, 1800)]
    [int]$DurationSeconds = 600,
    [string[]]$Profiles = @('menu', 'small', 'medium', 'large'),
    [string]$OutputRoot = '',
    [switch]$KeepRuntime
)

$ErrorActionPreference = 'Stop'
$Profiles = @(
    $Profiles |
        ForEach-Object { $_ -split ',' } |
        ForEach-Object { $_.Trim().ToLowerInvariant() } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
)
if ($Profiles.Count -eq 0) {
    throw 'At least one performance profile is required.'
}
$repositoryRoot = [IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot '..\..\..'))
$modRoot = Join-Path $repositoryRoot 'Mod'
$buildRoot = Join-Path 'E:\1937' 'probe-build'
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path 'E:\1937' (
        'mod-performance-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
}
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
if (-not $OutputRoot.StartsWith(
        [IO.Path]::GetFullPath('E:\1937\'),
        [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Performance output and runtime must stay under E:\1937.'
}
[IO.Directory]::CreateDirectory($OutputRoot) | Out-Null

$ambientGames = @(Get-CimInstance Win32_Process -Filter "Name='M1937.exe'")
if ($ambientGames.Count -gt 0) {
    $paths = ($ambientGames | ForEach-Object {
        if ([string]::IsNullOrWhiteSpace($_.ExecutablePath)) {
            "PID $($_.ProcessId)"
        }
        else {
            "PID $($_.ProcessId): $($_.ExecutablePath)"
        }
    }) -join [Environment]::NewLine
    throw (
        "Another M1937 process is already running. Close it before a " +
        "performance baseline so the result is not contaminated:" +
        [Environment]::NewLine + $paths)
}

& (Join-Path $repositoryRoot 'Patch\tools\Build-Mod.ps1') `
    -RepositoryRoot $repositoryRoot | Out-Host
& (Join-Path $PSScriptRoot 'Build-Probes.ps1') `
    -OutputDirectory $buildRoot | Out-Host

$probe = Join-Path $buildRoot 'ModPerformanceProbe.exe'
$runtime = Join-Path $OutputRoot 'isolated-runtime'
[IO.Directory]::CreateDirectory($runtime) | Out-Null
Get-ChildItem -LiteralPath $modRoot -Force | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination $runtime `
        -Recurse -Force
}

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class PerformanceIni {
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    public static extern bool WritePrivateProfileString(
        string section, string key, string value, string path);
}
'@
function Set-Ini {
    param([string]$Path, [string]$Section, [string]$Key, [string]$Value)
    if (-not [PerformanceIni]::WritePrivateProfileString(
            $Section, $Key, $Value, $Path)) {
        throw "Could not write isolated INI: [$Section] $Key"
    }
}

$runtimeIni = Join-Path $runtime 'rungame.ini'
$runtimeDdraw = Join-Path $runtime 'ddraw.ini'
Set-Ini $runtimeIni 'mod' 'Enabled' '1'
Set-Ini $runtimeIni 'mod' 'Diagnostics' '1'
Set-Ini $runtimeIni 'mod' 'Telemetry' '1'
Set-Ini $runtimeIni 'mod' 'TelemetryIntervalMs' '250'
Set-Ini $runtimeIni 'mod' 'SystemCursorMapping' '0'
Set-Ini $runtimeIni 'mod' 'PreserveLegacyUI' '1'
Set-Ini $runtimeIni 'mod' 'AILevel' '3'
Set-Ini $runtimeIni 'mod' 'Difficulty' '1'
Set-Ini $runtimeDdraw 'ddraw' 'fullscreen' 'false'
Set-Ini $runtimeDdraw 'ddraw' 'windowed' 'true'
Set-Ini $runtimeDdraw 'ddraw' 'width' '1024'
Set-Ini $runtimeDdraw 'ddraw' 'height' '768'
Set-Ini $runtimeDdraw 'ddraw' 'devmode' 'true'
Set-Ini $runtimeDdraw 'ddraw' 'no_dinput_hook' 'true'
Set-Ini $runtimeDdraw 'ddraw' 'adjmouse' 'false'
Set-Ini $runtimeDdraw 'ddraw' 'savesettings' '0'

$profileMap = @{
    menu = 0
    small = 1
    medium = 8
    large = 15
}
$results = [Collections.Generic.List[object]]::new()
foreach ($profile in $Profiles) {
    if (-not $profileMap.ContainsKey($profile)) {
        throw "Unknown performance profile: $profile"
    }
    Get-ChildItem -LiteralPath $runtime -File |
        Where-Object {
            $_.Name -in @('M1937Mod.log', 'M1937Telemetry.jsonl')
        } | Remove-Item -Force
    $output = Join-Path $OutputRoot $profile
    [IO.Directory]::CreateDirectory($output) | Out-Null
    Write-Host (
        "Running $profile performance baseline for " +
        "$DurationSeconds seconds...")
    & $probe $runtime $output $profile `
        ([int]$profileMap[$profile]) $DurationSeconds
    if ($LASTEXITCODE -ne 0) {
        throw "$profile performance probe failed with exit code $LASTEXITCODE."
    }
    $result = Get-Content -LiteralPath (
        Join-Path $output 'performance.json') -Raw -Encoding UTF8 |
        ConvertFrom-Json
    $results.Add($result)
    foreach ($name in @('M1937Mod.log', 'M1937Telemetry.jsonl')) {
        $source = Join-Path $runtime $name
        if (Test-Path -LiteralPath $source -PathType Leaf) {
            Copy-Item -LiteralPath $source `
                -Destination (Join-Path $output $name) -Force
        }
    }
}

$aggregate = [ordered]@{
    schema = 1
    generated_utc = [DateTime]::UtcNow.ToString('o')
    duration_seconds_per_profile = $DurationSeconds
    system_cursor_calls = 0
    global_focus_calls = 0
    cursor_clip_restricted_samples = [long]((
        $results | Measure-Object `
            -Property cursor_clip_restricted_samples -Sum).Sum)
    profiles = @($results)
    passed = @($results | Where-Object { -not $_.passed }).Count -eq 0
}
$aggregate | ConvertTo-Json -Depth 8 |
    Set-Content -LiteralPath (
        Join-Path $OutputRoot 'performance-baseline.json') -Encoding UTF8
$markdown = [Collections.Generic.List[string]]::new()
$durationLabel = if ($DurationSeconds % 60 -eq 0) {
    '{0}-Minute' -f ([int]($DurationSeconds / 60))
}
else {
    '{0}-Second' -f $DurationSeconds
}
$markdown.Add("# MOD $durationLabel Performance Baseline")
$markdown.Add('')
$markdown.Add(
    'Input is posted only to the isolated game window and consumed by the ' +
    'process-local DirectInput proxy. System cursor calls: 0.')
$markdown.Add('')
$markdown.Add(
    'The probe deliberately does not foreground the game. Cursor spans prove ' +
    'client-edge input delivery; foreground scroll movement is covered by the ' +
    'separate v1.3.7 real-mouse visual regression.')
$markdown.Add('')
$markdown.Add('| Profile | Result | Level | CPU% | P95/P99 | >25/>50 ms | Input max | Pump max | Log drop | Cursor clipped | Disk first/steady | Cursor X/Y | Camera X/Y | Classification |')
$markdown.Add('|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|')
foreach ($result in $results) {
    $resultLabel = if ($result.passed) { 'pass' } else { 'fail' }
    $markdown.Add((
        '| {0} | {1} | {2} | {3:F1} | {4:F2}/{5:F2} ms | {6}/{7} | ' +
        '{8} us | {9} us | {10} | {11} | {12}/{13} | {14}/{15} | {16}/{17} | {18} |') -f @(
        $result.profile,
        $resultLabel,
        $result.selector_level,
        $result.cpu_one_core_percent,
        $result.compositor_p95_ms,
        $result.compositor_p99_ms,
        $result.hitches_over_25ms,
        $result.hitches_over_50ms,
        $result.input_latency_max_us,
        $result.message_pump_max_us,
        $result.telemetry_queue_dropped,
        $result.cursor_clip_restricted_samples,
        $result.disk_peak_sample_bytes,
        $result.steady_disk_peak_sample_bytes,
        $result.cursor_span_x,
        $result.cursor_span_y,
        $result.camera_span_x,
        $result.camera_span_y,
        $result.classified_bottleneck))
}
$markdown | Set-Content -LiteralPath (
    Join-Path $OutputRoot 'performance-baseline.md') -Encoding UTF8

if (-not $KeepRuntime) {
    $resolved = [IO.Path]::GetFullPath($runtime)
    if (-not $resolved.StartsWith(
            $OutputRoot + [IO.Path]::DirectorySeparatorChar,
            [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Refusing to remove a runtime outside the output root.'
    }
    for ($attempt = 0; $attempt -lt 8; ++$attempt) {
        try {
            Remove-Item -LiteralPath $resolved -Recurse -Force
            break
        }
        catch {
            Start-Sleep -Milliseconds 250
        }
    }
}
Write-Host "Performance report: $(Join-Path $OutputRoot 'performance-baseline.md')"
if (-not $aggregate.passed) {
    exit 1
}
