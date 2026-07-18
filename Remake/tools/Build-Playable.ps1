[CmdletBinding()]
param(
    [string]$GodotExecutable = '',
    [ValidateSet('Junction', 'Copy')]
    [string]$AssetMode = 'Junction',
    [string]$OutputDirectory = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$remakeRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$gameRoot = Join-Path $remakeRoot 'game'
$localBuildRoot = [System.IO.Path]::GetFullPath((Join-Path $remakeRoot 'LocalBuild'))
$sourceAssets = Join-Path $remakeRoot 'LocalAssets'
$convertedAssets = Join-Path $sourceAssets 'converted'
$requiredLevel = Join-Path $convertedAssets 'levels\m000\level.json'
$presetName = 'Windows Desktop'
$expectedGodotVersion = '4.7.1'

function Resolve-GodotExecutable {
    param([string]$RequestedPath)

    $candidates = [System.Collections.Generic.List[string]]::new()
    if (-not [string]::IsNullOrWhiteSpace($RequestedPath)) {
        $candidates.Add($RequestedPath)
    }
    if (-not [string]::IsNullOrWhiteSpace($env:GODOT4)) {
        $candidates.Add($env:GODOT4)
    }
    foreach ($commandName in @('godot4', 'godot', 'Godot_v4.7.1-stable_win64_console')) {
        $command = Get-Command $commandName -ErrorAction SilentlyContinue
        if ($null -ne $command) {
            $candidates.Add($command.Source)
        }
    }
    $candidates.Add((Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links\godot.exe'))
    $candidates.Add('E:\1937\tools\Godot-WinGet\extracted\Godot_v4.7.1-stable_win64_console.exe')

    foreach ($candidate in $candidates) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return [System.IO.Path]::GetFullPath($candidate)
        }
    }

    throw 'Godot 4.7.1 was not found. Pass -GodotExecutable C:\path\to\Godot_v4.7.1-stable_win64_console.exe or set GODOT4.'
}

function Resolve-RunnerExecutable {
    param([string]$EditorExecutable)

    if ($EditorExecutable.EndsWith('_console.exe', [System.StringComparison]::OrdinalIgnoreCase)) {
        $candidate = $EditorExecutable.Substring(0, $EditorExecutable.Length - '_console.exe'.Length) + '.exe'
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return $candidate
        }
    }
    return $EditorExecutable
}

function Invoke-Godot {
    param(
        [string]$Executable,
        [string[]]$Arguments,
        [string]$Description
    )

    Write-Host $Description
    & $Executable @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Description failed with exit code $LASTEXITCODE."
    }
}

function Assert-SafeOutputDirectory {
    param([string]$Candidate)

    $full = [System.IO.Path]::GetFullPath($Candidate)
    $rootPrefix = $localBuildRoot.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
    if (-not $full.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "OutputDirectory must be a child of $localBuildRoot."
    }
    if ($full -eq $localBuildRoot) {
        throw 'OutputDirectory must not be the LocalBuild root itself.'
    }
    return $full
}

if (-not (Test-Path -LiteralPath $requiredLevel -PathType Leaf)) {
    throw "Converted local assets were not found at $convertedAssets. Run tools\Import-OriginalAssets.cmd first."
}

$godot = Resolve-GodotExecutable -RequestedPath $GodotExecutable
$runner = Resolve-RunnerExecutable -EditorExecutable $godot
$version = (& $godot --version | Select-Object -First 1).Trim()
if (-not $version.StartsWith($expectedGodotVersion, [System.StringComparison]::Ordinal)) {
    throw "Godot $expectedGodotVersion is required; found '$version' at $godot."
}

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $localBuildRoot '1937Remake'
}
$outputRoot = Assert-SafeOutputDirectory -Candidate $OutputDirectory
$outputGame = Join-Path $outputRoot 'game'
$outputAssets = Join-Path $outputRoot 'LocalAssets'
$outputExecutable = Join-Path $outputGame '1937Remake.exe'
$outputPack = Join-Path $outputGame '1937Remake.pck'
$smokeLog = Join-Path $outputRoot 'smoke-test.log'

Write-Host "Godot: $godot ($version)"
Write-Host "Output: $outputRoot"
Write-Host "Assets: $AssetMode"

