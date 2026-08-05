[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\', '/')
$testRoot = [IO.Path]::GetFullPath((Join-Path $tempRoot (
    'm1937-content-manifest-test-' + [Guid]::NewGuid().ToString('N'))))
$safePrefix = $tempRoot + [IO.Path]::DirectorySeparatorChar
if (-not $testRoot.StartsWith(
        $safePrefix,
        [StringComparison]::OrdinalIgnoreCase) -or
    -not (Split-Path -Leaf $testRoot).StartsWith(
        'm1937-content-manifest-test-',
        [StringComparison]::Ordinal)) {
    throw "Unsafe content-manifest test directory: $testRoot"
}

$script:checkCount = 0
function Assert-ContentManifest {
    param(
        [bool]$Condition,
        [string]$Description
    )

    $script:checkCount++
    if (-not $Condition) {
        throw "Content-manifest test failed: $Description"
    }
}

$contentRoot = Join-Path $testRoot 'converted'
$firstManifest = Join-Path $testRoot 'content-manifest-1.json'
$secondManifest = Join-Path $testRoot 'content-manifest-2.json'

try {
    foreach ($directory in @(
            $contentRoot,
            (Join-Path $contentRoot 'levels\m000'),
            (Join-Path $contentRoot 'levels\m011'))) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    [IO.File]::WriteAllText(
        (Join-Path $contentRoot 'asset-manifest.json'),
        '{"schema_version":1}',
        [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText(
        (Join-Path $contentRoot 'levels\m000\level.json'),
        '{"level_id":"m000"}',
        [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText(
        (Join-Path $contentRoot 'levels\m011\level.json'),
        '{"level_id":"m011"}',
        [Text.UTF8Encoding]::new($false))

    & (Join-Path $PSScriptRoot 'New-ContentManifest.ps1') `
        -ContentRoot $contentRoot `
        -OutputPath $firstManifest `
        -ProfileId 'synthetic-content-manifest-test' | Out-Null
    & (Join-Path $PSScriptRoot 'New-ContentManifest.ps1') `
        -ContentRoot $contentRoot `
        -OutputPath $secondManifest `
        -ProfileId 'synthetic-content-manifest-test' | Out-Null

    Assert-ContentManifest (
        (Test-Path -LiteralPath $firstManifest -PathType Leaf) -and
        (Test-Path -LiteralPath $secondManifest -PathType Leaf)) (
        'both manifests were written')
    $first = Get-Content -LiteralPath $firstManifest -Raw -Encoding utf8 |
        ConvertFrom-Json
    $second = Get-Content -LiteralPath $secondManifest -Raw -Encoding utf8 |
        ConvertFrom-Json
    Assert-ContentManifest ([int]$first.schema_version -eq 1) (
        'schema version is 1')
    Assert-ContentManifest ([int]$first.file_count -eq 3) (
        'all synthetic files are listed')
    Assert-ContentManifest (@($first.files).Count -eq 3) (
        'file records are materialized')
    Assert-ContentManifest (
        [string]$first.content_identity_sha256 -match '^[0-9a-f]{64}$') (
        'content identity is a lower-case SHA-256')
    Assert-ContentManifest (
        [string]$first.content_identity_sha256 -eq
            [string]$second.content_identity_sha256) (
        'content identity is deterministic')
    Assert-ContentManifest (
        @($first.files | Where-Object { [bool]$_.critical }).Count -eq 3) (
        'all default critical paths are marked')

    & (Join-Path $PSScriptRoot 'Test-ContentPackage.ps1') `
        -ContentRoot $contentRoot `
        -ManifestPath $firstManifest `
        -VerifyAllHashes | Out-Null
    Assert-ContentManifest $true (
        'generated manifest passes full package verification')

    $manifestScriptText = Get-Content -LiteralPath (
        Join-Path $PSScriptRoot 'New-ContentManifest.ps1') -Raw -Encoding utf8
    $buildScriptText = Get-Content -LiteralPath (
        Join-Path $PSScriptRoot 'Build-Playable.ps1') -Raw -Encoding utf8
    Assert-ContentManifest (
        -not $manifestScriptText.Contains(
            '[Security.Cryptography.SHA256]::HashData')) (
        'manifest generation avoids the .NET 5-only SHA256.HashData API')
    Assert-ContentManifest (
        -not $buildScriptText.Contains('[IO.Path]::GetRelativePath')) (
        'playable build avoids the modern-only Path.GetRelativePath API')
}
finally {
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}

Write-Host "Content-manifest tests passed ($script:checkCount checks)."
