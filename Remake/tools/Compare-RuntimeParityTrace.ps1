[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ReferenceTrace,
    [Parameter(Mandatory)]
    [string]$CandidateTrace,
    [string]$OutputJson = '',
    [string]$OutputMarkdown = '',
    [ValidateRange(0, 4096)]
    [double]$PositionTolerance = 12,
    [ValidateRange(0, 4096)]
    [double]$TargetTolerance = 12,
    [ValidateRange(0, 4096)]
    [double]$CameraTolerance = 24,
    [ValidateRange(0, 600000)]
    [double]$ElapsedToleranceMs = 1500,
    [ValidateRange(0, 4096)]
    [double]$RouteShapeTolerance = 4,
    [int[]]$SceneIndices = @(),
    [switch]$IgnoreHitPoints,
    [switch]$IgnoreAliveState,
    [switch]$RequireExactActorSet,
    [switch]$CompareObservedRouteShape,
    [switch]$AllowMismatch
)

$ErrorActionPreference = 'Stop'

function Read-Trace {
    param([Parameter(Mandatory)][string]$Path)
    $resolved = (Resolve-Path -LiteralPath $Path).Path
    $trace = Get-Content -LiteralPath $resolved -Raw -Encoding UTF8 |
        ConvertFrom-Json
    if ([int]$trace.schema_version -ne 1) {
        throw "Unsupported runtime parity trace schema: $resolved"
    }
    return $trace
}

function Point-Distance {
    param($First, $Second)
    if (@($First).Count -ne 2 -or @($Second).Count -ne 2) {
        return [double]::PositiveInfinity
    }
    $x = [double]$First[0] - [double]$Second[0]
    $y = [double]$First[1] - [double]$Second[1]
    return [Math]::Sqrt($x * $x + $y * $y)
}

function Point-Segment-Distance {
    param($Point, $SegmentStart, $SegmentEnd)
    if (@($Point).Count -ne 2 -or
        @($SegmentStart).Count -ne 2 -or
        @($SegmentEnd).Count -ne 2) {
        return [double]::PositiveInfinity
    }
    $pointX = [double]$Point[0]
    $pointY = [double]$Point[1]
    $startX = [double]$SegmentStart[0]
    $startY = [double]$SegmentStart[1]
    $deltaX = [double]$SegmentEnd[0] - $startX
    $deltaY = [double]$SegmentEnd[1] - $startY
    $lengthSquared = $deltaX * $deltaX + $deltaY * $deltaY
    if ($lengthSquared -le 0.0000001) {
        return Point-Distance $Point $SegmentStart
    }
    $projection = (
        (($pointX - $startX) * $deltaX) +
        (($pointY - $startY) * $deltaY)
    ) / $lengthSquared
    $projection = [Math]::Max(0.0, [Math]::Min(1.0, $projection))
    $projected = @(
        ($startX + $projection * $deltaX)
        ($startY + $projection * $deltaY)
    )
    return Point-Distance $Point $projected
}

