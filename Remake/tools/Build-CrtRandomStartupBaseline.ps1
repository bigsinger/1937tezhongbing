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
        $actorStatePath = Join-Path $CaptureRoot (
            'level-{0:D2}\actor-states-crt-startup.csv' -f (
                $levelIndex + 1))
        if (-not (Test-Path -LiteralPath $actorStatePath -PathType Leaf)) {
            throw "CRT startup actor state is missing: $actorStatePath"
        }
        $actorStateByRuntimeIndex = @{}
        foreach ($actorState in @(Import-Csv -LiteralPath $actorStatePath)) {
            $runtimeIndex = [int]$actorState.index
            if ($actorStateByRuntimeIndex.ContainsKey($runtimeIndex)) {
                throw (
                    "Duplicate CRT startup actor state runtime index " +
                    "$runtimeIndex in $levelId.")
            }
            $actorStateByRuntimeIndex[$runtimeIndex] = $actorState
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
        $firstGameplayRecords = @(
            foreach ($record in @(
                    $summary.first_gameplay_update.records)) {
                $runtimeIndex = [int]$record.runtime_index
                $callSite = [string]$record.call_site_rva
                if (
                    $runtimeIndex -lt 0 -and
                    $callSite -ne '0x00006A73'
                ) {
                    throw (
                        "First gameplay update for $levelId has an " +
                        "unmapped non-music call at $callSite.")
                }
                if (
                    $runtimeIndex -ge 0 -and
                    -not $knownRuntimeIndices.ContainsKey($runtimeIndex)
                ) {
                    throw (
                        "First gameplay update actor $runtimeIndex in " +
                        "$levelId is not active.")
                }
                [ordered]@{
                    runtime_index = $runtimeIndex
                    call_site_rva = $callSite
                    value = [int]$record.value
                }
            }
        )
        if (
            $firstGameplayRecords.Count -ne (
                [int]$summary.first_gameplay_update.draw_count) -or
            @($firstGameplayRecords | Where-Object {
                [string]$_.call_site_rva -eq '0x0005C81C'
            }).Count -ne $gateActorIndices.Count
        ) {
            throw "First gameplay update mismatch for $levelId."
        }
        $firstGameplayRecordsByActor = @{}
        $firstGameplayActorOrder = @()
        foreach ($record in $firstGameplayRecords) {
            $runtimeIndex = [int]$record.runtime_index
            $callSite = [string]$record.call_site_rva
            if (
                $runtimeIndex -lt 0 -or
                $callSite -eq '0x0005C81C'
            ) {
                continue
            }
            if (-not $firstGameplayRecordsByActor.ContainsKey(
                    $runtimeIndex)) {
                $firstGameplayRecordsByActor[$runtimeIndex] = @()
                $firstGameplayActorOrder += $runtimeIndex
            }
            $firstGameplayRecordsByActor[$runtimeIndex] = @(
                $firstGameplayRecordsByActor[$runtimeIndex]) + @($record)
        }
        $firstGameplayActorOutcomes = @(
            foreach ($runtimeIndexValue in $firstGameplayActorOrder) {
                $runtimeIndex = [int]$runtimeIndexValue
                if (
                    -not $initializationByRuntimeIndex.ContainsKey(
                        $runtimeIndex) -or
                    -not $actorStateByRuntimeIndex.ContainsKey(
                        $runtimeIndex)
                ) {
                    throw (
                        "First gameplay actor outcome $runtimeIndex in " +
                        "$levelId has no identity or post-update state.")
                }
                $actorRecords = @(
                    $firstGameplayRecordsByActor[$runtimeIndex])
                $callSites = @(
                    $actorRecords |
                        ForEach-Object {
                            [string]$_.call_site_rva
                        })
                $semanticEffects = @()
                if ($callSites -contains '0x00058946') {
                    $semanticEffects += 'route_wait_limit'
                }
                if ($callSites -contains '0x00055BFB') {
                    foreach ($requiredSite in @(
                            '0x00055BFB',
                            '0x00055C0F',
                            '0x00055C23',
                            '0x00055C3A')) {
                        if ($callSites -notcontains $requiredSite) {
                            throw (
                                "Incomplete blocked retry tuple for " +
                                "$levelId actor $runtimeIndex.")
                        }
                    }
                    $semanticEffects += 'blocked_retry_destination'
                }
                if ($callSites -contains '0x00055216') {
                    $semanticEffects += 'primary_candidate_scan'
                }
                if ($callSites -contains '0x0005CEA6') {
                    if ($callSites -contains '0x0005CF33') {
                        foreach ($requiredSite in @(
                                '0x0005CF33',
                                '0x0005CF4A',
                                '0x0005CF61',
                                '0x0005CF78')) {
                            if ($callSites -notcontains $requiredSite) {
                                throw (
                                    "Incomplete secondary search tuple " +
                                    "for $levelId actor $runtimeIndex.")
                            }
                        }
                        $semanticEffects += (
                            'secondary_search_destination')
                    }
                    else {
                        $semanticEffects += 'secondary_candidate_scan'
                    }
                }
                if ($callSites -contains '0x0005D47E') {
                    $semanticEffects += 'pursuit_command_snapshot'
                }
                if ($semanticEffects.Count -eq 0) {
                    throw (
                        "First gameplay actor $runtimeIndex in $levelId " +
                        'has no supported side-effect family.')
                }
                $routeWaitLimit = -1
                if ($callSites -contains '0x00058946') {
                    $routeRecord = @($actorRecords | Where-Object {
                        [string]$_.call_site_rva -eq '0x00058946'
                    })
                    if ($routeRecord.Count -ne 1) {
                        throw (
                            "Invalid route wait record for $levelId " +
                            "actor $runtimeIndex.")
                    }
                    $routeWaitLimit = (
                        [int]$routeRecord[0].value % 160) + 40
                }
                $actorState = $actorStateByRuntimeIndex[$runtimeIndex]
                $activeActorEntry = @(
                    $activeActorInitialization | Where-Object {
                        [int]$_.runtime_index -eq $runtimeIndex
                    })
                if ($activeActorEntry.Count -ne 1) {
                    throw (
                        "First gameplay actor $runtimeIndex in $levelId " +
                        'has no unique scene identity.')
                }
                [ordered]@{
                    runtime_index = $runtimeIndex
                    scene_index = [int]$activeActorEntry[0].scene_index
                    semantic_effects = $semanticEffects
                    call_site_rvas = $callSites
                    route_wait_limit = $routeWaitLimit
                    post_update_state = [ordered]@{
                        world_x = [int]$actorState.world_x
                        world_y = [int]$actorState.world_y
                        goal_kind = [int]$actorState.goal_kind
                        goal_x = [int]$actorState.goal_x
                        goal_y = [int]$actorState.goal_y
                        command_variant = (
                            [int]$actorState.command_variant)
                        command_pending = (
                            [int]$actorState.command_pending)
                        movement_active = (
                            [int]$actorState.movement_active)
                        movement_path_state = (
                            [int]$actorState.movement_path_state)
                        movement_mode = [int]$actorState.movement_mode
                        resolved_goal_x = (
                            [int]$actorState.resolved_goal_x)
                        resolved_goal_y = (
                            [int]$actorState.resolved_goal_y)
                        path_override_active = (
                            [int]$actorState.path_override)
                    }
                }
            }
        )

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
            first_gameplay_update = [ordered]@{
                draw_count = (
                    [int]$summary.first_gameplay_update.draw_count)
                ordered_call_site_sha256 = (
                    [string]$summary.first_gameplay_update.ordered_call_site_sha256)
                ordered_value_sha256 = (
                    [string]$summary.first_gameplay_update.ordered_value_sha256)
                records = $firstGameplayRecords
                actor_outcomes = $firstGameplayActorOutcomes
            }
        }
    }
)

$baseline = [ordered]@{
    schema_version = 3
    catalog_id = 'original-crt-random-startup-v3'
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
        post_update_actor_state = (
            'process-local RuntimeActorV1 snapshot after the captured ' +
            'first complete gameplay update')
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
