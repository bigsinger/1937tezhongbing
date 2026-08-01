param(
    [Parameter(Mandatory = $true)]
    [string]$TelemetryPath,
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^m\d{3}$')]
    [string]$LevelId,
    [string]$OutputPath = '',
    [string]$RepositoryRoot = '',
    [string]$ConvertedAssetsRoot = '',
    [string]$ActorStatePath = ''
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    $RepositoryRoot = [IO.Path]::GetFullPath(
        (Join-Path $PSScriptRoot '..\..'))
}
else {
    $RepositoryRoot = [IO.Path]::GetFullPath($RepositoryRoot)
}
$TelemetryPath = [IO.Path]::GetFullPath($TelemetryPath)
if (-not (Test-Path -LiteralPath $TelemetryPath -PathType Leaf)) {
    throw "CRT random telemetry is missing: $TelemetryPath"
}
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path (
        Split-Path -Parent $TelemetryPath
    ) 'crt-random-startup-summary.json'
}
$OutputPath = [IO.Path]::GetFullPath($OutputPath)
if ([string]::IsNullOrWhiteSpace($ConvertedAssetsRoot)) {
    $ConvertedAssetsRoot = Join-Path $RepositoryRoot (
        'Remake\LocalAssets\converted')
}
$ConvertedAssetsRoot = [IO.Path]::GetFullPath(
    $ConvertedAssetsRoot)
if ([string]::IsNullOrWhiteSpace($ActorStatePath)) {
    $candidateActorStatePath = Join-Path (
        Split-Path -Parent $TelemetryPath
    ) 'actor-states-crt-startup.csv'
    if (Test-Path -LiteralPath $candidateActorStatePath -PathType Leaf) {
        $ActorStatePath = $candidateActorStatePath
    }
}
if (-not [string]::IsNullOrWhiteSpace($ActorStatePath)) {
    $ActorStatePath = [IO.Path]::GetFullPath($ActorStatePath)
    if (-not (Test-Path -LiteralPath $ActorStatePath -PathType Leaf)) {
        throw "Actor-state snapshot is missing: $ActorStatePath"
    }
}

$catalogPath = Join-Path $RepositoryRoot (
    'SDK\crt-rand-call-sites.json')
$catalogText = [IO.File]::ReadAllText(
    $catalogPath,
    [Text.UTF8Encoding]::new($false))
$catalog = $catalogText | ConvertFrom-Json
$catalogBySite = @{}
function ConvertTo-CanonicalRva {
    param([string]$Value)
    $trimmed = $Value.Trim()
    if ($trimmed.StartsWith(
            '0x',
            [StringComparison]::OrdinalIgnoreCase)) {
        return '0x' + $trimmed.Substring(2).ToUpperInvariant()
    }
    return $trimmed.ToUpperInvariant()
}
foreach ($caller in $catalog.callers) {
    foreach ($operation in $caller.operations) {
        foreach ($rawSite in $operation.sites) {
            $site = ConvertTo-CanonicalRva ([string]$rawSite)
            $catalogBySite[$site] = [ordered]@{
                call_site_rva = $site
                caller_rva = [string]$caller.caller_rva
                engine_symbol = [string]$caller.engine_symbol
                semantic_name = [string]$caller.semantic_name
                domain = [string]$caller.domain
                purpose = [string]$operation.purpose
            }
        }
    }
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
    throw 'Telemetry contains no crt_rand_batch records.'
}

$state = [uint64]1
$previousSequence = 0
$unknownSites = [Collections.Generic.HashSet[string]]::new(
    [StringComparer]::OrdinalIgnoreCase)
