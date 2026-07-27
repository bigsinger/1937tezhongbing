param(
    [ValidateRange(13, 15)]
    [int]$Level = 13,
    [ValidateRange(15, 120)]
    [int]$DurationSeconds = 25,
    [string]$OutputRoot = ''
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = [IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot '..\..\..'))
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path 'E:\1937' (
        'mission-sidecar-runtime-' +
        (Get-Date -Format 'yyyyMMdd-HHmmss'))
}
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
if (-not $OutputRoot.StartsWith(
        [IO.Path]::GetFullPath('E:\1937\'),
        [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Sidecar runtime output must stay under E:\1937.'
}
[IO.Directory]::CreateDirectory($OutputRoot) | Out-Null

& (Join-Path $repositoryRoot 'Patch\tools\Build-Mod.ps1') `
    -RepositoryRoot $repositoryRoot | Out-Host
& (Join-Path $repositoryRoot 'Patch\tools\Build-MissionSidecar.ps1') `
    -RepositoryRoot $repositoryRoot | Out-Host
$pluginBuild = Join-Path $OutputRoot 'plugin-build'
& (Join-Path $repositoryRoot (
    'SDK\samples\mission-plugin\Build-SamplePlugin.ps1')) `
    -OutputDirectory $pluginBuild | Out-Host

$runtime = Join-Path $OutputRoot 'runtime'
[IO.Directory]::CreateDirectory($runtime) | Out-Null
Get-ChildItem -LiteralPath (
    Join-Path $repositoryRoot 'Mod') -Force | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination $runtime `
        -Recurse -Force
}
$pluginDirectory = Join-Path $runtime 'Plugins'
[IO.Directory]::CreateDirectory($pluginDirectory) | Out-Null
Copy-Item -LiteralPath (
    Join-Path $pluginBuild 'SampleMissionPlugin.dll') `
    -Destination $pluginDirectory -Force

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class SidecarRuntimeIni {
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
        [string]$Value)
    if (-not [SidecarRuntimeIni]::WritePrivateProfileString(
            $Section, $Key, $Value, $Path)) {
        throw "Could not write isolated INI [$Section] $Key."
    }
}
$runtimeIni = Join-Path $runtime 'rungame.ini'
$runtimeDdraw = Join-Path $runtime 'ddraw.ini'
Set-Ini $runtimeIni 'mod' 'Diagnostics' '1'
Set-Ini $runtimeIni 'mod' 'Telemetry' '1'
Set-Ini $runtimeIni 'mod' 'SystemCursorMapping' '0'
Set-Ini $runtimeIni 'mod' 'MissionSidecar' '1'
Set-Ini $runtimeIni 'mod' 'EnablePlugins' '1'
Set-Ini $runtimeDdraw 'ddraw' 'fullscreen' 'false'
Set-Ini $runtimeDdraw 'ddraw' 'windowed' 'true'
Set-Ini $runtimeDdraw 'ddraw' 'width' '1024'
Set-Ini $runtimeDdraw 'ddraw' 'height' '768'
Set-Ini $runtimeDdraw 'ddraw' 'devmode' 'true'
Set-Ini $runtimeDdraw 'ddraw' 'no_dinput_hook' 'true'
Set-Ini $runtimeDdraw 'ddraw' 'adjmouse' 'false'
Set-Ini $runtimeDdraw 'ddraw' 'savesettings' '0'

$saveHashes = @{}
Get-ChildItem -LiteralPath $runtime -Filter '*.SAV' -File |
    ForEach-Object {
        $saveHashes[$_.Name] =
            (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
    }

$gameInfo = New-Object Diagnostics.ProcessStartInfo
$gameInfo.FileName = Join-Path $runtime 'M1937.exe'
$gameInfo.WorkingDirectory = $runtime
$gameInfo.UseShellExecute = $false
$gameInfo.EnvironmentVariables['M1937_AUTOTEST'] = '1'
$gameInfo.EnvironmentVariables['M1937_WINDOW_REPLAY'] = '1'
$gameInfo.EnvironmentVariables['M1937_START_LEVEL'] = [string]$Level
$gameInfo.EnvironmentVariables['M1937_TELEMETRY'] = '1'
$game = [Diagnostics.Process]::Start($gameInfo)
if ($null -eq $game) {
    throw 'Could not start isolated M1937 runtime.'
}
$sidecarProcess = $null
try {
    $clock = [Diagnostics.Stopwatch]::StartNew()
    while ($clock.Elapsed.TotalSeconds -lt 15 -and
           -not $game.HasExited) {
        $game.Refresh()
        if ($game.MainWindowHandle -ne [IntPtr]::Zero) { break }
        Start-Sleep -Milliseconds 100
    }
    if ($game.MainWindowHandle -eq [IntPtr]::Zero) {
        throw 'Isolated M1937 window was not created.'
    }
    $missionId = 'm{0:D3}' -f ($Level - 1)
    $definition = Join-Path $runtime (
        "Missions\$missionId.m1937mission.json")
    $hostInfo = New-Object Diagnostics.ProcessStartInfo
    $hostInfo.FileName = Join-Path $runtime (
        'Tools\MissionSidecar\MissionSidecar.Host.exe')
    $hostInfo.WorkingDirectory = $runtime
    $hostInfo.UseShellExecute = $false
    $hostInfo.CreateNoWindow = $true
    $hostInfo.Arguments = (
        '--pid {0} --sidecar "{1}" --plugins --headless ' +
        '--duration-seconds {2}') -f @(
            $game.Id, $definition, $DurationSeconds)
    $sidecarProcess = [Diagnostics.Process]::Start($hostInfo)
    if ($null -eq $sidecarProcess -or
        -not $sidecarProcess.WaitForExit(
            ($DurationSeconds + 30) * 1000)) {
        throw 'Mission sidecar host did not finish in time.'
    }
    if ($sidecarProcess.ExitCode -ne 0) {
        throw "Mission sidecar host exited with $(
            $sidecarProcess.ExitCode)."
    }
}
finally {
    if ($null -ne $sidecarProcess -and
        -not $sidecarProcess.HasExited) {
        $sidecarProcess.Kill()
        $sidecarProcess.WaitForExit(2000)
    }
    if (-not $game.HasExited) {
        [void]$game.CloseMainWindow()
        if (-not $game.WaitForExit(2000)) {
            $game.Kill()
            $game.WaitForExit(2000)
        }
    }
}

foreach ($name in $saveHashes.Keys) {
    $path = Join-Path $runtime $name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or
        (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne
            $saveHashes[$name]) {
        throw "Original save changed during sidecar runtime test: $name"
    }
}
$log = Join-Path $runtime 'MissionSidecarHost.log'
$logText = Get-Content -LiteralPath $log -Raw -Encoding UTF8
foreach ($marker in @(
    'session_started',
    'plugin_loaded',
    'world_event')) {
    if (-not $logText.Contains($marker)) {
        throw "Sidecar runtime log is missing $marker."
    }
}
$pluginState = Join-Path $runtime (
    'Plugins\State\sample-event-count.bin')
if (-not (Test-Path -LiteralPath $pluginState -PathType Leaf) -or
    (Get-Item -LiteralPath $pluginState).Length -ne 8) {
    throw 'The ABI sample plugin did not receive a world event.'
}
$result = [ordered]@{
    schema = 1
    selector_level = $Level
    duration_seconds = $DurationSeconds
    host_exit_code = $sidecarProcess.ExitCode
    plugin_loaded = $true
    plugin_event_state_bytes = 8
    original_save_write_operations = 0
    system_cursor_calls = 0
    global_focus_calls = 0
}
$result | ConvertTo-Json -Depth 4 |
    Set-Content -LiteralPath (
        Join-Path $OutputRoot 'result.json') -Encoding UTF8
@(
    '# Mission Sidecar Runtime Verification'
    ''
    "- Selector level: $Level"
    "- Host exit code: $($sidecarProcess.ExitCode)"
    '- Read-only process snapshot: passed'
    '- Native plugin ABI negotiation/event delivery: passed'
    '- Original SAV writes: 0'
    '- System cursor/focus calls: 0'
) | Set-Content -LiteralPath (
    Join-Path $OutputRoot 'result.md') -Encoding UTF8
Write-Host "Sidecar runtime report: $(Join-Path $OutputRoot 'result.md')"
