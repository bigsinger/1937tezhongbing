[CmdletBinding()]
param(
    [string]$GodotExecutable = '',
    [int[]]$Levels = (1..12),
    [string]$OutputDirectory = '',
    [switch]$UpdateBaselines,
    [switch]$AllowMismatch,
    [switch]$KeepRuntime
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$remakeRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $remakeRoot '..'))
$gameRoot = Join-Path $remakeRoot 'game'
$modRoot = Join-Path $repositoryRoot 'Mod'
$identityRoot = Join-Path $remakeRoot 'validation\identities\mod'
$baselineRoot = Join-Path $remakeRoot 'validation\baselines\mod'
$probeBuildRoot = 'E:\1937\probe-build'
$temporaryRoot = [IO.Path]::GetFullPath('E:\1937\')
$runtimePrefix = 'mod-movement-parity-runtime-'

$routes = @(
    [pscustomobject]@{ level = 1; scene = 1436; out_x = 9; out_y = 7; back_x = 1; back_y = 1 },
    [pscustomobject]@{ level = 2; scene = 1993; out_x = 112; out_y = 248; back_x = 125; back_y = 254 },
    [pscustomobject]@{ level = 3; scene = 886; out_x = 1; out_y = 107; back_x = 13; back_y = 118 },
    [pscustomobject]@{ level = 4; scene = 1150; out_x = 23; out_y = 173; back_x = 10; back_y = 187 },
    [pscustomobject]@{ level = 5; scene = 2629; out_x = 54; out_y = 8; back_x = 54; back_y = 12 },
    [pscustomobject]@{ level = 6; scene = 663; out_x = 9; out_y = 194; back_x = 1; back_y = 192 },
    [pscustomobject]@{ level = 7; scene = 1458; out_x = 12; out_y = 13; back_x = 23; back_y = 9 },
    [pscustomobject]@{ level = 8; scene = 2325; out_x = 28; out_y = 41; back_x = 31; back_y = 53 },
    [pscustomobject]@{ level = 9; scene = 753; out_x = 13; out_y = 5; back_x = 1; back_y = 23 },
    [pscustomobject]@{ level = 10; scene = 1709; out_x = 7; out_y = 78; back_x = 0; back_y = 78 },
    [pscustomobject]@{ level = 11; scene = 1590; out_x = 8; out_y = 10; back_x = 1; back_y = 9 },
    [pscustomobject]@{ level = 12; scene = 1176; out_x = 80; out_y = 5; back_x = 96; back_y = 7 }
)

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $remakeRoot (
        'LocalAssets\qa\twelve-level-movement-parity-' +
        (Get-Date -Format 'yyyyMMdd-HHmmss'))
}
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
[IO.Directory]::CreateDirectory($OutputDirectory) | Out-Null

$Levels = @($Levels | Sort-Object -Unique)
if ($Levels.Count -eq 0) {
    throw 'At least one selector level is required.'
}
foreach ($level in $Levels) {
    if ($level -lt 1 -or $level -gt 12) {
        throw "Selector level is outside 1..12: $level"
    }
}

if ([string]::IsNullOrWhiteSpace($GodotExecutable) -and
    -not [string]::IsNullOrWhiteSpace($env:GODOT4)) {
    $GodotExecutable = $env:GODOT4
}
if ([string]::IsNullOrWhiteSpace($GodotExecutable)) {
    foreach ($candidate in @(
            'D:\Godot\Godot_v4.7.1-stable_win64_console.exe',
            'godot4',
            'godot')) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            $GodotExecutable = $candidate
            break
        }
        $command = Get-Command $candidate -ErrorAction SilentlyContinue
        if ($null -ne $command) {
            $GodotExecutable = $command.Source
            break
        }
    }
}
if ([string]::IsNullOrWhiteSpace($GodotExecutable)) {
    throw 'Godot was not found. Pass -GodotExecutable.'
}
$GodotExecutable = (Resolve-Path -LiteralPath $GodotExecutable).Path

