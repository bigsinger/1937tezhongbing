[CmdletBinding()]
param(
    [string]$GodotExecutable = '',

    [string]$OutputDirectory = '',

    [string[]]$ScenarioId = @(),

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
$probeBuildRoot = Join-Path 'E:\1937' 'probe-build'
$temporaryRoot = [IO.Path]::GetFullPath('E:\1937\')

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $remakeRoot (
        'LocalAssets\qa\inventory-parity-' +
        (Get-Date -Format 'yyyyMMdd-HHmmss'))
}
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
[IO.Directory]::CreateDirectory($OutputDirectory) | Out-Null

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
    'mod-inventory-parity-runtime-' +
    [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($runtime) | Out-Null
Get-ChildItem -LiteralPath $modRoot -Force | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName `
        -Destination $runtime -Recurse -Force
}

if (-not ('InventoryParityIni' -as [type])) {
    Add-Type -TypeDefinition @'
using System.Runtime.InteropServices;
public static class InventoryParityIni
{
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    public static extern bool WritePrivateProfileString(
        string section, string key, string value, string path);
}
'@
}

function Set-IniValue {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Section,
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][string]$Value
    )

    if (-not [InventoryParityIni]::WritePrivateProfileString(
            $Section, $Key, $Value, $Path)) {
        throw "Could not write isolated INI value [$Section] $Key."
    }
}

$runtimeIni = Join-Path $runtime 'rungame.ini'
$runtimeDdraw = Join-Path $runtime 'ddraw.ini'
Set-IniValue $runtimeIni 'mod' 'Enabled' '1'
Set-IniValue $runtimeIni 'mod' 'Diagnostics' '1'
Set-IniValue $runtimeIni 'mod' 'Telemetry' '1'
Set-IniValue $runtimeIni 'mod' 'TelemetryIntervalMs' '250'
Set-IniValue $runtimeIni 'mod' 'SystemCursorMapping' '0'
Set-IniValue $runtimeIni 'mod' 'AutoStart' '0'
Set-IniValue $runtimeIni 'mod' 'PreserveLegacyUI' '1'
Set-IniValue $runtimeIni 'mod' 'ExpandedViewport' '0'
Set-IniValue $runtimeIni 'mod' 'AILevel' '3'
Set-IniValue $runtimeIni 'mod' 'Difficulty' '1'
Set-IniValue $runtimeDdraw 'ddraw' 'fullscreen' 'false'
Set-IniValue $runtimeDdraw 'ddraw' 'windowed' 'true'
Set-IniValue $runtimeDdraw 'ddraw' 'width' '1024'
Set-IniValue $runtimeDdraw 'ddraw' 'height' '768'
Set-IniValue $runtimeDdraw 'ddraw' 'devmode' 'true'
Set-IniValue $runtimeDdraw 'ddraw' 'no_dinput_hook' 'true'
Set-IniValue $runtimeDdraw 'ddraw' 'adjmouse' 'false'
Set-IniValue $runtimeDdraw 'ddraw' 'savesettings' '0'
Set-IniValue $runtimeDdraw 'ddraw' 'noactivateapp' 'false'

$scenarios = @(
    [pscustomobject]@{
        id = 'm001-mine-pickup-inventory-v1'
        level_id = 'm001'
        selector_level = 2
        parity_flag = '--parity-pickup-only'
    },
    [pscustomobject]@{
        id = 'm000-pistol-attack-inventory-v1'
        level_id = 'm000'
        selector_level = 1
        parity_flag = '--parity-attack-only'
    },
    [pscustomobject]@{
        id = 'm010-rifle-attack-inventory-v1'
        level_id = 'm010'
        selector_level = 11
        parity_flag = '--parity-attack-only'
    },
    [pscustomobject]@{
        id = 'm010-machine-gun-attack-inventory-v1'
        level_id = 'm010'
        selector_level = 11
        parity_flag = '--parity-attack-only'
    },
    [pscustomobject]@{
        id = 'm004-dart-attack-inventory-v1'
        level_id = 'm004'
        selector_level = 5
        parity_flag = '--parity-attack-only'
    },
    [pscustomobject]@{
        id = 'm007-special-attention-attack-inventory-v1'
        level_id = 'm007'
        selector_level = 8
        parity_flag = '--parity-attack-only'
    },
    [pscustomobject]@{
        id = 'm010-dagger-attack-inventory-v1'
        level_id = 'm010'
        selector_level = 11
        parity_flag = '--parity-attack-only'
    },
    [pscustomobject]@{
        id = 'm010-broadsword-attack-inventory-v1'
        level_id = 'm010'
        selector_level = 11
        parity_flag = '--parity-attack-only'
    },
    [pscustomobject]@{
        id = 'm010-grenade-attack-inventory-v1'
        level_id = 'm010'
        selector_level = 11
        parity_flag = '--parity-attack-only'
    },
    [pscustomobject]@{
        id = 'm010-mine-deploy-inventory-v1'
        level_id = 'm010'
        selector_level = 11
        parity_flag = '--parity-attack-only'
    },
    [pscustomobject]@{
        id = 'm010-explosive-deploy-inventory-v1'
        level_id = 'm010'
        selector_level = 11
        parity_flag = '--parity-attack-only'
    },
    [pscustomobject]@{
        id = 'm007-chicken-world-item-v1'
        level_id = 'm007'
        selector_level = 8
        parity_flag = '--parity-world-item-only'
    },
    [pscustomobject]@{
        id = 'm010-canned-meat-world-item-v1'
        level_id = 'm010'
        selector_level = 11
        parity_flag = '--parity-world-item-only'
    },
    [pscustomobject]@{
        id = 'm010-hypnosis-doll-world-item-v1'
        level_id = 'm010'
        selector_level = 11
        parity_flag = '--parity-world-item-only'
    },
    [pscustomobject]@{
        id = 'm010-poisoned-wine-world-item-v1'
        level_id = 'm010'
        selector_level = 11
        parity_flag = '--parity-world-item-only'
    },
    [pscustomobject]@{
        id = 'm009-dog-bone-world-item-v1'
        level_id = 'm009'
        selector_level = 10
        parity_flag = '--parity-world-item-only'
    },
    [pscustomobject]@{
        id = 'm010-cigarette-world-item-v1'
        level_id = 'm010'
        selector_level = 11
        parity_flag = '--parity-world-item-only'
    },
    [pscustomobject]@{
        id = 'm010-sight-direct-target-v1'
        level_id = 'm010'
        selector_level = 11
        parity_flag = '--parity-sb-only'
    },
    [pscustomobject]@{
        id = 'm010-burial-command-v1'
        level_id = 'm010'
        selector_level = 11
        parity_flag = '--parity-sb-only'
    }
)
if ($ScenarioId.Count -gt 0) {
    $requestedScenarioIds = @(
        $ScenarioId |
            ForEach-Object { $_.Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Select-Object -Unique
    )
    $unknownScenarioIds = @(
        $requestedScenarioIds |
            Where-Object { $_ -notin @($scenarios.id) }
    )
    if ($unknownScenarioIds.Count -gt 0) {
        throw (
            'Unknown inventory parity scenario(s): ' +
            ($unknownScenarioIds -join ', '))
    }
    $scenarios = @(
        $scenarios |
            Where-Object { $_.id -in $requestedScenarioIds }
    )
}

$results = [Collections.Generic.List[object]]::new()
$completed = $false
try {
    foreach ($scenario in $scenarios) {
        Get-ChildItem -LiteralPath $runtime -File -Force |
            Where-Object {
                $_.Name -like '1937M*.SAV' -or
                $_.Name -in @(
                    'M1937Mod.log',
                    'M1937Telemetry.jsonl')
            } |
            Remove-Item -Force

        $modOutput = Join-Path $OutputDirectory (
            'mod\' + $scenario.level_id)
        $remakeOutput = Join-Path $OutputDirectory (
            'remake\' + $scenario.level_id)
        $comparisonOutput = Join-Path $OutputDirectory (
            'comparison\' + $scenario.level_id)
        foreach ($directory in @(
                $modOutput,
                $remakeOutput,
                $comparisonOutput)) {
            [IO.Directory]::CreateDirectory($directory) | Out-Null
        }

        $identityCatalog = Join-Path $identityRoot (
            "$($scenario.level_id)-runtime-actors-v1.json")
        if (-not (Test-Path -LiteralPath $identityCatalog -PathType Leaf)) {
            throw "Runtime identity catalog is missing: $identityCatalog"
        }

        Write-Host "Capturing stable MOD trace: $($scenario.id)"
        $maximumProbeAttempts =
            if ($scenario.parity_flag -eq '--parity-world-item-only') {
                3
            } else {
                1
            }
        $modProbePassed = $false
        for ($probeAttempt = 1;
             $probeAttempt -le $maximumProbeAttempts;
             ++$probeAttempt) {
            if ($probeAttempt -gt 1) {
                Write-Warning (
                    "Retrying isolated stable MOD trace $($scenario.id) " +
                    "($probeAttempt/$maximumProbeAttempts) after the original " +
                    'actor factory declined the prior timing boundary.')
                Get-ChildItem -LiteralPath $runtime -File -Force |
                    Where-Object {
                        $_.Name -like '1937M*.SAV' -or
                        $_.Name -in @(
                            'M1937Mod.log',
                            'M1937Telemetry.jsonl')
                    } |
                    Remove-Item -Force
            }
            & $modProbe @(
                $runtime,
                $modOutput,
                $scenario.selector_level,
                60,
                "--identity-catalog=$identityCatalog",
                $scenario.parity_flag,
                "--parity-scenario=$($scenario.id)")
            if ($LASTEXITCODE -eq 0) {
                $modProbePassed = $true
                break
            }
        }
        if (-not $modProbePassed) {
            throw "Stable MOD inventory probe failed: $($scenario.id)"
        }
        $modTrace = Join-Path $modOutput "mod-$($scenario.id).json"
        if (-not (Test-Path -LiteralPath $modTrace -PathType Leaf)) {
            throw "Stable MOD trace was not produced: $modTrace"
        }

        $baselineTrace = Join-Path $baselineRoot "$($scenario.id).json"
        if ($UpdateBaselines) {
            Copy-Item -LiteralPath $modTrace `
                -Destination $baselineTrace -Force
        }
        elseif (-not (Test-Path -LiteralPath $baselineTrace -PathType Leaf)) {
            throw (
                'Stable MOD baseline is missing. Use -UpdateBaselines only ' +
                'after auditing an isolated capture: ' + $baselineTrace)
        }

        $baselineComparison = Join-Path $comparisonOutput (
            "$($scenario.id)-mod-recapture.json")
        $comparisonToolName = 'Compare-InventoryParityTrace.ps1'
        if ($scenario.id -in @(
                'm010-sight-direct-target-v1',
                'm010-burial-command-v1')) {
            $comparisonToolName = 'Compare-ContextualCommandParity.ps1'
        }
        $comparisonTool = Join-Path $PSScriptRoot $comparisonToolName
        & $comparisonTool `
            -ReferenceTrace $baselineTrace `
            -CandidateTrace $modTrace `
            -AllowMismatch:$AllowMismatch `
            -OutputJson $baselineComparison | Out-Null

        Write-Host "Capturing Remake trace: $($scenario.id)"
        $godotLog = Join-Path $remakeOutput 'godot.log'
        & $GodotExecutable @(
            '--headless',
            '--path',
            $gameRoot,
            '--max-fps',
            '60',
            '--disable-vsync',
            '--log-file',
            $godotLog,
            '--script',
            'res://tests/parity_runtime_probe.gd',
            '--',
            "--output-dir=$remakeOutput",
            "--level-id=$($scenario.level_id)",
            "--scenario-id=$($scenario.id)")
        if ($LASTEXITCODE -ne 0) {
            throw "Remake inventory probe failed: $($scenario.id)"
        }
        $remakeTrace = Join-Path $remakeOutput (
            "remake-$($scenario.id).json")
        if (-not (Test-Path -LiteralPath $remakeTrace -PathType Leaf)) {
            throw "Remake trace was not produced: $remakeTrace"
        }

        $comparisonJson = Join-Path $comparisonOutput (
            "$($scenario.id)-comparison.json")
        $comparisonMarkdown = Join-Path $comparisonOutput (
            "$($scenario.id)-comparison.md")
        $comparison = & $comparisonTool `
            -ReferenceTrace $baselineTrace `
            -CandidateTrace $remakeTrace `
            -AllowMismatch:$AllowMismatch `
            -OutputJson $comparisonJson `
            -OutputMarkdown $comparisonMarkdown
        $results.Add([pscustomobject][ordered]@{
            scenario_id = $scenario.id
            passed = [bool]$comparison.passed
            mismatch_count = [int]$comparison.mismatch_count
            mod_trace = $modTrace
            remake_trace = $remakeTrace
            comparison = $comparisonJson
        })
    }

    $summaryPath = Join-Path $OutputDirectory 'inventory-parity-summary.json'
    [pscustomobject][ordered]@{
        schema_version = 1
        input_isolation = (
            'target-window messages and process-local DirectInput only; ' +
            'world-item scenarios use the opt-in original actor factory ' +
            'inside the isolated process; no global cursor APIs')
        result_count = $results.Count
        passed = @($results | Where-Object { -not $_.passed }).Count -eq 0
        results = @($results)
    } | ConvertTo-Json -Depth 20 |
        Set-Content -LiteralPath $summaryPath -Encoding UTF8
    Write-Host "Inventory parity evidence: $summaryPath"
    $completed = $true
}
finally {
    if (-not $KeepRuntime -and
        (Test-Path -LiteralPath $runtime -PathType Container)) {
        $resolvedRuntime = [IO.Path]::GetFullPath($runtime)
        if (-not $resolvedRuntime.StartsWith(
                $temporaryRoot,
                [StringComparison]::OrdinalIgnoreCase) -or
            [IO.Path]::GetFileName($resolvedRuntime) -notlike
                'mod-inventory-parity-runtime-*') {
            throw (
                'Refusing to remove inventory probe output outside the ' +
                'validated E:\1937 temporary root.')
        }
        Remove-Item -LiteralPath $resolvedRuntime -Recurse -Force
    }
    elseif ($KeepRuntime) {
        Write-Host "Isolated MOD runtime retained: $runtime"
    }
}

if (-not $completed) {
    throw 'Inventory parity capture did not complete.'
}
