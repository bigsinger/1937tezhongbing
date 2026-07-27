param(
    [string]$RepositoryRoot = ''
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    $RepositoryRoot = [IO.Path]::GetFullPath(
        (Join-Path $PSScriptRoot '..\..\..'))
}
else {
    $RepositoryRoot = [IO.Path]::GetFullPath($RepositoryRoot)
}
$sourcePath = Join-Path $RepositoryRoot (
    'Patch\src\dinput-proxy\dinput_proxy.cpp')
$source = Get-Content -LiteralPath $sourcePath -Raw -Encoding UTF8

foreach ($forbidden in @(
    'SetCursorPos',
    'ClipCursor',
    'mouse_event',
    'SendInput',
    'SetCapture',
    'ReleaseCapture',
    'SetForegroundWindow',
    'SwitchToThisWindow')) {
    if ($source -match [Regex]::Escape($forbidden)) {
        throw "Proxy contains forbidden global input/focus call: $forbidden"
    }
}

$snapshotStart = $source.IndexOf(
    'void FlushTelemetrySnapshot',
    [StringComparison]::Ordinal)
$snapshotEnd = $source.IndexOf(
    'void LoadModConfig',
    $snapshotStart,
    [StringComparison]::Ordinal)
if ($snapshotStart -lt 0 -or $snapshotEnd -le $snapshotStart) {
    throw 'Could not isolate FlushTelemetrySnapshot.'
}
$snapshot = $source.Substring(
    $snapshotStart,
    $snapshotEnd - $snapshotStart)
foreach ($blocking in @(
    'CreateFile',
    'WriteFile',
    'CloseHandle')) {
    if ($snapshot -match [Regex]::Escape($blocking)) {
        throw "Telemetry snapshot performs blocking I/O: $blocking"
    }
}
foreach ($required in @(
    'TelemetryWriterThread',
    'QueueTelemetryLine',
    'kTelemetryQueueCapacity',
    'THREAD_PRIORITY_BELOW_NORMAL',
    'writer_queue_dropped')) {
    if (-not $source.Contains($required)) {
        throw "Proxy is missing asynchronous telemetry element: $required"
    }
}

[pscustomobject]@{
    GlobalInputOrFocusCalls = 0
    TelemetryDiskIoOnInputThread = 0
    TelemetryQueue = 'bounded'
    TelemetryWriterPriority = 'below-normal'
}
