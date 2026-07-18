namespace Mission1937.Remake.Resources;

/// <summary>
/// The six terrain identifiers stored in TLG1 transition metadata.
/// </summary>
public enum LegacyTerrainKind : uint
{
    DeepSoil = 1,
    LightSoil = 2,
    Grass = 3,
    SandyGravel = 4,
    EarthAndStone = 5,
    Brick = 6
}

public sealed record TerrainTransition(
    ushort TileGroupMapId,
    string ResourceName,
    LegacyTerrainKind FirstTerrain,
    LegacyTerrainKind SecondTerrain,
    int TileCount);

/// <summary>
/// Resolves the one-based tile-group IDs in a VWF terrain cell to decoded TLG1 atlases.
/// </summary>
public sealed class TerrainTileCatalog
{
    public const int ExpectedColumns = 4;
    public const int ExpectedRows = 4;
    public const int ExpectedTileCount = ExpectedColumns * ExpectedRows;

    private readonly IReadOnlyList<TlgTileGroup> _tileGroups;

    private TerrainTileCatalog(
        IReadOnlyList<TlgTileGroup> tileGroups,
        IReadOnlyList<TerrainTransition> transitions,
        int tileWidth,
        int tileHeight)
    {
        _tileGroups = tileGroups;
        Transitions = transitions;
        TileWidth = tileWidth;
        TileHeight = tileHeight;
    }

    public int TileWidth { get; }

    public int TileHeight { get; }

    public IReadOnlyList<TerrainTransition> Transitions { get; }

    /// <summary>
    /// Matches decoded TLG1 resources to the DBL tile-group table by resource name.
    /// The DBL ordinal becomes the one-based VWF tile-group map ID.
    /// </summary>
    public static TerrainTileCatalog FromDatabase(
        DblDatabase database,
        IEnumerable<TlgTileGroup> tileGroups)
    {
        ArgumentNullException.ThrowIfNull(database);
        ArgumentNullException.ThrowIfNull(tileGroups);

        var groupsByName = new Dictionary<string, TlgTileGroup>(StringComparer.OrdinalIgnoreCase);
        foreach (var group in tileGroups)
        {
            ArgumentNullException.ThrowIfNull(group);
            var normalizedName = NormalizeName(group.InternalName);
            if (!groupsByName.TryAdd(normalizedName, group))
            {
                throw new ArgumentException(
                    $"More than one TLG1 resource is named '{group.InternalName}'.",
                    nameof(tileGroups));
            }
        }

        var orderedGroups = new TlgTileGroup[database.TileGroupMap.Count];
        var usedNames = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var mapping in database.TileGroupMap)
        {
            var normalizedName = NormalizeName(mapping.DatabaseEntry.ResourceName);
            if (!groupsByName.TryGetValue(normalizedName, out var group))
            {
                throw new InvalidDataException(
                    $"DBL tile-group map ID {mapping.MapId} references missing TLG1 " +
                    $"resource '{mapping.DatabaseEntry.ResourceName}'.");
            }

            if (mapping.DatabaseEntry.ElementCount != group.Regions.Count)
            {
                throw new InvalidDataException(
                    $"DBL resource '{mapping.DatabaseEntry.ResourceName}' declares " +
                    $"{mapping.DatabaseEntry.ElementCount} tiles, but its TLG1 contains " +
                    $"{group.Regions.Count}.");
            }

            orderedGroups[mapping.MapId - 1] = group;
            usedNames.Add(normalizedName);
        }

        if (usedNames.Count != groupsByName.Count)
        {
            var unused = groupsByName.Keys
                .Where(name => !usedNames.Contains(name))
                .Order(StringComparer.OrdinalIgnoreCase);
            throw new ArgumentException(
                $"TLG1 resources are not present in the DBL: {string.Join(", ", unused)}.",
                nameof(tileGroups));
        }

