using System.Buffers.Binary;
using System.Text;

namespace Mission1937.Remake.Resources;

public sealed record VwfGridPoint(uint X, uint Y);

public sealed record VwfPatrolData(
    uint Signature,
    uint FormatVersion,
    uint CurrentWaypointIndex,
    // The original object persists this value at +0x0C and initializes it to 1.
    // No runtime read proving that it gates patrol execution has been found yet.
    uint PersistentFlag,
    int CachedWaypointWorldX,
    int CachedWaypointWorldY,
    IReadOnlyList<VwfGridPoint> WorkingPoints,
    IReadOnlyList<VwfGridPoint> Waypoints)
{
    // Compatibility aliases for callers written before the runtime field meanings
    // were recovered. These are aliases only: "Enabled" is not a proven semantic
    // interpretation, and the cached coordinate is not a route origin.
    public uint Enabled => PersistentFlag;
    public int OriginX => CachedWaypointWorldX;
    public int OriginY => CachedWaypointWorldY;
}

public sealed record VwfSceneEntity(
    int SceneIndex,
    long RecordOffset,
    int RecordLength,
    uint FormatVersion,
    int DatabaseEntryId,
    uint DirectionIndex,
    uint DeathState,
    uint CrawlState,
    int WorldX,
    int WorldY,
    int ReferenceX,
    int ReferenceY,
    uint ExtendedDataPresence,
    IReadOnlyList<uint> ExtendedFields,
    IReadOnlyList<uint> AuxiliaryArrayLengths,
    VwfPatrolData? Patrol,
    DblEntry? DatabaseEntry)
{
    public bool HasExtendedData => ExtendedDataPresence != 0;
    public uint ReactionState => ExtendedFields[1];
    public uint DefaultAttackType => ExtendedFields[2];
    public uint CurrentHitPoints => ExtendedFields[3];
}

public sealed class VwfSceneList
{
    public const int HeaderSize = 137;

    private const string Magic = "SLIST1 U.M.E Guowei 2000\0";
    private const uint SupportedEntityVersion = 5;
    private const uint PatrolSignature = 1001;
    private const uint SupportedPatrolVersion = 1;
    private const int ExtendedFieldCount = 41;
    private const int ExtendedTailByteCount = 24 * sizeof(uint);

    private VwfSceneList(
        string path,
        long offset,
        uint formatVersion,
        int slotCount,
        uint gridWidth,
        uint gridHeight,
        uint gridCellParameter,
        int viewportLeft,
        int viewportTop,
        int viewportRight,
        int viewportBottom,
        IReadOnlyList<VwfSceneEntity> entities)
    {
        Path = path;
        Offset = offset;
        FormatVersion = formatVersion;
        SlotCount = slotCount;
        GridWidth = gridWidth;
        GridHeight = gridHeight;
        GridCellParameter = gridCellParameter;
        ViewportLeft = viewportLeft;
        ViewportTop = viewportTop;
        ViewportRight = viewportRight;
        ViewportBottom = viewportBottom;
        Entities = entities;
    }

    public string Path { get; }
    public long Offset { get; }
    public uint FormatVersion { get; }
    public int SlotCount { get; }
    public uint GridWidth { get; }
    public uint GridHeight { get; }
    public uint GridCellParameter { get; }
    public int ViewportLeft { get; }
    public int ViewportTop { get; }
    public int ViewportRight { get; }
    public int ViewportBottom { get; }
    public IReadOnlyList<VwfSceneEntity> Entities { get; }
    public int EmptySlotCount => SlotCount - Entities.Count;

    public static VwfSceneList Open(string path, DblDatabase? database = null)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(path);
        var fullPath = System.IO.Path.GetFullPath(path);
        var world = VwfWorldHeader.Open(fullPath);
        var data = File.ReadAllBytes(fullPath);
        var offset = checked((int)world.SceneListOffset);
        if (offset > data.Length - HeaderSize)
        {
            throw new InvalidDataException("The VWF SLIST1 header extends beyond the end of the file.");
        }

        var header = data.AsSpan(offset, HeaderSize);
        if (!header[..Magic.Length].SequenceEqual(Encoding.ASCII.GetBytes(Magic)))
        {
            throw new InvalidDataException("The file does not contain the expected SLIST1 header.");
        }

        var formatVersion = ReadUInt32(header, 25);
        var slotCountValue = ReadUInt32(header, 29);
        if (slotCountValue > 1_000_000)
        {
            throw new InvalidDataException($"Implausible SLIST1 entity slot count: {slotCountValue}.");
        }

