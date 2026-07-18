using System.Buffers.Binary;
using System.Text;
using Mission1937.Remake.Resources;

namespace Mission1937.Remake.ResourceFormats.Tests;

internal static class TerrainRasterizerSyntheticTests
{
    public static int Run()
    {
        var checks = 0;
        var group = TlgTileGroup.Read(CreateTileGroupFixture());
        var catalog = TerrainTileCatalog.CreateOrdered([group]);

        Equal(2, catalog.TileWidth, "terrain tile width", ref checks);
        Equal(1, catalog.TileHeight, "terrain tile height", ref checks);
        Equal(1, catalog.Transitions.Count, "terrain transition count", ref checks);
        Equal((ushort)1, catalog.Transitions[0].TileGroupMapId, "one-based tile-group ID", ref checks);
        Equal(LegacyTerrainKind.Grass, catalog.Transitions[0].FirstTerrain, "first terrain kind", ref checks);
        Equal(LegacyTerrainKind.LightSoil, catalog.Transitions[0].SecondTerrain, "second terrain kind", ref checks);

        Equal(1u, (uint)LegacyTerrainKind.DeepSoil, "deep-soil ID", ref checks);
        Equal(2u, (uint)LegacyTerrainKind.LightSoil, "light-soil ID", ref checks);
        Equal(3u, (uint)LegacyTerrainKind.Grass, "grass ID", ref checks);
        Equal(4u, (uint)LegacyTerrainKind.SandyGravel, "sandy-gravel ID", ref checks);
        Equal(5u, (uint)LegacyTerrainKind.EarthAndStone, "earth-and-stone ID", ref checks);
        Equal(6u, (uint)LegacyTerrainKind.Brick, "brick ID", ref checks);

        VwfTerrainCell[] cells =
        [
            new(0, 1, 0, 0, 0, 0),
            new(1, 1, 0, 0, 0, 0),
            new(6, 0, 0, 0, 0, 0),
            new(2, 1, 0, 0, 0, 0)
        ];
        var image = TerrainRasterizer.Rasterize(2, 2, cells, catalog);
        Equal(4, image.Width, "terrain raster width", ref checks);
        Equal(2, image.Height, "terrain raster height", ref checks);

        byte[] expected =
        [
            255, 0, 0, 255, 255, 0, 0, 255,
            0, 255, 0, 255, 0, 255, 0, 255,
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 255, 255, 0, 0, 255, 255
        ];
        True(
            image.Rgba32.Span.SequenceEqual(expected),
            "terrain tiles and transparent group-zero cells",
            ref checks);

        using var png = new MemoryStream();
        image.WritePng(png);
        var pngBytes = png.ToArray();
        byte[] signature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
        True(pngBytes.AsSpan(0, 8).SequenceEqual(signature), "terrain PNG signature", ref checks);
        Equal(4u, BinaryPrimitives.ReadUInt32BigEndian(pngBytes.AsSpan(16, 4)), "terrain PNG width", ref checks);
        Equal(2u, BinaryPrimitives.ReadUInt32BigEndian(pngBytes.AsSpan(20, 4)), "terrain PNG height", ref checks);

        VwfTerrainCell[] missingGroup = [new(0, 2, 0, 0, 0, 0)];
        Throws<InvalidDataException>(
            () => TerrainRasterizer.Rasterize(1, 1, missingGroup, catalog),
            "missing terrain group rejection",
            ref checks);

        VwfTerrainCell[] missingTile = [new(16, 1, 0, 0, 0, 0)];
        Throws<InvalidDataException>(
            () => TerrainRasterizer.Rasterize(1, 1, missingTile, catalog),
            "missing terrain tile rejection",
            ref checks);

        return checks;
    }

