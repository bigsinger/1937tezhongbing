[CmdletBinding()]
param(
    [string]$ConvertedLevelsRoot = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$remakeRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if ([string]::IsNullOrWhiteSpace($ConvertedLevelsRoot)) {
    $ConvertedLevelsRoot = Join-Path `
        $remakeRoot `
        'LocalAssets\converted\levels'
}
$ConvertedLevelsRoot = [IO.Path]::GetFullPath($ConvertedLevelsRoot)

$expectedEntityCounts = @(
    1630, 2525, 898, 1254, 2721, 771,
    1470, 2408, 805, 1720, 1629, 1368
)
$expectedActorCounts = @(
    62, 80, 34, 53, 116, 92,
    44, 99, 28, 56, 81, 40
)
$unsignedKeys = @(
    'route_update_active',
    'contact_state',
    'hidden_or_removed',
    'burial_or_disguise_transition_ready',
    'hypnosis_active',
    'corpse_discovered',
    'target_lost',
    'movement_active',
    'movement_path_state',
    'movement_mode',
    'search_delay_limit',
    'search_delay_counter',
    'reaction_state',
    'poison_active',
    'poison_counter',
    'poison_counter_limit',
    'hypnosis_counter_limit',
    'hypnosis_counter',
    'burial_action_started',
    'disguise_change_pending',
    'path_override_or_special_attention_hold',
    'disguise_recovery_active',
    'disguise_recovery_limit',
    'disguise_recovery_or_pursuit_delay_counter'
)
$signedKeys = @('resolved_goal_x', 'resolved_goal_y')
$expectedKeys = @('schema_version') + $unsignedKeys + $signedKeys |
    Sort-Object
$expectedNonZeroKeys = @(
    'contact_state',
    'disguise_recovery_limit',
    'hidden_or_removed',
    'hypnosis_counter_limit',
    'movement_active',
    'movement_mode',
    'movement_path_state',
    'poison_counter_limit',
    'resolved_goal_x',
    'resolved_goal_y',
    'route_update_active',
    'search_delay_counter',
    'search_delay_limit',
    'target_lost'
) | Sort-Object

$entityTotal = 0
$actorTotal = 0
$nonZeroKeys = @{}
for ($levelIndex = 0; $levelIndex -lt 12; ++$levelIndex) {
    $levelId = 'm{0:D3}' -f $levelIndex
    $levelPath = Join-Path $ConvertedLevelsRoot "$levelId\level.json"
    if (-not (Test-Path -LiteralPath $levelPath -PathType Leaf)) {
        throw "Converted actor-state audit is missing ${levelId}: $levelPath"
    }
    $level = Get-Content -LiteralPath $levelPath -Raw -Encoding UTF8 |
        ConvertFrom-Json
    $entities = @($level.entities)
    if ($entities.Count -ne $expectedEntityCounts[$levelIndex]) {
        throw (
            "$levelId entity count changed: expected " +
            "$($expectedEntityCounts[$levelIndex]), got $($entities.Count).")
    }
    $actors = @($entities | Where-Object {
        $null -ne $_.native_actor_state
    })
    if ($actors.Count -ne $expectedActorCounts[$levelIndex]) {
        throw (
            "$levelId actor count changed: expected " +
            "$($expectedActorCounts[$levelIndex]), got $($actors.Count).")
    }
    foreach ($entity in $entities) {
        if ($null -eq $entity.native_actor_state) {
            continue
        }
        $state = $entity.native_actor_state
        if ($null -eq $state -or [int]$state.schema_version -ne 1) {
            throw "$levelId scene $($entity.scene_index) has no schema-1 native actor state."
        }
        $actualKeys = @($state.PSObject.Properties.Name | Sort-Object)
        if (($actualKeys -join "`n") -cne ($expectedKeys -join "`n")) {
            throw "$levelId scene $($entity.scene_index) native actor keys changed."
        }
        if ([long]$entity.contact_state -ne [long]$state.contact_state -or
            [long]$entity.reaction_state -ne [long]$state.reaction_state) {
            throw (
                "$levelId scene $($entity.scene_index) contact/reaction " +
                'compatibility fields disagree with native actor state.')
        }
        foreach ($key in $unsignedKeys) {
            $value = [long]$state.$key
            if ($value -lt 0 -or $value -gt [uint32]::MaxValue) {
                throw "$levelId scene $($entity.scene_index) has invalid unsigned '$key'."
            }
            if ($value -ne 0) {
                $nonZeroKeys[$key] = $true
            }
        }
        foreach ($key in $signedKeys) {
            $value = [long]$state.$key
            if ($value -lt [int32]::MinValue -or
                $value -gt [int32]::MaxValue) {
                throw "$levelId scene $($entity.scene_index) has invalid signed '$key'."
            }
            if ($value -ne 0) {
                $nonZeroKeys[$key] = $true
            }
        }
    }
    $entityTotal += $entities.Count
    $actorTotal += $actors.Count
}

if ($entityTotal -ne 19199 -or $actorTotal -ne 785) {
    throw "Converted actor-state totals changed: $entityTotal entities, $actorTotal actors."
}
$actualNonZeroKeys = @($nonZeroKeys.Keys | Sort-Object)
if (($actualNonZeroKeys -join "`n") -cne
    ($expectedNonZeroKeys -join "`n")) {
    throw 'Converted native actor-state nonzero field set changed.'
}

Write-Host (
    'Original actor-state import passed: 12 levels, ' +
    "$entityTotal entities, $actorTotal actors, " +
    "$($nonZeroKeys.Count) exported fields observed nonzero.")
