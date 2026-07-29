[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$CaptureRoot,

    [string]$IdentityRoot = '',

    [string]$BaselinePath = '',

    [string]$GameDataPath = ''
)

$ErrorActionPreference = 'Stop'
$remakeRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if ([string]::IsNullOrWhiteSpace($IdentityRoot)) {
    $IdentityRoot = Join-Path $remakeRoot 'validation\identities\mod'
}
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

$quantityModes = [ordered]@{
    '36' = 2
    '37' = 2
    '38' = 2
    '39' = 1
    '40' = 1
    '41' = 0
    '42' = 1
    '43' = 0
    '44' = 0
    '45' = 0
    '99' = 1
}
$attackTypeToItemId = [ordered]@{
    '1' = 36
    '2' = 37
    '3' = 38
    '4' = 39
    '5' = 40
    '6' = 41
    '7' = 42
    '8' = 43
    '9' = 44
    '10' = 45
    '11' = 99
}
$expectedPlayerCounts = @(1, 3, 1, 4, 1, 3, 1, 3, 2, 2, 4, 2)

function Get-Sha256 {
    param([Parameter(Mandatory = $true)][string]$LiteralPath)

    return (Get-FileHash -LiteralPath $LiteralPath -Algorithm SHA256).Hash
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

function Read-Json {
    param([Parameter(Mandatory = $true)][string]$LiteralPath)

    return Get-Content -LiteralPath $LiteralPath -Raw -Encoding UTF8 |
        ConvertFrom-Json
}

function Convert-InventoryRows {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Rows
    )

    $items = @()
    foreach ($row in ($Rows | Sort-Object { [int]$_.inventory_index })) {
        $itemId = [int]$row.item_id
        $quantity = [int]$row.quantity
        $quantityMode = [int]$row.quantity_mode
        if (-not $quantityModes.Contains($itemId.ToString())) {
            throw "Unsupported original weapon item id $itemId."
        }
        if ($quantityMode -ne [int]$quantityModes[$itemId.ToString()]) {
            throw (
                "Item $itemId uses quantity mode $quantityMode, expected " +
                "$($quantityModes[$itemId.ToString()]).")
        }
        if ($quantity -lt 0) {
            throw "Item $itemId has negative quantity $quantity."
        }
        $items += [ordered]@{
            inventory_index = [int]$row.inventory_index
            item_id = $itemId
            quantity = $quantity
            quantity_mode = $quantityMode
        }
    }
    return $items
}

