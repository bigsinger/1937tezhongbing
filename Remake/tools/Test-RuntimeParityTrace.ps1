[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$remakeRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $remakeRoot '..'))
$schemaPath = Join-Path $repositoryRoot `
    'SDK\schemas\runtime-parity-trace-v1.schema.json'
$compareScript = Join-Path $PSScriptRoot `
    'Compare-RuntimeParityTrace.ps1'
$contactCompareScript = Join-Path $PSScriptRoot `
    'Compare-NaturalContactParity.ps1'
$nativeFailureCompareScript = Join-Path $PSScriptRoot `
    'Compare-NativeMissionFailureParity.ps1'
$inventoryCompareScript = Join-Path $PSScriptRoot `
    'Compare-InventoryParityTrace.ps1'
$baselinePath = Join-Path $remakeRoot `
    'validation\baselines\mod\m000-basic-movement-v1.json'
$obstacleBaselinePath = Join-Path $remakeRoot `
    'validation\baselines\mod\m000-obstacle-route-v1.json'
$movementBaselineDefinitions = @(
    [pscustomobject]@{ level = 0; scene = 1436; out_x = 9; out_y = 7; back_x = 1; back_y = 1 },
    [pscustomobject]@{ level = 1; scene = 1993; out_x = 112; out_y = 248; back_x = 125; back_y = 254 },
    [pscustomobject]@{ level = 2; scene = 886; out_x = 1; out_y = 107; back_x = 13; back_y = 118 },
    [pscustomobject]@{ level = 3; scene = 1150; out_x = 23; out_y = 173; back_x = 10; back_y = 187 },
    [pscustomobject]@{ level = 4; scene = 2629; out_x = 54; out_y = 8; back_x = 54; back_y = 12 },
    [pscustomobject]@{ level = 5; scene = 663; out_x = 9; out_y = 194; back_x = 1; back_y = 192 },
    [pscustomobject]@{ level = 6; scene = 1458; out_x = 12; out_y = 13; back_x = 23; back_y = 9 },
    [pscustomobject]@{ level = 7; scene = 2325; out_x = 28; out_y = 41; back_x = 31; back_y = 53 },
    [pscustomobject]@{ level = 8; scene = 753; out_x = 13; out_y = 5; back_x = 1; back_y = 23 },
    [pscustomobject]@{ level = 9; scene = 1709; out_x = 7; out_y = 78; back_x = 0; back_y = 78 },
    [pscustomobject]@{ level = 10; scene = 1590; out_x = 8; out_y = 10; back_x = 1; back_y = 9 },
    [pscustomobject]@{ level = 11; scene = 1176; out_x = 80; out_y = 5; back_x = 96; back_y = 7 }
)
$movementBaselinePaths = @(
    $movementBaselineDefinitions | ForEach-Object {
        Join-Path $remakeRoot (
            'validation\baselines\mod\m{0:D3}-player-obstacle-route-v1.json' -f
            [int]$_.level)
    })
$patrolBaselinePaths = @(
    0..11 | ForEach-Object {
        Join-Path $remakeRoot (
            'validation\baselines\mod\m{0:D3}-enemy-patrol-v1.json' -f $_)
    })
$patrolBaselinePath = $patrolBaselinePaths[0]
$contactBaselinePath = Join-Path $remakeRoot `
    'validation\baselines\mod\m000-natural-contact-v1.json'
$runtimeActorCatalogPath = Join-Path $remakeRoot `
    'game\data\original_runtime_actor_catalog.json'
$nativeAlertBaselinePath = Join-Path $remakeRoot `
    'validation\baselines\mod\m000-native-alert-command-v1.json'
$nativeFailureSceneIndices = @(
    1436, 1994, 886, 1150, 2629, 663,
    1458, 2325, 753, 1709, 1590, 1176
)
$nativeFailureBaselinePaths = @(
    0..11 | ForEach-Object {
        Join-Path $remakeRoot (
            'validation\baselines\mod\' +
            ('m{0:D3}-native-required-player-failure-v1.json' -f $_))
    })
$nativeFailureBaselinePath = $nativeFailureBaselinePaths[0]
$minePickupBaselinePath = Join-Path $remakeRoot `
    'validation\baselines\mod\m001-mine-pickup-inventory-v1.json'
$pistolAttackBaselinePath = Join-Path $remakeRoot `
    'validation\baselines\mod\m000-pistol-attack-inventory-v1.json'
$rifleAttackBaselinePath = Join-Path $remakeRoot `
    'validation\baselines\mod\m010-rifle-attack-inventory-v1.json'
$machineGunAttackBaselinePath = Join-Path $remakeRoot `
    'validation\baselines\mod\m010-machine-gun-attack-inventory-v1.json'
$dartAttackBaselinePath = Join-Path $remakeRoot `
    'validation\baselines\mod\m004-dart-attack-inventory-v1.json'
$specialAttentionAttackBaselinePath = Join-Path $remakeRoot `
    'validation\baselines\mod\m007-special-attention-attack-inventory-v1.json'
$daggerAttackBaselinePath = Join-Path $remakeRoot `
    'validation\baselines\mod\m010-dagger-attack-inventory-v1.json'
$broadswordAttackBaselinePath = Join-Path $remakeRoot `
    'validation\baselines\mod\m010-broadsword-attack-inventory-v1.json'
$grenadeAttackBaselinePath = Join-Path $remakeRoot `
    'validation\baselines\mod\m010-grenade-attack-inventory-v1.json'
$mineDeployBaselinePath = Join-Path $remakeRoot `
    'validation\baselines\mod\m010-mine-deploy-inventory-v1.json'
