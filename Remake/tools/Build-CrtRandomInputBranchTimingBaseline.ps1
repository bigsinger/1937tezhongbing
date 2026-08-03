[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$EvidenceDirectory,
    [string]$OutputPath = '',
    [string]$RepositoryRoot = ''
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
$EvidenceDirectory = [IO.Path]::GetFullPath($EvidenceDirectory)
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $RepositoryRoot (
        'Remake\game\data\original_crt_random_input_branch_timing.json')
}
$OutputPath = [IO.Path]::GetFullPath($OutputPath)

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
        return '0x' + $trimmed.Substring(2).PadLeft(
            8, '0').ToUpperInvariant()
    }
    return $trimmed.ToUpperInvariant()
}

function ConvertTo-Hex {
    param([byte[]]$Bytes)
    return ([BitConverter]::ToString($Bytes)).Replace('-', '')
}

function Get-Sha256Bytes {
    param([byte[]]$Bytes)
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try {
        return ConvertTo-Hex $algorithm.ComputeHash($Bytes)
    }
    finally {
        $algorithm.Dispose()
    }
}

function New-PendingRound {
    param(
        [int]$Index,
        [int]$FirstSequence
    )
    $orderStream = [IO.MemoryStream]::new()
    $valueStream = [IO.MemoryStream]::new()
    $actorOrderStream = [IO.MemoryStream]::new()
    $actorValueStream = [IO.MemoryStream]::new()
    return [ordered]@{
        Index = $Index
        FirstSequence = $FirstSequence
        LastSequence = $FirstSequence
        FinalState = [uint64]0
        DrawCount = 0
        ActorDrawCount = 0
        GateActors = [Collections.Generic.List[int]]::new()
        SiteCounts = @{}
        ActorSiteCounts = @{}
        ActorEvents = [Collections.Generic.List[object]]::new()
        InputEvents = [Collections.Generic.List[object]]::new()
        OrderStream = $orderStream
        ValueStream = $valueStream
        ActorOrderStream = $actorOrderStream
        ActorValueStream = $actorValueStream
        OrderWriter = [IO.BinaryWriter]::new($orderStream)
        ValueWriter = [IO.BinaryWriter]::new($valueStream)
        ActorOrderWriter = [IO.BinaryWriter]::new($actorOrderStream)
        ActorValueWriter = [IO.BinaryWriter]::new($actorValueStream)
    }
}

function Complete-PendingRound {
    param(
        [Collections.Specialized.OrderedDictionary]$Round,
        [int[]]$ExpectedGateActors
    )
    if (
        (@($Round.GateActors) -join ',') -ne
        ($ExpectedGateActors -join ',')
    ) {
        throw (
            "Observation-gate actor order diverged in round " +
            "$($Round.Index).")
    }
    foreach ($writer in @(
            $Round.OrderWriter,
            $Round.ValueWriter,
            $Round.ActorOrderWriter,
            $Round.ActorValueWriter)) {
        $writer.Flush()
    }
    $orderBytes = $Round.OrderStream.ToArray()
    $valueBytes = $Round.ValueStream.ToArray()
    $actorOrderBytes = $Round.ActorOrderStream.ToArray()
    $actorValueBytes = $Round.ActorValueStream.ToArray()
    foreach ($writer in @(
            $Round.OrderWriter,
            $Round.ValueWriter,
            $Round.ActorOrderWriter,
            $Round.ActorValueWriter)) {
        $writer.Dispose()
    }
    return [pscustomobject]@{
        Summary = [ordered]@{
            index = [int]$Round.Index
            first_sequence = [int]$Round.FirstSequence
            last_sequence = [int]$Round.LastSequence
            draw_count = [int]$Round.DrawCount
            actor_draw_count = [int]$Round.ActorDrawCount
            final_state_hex = '0x{0:X8}' -f [uint32]$Round.FinalState
            ordered_call_site_actor_sha256 = Get-Sha256Bytes $orderBytes
            ordered_call_site_actor_value_sha256 = Get-Sha256Bytes $valueBytes
            actor_order_sha256 = Get-Sha256Bytes $actorOrderBytes
            actor_value_sha256 = Get-Sha256Bytes $actorValueBytes
        }
        OrderBytes = $orderBytes
        ValueBytes = $valueBytes
        ActorOrderBytes = $actorOrderBytes
        ActorValueBytes = $actorValueBytes
        SiteCounts = $Round.SiteCounts
        ActorSiteCounts = $Round.ActorSiteCounts
        ActorEvents = @($Round.ActorEvents)
        InputEvents = @($Round.InputEvents)
    }
}

