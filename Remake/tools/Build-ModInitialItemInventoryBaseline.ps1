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
        'validation\baselines\mod\initial-item-inventory-v1.json'
}
if ([string]::IsNullOrWhiteSpace($GameDataPath)) {
    $GameDataPath = Join-Path `
        $remakeRoot `
        'game\data\original_initial_item_inventory.json'
}

$expectedPlayerCounts = @(1, 3, 1, 4, 1, 3, 1, 3, 2, 2, 4, 2)
$allowedQuantityModes = [ordered]@{
    '33' = @(0, 1)
    '46' = @(0)
    '47' = @(0)
    '48' = @(0)
    '49' = @(0, 1)
    '50' = @(0)
    '51' = @(0)
    '52' = @(0, 1)
    '53' = @(0)
    '54' = @(0)
    '82' = @(0)
    '83' = @(0, 1)
    '92' = @(0)
    '101' = @(0)
}

function Convert-Utf8Base64 {
    param([Parameter(Mandatory = $true)][string]$Value)

    return [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Value))
}

$itemCatalog = [ordered]@{
    '33' = [ordered]@{
        display_name = Convert-Utf8Base64 '6bih'
        ui_resource = Convert-Utf8Base64 '6bihLnBzZA=='
        behavior = 'world_interaction'
        source_status = 'recovered_original_code_and_resources'
    }
    '46' = [ordered]@{
        display_name = Convert-Utf8Base64 '5by56I2v566x'
        ui_resource = Convert-Utf8Base64 '5by56I2v566xLnBzZA=='
        behavior = 'use'
        effect = [ordered]@{
            kind = 'refill_original_weapons'
            refill_by_weapon_item_id = [ordered]@{
                '36' = 10
                '37' = 5
                '38' = 5
                '41' = 5
                '43' = 3
                '44' = 3
                '45' = 3
            }
        }
        source_status = 'recovered_sub_457E60_and_sub_457F00'
    }
    '47' = [ordered]@{
        display_name = Convert-Utf8Base64 '5Yy76I2v566x'
        ui_resource = Convert-Utf8Base64 '5Yy76I2v566xLnBzZA=='
        behavior = 'use'
        effect = [ordered]@{
            kind = 'set_hit_points'
            value = 8
        }
        source_status = 'recovered_sub_457EF0_and_sub_457F00'
    }
    '48' = [ordered]@{
        display_name = Convert-Utf8Base64 '6IKJ572Q5aS0'
        ui_resource = Convert-Utf8Base64 '572Q5aS0LnBzZA=='
        behavior = 'world_interaction'
        source_status = 'recovered_original_code_and_resources'
    }
    '49' = [ordered]@{
        display_name = Convert-Utf8Base64 '6ZmN5aS05pyo5YG2'
        ui_resource = Convert-Utf8Base64 '6ZmN5aS05pyo5YG2LnBzZA=='
        behavior = 'world_interaction'
        source_status = 'recovered_original_code_and_resources'
    }
    '50' = [ordered]@{
        display_name = Convert-Utf8Base64 '6KW/55Oc'
        ui_resource = Convert-Utf8Base64 '6KW/55OcLnBzZA=='
        behavior = 'use'
        effect = [ordered]@{
            kind = 'heal'
            value = 4
            cap = 8
        }
        source_status = 'recovered_sub_457F00'
    }
    '51' = [ordered]@{
        display_name = Convert-Utf8Base64 '5Lit6I2v'
        ui_resource = Convert-Utf8Base64 '5Lit6I2vLnBzZA=='
        behavior = 'use'
        effect = [ordered]@{
            kind = 'heal'
            value = 6
            cap = 8
        }
        source_status = 'recovered_sub_457F00'
    }
    '52' = [ordered]@{
        display_name = Convert-Utf8Base64 '5q+S6YWS'
        ui_resource = Convert-Utf8Base64 '5q+S6YWSLnBzZA=='
        behavior = 'world_interaction'
        source_status = 'recovered_original_code_and_resources'
    }
    '53' = [ordered]@{
        display_name = Convert-Utf8Base64 '5rG95rK55qG2'
        ui_resource = Convert-Utf8Base64 '5rG95rK55qG2LnBzZA=='
        behavior = 'world_placeable'
        source_status = 'recovered_original_code_and_resources'
    }
    '54' = [ordered]@{
        display_name = Convert-Utf8Base64 '5pel5Yab5Yab5pyN'
        ui_resource = Convert-Utf8Base64 '5Yab5pyNLnBzZA=='
        behavior = 'use'
        effect = [ordered]@{
            kind = 'set_disguise'
            appearance_state = 100
        }
        source_status = 'recovered_sub_457F00'
    }
    '82' = [ordered]@{
        display_name = Convert-Utf8Base64 '54uX6aqo5aS0'
        ui_resource = Convert-Utf8Base64 '54uX6aqo5aS0LnBzZA=='
        behavior = 'world_interaction'
        source_status = 'recovered_original_code_and_resources'
    }
    '83' = [ordered]@{
        display_name = Convert-Utf8Base64 '6aaZ54Of'
        ui_resource = Convert-Utf8Base64 '6aaZ54OfLnBzZA=='
        behavior = 'world_interaction'
        source_status = 'recovered_original_code_and_resources'
    }
    '92' = [ordered]@{
        display_name = Convert-Utf8Base64 '6Z2S6KGr'
        ui_resource = Convert-Utf8Base64 '6Z2S6KGrLnBzZA=='
        behavior = 'use'
        effect = [ordered]@{
            kind = 'set_disguise'
            appearance_state = 100
        }
        source_status = 'recovered_sub_457F00'
    }
    '101' = [ordered]@{
        display_name = Convert-Utf8Base64 '5paH5Lu26KKL'
        ui_resource = Convert-Utf8Base64 '5paH5Lu26KKLLnBzZA=='
        behavior = 'mission_item'
        source_status = 'recovered_original_code_and_resources'
    }
}

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

