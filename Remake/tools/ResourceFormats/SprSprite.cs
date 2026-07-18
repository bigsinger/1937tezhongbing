using System.Buffers.Binary;
using System.Text;

namespace Mission1937.Remake.Resources;

/// <summary>
/// One animation serial (direction/action group) from a SPR1 resource.
/// Unknown engine-era fields are preserved in file order for later semantic work.
/// </summary>
public sealed record SprFrameGroup(
    uint SerializationVersion,
    IReadOnlyList<int> PrimaryTriplet,
    IReadOnlyList<int> SecondaryTriplet,
    IReadOnlyList<int> TertiaryTriplet,
    IReadOnlyList<int> Parameters,
    IReadOnlyList<int> FirstLookup,
    IReadOnlyList<int> SecondLookup,
    IReadOnlyList<int> RowLookup,
    int TrailingValue,
    IReadOnlyList<IBlockImage> Frames);

/// <summary>
/// Reads all three SPR1 container variants used by Mission 1937.
/// </summary>
public sealed class SprSprite
{
    public const int SignatureSize = 102;
    public const int NameFieldSize = 256;
    public const int ExtendedHeaderValueCount = 50;

    private const string Magic =
        "SPR1 Intuition Engine Professional Sprite File V1.0.0 " +
        "Copyright Unlimited Mirage Entertainment Guowei";

    private SprSprite(
        uint serializationVersion,
        IReadOnlyList<int> headerValues,
        IReadOnlyList<int> extendedHeaderValues,
        string internalName,
        IReadOnlyList<SprFrameGroup> groups)
    {
        SerializationVersion = serializationVersion;
        HeaderValues = headerValues;
        ExtendedHeaderValues = extendedHeaderValues;
        InternalName = internalName;
        Groups = groups;
    }

    public uint SerializationVersion { get; }

    public IReadOnlyList<int> HeaderValues { get; }

    public IReadOnlyList<int> ExtendedHeaderValues { get; }

    public string InternalName { get; }

    public IReadOnlyList<SprFrameGroup> Groups { get; }

    public int FrameCount => Groups.Sum(group => group.Frames.Count);

