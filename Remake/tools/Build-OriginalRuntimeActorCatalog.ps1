[CmdletBinding()]
param(
    [string]$IdentityRoot = '',
    [string]$PatrolBaselineRoot = '',
    [string]$OutputPath = ''
)

$ErrorActionPreference = 'Stop'
$remakeRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if ([string]::IsNullOrWhiteSpace($IdentityRoot)) {
    $IdentityRoot = Join-Path $remakeRoot 'validation\identities\mod'
}
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path `
        $remakeRoot `
        'game\data\original_runtime_actor_catalog.json'
}
if ([string]::IsNullOrWhiteSpace($PatrolBaselineRoot)) {
    $PatrolBaselineRoot = Join-Path $remakeRoot 'validation\baselines\mod'
}
$IdentityRoot = (Resolve-Path -LiteralPath $IdentityRoot).Path
$PatrolBaselineRoot = (Resolve-Path -LiteralPath $PatrolBaselineRoot).Path

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

function Convert-ObservedPoint {
    param(
        $Value,
        [string]$Description
    )

    if ($Value -is [Array] -and @($Value).Count -eq 2) {
        return @([int]$Value[0], [int]$Value[1])
    }
    $parts = @(([string]$Value).Split(
        @(' ', ','),
        [StringSplitOptions]::RemoveEmptyEntries))
    if ($parts.Count -ne 2) {
        throw "Invalid observed point for $Description."
    }
    return @([int]$parts[0], [int]$parts[1])
}

# Four reconstructed A* routes produce a one-second detour substantially
# larger than the stable process displacement. These scene/segment decisions
# come from the audited all-level parity comparison, not from VWF guesswork.
# The runtime keeps the legal A* geometry but bounds only these adjudicated
# segments to the captured displacement radius.
$patrolRadiusGuards = @{
    m002 = @{ 871 = @(3) }
    m004 = @{ 2637 = @(2) }
    m007 = @{ 2281 = @(2) }
    m011 = @{ 1203 = @(3) }
}
# Two m004 evidence legs end inside cells that the reconstructed static overlay
# marks blocked even though the stable executable reaches those exact runtime
# coordinates. Follow normal A* geometry first, then let only the final
# evidence-backed leg cross that reconstructed endpoint discrepancy.
$patrolFinalRelocations = @{
    m004 = @{
        2534 = @(2)
        2657 = @(1, 3)
    }
}

$levels = [ordered]@{}
$resolvedTotal = 0
$unresolvedTotal = 0
$factionOverrideTotal = 0
$patrolRadiusGuardTotal = 0
$patrolFinalRelocationTotal = 0
for ($levelIndex = 0; $levelIndex -lt 12; ++$levelIndex) {
    $levelId = 'm{0:D3}' -f $levelIndex
    $identityPath = Join-Path `
        $IdentityRoot `
        "$levelId-runtime-actors-v1.json"
    if (-not (Test-Path -LiteralPath $identityPath -PathType Leaf)) {
        throw "Missing runtime identity catalog: $identityPath"
    }
    $identityCatalog = Get-Content -LiteralPath $identityPath `
        -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([string]$identityCatalog.level.id -ne $levelId) {
        throw "Runtime identity route mismatch for $levelId."
    }
    $patrolBaselinePath = Join-Path `
        $PatrolBaselineRoot `
        "$levelId-enemy-patrol-v1.json"
    if (-not (Test-Path -LiteralPath $patrolBaselinePath -PathType Leaf)) {
        throw "Missing stable-MOD patrol baseline: $patrolBaselinePath"
    }
    $patrolBaseline = Get-Content -LiteralPath $patrolBaselinePath `
        -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([string]$patrolBaseline.level.id -ne $levelId -or
        [string]$patrolBaseline.scenario.id -ne
            "$levelId-enemy-patrol-v1" -or
        @($patrolBaseline.checkpoints).Count -ne 4) {
        throw "Stable-MOD patrol baseline route mismatch for $levelId."
    }
    $patrolActors = @{}
    foreach ($patrolActor in $patrolBaseline.checkpoints[0].actors) {
        $patrolActors[[int]$patrolActor.scene_index] = @(
            $patrolActor,
            @($patrolBaseline.checkpoints[1].actors |
                Where-Object scene_index -eq $patrolActor.scene_index)[0],
            @($patrolBaseline.checkpoints[3].actors |
                Where-Object scene_index -eq $patrolActor.scene_index)[0]
        )
    }

    $actors = [ordered]@{}
    foreach ($identity in $identityCatalog.identities) {
        if ([string]$identity.status -ne 'resolved') {
            continue
        }
        $sceneIndex = [int]$identity.scene_index
        if ($sceneIndex -lt 0 -or $actors.Contains($sceneIndex.ToString())) {
            throw "$levelId has an invalid or duplicate resolved scene identity."
        }
        $runtimeFaction = [int]$identity.runtime_faction_id
        $vwfFaction = [int]$identity.vwf_faction_id
        if ($runtimeFaction -ne $vwfFaction) {
            ++$factionOverrideTotal
        }
        $actor = [ordered]@{
            runtime_index = [int]$identity.runtime_index
            runtime_type = [int]$identity.runtime_type
            runtime_faction_id = $runtimeFaction
            vwf_faction_id = $vwfFaction
            database_entry_id = [int]$identity.database_entry_id
            display_name = [string]$identity.display_name
            authored_hit_points = [int]$identity.authored_hit_points
            authored_attack_type = [int]$identity.authored_attack_type
            confidence = [string]$identity.confidence
        }
        if ($null -ne $identity.observed) {
            $actor.observed = [ordered]@{
                position = Convert-ObservedPoint `
                    $identity.observed.position `
                    "$levelId scene $sceneIndex position"
                facing_direction = [int]$identity.observed.facing_direction
                goal_kind = [int]$identity.observed.goal_kind
                goal = Convert-ObservedPoint `
                    $identity.observed.goal `
                    "$levelId scene $sceneIndex goal"
            }
        }
        if ($vwfFaction -eq 1 -and
            $patrolActors.ContainsKey($sceneIndex)) {
            $samples = $patrolActors[$sceneIndex]
            $initialPosition = @($actor.observed.position)
            $actor.patrol_timeline = @(
                [ordered]@{
                    elapsed_ms = 0
                    position = $initialPosition
                    facing_direction = [int]$actor.observed.facing_direction
                },
                [ordered]@{
                    elapsed_ms = 5000
                    position = @(
                        [int]$samples[0].position[0],
                        [int]$samples[0].position[1])
                    facing_direction =
                        [int]$samples[0].facing_direction
                },
                [ordered]@{
                    elapsed_ms = 6000
                    position = @(
                        [int]$samples[1].position[0],
                        [int]$samples[1].position[1])
                    facing_direction =
                        [int]$samples[1].facing_direction
                },
                [ordered]@{
                    elapsed_ms = 7000
                    position = @(
                        [int]$samples[2].position[0],
                        [int]$samples[2].position[1])
                    facing_direction =
                        [int]$samples[2].facing_direction
                },
                [ordered]@{
                    elapsed_ms = 12000
                    position = $initialPosition
                    facing_direction = [int]$actor.observed.facing_direction
                }
            )
            if ($patrolRadiusGuards.ContainsKey($levelId) -and
                $patrolRadiusGuards[$levelId].ContainsKey($sceneIndex)) {
                $actor.patrol_radius_guard_target_indices = @(
                    $patrolRadiusGuards[$levelId][$sceneIndex] |
                        ForEach-Object { [int]$_ })
                ++$patrolRadiusGuardTotal
            }
            if ($patrolFinalRelocations.ContainsKey($levelId) -and
                $patrolFinalRelocations[$levelId].ContainsKey($sceneIndex)) {
                $actor.patrol_final_relocation_target_indices = @(
                    $patrolFinalRelocations[$levelId][$sceneIndex] |
                        ForEach-Object { [int]$_ })
                ++$patrolFinalRelocationTotal
            }
        }
        $actors[$sceneIndex.ToString()] = $actor
        ++$resolvedTotal
    }
    $unresolvedCount = [int]$identityCatalog.summary.unresolved_count
    $unresolvedTotal += $unresolvedCount
    $levels[$levelId] = [ordered]@{
        resolved_actor_count = $actors.Count
        unresolved_actor_count = $unresolvedCount
        identity_catalog_sha256 =
            Get-CanonicalTextSha256 -LiteralPath $identityPath
        patrol_baseline_sha256 =
            Get-CanonicalTextSha256 -LiteralPath $patrolBaselinePath
        actors = $actors
    }
}

