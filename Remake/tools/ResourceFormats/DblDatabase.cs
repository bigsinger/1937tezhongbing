using System.Buffers.Binary;
using System.Text;

namespace Mission1937.Remake.Resources;

public enum DblEntryKind : uint
{
    Sprite = 1,
    TileGroup = 2
}

public sealed record DblCategory(uint Id, string Name);

public sealed record DblTileGroupMapEntry(ushort MapId, DblEntry DatabaseEntry);

public sealed record DblEntry(
    int Id,
    DblEntryKind Kind,
    string ResourceName,
    string DisplayName,
    uint CategoryId,
    string CategoryName,
    IReadOnlyList<uint> HeaderValues,
    uint ElementCount,
    long RecordOffset,
    int RecordLength)
{
    // Sprite records contain fourteen uint32 values beginning at raw record
    // offset +516. Tile-group records use a different layout and therefore
    // expose an empty collection here.
    public uint? FactionId => HeaderValues.Count == 14 ? HeaderValues[8] : null;
    public uint? TeamId => FactionId;
    public uint? SpecialSensor => HeaderValues.Count == 14 ? HeaderValues[12] : null;
}

public sealed class DblDatabase
{
    public const int HeaderSize = 78;

    private const string Magic = "DBL1 Intuition Engine Database File";
    private static readonly Encoding Gbk = CreateGbkEncoding();

    private DblDatabase(
        string path,
        uint formatVersion,
        IReadOnlyList<DblEntry> entries,
        IReadOnlyList<DblCategory> categories)
    {
        Path = path;
        FormatVersion = formatVersion;
        Entries = entries;
        Categories = categories;
        // VWF terrain uses 0 as empty and a one-based ordinal into DBL kind-2 entries.
        TileGroupMap = entries
            .Where(entry => entry.Kind == DblEntryKind.TileGroup)
            .Select((entry, index) => new DblTileGroupMapEntry(
                checked((ushort)(index + 1)),
                entry))
            .ToArray();
    }

    public string Path { get; }
    public uint FormatVersion { get; }
    public IReadOnlyList<DblEntry> Entries { get; }
    public IReadOnlyList<DblCategory> Categories { get; }
    public IReadOnlyList<DblTileGroupMapEntry> TileGroupMap { get; }

    public DblEntry? ResolveTileGroupMapId(ushort mapId)
    {
        if (mapId == 0)
        {
            return null;
        }

        var index = mapId - 1;
        if (index >= TileGroupMap.Count)
        {
            throw new ArgumentOutOfRangeException(
                nameof(mapId),
                mapId,
                $"The DBL contains only {TileGroupMap.Count} tile groups.");
        }

        return TileGroupMap[index].DatabaseEntry;
    }

    public static DblDatabase Open(string path)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(path);
        var fullPath = System.IO.Path.GetFullPath(path);
        var data = File.ReadAllBytes(fullPath);
        if (data.Length < HeaderSize + 8)
        {
            throw new InvalidDataException("The DBL file is too short.");
        }

        if (!Encoding.ASCII.GetString(data, 0, HeaderSize).StartsWith(Magic, StringComparison.Ordinal))
        {
            throw new InvalidDataException("The file does not contain the expected DBL1 header.");
        }

        var reader = new BufferReader(data, HeaderSize);
        var formatVersion = reader.ReadUInt32("DBL format version");
        var entryCount = reader.ReadCount("DBL entry count", 100_000);
        var pendingEntries = new List<PendingEntry>(entryCount);

        for (var id = 0; id < entryCount; id++)
        {
            var recordOffset = reader.Position;
            var rawKind = reader.ReadUInt32($"DBL entry {id} kind");
            if (!Enum.IsDefined(typeof(DblEntryKind), rawKind))
            {
                throw new InvalidDataException($"Unsupported DBL entry kind {rawKind} at index {id}.");
            }

            var kind = (DblEntryKind)rawKind;
            var resourceName = DecodeShiftedFixedName(reader.ReadSpan(256, $"DBL entry {id} resource name"));
            var displayName = DecodeShiftedFixedName(reader.ReadSpan(256, $"DBL entry {id} display name"));
            IReadOnlyList<uint> headerValues;
            uint elementCount;

            if (kind == DblEntryKind.TileGroup)
            {
                headerValues = Array.Empty<uint>();
                elementCount = reader.ReadUInt32($"DBL tile group {id} element count");
                _ = reader.ReadUInt32($"DBL tile group {id} width");
                _ = reader.ReadUInt32($"DBL tile group {id} height");
                reader.Skip(CheckedByteCount(elementCount, 16, $"DBL tile group {id} elements"));
                reader.Skip(8);
            }
            else
            {
                var spriteHeader = reader.ReadUInt32Array(14, $"DBL sprite {id} header");
                headerValues = spriteHeader;
                elementCount = spriteHeader[4];
                reader.Skip(164);
                for (var elementIndex = 0; elementIndex < elementCount; elementIndex++)
                {
                    SkipSpriteElement(reader, id, elementIndex);
                }
            }

            pendingEntries.Add(new PendingEntry(
                id,
                kind,
                resourceName,
                displayName,
                headerValues,
                elementCount,
                recordOffset,
                checked(reader.Position - recordOffset)));
        }

