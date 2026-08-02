[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$EvidenceRoot,
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
$EvidenceRoot = [IO.Path]::GetFullPath($EvidenceRoot)
$remakeRoot = Join-Path $RepositoryRoot 'Remake'
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $remakeRoot (
        'game\data\original_crt_random_recurring_timing.json')
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

function New-IncrementalSha256 {
    return [Security.Cryptography.IncrementalHash]::CreateHash(
        [Security.Cryptography.HashAlgorithmName]::SHA256)
}

function New-PendingRound {
    param(
        [int]$Index,
        [object]$Record
    )
    $orderStream = [IO.MemoryStream]::new()
    $valueStream = [IO.MemoryStream]::new()
    $actorOrderStream = [IO.MemoryStream]::new()
    $actorValueStream = [IO.MemoryStream]::new()
    return [ordered]@{
        Index = $Index
        TickMs = [long]$Record.tick_ms
        FirstSequence = [int]$Record.sequence
        LastSequence = [int]$Record.sequence
        FinalState = [uint64]0
        DrawCount = 0
        ActorDrawCount = 0
        GateActors = [Collections.Generic.List[int]]::new()
        SiteCounts = @{}
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
        [int[]]$ExpectedGateActors,
        [long]$FirstAcceptedTick
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
            tick_ms_offset = [long]$Round.TickMs - $FirstAcceptedTick
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
    throw 'Unsupported startup catalog for recurring timing evidence.'
}
if (@($startup.levels).Count -ne 12) {
    throw 'Recurring timing evidence requires exactly twelve formal levels.'
}

$cataloguedSites = @{}
foreach ($caller in $callSiteCatalog.callers) {
    foreach ($operation in $caller.operations) {
        foreach ($rawSite in $operation.sites) {
            $cataloguedSites[(Canonical-Rva ([string]$rawSite))] = $true
        }
    }
}

$levelResults = [Collections.Generic.List[object]]::new()
for ($levelIndex = 0; $levelIndex -lt 12; $levelIndex++) {
    $levelId = 'm{0:D3}' -f $levelIndex
    $levelFolder = Join-Path $EvidenceRoot (
        'level-{0:D2}' -f ($levelIndex + 1))
    $telemetryPath = Join-Path $levelFolder (
        'crt-random-runtime-telemetry.jsonl')
    $actorStatePath = Join-Path $levelFolder 'actor-states-entry.csv'
    foreach ($requiredPath in @($telemetryPath, $actorStatePath)) {
        if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
            throw "Recurring timing evidence is missing: $requiredPath"
        }
    }

    $levelProfiles = @($startup.levels | Where-Object {
        [string]$_.id -eq $levelId
    })
    if ($levelProfiles.Count -ne 1) {
        throw "Startup profile is missing or duplicated: $levelId"
    }
    $levelProfile = $levelProfiles[0]
    $expectedGateActors = @(
        $levelProfile.observation_gate_actor_indices |
            ForEach-Object { [int]$_ })
    if ($expectedGateActors.Count -eq 0) {
        throw "Startup profile has no observation-gate actors: $levelId"
    }
    $firstGameplaySequence = [int](
        $levelProfile.first_gameplay_update_sequence)

    $actorIndexByAddress = @{}
    foreach ($row in Import-Csv -LiteralPath $actorStatePath) {
        $address = ([string]$row.address).Trim().ToUpperInvariant()
        if ($address -notmatch '^0X[0-9A-F]{8}$') {
            throw "Invalid actor address in ${levelId}: $address"
        }
        if ($actorIndexByAddress.ContainsKey($address)) {
            throw "Duplicate actor address in ${levelId}: $address"
        }
        $actorIndexByAddress[$address] = [int]$row.index
    }

    $rounds = [Collections.Generic.List[object]]::new()
    $pendingRound = $null
    $firstAcceptedTick = [long]-1
    $globalOrder = New-IncrementalSha256
    $globalValue = New-IncrementalSha256
    $globalActorOrder = New-IncrementalSha256
    $globalActorValue = New-IncrementalSha256
    $globalSiteCounts = @{}
    $globalDrawCount = 0
    $globalActorDrawCount = 0
    $state = [uint64]1
    $previousSequence = 0
    $sawGameplayBoundary = $false

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
                throw (
                    "CRT sequence is not contiguous in ${levelId}: " +
                    "$previousSequence -> $sequence")
            }
            $previousSequence = $sequence
            $site = Canonical-Rva ([string]$record.call_site_rva)
            if (-not $cataloguedSites.ContainsKey($site)) {
                throw "Uncatalogued CRT call site in ${levelId}: $site"
            }
            if ($null -eq $record.PSObject.Properties['tick_ms']) {
                throw "Timestamp is missing at ${levelId} sequence $sequence."
            }
            $state = (
                ($state * [uint64]214013 + [uint64]2531011) -band
                [uint64]4294967295)
            $expectedValue = [int](($state -shr 16) -band 0x7fff)
            if ($expectedValue -ne [int]$record.value) {
                throw (
                    "CRT LCG mismatch at ${levelId} sequence ${sequence}: " +
                    "$expectedValue != $($record.value)")
            }
            if ($sequence -lt $firstGameplaySequence) {
                continue
            }

            $runtimeAddress = (
                [string]$record.caller_esi).Trim().ToUpperInvariant()
            $runtimeIndex = -1
            if ($actorIndexByAddress.ContainsKey($runtimeAddress)) {
                $runtimeIndex = [int](
                    $actorIndexByAddress[$runtimeAddress])
            }
            $siteValue = [Convert]::ToUInt32($site.Substring(2), 16)
            $isRoundMarker = (
                $site -eq '0x0005C81C' -and
                $runtimeIndex -eq $expectedGateActors[0])
            if ($isRoundMarker) {
                if ($null -ne $pendingRound) {
                    $completed = Complete-PendingRound `
                        -Round $pendingRound `
                        -ExpectedGateActors $expectedGateActors `
                        -FirstAcceptedTick $firstAcceptedTick
                    $rounds.Add($completed.Summary)
                    $globalOrder.AppendData($completed.OrderBytes)
                    $globalValue.AppendData($completed.ValueBytes)
                    $globalActorOrder.AppendData($completed.ActorOrderBytes)
                    $globalActorValue.AppendData($completed.ActorValueBytes)
                    $globalDrawCount += [int]$completed.Summary.draw_count
                    $globalActorDrawCount += [int](
                        $completed.Summary.actor_draw_count)
                    foreach ($countSite in $completed.SiteCounts.Keys) {
                        if ($globalSiteCounts.ContainsKey($countSite)) {
                            $globalSiteCounts[$countSite] = (
                                [int]$globalSiteCounts[$countSite] +
                                [int]$completed.SiteCounts[$countSite])
                        }
                        else {
                            $globalSiteCounts[$countSite] = [int](
                                $completed.SiteCounts[$countSite])
                        }
                    }
                }
                if ($firstAcceptedTick -lt 0) {
                    if ($sequence -ne $firstGameplaySequence) {
                        throw (
                            "Gameplay boundary mismatch in ${levelId}: " +
                            "$sequence != $firstGameplaySequence")
                    }
                    $firstAcceptedTick = [long]$record.tick_ms
                    $sawGameplayBoundary = $true
                }
                $pendingRound = New-PendingRound `
                    -Index ($rounds.Count + 1) `
                    -Record $record
            }
            if ($null -eq $pendingRound) {
                throw (
                    "Runtime call precedes first actor round in ${levelId}: " +
                    "$sequence")
            }

            $pendingRound.OrderWriter.Write([uint32]$siteValue)
            $pendingRound.OrderWriter.Write([int]$runtimeIndex)
            $pendingRound.ValueWriter.Write([uint32]$siteValue)
            $pendingRound.ValueWriter.Write([int]$runtimeIndex)
            $pendingRound.ValueWriter.Write([uint32]$expectedValue)
            $pendingRound.DrawCount = [int]$pendingRound.DrawCount + 1
            $pendingRound.LastSequence = $sequence
            $pendingRound.FinalState = $state
            if ($pendingRound.SiteCounts.ContainsKey($site)) {
                $pendingRound.SiteCounts[$site] = (
                    [int]$pendingRound.SiteCounts[$site] + 1)
            }
            else {
                $pendingRound.SiteCounts[$site] = 1
            }
            if ($runtimeIndex -ge 0) {
                $pendingRound.ActorOrderWriter.Write([uint32]$siteValue)
                $pendingRound.ActorOrderWriter.Write([int]$runtimeIndex)
                $pendingRound.ActorValueWriter.Write([uint32]$siteValue)
                $pendingRound.ActorValueWriter.Write([int]$runtimeIndex)
                $pendingRound.ActorValueWriter.Write([uint32]$expectedValue)
                $pendingRound.ActorDrawCount = (
                    [int]$pendingRound.ActorDrawCount + 1)
            }
            if ($site -eq '0x0005C81C') {
                if ($runtimeIndex -lt 0) {
                    throw (
                        "Observation gate has no actor in ${levelId} " +
                        "at sequence $sequence.")
                }
                $pendingRound.GateActors.Add($runtimeIndex)
            }
        }
    }

    # The final marker has no following marker proving that its full frame was
    # captured. Deliberately discard that pending tail instead of guessing.
    if ($null -ne $pendingRound) {
        foreach ($writer in @(
                $pendingRound.OrderWriter,
                $pendingRound.ValueWriter,
                $pendingRound.ActorOrderWriter,
                $pendingRound.ActorValueWriter)) {
            $writer.Dispose()
        }
    }
    if (-not $sawGameplayBoundary -or $rounds.Count -lt $MinimumRounds) {
        throw (
            "Only $($rounds.Count) proven complete rounds in ${levelId}; " +
            "$MinimumRounds required.")
    }

    $globalOrderHash = ConvertTo-Hex $globalOrder.GetHashAndReset()
    $globalValueHash = ConvertTo-Hex $globalValue.GetHashAndReset()
    $globalActorOrderHash = ConvertTo-Hex (
        $globalActorOrder.GetHashAndReset())
    $globalActorValueHash = ConvertTo-Hex (
        $globalActorValue.GetHashAndReset())
    foreach ($hash in @(
            $globalOrder,
            $globalValue,
            $globalActorOrder,
            $globalActorValue)) {
        $hash.Dispose()
    }

    $intervals = [Collections.Generic.List[long]]::new()
    for ($roundIndex = 1; $roundIndex -lt $rounds.Count; $roundIndex++) {
        $intervals.Add(
            [long]$rounds[$roundIndex].tick_ms_offset -
            [long]$rounds[$roundIndex - 1].tick_ms_offset)
    }
    $steadyIntervals = @($intervals | Where-Object {
        $_ -ge 10 -and $_ -le 40 })
    $steadyAverage = 0.0
    if ($steadyIntervals.Count -gt 0) {
        $steadyAverage = [double](
            $steadyIntervals | Measure-Object -Average).Average
    }
    $lastRound = $rounds[$rounds.Count - 1]
    $counts = @(
        foreach ($site in @($globalSiteCounts.Keys | Sort-Object)) {
            [ordered]@{
                call_site_rva = $site
                count = [int]$globalSiteCounts[$site]
            }
        })
    $levelResults.Add([ordered]@{
        id = $levelId
        evidence = [ordered]@{
            source_trace_sha256 = (
                Get-FileHash -LiteralPath $telemetryPath `
                    -Algorithm SHA256).Hash
            actor_snapshot_sha256 = (
                Get-FileHash -LiteralPath $actorStatePath `
                    -Algorithm SHA256).Hash
        }
        first_gameplay_sequence = $firstGameplaySequence
        first_accepted_sequence = [int]$rounds[0].first_sequence
        last_accepted_sequence = [int]$lastRound.last_sequence
        complete_round_count = $rounds.Count
        accepted_draw_count = $globalDrawCount
        accepted_actor_draw_count = $globalActorDrawCount
        initial_state_hex = [string]$levelProfile.final_state_hex
        final_state_hex = [string]$lastRound.final_state_hex
        final_draw_index = [int]$lastRound.last_sequence
        tick_span_ms = [long]$lastRound.tick_ms_offset
        steady_interval_count = $steadyIntervals.Count
        steady_average_ms = [Math]::Round($steadyAverage, 6)
        steady_frequency_hz = $(
            if ($steadyAverage -gt 0.0) {
                [Math]::Round(1000.0 / $steadyAverage, 6)
            }
            else {
                0.0
            })
        observation_gate_actor_indices = $expectedGateActors
        ordered_call_site_actor_sha256 = $globalOrderHash
        ordered_call_site_actor_value_sha256 = $globalValueHash
        actor_order_sha256 = $globalActorOrderHash
        actor_value_sha256 = $globalActorValueHash
        call_site_counts = $counts
        rounds = @($rounds)
    })
    Write-Host (
        "Recovered ${levelId}: $($rounds.Count) complete rounds, " +
        "$globalDrawCount accepted draws.")
}

$result = [ordered]@{
    schema_version = 1
    baseline_id = 'original-crt-random-recurring-timing-v1'
    content_profile = [string]$startup.content_profile
    executable_sha256 = [string]$startup.executable_sha256
    evidence = [ordered]@{
        capture_mode = 'process-local-crt-rand-hook'
        input_scope = 'target-window-only'
        accepted_scope = (
            'complete actor-update rounds only; unproven final tail omitted')
    }
    hash_encoding = [ordered]@{
        byte_order = 'little-endian'
        order_record = 'uint32 call_site_rva + int32 runtime_index'
        value_record = (
            'uint32 call_site_rva + int32 runtime_index + uint32 rand_value')
        non_actor_runtime_index = -1
        algorithm = 'SHA-256'
    }
    levels = @($levelResults)
}

$parent = Split-Path -Parent $OutputPath
[IO.Directory]::CreateDirectory($parent) | Out-Null
$json = $result | ConvertTo-Json -Depth 10 -Compress
[IO.File]::WriteAllText(
    $OutputPath,
    $json + [Environment]::NewLine,
    [Text.UTF8Encoding]::new($false))
Write-Host "Recurring timing baseline wrote twelve levels: $OutputPath"