function Get-RealInventoryRows {
    param([Parameter(Mandatory = $true)][object[]]$Rows)

    return @($Rows |
        Where-Object { [int]$_.inventory_index -ge 0 } |
        Sort-Object { [int]$_.inventory_index })
}

function Convert-InventoryRows {
    param([Parameter(Mandatory = $true)][object[]]$Rows)

    $items = @()
    $expectedIndex = 0
    $seenItemIds = @{}
    foreach ($row in (Get-RealInventoryRows -Rows $Rows)) {
        $itemId = [int]$row.item_id
        $quantity = [int]$row.quantity
        $quantityMode = [int]$row.quantity_mode
        $itemKey = $itemId.ToString()
        if (-not $allowedQuantityModes.Contains($itemKey)) {
            throw "Unsupported original backpack item id $itemId."
        }
        if ($quantityMode -notin @($allowedQuantityModes[$itemKey])) {
            throw "Item $itemId uses unsupported quantity mode $quantityMode."
        }
        if ([int]$row.inventory_index -ne $expectedIndex) {
            throw "Backpack inventory indices are not contiguous."
        }
        if ($quantity -lt 0) {
            throw "Item $itemId has negative quantity $quantity."
        }
        if ($seenItemIds.ContainsKey($itemId)) {
            throw "Backpack contains duplicate item id $itemId."
        }
        $seenItemIds[$itemId] = $true
        $items += [ordered]@{
            inventory_index = $expectedIndex
            item_id = $itemId
            quantity = $quantity
            quantity_mode = $quantityMode
        }
        ++$expectedIndex
    }
    return $items
}