        var slotCount = checked((int)slotCountValue);
        var gridWidth = ReadUInt32(header, 109);
        var gridHeight = ReadUInt32(header, 113);
        var gridCellParameter = ReadUInt32(header, 117);
        var viewportLeft = ReadInt32(header, 121);
        var viewportTop = ReadInt32(header, 125);
        var viewportRight = ReadInt32(header, 129);
        var viewportBottom = ReadInt32(header, 133);

        if (gridWidth != world.GridWidth || gridHeight != world.GridHeight)
        {
            throw new InvalidDataException(
                $"SLIST1 grid {gridWidth}x{gridHeight} does not match the VWF grid " +
                $"{world.GridWidth}x{world.GridHeight}.");
        }

        var reader = new BufferReader(data, offset + HeaderSize);
        var entities = new List<VwfSceneEntity>(slotCount);
        for (var sceneIndex = 0; sceneIndex < slotCount; sceneIndex++)
        {
            var present = reader.ReadPresence($"SLIST1 entity slot {sceneIndex}");
            if (!present)
            {
                continue;
            }

            entities.Add(ReadEntity(reader, sceneIndex, database));
        }

        if (!reader.AtEnd)
        {
            throw new InvalidDataException(
                $"The SLIST1 parser stopped at 0x{reader.Position:X}, " +
                $"but the VWF file ends at 0x{data.Length:X}.");
        }

