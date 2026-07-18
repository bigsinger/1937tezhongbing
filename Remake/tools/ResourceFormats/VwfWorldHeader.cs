using System.Text;

namespace Mission1937.Remake.Resources;

public sealed class VwfWorldHeader
{
    public const int HeaderSize = 331;
    public const int GridCellSize = 20;
    private const string Magic = "VWL1 Intuition Engine Virtual World File";
    private const string SceneListMagic = "SLIST1";

    private VwfWorldHeader(
        string path,
        uint viewportWidth,
        uint viewportHeight,
        int viewportLeft,
        int viewportTop,
        int viewportRight,
        int viewportBottom,
        uint gridWidth,
        uint gridHeight,
        uint gridCellParameter,
        long sceneListOffset)
    {
        Path = path;
        ViewportWidth = viewportWidth;
        ViewportHeight = viewportHeight;
        ViewportLeft = viewportLeft;
        ViewportTop = viewportTop;
        ViewportRight = viewportRight;
        ViewportBottom = viewportBottom;
        GridWidth = gridWidth;
        GridHeight = gridHeight;
        GridCellParameter = gridCellParameter;
        SceneListOffset = sceneListOffset;
    }

    public string Path { get; }
    public uint ViewportWidth { get; }
    public uint ViewportHeight { get; }
    public int ViewportLeft { get; }
    public int ViewportTop { get; }
    public int ViewportRight { get; }
    public int ViewportBottom { get; }
    public uint GridWidth { get; }
    public uint GridHeight { get; }
    public uint GridCellParameter { get; }
    public long SceneListOffset { get; }

    public static VwfWorldHeader Open(string path)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(path);
        var fullPath = System.IO.Path.GetFullPath(path);
        using var stream = new FileStream(fullPath, FileMode.Open, FileAccess.Read, FileShare.Read);
        if (stream.Length < HeaderSize + SceneListMagic.Length)
        {
            throw new InvalidDataException("The VWF file is too short.");
        }

        var header = new byte[HeaderSize];
        stream.ReadExactly(header);
        if (!Encoding.ASCII.GetString(header).StartsWith(Magic, StringComparison.Ordinal))
        {
            throw new InvalidDataException("The file does not contain the expected VWL1 header.");
        }

        var viewportWidth = BitConverter.ToUInt32(header, 95);
        var viewportHeight = BitConverter.ToUInt32(header, 99);
        var viewportLeft = BitConverter.ToInt32(header, 103);
        var viewportTop = BitConverter.ToInt32(header, 107);
        var viewportRight = BitConverter.ToInt32(header, 111);
        var viewportBottom = BitConverter.ToInt32(header, 115);
        var gridWidth = BitConverter.ToUInt32(header, 135);
        var gridHeight = BitConverter.ToUInt32(header, 139);
        var gridCellParameter = BitConverter.ToUInt32(header, 143);

        if (gridWidth == 0 || gridHeight == 0 || gridWidth > 16_384 || gridHeight > 16_384)
        {
            throw new InvalidDataException($"Implausible VWF grid dimensions: {gridWidth}x{gridHeight}.");
        }

        var sceneListOffset = checked(HeaderSize + (long)gridWidth * gridHeight * GridCellSize);
        if (sceneListOffset + SceneListMagic.Length > stream.Length)
        {
            throw new InvalidDataException("The VWF grid extends beyond the end of the file.");
        }

        stream.Position = sceneListOffset;
        var sceneListHeader = new byte[SceneListMagic.Length];
        stream.ReadExactly(sceneListHeader);
        if (!Encoding.ASCII.GetString(sceneListHeader).Equals(SceneListMagic, StringComparison.Ordinal))
        {
            throw new InvalidDataException(
                $"Expected SLIST1 at 0x{sceneListOffset:X}, but the marker was not found.");
        }

        return new VwfWorldHeader(
            fullPath,
            viewportWidth,
            viewportHeight,
            viewportLeft,
            viewportTop,
            viewportRight,
            viewportBottom,
            gridWidth,
            gridHeight,
            gridCellParameter,
            sceneListOffset);
    }

    public VwfLevelSummary ToSummary() => new(
        System.IO.Path.GetFileName(Path),
        ViewportWidth,
        ViewportHeight,
        ViewportLeft,
        ViewportTop,
        ViewportRight,
        ViewportBottom,
        GridWidth,
        GridHeight,
        GridCellParameter,
        SceneListOffset);
}
