[CmdletBinding()]
param(
    [string]$DatabasePath = '',

    [string]$BaselinePath = '',

    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Release'
)

$ErrorActionPreference = 'Stop'
$remakeRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $remakeRoot '..'))
if ([string]::IsNullOrWhiteSpace($DatabasePath)) {
    $DatabasePath = Join-Path $repositoryRoot 'Mod\1937Database.dbl'
}
if ([string]::IsNullOrWhiteSpace($BaselinePath)) {
    $BaselinePath = Join-Path `
        $remakeRoot `
        'validation\baselines\mod\world-pickups-v1.json'
}
if (-not (Test-Path -LiteralPath $DatabasePath -PathType Leaf)) {
    throw "Stable MOD database is missing: $DatabasePath"
}
if ((Get-Item -LiteralPath $DatabasePath).Length -lt 1000000) {
    throw "Stable MOD database is not materialized: $DatabasePath"
}

$project = Join-Path $PSScriptRoot 'ResourceTool\ResourceTool.csproj'
dotnet run --project $project --configuration $Configuration -- `
    world-pickup-baseline `
    ([IO.Path]::GetFullPath($DatabasePath)) `
    ([IO.Path]::GetFullPath($BaselinePath))
if ($LASTEXITCODE -ne 0) {
    throw "World-pickup baseline generation failed with exit code $LASTEXITCODE."
}

$document = Get-Content -LiteralPath $BaselinePath -Raw -Encoding UTF8 |
    ConvertFrom-Json
if ([int]$document.schema_version -ne 1 -or
    [string]$document.catalog_id -ne 'original-world-pickups-v1' -or
    @($document.pickup_grants).Count -ne 10 -or
    @($document.explosive_props).Count -ne 1) {
    throw 'Generated world-pickup baseline is incomplete.'
}

Write-Host "World-pickup baseline generated: $BaselinePath"
