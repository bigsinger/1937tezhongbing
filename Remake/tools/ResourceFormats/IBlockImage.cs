using System.Buffers.Binary;
using System.Text;

namespace Mission1937.Remake.Resources;

public sealed class IBlockImage
{
    public const int SignatureSize = 34;
    public const int EmbeddedHeaderSize = 815;
    public const int HeaderSize = SignatureSize + EmbeddedHeaderSize;
    public const int WidthOffset = 42;
    public const int HeightOffset = 46;
    public const int BitsPerPixelOffset = 841;
    public const int CompressedLengthOffset = 845;

    private const int EmbeddedWidthOffset = 8;
    private const int EmbeddedHeightOffset = 12;
    private const int EmbeddedBitsPerPixelOffset = 807;
    private const int EmbeddedCompressedLengthOffset = 811;
    private const string Magic = "IBLOCK 1.0.0 Copyright U.M.E 2000";

    private readonly byte[] _rgba32;

    private IBlockImage(
        int width,
        int height,
        int bitsPerPixel,
        byte[] rgba32,
        bool hasAlphaPlane = false)
    {
        Width = width;
        Height = height;
        BitsPerPixel = bitsPerPixel;
        _rgba32 = rgba32;
        HasAlphaPlane = hasAlphaPlane;
    }

    public int Width { get; }

    public int Height { get; }

    public int BitsPerPixel { get; }

    public bool HasAlphaPlane { get; }

    public ReadOnlyMemory<byte> Rgba32 => _rgba32;

