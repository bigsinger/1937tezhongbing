[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$TelemetryPath,
    [Parameter(Mandatory = $true)]
    [string]$ActorStatePath,
    [ValidatePattern('^m\d{3}$')]
    [string]$LevelId = 'm000',
    [string]$OutputPath = '',
    [string]$RepositoryRoot = '',
    [ValidateRange(120, 100000)]
    [int]$MinimumRounds = 120
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
$TelemetryPath = [IO.Path]::GetFullPath($TelemetryPath)
$ActorStatePath = [IO.Path]::GetFullPath($ActorStatePath)
foreach ($requiredPath in @($TelemetryPath, $ActorStatePath)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "Runtime timing evidence is missing: $requiredPath"
    }
}

$remakeRoot = Join-Path $RepositoryRoot 'Remake'
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $remakeRoot (
        'game\data\original_crt_random_runtime_timing.json')
}
$OutputPath = [IO.Path]::GetFullPath($OutputPath)
$startupPath = Join-Path $remakeRoot (
    'game\data\original_crt_random_startup_catalog.json')
$callSitePath = Join-Path $RepositoryRoot (
    'SDK\crt-rand-call-sites.json')

function Read-Utf8Json {
    param([string]$Path)
    return (
        [IO.File]::ReadAllText(
            $Path,
            [Text.UTF8Encoding]::new($false)) |
            ConvertFrom-Json)
}

function Canonical-Rva {
    param([string]$Value)
    $trimmed = $Value.Trim()
    if ($trimmed.StartsWith(
            '0x',
            [StringComparison]::OrdinalIgnoreCase)) {
        return '0x' + $trimmed.Substring(2).ToUpperInvariant()
    }
    return $trimmed.ToUpperInvariant()
}

function Get-Utf8Sha256 {
    param([string]$Value)
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.UTF8Encoding]::new($false).GetBytes($Value)
        return ([BitConverter]::ToString(
            $algorithm.ComputeHash($bytes))).Replace('-', '')
    }
    finally {
        $algorithm.Dispose()
    }
}

$startup = Read-Utf8Json -Path $startupPath
$callSiteCatalog = Read-Utf8Json -Path $callSitePath
if (
    [int]$startup.schema_version -ne 3 -or
    [string]$startup.catalog_id -ne (
        'original-crt-random-startup-v3') -or
    [string]$startup.content_profile -ne (
        'repository-mod-12-level-20260729')
) {
    throw 'Unsupported startup catalog for runtime timing evidence.'
}
$level = @($startup.levels | Where-Object {
    [string]$_.id -eq $LevelId
})
if ($level.Count -ne 1) {
    throw "Startup profile is missing or duplicated: $LevelId"
}
$level = $level[0]
$expectedGateActors = @(
    $level.observation_gate_actor_indices |
        ForEach-Object { [int]$_ }
)
if ($expectedGateActors.Count -eq 0) {
    throw "Startup profile has no observation-gate actors: $LevelId"
}
$expectedPrimaryActors = @(
    foreach ($outcome in $level.first_gameplay_update.actor_outcomes) {
        if (@($outcome.semantic_effects) -contains (
                'primary_candidate_scan')) {
            [int]$outcome.runtime_index
        }
    }
)
if ($expectedPrimaryActors.Count -eq 0) {
    throw "Startup profile has no primary candidate actors: $LevelId"
}

$cataloguedSites = @{}
foreach ($caller in $callSiteCatalog.callers) {
    foreach ($operation in $caller.operations) {
        foreach ($rawSite in $operation.sites) {
            $site = Canonical-Rva ([string]$rawSite)
            $cataloguedSites[$site] = $true
        }
    }
}

$actorIndexByAddress = @{}
foreach ($row in Import-Csv -LiteralPath $ActorStatePath) {
    $address = ([string]$row.address).Trim().ToUpperInvariant()
    if ($address -notmatch '^0X[0-9A-F]{8}$') {
        throw "Invalid actor address: $address"
    }
    if ($actorIndexByAddress.ContainsKey($address)) {
        throw "Duplicate actor address: $address"
    }
    $actorIndexByAddress[$address] = [int]$row.index
}

function Get-RuntimeIndex {
    param([object]$Record)
    $address = (
        [string]$Record.caller_esi
    ).Trim().ToUpperInvariant()
    if ($actorIndexByAddress.ContainsKey($address)) {
        return [int]$actorIndexByAddress[$address]
    }
    return -1
}

