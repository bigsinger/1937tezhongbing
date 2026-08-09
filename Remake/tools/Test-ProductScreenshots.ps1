[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ScreenshotRoot
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = [IO.Path]::GetFullPath($ScreenshotRoot)
if (-not (Test-Path -LiteralPath $root -PathType Container)) {
    throw "Product screenshot root was not found: $root"
}

Add-Type -AssemblyName System.Drawing

$expectedNames = @(
    'startup-level-selector.jpg',
    'gameplay-hud.jpg',
    'tactical-map.jpg',
    'inventory.jpg',
    'control-guide.jpg',
    'pause-menu.jpg',
    'modern-settings.jpg',
    'history-archive.jpg',
    'accessibility-settings.jpg',
    'credits.jpg',
    'level-selector.jpg',
    'failure-menu.jpg',
    'developer-diagnostics.jpg'
)
$viewports = [ordered]@{
    '1024x768' = [Drawing.Size]::new(1024, 768)
    '1920x1080' = [Drawing.Size]::new(1920, 1080)
}
# These two captures intentionally exercise the same selector surface through
# different product journeys: once during startup and once from the pause-menu
# route. Their state-transition assertions live in product_ui_probe.gd, while
# the resulting pixels are allowed to match exactly on deterministic drivers.
$allowedDuplicatePairs = @{
    'level-selector.jpg|startup-level-selector.jpg' = $true
}
$failures = [Collections.Generic.List[string]]::new()
$records = [Collections.Generic.List[object]]::new()

foreach ($viewport in $viewports.Keys) {
    $directory = Join-Path $root $viewport
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        $failures.Add("Missing viewport directory: $viewport")
        continue
    }
    $layoutPath = Join-Path $directory 'gameplay-hud-layout.json'
    if (-not (Test-Path -LiteralPath $layoutPath -PathType Leaf)) {
        $failures.Add("Missing viewport layout evidence: $viewport/gameplay-hud-layout.json")
        continue
    }
    $layout = Get-Content -LiteralPath $layoutPath -Raw -Encoding utf8 |
        ConvertFrom-Json
    $requestedSize = $viewports[$viewport]
    $viewportWidth = [int]$layout.viewport.width
    $viewportHeight = [int]$layout.viewport.height
    if ($viewportWidth -ne $requestedSize.Width -or
        $viewportHeight -gt $requestedSize.Height -or
        $viewportHeight -lt ($requestedSize.Height - 128)) {
        $failures.Add(
            "Unexpected render viewport for ${viewport}: " +
            "${viewportWidth}x${viewportHeight}")
        continue
    }
    $expectedImageSize = [Drawing.Size]::new(
        [Math]::Min(960, $viewportWidth),
        [Math]::Round(
            $viewportHeight * [Math]::Min(960, $viewportWidth) / $viewportWidth,
            [MidpointRounding]::AwayFromZero))
    $observedHashes = [Collections.Generic.Dictionary[string,string]]::new(
        [StringComparer]::OrdinalIgnoreCase)
    foreach ($name in $expectedNames) {
        $path = Join-Path $directory $name
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            $failures.Add("Missing screenshot: $viewport/$name")
            continue
        }
        $file = Get-Item -LiteralPath $path
        if ($file.Length -lt 4096) {
            $failures.Add("Screenshot is unexpectedly small: $viewport/$name ($($file.Length) bytes)")
            continue
        }
        $bitmap = $null
        try {
            $bitmap = [Drawing.Bitmap]::FromFile($path)
            if ($bitmap.Width -ne $expectedImageSize.Width -or
                $bitmap.Height -ne $expectedImageSize.Height) {
                $failures.Add(
                    "Screenshot size mismatch: $viewport/$name is " +
                    "$($bitmap.Width)x$($bitmap.Height), expected " +
                    "$($expectedImageSize.Width)x$($expectedImageSize.Height)")
            }
            $minimumLuma = 255.0
            $maximumLuma = 0.0
            $sampleCount = 0
            $stepX = [Math]::Max(1, [int]($bitmap.Width / 31))
            $stepY = [Math]::Max(1, [int]($bitmap.Height / 23))
            for ($y = 0; $y -lt $bitmap.Height; $y += $stepY) {
                for ($x = 0; $x -lt $bitmap.Width; $x += $stepX) {
                    $pixel = $bitmap.GetPixel($x, $y)
                    $luma = 0.2126 * $pixel.R + 0.7152 * $pixel.G + 0.0722 * $pixel.B
                    $minimumLuma = [Math]::Min($minimumLuma, $luma)
                    $maximumLuma = [Math]::Max($maximumLuma, $luma)
                    $sampleCount++
                }
            }
            if (($maximumLuma - $minimumLuma) -lt 18.0) {
                $failures.Add(
                    "Screenshot appears blank or flat: $viewport/$name " +
                    "(sampled luma range $([Math]::Round($maximumLuma - $minimumLuma, 2)))")
            }
        }
        catch {
            $failures.Add("Screenshot cannot be decoded: $viewport/$name ($($_.Exception.Message))")
            continue
        }
        finally {
            if ($null -ne $bitmap) {
                $bitmap.Dispose()
            }
        }
        $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($observedHashes.ContainsKey($hash)) {
            $duplicateName = $observedHashes[$hash]
            $pairKey = (@($name, $duplicateName) | Sort-Object) -join '|'
            if (-not $allowedDuplicatePairs.ContainsKey($pairKey)) {
                $failures.Add(
                    "Screenshots are unexpectedly identical: $viewport/$name and " +
                    $duplicateName)
            }
        }
        else {
            $observedHashes[$hash] = $name
        }
        $records.Add([ordered]@{
            viewport = $viewport
            file = $name
            bytes = [int64]$file.Length
            sha256 = $hash
        })
    }
}

if ($failures.Count -gt 0) {
    throw "Product screenshot regression failed:`n - $($failures -join "`n - ")"
}

[pscustomobject]@{
    Status = 'passed'
    Viewports = $viewports.Count
    Screenshots = $records.Count
    Contract = 'dimensions, decode, minimum size, sampled luminance, uniqueness'
}