    public static IBlockImage Open(string path)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(path);
        using var stream = new FileStream(
            System.IO.Path.GetFullPath(path),
            FileMode.Open,
            FileAccess.Read,
            FileShare.Read);
        return Read(stream);
    }

    public static IBlockImage Read(Stream stream)
    {
        ArgumentNullException.ThrowIfNull(stream);
        if (!stream.CanRead)
        {
            throw new ArgumentException("The IBLOCK source stream is not readable.", nameof(stream));
        }

        var header = new byte[HeaderSize];
        try
        {
            stream.ReadExactly(header);
        }
        catch (EndOfStreamException exception)
        {
            throw new InvalidDataException("The file is shorter than an IBLOCK1 header.", exception);
        }

        ValidateSignature(header);
        var embeddedHeader = header.AsSpan(SignatureSize, EmbeddedHeaderSize);
        var metadata = ParseEmbeddedMetadata(embeddedHeader);
        var compressed = new byte[metadata.CompressedLength];
        try
        {
            stream.ReadExactly(compressed);
        }
        catch (EndOfStreamException exception)
        {
            throw new InvalidDataException("The IBLOCK compressed payload is truncated.", exception);
        }

        byte[] alphaCompressed = [];
        if (metadata.HasAlpha)
        {
            var alphaHeader = new byte[8];
            try
            {
                stream.ReadExactly(alphaHeader);
            }
            catch (EndOfStreamException exception)
            {
                throw new InvalidDataException("The IBLOCK alpha header is truncated.", exception);
            }

            var alphaLength = ReadAlphaLength(alphaHeader);
            alphaCompressed = new byte[alphaLength];
            try
            {
                stream.ReadExactly(alphaCompressed);
            }
            catch (EndOfStreamException exception)
            {
                throw new InvalidDataException("The IBLOCK alpha payload is truncated.", exception);
            }
        }

        if (stream.ReadByte() != -1)
        {
            throw new InvalidDataException("The IBLOCK file contains bytes beyond its declared payload.");
        }

        return DecodeEmbedded(metadata, compressed, alphaCompressed);
    }

    /// <summary>
    /// Reads the signature-free IBLOCK form embedded in TLG1 resources.
    /// </summary>
    /// <remarks>
    /// The returned consumed length permits a caller to continue parsing a
    /// containing format. Trailing bytes in <paramref name="source"/> are not
    /// considered part of the image.
    /// </remarks>
    public static IBlockImage ReadEmbedded(
        ReadOnlySpan<byte> source,
        out int consumedBytes)
    {
        if (source.Length < EmbeddedHeaderSize)
        {
            throw new InvalidDataException("The embedded IBLOCK header is truncated.");
        }

        var metadata = ParseEmbeddedMetadata(source[..EmbeddedHeaderSize]);
        var colorEnd = checked(EmbeddedHeaderSize + metadata.CompressedLength);
        if (source.Length < colorEnd)
        {
            throw new InvalidDataException("The embedded IBLOCK compressed payload is truncated.");
        }

        ReadOnlySpan<byte> alphaCompressed = [];
        consumedBytes = colorEnd;
        if (metadata.HasAlpha)
        {
            const int alphaHeaderSize = 8;
            if (source.Length - colorEnd < alphaHeaderSize)
            {
                throw new InvalidDataException("The embedded IBLOCK alpha header is truncated.");
            }

            var alphaLength = ReadAlphaLength(source.Slice(colorEnd, alphaHeaderSize));
            consumedBytes = checked(colorEnd + alphaHeaderSize + alphaLength);
            if (source.Length < consumedBytes)
            {
                throw new InvalidDataException("The embedded IBLOCK alpha payload is truncated.");
            }

            alphaCompressed = source.Slice(colorEnd + alphaHeaderSize, alphaLength);
        }

        return DecodeEmbedded(
            metadata,
            source.Slice(EmbeddedHeaderSize, metadata.CompressedLength),
            alphaCompressed);
    }

    public static IBlockImage DecodeCompressedRgb565(
        int width,
        int height,
        ReadOnlySpan<byte> compressed)
    {
        ValidateDimensions(width, height);
        var pixelCount = checked(width * height);
        var rgb565 = Lzo1XDecoder.DecodePrefixWithLegacySlack(
            compressed,
            checked(pixelCount * sizeof(ushort)));
        return FromRgb565(width, height, rgb565);
    }

    public static IBlockImage FromRgb565(
        int width,
        int height,
        ReadOnlySpan<byte> rgb565)
    {
        ValidateDimensions(width, height);
        var expectedLength = checked(width * height * sizeof(ushort));
        if (rgb565.Length != expectedLength)
        {
            throw new ArgumentException(
                $"RGB565 buffer has {rgb565.Length} bytes; {expectedLength} are required.",
                nameof(rgb565));
        }

        return new IBlockImage(width, height, 16, Rgb565.ToRgba32(rgb565));
    }

    public void WritePng(Stream destination)
    {
        PngWriter.WriteRgba32(destination, Width, Height, _rgba32);
    }

    public void SavePng(string path)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(path);
        var fullPath = System.IO.Path.GetFullPath(path);
        var directory = System.IO.Path.GetDirectoryName(fullPath);
        if (!string.IsNullOrEmpty(directory))
        {
            Directory.CreateDirectory(directory);
        }

        using var stream = new FileStream(
            fullPath,
            FileMode.Create,
            FileAccess.Write,
            FileShare.None);
        WritePng(stream);
    }

    internal int ApplyRgbColorKey(byte red, byte green, byte blue)
    {
        if (HasAlphaPlane)
        {
            throw new InvalidOperationException(
                "A color key must not replace an explicit IBLOCK alpha plane.");
        }

        var transparentPixels = 0;
        for (var offset = 0; offset < _rgba32.Length; offset += 4)
        {
            if (_rgba32[offset] == red &&
                _rgba32[offset + 1] == green &&
                _rgba32[offset + 2] == blue)
            {
                _rgba32[offset + 3] = 0;
                transparentPixels++;
            }
        }

        return transparentPixels;
    }

    private static EmbeddedMetadata ParseEmbeddedMetadata(ReadOnlySpan<byte> header)
    {
        if (header.Length < EmbeddedHeaderSize)
        {
            throw new InvalidDataException("The embedded IBLOCK header is truncated.");
        }

        var directSurface = ReadUInt32(header, 20);
        var hasAlpha = ReadUInt32(header, 24);
        if (ReadUInt32(header, 0) != 1 ||
            ReadUInt32(header, 4) != 1 ||
            ReadUInt32(header, 16) != 0 ||
            directSurface > 1 ||
            hasAlpha > 1 ||
            directSurface + hasAlpha != 1 ||
            ReadUInt32(header, 28) != 0)
        {
            throw new InvalidDataException("The embedded IBLOCK header is an unsupported structural variant.");
        }

        var width = ReadDimension(header, EmbeddedWidthOffset, "width");
        var height = ReadDimension(header, EmbeddedHeightOffset, "height");
        var bitsPerPixel = ReadUInt32(header, EmbeddedBitsPerPixelOffset);
        if (bitsPerPixel != 16)
        {
            throw new InvalidDataException(
                $"IBLOCK uses {bitsPerPixel} bits per pixel; only the known RGB565 variant is supported.");
        }

        var compressedLength = ReadUInt32(header, EmbeddedCompressedLengthOffset);
        if (compressedLength > int.MaxValue)
        {
            throw new InvalidDataException("The IBLOCK compressed payload is too large.");
        }

        return new EmbeddedMetadata(
            width,
            height,
            checked((int)compressedLength),
            hasAlpha == 1);
    }

    private static int ReadAlphaLength(ReadOnlySpan<byte> header)
    {
        if (ReadUInt32(header, 0) != 1)
        {
            throw new InvalidDataException("The IBLOCK alpha plane uses an unsupported version.");
        }

        var length = ReadUInt32(header, 4);
        if (length > int.MaxValue)
        {
            throw new InvalidDataException("The IBLOCK alpha payload is too large.");
        }

        return checked((int)length);
    }

    private static IBlockImage DecodeEmbedded(
        EmbeddedMetadata metadata,
        ReadOnlySpan<byte> compressed,
        ReadOnlySpan<byte> alphaCompressed)
    {
        var image = DecodeCompressedRgb565(metadata.Width, metadata.Height, compressed);
        if (!metadata.HasAlpha)
        {
            return image;
        }

        var pixelCount = checked(metadata.Width * metadata.Height);
        var alpha = Lzo1XDecoder.DecodePrefixWithLegacySlack(alphaCompressed, pixelCount);
        var rgba32 = image._rgba32;
        for (var pixelIndex = 0; pixelIndex < pixelCount; pixelIndex++)
        {
            rgba32[(pixelIndex * 4) + 3] = alpha[pixelIndex];
        }

        return new IBlockImage(
            metadata.Width,
            metadata.Height,
            image.BitsPerPixel,
            rgba32,
            hasAlphaPlane: true);
    }

    private static void ValidateSignature(ReadOnlySpan<byte> header)
    {
        var magicBytes = Encoding.ASCII.GetBytes(Magic);
        if (magicBytes.Length + 1 != SignatureSize ||
            !header[..magicBytes.Length].SequenceEqual(magicBytes) ||
            header[magicBytes.Length] != 0)
        {
            throw new InvalidDataException("The file does not contain the expected IBLOCK 1.0.0 header.");
        }
    }

    private static int ReadDimension(ReadOnlySpan<byte> header, int offset, string name)
    {
        var value = ReadUInt32(header, offset);
        if (value == 0 || value > 16_384)
        {
            throw new InvalidDataException($"IBLOCK {name} {value} is outside the supported range.");
        }

        return checked((int)value);
    }

    private static uint ReadUInt32(ReadOnlySpan<byte> source, int offset)
    {
        return BinaryPrimitives.ReadUInt32LittleEndian(source.Slice(offset, sizeof(uint)));
    }

    private static void ValidateDimensions(int width, int height)
    {
        if (width <= 0 || width > 16_384)
        {
            throw new ArgumentOutOfRangeException(nameof(width));
        }

        if (height <= 0 || height > 16_384)
        {
            throw new ArgumentOutOfRangeException(nameof(height));
        }

        _ = checked(width * height * 4);
    }

    private sealed record EmbeddedMetadata(
        int Width,
        int Height,
        int CompressedLength,
        bool HasAlpha);
}
