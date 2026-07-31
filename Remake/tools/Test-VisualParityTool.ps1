[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$compare = Join-Path $PSScriptRoot 'Compare-VisualParity.ps1'
if (-not (Test-Path -LiteralPath $compare -PathType Leaf)) {
    throw "Visual parity comparator is missing: $compare"
}

$temporaryRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$work = [IO.Path]::GetFullPath((Join-Path $temporaryRoot (
    'mission1937-visual-parity-test-' +
    [Guid]::NewGuid().ToString('N'))))
if (-not $work.StartsWith(
        $temporaryRoot.TrimEnd('\') + '\',
        [StringComparison]::OrdinalIgnoreCase)) {
    throw "Unsafe visual parity test directory: $work"
}
[IO.Directory]::CreateDirectory($work) | Out-Null

try {
    if (-not ('Mission1937VisualParityFixtureV1' -as [type])) {
        Add-Type -ReferencedAssemblies @(
            'System.dll',
            'System.Drawing.dll'
        ) -TypeDefinition @'
using System.Drawing;
using System.Drawing.Imaging;

public static class Mission1937VisualParityFixtureV1
{
    public static void Create(string path, bool damage)
    {
        using (var bitmap = new Bitmap(64, 48, PixelFormat.Format32bppArgb))
        {
            for (int y = 0; y < bitmap.Height; ++y)
            for (int x = 0; x < bitmap.Width; ++x)
            {
                int r = 32 + (x * 3 + y) % 192;
                int g = 32 + (x + y * 5) % 192;
                int b = 32 + (x * 7 + y * 3) % 192;
                bitmap.SetPixel(x, y, Color.FromArgb(255, r, g, b));
            }
            if (damage)
            {
                using (var graphics = Graphics.FromImage(bitmap))
                using (var brush = new SolidBrush(Color.Black))
                    graphics.FillRectangle(brush, 20, 12, 24, 20);
            }
            bitmap.Save(path, ImageFormat.Png);
        }
    }
}
'@
    }

    $reference = Join-Path $work 'reference.png'
    $identical = Join-Path $work 'identical.png'
    $damaged = Join-Path $work 'damaged.png'
    [Mission1937VisualParityFixtureV1]::Create($reference, $false)
    [Mission1937VisualParityFixtureV1]::Create($identical, $false)
    [Mission1937VisualParityFixtureV1]::Create($damaged, $true)

    $identicalOutput = Join-Path $work 'identical-result'
    $identicalResult = & $compare `
        -ReferenceImage $reference `
        -CandidateImage $identical `
        -OutputDirectory $identicalOutput `
        -MaximumMeanAbsoluteError 0 `
        -MinimumNearMatchRatio 1 `
        -MinimumEdgeCorrelation 0.999999 `
        -MaximumBlackHoleRatio 0
    if (-not [bool]$identicalResult.passed) {
        throw 'An identical image pair did not pass visual parity.'
    }
    if (-not (Test-Path -LiteralPath (
            Join-Path $identicalOutput 'visual-parity-contact-sheet.png'
        ) -PathType Leaf)) {
        throw 'The visual parity contact sheet was not produced.'
    }

    $damagedOutput = Join-Path $work 'damaged-result'
    $damagedResult = & $compare `
        -ReferenceImage $reference `
        -CandidateImage $damaged `
        -OutputDirectory $damagedOutput `
        -MaximumMeanAbsoluteError 1 `
        -MinimumNearMatchRatio 0.99 `
        -MinimumEdgeCorrelation 0.99 `
        -MaximumBlackHoleRatio 0.001 `
        -AllowMismatch
    if ([bool]$damagedResult.passed) {
        throw 'A synthetic black-hole regression was not rejected.'
    }
    if ([double]$damagedResult.metrics.black_hole_ratio -le 0.01) {
        throw 'The synthetic black-hole regression was not measured.'
    }

    Write-Host 'Visual parity comparator tests passed.'
}
finally {
    if (Test-Path -LiteralPath $work) {
        Remove-Item -LiteralPath $work -Recurse -Force
    }
}
