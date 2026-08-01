param(
    [int[]]$Levels = (1..12),
    [string]$LevelList = '',
    [ValidateRange(20, 600)]
    [int]$DurationSeconds = 60,
    [string]$OutputRoot = '',
    [switch]$KeepRuntime,
    [switch]$BriefingOnly,
    [switch]$CrtRandomStartupOnly,
    [switch]$CrtRandomRuntimeOnly,
    [ValidateRange(1000, 60000)]
    [int]$CrtRandomRuntimeMilliseconds = 12500,
    [switch]$MovementOnly
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = [IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot '..\..\..'))
$modRoot = Join-Path $repositoryRoot 'Mod'
$routesPath = Join-Path $repositoryRoot 'SDK\mission-routes.json'
$buildRoot = Join-Path 'E:\1937' 'probe-build'
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path 'E:\1937' (
        'mod-regression-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
}
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
if (-not $OutputRoot.StartsWith(
        [IO.Path]::GetFullPath('E:\1937\'),
        [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Regression output and temporary runtime must stay under E:\1937.'
}
[IO.Directory]::CreateDirectory($OutputRoot) | Out-Null

if (-not [string]::IsNullOrWhiteSpace($LevelList)) {
    $Levels = @($LevelList.Split(',') | ForEach-Object {
        [int]$_.Trim()
    })
}

foreach ($level in $Levels) {
    if ($level -lt 1 -or $level -gt 12) {
        throw "Level is outside 1..12: $level"
    }
}

& (Join-Path $repositoryRoot 'Patch\tools\Build-Mod.ps1') `
    -RepositoryRoot $repositoryRoot | Out-Host
& (Join-Path $PSScriptRoot 'Build-Probes.ps1') `
    -OutputDirectory $buildRoot | Out-Host

$probe = Join-Path $buildRoot 'ModRegressionProbe.exe'
$runtime = Join-Path $OutputRoot 'isolated-runtime'
[IO.Directory]::CreateDirectory($runtime) | Out-Null
Get-ChildItem -LiteralPath $modRoot -Force | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination $runtime `
        -Recurse -Force
}

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class RegressionIni {
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    public static extern bool WritePrivateProfileString(
        string section, string key, string value, string path);
}
'@

function Set-Ini {
    param(
        [string]$Path,
        [string]$Section,
        [string]$Key,
        [string]$Value
    )
    if (-not [RegressionIni]::WritePrivateProfileString(
            $Section, $Key, $Value, $Path)) {
        throw "Could not write isolated INI: [$Section] $Key"
    }
}

function Get-EvidenceNumber {
    param(
        [string]$Evidence,
        [string]$Key
    )
    if ($Evidence -match (
            '(?:^|;\s*)' + [Regex]::Escape($Key) + '=([0-9]+)')) {
        return [long]$Matches[1]
    }
    return [long]0
}

function Get-EvidenceBoolean {
    param(
        [string]$Evidence,
        [string]$Key
    )
    if ($Evidence -match (
            '(?:^|;\s*)' + [Regex]::Escape($Key) + '=(True|False)')) {
        return $Matches[1] -eq 'True'
    }
    return $false
}

$runtimeIni = Join-Path $runtime 'rungame.ini'
$runtimeDdraw = Join-Path $runtime 'ddraw.ini'
Set-Ini $runtimeIni 'mod' 'Enabled' '1'
Set-Ini $runtimeIni 'mod' 'Diagnostics' '1'
Set-Ini $runtimeIni 'mod' 'Telemetry' '1'
Set-Ini $runtimeIni 'mod' 'TelemetryIntervalMs' '250'
Set-Ini $runtimeIni 'mod' 'SystemCursorMapping' '0'
Set-Ini $runtimeIni 'mod' 'AutoStart' '0'
Set-Ini $runtimeIni 'mod' 'PreserveLegacyUI' '1'
Set-Ini $runtimeIni 'mod' 'ExpandedViewport' '0'
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
# The isolated probe never requests real foreground focus. Let its window-only
# WM_ACTIVATE messages reach the original game so gameplay input can be
# exercised without stealing focus from the user's desktop.
Set-Ini $runtimeDdraw 'ddraw' 'noactivateapp' 'false'

$routes = (Get-Content -LiteralPath $routesPath -Raw -Encoding UTF8 |
    ConvertFrom-Json).routes
$results = [Collections.Generic.List[object]]::new()

foreach ($level in $Levels) {
    $route = @($routes | Where-Object {
        [int]$_.selector_level -eq $level
    })[0]
    Get-ChildItem -LiteralPath $runtime -File |
        Where-Object {
            $_.Name -like '1937M*.SAV' -or
            $_.Name -in @('M1937Mod.log', 'M1937Telemetry.jsonl')
        } |
        Remove-Item -Force

    $levelOutput = Join-Path $OutputRoot ('level-{0:D2}' -f $level)
    [IO.Directory]::CreateDirectory($levelOutput) | Out-Null
    Write-Host ("Running isolated level {0:D2}: {1}" -f
        $level, [string]$route.title)
    $probeArguments = @(
        $runtime, $levelOutput, $level, $DurationSeconds)
    if ($BriefingOnly) {
        $probeArguments += '--briefing-only'
    }
    if ($CrtRandomStartupOnly) {
        $probeArguments += '--crt-random-startup-only'
    }
    if ($CrtRandomRuntimeOnly) {
        $probeArguments += '--crt-random-runtime-only'
        $probeArguments += (
            '--crt-random-runtime-ms=' +
            $CrtRandomRuntimeMilliseconds)
    }
    if ($MovementOnly) {
        $probeArguments += '--movement-only'
    }
    $previousRandomTrace = $env:M1937_RNG_TRACE
    try {
        if ($CrtRandomStartupOnly -or $CrtRandomRuntimeOnly) {
            # Enable the test-only process-local hook only for this child
            # launch. Ordinary MOD launches never inherit the diagnostic
            # instrumentation from this regression script.
            $env:M1937_RNG_TRACE = '1'
        }
        & $probe @probeArguments
        $probeExit = $LASTEXITCODE
    }
    finally {
        if ($null -eq $previousRandomTrace) {
            Remove-Item Env:M1937_RNG_TRACE -ErrorAction SilentlyContinue
        }
        else {
            $env:M1937_RNG_TRACE = $previousRandomTrace
        }
    }
    if (
        $CrtRandomStartupOnly -or $CrtRandomRuntimeOnly
    ) {
        $runtimeTelemetry = Join-Path $runtime (
            'M1937Telemetry.jsonl')
        if (Test-Path -LiteralPath $runtimeTelemetry -PathType Leaf) {
            Copy-Item -LiteralPath $runtimeTelemetry `
                -Destination (Join-Path $levelOutput (
                    $(if ($CrtRandomStartupOnly) {
                        'crt-random-telemetry.jsonl'
                    }
                    else {
                        'crt-random-runtime-telemetry.jsonl'
                    }))) -Force
        }
    }
    $resultPath = Join-Path $levelOutput 'result.json'
    $result = if (Test-Path -LiteralPath $resultPath -PathType Leaf) {
        Get-Content -LiteralPath $resultPath -Raw -Encoding UTF8 |
            ConvertFrom-Json
    } else {
        [pscustomobject]@{
            selector_level = $level
            engine_mission = [int]$route.engine_mission
            passed = $false
            performance = [pscustomobject]@{
                cpu_one_core_percent = 0
                disk_read_bytes = 0
                unresponsive_samples = 1
                compositor_wait_p95_ms = 0
                compositor_wait_p99_ms = 0
            }
            stages = @()
        }
    }
    $aiStage = @($result.stages | Where-Object {
        $_.name -eq 'ai_last_known_coordination'
    }) | Select-Object -First 1
    $aiEvidence = if ($null -eq $aiStage) {
        ''
    }
    else {
        [string]$aiStage.evidence
    }
    $results.Add([pscustomobject]@{
        Level = $level
        Title = [string]$route.title
        EngineMission = [int]$route.engine_mission
        Passed = $probeExit -eq 0 -and [bool]$result.passed
        CpuPercent = [double]$result.performance.cpu_one_core_percent
        ReadBytes = [long]$result.performance.disk_read_bytes
        Unresponsive = [int]$result.performance.unresponsive_samples
        CursorClipRestricted = [int](
            $result.performance.cursor_clip_restricted_samples)
        PresentP95 = [double]$result.performance.compositor_wait_p95_ms
        PresentP99 = [double]$result.performance.compositor_wait_p99_ms
        StageCount = @($result.stages).Count
        AiAlert = Get-EvidenceBoolean $aiEvidence 'alert_event'
        AiReinforcements = Get-EvidenceNumber `
            $aiEvidence 'max_reinforcements'
        AiReactionMaxMs = Get-EvidenceNumber `
            $aiEvidence 'reaction_max_ms'
        AiSearches = Get-EvidenceNumber $aiEvidence 'searches_started'
        AiReplans = Get-EvidenceNumber $aiEvidence 'path_replans'
        AiEscapeTrials = Get-EvidenceNumber $aiEvidence 'escape_trials'
        AiEscapeSuccesses = Get-EvidenceNumber `
            $aiEvidence 'escape_successes'
        AiTickMaxUs = Get-EvidenceNumber $aiEvidence 'ai_tick_max_us'
        AiLiveTargetSampling = Get-EvidenceBoolean `
            $aiEvidence 'live_target_sampling'
    })

    foreach ($name in @('M1937Mod.log', 'M1937Telemetry.jsonl')) {
        $source = Join-Path $runtime $name
        if (Test-Path -LiteralPath $source -PathType Leaf) {
            Copy-Item -LiteralPath $source `
                -Destination (Join-Path $levelOutput $name) -Force
        }
    }
}

$allPassed = @($results | Where-Object { -not $_.Passed }).Count -eq 0
$escapeTrials = [long](($results | Measure-Object `
    -Property AiEscapeTrials -Sum).Sum)
$escapeSuccesses = [long](($results | Measure-Object `
    -Property AiEscapeSuccesses -Sum).Sum)
$escapeRate = if ($escapeTrials -gt 0) {
    [Math]::Min(100.0, $escapeSuccesses * 100.0 / $escapeTrials)
}
else {
    100.0
}
$summary = [ordered]@{
    schema = 1
    generated_utc = [DateTime]::UtcNow.ToString('o')
    input_isolation = 'window-message-to-process-local-DirectInput'
    system_cursor_calls = 0
    global_focus_calls = 0
    cursor_clip_restricted_samples = [long]((
        $results | Measure-Object `
            -Property CursorClipRestricted -Sum).Sum)
    levels = @($results)
    ai = [ordered]@{
        alert_levels = @($results | Where-Object { $_.AiAlert }).Count
        maximum_reaction_ms = [long](($results | Measure-Object `
            -Property AiReactionMaxMs -Maximum).Maximum)
        maximum_reinforcements = [long](($results | Measure-Object `
            -Property AiReinforcements -Maximum).Maximum)
        searches_started = [long](($results | Measure-Object `
            -Property AiSearches -Sum).Sum)
        path_replans = [long](($results | Measure-Object `
            -Property AiReplans -Sum).Sum)
        escape_trials = $escapeTrials
        escape_successes = $escapeSuccesses
        escape_success_rate_percent = $escapeRate
        maximum_tick_us = [long](($results | Measure-Object `
            -Property AiTickMaxUs -Maximum).Maximum)
        samples_live_target_after_alert = @(
            $results | Where-Object {
                $_.AiLiveTargetSampling
            }).Count -gt 0
    }
    passed = $allPassed
}
$summary | ConvertTo-Json -Depth 8 |
    Set-Content -LiteralPath (Join-Path $OutputRoot 'summary.json') `
        -Encoding UTF8

$markdown = [Collections.Generic.List[string]]::new()
$markdown.Add('# MOD 12-Level Isolated Regression Report')
$markdown.Add('')
$markdown.Add(
    'The probe posts only to the tested game window and the process-local ' +
    'DirectInput proxy. It never calls global cursor, input, or focus APIs.')
$markdown.Add('')
$markdown.Add('| Level | Route | Result | Stages | CPU% | Read | Compositor P95/P99 | Unresponsive | Cursor clipped |')
$markdown.Add('|---:|---:|---|---:|---:|---:|---:|---:|---:|')
foreach ($result in $results) {
    $resultLabel = if ($result.Passed) { 'pass' } else { 'fail' }
    $line = (
        '| {0:D2} | {1} | {2} | {3} | {4:F1} | {5} | ' +
        '{6:F2}/{7:F2} ms | {8} | {9} |') -f
        @($result.Level, $result.EngineMission, $resultLabel,
        $result.StageCount, $result.CpuPercent, $result.ReadBytes,
        $result.PresentP95, $result.PresentP99,
        $result.Unresponsive, $result.CursorClipRestricted)
    $markdown.Add($line)
}
$markdown.Add('')
$markdown.Add('| Level | Alert | Reaction max | Reinforcements | Searches/replans | Escape | AI tick max | Live target |')
$markdown.Add('|---:|---|---:|---:|---:|---:|---:|---|')
foreach ($result in $results) {
    $markdown.Add((
        '| {0:D2} | {1} | {2} ms | {3} | {4}/{5} | {6}/{7} | ' +
        '{8} us | {9} |') -f @(
        $result.Level,
        $(if ($result.AiAlert) { 'yes' } else { 'no' }),
        $result.AiReactionMaxMs,
        $result.AiReinforcements,
        $result.AiSearches,
        $result.AiReplans,
        $result.AiEscapeSuccesses,
        $result.AiEscapeTrials,
        $result.AiTickMaxUs,
        $(if ($result.AiLiveTargetSampling) { 'yes' } else { 'no' })))
}
$markdown.Add('')
$markdown.Add((
    'AI aggregate: escape {0}/{1} ({2:F1}%); maximum reaction {3} ms; ' +
    'maximum reinforcements {4}; live target sampling after alert: {5}.') -f @(
    $escapeSuccesses,
    $escapeTrials,
    $escapeRate,
    $summary.ai.maximum_reaction_ms,
    $summary.ai.maximum_reinforcements,
    $summary.ai.samples_live_target_after_alert))
$markdown.Add('')
$markdown.Add('Overall: ' + $(if ($allPassed) { 'pass' } else { 'fail' }))
$markdown |
    Set-Content -LiteralPath (Join-Path $OutputRoot 'summary.md') `
        -Encoding UTF8

if (-not $KeepRuntime) {
    $resolvedRuntime = [IO.Path]::GetFullPath($runtime)
    if (-not $resolvedRuntime.StartsWith(
            $OutputRoot + [IO.Path]::DirectorySeparatorChar,
            [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Refusing to remove a runtime outside the regression output.'
    }
    $removed = $false
    for ($attempt = 0; $attempt -lt 8 -and -not $removed; $attempt++) {
        try {
            Remove-Item -LiteralPath $resolvedRuntime -Recurse -Force `
                -ErrorAction Stop
            $removed = $true
        }
        catch {
            Start-Sleep -Milliseconds 250
        }
    }
    if (-not $removed) {
        Write-Warning (
            'The isolated runtime is still locked and was retained: ' +
            $resolvedRuntime)
    }
}

Write-Host "Regression report: $(Join-Path $OutputRoot 'summary.md')"
if (-not $allPassed) {
    exit 1
}
