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
$runtimePrefix = 'mod-native-mission-failure-runtime-'

$routes = @(
    [pscustomobject]@{ level = 1; scene = 1436 },
    [pscustomobject]@{ level = 2; scene = 1994 },
    [pscustomobject]@{ level = 3; scene = 886 },
    [pscustomobject]@{ level = 4; scene = 1150 },
    [pscustomobject]@{ level = 5; scene = 2629 },
    [pscustomobject]@{ level = 6; scene = 663 },
    [pscustomobject]@{ level = 7; scene = 1458 },
    [pscustomobject]@{ level = 8; scene = 2325 },
    [pscustomobject]@{ level = 9; scene = 753 },
    [pscustomobject]@{ level = 10; scene = 1709 },
    [pscustomobject]@{ level = 11; scene = 1590 },
    [pscustomobject]@{ level = 12; scene = 1176 }
)

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $remakeRoot (
        'LocalAssets\qa\twelve-level-native-mission-failure-' +
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
    Copy-Item -LiteralPath $_.FullName `
        -Destination $runtime -Recurse -Force
}

if (-not ('NativeMissionFailureIniV1' -as [type])) {
    Add-Type -TypeDefinition @'
using System.Runtime.InteropServices;
public static class NativeMissionFailureIniV1
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
    if (-not [NativeMissionFailureIniV1]::WritePrivateProfileString(
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
        @($runtimeIni, 'mod', 'TelemetryIntervalMs', '100'),
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
            throw "Native failure route is missing for level $level."
        }
        $levelId = 'm{0:D3}' -f ($level - 1)
        $scenarioId = "$levelId-native-required-player-failure-v1"
        $identityCatalog = Join-Path $identityRoot (
            "$levelId-runtime-actors-v1.json")
        if (-not (Test-Path -LiteralPath $identityCatalog -PathType Leaf)) {
            throw "Runtime actor identity catalog is missing: $identityCatalog"
        }

        Get-ChildItem -LiteralPath $runtime -File -Force |
            Where-Object {
                $_.Name -like '1937M*.SAV' -or
                $_.Name -in @(
                    'M1937Mod.log',
                    'M1937Telemetry.jsonl')
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

        Write-Host "Observing stable MOD native mission failure for $levelId..."
        $successfulModOutput = ''
        foreach ($attempt in 1..2) {
            $attemptOutput = Join-Path $modOutput (
                'attempt-{0:D2}' -f $attempt)
            [IO.Directory]::CreateDirectory($attemptOutput) | Out-Null
            & $modProbe @(
                $runtime,
                $attemptOutput,
                $level,
                45,
                "--identity-catalog=$identityCatalog",
                '--native-mission-failure-only',
                "--native-failure-scene=$($route.scene)")
            if ($LASTEXITCODE -eq 0) {
                $successfulModOutput = $attemptOutput
                break
            }
            Write-Warning (
                "Stable MOD exited during $levelId attempt $attempt; " +
                'the isolated evidence was retained.')
            Start-Sleep -Milliseconds 500
        }
        if ([string]::IsNullOrWhiteSpace($successfulModOutput)) {
            throw "Stable MOD native mission-failure probe failed for $levelId."
        }
        $modTrace = Join-Path $successfulModOutput "mod-$scenarioId.json"
        if (-not (Test-Path -LiteralPath $modTrace -PathType Leaf)) {
            throw "Stable MOD native failure trace is missing: $modTrace"
        }

        $baselineTrace = Join-Path $baselineRoot "$scenarioId.json"
        if ($UpdateBaselines) {
            Copy-Item -LiteralPath $modTrace `
                -Destination $baselineTrace -Force
        }
        elseif (-not (Test-Path -LiteralPath $baselineTrace -PathType Leaf)) {
            throw (
                "Stable MOD baseline is missing for $levelId. " +
                'Use -UpdateBaselines after auditing the isolated capture.')
        }

        Write-Host "Replaying Remake required-player failure for $levelId..."
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
            "--scenario-id=$scenarioId")
        if ($LASTEXITCODE -ne 0) {
            throw "Remake native mission-failure probe failed for $levelId."
        }
        $remakeTrace = Join-Path $remakeOutput "remake-$scenarioId.json"
        if (-not (Test-Path -LiteralPath $remakeTrace -PathType Leaf)) {
            throw "Remake native failure trace is missing: $remakeTrace"
        }

        $comparisonJson = Join-Path $comparisonOutput (
            "$scenarioId-comparison.json")
        $comparisonMarkdown = Join-Path $comparisonOutput (
            "$scenarioId-comparison.md")
        $comparison = & (
            Join-Path $PSScriptRoot `
                'Compare-NativeMissionFailureParity.ps1') `
            -ReferenceTrace $baselineTrace `
            -CandidateTrace $remakeTrace `
            -OutputJson $comparisonJson `
            -OutputMarkdown $comparisonMarkdown
        $results.Add([pscustomobject][ordered]@{
            level_id = $levelId
            selector_level = $level
            required_player_scene_index = [int]$route.scene
            check_count = [int]$comparison.check_count
            mismatch_count = @($comparison.mismatches).Count
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
                            'The isolated native-failure runtime remains ' +
                            "locked: $resolvedRuntime")
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
    input_isolation = 'private-window-message'
    mission_result_writes = 0
    system_cursor_calls = 0
    global_focus_calls = 0
    levels = @($results)
    passed = $allPassed
}
$summaryJson = Join-Path $OutputDirectory 'summary.json'
$summary | ConvertTo-Json -Depth 8 |
    Set-Content -LiteralPath $summaryJson -Encoding UTF8

$markdown = [Collections.Generic.List[string]]::new()
$markdown.Add('# Twelve-level native mission failure parity')
$markdown.Add('')
$markdown.Add(
    'Each stable-MOD run invokes the original actor damage routine at a ' +
    'process-local replay boundary and only observes the original mission ' +
    'evaluator. No mission field, system cursor or foreground window is changed.')
$markdown.Add('')
$markdown.Add('| Level | Required scene | Checks | Mismatches | Result |')
$markdown.Add('|---|---:|---:|---:|---|')
foreach ($result in $results) {
    $markdown.Add(
        '| {0} | {1} | {2} | {3} | {4} |' -f @(
            $result.level_id,
            $result.required_player_scene_index,
            $result.check_count,
            $result.mismatch_count,
            $(if ($result.passed) { 'pass' } else { 'fail' })))
}
$markdown.Add('')
$markdown.Add('Overall: ' + $(if ($allPassed) { 'pass' } else { 'fail' }))
$summaryMarkdown = Join-Path $OutputDirectory 'summary.md'
$markdown | Set-Content -LiteralPath $summaryMarkdown -Encoding UTF8

Write-Host "Native mission failure parity summary: $summaryMarkdown"
if (-not $allPassed -and -not $AllowMismatch) {
    throw 'One or more native mission failure comparisons failed.'
}