        return new VwfSceneList(
            fullPath,
            world.SceneListOffset,
            formatVersion,
            slotCount,
            gridWidth,
            gridHeight,
            gridCellParameter,
            viewportLeft,
            viewportTop,
            viewportRight,
            viewportBottom,
            entities);
    }

    private static VwfSceneEntity ReadEntity(BufferReader reader, int sceneIndex, DblDatabase? database)
    {
        var recordOffset = reader.Position;
        var prefix = reader.ReadSpan(200, $"SLIST1 entity {sceneIndex} prefix");
        var formatVersion = ReadUInt32(prefix, 0);
        if (formatVersion != SupportedEntityVersion)
        {
            throw new InvalidDataException(
                $"Unsupported SLIST1 entity version {formatVersion} at slot {sceneIndex}.");
        }

        var databaseEntryId = ReadInt32(prefix, 8);
        DblEntry? databaseEntry = null;
        if (database is not null)
        {
            if (databaseEntryId < 0 || databaseEntryId >= database.Entries.Count)
            {
                throw new InvalidDataException(
                    $"SLIST1 entity {sceneIndex} references missing DBL entry {databaseEntryId}.");
            }

            databaseEntry = database.Entries[databaseEntryId];
        }

        var patrol = reader.ReadPresence($"SLIST1 entity {sceneIndex} patrol data")
            ? ReadPatrolData(reader, sceneIndex)
            : null;
        // This uint32 is a presence/enable value in the original actor object,
        // not a serialization version. The following 260 bytes consist of 41
        // actor fields followed by a 24-uint tail. Keeping that exact boundary
        // is essential because the four auxiliary arrays immediately follow it.
        var extendedDataPresence = reader.ReadUInt32(
            $"SLIST1 entity {sceneIndex} extended data presence");
        var extendedFields = reader.ReadUInt32Array(
            ExtendedFieldCount,
            $"SLIST1 entity {sceneIndex} extended fields");
        reader.Skip(
            ExtendedTailByteCount,
            $"SLIST1 entity {sceneIndex} extended data tail");

        var auxiliaryArrayLengths = new uint[4];
        for (var arrayIndex = 0; arrayIndex < auxiliaryArrayLengths.Length; arrayIndex++)
        {
            if (!reader.ReadPresence($"SLIST1 entity {sceneIndex} auxiliary array {arrayIndex}"))
            {
                continue;
            }

            var length = reader.ReadUInt32(
                $"SLIST1 entity {sceneIndex} auxiliary array {arrayIndex} length");
            auxiliaryArrayLengths[arrayIndex] = length;
            reader.Skip(
                CheckedByteCount(length, 12, $"SLIST1 entity {sceneIndex} auxiliary array {arrayIndex}"),
                $"SLIST1 entity {sceneIndex} auxiliary array {arrayIndex}");
        }

        return new VwfSceneEntity(
            sceneIndex,
            recordOffset,
            checked(reader.Position - recordOffset),
            formatVersion,
            databaseEntryId,
            ReadUInt32(prefix, 44),
            ReadUInt32(prefix, 48),
            ReadUInt32(prefix, 56),
            ReadInt32(prefix, 60),
            ReadInt32(prefix, 64),
            ReadInt32(prefix, 104),
            ReadInt32(prefix, 112),
            extendedDataPresence,
            extendedFields,
            auxiliaryArrayLengths,
            patrol,
            databaseEntry);
    }

    private static VwfPatrolData ReadPatrolData(BufferReader reader, int sceneIndex)
    {
        var signature = reader.ReadUInt32($"SLIST1 entity {sceneIndex} patrol signature");
        if (signature != PatrolSignature)
        {
            throw new InvalidDataException(
                $"Unexpected SLIST1 patrol signature {signature} at entity {sceneIndex}.");
        }

        var firstCount = reader.ReadCount($"SLIST1 entity {sceneIndex} patrol point count", 1_000_000);
        var formatVersion = reader.ReadUInt32($"SLIST1 entity {sceneIndex} patrol format version");
        if (formatVersion != SupportedPatrolVersion)
        {
            throw new InvalidDataException(
                $"Unsupported SLIST1 patrol version {formatVersion} at entity {sceneIndex}.");
        }

        var workingPoints = ReadPoints(reader, firstCount, $"SLIST1 entity {sceneIndex} patrol working points");
        var secondCount = reader.ReadCount(
            $"SLIST1 entity {sceneIndex} repeated patrol point count",
            1_000_000);
        if (firstCount != secondCount)
        {
            throw new InvalidDataException(
                $"SLIST1 entity {sceneIndex} patrol counts disagree: {firstCount} and {secondCount}.");
        }

        var currentWaypointIndex = reader.ReadUInt32(
            $"SLIST1 entity {sceneIndex} current patrol waypoint index");
        if (secondCount == 0
            ? currentWaypointIndex != 0
            : currentWaypointIndex >= secondCount)
        {
            throw new InvalidDataException(
                $"SLIST1 entity {sceneIndex} current patrol waypoint index " +
                $"{currentWaypointIndex} is outside a {secondCount}-point route.");
        }
        var persistentFlag = reader.ReadUInt32(
            $"SLIST1 entity {sceneIndex} patrol persistent flag");
        var cachedWaypointWorldX = reader.ReadInt32(
            $"SLIST1 entity {sceneIndex} cached patrol waypoint world X");
        var cachedWaypointWorldY = reader.ReadInt32(
            $"SLIST1 entity {sceneIndex} cached patrol waypoint world Y");
        var waypoints = ReadPoints(reader, secondCount, $"SLIST1 entity {sceneIndex} patrol waypoints");

        return new VwfPatrolData(
            signature,
            formatVersion,
            currentWaypointIndex,
            persistentFlag,
            cachedWaypointWorldX,
            cachedWaypointWorldY,
            workingPoints,
            waypoints);
    }

    private static IReadOnlyList<VwfGridPoint> ReadPoints(
        BufferReader reader,
        int count,
        string description)
    {
        var points = new VwfGridPoint[count];
        for (var index = 0; index < points.Length; index++)
        {
            points[index] = new VwfGridPoint(
                reader.ReadUInt32($"{description} X"),
                reader.ReadUInt32($"{description} Y"));
        }

        return points;
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

    private static uint ReadUInt32(ReadOnlySpan<byte> data, int offset) =>
        BinaryPrimitives.ReadUInt32LittleEndian(data[offset..]);

    private static int ReadInt32(ReadOnlySpan<byte> data, int offset) =>
        BinaryPrimitives.ReadInt32LittleEndian(data[offset..]);

    private sealed class BufferReader(byte[] data, int position)
    {
        public int Position { get; private set; } = position;
        public bool AtEnd => Position == data.Length;

        public uint ReadUInt32(string description) =>
            BinaryPrimitives.ReadUInt32LittleEndian(ReadSpan(4, description));

        public uint[] ReadUInt32Array(int count, string description)
        {
            var values = new uint[count];
            for (var index = 0; index < values.Length; index++)
            {
                values[index] = ReadUInt32($"{description} {index}");
            }

            return values;
        }

        public int ReadInt32(string description) =>
            BinaryPrimitives.ReadInt32LittleEndian(ReadSpan(4, description));

        public int ReadCount(string description, int maximum)
        {
            var value = ReadUInt32(description);
            if (value > maximum)
            {
                throw new InvalidDataException($"Implausible {description}: {value}.");
            }

            return checked((int)value);
        }

        public bool ReadPresence(string description)
        {
            var value = ReadUInt32(description);
            if (value > 1)
            {
                throw new InvalidDataException($"Invalid {description} marker: {value}.");
            }

            return value == 1;
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

        public void Skip(int length, string description) => _ = ReadSpan(length, description);
    }
}