$records = [Collections.Generic.List[object]]::new()
foreach ($line in [IO.File]::ReadLines(
        $TelemetryPath,
        [Text.UTF8Encoding]::new($false))) {
    if (-not $line.Contains('"event":"crt_rand_batch"')) {
        continue
    }
    $batch = $line | ConvertFrom-Json
    foreach ($record in $batch.records) {
        $records.Add($record)
    }
}
if ($records.Count -eq 0) {
    throw 'Telemetry contains no CRT random records.'
}

$state = [uint64]1
$previousSequence = 0
foreach ($record in $records) {
    $sequence = [int]$record.sequence
    if (
        ($previousSequence -eq 0 -and $sequence -ne 1) -or
        ($previousSequence -gt 0 -and
            $sequence -ne $previousSequence + 1)
    ) {
        throw (
            "CRT sequence is not contiguous: " +
            "$previousSequence -> $sequence")
    }
    $previousSequence = $sequence
    $site = Canonical-Rva ([string]$record.call_site_rva)
    if (-not $cataloguedSites.ContainsKey($site)) {
        throw "Uncatalogued CRT call site: $site"
    }
    if ($null -eq $record.PSObject.Properties['tick_ms']) {
        throw "Timestamp is missing at sequence $sequence."
    }
    $state = (
        ($state * [uint64]214013 + [uint64]2531011) -band
        [uint64]4294967295
    )
    $expectedValue = [int](($state -shr 16) -band 0x7fff)
    if ($expectedValue -ne [int]$record.value) {
        throw (
            "CRT LCG mismatch at sequence ${sequence}: " +
            "$expectedValue != $($record.value)")
    }
}

$firstGameplaySequence = [int](
    $level.first_gameplay_update_sequence)
$runtimeRecords = @($records | Where-Object {
    [int]$_.sequence -ge $firstGameplaySequence
})
if (
    $runtimeRecords.Count -eq 0 -or
    [int]$runtimeRecords[0].sequence -ne $firstGameplaySequence -or
    (Canonical-Rva (
        [string]$runtimeRecords[0].call_site_rva)) -ne (
        '0x0005C81C')
) {
    throw 'Runtime trace does not start at the proven gameplay boundary.'
}

$rounds = [Collections.Generic.List[object]]::new()
$currentRound = $null
$siteCounts = @{}
$orderText = [Text.StringBuilder]::new()
foreach ($record in $runtimeRecords) {
    $site = Canonical-Rva ([string]$record.call_site_rva)
    $runtimeIndex = Get-RuntimeIndex -Record $record
    if (
        $site -eq '0x0005C81C' -and
        $runtimeIndex -eq $expectedGateActors[0]
    ) {
        $currentRound = [ordered]@{
            index = $rounds.Count + 1
            tick_ms = [long]$record.tick_ms
            gate_actors =
                [Collections.Generic.List[int]]::new()
            primary_actors =
                [Collections.Generic.List[int]]::new()
        }
        $rounds.Add($currentRound)
    }
    if ($null -eq $currentRound) {
        throw (
            "Runtime call precedes the first actor round: " +
            "$($record.sequence)")
    }
    if (-not $siteCounts.ContainsKey($site)) {
        $siteCounts[$site] = 0
    }
    $siteCounts[$site] = [int]$siteCounts[$site] + 1
    if ($site -eq '0x0005C81C') {
        if ($runtimeIndex -lt 0) {
            throw "Observation gate has no actor at $($record.sequence)."
        }
        $currentRound.gate_actors.Add($runtimeIndex)
        [void]$orderText.Append(
            ('{0}:{1}:{2}' -f
                $currentRound.index, $site, $runtimeIndex)
        ).Append("`n")
    }
    elseif ($site -eq '0x00055216') {
        if ($runtimeIndex -lt 0) {
            throw "Candidate scan has no actor at $($record.sequence)."
        }
        $currentRound.primary_actors.Add($runtimeIndex)
        [void]$orderText.Append(
            ('{0}:{1}:{2}' -f
                $currentRound.index, $site, $runtimeIndex)
        ).Append("`n")
    }
}
if ($rounds.Count -lt $MinimumRounds) {
    throw (
        "Only $($rounds.Count) actor rounds were captured; " +
        "$MinimumRounds required.")
}
foreach ($round in $rounds) {
    if (
        (@($round.gate_actors) -join ',') -ne
            ($expectedGateActors -join ',') -or
        (@($round.primary_actors) -join ',') -ne
            ($expectedPrimaryActors -join ',')
    ) {
        throw "Actor random-call order diverged in round $($round.index)."
    }
}

