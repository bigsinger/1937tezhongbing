using System.Buffers.Binary;
using System.IO.Compression;
using System.Text;
using Mission1937.Remake.Resources;

namespace Mission1937.Remake.ResourceFormats.Tests;

internal static class IBlockSyntheticTests
{
    public static int Run(string directory)
    {
        var checks = 0;
        var path = System.IO.Path.Combine(directory, "synthetic.iblock");
        var expectedRgba = new byte[]
        {
            255, 0, 0, 255,
            0, 255, 0, 255,
            0, 0, 255, 255,
            255, 255, 255, 255
        };
        File.WriteAllBytes(
            path,
            CreateFixture(2, 2, [0xF800, 0x07E0, 0x001F, 0xFFFF]));

        var image = IBlockImage.Open(path);
        Equal(2, image.Width, "IBLOCK width", ref checks);
        Equal(2, image.Height, "IBLOCK height", ref checks);
        Equal(16, image.BitsPerPixel, "IBLOCK bit depth", ref checks);
        True(
            image.Rgba32.Span.SequenceEqual(expectedRgba),
            "RGB565 to RGBA conversion",
            ref checks);

        using var png = new MemoryStream();
        image.WritePng(png);
        ValidatePng(png.ToArray(), 2, 2, expectedRgba, ref checks);

        byte[] matchFixture =
        [
            20, (byte)'A', (byte)'B', (byte)'C',
            0xA8, 0x00,
            0x11, 0x00, 0x00
        ];
        var matchOutput = Lzo1XDecoder.Decode(matchFixture, 9);
        True(
            matchOutput.AsSpan().SequenceEqual("ABCABCABC"u8),
            "overlapping LZO1X dictionary match",
            ref checks);

        Throws<InvalidDataException>(
            () => Lzo1XDecoder.Decode([0x11, 0x00, 0x00], 1),
            "LZO1X output length mismatch rejection",
            ref checks);
        Throws<InvalidDataException>(
            () => Lzo1XDecoder.Decode([18, (byte)'A', 0x0C, 0xFF], 3),
            "LZO1X look-behind overrun rejection",
            ref checks);
        Throws<InvalidDataException>(
            () => IBlockImage.Read(new MemoryStream(CreateFixtureWithWrongPayloadLength())),
            "IBLOCK payload length mismatch rejection",
            ref checks);

        var embeddedFixture = CreateFixture(2, 2, [0xF800, 0x07E0, 0x001F, 0xFFFF])
            .AsSpan(IBlockImage.SignatureSize)
            .ToArray();
        Array.Resize(ref embeddedFixture, embeddedFixture.Length + 2);
        var embeddedImage = IBlockImage.ReadEmbedded(embeddedFixture, out var consumedBytes);
        Equal(
            embeddedFixture.Length - 2,
            consumedBytes,
            "embedded IBLOCK consumed byte count",
            ref checks);
        True(
            embeddedImage.Rgba32.Span.SequenceEqual(expectedRgba),
            "embedded IBLOCK decode",
            ref checks);

        return checks;
    }