$siteCounts = @{}
$orderedSites = [Text.StringBuilder]::new()
$orderedValues = [Text.StringBuilder]::new()
foreach ($record in $records) {
    $sequence = [int]$record.sequence
    if (
        ($previousSequence -eq 0 -and $sequence -ne 1) -or
        ($previousSequence -gt 0 -and
            $sequence -ne $previousSequence + 1)
    ) {
        throw (
            "CRT trace sequence is not contiguous: " +
            "$previousSequence -> $sequence")
    }
    $previousSequence = $sequence
    $site = ConvertTo-CanonicalRva (
        [string]$record.call_site_rva)
    if (-not $catalogBySite.ContainsKey($site)) {
        [void]$unknownSites.Add($site)
    }
    if (-not $siteCounts.ContainsKey($site)) {
        $siteCounts[$site] = 0
    }
    $siteCounts[$site] = [int]$siteCounts[$site] + 1

    $state = (
        ($state * [uint64]214013 + [uint64]2531011) -band
        [uint64]4294967295
    )
    $expectedValue = [int](($state -shr 16) -band 0x7fff)
    if ($expectedValue -ne [int]$record.value) {
        throw (
            "CRT LCG mismatch at sequence ${sequence}: " +
            "expected $expectedValue, actual $($record.value)")
    }
    [void]$orderedSites.Append($site).Append("`n")
    [void]$orderedValues.Append(
        ('{0}:{1}' -f $site, [int]$record.value)
    ).Append("`n")
}
if ($unknownSites.Count -gt 0) {
    throw (
        'CRT trace contains uncatalogued call sites: ' +
        (@($unknownSites) -join ', '))
}

$firstActorRecord = @($records | Where-Object {
    ([string]$_.call_site_rva).Equals(
        '0x00050967',
        [StringComparison]::OrdinalIgnoreCase)
} | Select-Object -First 1)
if ($firstActorRecord.Count -ne 1) {
    throw 'CRT trace does not contain actor initialization.'
}
$firstGameplayRecord = @($records | Where-Object {
    ([string]$_.call_site_rva).Equals(
        '0x0005C81C',
        [StringComparison]::OrdinalIgnoreCase)
} | Select-Object -First 1)
if ($firstGameplayRecord.Count -ne 1) {
    throw 'CRT trace does not reach the first enemy update.'
}
$initializationEnd = [int]$firstGameplayRecord[0].sequence - 1
if ($initializationEnd -lt [int]$firstActorRecord[0].sequence) {
    throw 'CRT startup phase boundary is inverted.'
}
$initializationRecords = @($records | Where-Object {
    [int]$_.sequence -le $initializationEnd
})
$runtimeRecords = @($records | Where-Object {
    [int]$_.sequence -gt $initializationEnd
})

$actorIndexByAddress = @{}
if (-not [string]::IsNullOrWhiteSpace($ActorStatePath)) {
    foreach ($actorRow in Import-Csv -LiteralPath $ActorStatePath) {
        $address = ([string]$actorRow.address).Trim().ToUpperInvariant()
        if ($address -notmatch '^0X[0-9A-F]{8}$') {
            throw "Invalid actor address in snapshot: $address"
        }
        if ($actorIndexByAddress.ContainsKey($address)) {
            throw "Duplicate actor address in snapshot: $address"
        }
        $actorIndexByAddress[$address] = [int]$actorRow.index
    }
}

function Get-ActorRuntimeIndex {
    param([object]$Record)
    if (
        $actorIndexByAddress.Count -eq 0 -or
        $null -eq $Record.PSObject.Properties['caller_esi']
    ) {
        return -1
    }
    $address = ([string]$Record.caller_esi).Trim().ToUpperInvariant()
    if ($actorIndexByAddress.ContainsKey($address)) {
        return [int]$actorIndexByAddress[$address]
    }
    return -1
}

$gateRecords = @($runtimeRecords | Where-Object {
    ([string]$_.call_site_rva).Equals(
        '0x0005C81C',
        [StringComparison]::OrdinalIgnoreCase)
})
$gateActorIndices = @(
    foreach ($record in $gateRecords) {
        Get-ActorRuntimeIndex $record
    }
)
if (
    $actorIndexByAddress.Count -gt 0 -and
    @($gateActorIndices | Where-Object { $_ -lt 0 }).Count -gt 0
) {
    throw 'Observation-gate trace contains an unmapped ESI actor address.'
}
$firstGateRound = [Collections.Generic.List[int]]::new()
if ($gateActorIndices.Count -gt 0 -and $gateActorIndices[0] -ge 0) {
    $previousActorIndex = -1
    foreach ($actorIndex in $gateActorIndices) {
        if (
            $firstGateRound.Count -gt 0 -and
            $actorIndex -le $previousActorIndex
        ) {
            break
        }
        $firstGateRound.Add([int]$actorIndex)
        $previousActorIndex = [int]$actorIndex
    }
    if (
        $firstGateRound.Count -eq 0 -or
        $firstGateRound.Count -ne (
            @($firstGateRound | Select-Object -Unique).Count)
    ) {
        throw 'The first observation-gate actor round is invalid.'
    }
}

