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
        'validation\baselines\mod\initial-weapon-inventory-v1.json'
}
if ([string]::IsNullOrWhiteSpace($GameDataPath)) {
    $GameDataPath = Join-Path `
        $remakeRoot `
        'game\data\original_initial_weapon_inventory.json'
}

function Read-Json {
    param([Parameter(Mandatory = $true)][string]$LiteralPath)

    if (-not (Test-Path -LiteralPath $LiteralPath -PathType Leaf)) {
        throw "Required inventory artifact is missing: $LiteralPath"
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
    throw 'Original initial inventory schema version is invalid.'
}
if ([string]$baseline.content_profile -ne
    [string]$gameData.content_profile) {
    throw 'Inventory baseline and product data use different content profiles.'
}
foreach ($field in @(
    'attack_type_to_item_id',
    'quantity_modes',
    'semantics',
    'summary',
    'levels'
)) {
    if ((Canonical-Json $baseline.$field) -cne
        (Canonical-Json $gameData.$field)) {
        throw "Inventory baseline and product data differ at '$field'."
    }
}

$expectedModes = @{
    36 = 2; 37 = 2; 38 = 2; 39 = 1; 40 = 1; 41 = 0
    42 = 1; 43 = 0; 44 = 0; 45 = 0; 99 = 1
}
$expectedAttackItems = @{
    1 = 36; 2 = 37; 3 = 38; 4 = 39; 5 = 40; 6 = 41
    7 = 42; 8 = 43; 9 = 44; 10 = 45; 11 = 99
}
$expectedPlayerCounts = @(1, 3, 1, 4, 1, 3, 1, 3, 2, 2, 4, 2)
$playerTotal = 0
$entryTotal = 0
$sceneKeys = @{}

for ($levelIndex = 0; $levelIndex -lt 12; ++$levelIndex) {
    $levelId = 'm{0:D3}' -f $levelIndex
    $level = $gameData.levels.$levelId
    if ($null -eq $level) {
        throw "Product inventory catalog is missing $levelId."
    }
    $players = @($level.players)
    if ($players.Count -ne $expectedPlayerCounts[$levelIndex]) {
        throw (
            "$levelId has $($players.Count) player loadouts; expected " +
            "$($expectedPlayerCounts[$levelIndex]).")
    }
    foreach ($player in $players) {
        $sceneKey = "$levelId/$([int]$player.scene_index)"
        if ($sceneKeys.ContainsKey($sceneKey)) {
            throw "Duplicate player scene loadout: $sceneKey"
        }
        $sceneKeys[$sceneKey] = $true
        if ([string]::IsNullOrWhiteSpace([string]$player.display_name)) {
            throw "$sceneKey has no display name."
        }
        if ([int]$player.default_attack_type -lt 1 -or
            [int]$player.default_attack_type -gt 11) {
            throw "$sceneKey has an invalid default attack type."
        }
        $indices = @()
        foreach ($item in @($player.items)) {
            $itemId = [int]$item.item_id
            if (-not $expectedModes.ContainsKey($itemId) -or
                [int]$item.quantity_mode -ne $expectedModes[$itemId]) {
                throw "$sceneKey item $itemId has invalid quantity semantics."
            }
            if ([int]$item.quantity -lt 0) {
                throw "$sceneKey item $itemId has a negative quantity."
            }
            $indices += [int]$item.inventory_index
            ++$entryTotal
        }
        $orderedIndices = @($indices | Sort-Object)
        for ($inventoryIndex = 0;
             $inventoryIndex -lt $orderedIndices.Count;
             ++$inventoryIndex) {
            if ($orderedIndices[$inventoryIndex] -ne $inventoryIndex) {
                throw "$sceneKey inventory order is not contiguous."
            }
        }
        ++$playerTotal
    }
}
foreach ($attackType in 1..11) {
    if ([int]$gameData.attack_type_to_item_id."$attackType" -ne
        $expectedAttackItems[$attackType]) {
        throw "Attack type $attackType maps to the wrong item id."
    }
}
foreach ($itemId in $expectedModes.Keys) {
    if ([int]$gameData.quantity_modes."$itemId" -ne
        $expectedModes[$itemId]) {
        throw "Item $itemId maps to the wrong quantity mode."
    }
}
if ($playerTotal -ne 27 -or $entryTotal -ne 83) {
    throw (
        "Inventory totals are invalid: players=$playerTotal, entries=$entryTotal.")
}
if ([int]$gameData.summary.player_count -ne $playerTotal -or
    [int]$gameData.summary.inventory_entry_count -ne $entryTotal) {
    throw 'Inventory summary totals do not match the catalog.'
}

Write-Host (
    "Original initial inventory parity passed: 12 levels, $playerTotal players, " +
    "$entryTotal ordered entries.")
