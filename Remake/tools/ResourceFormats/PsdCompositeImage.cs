using System.Buffers.Binary;
using System.Text;

namespace Mission1937.Remake.Resources;

/// <summary>
/// Reads the flattened composite image stored at the end of the Photoshop 3.x
/// files shipped in 1937Resources.GFL.  The original archive uses 8-bit RGB
/// PSD version 1 files with either raw planar pixels or PackBits-compressed
/// scanlines; layers are deliberately ignored because the game consumed the
/// same flattened composite.
/// </summary>
public sealed class PsdCompositeImage
{
    private const int HeaderSize = 26;
    private const ushort SupportedVersion = 1;
    private const ushort SupportedDepth = 8;
    private const ushort RgbColorMode = 3;
    private const ushort RawCompression = 0;
    private const ushort PackBitsCompression = 1;
    private readonly byte[] _rgba32;

    private PsdCompositeImage(
        int width,
        int height,
        int channelCount,
        byte[] rgba32)
    {
        Width = width;
        Height = height;
        ChannelCount = channelCount;
        _rgba32 = rgba32;
    }

    public int Width { get; }

    public int Height { get; }

    public int ChannelCount { get; }

    public bool HasAlphaPlane => ChannelCount >= 4;

    public ReadOnlyMemory<byte> Rgba32 => _rgba32;

