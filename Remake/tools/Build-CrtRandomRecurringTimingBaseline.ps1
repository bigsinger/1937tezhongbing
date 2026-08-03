[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$EvidenceRoot,
    [string]$OutputPath = '',
    [string]$LocalSearchOutputPath = '',
    [string]$ActorEventOutputPath = '',
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
if ([string]::IsNullOrWhiteSpace($LocalSearchOutputPath)) {
    $LocalSearchOutputPath = Join-Path $remakeRoot (
        'game\data\original_crt_random_local_search_timing.json')
}
$LocalSearchOutputPath = [IO.Path]::GetFullPath($LocalSearchOutputPath)
if ([string]::IsNullOrWhiteSpace($ActorEventOutputPath)) {
    $ActorEventOutputPath = Join-Path $remakeRoot (
        'game\data\original_crt_random_actor_event_timing.json')
}
$ActorEventOutputPath = [IO.Path]::GetFullPath($ActorEventOutputPath)
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
        ActorSiteCounts = @{}
        LocalSearchCalls = [Collections.Generic.List[object]]::new()
        ActorEvents = [Collections.Generic.List[object]]::new()
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
        ActorSiteCounts = $Round.ActorSiteCounts
        LocalSearchCalls = @($Round.LocalSearchCalls)
        ActorEvents = @($Round.ActorEvents)
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
$localSearchLevelResults = [Collections.Generic.List[object]]::new()
$actorEventLevelResults = [Collections.Generic.List[object]]::new()
$localSearchCallSites = @(
    '0x0005D08F',
    '0x0005D09D',
    '0x0005D0B4',
    '0x0005D0CB',
    '0x0005D15F')
$actorEventCallSites = @(
    '0x00055216',
    '0x0005528C',
    '0x000552A3',
    '0x000552BA',
    '0x000552D1',
    '0x00055BFB',
    '0x00055C0F',
    '0x00055C23',
    '0x00055C3A',
    '0x00056105',
    '0x0005614F',
    '0x00058946',
    '0x0005CB2B',
    '0x0005CEA6',
    '0x0005CF33',
    '0x0005CF4A',
    '0x0005CF61',
    '0x0005CF78',
    '0x0005D394',
    '0x0005D47E')
$actorEventSnapshotRequiredSites = @(
    '0x00055216',
    '0x00055BFB',
    '0x00055C0F',
    '0x00055C23',
    '0x00055C3A',
    '0x00056105',
    '0x00058946',
    '0x0005D394',
    '0x0005D47E')
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
    $globalActorSiteCounts = @{}
    $localSearchEvents = [Collections.Generic.List[object]]::new()
    $actorEvents = [Collections.Generic.List[object]]::new()
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
                    foreach ($actorSite in $completed.ActorSiteCounts.Keys) {
                        if ($globalActorSiteCounts.ContainsKey($actorSite)) {
                            $globalActorSiteCounts[$actorSite] = (
                                [int]$globalActorSiteCounts[$actorSite] +
                                [int]$completed.ActorSiteCounts[$actorSite])
                        }
                        else {
                            $globalActorSiteCounts[$actorSite] = [int](
                                $completed.ActorSiteCounts[$actorSite])
                        }
                    }
                    foreach ($actorEvent in @($completed.ActorEvents)) {
                        $actorEvents.Add($actorEvent)
                    }
                    $localCalls = @($completed.LocalSearchCalls)
                    if ($localCalls.Count % $localSearchCallSites.Count -ne 0) {
                        throw (
                            "Incomplete local-search group in ${levelId} " +
                            "round $($completed.Summary.index).")
                    }
                    for (
                        $localIndex = 0;
                        $localIndex -lt $localCalls.Count;
                        $localIndex += $localSearchCallSites.Count
                    ) {
                        $firstLocal = $localCalls[$localIndex]
                        $values = [Collections.Generic.List[int]]::new()
                        for (
                            $siteIndex = 0;
                            $siteIndex -lt $localSearchCallSites.Count;
                            $siteIndex++
                        ) {
                            $localCall = $localCalls[$localIndex + $siteIndex]
                            if (
                                [int]$localCall.runtime_index -ne
                                    [int]$firstLocal.runtime_index -or
                                [string]$localCall.call_site_rva -ne
                                    $localSearchCallSites[$siteIndex]
                            ) {
                                throw (
                                    "Local-search order diverged in ${levelId} " +
                                    "round $($completed.Summary.index).")
                            }
                            $values.Add([int]$localCall.value)
                        }
                        $snapshot = $firstLocal.actor_snapshot
                        $localSearchEvents.Add([pscustomobject][ordered]@{
                            round_index = [int]$completed.Summary.index
                            runtime_index = [int]$firstLocal.runtime_index
                            world_x = [int]$snapshot.world_x
                            world_y = [int]$snapshot.world_y
                            shared_counter_before = [int](
                                $snapshot.stationary_tick_counter)
                            shared_limit_before = [int](
                                $snapshot.stationary_tick_limit)
                            movement_path_state = [int](
                                $snapshot.movement_path_state)
                            route_update_active = [int](
                                $snapshot.route_update_active)
                            search_delay_counter = [int](
                                $snapshot.search_delay_counter)
                            search_delay_limit = [int](
                                $snapshot.search_delay_limit)
                            values = @($values)
                        })
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
                $actorSiteKey = "${runtimeIndex}|${site}"
                if ($pendingRound.ActorSiteCounts.ContainsKey($actorSiteKey)) {
                    $pendingRound.ActorSiteCounts[$actorSiteKey] = (
                        [int]$pendingRound.ActorSiteCounts[$actorSiteKey] + 1)
                }
                else {
                    $pendingRound.ActorSiteCounts[$actorSiteKey] = 1
                }
                if ($site -in $localSearchCallSites) {
                    if ($null -eq $record.PSObject.Properties['actor_snapshot']) {
                        throw (
                            "Local-search actor snapshot is missing in " +
                            "${levelId} sequence $sequence.")
                    }
                    $pendingRound.LocalSearchCalls.Add(
                        [pscustomobject][ordered]@{
                            runtime_index = $runtimeIndex
                            call_site_rva = $site
                            value = $expectedValue
                            actor_snapshot = $record.actor_snapshot
                        })
                }
                if ($site -in $actorEventCallSites) {
                    $snapshotProperty = (
                        $record.PSObject.Properties['actor_snapshot'])
                    if (
                        $null -eq $snapshotProperty -and
                        $site -in $actorEventSnapshotRequiredSites
                    ) {
                        throw (
                            "Actor-event snapshot is missing in " +
                            "${levelId} sequence $sequence.")
                    }
                    $worldX = -1
                    $worldY = -1
                    $previousWorldX = -1
                    $previousWorldY = -1
                    $sharedCounter = -1
                    $sharedLimit = -1
                    $routeUpdateActive = -1
                    $movementPathState = -1
                    $movementActive = -1
                    $goalKind = -1
                    $goalX = -1
                    $goalY = -1
                    $commandVariant = -1
                    $pursuitRuntimeIndex = -1
                    $pursuitDelayCounter = -1
                    $targetRuntimeIndex = -1
                    if ($null -ne $snapshotProperty) {
                        $snapshot = $snapshotProperty.Value
                        $worldX = [int]$snapshot.world_x
                        $worldY = [int]$snapshot.world_y
                        $previousWorldX = [int]$snapshot.previous_world_x
                        $previousWorldY = [int]$snapshot.previous_world_y
                        $sharedCounter = [int](
                            $snapshot.stationary_tick_counter)
                        $sharedLimit = [int]$snapshot.stationary_tick_limit
                        $routeUpdateActive = [int]$snapshot.route_update_active
                        $movementPathState = [int]$snapshot.movement_path_state
                        $movementActive = [int]$snapshot.movement_active
                        $goalKind = [int]$snapshot.goal_kind
                        $goalX = [int]$snapshot.goal_x
                        $goalY = [int]$snapshot.goal_y
                        $commandVariant = [int]$snapshot.command_variant
                        $pursuitDelayCounter = [int](
                            $snapshot.pursuit_delay_counter)
                        $pursuitAddressProperty = (
                            $snapshot.PSObject.Properties['pursuit_address'])
                        if ($null -ne $pursuitAddressProperty) {
                            $pursuitAddress = (
                                [string]$pursuitAddressProperty.Value
                            ).Trim().ToUpperInvariant()
                            if ($actorIndexByAddress.ContainsKey(
                                    $pursuitAddress)) {
                                $pursuitRuntimeIndex = [int](
                                    $actorIndexByAddress[$pursuitAddress])
                            }
                        }
                        $targetAddressProperty = (
                            $snapshot.PSObject.Properties['target_address'])
                        if ($null -ne $targetAddressProperty) {
                            $targetAddress = (
                                [string]$targetAddressProperty.Value
                            ).Trim().ToUpperInvariant()
                            if ($actorIndexByAddress.ContainsKey(
                                    $targetAddress)) {
                                $targetRuntimeIndex = [int](
                                    $actorIndexByAddress[$targetAddress])
                            }
                        }
                    }
                    [object]$actorEvent = @(
                        [int]$pendingRound.Index,
                        [int]$runtimeIndex,
                        [uint32]$siteValue,
                        [int]$expectedValue,
                        [int]$worldX,
                        [int]$worldY,
                        [int]$previousWorldX,
                        [int]$previousWorldY,
                        [int]$sharedCounter,
                        [int]$sharedLimit,
                        [int]$routeUpdateActive,
                        [int]$movementPathState,
                        [int]$movementActive,
                        [int]$goalKind,
                        [int]$goalX,
                        [int]$goalY,
                        [int]$commandVariant,
                        [int]$pursuitRuntimeIndex,
                        [int]$pursuitDelayCounter,
                        [int]$targetRuntimeIndex)
                    $pendingRound.ActorEvents.Add($actorEvent)
                }
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
    $actorCountText = [string]::Join(
        "`n",
        @($actorCounts | ForEach-Object {
            '{0}|{1}|{2}' -f `
                [int]$_.runtime_index,
                [string]$_.call_site_rva,
                [int]$_.count
        })) + "`n"
    $actorCountHash = Get-Sha256Bytes (
        [Text.UTF8Encoding]::new($false).GetBytes($actorCountText))
    $localSearchEventText = [string]::Join(
        "`n",
        @($localSearchEvents | ForEach-Object {
            '{0}|{1}|{2}|{3}|{4}|{5}|{6}|{7}|{8}|{9}|{10}' -f `
                [int]$_.round_index,
                [int]$_.runtime_index,
                [int]$_.world_x,
                [int]$_.world_y,
                [int]$_.shared_counter_before,
                [int]$_.shared_limit_before,
                [int]$_.movement_path_state,
                [int]$_.route_update_active,
                [int]$_.search_delay_counter,
                [int]$_.search_delay_limit,
                (@($_.values) -join ',')
        }))
    if ($localSearchEvents.Count -gt 0) {
        $localSearchEventText += "`n"
    }
    $localSearchEventHash = Get-Sha256Bytes (
        [Text.UTF8Encoding]::new($false).GetBytes($localSearchEventText))
    $localSearchLevelResults.Add([ordered]@{
        id = $levelId
        complete_round_count = $rounds.Count
        event_count = $localSearchEvents.Count
        events_sha256 = $localSearchEventHash
        events = @($localSearchEvents)
    })
    $actorEventText = [string]::Join(
        "`n",
        @($actorEvents | ForEach-Object { @($_) -join '|' }))
    if ($actorEvents.Count -gt 0) {
        $actorEventText += "`n"
    }
    $actorEventHash = Get-Sha256Bytes (
        [Text.UTF8Encoding]::new($false).GetBytes($actorEventText))
    $actorEventLevelResults.Add([ordered]@{
        id = $levelId
        complete_round_count = $rounds.Count
        event_count = $actorEvents.Count
        events_sha256 = $actorEventHash
        events = @($actorEvents)
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
        actor_call_site_counts_sha256 = $actorCountHash
        actor_call_site_counts = $actorCounts
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

$localSearchResult = [ordered]@{
    schema_version = 1
    catalog_id = 'original-crt-random-local-search-timing-v1'
    content_profile = [string]$startup.content_profile
    executable_sha256 = [string]$startup.executable_sha256
    call_site_rvas = $localSearchCallSites
    evidence = [ordered]@{
        source = 'complete rounds in original CRT recurring timing evidence'
        final_incomplete_rounds_omitted = $true
        input_scope = 'target-window-only'
    }
    levels = @($localSearchLevelResults)
}
$localSearchParent = Split-Path -Parent $LocalSearchOutputPath
[IO.Directory]::CreateDirectory($localSearchParent) | Out-Null
$localSearchJson = $localSearchResult | ConvertTo-Json -Depth 10 -Compress
[IO.File]::WriteAllText(
    $LocalSearchOutputPath,
    $localSearchJson + [Environment]::NewLine,
    [Text.UTF8Encoding]::new($false))
Write-Host (
    "Local-search timing catalog wrote twelve levels: " +
    $LocalSearchOutputPath)

$actorEventResult = [ordered]@{
    schema_version = 2
    catalog_id = 'original-crt-random-actor-event-timing-v2'
    content_profile = [string]$startup.content_profile
    executable_sha256 = [string]$startup.executable_sha256
    event_fields = @(
        'round_index',
        'runtime_index',
        'call_site_rva',
        'value',
        'world_x',
        'world_y',
        'previous_world_x',
        'previous_world_y',
        'shared_counter_before',
        'shared_limit_before',
        'route_update_active',
        'movement_path_state',
        'movement_active',
        'goal_kind',
        'goal_x',
        'goal_y',
        'command_variant',
        'pursuit_runtime_index',
        'pursuit_delay_counter',
        'target_runtime_index')
    call_site_rvas = $actorEventCallSites
    evidence = [ordered]@{
        source = 'complete rounds in original CRT recurring timing evidence'
        final_incomplete_rounds_omitted = $true
        input_scope = 'target-window-only'
        event_scope = (
            'all proven conditional actor calls except observation gates ' +
            'and the separately grouped five-draw local-search routine')
    }
    levels = @($actorEventLevelResults)
}
$actorEventParent = Split-Path -Parent $ActorEventOutputPath
[IO.Directory]::CreateDirectory($actorEventParent) | Out-Null
$actorEventJson = $actorEventResult | ConvertTo-Json -Depth 10 -Compress
[IO.File]::WriteAllText(
    $ActorEventOutputPath,
    $actorEventJson + [Environment]::NewLine,
    [Text.UTF8Encoding]::new($false))
Write-Host (
    "Actor-event timing catalog wrote twelve levels: " +
    $ActorEventOutputPath)
