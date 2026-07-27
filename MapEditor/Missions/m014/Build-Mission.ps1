param(
    [string]$RepositoryRoot = '',
    [string]$WorkDirectory = ''
)

$ErrorActionPreference = 'Stop'
$missionRoot = [IO.Path]::GetFullPath($PSScriptRoot)
if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    $RepositoryRoot = [IO.Path]::GetFullPath(
        (Join-Path $missionRoot '..\..\..'))
} else {
    $RepositoryRoot = [IO.Path]::GetFullPath($RepositoryRoot)
}
if ([string]::IsNullOrWhiteSpace($WorkDirectory)) {
    $WorkDirectory = Join-Path ([IO.Path]::GetTempPath()) (
        '1937-vwf\m014')
}
$WorkDirectory = [IO.Path]::GetFullPath($WorkDirectory)
[IO.Directory]::CreateDirectory($WorkDirectory) | Out-Null

$source = Join-Path $RepositoryRoot 'Mod\1937m006.vwf'
$composed = Join-Path $WorkDirectory '1937m014-composed.vwf'
$output = Join-Path $RepositoryRoot 'Mod\1937m014.vwf'
$composer = Join-Path $RepositoryRoot (
    'MapEditor\tools\VwfBlueprintComposer\VwfBlueprintComposer.csproj')
$builder = Join-Path $RepositoryRoot (
    'MapEditor\tools\VwfMissionBuilder\VwfMissionBuilder.csproj')
$blueprint = Join-Path $missionRoot 'blueprint.json'
$mission = Join-Path $missionRoot 'mission.json'
$compositionReport = Join-Path $missionRoot 'composition.md'
$validationReport = Join-Path $missionRoot 'validation.md'

dotnet run --project $composer -c Release -- `
    $source $composed $blueprint $compositionReport
if ($LASTEXITCODE -ne 0) {
    throw "VWF blueprint composition failed with exit code $LASTEXITCODE."
}
dotnet run --project $builder -c Release -- `
    $composed $output $mission $validationReport
if ($LASTEXITCODE -ne 0) {
    throw "VWF mission deployment failed with exit code $LASTEXITCODE."
}

if ($IsWindows -or $env:OS -eq 'Windows_NT') {
    $previewScript = Join-Path $RepositoryRoot (
        'MapEditor\tools\VwfBlueprintComposer\Compose-PreviewAssets.ps1')
    $sourceTerrain = Join-Path $RepositoryRoot (
        'MapEditor\Assets\Original\maps\m006\terrain.png')
    $previewDirectory = Join-Path $RepositoryRoot (
        'MapEditor\Assets\Original\maps\m014')
    & $previewScript `
        -SourceTerrain $sourceTerrain `
        -Blueprint $blueprint `
        -OutputDirectory $previewDirectory
}

[pscustomobject]@{
    Output = $output
    Sha256 = (Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash
    CompositionReport = $compositionReport
    ValidationReport = $validationReport
}
