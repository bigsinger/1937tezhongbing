[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ReferenceTrace,
    [Parameter(Mandatory)]
    [string]$CandidateTrace,
    [string]$OutputJson = '',
    [string]$OutputMarkdown = '',
    [switch]$AllowMismatch
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Read-Trace {
    param([Parameter(Mandatory)][string]$Path)
    $resolved = (Resolve-Path -LiteralPath $Path).Path
    $raw = [IO.File]::ReadAllText($resolved, [Text.Encoding]::UTF8)
    $trace = $raw | ConvertFrom-Json
    if ([int]$trace.schema_version -ne 1) {
        throw "Unsupported human-input mission trace schema: $resolved"
    }
    return $trace
}

function Checkpoint-ById {
    param($Trace, [string]$Id)
    return @(
        $Trace.checkpoints |
            Where-Object { [string]$_.id -ceq $Id } |
            Select-Object -First 1
    )[0]
}

function Candidate-Actor {
    param($Checkpoint, [int]$SceneIndex)
    if ($null -eq $Checkpoint) {
        return $null
    }
    return @(
        $Checkpoint.actors |
            Where-Object { [int]$_.scene_index -eq $SceneIndex } |
            Select-Object -First 1
    )[0]
}

function Test-MonotonicDeathSequence {
    param($Values)
    $samples = @($Values | ForEach-Object { [int]$_ })
    if ($samples.Count -lt 2 -or $samples[0] -ne 8 -or
        $samples[-1] -ne 0) {
        return $false
    }
    $observedDrop = $false
    for ($index = 1; $index -lt $samples.Count; ++$index) {
        if ($samples[$index] -gt $samples[$index - 1]) {
            return $false
        }
        if ($samples[$index] -lt $samples[$index - 1]) {
            $observedDrop = $true
        }
    }
    return $observedDrop
}

function Expected-ViewportInputEventCount {
    param($Sequence)
    $count = 0
    foreach ($entry in @($Sequence)) {
        switch ([string]$entry.kind) {
            'character_hotkey' { $count += 2 }
            'weapon_hotkey' { $count += 2 }
            'ground_move' { $count += 5 }
            'force_target_attack' { $count += 5 }
            default { return -1 }
        }
    }
    return $count
}

$reference = Read-Trace $ReferenceTrace
$candidate = Read-Trace $CandidateTrace
$mismatches = [Collections.Generic.List[object]]::new()
$checkCount = 0

function Add-Mismatch {
    param(
        [string]$Path,
        $Expected,
        $Actual,
        [string]$Rule
    )
    $script:mismatches.Add([pscustomobject][ordered]@{
        path = $Path
        expected = $Expected
        actual = $Actual
        rule = $Rule
    })
}

function Expect-Exact {
    param([string]$Path, $Expected, $Actual)
    $script:checkCount++
    if ([string]$Expected -cne [string]$Actual) {
        Add-Mismatch $Path $Expected $Actual 'exact'
    }
}

function Expect-True {
    param([string]$Path, [bool]$Condition, $Actual, [string]$Rule)
    $script:checkCount++
    if (-not $Condition) {
        Add-Mismatch $Path $true $Actual $Rule
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
        Add-Mismatch `
            $Path $Expected $Actual "absolute tolerance $Tolerance"
    }
}

Expect-Exact 'reference.runtime' 'mod' $reference.runtime
Expect-Exact 'candidate.runtime' 'remake' $candidate.runtime
Expect-Exact 'content_profile' `
    $reference.content_profile $candidate.content_profile
foreach ($field in @('id', 'selector_level', 'engine_mission')) {
    Expect-Exact "level.$field" `
        $reference.level.$field $candidate.level.$field
}
Expect-Exact 'scenario.id' $reference.scenario.id $candidate.scenario.id
Expect-Exact 'reference.passed' $true $reference.passed
Expect-Exact 'candidate.passed' $true $candidate.passed

foreach ($runtime in @(
    [pscustomobject]@{ name = 'reference'; trace = $reference },
    [pscustomobject]@{ name = 'candidate'; trace = $candidate }
)) {
    Expect-Exact "$($runtime.name).metadata.mission_result_writes" `
        0 $runtime.trace.metadata.mission_result_writes
    Expect-Exact "$($runtime.name).metadata.system_cursor_calls" `
        0 $runtime.trace.metadata.system_cursor_calls
    Expect-Exact "$($runtime.name).metadata.global_focus_calls" `
        0 $runtime.trace.metadata.global_focus_calls
    Expect-Exact "$($runtime.name).metadata.damage_entry" `
        'original_unmodified_gameplay_pipeline' `
        $runtime.trace.metadata.damage_entry
}
Expect-Exact 'reference.metadata.input_isolation' `
    'window-message-to-process-local-DirectInput' `
    $reference.metadata.input_isolation
Expect-Exact 'candidate.metadata.input_isolation' `
    'target-viewport-events' $candidate.metadata.input_isolation
Expect-Exact 'reference.metadata.mission_evaluator' `
    'sub_405410' $reference.metadata.mission_evaluator
Expect-Exact 'candidate.metadata.mission_evaluator' `
    'MissionRuntime.record_event' $candidate.metadata.mission_evaluator

$allowedInputKinds = @('ground_danger_route', 'weapon_noise_lure')
Expect-True 'reference.input.action_kind' `
    ($allowedInputKinds -ccontains [string]$reference.input.action_kind) `
    $reference.input.action_kind 'allowed real-input route'
Expect-True 'candidate.input.action_kind' `
    ($allowedInputKinds -ccontains [string]$candidate.input.action_kind) `
    $candidate.input.action_kind 'allowed real-input route'
Expect-True 'reference.input.input_evidence' `
    (-not [string]::IsNullOrWhiteSpace(
        [string]$reference.input.input_evidence)) `
    $reference.input.input_evidence 'non-empty process-local input evidence'

$sceneIndex = [int]$reference.input.player_scene_index
Expect-True 'reference.input.player_scene_index' `
    ($sceneIndex -gt 0) $sceneIndex 'positive authored scene identity'
Expect-Exact 'candidate.input.player_scene_index' `
    $sceneIndex $candidate.input.player_scene_index
$inputSequence = @($candidate.input.sequence)
Expect-True 'candidate.input.sequence' `
    ($inputSequence.Count -ge 2) $inputSequence.Count `
    'character hotkey plus a gameplay command'
if ($inputSequence.Count -gt 0) {
    Expect-Exact 'candidate.input.sequence[0].kind' `
        'character_hotkey' $inputSequence[0].kind
    Expect-Exact 'candidate.input.sequence[0].scene_index' `
        $sceneIndex $inputSequence[0].scene_index
}
$expectedViewportEvents = Expected-ViewportInputEventCount $inputSequence
Expect-True 'candidate.input.sequence.event_kinds' `
    ($expectedViewportEvents -gt 0) $expectedViewportEvents `
    'all target-viewport inputs have audited event costs'
Expect-Exact 'candidate.input.viewport_input_events' `
    $expectedViewportEvents $candidate.input.viewport_input_events

$referenceActive = Checkpoint-ById $reference 'gameplay_active'
$referenceFailed = Checkpoint-ById $reference 'required_player_lost'
$candidateActive = Checkpoint-ById $candidate 'gameplay_active'
$candidateFailed = Checkpoint-ById $candidate 'required_player_lost'
foreach ($checkpoint in @(
    [pscustomobject]@{ path = 'reference.gameplay_active'; value = $referenceActive },
    [pscustomobject]@{ path = 'reference.required_player_lost'; value = $referenceFailed },
    [pscustomobject]@{ path = 'candidate.gameplay_active'; value = $candidateActive },
    [pscustomobject]@{ path = 'candidate.required_player_lost'; value = $candidateFailed }
)) {
    Expect-True $checkpoint.path ($null -ne $checkpoint.value) `
        $(if ($null -eq $checkpoint.value) { 'missing' } else { 'present' }) `
        'required checkpoint'
}

if ($null -ne $referenceActive -and $null -ne $referenceFailed -and
    $null -ne $candidateActive -and $null -ne $candidateFailed) {
    Expect-Exact 'reference.gameplay_active.actor.scene_index' `
        $sceneIndex $referenceActive.actor.scene_index
    Expect-Exact 'reference.required_player_lost.actor.scene_index' `
        $sceneIndex $referenceFailed.actor.scene_index
    $candidateActiveActor = Candidate-Actor $candidateActive $sceneIndex
    $candidateFailedActor = Candidate-Actor $candidateFailed $sceneIndex
    Expect-True 'candidate.gameplay_active.actor' `
        ($null -ne $candidateActiveActor) `
        $(if ($null -eq $candidateActiveActor) { 'missing' } else { 'present' }) `
        "scene $sceneIndex is present"
    Expect-True 'candidate.required_player_lost.actor' `
        ($null -ne $candidateFailedActor) `
        $(if ($null -eq $candidateFailedActor) { 'missing' } else { 'present' }) `
        "scene $sceneIndex is present"

    if ($null -ne $candidateActiveActor -and
        $null -ne $candidateFailedActor) {
        Expect-Exact 'gameplay_active.mission.status' `
            $referenceActive.mission.status $candidateActive.mission.status
        Expect-Exact 'required_player_lost.mission.status' `
            $referenceFailed.mission.status $candidateFailed.mission.status
        Expect-Exact 'required_player_lost.mission.failure_id' `
            $referenceFailed.mission.semantic_failure_id `
            $candidateFailed.mission.failure_id
        Expect-Exact 'required_player_lost.result_state' `
            $referenceFailed.mission.result_state `
            $candidateFailed.tags.original_result_state
        Expect-Exact 'gameplay_active.actor.faction_id' `
            $referenceActive.actor.faction_id $candidateActiveActor.faction_id
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
        Expect-Near 'gameplay_active.actor.position.x' `
            ([double]$referenceActive.actor.position[0]) `
            ([double]$candidateActiveActor.position[0]) 0.01
        Expect-Near 'gameplay_active.actor.position.y' `
            ([double]$referenceActive.actor.position[1]) `
            ([double]$candidateActiveActor.position[1]) 0.01
        Expect-True 'candidate.required_player_lost.damage_event_count' `
            ([int]$candidateFailedActor.native.damage_event_count -gt 0) `
            $candidateFailedActor.native.damage_event_count `
            'real damage event count is positive'
        Expect-True 'candidate.required_player_lost.damage_taken_total' `
            ([int]$candidateFailedActor.native.damage_taken_total -ge 8) `
            $candidateFailedActor.native.damage_taken_total `
            'real accumulated damage reaches starting HP'
    }
}

Expect-True 'reference.combat.hit_point_samples' `
    (Test-MonotonicDeathSequence $reference.combat.hit_point_samples) `
    (@($reference.combat.hit_point_samples) -join ',') `
    'monotonic 8-to-0 authentic combat sequence'
Expect-True 'candidate.combat.hit_point_samples' `
    (Test-MonotonicDeathSequence $candidate.combat.hit_point_samples) `
    (@($candidate.combat.hit_point_samples) -join ',') `
    'monotonic 8-to-0 authentic combat sequence'
Expect-True 'reference.combat.attacker_scene_indices' `
    (@($reference.combat.attacker_scene_indices).Count -gt 0) `
    (@($reference.combat.attacker_scene_indices) -join ',') `
    'at least one observed original enemy attacker'
Expect-True 'candidate.combat.attacker_scene_indices' `
    (@($candidate.combat.attacker_scene_indices).Count -gt 0) `
    (@($candidate.combat.attacker_scene_indices) -join ',') `
    'at least one observed Remake enemy attacker'
Expect-True 'candidate.combat.damage_event_count' `
    ([int]$candidate.combat.damage_event_count -gt 0) `
    $candidate.combat.damage_event_count 'real damage events are present'
Expect-True 'candidate.combat.damage_taken_total' `
    ([int]$candidate.combat.damage_taken_total -ge 8) `
    $candidate.combat.damage_taken_total 'accumulated damage reaches starting HP'

$result = [pscustomobject][ordered]@{
    schema_version = 1
    comparison_id = [string]$reference.scenario.id
    passed = $mismatches.Count -eq 0
    check_count = $checkCount
    mismatch_count = $mismatches.Count
    reference = (Resolve-Path -LiteralPath $ReferenceTrace).Path
    candidate = (Resolve-Path -LiteralPath $CandidateTrace).Path
    evidence = [pscustomobject][ordered]@{
        scene_index = $sceneIndex
        reference_input_kind = [string]$reference.input.action_kind
        candidate_input_kind = [string]$candidate.input.action_kind
        reference_damage_entry = [string]$reference.metadata.damage_entry
        candidate_damage_entry = [string]$candidate.metadata.damage_entry
        expected_result_state = 2
        expected_failure_id = 'required_character_lost'
        system_cursor_calls = 0
        global_focus_calls = 0
        mission_result_writes = 0
    }
    mismatches = @($mismatches)
}

if (-not [string]::IsNullOrWhiteSpace($OutputJson)) {
    $fullOutputJson = [IO.Path]::GetFullPath($OutputJson)
    [IO.Directory]::CreateDirectory(
        [IO.Path]::GetDirectoryName($fullOutputJson)) | Out-Null
    $result | ConvertTo-Json -Depth 14 |
        Set-Content -LiteralPath $fullOutputJson -Encoding UTF8
}
if (-not [string]::IsNullOrWhiteSpace($OutputMarkdown)) {
    $fullOutputMarkdown = [IO.Path]::GetFullPath($OutputMarkdown)
    [IO.Directory]::CreateDirectory(
        [IO.Path]::GetDirectoryName($fullOutputMarkdown)) | Out-Null
    $status = if ($result.passed) { 'PASS' } else { 'FAIL' }
    $lines = [Collections.Generic.List[string]]::new()
    $lines.Add('# Human-input natural mission failure parity')
    $lines.Add('')
    $lines.Add("- Status: **$status**")
    $lines.Add("- Checks: $checkCount")
    $lines.Add("- Required player scene: $sceneIndex")
    $lines.Add(
        '- Both runtimes use isolated human input and authentic enemy combat; ' +
        'neither writes actor HP, mission result, system cursor or global focus.')
    if ($mismatches.Count -gt 0) {
        $lines.Add('')
        $lines.Add('## Mismatches')
        foreach ($mismatch in $mismatches) {
            $lines.Add(
                ('- `{0}`: expected `{1}`, actual `{2}` ({3})' -f
                    $mismatch.path,
                    $mismatch.expected,
                    $mismatch.actual,
                    $mismatch.rule))
        }
    }
    $lines | Set-Content -LiteralPath $fullOutputMarkdown -Encoding UTF8
}

$result
if (-not $result.passed -and -not $AllowMismatch) {
    exit 1
}