        var categoryCount = reader.ReadCount("DBL category count", 4_096);
        var categories = new List<DblCategory>(categoryCount);
        for (var id = 0; id < categoryCount; id++)
        {
            categories.Add(new DblCategory(
                checked((uint)id),
                DecodePlainFixedName(reader.ReadSpan(256, $"DBL category {id} name"))));
        }

        var entries = new List<DblEntry>(entryCount);
        foreach (var pending in pendingEntries)
        {
            var categoryId = reader.ReadUInt32($"DBL category map for entry {pending.Id}");
            if (categoryId >= categories.Count)
            {
                throw new InvalidDataException(
                    $"DBL entry {pending.Id} references missing category {categoryId}.");
            }

            entries.Add(new DblEntry(
                pending.Id,
                pending.Kind,
                pending.ResourceName,
                pending.DisplayName,
                categoryId,
                categories[checked((int)categoryId)].Name,
                pending.HeaderValues,
                pending.ElementCount,
                pending.RecordOffset,
                pending.RecordLength));
        }

        if (!reader.AtEnd)
        {
            throw new InvalidDataException(
                $"The DBL parser stopped at 0x{reader.Position:X}, but the file ends at 0x{data.Length:X}.");
        }

        return new DblDatabase(fullPath, formatVersion, entries, categories);
    }

    private static void SkipSpriteElement(BufferReader reader, int entryId, int elementIndex)
    {
        var prefix = $"DBL sprite {entryId} element {elementIndex}";
        var layerCount = reader.ReadUInt32($"{prefix} layer count");
        reader.Skip(36);
        var fields = reader.ReadUInt32Array(9, $"{prefix} fields");
        var width = fields[5];
        var height = fields[6];

        if (layerCount > 0)
        {
            var cellCount = checked((long)width * height);
            var valueCount = checked((cellCount * 2) + width);
            if (valueCount > int.MaxValue / 4)
            {
                throw new InvalidDataException($"{prefix} contains an implausibly large grid.");
            }

            reader.Skip(checked((int)valueCount * 4));
        }

        reader.Skip(4);
    }

    private static int CheckedByteCount(uint count, int stride, string description)
    {
        var byteCount = checked((long)count * stride);
        if (byteCount > int.MaxValue)
        {
            throw new InvalidDataException($"{description} exceed the supported size.");
        }

        return checked((int)byteCount);
    }

    private static string DecodeShiftedFixedName(ReadOnlySpan<byte> source)
    {
        var decoded = new byte[source.Length];
        for (var index = 0; index < source.Length; index++)
        {
            decoded[index] = unchecked((byte)(source[index] - 5));
        }

        return DecodeNullTerminated(decoded);
    }

    private static string DecodePlainFixedName(ReadOnlySpan<byte> source) =>
        DecodeNullTerminated(source);

    private static string DecodeNullTerminated(ReadOnlySpan<byte> source)
    {
        var terminator = source.IndexOf((byte)0);
        var text = terminator >= 0 ? source[..terminator] : source;
        try
        {
            return Gbk.GetString(text);
        }
        catch (DecoderFallbackException exception)
        {
            throw new InvalidDataException("A DBL fixed name is not valid GBK.", exception);
        }
    }

    private static Encoding CreateGbkEncoding()
    {
        Encoding.RegisterProvider(CodePagesEncodingProvider.Instance);
        return Encoding.GetEncoding(
            936,
            EncoderFallback.ExceptionFallback,
            DecoderFallback.ExceptionFallback);
    }

    private sealed record PendingEntry(
        int Id,
        DblEntryKind Kind,
        string ResourceName,
        string DisplayName,
        IReadOnlyList<uint> HeaderValues,
        uint ElementCount,
        int RecordOffset,
        int RecordLength);

    private sealed class BufferReader(byte[] data, int position)
    {
        public int Position { get; private set; } = position;
        public bool AtEnd => Position == data.Length;

        public uint ReadUInt32(string description)
        {
            var value = BinaryPrimitives.ReadUInt32LittleEndian(ReadSpan(4, description));
            return value;
        }

        public int ReadCount(string description, int maximum)
        {
            var value = ReadUInt32(description);
            if (value > maximum)
            {
                throw new InvalidDataException($"Implausible {description}: {value}.");
            }

            return checked((int)value);
        }

        public uint[] ReadUInt32Array(int count, string description)
        {
            var values = new uint[count];
            for (var index = 0; index < values.Length; index++)
            {
                values[index] = ReadUInt32(description);
            }

            return values;
        }

        public ReadOnlySpan<byte> ReadSpan(int length, string description)
        {
            if (length < 0 || Position > data.Length - length)
            {
                throw new InvalidDataException(
                    $"Truncated {description} at 0x{Position:X}; requested {length} bytes.");
            }

            var span = data.AsSpan(Position, length);
            Position += length;
            return span;
        }

        public void Skip(int length) => _ = ReadSpan(length, "DBL data");
    }
}
