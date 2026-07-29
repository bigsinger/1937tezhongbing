[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$RuntimeSnapshotCsv,

    [Parameter(Mandatory)]
    [string]$LevelManifest,

    [Parameter(Mandatory)]
    [string]$OutputPath,

    [string]$LevelId = 'm000',
    [int]$SelectorLevel = 1,
    [int]$EngineMission = 1,
    [string]$ContentProfile = 'repository-mod-12-level-20260729',
    [string]$CaptureId = 'm000-gameplay-entry-20260729'
)

$ErrorActionPreference = 'Stop'
$RuntimeSnapshotCsv = (Resolve-Path -LiteralPath $RuntimeSnapshotCsv).Path
$LevelManifest = (Resolve-Path -LiteralPath $LevelManifest).Path
$OutputPath = [IO.Path]::GetFullPath($OutputPath)

function Get-EntityRuntimeType {
    param([Parameter(Mandatory)]$Entity)
    $header = @($Entity.database_header_values)
    if ($header.Count -lt 3) {
        return $null
    }
    return [int]$header[2]
}

function Get-ReferenceX {
    param([Parameter(Mandatory)]$Entity)
    if ($null -ne $Entity.reference_x) {
        return [int]$Entity.reference_x
    }
    return [int]$Entity.x
}

function Get-ReferenceY {
    param([Parameter(Mandatory)]$Entity)
    if ($null -ne $Entity.reference_y) {
        return [int]$Entity.reference_y
    }
    return [int]$Entity.y
}

function Get-Distance {
    param(
        [double]$FirstX,
        [double]$FirstY,
        [double]$SecondX,
        [double]$SecondY
    )
    $dx = $FirstX - $SecondX
    $dy = $FirstY - $SecondY
    return [Math]::Sqrt(($dx * $dx) + ($dy * $dy))
}

function Test-ExactPatrolGoal {
    param(
        [Parameter(Mandatory)]$Observation,
        [Parameter(Mandatory)]$Entity
    )
    if ([int]$Observation.goal_kind -ne 1) {
        return $false
    }
    $goalX = [int]$Observation.goal_x
    $goalY = [int]$Observation.goal_y
    if ($goalX -eq 0 -and $goalY -eq 0) {
        return $false
    }
    foreach ($waypoint in @($Entity.patrol.waypoints)) {
        $waypointX = (32 * [int]$waypoint.x) + 16
        $waypointY = (16 * [int]$waypoint.y) + 8
        if ($waypointX -eq $goalX -and $waypointY -eq $goalY) {
            return $true
        }
    }
    return $false
}

$level = Get-Content -LiteralPath $LevelManifest -Raw -Encoding UTF8 |
    ConvertFrom-Json
$runtimeRows = @(Import-Csv -LiteralPath $RuntimeSnapshotCsv)
$observations = @($runtimeRows |
    Where-Object { [int]$_.faction -in 1, 2, 3 } |
    Sort-Object { [int]$_.index })
$entities = @($level.entities |
    Where-Object {
        $null -ne $_.faction_id -and
        [int]$_.faction_id -in 1, 2, 3 -and
        $null -ne (Get-EntityRuntimeType $_)
    } |
    Sort-Object { [int]$_.scene_index })

if ($observations.Count -ne $entities.Count) {
    throw (
        "Runtime/VWF dynamic-actor counts differ: " +
        "$($observations.Count) versus $($entities.Count).")
}

$assignedScenes = @{}
$mappings = @{}

function Add-IdentityMapping {
    param(
        [Parameter(Mandatory)]$Observation,
        [Parameter(Mandatory)]$Entity,
        [Parameter(Mandatory)][string]$Method,
        [Parameter(Mandatory)][ValidateSet('exact', 'high')]
        [string]$Confidence,
        [Parameter(Mandatory)]$Evidence
    )
    $runtimeIndex = [int]$Observation.index
    $sceneIndex = [int]$Entity.scene_index
    if ($mappings.ContainsKey($runtimeIndex)) {
        throw "Runtime index $runtimeIndex was mapped more than once."
    }
    if ($assignedScenes.ContainsKey($sceneIndex)) {
        throw "VWF scene $sceneIndex was mapped more than once."
    }
    $mappings[$runtimeIndex] = [pscustomobject]@{
        Entity = $Entity
        Method = $Method
        Confidence = $Confidence
        Evidence = $Evidence
    }
    $assignedScenes[$sceneIndex] = $runtimeIndex
}