$intervals = [Collections.Generic.List[long]]::new()
for ($index = 1; $index -lt $rounds.Count; $index++) {
    $intervals.Add(
        [long]$rounds[$index].tick_ms -
        [long]$rounds[$index - 1].tick_ms)
}
$steadyIntervals = @($intervals | Where-Object {
    $_ -ge 10 -and $_ -le 40
})
$zeroIntervals = @($intervals | Where-Object { $_ -eq 0 }).Count
$stallIntervals = @($intervals | Where-Object { $_ -gt 40 }).Count
if (
    $steadyIntervals.Count -lt [Math]::Floor(
        $intervals.Count * 0.95) -or
    $zeroIntervals -gt 1
) {
    throw 'Timestamped actor rounds are not a stable 60 Hz sample.'
}
$sortedIntervals = @($steadyIntervals | Sort-Object)
$intervalMeasure = $steadyIntervals | Measure-Object `
    -Average -Minimum -Maximum
$p50Index = [int][Math]::Floor(
    ($sortedIntervals.Count - 1) * 0.50)
$p95Index = [int][Math]::Floor(
    ($sortedIntervals.Count - 1) * 0.95)
$averageMs = [double]$intervalMeasure.Average
$frequencyHz = 1000.0 / $averageMs
if ($frequencyHz -lt 59.5 -or $frequencyHz -gt 60.5) {
    throw "Recovered actor cadence is not 60 Hz: $frequencyHz"
}

$gateOrderText = (
    ($expectedGateActors | ForEach-Object { "$_`n" }) -join '')
$counts = @(
    foreach ($site in @($siteCounts.Keys | Sort-Object)) {
        [ordered]@{
            call_site_rva = $site
            count = [int]$siteCounts[$site]
        }
    }
)
$result = [ordered]@{
    schema_version = 1
    baseline_id = 'original-crt-random-runtime-timing-v1'
    content_profile = [string]$startup.content_profile
    executable_sha256 = [string]$startup.executable_sha256
    evidence = [ordered]@{
        capture_mode = 'process-local-crt-rand-hook'
        hook_scope = 'test-only-environment-gated'
        input_scope = 'target-window-only'
        clock = 'GetTickCount milliseconds captured in the rand hook'
        accepted_scope = (
            'actor update cadence/order only; UI command outcome excluded')
        source_trace_sha256 = (
            Get-FileHash -LiteralPath $TelemetryPath `
                -Algorithm SHA256).Hash
        actor_snapshot_sha256 = (
            Get-FileHash -LiteralPath $ActorStatePath `
                -Algorithm SHA256).Hash
    }
    levels = @(
        [ordered]@{
            id = $LevelId
            first_gameplay_sequence = $firstGameplaySequence
            actor_update_round_count = $rounds.Count
            tick_span_ms = (
                [long]$rounds[$rounds.Count - 1].tick_ms -
                [long]$rounds[0].tick_ms)
            observation_gate_actor_indices = $expectedGateActors
            observation_gate_actor_count =
                $expectedGateActors.Count
            observation_gate_draw_count = [int](
                $siteCounts['0x0005C81C'])
            primary_candidate_scan_actor_indices =
                $expectedPrimaryActors
            primary_candidate_scan_actor_count =
                $expectedPrimaryActors.Count
            primary_candidate_scan_draw_count = [int](
                $siteCounts['0x00055216'])
            steady_interval_count = $steadyIntervals.Count
            excluded_zero_interval_count = $zeroIntervals
            excluded_stall_interval_count = $stallIntervals
            steady_average_ms = [Math]::Round($averageMs, 6)
            steady_frequency_hz = [Math]::Round(
                $frequencyHz, 6)
            steady_min_ms = [long]$intervalMeasure.Minimum
            steady_p50_ms = [long]$sortedIntervals[$p50Index]
            steady_p95_ms = [long]$sortedIntervals[$p95Index]
            steady_max_ms = [long]$intervalMeasure.Maximum
            gate_actor_order_sha256 = Get-Utf8Sha256(
                $gateOrderText)
            recurring_actor_call_order_sha256 = Get-Utf8Sha256(
                $orderText.ToString())
            call_site_counts = $counts
        }
    )
}

$parent = Split-Path -Parent $OutputPath
[IO.Directory]::CreateDirectory($parent) | Out-Null
$json = $result | ConvertTo-Json -Depth 8
[IO.File]::WriteAllText(
    $OutputPath,
    $json + [Environment]::NewLine,
    [Text.UTF8Encoding]::new($false))
Write-Host (
    "Runtime timing baseline wrote $($rounds.Count) rounds at " +
    "$([Math]::Round($frequencyHz, 3)) Hz: $OutputPath")