function Maximum-Point-To-Polyline-Distance {
    param($Points, $Polyline)
    $pointList = @($Points)
    $lineList = @($Polyline)
    if ($pointList.Count -lt 1 -or $lineList.Count -lt 2) {
        return [double]::PositiveInfinity
    }
    $maximum = 0.0
    foreach ($point in $pointList) {
        $minimum = [double]::PositiveInfinity
        for ($index = 0; $index -lt $lineList.Count - 1; $index++) {
            $distance = Point-Segment-Distance `
                $point $lineList[$index] $lineList[$index + 1]
            if ($distance -lt $minimum) {
                $minimum = $distance
            }
        }
        if ($minimum -gt $maximum) {
            $maximum = $minimum
        }
    }
    return $maximum
}

function Add-Mismatch {
    param(
        [Collections.Generic.List[object]]$Items,
        [string]$Checkpoint,
        [string]$Path,
        $Expected,
        $Actual,
        [string]$Rule
    )
    $Items.Add([pscustomobject][ordered]@{
        checkpoint = $Checkpoint
        path = $Path
        expected = $Expected
        actual = $Actual
        rule = $Rule
    })
}

function Property-Exists {
    param($Source, [string]$Name)
    return $null -ne $Source -and
        $null -ne $Source.PSObject.Properties[$Name]
}

function Compare-ExactField {
    param(
        [Collections.Generic.List[object]]$Items,
        [string]$Checkpoint,
        [string]$Path,
        $Reference,
        $Candidate,
        [string]$Field
    )
    if (-not (Property-Exists $Reference $Field) -or
        -not (Property-Exists $Candidate $Field)) {
        return
    }
    $expected = $Reference.$Field
    $actual = $Candidate.$Field
    if ([string]$expected -cne [string]$actual) {
        Add-Mismatch $Items $Checkpoint "$Path.$Field" `
            $expected $actual 'exact'
    }
}

$reference = Read-Trace $ReferenceTrace
$candidate = Read-Trace $CandidateTrace
$mismatches = [Collections.Generic.List[object]]::new()
$routeShapeMetrics = [Collections.Generic.List[object]]::new()
$sceneFilter = @{}
foreach ($sceneIndex in @($SceneIndices | Sort-Object -Unique)) {
    $sceneFilter[[int]$sceneIndex] = $true
}

foreach ($field in @('content_profile')) {
    Compare-ExactField $mismatches 'trace' 'trace' `
        $reference $candidate $field
}
foreach ($field in @('id', 'selector_level', 'engine_mission')) {
    Compare-ExactField $mismatches 'trace' 'level' `
        $reference.level $candidate.level $field
}
foreach ($field in @('id', 'coordinate_space')) {
    Compare-ExactField $mismatches 'trace' 'scenario' `
        $reference.scenario $candidate.scenario $field
}

$referenceCheckpoints = @($reference.checkpoints)
$candidateCheckpoints = @($candidate.checkpoints)
$candidateById = @{}
foreach ($checkpoint in $candidateCheckpoints) {
    $id = [string]$checkpoint.id
    if ($candidateById.ContainsKey($id)) {
        Add-Mismatch $mismatches $id 'checkpoint.id' `
            'unique' 'duplicate' 'unique'
    }
    else {
        $candidateById[$id] = $checkpoint
    }
}

