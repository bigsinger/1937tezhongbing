[CmdletBinding()]
param(
    [string]$BaselinePath = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$remakeRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if ([string]::IsNullOrWhiteSpace($BaselinePath)) {
    $BaselinePath = Join-Path $remakeRoot `
        'game\data\original_overlay_asset_baseline.json'
}
if (-not (Test-Path -LiteralPath $BaselinePath -PathType Leaf)) {
    throw "Original overlay baseline is missing: $BaselinePath"
}
$baseline = Get-Content -LiteralPath $BaselinePath -Raw -Encoding UTF8 |
    ConvertFrom-Json

if ([int]$baseline.schema_version -ne 1 -or
    [string]$baseline.baseline_id -ne
        'stable-mod-original-overlay-assets-v1' -or
    [string]$baseline.content_profile -ne
        'repository-mod-12-level-20260729') {
    throw 'Original overlay baseline identity is invalid.'
}
$inventory = $baseline.inventory
if (@($inventory.panel_size) -join ',' -ne '276,421' -or
    [int]$inventory.bottom_hud_height -ne 62 -or
    @($inventory.grid_origin) -join ',' -ne '13,40' -or
    [int]$inventory.columns -ne 5 -or
    @($inventory.cell_size) -join ',' -ne '50,74' -or
    [int]$inventory.row_pitch -ne 84 -or
    [int]$inventory.background.gfl_index -ne 1129) {
    throw 'Recovered inventory popup geometry is invalid.'
}
if (@($inventory.item_icon_pairs.PSObject.Properties).Count -ne 24 -or
    @($inventory.mission_item_icon_pairs.PSObject.Properties).Count -ne 2) {
    throw 'Original inventory icon mapping is incomplete.'
}
if ([int]$baseline.help.asset.gfl_index -ne 1047 -or
    @($baseline.help.size) -join ',' -ne '640,480') {
    throw 'Original F1 help identity is invalid.'
}
$pauseMenu = $baseline.pause_menu
if (@($pauseMenu.center_offset) -join ',' -ne '-305,-118' -or
    @($pauseMenu.panel_size) -join ',' -ne '132,318' -or
    [int]$pauseMenu.button_pitch -ne 40 -or
    [int]$pauseMenu.button_background.gfl_index -ne 1095 -or
    @($pauseMenu.label_offset) -join ',' -ne '5,4' -or
    [string]$pauseMenu.background_transform -ne
        'equal_rgb_average_no_dimming' -or
    @($pauseMenu.button_pairs.PSObject.Properties).Count -ne 8) {
    throw 'Recovered original pause-menu geometry is invalid.'
}
if ([int]$baseline.credits.asset.gfl_index -ne 1254 -or
    @($baseline.credits.size) -join ',' -ne '640,480') {
    throw 'Original credits identity is invalid.'
}
$failureMenu = $baseline.failure_menu
if ([int]$failureMenu.title.background.gfl_index -ne 1093 -or
    @($failureMenu.title.center_offset) -join ',' -ne '-99,-59' -or
    @($failureMenu.title.size) -join ',' -ne '172,50' -or
    [int]$failureMenu.restart.background.gfl_index -ne 1095 -or
    [int]$failureMenu.restart.normal.gfl_index -ne 1260 -or
    [int]$failureMenu.restart.hover.gfl_index -ne 1261 -or
    @($failureMenu.restart.label_offset) -join ',' -ne '8,8' -or
    @($failureMenu.restart.center_offset) -join ',' -ne '-158,-3' -or
    @($failureMenu.main.center_offset) -join ',' -ne '-8,-3' -or
    [string]$failureMenu.background_transform -ne
        'equal_rgb_average_no_dimming') {
    throw 'Recovered original failure-menu geometry is invalid.'
}
$expectedLevels = 0..11 | ForEach-Object { 'm{0:D3}' -f $_ }
$minimapLevels = @($baseline.minimaps.level_id)
if (@($baseline.minimaps).Count -ne 12 -or
    (Compare-Object $expectedLevels $minimapLevels)) {
    throw 'Original minimap catalog must contain exactly m000-m011.'
}
$cursor = $baseline.cursor
$cursorSerials = @($cursor.groups.serial_id | ForEach-Object { [int]$_ })
if ([int]$cursor.gfl_index -ne 16 -or
    [string]$cursor.resource_name -ne 'mouse.spr' -or
    [int]$cursor.runtime_type -ne 55 -or
    [int]$cursor.ticks_per_second -ne 60 -or
    ($cursorSerials -join ',') -ne '0,1,2,3,4,6,8,9,10') {
    throw 'Original cursor identity or serial ordering is invalid.'
}
$cursorFrameCount = 0
foreach ($group in @($cursor.groups)) {
    if (@($group.hotspot).Count -ne 2 -or
        [int]$group.frame_hold_ticks -ne 2 -or
        @($group.frames).Count -lt 1) {
        throw "Cursor serial $($group.serial_id) timing/hotspot is invalid."
    }
    foreach ($frame in @($group.frames)) {
        if ([int]$frame.width -le 0 -or
            [int]$frame.height -le 0 -or
            [string]$frame.converted_png_sha256 -notmatch '^[0-9a-f]{64}$') {
            throw "Cursor serial $($group.serial_id) contains an invalid frame."
        }
        ++$cursorFrameCount
    }
}
if ($cursorFrameCount -ne 16) {
    throw "Original cursor must retain all 16 frames; found $cursorFrameCount."
}
$assets = @($baseline.assets)
if ($assets.Count -lt 50) {
    throw 'Original overlay asset catalog is unexpectedly small.'
}
$keys = @{}
foreach ($asset in $assets) {
    $key = "$($asset.kind)/$([int]$asset.gfl_index)"
    if ($keys.ContainsKey($key) -or
        [int]$asset.width -le 0 -or
        [int]$asset.height -le 0 -or
        [string]$asset.converted_png_sha256 -notmatch '^[0-9a-f]{64}$') {
        throw "Invalid or duplicate overlay asset: $key"
    }
    $keys[$key] = $true
}
foreach ($requiredKey in @(
        'psd/1129',
        'psd/1095',
        'psd/1093',
        'psd/1260',
        'psd/1261',
        'psd/1254',
        'psd/1097',
        'psd/1115',
        'iblock/1047')) {
    if (-not $keys.ContainsKey($requiredKey)) {
        throw "Required overlay asset is absent: $requiredKey"
    }
}
if (@($baseline.viewports).Count -ne 2) {
    throw 'Both 1024x768 and 1920x1080 overlay layouts are required.'
}
foreach ($viewport in @($baseline.viewports)) {
    $expectedInventory = @(
        ([int]$viewport.width - 276),
        ([int]$viewport.height - 483),
        276,
        421) -join ','
    $expectedHelp = @(
        (([int]$viewport.width - 640) / 2),
        (([int]$viewport.height - 480) / 2),
        640,
        480) -join ','
    $expectedPause = @(
        (([int]$viewport.width / 2) - 305),
        (([int]$viewport.height / 2) - 118),
        132,
        318) -join ','
    $expectedFailureTitle = @(
        (([int]$viewport.width / 2) - 99),
        (([int]$viewport.height / 2) - 59),
        172,
        50) -join ','
    $expectedFailureRestart = @(
        (([int]$viewport.width / 2) - 158),
        (([int]$viewport.height / 2) - 3),
        132,
        38) -join ','
    $expectedFailureMain = @(
        (([int]$viewport.width / 2) - 8),
        (([int]$viewport.height / 2) - 3),
        132,
        38) -join ','
    $expectedFailureMenu = @(
        (([int]$viewport.width / 2) - 158),
        (([int]$viewport.height / 2) - 59),
        282,
        94) -join ','
    if (@($viewport.inventory_rect) -join ',' -ne $expectedInventory -or
        @($viewport.help_rect) -join ',' -ne $expectedHelp -or
        @($viewport.credits_rect) -join ',' -ne $expectedHelp -or
        @($viewport.pause_menu_rect) -join ',' -ne $expectedPause -or
        @($viewport.failure_title_rect) -join ',' -ne $expectedFailureTitle -or
        @($viewport.failure_restart_rect) -join ',' -ne $expectedFailureRestart -or
        @($viewport.failure_main_rect) -join ',' -ne $expectedFailureMain -or
        @($viewport.failure_menu_rect) -join ',' -ne $expectedFailureMenu) {
        throw "Overlay anchoring is invalid at $($viewport.width)x$($viewport.height)."
    }
}
if ($baseline.evidence.original_bytes_committed -ne $false) {
    throw 'The compact baseline must not claim to contain original image bytes.'
}
$serialized = Get-Content -LiteralPath $BaselinePath -Raw -Encoding UTF8
if ($serialized -match 'LocalAssets|[A-Z]:\\|/converted/') {
    throw 'The compact overlay baseline must not contain local asset paths.'
}

Write-Host (
    "Original overlay baseline passed: {0} assets, 12 maps, 8 pause buttons, exact failure menu, 16 cursor frames, two viewports." -f
    $assets.Count)
