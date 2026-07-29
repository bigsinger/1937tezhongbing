[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$remakeRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $remakeRoot '..'))
$schemaPath = Join-Path $repositoryRoot `
    'SDK\schemas\runtime-parity-trace-v1.schema.json'
$compareScript = Join-Path $PSScriptRoot `
    'Compare-RuntimeParityTrace.ps1'
$baselinePath = Join-Path $remakeRoot `
    'validation\baselines\mod\m000-basic-movement-v1.json'
$obstacleBaselinePath = Join-Path $remakeRoot `
    'validation\baselines\mod\m000-obstacle-route-v1.json'
$patrolBaselinePath = Join-Path $remakeRoot `
    'validation\baselines\mod\m000-enemy-patrol-v1.json'

$schema = Get-Content -LiteralPath $schemaPath -Raw -Encoding UTF8 |
    ConvertFrom-Json
if ($schema.title -ne '1937 MOD and Remake runtime parity trace' -or
    $null -eq $schema.'$defs'.checkpoint -or
    $null -eq $schema.'$defs'.actor) {
    throw 'Runtime parity trace JSON schema is incomplete.'
}
$baseline = Get-Content -LiteralPath $baselinePath -Raw -Encoding UTF8 |
    ConvertFrom-Json
if ($baseline.runtime -ne 'mod' -or
    $baseline.content_profile -ne 'repository-mod-12-level-20260729' -or
    @($baseline.checkpoints).Count -ne 6 -or
    @($baseline.checkpoints[0].actors).Count -ne 1 -or
    [int]$baseline.checkpoints[0].actors[0].scene_index -ne 1436 -or
    [int]$baseline.checkpoints[0].actors[0].database_entry_id -ne 924 -or
    $baseline.metadata.input_isolation -ne
    'window-message-to-process-local-DirectInput') {
    throw 'The checked-in m000 stable-MOD baseline identity is invalid.'
}
$obstacleBaseline = Get-Content -LiteralPath $obstacleBaselinePath `
    -Raw -Encoding UTF8 | ConvertFrom-Json
