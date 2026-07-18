using System.Buffers.Binary;
using System.Text;
using Mission1937.Remake.Resources;

namespace Mission1937.Remake.ResourceFormats.Tests;

internal static class TlgSyntheticTests
{
    public static int Run()
    {
        var checks = 0;
        var fixture = CreateFixture();
        var tileGroup = TlgTileGroup.Read(fixture);

        Equal("synthetic.tlg", tileGroup.InternalName, "TLG1 internal name", ref checks);
        Equal(1, tileGroup.Columns, "TLG1 column count", ref checks);
        Equal(1, tileGroup.Rows, "TLG1 row count", ref checks);
        Equal(1, tileGroup.Regions.Count, "TLG1 tile count", ref checks);
        Equal(2, tileGroup.Regions[0].Width, "TLG1 tile width", ref checks);
        Equal(2, tileGroup.Regions[0].Height, "TLG1 tile height", ref checks);
        Equal(3u, tileGroup.FirstTerrainKind, "TLG1 first terrain kind", ref checks);
        Equal(6u, tileGroup.SecondTerrainKind, "TLG1 second terrain kind", ref checks);
        True(tileGroup.Atlas is not null, "TLG1 embedded atlas presence", ref checks);
        Equal(2, tileGroup.Atlas!.Width, "TLG1 atlas width", ref checks);
        Equal(2, tileGroup.Atlas.Height, "TLG1 atlas height", ref checks);

        byte[] expectedRgba =
        [
            255, 0, 0, 255,
            0, 255, 0, 255,
            0, 0, 255, 255,
            255, 255, 255, 255
        ];
        True(
            tileGroup.Atlas.Rgba32.Span.SequenceEqual(expectedRgba),
            "TLG1 atlas RGB565 decode",
            ref checks);

        var truncated = fixture[..^1];
        Throws<InvalidDataException>(
            () => TlgTileGroup.Read(truncated),
            "truncated TLG1 rejection",
            ref checks);

        return checks;
    }

    private static byte[] CreateFixture()
    {
        const int tileCount = 1;
        const int embeddedOffset = TlgTileGroup.FixedPrefixSize +
                                   (tileCount * TlgTileGroup.TileRegionSize) +
                                   12;
        ushort[] pixels = [0xF800, 0x07E0, 0x001F, 0xFFFF];
        var rgb565 = new byte[pixels.Length * sizeof(ushort)];
        for (var index = 0; index < pixels.Length; index++)
        {
            BinaryPrimitives.WriteUInt16LittleEndian(
                rgb565.AsSpan(index * sizeof(ushort), sizeof(ushort)),
                pixels[index]);
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
        WriteUInt32(fixture, 373, 1);
        WriteUInt32(fixture, 377, 1);
        WriteUInt32(fixture, 381, 0);
        WriteUInt32(fixture, 385, 0);
        WriteUInt32(fixture, 389, 2);
        WriteUInt32(fixture, 393, 2);
        WriteUInt32(fixture, 397, 3);
        WriteUInt32(fixture, 401, 6);
        WriteUInt32(fixture, 405, 1);

        WriteUInt32(fixture, embeddedOffset, 1);
        WriteUInt32(fixture, embeddedOffset + 4, 1);
        WriteUInt32(fixture, embeddedOffset + 8, 2);
        WriteUInt32(fixture, embeddedOffset + 12, 2);
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
