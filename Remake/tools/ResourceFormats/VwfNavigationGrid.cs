using System.Buffers.Binary;
using System.Text;

namespace Mission1937.Remake.Resources;

/// <summary>
/// Semantic VWF grid layers used by the original engine.
/// The names come from the original layer-name table at M1937.exe VA 0x4D276C.
/// </summary>
public enum VwfSemanticLayer : uint
{
    TileIndex = 1,
    LineOfSightObstacle = 2,
    MovementObstacle = 3,
    Event = 4,
    ManualMovementCorrection = 5
}

/// <summary>
/// Portable runtime copy of the four non-rendering VWF grid layers.
/// Values are intentionally kept as 32-bit integers: zero is open, one is a
/// static obstacle, and values beginning at 1000 normally identify an occupying
/// SLIST scene slot as scene_index + 1000.
/// </summary>
public sealed class VwfNavigationGrid
{
    public const uint FormatVersion = 1;
    public const int HeaderSize = 32;
    public const int SemanticLayerCount = 4;

    private static readonly byte[] Magic = Encoding.ASCII.GetBytes("M37NAV1\0");
    private static readonly VwfSemanticLayer[] SerializedLayers =
    [
        VwfSemanticLayer.LineOfSightObstacle,
        VwfSemanticLayer.MovementObstacle,
        VwfSemanticLayer.Event,
        VwfSemanticLayer.ManualMovementCorrection
    ];

    private readonly IReadOnlyDictionary<VwfSemanticLayer, IReadOnlyList<uint>> layers;

    private VwfNavigationGrid(
        uint width,
        uint height,
        uint cellWidth,
        uint cellHeight,
        IReadOnlyDictionary<VwfSemanticLayer, IReadOnlyList<uint>> layers)
    {
        Width = width;
        Height = height;
        CellWidth = cellWidth;
        CellHeight = cellHeight;
        this.layers = layers;
    }

    public uint Width { get; }
    public uint Height { get; }
    public uint CellWidth { get; }
    public uint CellHeight { get; }
    public int CellCount => checked((int)(Width * Height));

    public static VwfNavigationGrid FromTerrain(
        VwfTerrainGrid terrain,
        uint cellWidth,
        uint cellHeight)
    {
        ArgumentNullException.ThrowIfNull(terrain);
        if (cellWidth == 0 || cellHeight == 0)
        {
            throw new ArgumentOutOfRangeException(
                nameof(cellWidth),
                "Navigation cell dimensions must be positive.");
        }

        var copiedLayers = new Dictionary<VwfSemanticLayer, IReadOnlyList<uint>>();
        foreach (var semanticLayer in SerializedLayers)
        {
            var source = terrain.Layers[checked((int)semanticLayer - 1)];
            if (source.Id != (uint)semanticLayer)
            {
                throw new InvalidDataException(
                    $"VWF layer {semanticLayer} has unexpected source ID {source.Id}.");
            }
            copiedLayers.Add(semanticLayer, Array.AsReadOnly(source.Values.ToArray()));
        }

        return Create(terrain.Width, terrain.Height, cellWidth, cellHeight, copiedLayers);
    }

    public static VwfNavigationGrid Create(
        uint width,
        uint height,
        uint cellWidth,
        uint cellHeight,
        IReadOnlyDictionary<VwfSemanticLayer, IReadOnlyList<uint>> layers)
    {
        ArgumentNullException.ThrowIfNull(layers);
        if (width == 0 || height == 0 || cellWidth == 0 || cellHeight == 0)
        {
            throw new ArgumentOutOfRangeException(
                nameof(width),
                "Navigation dimensions and cell dimensions must be positive.");
        }

        var cellCountValue = checked((long)width * height);
        if (cellCountValue > int.MaxValue)
        {
            throw new InvalidDataException("The navigation grid is too large.");
        }
        var cellCount = checked((int)cellCountValue);
        var copiedLayers = new Dictionary<VwfSemanticLayer, IReadOnlyList<uint>>();
        foreach (var semanticLayer in SerializedLayers)
        {
            if (!layers.TryGetValue(semanticLayer, out var values) || values.Count != cellCount)
            {
                throw new InvalidDataException(
                    $"Navigation layer {semanticLayer} must contain exactly {cellCount} cells.");
            }
            copiedLayers.Add(semanticLayer, Array.AsReadOnly(values.ToArray()));
        }

        return new VwfNavigationGrid(width, height, cellWidth, cellHeight, copiedLayers);
    }

    public IReadOnlyList<uint> GetLayer(VwfSemanticLayer layer)
    {
        if (!layers.TryGetValue(layer, out var values))
        {
            throw new ArgumentOutOfRangeException(nameof(layer), layer, "The layer is not a runtime obstacle layer.");
        }
        return values;
    }

    public uint GetValue(VwfSemanticLayer layer, uint x, uint y)
    {
        if (x >= Width)
        {
            throw new ArgumentOutOfRangeException(nameof(x));
        }
        if (y >= Height)
        {
            throw new ArgumentOutOfRangeException(nameof(y));
        }
        return GetLayer(layer)[checked((int)(y * Width + x))];
    }

