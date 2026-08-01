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
    [int]$baseline.schema_version -ne 1 -or
    [string]$baseline.catalog_id -ne (
        'original-crt-random-startup-v1') -or
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
if (@($baseline.levels).Count -ne 12) {
    throw 'The CRT random startup baseline must contain exactly 12 levels.'
}

$verifiedActors = 0
$verifiedGateActors = 0
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

[pscustomobject]@{
    ContentProfile = [string]$baseline.content_profile
    Levels = @($baseline.levels).Count
    ActiveActorInitializations = $verifiedActors
    ObservationGateActors = $verifiedGateActors
    StartupLcgCheckpoints = 'verified'
}
