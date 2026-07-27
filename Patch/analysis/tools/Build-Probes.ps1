param(
    [string]$OutputDirectory = ''
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = [IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot '..\..\..'))
$generatedAddresses = Join-Path $repositoryRoot (
    'SDK\generated\M1937Addresses.cs')
$generatedRoutes = Join-Path $repositoryRoot (
    'SDK\generated\M1937MissionRoutes.cs')

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $preferredRoot = 'E:\1937'
    $OutputDirectory = if (Test-Path -LiteralPath $preferredRoot) {
        Join-Path $preferredRoot 'probe-build'
    } else {
        Join-Path $PSScriptRoot 'build'
    }
}
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
[IO.Directory]::CreateDirectory($OutputDirectory) | Out-Null

& (Join-Path $repositoryRoot 'SDK\tools\Generate-SdkArtifacts.ps1') -Check

$references = @(
    'System.dll',
    'System.Core.dll',
    'System.Drawing.dll'
)
foreach ($name in @('OriginalLevelProbe', 'GameFrameProbe')) {
    $source = Join-Path $PSScriptRoot "$name.cs"
    $output = Join-Path $OutputDirectory "$name.exe"
    if (Test-Path -LiteralPath $output -PathType Leaf) {
        Remove-Item -LiteralPath $output -Force
    }
    Add-Type `
        -Path @($generatedAddresses, $generatedRoutes, $source) `
        -ReferencedAssemblies $references `
        -OutputAssembly $output `
        -OutputType ConsoleApplication
}

Write-Host "Probe build passed: $OutputDirectory"
