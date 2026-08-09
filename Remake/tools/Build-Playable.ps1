[CmdletBinding()]
param(
    [string]$GodotExecutable = '',
    [ValidateSet('Junction', 'Copy')]
    [string]$AssetMode = 'Copy',
    [string]$OutputDirectory = '',
    [bool]$CreateArchive = $true,
    [string]$CertificatePath = '',
    [string]$CertificatePassword = '',
    [switch]$AllowEditorRunnerFallback
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$remakeRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$gameRoot = Join-Path $remakeRoot 'game'
$localBuildRoot = [System.IO.Path]::GetFullPath((Join-Path $remakeRoot 'LocalBuild'))
$sourceAssets = Join-Path $remakeRoot 'LocalAssets'
$convertedAssets = Join-Path $sourceAssets 'converted'
$sourceSchemas = Join-Path $remakeRoot 'schemas'
$requiredLevel = Join-Path $convertedAssets 'levels\m000\level.json'
$presetName = 'Windows Desktop'
$expectedGodotVersion = '4.7.1'
$projectText = Get-Content -LiteralPath (Join-Path $gameRoot 'project.godot') `
    -Raw -Encoding UTF8
$applicationVersion = 'development'
if ($projectText -match '(?m)^config/version="([^"]+)"\s*$') {
    $applicationVersion = $Matches[1]
}

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
	$candidates.Add('D:\Godot\Godot_v4.7.1-stable_win64_console.exe')
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

function Get-ContainedRelativePath {
    param(
        [string]$Root,
        [string]$Target
    )

    # Path.GetRelativePath is unavailable in Windows PowerShell 5.1's .NET
    # Framework runtime. Every checksum target is required to live under the
    # build root anyway, so a validated prefix removal is both compatible and
    # stricter than accepting a relative path containing '..'.
    $fullRoot = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/') +
        [IO.Path]::DirectorySeparatorChar
    $fullTarget = [IO.Path]::GetFullPath($Target)
    if (-not $fullTarget.StartsWith(
            $fullRoot,
            [StringComparison]::OrdinalIgnoreCase)) {
        throw "Checksum target escaped the build root: $fullTarget"
    }
    return $fullTarget.Substring($fullRoot.Length).Replace('\', '/')
}

function Remove-SafeOutputDirectory {
    param([string]$Candidate)

    $full = Assert-SafeOutputDirectory -Candidate $Candidate
    if (-not (Test-Path -LiteralPath $full)) {
        return
    }
    $rootItem = Get-Item -LiteralPath $full -Force
    if (($rootItem.Attributes -band
            [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Refusing to replace a reparse-point output directory: $full"
    }

    # Walk ordinary directories ourselves and never descend into a junction or
    # symbolic link. Remove each link object with the matching .NET API before
    # recursively deleting the now self-contained build tree. This prevents an
    # old Junction-mode build from making Remove-Item traverse into LocalAssets.
    $rootPrefix =
        $full.TrimEnd('\', '/') +
        [System.IO.Path]::DirectorySeparatorChar
    $directories =
        [System.Collections.Generic.Stack[System.IO.DirectoryInfo]]::new()
    $reparsePoints =
        [System.Collections.Generic.List[System.IO.FileSystemInfo]]::new()
    $directories.Push([System.IO.DirectoryInfo]$rootItem)
    while ($directories.Count -gt 0) {
        $directory = $directories.Pop()
        foreach ($entry in $directory.EnumerateFileSystemInfos()) {
            if (($entry.Attributes -band
                    [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                $reparsePoints.Add($entry)
                continue
            }
            if (($entry.Attributes -band
                    [System.IO.FileAttributes]::Directory) -ne 0) {
                $directories.Push([System.IO.DirectoryInfo]$entry)
            }
        }
    }
    foreach ($entry in $reparsePoints) {
        $entryPath = [System.IO.Path]::GetFullPath($entry.FullName)
        if (-not $entryPath.StartsWith(
                $rootPrefix,
                [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to unlink a reparse point outside the build: $entryPath"
        }
        if (($entry.Attributes -band
                [System.IO.FileAttributes]::Directory) -ne 0) {
            [System.IO.Directory]::Delete($entryPath, $false)
        }
        else {
            [System.IO.File]::Delete($entryPath)
        }
        Write-Host "Detached old build reparse point: $entryPath"
    }
    Remove-Item -LiteralPath $full -Recurse -Force
}

$assetManifestPath = Join-Path $sourceAssets 'manifest.json'
$assetProfile = ''
$assetActorStateSchema = 0
if (Test-Path -LiteralPath $assetManifestPath -PathType Leaf) {
    try {
        $assetManifest = Get-Content -LiteralPath $assetManifestPath `
            -Raw -Encoding UTF8 | ConvertFrom-Json
        $assetProfile =
            [string]$assetManifest.source.known_version.version_id
    }
    catch {
        $assetProfile = ''
    }
}
if (Test-Path -LiteralPath $requiredLevel -PathType Leaf) {
    try {
        $levelDocument = Get-Content -LiteralPath $requiredLevel `
            -Raw -Encoding UTF8 | ConvertFrom-Json
        $firstActorState = @($levelDocument.entities | Where-Object {
            $null -ne $_.native_actor_state
        } | Select-Object -First 1)
        if ($firstActorState.Count -eq 1) {
            $assetActorStateSchema =
                [int]$firstActorState[0].native_actor_state.schema_version
        }
    }
    catch {
        $assetActorStateSchema = 0
    }
}
if (-not (Test-Path -LiteralPath $requiredLevel -PathType Leaf) -or
    $assetProfile -ne 'repository-mod-12-level-20260729' -or
    $assetActorStateSchema -ne 2) {
    Write-Host 'Stable Mod assets are missing or stale; importing them now.'
    & (Join-Path $PSScriptRoot 'Import-ModAssets.ps1') `
        -OutputDirectory $sourceAssets
    if ($LASTEXITCODE -ne 0 -or
        -not (Test-Path -LiteralPath $requiredLevel -PathType Leaf)) {
        throw 'Stable Mod asset import did not produce a playable content set.'
    }
    $assetProfile = 'repository-mod-12-level-20260729'
    $assetActorStateSchema = 2
}
$sourceConvertedBytes = [int64](
    Get-ChildItem -LiteralPath $convertedAssets -Recurse -File |
        Measure-Object -Property Length -Sum
).Sum

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
$executableSmokeLog = Join-Path $outputRoot 'executable-smoke-test.log'
$contentManifestPath = Join-Path $outputAssets 'content-manifest.json'

Write-Host "Godot: $godot ($version)"
Write-Host "Output: $outputRoot"
Write-Host "Assets: $AssetMode"

if (Test-Path -LiteralPath $outputRoot) {
    Remove-SafeOutputDirectory -Candidate $outputRoot
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
    if (-not $AllowEditorRunnerFallback) {
        throw (
            "The official Godot $expectedGodotVersion Windows export template " +
            "is required at $releaseTemplate. Install it or pass " +
            "-AllowEditorRunnerFallback for a developer-only build."
        )
    }
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
    # The modern product no longer plays the blocking startup logo/history CG.
    # Keep analysis/source conversions intact, but omit those large files from
    # portable copies so the playable package benefits from the removal too.
    $copiedConvertedRoot = Join-Path $outputAssets 'converted'
    foreach ($relativeStartupMovie in @(
            'media\video\logo.ogv',
            'media\video\historical_intro.ogv')) {
        $startupMovie = [System.IO.Path]::GetFullPath(
            (Join-Path $copiedConvertedRoot $relativeStartupMovie))
        $safePrefix =
            [System.IO.Path]::GetFullPath($copiedConvertedRoot).TrimEnd('\', '/') +
            [System.IO.Path]::DirectorySeparatorChar
        if (-not $startupMovie.StartsWith(
                $safePrefix,
                [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Unsafe startup media path: $startupMovie"
        }
        if (Test-Path -LiteralPath $startupMovie -PathType Leaf) {
            Remove-Item -LiteralPath $startupMovie -Force
        }
    }

    # Compact only the isolated release copy. The optimizer proves that every
    # standalone sprite preview equals atlas group 0/frame 0, verifies complete
    # atlas coverage before removing individual-frame fallbacks, and performs a
    # pixel-for-pixel round trip before replacing terrain PNGs with lossless
    # WebP. Remake/LocalAssets remains the complete forensic/development import.
    Invoke-Godot -Executable $godot -Arguments @(
        '--headless', '--path', $gameRoot,
        '--script', 'res://tools/portable_content_optimizer.gd', '--',
        "--content-root=$copiedConvertedRoot",
        '--expected-level-count=12'
    ) -Description 'Optimizing the isolated portable content copy...'
}

# Publish the authoring contract beside the portable game. The runtime itself
# remains declarative and validates packages internally; these small JSON
# schemas let players and editor authors inspect exactly which version the
# build accepts without shipping any original content.
$outputSchemas = Join-Path $outputRoot 'schemas'
New-Item -ItemType Directory -Force -Path $outputSchemas | Out-Null
$schemaFiles = @(Get-ChildItem -LiteralPath $sourceSchemas -Filter '*.schema.json' -File)
if ($schemaFiles.Count -ne 5) {
    throw 'Portable build requires all five native-content schema documents.'
}
foreach ($schemaFile in $schemaFiles) {
    Copy-Item -LiteralPath $schemaFile.FullName `
        -Destination (Join-Path $outputSchemas $schemaFile.Name) -Force
}

$criticalContentPaths = @(
    'levels/m000/level.json',
    'levels/m011/level.json'
)
if ($AssetMode -eq 'Junction') {
    $criticalContentPaths = @('asset-manifest.json') + $criticalContentPaths
}
& (Join-Path $PSScriptRoot 'New-ContentManifest.ps1') `
    -ContentRoot (Join-Path $outputAssets 'converted') `
    -OutputPath $contentManifestPath `
    -ProfileId $assetProfile `
    -CriticalPaths $criticalContentPaths | Format-List
if ($LASTEXITCODE -ne 0) {
    throw 'Content manifest generation failed.'
}
$contentValidationArguments = @{
    ContentRoot = Join-Path $outputAssets 'converted'
    ManifestPath = $contentManifestPath
}
if ($AssetMode -eq 'Copy') {
    # A distributable copy cannot rely on the source directory after it has
    # left the development machine. Re-read every copied payload against the
    # freshly generated manifest so same-length copy corruption is caught too.
    $contentValidationArguments['VerifyAllHashes'] = $true
}
& (Join-Path $PSScriptRoot 'Test-ContentPackage.ps1') @contentValidationArguments
if ($LASTEXITCODE -ne 0) {
    throw 'Content package validation failed.'
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

$contentManifestDocument = Get-Content -LiteralPath $contentManifestPath `
    -Raw -Encoding utf8 | ConvertFrom-Json
$buildInfo = [ordered]@{
    schema_version = 3
    built_at_utc = [DateTime]::UtcNow.ToString('o')
    git_commit = (& git -C (Split-Path $remakeRoot -Parent) rev-parse HEAD).Trim()
    application_version = $applicationVersion
    godot_version = $version
    build_kind = $buildKind
    asset_mode = $AssetMode
    startup_media_playback_disabled = $true
    startup_media_files_omitted = ($AssetMode -eq 'Copy')
    portable_content_profile = if ($AssetMode -eq 'Copy') {
        'lossless-portable-v1'
    } else {
        'complete-development-assets'
    }
    lossless_terrain_webp = ($AssetMode -eq 'Copy')
    standalone_sprite_previews_omitted = ($AssetMode -eq 'Copy')
    individual_sprite_frame_fallbacks_omitted = ($AssetMode -eq 'Copy')
    source_converted_bytes = $sourceConvertedBytes
    packaged_converted_bytes = [int64]$contentManifestDocument.total_bytes
    asset_content_profile = $assetProfile
    asset_manifest_sha256 = (
        Get-FileHash -LiteralPath $assetManifestPath -Algorithm SHA256).Hash
    parity_contract_sha256 = (
        Get-FileHash -LiteralPath (
            Join-Path $gameRoot 'data\mod_parity_contract.json') `
            -Algorithm SHA256).Hash
    content_manifest_sha256 = (
        Get-FileHash -LiteralPath $contentManifestPath -Algorithm SHA256).Hash
    content_identity_sha256 = $contentManifestDocument.content_identity_sha256
    native_content_schemas = [ordered]@{}
}
foreach ($schemaFile in $schemaFiles | Sort-Object Name) {
    $buildInfo.native_content_schemas[$schemaFile.Name] = (
        Get-FileHash -LiteralPath (Join-Path $outputSchemas $schemaFile.Name) `
            -Algorithm SHA256).Hash.ToLowerInvariant()
}
$buildInfo | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $outputRoot 'build-info.json') -Encoding utf8

$playableReadme = @"
1937 Remake local playable build

Run: double-click Play-1937-Remake.cmd.
Level selection: use the native startup/menu selector, or launch directly with
Play-1937-Remake.cmd -- --level=m007 (m000 through m011).
The legacy startup CG is disabled. Press Alt+Enter at any time to switch between
fullscreen and the saved window size.

Copy-mode packages use pixel-identical lossless terrain WebP and read sprite
previews/animations from the original atlases. Standalone preview duplicates and
individual-frame fallback PNGs stay in LocalAssets for development, but are not
shipped in the portable build.

Keep game and LocalAssets in their current relative locations. The launcher fixes the working
directory so the exported program can find the locally converted assets.
Asset mode: $AssetMode
Build kind: $buildKind
Application version: $applicationVersion
Content profile: $assetProfile

Junction mode is local-only. LocalAssets points to Remake\LocalAssets. Before moving this
directory, rebuild it in Copy mode:
  .\tools\Build-Playable.cmd -AssetMode Copy

This generated directory is ignored by Git. Do not commit local converted assets or binaries.
"@
$playableReadme | Set-Content -LiteralPath (Join-Path $outputRoot 'README.txt') -Encoding utf8

Push-Location $outputGame
try {
    & $godot --headless --main-pack $outputPack --quit-after 12 `
        --log-file $smokeLog -- --level=m000 --skip-briefing
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

# Exercise the exact copied/exported product binary as well as the PCK through
# the editor executable. This catches basename, working-directory, runner and
# side-by-side packaging mistakes that --main-pack alone cannot detect.
$executableSmoke = Start-Process `
    -FilePath $outputExecutable `
    -ArgumentList @(
        '--headless', '--quit-after', '12', '--log-file', $executableSmokeLog,
        '--', '--level=m000', '--skip-briefing'
    ) `
    -WorkingDirectory $outputGame `
    -WindowStyle Hidden `
    -Wait `
    -PassThru
if ($executableSmoke.ExitCode -ne 0) {
    throw "Playable executable smoke test failed with exit code $($executableSmoke.ExitCode). See $executableSmokeLog."
}
$executableSmokeText = Get-Content -LiteralPath $executableSmokeLog -Raw -Encoding utf8
if ($executableSmokeText -match '(?m)^(SCRIPT ERROR|ERROR:)') {
    throw "Playable executable smoke test logged an engine or script error. See $executableSmokeLog."
}

if (-not [string]::IsNullOrWhiteSpace($CertificatePath)) {
    $certificate = [IO.Path]::GetFullPath($CertificatePath)
    if (-not (Test-Path -LiteralPath $certificate -PathType Leaf)) {
        throw "Code-signing certificate was not found: $certificate"
    }
    $signTool = Get-Command signtool.exe -ErrorAction SilentlyContinue
    if ($null -eq $signTool) {
        throw 'signtool.exe was not found; install the Windows SDK before signing.'
    }
    $signArguments = @(
        'sign', '/fd', 'SHA256', '/td', 'SHA256',
        '/tr', 'http://timestamp.digicert.com', '/f', $certificate
    )
    if (-not [string]::IsNullOrWhiteSpace($CertificatePassword)) {
        $signArguments += @('/p', $CertificatePassword)
    }
    $signArguments += $outputExecutable
    & $signTool.Source @signArguments
    if ($LASTEXITCODE -ne 0) {
        throw "Authenticode signing failed with exit code $LASTEXITCODE."
    }
}

$checksumTargets = @(
    $outputExecutable,
    $outputPack,
    (Join-Path $outputRoot 'build-info.json'),
    $contentManifestPath
)
$checksumLines = foreach ($target in $checksumTargets) {
    if (Test-Path -LiteralPath $target -PathType Leaf) {
        $relative = Get-ContainedRelativePath -Root $outputRoot -Target $target
        $hash = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant()
        "$hash  $relative"
    }
}
$checksumPath = Join-Path $outputRoot 'SHA256SUMS.txt'
[IO.File]::WriteAllLines(
    $checksumPath,
    [string[]]$checksumLines,
    [Text.UTF8Encoding]::new($false)
)

$archivePath = Join-Path $localBuildRoot '1937Remake-portable.zip'
if ($CreateArchive -and $AssetMode -eq 'Copy') {
    $archiveFull = [IO.Path]::GetFullPath($archivePath)
    $localPrefix = $localBuildRoot.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    if (-not $archiveFull.StartsWith(
            $localPrefix,
            [StringComparison]::OrdinalIgnoreCase)) {
        throw "Unsafe archive path: $archiveFull"
    }
    if (Test-Path -LiteralPath $archiveFull -PathType Leaf) {
        Remove-Item -LiteralPath $archiveFull -Force
    }
    Compress-Archive -LiteralPath $outputRoot -DestinationPath $archiveFull -CompressionLevel Optimal
    $archiveHash = (Get-FileHash -LiteralPath $archiveFull -Algorithm SHA256).Hash.ToLowerInvariant()
    "$archiveHash  $(Split-Path -Leaf $archiveFull)" |
        Set-Content -LiteralPath "$archiveFull.sha256" -Encoding ascii
}

$packHash = (Get-FileHash -LiteralPath $outputPack -Algorithm SHA256).Hash
Write-Host ''
Write-Host 'Playable build completed.'
Write-Host "Launch: $(Join-Path $outputRoot 'Play-1937-Remake.cmd')"
Write-Host "PCK SHA-256: $packHash"
Write-Host "PCK smoke test: passed ($smokeLog)"
Write-Host "Executable smoke test: passed ($executableSmokeLog)"
Write-Host "Checksums: $checksumPath"
if ($CreateArchive -and $AssetMode -eq 'Copy') {
    Write-Host "Portable archive: $archivePath"
}
