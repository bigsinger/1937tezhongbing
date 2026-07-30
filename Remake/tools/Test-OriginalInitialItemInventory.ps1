[CmdletBinding()]
param(
    [string]$BaselinePath = '',

    [string]$GameDataPath = ''
)

$ErrorActionPreference = 'Stop'
$remakeRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if ([string]::IsNullOrWhiteSpace($BaselinePath)) {
    $BaselinePath = Join-Path `
        $remakeRoot `
        'validation\baselines\mod\initial-item-inventory-v1.json'
}
if ([string]::IsNullOrWhiteSpace($GameDataPath)) {
    $GameDataPath = Join-Path `
        $remakeRoot `
        'game\data\original_initial_item_inventory.json'
}

function Read-Json {
    param([Parameter(Mandatory = $true)][string]$LiteralPath)

    if (-not (Test-Path -LiteralPath $LiteralPath -PathType Leaf)) {
        throw "Required backpack artifact is missing: $LiteralPath"
    }
    return Get-Content -LiteralPath $LiteralPath -Raw -Encoding UTF8 |
        ConvertFrom-Json
}

function Canonical-Json {
    param([Parameter(Mandatory = $true)][object]$Value)

    return $Value | ConvertTo-Json -Depth 24 -Compress
}

$baseline = Read-Json -LiteralPath $BaselinePath
$gameData = Read-Json -LiteralPath $GameDataPath
if ([int]$baseline.schema_version -ne 1 -or
    [int]$gameData.schema_version -ne 1) {
    throw 'Original initial backpack schema version is invalid.'
}
if ([string]$baseline.content_profile -ne
    [string]$gameData.content_profile) {
    throw 'Backpack baseline and product data use different content profiles.'
}
foreach ($field in @(
    'item_catalog',
    'allowed_quantity_modes',
    'semantics',
    'summary',
    'levels'
)) {
    if ((Canonical-Json $baseline.$field) -cne
        (Canonical-Json $gameData.$field)) {
        throw "Backpack baseline and product data differ at '$field'."
    }
}

$expectedPlayerCounts = @(1, 3, 1, 4, 1, 3, 1, 3, 2, 2, 4, 2)
$expectedItemIds = @(33, 46, 47, 48, 49, 50, 51, 52, 53, 54, 82, 83, 92, 101)
$actorTotal = 0
$entryTotal = 0
$emptyActorTotal = 0
$playerTotal = 0
$playerEntryTotal = 0
$emptyPlayerTotal = 0
$sceneKeys = @{}

for ($levelIndex = 0; $levelIndex -lt 12; ++$levelIndex) {
    $levelId = 'm{0:D3}' -f $levelIndex
    $level = $gameData.levels.$levelId
    if ($null -eq $level) {
        throw "Product backpack catalog is missing $levelId."
    }
    $levelPlayerCount = 0
    foreach ($actor in @($level.actors)) {
        $sceneKey = "$levelId/$([int]$actor.scene_index)"
        if ($sceneKeys.ContainsKey($sceneKey)) {
            throw "Duplicate actor backpack scene identity: $sceneKey"
        }
        $sceneKeys[$sceneKey] = $true
        if ([string]::IsNullOrWhiteSpace([string]$actor.display_name)) {
            throw "$sceneKey has no display name."
        }
        $indices = @()
        $seenItems = @{}
        foreach ($item in @($actor.items)) {
            $itemId = [int]$item.item_id
            if ($itemId -notin $expectedItemIds) {
                throw "$sceneKey contains unsupported item $itemId."
            }
            $allowedModes = @($gameData.allowed_quantity_modes."$itemId")
            if ([int]$item.quantity_mode -notin $allowedModes) {
                throw "$sceneKey item $itemId has invalid quantity semantics."
            }
            if ([int]$item.quantity -lt 0 -or $seenItems.ContainsKey($itemId)) {
                throw "$sceneKey item $itemId has invalid quantity or is duplicated."
            }
            $seenItems[$itemId] = $true
            $indices += [int]$item.inventory_index
            ++$entryTotal
            if ([bool]$actor.is_player_at_capture) {
                ++$playerEntryTotal
            }
        }
        $orderedIndices = @($indices | Sort-Object)
        for ($inventoryIndex = 0;
             $inventoryIndex -lt $orderedIndices.Count;
             ++$inventoryIndex) {
            if ($orderedIndices[$inventoryIndex] -ne $inventoryIndex) {
                throw "$sceneKey backpack order is not contiguous."
            }
        }
        if ($indices.Count -eq 0) {
            ++$emptyActorTotal
            if ([bool]$actor.is_player_at_capture) {
                ++$emptyPlayerTotal
            }
        }
        if ([bool]$actor.is_player_at_capture) {
            ++$playerTotal
            ++$levelPlayerCount
        }
        ++$actorTotal
    }
    if ($levelPlayerCount -ne $expectedPlayerCounts[$levelIndex]) {
        throw (
            "$levelId has $levelPlayerCount players; expected " +
            "$($expectedPlayerCounts[$levelIndex]).")
    }
}

