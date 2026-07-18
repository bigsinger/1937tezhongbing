[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Container })]
    [string]$GameDirectory,

    [string]$OutputDirectory
)

$ErrorActionPreference = 'Stop'
$toolProject = Join-Path $PSScriptRoot 'ResourceTool\ResourceTool.csproj'
$resolvedGameDirectory = (Resolve-Path -LiteralPath $GameDirectory).Path
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $PSScriptRoot '..\LocalAssets'
}
$resolvedOutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)

dotnet run --project $toolProject --configuration Release -- import $resolvedGameDirectory $resolvedOutputDirectory
if ($LASTEXITCODE -ne 0) {
    throw "Resource import failed with exit code $LASTEXITCODE."
}

Write-Host "Local import complete: $resolvedOutputDirectory"
Write-Host 'The importer verified that any repository-local output is excluded from Git.'