foreach ($referenceCheckpoint in $referenceCheckpoints) {
    $checkpointId = [string]$referenceCheckpoint.id
    if (-not $candidateById.ContainsKey($checkpointId)) {
        Add-Mismatch $mismatches $checkpointId 'checkpoint' `
            'present' 'missing' 'required'
        continue
    }
    $candidateCheckpoint = $candidateById[$checkpointId]
    $referenceIndex = [Array]::IndexOf(
        $referenceCheckpoints, $referenceCheckpoint)
    if ($referenceIndex -gt 0 -and
        $checkpointId -cne 'player_selected') {
        $previousReference = $referenceCheckpoints[$referenceIndex - 1]
        $previousId = [string]$previousReference.id
        if ($candidateById.ContainsKey($previousId)) {
            $previousCandidate = $candidateById[$previousId]
            $referenceInterval =
                [double]$referenceCheckpoint.elapsed_ms -
                [double]$previousReference.elapsed_ms
            $candidateInterval =
                [double]$candidateCheckpoint.elapsed_ms -
                [double]$previousCandidate.elapsed_ms
            $intervalDelta = [Math]::Abs(
                $referenceInterval - $candidateInterval)
            if ($intervalDelta -gt $ElapsedToleranceMs) {
                Add-Mismatch $mismatches $checkpointId `
                    'checkpoint.delta_ms' `
                    $referenceInterval `
                    $candidateInterval `
                    "interval tolerance $ElapsedToleranceMs ms"
            }
        }
    }

    $referenceViewport = @($referenceCheckpoint.camera.viewport) -join ','
    $candidateViewport = @($candidateCheckpoint.camera.viewport) -join ','
    if ($referenceViewport -ceq $candidateViewport) {
        $cameraDistance = Point-Distance `
            @($referenceCheckpoint.camera.position) `
            @($candidateCheckpoint.camera.position)
        if ($cameraDistance -gt $CameraTolerance) {
            Add-Mismatch $mismatches $checkpointId 'camera.position' `
                @($referenceCheckpoint.camera.position) `
                @($candidateCheckpoint.camera.position) `
                "Euclidean tolerance $CameraTolerance px"
        }
    }

    Compare-ExactField $mismatches $checkpointId 'mission' `
        $referenceCheckpoint.mission $candidateCheckpoint.mission 'id'
    Compare-ExactField $mismatches $checkpointId 'mission' `
        $referenceCheckpoint.mission $candidateCheckpoint.mission 'status'

    if ($CompareObservedRouteShape -and
        $checkpointId.EndsWith(
            '_observed',
            [StringComparison]::OrdinalIgnoreCase)) {
        $commandedId = $checkpointId.Substring(
            0,
            $checkpointId.Length - '_observed'.Length) +
            '_commanded'
        $candidateCommanded = if (
            $candidateById.ContainsKey($commandedId)) {
            $candidateById[$commandedId]
        }
        else {
            $null
        }
        $referenceObserved = if (
            (Property-Exists $referenceCheckpoint 'tags') -and
            (Property-Exists $referenceCheckpoint.tags 'observed_positions')) {
            @($referenceCheckpoint.tags.observed_positions)
        }
        else {
            @()
        }
        $candidateObserved = if (
            (Property-Exists $candidateCheckpoint 'tags') -and
            (Property-Exists $candidateCheckpoint.tags 'observed_positions')) {
            @($candidateCheckpoint.tags.observed_positions)
        }
        else {
            @()
        }
        $candidatePath = if (
            $null -ne $candidateCommanded -and
            (Property-Exists $candidateCommanded 'tags') -and
            (Property-Exists $candidateCommanded.tags 'path')) {
            @($candidateCommanded.tags.path)
        }
        else {
            @()
        }
        if ($referenceObserved.Count -lt 2 -or
            $candidateObserved.Count -lt 2 -or
            $candidatePath.Count -lt 2) {
            Add-Mismatch $mismatches $checkpointId `
                'tags.observed_route_shape' `
                @{
                    reference_observed_minimum = 2
                    candidate_observed_minimum = 2
                    candidate_path_minimum = 2
                } `
                @{
                    reference_observed = $referenceObserved.Count
                    candidate_observed = $candidateObserved.Count
                    candidate_path = $candidatePath.Count
                } `
                'required route-shape evidence'
        }
        else {
            $referenceToCandidatePath =
                Maximum-Point-To-Polyline-Distance `
                    $referenceObserved $candidatePath
            $candidateObservedToReference =
                Maximum-Point-To-Polyline-Distance `
                    $candidateObserved $referenceObserved
            $candidateObservedToPath =
                Maximum-Point-To-Polyline-Distance `
                    $candidateObserved $candidatePath
            $routeMetric = [pscustomobject][ordered]@{
                checkpoint = $checkpointId
                reference_observed_points = $referenceObserved.Count
                candidate_observed_points = $candidateObserved.Count
                candidate_path_points = $candidatePath.Count
                reference_to_candidate_path_px = [Math]::Round(
                    $referenceToCandidatePath,
                    6)
                candidate_observed_to_reference_px = [Math]::Round(
                    $candidateObservedToReference,
                    6)
                candidate_observed_to_candidate_path_px = [Math]::Round(
                    $candidateObservedToPath,
                    6)
            }
            $routeShapeMetrics.Add($routeMetric)
            foreach ($measurement in @(
                [pscustomobject]@{
                    path = 'tags.observed_positions.reference_to_candidate_path'
                    value = $referenceToCandidatePath
                },
                [pscustomobject]@{
                    path = 'tags.observed_positions.candidate_to_reference'
                    value = $candidateObservedToReference
                },
                [pscustomobject]@{
                    path = 'tags.observed_positions.candidate_to_candidate_path'
                    value = $candidateObservedToPath
                }
            )) {
                if ([double]$measurement.value -gt $RouteShapeTolerance) {
                    Add-Mismatch $mismatches $checkpointId `
                        ([string]$measurement.path) `
                        "<= $RouteShapeTolerance" `
                        ([Math]::Round([double]$measurement.value, 6)) `
                        "directed point-to-polyline tolerance $RouteShapeTolerance px"
                }
            }
        }
    }

    $referenceActors = @($referenceCheckpoint.actors)
    $candidateActors = @($candidateCheckpoint.actors)
    if ($sceneFilter.Count -gt 0) {
        $referenceActors = @(
            $referenceActors |
                Where-Object {
                    $sceneFilter.ContainsKey([int]$_.scene_index)
                })
        $candidateActors = @(
            $candidateActors |
                Where-Object {
                    $sceneFilter.ContainsKey([int]$_.scene_index)
                })
    }
    $referenceByScene = @{}
    $candidateByScene = @{}
    foreach ($actor in $referenceActors) {
        $referenceByScene[[int]$actor.scene_index] = $actor
    }
    foreach ($actor in $candidateActors) {
        $candidateByScene[[int]$actor.scene_index] = $actor
    }
    foreach ($sceneIndex in $referenceByScene.Keys) {
        if (-not $candidateByScene.ContainsKey($sceneIndex)) {
            Add-Mismatch $mismatches $checkpointId `
                "actors.scene:$sceneIndex" 'present' 'missing' 'required'
            continue
        }
        $referenceActor = $referenceByScene[$sceneIndex]
        $candidateActor = $candidateByScene[$sceneIndex]
        $actorPath = "actors.scene:$sceneIndex"
        $exactActorFields = @(
            'actor_id',
            'role',
            'database_entry_id',
            'faction_id'
        )
        if (-not $IgnoreAliveState) {
            $exactActorFields += 'alive'
        }
        if (-not $checkpointId.EndsWith(
                '_commanded',
                [StringComparison]::OrdinalIgnoreCase)) {
            $exactActorFields += 'facing_direction'
        }
        foreach ($field in $exactActorFields) {
            Compare-ExactField $mismatches $checkpointId $actorPath `
                $referenceActor $candidateActor $field
        }
        if (-not $IgnoreHitPoints) {
            foreach ($field in @('current', 'maximum')) {
                if ((Property-Exists $referenceActor 'hit_points') -and
                    (Property-Exists $candidateActor 'hit_points')) {
                    Compare-ExactField $mismatches $checkpointId `
                        "$actorPath.hit_points" `
                        $referenceActor.hit_points `
                        $candidateActor.hit_points $field
                }
            }
        }
        foreach ($field in @(
            'attack_type',
            'magazine_ammo',
            'reserve_ammo',
            'infinite_ammo'
        )) {
            if ((Property-Exists $referenceActor 'weapon') -and
                (Property-Exists $candidateActor 'weapon')) {
                Compare-ExactField $mismatches $checkpointId `
                    "$actorPath.weapon" `
                    $referenceActor.weapon `
                    $candidateActor.weapon $field
            }
        }

        if ($checkpointId.EndsWith(
                '_observed',
                [StringComparison]::OrdinalIgnoreCase)) {
            $commandedId = $checkpointId.Substring(
                0,
                $checkpointId.Length - '_observed'.Length) +
                '_commanded'
            $referenceCommanded = @($referenceCheckpoints |
                Where-Object { [string]$_.id -ceq $commandedId }) |
                Select-Object -First 1
            $candidateCommanded = if (
                $candidateById.ContainsKey($commandedId)) {
                $candidateById[$commandedId]
            }
            else {
                $null
            }
            $referenceCommandActor = @(
                $referenceCommanded.actors |
                Where-Object { [int]$_.scene_index -eq $sceneIndex }
            ) | Select-Object -First 1
            $candidateCommandActor = @(
                $candidateCommanded.actors |
                Where-Object { [int]$_.scene_index -eq $sceneIndex }
            ) | Select-Object -First 1
            if ($null -ne $referenceCommandActor -and
                $null -ne $candidateCommandActor) {
                $referenceReachedTarget = (
                    Point-Distance `
                        @($referenceActor.position) `
                        @($referenceActor.target_position)
                ) -le $TargetTolerance
                $candidateReachedTarget = (
                    Point-Distance `
                        @($candidateActor.position) `
                        @($candidateActor.target_position)
                ) -le $TargetTolerance
                if (-not (
                    $referenceReachedTarget -and
                    $candidateReachedTarget)) {
                    $referenceMovement = @(
                        (
                            [double]$referenceActor.position[0] -
                            [double]$referenceCommandActor.position[0]
                        )
                        (
                            [double]$referenceActor.position[1] -
                            [double]$referenceCommandActor.position[1]
                        )
                    )
                    $candidateMovement = @(
                        (
                            [double]$candidateActor.position[0] -
                            [double]$candidateCommandActor.position[0]
                        )
                        (
                            [double]$candidateActor.position[1] -
                            [double]$candidateCommandActor.position[1]
                        )
                    )
                    $movementDistance = Point-Distance `
                        $referenceMovement $candidateMovement
                    if ($movementDistance -gt $PositionTolerance) {
                        Add-Mismatch $mismatches $checkpointId `
                            "$actorPath.movement_delta" `
                            $referenceMovement $candidateMovement `
                            "Euclidean tolerance $PositionTolerance px"
                    }
                }
            }
        }
        elseif (-not $checkpointId.EndsWith(
                '_commanded',
                [StringComparison]::OrdinalIgnoreCase)) {
            $positionDistance = Point-Distance `
                @($referenceActor.position) @($candidateActor.position)
            if ($positionDistance -gt $PositionTolerance) {
                Add-Mismatch $mismatches $checkpointId "$actorPath.position" `
                    @($referenceActor.position) @($candidateActor.position) `
                    "Euclidean tolerance $PositionTolerance px"
            }
        }
        $targetDistance = Point-Distance `
            @($referenceActor.target_position) `
            @($candidateActor.target_position)
        if ($targetDistance -gt $TargetTolerance) {
            Add-Mismatch $mismatches $checkpointId `
                "$actorPath.target_position" `
                @($referenceActor.target_position) `
                @($candidateActor.target_position) `
                "Euclidean tolerance $TargetTolerance px"
        }
    }
    if ($RequireExactActorSet) {
        foreach ($sceneIndex in $candidateByScene.Keys) {
            if (-not $referenceByScene.ContainsKey($sceneIndex)) {
                Add-Mismatch $mismatches $checkpointId `
                    "actors.scene:$sceneIndex" 'absent' 'unexpected' 'exact actor set'
            }
        }
    }
}
foreach ($candidateCheckpoint in $candidateCheckpoints) {
    $checkpointId = [string]$candidateCheckpoint.id
    if (@($referenceCheckpoints |
            Where-Object { [string]$_.id -ceq $checkpointId }).Count -eq 0) {
        Add-Mismatch $mismatches $checkpointId 'checkpoint' `
            'absent' 'unexpected' 'exact checkpoint set'
    }
}

$result = [pscustomobject][ordered]@{
    schema_version = 1
    reference_runtime = [string]$reference.runtime
    candidate_runtime = [string]$candidate.runtime
    level_id = [string]$reference.level.id
    scenario_id = [string]$reference.scenario.id
    reference_checkpoints = $referenceCheckpoints.Count
    candidate_checkpoints = $candidateCheckpoints.Count
    mismatch_count = $mismatches.Count
    passed = $mismatches.Count -eq 0
    tolerances = [pscustomobject][ordered]@{
        position_px = $PositionTolerance
        target_px = $TargetTolerance
        camera_px = $CameraTolerance
        elapsed_ms = $ElapsedToleranceMs
        scene_indices = @($sceneFilter.Keys | Sort-Object)
        ignore_hit_points = [bool]$IgnoreHitPoints
        ignore_alive_state = [bool]$IgnoreAliveState
        exact_actor_set = [bool]$RequireExactActorSet
        compare_observed_route_shape = [bool]$CompareObservedRouteShape
        route_shape_px = $RouteShapeTolerance
    }
    route_shape_metrics = @($routeShapeMetrics)
    mismatches = @($mismatches)
}

if (-not [string]::IsNullOrWhiteSpace($OutputJson)) {
    $OutputJson = [IO.Path]::GetFullPath($OutputJson)
    [IO.Directory]::CreateDirectory(
        [IO.Path]::GetDirectoryName($OutputJson)) | Out-Null
    $result | ConvertTo-Json -Depth 20 |
        Set-Content -LiteralPath $OutputJson -Encoding UTF8
}
if (-not [string]::IsNullOrWhiteSpace($OutputMarkdown)) {
    $OutputMarkdown = [IO.Path]::GetFullPath($OutputMarkdown)
    [IO.Directory]::CreateDirectory(
        [IO.Path]::GetDirectoryName($OutputMarkdown)) | Out-Null
    $lines = [Collections.Generic.List[string]]::new()
    $lines.Add('# Runtime Parity Comparison')
    $lines.Add('')
    $lines.Add("- Level/scenario: $($result.level_id) / $($result.scenario_id)")
    $lines.Add("- Result: $(if ($result.passed) { 'pass' } else { 'mismatch' })")
    $lines.Add("- Mismatches: $($result.mismatch_count)")
    $lines.Add('')
    $lines.Add('| Checkpoint | Path | Expected | Actual | Rule |')
    $lines.Add('|---|---|---|---|---|')
    foreach ($item in $mismatches) {
        $expected = ($item.expected | ConvertTo-Json -Compress -Depth 10)
        $actual = ($item.actual | ConvertTo-Json -Compress -Depth 10)
        $lines.Add(
            '| {0} | {1} | {2} | {3} | {4} |' -f @(
                ([string]$item.checkpoint).Replace('|', '\|'),
                ([string]$item.path).Replace('|', '\|'),
                ([string]$expected).Replace('|', '\|'),
                ([string]$actual).Replace('|', '\|'),
                ([string]$item.rule).Replace('|', '\|')))
    }
    $lines | Set-Content -LiteralPath $OutputMarkdown -Encoding UTF8
}

if (-not $result.passed -and -not $AllowMismatch) {
    throw (
        "Runtime parity comparison failed with $($result.mismatch_count) " +
        "mismatches for $($result.level_id)/$($result.scenario_id).")
}
$result