& (Join-Path $repositoryRoot 'Patch\analysis\tools\Build-Probes.ps1') `
    -OutputDirectory $probeBuildRoot | Out-Host
$modProbe = Join-Path $probeBuildRoot 'ModRegressionProbe.exe'
if (-not (Test-Path -LiteralPath $modProbe -PathType Leaf)) {
    throw "MOD regression probe was not built: $modProbe"
}

$runtime = Join-Path $temporaryRoot (
    $runtimePrefix + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($runtime) | Out-Null
Get-ChildItem -LiteralPath $modRoot -Force | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination $runtime -Recurse -Force
}

if (-not ('MovementParityIniV1' -as [type])) {
    Add-Type -TypeDefinition @'
using System.Runtime.InteropServices;
public static class MovementParityIniV1
{
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    public static extern bool WritePrivateProfileString(
        string section, string key, string value, string path);
}
'@
}

function Set-IsolatedIniValue {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Section,
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][string]$Value
    )
    if (-not [MovementParityIniV1]::WritePrivateProfileString(
            $Section, $Key, $Value, $Path)) {
        throw "Could not write isolated INI value [$Section] $Key."
    }
}

$runtimeIni = Join-Path $runtime 'rungame.ini'
$runtimeDdraw = Join-Path $runtime 'ddraw.ini'
foreach ($entry in @(
        @($runtimeIni, 'mod', 'Enabled', '1'),
        @($runtimeIni, 'mod', 'Diagnostics', '1'),
        @($runtimeIni, 'mod', 'Telemetry', '1'),
        @($runtimeIni, 'mod', 'TelemetryIntervalMs', '250'),
        @($runtimeIni, 'mod', 'SystemCursorMapping', '0'),
        @($runtimeIni, 'mod', 'AutoStart', '0'),
        @($runtimeIni, 'mod', 'PreserveLegacyUI', '1'),
        @($runtimeIni, 'mod', 'ExpandedViewport', '0'),
        @($runtimeIni, 'mod', 'AILevel', '3'),
        @($runtimeIni, 'mod', 'Difficulty', '1'),
        @($runtimeDdraw, 'ddraw', 'fullscreen', 'false'),
        @($runtimeDdraw, 'ddraw', 'windowed', 'true'),
        @($runtimeDdraw, 'ddraw', 'width', '1024'),
        @($runtimeDdraw, 'ddraw', 'height', '768'),
        @($runtimeDdraw, 'ddraw', 'devmode', 'true'),
        @($runtimeDdraw, 'ddraw', 'no_dinput_hook', 'true'),
        @($runtimeDdraw, 'ddraw', 'adjmouse', 'false'),
        @($runtimeDdraw, 'ddraw', 'savesettings', '0'),
        @($runtimeDdraw, 'ddraw', 'noactivateapp', 'false'))) {
    Set-IsolatedIniValue `
        -Path $entry[0] -Section $entry[1] `
        -Key $entry[2] -Value $entry[3]
}

$results = [Collections.Generic.List[object]]::new()
$completed = $false
try {
    foreach ($level in $Levels) {
        $route = $routes | Where-Object level -eq $level |
            Select-Object -First 1
        if ($null -eq $route) {
            throw "Movement route configuration is missing for level $level."
        }
        $levelId = 'm{0:D3}' -f ($level - 1)
        $scenarioId = "$levelId-player-obstacle-route-v1"
        $identityCatalog = Join-Path $identityRoot (
            "$levelId-runtime-actors-v1.json")
        if (-not (Test-Path -LiteralPath $identityCatalog -PathType Leaf)) {
            throw "Runtime actor identity catalog is missing: $identityCatalog"
        }

        Get-ChildItem -LiteralPath $runtime -File -Force |
            Where-Object {
                $_.Name -like '1937M*.SAV' -or
                $_.Name -in @('M1937Mod.log', 'M1937Telemetry.jsonl')
            } |
            Remove-Item -Force

        $modOutput = Join-Path $OutputDirectory "mod\$levelId"
        $remakeOutput = Join-Path $OutputDirectory "remake\$levelId"
        $comparisonOutput = Join-Path $OutputDirectory "comparison\$levelId"
        foreach ($directory in @(
                $modOutput,
                $remakeOutput,
                $comparisonOutput)) {
            [IO.Directory]::CreateDirectory($directory) | Out-Null
        }

        Write-Host "Capturing stable MOD player route for $levelId..."
        $observationMilliseconds = if ($level -eq 1) {
            750
        }
        else {
            1800
        }
        $successfulModOutput = ''
        foreach ($attempt in 1..3) {
            $attemptOutput = Join-Path $modOutput (
                'attempt-{0:D2}' -f $attempt)
            [IO.Directory]::CreateDirectory($attemptOutput) | Out-Null
            & $modProbe @(
                $runtime,
                $attemptOutput,
                $level,
                60,
                $route.out_x,
                $route.out_y,
                $route.back_x,
                $route.back_y,
                "--identity-catalog=$identityCatalog",
                '--movement-only',
                "--movement-player-scene=$($route.scene)",
                "--movement-observation-ms=$observationMilliseconds",
                "--parity-scenario=$scenarioId")
            if ($LASTEXITCODE -eq 0) {
                $successfulModOutput = $attemptOutput
                break
            }
            Write-Warning (
                "Stable MOD exited during $levelId attempt $attempt; " +
                'the isolated attempt evidence was retained.')
            Start-Sleep -Milliseconds 500
        }
        if ([string]::IsNullOrWhiteSpace($successfulModOutput)) {
            throw "Stable MOD player-route probe failed for $levelId."
        }
        $modTrace = Join-Path $successfulModOutput "mod-$scenarioId.json"
        if (-not (Test-Path -LiteralPath $modTrace -PathType Leaf)) {
            throw "Stable MOD movement trace was not produced: $modTrace"
        }

        $baselineTrace = Join-Path $baselineRoot "$scenarioId.json"
        if ($UpdateBaselines) {
            Copy-Item -LiteralPath $modTrace -Destination $baselineTrace -Force
        }
        elseif (-not (Test-Path -LiteralPath $baselineTrace -PathType Leaf)) {
            throw (
                "Stable MOD baseline is missing for $levelId. " +
                'Use -UpdateBaselines after auditing the isolated capture.')
        }

        $outboundWorld = '{0},{1}' -f (
            [int]$route.out_x * 32 + 16), (
            [int]$route.out_y * 16 + 8)
        $returnWorld = '{0},{1}' -f (
            [int]$route.back_x * 32 + 16), (
            [int]$route.back_y * 16 + 8)
        $observationSeconds = $observationMilliseconds / 1000.0
        Write-Host "Capturing Remake player route for $levelId..."
        & $GodotExecutable @(
            '--headless',
            '--path',
            $gameRoot,
            '--max-fps',
            '60',
            '--disable-vsync',
            '--script',
            'res://tests/parity_runtime_probe.gd',
            '--',
            "--output-dir=$remakeOutput",
            "--level-id=$levelId",
            "--scenario-id=$scenarioId",
            "--player-scene-index=$($route.scene)",
            "--outbound-target=$outboundWorld",
            "--return-target=$returnWorld",
            "--observation-seconds=$observationSeconds",
            '--command-handoff-seconds=0.30')
        if ($LASTEXITCODE -ne 0) {
            throw "Remake player-route probe failed for $levelId."
        }
        $remakeTrace = Join-Path $remakeOutput "remake-$scenarioId.json"
        if (-not (Test-Path -LiteralPath $remakeTrace -PathType Leaf)) {
            throw "Remake movement trace was not produced: $remakeTrace"
        }

        $comparisonJson = Join-Path $comparisonOutput (
            "$scenarioId-comparison.json")
        $comparisonMarkdown = Join-Path $comparisonOutput (
            "$scenarioId-comparison.md")
        $comparison = & (
            Join-Path $PSScriptRoot 'Compare-RuntimeParityTrace.ps1') `
             -ReferenceTrace $baselineTrace `
             -CandidateTrace $remakeTrace `
             -SceneIndices ([int]$route.scene) `
             -IgnoreHitPoints `
             -IgnoreAliveState `
             -CompareObservedRouteShape `
             -ElapsedToleranceMs 1800 `
            -AllowMismatch `
            -OutputJson $comparisonJson `
            -OutputMarkdown $comparisonMarkdown
        $results.Add([pscustomobject][ordered]@{
            level_id = $levelId
            selector_level = $level
            player_scene_index = [int]$route.scene
            outbound_cell = @([int]$route.out_x, [int]$route.out_y)
            return_cell = @([int]$route.back_x, [int]$route.back_y)
            mismatch_count = [int]$comparison.mismatch_count
            passed = [bool]$comparison.passed
            mod_trace = $modTrace
            remake_trace = $remakeTrace
            comparison = $comparisonJson
        })
    }
    $completed = $true
}
finally {
    if (-not $KeepRuntime) {
        $resolvedRuntime = [IO.Path]::GetFullPath($runtime)
        $safePrefix = [IO.Path]::Combine(
            $temporaryRoot,
            $runtimePrefix)
        if (-not $resolvedRuntime.StartsWith(
                $safePrefix,
                [StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to remove unexpected runtime: $resolvedRuntime"
        }
        if (Test-Path -LiteralPath $resolvedRuntime) {
            for ($attempt = 0; $attempt -lt 8; ++$attempt) {
                try {
                    Remove-Item -LiteralPath $resolvedRuntime `
                        -Recurse -Force -ErrorAction Stop
                    break
                }
                catch {
                    if ($attempt -eq 7) {
                        Write-Warning (
                            'The isolated movement runtime remains locked: ' +
                            $resolvedRuntime)
                    }
                    else {
                        Start-Sleep -Milliseconds 250
                    }
                }
            }
        }
    }
}

