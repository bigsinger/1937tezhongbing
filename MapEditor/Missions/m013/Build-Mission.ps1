[CmdletBinding()]
param(
    [string]$RepositoryRoot = '',
    [string]$WorkDirectory = ''
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    $RepositoryRoot = [IO.Path]::GetFullPath(
        (Join-Path $PSScriptRoot '..\..\..'))
}

& (Join-Path $RepositoryRoot 'MapEditor\tools\Build-MissionPackage.ps1') `
    -MissionId m013 `
    -RepositoryRoot $RepositoryRoot `
    -WorkDirectory $WorkDirectory
