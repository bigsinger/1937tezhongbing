using System.Buffers.Binary;
using System.Text;

namespace Mission1937.Remake.Resources;

public sealed record VwfTerrainLayer(
    uint Id,
    uint Width,
    uint Height,
    IReadOnlyList<uint> Values);

public readonly record struct VwfTerrainCell(
    ushort TileIndex,
    ushort TileGroupMapId,
    uint Layer2,
    uint Layer3,
    uint Layer4,
    uint Layer5);

public sealed class VwfTerrainGrid
{
    // The five arrays are serialized plane-by-plane. Each has its own 16-byte
    // header; the 331-byte constant in the SLIST1 offset formula includes all
    // five layer headers and the viewport footer, not one interleaved cell.
    public const int PreambleSize = 235;
    public const int LayerCount = 5;
    public const int LayerHeaderSize = 16;
    public const int FooterSize = 16;

    private const string Magic = "VWL1 Intuition Engine Virtual World File";
    private readonly DblDatabase? database;

    private VwfTerrainGrid(
        string path,
        uint width,
        uint height,
        IReadOnlyList<VwfTerrainLayer> layers,
        int localViewportLeft,
        int localViewportTop,
        int localViewportRight,
        int localViewportBottom,
        long sceneListOffset,
        DblDatabase? database)
    {
        Path = path;
        Width = width;
        Height = height;
        Layers = layers;
        LocalViewportLeft = localViewportLeft;
        LocalViewportTop = localViewportTop;
        LocalViewportRight = localViewportRight;
        LocalViewportBottom = localViewportBottom;
        SceneListOffset = sceneListOffset;
        this.database = database;
    }

    public string Path { get; }
    public uint Width { get; }
    public uint Height { get; }
    public IReadOnlyList<VwfTerrainLayer> Layers { get; }
    public int LocalViewportLeft { get; }
    public int LocalViewportTop { get; }
    public int LocalViewportRight { get; }
    public int LocalViewportBottom { get; }
    public long SceneListOffset { get; }

    public static VwfTerrainGrid Open(string path, DblDatabase? database = null)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(path);
        var fullPath = System.IO.Path.GetFullPath(path);
        var world = VwfWorldHeader.Open(fullPath);
        var data = File.ReadAllBytes(fullPath);
        if (data.Length < PreambleSize ||
            !Encoding.ASCII.GetString(data, 0, PreambleSize).StartsWith(Magic, StringComparison.Ordinal))
        {
            throw new InvalidDataException("The file does not contain the expected VWL1 preamble.");
        }

        var cellCountValue = checked((long)world.GridWidth * world.GridHeight);
        if (cellCountValue > int.MaxValue)
        {
            throw new InvalidDataException("The VWF terrain grid is too large to load.");
        }

        var cellCount = checked((int)cellCountValue);
        var reader = new BufferReader(data, PreambleSize);
        var layers = new VwfTerrainLayer[LayerCount];
        for (var layerIndex = 0; layerIndex < layers.Length; layerIndex++)
        {
            var expectedId = checked((uint)(layerIndex + 1));
            var id = reader.ReadUInt32($"VWF terrain layer {expectedId} identifier");
            var width = reader.ReadUInt32($"VWF terrain layer {expectedId} width");
            var height = reader.ReadUInt32($"VWF terrain layer {expectedId} height");
            var count = reader.ReadUInt32($"VWF terrain layer {expectedId} cell count");
            if (id != expectedId || width != world.GridWidth || height != world.GridHeight || count != cellCount)
            {
                throw new InvalidDataException(
                    $"Invalid VWF terrain layer {expectedId} header: " +
                    $"id={id}, size={width}x{height}, count={count}.");
            }

            var values = new uint[cellCount];
            for (var valueIndex = 0; valueIndex < values.Length; valueIndex++)
            {
                values[valueIndex] = reader.ReadUInt32($"VWF terrain layer {expectedId} data");
            }

            layers[layerIndex] = new VwfTerrainLayer(id, width, height, Array.AsReadOnly(values));
        }

        var localViewportLeft = reader.ReadInt32("VWF local viewport left");
        var localViewportTop = reader.ReadInt32("VWF local viewport top");
        var localViewportRight = reader.ReadInt32("VWF local viewport right");
        var localViewportBottom = reader.ReadInt32("VWF local viewport bottom");
        if (reader.Position != world.SceneListOffset)
        {
            throw new InvalidDataException(
                $"The VWF terrain parser stopped at 0x{reader.Position:X}, " +
                $"but SLIST1 starts at 0x{world.SceneListOffset:X}.");
        }

        if (database is not null)
        {
            foreach (var rawCell in layers[0].Values)
            {
                var mapId = checked((ushort)(rawCell >> 16));
                if (mapId > database.TileGroupMap.Count)
                {
                    throw new InvalidDataException(
                        $"The VWF terrain references tile-group map ID {mapId}, " +
                        $"but the DBL contains only {database.TileGroupMap.Count} tile groups.");
                }
            }
        }

        return new VwfTerrainGrid(
            fullPath,
            world.GridWidth,
            world.GridHeight,
            layers,
            localViewportLeft,
            localViewportTop,
            localViewportRight,
            localViewportBottom,
            world.SceneListOffset,
            database);
    }

    public VwfTerrainCell GetCell(uint x, uint y)
    {
        if (x >= Width)
        {
            throw new ArgumentOutOfRangeException(nameof(x));
        }
        if (y >= Height)
        {
            throw new ArgumentOutOfRangeException(nameof(y));
        }

        var index = checked((int)(y * Width + x));
        var firstLayer = Layers[0].Values[index];
        return new VwfTerrainCell(
            checked((ushort)(firstLayer & 0xFFFF)),
            checked((ushort)(firstLayer >> 16)),
            Layers[1].Values[index],
            Layers[2].Values[index],
            Layers[3].Values[index],
            Layers[4].Values[index]);
    }

    public DblEntry? ResolveTileGroup(VwfTerrainCell cell) =>
        database?.ResolveTileGroupMapId(cell.TileGroupMapId);

    private sealed class BufferReader(byte[] data, int position)
    {
        public int Position { get; private set; } = position;

        public uint ReadUInt32(string description) =>
            BinaryPrimitives.ReadUInt32LittleEndian(ReadSpan(4, description));

        public int ReadInt32(string description) =>
            BinaryPrimitives.ReadInt32LittleEndian(ReadSpan(4, description));

        private ReadOnlySpan<byte> ReadSpan(int length, string description)
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
    }
}