if (Test-Path -LiteralPath $outputRoot) {
    $attributes = (Get-Item -LiteralPath $outputRoot -Force).Attributes
    if (($attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Refusing to replace a reparse-point output directory: $outputRoot"
    }
    Remove-Item -LiteralPath $outputRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $outputGame -Force | Out-Null

Invoke-Godot -Executable $godot -Arguments @(
    '--headless', '--path', $gameRoot, '--editor', '--quit'
) -Description 'Preparing Godot imports and script metadata...'

$templateDirectory = Join-Path $env:APPDATA "Godot\export_templates\$expectedGodotVersion.stable"
$releaseTemplate = Join-Path $templateDirectory 'windows_release_x86_64.exe'
$buildKind = 'editor-runner-with-pck'
if (Test-Path -LiteralPath $releaseTemplate -PathType Leaf) {
    Invoke-Godot -Executable $godot -Arguments @(
        '--headless', '--path', $gameRoot, '--export-release', $presetName, $outputExecutable
    ) -Description 'Exporting the Windows release executable...'
    $buildKind = 'official-release-template'
} else {
    Invoke-Godot -Executable $godot -Arguments @(
        '--headless', '--path', $gameRoot, '--export-pack', $presetName, $outputPack
    ) -Description 'Export templates are absent; exporting a PCK for the matching local Godot runner...'
    Copy-Item -LiteralPath $runner -Destination $outputExecutable -Force
}

if ($AssetMode -eq 'Junction') {
    New-Item -ItemType Junction -Path $outputAssets -Target $sourceAssets | Out-Null
} else {
    New-Item -ItemType Directory -Path $outputAssets -Force | Out-Null
    Copy-Item -LiteralPath $convertedAssets -Destination $outputAssets -Recurse -Force
}

$launcher = @'
@echo off
setlocal
pushd "%~dp0game"
start "1937 Remake" "1937Remake.exe" %*
popd
'@
[System.IO.File]::WriteAllText(
    (Join-Path $outputRoot 'Play-1937-Remake.cmd'),
    $launcher,
    [System.Text.Encoding]::ASCII
)

$buildInfo = [ordered]@{
    schema_version = 1
    built_at_utc = [DateTime]::UtcNow.ToString('o')
    git_commit = (& git -C (Split-Path $remakeRoot -Parent) rev-parse HEAD).Trim()
    godot_version = $version
    build_kind = $buildKind
    asset_mode = $AssetMode
}
$buildInfo | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $outputRoot 'build-info.json') -Encoding utf8

$playableReadme = @"
1937 Remake local playable build

Run: double-click Play-1937-Remake.cmd.
Level selection: Play-1937-Remake.cmd -- --level=m007 (m000 through m011).

Keep game and LocalAssets in their current relative locations. The launcher fixes the working
directory so the exported program can find the locally converted assets.
Asset mode: $AssetMode
Build kind: $buildKind

Junction mode is local-only. LocalAssets points to Remake\LocalAssets. Before moving this
directory, rebuild it in Copy mode:
  .\tools\Build-Playable.cmd -AssetMode Copy

This generated directory is ignored by Git. Do not commit local converted assets or binaries.
"@
$playableReadme | Set-Content -LiteralPath (Join-Path $outputRoot 'README.txt') -Encoding utf8

Push-Location $outputGame
try {
    & $godot --headless --main-pack $outputPack --quit-after 8 --log-file $smokeLog
    $smokeExitCode = $LASTEXITCODE
} finally {
    Pop-Location
}
if ($smokeExitCode -ne 0) {
    throw "Playable smoke test failed with exit code $smokeExitCode. See $smokeLog."
}
$smokeText = Get-Content -LiteralPath $smokeLog -Raw -Encoding utf8
if ($smokeText -match '(?m)^(SCRIPT ERROR|ERROR:)') {
    throw "Playable smoke test logged an engine or script error. See $smokeLog."
}

$packHash = (Get-FileHash -LiteralPath $outputPack -Algorithm SHA256).Hash
Write-Host ''
Write-Host 'Playable build completed.'
Write-Host "Launch: $(Join-Path $outputRoot 'Play-1937-Remake.cmd')"
Write-Host "PCK SHA-256: $packHash"
Write-Host "Smoke test: passed ($smokeLog)"
