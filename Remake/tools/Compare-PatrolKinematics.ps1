[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ReferenceTrace,
    [Parameter(Mandatory)]
    [string]$CandidateTrace,
    [ValidateRange(0, 100)]
    [double]$MaximumDisplacementTolerance = 4,
    [ValidateRange(0, 100)]
    [double]$Percentile90Tolerance = 4,
    [ValidateRange(0, 46)]
    [int]$MovingActorCountTolerance = 2,
    [ValidateRange(0, 46)]
    [int]$StationaryActorCountTolerance = 1,
    [string]$OutputJson = '',
    [switch]$AllowMismatch
)

$ErrorActionPreference = 'Stop'

function Read-Trace {
    param([string]$Path)
    return Get-Content -LiteralPath (Resolve-Path -LiteralPath $Path).Path `
        -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Point-Distance {
    param($First, $Second)
    $dx = [double]$Second[0] - [double]$First[0]
    $dy = [double]$Second[1] - [double]$First[1]
    return [Math]::Sqrt($dx * $dx + $dy * $dy)
}

function Percentile {
    param([double[]]$Values, [double]$Fraction)
    if ($Values.Count -eq 0) {
        return 0.0
    }
    $ordered = @($Values | Sort-Object)
    $index = [Math]::Max(
        0,
        [Math]::Min(
            $ordered.Count - 1,
            [Math]::Ceiling($ordered.Count * $Fraction) - 1))
    return [double]$ordered[$index]
}

function Add-Mismatch {
    param(
        [Collections.Generic.List[object]]$Target,
        [string]$Path,
        $Expected,
        $Actual,
        [string]$Rule
    )
    $Target.Add([pscustomobject][ordered]@{
        path = $Path
        expected = $Expected
        actual = $Actual
        rule = $Rule
    })
}

$reference = Read-Trace $ReferenceTrace
$candidate = Read-Trace $CandidateTrace
$mismatches = [Collections.Generic.List[object]]::new()
if ($reference.scenario.id -ne 'm000-enemy-patrol-v1' -or
    $candidate.scenario.id -ne $reference.scenario.id -or
    $candidate.level.id -ne $reference.level.id -or
    $candidate.content_profile -ne $reference.content_profile) {
    throw 'Patrol traces do not share the m000 stable-MOD identity.'
}

$referenceCheckpoints = @($reference.checkpoints)
$candidateCheckpoints = @($candidate.checkpoints)
$expectedCheckpointIds = @(
    'patrol_interval_1_commanded',
    'patrol_interval_1_observed',
    'patrol_interval_2_commanded',
    'patrol_interval_2_observed'
)
if ($referenceCheckpoints.Count -ne 4 -or
    $candidateCheckpoints.Count -ne 4 -or
    (Compare-Object $expectedCheckpointIds @($referenceCheckpoints.id)).Count -ne 0 -or
    (Compare-Object $expectedCheckpointIds @($candidateCheckpoints.id)).Count -ne 0) {
    throw 'Patrol traces must contain the two commanded/observed intervals.'
}

$referenceActors = @($referenceCheckpoints[0].actors)
$candidateByScene = @{}
foreach ($actor in @($candidateCheckpoints[0].actors)) {
    $candidateByScene[[int]$actor.scene_index] = $actor
}
if ($referenceActors.Count -ne 46) {
    throw 'The stable m000 patrol baseline must contain 46 audited enemies.'
}
foreach ($actor in $referenceActors) {
    $sceneIndex = [int]$actor.scene_index
    if (-not $candidateByScene.ContainsKey($sceneIndex)) {
        Add-Mismatch $mismatches "actors.scene:$sceneIndex" `
            'present' 'missing' 'required audited identity'
        continue
    }
    $actual = $candidateByScene[$sceneIndex]
    foreach ($field in @('role', 'database_entry_id', 'faction_id')) {
        if ([string]$actual.$field -cne [string]$actor.$field) {
            Add-Mismatch $mismatches "actors.scene:$sceneIndex.$field" `
                $actor.$field $actual.$field 'exact identity'
        }
    }
}

$intervalResults = @()
foreach ($interval in 0, 1) {
    $startIndex = $interval * 2
    $endIndex = $startIndex + 1
    $referenceStartByScene = @{}
    $referenceEndByScene = @{}
    $candidateStartByScene = @{}
    $candidateEndByScene = @{}
    foreach ($actor in @($referenceCheckpoints[$startIndex].actors)) {
        $referenceStartByScene[[int]$actor.scene_index] = $actor
    }
    foreach ($actor in @($referenceCheckpoints[$endIndex].actors)) {
        $referenceEndByScene[[int]$actor.scene_index] = $actor
    }
    foreach ($actor in @($candidateCheckpoints[$startIndex].actors)) {
        $candidateStartByScene[[int]$actor.scene_index] = $actor
    }
    foreach ($actor in @($candidateCheckpoints[$endIndex].actors)) {
        $candidateEndByScene[[int]$actor.scene_index] = $actor
    }
    $referenceDistances = [Collections.Generic.List[double]]::new()
    $candidateDistances = [Collections.Generic.List[double]]::new()
    foreach ($actor in $referenceActors) {
        $sceneIndex = [int]$actor.scene_index
        if (-not $candidateStartByScene.ContainsKey($sceneIndex) -or
            -not $candidateEndByScene.ContainsKey($sceneIndex)) {
            continue
        }
        $referenceDistances.Add(
            (Point-Distance `
                $referenceStartByScene[$sceneIndex].position `
                $referenceEndByScene[$sceneIndex].position))
        $candidateDistances.Add(
            (Point-Distance `
                $candidateStartByScene[$sceneIndex].position `
                $candidateEndByScene[$sceneIndex].position))
    }
    $referenceValues = @($referenceDistances)
    $candidateValues = @($candidateDistances)
    $referenceMetrics = [ordered]@{
        maximum = [Math]::Round(
            ($referenceValues | Measure-Object -Maximum).Maximum, 3)
        percentile_90 = [Math]::Round(
            (Percentile $referenceValues 0.90), 3)
        moving_actor_count = @($referenceValues |
            Where-Object { $_ -gt 10.0 }).Count
        stationary_actor_count = @($referenceValues |
            Where-Object { $_ -le 2.0 }).Count
    }
    $candidateMetrics = [ordered]@{
        maximum = [Math]::Round(
            ($candidateValues | Measure-Object -Maximum).Maximum, 3)
        percentile_90 = [Math]::Round(
            (Percentile $candidateValues 0.90), 3)
        moving_actor_count = @($candidateValues |
            Where-Object { $_ -gt 10.0 }).Count
        stationary_actor_count = @($candidateValues |
            Where-Object { $_ -le 2.0 }).Count
    }
    $intervalId = $interval + 1
    if ([Math]::Abs(
            $referenceMetrics.maximum -
            $candidateMetrics.maximum) -gt
        $MaximumDisplacementTolerance) {
        Add-Mismatch $mismatches "interval:$intervalId.maximum" `
            $referenceMetrics.maximum $candidateMetrics.maximum `
            "absolute tolerance $MaximumDisplacementTolerance px"
    }
    if ([Math]::Abs(
            $referenceMetrics.percentile_90 -
            $candidateMetrics.percentile_90) -gt
        $Percentile90Tolerance) {
        Add-Mismatch $mismatches "interval:$intervalId.percentile_90" `
            $referenceMetrics.percentile_90 `
            $candidateMetrics.percentile_90 `
            "absolute tolerance $Percentile90Tolerance px"
    }
    if ([Math]::Abs(
            $referenceMetrics.moving_actor_count -
            $candidateMetrics.moving_actor_count) -gt
        $MovingActorCountTolerance) {
        Add-Mismatch $mismatches "interval:$intervalId.moving_actor_count" `
            $referenceMetrics.moving_actor_count `
            $candidateMetrics.moving_actor_count `
            "absolute tolerance $MovingActorCountTolerance actors"
    }
    if ([Math]::Abs(
            $referenceMetrics.stationary_actor_count -
            $candidateMetrics.stationary_actor_count) -gt
        $StationaryActorCountTolerance) {
        Add-Mismatch $mismatches "interval:$intervalId.stationary_actor_count" `
            $referenceMetrics.stationary_actor_count `
            $candidateMetrics.stationary_actor_count `
            "absolute tolerance $StationaryActorCountTolerance actors"
    }
    $intervalResults += [pscustomobject][ordered]@{
        id = $intervalId
        reference = [pscustomobject]$referenceMetrics
        candidate = [pscustomobject]$candidateMetrics
    }
}

$result = [pscustomobject][ordered]@{
    schema_version = 1
    level_id = [string]$reference.level.id
    scenario_id = [string]$reference.scenario.id
    audited_actor_count = $referenceActors.Count
    interval_metrics = $intervalResults
    mismatch_count = $mismatches.Count
    passed = $mismatches.Count -eq 0
    mismatches = @($mismatches)
}
if (-not [string]::IsNullOrWhiteSpace($OutputJson)) {
    $OutputJson = [IO.Path]::GetFullPath($OutputJson)
    [IO.Directory]::CreateDirectory(
        [IO.Path]::GetDirectoryName($OutputJson)) | Out-Null
    $result | ConvertTo-Json -Depth 12 |
        Set-Content -LiteralPath $OutputJson -Encoding UTF8
}
if (-not $result.passed -and -not $AllowMismatch) {
    throw (
        "Patrol kinematics comparison failed with " +
        "$($mismatches.Count) mismatches.")
}
$result