# Strongest rule: the runtime type and active patrol destination both match
# exactly one authored VWF actor. Runtime faction is deliberately not a key:
# mission scripting can change it after the VWF has been loaded.
foreach ($observation in $observations) {
    $runtimeType = [int]$observation.database_entry
    $candidates = @($entities |
        Where-Object {
            -not $assignedScenes.ContainsKey([int]$_.scene_index) -and
            (Get-EntityRuntimeType $_) -eq $runtimeType -and
            (Test-ExactPatrolGoal $observation $_)
        })
    if ($candidates.Count -eq 1) {
        $entity = $candidates[0]
        Add-IdentityMapping $observation $entity `
            'unique_runtime_type_and_exact_patrol_goal' 'exact' `
            ([ordered]@{
                runtime_type = $runtimeType
                patrol_goal = @(
                    [int]$observation.goal_x,
                    [int]$observation.goal_y)
                runtime_faction_id = [int]$observation.faction
                vwf_faction_id = [int]$entity.faction_id
                faction_consistent = (
                    [int]$observation.faction -eq
                    [int]$entity.faction_id)
            })
    }
}

# Actors with no live patrol goal can still be proven when the observed world
# position is the exact authored reference coordinate for one remaining actor
# of the same runtime type.
foreach ($observation in $observations) {
    $runtimeIndex = [int]$observation.index
    if ($mappings.ContainsKey($runtimeIndex)) {
        continue
    }
    $runtimeType = [int]$observation.database_entry
    $candidates = @($entities |
        Where-Object {
            -not $assignedScenes.ContainsKey([int]$_.scene_index) -and
            (Get-EntityRuntimeType $_) -eq $runtimeType -and
            (Get-ReferenceX $_) -eq [int]$observation.world_x -and
            (Get-ReferenceY $_) -eq [int]$observation.world_y
        })
    if ($candidates.Count -eq 1) {
        $entity = $candidates[0]
        Add-IdentityMapping $observation $entity `
            'unique_runtime_type_and_exact_reference_position' 'exact' `
            ([ordered]@{
                runtime_type = $runtimeType
                position = @(
                    [int]$observation.world_x,
                    [int]$observation.world_y)
                reference_position = @(
                    (Get-ReferenceX $entity),
                    (Get-ReferenceY $entity))
            })
    }
}

# A small bounded drift is expected for ambient animals. Accept a nearest
# authored reference only when it is <=64 pixels and is separated from the
# runner-up by at least 32 pixels. Proposals are applied as a one-to-one batch.
$nearReferenceProposals = @()
foreach ($observation in $observations) {
    $runtimeIndex = [int]$observation.index
    if ($mappings.ContainsKey($runtimeIndex)) {
        continue
    }
    $runtimeType = [int]$observation.database_entry
    $ranked = @($entities |
        Where-Object {
            -not $assignedScenes.ContainsKey([int]$_.scene_index) -and
            (Get-EntityRuntimeType $_) -eq $runtimeType
        } |
        ForEach-Object {
            [pscustomobject]@{
                Entity = $_
                Distance = Get-Distance `
                    ([int]$observation.world_x) `
                    ([int]$observation.world_y) `
                    (Get-ReferenceX $_) `
                    (Get-ReferenceY $_)
            }
        } |
        Sort-Object Distance, { [int]$_.Entity.scene_index })
    if ($ranked.Count -eq 0 -or $ranked[0].Distance -gt 64.0) {
        continue
    }
    $runnerUp = if ($ranked.Count -gt 1) {
        [double]$ranked[1].Distance
    } else {
        [double]::PositiveInfinity
    }
    if (($runnerUp - [double]$ranked[0].Distance) -lt 32.0) {
        continue
    }
    $nearReferenceProposals += [pscustomobject]@{
        Observation = $observation
        Entity = $ranked[0].Entity
        Distance = [double]$ranked[0].Distance
        RunnerUp = $runnerUp
    }
}
foreach ($proposal in $nearReferenceProposals) {
    $sceneIndex = [int]$proposal.Entity.scene_index
    $proposalCount = @($nearReferenceProposals |
        Where-Object { [int]$_.Entity.scene_index -eq $sceneIndex }).Count
    if ($proposalCount -ne 1 -or $assignedScenes.ContainsKey($sceneIndex)) {
        continue
    }
    Add-IdentityMapping $proposal.Observation $proposal.Entity `
        'bounded_unambiguous_reference_drift' 'high' `
        ([ordered]@{
            reference_distance = [Math]::Round($proposal.Distance, 3)
            runner_up_distance = if (
                [double]::IsPositiveInfinity($proposal.RunnerUp)
            ) { $null } else { [Math]::Round($proposal.RunnerUp, 3) }
            maximum_distance = 64
            minimum_runner_up_gap = 32
        })
}