$summaryPath = Join-Path $EvidenceDirectory (
    'crt-random-runtime-summary.json')
$telemetryPath = Join-Path $EvidenceDirectory 'M1937Telemetry.jsonl'
$actorStatePath = Join-Path $EvidenceDirectory 'actor-states-entry.csv'
$scenarioPath = Join-Path $EvidenceDirectory 'mod-m000-basic-movement-v1.json'
foreach ($requiredPath in @(
        $summaryPath,
        $telemetryPath,
        $actorStatePath,
        $scenarioPath)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "Missing input-branch evidence file: $requiredPath"
    }
}

$summary = Read-Utf8Json -Path $summaryPath
$scenario = Read-Utf8Json -Path $scenarioPath
$startup = Read-Utf8Json -Path (Join-Path $RepositoryRoot (
    'Remake\game\data\original_crt_random_startup_catalog.json'))
$callSiteCatalog = Read-Utf8Json -Path (Join-Path $RepositoryRoot (
    'SDK\crt-rand-call-sites.json'))
$contentProfile = 'repository-mod-12-level-20260729'
if (
    [int]$summary.schema_version -ne 1 -or
    [string]$summary.source_profile -ne $contentProfile -or
    [string]$summary.level_id -ne 'm000' -or
    [int]$scenario.schema_version -ne 1 -or
    [string]$scenario.content_profile -ne $contentProfile -or
    [string]$scenario.level.id -ne 'm000' -or
    [string]$scenario.scenario.id -ne 'm000-basic-movement-v1'
) {
    throw 'Unsupported m000 movement input-branch evidence.'
}
if (
    [string]$summary.executable_sha256 -ne
        [string]$startup.executable_sha256
) {
    throw 'Input-branch executable hash differs from the startup catalog.'
}

$cataloguedSites = @{}
foreach ($caller in $callSiteCatalog.callers) {
    foreach ($operation in $caller.operations) {
        foreach ($rawSite in $operation.sites) {
            $cataloguedSites[(Canonical-Rva ([string]$rawSite))] = $true
        }
    }
}
$actorIndexByAddress = @{}
foreach ($row in Import-Csv -LiteralPath $actorStatePath) {
    $address = ([string]$row.address).Trim().ToUpperInvariant()
    if ($address -notmatch '^0X[0-9A-F]{8}$') {
        throw "Invalid actor address: $address"
    }
    if ($actorIndexByAddress.ContainsKey($address)) {
        throw "Duplicate actor address: $address"
    }
    $actorIndexByAddress[$address] = [int]$row.index
}

$firstGameplaySequence = [int](
    $summary.startup.first_gameplay_update_sequence)
$expectedGateActors = @(
    $summary.startup.observation_gate_actor_indices |
        ForEach-Object { [int]$_ })
if ($expectedGateActors.Count -eq 0) {
    throw 'Input branch has no observation-gate actors.'
}
$actorEventSites = @(
    '0x00055216', '0x0005528C', '0x000552A3', '0x000552BA',
    '0x000552D1', '0x00055BFB', '0x00055C0F', '0x00055C23',
    '0x00055C3A', '0x00056105', '0x0005614F', '0x00058946',
    '0x0005CB2B', '0x0005CEA6', '0x0005CF33', '0x0005CF4A',
    '0x0005CF61', '0x0005CF78', '0x0005D08F', '0x0005D09D',
    '0x0005D0B4', '0x0005D0CB', '0x0005D15F', '0x0005D394',
    '0x0005D47E')
$acknowledgementSites = @(
    '0x0005D7CF', '0x0005D7F8', '0x0005D821', '0x0005D855')

