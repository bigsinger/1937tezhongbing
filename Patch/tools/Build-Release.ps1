param(
    [string]$WorkDirectory = 'E:\1937\patch-v140-build'
)

$ErrorActionPreference = 'Stop'
$patchRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $patchRoot '..'))
$workRoot = [IO.Path]::GetFullPath($WorkDirectory)
$allowedRoot = [IO.Path]::GetFullPath('E:\1937').TrimEnd('\') + '\'
if (-not ($workRoot.TrimEnd('\') + '\').StartsWith(
    $allowedRoot,
    [StringComparison]::OrdinalIgnoreCase)) {
    throw "WorkDirectory must stay under E:\1937: $workRoot"
}

$basePackageItem = Get-ChildItem -LiteralPath (Join-Path $patchRoot 'release') `
    -Filter '*v1.2.0-20260726.zip' -File | Select-Object -First 1
$basePackage = if ($basePackageItem) { $basePackageItem.FullName } else { '' }
$packageName = if ($basePackageItem) {
    $basePackageItem.BaseName.Replace(
        'v1.2.0-20260726',
        'v1.4.0-20260727')
} else {
    '1937-compatibility-patch-v1.4.0-20260727'
}
$stage = Join-Path $workRoot $packageName
$archive = Join-Path $patchRoot ('release\' + $packageName + '.zip')
$archiveHash = $archive + '.sha256.txt'
$proxyRoot = Join-Path $patchRoot 'src\dinput-proxy'
$selectorRoot = Join-Path $patchRoot 'src\level-selector'
$modRoot = Join-Path $repositoryRoot 'Mod'

function Copy-SourceTree {
    param(
        [Parameter(Mandatory)]
        [string]$From,
        [Parameter(Mandatory)]
        [string]$To
    )
    $sourceRoot = [IO.Path]::GetFullPath($From).TrimEnd('\')
    Get-ChildItem -LiteralPath $sourceRoot -Recurse -File |
        Where-Object {
            $_.FullName -notmatch '\\(bin|obj|build|\.vs)\\'
        } |
        ForEach-Object {
            $relative = $_.FullName.Substring($sourceRoot.Length + 1)
            $target = Join-Path $To $relative
            [IO.Directory]::CreateDirectory(
                [IO.Path]::GetDirectoryName($target)) | Out-Null
            Copy-Item -LiteralPath $_.FullName -Destination $target -Force
        }
}

if (-not (Test-Path -LiteralPath $basePackage -PathType Leaf)) {
    throw "Base package is missing: $basePackage"
}

& (Join-Path $PSScriptRoot 'Build-Mod.ps1') `
    -RepositoryRoot $repositoryRoot | Out-Null
& (Join-Path $PSScriptRoot 'Build-MissionSidecar.ps1') `
    -RepositoryRoot $repositoryRoot | Out-Null

if (Test-Path -LiteralPath $workRoot) {
    $resolved = [IO.Path]::GetFullPath($workRoot)
    if ($resolved -eq 'E:\1937' -or $resolved.Length -le 'E:\1937'.Length) {
        throw "Refusing to remove unsafe work directory: $resolved"
    }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
New-Item -ItemType Directory -Path $workRoot | Out-Null
Expand-Archive -LiteralPath $basePackage -DestinationPath $stage

$payload = Join-Path $stage 'payload'
$source = Join-Path $stage 'source'
# Older ZIP tools stored several Chinese entry names without the UTF-8 flag.
# PowerShell extracts those names as literal question marks. Do not propagate
# those unusable aliases into a new release; current files are copied below
# from the repository with their real Unicode names.
Get-ChildItem -LiteralPath $stage -Recurse -File |
    Where-Object { $_.Name.Contains('?') } |
    ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force }
# Root-level localized aliases from the legacy ZIP are also replaced by the
# ASCII, UTF-8-safe v1.3 entry points below.
Get-ChildItem -LiteralPath $stage -File |
    Where-Object { $_.Name -match '[^\x00-\x7F]' } |
    ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force }
$staleFiles = @(
    (Join-Path $payload 'M1937.exe.local'),
    (Join-Path $payload '选择关卡.cmd'),
    (Join-Path $source 'level-selector\选择关卡.cmd')
)
foreach ($staleFile in $staleFiles) {
    if (Test-Path -LiteralPath $staleFile -PathType Leaf) {
        Remove-Item -LiteralPath $staleFile -Force
    }
}
Copy-Item -LiteralPath (Join-Path $proxyRoot 'build\dinput.dll') `
    -Destination (Join-Path $payload 'dinput.dll') -Force
Copy-Item -LiteralPath (Join-Path $modRoot 'ddraw.ini') `
    -Destination (Join-Path $payload 'ddraw.ini') -Force
$sidecarTarget = Join-Path $payload 'Tools\MissionSidecar'
New-Item -ItemType Directory -Path $sidecarTarget -Force | Out-Null
Get-ChildItem -LiteralPath (Join-Path $modRoot 'Tools\MissionSidecar') |
    ForEach-Object {
        Copy-Item -LiteralPath $_.FullName `
            -Destination $sidecarTarget -Recurse -Force
    }
$missionTarget = Join-Path $payload 'Missions'
New-Item -ItemType Directory -Path $missionTarget -Force | Out-Null
Get-ChildItem -LiteralPath (Join-Path $modRoot 'Missions') -File |
    ForEach-Object {
        Copy-Item -LiteralPath $_.FullName `
            -Destination $missionTarget -Force
    }
$sdkSourceTarget = Join-Path $source 'SDK'
$schemaTarget = Join-Path $sdkSourceTarget 'schemas'
New-Item -ItemType Directory -Path $schemaTarget -Force | Out-Null
Copy-Item -LiteralPath (
    Join-Path $repositoryRoot 'SDK\schemas\mission-sidecar-v1.schema.json') `
    -Destination $schemaTarget -Force
Copy-Item -LiteralPath (
    Join-Path $repositoryRoot 'SDK\schemas\mission-state-v1.schema.json') `
    -Destination $schemaTarget -Force
$sidecarSourceTarget = Join-Path $source 'Patch\tools\MissionSidecar'
Copy-SourceTree `
    -From (Join-Path $patchRoot 'tools\MissionSidecar') `
    -To $sidecarSourceTarget
Copy-SourceTree `
    -From (Join-Path $repositoryRoot 'SDK\include') `
    -To (Join-Path $sdkSourceTarget 'include')
Copy-SourceTree `
    -From (Join-Path $repositoryRoot 'SDK\generated') `
    -To (Join-Path $sdkSourceTarget 'generated')
Copy-SourceTree `
    -From (Join-Path $repositoryRoot 'SDK\samples\mission-plugin') `
    -To (Join-Path $sdkSourceTarget 'samples\mission-plugin')
Copy-Item -LiteralPath (Join-Path $proxyRoot 'dinput_proxy.cpp') `
    -Destination (Join-Path $source 'dinput-proxy\dinput_proxy.cpp') -Force
Copy-Item -LiteralPath (Join-Path $proxyRoot 'dinput_proxy.def') `
    -Destination (Join-Path $source 'dinput-proxy\dinput_proxy.def') -Force
Copy-Item -LiteralPath (Join-Path $proxyRoot 'build.cmd') `
    -Destination (Join-Path $source 'dinput-proxy\build.cmd') -Force
Copy-Item -LiteralPath (Join-Path $proxyRoot 'README.md') `
    -Destination (Join-Path $source 'dinput-proxy\README.md') -Force

$selectorSourceTarget = Join-Path $source 'level-selector'
New-Item -ItemType Directory -Path $selectorSourceTarget -Force | Out-Null
foreach ($selectorFile in Get-ChildItem -LiteralPath $selectorRoot -File) {
    Copy-Item -LiteralPath $selectorFile.FullName `
        -Destination (Join-Path $payload $selectorFile.Name) -Force
    Copy-Item -LiteralPath $selectorFile.FullName `
        -Destination (Join-Path $selectorSourceTarget $selectorFile.Name) -Force
}
# v1.2 shipped a now-obsolete wrapper whose body contains both -NoLogo and
# -STA. Match its content so PowerShell 5.1 source-file encoding cannot make
# cleanup depend on a Chinese filename literal.
Get-ChildItem -LiteralPath $payload,$selectorSourceTarget -Filter '*.cmd' -File |
    Where-Object {
        $body = Get-Content -LiteralPath $_.FullName -Raw
        $body -match '-NoLogo' -and $body -match '-STA'
    } |
    ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force }

$helpSource = Get-ChildItem -LiteralPath (Join-Path $patchRoot 'docs') `
    -Filter 'Win10-Win11*.md' -File | Select-Object -First 1
$technicalSource = Get-ChildItem -LiteralPath (Join-Path $patchRoot 'docs') `
    -Filter '1937*' -File | Select-Object -First 1
$stageHelp = Join-Path $stage 'README-Usage.md'
$stageTechnical = Join-Path $stage 'Technical-Notes.md'
$versionSource = Get-ChildItem -LiteralPath (Join-Path $patchRoot 'release') `
    -Filter '*.txt' -File |
    Where-Object { $_.Name -notmatch 'sha256' } |
    Select-Object -First 1
$stageVersion = Join-Path $stage 'Version.txt'

Copy-Item -LiteralPath $helpSource.FullName `
    -Destination $stageHelp -Force
Copy-Item -LiteralPath $helpSource.FullName `
    -Destination (Join-Path $payload 'Win10-Win11-Patch-README.md') -Force
Copy-Item -LiteralPath $technicalSource.FullName `
    -Destination $stageTechnical -Force
Copy-Item -LiteralPath $technicalSource.FullName `
    -Destination (Join-Path $payload 'Win10-Win11-Patch-Technical.md') -Force
Copy-Item -LiteralPath $versionSource.FullName `
    -Destination $stageVersion -Force

$installPath = Join-Path $stage 'Install-Patch.ps1'
$installText = Get-Content -LiteralPath $installPath -Raw -Encoding UTF8
$installText = $installText.Replace(
    '1937 compatibility patch v1.1.1 backup',
    '1937 compatibility patch v1.4.0 backup')
$installText = $installText.Replace(
    '1937 compatibility patch v1.2.0 backup',
    '1937 compatibility patch v1.4.0 backup')
$installText = $installText.Replace(
    '1937 compatibility patch v1.3.0 backup',
    '1937 compatibility patch v1.4.0 backup')
$installText = $installText.Replace(
    '1937 compatibility patch v1.3.2 backup',
    '1937 compatibility patch v1.4.0 backup')
$installText = $installText.Replace(
    '1937 compatibility patch v1.3.3 backup',
    '1937 compatibility patch v1.4.0 backup')
$installText = $installText.Replace(
    '1937 compatibility patch v1.3.4 backup',
    '1937 compatibility patch v1.4.0 backup')
$installText = $installText.Replace(
    '1937 compatibility patch v1.3.5 backup',
    '1937 compatibility patch v1.4.0 backup')
$installText = $installText.Replace(
    '1937 compatibility patch v1.3.6 backup',
    '1937 compatibility patch v1.4.0 backup')
$installText = $installText.Replace(
    '1937 compatibility patch v1.3.7 backup',
    '1937 compatibility patch v1.4.0 backup')
$installText = $installText.Replace(
    'Use the windowed-mode launcher in the game directory. Press Alt+Enter for fullscreen.',
    'Run the modern enhanced launcher, then choose the validated 1024x768 stable window mode.')
[IO.File]::WriteAllText(
    $installPath,
    $installText,
    (New-Object Text.UTF8Encoding($false)))

$sumPath = Join-Path $stage 'SHA256SUMS.txt'
$sumLines = Get-ChildItem -LiteralPath $stage -Recurse -File |
    Where-Object { $_.FullName -ne $sumPath } |
    Sort-Object FullName |
    ForEach-Object {
        $relative = $_.FullName.Substring($stage.Length + 1).Replace('\', '/')
        $hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
        "$hash *$relative"
    }
[IO.File]::WriteAllLines(
    $sumPath,
    [string[]]$sumLines,
    (New-Object Text.UTF8Encoding($false)))

if (Test-Path -LiteralPath $archive) {
    Remove-Item -LiteralPath $archive -Force
}
Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $archive
$zipHash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash
$hashLine = "$zipHash *$([IO.Path]::GetFileName($archive))"
[IO.File]::WriteAllText(
    $archiveHash,
    $hashLine + [Environment]::NewLine,
    (New-Object Text.UTF8Encoding($false)))

[pscustomobject]@{
    Package = $archive
    Sha256 = $zipHash
    Entries = @(Get-ChildItem -LiteralPath $stage -Recurse -File).Count
    WorkDirectory = $stage
}