# Once exact mappings have consumed the other same-type actors, a one-to-one
# residual type pair is independently identifiable.
foreach ($observation in $observations) {
    $runtimeIndex = [int]$observation.index
    if ($mappings.ContainsKey($runtimeIndex)) {
        continue
    }
    $runtimeType = [int]$observation.database_entry
    $remainingObservations = @($observations |
        Where-Object {
            -not $mappings.ContainsKey([int]$_.index) -and
            [int]$_.database_entry -eq $runtimeType
        })
    $remainingEntities = @($entities |
        Where-Object {
            -not $assignedScenes.ContainsKey([int]$_.scene_index) -and
            (Get-EntityRuntimeType $_) -eq $runtimeType
        })
    if ($remainingObservations.Count -eq 1 -and
        $remainingEntities.Count -eq 1) {
        Add-IdentityMapping $observation $remainingEntities[0] `
            'residual_unique_runtime_type' 'high' `
            ([ordered]@{
                runtime_type = $runtimeType
                remaining_runtime_count = 1
                remaining_vwf_count = 1
            })
    }
}

# A scripted actor may have moved far from its authored reference before the
# first gameplay checkpoint. Keep this rule deliberately narrow: <=320 pixels
# and at least a 400-pixel separation from every other remaining same-type
# candidate.
foreach ($observation in $observations) {
    $runtimeIndex = [int]$observation.index
    if ($mappings.ContainsKey($runtimeIndex)) {
        continue
    }
    $runtimeType = [int]$observation.database_entry
    $ranked = @($entities |
        Where-Object {
            -not $assignedScenes.ContainsKey([int]$_.scene_index) -and
            (Get-EntityRuntimeType $_) -eq $runtimeType
        } |
        ForEach-Object {
            [pscustomobject]@{
                Entity = $_
                Distance = Get-Distance `
                    ([int]$observation.world_x) `
                    ([int]$observation.world_y) `
                    (Get-ReferenceX $_) `
                    (Get-ReferenceY $_)
            }
        } |
        Sort-Object Distance, { [int]$_.Entity.scene_index })
    if ($ranked.Count -lt 2 -or
        $ranked[0].Distance -gt 320.0 -or
        ($ranked[1].Distance - $ranked[0].Distance) -lt 400.0) {
        continue
    }
    Add-IdentityMapping $observation $ranked[0].Entity `
        'isolated_nearest_reference_after_exact_matches' 'high' `
        ([ordered]@{
            reference_distance = [Math]::Round($ranked[0].Distance, 3)
            runner_up_distance = [Math]::Round($ranked[1].Distance, 3)
            maximum_distance = 320
            minimum_runner_up_gap = 400
        })
}