$allPassed = $completed -and @(
    $results | Where-Object { -not $_.passed }).Count -eq 0
$summary = [pscustomobject][ordered]@{
    schema_version = 1
    content_profile = 'repository-mod-12-level-20260729'
    generated_utc = [DateTime]::UtcNow.ToString('o')
    input_isolation = 'window-message-to-process-local-DirectInput'
    system_cursor_calls = 0
    global_focus_calls = 0
    levels = @($results)
    passed = $allPassed
}
$summaryJson = Join-Path $OutputDirectory 'summary.json'
$summary | ConvertTo-Json -Depth 8 |
    Set-Content -LiteralPath $summaryJson -Encoding UTF8

$markdown = [Collections.Generic.List[string]]::new()
$markdown.Add('# Twelve-level player movement parity')
$markdown.Add('')
$markdown.Add(
    'Each route starts from an audited original player scene and crosses ' +
    'nearby baked VWF L3 obstacles. Input is delivered only to the isolated ' +
    'target process; the system cursor and foreground window are untouched.')
$markdown.Add('')
$markdown.Add(
    '| Level | Player scene | Outbound cell | Return cell | Mismatches | Result |')
$markdown.Add('|---|---:|---:|---:|---:|---|')
foreach ($result in $results) {
    $markdown.Add(
        '| {0} | {1} | {2},{3} | {4},{5} | {6} | {7} |' -f @(
            $result.level_id,
            $result.player_scene_index,
            $result.outbound_cell[0],
            $result.outbound_cell[1],
            $result.return_cell[0],
            $result.return_cell[1],
            $result.mismatch_count,
            $(if ($result.passed) { 'pass' } else { 'fail' })))
}
$markdown.Add('')
$markdown.Add('Overall: ' + $(if ($allPassed) { 'pass' } else { 'fail' }))
$summaryMarkdown = Join-Path $OutputDirectory 'summary.md'
$markdown | Set-Content -LiteralPath $summaryMarkdown -Encoding UTF8

Write-Host "Movement parity summary: $summaryMarkdown"
if (-not $allPassed -and -not $AllowMismatch) {
    throw 'One or more player movement comparisons failed.'
}