function Inventory-Signature {
    param([Parameter(Mandatory = $true)][object[]]$Rows)

    return (($Rows |
        Sort-Object { [int]$_.inventory_index } |
        ForEach-Object {
            '{0}:{1}:{2}:{3}' -f `
                [int]$_.inventory_index,
                [int]$_.item_id,
                [int]$_.quantity,
                [int]$_.quantity_mode
        }) -join ';')
}

$resolvedCaptureRoot = (Resolve-Path -LiteralPath $CaptureRoot).Path
$resolvedIdentityRoot = (Resolve-Path -LiteralPath $IdentityRoot).Path
$levels = [ordered]@{}
$provenanceLevels = [ordered]@{}
$playerTotal = 0
$itemTotal = 0

for ($levelIndex = 0; $levelIndex -lt 12; ++$levelIndex) {
    $levelId = 'm{0:D3}' -f $levelIndex
    $captureDirectory = Join-Path $resolvedCaptureRoot $levelId
    $entryPath = Join-Path $captureDirectory 'actor-inventory-entry.csv'
    $steadyPath = Join-Path $captureDirectory 'actor-inventory-steady.csv'
    $identityPath = Join-Path `
        $resolvedIdentityRoot `
        "$levelId-runtime-actors-v1.json"
    foreach ($requiredPath in @($entryPath, $steadyPath, $identityPath)) {
        if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
            throw "Required evidence is missing: $requiredPath"
        }
    }

    $identityCatalog = Read-Json -LiteralPath $identityPath
    if ([string]$identityCatalog.level.id -ne $levelId) {
        throw "Identity catalog route mismatch for $levelId."
    }
    $identitiesByRuntimeIndex = @{}
    foreach ($identity in $identityCatalog.identities) {
        $identitiesByRuntimeIndex[[int]$identity.runtime_index] = $identity
    }

    $entryRows = @(Import-Csv -LiteralPath $entryPath |
        Where-Object { [int]$_.faction -eq 3 })
    $steadyRows = @(Import-Csv -LiteralPath $steadyPath |
        Where-Object { [int]$_.faction -eq 3 })
    $runtimeIndices = @($entryRows |
        ForEach-Object { [int]$_.runtime_index } |
        Sort-Object -Unique)
    if ($runtimeIndices.Count -ne $expectedPlayerCounts[$levelIndex]) {
        throw (
            "$levelId has $($runtimeIndices.Count) captured players; expected " +
            "$($expectedPlayerCounts[$levelIndex]).")
    }

    $players = @()
    foreach ($runtimeIndex in $runtimeIndices) {
        if (-not $identitiesByRuntimeIndex.ContainsKey($runtimeIndex)) {
            throw "$levelId runtime actor $runtimeIndex has no identity record."
        }
        $identity = $identitiesByRuntimeIndex[$runtimeIndex]
        if ([string]$identity.status -ne 'resolved' -or
            [string]$identity.confidence -ne 'exact') {
            throw (
                "$levelId runtime actor $runtimeIndex is not an exact resolved " +
                'identity.')
        }
        if ([int]$identity.vwf_faction_id -ne 3) {
            throw "$levelId runtime actor $runtimeIndex is not a player actor."
        }
        $actorEntryRows = @($entryRows |
            Where-Object { [int]$_.runtime_index -eq $runtimeIndex })
        $actorSteadyRows = @($steadyRows |
            Where-Object { [int]$_.runtime_index -eq $runtimeIndex })
        if ((Inventory-Signature $actorEntryRows) -ne
            (Inventory-Signature $actorSteadyRows)) {
            throw (
                "$levelId runtime actor $runtimeIndex changed inventory before " +
                'the steady checkpoint.')
        }
        $items = @(Convert-InventoryRows -Rows $actorEntryRows)
        if ($items.Count -eq 0) {
            throw "$levelId runtime actor $runtimeIndex has an empty weapon list."
        }
        $players += [ordered]@{
            runtime_index = $runtimeIndex
            scene_index = [int]$identity.scene_index
            database_entry_id = [int]$identity.database_entry_id
            display_name = [string]$identity.display_name
            default_attack_type = [int]$identity.authored_attack_type
            items = $items
        }
        ++$playerTotal
        $itemTotal += $items.Count
    }

    $levels[$levelId] = [ordered]@{
        selector_level = $levelIndex + 1
        engine_mission = $levelIndex + 1
        players = $players
    }
    $provenanceLevels[$levelId] = [ordered]@{
        entry_snapshot_sha256 = Get-Sha256 -LiteralPath $entryPath
        steady_snapshot_sha256 = Get-Sha256 -LiteralPath $steadyPath
        identity_catalog_sha256 =
            Get-CanonicalTextSha256 -LiteralPath $identityPath
        player_count = $players.Count
    }
}

if ($playerTotal -ne 27 -or $itemTotal -ne 83) {
    throw (
        "Recovered inventory totals are invalid: players=$playerTotal, " +
        "items=$itemTotal; expected players=27, items=83.")
}

$sharedSemantics = [ordered]@{
    runtime_actor_inventory_offset = '0x22C'
    container_layout = [ordered]@{
        item_ids_address = '0x00'
        quantities_address = '0x04'
        quantity_modes_address = '0x08'
        item_count = '0x0C'
        size = '0x10'
    }
    attack_consumption = [ordered]@{
        mode_0 = 'decrement and remove at zero'
        mode_1 = 'durable for normal attacks'
        mode_2 = 'decrement and retain the owned firearm at zero'
        magazines = 'not present in the original runtime'
        reload = 'not present in the original runtime'
    }
}

$gameData = [ordered]@{
    schema_version = 1
    catalog_id = 'original-initial-weapon-inventory-v1'
    content_profile = 'repository-mod-12-level-20260729'
    attack_type_to_item_id = $attackTypeToItemId
    quantity_modes = $quantityModes
    semantics = $sharedSemantics
    summary = [ordered]@{
        level_count = 12
        player_count = $playerTotal
        inventory_entry_count = $itemTotal
    }
    levels = $levels
}
$baseline = [ordered]@{
    schema_version = 1
    baseline_id = 'mod-original-initial-weapon-inventory-v1'
    content_profile = 'repository-mod-12-level-20260729'
    observation_point = 'gameplay entry after the original briefing'
    attack_type_to_item_id = $attackTypeToItemId
    quantity_modes = $quantityModes
    semantics = $sharedSemantics
    summary = $gameData.summary
    provenance = [ordered]@{
        capture_method = 'process-local read-only RuntimeActorV1 inventory snapshots'
        actor_identity_method = 'exact runtime actor to VWF scene correlation'
        identity_catalog_hash = 'SHA-256 of UTF-8 text normalized to LF without BOM'
        levels = $provenanceLevels
    }
    levels = $levels
}

foreach ($outputPath in @($BaselinePath, $GameDataPath)) {
    $parent = [System.IO.Path]::GetDirectoryName($outputPath)
    [System.IO.Directory]::CreateDirectory($parent) | Out-Null
}
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$baselineJson = (
    ($baseline | ConvertTo-Json -Depth 24).
        Replace("`r`n", "`n").
        Replace("`r", "`n") + "`n")
$gameDataJson = (
    ($gameData | ConvertTo-Json -Depth 24).
        Replace("`r`n", "`n").
        Replace("`r", "`n") + "`n")
[System.IO.File]::WriteAllText(
    [System.IO.Path]::GetFullPath($BaselinePath),
    $baselineJson,
    $utf8NoBom)
[System.IO.File]::WriteAllText(
    [System.IO.Path]::GetFullPath($GameDataPath),
    $gameDataJson,
    $utf8NoBom)

Write-Host (
    "Recovered original initial inventories: 12 levels, $playerTotal players, " +
    "$itemTotal ordered entries.")
Write-Host "Baseline: $([System.IO.Path]::GetFullPath($BaselinePath))"
Write-Host "Game data: $([System.IO.Path]::GetFullPath($GameDataPath))"