$explosiveDeployBaselinePath = Join-Path $remakeRoot `
    'validation\baselines\mod\m010-explosive-deploy-inventory-v1.json'

$schema = Get-Content -LiteralPath $schemaPath -Raw -Encoding UTF8 |
    ConvertFrom-Json
if ($schema.title -ne '1937 MOD and Remake runtime parity trace' -or
    $null -eq $schema.'$defs'.checkpoint -or
    $null -eq $schema.'$defs'.actor) {
    throw 'Runtime parity trace JSON schema is incomplete.'
}
$baseline = Get-Content -LiteralPath $baselinePath -Raw -Encoding UTF8 |
    ConvertFrom-Json
if ($baseline.runtime -ne 'mod' -or
    $baseline.content_profile -ne 'repository-mod-12-level-20260729' -or
    @($baseline.checkpoints).Count -ne 6 -or
    @($baseline.checkpoints[0].actors).Count -ne 1 -or
    [int]$baseline.checkpoints[0].actors[0].scene_index -ne 1436 -or
    [int]$baseline.checkpoints[0].actors[0].database_entry_id -ne 924 -or
    $baseline.metadata.input_isolation -ne
    'window-message-to-process-local-DirectInput') {
    throw 'The checked-in m000 stable-MOD baseline identity is invalid.'
}
$obstacleBaseline = Get-Content -LiteralPath $obstacleBaselinePath `
    -Raw -Encoding UTF8 | ConvertFrom-Json
if ($obstacleBaseline.runtime -ne 'mod' -or
    $obstacleBaseline.scenario.id -ne 'm000-obstacle-route-v1' -or
    @($obstacleBaseline.checkpoints).Count -ne 6 -or
    @($obstacleBaseline.checkpoints[3].tags.observed_positions).Count -lt 10 -or
    [int]$obstacleBaseline.checkpoints[0].actors[0].scene_index -ne 1436) {
    throw 'The checked-in m000 obstacle-route baseline is invalid.'
}
$movementCheckpointIds = @(
    'gameplay_ready',
    'player_selected',
    'move_outbound_commanded',
    'move_outbound_observed',
    'move_return_commanded',
    'move_return_observed'
)
for ($movementIndex = 0;
    $movementIndex -lt $movementBaselineDefinitions.Count;
    $movementIndex++) {
    $movementDefinition = $movementBaselineDefinitions[$movementIndex]
    $levelId = 'm{0:D3}' -f [int]$movementDefinition.level
    $movementBaseline = Get-Content `
        -LiteralPath $movementBaselinePaths[$movementIndex] `
        -Raw -Encoding UTF8 | ConvertFrom-Json
    $auditedScene = [int]$movementDefinition.scene
    $auditedActors = @(
        foreach ($checkpoint in @($movementBaseline.checkpoints)) {
            @(
                $checkpoint.actors |
                    Where-Object {
                        [int]$_.scene_index -eq $auditedScene
                    }
            )[0]
        }
    )
    $expectedOutbound = @(
        ([int]$movementDefinition.out_x * 32 + 16),
        ([int]$movementDefinition.out_y * 16 + 8)
    )
    $expectedReturn = @(
        ([int]$movementDefinition.back_x * 32 + 16),
        ([int]$movementDefinition.back_y * 16 + 8)
    )
    if ($movementBaseline.runtime -ne 'mod' -or
        $movementBaseline.content_profile -ne
            'repository-mod-12-level-20260729' -or
        $movementBaseline.level.id -ne $levelId -or
        $movementBaseline.scenario.id -ne
            "$levelId-player-obstacle-route-v1" -or
        $movementBaseline.metadata.input_isolation -ne
            'window-message-to-process-local-DirectInput' -or
        @($movementBaseline.checkpoints).Count -ne 6 -or
        @(Compare-Object `
            $movementCheckpointIds `
            @($movementBaseline.checkpoints.id)).Count -ne 0 -or
        @($auditedActors | Where-Object { $null -eq $_ }).Count -ne 0 -or
        @($auditedActors | Where-Object role -ne 'player').Count -ne 0 -or
        (@($auditedActors[2].target_position) -join ',') -ne
            ($expectedOutbound -join ',') -or
        (@($auditedActors[4].target_position) -join ',') -ne
            ($expectedReturn -join ',') -or
        [double]$auditedActors[3].position[0] -eq
            [double]$auditedActors[0].position[0] -and
        [double]$auditedActors[3].position[1] -eq
            [double]$auditedActors[0].position[1]) {
        throw (
            "The checked-in $levelId player obstacle-route baseline is invalid.")
    }
}
$patrolCheckpointIds = @(
    'patrol_interval_1_commanded',
    'patrol_interval_1_observed',
    'patrol_interval_2_commanded',
    'patrol_interval_2_observed'
)
$expectedPatrolActorCounts = @(54, 70, 28, 48, 96, 79, 31, 74, 26, 43, 74, 33)
$patrolBaselineDocuments = [Collections.Generic.List[object]]::new()
$totalPatrolActorCount = 0
for ($levelIndex = 0; $levelIndex -lt 12; $levelIndex++) {
    $levelId = 'm{0:D3}' -f $levelIndex
    $patrolBaseline = Get-Content `
        -LiteralPath $patrolBaselinePaths[$levelIndex] `
        -Raw -Encoding UTF8 | ConvertFrom-Json
    $expectedActorCount = $expectedPatrolActorCounts[$levelIndex]
    if ($patrolBaseline.runtime -ne 'mod' -or
        $patrolBaseline.scenario.id -ne "$levelId-enemy-patrol-v1" -or
        @($patrolBaseline.checkpoints).Count -ne 4 -or
        @(Compare-Object `
            $patrolCheckpointIds `
            @($patrolBaseline.checkpoints.id)).Count -ne 0 -or
        @($patrolBaseline.checkpoints |
            Where-Object {
                @($_.actors).Count -ne $expectedActorCount
            }).Count -ne 0 -or
        @($patrolBaseline.checkpoints[0].actors.scene_index |
            Select-Object -Unique).Count -ne $expectedActorCount -or
        @($patrolBaseline.checkpoints[0].actors |
            Where-Object role -ne 'enemy').Count -ne 0) {
        throw "The checked-in $levelId enemy-patrol baseline is invalid."
    }
    $patrolBaselineDocuments.Add($patrolBaseline)
    $totalPatrolActorCount += $expectedActorCount
}
if ($totalPatrolActorCount -ne 656) {
    throw 'The twelve-level patrol baseline roster is incomplete.'
}
$contactBaseline = Get-Content -LiteralPath $contactBaselinePath `
    -Raw -Encoding UTF8 | ConvertFrom-Json
$contactCheckpointIds = @(
    'contact_ready',
    'player_selected',
    'move_outbound_commanded',
    'move_outbound_observed',
    'move_return_commanded',
    'move_return_observed',
    'contact_settled'
)
$contactFinalActor = @(
    $contactBaseline.checkpoints[-1].actors |
        Where-Object { [int]$_.scene_index -eq 1598 }
)[0]
$contactPlayerHitPointSequence = @(
    $contactBaseline.checkpoints |
        ForEach-Object {
            [int](@(
                $_.actors |
                    Where-Object { [int]$_.scene_index -eq 1436 }
            )[0].hit_points.current)
        }
)
if ($contactBaseline.runtime -ne 'mod' -or
    $contactBaseline.scenario.id -ne 'm000-natural-contact-v1' -or
    @($contactBaseline.checkpoints).Count -ne 7 -or
    @(Compare-Object `
        $contactCheckpointIds `
        @($contactBaseline.checkpoints.id)).Count -ne 0 -or
    @($contactBaseline.checkpoints |
        Where-Object { @($_.actors).Count -ne 54 }).Count -ne 0 -or
    $null -eq $contactFinalActor -or
    [int]$contactFinalActor.native.contact_state -ne 1 -or
    [int]$contactFinalActor.native.target_lost -ne 0 -or
    [int]$contactFinalActor.native.interest_scene_index -ne 1436 -or
    [int]$contactFinalActor.native.target_scene_index -ne 1436 -or
    [int]$contactFinalActor.hit_points.current -ne 8 -or
    [int]$contactFinalActor.hit_points.maximum -ne 8 -or
    [int]$contactFinalActor.native.default_attack_type -ne 2 -or
    ($contactPlayerHitPointSequence -join ',') -ne '8,8,8,8,8,6,4' -or
    @($contactBaseline.checkpoints[0].actors |
        Where-Object {
            $null -eq $_.hit_points -or
            $null -eq $_.native.default_attack_type
        }).Count -ne 0) {
    throw 'The checked-in m000 natural-contact baseline is invalid.'
}
$nativeAlertBaseline = Get-Content -LiteralPath $nativeAlertBaselinePath `
    -Raw -Encoding UTF8 | ConvertFrom-Json
