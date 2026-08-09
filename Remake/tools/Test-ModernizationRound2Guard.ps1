[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$remakeRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$repositoryRoot = (Resolve-Path (Join-Path $remakeRoot '..')).Path

& (Join-Path $PSScriptRoot 'Check-NoOriginalAssets.ps1')

$forbiddenPointerPatterns = @(
    'Input\.warp_mouse',
    'DisplayServer\.mouse_set_mode',
    'MOUSE_MODE_CAPTURED',
    'MOUSE_MODE_CONFINED',
    'SetCursorPos',
    'ClipCursor',
    'SendInput',
    'mouse_event\s*\('
) -join '|'

$runtimeFiles = @(
    Get-ChildItem -LiteralPath (Join-Path $remakeRoot 'game\scripts') -Recurse -File |
        Where-Object { $_.Extension -in @('.gd', '.cs') }
    Get-ChildItem -LiteralPath (Join-Path $repositoryRoot 'MapEditor') -Recurse -File |
        Where-Object {
            $_.Extension -in @('.cs', '.xaml') -and
            $_.FullName -notmatch '[\\/](bin|obj|LocalBuild)[\\/]'
        }
)
$pointerViolations = @(
    $runtimeFiles |
        Select-String -Pattern $forbiddenPointerPatterns -CaseSensitive:$false
)
if ($pointerViolations.Count -gt 0) {
    $pointerViolations | ForEach-Object {
        Write-Error "Global pointer API is forbidden: $($_.Path):$($_.LineNumber)"
    }
    throw "Global pointer guard found $($pointerViolations.Count) violation(s)."
}

$requiredBaseline = Join-Path $remakeRoot `
    'validation\baselines\remake\modernization-round2-baseline-v1.json'
$baseline = Get-Content -LiteralPath $requiredBaseline -Raw -Encoding UTF8 |
    ConvertFrom-Json
if ([int]$baseline.schema_version -ne 1 -or
    [string]$baseline.baseline_commit -ne 'daae74b' -or
    [bool]$baseline.reference_stability.global_pointer_control) {
    throw 'Modernization round-two baseline is missing or invalid.'
}

$userDataChanges = @(git -C $repositoryRoot status --short -- Mod)
if ($LASTEXITCODE -ne 0) {
    throw 'Unable to inspect protected Mod user data.'
}
Write-Host (
    'Modernization guard passed. Protected Mod changes observed and left untouched: ' +
    $userDataChanges.Count)
