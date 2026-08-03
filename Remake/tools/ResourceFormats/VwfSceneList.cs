using System.Buffers.Binary;
using System.Text;

namespace Mission1937.Remake.Resources;

public sealed record VwfGridPoint(uint X, uint Y);

public sealed record VwfAuxiliaryEntry(
    uint ItemId,
    uint Quantity,
    uint QuantityMode);

/// <summary>
/// Version-5 SLIST actor-state fields in their serialized order. The original
/// loader writes these values to non-contiguous RuntimeActorV1 offsets; names
/// below use the runtime semantics that have been proven. Unknown slots keep
/// their destination offset instead of receiving a speculative meaning.
/// </summary>
public enum VwfActorExtendedFieldV5
{
    RouteUpdateActive = 0,
    ContactState = 1,
    DefaultAttackType = 2,
    CurrentHitPoints = 3,
    HiddenOrRemoved = 4,
    TimedActionLimit = 5,
    TimedActionCounter = 6,
    BurialOrDisguiseTransitionReady = 7,
    TimedActionProgressActive = 8,
    HypnosisActive = 9,
    PursuitActorSceneIndex = 10,
    WorldPickupQuantity = 11,
    CorpseDiscovered = 12,
    TargetLost = 13,
    MovementActive = 14,
    CoordinateMoveCommandActive = 15,
    MovementPathState = 16,
    MovementMode = 17,
    ResolvedGoalX = 18,
    UnknownRuntime21C = 19,
    ResolvedGoalY = 20,
    SearchDelayLimit = 21,
    SearchDelayCounter = 22,
    ReactionState = 23,
    SearchWanderStepCounter = 24,
    PoisonActive = 25,
    PoisonCounter = 26,
    PoisonCounterLimit = 27,
    HypnosisCounterLimit = 28,
    HypnosisCounter = 29,
    UnknownRuntime274 = 30,
    NavigationOccupancyEnabled = 31,
    StationaryRouteFacingDirection = 32,
    StationaryRouteFacingRestoreEnabled = 33,
    BurialActionStarted = 34,
    DisguiseChangePending = 35,
    PathOverrideOrSpecialAttentionHold = 36,
    DisguiseRecoveryActive = 37,
    DisguiseRecoveryLimit = 38,
    DisguiseRecoveryOrPursuitDelayCounter = 39,
    EscortRecruitmentCompleted = 40,
}

public static class VwfActorExtendedLayoutV5
{
    public const int FieldCount = 41;
    public const int ReservedTailFieldCount = 24;