function Inventory-Signature {
    param([Parameter(Mandatory = $true)][object[]]$Rows)

    return (((Get-RealInventoryRows -Rows $Rows) |
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
$actorTotal = 0
$entryTotal = 0
$emptyActorTotal = 0
$playerTotal = 0
$playerEntryTotal = 0
$emptyPlayerTotal = 0
$excludedResolvedHighTotal = 0
$excludedUnresolvedTotal = 0

for ($levelIndex = 0; $levelIndex -lt 12; ++$levelIndex) {
    $levelId = 'm{0:D3}' -f $levelIndex
    $captureDirectory = Join-Path $resolvedCaptureRoot $levelId
    $entryPath = Join-Path $captureDirectory 'actor-items-entry.csv'
    $steadyPath = Join-Path $captureDirectory 'actor-items-steady.csv'
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
    $entryRows = @(Import-Csv -LiteralPath $entryPath)
    $steadyRows = @(Import-Csv -LiteralPath $steadyPath)
    $entryByRuntimeIndex = @{}
    $steadyByRuntimeIndex = @{}
    foreach ($row in $entryRows) {
        $runtimeIndex = [int]$row.runtime_index
        if (-not $entryByRuntimeIndex.ContainsKey($runtimeIndex)) {
            $entryByRuntimeIndex[$runtimeIndex] = @()
        }
        $entryByRuntimeIndex[$runtimeIndex] += $row
    }
    foreach ($row in $steadyRows) {
        $runtimeIndex = [int]$row.runtime_index
        if (-not $steadyByRuntimeIndex.ContainsKey($runtimeIndex)) {
            $steadyByRuntimeIndex[$runtimeIndex] = @()
        }
        $steadyByRuntimeIndex[$runtimeIndex] += $row
    }

    $actors = @()
    $levelPlayerCount = 0
    foreach ($identity in @($identityCatalog.identities |
        Sort-Object { [int]$_.runtime_index })) {
        if ([string]$identity.status -ne 'resolved') {
            ++$excludedUnresolvedTotal
            continue
        }
        if ([string]$identity.confidence -ne 'exact') {
            ++$excludedResolvedHighTotal
            continue
        }
        $runtimeIndex = [int]$identity.runtime_index
        if (-not $entryByRuntimeIndex.ContainsKey($runtimeIndex) -or
            -not $steadyByRuntimeIndex.ContainsKey($runtimeIndex)) {
            throw "$levelId exact actor $runtimeIndex has no backpack capture."
        }
        $actorEntryRows = @($entryByRuntimeIndex[$runtimeIndex])
        $actorSteadyRows = @($steadyByRuntimeIndex[$runtimeIndex])
        if ((Inventory-Signature -Rows $actorEntryRows) -cne
            (Inventory-Signature -Rows $actorSteadyRows)) {
            throw (
                "$levelId runtime actor $runtimeIndex changed backpack before " +
                'the steady checkpoint.')
        }
        $items = @(Convert-InventoryRows -Rows $actorEntryRows)
        $captureFaction = [int]$actorEntryRows[0].faction
        $isPlayer = $captureFaction -eq 3
        $actors += [ordered]@{
            runtime_index = $runtimeIndex
            scene_index = [int]$identity.scene_index
            database_entry_id = [int]$identity.database_entry_id
            display_name = [string]$identity.display_name
            runtime_type = [int]$identity.runtime_type
            captured_faction_id = $captureFaction
            vwf_faction_id = [int]$identity.vwf_faction_id
            is_player_at_capture = $isPlayer
            items = $items
        }
        ++$actorTotal
        $entryTotal += $items.Count
        if ($items.Count -eq 0) {
            ++$emptyActorTotal
        }
        if ($isPlayer) {
            ++$levelPlayerCount
            ++$playerTotal
            $playerEntryTotal += $items.Count
            if ($items.Count -eq 0) {
                ++$emptyPlayerTotal
            }
        }
    }
    if ($levelPlayerCount -ne $expectedPlayerCounts[$levelIndex]) {
        throw (
            "$levelId has $levelPlayerCount exact captured players; expected " +
            "$($expectedPlayerCounts[$levelIndex]).")
    }
    $levels[$levelId] = [ordered]@{
        selector_level = $levelIndex + 1
        engine_mission = $levelIndex + 1
        actors = $actors
    }
    $provenanceLevels[$levelId] = [ordered]@{
        entry_snapshot_sha256 = Get-Sha256 -LiteralPath $entryPath
        steady_snapshot_sha256 = Get-Sha256 -LiteralPath $steadyPath
        identity_catalog_sha256 =
            Get-CanonicalTextSha256 -LiteralPath $identityPath
        exact_actor_count = $actors.Count
        player_count = $levelPlayerCount
    }
}

$expectedTotals = @{
    actors = 650
    entries = 538
    empty_actors = 307
    players = 27
    player_entries = 74
    empty_players = 1
    excluded_resolved_high = 112
    excluded_unresolved = 10
}
$actualTotals = @{
    actors = $actorTotal
    entries = $entryTotal
    empty_actors = $emptyActorTotal
    players = $playerTotal
    player_entries = $playerEntryTotal
    empty_players = $emptyPlayerTotal
    excluded_resolved_high = $excludedResolvedHighTotal
    excluded_unresolved = $excludedUnresolvedTotal
}
foreach ($key in $expectedTotals.Keys) {
    if ([int]$actualTotals[$key] -ne [int]$expectedTotals[$key]) {
        throw (
            "Recovered backpack total '$key' is $($actualTotals[$key]); " +
            "expected $($expectedTotals[$key]).")
    }
}

$sharedSemantics = [ordered]@{
    runtime_actor_item_inventory_offset = '0x228'
    runtime_actor_weapon_inventory_offset = '0x22C'
    container_layout = [ordered]@{
        item_ids_address = '0x00'
        quantities_address = '0x04'
        quantity_modes_address = '0x08'
        item_count = '0x0C'
        size = '0x10'
    }
    consumption = [ordered]@{
        mode_0 = 'decrement and remove at zero'
        mode_1 = 'durable unless the caller explicitly forces consumption'
        mode_2 = 'decrement and retain zero unless the caller explicitly forces removal'
    }
    death_drop = 'sub_456AB0 drops both +0x228 items and +0x22C weapons, then clears both containers'
}
$summary = [ordered]@{
    level_count = 12
    exact_actor_count = $actorTotal
    inventory_entry_count = $entryTotal
    empty_actor_count = $emptyActorTotal
    player_count = $playerTotal
    player_inventory_entry_count = $playerEntryTotal
    empty_player_count = $emptyPlayerTotal
    excluded_resolved_high_confidence_actor_count = $excludedResolvedHighTotal
    excluded_unresolved_actor_count = $excludedUnresolvedTotal
}
$gameData = [ordered]@{
    schema_version = 1
    catalog_id = 'original-initial-item-inventory-v1'
    content_profile = 'repository-mod-12-level-20260729'
    item_catalog = $itemCatalog
    allowed_quantity_modes = $allowedQuantityModes
    semantics = $sharedSemantics
    summary = $summary
    levels = $levels
}
$baseline = [ordered]@{
    schema_version = 1
    baseline_id = 'mod-original-initial-item-inventory-v1'
    content_profile = 'repository-mod-12-level-20260729'
    observation_point = 'gameplay entry after the original briefing'
    item_catalog = $itemCatalog
    allowed_quantity_modes = $allowedQuantityModes
    semantics = $sharedSemantics
    summary = $summary
    provenance = [ordered]@{
        capture_method = 'process-local read-only RuntimeActorV1 +0x228 snapshots'
        actor_identity_method = 'exact runtime actor to VWF scene correlation'
        exclusion_policy = 'resolved/high and unresolved identities are retained as evidence but never guessed into product scene identities'
        identity_catalog_hash = 'SHA-256 of UTF-8 text normalized to LF without BOM'
        reverse_engineering = [ordered]@{
            container_add = 'M1937.exe sub_4529F0'
            container_consume = 'M1937.exe sub_452BB0'
            direct_item_use = 'M1937.exe sub_457E60, sub_457EF0, sub_457F00'
            death_drop = 'M1937.exe sub_456AB0'
        }
        levels = $provenanceLevels
    }
    levels = $levels
}

foreach ($outputPath in @($BaselinePath, $GameDataPath)) {
    $parent = [IO.Path]::GetDirectoryName($outputPath)
    [IO.Directory]::CreateDirectory($parent) | Out-Null
}
$utf8NoBom = [Text.UTF8Encoding]::new($false)
$baselineJson = (
    ($baseline | ConvertTo-Json -Depth 24).
        Replace("`r`n", "`n").
        Replace("`r", "`n") + "`n")
$gameDataJson = (
    ($gameData | ConvertTo-Json -Depth 24).
        Replace("`r`n", "`n").
        Replace("`r", "`n") + "`n")
[IO.File]::WriteAllText(
    [IO.Path]::GetFullPath($BaselinePath),
    $baselineJson,
    $utf8NoBom)
[IO.File]::WriteAllText(
    [IO.Path]::GetFullPath($GameDataPath),
    $gameDataJson,
    $utf8NoBom)

Write-Host (
    "Recovered original backpacks: 12 levels, $actorTotal exact actors, " +
    "$entryTotal ordered entries; players=$playerTotal/$playerEntryTotal.")
Write-Host "Baseline: $([IO.Path]::GetFullPath($BaselinePath))"
Write-Host "Game data: $([IO.Path]::GetFullPath($GameDataPath))"