    public bool IsBlocked(VwfSemanticLayer layer, uint x, uint y, int ignoredSceneIndex = -1)
    {
        var value = GetValue(layer, x, y);
        if (value == 0)
        {
            return false;
        }
        return ignoredSceneIndex < 0 || value != checked((uint)(ignoredSceneIndex + 1000));
    }

    public static int? OccupyingSceneIndex(uint value)
    {
        if (value < 1000 || value - 1000 > int.MaxValue)
        {
            return null;
        }
        return checked((int)(value - 1000));
    }

    public void Save(string path)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(path);
        var fullPath = System.IO.Path.GetFullPath(path);
        Directory.CreateDirectory(System.IO.Path.GetDirectoryName(fullPath)!);
        using var stream = new FileStream(fullPath, FileMode.Create, FileAccess.Write, FileShare.None);
        Write(stream);
    }

    public void Write(Stream destination)
    {
        ArgumentNullException.ThrowIfNull(destination);
        if (!destination.CanWrite)
        {
            throw new ArgumentException("The navigation destination is not writable.", nameof(destination));
        }

        destination.Write(Magic);
        Span<byte> valueBuffer = stackalloc byte[4];
        WriteUInt32(destination, valueBuffer, FormatVersion);
        WriteUInt32(destination, valueBuffer, Width);
        WriteUInt32(destination, valueBuffer, Height);
        WriteUInt32(destination, valueBuffer, CellWidth);
        WriteUInt32(destination, valueBuffer, CellHeight);
        WriteUInt32(destination, valueBuffer, SemanticLayerCount);
        foreach (var semanticLayer in SerializedLayers)
        {
            WriteUInt32(destination, valueBuffer, (uint)semanticLayer);
            foreach (var value in GetLayer(semanticLayer))
            {
                WriteUInt32(destination, valueBuffer, value);
            }
        }
    }

    public static VwfNavigationGrid Open(string path)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(path);
        using var stream = new FileStream(
            System.IO.Path.GetFullPath(path),
            FileMode.Open,
            FileAccess.Read,
            FileShare.Read);
        return Read(stream);
    }

    public static VwfNavigationGrid Read(Stream source)
    {
        ArgumentNullException.ThrowIfNull(source);
        if (!source.CanRead)
        {
            throw new ArgumentException("The navigation source is not readable.", nameof(source));
        }

        Span<byte> magic = stackalloc byte[Magic.Length];
        ReadExactly(source, magic, "navigation magic");
        if (!magic.SequenceEqual(Magic))
        {
            throw new InvalidDataException("The file does not contain an M37NAV1 navigation grid.");
        }

        Span<byte> valueBuffer = stackalloc byte[4];
        var version = ReadUInt32(source, valueBuffer, "navigation format version");
        if (version != FormatVersion)
        {
            throw new InvalidDataException($"Unsupported navigation format version {version}.");
        }
        var width = ReadUInt32(source, valueBuffer, "navigation width");
        var height = ReadUInt32(source, valueBuffer, "navigation height");
        var cellWidth = ReadUInt32(source, valueBuffer, "navigation cell width");
        var cellHeight = ReadUInt32(source, valueBuffer, "navigation cell height");
        var layerCount = ReadUInt32(source, valueBuffer, "navigation layer count");
        if (layerCount != SemanticLayerCount)
        {
            throw new InvalidDataException(
                $"Navigation layer count is {layerCount}; expected {SemanticLayerCount}.");
        }

        var cellCountValue = checked((long)width * height);
        if (width == 0 || height == 0 || cellWidth == 0 || cellHeight == 0 || cellCountValue > int.MaxValue)
        {
            throw new InvalidDataException("The navigation header contains invalid dimensions.");
        }
        var cellCount = checked((int)cellCountValue);
        var layers = new Dictionary<VwfSemanticLayer, IReadOnlyList<uint>>();
        foreach (var expectedLayer in SerializedLayers)
        {
            var rawLayer = ReadUInt32(source, valueBuffer, "navigation layer identifier");
            if (rawLayer != (uint)expectedLayer)
            {
                throw new InvalidDataException(
                    $"Navigation layer ID is {rawLayer}; expected {(uint)expectedLayer} ({expectedLayer}).");
            }
            var values = new uint[cellCount];
            for (var index = 0; index < values.Length; index++)
            {
                values[index] = ReadUInt32(source, valueBuffer, $"navigation layer {rawLayer} cell {index}");
            }
            layers.Add(expectedLayer, Array.AsReadOnly(values));
        }

        if (source.CanSeek && source.Position != source.Length)
        {
            throw new InvalidDataException("The navigation file contains trailing data.");
        }
        return Create(width, height, cellWidth, cellHeight, layers);
    }

    private static void WriteUInt32(Stream destination, Span<byte> buffer, uint value)
    {
        BinaryPrimitives.WriteUInt32LittleEndian(buffer, value);
        destination.Write(buffer);
    }

    private static uint ReadUInt32(Stream source, Span<byte> buffer, string description)
    {
        ReadExactly(source, buffer, description);
        return BinaryPrimitives.ReadUInt32LittleEndian(buffer);
    }

    private static void ReadExactly(Stream source, Span<byte> buffer, string description)
    {
        try
        {
            source.ReadExactly(buffer);
        }
        catch (EndOfStreamException exception)
        {
            throw new InvalidDataException($"Truncated {description}.", exception);
        }
    }
}