$rounds = [Collections.Generic.List[object]]::new()
$actorEvents = [Collections.Generic.List[object]]::new()
$inputEvents = [Collections.Generic.List[object]]::new()
$pendingRound = $null
$globalOrderStream = [IO.MemoryStream]::new()
$globalValueStream = [IO.MemoryStream]::new()
$globalActorOrderStream = [IO.MemoryStream]::new()
$globalActorValueStream = [IO.MemoryStream]::new()
$globalOrderWriter = [IO.BinaryWriter]::new($globalOrderStream)
$globalValueWriter = [IO.BinaryWriter]::new($globalValueStream)
$globalActorOrderWriter = [IO.BinaryWriter]::new($globalActorOrderStream)
$globalActorValueWriter = [IO.BinaryWriter]::new($globalActorValueStream)
$globalSiteCounts = @{}
$globalActorSiteCounts = @{}
$acceptedDrawCount = 0
$acceptedActorDrawCount = 0
$state = [uint64]1
$previousSequence = 0

foreach ($line in [IO.File]::ReadLines(
        $telemetryPath,
        [Text.UTF8Encoding]::new($false))) {
    if (-not $line.Contains('"event":"crt_rand_batch"')) {
        continue
    }
    $batch = $line | ConvertFrom-Json
    foreach ($record in $batch.records) {
        $sequence = [int]$record.sequence
        if (
            ($previousSequence -eq 0 -and $sequence -ne 1) -or
            ($previousSequence -gt 0 -and
                $sequence -ne $previousSequence + 1)
        ) {
            throw "Non-contiguous CRT sequence: $previousSequence -> $sequence"
        }
        $previousSequence = $sequence
        $site = Canonical-Rva ([string]$record.call_site_rva)
        if (-not $cataloguedSites.ContainsKey($site)) {
            throw "Uncatalogued CRT call site: $site"
        }
        $state = (
            ($state * [uint64]214013 + [uint64]2531011) -band
            [uint64]4294967295)
        $expectedValue = [int](($state -shr 16) -band 0x7fff)
        if ($expectedValue -ne [int]$record.value) {
            throw (
                "CRT LCG mismatch at sequence ${sequence}: " +
                "$expectedValue != $($record.value)")
        }
        if ($sequence -lt $firstGameplaySequence) {
            continue
        }

        $runtimeAddress = (
            [string]$record.caller_esi).Trim().ToUpperInvariant()
        $runtimeIndex = -1
        if ($actorIndexByAddress.ContainsKey($runtimeAddress)) {
            $runtimeIndex = [int]$actorIndexByAddress[$runtimeAddress]
        }
        $isRoundMarker = (
            $site -eq '0x0005C81C' -and
            $runtimeIndex -eq $expectedGateActors[0])
        if ($isRoundMarker) {
            if ($null -ne $pendingRound) {
                $completed = Complete-PendingRound `
                    -Round $pendingRound `
                    -ExpectedGateActors $expectedGateActors
                $rounds.Add($completed.Summary)
                $globalOrderWriter.Write($completed.OrderBytes)
                $globalValueWriter.Write($completed.ValueBytes)
                $globalActorOrderWriter.Write($completed.ActorOrderBytes)
                $globalActorValueWriter.Write($completed.ActorValueBytes)
                $acceptedDrawCount += [int]$completed.Summary.draw_count
                $acceptedActorDrawCount += [int](
                    $completed.Summary.actor_draw_count)
                foreach ($countSite in $completed.SiteCounts.Keys) {
                    $globalSiteCounts[$countSite] = (
                        [int]$globalSiteCounts[$countSite] +
                        [int]$completed.SiteCounts[$countSite])
                }
                foreach ($actorSite in $completed.ActorSiteCounts.Keys) {
                    $globalActorSiteCounts[$actorSite] = (
                        [int]$globalActorSiteCounts[$actorSite] +
                        [int]$completed.ActorSiteCounts[$actorSite])
                }
                foreach ($event in $completed.ActorEvents) {
                    $actorEvents.Add($event)
                }
                foreach ($event in $completed.InputEvents) {
                    $inputEvents.Add($event)
                }
            }
            $pendingRound = New-PendingRound `
                -Index ($rounds.Count + 1) `
                -FirstSequence $sequence
        }
        if ($null -eq $pendingRound) {
            throw "Runtime call precedes the first actor round: $sequence"
        }

        $siteValue = [Convert]::ToUInt32($site.Substring(2), 16)
        $pendingRound.OrderWriter.Write([uint32]$siteValue)
        $pendingRound.OrderWriter.Write([int]$runtimeIndex)
        $pendingRound.ValueWriter.Write([uint32]$siteValue)
        $pendingRound.ValueWriter.Write([int]$runtimeIndex)
        $pendingRound.ValueWriter.Write([uint32]$expectedValue)
        $pendingRound.DrawCount = [int]$pendingRound.DrawCount + 1
        $pendingRound.LastSequence = $sequence
        $pendingRound.FinalState = $state
        $pendingRound.SiteCounts[$site] = (
            [int]$pendingRound.SiteCounts[$site] + 1)
        if ($runtimeIndex -ge 0) {
            $pendingRound.ActorOrderWriter.Write([uint32]$siteValue)
            $pendingRound.ActorOrderWriter.Write([int]$runtimeIndex)
            $pendingRound.ActorValueWriter.Write([uint32]$siteValue)
            $pendingRound.ActorValueWriter.Write([int]$runtimeIndex)
            $pendingRound.ActorValueWriter.Write([uint32]$expectedValue)
            $pendingRound.ActorDrawCount = (
                [int]$pendingRound.ActorDrawCount + 1)
            $actorSiteKey = "${runtimeIndex}|${site}"
            $pendingRound.ActorSiteCounts[$actorSiteKey] = (
                [int]$pendingRound.ActorSiteCounts[$actorSiteKey] + 1)
            if ($site -in $actorEventSites) {
                [object]$event = @(
                    [int]$pendingRound.Index,
                    [int]$runtimeIndex,
                    [uint32]$siteValue,
                    [int]$expectedValue)
                $pendingRound.ActorEvents.Add($event)
            }
            if ($site -in $acknowledgementSites) {
                $pendingRound.InputEvents.Add([ordered]@{
                    round_index = [int]$pendingRound.Index
                    sequence = $sequence
                    runtime_index = $runtimeIndex
                    call_site_rva = $site
                    value = $expectedValue
                })
            }
        }
        if ($site -eq '0x0005C81C') {
            if ($runtimeIndex -lt 0) {
                throw "Observation gate has no actor at sequence $sequence."
            }
            $pendingRound.GateActors.Add($runtimeIndex)
        }
    }
}

