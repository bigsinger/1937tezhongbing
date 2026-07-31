[CmdletBinding()]
param(
    [string]$GodotExecutable = '',

    [string]$OutputDirectory = '',

    [switch]$UpdateBaseline,

    [switch]$KeepRuntime
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$remakeRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $remakeRoot '..'))
$gameRoot = Join-Path $remakeRoot 'game'
$modRoot = Join-Path $repositoryRoot 'Mod'
$baselinePath = Join-Path $remakeRoot (
    'validation\baselines\mod\' +
    'm010-briefing-left-click-dismissal-v1.json')
$probeBuildRoot = 'E:\1937\probe-build'
$temporaryRoot = [IO.Path]::GetFullPath('E:\1937\')
$scenarioId = 'm010-briefing-left-click-dismissal-v1'

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $remakeRoot (
        'LocalAssets\qa\briefing-input-parity-' +
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

if (-not ('BriefingParityIni' -as [type])) {
    Add-Type -TypeDefinition @'
using System.Runtime.InteropServices;
public static class BriefingParityIni
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

    if (-not [BriefingParityIni]::WritePrivateProfileString(
            $Section, $Key, $Value, $Path)) {
        throw "Could not write isolated INI value [$Section] $Key."
    }
}

function Stage-ByName {
    param($Result, [string]$Name)

    return @(
        $Result.stages |
            Where-Object { [string]$_.name -ceq $Name }
    ) | Select-Object -First 1
}

function Evidence-Bool {
    param([string]$Evidence, [string]$Key)

    $match = [regex]::Match(
        $Evidence,
        '(?:^|;\s*)' + [regex]::Escape($Key) +
            '=(?<value>true|false)',
        [Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if (-not $match.Success) {
        throw "Evidence field '$Key' is missing: $Evidence"
    }
    return [bool]::Parse($match.Groups['value'].Value)
}

function Evidence-Int {
    param([string]$Evidence, [string]$Key)

    $match = [regex]::Match(
        $Evidence,
        '(?:^|;\s*)' + [regex]::Escape($Key) +
            '=(?<value>-?\d+)',
        [Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if (-not $match.Success) {
        throw "Evidence field '$Key' is missing: $Evidence"
    }
    return [int]$match.Groups['value'].Value
}

function Convert-ModBriefingResult {
    param([Parameter(Mandatory)]$Result)

    $visible = Stage-ByName $Result 'briefing_route_and_original_flow'
    $dismissed = Stage-ByName $Result 'briefing_dismissed'
    if ($null -eq $visible -or $null -eq $dismissed) {
        throw 'Stable MOD briefing result is missing a required stage.'
    }
    $worldActors = Evidence-Int $visible.evidence 'world_actors'
    $surfaceNonBlank = Evidence-Bool `
        $visible.evidence 'surface_non_blank'
    $sameWindow = Evidence-Bool $visible.evidence 'same_main_window'
    $externalDialog = Evidence-Bool $visible.evidence 'external_dialog'
    $inputDelivered = Evidence-Bool `
        $dismissed.evidence 'process_local_mouse'
    $worldAdvanced = Evidence-Bool `
        $dismissed.evidence 'world_state_advanced'

    return [pscustomobject][ordered]@{
        schema_version = 1
        runtime = 'mod'
        content_profile = 'repository-mod-12-level-20260729'
        level = [pscustomobject][ordered]@{
            id = 'm010'
            selector_level = 11
            engine_mission = 11
        }
        scenario = [pscustomobject][ordered]@{
            id = $scenarioId
            input = 'left_mouse_press_release'
        }
        metadata = [pscustomobject][ordered]@{
            input_isolation = 'process-local-DirectInput'
            global_pointer_control = $false
            same_main_window = $sameWindow
            external_dialog = $externalDialog
        }
        checkpoints = @(
            [pscustomobject][ordered]@{
                id = 'briefing_visible'
                modal_visible = (
                    [bool]$visible.sent -and
                    [bool]$visible.responding -and
                    $surfaceNonBlank)
                world_state_active = $worldActors -gt 0
                surface_non_blank = $surfaceNonBlank
            },
            [pscustomobject][ordered]@{
                id = 'briefing_dismissed'
                input_delivered = $inputDelivered
                world_state_active = $worldAdvanced
            }
        )
        passed = (
            [bool]$Result.passed -and
            [bool]$visible.sent -and
            [bool]$visible.responding -and
            [bool]$dismissed.sent -and
            [bool]$dismissed.responding)
    }
}

$runtime = Join-Path $temporaryRoot (
    'mod-briefing-parity-runtime-' +
    [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($runtime) | Out-Null
Get-ChildItem -LiteralPath $modRoot -Force | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName `
        -Destination $runtime -Recurse -Force
}

$completed = $false
try {
    $runtimeIni = Join-Path $runtime 'rungame.ini'
    $runtimeDdraw = Join-Path $runtime 'ddraw.ini'
    Set-IniValue $runtimeIni 'mod' 'Enabled' '1'
    Set-IniValue $runtimeIni 'mod' 'SystemCursorMapping' '0'
    Set-IniValue $runtimeIni 'mod' 'AutoStart' '0'
    Set-IniValue $runtimeIni 'mod' 'PreserveLegacyUI' '1'
    Set-IniValue $runtimeIni 'mod' 'ExpandedViewport' '0'
    Set-IniValue $runtimeDdraw 'ddraw' 'fullscreen' 'false'
    Set-IniValue $runtimeDdraw 'ddraw' 'windowed' 'true'
    Set-IniValue $runtimeDdraw 'ddraw' 'width' '1024'
    Set-IniValue $runtimeDdraw 'ddraw' 'height' '768'
    Set-IniValue $runtimeDdraw 'ddraw' 'devmode' 'true'
    Set-IniValue $runtimeDdraw 'ddraw' 'no_dinput_hook' 'true'
    Set-IniValue $runtimeDdraw 'ddraw' 'adjmouse' 'false'
    Set-IniValue $runtimeDdraw 'ddraw' 'savesettings' '0'

    $modOutput = Join-Path $OutputDirectory 'mod\m010'
    $remakeOutput = Join-Path $OutputDirectory 'remake\m010'
    $comparisonOutput = Join-Path $OutputDirectory 'comparison\m010'
    foreach ($directory in @(
            $modOutput,
            $remakeOutput,
            $comparisonOutput)) {
        [IO.Directory]::CreateDirectory($directory) | Out-Null
    }

    Write-Host 'Capturing stable MOD briefing dismissal'
    & $modProbe @(
        $runtime,
        $modOutput,
        11,
        45,
        '--briefing-dismissal-only')
    if ($LASTEXITCODE -ne 0) {
        throw 'Stable MOD briefing-dismissal probe failed.'
    }
    $rawModResultPath = Join-Path $modOutput 'result.json'
    $rawModResult = Get-Content -LiteralPath $rawModResultPath `
        -Raw -Encoding UTF8 | ConvertFrom-Json
    $modTrace = Join-Path $modOutput "mod-$scenarioId.json"
    $normalizedMod = Convert-ModBriefingResult $rawModResult
    $normalizedMod | ConvertTo-Json -Depth 20 |
        Set-Content -LiteralPath $modTrace -Encoding UTF8
    if (-not $normalizedMod.passed) {
        throw 'Stable MOD normalized briefing trace failed.'
    }

    if ($UpdateBaseline) {
        [IO.Directory]::CreateDirectory(
            [IO.Path]::GetDirectoryName($baselinePath)) | Out-Null
        Copy-Item -LiteralPath $modTrace -Destination $baselinePath -Force
    }
    elseif (-not (Test-Path -LiteralPath $baselinePath -PathType Leaf)) {
        throw (
            'Stable MOD briefing baseline is missing. Audit an isolated ' +
            'capture, then use -UpdateBaseline once.')
    }

    $baseline = Get-Content -LiteralPath $baselinePath `
        -Raw -Encoding UTF8 | ConvertFrom-Json
    $baselineJson = $baseline | ConvertTo-Json -Depth 20 -Compress
    $recaptureJson = $normalizedMod | ConvertTo-Json -Depth 20 -Compress
    if ($baselineJson -cne $recaptureJson) {
        throw 'Stable MOD briefing recapture differs from its normalized baseline.'
    }

    Write-Host 'Capturing Remake briefing dismissal'
    $remakeTrace = Join-Path $remakeOutput "remake-$scenarioId.json"
    & $GodotExecutable @(
        '--headless',
        '--path',
        $gameRoot,
        '--log-file',
        (Join-Path $remakeOutput 'godot.log'),
        '--script',
        'res://tests/briefing_input_parity_probe.gd',
        '--',
        "--output=$remakeTrace")
    if ($LASTEXITCODE -ne 0) {
        throw 'Remake briefing-input probe failed.'
    }

    $comparisonTool = Join-Path `
        $PSScriptRoot 'Compare-BriefingInputParity.ps1'
    $comparisonJson = Join-Path `
        $comparisonOutput "$scenarioId-comparison.json"
    $comparisonMarkdown = Join-Path `
        $comparisonOutput "$scenarioId-comparison.md"
    $comparison = & $comparisonTool `
        -ReferenceTrace $baselinePath `
        -CandidateTrace $remakeTrace `
        -OutputJson $comparisonJson `
        -OutputMarkdown $comparisonMarkdown

    $summaryPath = Join-Path `
        $OutputDirectory 'briefing-input-parity-summary.json'
    [pscustomobject][ordered]@{
        schema_version = 1
        scenario_id = $scenarioId
        passed = [bool]$comparison.passed
        mismatch_count = [int]$comparison.mismatch_count
        mod_trace = $modTrace
        remake_trace = $remakeTrace
        comparison = $comparisonJson
        global_pointer_control = $false
    } | ConvertTo-Json -Depth 20 |
        Set-Content -LiteralPath $summaryPath -Encoding UTF8
    Write-Host "Briefing input parity evidence: $summaryPath"
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
                'mod-briefing-parity-runtime-*') {
            throw (
                'Refusing to remove briefing probe output outside the ' +
                'validated E:\1937 temporary root.')
        }
        Remove-Item -LiteralPath $resolvedRuntime -Recurse -Force
    }
    elseif ($KeepRuntime) {
        Write-Host "Isolated MOD runtime retained: $runtime"
    }
}

if (-not $completed) {
    throw 'Briefing input parity capture did not complete.'
}
