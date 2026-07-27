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

# PowerShell 7's Add-Type no longer supports emitting ConsoleApplication
# assemblies. Use the inbox Windows PowerShell compiler host when this script
# is entered from pwsh so the same command works locally and in GitHub Actions.
if ($PSVersionTable.PSEdition -eq 'Core') {
    $windowsPowerShell = Join-Path $env:WINDIR (
        'System32\WindowsPowerShell\v1.0\powershell.exe')
    if (-not (Test-Path -LiteralPath $windowsPowerShell -PathType Leaf)) {
        throw 'Windows PowerShell is required to emit the runtime probe executables.'
    }
    & $windowsPowerShell `
        -NoLogo `
        -NoProfile `
        -NonInteractive `
        -ExecutionPolicy Bypass `
        -File $PSCommandPath `
        -OutputDirectory $OutputDirectory
    if ($LASTEXITCODE -ne 0) {
        throw "Windows PowerShell probe build failed with exit code $LASTEXITCODE."
    }
    exit 0
}

& (Join-Path $repositoryRoot 'SDK\tools\Generate-SdkArtifacts.ps1') -Check

$references = @(
    'System.dll',
    'System.Core.dll',
    'System.Drawing.dll'
)
foreach ($name in @(
    'OriginalLevelProbe',
    'GameFrameProbe',
    'ModRegressionProbe',
    'ModPerformanceProbe'
)) {
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
