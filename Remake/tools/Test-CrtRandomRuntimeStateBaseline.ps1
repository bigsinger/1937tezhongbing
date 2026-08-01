[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$remakeRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$baselinePath = Join-Path $remakeRoot (
    'game\data\original_crt_random_runtime_state.json')
$startupPath = Join-Path $remakeRoot (
    'game\data\original_crt_random_startup_catalog.json')
$baseline = (
    [IO.File]::ReadAllText(
        $baselinePath,
        [Text.UTF8Encoding]::new($false)) |
        ConvertFrom-Json)
$startup = (
    [IO.File]::ReadAllText(
        $startupPath,
        [Text.UTF8Encoding]::new($false)) |
        ConvertFrom-Json)

if (
    [int]$baseline.schema_version -ne 1 -or
    [string]$baseline.baseline_id -ne (
        'original-crt-random-runtime-state-v1') -or
    [string]$baseline.content_profile -ne (
        'repository-mod-12-level-20260729') -or
    [string]$baseline.executable_sha256 -ne (
        'F4DD1131DF6C993C01EA011F9439BC725E6DC6491B5FBBA47724D7D5B64DA3F3')
) {
    throw 'Unsupported original CRT runtime-state baseline.'
}
if (
    [string]$baseline.evidence.capture_mode -ne (
        'process-local-crt-rand-hook-and-memory-snapshot') -or
    [string]$baseline.evidence.hook_scope -ne (
        'test-only-environment-gated') -or
    [string]$baseline.evidence.input_scope -ne (
        'target-window-only') -or
    [string]$baseline.evidence.observation_scope -ne (
        'read-only-gameplay-window') -or
    [int]$baseline.recovered_rules.actor_tick_hz -ne 60
) {
    throw 'Runtime-state provenance or recovered cadence changed.'
}
$evidenceFiles = @($baseline.evidence.files)
if ($evidenceFiles.Count -ne 48) {
    throw 'Runtime-state provenance must retain four files for twelve levels.'
}
foreach ($file in $evidenceFiles) {
    if (
        [string]$file.level_id -notmatch '^m0(0[0-9]|1[01])$' -or
        [string]$file.sha256 -notmatch '^[0-9A-F]{64}$'
    ) {
        throw 'Runtime-state evidence file identity/hash is invalid.'
    }
}

$expected = @(
    @('m000', 302, 18208, 62, 127,
        'F93111C4A596972B8759105A57D799C4ED6F75DA3E93058102C08EA3C8696269',
        'B9CFB24B37498B66B7FA5ED7228BA2AE1ABC81E25D502CE27B240D6DA3DA17D3'),
    @('m001', 308, 22423, 75, 157,
        'F152773D2128742F9509404658816E5552B0789823F32337F96DC50ED94B74C9',
        'F512A21E9607D715A1425074799225475D305B38A957EDF1C55C8D837079889F'),
    @('m002', 301, 129183, 34, 84,
        'C52EFC9025105F1EB99647A1ECDAD7CCCBBB75C80A001A83F686539AA4D3C850',
        '41E0A42F05DD52093437FB769BF95B7F98ABEB9F22D4E3A67620E7A2A92E9B02'),
    @('m003', 301, 15749, 53, 96,
        '710533B4F890465AC77E869EEA334E86156BBBDB3B6438441D73901D2E9E48B5',
        '00259FB9A7FC9DE6F8F2B40D3B6A17716C8E2974326AFF5D3C14DAAEEC9AE9E2'),
    @('m004', 227, 24391, 116, 145,
        '94085ED38008C0DDF8F150A6AEA763611E3A2D94E2A21A9529562467359D6B76',
        '28512AAC8193397215A89FB8894B6D211E911301FC6B2BD0F0396CE54B7A6E30'),
    @('m005', 302, 125131, 92, 122,
        '687EB3F395FBAB4E3CD34F0946E916C1060118526450E55AFF686BDA5AFB9771',
        'F1313F821AA00BAC8E2AF30D617567B7FC617B4AB442AB55DBF6E542011AD5EB'),
    @('m006', 302, 11266, 44, 75,
        'C564A2988105DB3229459EE67C88396DE1E2CFEAC9160A1C896FE545F3FDC579',
        '1B0B6EF75778EFCD908AF8C834AC9A41B101985E30B9C9777CB5E8364D432C9C'),
    @('m007', 302, 27806, 99, 121,
        'F0D4C9E3A8BD180A4AC0785D2FACBA5389FBE2AE7191EDCA442BB529AEB41F09',
        'ABC8FB82141788254A94FCE29EAE43B14E60549A605604A863FF700554E6E2B9'),
    @('m008', 303, 8312, 28, 52,
        '060FDD915801B6D3B8CF0B6010A4BAF24DB42A1F047AEE4C7FB70C5338560158',
        '242C223B8038DDCEAB023DA7E9556117C8A15436E30433538022A923EB0BE2F3'),
    @('m009', 302, 13276, 48, 136,
        '17F91AA3101EA1C4568AF49AD7AAEB19711FCF878D1421C73D9B573D1CF7F6BC',
        '9BC214734A4EE97AA2C9D143E074DF2FD5C564144E3C331F05AAA7D5D42DE3A4'),
    @('m010', 301, 22956, 81, 122,
        '2F4CD797AC4E266F6C58CD23024632B86A6CE096F88C840038A8F44070D05082',
        '666EEF5DB14CB82D5CE6ABC4E1CCD75F1A293DF7DF9C6B627BF9A0EB50B1CB4B'),
    @('m011', 301, 11171, 40, 101,
        'AEE0975979914E5BEC558D805AB7CB8A909339AE3B08703C4B79C1FA6CF46C09',
        '02F33750A08D76383BAA8AD08CDB14AFE86F93FE2D151732F83EBF99B9953238')
)
$levels = @($baseline.levels)
if ($levels.Count -ne 12) {
    throw 'Runtime-state baseline must cover exactly m000..m011.'
}
$totalDraws = 0
$totalRouteEvents = 0
$totalStationaryEvents = 0
$totalPursuitEvents = 0
$totalSearchGroups = 0
for ($index = 0; $index -lt $expected.Count; $index++) {
    $row = $expected[$index]
    $level = $levels[$index]
    $startupLevel = @($startup.levels | Where-Object {
        [string]$_.id -eq [string]$row[0]
    })
    if ($startupLevel.Count -ne 1) {
        throw "Startup level is missing: $($row[0])"
    }
    $startupLevel = $startupLevel[0]
    if (
        [string]$level.id -ne [string]$row[0] -or
        [int]$level.selector_level -ne $index + 1 -or
        [int]$level.complete_round_count -ne [int]$row[1] -or
        [int]$level.complete_draw_count -ne [int]$row[2] -or
        [int]$level.active_actor_count -ne [int]$row[3] -or
        [int]$level.actor_snapshot_count -ne [int]$row[4] -or
        [string]$level.complete_call_order_sha256 -ne [string]$row[5] -or
        [string]$level.complete_value_sha256 -ne [string]$row[6] -or
        [int]$level.first_gameplay_sequence -ne
            [int]$startupLevel.first_gameplay_update_sequence -or
        [int]$level.capture_span_ms -lt 4900
    ) {
        throw "Runtime-state capture identity changed: $($row[0])"
    }
    if (
        [int]$level.active_actor_count -ne
            @($startupLevel.actor_initialization).Count -or
        @($level.actors).Count -ne [int]$level.active_actor_count
    ) {
        throw "Active actor inventory diverged: $($row[0])"
    }
    if (
        [int]$level.reset_laws.route_violation_count -ne 0 -or
        [int]$level.reset_laws.stationary_violation_count -ne 0 -or
        [string]$level.reset_laws.next_limit_formula -ne (
            'rand()%160+40') -or
        [int]$level.pursuit.violation_count -ne 0 -or
        [int]$level.local_search.violation_count -ne 0 -or
        [int]$level.local_search.event_count -ne
            [int]$level.local_search.complete_group_count * 5
    ) {
        throw "Recovered runtime law no longer holds: $($row[0])"
    }
    $actorIndices = @{}
    foreach ($actor in $level.actors) {
        $runtimeIndex = [int]$actor.runtime_index
        if (
            $actorIndices.ContainsKey($runtimeIndex) -or
            [int]$actor.scene_index -lt 0 -or
            [int]$actor.runtime_type -le 0 -or
            [int]$actor.entry.route_update_active -notin @(0, 1) -or
            [int]$actor.exit.route_update_active -notin @(0, 1)
        ) {
            throw "Invalid active actor state in $($row[0])."
        }
        $actorIndices[$runtimeIndex] = $true
    }
    foreach ($link in $level.pursuit.links) {
        if (
            -not $actorIndices.ContainsKey([int]$link.runtime_index) -or
            -not $actorIndices.ContainsKey(
                [int]$link.target_runtime_index) -or
            [int]$link.runtime_index -eq
                [int]$link.target_runtime_index -or
            [int]$link.event_count -le 0 -or
            [string]$link.call_site_rva -notin @(
                '0x0005D394', '0x0005D47E')
        ) {
            throw "Invalid pursuit link in $($row[0])."
        }
    }
    $totalDraws += [int]$level.complete_draw_count
    $totalRouteEvents += [int]$level.reset_laws.route_event_count
    $totalStationaryEvents += (
        [int]$level.reset_laws.stationary_event_count)
    $totalPursuitEvents += [int]$level.pursuit.event_count
    $totalSearchGroups += [int]$level.local_search.complete_group_count
}
if (
    $totalDraws -ne 429872 -or
    $totalRouteEvents -ne 669 -or
    $totalStationaryEvents -ne 968 -or
    $totalPursuitEvents -ne 11409 -or
    $totalSearchGroups -ne 58
) {
    throw 'Twelve-level runtime-state aggregate changed.'
}

$m000Links = @($levels[0].pursuit.links | ForEach-Object {
    '{0}>{1}' -f (
        [int]$_.runtime_index), ([int]$_.target_runtime_index)
} | Sort-Object -Unique)
$expectedM000Links = @(
    '104>107', '105>103', '106>105', '107>106',
    '119>118', '121>124', '122>123', '123>120', '124>122')
if (($m000Links -join ',') -ne ($expectedM000Links -join ',')) {
    throw 'm000 authored formation pursuit chain changed.'
}

Write-Host (
    "Original CRT runtime-state baseline passed: 12 levels, " +
    "772 active actors, 429872 clean-window draws, " +
    "140 pursuit links, 58 local-search groups.")