    /// <summary>
    /// RuntimeActorV1 byte destinations used by M1937.exe sub_453FE0.
    /// </summary>
    public static IReadOnlyList<int> RuntimeOffsets { get; } =
    [
        0x184, 0x250, 0x20C, 0x1C0, 0x03C, 0x1C4, 0x1C8,
        0x1CC, 0x1D0, 0x238, 0x240, 0x244, 0x258, 0x254,
        0x1D8, 0x1E0, 0x1FC, 0x208, 0x218, 0x21C, 0x220,
        0x248, 0x24C, 0x25C, 0x260, 0x264, 0x268, 0x26C,
        0x278, 0x27C, 0x274, 0x1B0, 0x284, 0x280, 0x288,
        0x28C, 0x290, 0x294, 0x298, 0x29C, 0x1DC,
    ];
}

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
    IReadOnlyList<uint> ExtendedReservedTailFields,
    IReadOnlyList<IReadOnlyList<VwfAuxiliaryEntry>> AuxiliaryArrays,
    VwfPatrolData? Patrol,
    DblEntry? DatabaseEntry)
{
    public bool HasExtendedData => ExtendedDataPresence != 0;
    public uint RouteUpdateActive => ExtendedField(VwfActorExtendedFieldV5.RouteUpdateActive);
    public uint ContactState => ExtendedField(VwfActorExtendedFieldV5.ContactState);
    public uint DefaultAttackType => ExtendedField(VwfActorExtendedFieldV5.DefaultAttackType);
    public uint CurrentHitPoints => ExtendedField(VwfActorExtendedFieldV5.CurrentHitPoints);
    public uint HiddenOrRemoved => ExtendedField(VwfActorExtendedFieldV5.HiddenOrRemoved);
    public uint TimedActionLimit => ExtendedField(VwfActorExtendedFieldV5.TimedActionLimit);
    public uint TimedActionCounter => ExtendedField(VwfActorExtendedFieldV5.TimedActionCounter);
    public uint BurialOrDisguiseTransitionReady =>
        ExtendedField(VwfActorExtendedFieldV5.BurialOrDisguiseTransitionReady);
    public uint TimedActionProgressActive =>
        ExtendedField(VwfActorExtendedFieldV5.TimedActionProgressActive);
    public uint HypnosisActive => ExtendedField(VwfActorExtendedFieldV5.HypnosisActive);
    public int PursuitActorSceneIndex =>
        SignedExtendedField(VwfActorExtendedFieldV5.PursuitActorSceneIndex);
    public uint WorldPickupQuantity =>
        ExtendedField(VwfActorExtendedFieldV5.WorldPickupQuantity);
    public uint CorpseDiscovered => ExtendedField(VwfActorExtendedFieldV5.CorpseDiscovered);
    public uint TargetLost => ExtendedField(VwfActorExtendedFieldV5.TargetLost);
    public uint MovementActive => ExtendedField(VwfActorExtendedFieldV5.MovementActive);
    public uint CoordinateMoveCommandActive =>
        ExtendedField(VwfActorExtendedFieldV5.CoordinateMoveCommandActive);
    public uint MovementPathState => ExtendedField(VwfActorExtendedFieldV5.MovementPathState);
    public uint MovementMode => ExtendedField(VwfActorExtendedFieldV5.MovementMode);
    public int ResolvedGoalX => SignedExtendedField(VwfActorExtendedFieldV5.ResolvedGoalX);
    public int ResolvedGoalY => SignedExtendedField(VwfActorExtendedFieldV5.ResolvedGoalY);
    public uint SearchDelayLimit => ExtendedField(VwfActorExtendedFieldV5.SearchDelayLimit);
    public uint SearchDelayCounter => ExtendedField(VwfActorExtendedFieldV5.SearchDelayCounter);
    public uint ReactionState => ExtendedField(VwfActorExtendedFieldV5.ReactionState);
    public uint SearchWanderStepCounter =>
        ExtendedField(VwfActorExtendedFieldV5.SearchWanderStepCounter);
    public uint PoisonActive => ExtendedField(VwfActorExtendedFieldV5.PoisonActive);
    public uint PoisonCounter => ExtendedField(VwfActorExtendedFieldV5.PoisonCounter);
    public uint PoisonCounterLimit => ExtendedField(VwfActorExtendedFieldV5.PoisonCounterLimit);
    public uint HypnosisCounterLimit => ExtendedField(VwfActorExtendedFieldV5.HypnosisCounterLimit);
    public uint HypnosisCounter => ExtendedField(VwfActorExtendedFieldV5.HypnosisCounter);
    public uint NavigationOccupancyEnabled =>
        ExtendedField(VwfActorExtendedFieldV5.NavigationOccupancyEnabled);
    public uint StationaryRouteFacingDirection =>
        ExtendedField(VwfActorExtendedFieldV5.StationaryRouteFacingDirection);
    public uint StationaryRouteFacingRestoreEnabled =>
        ExtendedField(VwfActorExtendedFieldV5.StationaryRouteFacingRestoreEnabled);
    public uint BurialActionStarted => ExtendedField(VwfActorExtendedFieldV5.BurialActionStarted);
    public uint DisguiseChangePending => ExtendedField(VwfActorExtendedFieldV5.DisguiseChangePending);
    public uint PathOverrideOrSpecialAttentionHold =>
        ExtendedField(VwfActorExtendedFieldV5.PathOverrideOrSpecialAttentionHold);
    public uint DisguiseRecoveryActive =>
        ExtendedField(VwfActorExtendedFieldV5.DisguiseRecoveryActive);
    public uint DisguiseRecoveryLimit =>
        ExtendedField(VwfActorExtendedFieldV5.DisguiseRecoveryLimit);
    public uint DisguiseRecoveryOrPursuitDelayCounter =>
        ExtendedField(VwfActorExtendedFieldV5.DisguiseRecoveryOrPursuitDelayCounter);
    public uint EscortRecruitmentCompleted =>
        ExtendedField(VwfActorExtendedFieldV5.EscortRecruitmentCompleted);
    public IReadOnlyList<uint> AuxiliaryArrayLengths =>
        AuxiliaryArrays
            .Select(array => checked((uint)array.Count))
            .ToArray();

    public uint ExtendedField(VwfActorExtendedFieldV5 field) =>
        ExtendedFields[checked((int)field)];

    public int SignedExtendedField(VwfActorExtendedFieldV5 field) =>
        unchecked((int)ExtendedField(field));
}

