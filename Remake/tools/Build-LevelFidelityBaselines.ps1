[CmdletBinding()]
param(
    [string]$AssetsDirectory = '',
    [string]$OutputPath = '',
    [switch]$Verify
)

$ErrorActionPreference = 'Stop'
$remakeRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if ([string]::IsNullOrWhiteSpace($AssetsDirectory)) {
    $AssetsDirectory = Join-Path $remakeRoot 'LocalAssets'
}
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $remakeRoot 'game\data\level_fidelity_baselines.json'
}
$AssetsDirectory = [IO.Path]::GetFullPath($AssetsDirectory)
$OutputPath = [IO.Path]::GetFullPath($OutputPath)

$profileId = 'repository-mod-12-level-20260729'
$manifestPath = Join-Path $AssetsDirectory 'manifest.json'
$missionPath = Join-Path $remakeRoot 'game\data\missions.json'
$weaponPath = Join-Path $remakeRoot `
    'game\data\original_initial_weapon_inventory.json'
foreach ($requiredPath in @(
    $manifestPath,
    $missionPath,
    $weaponPath
)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "Required fidelity input is missing: $requiredPath"
    }
}

$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 |
    ConvertFrom-Json
$knownVersion = $manifest.source.known_version
if ($knownVersion.version_id -ne $profileId -or -not $knownVersion.is_match) {
    throw 'LocalAssets does not identify the supported stable Mod profile.'
}
$missions = @(
    (Get-Content -LiteralPath $missionPath -Raw -Encoding UTF8 |
        ConvertFrom-Json).missions
)
$weaponCatalog = Get-Content -LiteralPath $weaponPath -Raw -Encoding UTF8 |
    ConvertFrom-Json
if ($missions.Count -ne 12 -or
    $weaponCatalog.content_profile -ne $profileId) {
    throw 'Mission or player-identity catalog is not the supported 12-level profile.'
}

function Add-Count {
    param(
        [hashtable]$Table,
        [string]$Key
    )
    $Table[$Key] = 1 + [int]$Table[$Key]
}

function ConvertTo-SortedCountObject {
    param([hashtable]$Table)
    $result = [ordered]@{}
    foreach ($key in @($Table.Keys | Sort-Object)) {
        $result[[string]$key] = [int]$Table[$key]
    }
    return $result
}

function Get-TextSha256 {
    param([string[]]$Lines)
    $utf8 = [Text.UTF8Encoding]::new($false)
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = $utf8.GetBytes(($Lines -join "`n"))
        return ([BitConverter]::ToString(
                $algorithm.ComputeHash($bytes)
            )).Replace('-', '')
    }
    finally {
        $algorithm.Dispose()
    }
}

function Add-SceneRole {
    param(
        [hashtable]$RolesByScene,
        [int]$SceneIndex,
        [string]$Role
    )
    $key = [string]$SceneIndex
    if (-not $RolesByScene.ContainsKey($key)) {
        $RolesByScene[$key] = [Collections.Generic.List[string]]::new()
    }
    if (-not $RolesByScene[$key].Contains($Role)) {
        $RolesByScene[$key].Add($Role)
    }
}

function ConvertTo-CanonicalJson {
    param([AllowNull()]$Value)
    if ($null -eq $Value) {
        return 'null'
    }
    if ($Value -is [string] -or $Value -is [char]) {
        return ConvertTo-Json -InputObject ([string]$Value) -Compress
    }
    if ($Value -is [bool]) {
        return $(if ($Value) { 'true' } else { 'false' })
    }
    if ($Value -is [Collections.IDictionary]) {
        $parts = [Collections.Generic.List[string]]::new()
        foreach ($key in @($Value.Keys | ForEach-Object { [string]$_ } |
                Sort-Object)) {
            $parts.Add(
                (ConvertTo-CanonicalJson $key) + ':' +
                (ConvertTo-CanonicalJson $Value[$key])
            )
        }
        return '{' + ($parts -join ',') + '}'
    }
    if ($Value -is [Management.Automation.PSCustomObject]) {
        $parts = [Collections.Generic.List[string]]::new()
        foreach ($property in @($Value.PSObject.Properties |
                Sort-Object Name)) {
            $parts.Add(
                (ConvertTo-CanonicalJson $property.Name) + ':' +
                (ConvertTo-CanonicalJson $property.Value)
            )
        }
        return '{' + ($parts -join ',') + '}'
    }
    if ($Value -is [Collections.IEnumerable]) {
        $parts = [Collections.Generic.List[string]]::new()
        foreach ($item in $Value) {
            $parts.Add((ConvertTo-CanonicalJson $item))
        }
        return '[' + ($parts -join ',') + ']'
    }
    if ($Value -is [IFormattable]) {
        return $Value.ToString(
            $null,
            [Globalization.CultureInfo]::InvariantCulture
        )
    }
    return ConvertTo-Json -InputObject ([string]$Value) -Compress
}

