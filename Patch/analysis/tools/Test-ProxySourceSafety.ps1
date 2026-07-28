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
    'SetActiveWindow',
    'SwitchToThisWindow')) {
    if ($source -match [Regex]::Escape($forbidden)) {
        throw "Proxy contains forbidden global input/focus call: $forbidden"
    }
}

foreach ($forbiddenBriefingPrimitive in @(
    'MessageBoxW',
    'SetWindowsHookExW')) {
    if ($source -match [Regex]::Escape(
            $forbiddenBriefingPrimitive)) {
        throw (
            'Text briefing uses a focus/performance-sensitive primitive: ' +
            $forbiddenBriefingPrimitive)
    }
}
foreach ($requiredBriefingElement in @(
    'original_text_asset',
    'Brief_012.psd',
    'Brief_013.psd',
    'Brief_014.psd',
    'briefing_advance')) {
    if (-not $source.Contains($requiredBriefingElement)) {
        throw (
            'Proxy is missing original-flow text briefing element: ' +
            $requiredBriefingElement)
    }
}
if ($source -notmatch (
        '(?s)#if\s+0\s+struct TextBriefingContent.*?' +
        '#endif\s+bool UseEnhancedEnemyAI')) {
    throw 'The obsolete top-level briefing dialog is not compile-disabled.'
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
    InGameTextBriefing = 'original-screen-gfl-text-picture'
    ExternalBriefingDialog = $false
    RuntimeEditableCatalog = 'rebuild-gfl-from-json'
}
