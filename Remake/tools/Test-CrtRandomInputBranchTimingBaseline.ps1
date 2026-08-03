[CmdletBinding()]
param(
    [string]$BaselinePath = '',
    [string]$QuietBaselinePath = '',
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
if ([string]::IsNullOrWhiteSpace($BaselinePath)) {
    $BaselinePath = Join-Path $RepositoryRoot (
        'Remake\game\data\original_crt_random_input_branch_timing.json')
}
if ([string]::IsNullOrWhiteSpace($QuietBaselinePath)) {
    $QuietBaselinePath = Join-Path $RepositoryRoot (
        'Remake\game\data\original_crt_random_recurring_timing.json')
}

function Read-Utf8Json {
    param([string]$Path)
    return (
        [IO.File]::ReadAllText(
            $Path,
            [Text.UTF8Encoding]::new($false)) |
            ConvertFrom-Json)
}

function ConvertTo-Hex {
    param([byte[]]$Bytes)
    return ([BitConverter]::ToString($Bytes)).Replace('-', '')
}

function Get-Sha256Text {
    param([string]$Text)
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try {
        return ConvertTo-Hex $algorithm.ComputeHash(
            [Text.UTF8Encoding]::new($false).GetBytes($Text))
    }
    finally {
        $algorithm.Dispose()
    }
}

$baseline = Read-Utf8Json -Path $BaselinePath
$quiet = Read-Utf8Json -Path $QuietBaselinePath
if (
    [int]$baseline.schema_version -ne 1 -or
    [string]$baseline.baseline_id -ne
        'original-crt-random-input-branch-timing-v1' -or
    [string]$baseline.content_profile -ne
        'repository-mod-12-level-20260729' -or
    [string]$baseline.executable_sha256 -ne
        'F4DD1131DF6C993C01EA011F9439BC725E6DC6491B5FBBA47724D7D5B64DA3F3'
) {
    throw 'Unexpected original CRT input-branch baseline identity.'
}
if (
    [string]$baseline.evidence.capture_mode -ne
        'process-local-crt-rand-hook' -or
    [string]$baseline.evidence.input_isolation -ne
        'window-message-to-process-local-DirectInput' -or
    [string]$baseline.evidence.source_trace_sha256 -ne
        '8E4BDEAC3345CBBCA970D8538DB424375078D30404468AE2331D00BC97D65587' -or
    [string]$baseline.evidence.actor_snapshot_sha256 -ne
        'E582A7BD312B40804AD924CDC5D027947CA107635EE224052E31D7FB91501598' -or
    [string]$baseline.evidence.scenario_sha256 -ne
        '885C8E915B937275742B790626255F26D8B9E76C8CE69A6EF93A5C2FE067DA9E'
) {
    throw 'Input-branch source provenance changed unexpectedly.'
}

$branches = @($baseline.branches)
if ($branches.Count -ne 1) {
    throw 'Exactly one bounded input branch is expected.'
}
$branch = $branches[0]
if (
    [string]$branch.id -ne 'm000-basic-movement-v1' -or
    [string]$branch.level_id -ne 'm000' -or
    [int]$branch.first_gameplay_sequence -ne 8490 -or
    [int]$branch.first_accepted_sequence -ne 8490 -or
    [int]$branch.last_accepted_sequence -ne 33075 -or
    [int]$branch.complete_round_count -ne 413 -or
    [int]$branch.quiet_prefix_round_count -ne 297 -or
    [int]$branch.accepted_draw_count -ne 24586 -or
    [int]$branch.accepted_actor_draw_count -ne 24585 -or
    [string]$branch.initial_state_hex -ne '0xCEBEAFA8' -or
    [string]$branch.final_state_hex -ne '0xE9B3096A' -or
    [int]$branch.final_draw_index -ne 33075 -or
    [string]$branch.ordered_call_site_actor_sha256 -ne
        'BE66206BAFBE78E45F323A1013872D818620D712CE7D94BAEBE2E5DDF0FAC3D4' -or
    [string]$branch.ordered_call_site_actor_value_sha256 -ne
        '5816D4B7AA17DAEAF7B028EA4733176D9FE5969553F7B181EA6EC82C94EDF80F' -or
    [string]$branch.actor_order_sha256 -ne
        'F8611B26D584BB6BE907575DC3666A910C003D77BCEC0377069C28DD86D91C93' -or
    [string]$branch.actor_value_sha256 -ne
        '68F64743CCFDD7A79549F70DE14AB279A3703500C1106F8C2753FB219DE0A0F2'
) {
    throw 'Input-branch scalar or stream-hash contract changed.'
}

$rounds = @($branch.rounds)
if ($rounds.Count -ne [int]$branch.complete_round_count) {
    throw 'Input-branch round count is inconsistent.'
}
for ($roundIndex = 0; $roundIndex -lt $rounds.Count; $roundIndex++) {
    $round = $rounds[$roundIndex]
    if ([int]$round.index -ne $roundIndex + 1) {
        throw "Non-contiguous input round index at $roundIndex."
    }
    if (
        $roundIndex -gt 0 -and
        [int]$round.first_sequence -ne
            [int]$rounds[$roundIndex - 1].last_sequence + 1
    ) {
        throw "Non-contiguous input round sequence at $($round.index)."
    }
    if (
        [int]$round.draw_count -ne
            [int]$round.last_sequence - [int]$round.first_sequence + 1
    ) {
        throw "Round draw count mismatch at $($round.index)."
    }
}

$quietLevel = @($quiet.levels | Where-Object {
    [string]$_.id -eq 'm000'
})[0]
$quietPrefix = [int]$branch.quiet_prefix_round_count
for ($roundIndex = 0; $roundIndex -lt $quietPrefix; $roundIndex++) {
    if (
        [string]$rounds[$roundIndex].ordered_call_site_actor_sha256 -ne
            [string]$quietLevel.rounds[$roundIndex].ordered_call_site_actor_sha256 -or
        [string]$rounds[$roundIndex].ordered_call_site_actor_value_sha256 -ne
            [string]$quietLevel.rounds[$roundIndex].ordered_call_site_actor_value_sha256
    ) {
        throw "Quiet prefix diverges before round 298 at $($roundIndex + 1)."
    }
}
if (
    [string]$rounds[$quietPrefix].ordered_call_site_actor_sha256 -eq
        [string]$quietLevel.rounds[$quietPrefix].ordered_call_site_actor_sha256 -or
    [string]$rounds[$quietPrefix].ordered_call_site_actor_value_sha256 -eq
        [string]$quietLevel.rounds[$quietPrefix].ordered_call_site_actor_value_sha256
) {
    throw 'The first movement acknowledgement no longer begins at round 298.'
}

$inputEvents = @($branch.input_events)
$expectedInputEvents = @(
    @(298, 26033, 18, '0x0005D7CF', 6223,
        'move_outbound_commanded', 48, 56),
    @(358, 29729, 18, '0x0005D7CF', 8747,
        'move_return_commanded', 176, 56))
if ($inputEvents.Count -ne $expectedInputEvents.Count) {
    throw 'Exactly two movement acknowledgement events are required.'
}
for ($eventIndex = 0; $eventIndex -lt $inputEvents.Count; $eventIndex++) {
    $event = $inputEvents[$eventIndex]
    $expected = $expectedInputEvents[$eventIndex]
    $actual = @(
        [int]$event.round_index,
        [int]$event.sequence,
        [int]$event.runtime_index,
        [string]$event.call_site_rva,
        [int]$event.value,
        [string]$event.checkpoint_id,
        [int]$event.destination_x,
        [int]$event.destination_y)
    if (($actual -join '|') -ne ($expected -join '|')) {
        throw "Input event $eventIndex changed: $($actual -join '|')"
    }
    $eventRound = $rounds[[int]$event.round_index - 1]
    if (
        [int]$event.sequence -lt [int]$eventRound.first_sequence -or
        [int]$event.sequence -gt [int]$eventRound.last_sequence
    ) {
        throw "Input event $eventIndex lies outside its actor round."
    }
}

$siteCounts = @{}
$siteTotal = 0
foreach ($row in $branch.call_site_counts) {
    $site = [string]$row.call_site_rva
    if ($siteCounts.ContainsKey($site)) {
        throw "Duplicate input-branch call-site count: $site"
    }
    $siteCounts[$site] = [int]$row.count
    $siteTotal += [int]$row.count
}
if (
    $siteTotal -ne [int]$branch.accepted_draw_count -or
    [int]$siteCounts['0x0005C81C'] -ne
        @($branch.observation_gate_actor_indices).Count *
            [int]$branch.complete_round_count -or
    [int]$siteCounts['0x0005D7CF'] -ne 2
) {
    throw 'Input-branch call-site totals are inconsistent.'
}
$actorTotal = 0
foreach ($row in $branch.actor_call_site_counts) {
    $actorTotal += [int]$row.count
}
if ($actorTotal -ne [int]$branch.accepted_actor_draw_count) {
    throw 'Input-branch actor-call totals are inconsistent.'
}

$actorEvents = @($branch.actor_events)
if (
    $actorEvents.Count -ne [int]$branch.actor_event_count -or
    $actorEvents.Count -ne 2281
) {
    throw 'Input-branch conditional actor-event count changed.'
}
$actorEventText = [string]::Join(
    "`n",
    @($actorEvents | ForEach-Object { @($_) -join '|' })) + "`n"
$actorEventHash = Get-Sha256Text $actorEventText
if (
    $actorEventHash -ne [string]$branch.actor_events_sha256 -or
    $actorEventHash -ne
        '1D8ABEE609B312A943725236D27D4BC587334CFA505E53FE3ED0D6BAE42664A0'
) {
    throw 'Input-branch conditional actor-event hash changed.'
}

Write-Host (
    'Original CRT input-branch timing baseline passed ' +
    '(413 rounds, 24586 draws, two actor-slot acknowledgements).')