$sourceFilesByName = @{}
foreach ($sourceFile in @($knownVersion.files)) {
    $sourceFilesByName[[string]$sourceFile.name] = $sourceFile
}
$worldPickupIds = @(982, 983, 984, 986, 987, 988, 990, 993, 998, 999, 1003)
$levels = [Collections.Generic.List[object]]::new()
$totalEntities = 0
$totalKeyEntities = 0

for ($levelIndex = 0; $levelIndex -lt 12; $levelIndex++) {
    $levelId = 'm{0:D3}' -f $levelIndex
    $levelDirectory = Join-Path (
        Join-Path $AssetsDirectory 'converted\levels'
    ) $levelId
    $levelPath = Join-Path $levelDirectory 'level.json'
    if (-not (Test-Path -LiteralPath $levelPath -PathType Leaf)) {
        throw "Converted level is missing: $levelPath"
    }
    $level = Get-Content -LiteralPath $levelPath -Raw -Encoding UTF8 |
        ConvertFrom-Json
    $mission = @($missions | Where-Object id -eq $levelId)
    if ($mission.Count -ne 1) {
        throw "Mission catalog does not contain exactly one $levelId entry."
    }
    $mission = $mission[0]
    $levelPlayersProperty = $weaponCatalog.levels.PSObject.Properties[$levelId]
    if ($null -eq $levelPlayersProperty) {
        throw "Player identity catalog has no $levelId entry."
    }
    $players = @($levelPlayersProperty.Value.players)

    $entitiesByScene = @{}
    $factionCounts = @{}
    $queueCounts = @{'0' = 0; '1' = 0; '2' = 0; '3' = 0}
    $enemyAttackCounts = @{}
    $enemyHitPointCounts = @{}
    $worldPickupCounts = @{}
    $enemyCount = 0
    $enemyPatrolCount = 0
    $enemySpecialSensorCount = 0
    $entitySignatureLines = [Collections.Generic.List[string]]::new()
    foreach ($entity in @($level.entities | Sort-Object {
                [int]$_.scene_index
            })) {
        $sceneIndex = [int]$entity.scene_index
        $entitiesByScene[[string]$sceneIndex] = $entity
        Add-Count $factionCounts ([string][int]$entity.faction_id)
        $headers = @($entity.database_header_values)
        $queue = $(if ($headers.Count -gt 0) {
                [int]$headers[0]
            } else {
                0
            })
        if (-not $queueCounts.ContainsKey([string]$queue)) {
            throw "$levelId scene $sceneIndex uses invalid draw queue $queue."
        }
        Add-Count $queueCounts ([string]$queue)
        $databaseEntryId = [int]$entity.database_entry_id
        $specialSensorMode = $false
        if ($null -ne $entity.PSObject.Properties['special_sensor_mode']) {
            $specialSensorMode = [bool]$entity.special_sensor_mode
        }
        elseif ($null -ne $entity.PSObject.Properties['special_sensor']) {
            $specialSensorMode = [int]$entity.special_sensor -ne 0
        }
        if ($worldPickupIds -contains $databaseEntryId) {
            Add-Count $worldPickupCounts ([string]$databaseEntryId)
        }
        if ([int]$entity.faction_id -eq 1) {
            $enemyCount++
            if (@($entity.patrol_waypoints).Count -gt 0) {
                $enemyPatrolCount++
            }
            if ($specialSensorMode) {
                $enemySpecialSensorCount++
            }
            Add-Count $enemyAttackCounts (
                [string][int]$entity.default_attack_type
            )
            Add-Count $enemyHitPointCounts (
                [string][int]$entity.current_hit_points
            )
        }
        $waypoints = @(
            $entity.patrol_waypoints | ForEach-Object {
                '{0}:{1}' -f [int]$_.x, [int]$_.y
            }
        )
        $signature = [ordered]@{
            scene_index = $sceneIndex
            database_entry_id = $databaseEntryId
            resource_name = [string]$entity.resource_name
            display_name = [string]$entity.display_name
            category_name = [string]$entity.category_name
            x = [int]$entity.x
            y = [int]$entity.y
            reference_x = [int]$entity.reference_x
            reference_y = [int]$entity.reference_y
            database_header_values = @($headers | ForEach-Object { [int]$_ })
            faction_id = [int]$entity.faction_id
            direction_index = [int]$entity.direction_index
            death_state = [int]$entity.death_state
            crawl_state = [int]$entity.crawl_state
            current_hit_points = [int]$entity.current_hit_points
            default_attack_type = [int]$entity.default_attack_type
            special_sensor_mode = $specialSensorMode
            patrol_current_waypoint_index = [int]$entity.patrol_current_waypoint_index
            patrol_persistent_flag = [int]$entity.patrol_persistent_flag
            patrol_waypoints = $waypoints
        }
        $entitySignatureLines.Add(
            ($signature | ConvertTo-Json -Compress -Depth 8)
        )
    }

    $anchorCounts = @{}
    $anchorSignatureLines = [Collections.Generic.List[string]]::new()
    $rolesByScene = @{}
    foreach ($anchor in @($level.task_anchors | Sort-Object {
                [int]$_.scene_index
            })) {
        Add-Count $anchorCounts ([string]$anchor.kind)
        Add-SceneRole $rolesByScene ([int]$anchor.scene_index) (
            'anchor:' + [string]$anchor.kind
        )
        $anchorSignatureLines.Add(
            (([ordered]@{
                scene_index = [int]$anchor.scene_index
                database_entry_id = [int]$anchor.database_entry_id
                kind = [string]$anchor.kind
                x = [int]$anchor.x
                y = [int]$anchor.y
                reference_x = [int]$anchor.reference_x
                reference_y = [int]$anchor.reference_y
            }) | ConvertTo-Json -Compress))
    }
    foreach ($binding in @($mission.scene_bindings.PSObject.Properties)) {
        foreach ($sceneValue in @($binding.Value)) {
            Add-SceneRole $rolesByScene ([int]$sceneValue) (
                'binding:' + [string]$binding.Name
            )
        }
    }
    foreach ($player in $players) {
        Add-SceneRole $rolesByScene ([int]$player.scene_index) (
            'player:' + [string]$player.display_name
        )
    }

    $keyEntities = [Collections.Generic.List[object]]::new()
    foreach ($sceneKey in @($rolesByScene.Keys |
            Sort-Object { [int]$_ })) {
        if (-not $entitiesByScene.ContainsKey($sceneKey)) {
            throw "$levelId key role references missing scene $sceneKey."
        }
        $entity = $entitiesByScene[$sceneKey]
        $headers = @($entity.database_header_values)
        $keyEntities.Add([ordered]@{
            scene_index = [int]$entity.scene_index
            roles = @($rolesByScene[$sceneKey] | Sort-Object)
            database_entry_id = [int]$entity.database_entry_id
            display_name = [string]$entity.display_name
            faction_id = [int]$entity.faction_id
            default_attack_type = [int]$entity.default_attack_type
            draw_queue = $(if ($headers.Count -gt 0) {
                    [int]$headers[0]
                } else {
                    0
                })
            x = [int]$entity.x
            y = [int]$entity.y
            reference_x = [int]$entity.reference_x
            reference_y = [int]$entity.reference_y
        })
    }

    $terrainPath = Join-Path $levelDirectory ([string]$level.terrain_image)
    $navigationPath = Join-Path $levelDirectory (
        [string]$level.navigation.relative_path
    )
    foreach ($artifactPath in @($terrainPath, $navigationPath)) {
        if (-not (Test-Path -LiteralPath $artifactPath -PathType Leaf)) {
            throw "Converted level artifact is missing: $artifactPath"
        }
    }
    $sourceVwfName = '1937{0}.vwf' -f $levelId
    if (-not $sourceFilesByName.ContainsKey($sourceVwfName)) {
        throw "Stable profile has no source hash for $sourceVwfName."
    }
    $levelBaseline = [ordered]@{
        id = $levelId
        number = [int]$mission.number
        title = [string]$mission.title
        source_vwf_sha256 = [string](
            $sourceFilesByName[$sourceVwfName].actual_sha256
        )
        world_size = [ordered]@{
            width = [int]$level.world_size.width
            height = [int]$level.world_size.height
        }
        navigation = [ordered]@{
            width = [int]$level.navigation.width
            height = [int]$level.navigation.height
            cell_width = [int]$level.navigation.cell_width
            cell_height = [int]$level.navigation.cell_height
        }
        entity_count = @($level.entities).Count
        faction_counts = ConvertTo-SortedCountObject $factionCounts
        draw_queue_counts = ConvertTo-SortedCountObject $queueCounts
        enemy = [ordered]@{
            count = $enemyCount
            nonempty_patrol_count = $enemyPatrolCount
            attack_type_counts = ConvertTo-SortedCountObject $enemyAttackCounts
            hit_point_counts = ConvertTo-SortedCountObject $enemyHitPointCounts
            special_sensor_count = $enemySpecialSensorCount
        }
        world_interactable_counts = (
            ConvertTo-SortedCountObject $worldPickupCounts
        )
        task_anchor_counts = ConvertTo-SortedCountObject $anchorCounts
        converted_artifacts = [ordered]@{
            terrain_sha256 = (
                Get-FileHash -LiteralPath $terrainPath -Algorithm SHA256
            ).Hash
            navigation_sha256 = (
                Get-FileHash -LiteralPath $navigationPath -Algorithm SHA256
            ).Hash
            entity_semantics_sha256 = Get-TextSha256 $entitySignatureLines
            task_anchor_semantics_sha256 = Get-TextSha256 $anchorSignatureLines
        }
        key_entities = @($keyEntities)
    }
    if ($levelId -eq 'm000') {
        $farmlandBases = @(
            $level.entities | Where-Object {
                [int]$_.database_entry_id -in @(336, 337)
            }
        )
        $rice = @(
            $level.entities | Where-Object {
                [int]$_.database_entry_id -eq 335
            }
        )
        $levelBaseline['landscape'] = [ordered]@{
            farmland_base_database_ids = @(336, 337)
            farmland_base_count = $farmlandBases.Count
            farmland_base_queue = 1
            rice_database_id = 335
            rice_count = $rice.Count
            rice_queue = 0
        }
    }
    $levels.Add($levelBaseline)
    $totalEntities += @($level.entities).Count
    $totalKeyEntities += $keyEntities.Count
}

