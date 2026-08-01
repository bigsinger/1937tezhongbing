[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$remakeRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$baselinePath = Join-Path $remakeRoot (
    'game\data\original_crt_random_startup_catalog.json')
$actorCatalogPath = Join-Path $remakeRoot (
    'game\data\original_runtime_actor_catalog.json')

$baseline = (
    [IO.File]::ReadAllText(
        $baselinePath,
        [Text.UTF8Encoding]::new($false)) |
        ConvertFrom-Json)
$actorCatalog = (
    [IO.File]::ReadAllText(
        $actorCatalogPath,
        [Text.UTF8Encoding]::new($false)) |
        ConvertFrom-Json)

if (
    [int]$baseline.schema_version -ne 3 -or
    [string]$baseline.catalog_id -ne (
        'original-crt-random-startup-v3') -or
    [string]$baseline.content_profile -ne (
        'repository-mod-12-level-20260729') -or
    [string]$baseline.executable_sha256 -ne (
        'F4DD1131DF6C993C01EA011F9439BC725E6DC6491B5FBBA47724D7D5B64DA3F3')
) {
    throw 'Unsupported original CRT random startup baseline.'
}

$expected = [ordered]@{
    m000 = @(
        8489, '0xCEBEAFA8',
        '9C59582928AE9E8F58088B5B8A3359E912B3C1D102DD309A5B59683A300082EF',
        '81E53FE486D853148A0C490FA87097A228EAC1017EF2193308BF275DA823C20A')
    m001 = @(
        12060, '0x41EC09CD',
        '13CB436F0028735BB3C8EF494834F49FA40B08360819EF5ECCB8C0008C945C92',
        'C7DBC1B733AF57021BDC23B9CCC1F9BD5E58F1FBCBB9B975383363EDCA50DA18')
    m002 = @(
        5552, '0x44F598F1',
        '7DE8D00D3BE904BEA2A3EC3736C8ECD24EB55B2ABA8C2344757ECA08FDA1B592',
        '531AE91E40A90F7ABBFDB7F1190C9B4690E04882EE89CF1AC93FC1AD8C7222B2')
    m003 = @(
        6976, '0x18C06E41',
        'EA9080D725A6A041E37B2A8ECA530DDA1EA9CE904EC8D37E5FFEC584728615B5',
        'DB3D58A30AAEC12F2F3E706F48462EE7AAEF16B210B2D26F683CDBADCF15321F')
    m004 = @(
        12844, '0xCC28B19D',
        '8FD7A6C608DD5AB7C92920070835B7BAB597275DEA1BFE81057626C2FB4931B6',
        '9F6FA929A86FBFF131C493435B6DD257AE67EFAB8F977050D057CCD9E790A8FE')
    m005 = @(
        5044, '0x2B243B05',
        '3F20E896849F13BF00B5106E83F7989DE8BE73603FF005EDE44EA28DCFF02F2B',
        '1589739B1CE7E90C74814D427C93A688A384F71EC2804DF1CD62F392EBB3A77D')
    m006 = @(
        7840, '0xD2297C21',
        'A7FF1C2B6740CD35CA03D4B07C0ED363D09EAD6448A0F3B20C08B592139FE0A4',
        '9B1647C13634229521C76E5B82E7ADF5EA2FA2DC84AEDE2244AF59CBBF4B7BFE')
    m007 = @(
        11592, '0xE16B18A9',
        '1657763FCE767D58050479DFC1F5EE6CCE7AC546BE06DBBF04661977104071A0',
        '55E466E909F5FAB378DEEE8C14973B734E2B399B030B7C08137203D08070527C')
    m008 = @(
        5180, '0x3C0EB06D',
        'ACB67E5A73103AA4879D4FDB17A8236E4BEFCC0BC71014A2FEA8847C79F03062',
        '3902AFCC80579CDE0AE831069223D18C770F7038E581C5E406AA1A4E434F6BC6')
    m009 = @(
        8858, '0x41CD28FB',
        'CAD51FF081F91C7D107B6D4463091E010D96EF136395D19ECC7A62513582262A',
        '8F7BCCEDCDD32FEEF198382DA4EF6CE41C21012193880C5C7EAAE15894258D97')
    m010 = @(
        8476, '0xF09B13CD',
        '0EDDCB241423E2D4B8EC90F374BAF964046B34170F4B7CC6B41E726223731155',
        '4E4AFB3D7FD6DFDA36CAB49246CD6DD6E3A7450F9205CC8572EB6616F927BBF3')
    m011 = @(
        7432, '0x776D4169',
        '5215B194AFA4AFFEB57CB4CAE7B3C21D0272EBE14B306BCB81934E31F29C0B33',
        '5C8578CAE548CD42810D04FD8F48CD994E6077E1536F86ABCF14689A9CA4B3ED')
}
$expectedFirstUpdates = [ordered]@{
    m000 = @(
        59,
        '3231756386A076702BE58FC4271C8324EA5D86368818035DD4957C2DCF348727',
        '3E4818E0F54531058709D9E122E3DAC2C0AAE8608210367F1CF7F690162AE71E')
    m001 = @(
        81,
        '8C5BA71514E4E53B019E51FFF10974C25C145D38FD70337F3EFC64B7F8E27CC6',
        'A278E116DF7E13D4C5EB65707592E0B3D61268F5E951E74189BA6CB40A98D895')
    m002 = @(
        30,
        'CBF5A5B916F4FC5617892B996C737C57869E0F9AE23FDBF0A3D448D4C270CF4C',
        '445A6D1D89325211E337CB951345C89CB0A6267A9CFF77FE617D4491372B9751')
    m003 = @(
        50,
        '22CA923DD09206333EDEC73118FAE01B24E01F43F530276D7197E39DCDD271E6',
        'AE8D592B138C2F64BBB19473BAE8A9B68222DC54E33DA1FC47E5C21B6233C01C')
    m004 = @(
        112,
        '0A1BD8BFB65D206955EC0131D355A9B79E55942460731294E0F97345E32A3563',
        'AEA3468F16E80251C22F76615C6CD993F183EF46E0865A7581918A70E5A0FAA3')
    m005 = @(
        108,
        'BB5AE9D73808AE439CADA6A38A7A72DC2E5E7C1A5F457702A1FEB8757DF9E0E2',
        'FA2C66C62B6B9A2AD1610FBA00A63B5AF6E96898E034F1521D1F92950FC09D92')
    m006 = @(
        45,
        'BD7852474CAF807EF403AC2D1A90FD9808246862B933B6465456F439EF68067F',
        '945B1C4FE39992A64BB1B00FBB617CDF88DE96F33B0115C40C54B17233F7E37F')
    m007 = @(
        89,
        '5C56C3528E04495BF72B4D703B0BE398991B639E015AC35FED1F0A26F19BE154',
        'CBB9DAB6B588FFEE07BF5999C40D24A39C7F7861C96A4C8403A2550E02C3826F')
    m008 = @(
        30,
        'C9F2D3B8E471D739C363FCC3F042779A2D557A6A3A880851A8D3FFC44350C6F7',
        '64A8E1FF50DE9B478E5DAA81641B454585F5D90BF1C925E6AE7CA6CFEAF243D2')
    m009 = @(
        44,
        'DD65236BFB7CD0AE30F5E925AEC7024D728C8DFC6B903B58B7530A97E490D16C',
        'B1E4C16F3A25A57CEB0D1C30E54A84CC775B194B4D794283823A0851E90CCE48')
    m010 = @(
        87,
        '28F67AC498B744B05CAB19C921AD1F9A729B32A8987D1024D8FD4DE2DBE58190',
        'CBC8916C2191F44620E6888C915213AD4ED66086AA81F4F6A1147B2C82DAD6A5')
    m011 = @(
        34,
        '693FBA57D12E2B94F955BCC8D476D61CD7BA2E6E27CD1A56BF97737DA3DFB246',
        'B631048EB48E33B3DE6A036CE1B6CDAB635D801588A64395D648DD26F1BD415E')
}
if (@($baseline.levels).Count -ne 12) {
    throw 'The CRT random startup baseline must contain exactly 12 levels.'
}

$verifiedActors = 0
$verifiedGateActors = 0
$verifiedFirstUpdateDraws = 0
$verifiedFirstUpdateActorOutcomes = 0
$verifiedSemanticEffects = @{
    route_wait_limit = 0
    pursuit_command_snapshot = 0
    primary_candidate_scan = 0
    blocked_retry_destination = 0
    secondary_candidate_scan = 0
    secondary_search_destination = 0
}
foreach ($levelIndex in 0..11) {
    $levelId = 'm{0:D3}' -f $levelIndex
    $level = @($baseline.levels | Where-Object {
        [string]$_.id -eq $levelId
    })
    if ($level.Count -ne 1) {
        throw "The CRT random baseline has no unique $levelId entry."
    }
    $level = $level[0]
    $expectedLevel = $expected[$levelId]
    if (
        [int]$level.initialization_draw_count -ne (
            [int]$expectedLevel[0]) -or
        [string]$level.final_state_hex -ne (
            [string]$expectedLevel[1]) -or
        [int]$level.ambient_prefix_draw_count -ne 1960 -or
        [int]$level.first_actor_sequence -ne 1961 -or
        [int]$level.first_gameplay_update_sequence -ne (
            [int]$level.initialization_draw_count + 1) -or
        [string]$level.ordered_call_site_sha256 -ne (
            [string]$expectedLevel[2]) -or
        [string]$level.ordered_value_sha256 -ne (
            [string]$expectedLevel[3])
    ) {
        throw "CRT random startup evidence mismatch for $levelId."
    }

    [uint64]$state = 1
    for (
        $drawIndex = 0;
        $drawIndex -lt [int]$level.initialization_draw_count;
        $drawIndex++
    ) {
        $state = (
            ($state * [uint64]214013 + [uint64]2531011) -band
            [uint64]4294967295)
    }
    if (('0x{0:X8}' -f $state) -ne [string]$level.final_state_hex) {
        throw "CRT random startup LCG checkpoint mismatch for $levelId."
    }

    $firstUpdate = $level.first_gameplay_update
    $expectedFirstUpdate = $expectedFirstUpdates[$levelId]
    $firstUpdateRecords = @($firstUpdate.records)
    if (
        [int]$firstUpdate.draw_count -ne (
            [int]$expectedFirstUpdate[0]) -or
        $firstUpdateRecords.Count -ne (
            [int]$expectedFirstUpdate[0]) -or
        [string]$firstUpdate.ordered_call_site_sha256 -ne (
            [string]$expectedFirstUpdate[1]) -or
        [string]$firstUpdate.ordered_value_sha256 -ne (
            [string]$expectedFirstUpdate[2])
    ) {
        throw "First gameplay random update mismatch for $levelId."
    }
    $musicDraws = 0
    $gateDraws = 0
    foreach ($record in $firstUpdateRecords) {
        $state = (
            ($state * [uint64]214013 + [uint64]2531011) -band
            [uint64]4294967295)
        $expectedValue = [int](($state -shr 16) -band 0x7fff)
        $site = [string]$record.call_site_rva
        $runtimeIndex = [int]$record.runtime_index
        if ([int]$record.value -ne $expectedValue) {
            throw "First gameplay LCG value mismatch for $levelId."
        }
        if ($site -eq '0x00006A73') {
            if ($runtimeIndex -ne -1) {
                throw "Level music draw is actor-bound in $levelId."
            }
            $musicDraws++
        }
        elseif ($runtimeIndex -lt 0) {
            throw "First gameplay actor draw is unmapped in $levelId."
        }
        if ($site -eq '0x0005C81C') {
            $gateDraws++
        }
    }
    if (
        $musicDraws -ne 1 -or
        $gateDraws -ne @($level.observation_gate_actor_indices).Count
    ) {
        throw "First gameplay call family mismatch for $levelId."
    }
    $verifiedFirstUpdateDraws += $firstUpdateRecords.Count
    $actorRecordsByRuntimeIndex = @{}
    foreach ($record in $firstUpdateRecords) {
        $runtimeIndex = [int]$record.runtime_index
        $site = [string]$record.call_site_rva
        if ($runtimeIndex -lt 0 -or $site -eq '0x0005C81C') {
            continue
        }
        if (-not $actorRecordsByRuntimeIndex.ContainsKey($runtimeIndex)) {
            $actorRecordsByRuntimeIndex[$runtimeIndex] = @()
        }
        $actorRecordsByRuntimeIndex[$runtimeIndex] = @(
            $actorRecordsByRuntimeIndex[$runtimeIndex]) + @($record)
    }
    $outcomes = @($firstUpdate.actor_outcomes)
    if ($outcomes.Count -ne $actorRecordsByRuntimeIndex.Count) {
        throw "First gameplay actor outcome count mismatch for $levelId."
    }
    $seenOutcomeActors = @{}
    foreach ($outcome in $outcomes) {
        $runtimeIndex = [int]$outcome.runtime_index
        if (
            $seenOutcomeActors.ContainsKey($runtimeIndex) -or
            -not $actorRecordsByRuntimeIndex.ContainsKey($runtimeIndex)
        ) {
            throw "Invalid first gameplay actor outcome in $levelId."
        }
        $seenOutcomeActors[$runtimeIndex] = $true
        $actorRecords = @($actorRecordsByRuntimeIndex[$runtimeIndex])
        $outcomeSites = @($outcome.call_site_rvas)
        if ($outcomeSites.Count -ne $actorRecords.Count) {
            throw "First gameplay actor call count mismatch in $levelId."
        }
        for ($recordIndex = 0; $recordIndex -lt $actorRecords.Count;
                $recordIndex++) {
            if (
                [string]$outcomeSites[$recordIndex] -ne
                [string]$actorRecords[$recordIndex].call_site_rva
            ) {
                throw "First gameplay actor call order mismatch in $levelId."
            }
        }
        $effects = @($outcome.semantic_effects)
        if ($effects.Count -eq 0) {
            throw "First gameplay actor outcome has no effect in $levelId."
        }
        foreach ($effect in $effects) {
            $effectName = [string]$effect
            if (-not $verifiedSemanticEffects.ContainsKey($effectName)) {
                throw "Unknown first gameplay effect $effectName."
            }
            $verifiedSemanticEffects[$effectName]++
        }
        $postUpdateState = $outcome.post_update_state
        if ($null -eq $postUpdateState) {
            throw "First gameplay actor outcome has no state in $levelId."
        }
        if ($effects -contains 'route_wait_limit') {
            $routeRecord = @($actorRecords | Where-Object {
                [string]$_.call_site_rva -eq '0x00058946'
            })
            if (
                $routeRecord.Count -ne 1 -or
                [int]$outcome.route_wait_limit -ne (
                    ([int]$routeRecord[0].value % 160) + 40)
            ) {
                throw "First gameplay route wait mismatch in $levelId."
            }
        }
        elseif ([int]$outcome.route_wait_limit -ne -1) {
            throw "Unexpected first gameplay route wait in $levelId."
        }
        if ($effects -contains 'secondary_search_destination') {
            if (
                [int]$postUpdateState.goal_kind -ne 1 -or
                [int]$postUpdateState.goal_x -ne (
                    [int]$postUpdateState.resolved_goal_x) -or
                [int]$postUpdateState.goal_y -ne (
                    [int]$postUpdateState.resolved_goal_y) -or
                [int]$postUpdateState.movement_path_state -ne 2
            ) {
                throw "Secondary search outcome mismatch in $levelId."
            }
        }
        if (
            $effects -contains 'pursuit_command_snapshot' -and
            [int]$postUpdateState.command_variant -ne 0
        ) {
            throw "First-update pursuit command changed in $levelId."
        }
        $verifiedFirstUpdateActorOutcomes++
    }

    $runtimeLevel = $actorCatalog.levels.$levelId
    $runtimeActors = @($runtimeLevel.actors.PSObject.Properties)
    $initialization = @($level.actor_initialization)
    if (
        $initialization.Count -ne [int]$runtimeLevel.resolved_actor_count -or
        $initialization.Count -ne $runtimeActors.Count
    ) {
        throw "Active actor initialization count mismatch for $levelId."
    }
    $actorByRuntimeIndex = @{}
    foreach ($entry in $initialization) {
        $runtimeIndex = [int]$entry.runtime_index
        if (
            $actorByRuntimeIndex.ContainsKey($runtimeIndex) -or
            [int]$entry.initial_idle_limit -lt 0 -or
            [int]$entry.initial_idle_limit -gt 159 -or
            [int]$entry.initial_facing_direction -lt 1 -or
            [int]$entry.initial_facing_direction -gt 8 -or
            [int]$entry.initial_ai_phase -lt 0 -or
            [int]$entry.initial_ai_phase -gt 59 -or
            [int]$entry.initial_reaction_limit -lt 40 -or
            [int]$entry.initial_reaction_limit -gt 79
        ) {
            throw "Invalid active actor startup state in $levelId."
        }
        $actorByRuntimeIndex[$runtimeIndex] = $entry
    }
    foreach ($runtimeActor in $runtimeActors) {
        $runtimeIndex = [int]$runtimeActor.Value.runtime_index
        if (
            -not $actorByRuntimeIndex.ContainsKey($runtimeIndex) -or
            [int]$actorByRuntimeIndex[$runtimeIndex].scene_index -ne (
                [int]$runtimeActor.Name)
        ) {
            throw "Runtime actor startup identity mismatch for $levelId."
        }
    }
    $previousGateActor = -1
    foreach ($runtimeIndexValue in @(
            $level.observation_gate_actor_indices)) {
        $runtimeIndex = [int]$runtimeIndexValue
        if (
            $runtimeIndex -le $previousGateActor -or
            -not $actorByRuntimeIndex.ContainsKey($runtimeIndex)
        ) {
            throw "Invalid observation-gate actor order for $levelId."
        }
        $previousGateActor = $runtimeIndex
        $verifiedGateActors++
    }
    $verifiedActors += $initialization.Count
}
if (
    $verifiedFirstUpdateActorOutcomes -ne 76 -or
    [int]$verifiedSemanticEffects.route_wait_limit -ne 3 -or
    [int]$verifiedSemanticEffects.pursuit_command_snapshot -ne 36 -or
    [int]$verifiedSemanticEffects.primary_candidate_scan -ne 14 -or
    [int]$verifiedSemanticEffects.blocked_retry_destination -ne 3 -or
    [int]$verifiedSemanticEffects.secondary_candidate_scan -ne 16 -or
    [int]$verifiedSemanticEffects.secondary_search_destination -ne 4
) {
    throw 'First gameplay actor side-effect family totals mismatch.'
}

[pscustomobject]@{
    ContentProfile = [string]$baseline.content_profile
    Levels = @($baseline.levels).Count
    ActiveActorInitializations = $verifiedActors
    ObservationGateActors = $verifiedGateActors
    FirstGameplayUpdateDraws = $verifiedFirstUpdateDraws
    FirstGameplayActorOutcomes = $verifiedFirstUpdateActorOutcomes
    StartupLcgCheckpoints = 'verified'
}
