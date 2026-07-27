param(
    [Parameter(Mandatory = $true)]
    [string]$SourceTerrain,

    [Parameter(Mandatory = $true)]
    [string]$Blueprint,

    [Parameter(Mandatory = $true)]
    [string]$OutputDirectory
)

$ErrorActionPreference = 'Stop'
$sourcePath = [IO.Path]::GetFullPath($SourceTerrain)
$blueprintPath = [IO.Path]::GetFullPath($Blueprint)
$outputPath = [IO.Path]::GetFullPath($OutputDirectory)
$definition = Get-Content -LiteralPath $blueprintPath -Raw -Encoding utf8 |
    ConvertFrom-Json

Add-Type -AssemblyName System.Drawing
$source = [Drawing.Bitmap]::new($sourcePath)
try {
    $blockWidth = [int]$definition.block_width * 32
    $blockHeight = [int]$definition.block_height * 16
    if (
        $blockWidth -le 0 -or $blockHeight -le 0 -or
        $source.Width % $blockWidth -ne 0 -or
        $source.Height % $blockHeight -ne 0
    ) {
        throw 'Blueprint block dimensions do not match the terrain PNG.'
    }
    $columns = [int]($source.Width / $blockWidth)
    $rows = [int]($source.Height / $blockHeight)
    $permutation = @($definition.destination_to_source_blocks)
    if ($permutation.Count -ne $columns * $rows) {
        throw 'Blueprint permutation does not cover every terrain block.'
    }

    [IO.Directory]::CreateDirectory($outputPath) | Out-Null
    $terrainPath = Join-Path $outputPath 'terrain.png'
    $destination = [Drawing.Bitmap]::new(
        $source.Width,
        $source.Height,
        [Drawing.Imaging.PixelFormat]::Format32bppArgb)
    try {
        $graphics = [Drawing.Graphics]::FromImage($destination)
        try {
            $graphics.CompositingMode =
                [Drawing.Drawing2D.CompositingMode]::SourceCopy
            for ($destinationBlock = 0;
                 $destinationBlock -lt $permutation.Count;
                 $destinationBlock++) {
                $sourceBlock = [int]$permutation[$destinationBlock]
                $sourceRectangle = [Drawing.Rectangle]::new(
                    ($sourceBlock % $columns) * $blockWidth,
                    [Math]::Floor($sourceBlock / $columns) * $blockHeight,
                    $blockWidth,
                    $blockHeight)
                $destinationRectangle = [Drawing.Rectangle]::new(
                    ($destinationBlock % $columns) * $blockWidth,
                    [Math]::Floor($destinationBlock / $columns) *
                        $blockHeight,
                    $blockWidth,
                    $blockHeight)
                $graphics.DrawImage(
                    $source,
                    $destinationRectangle,
                    $sourceRectangle,
                    [Drawing.GraphicsUnit]::Pixel)
            }
        } finally {
            $graphics.Dispose()
        }
        $destination.Save(
            $terrainPath,
            [Drawing.Imaging.ImageFormat]::Png)

        $thumbnailPath = Join-Path $outputPath 'thumbnail.png'
        $thumbnail = [Drawing.Bitmap]::new(
            264,
            220,
            [Drawing.Imaging.PixelFormat]::Format32bppArgb)
        try {
            $thumbnailGraphics =
                [Drawing.Graphics]::FromImage($thumbnail)
            try {
                $thumbnailGraphics.InterpolationMode =
                    [Drawing.Drawing2D.InterpolationMode]::
                        HighQualityBicubic
                $thumbnailGraphics.PixelOffsetMode =
                    [Drawing.Drawing2D.PixelOffsetMode]::HighQuality
                $thumbnailGraphics.DrawImage(
                    $destination,
                    [Drawing.Rectangle]::new(0, 0, 264, 220))
            } finally {
                $thumbnailGraphics.Dispose()
            }
            $thumbnail.Save(
                $thumbnailPath,
                [Drawing.Imaging.ImageFormat]::Png)
        } finally {
            $thumbnail.Dispose()
        }
    } finally {
        $destination.Dispose()
    }
} finally {
    $source.Dispose()
}

[pscustomobject]@{
    Terrain = Join-Path $outputPath 'terrain.png'
    Thumbnail = Join-Path $outputPath 'thumbnail.png'
    Blocks = $permutation.Count
}
