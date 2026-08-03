[CmdletBinding()]
param(
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
$remakeRoot = Join-Path $RepositoryRoot 'Remake'
$catalogPath = Join-Path $remakeRoot (
    'game\data\original_crt_random_actor_event_timing.json')
$recurringPath = Join-Path $remakeRoot (
    'game\data\original_crt_random_recurring_timing.json')
$startupPath = Join-Path $remakeRoot (
    'game\data\original_crt_random_startup_catalog.json')

function Read-Utf8Json {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Required actor-event timing input is missing: $Path"
    }
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

$catalog = Read-Utf8Json -Path $catalogPath
$recurring = Read-Utf8Json -Path $recurringPath
$startup = Read-Utf8Json -Path $startupPath
if (
    [int]$catalog.schema_version -ne 2 -or
    [string]$catalog.catalog_id -ne
        'original-crt-random-actor-event-timing-v2' -or
    [string]$catalog.content_profile -ne [string]$startup.content_profile -or
    [string]$catalog.executable_sha256 -ne [string]$startup.executable_sha256 -or
    [string]$recurring.content_profile -ne [string]$catalog.content_profile
) {
    throw 'Actor-event timing catalog identity is invalid.'
}

$expectedFields = @(
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
$expectedSites = @(
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
if (
    (@($catalog.event_fields) -join ',') -ne ($expectedFields -join ',') -or
    (@($catalog.call_site_rvas) -join ',') -ne ($expectedSites -join ',')
) {
    throw 'Actor-event timing schema changed unexpectedly.'
}

$expectedByLevel = @{}
$expectedText = @'
m000|563|3073|C9D357AE643303BBFD77B21E88421904105C96BD54D69CC85F60A8E450ECF44C
m001|567|1797|E5DD4E4EC57ECA1DDCB0A05087D7739862B7DD2C475BBB8A0F40755FEC686ABD
m002|205|92|55FAEE39671445C404BF0ADD8CCB91B67904622A0A05594130476CB2797F5812
m003|560|1707|FBD1191C95D8E10517C18F189B6EAD5108C204A1C65B774EFE175ECF8CD5DA28
m004|397|3878|2A1E1E72B29E3011ED86A112040F642C6DC4526DC53F4BB9F98DFF562763C4DB
m005|187|2069|FA7FE8598BF53DA8CC59AD77CB5C5DD9B9EABC77F813E4F2C1699C99F3401D16
m006|561|3171|375A2FBDEFEDC61CE85FE35955BD9676042DFE9E9A818AADBBCCF2E106A5D3D1
m007|562|9473|2F0AE448FD459DDCC17CBF19C494B26AE1A1BC7CAD064A170573D36615D3B8FC
m008|561|1228|D7730CBBBC4290F1266EF9476A1E53337BE315AA9610F4112FCC543FE5F917EB
m009|562|584|BAF079759156F0167FAAEB4C99E2B25DD1C5AA0834B4F365196770E3380093A3
m010|560|1076|445AEE6D0454AD7C6A6B0A4AF2A916D04AC72F6FF4E31D10D6223C058EA48BE6
m011|560|1514|60F0D1414AA126C9466DB8BDCB48FF74D68875BA4A02701AB9C44215DD1AF8BB
'@
foreach ($line in $expectedText.Trim().Split("`n")) {
    $parts = $line.Trim().Split('|')
    if ($parts.Count -ne 4) {
        throw 'Invalid embedded actor-event timing expectation.'
    }
    $expectedByLevel[$parts[0]] = $parts
}

$levels = @($catalog.levels)
$recurringLevels = @($recurring.levels)
$startupLevels = @($startup.levels)
if (
    $levels.Count -ne 12 -or
    $recurringLevels.Count -ne 12 -or
    $startupLevels.Count -ne 12
) {
    throw 'Actor-event timing catalog must cover twelve formal levels.'
}

$totalEvents = 0
$siteTotals = @{}
foreach ($site in $expectedSites) {
    $siteTotals[$site] = 0
}
$unsnapshottedSites = @(
    '0x0005528C',
    '0x000552A3',
    '0x000552BA',
    '0x000552D1',
    '0x0005614F',
    '0x0005CB2B',
    '0x0005CEA6',
    '0x0005CF33',
    '0x0005CF4A',
    '0x0005CF61',
    '0x0005CF78')
for ($levelIndex = 0; $levelIndex -lt 12; $levelIndex++) {
    $levelId = 'm{0:D3}' -f $levelIndex
    $level = $levels[$levelIndex]
    $recurringLevel = $recurringLevels[$levelIndex]
    $startupLevel = $startupLevels[$levelIndex]
    $expected = $expectedByLevel[$levelId]
    if (
        [string]$level.id -ne $levelId -or
        [string]$recurringLevel.id -ne $levelId -or
        [string]$startupLevel.id -ne $levelId -or
        [int]$level.complete_round_count -ne [int]$expected[1] -or
        [int]$level.complete_round_count -ne
            [int]$recurringLevel.complete_round_count
    ) {
        throw "Actor-event timing linkage failed for $levelId."
    }

    $validActors = @{}
    foreach ($actor in @($startupLevel.actor_initialization)) {
        $validActors[[int]$actor.runtime_index] = $true
    }
    $events = @($level.events)
    if (
        $events.Count -ne [int]$level.event_count -or
        $events.Count -ne [int]$expected[2]
    ) {
        throw "Actor-event timing count drifted for $levelId."
    }

    $previousRound = 0
    $eventLines = [Collections.Generic.List[string]]::new()
    $eventsByRoundActor = @{}
    $levelSiteCounts = @{}
    foreach ($site in $expectedSites) {
        $levelSiteCounts[$site] = 0
    }
    foreach ($eventValue in $events) {
        $event = @($eventValue)
        if ($event.Count -ne $expectedFields.Count) {
            throw "Actor-event field count is invalid for $levelId."
        }
        $round = [int]$event[0]
        $runtimeIndex = [int]$event[1]
        $site = '0x{0:X8}' -f [uint32]$event[2]
        $value = [int]$event[3]
        if (
            $round -lt 1 -or
            $round -gt [int]$level.complete_round_count -or
            -not $validActors.ContainsKey($runtimeIndex) -or
            -not $levelSiteCounts.ContainsKey($site) -or
            $value -lt 0 -or
            $value -gt 32767 -or
            $round -lt $previousRound
        ) {
            throw "Actor-event ordering or identity is invalid for $levelId."
        }
        if ($site -in $unsnapshottedSites) {
            for ($fieldIndex = 4; $fieldIndex -lt $event.Count; $fieldIndex++) {
                if ([int]$event[$fieldIndex] -ne -1) {
                    throw (
                        "Unsnapshotted actor event gained invented fields " +
                        "for $levelId $site.")
                }
            }
        }
        else {
            if (
                [int]$event[4] -lt 0 -or
                [int]$event[5] -lt 0 -or
                [int]$event[8] -lt 0 -or
                [int]$event[9] -lt 0 -or
                [int]$event[11] -lt 0
            ) {
                throw "Actor-event snapshot is incomplete for $levelId."
            }
            if (
                $site -in @('0x00056105', '0x00058946') -and
                [int]$event[8] -ne [int]$event[9]
            ) {
                throw "Shared-counter reset boundary drifted for $levelId."
            }
            if (
                $site -eq '0x00058946' -and
                ([int]$event[10] -ne 1 -or [int]$event[11] -ne 0)
            ) {
                throw "Route-wait reset state drifted for $levelId."
            }
            if (
                $site -eq '0x0005D47E' -and
                ([int]$event[10] -ne 0 -or
                 [int]$event[11] -ne 0 -or
                 [int]$event[17] -lt 0)
            ) {
                throw "Pursuit resample state drifted for $levelId."
            }
        }
        $levelSiteCounts[$site] = [int]$levelSiteCounts[$site] + 1
        $siteTotals[$site] = [int]$siteTotals[$site] + 1
        $previousRound = $round
        $eventLines.Add(($event -join '|'))
        $groupKey = "${round}|${runtimeIndex}"
        if (-not $eventsByRoundActor.ContainsKey($groupKey)) {
            $eventsByRoundActor[$groupKey] = (
                [Collections.Generic.List[string]]::new())
        }
        $eventsByRoundActor[$groupKey].Add($site)
    }
    $primarySites = @($expectedSites[0..4])
    $blockedSites = @($expectedSites[5..8])
    $secondarySites = @($expectedSites[13..17])
    foreach ($groupSitesValue in $eventsByRoundActor.Values) {
        $groupSites = @($groupSitesValue)
        $primary = @($groupSites | Where-Object { $_ -in $primarySites })
        if (
            $primary.Count -gt 0 -and
            ($primary -join ',') -notin @(
                '0x00055216',
                ($primarySites -join ','))
        ) {
            throw "Primary-search event group is incomplete for $levelId."
        }
        $blocked = @($groupSites | Where-Object { $_ -in $blockedSites })
        if (
            $blocked.Count -gt 0 -and
            ($blocked -join ',') -ne ($blockedSites -join ',')
        ) {
            throw "Blocked-retry event group is incomplete for $levelId."
        }
        $secondary = @(
            $groupSites | Where-Object { $_ -in $secondarySites })
        if (
            $secondary.Count -gt 0 -and
            ($secondary -join ',') -notin @(
                '0x0005CEA6',
                ($secondarySites -join ','))
        ) {
            throw "Secondary-search event group is incomplete for $levelId."
        }
    }
    $eventText = [string]::Join("`n", $eventLines)
    if ($events.Count -gt 0) {
        $eventText += "`n"
    }
    $eventHash = Get-Sha256Text $eventText
    if (
        [string]$level.events_sha256 -ne $eventHash -or
        [string]$expected[3] -ne $eventHash
    ) {
        throw "Actor-event timing hash drifted for $levelId."
    }
    foreach ($site in $expectedSites) {
        $recurringRows = @($recurringLevel.call_site_counts | Where-Object {
            [string]$_.call_site_rva -eq $site
        })
        $recurringCount = 0
        if ($recurringRows.Count -eq 1) {
            $recurringCount = [int]$recurringRows[0].count
        }
        if ([int]$levelSiteCounts[$site] -ne $recurringCount) {
            throw "Actor-event recurring count failed for $levelId $site."
        }
    }
    $totalEvents += $events.Count
}

$expectedTotals = @{
    '0x00055216' = 7143
    '0x0005528C' = 11
    '0x000552A3' = 11
    '0x000552BA' = 11
    '0x000552D1' = 11
    '0x00055BFB' = 43
    '0x00055C0F' = 43
    '0x00055C23' = 43
    '0x00055C3A' = 43
    '0x00056105' = 1464
    '0x0005614F' = 11
    '0x00058946' = 1024
    '0x0005CB2B' = 1
    '0x0005CEA6' = 4776
    '0x0005CF33' = 84
    '0x0005CF4A' = 84
    '0x0005CF61' = 84
    '0x0005CF78' = 84
    '0x0005D394' = 0
    '0x0005D47E' = 14691
}
if ($totalEvents -ne 29662) {
    throw "Actor-event timing total drifted: $totalEvents."
}
foreach ($site in $expectedSites) {
    if ([int]$siteTotals[$site] -ne [int]$expectedTotals[$site]) {
        throw "Actor-event site total drifted for $site."
    }
}
Write-Host (
    'Original actor-event timing baseline passed for 12 levels ' +
    "($totalEvents conditional events).")