# The startup-only probe exits after the first complete RuntimeActor update
# has been published. Preserve that entire tail, not just the observation
# actors: route waits, pursuit gates, secondary searches, blocked-path retries
# and the one level-music draw all share the same process-global stream.
$firstGameplayUpdate = @(
    foreach ($record in $runtimeRecords) {
        $site = ConvertTo-CanonicalRva (
            [string]$record.call_site_rva)
        $runtimeIndex = Get-ActorRuntimeIndex $record
        if (
            $actorIndexByAddress.Count -gt 0 -and
            $runtimeIndex -lt 0 -and
            $site -ne '0x00006A73'
        ) {
            throw (
                "First gameplay update contains an unmapped actor at " +
                "$site.")
        }
        [ordered]@{
            runtime_index = $runtimeIndex
            call_site_rva = $site
            value = [int]$record.value
        }
    }
)
if (
    $firstGameplayUpdate.Count -eq 0 -or
    @($firstGameplayUpdate | Where-Object {
        [string]$_.call_site_rva -eq '0x0005C81C'
    }).Count -ne $firstGateRound.Count -or
    @($firstGameplayUpdate | Where-Object {
        [string]$_.call_site_rva -eq '0x00006A73' -and
        [int]$_.runtime_index -eq -1
    }).Count -ne 1
) {
    throw 'The captured first gameplay update is incomplete.'
}

$actorInitialization = @(
    if ($actorIndexByAddress.Count -gt 0) {
        $stateByActor = @{}
        foreach ($record in $initializationRecords) {
            $actorIndex = Get-ActorRuntimeIndex $record
            if ($actorIndex -lt 0) {
                continue
            }
            if (-not $stateByActor.ContainsKey($actorIndex)) {
                $stateByActor[$actorIndex] = [ordered]@{
                    runtime_index = $actorIndex
                    initial_idle_limit = -1
                    initial_facing_direction = -1
                    initial_ai_phase = -1
                    initial_reaction_limit = -1
                }
            }
            $actorState = $stateByActor[$actorIndex]
            $site = ConvertTo-CanonicalRva (
                [string]$record.call_site_rva)
            $value = [int]$record.value
            switch ($site) {
                '0x00050967' {
                    $actorState.initial_idle_limit = $value % 160
                }
                '0x00050B64' {
                    $actorState.initial_idle_limit = $value % 160
                }
                '0x00050980' {
                    $actorState.initial_facing_direction = [Math]::Min(
                        ($value % 9) + 1,
                        8)
                }
                '0x00050B7D' {
                    $actorState.initial_facing_direction = [Math]::Min(
                        ($value % 9) + 1,
                        8)
                }
                '0x0005BBBC' {
                    $actorState.initial_facing_direction = [Math]::Max(
                        $value % 9,
                        1)
                }
                '0x0005BFAC' {
                    $actorState.initial_facing_direction = [Math]::Max(
                        $value % 9,
                        1)
                }
                '0x0005340B' {
                    $actorState.initial_ai_phase = $value % 60
                }
                '0x00053655' {
                    $actorState.initial_ai_phase = $value % 60
                }
                '0x0005358B' {
                    $actorState.initial_reaction_limit = (
                        $value % 40) + 40
                }
                '0x000537A3' {
                    $actorState.initial_reaction_limit = (
                        $value % 40) + 40
                }
            }
        }
        foreach ($actorIndex in @($stateByActor.Keys | Sort-Object)) {
            [pscustomobject]$stateByActor[$actorIndex]
        }
    }
)

function Get-Sha256Text {
    param([string]$Value)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.UTF8Encoding]::new($false).GetBytes($Value)
        return (
            [BitConverter]::ToString(
                $sha.ComputeHash($bytes)
            ).Replace('-', '')
        )
    }
    finally {
        $sha.Dispose()
    }
}

function Get-RecordHash {
    param(
        [object[]]$Values,
        [switch]$IncludeValue
    )
    $builder = [Text.StringBuilder]::new()
    foreach ($record in $Values) {
        $site = ConvertTo-CanonicalRva (
            [string]$record.call_site_rva)
        if ($IncludeValue) {
            [void]$builder.Append(
                ('{0}:{1}' -f $site, [int]$record.value)
            ).Append("`n")
        }
        else {
            [void]$builder.Append($site).Append("`n")
        }
    }
    return Get-Sha256Text $builder.ToString()
}

