param(
    [string]$RepositoryRoot = ''
)

$ErrorActionPreference = 'Stop'
$patchRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    $RepositoryRoot = [IO.Path]::GetFullPath((Join-Path $patchRoot '..'))
} else {
    $RepositoryRoot = [IO.Path]::GetFullPath($RepositoryRoot)
}

$proxyRoot = Join-Path $patchRoot 'src\dinput-proxy'
$selectorRoot = Join-Path $patchRoot 'src\level-selector'
$modRoot = Join-Path $RepositoryRoot 'Mod'
$gameExe = Join-Path $modRoot 'M1937.exe'

if (-not (Test-Path -LiteralPath $gameExe -PathType Leaf)) {
    throw "Mod runtime is incomplete; M1937.exe is missing: $gameExe"
}

& (Join-Path $proxyRoot 'build.cmd')
if ($LASTEXITCODE -ne 0) {
    throw "dinput proxy build failed with exit code $LASTEXITCODE"
}

$proxyDll = Join-Path $proxyRoot 'build\dinput.dll'
$modDll = Join-Path $modRoot 'dinput.dll'
$proxyHash = (Get-FileHash -LiteralPath $proxyDll -Algorithm SHA256).Hash
$copyProxy = -not (Test-Path -LiteralPath $modDll -PathType Leaf)
if (-not $copyProxy) {
    $copyProxy =
        (Get-FileHash -LiteralPath $modDll -Algorithm SHA256).Hash -ne
        $proxyHash
}
if ($copyProxy) {
    Copy-Item -LiteralPath $proxyDll -Destination $modDll -Force
}
foreach ($selectorFile in Get-ChildItem -LiteralPath $selectorRoot -File) {
    Copy-Item -LiteralPath $selectorFile.FullName `
        -Destination (Join-Path $modRoot $selectorFile.Name) -Force
}

$modHash = (Get-FileHash -LiteralPath $modDll -Algorithm SHA256).Hash
if ($proxyHash -ne $modHash) {
    throw 'Compiled proxy and Mod copy do not match.'
}

[pscustomobject]@{
    Mod = $modRoot
    ProxySha256 = $modHash
    LauncherFiles = @(Get-ChildItem -LiteralPath $selectorRoot -File).Count
}