        return CreateOrdered(orderedGroups);
    }

    /// <summary>
    /// Creates a catalog from TLG1 resources already arranged in DBL order.
    /// Item zero maps to VWF tile-group ID one.
    /// </summary>
    public static TerrainTileCatalog CreateOrdered(IEnumerable<TlgTileGroup> tileGroups)
    {
        ArgumentNullException.ThrowIfNull(tileGroups);
        var groups = tileGroups.ToArray();
        if (groups.Length == 0)
        {
            throw new ArgumentException("At least one TLG1 tile group is required.", nameof(tileGroups));
        }
        if (groups.Length > ushort.MaxValue)
        {
            throw new ArgumentException("There are too many TLG1 tile groups.", nameof(tileGroups));
        }

        var firstGroup = groups[0]
            ?? throw new ArgumentException("A TLG1 tile group cannot be null.", nameof(tileGroups));
        ValidateGroup(firstGroup, expectedTileWidth: null, expectedTileHeight: null);
        var tileWidth = firstGroup.Regions[0].Width;
        var tileHeight = firstGroup.Regions[0].Height;
        var transitions = new TerrainTransition[groups.Length];

        for (var index = 0; index < groups.Length; index++)
        {
            var group = groups[index]
                ?? throw new ArgumentException("A TLG1 tile group cannot be null.", nameof(tileGroups));
            ValidateGroup(group, tileWidth, tileHeight);
            transitions[index] = new TerrainTransition(
                checked((ushort)(index + 1)),
                group.InternalName,
                ParseTerrainKind(group.FirstTerrainKind, group.InternalName),
                ParseTerrainKind(group.SecondTerrainKind, group.InternalName),
                group.Regions.Count);
        }

        return new TerrainTileCatalog(
            Array.AsReadOnly(groups),
            Array.AsReadOnly(transitions),
            tileWidth,
            tileHeight);
    }

    internal TlgTileGroup ResolveTileGroup(ushort mapId)
    {
        if (mapId == 0 || mapId > _tileGroups.Count)
        {
            throw new InvalidDataException(
                $"VWF terrain references missing tile-group map ID {mapId}; " +
                $"the catalog contains {_tileGroups.Count} groups.");
        }

        return _tileGroups[mapId - 1];
    }

    private static void ValidateGroup(
        TlgTileGroup group,
        int? expectedTileWidth,
        int? expectedTileHeight)
    {
        if (group.Columns != ExpectedColumns ||
            group.Rows != ExpectedRows ||
            group.Regions.Count != ExpectedTileCount)
        {
            throw new InvalidDataException(
                $"TLG1 resource '{group.InternalName}' is {group.Columns}x{group.Rows}; " +
                $"the terrain renderer requires the known 4x4 transition layout.");
        }
        if (group.Atlas is null)
        {
            throw new InvalidDataException(
                $"TLG1 resource '{group.InternalName}' does not contain an image atlas.");
        }

        foreach (var region in group.Regions)
        {
            if ((expectedTileWidth is not null && region.Width != expectedTileWidth) ||
                (expectedTileHeight is not null && region.Height != expectedTileHeight))
            {
                throw new InvalidDataException(
                    $"TLG1 resource '{group.InternalName}' does not use the catalog's " +
                    "uniform tile dimensions.");
            }
        }

        var firstRegion = group.Regions[0];
        if (group.Regions.Any(region =>
                region.Width != firstRegion.Width || region.Height != firstRegion.Height))
        {
            throw new InvalidDataException(
                $"TLG1 resource '{group.InternalName}' contains non-uniform tile regions.");
        }
    }

    private static LegacyTerrainKind ParseTerrainKind(uint value, string resourceName)
    {
        if (!Enum.IsDefined(typeof(LegacyTerrainKind), value))
        {
            throw new InvalidDataException(
                $"TLG1 resource '{resourceName}' references unknown terrain kind {value}.");
        }

        return (LegacyTerrainKind)value;
    }

    private static string NormalizeName(string name)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(name);
        var fileName = System.IO.Path.GetFileName(name);
        return fileName.EndsWith(".tlg", StringComparison.OrdinalIgnoreCase)
            ? fileName[..^4]
            : fileName;
    }
}

