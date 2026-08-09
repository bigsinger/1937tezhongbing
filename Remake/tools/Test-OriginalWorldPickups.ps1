[CmdletBinding()]
param(
    [string]$BaselinePath = '',

    [string]$GameDataPath = '',

    [string]$DatabasePath = '',

    [string]$ConvertedLevelsRoot = ''
)

$ErrorActionPreference = 'Stop'
$remakeRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $remakeRoot '..'))
if ([string]::IsNullOrWhiteSpace($BaselinePath)) {
    $BaselinePath = Join-Path `
        $remakeRoot `
        'validation\baselines\mod\world-pickups-v1.json'
}
if ([string]::IsNullOrWhiteSpace($GameDataPath)) {
    $GameDataPath = Join-Path $remakeRoot 'game\data\world_pickups.json'
}
if ([string]::IsNullOrWhiteSpace($DatabasePath)) {
    $DatabasePath = Join-Path $repositoryRoot 'Mod\1937Database.dbl'
}
if ([string]::IsNullOrWhiteSpace($ConvertedLevelsRoot)) {
    $ConvertedLevelsRoot = Join-Path `
        $remakeRoot `
        'LocalAssets\converted\levels'
}

function Read-Json {
    param([Parameter(Mandatory = $true)][string]$LiteralPath)

    if (-not (Test-Path -LiteralPath $LiteralPath -PathType Leaf)) {
        throw "Required world-pickup artifact is missing: $LiteralPath"
    }
    return Get-Content -LiteralPath $LiteralPath -Raw -Encoding UTF8 |
        ConvertFrom-Json
}

$baseline = Read-Json -LiteralPath $BaselinePath
$gameData = Read-Json -LiteralPath $GameDataPath
if ([int]$baseline.schema_version -ne 1 -or
    [string]$baseline.catalog_id -ne 'original-world-pickups-v1' -or
    [string]$baseline.content_profile -ne
        'repository-mod-12-level-20260729') {
    throw 'Original world-pickup baseline identity is invalid.'
}
if ([int]$gameData.schema_version -ne 3 -or
    [int]$gameData.entity_count -ne 11) {
    throw 'Product world-pickup catalog schema is invalid.'
}

$expectedDatabaseIds = @(982, 983, 984, 986, 987, 988, 990, 993, 998, 999)
$actualDatabaseIds = @($baseline.pickup_grants |
    ForEach-Object { [int]$_.database_entry_id })
if (@(Compare-Object $expectedDatabaseIds $actualDatabaseIds).Count -ne 0) {
    throw 'World-pickup baseline has an unexpected DBL identity set.'
}

foreach ($row in @($baseline.pickup_grants)) {
    $databaseEntryId = [int]$row.database_entry_id
    $profile = $gameData.entities."$databaseEntryId"
    if ($null -eq $profile) {
        throw "Product catalog is missing DBL $databaseEntryId."
    }
    $grant = $profile.grant
    if ([string]$profile.original_display_name -cne
            [string]$row.display_name -or
        [string]$profile.behavior -ne 'field_pickup' -or
        [string]$grant.kind -ne 'original_inventory_item' -or
        [int]$grant.item_id -ne [int]$row.item_id -or
        [string]$grant.container -ne [string]$row.container -or
        [int]$grant.quantity -ne [int]$row.quantity -or
        [int]$grant.quantity_mode -ne [int]$row.quantity_mode) {
        throw "Product grant for DBL $databaseEntryId differs from MOD evidence."
    }
    if ([string]$profile.source_status.item_id -ne
            'recovered_dbl_header_2' -or
        [string]$profile.source_status.container -ne
            'recovered_sub_45AE10' -or
        [string]$profile.source_status.quantity_mode -ne
            'recovered_sub_45AE10' -or
        [string]$profile.source_status.grant_quantity -ne
            'recovered_sub_453F70' -or
        [string]$profile.source_status.interaction_radius -ne
            'recovered_sub_456AB0_adjacent_navigation_cells') {
        throw "Product source labels for DBL $databaseEntryId are inaccurate."
    }
}

