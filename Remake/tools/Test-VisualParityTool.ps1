[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$compare = Join-Path $PSScriptRoot 'Compare-VisualParity.ps1'
$baselineBuilder = Join-Path $PSScriptRoot 'Build-VisualParityBaseline.ps1'
if (-not (Test-Path -LiteralPath $compare -PathType Leaf)) {
    throw "Visual parity comparator is missing: $compare"
}
if (-not (Test-Path -LiteralPath $baselineBuilder -PathType Leaf)) {
    throw "Visual parity baseline builder is missing: $baselineBuilder"
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
    private static Color Pixel(int x, int y)
    {
        int r = 32 + (x * 3 + y) % 192;
        int g = 32 + (x + y * 5) % 192;
        int b = 32 + (x * 7 + y * 3) % 192;
        return Color.FromArgb(255, r, g, b);
    }

    public static void Create(string path, bool damage)
    {
        using (var bitmap = new Bitmap(64, 48, PixelFormat.Format32bppArgb))
        {
            for (int y = 0; y < bitmap.Height; ++y)
            for (int x = 0; x < bitmap.Width; ++x)
                bitmap.SetPixel(x, y, Pixel(x, y));
            if (damage)
            {
                using (var graphics = Graphics.FromImage(bitmap))
                using (var brush = new SolidBrush(Color.Black))
                    graphics.FillRectangle(brush, 20, 12, 24, 20);
            }
            bitmap.Save(path, ImageFormat.Png);
        }
    }

    public static void CreateOffset(
        string path, int left, int top)
    {
        using (var bitmap = new Bitmap(
            128, 96, PixelFormat.Format32bppArgb))
        {
            using (var graphics = Graphics.FromImage(bitmap))
                graphics.Clear(Color.Black);
            for (int y = 0; y < 48; ++y)
            for (int x = 0; x < 64; ++x)
                bitmap.SetPixel(left + x, top + y, Pixel(x, y));
            bitmap.Save(path, ImageFormat.Png);
        }
    }

    public static void CreateOffsetPartial(
        string path, int left, int top, int rows)
    {
        using (var bitmap = new Bitmap(
            128, top + rows, PixelFormat.Format32bppArgb))
        {
            using (var graphics = Graphics.FromImage(bitmap))
                graphics.Clear(Color.Black);
            for (int y = 0; y < rows; ++y)
            for (int x = 0; x < 64; ++x)
                bitmap.SetPixel(left + x, top + y, Pixel(x, y));
            bitmap.Save(path, ImageFormat.Png);
        }
    }
}
'@
    }

    $reference = Join-Path $work 'reference.png'
    $identical = Join-Path $work 'identical.png'
    $offset = Join-Path $work 'offset.png'
    $partialOffset = Join-Path $work 'partial-offset.png'
    $damaged = Join-Path $work 'damaged.png'
    [Mission1937VisualParityFixtureV1]::Create($reference, $false)
    [Mission1937VisualParityFixtureV1]::Create($identical, $false)
    [Mission1937VisualParityFixtureV1]::CreateOffset($offset, 17, 23)
    [Mission1937VisualParityFixtureV1]::CreateOffsetPartial(
        $partialOffset, 17, 23, 40)
    [Mission1937VisualParityFixtureV1]::Create($damaged, $true)

    $overwriteRejected = $false
    try {
        & $baselineBuilder `
            -SummaryPath @($reference) `
            -OutputPath $reference
    }
    catch {
        if (
            $_.Exception.Message -like
                '*must not overwrite an input summary*'
        ) {
            $overwriteRejected = $true
        }
        else {
            throw
        }
    }
    if (-not $overwriteRejected -or
        -not (Test-Path -LiteralPath $reference -PathType Leaf)) {
        throw 'The baseline builder did not reject an input/output collision.'
    }

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

    $offsetOutput = Join-Path $work 'offset-result'
    $offsetResult = & $compare `
        -ReferenceImage $reference `
        -CandidateImage $offset `
        -CandidateLeft 17 `
        -CandidateTop 23 `
        -OutputDirectory $offsetOutput `
        -MaximumMeanAbsoluteError 0 `
        -MinimumNearMatchRatio 1 `
        -MinimumEdgeCorrelation 0.999999 `
        -MaximumBlackHoleRatio 0
    if (-not [bool]$offsetResult.passed -or
        (@($offsetResult.candidate_crop) -join ',') -ne '17,23') {
        throw 'A matching crop inside a larger candidate did not pass.'
    }

    $partialOffsetOutput = Join-Path $work 'partial-offset-result'
    $partialOffsetResult = & $compare `
        -ReferenceImage $reference `
        -CandidateImage $partialOffset `
        -CandidateLeft 17 `
        -CandidateTop 23 `
        -RegionBottom 40 `
        -OutputDirectory $partialOffsetOutput `
        -MaximumMeanAbsoluteError 0 `
        -MinimumNearMatchRatio 1 `
        -MinimumEdgeCorrelation 0.999999 `
        -MaximumBlackHoleRatio 0
    if (-not [bool]$partialOffsetResult.passed) {
        throw (
            'A lower crop ending before excluded legacy HUD rows ' +
            'did not pass.')
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