if ($resolvedTotal -ne 772 -or
    $unresolvedTotal -ne 0 -or
    $factionOverrideTotal -ne 5 -or
    $patrolRadiusGuardTotal -ne 4 -or
    $patrolFinalRelocationTotal -ne 2) {
    throw (
        "Runtime actor totals changed: resolved=$resolvedTotal, " +
        "unresolved=$unresolvedTotal, faction overrides=$factionOverrideTotal, " +
        "patrol radius guards=$patrolRadiusGuardTotal, " +
        "patrol final relocations=$patrolFinalRelocationTotal.")
}

$document = [ordered]@{
    schema_version = 1
    catalog_id = 'original-runtime-actor-catalog-v1'
    content_profile = 'repository-mod-12-level-20260729'
    summary = [ordered]@{
        level_count = 12
        resolved_actor_count = $resolvedTotal
        unresolved_actor_count = $unresolvedTotal
        runtime_faction_override_count = $factionOverrideTotal
        patrol_radius_guard_actor_count = $patrolRadiusGuardTotal
        patrol_final_relocation_actor_count = $patrolFinalRelocationTotal
    }
    semantics = [ordered]@{
        runtime_index = 'capture-local actor-array index; never a VWF scene index'
        scene_index = 'stable VWF scene identity'
        runtime_faction_id = 'live RuntimeActorV1 +0x150 value at gameplay entry'
        vwf_faction_id = 'authored VWF faction value'
        identity_catalog_hash = 'SHA-256 of UTF-8 text normalized to LF without BOM'
        patrol_timeline = 'MOD gameplay-entry position plus the audited 5 s, 6 s and 7 s patrol samples; 12 s closes a deterministic replay loop'
        patrol_radius_guard_target_indices = 'audited target-sample indices whose reconstructed A* detour must remain inside the stable-MOD displacement radius'
    }
    levels = $levels
}

[IO.Directory]::CreateDirectory(
    [IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($OutputPath))
) | Out-Null
$utf8NoBom = [Text.UTF8Encoding]::new($false)
$catalogJson = (
    ($document | ConvertTo-Json -Depth 20).
        Replace("`r`n", "`n").
        Replace("`r", "`n") + "`n")
[IO.File]::WriteAllText(
    [IO.Path]::GetFullPath($OutputPath),
    $catalogJson,
    $utf8NoBom)
Write-Host (
    "Original runtime actor catalog generated: $resolvedTotal resolved, " +
    "$unresolvedTotal unresolved, $factionOverrideTotal faction overrides.")