$identities = foreach ($observation in $observations) {
    $runtimeIndex = [int]$observation.index
    $base = [ordered]@{
        runtime_index = $runtimeIndex
        runtime_type = [int]$observation.database_entry
        runtime_faction_id = [int]$observation.faction
        observed = [ordered]@{
            position = @(
                [int]$observation.world_x,
                [int]$observation.world_y)
            facing_direction = [int]$observation.direction
            goal_kind = [int]$observation.goal_kind
            goal = @(
                [int]$observation.goal_x,
                [int]$observation.goal_y)
        }
        status = if ($mappings.ContainsKey($runtimeIndex)) {
            'resolved'
        } else {
            'unresolved'
        }
        mapping_scope = (
            'captured-runtime-array-index-within-supported-content-profile')
    }
    if ($mappings.ContainsKey($runtimeIndex)) {
        $mapping = $mappings[$runtimeIndex]
        $entity = $mapping.Entity
        $base.scene_index = [int]$entity.scene_index
        $base.database_entry_id = [int]$entity.database_entry_id
        $base.display_name = [string]$entity.display_name
        $base.vwf_faction_id = [int]$entity.faction_id
        $base.method = [string]$mapping.Method
        $base.confidence = [string]$mapping.Confidence
        $base.evidence = $mapping.Evidence
    }
    else {
        $runtimeType = [int]$observation.database_entry
        $base.candidates = @($entities |
            Where-Object {
                -not $assignedScenes.ContainsKey([int]$_.scene_index) -and
                (Get-EntityRuntimeType $_) -eq $runtimeType
            } |
            ForEach-Object {
                [ordered]@{
                    scene_index = [int]$_.scene_index
                    database_entry_id = [int]$_.database_entry_id
                    display_name = [string]$_.display_name
                    runtime_type = Get-EntityRuntimeType $_
                    vwf_faction_id = [int]$_.faction_id
                    reference_distance = [Math]::Round(
                        (Get-Distance `
                            ([int]$observation.world_x) `
                            ([int]$observation.world_y) `
                            (Get-ReferenceX $_) `
                            (Get-ReferenceY $_)),
                        3)
                }
            } |
            Sort-Object reference_distance, scene_index)
    }
    [pscustomobject]$base
}

$methodCounts = [ordered]@{}
foreach ($mapping in $mappings.Values) {
    $method = [string]$mapping.Method
    if (-not $methodCounts.Contains($method)) {
        $methodCounts[$method] = 0
    }
    $methodCounts[$method]++
}
$resolvedCount = $mappings.Count
$catalog = [ordered]@{
    schema_version = 1
    catalog_id = "mod-$LevelId-runtime-actors-v1"
    content_profile = $ContentProfile
    level = [ordered]@{
        id = $LevelId
        selector_level = $SelectorLevel
        engine_mission = $EngineMission
    }
    provenance = [ordered]@{
        runtime_snapshot = [ordered]@{
            capture_id = $CaptureId
            sha256 = (Get-FileHash -LiteralPath $RuntimeSnapshotCsv `
                -Algorithm SHA256).Hash
            observation_point = (
                'gameplay entry after briefing; read-only RuntimeActorV1 snapshots')
        }
        level_manifest = [ordered]@{
            level_id = [string]$level.level_id
            sha256 = (Get-FileHash -LiteralPath $LevelManifest `
                -Algorithm SHA256).Hash
        }
        field_semantics = [ordered]@{
            runtime_type = (
                'RuntimeActorV1 +0x064; historical SDK field name ' +
                'database_entry; this is a runtime type and never a DBL id')
            vwf_runtime_type = 'entity.database_header_values[2]'
            vwf_database_entry_id = (
                'entity.database_entry_id; the actual DBL resource identity')
            patrol_world_coordinate = (
                '[waypoint.x * 32 + 16, waypoint.y * 16 + 8]')
            runtime_index = (
                'capture-local actor-array index; never treated as a VWF scene index')
        }
    }
    summary = [ordered]@{
        runtime_object_count = $runtimeRows.Count
        runtime_dynamic_actor_count = $observations.Count
        vwf_dynamic_actor_count = $entities.Count
        resolved_count = $resolvedCount
        unresolved_count = $observations.Count - $resolvedCount
        method_counts = $methodCounts
    }
    identities = @($identities)
}

$parent = [IO.Path]::GetDirectoryName($OutputPath)
if (-not [string]::IsNullOrWhiteSpace($parent)) {
    [IO.Directory]::CreateDirectory($parent) | Out-Null
}
$catalog | ConvertTo-Json -Depth 16 |
    Set-Content -LiteralPath $OutputPath -Encoding UTF8

[pscustomobject]@{
    OutputPath = $OutputPath
    RuntimeObjects = $runtimeRows.Count
    DynamicActors = $observations.Count
    Resolved = $resolvedCount
    Unresolved = $observations.Count - $resolvedCount
}
