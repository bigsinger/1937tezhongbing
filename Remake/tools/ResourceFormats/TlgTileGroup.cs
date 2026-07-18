using System.Buffers.Binary;
using System.Text;

namespace Mission1937.Remake.Resources;

/// <summary>
/// A rectangular region in the 4x4 transition atlas stored by a TLG1 file.
/// </summary>
public sealed record TlgTileRegion(int Left, int Top, int Right, int Bottom)
{
    public int Width => checked(Right - Left);

    public int Height => checked(Bottom - Top);
}

/// <summary>
/// Reads the Intuition Engine TLG1 tile-transition container.
/// </summary>
public sealed class TlgTileGroup
{
    public const int SignatureSize = 105;
    public const int NameFieldSize = 256;
    public const int FixedPrefixSize = 381;
    public const int TileRegionSize = 16;

    private const string Magic =
        "TLG1 Intuition Engine Professional TileGroup File V1.0.0 " +
        "Copyright Unlimited Mirage Entertainment Guowei";

    private TlgTileGroup(
        uint serializationVersion,
        uint flags,
        string internalName,
        int columns,
        int rows,
        IReadOnlyList<TlgTileRegion> regions,
        uint firstTerrainKind,
        uint secondTerrainKind,
        IBlockImage? atlas)
    {
        SerializationVersion = serializationVersion;
        Flags = flags;
        InternalName = internalName;
        Columns = columns;
        Rows = rows;
        Regions = regions;
        FirstTerrainKind = firstTerrainKind;
        SecondTerrainKind = secondTerrainKind;
        Atlas = atlas;
    }

    public uint SerializationVersion { get; }

    public uint Flags { get; }

    public string InternalName { get; }

    public int Columns { get; }

    public int Rows { get; }

    public IReadOnlyList<TlgTileRegion> Regions { get; }

    public uint FirstTerrainKind { get; }

    public uint SecondTerrainKind { get; }

    public IBlockImage? Atlas { get; }

    public static TlgTileGroup Open(string path)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(path);
        return Read(File.ReadAllBytes(System.IO.Path.GetFullPath(path)));
    }

    public static TlgTileGroup Read(ReadOnlySpan<byte> source)
    {
        if (source.Length < FixedPrefixSize)
        {
            throw new InvalidDataException("The file is shorter than a TLG1 header.");
        }

        ValidateSignature(source);
        var serializationVersion = ReadUInt32(source, SignatureSize);
        if (serializationVersion != 1)
        {
            throw new InvalidDataException(
                $"TLG1 serialization version {serializationVersion} is unsupported.");
        }

        var flags = ReadUInt32(source, SignatureSize + sizeof(uint));
        var internalName = DecodeName(
            source.Slice(SignatureSize + (2 * sizeof(uint)), NameFieldSize));
        var tileCount = ReadCount(source, 369, "tile region count", maximum: 4_096);
        var columns = ReadCount(source, 373, "column count", maximum: 256);
        var rows = ReadCount(source, 377, "row count", maximum: 256);
        if (tileCount != checked(columns * rows))
        {
            throw new InvalidDataException(
                $"TLG1 declares {tileCount} tile regions for a {columns}x{rows} grid.");
        }

        var cursor = FixedPrefixSize;
        var regionBytes = checked(tileCount * TileRegionSize);
        EnsureAvailable(source, cursor, checked(regionBytes + 12));
        var regions = new TlgTileRegion[tileCount];
        for (var index = 0; index < regions.Length; index++)
        {
            var left = ReadCoordinate(source, cursor, "left");
            var top = ReadCoordinate(source, cursor + 4, "top");
            var right = ReadCoordinate(source, cursor + 8, "right");
            var bottom = ReadCoordinate(source, cursor + 12, "bottom");
            if (right <= left || bottom <= top)
            {
                throw new InvalidDataException(
                    $"TLG1 tile region {index} has inverted or empty bounds.");
            }

            regions[index] = new TlgTileRegion(left, top, right, bottom);
            cursor += TileRegionSize;
        }

        var firstTerrainKind = ReadUInt32(source, cursor);
        var secondTerrainKind = ReadUInt32(source, cursor + 4);
        var hasAtlas = ReadUInt32(source, cursor + 8);
        cursor += 12;
        if (hasAtlas > 1)
        {
            throw new InvalidDataException($"TLG1 has invalid atlas-presence value {hasAtlas}.");
        }

        IBlockImage? atlas = null;
        if (hasAtlas == 1)
        {
            atlas = IBlockImage.ReadEmbedded(source[cursor..], out var consumedBytes);
            cursor = checked(cursor + consumedBytes);
            foreach (var region in regions)
            {
                if (region.Right > atlas.Width || region.Bottom > atlas.Height)
                {
                    throw new InvalidDataException(
                        "A TLG1 tile region extends beyond the embedded atlas.");
                }
            }
        }

        if (cursor != source.Length)
        {
            throw new InvalidDataException(
                $"TLG1 contains {source.Length - cursor} trailing bytes.");
        }

        return new TlgTileGroup(
            serializationVersion,
            flags,
            internalName,
            columns,
            rows,
            regions,
            firstTerrainKind,
            secondTerrainKind,
            atlas);
    }

    private static void ValidateSignature(ReadOnlySpan<byte> source)
    {
        var magicBytes = Encoding.ASCII.GetBytes(Magic);
        if (magicBytes.Length + 1 != SignatureSize ||
            !source[..magicBytes.Length].SequenceEqual(magicBytes) ||
            source[magicBytes.Length] != 0)
        {
            throw new InvalidDataException("The file does not contain the expected TLG1 header.");
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
            throw new InvalidDataException("The TLG1 internal name is not valid GBK.", exception);
        }
    }

    private static int ReadCount(
        ReadOnlySpan<byte> source,
        int offset,
        string description,
        int maximum)
    {
        var value = ReadUInt32(source, offset);
        if (value == 0 || value > maximum)
        {
            throw new InvalidDataException(
                $"TLG1 {description} {value} is outside the supported range.");
        }

        return checked((int)value);
    }

    private static int ReadCoordinate(ReadOnlySpan<byte> source, int offset, string description)
    {
        var value = ReadUInt32(source, offset);
        if (value > 16_384)
        {
            throw new InvalidDataException(
                $"TLG1 {description} coordinate {value} is outside the supported range.");
        }

        return checked((int)value);
    }

    private static uint ReadUInt32(ReadOnlySpan<byte> source, int offset)
    {
        EnsureAvailable(source, offset, sizeof(uint));
        return BinaryPrimitives.ReadUInt32LittleEndian(source.Slice(offset, sizeof(uint)));
    }

    private static void EnsureAvailable(ReadOnlySpan<byte> source, int offset, int length)
    {
        if (offset < 0 || length < 0 || offset > source.Length - length)
        {
            throw new InvalidDataException("The TLG1 structure is truncated.");
        }
    }
}