function Get-LcgStateAfterDraws {
    param([int]$DrawCount)
    $result = [uint64]1
    for ($drawIndex = 0; $drawIndex -lt $DrawCount; $drawIndex++) {
        $result = (
            ($result * [uint64]214013 + [uint64]2531011) -band
            [uint64]4294967295
        )
    }
    return $result
}

$levelPath = Join-Path $ConvertedAssetsRoot (
    "levels\$LevelId\level.json")
$importedEntityCount = -1
if (Test-Path -LiteralPath $levelPath -PathType Leaf) {
    $levelText = [IO.File]::ReadAllText(
        $levelPath,
        [Text.UTF8Encoding]::new($false))
    $level = $levelText | ConvertFrom-Json
    $importedEntityCount = @($level.entities).Count
}
$actorConstructorCount = @($initializationRecords | Where-Object {
    ([string]$_.call_site_rva).Equals(
        '0x00050967',
        [StringComparison]::OrdinalIgnoreCase)
}).Count

$countRows = @(
    foreach ($site in @($siteCounts.Keys | Sort-Object)) {
        $metadata = $catalogBySite[$site]
        [ordered]@{
            call_site_rva = $site
            count = [int]$siteCounts[$site]
            semantic_name = [string]$metadata.semantic_name
            purpose = [string]$metadata.purpose
        }
    }
)
$summary = [ordered]@{
    schema_version = 1
    source_profile = 'repository-mod-12-level-20260729'
    executable_sha256 = [string]$catalog.supported_executable_sha256
    level_id = $LevelId
    trace = [ordered]@{
        record_count = $records.Count
        first_sequence = [int]$records[0].sequence
        last_sequence = [int]$records[$records.Count - 1].sequence
        contiguous = $true
        lcg_verified = $true
        catalogued_call_sites = $siteCounts.Count
        uncatalogued_call_sites = 0
        ordered_call_site_sha256 = Get-Sha256Text (
            $orderedSites.ToString())
        ordered_value_sha256 = Get-Sha256Text (
            $orderedValues.ToString())
        final_state_hex = ('0x{0:X8}' -f $state)
    }
    startup = [ordered]@{
        first_actor_sequence = [int]$firstActorRecord[0].sequence
        first_gameplay_update_sequence = (
            [int]$firstGameplayRecord[0].sequence)
        initialization_draw_count = $initializationRecords.Count
        runtime_tail_draw_count = $runtimeRecords.Count
        ambient_prefix_draw_count = (
            [int]$firstActorRecord[0].sequence - 1)
        actor_constructor_count = $actorConstructorCount
        imported_entity_count = $importedEntityCount
        constructor_minus_entity_count = (
            $actorConstructorCount - $importedEntityCount)
        ordered_call_site_sha256 = Get-RecordHash `
            -Values $initializationRecords
        ordered_value_sha256 = Get-RecordHash `
            -Values $initializationRecords `
            -IncludeValue
        final_state_hex = (
            '0x{0:X8}' -f (
                Get-LcgStateAfterDraws $initializationRecords.Count
            )
        )
        observation_gate_actor_indices = @($firstGateRound)
        actor_initialization = $actorInitialization
    }
    first_gameplay_update = [ordered]@{
        draw_count = $runtimeRecords.Count
        ordered_call_site_sha256 = Get-RecordHash `
            -Values $runtimeRecords
        ordered_value_sha256 = Get-RecordHash `
            -Values $runtimeRecords `
            -IncludeValue
        records = $firstGameplayUpdate
    }
    call_site_counts = $countRows
}

$outputDirectory = Split-Path -Parent $OutputPath
[IO.Directory]::CreateDirectory($outputDirectory) | Out-Null
$json = $summary | ConvertTo-Json -Depth 8
[IO.File]::WriteAllText(
    $OutputPath,
    $json + [Environment]::NewLine,
    [Text.UTF8Encoding]::new($false))

Write-Host ((
    "CRT random trace passed: {0} records, {1} startup draws, " +
    "{2} actor constructors, {3} catalogued sites.") -f
    $records.Count,
    $initializationRecords.Count,
    $actorConstructorCount,
    $siteCounts.Count)
Get-Item -LiteralPath $OutputPath