# The final marker proves the preceding round, but its own round is incomplete.
if ($null -ne $pendingRound) {
    foreach ($writer in @(
            $pendingRound.OrderWriter,
            $pendingRound.ValueWriter,
            $pendingRound.ActorOrderWriter,
            $pendingRound.ActorValueWriter)) {
        $writer.Dispose()
    }
}
foreach ($writer in @(
        $globalOrderWriter,
        $globalValueWriter,
        $globalActorOrderWriter,
        $globalActorValueWriter)) {
    $writer.Flush()
}

if ($rounds.Count -ne 413 -or $inputEvents.Count -ne 2) {
    throw (
        "Unexpected recovered branch size: $($rounds.Count) rounds, " +
        "$($inputEvents.Count) acknowledgement events.")
}
$checkpointIds = @(
    'move_outbound_commanded',
    'move_return_commanded')
for ($eventIndex = 0; $eventIndex -lt $inputEvents.Count; $eventIndex++) {
    $checkpointId = $checkpointIds[$eventIndex]
    $checkpoint = @($scenario.checkpoints | Where-Object {
        [string]$_.id -eq $checkpointId
    })[0]
    $actor = @($checkpoint.actors)[0]
    $target = @($actor.target_position)
    $inputEvents[$eventIndex].checkpoint_id = $checkpointId
    $inputEvents[$eventIndex].destination_x = [int]$target[0]
    $inputEvents[$eventIndex].destination_y = [int]$target[1]
}

$counts = @(
    foreach ($site in @($globalSiteCounts.Keys | Sort-Object)) {
        [ordered]@{
            call_site_rva = $site
            count = [int]$globalSiteCounts[$site]
        }
    })
