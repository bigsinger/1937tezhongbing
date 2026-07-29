param(
    [string]$RepositoryRoot = ''
)

$ErrorActionPreference = 'Stop'
$editorRoot = [IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot '..'))
if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    $RepositoryRoot = [IO.Path]::GetFullPath(
        (Join-Path $editorRoot '..'))
}
else {
    $RepositoryRoot = [IO.Path]::GetFullPath($RepositoryRoot)
}
$solution = Join-Path $editorRoot 'MapEditor.slnx'
$app = Join-Path $editorRoot (
    'MapEditor.App\MapEditor.App.csproj')
$tests = Join-Path $editorRoot (
    'MapEditor.Tests\MapEditor.Tests.csproj')
$output = [IO.Path]::GetFullPath(
    (Join-Path $editorRoot 'LocalBuild'))
$expectedOutput = [IO.Path]::GetFullPath(
    (Join-Path $editorRoot 'LocalBuild'))
if (-not $output.Equals(
        $expectedOutput,
        [StringComparison]::OrdinalIgnoreCase) -or
    -not $output.StartsWith(
        $editorRoot + [IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Refusing to publish outside MapEditor\LocalBuild.'
}

dotnet build $solution -c Release
if ($LASTEXITCODE -ne 0) {
    throw "MapEditor build failed with exit code $LASTEXITCODE."
}
$env:M1937_TEST_ROOT = Join-Path 'E:\1937' (
    'map-editor-publish-tests-' + [Diagnostics.Process]::GetCurrentProcess().Id)
$env:M1937_TEST_VWF_DIRECTORY = Join-Path $RepositoryRoot 'Mod'
$env:M1937_TEST_VWF = Join-Path $RepositoryRoot 'Mod\1937m000.vwf'
$env:M1937_MAPEDITOR_ASSETS = Join-Path $editorRoot 'Assets\Original'
dotnet run --project $tests -c Release --no-build
if ($LASTEXITCODE -ne 0) {
    throw "MapEditor tests failed with exit code $LASTEXITCODE."
}

if (Test-Path -LiteralPath $output -PathType Container) {
    Remove-Item -LiteralPath $output -Recurse -Force
}
[IO.Directory]::CreateDirectory($output) | Out-Null
dotnet publish $app -c Release --no-build `
    -p:DebugType=None `
    -p:DebugSymbols=false `
    -o $output
if ($LASTEXITCODE -ne 0) {
    throw "MapEditor publish failed with exit code $LASTEXITCODE."
}
Get-ChildItem -LiteralPath $output -Filter '*.pdb' -File |
    Remove-Item -Force
$executable = Join-Path $output '1937MapEditor.exe'
if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) {
    throw 'Published MapEditor executable is missing.'
}
$files = @(
    Get-ChildItem -LiteralPath $output -File |
        Sort-Object Name |
        ForEach-Object {
            [ordered]@{
                name = $_.Name
                length = $_.Length
                sha256 = (
                    Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256
                ).Hash
            }
        })
[ordered]@{
    schema = 1
    target_framework = 'net10.0-windows'
    entry_point = '1937MapEditor.exe'
    tests = 'passed'
    original_maps_round_trip = 'm000-m011'
    asset_metadata_count = 1037
    files = $files
} | ConvertTo-Json -Depth 5 |
    Set-Content -LiteralPath (
        Join-Path $output 'build-manifest.json') -Encoding UTF8

[pscustomobject]@{
    Executable = $executable
    Files = $files.Count
    OriginalMaps = 12
    AssetMetadata = 1037
}
