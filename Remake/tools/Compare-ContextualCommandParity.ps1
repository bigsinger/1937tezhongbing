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
    $trace = Get-Content -LiteralPath $resolved -Raw -Encoding UTF8 |
        ConvertFrom-Json
    if ([int]$trace.schema_version -ne 1) {
        throw "Unsupported runtime parity trace schema: $resolved"
    }
    return $trace
}

function Add-Mismatch {
    param(
        [Collections.Generic.List[object]]$Items,
        [string]$Path,
        $Expected,
        $Actual,
        [string]$Rule
    )

    $Items.Add([pscustomobject][ordered]@{
        path = $Path
        expected = $Expected
        actual = $Actual
        rule = $Rule
    })
}

function Compare-Exact {
    param(
        [Collections.Generic.List[object]]$Items,
        [string]$Path,
        $Expected,
        $Actual,
        [string]$Rule = 'exact'
    )

    if ([string]$Expected -cne [string]$Actual) {
        Add-Mismatch $Items $Path $Expected $Actual $Rule
    }
}

function Checkpoint-Map {
    param(
        $Trace,
        [Collections.Generic.List[object]]$Items,
        [string]$Label
    )

    $result = @{}
    foreach ($checkpoint in @($Trace.checkpoints)) {
        $id = [string]$checkpoint.id
        if ($result.ContainsKey($id)) {
            Add-Mismatch $Items "$Label.checkpoints.$id" `
                'unique' 'duplicate' 'unique checkpoint id'
        }
        else {
            $result[$id] = $checkpoint
        }
    }
    return $result
}

function Actor-At {
    param($Checkpoint, [int]$SceneIndex)

    return @(
        $Checkpoint.actors |
            Where-Object { [int]$_.scene_index -eq $SceneIndex }
    ) | Select-Object -First 1
}

function Require-Checkpoint {
    param(
        [Collections.Generic.List[object]]$Items,
        $Map,
        [string]$Label,
        [string]$Id
    )

    if (-not $Map.ContainsKey($Id)) {
        Add-Mismatch $Items "$Label.checkpoints.$Id" `
            'present' 'missing' 'required checkpoint'
        return $null
    }
    return $Map[$Id]
}

function Require-Actor {
    param(
        [Collections.Generic.List[object]]$Items,
        $Checkpoint,
        [string]$Label,
        [string]$CheckpointId,
        [int]$SceneIndex
    )

    if ($null -eq $Checkpoint) {
        return $null
    }
    $actor = Actor-At $Checkpoint $SceneIndex
    if ($null -eq $actor) {
        Add-Mismatch $Items `
            "$Label.checkpoints.$CheckpointId.actors.scene:$SceneIndex" `
            'present' 'missing' 'required actor'
    }
    return $actor
}

function Tag-Value {
    param($Checkpoint, [string]$Name)

    if ($null -eq $Checkpoint -or
        $null -eq $Checkpoint.tags.PSObject.Properties[$Name]) {
        return $null
    }
    return $Checkpoint.tags.$Name
}

$reference = Read-Trace $ReferenceTrace
$candidate = Read-Trace $CandidateTrace
$mismatches = [Collections.Generic.List[object]]::new()
$scenarioId = [string]$reference.scenario.id
$scenarioDefinitions = @{
    'm010-sight-direct-target-v1' = [ordered]@{
        checkpoints = @(
            'before_sight',
            'sight_mode_armed',
            'sight_target_selected'
        )
        target_scene = 1126
        worker_scene = -1
    }
    'm010-burial-command-v1' = [ordered]@{
        checkpoints = @(
            'before_attack',
            'after_attack',
            'burial_mode_armed',
            'burial_commanded'
        )
        target_scene = 1126
        worker_scene = 1590
        level_id = 'm010'
        selector_level = 11
        engine_mission = 11
    }
}
if (-not $scenarioDefinitions.ContainsKey($scenarioId)) {
    throw "Unsupported contextual-command parity scenario: $scenarioId"
}
$definition = $scenarioDefinitions[$scenarioId]
$expectedLevelId = 'm010'
$expectedSelectorLevel = 11
$expectedEngineMission = 11
if ($definition.Contains('level_id')) {
    $expectedLevelId = [string]$definition.level_id
    $expectedSelectorLevel = [int]$definition.selector_level
    $expectedEngineMission = [int]$definition.engine_mission
}

Compare-Exact $mismatches 'trace.content_profile' `
    $reference.content_profile $candidate.content_profile
Compare-Exact $mismatches 'scenario.id' `
    $scenarioId $candidate.scenario.id
Compare-Exact $mismatches 'scenario.coordinate_space' `
    $reference.scenario.coordinate_space $candidate.scenario.coordinate_space
foreach ($trace in @(
        [pscustomobject]@{ label = 'reference'; value = $reference },
        [pscustomobject]@{ label = 'candidate'; value = $candidate })) {
    Compare-Exact $mismatches "$($trace.label).level.id" `
        $expectedLevelId $trace.value.level.id 'scenario identity'
    Compare-Exact $mismatches "$($trace.label).level.selector_level" `
        $expectedSelectorLevel $trace.value.level.selector_level 'scenario identity'
    Compare-Exact $mismatches "$($trace.label).level.engine_mission" `
        $expectedEngineMission $trace.value.level.engine_mission 'scenario identity'
    Compare-Exact $mismatches "$($trace.label).checkpoints.count" `
        @($definition.checkpoints).Count `
        @($trace.value.checkpoints).Count `
        'exact scenario checkpoint count'
}

$referenceMap = Checkpoint-Map $reference $mismatches 'reference'
$candidateMap = Checkpoint-Map $candidate $mismatches 'candidate'
foreach ($checkpointId in @($definition.checkpoints)) {
    $referenceCheckpoint = Require-Checkpoint `
        $mismatches $referenceMap 'reference' $checkpointId
    $candidateCheckpoint = Require-Checkpoint `
        $mismatches $candidateMap 'candidate' $checkpointId
    if ($null -eq $referenceCheckpoint -or
        $null -eq $candidateCheckpoint) {
        continue
    }
    foreach ($tag in @(
            'runtime_type_78_count',
            'runtime_type_90_count')) {
        Compare-Exact $mismatches `
            "checkpoints.$checkpointId.tags.$tag" `
            (Tag-Value $referenceCheckpoint $tag) `
            (Tag-Value $candidateCheckpoint $tag) `
            'stable MOD/Remake exact contextual state'
    }

    $referenceTarget = Require-Actor `
        $mismatches $referenceCheckpoint 'reference' `
        $checkpointId ([int]$definition.target_scene)
    $candidateTarget = Require-Actor `
        $mismatches $candidateCheckpoint 'candidate' `
        $checkpointId ([int]$definition.target_scene)
    if ($null -ne $referenceTarget -and $null -ne $candidateTarget) {
        foreach ($field in @(
                'actor_id',
                'role',
                'scene_index',
                'database_entry_id',
                'faction_id',
                'alive')) {
            Compare-Exact $mismatches `
                "checkpoints.$checkpointId.target.$field" `
                $referenceTarget.$field $candidateTarget.$field `
                'stable MOD/Remake exact target state'
        }
        Compare-Exact $mismatches `
            "checkpoints.$checkpointId.target.selected_for_command" `
            $referenceTarget.native.selected_for_command `
            $candidateTarget.native.selected_for_command `
            'stable MOD/Remake exact selection state'
        Compare-Exact $mismatches `
            "checkpoints.$checkpointId.target.hit_points.current" `
            $referenceTarget.hit_points.current `
            $candidateTarget.hit_points.current `
            'stable MOD/Remake exact target outcome'
    }

    if ([int]$definition.worker_scene -ge 0) {
        $referenceWorker = Require-Actor `
            $mismatches $referenceCheckpoint 'reference' `
            $checkpointId ([int]$definition.worker_scene)
        $candidateWorker = Require-Actor `
            $mismatches $candidateCheckpoint 'candidate' `
            $checkpointId ([int]$definition.worker_scene)
        if ($null -ne $referenceWorker -and $null -ne $candidateWorker) {
            foreach ($field in @(
                    'actor_id',
                    'role',
                    'scene_index',
                    'database_entry_id',
                    'faction_id')) {
                Compare-Exact $mismatches `
                    "checkpoints.$checkpointId.worker.$field" `
                    $referenceWorker.$field $candidateWorker.$field `
                    'stable MOD/Remake exact worker state'
            }
        }
    }
}

if ($scenarioId -eq 'm010-sight-direct-target-v1') {
    foreach ($traceCase in @(
            [pscustomobject]@{
                label = 'reference'
                map = $referenceMap
            },
            [pscustomobject]@{
                label = 'candidate'
                map = $candidateMap
            })) {
        if (@($definition.checkpoints |
                Where-Object {
                    -not $traceCase.map.ContainsKey([string]$_)
                }).Count -gt 0) {
            continue
        }
        $before = $traceCase.map['before_sight']
        $armed = $traceCase.map['sight_mode_armed']
        $selected = $traceCase.map['sight_target_selected']
        $selectedActor = Actor-At $selected 1126
        Compare-Exact $mismatches `
            "$($traceCase.label).sight.armed_action" `
            0 (Tag-Value $armed 'current_action_id') `
            'S pointer mode does not overwrite CurrentActionId'
        Compare-Exact $mismatches `
            "$($traceCase.label).sight.consumed_action" `
            0 (Tag-Value $selected 'current_action_id') `
            'one-shot S command is consumed'
        Compare-Exact $mismatches `
            "$($traceCase.label).sight.actor90_before" `
            0 (Tag-Value $before 'runtime_type_90_count') `
            'direct-target scenario starts without actor 90'
        Compare-Exact $mismatches `
            "$($traceCase.label).sight.actor90_after" `
            0 (Tag-Value $selected 'runtime_type_90_count') `
            'direct enemy target does not create actor 90'
        if ($null -ne $selectedActor) {
            Compare-Exact $mismatches `
                "$($traceCase.label).sight.selected_for_command" `
                1 $selectedActor.native.selected_for_command `
                'living faction-1 target becomes the sole selection'
        }
    }
}
else {
    foreach ($traceCase in @(
            [pscustomobject]@{
                label = 'reference'
                map = $referenceMap
            },
            [pscustomobject]@{
                label = 'candidate'
                map = $candidateMap
            })) {
        if (@($definition.checkpoints |
                Where-Object {
                    -not $traceCase.map.ContainsKey([string]$_)
                }).Count -gt 0) {
            continue
        }
        $before = $traceCase.map['before_attack']
        $afterAttack = $traceCase.map['after_attack']
        $armed = $traceCase.map['burial_mode_armed']
        $commanded = $traceCase.map['burial_commanded']
        $beforeTarget = Actor-At $before 1126
        $afterTarget = Actor-At $afterAttack 1126
        $commandedWorker = Actor-At $commanded 1590
        Compare-Exact $mismatches `
            "$($traceCase.label).burial.target_before_hp" `
            8 $beforeTarget.hit_points.current `
            'original target hit points'
        Compare-Exact $mismatches `
            "$($traceCase.label).burial.target_after_hp" `
            0 $afterTarget.hit_points.current `
            'original dagger outcome'
        Compare-Exact $mismatches `
            "$($traceCase.label).burial.armed_action" `
            0 (Tag-Value $armed 'current_action_id') `
            'B pointer mode does not overwrite CurrentActionId'
        Compare-Exact $mismatches `
            "$($traceCase.label).burial.consumed_action" `
            0 (Tag-Value $commanded 'current_action_id') `
            'one-shot B command is consumed'
        Compare-Exact $mismatches `
            "$($traceCase.label).burial.goal_kind" `
            4 $commandedWorker.native.goal_kind `
            'original burial command kind'
        Compare-Exact $mismatches `
            "$($traceCase.label).burial.type78_before" `
            0 (Tag-Value $afterAttack 'runtime_type_78_count') `
            'scenario starts without a burial cache'
        Compare-Exact $mismatches `
            "$($traceCase.label).burial.type78_immediate" `
            0 (Tag-Value $commanded 'runtime_type_78_count') `
            'command kind 4 does not complete before its strict timer'
    }
}

$result = [pscustomobject][ordered]@{
    schema_version = 1
    reference_runtime = [string]$reference.runtime
    candidate_runtime = [string]$candidate.runtime
    level_id = $expectedLevelId
    scenario_id = $scenarioId
    checkpoint_ids = @($definition.checkpoints)
    mismatch_count = $mismatches.Count
    passed = $mismatches.Count -eq 0
    position_policy = (
        'Actor position and elapsed time remain diagnostic because live patrol ' +
        'phase differs between isolated launches; target identity, contextual ' +
        'mode action state after S/B, selection/command state, HP, goal kind, ' +
        'and absence of a premature actor 78 are strict. The transient weapon ' +
        'selection action before the burial setup is diagnostic.')
    mismatches = @($mismatches)
}

if (-not [string]::IsNullOrWhiteSpace($OutputJson)) {
    $resolvedOutput = [IO.Path]::GetFullPath($OutputJson)
    [IO.Directory]::CreateDirectory(
        [IO.Path]::GetDirectoryName($resolvedOutput)) | Out-Null
    $result | ConvertTo-Json -Depth 20 |
        Set-Content -LiteralPath $resolvedOutput -Encoding UTF8
}

if (-not [string]::IsNullOrWhiteSpace($OutputMarkdown)) {
    $resolvedMarkdown = [IO.Path]::GetFullPath($OutputMarkdown)
    [IO.Directory]::CreateDirectory(
        [IO.Path]::GetDirectoryName($resolvedMarkdown)) | Out-Null
    $status = if ($result.passed) { 'PASS' } else { 'FAIL' }
    $lines = [Collections.Generic.List[string]]::new()
    $lines.Add("# Contextual command parity: $scenarioId")
    $lines.Add('')
    $lines.Add("- Status: **$status**")
    $lines.Add("- Mismatches: $($mismatches.Count)")
    $lines.Add(
        '- Input isolation: target-window/process-local events only; ' +
        'no global pointer API.')
    $lines.Add('')
    if ($mismatches.Count -gt 0) {
        $lines.Add('| Path | Expected | Actual | Rule |')
        $lines.Add('|---|---|---|---|')
        foreach ($mismatch in $mismatches) {
            $lines.Add(
                '| {0} | {1} | {2} | {3} |' -f @(
                    ([string]$mismatch.path).Replace('|', '\|'),
                    ([string]$mismatch.expected).Replace('|', '\|'),
                    ([string]$mismatch.actual).Replace('|', '\|'),
                    ([string]$mismatch.rule).Replace('|', '\|')))
        }
    }
    else {
        $lines.Add(
            'Stable MOD and Remake match the recovered one-shot command ' +
            'identity, target filter and resulting world state.')
    }
    $lines.Add('')
    $lines.Add("> $($result.position_policy)")
    $lines |
        Set-Content -LiteralPath $resolvedMarkdown -Encoding UTF8
}

if (-not $result.passed -and -not $AllowMismatch) {
    throw (
        "Contextual-command parity failed for $scenarioId with " +
        "$($mismatches.Count) mismatch(es).")
}

return $result
