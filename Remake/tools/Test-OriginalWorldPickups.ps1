[CmdletBinding()]
param(
    [string]$BaselinePath = '',

    [string]$GameDataPath = '',

    [string]$DatabasePath = ''
)

$ErrorActionPreference = 'Stop'
$remakeRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $remakeRoot '..'))
if ([string]::IsNullOrWhiteSpace($BaselinePath)) {
    $BaselinePath = Join-Path `
        $remakeRoot `
        'validation\baselines\mod\world-pickups-v1.json'
}
if ([string]::IsNullOrWhiteSpace($GameDataPath)) {
    $GameDataPath = Join-Path $remakeRoot 'game\data\world_pickups.json'
}
if ([string]::IsNullOrWhiteSpace($DatabasePath)) {
    $DatabasePath = Join-Path $repositoryRoot 'Mod\1937Database.dbl'
}

function Read-Json {
    param([Parameter(Mandatory = $true)][string]$LiteralPath)

    if (-not (Test-Path -LiteralPath $LiteralPath -PathType Leaf)) {
        throw "Required world-pickup artifact is missing: $LiteralPath"
    }
    return Get-Content -LiteralPath $LiteralPath -Raw -Encoding UTF8 |
        ConvertFrom-Json
}

$baseline = Read-Json -LiteralPath $BaselinePath
$gameData = Read-Json -LiteralPath $GameDataPath
if ([int]$baseline.schema_version -ne 1 -or
    [string]$baseline.catalog_id -ne 'original-world-pickups-v1' -or
    [string]$baseline.content_profile -ne
        'repository-mod-12-level-20260729') {
    throw 'Original world-pickup baseline identity is invalid.'
}
if ([int]$gameData.schema_version -ne 2 -or
    [int]$gameData.entity_count -ne 11) {
    throw 'Product world-pickup catalog schema is invalid.'
}

$expectedDatabaseIds = @(982, 983, 984, 986, 987, 988, 990, 993, 998, 999)
$actualDatabaseIds = @($baseline.pickup_grants |
    ForEach-Object { [int]$_.database_entry_id })
if ((Compare-Object $expectedDatabaseIds $actualDatabaseIds).Count -ne 0) {
    throw 'World-pickup baseline has an unexpected DBL identity set.'
}

foreach ($row in @($baseline.pickup_grants)) {
    $databaseEntryId = [int]$row.database_entry_id
    $profile = $gameData.entities."$databaseEntryId"
    if ($null -eq $profile) {
        throw "Product catalog is missing DBL $databaseEntryId."
    }
    $grant = $profile.grant
    if ([string]$profile.original_display_name -cne
            [string]$row.display_name -or
        [string]$profile.behavior -ne 'field_pickup' -or
        [string]$grant.kind -ne 'original_inventory_item' -or
        [int]$grant.item_id -ne [int]$row.item_id -or
        [string]$grant.container -ne [string]$row.container -or
        [int]$grant.quantity -ne [int]$row.quantity -or
        [int]$grant.quantity_mode -ne [int]$row.quantity_mode) {
        throw "Product grant for DBL $databaseEntryId differs from MOD evidence."
    }
    if ([string]$profile.source_status.item_id -ne
            'recovered_dbl_header_2' -or
        [string]$profile.source_status.container -ne
            'recovered_sub_45AE10' -or
        [string]$profile.source_status.quantity_mode -ne
            'recovered_sub_45AE10' -or
        [string]$profile.source_status.grant_quantity -ne
            'recovered_sub_453F70' -or
        [string]$profile.source_status.interaction_radius -ne
            'unresolved_remake_default') {
        throw "Product source labels for DBL $databaseEntryId are inaccurate."
    }
}

$barrelEvidence = @($baseline.explosive_props)[0]
$barrel = $gameData.entities.'1003'
if ([int]$barrelEvidence.database_entry_id -ne 1003 -or
    [int]$barrelEvidence.runtime_item_id -ne 53 -or
    [int]$barrel.runtime_item_id -ne 53 -or
    [string]$barrel.original_display_name -cne
        [string]$barrelEvidence.display_name -or
    [string]$barrel.source_status.runtime_item_id -ne
        'recovered_dbl_header_2') {
    throw 'Gasoline-barrel DBL header[2] evidence differs from product data.'
}

if ((Test-Path -LiteralPath $DatabasePath -PathType Leaf) -and
    (Get-Item -LiteralPath $DatabasePath).Length -gt 1000000) {
    $databaseSha256 = (
        Get-FileHash -LiteralPath $DatabasePath -Algorithm SHA256
    ).Hash
    if ($databaseSha256 -cne [string]$baseline.source.database_sha256) {
        throw 'Materialized MOD DBL hash differs from the pickup baseline.'
    }
}

Write-Host (
    'Original world-pickup parity passed: 10 exact grants, ' +
    'one gasoline-barrel runtime item ID, actor-local containers.')
