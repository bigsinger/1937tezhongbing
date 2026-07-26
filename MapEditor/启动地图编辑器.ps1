$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($PSScriptRoot)
$published = Join-Path $root 'LocalBuild\1937MapEditor.exe'
if (Test-Path -LiteralPath $published -PathType Leaf) {
    Start-Process -FilePath $published -WorkingDirectory (Split-Path $published)
    exit 0
}
dotnet run --project (Join-Path $root 'MapEditor.App\MapEditor.App.csproj')
