[CmdletBinding()]
param(
    [string]$CatalogPath = ''
)

$ErrorActionPreference = 'Stop'
$remakeRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$identityRoot = Join-Path $remakeRoot 'validation\identities\mod'
$patrolBaselineRoot = Join-Path $remakeRoot 'validation\baselines\mod'
if ([string]::IsNullOrWhiteSpace($CatalogPath)) {
    $CatalogPath = Join-Path `
        $remakeRoot `
        'game\data\original_runtime_actor_catalog.json'
}
if (-not (Test-Path -LiteralPath $CatalogPath -PathType Leaf)) {
    throw "Original runtime actor catalog is missing: $CatalogPath"
}

function Get-CanonicalTextSha256 {
    param([Parameter(Mandatory = $true)][string]$LiteralPath)

    $text = [IO.File]::ReadAllText(
        [IO.Path]::GetFullPath($LiteralPath),
        [Text.Encoding]::UTF8)
    $canonical = $text.Replace("`r`n", "`n").Replace("`r", "`n")
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes($canonical)
    $sha256 = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString(
            $sha256.ComputeHash($bytes))).Replace('-', '')
    }
    finally {
        $sha256.Dispose()
    }
}

$catalog = Get-Content -LiteralPath $CatalogPath `
    -Raw -Encoding UTF8 | ConvertFrom-Json
if ([int]$catalog.schema_version -ne 1 -or
    [string]$catalog.catalog_id -ne 'original-runtime-actor-catalog-v1' -or
    [string]$catalog.content_profile -ne
        'repository-mod-12-level-20260729') {
    throw 'Original runtime actor catalog header is invalid.'
}

$resolvedTotal = 0
$unresolvedTotal = 0
$patrolTimelineTotal = 0
$factionOverrides = @()
$patrolRadiusGuards = @()
$patrolFinalRelocations = @()
for ($levelIndex = 0; $levelIndex -lt 12; ++$levelIndex) {
    $levelId = 'm{0:D3}' -f $levelIndex
    $level = $catalog.levels.$levelId
    if ($null -eq $level) {
        throw "Original runtime actor catalog is missing $levelId."
    }
    $identityPath = Join-Path `
        $identityRoot `
        "$levelId-runtime-actors-v1.json"
    if (-not (Test-Path -LiteralPath $identityPath -PathType Leaf) -or
        (Get-CanonicalTextSha256 -LiteralPath $identityPath) -ne
            [string]$level.identity_catalog_sha256) {
        throw "$levelId product actor data is stale against its identity evidence."
    }
    $patrolBaselinePath = Join-Path `
        $patrolBaselineRoot `
        "$levelId-enemy-patrol-v1.json"
    if (-not (Test-Path -LiteralPath $patrolBaselinePath -PathType Leaf) -or
        (Get-CanonicalTextSha256 -LiteralPath $patrolBaselinePath) -ne
            [string]$level.patrol_baseline_sha256) {
        throw "$levelId patrol timelines are stale against their process evidence."
    }
    $patrolBaseline = Get-Content -LiteralPath $patrolBaselinePath `
        -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([string]$patrolBaseline.level.id -ne $levelId -or
        [string]$patrolBaseline.scenario.id -ne
            "$levelId-enemy-patrol-v1" -or
        @($patrolBaseline.checkpoints).Count -ne 4) {
        throw "$levelId patrol baseline header or checkpoint count is invalid."
    }
    $patrolSceneLookup = @{}
    foreach ($patrolActor in @($patrolBaseline.checkpoints[0].actors)) {
        $patrolSceneLookup[[int]$patrolActor.scene_index] = $true
    }
    $actors = @($level.actors.PSObject.Properties)
    if ($actors.Count -ne [int]$level.resolved_actor_count) {
        throw "$levelId resolved actor summary is invalid."
    }
    foreach ($actorProperty in $actors) {
        $actor = $actorProperty.Value
        if ([int]$actorProperty.Name -lt 0 -or
            [int]$actor.database_entry_id -lt 0 -or
            [string]::IsNullOrWhiteSpace([string]$actor.display_name) -or
            [string]$actor.confidence -notin @('exact', 'high')) {
            throw "$levelId scene $($actorProperty.Name) identity is invalid."
        }
        if ([int]$actor.runtime_faction_id -ne
            [int]$actor.vwf_faction_id) {
            $factionOverrides += (
                "$levelId/$($actorProperty.Name):" +
                "$([int]$actor.runtime_faction_id)")
        }
        $timelineProperty = $actor.PSObject.Properties['patrol_timeline']
        $expectsTimeline = $patrolSceneLookup.ContainsKey(
            [int]$actorProperty.Name)
        if (($null -ne $timelineProperty) -ne $expectsTimeline) {
            throw (
                "$levelId scene $($actorProperty.Name) patrol timeline " +
                'does not match its recovered runtime faction.')
        }
        if ($null -ne $timelineProperty) {
            $timeline = @($timelineProperty.Value)
            $expectedElapsedMs = @(0, 5000, 6000, 7000, 12000)
            if ($timeline.Count -ne $expectedElapsedMs.Count) {
                throw "$levelId scene $($actorProperty.Name) patrol timeline size is invalid."
            }
            for ($sampleIndex = 0;
                $sampleIndex -lt $timeline.Count;
                ++$sampleIndex) {
                $sample = $timeline[$sampleIndex]
                if ([int]$sample.elapsed_ms -ne
                    $expectedElapsedMs[$sampleIndex] -or
                    @($sample.position).Count -ne 2 -or
                    [int]$sample.facing_direction -lt 0 -or
                    [int]$sample.facing_direction -gt 8) {
                    throw (
                        "$levelId scene $($actorProperty.Name) patrol " +
                        "sample $sampleIndex is invalid.")
                }
            }
            if (@(Compare-Object `
                    @($actor.observed.position) `
                    @($timeline[0].position)).Count -ne 0 -or
                @(Compare-Object `
                    @($timeline[0].position) `
                    @($timeline[-1].position)).Count -ne 0) {
                throw (
                    "$levelId scene $($actorProperty.Name) patrol timeline " +
                    'does not start at the observed position and close its loop.')
            }
            ++$patrolTimelineTotal
        }
        $radiusGuardProperty = (
            $actor.PSObject.Properties[
                'patrol_radius_guard_target_indices'
            ]
        )
        if ($null -ne $radiusGuardProperty) {
            $indices = @($radiusGuardProperty.Value | ForEach-Object {
                [int]$_
            })
            if ($indices.Count -ne 1 -or $indices[0] -notin @(2, 3)) {
                throw (
                    "$levelId scene $($actorProperty.Name) patrol radius " +
                    'guard is invalid.')
            }
            $patrolRadiusGuards += (
                "$levelId/$($actorProperty.Name):$($indices -join ',')")
        }
        $finalRelocationProperty = (
            $actor.PSObject.Properties[
                'patrol_final_relocation_target_indices'
            ]
        )
        if ($null -ne $finalRelocationProperty) {
            $indices = @($finalRelocationProperty.Value | ForEach-Object {
                [int]$_
            })
            if ($indices.Count -lt 1 -or
                $indices.Count -gt 2 -or
                @($indices | Where-Object { $_ -notin @(1, 2, 3) }).Count -ne 0) {
                throw (
                    "$levelId scene $($actorProperty.Name) patrol final " +
                    'relocation is invalid.')
            }
            $patrolFinalRelocations += (
                "$levelId/$($actorProperty.Name):$($indices -join ',')")
        }
    }
    $resolvedTotal += $actors.Count
    $unresolvedTotal += [int]$level.unresolved_actor_count
}
$expectedOverrides = @(
    'm000/1427:2',
    'm002/877:2',
    'm004/2700:2',
    'm006/1460:1',
    'm007/2298:1'
)
$expectedPatrolRadiusGuards = @(
    'm002/871:3',
    'm004/2637:2',
    'm007/2281:2',
    'm011/1203:3'
)
$expectedPatrolFinalRelocations = @(
    'm004/2534:2',
    'm004/2657:1,3'
)
if ($resolvedTotal -ne 772 -or
    $unresolvedTotal -ne 0 -or
    $patrolTimelineTotal -ne 656 -or
    @(Compare-Object $expectedOverrides $factionOverrides).Count -ne 0 -or
    @(Compare-Object `
        $expectedPatrolRadiusGuards `
        $patrolRadiusGuards).Count -ne 0 -or
    @(Compare-Object `
        $expectedPatrolFinalRelocations `
        $patrolFinalRelocations).Count -ne 0 -or
    [int]$catalog.summary.resolved_actor_count -ne $resolvedTotal -or
    [int]$catalog.summary.unresolved_actor_count -ne $unresolvedTotal -or
    [int]$catalog.summary.runtime_faction_override_count -ne
        $factionOverrides.Count -or
    [int]$catalog.summary.patrol_radius_guard_actor_count -ne
        $patrolRadiusGuards.Count -or
    [int]$catalog.summary.patrol_final_relocation_actor_count -ne
        $patrolFinalRelocations.Count) {
    throw 'Original runtime actor catalog totals or faction overrides changed.'
}
Write-Host (
    "Original runtime actor catalog passed: $resolvedTotal resolved actors, " +
    "$($factionOverrides.Count) exact faction overrides, " +
    "$patrolTimelineTotal evidence-backed patrol timelines, " +
    "$($patrolRadiusGuards.Count) adjudicated route guards, " +
    "$($patrolFinalRelocations.Count) final-endpoint corrections.")