$barrelEvidence = @($baseline.explosive_props)[0]
$barrel = $gameData.entities.'1003'
if ([int]$barrelEvidence.database_entry_id -ne 1003 -or
    [int]$barrelEvidence.runtime_actor_type -ne 53 -or
    [int]$barrelEvidence.observed_instance_count -ne 35 -or
    [int]$barrelEvidence.initial_hit_points -ne 8 -or
    [int]$barrelEvidence.detonation_hit_points_sentinel -ne 8 -or
    [int]$barrelEvidence.resolved_action_index -ne 1 -or
    [int]$barrelEvidence.effect_dispatch_type -ne 5 -or
    [int]$barrelEvidence.explosion_actor_type -ne 62 -or
    [int]$barrelEvidence.blast_damage -ne 128 -or
    [int]$barrelEvidence.blast_horizontal_radius -ne 128 -or
    [int]$barrelEvidence.blast_vertical_radius -ne 64 -or
    [int]$barrelEvidence.alert_radius -ne 800 -or
    @($barrelEvidence.main_excluded_runtime_actor_types).Count -ne 1 -or
    [int]@($barrelEvidence.main_excluded_runtime_actor_types)[0] -ne 85 -or
    [int]$barrel.runtime_actor_type -ne 53 -or
    [int]$barrel.initial_hit_points -ne 8 -or
    [int]$barrel.detonation_hit_points_sentinel -ne 8 -or
    [int]$barrel.resolved_action_index -ne 1 -or
    [int]$barrel.effect_dispatch_type -ne 5 -or
    [int]$barrel.explosion_actor_type -ne 62 -or
    [string]$barrel.original_display_name -cne
        [string]$barrelEvidence.display_name -or
    [string]$barrel.source_status.runtime_actor_type -ne
        'recovered_dbl_header_2' -or
    [string]$barrel.source_status.initial_hit_points -ne
        'recovered_35_vwf_actor_states' -or
    [string]$barrel.source_status.detonation_hit_points_sentinel -ne
        'recovered_sub_4551B0' -or
    [string]$barrel.source_status.explosion_actor_type -ne
        'recovered_sub_4656C0_case_5' -or
    [string]$barrel.source_status.explosion_profile -ne
        'recovered_sub_4554A0') {
    throw 'Gasoline-barrel actor-53/actor-62 evidence differs from product data.'
}
if ($null -ne $gameData.PSObject.Properties['deployables']) {
    throw 'Retired generic LandMine defaults returned to product data.'
}

if (Test-Path -LiteralPath $ConvertedLevelsRoot -PathType Container) {
    $observedBarrels = [Collections.Generic.List[object]]::new()
    foreach ($levelNumber in 0..11) {
        $levelId = 'm{0:D3}' -f $levelNumber
        $levelPath = Join-Path $ConvertedLevelsRoot "$levelId\level.json"
        $level = Read-Json -LiteralPath $levelPath
        foreach ($entity in @($level.entities)) {
            if ([int]$entity.database_entry_id -ne 1003) {
                continue
            }
            $header = @($entity.database_header_values)
            if ($header.Count -lt 3 -or
                [int]$header[2] -ne 53 -or
                [int]$entity.current_hit_points -ne 8) {
                throw "$levelId contains an invalid actor-53 gasoline barrel."
            }
            $observedBarrels.Add([pscustomobject]@{
                level_id = $levelId
                scene_index = [int]$entity.scene_index
            })
        }
    }
    $observedLevels = @($observedBarrels |
        Select-Object -ExpandProperty level_id -Unique)
    $expectedLevels = @($barrelEvidence.observed_level_ids |
        ForEach-Object { [string]$_ })
    if ($observedBarrels.Count -ne
            [int]$barrelEvidence.observed_instance_count -or
        @(Compare-Object $expectedLevels $observedLevels).Count -ne 0) {
        throw 'Converted twelve-level gasoline-barrel population differs from the evidence baseline.'
    }
}

if ((Test-Path -LiteralPath $DatabasePath -PathType Leaf) -and
    (Get-Item -LiteralPath $DatabasePath).Length -gt 1000000) {
    $databaseSha256 = (
        Get-FileHash -LiteralPath $DatabasePath -Algorithm SHA256
    ).Hash
    if ($databaseSha256 -cne [string]$baseline.source.database_sha256) {
        throw 'Materialized MOD DBL hash differs from the pickup baseline.'
    }
}

Write-Host (
    'Original world-pickup parity passed: 10 exact grants, ' +
    '35 actor-53 gasoline barrels, exact actor-62 explosion semantics, ' +
    'actor-local containers, recovered adjacent-cell completion range, ' +
    'and no generic LandMine defaults.')
