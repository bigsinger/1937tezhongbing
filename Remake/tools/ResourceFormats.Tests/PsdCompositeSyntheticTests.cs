using System.Buffers.Binary;
using Mission1937.Remake.Resources;

namespace Mission1937.Remake.ResourceFormats.Tests;

internal static class PsdCompositeSyntheticTests
{
    public static int Run(string temporaryDirectory)
    {
        var checks = 0;
        var raw = PsdCompositeImage.Read(new MemoryStream(CreateRawRgbFixture()));
        Equal(2, raw.Width, "raw PSD width", ref checks);
        Equal(2, raw.Height, "raw PSD height", ref checks);
        Equal(3, raw.ChannelCount, "raw PSD channel count", ref checks);
        Equal(false, raw.HasAlphaPlane, "raw PSD alpha flag", ref checks);
        SequenceEqual(
            new byte[]
            {
                255, 0, 0, 255,
                0, 255, 0, 255,
                0, 0, 255, 255,
                255, 255, 255, 255
            },
            raw.Rgba32.Span,
            "raw PSD RGB plane interleave",
            ref checks);

        var rlePath = System.IO.Path.Combine(temporaryDirectory, "synthetic-rle.psd");
        File.WriteAllBytes(rlePath, CreateRleRgbaFixture());
        var rle = PsdCompositeImage.Open(rlePath);
        Equal(3, rle.Width, "RLE PSD width", ref checks);
        Equal(2, rle.Height, "RLE PSD height", ref checks);
        Equal(4, rle.ChannelCount, "RLE PSD channel count", ref checks);
        Equal(true, rle.HasAlphaPlane, "RLE PSD alpha flag", ref checks);
        SequenceEqual(
            new byte[]
            {
                10, 40, 70, 255,
                20, 50, 80, 255,
                30, 60, 90, 255,
                11, 41, 71, 128,
                21, 51, 81, 128,
                31, 61, 91, 128
            },
            rle.Rgba32.Span,
            "RLE PSD RGBA plane interleave",
            ref checks);

        var pngPath = System.IO.Path.Combine(temporaryDirectory, "synthetic-rle.png");
        rle.SavePng(pngPath);
        Equal(true, File.Exists(pngPath), "PSD PNG output exists", ref checks);
        SequenceEqual(
            new byte[] { 137, 80, 78, 71, 13, 10, 26, 10 },
            File.ReadAllBytes(pngPath).AsSpan(0, 8),
            "PSD PNG signature",
            ref checks);

        var truncated = CreateRleRgbaFixture()[..^1];
        Throws<InvalidDataException>(
            () => PsdCompositeImage.Read(new MemoryStream(truncated)),
            "truncated RLE PSD rejection",
            ref checks);
        var unsupported = CreateRawRgbFixture();
        BinaryPrimitives.WriteUInt16BigEndian(unsupported.AsSpan(22, 2), 16);
        Throws<InvalidDataException>(
            () => PsdCompositeImage.Read(new MemoryStream(unsupported)),
            "unsupported PSD depth rejection",
            ref checks);
        return checks;
    }

    private static byte[] CreateRawRgbFixture()
    {
        var planes = new byte[]
        {
            255, 0, 0, 255,
            0, 255, 0, 255,
            0, 0, 255, 255
        };
        using var stream = new MemoryStream();
        WriteHeader(stream, channels: 3, width: 2, height: 2);
        WriteUInt16(stream, 0);
        stream.Write(planes);
        return stream.ToArray();
    }

    private static byte[] CreateRleRgbaFixture()
    {
        byte[][] rows =
        [
            [2, 10, 20, 30], [2, 11, 21, 31],
            [2, 40, 50, 60], [2, 41, 51, 61],
            [2, 70, 80, 90], [2, 71, 81, 91],
            [254, 255], [254, 128]
        ];
        using var stream = new MemoryStream();
        WriteHeader(stream, channels: 4, width: 3, height: 2);
        WriteUInt16(stream, 1);
        foreach (var row in rows)
        {
            WriteUInt16(stream, checked((ushort)row.Length));
        }
        foreach (var row in rows)
        {
            stream.Write(row);
        }
        return stream.ToArray();
    }

    private static void WriteHeader(
        Stream stream,
        ushort channels,
        uint width,
        uint height)
    {
        stream.Write("8BPS"u8);
        WriteUInt16(stream, 1);
        stream.Write(new byte[6]);
        WriteUInt16(stream, channels);
        WriteUInt32(stream, height);
        WriteUInt32(stream, width);
        WriteUInt16(stream, 8);
        WriteUInt16(stream, 3);
        WriteUInt32(stream, 0);
        WriteUInt32(stream, 0);
        WriteUInt32(stream, 0);
    }

    private static void WriteUInt16(Stream stream, ushort value)
    {
        Span<byte> bytes = stackalloc byte[2];
        BinaryPrimitives.WriteUInt16BigEndian(bytes, value);
        stream.Write(bytes);
    }

    private static void WriteUInt32(Stream stream, uint value)
    {
        Span<byte> bytes = stackalloc byte[4];
        BinaryPrimitives.WriteUInt32BigEndian(bytes, value);
        stream.Write(bytes);
    }

    private static void Equal<T>(T expected, T actual, string description, ref int checks)
    {
        checks++;
        if (!EqualityComparer<T>.Default.Equals(expected, actual))
        {
            throw new InvalidOperationException(
                $"{description}: expected '{expected}', actual '{actual}'.");
        }
    }

    private static void SequenceEqual(
        ReadOnlySpan<byte> expected,
        ReadOnlySpan<byte> actual,
        string description,
        ref int checks)
    {
        checks++;
        if (!expected.SequenceEqual(actual))
        {
            throw new InvalidOperationException($"{description}: byte sequences differ.");
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
