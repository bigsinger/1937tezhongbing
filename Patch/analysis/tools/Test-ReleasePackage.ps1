param(
    [string]$ArchivePath = '',
    [string]$OutputRoot = 'E:\1937\patch-v141-package-test'
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = [IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot '..\..\..'))
if ([string]::IsNullOrWhiteSpace($ArchivePath)) {
    $archiveItem = Get-ChildItem -LiteralPath (
        Join-Path $repositoryRoot 'Patch\release') `
        -Filter '*v1.4.1-20260727.zip' -File |
        Select-Object -First 1
    if (-not $archiveItem) {
        throw 'v1.4.1 release archive was not found.'
    }
    $ArchivePath = $archiveItem.FullName
}
$ArchivePath = [IO.Path]::GetFullPath($ArchivePath)
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
$allowedRoot = [IO.Path]::GetFullPath('E:\1937').TrimEnd('\') + '\'
if (-not ($OutputRoot.TrimEnd('\') + '\').StartsWith(
        $allowedRoot,
        [StringComparison]::OrdinalIgnoreCase) -or
    $OutputRoot.TrimEnd('\').Equals(
        'E:\1937',
        [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Release test output must be a child of E:\1937.'
}
if (-not (Test-Path -LiteralPath $ArchivePath -PathType Leaf)) {
    throw "Release archive is missing: $ArchivePath"
}
$archiveHash = (
    Get-FileHash -LiteralPath $ArchivePath -Algorithm SHA256).Hash
$archiveHashPath = $ArchivePath + '.sha256.txt'
$archiveHashText = if (Test-Path -LiteralPath $archiveHashPath -PathType Leaf) {
    Get-Content -LiteralPath $archiveHashPath -Raw -Encoding UTF8
}
else {
    ''
}
if (-not (Test-Path -LiteralPath $archiveHashPath -PathType Leaf) -or
    -not $archiveHashText.Contains($archiveHash)) {
    throw 'Release archive sidecar SHA-256 is missing or mismatched.'
}
if (Test-Path -LiteralPath $OutputRoot) {
    Remove-Item -LiteralPath $OutputRoot -Recurse -Force
}
$extracted = Join-Path $OutputRoot 'extracted'
$target = Join-Path $OutputRoot 'game'
[IO.Directory]::CreateDirectory($extracted) | Out-Null
[IO.Directory]::CreateDirectory($target) | Out-Null
Expand-Archive -LiteralPath $ArchivePath -DestinationPath $extracted

$install = Get-ChildItem -LiteralPath $extracted -Recurse `
    -Filter 'Install-Patch.ps1' -File | Select-Object -First 1
$uninstall = Get-ChildItem -LiteralPath $extracted -Recurse `
    -Filter 'Uninstall-Patch.ps1' -File | Select-Object -First 1
if (-not $install -or -not $uninstall) {
    throw 'Release archive does not contain installer/uninstaller scripts.'
}
$payload = Join-Path $install.Directory.FullName 'payload'
$forbiddenGameData = @(
    Get-ChildItem -LiteralPath $install.Directory.FullName -Recurse -File |
        Where-Object {
            $_.Name -ieq 'M1937.exe' -or
            $_.Extension -in @(
                '.GFL', '.VWF', '.SVT', '.SAV',
                '.DBL', '.SLF', '.SI0', '.SI1', '.SI2')
        })
if ($forbiddenGameData.Count -gt 0) {
    throw (
        'Release archive contains original game data: ' +
        ($forbiddenGameData.Name -join ', '))
}
$expectedEntries = Get-Content -LiteralPath (
    Join-Path $install.Directory.FullName 'SHA256SUMS.txt') `
    -Encoding UTF8
foreach ($line in $expectedEntries) {
    if ($line -notmatch '^([0-9A-Fa-f]{64}) \*(.+)$') {
        throw "Invalid SHA256SUMS line: $line"
    }
    $path = Join-Path $install.Directory.FullName (
        $Matches[2].Replace('/', '\'))
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or
        (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne
        $Matches[1].ToUpperInvariant()) {
        throw "Release entry hash mismatch: $($Matches[2])"
    }
}
$sidecarManifestPath = Join-Path $payload (
    'Tools\MissionSidecar\build-manifest.json')
$sidecarManifest = Get-Content -LiteralPath $sidecarManifestPath `
    -Raw -Encoding UTF8 | ConvertFrom-Json
if ([int]$sidecarManifest.schema_version -ne 1 -or
    [string]$sidecarManifest.architecture -ne 'x64' -or
    [int]$sidecarManifest.plugin_api_version -ne 65536) {
    throw 'MissionSidecar build manifest identity is invalid.'
}
foreach ($entry in $sidecarManifest.files) {
    $path = Join-Path (Split-Path $sidecarManifestPath) (
        [string]$entry.name)
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or
        (Get-Item -LiteralPath $path).Length -ne [long]$entry.length -or
        (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne
            [string]$entry.sha256) {
        throw "MissionSidecar manifest mismatch: $($entry.name)"
    }
}

$sourceExe = Join-Path $repositoryRoot 'Mod\M1937.exe'
$targetExe = Join-Path $target 'M1937.exe'
Copy-Item -LiteralPath $sourceExe -Destination $targetExe
$exeHash = (Get-FileHash -LiteralPath $targetExe -Algorithm SHA256).Hash
$preExisting = Join-Path $target 'ddraw.ini'
[IO.File]::WriteAllText(
    $preExisting,
    "[ddraw]`r`nkeep=this-original-file`r`n",
    [Text.Encoding]::ASCII)
$preExistingHash = (
    Get-FileHash -LiteralPath $preExisting -Algorithm SHA256).Hash
& powershell.exe -NoProfile -ExecutionPolicy Bypass `
    -File $install.FullName $target -Quiet
if ($LASTEXITCODE -ne 0) {
    throw "Release installer failed with exit code $LASTEXITCODE."
}
$installedChecks = @(
    'dinput.dll',
    'ddraw.dll',
    'Tools\MissionSidecar\MissionSidecar.Host.exe',
    'Tools\MissionSidecar\build-manifest.json',
    'Missions\m012.m1937mission.json')
foreach ($relative in $installedChecks) {
    if (-not (Test-Path -LiteralPath (
                Join-Path $target $relative) -PathType Leaf)) {
        throw "Installed payload is missing: $relative"
    }
}
$launcherScript = Get-ChildItem -LiteralPath $target -Filter '*.ps1' -File |
    Where-Object {
        (Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8) -match
            'M1937_START_LEVEL'
    } |
    Select-Object -First 1
$levelCatalog = Get-ChildItem -LiteralPath $target -Filter '*.json' -File |
    Where-Object {
        try {
            $catalog = Get-Content -LiteralPath $_.FullName -Raw `
                -Encoding UTF8 | ConvertFrom-Json
            @($catalog.missions).Count -eq 15
        }
        catch {
            $false
        }
    } |
    Select-Object -First 1
if (-not $launcherScript -or -not $levelCatalog) {
    throw 'Installed launcher or 15-level catalog is missing.'
}
$installedCatalog = Get-Content -LiteralPath $levelCatalog.FullName `
    -Raw -Encoding UTF8 | ConvertFrom-Json
$textBriefings = @($installedCatalog.missions | Where-Object {
    -not [string]::IsNullOrWhiteSpace([string]$_.briefing) -and
    @($_.objectives).Count -eq 3 -and
    [bool]$_.replace_legacy_briefing
})
if ($textBriefings.Count -ne 15) {
    throw 'Installed catalog does not contain 15 complete text briefings.'
}
$localizedInstalledPaths = @(
    $launcherScript.FullName,
    $levelCatalog.FullName)
foreach ($relative in @(
        'source\Patch\tools\MissionSidecar\MissionSidecar.slnx',
        'source\SDK\generated\M1937Addresses.cs',
        'source\SDK\include\M1937SDK\PluginABI.hpp',
        'source\SDK\samples\mission-plugin\mission_plugin.cpp',
        'source\SDK\schemas\mission-sidecar-v1.schema.json')) {
    $sourcePath = Join-Path $install.Directory.FullName $relative
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
        throw "Release source bundle is missing: $relative"
    }
}
$sourceSolution = Join-Path $install.Directory.FullName (
    'source\Patch\tools\MissionSidecar\MissionSidecar.slnx')
$sourceArtifacts = Join-Path $OutputRoot 'source-build'
& dotnet build $sourceSolution -c Release `
    --artifacts-path $sourceArtifacts
if ($LASTEXITCODE -ne 0) {
    throw "Packaged MissionSidecar source did not compile: $LASTEXITCODE"
}
$sampleBuild = Join-Path $install.Directory.FullName (
    'source\SDK\samples\mission-plugin\Build-SamplePlugin.ps1')
& $sampleBuild -OutputDirectory (
    Join-Path $OutputRoot 'sample-plugin-build') | Out-Host
if ($LASTEXITCODE -ne 0) {
    throw "Packaged sample plugin source did not compile: $LASTEXITCODE"
}
if ((Get-FileHash -LiteralPath $targetExe -Algorithm SHA256).Hash -ne
    $exeHash) {
    throw 'Installer modified M1937.exe.'
}
$installedDdraw = Get-Content -LiteralPath (
    Join-Path $target 'ddraw.ini') -Raw -Encoding UTF8
$ddrawSection = [Regex]::Match(
    $installedDdraw,
    '(?ms)^\[ddraw\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
foreach ($requiredSetting in @(
        'windowed=true',
        'fullscreen=false',
        'adjmouse=false',
        'devmode=true',
        'no_dinput_hook=true')) {
    if ($ddrawSection -notmatch (
            '(?m)^' + [Regex]::Escape($requiredSetting) + '\s*$')) {
        throw "Installed cursor-safe setting is missing: $requiredSetting"
    }
}
if ((Get-FileHash -LiteralPath $preExisting -Algorithm SHA256).Hash -eq
    $preExistingHash) {
    throw 'Installer did not deploy its ddraw.ini over the test sentinel.'
}

& powershell.exe -NoProfile -ExecutionPolicy Bypass `
    -File $uninstall.FullName $target -Quiet
if ($LASTEXITCODE -ne 0) {
    throw "Release uninstaller failed with exit code $LASTEXITCODE."
}
if (-not (Test-Path -LiteralPath $targetExe -PathType Leaf) -or
    (Get-FileHash -LiteralPath $targetExe -Algorithm SHA256).Hash -ne
    $exeHash) {
    throw 'Uninstaller removed or changed M1937.exe.'
}
if (-not (Test-Path -LiteralPath $preExisting -PathType Leaf) -or
    (Get-FileHash -LiteralPath $preExisting -Algorithm SHA256).Hash -ne
        $preExistingHash) {
    throw 'Uninstaller did not restore the pre-install ddraw.ini.'
}
foreach ($relative in $installedChecks) {
    if (Test-Path -LiteralPath (Join-Path $target $relative)) {
        throw "Uninstaller retained package file: $relative"
    }
}
foreach ($path in $localizedInstalledPaths) {
    if (Test-Path -LiteralPath $path) {
        throw "Uninstaller retained localized package file: $path"
    }
}

[ordered]@{
    schema = 1
    archive = [IO.Path]::GetFileName($ArchivePath)
    archive_sha256 = $archiveHash
    package_entries = @($expectedEntries).Count
    installer = 'passed'
    uninstaller = 'passed'
    executable_unchanged = $true
    preexisting_configuration_restored = $true
    stable_window_cursor_profile = $true
    mission_sidecar_included = $true
    mission_sidecar_manifest_verified = $true
    packaged_sidecar_source_compiles = $true
    packaged_plugin_source_compiles = $true
    text_briefings_verified = 15
    original_game_data_files = 0
} | ConvertTo-Json -Depth 4 |
    Set-Content -LiteralPath (
        Join-Path $OutputRoot 'result.json') -Encoding UTF8

Write-Host "Release package test passed: $OutputRoot"