$expectedTotals = @{
    actorTotal = 660
    entryTotal = 539
    emptyActorTotal = 316
    playerTotal = 27
    playerEntryTotal = 74
    emptyPlayerTotal = 1
}
foreach ($name in $expectedTotals.Keys) {
    $actual = Get-Variable -Name $name -ValueOnly
    if ([int]$actual -ne [int]$expectedTotals[$name]) {
        throw "$name is $actual; expected $($expectedTotals[$name])."
    }
}
if ([int]$gameData.summary.exact_actor_count -ne $actorTotal -or
    [int]$gameData.summary.inventory_entry_count -ne $entryTotal -or
    [int]$gameData.summary.empty_actor_count -ne $emptyActorTotal -or
    [int]$gameData.summary.player_count -ne $playerTotal -or
    [int]$gameData.summary.player_inventory_entry_count -ne $playerEntryTotal -or
    [int]$gameData.summary.empty_player_count -ne $emptyPlayerTotal) {
    throw 'Backpack summary totals do not match the catalog.'
}

$m000Player = @($gameData.levels.m000.actors |
    Where-Object { [bool]$_.is_player_at_capture })[0]
if ([int]$m000Player.scene_index -ne 1436 -or
    @($m000Player.items).Count -ne 1 -or
    [int]$m000Player.items[0].item_id -ne 50 -or
    [int]$m000Player.items[0].quantity -ne 2 -or
    [int]$m000Player.items[0].quantity_mode -ne 0) {
    throw 'm000 player backpack is not the recovered two-watermelon loadout.'
}
$m000FormationActor = @($gameData.levels.m000.actors |
    Where-Object { [int]$_.scene_index -eq 1572 })[0]
if ($null -eq $m000FormationActor -or
    @($m000FormationActor.items).Count -ne 1 -or
    [int]$m000FormationActor.items[0].item_id -ne 33 -or
    [int]$m000FormationActor.items[0].quantity -ne 1 -or
    [int]$m000FormationActor.items[0].quantity_mode -ne 0) {
    throw 'The recovered m000 formation actor item-33 inventory is invalid.'
}
if ([string]$gameData.item_catalog.'47'.effect.kind -ne 'set_hit_points' -or
    [int]$gameData.item_catalog.'47'.effect.value -ne 8 -or
    [int]$gameData.item_catalog.'50'.effect.value -ne 4 -or
    [int]$gameData.item_catalog.'51'.effect.value -ne 6) {
    throw 'Recovered healing behavior metadata is invalid.'
}
if ([int]$gameData.item_catalog.'46'.effect.refill_by_weapon_item_id.'36' -ne 10 -or
    [int]$gameData.item_catalog.'46'.effect.refill_by_weapon_item_id.'37' -ne 5 -or
    [int]$gameData.item_catalog.'46'.effect.refill_by_weapon_item_id.'43' -ne 3) {
    throw 'Recovered ammunition-box refill behavior metadata is invalid.'
}

Write-Host (
    "Original backpack parity passed: 12 levels, $actorTotal exact actors, " +
    "$entryTotal entries; players=$playerTotal/$playerEntryTotal.")