$result = [ordered]@{
    schema_version = 2
    content_profile = $profileId
    source_status = 'recovered_from_supported_mod_vwf_dbl'
    source_database_sha256 = [string](
        $sourceFilesByName['1937Database.dbl'].actual_sha256
    )
    level_count = $levels.Count
    levels = @($levels)
    summary = [ordered]@{
        entity_count = $totalEntities
        key_entity_count = $totalKeyEntities
    }
}

if ($Verify) {
    if (-not (Test-Path -LiteralPath $OutputPath -PathType Leaf)) {
        throw "Committed level-fidelity baseline is missing: $OutputPath"
    }
    $committed = Get-Content -LiteralPath $OutputPath -Raw -Encoding UTF8 |
        ConvertFrom-Json
    if ((ConvertTo-CanonicalJson $committed) -ne
        (ConvertTo-CanonicalJson $result)) {
        throw (
            'Committed level-fidelity baseline differs from the supported ' +
            'LocalAssets conversion. Regenerate it with ' +
            'Build-LevelFidelityBaselines.ps1 and review the diff.')
    }
    Write-Host (
        "Twelve-level fidelity baseline passed: {0} entities, {1} key scenes." -f
        $totalEntities,
        $totalKeyEntities
    )
    exit 0
}

$outputDirectory = [IO.Path]::GetDirectoryName($OutputPath)
[IO.Directory]::CreateDirectory($outputDirectory) | Out-Null
$json = $result | ConvertTo-Json -Depth 20
[IO.File]::WriteAllText(
    $OutputPath,
    $json + [Environment]::NewLine,
    [Text.UTF8Encoding]::new($false)
)
Write-Host "Wrote twelve-level fidelity baseline to $OutputPath"
