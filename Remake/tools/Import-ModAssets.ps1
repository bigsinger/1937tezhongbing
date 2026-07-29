[CmdletBinding()]
param(
    [string]$OutputDirectory = ''
)

$ErrorActionPreference = 'Stop'
$remakeRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $remakeRoot '..'))
$modDirectory = Join-Path $repositoryRoot 'Mod'
$importer = Join-Path $PSScriptRoot 'Import-OriginalAssets.ps1'

if (-not (Test-Path -LiteralPath (
        Join-Path $modDirectory '1937Resources.GFL') -PathType Leaf)) {
    throw (
        "The stable Mod content is unavailable at $modDirectory. " +
        'Run git lfs pull before importing remake assets.')
}
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $remakeRoot 'LocalAssets'
}

& $importer -GameDirectory $modDirectory `
    -OutputDirectory $OutputDirectory
if ($LASTEXITCODE -ne 0) {
    throw "Stable Mod asset import failed with exit code $LASTEXITCODE."
}

$manifestPath = Join-Path $OutputDirectory 'manifest.json'
$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 |
    ConvertFrom-Json
if ($manifest.source.known_version.version_id -ne
    'repository-mod-12-level-20260729' -or
    -not $manifest.source.known_version.is_match) {
    throw 'Imported assets do not identify the supported stable Mod profile.'
}

[pscustomobject]@{
    Source = $modDirectory
    Output = [IO.Path]::GetFullPath($OutputDirectory)
    Profile = $manifest.source.known_version.version_id
    FormalLevels = $manifest.source.formal_level_count
    GflEntries = @($manifest.gfl_entries).Count
}
