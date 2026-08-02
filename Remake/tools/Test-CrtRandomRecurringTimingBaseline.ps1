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
$baselinePath = Join-Path $remakeRoot (
    'game\data\original_crt_random_recurring_timing.json')
$startupPath = Join-Path $remakeRoot (
    'game\data\original_crt_random_startup_catalog.json')

function Read-Utf8Json {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Required CRT random baseline is missing: $Path"
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

function Get-Sha256Text {
    param([string]$Text)
    return Get-Sha256Bytes (
        [Text.UTF8Encoding]::new($false).GetBytes($Text))
}

function Get-FirstRoundHashes {
    param([object[]]$Records)
    $orderStream = [IO.MemoryStream]::new()
    $valueStream = [IO.MemoryStream]::new()
    $actorOrderStream = [IO.MemoryStream]::new()
    $actorValueStream = [IO.MemoryStream]::new()
    $orderWriter = [IO.BinaryWriter]::new($orderStream)
    $valueWriter = [IO.BinaryWriter]::new($valueStream)
    $actorOrderWriter = [IO.BinaryWriter]::new($actorOrderStream)
    $actorValueWriter = [IO.BinaryWriter]::new($actorValueStream)
    try {
        foreach ($record in $Records) {
            $siteText = ([string]$record.call_site_rva).Trim()
            $site = [Convert]::ToUInt32($siteText.Substring(2), 16)
            $runtimeIndex = [int]$record.runtime_index
            $value = [uint32]$record.value
            $orderWriter.Write($site)
            $orderWriter.Write($runtimeIndex)
            $valueWriter.Write($site)
            $valueWriter.Write($runtimeIndex)
            $valueWriter.Write($value)
            if ($runtimeIndex -ge 0) {
                $actorOrderWriter.Write($site)
                $actorOrderWriter.Write($runtimeIndex)
                $actorValueWriter.Write($site)
                $actorValueWriter.Write($runtimeIndex)
                $actorValueWriter.Write($value)
            }
        }
        foreach ($writer in @(
                $orderWriter,
                $valueWriter,
                $actorOrderWriter,
                $actorValueWriter)) {
            $writer.Flush()
        }
        return [ordered]@{
            ordered_call_site_actor_sha256 = Get-Sha256Bytes (
                $orderStream.ToArray())
            ordered_call_site_actor_value_sha256 = Get-Sha256Bytes (
                $valueStream.ToArray())
            actor_order_sha256 = Get-Sha256Bytes (
                $actorOrderStream.ToArray())
            actor_value_sha256 = Get-Sha256Bytes (
                $actorValueStream.ToArray())
        }
    }
    finally {
        foreach ($writer in @(
                $orderWriter,
                $valueWriter,
                $actorOrderWriter,
                $actorValueWriter)) {
            $writer.Dispose()
        }
    }
}

$baseline = Read-Utf8Json -Path $baselinePath
$startup = Read-Utf8Json -Path $startupPath
if (
    [int]$baseline.schema_version -ne 1 -or
    [string]$baseline.baseline_id -ne (
        'original-crt-random-recurring-timing-v1') -or
    [string]$baseline.content_profile -ne [string]$startup.content_profile -or
    [string]$baseline.executable_sha256 -ne [string]$startup.executable_sha256
) {
    throw 'Recurring CRT random baseline identity is invalid.'
}
if (
    [string]$baseline.hash_encoding.byte_order -ne 'little-endian' -or
    [int]$baseline.hash_encoding.non_actor_runtime_index -ne -1 -or
    [string]$baseline.hash_encoding.algorithm -ne 'SHA-256'
) {
    throw 'Recurring CRT random hash encoding changed unexpectedly.'
}

$expectedRows = @{}
$expectedText = @'
m000|563|33516|33515|42005|0x1C21E314|D09766812E10DCFB36E0D7A43D87FCDC62A843D8DE92E1C97C8E22C665FE65CD|76C72582B5E8888D89D4AF191AE76BACD78E6A9DBF60EC9A3C82DC434DB7D7B9|863774B281498770203139816B16535795FDFFE4A17083E7264C30E2578E2495|92DF591CA0B17E5AA34208EE290B73A505BB8F4FA70C993485B78F6AF3D9E078
m001|567|41488|41487|53548|0xB999A49D|7EF1F349E62CDD3984C645220982EB3165C99558D7E760A34AECACB764225C13|30F77D9464EDDBBF5037C9B5D2CC206058B3BBFBFF60794B7D5CB5A775FD1864|C2553CCEE84481C4982AB061FB3A0BBAAA901DC4132EBF5E7446742F998AB465|4E6E1944D461AF27639D930BBCB0F140FC630D91A45D21E40945145F4FC975A6
m002|205|125048|5832|130600|0x61707A09|ED7E74CACFB7FC20B1EA71F3EAD6B0D8F86B7EC0D78C0FA7D5F9A65EBD51FC8D|AF84F175DC70FAE96DCC8B66D1BAA5D12261B1EB47415DDC52F18A4C1BA18C64|D6AF2D17E34F44DF5DC71CBF9D722C52D00D6AC7D10A5247087060DD4FB550E7|C521E58D45518655AFBDC3CD93674EB1A7B96FC1F90D450DB5350ACCD2BEB372
m003|560|28588|28587|35564|0xF9762B5D|8B39518BCA3C12FE080514669E6F25CD92026E91E2673CEFAF1579FE354DF506|3A513A4E06592B0179C0C6922EF6AE5E3510ED9D40B31EF7CA59E69A56600ED7|C276C95780ADF3CD8D995CF385C58E158C96254F88E6D150477EE7016DC24D6E|EC145EE3199335B986F3FD32092AE2B83ED5D0034C9F89A34CF3290B3654B55E
m004|397|42031|42030|54875|0x16FFF792|68D201F9EB3B9C09AB684A2C79DA17A08ED1633D5F26A59ABC68F8E82E278B7F|DECC8A9853330BA807FA3464444299F82944EA9782CB3DD0E9121590543F0FC8|F007884531B14848D4C911A45EE8216F0315CA40665F1D7BAEBD06A696CBBD6B|7F110A3EE94CD9DCEADDB8C58277841B55B53229C08FB044BE6A640D0CB4C2CC
m005|187|125476|16872|130520|0xD0CC32F9|855D032A6E14E10E70D3D9CB35B90E4AF6176E0C83970454E07AAD106831F90A|D3ED89189B5BAFBE20EC4730BAB4FFB2B3538CAA8ABA16C8DEB4BFC06A1CD1C8|EC87C836BBE96E5E50929B23040E56E4A7B960DC12E3F9072EB24A2F129E1A1A|C991960C1544CEE3FCA0518422DDD07AB15FCFF5FAC351F47B6554FF9BB6FFA3
m006|561|20693|20692|28533|0x0A681774|B5FC48EF23563477900A63509790D36D0862D4D67EB0B38086C4814C91BBCE58|70AA430C1862E09DBB985BF164B9A69D31114C458F48D5774EB6009922D1D30A|5F0FA534382D8275716ED4A0B9F1C26920B572ECAB6FDCB0EE9C215AC3505A32|CBEE9BD0447024D17F75C2C7C9DEBA35A53388814B4B5AF1920FA4B07FB2851D
m007|562|51342|51341|62934|0x33055247|555DF49C4509822F2B315FB8FE26335293FD578BA5D80EE5636E2F14E7C76D77|A4E4DBA1219B00E3466264055ADDBB211673C452B34D3463F88FDC26DE1108B1|C8F5F856F13798A9038FA11D131B67D5012019ABDC46021C928D4050B7115146|1659BCBEB61BA39F56DFC498882390854E1FD589FFD4B70F360DF97370E63BEC
m008|561|15815|15814|20995|0x8F4D793A|6EDC021EDACDAC2F7113BBD680AB87BDD7879A83ECE801E3D7BC5A2F3BD71126|325F0FE28370FB5E69C503E1EDDAD19AF5703E7E261AB2A6BF91639B4A34AC0E|E1B93AFDDF2409F3912D43C77EB68A99660B0A0F0DF188A026E9AAD93C4D7362|63AE6BC78BB0F965C013FF9F8873A9794B7EC5C1A9E0226825E0B130E4F0E176
m009|562|24751|24750|33609|0x5FA6FEC8|75F65CCCACA5B0FCDD3EDECADD03997D1304EDDC875B525C94BFB67C2CA32EA9|76FA1D235B76838EB8928EA7F96E5A455D76263325297F3A18A77B6E43175EFF|CB20D3FCD5EFFBCF43E3DBA33098D63F8B2A494AC4E66E25E37D74E4DBDCA134|9069755AEB1E16DB4312A9E66D871F807C66B96830AC5A623F3D79A2D9CCE472
m010|560|42517|42516|50993|0x6D85F570|F7E215BD157C4EF60D94F2E3698FE4C90B9FFF430BB79A1102789B7FCEDEA4D2|1931F68B22E48201E733AF3F9DD144E659A8A0A5EE19440419279717249E3CCF|8A4719CA75600D1D919F95F543BBD6265B7C0D6CB05F53D881A4C5F3CEDC2C98|BF31AA8A27A4AE1B42C1D6D237865D18C8F98D880B3F4744B309756943C5BDB7
m011|560|20010|20009|27442|0xE74D3273|463A2D1CE35349EBFA499388B5677FCEB59C4C9F955435B6EE7F7717C13D0764|9957CEA617A4B056F05853AE61B2D2D0E7D90B0DC4D1033DCDFEF2571F3EB0F9|A01F830770F116D983A7113C1454CFA5C52441262650FC65FDB5BED07CEE0058|CF20219A8ACBEE3D1E861C094F8238889B2068FBFD04E5379FA09FF707E9D2AF
'@
foreach ($line in $expectedText.Trim().Split("`n")) {
    $parts = $line.Trim().Split('|')
    if ($parts.Count -ne 10) {
        throw 'Invalid embedded recurring baseline expectation.'
    }
    $expectedRows[$parts[0]] = $parts
}

$expectedActorCountHashes = @{}
$expectedActorCountHashText = @'
m000|0B9C196C179B2FB465488EA36F0947E4150BA0E2F3C3C7CF7311B0400BCB7A8A
m001|EFC6476AFE46BF74D357DC782BBB50501E5AB187E73BE8388FBA1E64ED646818
m002|D3404195C5C09FD20FDB5963A59DAF2B71BE078F9274DB0D8ACDB3ECFC4FC7A0
m003|817D1CEE2DFC818F47582897D415EAA92A2F20B25E4BBF00B584C18B09B85F4F
m004|A46A398EE47103AD96C30E40C7191149DC227E3F4715320341433112B48047BD
m005|AD019519466B9CB3F0D22C9F86C27F81D92BE8A5FC0126B07AAEFF24CC66EEFD
m006|9E724E2031FFD568F555C41936965A0C950A5AC3689515AAB98F3255644954DC
m007|DB1C0F9574B88DC83DB7B0ACF34E683B8DF1096DE1F67C308FC993D59302A464
m008|6EA68A7049E737679A0DF84ECA5AF9155AB49FF3657056356132269454E528A1
m009|E4CCAC208B94A174EE8A0FC07CB04F6D319610E6E36CFFE055575231F5E95D2C
m010|69091AD42914667B5CA7D4F5938AA7946091623143F62BEAB955EBA002CB639F
m011|1E8B342606B7083E32E79F92B585C68487E31E5A67C950B2A4E48964C6BABBD1
'@
foreach ($line in $expectedActorCountHashText.Trim().Split("`n")) {
    $parts = $line.Trim().Split('|')
    if ($parts.Count -ne 2) {
        throw 'Invalid embedded actor call-site count expectation.'
    }
    $expectedActorCountHashes[$parts[0]] = $parts[1]
}

$levels = @($baseline.levels)
if ($levels.Count -ne 12 -or @($startup.levels).Count -ne 12) {
    throw 'Recurring CRT random baseline must contain twelve levels.'
}
$hashNames = @(
    'ordered_call_site_actor_sha256',
    'ordered_call_site_actor_value_sha256',
    'actor_order_sha256',
    'actor_value_sha256')
$validatedRounds = 0
for ($levelIndex = 0; $levelIndex -lt 12; $levelIndex++) {
    $levelId = 'm{0:D3}' -f $levelIndex
    $level = $levels[$levelIndex]
    $startupLevel = @($startup.levels)[$levelIndex]
    if (
        [string]$level.id -ne $levelId -or
        [string]$startupLevel.id -ne $levelId
    ) {
        throw "Recurring CRT random level order changed at $levelIndex."
    }
    foreach ($evidenceHash in @(
            [string]$level.evidence.source_trace_sha256,
            [string]$level.evidence.actor_snapshot_sha256)) {
        if ($evidenceHash -notmatch '^[0-9A-F]{64}$') {
            throw "Invalid recurring evidence hash for $levelId."
        }
    }
    $expected = $expectedRows[$levelId]
    if (
        [int]$level.complete_round_count -ne [int]$expected[1] -or
        [int]$level.accepted_draw_count -ne [int]$expected[2] -or
        [int]$level.accepted_actor_draw_count -ne [int]$expected[3] -or
        [int]$level.last_accepted_sequence -ne [int]$expected[4] -or
        [string]$level.final_state_hex -ne [string]$expected[5]
    ) {
        throw "Recurring CRT random summary drifted for $levelId."
    }
    for ($hashIndex = 0; $hashIndex -lt $hashNames.Count; $hashIndex++) {
        $hashName = $hashNames[$hashIndex]
        if (
            [string]$level.$hashName -ne [string]$expected[$hashIndex + 6] -or
            [string]$level.$hashName -notmatch '^[0-9A-F]{64}$'
        ) {
            throw "Recurring CRT random $hashName drifted for $levelId."
        }
    }
    if (
        [int]$level.first_gameplay_sequence -ne
            [int]$startupLevel.first_gameplay_update_sequence -or
        [int]$level.first_accepted_sequence -ne
            [int]$startupLevel.first_gameplay_update_sequence -or
        [string]$level.initial_state_hex -ne
            [string]$startupLevel.final_state_hex -or
        (@($level.observation_gate_actor_indices) -join ',') -ne
            (@($startupLevel.observation_gate_actor_indices) -join ',')
    ) {
        throw "Recurring CRT random startup linkage failed for $levelId."
    }

    $rounds = @($level.rounds)
    if ($rounds.Count -ne [int]$level.complete_round_count) {
        throw "Recurring CRT random round count is invalid for $levelId."
    }
    $drawSum = 0
    $actorDrawSum = 0
    $previousLastSequence = 0
    $previousTickOffset = -1
    for ($roundIndex = 0; $roundIndex -lt $rounds.Count; $roundIndex++) {
        $round = $rounds[$roundIndex]
        $firstSequence = [int]$round.first_sequence
        $lastSequence = [int]$round.last_sequence
        if (
            [int]$round.index -ne $roundIndex + 1 -or
            $lastSequence -lt $firstSequence -or
            [int]$round.draw_count -ne
                ($lastSequence - $firstSequence + 1) -or
            ($roundIndex -eq 0 -and
                $firstSequence -ne [int]$level.first_accepted_sequence) -or
            ($roundIndex -gt 0 -and
                $firstSequence -ne $previousLastSequence + 1) -or
            [long]$round.tick_ms_offset -lt $previousTickOffset
        ) {
            throw (
                "Recurring CRT random round structure is invalid for " +
                "$levelId round $($roundIndex + 1).")
        }
        foreach ($hashName in $hashNames) {
            if ([string]$round.$hashName -notmatch '^[0-9A-F]{64}$') {
                throw (
                    "Invalid $hashName for $levelId round " +
                    "$($roundIndex + 1).")
            }
        }
        $drawSum += [int]$round.draw_count
        $actorDrawSum += [int]$round.actor_draw_count
        $previousLastSequence = $lastSequence
        $previousTickOffset = [long]$round.tick_ms_offset
    }
    if (
        $drawSum -ne [int]$level.accepted_draw_count -or
        $actorDrawSum -ne [int]$level.accepted_actor_draw_count -or
        $previousLastSequence -ne [int]$level.last_accepted_sequence -or
        [string]$rounds[-1].final_state_hex -ne
            [string]$level.final_state_hex -or
        [long]$rounds[-1].tick_ms_offset -ne [long]$level.tick_span_ms
    ) {
        throw "Recurring CRT random round totals failed for $levelId."
    }
    $siteCountSum = [int](
        @($level.call_site_counts | Measure-Object -Property count -Sum).Sum)
    if ($siteCountSum -ne $drawSum) {
        throw "Recurring CRT random call-site totals failed for $levelId."
    }

    $actorCountRows = @($level.actor_call_site_counts)
    if ($actorCountRows.Count -eq 0) {
        throw "Actor call-site counts are missing for $levelId."
    }
    $actorCountSum = 0
    $previousRuntimeIndex = -1
    $previousActorSite = ''
    $actorSiteTotals = @{}
    $actorCountLines = [Collections.Generic.List[string]]::new()
    foreach ($row in $actorCountRows) {
        $runtimeIndex = [int]$row.runtime_index
        $site = [string]$row.call_site_rva
        $count = [int]$row.count
        if (
            $runtimeIndex -lt 0 -or
            $site -notmatch '^0x[0-9A-F]{8}$' -or
            $count -le 0 -or
            $runtimeIndex -lt $previousRuntimeIndex -or
            ($runtimeIndex -eq $previousRuntimeIndex -and
                [string]::CompareOrdinal($site, $previousActorSite) -le 0)
        ) {
            throw "Actor call-site ordering is invalid for $levelId."
        }
        $previousRuntimeIndex = $runtimeIndex
        $previousActorSite = $site
        $actorCountSum += $count
        $actorSiteTotals[$site] = [int]$actorSiteTotals.Get_Item($site) + $count
        $actorCountLines.Add(
            ('{0}|{1}|{2}' -f $runtimeIndex, $site, $count))
    }
    if ($actorCountSum -ne $actorDrawSum) {
        throw "Actor call-site totals failed for $levelId."
    }
    $levelSiteTotals = @{}
    foreach ($row in @($level.call_site_counts)) {
        $levelSiteTotals[[string]$row.call_site_rva] = [int]$row.count
    }
    foreach ($site in $actorSiteTotals.Keys) {
        if (
            -not $levelSiteTotals.ContainsKey($site) -or
            [int]$actorSiteTotals[$site] -gt [int]$levelSiteTotals[$site]
        ) {
            throw "Actor call-site count exceeds the global count in $levelId."
        }
    }
    $actorCountText = [string]::Join("`n", $actorCountLines) + "`n"
    $actualActorCountHash = Get-Sha256Text $actorCountText
    if (
        [string]$level.actor_call_site_counts_sha256 -ne
            $actualActorCountHash -or
        $actualActorCountHash -ne
            [string]$expectedActorCountHashes[$levelId]
    ) {
        throw "Actor call-site count hash drifted for $levelId."
    }

    $firstRecords = @($startupLevel.first_gameplay_update.records)
    $firstRound = $rounds[0]
    $firstHashes = Get-FirstRoundHashes -Records $firstRecords
    if ($firstRecords.Count -ne [int]$firstRound.draw_count) {
        throw "First recurring round draw count failed for $levelId."
    }
    foreach ($hashName in $hashNames) {
        if ([string]$firstRound.$hashName -ne [string]$firstHashes[$hashName]) {
            throw "First recurring round $hashName failed for $levelId."
        }
    }
    $state = [Convert]::ToUInt64(
        ([string]$level.initial_state_hex).Substring(2), 16)
    foreach ($record in $firstRecords) {
        $state = (
            ($state * [uint64]214013 + [uint64]2531011) -band
            [uint64]4294967295)
        if ([int](($state -shr 16) -band 0x7fff) -ne [int]$record.value) {
            throw "First recurring round LCG failed for $levelId."
        }
    }
    if (('0x{0:X8}' -f [uint32]$state) -ne
        [string]$firstRound.final_state_hex) {
        throw "First recurring round state failed for $levelId."
    }
    $validatedRounds += $rounds.Count
}

Write-Host (
    "Recurring CRT random baseline passed for 12 levels " +
    "($validatedRounds complete rounds).")