$actorCounts = @(
    $globalActorSiteCounts.GetEnumerator() |
        ForEach-Object {
            $parts = ([string]$_.Key).Split('|', 2)
            [pscustomobject][ordered]@{
                runtime_index = [int]$parts[0]
                call_site_rva = [string]$parts[1]
                count = [int]$_.Value
            }
        } |
        Sort-Object `
            @{ Expression = { [int]$_.runtime_index } }, `
            @{ Expression = { [string]$_.call_site_rva } })
$actorEventText = [string]::Join(
    "`n",
    @($actorEvents | ForEach-Object { @($_) -join '|' })) + "`n"

$lastRound = $rounds[$rounds.Count - 1]
$result = [ordered]@{
    schema_version = 1
    baseline_id = 'original-crt-random-input-branch-timing-v1'
    content_profile = $contentProfile
    executable_sha256 = [string]$summary.executable_sha256
    evidence = [ordered]@{
        capture_mode = 'process-local-crt-rand-hook'
        input_isolation = [string]$scenario.metadata.input_isolation
        source_trace_sha256 = (
            Get-FileHash -LiteralPath $telemetryPath -Algorithm SHA256).Hash
        actor_snapshot_sha256 = (
            Get-FileHash -LiteralPath $actorStatePath -Algorithm SHA256).Hash
        scenario_sha256 = (
            Get-FileHash -LiteralPath $scenarioPath -Algorithm SHA256).Hash
        accepted_scope = (
            '413 proven-complete actor-update rounds; final tail omitted')
    }
    hash_encoding = [ordered]@{
        byte_order = 'little-endian'
        order_record = 'uint32 call_site_rva + int32 runtime_index'
        value_record = (
            'uint32 call_site_rva + int32 runtime_index + uint32 rand_value')
        non_actor_runtime_index = -1
        algorithm = 'SHA-256'
    }
    branches = @([ordered]@{
        id = 'm000-basic-movement-v1'
        level_id = 'm000'
        description = [string]$scenario.scenario.description
        first_gameplay_sequence = $firstGameplaySequence
        first_accepted_sequence = [int]$rounds[0].first_sequence
        last_accepted_sequence = [int]$lastRound.last_sequence
        complete_round_count = $rounds.Count
        quiet_prefix_round_count = 297
        accepted_draw_count = $acceptedDrawCount
        accepted_actor_draw_count = $acceptedActorDrawCount
        initial_state_hex = [string]$summary.startup.final_state_hex
        final_state_hex = [string]$lastRound.final_state_hex
        final_draw_index = [int]$lastRound.last_sequence
        observation_gate_actor_indices = $expectedGateActors
        ordered_call_site_actor_sha256 = Get-Sha256Bytes (
            $globalOrderStream.ToArray())
        ordered_call_site_actor_value_sha256 = Get-Sha256Bytes (
            $globalValueStream.ToArray())
        actor_order_sha256 = Get-Sha256Bytes (
            $globalActorOrderStream.ToArray())
        actor_value_sha256 = Get-Sha256Bytes (
            $globalActorValueStream.ToArray())
        call_site_counts = $counts
        actor_call_site_counts = $actorCounts
        input_events = @($inputEvents)
        actor_event_count = $actorEvents.Count
        actor_events_sha256 = Get-Sha256Bytes (
            [Text.UTF8Encoding]::new($false).GetBytes($actorEventText))
        actor_events = @($actorEvents)
        rounds = @($rounds)
    })
}

foreach ($writer in @(
        $globalOrderWriter,
        $globalValueWriter,
        $globalActorOrderWriter,
        $globalActorValueWriter)) {
    $writer.Dispose()
}
$parent = Split-Path -Parent $OutputPath
if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
}
$json = $result | ConvertTo-Json -Depth 20 -Compress
[IO.File]::WriteAllText(
    $OutputPath,
    $json + "`n",
    [Text.UTF8Encoding]::new($false))
Write-Host (
    "Recovered m000 input branch: $($rounds.Count) complete rounds, " +
    "$acceptedDrawCount draws, $($actorEvents.Count) conditional actor calls.")
Write-Host "Wrote $OutputPath"
