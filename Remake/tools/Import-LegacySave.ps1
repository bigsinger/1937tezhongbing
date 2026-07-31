[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string]$SavePath,

    [string]$GameDirectory,

    [string]$PreviewPath,

    [ValidatePattern('^[A-Za-z0-9_-]{1,32}$')]
    [string]$SlotId,

    [string]$OutputDirectory,

    [switch]$Install,

    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$remakeRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $remakeRoot '..'))
$toolProject = Join-Path $PSScriptRoot 'ResourceTool\ResourceTool.csproj'
$dataDirectory = Join-Path $remakeRoot 'game\data'

if ([string]::IsNullOrWhiteSpace($GameDirectory)) {
    $GameDirectory = Join-Path $repositoryRoot 'Mod'
}
$resolvedGameDirectory = (Resolve-Path -LiteralPath $GameDirectory).Path
$resolvedSavePath = (Resolve-Path -LiteralPath $SavePath).Path
if (-not $resolvedSavePath.EndsWith(
    '.SAV',
    [StringComparison]::OrdinalIgnoreCase)) {
    throw "Original save path must have the .SAV extension: $resolvedSavePath"
}

$saveStem = [IO.Path]::GetFileNameWithoutExtension($resolvedSavePath)
$saveNumberMatch = [regex]::Match($saveStem, '(\d{1,3})$')
if ([string]::IsNullOrWhiteSpace($SlotId)) {
    if ($saveNumberMatch.Success) {
        $SlotId = 'legacy_{0:D3}' -f [int]$saveNumberMatch.Groups[1].Value
    }
    else {
        $safeStem = [regex]::Replace(
            $saveStem.ToLowerInvariant(),
            '[^a-z0-9_-]',
            '_')
        $SlotId = "legacy_$safeStem"
    }
}
if ($SlotId.Length -gt 32 -or
    $SlotId -notmatch '^[A-Za-z0-9_-]{1,32}$') {
    throw "Slot ID is not compatible with the Remake save store: $SlotId"
}

if ([string]::IsNullOrWhiteSpace($PreviewPath) -and
    $saveNumberMatch.Success) {
    $previewCandidate = Join-Path $resolvedGameDirectory (
        'M1937.SI{0}' -f [int]$saveNumberMatch.Groups[1].Value)
    if (Test-Path -LiteralPath $previewCandidate -PathType Leaf) {
        $PreviewPath = $previewCandidate
    }
}
$resolvedPreviewPath = $null
if (-not [string]::IsNullOrWhiteSpace($PreviewPath)) {
    $resolvedPreviewPath = (Resolve-Path -LiteralPath $PreviewPath).Path
}

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $remakeRoot 'LocalBuild\ImportedSaves'
}
$resolvedOutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
[IO.Directory]::CreateDirectory($resolvedOutputDirectory) | Out-Null
$outputPath = Join-Path $resolvedOutputDirectory "$SlotId.json"
if ((Test-Path -LiteralPath $outputPath -PathType Leaf) -and -not $Force) {
    throw (
        "Output slot already exists: $outputPath. " +
        'Use -Force to replace it or select another -SlotId.')
}

$arguments = @(
    'run',
    '--project', $toolProject,
    '--configuration', 'Release',
    '--',
    'import-save',
    $resolvedSavePath,
    $resolvedGameDirectory,
    $outputPath
)
if ($null -ne $resolvedPreviewPath) {
    $arguments += $resolvedPreviewPath
}
$arguments += "--slot=$SlotId"
$arguments += "--data-dir=$dataDirectory"

& dotnet @arguments
if ($LASTEXITCODE -ne 0) {
    throw "Original save import failed with exit code $LASTEXITCODE."
}

$installedPath = $null
if ($Install) {
    if ([string]::IsNullOrWhiteSpace($env:APPDATA)) {
        throw 'APPDATA is unavailable; the Remake user-save directory cannot be resolved.'
    }
    $installDirectory = Join-Path $env:APPDATA (
        'Godot\app_userdata\1937 Remake Prototype\saves')
    [IO.Directory]::CreateDirectory($installDirectory) | Out-Null
    $installedPath = Join-Path $installDirectory "$SlotId.json"
    if ((Test-Path -LiteralPath $installedPath -PathType Leaf) -and -not $Force) {
        throw (
            "Installed slot already exists: $installedPath. " +
            'Use -Force to replace it or select another -SlotId.')
    }
    Copy-Item -LiteralPath $outputPath -Destination $installedPath -Force:$Force
}

Write-Host "Converted slot: $outputPath"
if ($null -ne $resolvedPreviewPath) {
    Write-Host (
        'Converted preview: ' +
        [IO.Path]::ChangeExtension($outputPath, '.preview.png'))
}
if ($null -ne $installedPath) {
    Write-Host "Installed slot: $installedPath"
    Write-Host 'Open “读取游戏” in the Remake menu and choose the imported-original slot.'
}