$nativeAlertRecipients = @(
    $nativeAlertBaseline.first_enemy_gunshot.recipients
)
if ($nativeAlertBaseline.scenario.id -ne
        'm000-native-alert-command-v1' -or
    $nativeAlertBaseline.first_enemy_gunshot.call_site_rva -ne
        '0x0005DF71' -or
    [int]$nativeAlertBaseline.first_enemy_gunshot.source.scene_index -ne
        1598 -or
    [int]$nativeAlertBaseline.first_enemy_gunshot.source.runtime_index -ne
        113 -or
    (@($nativeAlertRecipients.scene_index) -join ',') -ne
        '1433,1492' -or
    @($nativeAlertRecipients |
        Where-Object {
            [int]$_.goal_kind -ne 1 -or
            [int]$_.command_variant -ne 1 -or
            [int]$_.command_pending -ne 1 -or
            [int]$_.movement_active -ne 1 -or
            [string]$_.target_address -ne '0x00000000'
        }).Count -ne 0) {
    throw 'The checked-in m000 native alert-command evidence is invalid.'
}
if (-not (Test-Path -LiteralPath $nativeFailureCompareScript -PathType Leaf)) {
    throw 'The native mission-failure comparator is missing.'
}
$nativeFailureBaselineDocuments = [Collections.Generic.List[object]]::new()
for ($levelIndex = 0; $levelIndex -lt 12; $levelIndex++) {
    $levelId = 'm{0:D3}' -f $levelIndex
    $scenarioId = "$levelId-native-required-player-failure-v1"
    $nativeFailureBaseline = Get-Content `
        -LiteralPath $nativeFailureBaselinePaths[$levelIndex] `
        -Raw -Encoding UTF8 | ConvertFrom-Json
    $nativeFailureActive = @(
        $nativeFailureBaseline.checkpoints |
            Where-Object id -CEQ 'gameplay_active'
    )[0]
    $nativeFailureFailed = @(
        $nativeFailureBaseline.checkpoints |
            Where-Object id -CEQ 'required_player_lost'
    )[0]
    $requiredScene = $nativeFailureSceneIndices[$levelIndex]
    if ($nativeFailureBaseline.runtime -ne 'mod' -or
        $nativeFailureBaseline.content_profile -ne
            'repository-mod-12-level-20260729' -or
        $nativeFailureBaseline.level.id -ne $levelId -or
        [int]$nativeFailureBaseline.level.selector_level -ne
            ($levelIndex + 1) -or
        [int]$nativeFailureBaseline.level.engine_mission -ne
            ($levelIndex + 1) -or
        $nativeFailureBaseline.scenario.id -ne $scenarioId -or
        @($nativeFailureBaseline.checkpoints).Count -ne 2 -or
        (@($nativeFailureBaseline.checkpoints.id) -join ',') -ne
            'gameplay_active,required_player_lost' -or
        $null -eq $nativeFailureActive -or
        $null -eq $nativeFailureFailed -or
        [int]$nativeFailureActive.actor.scene_index -ne $requiredScene -or
        [int]$nativeFailureFailed.actor.scene_index -ne $requiredScene -or
        [int]$nativeFailureActive.actor.runtime_index -ne
            [int]$nativeFailureFailed.actor.runtime_index -or
        [int]$nativeFailureActive.actor.faction_id -ne 3 -or
        [int]$nativeFailureActive.actor.current_hit_points -ne 8 -or
        [int]$nativeFailureFailed.actor.current_hit_points -ne 0 -or
        [int]$nativeFailureActive.actor.dead_or_disabled -ne 0 -or
        [int]$nativeFailureFailed.actor.dead_or_disabled -ne 1 -or
        $nativeFailureActive.actor.damage_source -ne 'none' -or
        $nativeFailureFailed.actor.damage_source -ne
            'original_sub_458700' -or
        (@($nativeFailureActive.actor.position) -join ',') -ne
            (@($nativeFailureFailed.actor.position) -join ',') -or
        $nativeFailureActive.mission.status -ne 'active' -or
        $nativeFailureFailed.mission.status -ne 'failed' -or
        [int]$nativeFailureActive.mission.result_state -ne 0 -or
        [int]$nativeFailureFailed.mission.result_state -ne 2 -or
        [int]$nativeFailureActive.mission.transition_sequence -ne 0 -or
        [int]$nativeFailureFailed.mission.transition_sequence -ne 1 -or
        [long]$nativeFailureFailed.mission.evaluator_calls -le
            [long]$nativeFailureActive.mission.evaluator_calls -or
        $nativeFailureFailed.mission.semantic_failure_id -ne
            'required_character_lost' -or
        -not [bool]$nativeFailureBaseline.passed) {
        throw (
            "The checked-in $levelId native mission-failure evidence is " +
            'invalid.')
    }
    $nativeFailureBaselineDocuments.Add($nativeFailureBaseline)
}
$nativeFailureBaseline = $nativeFailureBaselineDocuments[0]

