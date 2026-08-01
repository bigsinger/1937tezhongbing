[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ReferenceTrace,
    [Parameter(Mandatory)][string]$CandidateTrace,
    [string]$OutputJson = '',
    [string]$OutputMarkdown = '',
    [switch]$AllowMismatch
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Read-Trace {
    param([Parameter(Mandatory)][string]$Path)
    $resolved = (Resolve-Path -LiteralPath $Path).Path
    $trace = [IO.File]::ReadAllText(
        $resolved, [Text.Encoding]::UTF8) | ConvertFrom-Json
    if ([int]$trace.schema_version -ne 1) {
        throw "Unsupported cheat-victory trace schema: $resolved"
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

$reference = Read-Trace $ReferenceTrace
$candidate = Read-Trace $CandidateTrace
$mismatches = [Collections.Generic.List[object]]::new()
$checkCount = 0

function Add-Mismatch {
    param([string]$Path, $Expected, $Actual, [string]$Rule)
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
    foreach ($field in @(
        'mission_result_writes',
        'actor_state_writes',
        'system_cursor_calls',
        'system_keyboard_calls',
        'global_focus_calls')) {
        Expect-Exact "$($runtime.name).metadata.$field" `
            0 $runtime.trace.metadata.$field
    }
    Expect-Exact "$($runtime.name).metadata.evidence_scope" `
        'cheat-victory-transition-only' `
        $runtime.trace.metadata.evidence_scope
    Expect-Exact "$($runtime.name).metadata.cheat_code" `
        'FLIPMISSION' $runtime.trace.metadata.cheat_code
    Expect-Exact "$($runtime.name).metadata.cheat_key_count" `
        11 $runtime.trace.metadata.cheat_key_count
    Expect-Exact "$($runtime.name).input.action_kind" `
        'original_builtin_cheat_text' $runtime.trace.input.action_kind
    Expect-Exact "$($runtime.name).input.text" `
        'FLIPMISSION' $runtime.trace.input.text
}
Expect-Exact 'reference.metadata.input_isolation' `
    'window-message-to-process-local-DirectInput' `
    $reference.metadata.input_isolation
Expect-Exact 'candidate.metadata.input_isolation' `
    'target-viewport-events' $candidate.metadata.input_isolation
Expect-Exact 'reference.metadata.mission_evaluator' `
    'sub_405410' $reference.metadata.mission_evaluator
Expect-Exact 'candidate.metadata.mission_evaluator' `
    'MissionState+Main._on_mission_victory' `
    $candidate.metadata.mission_evaluator
Expect-Exact 'reference.input.process_local_input_events' `
    22 $reference.input.process_local_input_events
Expect-Exact 'candidate.input.viewport_input_events' `
    22 $candidate.input.viewport_input_events

$candidateSequence = @($candidate.input.sequence)
Expect-Exact 'candidate.input.sequence.count' 11 $candidateSequence.Count
if ($candidateSequence.Count -eq 11) {
    Expect-Exact 'candidate.input.sequence.letters' `
        'FLIPMISSION' (($candidateSequence | ForEach-Object letter) -join '')
    Expect-Exact 'candidate.input.sequence.event_count' `
        22 (@($candidateSequence | Measure-Object events -Sum).Sum)
    Expect-Exact 'candidate.input.sequence.final_buffer' `
        '' $candidateSequence[-1].buffer_after
    $unicodeText = -join @(
        $candidateSequence | ForEach-Object {
            [char][int]$_.event_unicode
        })
    Expect-Exact 'candidate.input.sequence.unicode' `
        'FLIPMISSION' $unicodeText
}

Expect-Exact 'reference.checkpoints.count' 2 @($reference.checkpoints).Count
Expect-Exact 'candidate.checkpoints.count' 2 @($candidate.checkpoints).Count
$referenceActive = Checkpoint-ById $reference 'gameplay_active'
$referenceVictory = Checkpoint-ById $reference 'cheat_input_committed'
$candidateActive = Checkpoint-ById $candidate 'gameplay_active'
$candidateVictory = Checkpoint-ById $candidate 'cheat_input_committed'
foreach ($checkpoint in @(
    [pscustomobject]@{ path = 'reference.gameplay_active'; value = $referenceActive },
    [pscustomobject]@{ path = 'reference.cheat_input_committed'; value = $referenceVictory },
    [pscustomobject]@{ path = 'candidate.gameplay_active'; value = $candidateActive },
    [pscustomobject]@{ path = 'candidate.cheat_input_committed'; value = $candidateVictory }
)) {
    Expect-True $checkpoint.path ($null -ne $checkpoint.value) `
        $(if ($null -eq $checkpoint.value) { 'missing' } else { 'present' }) `
        'required checkpoint'
}

if ($null -ne $referenceActive -and $null -ne $referenceVictory -and
    $null -ne $candidateActive -and $null -ne $candidateVictory) {
    Expect-Exact 'reference.active.status' 'active' `
        $referenceActive.mission.status
    Expect-Exact 'reference.active.result_state' 0 `
        $referenceActive.mission.result_state
    Expect-Exact 'reference.victory.status' 'victory' `
        $referenceVictory.mission.status
    Expect-Exact 'reference.victory.result_state' 3 `
        $referenceVictory.mission.result_state
    Expect-True 'reference.evaluator_calls' `
        ([long]$referenceVictory.mission.evaluator_calls -gt
            [long]$referenceActive.mission.evaluator_calls) `
        $referenceVictory.mission.evaluator_calls `
        'original evaluator advances after input'
    Expect-True 'reference.transition_sequence' `
        ([long]$referenceVictory.mission.transition_sequence -gt
            [long]$referenceActive.mission.transition_sequence) `
        $referenceVictory.mission.transition_sequence `
        'original transition sequence advances once'
    Expect-Exact 'candidate.active.status' 'active' `
        $candidateActive.mission.status
    Expect-Exact 'candidate.active.result_state' 0 `
        $candidateActive.tags.original_result_state
    Expect-Exact 'candidate.victory.status' 'victory' `
        $candidateVictory.mission.status
    Expect-Exact 'candidate.victory.result_state' 3 `
        $candidateVictory.tags.original_result_state
    Expect-Exact 'candidate.victory.cheat_code' 'FLIPMISSION' `
        $candidateVictory.tags.cheat_code
    Expect-Exact 'candidate.victory.cheat_key_count' 11 `
        $candidateVictory.tags.cheat_key_count
    $completionProperties = @(
        $candidateVictory.mission.completed.PSObject.Properties)
    Expect-True 'candidate.victory.objectives.count' `
        ($completionProperties.Count -gt 0) $completionProperties.Count `
        'at least one authored objective'
    Expect-True 'candidate.victory.objectives.complete' `
        (@($completionProperties | Where-Object { -not [bool]$_.Value }).Count -eq 0) `
        (@($completionProperties | ForEach-Object { $_.Value }) -join ',') `
        'every authored objective is complete'
}

$result = [pscustomobject][ordered]@{
    schema_version = 1
    comparison_id = [string]$reference.scenario.id
    evidence_scope = 'cheat-victory-transition-only'
    passed = $mismatches.Count -eq 0
    check_count = $checkCount
    mismatch_count = $mismatches.Count
    reference = (Resolve-Path -LiteralPath $ReferenceTrace).Path
    candidate = (Resolve-Path -LiteralPath $CandidateTrace).Path
    evidence = [pscustomobject][ordered]@{
        cheat_code = 'FLIPMISSION'
        input_events = 22
        expected_result_state = 3
        mission_result_writes = 0
        actor_state_writes = 0
        system_cursor_calls = 0
        system_keyboard_calls = 0
        global_focus_calls = 0
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
    $lines.Add('# Human-input cheat-victory transition parity')
    $lines.Add('')
    $lines.Add("- Status: **$status**")
    $lines.Add("- Checks: $checkCount")
    $lines.Add('- Scope: built-in `FLIPMISSION` input-to-victory transition only.')
    $lines.Add(
        '- This evidence deliberately does not claim non-cheat gameplay completion.')
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
