param(
    [string]$AssetRoot = '',
    [string]$OutputPath = ''
)

$ErrorActionPreference = 'Stop'
$editorRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if ([string]::IsNullOrWhiteSpace($AssetRoot)) {
    $AssetRoot = Join-Path $editorRoot 'Assets\Original'
}
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $AssetRoot 'asset-metadata.json'
}
$catalog = Join-Path $AssetRoot 'catalog.json'
$project = Join-Path $PSScriptRoot 'AssetMetadataTool\AssetMetadataTool.csproj'
dotnet run --project $project -c Release -- $catalog $OutputPath
if ($LASTEXITCODE -ne 0) {
    throw "Asset metadata generation failed with exit code $LASTEXITCODE."
}
