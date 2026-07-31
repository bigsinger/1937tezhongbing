[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string]$ReferenceImage,

    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string]$CandidateImage,

    [Parameter(Mandatory)]
    [string]$OutputDirectory,

    [int]$RegionTop = 0,
    [int]$RegionBottom = 708,
    [double]$MaximumMeanAbsoluteError = 20.0,
    [double]$MinimumNearMatchRatio = 0.70,
    [double]$MinimumEdgeCorrelation = 0.90,
    [double]$MaximumBlackHoleRatio = 0.002,
    [switch]$AllowMismatch
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ReferenceImage = (Resolve-Path -LiteralPath $ReferenceImage).Path
$CandidateImage = (Resolve-Path -LiteralPath $CandidateImage).Path
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
[IO.Directory]::CreateDirectory($OutputDirectory) | Out-Null
$contactSheet = Join-Path $OutputDirectory 'visual-parity-contact-sheet.png'

if (-not ('Mission1937VisualParityV1' -as [type])) {
    Add-Type -ReferencedAssemblies @(
        'System.dll',
        'System.Drawing.dll'
    ) -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

public sealed class Mission1937VisualParityResultV1
{
    public int Width;
    public int Height;
    public int RegionTop;
    public int RegionBottom;
    public long ComparedPixels;
    public double MeanAbsoluteError;
    public double NearMatchRatio;
    public double EdgeCorrelation;
    public double BlackHoleRatio;
}

public static class Mission1937VisualParityV1
{
    public static Mission1937VisualParityResultV1 Compare(
        string referencePath,
        string candidatePath,
        string contactSheetPath,
        int regionTop,
        int regionBottom)
    {
        using (var referenceSource = new Bitmap(referencePath))
        using (var candidateSource = new Bitmap(candidatePath))
        {
            if (referenceSource.Width != candidateSource.Width ||
                referenceSource.Height != candidateSource.Height)
                throw new InvalidOperationException(
                    "Visual parity images must have identical dimensions.");

            int width = referenceSource.Width;
            int height = referenceSource.Height;
            int top = Math.Max(0, Math.Min(height, regionTop));
            int bottom = Math.Max(top, Math.Min(height, regionBottom));
            if (bottom - top < 3 || width < 3)
                throw new InvalidOperationException(
                    "Visual parity comparison region is too small.");

            using (var reference = Normalize(referenceSource))
            using (var candidate = Normalize(candidateSource))
            {
                int referenceStride;
                int candidateStride;
                byte[] referenceBytes = ReadBytes(
                    reference, out referenceStride);
                byte[] candidateBytes = ReadBytes(
                    candidate, out candidateStride);

                long channelError = 0;
                long nearMatches = 0;
                long blackHoles = 0;
                long comparedPixels = (long)width * (bottom - top);
                byte[] referenceLuma = new byte[checked(width * height)];
                byte[] candidateLuma = new byte[checked(width * height)];
                byte[] difference = new byte[
                    checked(referenceStride * height)];

                for (int y = 0; y < height; y++)
                {
                    int referenceRow = y * referenceStride;
                    int candidateRow = y * candidateStride;
                    int lumaRow = y * width;
                    for (int x = 0; x < width; x++)
                    {
                        int referenceOffset = referenceRow + x * 3;
                        int candidateOffset = candidateRow + x * 3;
                        int db = Math.Abs(
                            referenceBytes[referenceOffset] -
                            candidateBytes[candidateOffset]);
                        int dg = Math.Abs(
                            referenceBytes[referenceOffset + 1] -
                            candidateBytes[candidateOffset + 1]);
                        int dr = Math.Abs(
                            referenceBytes[referenceOffset + 2] -
                            candidateBytes[candidateOffset + 2]);
                        int differenceOffset = referenceOffset;
                        difference[differenceOffset] =
                            (byte)Math.Min(255, db * 4);
                        difference[differenceOffset + 1] =
                            (byte)Math.Min(255, dg * 4);
                        difference[differenceOffset + 2] =
                            (byte)Math.Min(255, dr * 4);

                        int referenceY =
                            (referenceBytes[referenceOffset] * 29 +
                             referenceBytes[referenceOffset + 1] * 150 +
                             referenceBytes[referenceOffset + 2] * 77) >> 8;
                        int candidateY =
                            (candidateBytes[candidateOffset] * 29 +
                             candidateBytes[candidateOffset + 1] * 150 +
                             candidateBytes[candidateOffset + 2] * 77) >> 8;
                        referenceLuma[lumaRow + x] =
                            (byte)referenceY;
                        candidateLuma[lumaRow + x] =
                            (byte)candidateY;
                        if (y < top || y >= bottom)
                            continue;
                        channelError += db + dg + dr;
                        if (db + dg + dr <= 36)
                            nearMatches++;
                        if (candidateY <= 4 && referenceY >= 24)
                            blackHoles++;
                    }
                }

                double sumReferenceEdge = 0;
                double sumCandidateEdge = 0;
                double sumReferenceSquared = 0;
                double sumCandidateSquared = 0;
                double sumProduct = 0;
                long edgeSamples = 0;
                for (int y = Math.Max(top + 1, 1);
                     y < Math.Min(bottom - 1, height - 1);
                     y += 2)
                {
                    int row = y * width;
                    for (int x = 1; x < width - 1; x += 2)
                    {
                        int referenceEdge =
                            Math.Abs(
                                referenceLuma[row + x + 1] -
                                referenceLuma[row + x - 1]) +
                            Math.Abs(
                                referenceLuma[row + width + x] -
                                referenceLuma[row - width + x]);
                        int candidateEdge =
                            Math.Abs(
                                candidateLuma[row + x + 1] -
                                candidateLuma[row + x - 1]) +
                            Math.Abs(
                                candidateLuma[row + width + x] -
                                candidateLuma[row - width + x]);
                        sumReferenceEdge += referenceEdge;
                        sumCandidateEdge += candidateEdge;
                        sumReferenceSquared +=
                            (double)referenceEdge * referenceEdge;
                        sumCandidateSquared +=
                            (double)candidateEdge * candidateEdge;
                        sumProduct +=
                            (double)referenceEdge * candidateEdge;
                        edgeSamples++;
                    }
                }
                double edgeCorrelation = Correlation(
                    edgeSamples,
                    sumReferenceEdge,
                    sumCandidateEdge,
                    sumReferenceSquared,
                    sumCandidateSquared,
                    sumProduct);

                using (var differenceBitmap =
                    new Bitmap(width, height, PixelFormat.Format24bppRgb))
                {
                    WriteBytes(
                        differenceBitmap,
                        difference,
                        referenceStride);
                    using (var contactSheet = new Bitmap(
                        checked(width * 3),
                        height,
                        PixelFormat.Format24bppRgb))
                    using (Graphics graphics =
                        Graphics.FromImage(contactSheet))
                    {
                        graphics.DrawImageUnscaled(reference, 0, 0);
                        graphics.DrawImageUnscaled(
                            candidate, width, 0);
                        graphics.DrawImageUnscaled(
                            differenceBitmap, width * 2, 0);
                        contactSheet.Save(
                            contactSheetPath,
                            ImageFormat.Png);
                    }
                }

                return new Mission1937VisualParityResultV1
                {
                    Width = width,
                    Height = height,
                    RegionTop = top,
                    RegionBottom = bottom,
                    ComparedPixels = comparedPixels,
                    MeanAbsoluteError =
                        channelError / (double)(comparedPixels * 3),
                    NearMatchRatio =
                        nearMatches / (double)comparedPixels,
                    EdgeCorrelation = edgeCorrelation,
                    BlackHoleRatio =
                        blackHoles / (double)comparedPixels
                };
            }
        }
    }

    private static Bitmap Normalize(Bitmap source)
    {
        var result = new Bitmap(
            source.Width,
            source.Height,
            PixelFormat.Format24bppRgb);
        using (Graphics graphics = Graphics.FromImage(result))
            graphics.DrawImageUnscaled(source, 0, 0);
        return result;
    }

    private static byte[] ReadBytes(
        Bitmap bitmap,
        out int stride)
    {
        var area = new Rectangle(
            0, 0, bitmap.Width, bitmap.Height);
        BitmapData data = bitmap.LockBits(
            area,
            ImageLockMode.ReadOnly,
            PixelFormat.Format24bppRgb);
        try
        {
            stride = Math.Abs(data.Stride);
            byte[] bytes = new byte[checked(stride * bitmap.Height)];
            Marshal.Copy(data.Scan0, bytes, 0, bytes.Length);
            return bytes;
        }
        finally
        {
            bitmap.UnlockBits(data);
        }
    }

    private static void WriteBytes(
        Bitmap bitmap,
        byte[] bytes,
        int sourceStride)
    {
        var area = new Rectangle(
            0, 0, bitmap.Width, bitmap.Height);
        BitmapData data = bitmap.LockBits(
            area,
            ImageLockMode.WriteOnly,
            PixelFormat.Format24bppRgb);
        try
        {
            int destinationStride = Math.Abs(data.Stride);
            if (destinationStride == sourceStride)
            {
                Marshal.Copy(
                    bytes, 0, data.Scan0,
                    destinationStride * bitmap.Height);
                return;
            }
            byte[] destination = new byte[
                checked(destinationStride * bitmap.Height)];
            int copiedWidth = Math.Min(
                sourceStride, destinationStride);
            for (int y = 0; y < bitmap.Height; y++)
                Buffer.BlockCopy(
                    bytes,
                    y * sourceStride,
                    destination,
                    y * destinationStride,
                    copiedWidth);
            Marshal.Copy(
                destination, 0, data.Scan0,
                destination.Length);
        }
        finally
        {
            bitmap.UnlockBits(data);
        }
    }

    private static double Correlation(
        long count,
        double sumX,
        double sumY,
        double sumXX,
        double sumYY,
        double sumXY)
    {
        if (count <= 1)
            return 0;
        double numerator = count * sumXY - sumX * sumY;
        double denominatorX =
            count * sumXX - sumX * sumX;
        double denominatorY =
            count * sumYY - sumY * sumY;
        double denominator =
            Math.Sqrt(Math.Max(0, denominatorX * denominatorY));
        return denominator <= 0 ? 0 : numerator / denominator;
    }
}
'@
}

