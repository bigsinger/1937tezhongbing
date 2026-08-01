[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ReferenceTrace,
    [Parameter(Mandatory)]
    [string]$CandidateTrace,
    [string]$OutputJson = '',
    [string]$OutputMarkdown = ''
)

$ErrorActionPreference = 'Stop'

function Read-Trace {
    param([Parameter(Mandatory)][string]$Path)
    $resolved = (Resolve-Path -LiteralPath $Path).Path
    $trace = Get-Content -LiteralPath $resolved -Raw -Encoding UTF8 |
        ConvertFrom-Json
    if ([int]$trace.schema_version -ne 1) {
        throw "Unsupported native mission trace schema: $resolved"
    }
    return $trace
}

function Checkpoint-ById {
    param($Trace, [string]$Id)
    return @($Trace.checkpoints |
        Where-Object { [string]$_.id -ceq $Id } |
        Select-Object -First 1)[0]
}

function Candidate-Actor {
    param($Checkpoint, [int]$SceneIndex)
    return @($Checkpoint.actors |
        Where-Object { [int]$_.scene_index -eq $SceneIndex } |
        Select-Object -First 1)[0]
}

$reference = Read-Trace $ReferenceTrace
$candidate = Read-Trace $CandidateTrace
$mismatches = [Collections.Generic.List[object]]::new()
$checkCount = 0

function Expect-Exact {
    param(
        [string]$Path,
        $Expected,
        $Actual
    )
    $script:checkCount++
    if ([string]$Expected -cne [string]$Actual) {
        $script:mismatches.Add([pscustomobject][ordered]@{
            path = $Path
            expected = $Expected
            actual = $Actual
            rule = 'exact'
        })
    }
}

function Expect-Near {
    param(
        [string]$Path,
        [double]$Expected,
        [double]$Actual,
        [double]$Tolerance
    )
    $script:checkCount++
    if ([Math]::Abs($Expected - $Actual) -gt $Tolerance) {
        $script:mismatches.Add([pscustomobject][ordered]@{
            path = $Path
            expected = $Expected
            actual = $Actual
            rule = "absolute tolerance $Tolerance"
        })
    }
}

Expect-Exact 'content_profile' `
    $reference.content_profile $candidate.content_profile
foreach ($field in @('id', 'selector_level', 'engine_mission')) {
    Expect-Exact "level.$field" `
        $reference.level.$field $candidate.level.$field
}
Expect-Exact 'scenario.id' `
    $reference.scenario.id $candidate.scenario.id

$sceneIndex = -1
$referenceActive = Checkpoint-ById $reference 'gameplay_active'
$referenceFailed = Checkpoint-ById $reference 'required_player_lost'
$candidateActive = Checkpoint-ById $candidate 'gameplay_active'
$candidateFailed = Checkpoint-ById $candidate 'required_player_lost'
foreach ($checkpoint in @(
    [pscustomobject]@{
        path = 'reference.gameplay_active'
        value = $referenceActive
    },
    [pscustomobject]@{
        path = 'reference.required_player_lost'
        value = $referenceFailed
    },
    [pscustomobject]@{
        path = 'candidate.gameplay_active'
        value = $candidateActive
    },
    [pscustomobject]@{
        path = 'candidate.required_player_lost'
        value = $candidateFailed
    }
)) {
    $script:checkCount++
    if ($null -eq $checkpoint.value) {
        $mismatches.Add([pscustomobject][ordered]@{
            path = [string]$checkpoint.path
            expected = 'present'
            actual = 'missing'
            rule = 'required checkpoint'
        })
    }
}

if ($mismatches.Count -eq 0) {
    $sceneIndex = [int]$referenceActive.actor.scene_index
    $checkCount++
    if ($sceneIndex -le 0 -or
        [int]$referenceFailed.actor.scene_index -ne $sceneIndex) {
        $mismatches.Add([pscustomobject][ordered]@{
            path = 'reference.required_actor.scene_index'
            expected = 'matching positive scene identity'
            actual = (
                "$($referenceActive.actor.scene_index)->" +
                "$($referenceFailed.actor.scene_index)")
            rule = 'required actor identity'
        })
    }
}

if ($mismatches.Count -eq 0) {
    $candidateActiveActor = Candidate-Actor $candidateActive $sceneIndex
    $candidateFailedActor = Candidate-Actor $candidateFailed $sceneIndex
    foreach ($actorCheck in @(
        [pscustomobject]@{
            path = 'candidate.gameplay_active.actor'
            value = $candidateActiveActor
        },
        [pscustomobject]@{
            path = 'candidate.required_player_lost.actor'
            value = $candidateFailedActor
        }
    )) {
        $checkCount++
        if ($null -eq $actorCheck.value) {
            $mismatches.Add([pscustomobject][ordered]@{
                path = [string]$actorCheck.path
                expected = "scene $sceneIndex present"
                actual = 'missing'
                rule = 'required actor'
            })
        }
    }

    if ($null -ne $candidateActiveActor -and
        $null -ne $candidateFailedActor) {
        Expect-Exact 'gameplay_active.mission.status' `
            $referenceActive.mission.status `
            $candidateActive.mission.status
        Expect-Exact 'required_player_lost.mission.status' `
            $referenceFailed.mission.status `
            $candidateFailed.mission.status
        Expect-Exact 'required_player_lost.mission.failure_id' `
            $referenceFailed.mission.semantic_failure_id `
            $candidateFailed.mission.failure_id
        Expect-Exact 'required_player_lost.result_state' `
            $referenceFailed.mission.result_state `
            $candidateFailed.tags.original_result_state
        Expect-Exact 'gameplay_active.actor.faction_id' `
            $referenceActive.actor.faction_id `
            $candidateActiveActor.faction_id
        Expect-Exact 'gameplay_active.actor.runtime_type' `
            $referenceActive.actor.runtime_type `
            $candidateActiveActor.native.runtime_type
        Expect-Exact 'gameplay_active.actor.current_hit_points' `
            $referenceActive.actor.current_hit_points `
            $candidateActiveActor.hit_points.current
        Expect-Exact 'required_player_lost.actor.current_hit_points' `
            $referenceFailed.actor.current_hit_points `
            $candidateFailedActor.hit_points.current
        Expect-Exact 'gameplay_active.actor.alive' `
            (1 - [int]$referenceActive.actor.dead_or_disabled) `
            ([int][bool]$candidateActiveActor.alive)
        Expect-Exact 'required_player_lost.actor.alive' `
            (1 - [int]$referenceFailed.actor.dead_or_disabled) `
            ([int][bool]$candidateFailedActor.alive)
        Expect-Exact 'required_player_lost.actor.damage_event_count' `
            1 $candidateFailedActor.native.damage_event_count
        Expect-Exact 'required_player_lost.actor.damage_taken_total' `
            $referenceActive.actor.current_hit_points `
            $candidateFailedActor.native.damage_taken_total
        Expect-Near 'gameplay_active.actor.position.x' `
            ([double]$referenceActive.actor.position[0]) `
            ([double]$candidateActiveActor.position[0]) 0.01
        Expect-Near 'gameplay_active.actor.position.y' `
            ([double]$referenceActive.actor.position[1]) `
            ([double]$candidateActiveActor.position[1]) 0.01
    }
}