    private static byte[] CreateFixture(
        int width,
        int height,
        IReadOnlyList<ushort> pixels)
    {
        if (pixels.Count != width * height)
        {
            throw new ArgumentException(
                "Synthetic pixel count does not match its dimensions.",
                nameof(pixels));
        }

        var rgb565 = new byte[pixels.Count * 2];
        for (var index = 0; index < pixels.Count; index++)
        {
            BinaryPrimitives.WriteUInt16LittleEndian(
                rgb565.AsSpan(index * 2, 2),
                pixels[index]);
        }

        if (rgb565.Length is < 4 or > 238)
        {
            throw new ArgumentOutOfRangeException(
                nameof(pixels),
                "The simple literal fixture supports 4..238 bytes.");
        }

        var compressed = new byte[rgb565.Length + 4];
        compressed[0] = checked((byte)(17 + rgb565.Length));
        rgb565.CopyTo(compressed, 1);
        compressed[^3] = 0x11;

        var fixture = new byte[IBlockImage.HeaderSize + compressed.Length];
        Encoding.ASCII
            .GetBytes("IBLOCK 1.0.0 Copyright U.M.E 2000")
            .CopyTo(fixture, 0);
        BinaryPrimitives.WriteUInt32LittleEndian(fixture.AsSpan(34, 4), 1);
        BinaryPrimitives.WriteUInt32LittleEndian(fixture.AsSpan(38, 4), 1);
        BinaryPrimitives.WriteUInt32LittleEndian(
            fixture.AsSpan(42, 4),
            checked((uint)width));
        BinaryPrimitives.WriteUInt32LittleEndian(
            fixture.AsSpan(46, 4),
            checked((uint)height));
        BinaryPrimitives.WriteUInt32LittleEndian(fixture.AsSpan(54, 4), 1);
        BinaryPrimitives.WriteUInt32LittleEndian(fixture.AsSpan(841, 4), 16);
        BinaryPrimitives.WriteUInt32LittleEndian(
            fixture.AsSpan(845, 4),
            checked((uint)compressed.Length));
        compressed.CopyTo(fixture, IBlockImage.HeaderSize);
        return fixture;
    }

    private static byte[] CreateFixtureWithWrongPayloadLength()
    {
        var fixture = CreateFixture(
            2,
            2,
            [0xF800, 0x07E0, 0x001F, 0xFFFF]);
        BinaryPrimitives.WriteUInt32LittleEndian(
            fixture.AsSpan(IBlockImage.CompressedLengthOffset, 4),
            checked((uint)(fixture.Length - IBlockImage.HeaderSize - 1)));
        return fixture;
    }

    private static void ValidatePng(
        ReadOnlySpan<byte> png,
        int expectedWidth,
        int expectedHeight,
        ReadOnlySpan<byte> expectedRgba,
        ref int checks)
    {
        byte[] expectedSignature =
        [
            0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A
        ];
        True(png[..8].SequenceEqual(expectedSignature), "PNG signature", ref checks);

        var cursor = 8;
        byte[]? imageHeader = null;
        using var compressed = new MemoryStream();
        while (cursor < png.Length)
        {
            var length = checked((int)BinaryPrimitives.ReadUInt32BigEndian(
                png.Slice(cursor, 4)));
            cursor += 4;
            var type = Encoding.ASCII.GetString(png.Slice(cursor, 4));
            cursor += 4;
            var data = png.Slice(cursor, length);
            cursor += length + 4; // Data and CRC.
            if (type == "IHDR")
            {
                imageHeader = data.ToArray();
            }
            else if (type == "IDAT")
            {
                compressed.Write(data);
            }
        }

        checks++;
        if (imageHeader is null)
        {
            throw new InvalidOperationException("PNG IHDR presence: expected true.");
        }

        Equal(
            expectedWidth,
            checked((int)BinaryPrimitives.ReadUInt32BigEndian(imageHeader.AsSpan(0, 4))),
            "PNG width",
            ref checks);
        Equal(
            expectedHeight,
            checked((int)BinaryPrimitives.ReadUInt32BigEndian(imageHeader.AsSpan(4, 4))),
            "PNG height",
            ref checks);

        compressed.Position = 0;
        using var zlib = new ZLibStream(compressed, CompressionMode.Decompress);
        using var scanlines = new MemoryStream();
        zlib.CopyTo(scanlines);
        var decoded = scanlines.ToArray();
        var rowBytes = expectedWidth * 4;
        var expectedScanlineLength = expectedHeight * (rowBytes + 1);
        Equal(expectedScanlineLength, decoded.Length, "PNG scanline length", ref checks);
        for (var row = 0; row < expectedHeight; row++)
        {
            Equal(
                (byte)0,
                decoded[row * (rowBytes + 1)],
                "PNG no-filter marker",
                ref checks);
            True(
                decoded.AsSpan((row * (rowBytes + 1)) + 1, rowBytes)
                    .SequenceEqual(expectedRgba.Slice(row * rowBytes, rowBytes)),
                "PNG RGBA scanline",
                ref checks);
        }
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
