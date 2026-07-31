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

function Read-Json {
    param([Parameter(Mandatory)][string]$Path)

    return Get-Content -LiteralPath (
        (Resolve-Path -LiteralPath $Path).Path
    ) -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Add-Mismatch {
    param(
        [Collections.Generic.List[object]]$Items,
        [string]$Path,
        $Expected,
        $Actual,
        [string]$Rule
    )

    if ([string]$Expected -cne [string]$Actual) {
        $Items.Add([pscustomobject][ordered]@{
            path = $Path
            expected = $Expected
            actual = $Actual
            rule = $Rule
        })
    }
}

function Checkpoint-ById {
    param($Trace, [string]$Id)

    return @(
        $Trace.checkpoints |
            Where-Object { [string]$_.id -ceq $Id }
    ) | Select-Object -First 1
}

$reference = Read-Json $ReferenceTrace
$candidate = Read-Json $CandidateTrace
$mismatches = [Collections.Generic.List[object]]::new()
$scenarioId = 'm010-briefing-left-click-dismissal-v1'

foreach ($traceCase in @(
        [pscustomobject]@{ label = 'reference'; value = $reference },
        [pscustomobject]@{ label = 'candidate'; value = $candidate })) {
    Add-Mismatch $mismatches "$($traceCase.label).schema_version" `
        1 $traceCase.value.schema_version 'trace schema'
    Add-Mismatch $mismatches "$($traceCase.label).content_profile" `
        'repository-mod-12-level-20260729' `
        $traceCase.value.content_profile 'content identity'
    Add-Mismatch $mismatches "$($traceCase.label).level.id" `
        'm010' $traceCase.value.level.id 'scenario identity'
    Add-Mismatch $mismatches "$($traceCase.label).level.selector_level" `
        11 $traceCase.value.level.selector_level 'scenario identity'
    Add-Mismatch $mismatches "$($traceCase.label).level.engine_mission" `
        11 $traceCase.value.level.engine_mission 'scenario identity'
    Add-Mismatch $mismatches "$($traceCase.label).scenario.id" `
        $scenarioId $traceCase.value.scenario.id 'scenario identity'
    Add-Mismatch $mismatches "$($traceCase.label).passed" `
        $true $traceCase.value.passed 'producer assertions'
    Add-Mismatch $mismatches `
        "$($traceCase.label).metadata.global_pointer_control" `
        $false $traceCase.value.metadata.global_pointer_control `
        'input isolation'
}

Add-Mismatch $mismatches 'reference.runtime' `
    'mod' $reference.runtime 'reference runtime'
Add-Mismatch $mismatches 'reference.metadata.input_isolation' `
    'process-local-DirectInput' $reference.metadata.input_isolation `
    'target-process input only'
Add-Mismatch $mismatches 'reference.metadata.same_main_window' `
    $true $reference.metadata.same_main_window `
    'briefing remains in the game window'
Add-Mismatch $mismatches 'reference.metadata.external_dialog' `
    $false $reference.metadata.external_dialog `
    'no external briefing dialog'
Add-Mismatch $mismatches 'candidate.runtime' `
    'remake' $candidate.runtime 'candidate runtime'
Add-Mismatch $mismatches 'candidate.metadata.input_isolation' `
    'target-viewport-event' $candidate.metadata.input_isolation `
    'target-viewport input only'

$referenceVisible = Checkpoint-ById $reference 'briefing_visible'
$referenceDismissed = Checkpoint-ById $reference 'briefing_dismissed'
$candidateVisible = Checkpoint-ById $candidate 'briefing_visible'
$candidatePressed = Checkpoint-ById $candidate 'pointer_pressed'
$candidateDismissed = Checkpoint-ById $candidate 'briefing_dismissed'
foreach ($required in @(
        [pscustomobject]@{
            path = 'reference.checkpoints.briefing_visible'
            value = $referenceVisible
        },
        [pscustomobject]@{
            path = 'reference.checkpoints.briefing_dismissed'
            value = $referenceDismissed
        },
        [pscustomobject]@{
            path = 'candidate.checkpoints.briefing_visible'
            value = $candidateVisible
        },
        [pscustomobject]@{
            path = 'candidate.checkpoints.pointer_pressed'
            value = $candidatePressed
        },
        [pscustomobject]@{
            path = 'candidate.checkpoints.briefing_dismissed'
            value = $candidateDismissed
        })) {
    if ($null -eq $required.value) {
        $mismatches.Add([pscustomobject][ordered]@{
            path = $required.path
            expected = 'present'
            actual = 'missing'
            rule = 'required checkpoint'
        })
    }
}

if ($null -ne $referenceVisible) {
    Add-Mismatch $mismatches 'reference.visible.modal_visible' `
        $true $referenceVisible.modal_visible 'original in-window modal'
    Add-Mismatch $mismatches 'reference.visible.world_state_active' `
        $false $referenceVisible.world_state_active `
        'world is not active behind the briefing'
    Add-Mismatch $mismatches 'reference.visible.surface_non_blank' `
        $true $referenceVisible.surface_non_blank `
        'original briefing surface is rendered'
}
if ($null -ne $referenceDismissed) {
    Add-Mismatch $mismatches 'reference.dismissed.world_state_active' `
        $true $referenceDismissed.world_state_active `
        'left-click advances into the mission state'
    Add-Mismatch $mismatches 'reference.dismissed.input_delivered' `
        $true $referenceDismissed.input_delivered `
        'process-local mouse pulse delivered'
}
if ($null -ne $candidateVisible) {
    Add-Mismatch $mismatches 'candidate.visible.active_briefing' `
        'm010' $candidateVisible.active_briefing `
        'same level briefing is active'
    Add-Mismatch $mismatches 'candidate.visible.overlay_visible' `
        $true $candidateVisible.overlay_visible 'briefing is visible'
    Add-Mismatch $mismatches 'candidate.visible.tree_paused' `
        $true $candidateVisible.tree_paused 'world is paused'
}
if ($null -ne $candidatePressed) {
    Add-Mismatch $mismatches 'candidate.pressed.active_briefing' `
        'm010' $candidatePressed.active_briefing `
        'press does not prematurely dismiss'
    Add-Mismatch $mismatches 'candidate.pressed.overlay_visible' `
        $true $candidatePressed.overlay_visible `
        'press is consumed by the modal'
    Add-Mismatch $mismatches 'candidate.pressed.closed_count' `
        0 $candidatePressed.closed_count `
        'press cannot click through'
}
if ($null -ne $candidateDismissed) {
    Add-Mismatch $mismatches 'candidate.dismissed.active_briefing' `
        '' $candidateDismissed.active_briefing `
        'release dismisses the briefing'
    Add-Mismatch $mismatches 'candidate.dismissed.overlay_visible' `
        $false $candidateDismissed.overlay_visible `
        'modal is hidden'
    Add-Mismatch $mismatches 'candidate.dismissed.tree_paused' `
        $false $candidateDismissed.tree_paused `
        'gameplay resumes'
    Add-Mismatch $mismatches 'candidate.dismissed.closed_count' `
        1 $candidateDismissed.closed_count `
        'one input cycle closes exactly one briefing'
}

$result = [pscustomobject][ordered]@{
    schema_version = 1
    scenario_id = $scenarioId
    reference_runtime = [string]$reference.runtime
    candidate_runtime = [string]$candidate.runtime
    mismatch_count = $mismatches.Count
    passed = $mismatches.Count -eq 0
    input_isolation = (
        'stable MOD process-local DirectInput and Remake target-viewport ' +
        'events only; no cursor positioning, clipping, capture, or desktop input')
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
    @(
        "# Briefing input parity: $scenarioId",
        '',
        "- Status: **$status**",
        "- Mismatches: $($mismatches.Count)",
        "- Input isolation: $($result.input_isolation)",
        '',
        'The stable MOD keeps the briefing in its main window and advances ' +
            'from a process-local left-click. Remake consumes the press in ' +
            'the modal overlay, dismisses on release, and resumes gameplay.'
    ) | Set-Content -LiteralPath $resolvedMarkdown -Encoding UTF8
}

$result
if (-not $result.passed -and -not $AllowMismatch) {
    throw (
        "Briefing input parity failed with $($mismatches.Count) " +
        'mismatch(es).')
}
