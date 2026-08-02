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
    'game\data\original_crt_random_local_search_timing.json')
$recurringPath = Join-Path $remakeRoot (
    'game\data\original_crt_random_recurring_timing.json')
$startupPath = Join-Path $remakeRoot (
    'game\data\original_crt_random_startup_catalog.json')

function Read-Utf8Json {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Required local-search timing input is missing: $Path"
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
    [int]$catalog.schema_version -ne 1 -or
    [string]$catalog.catalog_id -ne
        'original-crt-random-local-search-timing-v1' -or
    [string]$catalog.content_profile -ne [string]$startup.content_profile -or
    [string]$catalog.executable_sha256 -ne [string]$startup.executable_sha256 -or
    [string]$recurring.content_profile -ne [string]$catalog.content_profile
) {
    throw 'Local-search timing catalog identity is invalid.'
}

$expectedSites = @(
    '0x0005D08F',
    '0x0005D09D',
    '0x0005D0B4',
    '0x0005D0CB',
    '0x0005D15F')
if ((@($catalog.call_site_rvas) -join ',') -ne ($expectedSites -join ',')) {
    throw 'Local-search timing call-site order changed unexpectedly.'
}

$expectedHashes = @{}
$expectedHashText = @'
m000|8|910CEDA3716A19D35448BDB45C8867793FD0D87FDF3F4723ED2511E6C4580CCD
m001|0|E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855
m002|0|E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855
m003|0|E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855
m004|8|182DAD535D061B0910C9467B420CEED0E0787B20E5F6CC2C5C32576F8B035E3B
m005|6|65125317B68F35022C84127E170C757EC49E5FFCA4A63849D1049065695A4BC9
m006|26|E4E6228EB85D248F1A38BF8F4FA998F4600DA918A2CDDA627E6AC4CB335FE8BB
m007|56|FEE16AF08F4A3AB57C15C4CD05DA2D90CC115C705C39F98CCDEC6726D3BFB6B8
m008|0|E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855
m009|0|E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855
m010|0|E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855
m011|3|AC4A3FF47CD0C9E522D7F5163320D23B42CA73C52B08809CF4BFBACFFD808EFF
'@
foreach ($line in $expectedHashText.Trim().Split("`n")) {
    $parts = $line.Trim().Split('|')
    if ($parts.Count -ne 3) {
        throw 'Invalid embedded local-search timing expectation.'
    }
    $expectedHashes[$parts[0]] = $parts
}

$levels = @($catalog.levels)
$recurringLevels = @($recurring.levels)
$startupLevels = @($startup.levels)
if (
    $levels.Count -ne 12 -or
    $recurringLevels.Count -ne 12 -or
    $startupLevels.Count -ne 12
) {
    throw 'Local-search timing catalog must cover twelve formal levels.'
}

$totalEvents = 0
for ($levelIndex = 0; $levelIndex -lt 12; $levelIndex++) {
    $levelId = 'm{0:D3}' -f $levelIndex
    $level = $levels[$levelIndex]
    $recurringLevel = $recurringLevels[$levelIndex]
    $startupLevel = $startupLevels[$levelIndex]
    if (
        [string]$level.id -ne $levelId -or
        [string]$recurringLevel.id -ne $levelId -or
        [string]$startupLevel.id -ne $levelId -or
        [int]$level.complete_round_count -ne
            [int]$recurringLevel.complete_round_count
    ) {
        throw "Local-search timing linkage failed for $levelId."
    }

    $validActors = @{}
    foreach ($actor in @($startupLevel.actor_initialization)) {
        $validActors[[int]$actor.runtime_index] = $true
    }
    $events = @($level.events)
    if (
        $events.Count -ne [int]$level.event_count -or
        $events.Count -ne [int]$expectedHashes[$levelId][1]
    ) {
        throw "Local-search timing event count drifted for $levelId."
    }
    $previousRound = 0
    $previousActor = -1
    $lines = [Collections.Generic.List[string]]::new()
    foreach ($event in $events) {
        $round = [int]$event.round_index
        $runtimeIndex = [int]$event.runtime_index
        $values = @($event.values)
        if (
            $round -lt 1 -or
            $round -gt [int]$level.complete_round_count -or
            -not $validActors.ContainsKey($runtimeIndex) -or
            $round -lt $previousRound -or
            ($round -eq $previousRound -and $runtimeIndex -le $previousActor) -or
            $values.Count -ne 5 -or
            [int]$event.world_x -lt 0 -or
            [int]$event.world_y -lt 0 -or
            [int]$event.shared_counter_before -ne
                [int]$event.shared_limit_before -or
            [int]$event.shared_limit_before -lt 0 -or
            [int]$event.shared_limit_before -gt 199 -or
            [int]$event.movement_path_state -ne 0 -or
            [int]$event.route_update_active -ne 0 -or
            [int]$event.search_delay_counter -lt 0 -or
            [int]$event.search_delay_limit -lt 40 -or
            [int]$event.search_delay_limit -gt 79
        ) {
            throw "Local-search timing state is invalid for $levelId."
        }
        foreach ($value in $values) {
            if ([int]$value -lt 0 -or [int]$value -gt 32767) {
                throw "Local-search random value is invalid for $levelId."
            }
        }
        $previousRound = $round
        $previousActor = $runtimeIndex
        $lines.Add((
            '{0}|{1}|{2}|{3}|{4}|{5}|{6}|{7}|{8}|{9}|{10}' -f
                $round,
                $runtimeIndex,
                [int]$event.world_x,
                [int]$event.world_y,
                [int]$event.shared_counter_before,
                [int]$event.shared_limit_before,
                [int]$event.movement_path_state,
                [int]$event.route_update_active,
                [int]$event.search_delay_counter,
                [int]$event.search_delay_limit,
                ($values -join ',')))
    }
    $eventText = [string]::Join("`n", $lines)
    if ($events.Count -gt 0) {
        $eventText += "`n"
    }
    $eventHash = Get-Sha256Text $eventText
    if (
        [string]$level.events_sha256 -ne $eventHash -or
        [string]$expectedHashes[$levelId][2] -ne $eventHash
    ) {
        throw "Local-search timing hash drifted for $levelId."
    }
    foreach ($site in $expectedSites) {
        $siteRows = @($recurringLevel.call_site_counts | Where-Object {
            [string]$_.call_site_rva -eq $site
        })
        $siteCount = 0
        if ($siteRows.Count -eq 1) {
            $siteCount = [int]$siteRows[0].count
        }
        if ($siteCount -ne $events.Count) {
            throw "Local-search recurring count failed for $levelId $site."
        }
    }
    $totalEvents += $events.Count
}

if ($totalEvents -ne 107) {
    throw "Local-search timing total drifted: $totalEvents."
}
Write-Host (
    'Original local-search timing baseline passed ' +
    "for 12 levels ($totalEvents complete five-call events).")