public sealed class TerrainRasterImage
{
    private readonly byte[] _rgba32;

    internal TerrainRasterImage(int width, int height, byte[] rgba32)
    {
        Width = width;
        Height = height;
        _rgba32 = rgba32;
    }

    public int Width { get; }

    public int Height { get; }

    public ReadOnlyMemory<byte> Rgba32 => _rgba32;

    public void WritePng(Stream destination) =>
        PngWriter.WriteRgba32(destination, Width, Height, _rgba32);

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
}

/// <summary>
/// Composes the decoded 32x16 TLG1 transition tiles into a top-down RGBA image.
/// </summary>
public static class TerrainRasterizer
{
    public static TerrainRasterImage Rasterize(
        VwfTerrainGrid terrain,
        TerrainTileCatalog catalog)
    {
        ArgumentNullException.ThrowIfNull(terrain);
        var cellCount = checked((int)((long)terrain.Width * terrain.Height));
        var cells = new VwfTerrainCell[cellCount];
        for (uint y = 0; y < terrain.Height; y++)
        {
            for (uint x = 0; x < terrain.Width; x++)
            {
                cells[checked((int)(y * terrain.Width + x))] = terrain.GetCell(x, y);
            }
        }

        return Rasterize(
            checked((int)terrain.Width),
            checked((int)terrain.Height),
            cells,
            catalog);
    }

    public static TerrainRasterImage Rasterize(
        int gridWidth,
        int gridHeight,
        IReadOnlyList<VwfTerrainCell> cells,
        TerrainTileCatalog catalog)
    {
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(gridWidth);
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(gridHeight);
        ArgumentNullException.ThrowIfNull(cells);
        ArgumentNullException.ThrowIfNull(catalog);

        var expectedCellCount = checked(gridWidth * gridHeight);
        if (cells.Count != expectedCellCount)
        {
            throw new ArgumentException(
                $"Terrain cell array has {cells.Count} items; {expectedCellCount} are required.",
                nameof(cells));
        }

        var outputWidth = checked(gridWidth * catalog.TileWidth);
        var outputHeight = checked(gridHeight * catalog.TileHeight);
        var rgba32 = new byte[checked(outputWidth * outputHeight * 4)];

        for (var gridY = 0; gridY < gridHeight; gridY++)
        {
            for (var gridX = 0; gridX < gridWidth; gridX++)
            {
                var cell = cells[(gridY * gridWidth) + gridX];

                // The original runtime checks the high word first. Group zero is
                // deliberately not drawn, even when the low word contains 1..6.
                if (cell.TileGroupMapId == 0)
                {
                    continue;
                }

                var group = catalog.ResolveTileGroup(cell.TileGroupMapId);
                if (cell.TileIndex >= group.Regions.Count)
                {
                    throw new InvalidDataException(
                        $"VWF terrain cell ({gridX}, {gridY}) references tile " +
                        $"{cell.TileIndex} in group {cell.TileGroupMapId}, but the group " +
                        $"contains {group.Regions.Count} tiles.");
                }

                var atlas = group.Atlas!;
                var region = group.Regions[cell.TileIndex];
                for (var row = 0; row < catalog.TileHeight; row++)
                {
                    var sourceOffset = checked(
                        (((region.Top + row) * atlas.Width) + region.Left) * 4);
                    var destinationOffset = checked(
                        ((((gridY * catalog.TileHeight) + row) * outputWidth) +
                         (gridX * catalog.TileWidth)) * 4);
                    atlas.Rgba32.Span
                        .Slice(sourceOffset, catalog.TileWidth * 4)
                        .CopyTo(rgba32.AsSpan(destinationOffset, catalog.TileWidth * 4));
                }
            }
        }

        return new TerrainRasterImage(outputWidth, outputHeight, rgba32);
    }
}