    public static PsdCompositeImage Open(string path)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(path);
        using var stream = new FileStream(
            System.IO.Path.GetFullPath(path),
            FileMode.Open,
            FileAccess.Read,
            FileShare.Read);
        return Read(stream);
    }

    public static PsdCompositeImage Read(Stream stream)
    {
        ArgumentNullException.ThrowIfNull(stream);
        if (!stream.CanRead)
        {
            throw new ArgumentException("The PSD source stream is not readable.", nameof(stream));
        }

        var header = ReadExactly(stream, HeaderSize, "The PSD header is truncated.");
        if (!header.AsSpan(0, 4).SequenceEqual("8BPS"u8))
        {
            throw new InvalidDataException("The file does not have a PSD signature.");
        }

        var version = ReadUInt16(header, 4);
        if (version != SupportedVersion)
        {
            throw new InvalidDataException(
                $"PSD version {version} is not supported; version 1 is required.");
        }
        if (!header.AsSpan(6, 6).SequenceEqual(new byte[6]))
        {
            throw new InvalidDataException("The PSD reserved header bytes are not zero.");
        }

        var channels = ReadUInt16(header, 12);
        var height = checked((int)ReadUInt32(header, 14));
        var width = checked((int)ReadUInt32(header, 18));
        var depth = ReadUInt16(header, 22);
        var colorMode = ReadUInt16(header, 24);
        ValidateMetadata(width, height, channels, depth, colorMode);

        SkipLengthPrefixedSection(stream, "color-mode data");
        SkipLengthPrefixedSection(stream, "image resources");
        SkipLengthPrefixedSection(stream, "layer and mask data");

        var compressionBytes = ReadExactly(
            stream,
            sizeof(ushort),
            "The PSD composite compression field is truncated.");
        var compression = ReadUInt16(compressionBytes, 0);
        var pixelCount = checked(width * height);
        var planar = new byte[checked(pixelCount * channels)];
        switch (compression)
        {
            case RawCompression:
                ReadIntoExactly(
                    stream,
                    planar,
                    "The PSD raw composite pixels are truncated.");
                break;
            case PackBitsCompression:
                DecodePackBitsComposite(stream, width, height, channels, planar);
                break;
            default:
                throw new InvalidDataException(
                    $"PSD composite compression {compression} is not supported.");
        }

        if (stream.ReadByte() != -1)
        {
            throw new InvalidDataException(
                "The PSD contains bytes beyond its flattened composite image.");
        }

        var rgba = new byte[checked(pixelCount * 4)];
        for (var pixel = 0; pixel < pixelCount; pixel++)
        {
            var output = pixel * 4;
            rgba[output] = planar[pixel];
            rgba[output + 1] = planar[pixelCount + pixel];
            rgba[output + 2] = planar[(pixelCount * 2) + pixel];
            rgba[output + 3] = channels >= 4
                ? planar[(pixelCount * 3) + pixel]
                : byte.MaxValue;
        }

        return new PsdCompositeImage(width, height, channels, rgba);
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

    private static void DecodePackBitsComposite(
        Stream stream,
        int width,
        int height,
        int channels,
        Span<byte> planar)
    {
        var rowCount = checked(height * channels);
        var rowLengths = new ushort[rowCount];
        var lengthTable = ReadExactly(
            stream,
            checked(rowCount * sizeof(ushort)),
            "The PSD PackBits row-length table is truncated.");
        for (var row = 0; row < rowCount; row++)
        {
            rowLengths[row] = ReadUInt16(lengthTable, row * sizeof(ushort));
        }

        for (var channel = 0; channel < channels; channel++)
        {
            for (var row = 0; row < height; row++)
            {
                var rowIndex = checked((channel * height) + row);
                var encoded = ReadExactly(
                    stream,
                    rowLengths[rowIndex],
                    $"PSD PackBits row {rowIndex} is truncated.");
                var outputOffset = checked((channel * width * height) + (row * width));
                DecodePackBitsRow(
                    encoded,
                    planar.Slice(outputOffset, width),
                    rowIndex);
            }
        }
    }

    private static void DecodePackBitsRow(
        ReadOnlySpan<byte> encoded,
        Span<byte> decoded,
        int rowIndex)
    {
        var input = 0;
        var output = 0;
        while (input < encoded.Length && output < decoded.Length)
        {
            var control = unchecked((sbyte)encoded[input++]);
            if (control >= 0)
            {
                var count = control + 1;
                if (input + count > encoded.Length || output + count > decoded.Length)
                {
                    throw new InvalidDataException(
                        $"PSD PackBits literal overruns row {rowIndex}.");
                }
                encoded.Slice(input, count).CopyTo(decoded.Slice(output, count));
                input += count;
                output += count;
            }
            else if (control != sbyte.MinValue)
            {
                var count = 1 - control;
                if (input >= encoded.Length || output + count > decoded.Length)
                {
                    throw new InvalidDataException(
                        $"PSD PackBits repeat overruns row {rowIndex}.");
                }
                decoded.Slice(output, count).Fill(encoded[input++]);
                output += count;
            }
        }

        if (output != decoded.Length || input != encoded.Length)
        {
            throw new InvalidDataException(
                $"PSD PackBits row {rowIndex} does not decode to its declared width.");
        }
    }

    private static void SkipLengthPrefixedSection(Stream stream, string description)
    {
        var lengthBytes = ReadExactly(
            stream,
            sizeof(uint),
            $"The PSD {description} length is truncated.");
        var length = ReadUInt32(lengthBytes, 0);
        if (length > int.MaxValue)
        {
            throw new InvalidDataException($"The PSD {description} is too large.");
        }
        if (stream.CanSeek)
        {
            var remaining = stream.Length - stream.Position;
            if (remaining < length)
            {
                throw new InvalidDataException($"The PSD {description} is truncated.");
            }
            stream.Seek(length, SeekOrigin.Current);
            return;
        }

        var buffer = new byte[8192];
        var pending = checked((int)length);
        while (pending > 0)
        {
            var read = stream.Read(buffer, 0, Math.Min(buffer.Length, pending));
            if (read == 0)
            {
                throw new InvalidDataException($"The PSD {description} is truncated.");
            }
            pending -= read;
        }
    }

    private static void ValidateMetadata(
        int width,
        int height,
        int channels,
        int depth,
        int colorMode)
    {
        if (width <= 0 || height <= 0 || width > 30_000 || height > 30_000)
        {
            throw new InvalidDataException(
                $"PSD dimensions {width}x{height} are outside the supported range.");
        }
        if (channels < 3 || channels > 56)
        {
            throw new InvalidDataException(
                $"PSD RGB composite requires at least three channels; found {channels}.");
        }
        if (depth != SupportedDepth)
        {
            throw new InvalidDataException(
                $"PSD channel depth {depth} is not supported; 8-bit data is required.");
        }
        if (colorMode != RgbColorMode)
        {
            throw new InvalidDataException(
                $"PSD color mode {colorMode} is not supported; RGB mode is required.");
        }
        _ = checked(width * height * channels);
    }

    private static byte[] ReadExactly(Stream stream, int count, string message)
    {
        var bytes = new byte[count];
        ReadIntoExactly(stream, bytes, message);
        return bytes;
    }

    private static void ReadIntoExactly(Stream stream, byte[] bytes, string message)
    {
        try
        {
            stream.ReadExactly(bytes);
        }
        catch (EndOfStreamException exception)
        {
            throw new InvalidDataException(message, exception);
        }
    }

    private static ushort ReadUInt16(ReadOnlySpan<byte> source, int offset) =>
        BinaryPrimitives.ReadUInt16BigEndian(source.Slice(offset, sizeof(ushort)));

    private static uint ReadUInt32(ReadOnlySpan<byte> source, int offset) =>
        BinaryPrimitives.ReadUInt32BigEndian(source.Slice(offset, sizeof(uint)));
}