$inventoryBaselineDefinitions = @(
    [pscustomobject]@{
        path = $minePickupBaselinePath
        scenario = 'm001-mine-pickup-inventory-v1'
        checkpoint_ids = @('before_pickup', 'after_pickup')
        scene_index = 2280
        database_entry_id = 918
        item_id = 43
        before_quantity = 2
        after_quantity = 3
    },
    [pscustomobject]@{
        path = $pistolAttackBaselinePath
        scenario = 'm000-pistol-attack-inventory-v1'
        checkpoint_ids = @('before_attack', 'after_attack')
        scene_index = 1436
        database_entry_id = 924
        item_id = 36
        before_quantity = 7
        after_quantity = 6
    },
    [pscustomobject]@{
        path = $rifleAttackBaselinePath
        scenario = 'm010-rifle-attack-inventory-v1'
        checkpoint_ids = @('before_attack', 'after_attack')
        scene_index = 1589
        database_entry_id = 924
        item_id = 37
        before_quantity = 20
        after_quantity = 19
    },
    [pscustomobject]@{
        path = $machineGunAttackBaselinePath
        scenario = 'm010-machine-gun-attack-inventory-v1'
        checkpoint_ids = @('before_attack', 'after_attack')
        scene_index = 1589
        database_entry_id = 924
        item_id = 38
        before_quantity = 10
        after_quantity = 9
    },
    [pscustomobject]@{
        path = $dartAttackBaselinePath
        scenario = 'm004-dart-attack-inventory-v1'
        checkpoint_ids = @('before_attack', 'after_attack')
        scene_index = 2629
        database_entry_id = 910
        item_id = 41
        before_quantity = 20
        after_quantity = 19
    },
    [pscustomobject]@{
        path = $specialAttentionAttackBaselinePath
        scenario = 'm007-special-attention-attack-inventory-v1'
        checkpoint_ids = @('before_attack', 'after_attack')
        scene_index = 2389
        database_entry_id = 914
        item_id = 99
        before_quantity = 1
        after_quantity = 1
        expected_runtime_type = 91
        expected_faction_id = 1
        attention_target_scene_index = 2298
        attention_before = 0
        attention_after = 1
    },
    [pscustomobject]@{
        path = $daggerAttackBaselinePath
        scenario = 'm010-dagger-attack-inventory-v1'
        checkpoint_ids = @('before_attack', 'after_attack')
        scene_index = 1591
        database_entry_id = 910
        item_id = 39
        before_quantity = 1
        after_quantity = 1
        target_scene_index = 1126
        target_before_hit_points = 8
        target_after_hit_points = 0
    },
    [pscustomobject]@{
        path = $broadswordAttackBaselinePath
        scenario = 'm010-broadsword-attack-inventory-v1'
        checkpoint_ids = @('before_attack', 'after_attack')
        scene_index = 1591
        database_entry_id = 910
        item_id = 40
        before_quantity = 1
        after_quantity = 1
        target_scene_index = 1126
        target_before_hit_points = 8
        target_after_hit_points = 0
    },
    [pscustomobject]@{
        path = $grenadeAttackBaselinePath
        scenario = 'm010-grenade-attack-inventory-v1'
        checkpoint_ids = @('before_attack', 'after_attack')
        scene_index = 1589
        database_entry_id = 924
        item_id = 44
        before_quantity = 3
        after_quantity = 2
    },
    [pscustomobject]@{
        path = $mineDeployBaselinePath
        scenario = 'm010-mine-deploy-inventory-v1'
        checkpoint_ids = @('before_deploy', 'after_deploy')
        scene_index = 1590
        database_entry_id = 918
        item_id = 43
        before_quantity = 3
        after_quantity = 2
        runtime_object_delta = 1
    },
    [pscustomobject]@{
        path = $explosiveDeployBaselinePath
        scenario = 'm010-explosive-deploy-inventory-v1'
        checkpoint_ids = @('before_deploy', 'after_deploy')
        scene_index = 1590
        database_entry_id = 918
        item_id = 45
        before_quantity = 3
        after_quantity = 2
        runtime_object_delta = 1
    }
)
foreach ($inventoryDefinition in $inventoryBaselineDefinitions) {
    $inventoryBaseline = Get-Content `
        -LiteralPath $inventoryDefinition.path `
        -Raw -Encoding UTF8 | ConvertFrom-Json
    $checkpointIds = @($inventoryBaseline.checkpoints.id)
    if ($inventoryBaseline.runtime -ne 'mod' -or
        $inventoryBaseline.content_profile -ne
            'repository-mod-12-level-20260729' -or
        $inventoryBaseline.scenario.id -ne
            $inventoryDefinition.scenario -or
        @($inventoryBaseline.checkpoints).Count -ne 2 -or
        @(Compare-Object `
            @($inventoryDefinition.checkpoint_ids) `
            $checkpointIds).Count -ne 0) {
        throw (
            'The checked-in inventory baseline identity is invalid: ' +
            $inventoryDefinition.scenario)
    }
    $quantities = [Collections.Generic.List[int]]::new()
    foreach ($checkpoint in @($inventoryBaseline.checkpoints)) {
        $actor = @(
            $checkpoint.actors |
                Where-Object {
                    [int]$_.scene_index -eq
                        [int]$inventoryDefinition.scene_index
                }
        )[0]
        if ($null -eq $actor -or
            [int]$actor.database_entry_id -ne
                [int]$inventoryDefinition.database_entry_id -or
            [int]$actor.inventory.schema_version -ne 1) {
            throw (
                'The checked-in inventory actor is invalid: ' +
                $inventoryDefinition.scenario)
        }
        $entry = @(
            $actor.inventory.weapon_entries |
                Where-Object {
                    [int]$_.item_id -eq
                        [int]$inventoryDefinition.item_id
                }
        )[0]
        if ($null -eq $entry) {
            throw (
                'The checked-in inventory delta item is missing: ' +
                $inventoryDefinition.scenario)
        }
        $quantities.Add([int]$entry.quantity)
        if (
            $inventoryDefinition.PSObject.Properties.Name -contains
                'expected_runtime_type' -and
            (
                [int]$actor.native.runtime_type -ne
                    [int]$inventoryDefinition.expected_runtime_type -or
                [int]$actor.faction_id -ne
                    [int]$inventoryDefinition.expected_faction_id
            )
        ) {
            throw (
                'The checked-in transformed actor identity is invalid: ' +
                $inventoryDefinition.scenario)
        }
    }
    if ($quantities[0] -ne
            [int]$inventoryDefinition.before_quantity -or
        $quantities[1] -ne
            [int]$inventoryDefinition.after_quantity) {
        throw (
            'The checked-in inventory quantity transition is invalid: ' +
            $inventoryDefinition.scenario)
    }
    if (
        $inventoryDefinition.PSObject.Properties.Name -contains
            'runtime_object_delta'
    ) {
        $runtimeObjectDelta = (
            [int]$inventoryBaseline.checkpoints[1].world.runtime_object_count -
            [int]$inventoryBaseline.checkpoints[0].world.runtime_object_count
        )
        if ($runtimeObjectDelta -ne
            [int]$inventoryDefinition.runtime_object_delta) {
            throw (
                'The checked-in deployment runtime-object delta is invalid: ' +
                $inventoryDefinition.scenario)
        }
    }
    if (
        $inventoryDefinition.PSObject.Properties.Name -contains
            'target_scene_index'
    ) {
        $targetHitPoints = @(
            foreach ($checkpoint in @($inventoryBaseline.checkpoints)) {
                $target = @(
                    $checkpoint.actors |
                        Where-Object {
                            [int]$_.scene_index -eq
                                [int]$inventoryDefinition.target_scene_index
                        }
                )[0]
                if ($null -eq $target) {
                    throw (
                        'The checked-in durable-weapon target is missing: ' +
                        $inventoryDefinition.scenario)
                }
                [int]$target.hit_points.current
            }
        )
        if (
            $targetHitPoints[0] -ne
                [int]$inventoryDefinition.target_before_hit_points -or
            $targetHitPoints[1] -ne
                [int]$inventoryDefinition.target_after_hit_points
        ) {
            throw (
                'The checked-in durable-weapon target outcome is invalid: ' +
                $inventoryDefinition.scenario)
        }
    }
    if (
        $inventoryDefinition.PSObject.Properties.Name -contains
            'attention_target_scene_index'
    ) {
        $attentionStates = @(
            foreach ($checkpoint in @($inventoryBaseline.checkpoints)) {
                $target = @(
                    $checkpoint.actors |
                        Where-Object {
                            [int]$_.scene_index -eq
                                [int]$inventoryDefinition.attention_target_scene_index
                        }
                )[0]
                if ($null -eq $target) {
                    throw (
                        'The checked-in type-11 attention target is missing: ' +
                        $inventoryDefinition.scenario)
                }
                [int]$target.native.path_override_active
            }
        )
        if (
            $attentionStates[0] -ne
                [int]$inventoryDefinition.attention_before -or
            $attentionStates[1] -ne
                [int]$inventoryDefinition.attention_after
        ) {
            throw (
                'The checked-in type-11 attention outcome is invalid: ' +
                $inventoryDefinition.scenario)
        }
    }
}

