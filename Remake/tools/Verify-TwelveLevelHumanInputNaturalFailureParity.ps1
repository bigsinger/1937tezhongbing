[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$GodotExecutable,
    [string]$OutputDirectory = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$remakeRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$gameRoot = Join-Path $remakeRoot 'game'
$baselineRoot = Join-Path $remakeRoot 'validation\baselines\mod'
$GodotExecutable = (Resolve-Path -LiteralPath $GodotExecutable).Path
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $remakeRoot `
        'LocalAssets\qa\verify-human-input-natural-failure'
}
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
[IO.Directory]::CreateDirectory($OutputDirectory) | Out-Null

$results = [Collections.Generic.List[object]]::new()
foreach ($index in 0..11) {
    $levelId = 'm{0:D3}' -f $index
    $scenarioId = "$levelId-human-input-natural-failure-v1"
    $levelOutput = Join-Path $OutputDirectory $levelId
    [IO.Directory]::CreateDirectory($levelOutput) | Out-Null
    & $GodotExecutable @(
        '--headless',
        '--path',
        $gameRoot,
        '--max-fps',
        '60',
        '--disable-vsync',
        '--script',
        'res://tests/parity_runtime_probe.gd',
        '--',
        "--output-dir=$levelOutput",
        "--level-id=$levelId",
        "--scenario-id=$scenarioId")
    if ($LASTEXITCODE -ne 0) {
        throw "Godot $levelId human-input failure probe exited with $LASTEXITCODE."
    }

    $baseline = Join-Path $baselineRoot "$scenarioId.json"
    $candidate = Join-Path $levelOutput "remake-$scenarioId.json"
    $comparisonJson = Join-Path $levelOutput "$scenarioId-comparison.json"
    $comparisonMarkdown = Join-Path $levelOutput "$scenarioId-comparison.md"
    $comparison = & (Join-Path $PSScriptRoot `
        'Compare-HumanInputNaturalMissionFailureParity.ps1') `
        -ReferenceTrace $baseline `
        -CandidateTrace $candidate `
        -OutputJson $comparisonJson `
        -OutputMarkdown $comparisonMarkdown `
        -AllowMismatch
    $results.Add([pscustomobject][ordered]@{
        level_id = $levelId
        scene_index = [int]$comparison.evidence.scene_index
        check_count = [int]$comparison.check_count
        mismatch_count = [int]$comparison.mismatch_count
        passed = [bool]$comparison.passed
        trace = $candidate
        comparison = $comparisonJson
    })
}

$passed = @($results | Where-Object { -not $_.passed }).Count -eq 0
$summary = [pscustomobject][ordered]@{
    schema_version = 1
    verification = 'twelve-level-human-input-natural-failure-v1'
    input_isolation = 'target-viewport-events'
    mission_result_writes = 0
    system_cursor_calls = 0
    global_focus_calls = 0
    levels = @($results)
    check_count = [int](
        @($results | Measure-Object check_count -Sum).Sum)
    mismatch_count = [int](
        @($results | Measure-Object mismatch_count -Sum).Sum)
    passed = $passed
}
$summary | ConvertTo-Json -Depth 10 |
    Set-Content -LiteralPath (
        Join-Path $OutputDirectory 'summary.json') -Encoding UTF8
Write-Host (
    'Twelve-level human-input natural failure verification: ' +
    "checks=$($summary.check_count), " +
    "mismatches=$($summary.mismatch_count), passed=$passed")
if (-not $passed) {
    throw 'One or more human-input natural failure parity checks failed.'
}