public sealed class VwfSceneList
{
    public const int HeaderSize = 137;
    public const uint SupportedFormatVersion = 2;
    public const uint SupportedEntityVersion = 5;
    public const uint SupportedPatrolVersion = 1;
    public const uint PatrolSignature = 1001;
    public const int EntityPrefixSize = 200;
    public const int EntityDirectionOffset = 44;
    public const int EntityWorldXOffset = 60;
    public const int EntityWorldYOffset = 64;
    public const int EntityReferenceXOffset = 104;
    public const int EntityReferenceYOffset = 112;
    public const int EntityPatrolPresenceOffset = EntityPrefixSize;
    public const int EntityPatrolRecordOffset =
        EntityPatrolPresenceOffset + sizeof(uint);

    private const string Magic = "SLIST1 U.M.E Guowei 2000\0";
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
        if (formatVersion != SupportedFormatVersion)
        {
            throw new InvalidDataException(
                $"Unsupported SLIST1 format version {formatVersion}.");
        }
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
        var prefix = reader.ReadSpan(
            EntityPrefixSize, $"SLIST1 entity {sceneIndex} prefix");
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
            VwfActorExtendedLayoutV5.FieldCount,
            $"SLIST1 entity {sceneIndex} extended fields");
        // The executable reads these 24 values into a temporary and discards
        // them. Retain them so format inspection and future round-tripping do
        // not silently lose source bytes even though they have no runtime
        // destination in the supported executable.
        var extendedReservedTailFields = reader.ReadUInt32Array(
            VwfActorExtendedLayoutV5.ReservedTailFieldCount,
            $"SLIST1 entity {sceneIndex} extended reserved tail");

        IReadOnlyList<VwfAuxiliaryEntry>[] auxiliaryArrays =
            new IReadOnlyList<VwfAuxiliaryEntry>[4];
        for (var arrayIndex = 0; arrayIndex < auxiliaryArrays.Length; arrayIndex++)
        {
            if (!reader.ReadPresence($"SLIST1 entity {sceneIndex} auxiliary array {arrayIndex}"))
            {
                auxiliaryArrays[arrayIndex] = Array.Empty<VwfAuxiliaryEntry>();
                continue;
            }

            var length = reader.ReadUInt32(
                $"SLIST1 entity {sceneIndex} auxiliary array {arrayIndex} length");
            _ = CheckedByteCount(
                length,
                12,
                $"SLIST1 entity {sceneIndex} auxiliary array {arrayIndex}");
            var entries = new VwfAuxiliaryEntry[checked((int)length)];
            var itemIds = reader.ReadUInt32Array(
                entries.Length,
                $"SLIST1 entity {sceneIndex} auxiliary array {arrayIndex} item IDs");
            var quantities = reader.ReadUInt32Array(
                entries.Length,
                $"SLIST1 entity {sceneIndex} auxiliary array {arrayIndex} quantities");
            var quantityModes = reader.ReadUInt32Array(
                entries.Length,
                $"SLIST1 entity {sceneIndex} auxiliary array {arrayIndex} quantity modes");
            for (var entryIndex = 0; entryIndex < entries.Length; entryIndex++)
            {
                entries[entryIndex] = new VwfAuxiliaryEntry(
                    itemIds[entryIndex],
                    quantities[entryIndex],
                    quantityModes[entryIndex]);
            }
            auxiliaryArrays[arrayIndex] = entries;
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
            extendedReservedTailFields,
            auxiliaryArrays,
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
