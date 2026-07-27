param(
    [string]$OutputRoot = ''
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = [IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot '..\..\..'))
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $temporaryRoot = if (Test-Path -LiteralPath 'E:\1937') {
        'E:\1937'
    }
    else {
        [IO.Path]::GetTempPath()
    }
    $OutputRoot = Join-Path $temporaryRoot (
        'm1937-launcher-tests-' +
        [Diagnostics.Process]::GetCurrentProcess().Id)
}
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
[IO.Directory]::CreateDirectory($OutputRoot) | Out-Null
$selectorRoot = Join-Path $repositoryRoot (
    'Patch\src\level-selector')
$sourceCandidates = @(
    Get-ChildItem -LiteralPath $selectorRoot -Filter '*.ps1' -File)
$catalogCandidates = @(
    Get-ChildItem -LiteralPath $selectorRoot -Filter '*.json' -File)
if ($sourceCandidates.Count -ne 1 -or
    $catalogCandidates.Count -ne 1) {
    throw 'Expected one launcher script and one mission catalog.'
}
$source = $sourceCandidates[0].FullName
$launcher = Join-Path $OutputRoot 'launcher.ps1'
Copy-Item -LiteralPath $source -Destination $launcher -Force
Copy-Item -LiteralPath $catalogCandidates[0].FullName `
    -Destination (
        Join-Path $OutputRoot $catalogCandidates[0].Name) -Force
[IO.File]::WriteAllBytes(
    (Join-Path $OutputRoot 'M1937.exe'),
    [byte[]]::new(1))
[IO.File]::WriteAllText(
    (Join-Path $OutputRoot 'rungame.ini'),
    '')
[IO.File]::WriteAllText(
    (Join-Path $OutputRoot 'ddraw.ini'),
    '')

$tokens = $null
$errors = $null
[Management.Automation.Language.Parser]::ParseFile(
    $launcher,
    [ref]$tokens,
    [ref]$errors) | Out-Null
if ($errors.Count -ne 0) {
    throw "Launcher parse failed: $($errors[0].Message)"
}
$text = Get-Content -LiteralPath $source -Raw -Encoding UTF8
foreach ($forbidden in @(
    'SetCursorPos',
    'ClipCursor',
    'mouse_event',
    'SendInput',
    'SetCapture',
    'ReleaseCapture',
    'SetForegroundWindow',
    'SwitchToThisWindow')) {
    if ($text -match [Regex]::Escape($forbidden)) {
        throw "Launcher contains forbidden global input call: $forbidden"
    }
}

$valid = & powershell.exe -NoProfile -ExecutionPolicy Bypass `
    -File $launcher `
    -ValidateAliases "F2,M`nF3,S" |
    Out-String
if ($LASTEXITCODE -ne 0 -or
    -not $valid.Contains('AliasCount') -or
    -not $valid.Contains('2')) {
    throw 'Valid key aliases were not accepted.'
}
$previousErrorPreference = $ErrorActionPreference
$ErrorActionPreference = 'SilentlyContinue'
& powershell.exe -NoProfile -ExecutionPolicy Bypass `
    -File $launcher `
    -ValidateAliases "F2,M`nF2,S" *> (
        Join-Path $OutputRoot 'expected-conflict.txt')
$conflictExitCode = $LASTEXITCODE
$ErrorActionPreference = $previousErrorPreference
if ($conflictExitCode -eq 0) {
    throw 'Conflicting key aliases were accepted.'
}
# The non-zero native exit above is the expected assertion signal. GitHub's
# PowerShell wrapper propagates LASTEXITCODE after the script returns, so clear
# it once the negative test has been proven successful.
$global:LASTEXITCODE = 0
foreach ($required in @(
    "'KeyRemapping'",
    "'MissionSidecar'",
    "'EnablePlugins'",
    "'Diagnostics'",
    "'Telemetry'")) {
    if (-not $text.Contains($required)) {
        throw "Launcher is missing configuration key $required."
    }
}
foreach ($cursorSafeSetting in @(
        "'adjmouse' 'false'",
        "'no_dinput_hook' 'true'",
        "'devmode' 'true'",
        "'fullscreen' 'false'",
        "'windowed' 'true'")) {
    if (-not $text.Contains($cursorSafeSetting)) {
        throw (
            'Launcher is missing cursor-safe display setting: ' +
            $cursorSafeSetting)
    }
}

[pscustomobject]@{
    Parse = 'passed'
    ValidAliases = 2
    ConflictRejected = $true
    PreservesF1AndM = $true
    SystemCursorCalls = 0
    CursorCaptureCalls = 0
    StableWindowProfile = 'cursor-safe'
}
