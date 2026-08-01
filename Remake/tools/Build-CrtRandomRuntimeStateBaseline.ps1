[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string[]]$EvidenceRoots,
    [string]$OutputPath = '',
    [string]$RepositoryRoot = '',
    [ValidateRange(60, 100000)]
    [int]$MinimumCompleteRounds = 120
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    $RepositoryRoot = [IO.Path]::GetFullPath(
        (Join-Path $PSScriptRoot '..\..'))
}
else {
    $RepositoryRoot = [IO.Path]::GetFullPath($RepositoryRoot)
}
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $RepositoryRoot (
        'Remake\game\data\original_crt_random_runtime_state.json')
}

$node = Get-Command node -ErrorAction Stop
$arguments = [Collections.Generic.List[string]]::new()
$arguments.Add((Join-Path $PSScriptRoot (
    'Build-CrtRandomRuntimeStateBaseline.mjs')))
$arguments.Add('--repository-root')
$arguments.Add($RepositoryRoot)
$arguments.Add('--output')
$arguments.Add([IO.Path]::GetFullPath($OutputPath))
$arguments.Add('--minimum-rounds')
$arguments.Add($MinimumCompleteRounds.ToString(
    [Globalization.CultureInfo]::InvariantCulture))
foreach ($root in $EvidenceRoots) {
    $arguments.Add('--evidence-root')
    $arguments.Add([IO.Path]::GetFullPath($root))
}

& $node.Source @arguments
if ($LASTEXITCODE -ne 0) {
    throw "Runtime-state baseline generator failed: $LASTEXITCODE"
}
