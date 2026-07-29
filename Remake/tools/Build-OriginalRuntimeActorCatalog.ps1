[CmdletBinding()]
param(
    [string]$IdentityRoot = '',
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
$IdentityRoot = (Resolve-Path -LiteralPath $IdentityRoot).Path

$levels = [ordered]@{}
$resolvedTotal = 0
$unresolvedTotal = 0
$factionOverrideTotal = 0
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
        $actors[$sceneIndex.ToString()] = [ordered]@{
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
        ++$resolvedTotal
    }
    $unresolvedCount = [int]$identityCatalog.summary.unresolved_count
    $unresolvedTotal += $unresolvedCount
    $levels[$levelId] = [ordered]@{
        resolved_actor_count = $actors.Count
        unresolved_actor_count = $unresolvedCount
        identity_catalog_sha256 = (
            Get-FileHash -LiteralPath $identityPath -Algorithm SHA256
        ).Hash
        actors = $actors
    }
}

if ($resolvedTotal -ne 762 -or
    $unresolvedTotal -ne 10 -or
    $factionOverrideTotal -ne 5) {
    throw (
        "Runtime actor totals changed: resolved=$resolvedTotal, " +
        "unresolved=$unresolvedTotal, faction overrides=$factionOverrideTotal.")
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
    }
    semantics = [ordered]@{
        runtime_index = 'capture-local actor-array index; never a VWF scene index'
        scene_index = 'stable VWF scene identity'
        runtime_faction_id = 'live RuntimeActorV1 +0x150 value at gameplay entry'
        vwf_faction_id = 'authored VWF faction value'
    }
    levels = $levels
}

[IO.Directory]::CreateDirectory(
    [IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($OutputPath))
) | Out-Null
$utf8NoBom = [Text.UTF8Encoding]::new($false)
[IO.File]::WriteAllText(
    [IO.Path]::GetFullPath($OutputPath),
    (($document | ConvertTo-Json -Depth 20) + [Environment]::NewLine),
    $utf8NoBom)
Write-Host (
    "Original runtime actor catalog generated: $resolvedTotal resolved, " +
    "$unresolvedTotal unresolved, $factionOverrideTotal faction overrides.")
