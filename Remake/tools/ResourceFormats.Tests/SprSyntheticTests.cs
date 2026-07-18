using System.Buffers.Binary;
using System.Text;
using Mission1937.Remake.Resources;

namespace Mission1937.Remake.ResourceFormats.Tests;

internal static class SprSyntheticTests
{
    public static int Run()
    {
        var checks = 0;
        var fixture = CreateFixture();
        var sprite = SprSprite.Read(fixture);

        Equal(1u, sprite.SerializationVersion, "SPR1 version", ref checks);
        Equal("synthetic.spr", sprite.InternalName, "SPR1 internal name", ref checks);
        Equal(1, sprite.Groups.Count, "SPR1 frame group count", ref checks);
        Equal(1, sprite.FrameCount, "SPR1 total frame count", ref checks);
        Equal(1, sprite.Groups[0].FirstLookup.Count, "SPR1 first lookup size", ref checks);
        Equal(1, sprite.Groups[0].SecondLookup.Count, "SPR1 second lookup size", ref checks);
        Equal(1, sprite.Groups[0].RowLookup.Count, "SPR1 row lookup size", ref checks);

        var image = sprite.Groups[0].Frames[0];
        Equal(2, image.Width, "SPR1 frame width", ref checks);
        Equal(2, image.Height, "SPR1 frame height", ref checks);
        Equal(false, image.HasAlphaPlane, "SPR1 direct-surface frame mode", ref checks);
        byte[] expectedRgba =
        [
            255, 0, 0, 255,
            0, 255, 0, 255,
            0, 0, 255, 255,
            0, 0, 0, 0
        ];
        True(
            image.Rgba32.Span.SequenceEqual(expectedRgba),
            "SPR1 frame RGB565 decode and black source color key",
            ref checks);

        var alphaSprite = SprSprite.Read(CreateAlphaFixture());
        var alphaImage = alphaSprite.Groups[0].Frames[0];
        Equal(true, alphaImage.HasAlphaPlane, "SPR1 explicit alpha frame mode", ref checks);
        var alphaPixels = alphaImage.Rgba32.Span;
        True(
            new byte[] { 0, 85, 170, 255 }.AsSpan().SequenceEqual(
                new byte[] { alphaPixels[3], alphaPixels[7], alphaPixels[11], alphaPixels[15] }),
            "SPR1 LZO alpha plane decode",
            ref checks);

        byte[] oversizedLiteral = [23, 1, 2, 3, 4, 5, 6, 0x11, 0, 0];
        True(
            Lzo1XDecoder.DecodePrefixWithLegacySlack(oversizedLiteral, 4)
                .AsSpan()
                .SequenceEqual(new byte[] { 1, 2, 3, 4 }),
            "legacy LZO decoded-prefix behavior",
            ref checks);

        Throws<InvalidDataException>(
            () => SprSprite.Read(fixture[..^1]),
            "truncated SPR1 rejection",
            ref checks);

        return checks;
    }

    private static byte[] CreateFixture()
    {
        const int groupOffset = SprSprite.SignatureSize + 24 + SprSprite.NameFieldSize;
        const int groupHeaderSize = 8 + 12 + 12 + 36;
        const int lookupSize = 12;
        const int embeddedOffset = groupOffset + groupHeaderSize + lookupSize + 4;
        ushort[] pixels = [0xF800, 0x07E0, 0x001F, 0x0000];
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
                "SPR1 Intuition Engine Professional Sprite File V1.0.0 " +
                "Copyright Unlimited Mirage Entertainment Guowei")
            .CopyTo(fixture, 0);
        WriteUInt32(fixture, 102, 1);
        WriteUInt32(fixture, 122, 1);

        var nameBytes = Encoding.ASCII.GetBytes("synthetic.spr");
        fixture.AsSpan(126, SprSprite.NameFieldSize).Fill(5);
        for (var index = 0; index < nameBytes.Length; index++)
        {
            fixture[126 + index] = checked((byte)(nameBytes[index] + 5));
        }

        var cursor = groupOffset;
        WriteAndAdvance(fixture, ref cursor, 1); // Group version.
        WriteAndAdvance(fixture, ref cursor, 1); // Frame count.
        WriteAndAdvance(fixture, ref cursor, 2);
        WriteAndAdvance(fixture, ref cursor, 0);
        WriteAndAdvance(fixture, ref cursor, 2);
        WriteAndAdvance(fixture, ref cursor, 1);
        WriteAndAdvance(fixture, ref cursor, 1);
        WriteAndAdvance(fixture, ref cursor, 1);

        // Nine parameters; indexes five and six are lookup columns/rows.
        foreach (var value in new uint[] { 0, 0, 0, 2, 2, 1, 1, 1, 0 })
        {
            WriteAndAdvance(fixture, ref cursor, value);
        }

        WriteAndAdvance(fixture, ref cursor, 0); // First lookup.
        WriteAndAdvance(fixture, ref cursor, 0); // Second lookup.
        WriteAndAdvance(fixture, ref cursor, 0); // Row lookup.
        WriteAndAdvance(fixture, ref cursor, 0); // Trailing value.
        if (cursor != embeddedOffset)
        {
            throw new InvalidOperationException("Synthetic SPR1 offset calculation failed.");
        }

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

    private static byte[] CreateAlphaFixture()
    {
        const int groupOffset = SprSprite.SignatureSize + 24 + SprSprite.NameFieldSize;
        const int embeddedOffset = groupOffset + 68 + 12 + 4;
        byte[] alphaCompressed = [21, 0, 85, 170, 255, 0x11, 0, 0];
        var fixture = CreateFixture();
        var colorEnd = fixture.Length;
        Array.Resize(ref fixture, checked(colorEnd + 8 + alphaCompressed.Length));
        WriteUInt32(fixture, embeddedOffset + 20, 0);
        WriteUInt32(fixture, embeddedOffset + 24, 1);
        WriteUInt32(fixture, colorEnd, 1);
        WriteUInt32(fixture, colorEnd + 4, checked((uint)alphaCompressed.Length));
        alphaCompressed.CopyTo(fixture, colorEnd + 8);
        return fixture;
    }

    private static void WriteAndAdvance(byte[] destination, ref int offset, uint value)
    {
        WriteUInt32(destination, offset, value);
        offset += sizeof(uint);
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