$temporaryBase = if (Test-Path -LiteralPath 'E:\1937') {
    'E:\1937'
}
elseif (-not [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)) {
    $env:RUNNER_TEMP
}
else {
    [IO.Path]::GetTempPath()
}
$root = Join-Path $temporaryBase (
    'runtime-parity-trace-tests-' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($root) | Out-Null

try {
    $nativeFailureCandidatePath = Join-Path $root `
        'native-mission-failure-candidate.json'
    $nativeFailureCandidate = [ordered]@{
        schema_version = 1
        trace_id = 'remake-m000-native-required-player-failure-v1'
        runtime = 'remake'
        content_profile = 'repository-mod-12-level-20260729'
        level = [ordered]@{
            id = 'm000'
            selector_level = 1
            engine_mission = 1
        }
        scenario = [ordered]@{
            id = 'm000-native-required-player-failure-v1'
        }
        checkpoints = @(
            [ordered]@{
                id = 'gameplay_active'
                actors = @(
                    [ordered]@{
                        scene_index = 1436
                        faction_id = 3
                        position = @(241, 51)
                        alive = $true
                        hit_points = [ordered]@{ current = 8; maximum = 8 }
                        native = [ordered]@{
                            runtime_type = 1
                            damage_event_count = 0
                            damage_taken_total = 0
                        }
                    }
                )
                mission = [ordered]@{
                    status = 'active'
                    failure_id = ''
                }
                tags = [ordered]@{
                    original_result_state = 0
                }
            },
            [ordered]@{
                id = 'required_player_lost'
                actors = @(
                    [ordered]@{
                        scene_index = 1436
                        faction_id = 3
                        position = @(241, 51)
                        alive = $false
                        hit_points = [ordered]@{ current = 0; maximum = 8 }
                        native = [ordered]@{
                            runtime_type = 1
                            damage_event_count = 1
                            damage_taken_total = 8
                        }
                    }
                )
                mission = [ordered]@{
                    status = 'failed'
                    failure_id = 'required_character_lost'
                }
                tags = [ordered]@{
                    original_result_state = 2
                }
            }
        )
    }
    $nativeFailureCandidate | ConvertTo-Json -Depth 16 |
        Set-Content -LiteralPath $nativeFailureCandidatePath -Encoding UTF8
    $nativeFailureSelf = & $nativeFailureCompareScript `
        -ReferenceTrace $nativeFailureBaselinePath `
        -CandidateTrace $nativeFailureCandidatePath
    if (-not [bool]$nativeFailureSelf.passed -or
        [int]$nativeFailureSelf.check_count -ne 26 -or
        [int]$nativeFailureSelf.mismatches.Count -ne 0) {
        throw 'The native mission-failure comparator is not self-consistent.'
    }

    function New-Checkpoint {
        param(
            [string]$Id,
            [double]$Elapsed,
            [double]$X,
            [double]$Y,
            [int]$Facing = 5
        )
        return [ordered]@{
            id = $Id
            sequence = 0
            elapsed_ms = $Elapsed
            camera = [ordered]@{
                position = @(512, 344)
                viewport = @(1024, 688)
                zoom = @(1, 1)
            }
            world = [ordered]@{
                size = @(4960, 2240)
                tracked_actor_count = 1
                source_entity_count = 1630
            }
            actors = @(
                [ordered]@{
                    actor_id = 'scene:1436'
                    role = 'player'
                    scene_index = 1436
                    database_entry_id = 924
                    display_name = '强子'
                    faction_id = 3
                    position = @($X, $Y)
                    target_position = @(656, 616)
                    facing_direction = $Facing
                    alive = $true
                    selected = $true
                    stance = 'run'
                    hit_points = [ordered]@{
                        current = 8
                        maximum = 8
                    }
                    weapon = [ordered]@{
                        attack_type = 4
                        action_key = 'dagger_attack'
                        magazine_ammo = 0
                        reserve_ammo = 0
                        infinite_ammo = $true
                    }
                    inventory = [ordered]@{}
                    native = [ordered]@{}
                }
            )
            mission = [ordered]@{
                id = 'm000'
                status = 'active'
                failure_id = ''
                completed = [ordered]@{}
                progress = [ordered]@{}
                elapsed_seconds = 1
            }
            tags = [ordered]@{}
        }
    }

    function New-Trace {
        param([string]$Runtime, $Checkpoint)
        return [ordered]@{
            schema_version = 1
            trace_id = "$Runtime-m000-m000-basic-movement-v1"
            runtime = $Runtime
            content_profile = 'repository-mod-12-level-20260729'
            level = [ordered]@{
                id = 'm000'
                selector_level = 1
                engine_mission = 1
            }
            scenario = [ordered]@{
                id = 'm000-basic-movement-v1'
                coordinate_space = 'legacy-world-pixels'
                description = 'synthetic comparator fixture'
            }
            metadata = [ordered]@{}
            checkpoints = @($Checkpoint)
        }
    }

    $referencePath = Join-Path $root 'reference.json'
    $withinPath = Join-Path $root 'within-tolerance.json'
    $mismatchPath = Join-Path $root 'mismatch.json'
    New-Trace 'mod' (New-Checkpoint 'gameplay_ready' 1000 241 51) |
        ConvertTo-Json -Depth 20 |
        Set-Content -LiteralPath $referencePath -Encoding UTF8
    New-Trace 'remake' (New-Checkpoint 'gameplay_ready' 1450 248 55) |
        ConvertTo-Json -Depth 20 |
        Set-Content -LiteralPath $withinPath -Encoding UTF8
    $mismatchCheckpoint = New-Checkpoint `
        'gameplay_ready' 4000 400 300 2
    $mismatchCheckpoint.actors[0].database_entry_id = 999
    New-Trace 'remake' $mismatchCheckpoint |
        ConvertTo-Json -Depth 20 |
        Set-Content -LiteralPath $mismatchPath -Encoding UTF8

    $positive = & $compareScript `
        -ReferenceTrace $referencePath `
        -CandidateTrace $withinPath
    if (-not [bool]$positive.passed -or
        [int]$positive.mismatch_count -ne 0) {
        throw 'Tolerance-compatible runtime traces did not compare equal.'
    }
    $checkedBaselines = @($baselinePath, $obstacleBaselinePath) +
        @($movementBaselinePaths) +
        @($patrolBaselinePaths) +
        @($contactBaselinePath) +
        @($inventoryBaselineDefinitions.path)
    foreach ($checkedBaseline in $checkedBaselines) {
        $baselineSelf = & $compareScript `
            -ReferenceTrace $checkedBaseline `
            -CandidateTrace $checkedBaseline
        if (-not [bool]$baselineSelf.passed) {
            throw "The checked-in MOD trace is not self-consistent: $checkedBaseline"
        }
    }

    $routeCandidatePath = Join-Path $root 'route-shape-candidate.json'
    $routeCandidate = Get-Content -LiteralPath $movementBaselinePaths[0] `
        -Raw -Encoding UTF8 | ConvertFrom-Json
    $routeCandidate.runtime = 'remake'
    $routeCandidate.trace_id = 'remake-m000-m000-player-obstacle-route-v1'
    $routeCandidate.checkpoints[2].tags | Add-Member `
        -NotePropertyName path `
        -NotePropertyValue @(
            $routeCandidate.checkpoints[3].tags.observed_positions)
    $routeCandidate.checkpoints[4].tags | Add-Member `
        -NotePropertyName path `
        -NotePropertyValue @(
            $routeCandidate.checkpoints[5].tags.observed_positions)
    $routeCandidate | ConvertTo-Json -Depth 40 |
        Set-Content -LiteralPath $routeCandidatePath -Encoding UTF8
    $routePositive = & $compareScript `
        -ReferenceTrace $movementBaselinePaths[0] `
        -CandidateTrace $routeCandidatePath `
        -SceneIndices 1436 `
        -CompareObservedRouteShape
    if (-not [bool]$routePositive.passed -or
        @($routePositive.route_shape_metrics).Count -ne 2) {
        throw 'Equivalent observed route geometry did not compare equal.'
    }

    $routeObservedMismatchPath = Join-Path $root `
        'route-shape-observed-mismatch.json'
    $routeObservedMismatch = Get-Content -LiteralPath $routeCandidatePath `
        -Raw -Encoding UTF8 | ConvertFrom-Json
    $routeObservedMismatch.checkpoints[3].tags.observed_positions[6][1] =
        [double]$routeObservedMismatch.checkpoints[3].
            tags.observed_positions[6][1] + 16.0
    $routeObservedMismatch | ConvertTo-Json -Depth 40 |
        Set-Content -LiteralPath $routeObservedMismatchPath -Encoding UTF8
    $routeObservedNegative = & $compareScript `
        -ReferenceTrace $movementBaselinePaths[0] `
        -CandidateTrace $routeObservedMismatchPath `
        -SceneIndices 1436 `
        -CompareObservedRouteShape `
        -AllowMismatch
    if ([bool]$routeObservedNegative.passed -or
        @($routeObservedNegative.mismatches.path) -notcontains
            'tags.observed_positions.candidate_to_reference') {
        throw 'Observed route-shape divergence was not detected.'
    }

    $routePlannedMismatchPath = Join-Path $root `
        'route-shape-planned-mismatch.json'
    $routePlannedMismatch = Get-Content -LiteralPath $routeCandidatePath `
        -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($point in @($routePlannedMismatch.checkpoints[2].tags.path)) {
        $point[1] = [double]$point[1] + 16.0
    }
    $routePlannedMismatch | ConvertTo-Json -Depth 40 |
        Set-Content -LiteralPath $routePlannedMismatchPath -Encoding UTF8
    $routePlannedNegative = & $compareScript `
        -ReferenceTrace $movementBaselinePaths[0] `
        -CandidateTrace $routePlannedMismatchPath `
        -SceneIndices 1436 `
        -CompareObservedRouteShape `
        -AllowMismatch
    if ([bool]$routePlannedNegative.passed -or
        @($routePlannedNegative.mismatches.path) -notcontains
            'tags.observed_positions.reference_to_candidate_path') {
        throw 'Planned route-shape divergence was not detected.'
    }

    # The contact baseline was captured before the independent live-faction
    # catalog and therefore contains the authored VWF faction for scene 1427.
    # Build a Remake-shaped candidate with the authoritative runtime factions
    # instead of incorrectly using that historical MOD trace as both sides.
    $contactSelfCandidatePath = Join-Path $root `
        'natural-contact-self-candidate.json'
    $contactSelfCandidate = Get-Content -LiteralPath $contactBaselinePath `
        -Raw -Encoding UTF8 | ConvertFrom-Json
    $contactSelfCandidate.runtime = 'remake'
    $contactSelfCandidate.trace_id = 'remake-m000-m000-natural-contact-v1'
    $runtimeActorCatalog = Get-Content `
        -LiteralPath $runtimeActorCatalogPath `
        -Raw -Encoding UTF8 | ConvertFrom-Json
    $runtimeActorProfiles = $runtimeActorCatalog.levels.m000.actors
    foreach ($checkpoint in @($contactSelfCandidate.checkpoints)) {
        foreach ($actor in @($checkpoint.actors)) {
            $runtimeProfileProperty =
                $runtimeActorProfiles.PSObject.Properties[
                    [string][int]$actor.scene_index]
            if ($null -ne $runtimeProfileProperty) {
                $actor.faction_id =
                    [int]$runtimeProfileProperty.Value.runtime_faction_id
            }
        }
    }
    $contactSelfCandidate | ConvertTo-Json -Depth 40 |
        Set-Content -LiteralPath $contactSelfCandidatePath -Encoding UTF8
    $contactSelf = & $contactCompareScript `
        -ReferenceTrace $contactBaselinePath `
        -CandidateTrace $contactSelfCandidatePath
    if (-not [bool]$contactSelf.passed -or
        [int]$contactSelf.audited_actor_count -ne 54 -or
        @($contactSelf.required_contact_scenes) -notcontains 1598 -or
        (@($contactSelf.player_hit_point_sequence.reference) -join ',') -ne
            '8,8,8,8,8,6,4') {
        throw 'The checked-in natural-contact baseline is not self-consistent.'
    }
    foreach ($inventoryDefinition in $inventoryBaselineDefinitions) {
        $inventorySelf = & $inventoryCompareScript `
            -ReferenceTrace $inventoryDefinition.path `
            -CandidateTrace $inventoryDefinition.path
        if (-not [bool]$inventorySelf.passed -or
            [int]$inventorySelf.mismatch_count -ne 0) {
            throw (
                'The checked-in inventory baseline is not self-consistent: ' +
                $inventoryDefinition.scenario)
        }
    }

    $inventoryMismatchPath = Join-Path $root `
        'mine-pickup-inventory-mismatch.json'
    $inventoryMismatch = Get-Content `
        -LiteralPath $minePickupBaselinePath `
        -Raw -Encoding UTF8 | ConvertFrom-Json
    $inventoryMismatchActor = @(
        $inventoryMismatch.checkpoints[1].actors |
            Where-Object { [int]$_.scene_index -eq 2280 }
    )[0]
    $inventoryMismatchEntry = @(
        $inventoryMismatchActor.inventory.weapon_entries |
            Where-Object { [int]$_.item_id -eq 43 }
    )[0]
    $inventoryMismatchEntry.quantity = 2
    $inventoryMismatch | ConvertTo-Json -Depth 40 |
        Set-Content -LiteralPath $inventoryMismatchPath -Encoding UTF8
    $inventoryNegative = & $inventoryCompareScript `
        -ReferenceTrace $minePickupBaselinePath `
        -CandidateTrace $inventoryMismatchPath `
        -AllowMismatch
    if ([bool]$inventoryNegative.passed -or
        @($inventoryNegative.mismatches.path) -notcontains
            'checkpoints.after_pickup.actors.scene:2280.inventory.weapon_entries[1].quantity' -or
        @($inventoryNegative.mismatches.path) -notcontains
            'candidate.delta.after_quantity') {
        throw 'Inventory quantity divergence was not detected.'
    }

    $movementMismatchPath = Join-Path $root 'movement-mismatch.json'
    $movementMismatch = Get-Content -LiteralPath $baselinePath `
        -Raw -Encoding UTF8 | ConvertFrom-Json
    $movementActor = @(
        $movementMismatch.checkpoints[3].actors |
        Where-Object { [int]$_.scene_index -eq 1436 }
    )[0]
    $movementActor.position[0] =
        [double]$movementActor.position[0] + 40.0
    $movementMismatch | ConvertTo-Json -Depth 30 |
        Set-Content -LiteralPath $movementMismatchPath -Encoding UTF8
    $movementResult = & $compareScript `
        -ReferenceTrace $baselinePath `
        -CandidateTrace $movementMismatchPath `
        -AllowMismatch
    if ([bool]$movementResult.passed -or
        @($movementResult.mismatches.path) -notcontains
        'actors.scene:1436.movement_delta') {
        throw 'Observed movement-vector divergence was not detected.'
    }

    $negative = & $compareScript `
        -ReferenceTrace $referencePath `
        -CandidateTrace $mismatchPath `
        -AllowMismatch
    if ([bool]$negative.passed -or
        [int]$negative.mismatch_count -lt 3 -or
        @($negative.mismatches.path) -notcontains
        'actors.scene:1436.facing_direction') {
        throw 'Runtime trace comparator did not identify semantic divergence.'
    }

    $contactMismatchPath = Join-Path $root 'contact-mismatch.json'
    $contactMismatch = Get-Content -LiteralPath $contactBaselinePath `
        -Raw -Encoding UTF8 | ConvertFrom-Json
    $contactMismatchActor = @(
        $contactMismatch.checkpoints[-1].actors |
            Where-Object { [int]$_.scene_index -eq 1598 }
    )[0]
    $contactMismatchActor.native.contact_state = 0
    $contactMismatchActor.native.target_lost = 1
    $contactMismatchActor.native.interest_scene_index = -1
    $contactMismatchActor.native.target_scene_index = -1
    $contactMismatch | ConvertTo-Json -Depth 40 |
        Set-Content -LiteralPath $contactMismatchPath -Encoding UTF8
    $contactNegative = & $contactCompareScript `
        -ReferenceTrace $contactBaselinePath `
        -CandidateTrace $contactMismatchPath `
        -AllowMismatch
    if ([bool]$contactNegative.passed -or
        @($contactNegative.mismatches.path) -notcontains
        'contact_settled.live_contact_scenes') {
        throw 'Natural-contact target loss was not detected.'
    }

    $damageMismatchPath = Join-Path $root 'contact-damage-mismatch.json'
    $damageMismatch = Get-Content -LiteralPath $contactBaselinePath `
        -Raw -Encoding UTF8 | ConvertFrom-Json
    $damageMismatchPlayer = @(
        $damageMismatch.checkpoints[-1].actors |
            Where-Object { [int]$_.scene_index -eq 1436 }
    )[0]
    $damageMismatchPlayer.hit_points.current = 6
    $damageMismatchPlayer.native.current_hit_points = 6
    $damageMismatch | ConvertTo-Json -Depth 40 |
        Set-Content -LiteralPath $damageMismatchPath -Encoding UTF8
    $damageNegative = & $contactCompareScript `
        -ReferenceTrace $contactBaselinePath `
        -CandidateTrace $damageMismatchPath `
        -AllowMismatch
    if ([bool]$damageNegative.passed -or
        @($damageNegative.mismatches.path) -notcontains
        'checkpoints.contact_settled.player.hit_points') {
        throw 'Natural-contact damage-sequence divergence was not detected.'
    }
}
finally {
    if (Test-Path -LiteralPath $root -PathType Container) {
        $resolvedRoot = [IO.Path]::GetFullPath($root)
        $resolvedBase = [IO.Path]::GetFullPath($temporaryBase)
        if (-not $resolvedRoot.StartsWith(
                $resolvedBase + [IO.Path]::DirectorySeparatorChar,
                [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Refusing to remove parity-test output outside its temporary root.'
        }
        Remove-Item -LiteralPath $resolvedRoot -Recurse -Force
    }
}

Write-Host 'Runtime parity trace schema/comparator tests passed.'