if ($obstacleBaseline.runtime -ne 'mod' -or
    $obstacleBaseline.scenario.id -ne 'm000-obstacle-route-v1' -or
    @($obstacleBaseline.checkpoints).Count -ne 6 -or
    @($obstacleBaseline.checkpoints[3].tags.observed_positions).Count -lt 10 -or
    [int]$obstacleBaseline.checkpoints[0].actors[0].scene_index -ne 1436) {
    throw 'The checked-in m000 obstacle-route baseline is invalid.'
}
$patrolBaseline = Get-Content -LiteralPath $patrolBaselinePath `
    -Raw -Encoding UTF8 | ConvertFrom-Json
$patrolCheckpointIds = @(
    'patrol_interval_1_commanded',
    'patrol_interval_1_observed',
    'patrol_interval_2_commanded',
    'patrol_interval_2_observed'
)
if ($patrolBaseline.runtime -ne 'mod' -or
    $patrolBaseline.scenario.id -ne 'm000-enemy-patrol-v1' -or
    @($patrolBaseline.checkpoints).Count -ne 4 -or
    (Compare-Object `
        $patrolCheckpointIds `
        @($patrolBaseline.checkpoints.id)).Count -ne 0 -or
    @($patrolBaseline.checkpoints |
        Where-Object { @($_.actors).Count -ne 46 }).Count -ne 0 -or
    @($patrolBaseline.checkpoints[0].actors.scene_index |
        Select-Object -Unique).Count -ne 46) {
    throw 'The checked-in m000 enemy-patrol baseline is invalid.'
}

$temporaryBase = if (Test-Path -LiteralPath 'E:\1937') {
    'E:\1937'
}
elseif (-not [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)) {
    $env:RUNNER_TEMP
}
else {
    [IO.Path]::GetTempPath()
}
$root = Join-Path $temporaryBase (
    'runtime-parity-trace-tests-' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($root) | Out-Null

try {
    function New-Checkpoint {
        param(
            [string]$Id,
            [double]$Elapsed,
            [double]$X,
            [double]$Y,
            [int]$Facing = 5
        )
        return [ordered]@{
            id = $Id
            sequence = 0
            elapsed_ms = $Elapsed
            camera = [ordered]@{
                position = @(512, 344)
                viewport = @(1024, 688)
                zoom = @(1, 1)
            }
            world = [ordered]@{
                size = @(4960, 2240)
                tracked_actor_count = 1
                source_entity_count = 1630
            }
            actors = @(
                [ordered]@{
                    actor_id = 'scene:1436'
                    role = 'player'
                    scene_index = 1436
                    database_entry_id = 924
                    display_name = '强子'
                    faction_id = 3
                    position = @($X, $Y)
                    target_position = @(656, 616)
                    facing_direction = $Facing
                    alive = $true
                    selected = $true
                    stance = 'run'
                    hit_points = [ordered]@{
                        current = 8
                        maximum = 8
                    }
                    weapon = [ordered]@{
                        attack_type = 4
                        action_key = 'dagger_attack'
                        magazine_ammo = 0
                        reserve_ammo = 0
                        infinite_ammo = $true
                    }
                    inventory = [ordered]@{}
                    native = [ordered]@{}
                }
            )
            mission = [ordered]@{
                id = 'm000'
                status = 'active'
                failure_id = ''
                completed = [ordered]@{}
                progress = [ordered]@{}
                elapsed_seconds = 1
            }
            tags = [ordered]@{}
        }
    }

    function New-Trace {
        param([string]$Runtime, $Checkpoint)
        return [ordered]@{
            schema_version = 1
            trace_id = "$Runtime-m000-m000-basic-movement-v1"
            runtime = $Runtime
            content_profile = 'repository-mod-12-level-20260729'
            level = [ordered]@{
                id = 'm000'
                selector_level = 1
                engine_mission = 1
            }
            scenario = [ordered]@{
                id = 'm000-basic-movement-v1'
                coordinate_space = 'legacy-world-pixels'
                description = 'synthetic comparator fixture'
            }
            metadata = [ordered]@{}
            checkpoints = @($Checkpoint)
        }
    }

    $referencePath = Join-Path $root 'reference.json'
    $withinPath = Join-Path $root 'within-tolerance.json'
    $mismatchPath = Join-Path $root 'mismatch.json'
    New-Trace 'mod' (New-Checkpoint 'gameplay_ready' 1000 241 51) |
        ConvertTo-Json -Depth 20 |
        Set-Content -LiteralPath $referencePath -Encoding UTF8
    New-Trace 'remake' (New-Checkpoint 'gameplay_ready' 1450 248 55) |
        ConvertTo-Json -Depth 20 |
        Set-Content -LiteralPath $withinPath -Encoding UTF8
    $mismatchCheckpoint = New-Checkpoint `
        'gameplay_ready' 4000 400 300 2
    $mismatchCheckpoint.actors[0].database_entry_id = 999
    New-Trace 'remake' $mismatchCheckpoint |
        ConvertTo-Json -Depth 20 |
        Set-Content -LiteralPath $mismatchPath -Encoding UTF8

    $positive = & $compareScript `
        -ReferenceTrace $referencePath `
        -CandidateTrace $withinPath
    if (-not [bool]$positive.passed -or
        [int]$positive.mismatch_count -ne 0) {
        throw 'Tolerance-compatible runtime traces did not compare equal.'
    }
    foreach ($checkedBaseline in @(
        $baselinePath,
        $obstacleBaselinePath,
        $patrolBaselinePath
    )) {
        $baselineSelf = & $compareScript `
            -ReferenceTrace $checkedBaseline `
            -CandidateTrace $checkedBaseline
        if (-not [bool]$baselineSelf.passed) {
            throw "The checked-in MOD trace is not self-consistent: $checkedBaseline"
        }
    }

    $movementMismatchPath = Join-Path $root 'movement-mismatch.json'
    $movementMismatch = Get-Content -LiteralPath $baselinePath `
        -Raw -Encoding UTF8 | ConvertFrom-Json
    $movementActor = @(
        $movementMismatch.checkpoints[3].actors |
        Where-Object { [int]$_.scene_index -eq 1436 }
    )[0]
    $movementActor.position[0] =
        [double]$movementActor.position[0] + 40.0
    $movementMismatch | ConvertTo-Json -Depth 30 |
        Set-Content -LiteralPath $movementMismatchPath -Encoding UTF8
    $movementResult = & $compareScript `
        -ReferenceTrace $baselinePath `
        -CandidateTrace $movementMismatchPath `
        -AllowMismatch
    if ([bool]$movementResult.passed -or
        @($movementResult.mismatches.path) -notcontains
        'actors.scene:1436.movement_delta') {
        throw 'Observed movement-vector divergence was not detected.'
    }

    $negative = & $compareScript `
        -ReferenceTrace $referencePath `
        -CandidateTrace $mismatchPath `
        -AllowMismatch
    if ([bool]$negative.passed -or
        [int]$negative.mismatch_count -lt 3 -or
        @($negative.mismatches.path) -notcontains
        'actors.scene:1436.facing_direction') {
        throw 'Runtime trace comparator did not identify semantic divergence.'
    }
}
finally {
    if (Test-Path -LiteralPath $root -PathType Container) {
        $resolvedRoot = [IO.Path]::GetFullPath($root)
        $resolvedBase = [IO.Path]::GetFullPath($temporaryBase)
        if (-not $resolvedRoot.StartsWith(
                $resolvedBase + [IO.Path]::DirectorySeparatorChar,
                [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Refusing to remove parity-test output outside its temporary root.'
        }
        Remove-Item -LiteralPath $resolvedRoot -Recurse -Force
    }
}

Write-Host 'Runtime parity trace schema/comparator tests passed.'
