param(
    [string]$WorkDirectory = 'E:\1937\patch-v120-build'
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
    -Filter '*v1.1.1-20260718.zip' -File | Select-Object -First 1
$basePackage = if ($basePackageItem) { $basePackageItem.FullName } else { '' }
$packageName = if ($basePackageItem) {
    $basePackageItem.BaseName.Replace(
        'v1.1.1-20260718',
        'v1.2.0-20260726')
} else {
    '1937-compatibility-patch-v1.2.0-20260726'
}
$stage = Join-Path $workRoot $packageName
$archive = Join-Path $patchRoot ('release\' + $packageName + '.zip')
$archiveHash = $archive + '.sha256.txt'
$proxyRoot = Join-Path $patchRoot 'src\dinput-proxy'
$selectorRoot = Join-Path $patchRoot 'src\level-selector'

if (-not (Test-Path -LiteralPath $basePackage -PathType Leaf)) {
    throw "Base package is missing: $basePackage"
}

& (Join-Path $proxyRoot 'build.cmd')
if ($LASTEXITCODE -ne 0) {
    throw "dinput proxy build failed with exit code $LASTEXITCODE"
}

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
Copy-Item -LiteralPath (Join-Path $proxyRoot 'build\dinput.dll') `
    -Destination (Join-Path $payload 'dinput.dll') -Force
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

$helpSource = Get-ChildItem -LiteralPath (Join-Path $patchRoot 'docs') `
    -Filter 'Win10-Win11*.md' -File | Select-Object -First 1
$technicalSource = Get-ChildItem -LiteralPath (Join-Path $patchRoot 'docs') `
    -Filter '1937*' -File | Select-Object -First 1
$stageHelp = Get-ChildItem -LiteralPath $stage -Filter 'README-*.md' -File |
    Select-Object -First 1
$stageTechnical = Get-ChildItem -LiteralPath $stage -Filter '*.md' -File |
    Where-Object { $_.Name -notmatch '^README-' } |
    Select-Object -First 1
$versionSource = Get-ChildItem -LiteralPath (Join-Path $patchRoot 'release') `
    -Filter '*.txt' -File |
    Where-Object { $_.Name -notmatch 'sha256' } |
    Select-Object -First 1
$stageVersion = Get-ChildItem -LiteralPath $stage -Filter '*.txt' -File |
    Where-Object { $_.Name -notmatch '^SHA256SUMS' } |
    Select-Object -First 1

Copy-Item -LiteralPath $helpSource.FullName `
    -Destination $stageHelp.FullName -Force
Copy-Item -LiteralPath $helpSource.FullName `
    -Destination (Join-Path $payload 'Win10-Win11-Patch-README.md') -Force
Copy-Item -LiteralPath $technicalSource.FullName `
    -Destination $stageTechnical.FullName -Force
Copy-Item -LiteralPath $technicalSource.FullName `
    -Destination (Join-Path $payload 'Win10-Win11-Patch-Technical.md') -Force
Copy-Item -LiteralPath $versionSource.FullName `
    -Destination $stageVersion.FullName -Force

$installPath = Join-Path $stage 'Install-Patch.ps1'
$installText = Get-Content -LiteralPath $installPath -Raw -Encoding UTF8
$installText = $installText.Replace(
    '1937 compatibility patch v1.1.1 backup',
    '1937 compatibility patch v1.2.0 backup')
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
