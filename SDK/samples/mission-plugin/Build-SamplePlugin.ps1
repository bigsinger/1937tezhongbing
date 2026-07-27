param(
    [string]$OutputDirectory = ''
)

$ErrorActionPreference = 'Stop'
$sampleRoot = [IO.Path]::GetFullPath($PSScriptRoot)
$sdkRoot = [IO.Path]::GetFullPath(
    (Join-Path $sampleRoot '..\..'))
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $sampleRoot 'build'
}
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
[IO.Directory]::CreateDirectory($OutputDirectory) | Out-Null

$vswhere = Join-Path ${env:ProgramFiles(x86)} (
    'Microsoft Visual Studio\Installer\vswhere.exe')
if (-not (Test-Path -LiteralPath $vswhere -PathType Leaf)) {
    throw 'Visual Studio C++ Build Tools were not found.'
}
$installation = & $vswhere -latest -products * `
    -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
    -property installationPath
if ([string]::IsNullOrWhiteSpace($installation)) {
    throw 'Visual Studio x64 C++ tools were not found.'
}
$vcvars = Join-Path $installation 'VC\Auxiliary\Build\vcvars64.bat'
$source = Join-Path $sampleRoot 'mission_plugin.cpp'
$output = Join-Path $OutputDirectory 'SampleMissionPlugin.dll'
$object = Join-Path $OutputDirectory 'mission_plugin.obj'
$command = (
    'call "{0}" >nul && cl.exe /nologo /LD /EHsc /std:c++17 ' +
    '/O2 /MT /W4 /WX /I"{1}" "{2}" /Fo:"{3}" /link ' +
    '/OUT:"{4}" /MACHINE:X64 /Brepro') -f @(
        $vcvars,
        (Join-Path $sdkRoot 'include'),
        $source,
        $object,
        $output)
cmd.exe /d /s /c $command
if ($LASTEXITCODE -ne 0) {
    throw "Sample plugin build failed with exit code $LASTEXITCODE."
}
[pscustomobject]@{
    Plugin = $output
    Architecture = 'x64'
    AbiVersion = '0x00010000'
}