    public static SprSprite Open(string path)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(path);
        return Read(File.ReadAllBytes(System.IO.Path.GetFullPath(path)));
    }

    public static SprSprite Read(ReadOnlySpan<byte> source)
    {
        if (source.Length < SignatureSize + 24 + NameFieldSize)
        {
            throw new InvalidDataException("The file is shorter than a SPR1 header.");
        }

        ValidateSignature(source);
        var cursor = SignatureSize;
        var serializationVersion = ReadUInt32(source, ref cursor);
        if (serializationVersion is < 1 or > 3)
        {
            throw new InvalidDataException(
                $"SPR1 serialization version {serializationVersion} is unsupported.");
        }

        var headerValues = ReadInt32Array(source, ref cursor, 4);
        var groupCount = ReadCount(source, ref cursor, "frame group count", maximum: 4_096);
        var extendedHeaderValues = serializationVersion > 1
            ? ReadInt32Array(source, ref cursor, ExtendedHeaderValueCount)
            : [];
        var internalName = DecodeName(ReadBytes(source, ref cursor, NameFieldSize));

        var groups = new SprFrameGroup[groupCount];
        for (var groupIndex = 0; groupIndex < groups.Length; groupIndex++)
        {
            groups[groupIndex] = ReadGroup(source, ref cursor, groupIndex);
        }

        if (cursor != source.Length)
        {
            throw new InvalidDataException(
                $"SPR1 contains {source.Length - cursor} trailing bytes.");
        }

        return new SprSprite(
            serializationVersion,
            headerValues,
            extendedHeaderValues,
            internalName,
            groups);
    }

    private static SprFrameGroup ReadGroup(
        ReadOnlySpan<byte> source,
        ref int cursor,
        int groupIndex)
    {
        var serializationVersion = ReadUInt32(source, ref cursor);
        if (serializationVersion is < 1 or > 2)
        {
            throw new InvalidDataException(
                $"SPR1 frame group {groupIndex} uses unsupported version {serializationVersion}.");
        }

        var frameCount = ReadCount(source, ref cursor, "frame count", maximum: 65_536);
        var primaryTriplet = ReadInt32Array(source, ref cursor, 3);
        var secondaryTriplet = serializationVersion >= 2
            ? ReadInt32Array(source, ref cursor, 3)
            : primaryTriplet.ToArray();
        var tertiaryTriplet = ReadInt32Array(source, ref cursor, 3);
        var parameters = ReadInt32Array(source, ref cursor, 9);
        var lookupColumns = parameters[5];
        var lookupRows = parameters[6];
        if (lookupColumns is < 0 or > 4_096 || lookupRows is < 0 or > 4_096)
        {
            throw new InvalidDataException(
                $"SPR1 frame group {groupIndex} has invalid lookup dimensions " +
                $"{lookupColumns}x{lookupRows}.");
        }

        var lookupLength = checked(lookupColumns * lookupRows);
        var firstLookup = ReadInt32Array(source, ref cursor, lookupLength);
        var secondLookup = ReadInt32Array(source, ref cursor, lookupLength);
        var rowLookup = ReadInt32Array(source, ref cursor, lookupColumns);
        var trailingValue = ReadInt32(source, ref cursor);

        var frames = new IBlockImage[frameCount];
        for (var frameIndex = 0; frameIndex < frames.Length; frameIndex++)
        {
            try
            {
                var frame = IBlockImage.ReadEmbedded(
                    source[cursor..],
                    out var consumedBytes);
                cursor = checked(cursor + consumedBytes);
                // Direct-surface SPR frames use RGB565 zero as the legacy
                // DirectDraw source color key. Frames with an explicit alpha
                // plane must retain that plane, including opaque black pixels.
                if (!frame.HasAlphaPlane)
                {
                    _ = frame.ApplyRgbColorKey(0, 0, 0);
                }

                frames[frameIndex] = frame;
            }
            catch (InvalidDataException exception)
            {
                throw new InvalidDataException(
                    $"SPR1 frame group {groupIndex}, frame {frameIndex} is invalid.",
                    exception);
            }
        }

        return new SprFrameGroup(
            serializationVersion,
            primaryTriplet,
            secondaryTriplet,
            tertiaryTriplet,
            parameters,
            firstLookup,
            secondLookup,
            rowLookup,
            trailingValue,
            frames);
    }

    private static void ValidateSignature(ReadOnlySpan<byte> source)
    {
        var magicBytes = Encoding.ASCII.GetBytes(Magic);
        if (magicBytes.Length + 1 != SignatureSize ||
            !source[..magicBytes.Length].SequenceEqual(magicBytes) ||
            source[magicBytes.Length] != 0)
        {
            throw new InvalidDataException("The file does not contain the expected SPR1 header.");
        }
    }

    private static string DecodeName(ReadOnlySpan<byte> encoded)
    {
        var decoded = new byte[encoded.Length];
        for (var index = 0; index < encoded.Length; index++)
        {
            decoded[index] = unchecked((byte)(encoded[index] - 5));
        }

        var length = Array.IndexOf(decoded, (byte)0);
        if (length < 0)
        {
            length = decoded.Length;
        }

        Encoding.RegisterProvider(CodePagesEncodingProvider.Instance);
        var gbk = Encoding.GetEncoding(
            936,
            EncoderFallback.ExceptionFallback,
            DecoderFallback.ExceptionFallback);
        try
        {
            return gbk.GetString(decoded, 0, length);
        }
        catch (DecoderFallbackException exception)
        {
            throw new InvalidDataException("The SPR1 internal name is not valid GBK.", exception);
        }
    }

    private static int ReadCount(
        ReadOnlySpan<byte> source,
        ref int cursor,
        string description,
        int maximum)
    {
        var value = ReadUInt32(source, ref cursor);
        if (value == 0 || value > maximum)
        {
            throw new InvalidDataException(
                $"SPR1 {description} {value} is outside the supported range.");
        }

        return checked((int)value);
    }

    private static int[] ReadInt32Array(ReadOnlySpan<byte> source, ref int cursor, int count)
    {
        if (count < 0)
        {
            throw new InvalidDataException("SPR1 contains a negative array length.");
        }

        var values = new int[count];
        for (var index = 0; index < values.Length; index++)
        {
            values[index] = ReadInt32(source, ref cursor);
        }

        return values;
    }

    private static int ReadInt32(ReadOnlySpan<byte> source, ref int cursor)
    {
        EnsureAvailable(source, cursor, sizeof(int));
        var value = BinaryPrimitives.ReadInt32LittleEndian(source.Slice(cursor, sizeof(int)));
        cursor += sizeof(int);
        return value;
    }

    private static uint ReadUInt32(ReadOnlySpan<byte> source, ref int cursor)
    {
        EnsureAvailable(source, cursor, sizeof(uint));
        var value = BinaryPrimitives.ReadUInt32LittleEndian(source.Slice(cursor, sizeof(uint)));
        cursor += sizeof(uint);
        return value;
    }

    private static ReadOnlySpan<byte> ReadBytes(
        ReadOnlySpan<byte> source,
        ref int cursor,
        int length)
    {
        EnsureAvailable(source, cursor, length);
        var value = source.Slice(cursor, length);
        cursor += length;
        return value;
    }

    private static void EnsureAvailable(ReadOnlySpan<byte> source, int offset, int length)
    {
        if (offset < 0 || length < 0 || offset > source.Length - length)
        {
            throw new InvalidDataException("The SPR1 structure is truncated.");
        }
    }
}