$metrics = [Mission1937VisualParityV1]::Compare(
    $ReferenceImage,
    $CandidateImage,
    $contactSheet,
    $RegionTop,
    $RegionBottom)
$passed = (
    $metrics.MeanAbsoluteError -le $MaximumMeanAbsoluteError -and
    $metrics.NearMatchRatio -ge $MinimumNearMatchRatio -and
    $metrics.EdgeCorrelation -ge $MinimumEdgeCorrelation -and
    $metrics.BlackHoleRatio -le $MaximumBlackHoleRatio
)
$result = [pscustomobject][ordered]@{
    schema_version = 1
    reference = $ReferenceImage
    candidate = $CandidateImage
    dimensions = @($metrics.Width, $metrics.Height)
    region = [pscustomobject][ordered]@{
        top = $metrics.RegionTop
        bottom = $metrics.RegionBottom
        compared_pixels = $metrics.ComparedPixels
    }
    metrics = [pscustomobject][ordered]@{
        mean_absolute_error = [Math]::Round(
            $metrics.MeanAbsoluteError, 6)
        near_match_ratio = [Math]::Round(
            $metrics.NearMatchRatio, 6)
        edge_correlation = [Math]::Round(
            $metrics.EdgeCorrelation, 6)
        black_hole_ratio = [Math]::Round(
            $metrics.BlackHoleRatio, 8)
    }
    thresholds = [pscustomobject][ordered]@{
        maximum_mean_absolute_error = $MaximumMeanAbsoluteError
        minimum_near_match_ratio = $MinimumNearMatchRatio
        minimum_edge_correlation = $MinimumEdgeCorrelation
        maximum_black_hole_ratio = $MaximumBlackHoleRatio
    }
    contact_sheet = $contactSheet
    panel_order = @('stable_mod', 'remake', 'absolute_difference_x4')
    passed = $passed
}
$jsonPath = Join-Path $OutputDirectory 'visual-parity.json'
$result | ConvertTo-Json -Depth 8 |
    Set-Content -LiteralPath $jsonPath -Encoding UTF8

$markdown = @(
    '# Visual parity'
    ''
    "- Result: $(if ($passed) { 'pass' } else { 'fail' })"
    "- Region: y=$($metrics.RegionTop)..$($metrics.RegionBottom - 1)"
    "- Mean absolute RGB error: $([Math]::Round($metrics.MeanAbsoluteError, 3))"
    "- Near-match ratio: $([Math]::Round($metrics.NearMatchRatio, 4))"
    "- Edge correlation: $([Math]::Round($metrics.EdgeCorrelation, 4))"
    "- Black-hole ratio: $([Math]::Round($metrics.BlackHoleRatio, 6))"
    "- Contact sheet: $contactSheet"
    ''
    'Panel order: stable MOD | Remake | absolute difference ×4.'
)
$markdownPath = Join-Path $OutputDirectory 'visual-parity.md'
$markdown | Set-Content -LiteralPath $markdownPath -Encoding UTF8

$result
if (-not $passed -and -not $AllowMismatch) {
    throw 'Visual parity thresholds were not met.'
}
