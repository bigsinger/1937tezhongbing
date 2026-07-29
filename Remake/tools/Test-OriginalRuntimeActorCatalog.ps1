[CmdletBinding()]
param(
    [string]$CatalogPath = ''
)

$ErrorActionPreference = 'Stop'
$remakeRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$identityRoot = Join-Path $remakeRoot 'validation\identities\mod'
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
$factionOverrides = @()
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
if ($resolvedTotal -ne 762 -or
    $unresolvedTotal -ne 10 -or
    (Compare-Object $expectedOverrides $factionOverrides).Count -ne 0 -or
    [int]$catalog.summary.resolved_actor_count -ne $resolvedTotal -or
    [int]$catalog.summary.unresolved_actor_count -ne $unresolvedTotal -or
    [int]$catalog.summary.runtime_faction_override_count -ne
        $factionOverrides.Count) {
    throw 'Original runtime actor catalog totals or faction overrides changed.'
}
Write-Host (
    "Original runtime actor catalog passed: $resolvedTotal resolved actors, " +
    "$($factionOverrides.Count) exact faction overrides.")
