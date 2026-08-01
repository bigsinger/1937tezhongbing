[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$CaptureRoot,
    [string]$OutputPath = '',
    [string]$RepositoryRoot = ''
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    $RepositoryRoot = [IO.Path]::GetFullPath(
        (Join-Path $PSScriptRoot '..\..'))
}
else {
    $RepositoryRoot = [IO.Path]::GetFullPath($RepositoryRoot)
}
$CaptureRoot = [IO.Path]::GetFullPath($CaptureRoot)
if (-not (Test-Path -LiteralPath $CaptureRoot -PathType Container)) {
    throw "CRT random capture root is missing: $CaptureRoot"
}
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $RepositoryRoot (
        'Remake\game\data\original_crt_random_startup_catalog.json')
}
$OutputPath = [IO.Path]::GetFullPath($OutputPath)

$actorCatalogPath = Join-Path $RepositoryRoot (
    'Remake\game\data\original_runtime_actor_catalog.json')
$actorCatalogText = [IO.File]::ReadAllText(
    $actorCatalogPath,
    [Text.UTF8Encoding]::new($false))
$actorCatalog = $actorCatalogText | ConvertFrom-Json
if (
    [int]$actorCatalog.schema_version -ne 1 -or
    [string]$actorCatalog.content_profile -ne (
        'repository-mod-12-level-20260729')
) {
    throw 'The original runtime actor catalog has an unsupported profile.'
}

$levels = @(
    for ($levelIndex = 0; $levelIndex -lt 12; $levelIndex++) {
        $levelId = 'm{0:D3}' -f $levelIndex
        $summaryPath = Join-Path $CaptureRoot (
            'level-{0:D2}\crt-random-startup-summary.json' -f (
                $levelIndex + 1))
        if (-not (Test-Path -LiteralPath $summaryPath -PathType Leaf)) {
            throw "CRT random startup summary is missing: $summaryPath"
        }
        $summaryText = [IO.File]::ReadAllText(
            $summaryPath,
            [Text.UTF8Encoding]::new($false))
        $summary = $summaryText | ConvertFrom-Json
        if (
            [int]$summary.schema_version -ne 1 -or
            [string]$summary.source_profile -ne (
                'repository-mod-12-level-20260729') -or
            [string]$summary.level_id -ne $levelId -or
            -not [bool]$summary.trace.contiguous -or
            -not [bool]$summary.trace.lcg_verified -or
            [int]$summary.trace.uncatalogued_call_sites -ne 0
        ) {
            throw "Unsupported or failed CRT random summary for $levelId."
        }

        $runtimeLevel = $actorCatalog.levels.$levelId
        if ($null -eq $runtimeLevel) {
            throw "Runtime actor catalog does not contain $levelId."
        }
        $initializationByRuntimeIndex = @{}
        foreach ($entry in @($summary.startup.actor_initialization)) {
            $runtimeIndex = [int]$entry.runtime_index
            if ($initializationByRuntimeIndex.ContainsKey($runtimeIndex)) {
                throw (
                    "Duplicate startup actor runtime index " +
                    "$runtimeIndex in $levelId.")
            }
            $initializationByRuntimeIndex[$runtimeIndex] = $entry
        }
        $activeActorInitialization = @(
            foreach ($actorProperty in @(
                    $runtimeLevel.actors.PSObject.Properties |
                        Sort-Object {
                            [int]$_.Value.runtime_index
                        })) {
                $actor = $actorProperty.Value
                $runtimeIndex = [int]$actor.runtime_index
                if (-not $initializationByRuntimeIndex.ContainsKey(
                        $runtimeIndex)) {
                    throw (
                        "Startup capture for $levelId does not contain " +
                        "active runtime actor $runtimeIndex.")
                }
                $initialization = (
                    $initializationByRuntimeIndex[$runtimeIndex])
                [ordered]@{
                    runtime_index = $runtimeIndex
                    scene_index = [int]$actorProperty.Name
                    initial_idle_limit = (
                        [int]$initialization.initial_idle_limit)
                    initial_facing_direction = (
                        [int]$initialization.initial_facing_direction)
                    initial_ai_phase = (
                        [int]$initialization.initial_ai_phase)
                    initial_reaction_limit = (
                        [int]$initialization.initial_reaction_limit)
                }
            }
        )
        $gateActorIndices = @(
            $summary.startup.observation_gate_actor_indices |
                ForEach-Object { [int]$_ }
        )
        $knownRuntimeIndices = @{}
        foreach ($entry in $activeActorInitialization) {
            $knownRuntimeIndices[[int]$entry.runtime_index] = $true
        }
        foreach ($runtimeIndex in $gateActorIndices) {
            if (-not $knownRuntimeIndices.ContainsKey($runtimeIndex)) {
                throw (
                    "Observation gate actor $runtimeIndex in $levelId " +
                    'is not an active resolved actor.')
            }
        }

        [ordered]@{
            id = $levelId
            initialization_draw_count = (
                [int]$summary.startup.initialization_draw_count)
            final_state_hex = (
                [string]$summary.startup.final_state_hex)
            ambient_prefix_draw_count = (
                [int]$summary.startup.ambient_prefix_draw_count)
            first_actor_sequence = (
                [int]$summary.startup.first_actor_sequence)
            first_gameplay_update_sequence = (
                [int]$summary.startup.first_gameplay_update_sequence)
            actor_constructor_count = (
                [int]$summary.startup.actor_constructor_count)
            imported_entity_count = (
                [int]$summary.startup.imported_entity_count)
            constructor_minus_entity_count = (
                [int]$summary.startup.constructor_minus_entity_count)
            ordered_call_site_sha256 = (
                [string]$summary.startup.ordered_call_site_sha256)
            ordered_value_sha256 = (
                [string]$summary.startup.ordered_value_sha256)
            observation_gate_actor_indices = $gateActorIndices
            actor_initialization = $activeActorInitialization
        }
    }
)

$baseline = [ordered]@{
    schema_version = 1
    catalog_id = 'original-crt-random-startup-v1'
    content_profile = 'repository-mod-12-level-20260729'
    executable_sha256 = (
        [string](
            [IO.File]::ReadAllText(
                (Join-Path $CaptureRoot (
                    'level-01\crt-random-startup-summary.json')),
                [Text.UTF8Encoding]::new($false)) |
                ConvertFrom-Json
        ).executable_sha256
    )
    evidence = [ordered]@{
        capture_mode = 'process-local-crt-rand-hook'
        hook_scope = 'test-only-environment-gated'
        input_scope = 'target-window-only'
        initial_state = '0x00000001'
        algorithm = 'MSVC LCG: state=state*214013+2531011; value=(state>>16)&0x7fff'
        call_site_catalog = 'SDK/crt-rand-call-sites.json'
        actor_identity_catalog = (
            'game/data/original_runtime_actor_catalog.json')
    }
    levels = $levels
}

$outputDirectory = Split-Path -Parent $OutputPath
[IO.Directory]::CreateDirectory($outputDirectory) | Out-Null
$json = $baseline | ConvertTo-Json -Depth 12 -Compress
[IO.File]::WriteAllText(
    $OutputPath,
    $json + [Environment]::NewLine,
    [Text.UTF8Encoding]::new($false))

Write-Host (
    "CRT random startup baseline generated: {0} levels, {1} actors." -f
    $levels.Count,
    @($levels.actor_initialization).Count)
Get-Item -LiteralPath $OutputPath
