[CmdletBinding()]
param(
    [string]$CatalogPath = '',
    [string]$LevelManifest = ''
)

$ErrorActionPreference = 'Stop'
$remakeRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $remakeRoot '..'))
if ([string]::IsNullOrWhiteSpace($CatalogPath)) {
    $CatalogPath = Join-Path $remakeRoot (
        'validation\identities\mod\m000-runtime-actors-v1.json')
}
$CatalogPath = (Resolve-Path -LiteralPath $CatalogPath).Path
$catalog = Get-Content -LiteralPath $CatalogPath -Raw -Encoding UTF8 |
    ConvertFrom-Json

if ($catalog.schema_version -ne 1 -or
    $catalog.catalog_id -ne 'mod-m000-runtime-actors-v1' -or
    $catalog.content_profile -ne 'repository-mod-12-level-20260729') {
    throw 'The m000 runtime identity catalog header is invalid.'
}
if ($catalog.level.id -ne 'm000' -or
    $catalog.level.selector_level -ne 1 -or
    $catalog.level.engine_mission -ne 1) {
    throw 'The m000 runtime identity catalog level route is invalid.'
}

$identities = @($catalog.identities)
$resolved = @($identities | Where-Object { $_.status -eq 'resolved' })
$unresolved = @($identities | Where-Object { $_.status -eq 'unresolved' })
if ($catalog.summary.runtime_object_count -ne 127 -or
    $catalog.summary.runtime_dynamic_actor_count -ne 62 -or
    $catalog.summary.vwf_dynamic_actor_count -ne 62 -or
    $identities.Count -ne 62 -or
    $resolved.Count -ne 62 -or
    $unresolved.Count -ne 0 -or
    $catalog.summary.resolved_count -ne $resolved.Count -or
    $catalog.summary.unresolved_count -ne $unresolved.Count) {
    throw 'The m000 runtime identity catalog coverage is invalid.'
}

$runtimeIndices = @($identities | Select-Object -ExpandProperty runtime_index)
$sceneIndices = @($resolved | Select-Object -ExpandProperty scene_index)
if (@($runtimeIndices | Select-Object -Unique).Count -ne $identities.Count) {
    throw 'Runtime actor indices must be unique within the capture.'
}
if (@($sceneIndices | Select-Object -Unique).Count -ne $resolved.Count) {
    throw 'Resolved VWF scene assignments must be one-to-one.'
}
if (@($identities |
    Where-Object {
        $_.mapping_scope -ne
        'captured-runtime-array-index-within-supported-content-profile'
    }).Count -ne 0) {
    throw 'Runtime array indices must stay scoped to the supported capture.'
}

$methodCounts = @{}
foreach ($identity in $resolved) {
    $method = [string]$identity.method
    if (-not $methodCounts.ContainsKey($method)) {
        $methodCounts[$method] = 0
    }
    $methodCounts[$method]++
    if ($identity.runtime_type -eq $identity.database_entry_id) {
        # There can be accidental numeric equality in other levels, but m000
        # has none. This guards the historical +0x64 naming trap here.
        throw (
            "Runtime type was incorrectly used as a DBL id at runtime index " +
            "$($identity.runtime_index).")
    }
    if ([int]$identity.authored_hit_points -le 0 -or
        [int]$identity.authored_attack_type -lt 0 -or
        [int]$identity.authored_attack_type -gt 11) {
        throw (
            "Resolved combat identity is invalid at runtime index " +
            "$($identity.runtime_index).")
    }
}
$expectedMethods = [ordered]@{
    unique_runtime_type_and_exact_patrol_goal = 45
    unique_runtime_type_and_exact_reference_position = 5
    bounded_unambiguous_reference_drift = 2
    residual_unique_runtime_type = 1
    isolated_nearest_reference_after_exact_matches = 1
    contiguous_runtime_and_vwf_order_between_resolved_neighbors = 8
}
foreach ($entry in $expectedMethods.GetEnumerator()) {
    if ($methodCounts[$entry.Key] -ne $entry.Value -or
        $catalog.summary.method_counts.($entry.Key) -ne $entry.Value) {
        throw "Unexpected identity count for method $($entry.Key)."
    }
}

$player = @($resolved |
    Where-Object { $_.runtime_index -eq 18 }) |
    Select-Object -First 1
$expectedPlayerName = [string]::Concat([char]0x5F3A, [char]0x5B50)
if ($null -eq $player -or
    $player.runtime_type -ne 1 -or
    $player.runtime_faction_id -ne 3 -or
    $player.scene_index -ne 1436 -or
    $player.database_entry_id -ne 924 -or
    $player.display_name -ne $expectedPlayerName) {
    throw 'The unique m000 player identity is invalid.'
}
$expectedOrderedScenes = [ordered]@{
    104 = 1571
    105 = 1572
    106 = 1573
    107 = 1574
    121 = 1617
    122 = 1618
    123 = 1619
    124 = 1620
}
foreach ($entry in $expectedOrderedScenes.GetEnumerator()) {
    $identity = @($resolved |
        Where-Object { [int]$_.runtime_index -eq [int]$entry.Key }) |
        Select-Object -First 1
    if ($null -eq $identity -or
        [int]$identity.scene_index -ne [int]$entry.Value -or
        [string]$identity.confidence -ne 'exact' -or
        [string]$identity.method -ne
        'contiguous_runtime_and_vwf_order_between_resolved_neighbors') {
        throw (
            "The bounded formation mapping for runtime actor $($entry.Key) " +
            'is invalid.')
    }
}

if (-not [string]::IsNullOrWhiteSpace($LevelManifest)) {
    $LevelManifest = (Resolve-Path -LiteralPath $LevelManifest).Path
    $manifest = Get-Content -LiteralPath $LevelManifest -Raw -Encoding UTF8 |
        ConvertFrom-Json
    $entitiesByScene = @{}
    foreach ($entity in @($manifest.entities)) {
        $entitiesByScene[[int]$entity.scene_index] = $entity
    }
    foreach ($identity in $resolved) {
        if (-not $entitiesByScene.ContainsKey([int]$identity.scene_index)) {
            throw "Resolved scene $($identity.scene_index) is absent from the VWF."
        }
        $entity = $entitiesByScene[[int]$identity.scene_index]
        if ([int]$entity.database_entry_id -ne
            [int]$identity.database_entry_id -or
            [int]$entity.database_header_values[2] -ne
            [int]$identity.runtime_type -or
            [int]$entity.current_hit_points -ne
            [int]$identity.authored_hit_points -or
            [int]$entity.default_attack_type -ne
            [int]$identity.authored_attack_type) {
            throw (
                "Resolved identity fields disagree with VWF scene " +
                "$($identity.scene_index).")
        }
    }
}

[pscustomobject]@{
    Catalog = $catalog.catalog_id
    RuntimeActors = $identities.Count
    Resolved = $resolved.Count
    Unresolved = $unresolved.Count
    ExactPatrolGoalMappings = $methodCounts[
        'unique_runtime_type_and_exact_patrol_goal']
}
