param(
    [string]$RepositoryRoot = ''
)

$ErrorActionPreference = 'Stop'
$patchRoot = [IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot '..'))
if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    $RepositoryRoot = [IO.Path]::GetFullPath(
        (Join-Path $patchRoot '..'))
}
else {
    $RepositoryRoot = [IO.Path]::GetFullPath($RepositoryRoot)
}
$solution = Join-Path $patchRoot (
    'tools\MissionSidecar\MissionSidecar.slnx')
$hostProject = Join-Path $patchRoot (
    'tools\MissionSidecar\MissionSidecar.Host\' +
    'MissionSidecar.Host.csproj')
$output = Join-Path $RepositoryRoot 'Mod\Tools\MissionSidecar'
$output = [IO.Path]::GetFullPath($output)
$expectedParent = [IO.Path]::GetFullPath(
    (Join-Path $RepositoryRoot 'Mod\Tools')).TrimEnd('\') + '\'
if (-not ($output.TrimEnd('\') + '\').StartsWith(
        $expectedParent,
        [StringComparison]::OrdinalIgnoreCase) -or
    [IO.Path]::GetFileName($output) -ne 'MissionSidecar') {
    throw "Refusing unsafe MissionSidecar output path: $output"
}

dotnet build $solution -c Release
if ($LASTEXITCODE -ne 0) {
    throw "Mission sidecar build failed with exit code $LASTEXITCODE."
}
dotnet run --project (
    Join-Path $patchRoot (
        'tools\MissionSidecar\MissionSidecar.Tests\' +
        'MissionSidecar.Tests.csproj')) -c Release --no-build
if ($LASTEXITCODE -ne 0) {
    throw "Mission sidecar tests failed with exit code $LASTEXITCODE."
}
if (Test-Path -LiteralPath $output -PathType Container) {
    Remove-Item -LiteralPath $output -Recurse -Force
}
dotnet publish $hostProject -c Release --no-build -o $output
if ($LASTEXITCODE -ne 0) {
    throw "Mission sidecar publish failed with exit code $LASTEXITCODE."
}
$manifestPath = Join-Path $output 'build-manifest.json'
$manifest = [ordered]@{
    schema_version = 1
    architecture = 'x64'
    plugin_api_version = 65536
    files = @(
        Get-ChildItem -LiteralPath $output -File |
            Where-Object { $_.FullName -ne $manifestPath } |
            Sort-Object Name |
            ForEach-Object {
                [ordered]@{
                    name = $_.Name
                    length = $_.Length
                    sha256 = (
                        Get-FileHash -LiteralPath $_.FullName `
                            -Algorithm SHA256).Hash
                }
            }
    )
}
$manifest | ConvertTo-Json -Depth 5 |
    Set-Content -LiteralPath $manifestPath -Encoding UTF8

[pscustomobject]@{
    Host = Join-Path $output 'MissionSidecar.Host.exe'
    Manifest = $manifestPath
    Definitions = @(
        Get-ChildItem -LiteralPath (
            Join-Path $RepositoryRoot 'Mod\Missions') `
            -Filter '*.m1937mission.json' -File).Count
    OriginalSaveWriteOperations = 0
}