    private static byte[] CreateTileGroupFixture()
    {
        const int tileWidth = 2;
        const int tileHeight = 1;
        const int columns = 4;
        const int rows = 4;
        const int tileCount = columns * rows;
        const int atlasWidth = tileWidth * columns;
        const int atlasHeight = tileHeight * rows;
        const int embeddedOffset = TlgTileGroup.FixedPrefixSize +
                                   (tileCount * TlgTileGroup.TileRegionSize) +
                                   12;

        ushort[] tileColors =
        [
            0xF800, 0x07E0, 0x001F, 0xFFFF,
            0x0000, 0xFFE0, 0xF81F, 0x07FF,
            0x8410, 0x4208, 0xC618, 0xA145,
            0x18E3, 0x632C, 0xAD55, 0xEF7D
        ];
        var rgb565 = new byte[atlasWidth * atlasHeight * sizeof(ushort)];
        for (var tileY = 0; tileY < rows; tileY++)
        {
            for (var tileX = 0; tileX < columns; tileX++)
            {
                var color = tileColors[(tileY * columns) + tileX];
                for (var pixelX = 0; pixelX < tileWidth; pixelX++)
                {
                    var pixelOffset =
                        (((tileY * atlasWidth) + (tileX * tileWidth) + pixelX) * sizeof(ushort));
                    BinaryPrimitives.WriteUInt16LittleEndian(
                        rgb565.AsSpan(pixelOffset, sizeof(ushort)),
                        color);
                }
            }
        }

        var compressed = new byte[rgb565.Length + 4];
        compressed[0] = checked((byte)(17 + rgb565.Length));
        rgb565.CopyTo(compressed, 1);
        compressed[^3] = 0x11;

        var fixture = new byte[embeddedOffset + IBlockImage.EmbeddedHeaderSize + compressed.Length];
        Encoding.ASCII
            .GetBytes(
                "TLG1 Intuition Engine Professional TileGroup File V1.0.0 " +
                "Copyright Unlimited Mirage Entertainment Guowei")
            .CopyTo(fixture, 0);
        WriteUInt32(fixture, TlgTileGroup.SignatureSize, 1);

        var nameBytes = Encoding.ASCII.GetBytes("synthetic.tlg");
        fixture.AsSpan(113, TlgTileGroup.NameFieldSize).Fill(5);
        for (var index = 0; index < nameBytes.Length; index++)
        {
            fixture[113 + index] = checked((byte)(nameBytes[index] + 5));
        }

        WriteUInt32(fixture, 369, tileCount);
        WriteUInt32(fixture, 373, columns);
        WriteUInt32(fixture, 377, rows);
        for (var index = 0; index < tileCount; index++)
        {
            var tileX = index % columns;
            var tileY = index / columns;
            var regionOffset = TlgTileGroup.FixedPrefixSize +
                               (index * TlgTileGroup.TileRegionSize);
            WriteUInt32(fixture, regionOffset, checked((uint)(tileX * tileWidth)));
            WriteUInt32(fixture, regionOffset + 4, checked((uint)(tileY * tileHeight)));
            WriteUInt32(fixture, regionOffset + 8, checked((uint)((tileX + 1) * tileWidth)));
            WriteUInt32(fixture, regionOffset + 12, checked((uint)((tileY + 1) * tileHeight)));
        }

        var metadataOffset = TlgTileGroup.FixedPrefixSize +
                             (tileCount * TlgTileGroup.TileRegionSize);
        WriteUInt32(fixture, metadataOffset, (uint)LegacyTerrainKind.Grass);
        WriteUInt32(fixture, metadataOffset + 4, (uint)LegacyTerrainKind.LightSoil);
        WriteUInt32(fixture, metadataOffset + 8, 1);

        WriteUInt32(fixture, embeddedOffset, 1);
        WriteUInt32(fixture, embeddedOffset + 4, 1);
        WriteUInt32(fixture, embeddedOffset + 8, atlasWidth);
        WriteUInt32(fixture, embeddedOffset + 12, atlasHeight);
        WriteUInt32(fixture, embeddedOffset + 20, 1);
        WriteUInt32(fixture, embeddedOffset + 807, 16);
        WriteUInt32(fixture, embeddedOffset + 811, checked((uint)compressed.Length));
        compressed.CopyTo(fixture, embeddedOffset + IBlockImage.EmbeddedHeaderSize);
        return fixture;
    }

    private static void WriteUInt32(byte[] destination, int offset, uint value)
    {
        BinaryPrimitives.WriteUInt32LittleEndian(destination.AsSpan(offset, sizeof(uint)), value);
    }

    private static void Equal<T>(
        T expected,
        T actual,
        string description,
        ref int checks)
    {
        checks++;
        if (!EqualityComparer<T>.Default.Equals(expected, actual))
        {
            throw new InvalidOperationException(
                $"{description}: expected '{expected}', actual '{actual}'.");
        }
    }

    private static void True(bool value, string description, ref int checks)
    {
        checks++;
        if (!value)
        {
            throw new InvalidOperationException($"{description}: expected true.");
        }
    }

    private static void Throws<TException>(
        Action action,
        string description,
        ref int checks)
        where TException : Exception
    {
        checks++;
        try
        {
            action();
        }
        catch (TException)
        {
            return;
        }

        throw new InvalidOperationException(
            $"{description}: expected {typeof(TException).Name}.");
    }
}