$result = [pscustomobject][ordered]@{
    schema_version = 1
    comparison_id = [string]$reference.scenario.id
    passed = $mismatches.Count -eq 0
    check_count = $checkCount
    reference = (Resolve-Path -LiteralPath $ReferenceTrace).Path
    candidate = (Resolve-Path -LiteralPath $CandidateTrace).Path
    evidence = [pscustomobject][ordered]@{
        scene_index = $sceneIndex
        original_damage_entry = 'sub_458700'
        original_mission_evaluator = 'sub_405410'
        expected_result_state = 2
        expected_failure_id = 'required_character_lost'
    }
    mismatches = @($mismatches)
}

if (-not [string]::IsNullOrWhiteSpace($OutputJson)) {
    $fullOutputJson = [IO.Path]::GetFullPath($OutputJson)
    [IO.Directory]::CreateDirectory(
        [IO.Path]::GetDirectoryName($fullOutputJson)) | Out-Null
    $result | ConvertTo-Json -Depth 12 |
        Set-Content -LiteralPath $fullOutputJson -Encoding UTF8
}
if (-not [string]::IsNullOrWhiteSpace($OutputMarkdown)) {
    $fullOutputMarkdown = [IO.Path]::GetFullPath($OutputMarkdown)
    [IO.Directory]::CreateDirectory(
        [IO.Path]::GetDirectoryName($fullOutputMarkdown)) | Out-Null
    $status = if ($result.passed) { 'PASS' } else { 'FAIL' }
    $lines = [Collections.Generic.List[string]]::new()
    $lines.Add('# Native mission failure parity')
    $lines.Add('')
    $lines.Add("- Status: **$status**")
    $lines.Add("- Checks: $checkCount")
    $lines.Add("- Scene: $sceneIndex")
    $lines.Add('- Original path: `sub_458700` -> `sub_405410` -> result 2')
    if ($mismatches.Count -gt 0) {
        $lines.Add('')
        $lines.Add('## Mismatches')
        foreach ($mismatch in $mismatches) {
            $lines.Add(
                ('- `{0}`: expected `{1}`, actual `{2}`' -f
                    $mismatch.path,
                    $mismatch.expected,
                    $mismatch.actual))
        }
    }
    $lines | Set-Content -LiteralPath $fullOutputMarkdown -Encoding UTF8
}

$result
if (-not $result.passed) {
    exit 1
}
