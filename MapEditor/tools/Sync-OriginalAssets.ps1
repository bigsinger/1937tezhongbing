param(
    [string]$ConvertedAssets = '',
    [string]$Destination = ''
)

$ErrorActionPreference = 'Stop'
$editorRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $editorRoot '..'))
if ([string]::IsNullOrWhiteSpace($ConvertedAssets)) {
    $ConvertedAssets = Join-Path `
        $repositoryRoot 'Remake\LocalAssets\converted'
}
if ([string]::IsNullOrWhiteSpace($Destination)) {
    $Destination = Join-Path $editorRoot 'Assets\Original'
}
$ConvertedAssets = [IO.Path]::GetFullPath($ConvertedAssets)
$Destination = [IO.Path]::GetFullPath($Destination)

$allowedDestination = (
    [IO.Path]::GetFullPath((Join-Path $editorRoot 'Assets')).
        TrimEnd('\') + '\')
if (-not (($Destination.TrimEnd('\') + '\').StartsWith(
    $allowedDestination,
    [StringComparison]::OrdinalIgnoreCase))) {
    throw "Destination must stay under MapEditor\Assets: $Destination"
}

$sourceManifest = Join-Path $ConvertedAssets 'asset-manifest.json'
$levelIndex = Join-Path $ConvertedAssets 'levels\index.json'
if (-not (Test-Path -LiteralPath $sourceManifest -PathType Leaf) -or
    -not (Test-Path -LiteralPath $levelIndex -PathType Leaf)) {
    throw "Converted original assets are incomplete: $ConvertedAssets"
}

Add-Type -AssemblyName System.Drawing

function New-Thumbnail {
    param(
        [string]$Source,
        [string]$Target,
        [int]$MaximumWidth,
        [int]$MaximumHeight
    )
    $targetDirectory = Split-Path -Parent $Target
    New-Item -ItemType Directory -Path $targetDirectory -Force |
        Out-Null
    $image = [Drawing.Image]::FromFile($Source)
    try {
        $scale = [Math]::Min(
            1.0,
            [Math]::Min(
                $MaximumWidth / [double]$image.Width,
                $MaximumHeight / [double]$image.Height))
        $width = [Math]::Max(1, [int][Math]::Round($image.Width * $scale))
        $height = [Math]::Max(1, [int][Math]::Round($image.Height * $scale))
        $bitmap = New-Object Drawing.Bitmap $width, $height,
            ([Drawing.Imaging.PixelFormat]::Format32bppArgb)
        try {
            $graphics = [Drawing.Graphics]::FromImage($bitmap)
            try {
                $graphics.Clear([Drawing.Color]::Transparent)
                $graphics.CompositingQuality =
                    [Drawing.Drawing2D.CompositingQuality]::HighQuality
                $graphics.InterpolationMode =
                    [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                $graphics.PixelOffsetMode =
                    [Drawing.Drawing2D.PixelOffsetMode]::HighQuality
                $graphics.DrawImage(
                    $image, 0, 0, $width, $height)
            }
            finally {
                $graphics.Dispose()
            }
            $bitmap.Save(
                $Target, [Drawing.Imaging.ImageFormat]::Png)
        }
        finally {
            $bitmap.Dispose()
        }
    }
    finally {
        $image.Dispose()
    }
}

function Get-AssetClassification {
    param([string]$Name)
    if ($Name -match '树|草|花|灌木|竹') {
        return @('树木花草', 'vegetation')
    }
    if ($Name -match '墙|栅栏|铁丝网|围栏') {
        return @('院墙围栏', 'wall')
    }
    if ($Name -match '房|屋|楼|仓库|岗楼|车站|塔|棚') {
        return @('房屋建筑', 'building')
    }
    if ($Name -match '门|窗') {
        return @('门窗', 'door')
    }
    if ($Name -match '桥|道路|公路|铁路|地面') {
        return @('道路桥梁', 'terrain')
    }
    if ($Name -match '阿莲|阿全|古明|强子|王二|龟田|士兵|军官|二等兵|推车人|队长|特务|翻译官') {
        return @('角色', 'character')
    }
    if ($Name -match '箱|枪|刀|药|弹|雷|物品|服装') {
        return @('武器物品', 'item')
    }
    if ($Name -match '车|船|马') {
        return @('车辆', 'vehicle')
    }
    if ($Name -match '石|木|桌|椅|桶|路障|废墟') {
        return @('障碍与摆设', 'obstacle')
    }
    return @('其他', 'decoration')
}

New-Item -ItemType Directory -Path $Destination -Force | Out-Null
$manifest = Get-Content -LiteralPath $sourceManifest -Raw -Encoding UTF8 |
    ConvertFrom-Json
$catalog = New-Object Collections.Generic.List[object]

foreach ($sprite in $manifest.sprite_previews) {
    $fileName = [IO.Path]::GetFileName([string]$sprite.relative_path)
    $source = Join-Path $ConvertedAssets (
        ([string]$sprite.relative_path).Replace('/', '\'))
    $relative = "sprites/$fileName"
    $thumbnailRelative = "thumbnails/sprites/$fileName"
    $target = Join-Path $Destination $relative.Replace('/', '\')
    $thumbnail = Join-Path `
        $Destination $thumbnailRelative.Replace('/', '\')
    New-Item -ItemType Directory -Path (Split-Path -Parent $target) `
        -Force | Out-Null
    Copy-Item -LiteralPath $source -Destination $target -Force
    New-Thumbnail $source $thumbnail 128 96
    $classification = Get-AssetClassification `
        ([string]$sprite.resource_name)
    $catalog.Add([pscustomobject]@{
        id = [int]$sprite.gfl_index
        name = [IO.Path]::GetFileNameWithoutExtension(
            [string]$sprite.resource_name)
        category = $classification[0]
        kind = $classification[1]
        relative_path = $relative
        thumbnail_relative_path = $thumbnailRelative
        source_name = [string]$sprite.resource_name
    })
}

foreach ($tile in $manifest.tile_atlases) {
    $fileName = [IO.Path]::GetFileName([string]$tile.relative_path)
    $source = Join-Path $ConvertedAssets (
        ([string]$tile.relative_path).Replace('/', '\'))
    $relative = "tiles/$fileName"
    $target = Join-Path $Destination $relative.Replace('/', '\')
    New-Item -ItemType Directory -Path (Split-Path -Parent $target) `
        -Force | Out-Null
    Copy-Item -LiteralPath $source -Destination $target -Force
    $catalog.Add([pscustomobject]@{
        id = 100000 + [int]$tile.gfl_index
        name = [IO.Path]::GetFileNameWithoutExtension(
            [string]$tile.resource_name)
        category = '地表图块'
        kind = 'terrain_tile'
        relative_path = $relative
        thumbnail_relative_path = $relative
        source_name = [string]$tile.resource_name
    })
}

$levels = Get-Content -LiteralPath $levelIndex -Raw -Encoding UTF8 |
    ConvertFrom-Json
foreach ($level in $levels.levels) {
    $levelId = [string]$level.level_id
    $sourceDirectory = Join-Path `
        $ConvertedAssets "levels\$levelId"
    $targetDirectory = Join-Path $Destination "maps\$levelId"
    New-Item -ItemType Directory -Path $targetDirectory -Force |
        Out-Null
    Copy-Item -LiteralPath (Join-Path $sourceDirectory 'terrain.png') `
        -Destination (Join-Path $targetDirectory 'terrain.png') -Force
    Copy-Item -LiteralPath (Join-Path $sourceDirectory 'level.json') `
        -Destination (Join-Path $targetDirectory 'level.json') -Force
    New-Thumbnail `
        (Join-Path $sourceDirectory 'terrain.png') `
        (Join-Path $targetDirectory 'thumbnail.png') 360 220
    $number = [int]$levelId.Substring(1) + 1
    $catalog.Add([pscustomobject]@{
        id = 200000 + $number
        name = ('第 {0:D2} 关整图' -f $number)
        category = '关卡地图'
        kind = 'map_background'
        relative_path = "maps/$levelId/terrain.png"
        thumbnail_relative_path = "maps/$levelId/thumbnail.png"
        source_name = "$levelId.vwf"
    })
}

$catalogDocument = [ordered]@{
    schema_version = 1
    source_archive = 'Mod/1937Resources.GFL'
    generated_at = [DateTime]::UtcNow.ToString('O')
    assets = $catalog
}
$catalogJson = $catalogDocument |
    ConvertTo-Json -Depth 8
[IO.File]::WriteAllText(
    (Join-Path $Destination 'catalog.json'),
    $catalogJson,
    (New-Object Text.UTF8Encoding($false)))

[pscustomobject]@{
    Destination = $Destination
    Assets = $catalog.Count
    Sprites = $manifest.sprite_previews.Count
    Tiles = $manifest.tile_atlases.Count
    Maps = $levels.levels.Count
}
