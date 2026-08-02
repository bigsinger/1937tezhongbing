[CmdletBinding()]
param(
    [string]$ConvertedAssets = '',
    [string]$OutputPath = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$remakeRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if ([string]::IsNullOrWhiteSpace($ConvertedAssets)) {
    $ConvertedAssets = Join-Path $remakeRoot 'LocalAssets\converted'
}
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $remakeRoot `
        'game\data\original_overlay_asset_baseline.json'
}
$ConvertedAssets = [IO.Path]::GetFullPath($ConvertedAssets)
$OutputPath = [IO.Path]::GetFullPath($OutputPath)
$manifestPath = Join-Path $ConvertedAssets 'asset-manifest.json'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "Converted asset manifest is missing: $manifestPath"
}
$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 |
    ConvertFrom-Json
$cursorManifestPath = Join-Path $ConvertedAssets `
    'sprite-frames\0016\sprite.json'
if (-not (Test-Path -LiteralPath $cursorManifestPath -PathType Leaf)) {
    throw "Converted mouse.spr manifest is missing: $cursorManifestPath"
}
$cursorManifest = Get-Content -LiteralPath $cursorManifestPath `
    -Raw -Encoding UTF8 | ConvertFrom-Json

$inventoryPairs = [ordered]@{
    '33' = @(1166, 1167); '36' = @(1212, 1213)
    '37' = @(1120, 1121); '38' = @(1164, 1165)
    '39' = @(1117, 1118); '40' = @(1123, 1124)
    '41' = @(1149, 1150); '42' = @(1133, 1134)
    '43' = @(1141, 1142); '44' = @(1210, 1211)
    '45' = @(1248, 1249); '46' = @(1135, 1136)
    '47' = @(1240, 1241); '48' = @(1162, 1163)
    '49' = @(1175, 1176); '50' = @(1230, 1231)
    '51' = @(1258, 1259); '52' = @(1145, 1146)
    '53' = @(1195, 1196); '54' = @(1178, 1179)
    '82' = @(1151, 1152); '83' = @(1234, 1235)
    '92' = @(1201, 1202); '101' = @(1221, 1222)
}
$missionItemPairs = [ordered]@{
    uniform = @(1178, 1179)
    explosives = @(1248, 1249)
}
$pauseMenuPairs = [ordered]@{
    resume = @(1103, 1104)
    restart = @(1114, 1115)
    missions = @(1101, 1102)
    save = @(1097, 1098)
    load = @(1109, 1110)
    settings = @(1107, 1108)
    credits = @(1112, 1113)
    quit = @(1105, 1106)
}
$minimapIds = [ordered]@{
    m000 = 1036; m001 = 1026; m002 = 1027; m003 = 1028
    m004 = 1029; m005 = 1030; m006 = 1031; m007 = 1032
    m008 = 1033; m009 = 1034; m010 = 1035; m011 = 1025
}

$manifestLookup = @{}
foreach ($entry in @($manifest.psd_composites)) {
    $manifestLookup["psd/$([int]$entry.gfl_index)"] = $entry
}
foreach ($entry in @($manifest.iblock)) {
    $manifestLookup["iblock/$([int]$entry.gfl_index)"] = $entry
}

$assetKeys = [Collections.Generic.HashSet[string]]::new(
    [StringComparer]::Ordinal)
[void]$assetKeys.Add('psd/1129')
[void]$assetKeys.Add('psd/1095')
[void]$assetKeys.Add('psd/1254')
[void]$assetKeys.Add('iblock/1047')
foreach ($id in $minimapIds.Values) {
    [void]$assetKeys.Add("iblock/$id")
}
foreach ($pair in $inventoryPairs.Values + $missionItemPairs.Values) {
    foreach ($id in $pair) {
        [void]$assetKeys.Add("psd/$id")
    }
}
foreach ($pair in $pauseMenuPairs.Values) {
    foreach ($id in $pair) {
        [void]$assetKeys.Add("psd/$id")
    }
}

Add-Type -AssemblyName System.Drawing
$assets = [Collections.Generic.List[object]]::new()
foreach ($assetKey in @($assetKeys | Sort-Object)) {
    if (-not $manifestLookup.ContainsKey($assetKey)) {
        throw "Overlay resource is absent from the converter manifest: $assetKey"
    }
    $entry = $manifestLookup[$assetKey]
    $sourcePath = Join-Path $ConvertedAssets ([string]$entry.relative_path)
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
        throw "Converted overlay PNG is missing: $sourcePath"
    }
    $image = [Drawing.Image]::FromFile($sourcePath)
    try {
        $parts = $assetKey.Split('/')
        $assets.Add([ordered]@{
            kind = $parts[0]
            gfl_index = [int]$parts[1]
            resource_name = [string]$entry.resource_name
            width = [int]$image.Width
            height = [int]$image.Height
            converted_png_sha256 = (
                Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256
            ).Hash.ToLowerInvariant()
        })
    }
    finally {
        $image.Dispose()
    }
}

function Get-AssetSize {
    param([string]$Kind, [int]$GflIndex)
    $asset = $assets | Where-Object {
        $_.kind -eq $Kind -and $_.gfl_index -eq $GflIndex
    } | Select-Object -First 1
    if ($null -eq $asset) {
        throw "Baseline asset lookup failed: $Kind/$GflIndex"
    }
    return @([int]$asset.width, [int]$asset.height)
}

$minimaps = [Collections.Generic.List[object]]::new()
foreach ($levelId in $minimapIds.Keys) {
    $gflIndex = [int]$minimapIds[$levelId]
    $size = Get-AssetSize -Kind iblock -GflIndex $gflIndex
    $minimaps.Add([ordered]@{
        level_id = $levelId
        gfl_index = $gflIndex
        width = $size[0]
        height = $size[1]
        anchor = 'bottom_right_above_62px_hud'
    })
}

$cursorGroups = [Collections.Generic.List[object]]::new()
foreach ($group in @($cursorManifest.groups | Sort-Object {
            [int]$_.serial_id
        })) {
    $frames = [Collections.Generic.List[object]]::new()
    foreach ($frame in @($group.frames | Sort-Object {
                [int]$_.frame_index
            })) {
        $framePath = Join-Path `
            (Split-Path -Parent $cursorManifestPath) `
            ([string]$frame.relative_path)
        if (-not (Test-Path -LiteralPath $framePath -PathType Leaf)) {
            throw "Converted cursor frame is missing: $framePath"
        }
        $frames.Add([ordered]@{
            frame_index = [int]$frame.frame_index
            width = [int]$frame.width
            height = [int]$frame.height
            converted_png_sha256 = (
                Get-FileHash -LiteralPath $framePath -Algorithm SHA256
            ).Hash.ToLowerInvariant()
        })
    }
    $cursorGroups.Add([ordered]@{
        serial_id = [int]$group.serial_id
        hotspot = @(
            [int]$group.primary_triplet[0],
            [int]$group.primary_triplet[2])
        frame_hold_ticks = [int]$group.frame_hold_ticks
        frames = $frames
    })
}

$viewports = foreach ($viewport in @(
        @{ width = 1024; height = 768 },
        @{ width = 1920; height = 1080 }
    )) {
    [ordered]@{
        width = $viewport.width
        height = $viewport.height
        inventory_rect = @(
            ($viewport.width - 276),
            ($viewport.height - 62 - 421),
            276,
            421)
        help_rect = @(
            (($viewport.width - 640) / 2),
            (($viewport.height - 480) / 2),
            640,
            480)
        pause_menu_rect = @(
            (($viewport.width / 2) - 305),
            (($viewport.height / 2) - 118),
            132,
            318)
        credits_rect = @(
            (($viewport.width - 640) / 2),
            (($viewport.height - 480) / 2),
            640,
            480)
    }
}

$baseline = [ordered]@{
    schema_version = 1
    baseline_id = 'stable-mod-original-overlay-assets-v1'
    content_profile = 'repository-mod-12-level-20260729'
    source_status = 'recovered_original_resources_and_runtime_hit_geometry'
    inventory = [ordered]@{
        background = @{ kind = 'psd'; gfl_index = 1129 }
        panel_size = @(276, 421)
        bottom_hud_height = 62
        grid_origin = @(13, 40)
        columns = 5
        cell_size = @(50, 74)
        row_pitch = 84
        item_icon_pairs = $inventoryPairs
        mission_item_icon_pairs = $missionItemPairs
    }
    help = [ordered]@{
        asset = @{ kind = 'iblock'; gfl_index = 1047 }
        size = @(640, 480)
        anchor = 'viewport_center'
    }
    pause_menu = [ordered]@{
        anchor = 'viewport_center_plus_recovered_1024_offset'
        center_offset = @(-305, -118)
        panel_size = @(132, 318)
        button_pitch = 40
        button_background = @{ kind = 'psd'; gfl_index = 1095 }
        label_offset = @(5, 4)
        background_transform = 'equal_rgb_average_no_dimming'
        button_pairs = $pauseMenuPairs
    }
    credits = [ordered]@{
        asset = @{ kind = 'psd'; gfl_index = 1254 }
        size = @(640, 480)
        anchor = 'viewport_center'
    }
    minimaps = $minimaps
    cursor = [ordered]@{
        gfl_index = 16
        resource_name = 'mouse.spr'
        runtime_type = 55
        ticks_per_second = 60
        context_serials = [ordered]@{
            normal = 0
            move = 1
            force_target = 2
            interaction_hand = 3
            burial = 4
            door_hand = 6
            sight = 8
            outside_world = 9
            blocked = 10
        }
        groups = $cursorGroups
    }
    viewports = @($viewports)
    assets = $assets
    evidence = [ordered]@{
        original_click_formula = `
            'screen-276+13+50*column, screen-62-421+40+84*row'
        original_pause_geometry = `
            '1024x768 primary surface: PSD1095 x=207, y=266+40*row; label +5,+4'
        runtime_loading = `
            'Remake loads these exact converted PNG files without filtering'
        cursor_runtime = `
            'mouse.spr primary.x/z are the hotspot and frame_hold_ticks drive a 60 Hz loop'
        original_bytes_committed = $false
    }
}

$parent = Split-Path -Parent $OutputPath
[IO.Directory]::CreateDirectory($parent) | Out-Null
$baseline | ConvertTo-Json -Depth 12 |
    Set-Content -LiteralPath $OutputPath -Encoding UTF8
Write-Host (
    "Original overlay baseline: {0} assets, 12 minimaps, output {1}" -f
    $assets.Count,
    $OutputPath)
