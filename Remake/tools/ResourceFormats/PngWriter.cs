using System.Buffers.Binary;
using System.IO.Compression;
using System.Text;

namespace Mission1937.Remake.Resources;

public static class PngWriter
{
    private static readonly byte[] Signature =
    [
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A
    ];

    private static readonly uint[] CrcTable = CreateCrcTable();

    public static void WriteRgba32(
        Stream destination,
        int width,
        int height,
        ReadOnlySpan<byte> rgba32)
    {
        ArgumentNullException.ThrowIfNull(destination);
        if (!destination.CanWrite)
        {
            throw new ArgumentException("The PNG destination stream is not writable.", nameof(destination));
        }

        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(width);
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(height);
        var rowByteCount = checked(width * 4);
        var expectedLength = checked(rowByteCount * height);
        if (rgba32.Length != expectedLength)
        {
            throw new ArgumentException(
                $"RGBA buffer has {rgba32.Length} bytes; {expectedLength} are required.",
                nameof(rgba32));
        }

        destination.Write(Signature);

        Span<byte> imageHeader = stackalloc byte[13];
        BinaryPrimitives.WriteUInt32BigEndian(imageHeader, checked((uint)width));
        BinaryPrimitives.WriteUInt32BigEndian(imageHeader[4..], checked((uint)height));
        imageHeader[8] = 8;
        imageHeader[9] = 6;
        imageHeader[10] = 0;
        imageHeader[11] = 0;
        imageHeader[12] = 0;
        WriteChunk(destination, "IHDR", imageHeader);

        using var compressed = new MemoryStream();
        using (var zlib = new ZLibStream(
            compressed,
            CompressionLevel.SmallestSize,
            leaveOpen: true))
        {
            for (var row = 0; row < height; row++)
            {
                zlib.WriteByte(0); // PNG filter method: None.
                zlib.Write(rgba32.Slice(row * rowByteCount, rowByteCount));
            }
        }

        WriteChunk(
            destination,
            "IDAT",
            compressed.GetBuffer().AsSpan(0, checked((int)compressed.Length)));
        WriteChunk(destination, "IEND", ReadOnlySpan<byte>.Empty);
    }

    private static void WriteChunk(Stream destination, string type, ReadOnlySpan<byte> data)
    {
        Span<byte> length = stackalloc byte[4];
        BinaryPrimitives.WriteUInt32BigEndian(length, checked((uint)data.Length));
        destination.Write(length);

        Span<byte> typeBytes = stackalloc byte[4];
        if (Encoding.ASCII.GetBytes(type, typeBytes) != typeBytes.Length)
        {
            throw new ArgumentException(
                "A PNG chunk type must be exactly four ASCII bytes.",
                nameof(type));
        }

        destination.Write(typeBytes);
        destination.Write(data);

        var crc = UpdateCrc(0xFFFF_FFFFu, typeBytes);
        crc = UpdateCrc(crc, data) ^ 0xFFFF_FFFFu;
        Span<byte> checksum = stackalloc byte[4];
        BinaryPrimitives.WriteUInt32BigEndian(checksum, crc);
        destination.Write(checksum);
    }

    private static uint UpdateCrc(uint crc, ReadOnlySpan<byte> data)
    {
        foreach (var value in data)
        {
            crc = CrcTable[(crc ^ value) & 0xFF] ^ (crc >> 8);
        }

        return crc;
    }

    private static uint[] CreateCrcTable()
    {
        var table = new uint[256];
        for (uint index = 0; index < table.Length; index++)
        {
            var value = index;
            for (var bit = 0; bit < 8; bit++)
            {
                value = (value & 1) == 0
                    ? value >> 1
                    : 0xEDB_88320u ^ (value >> 1);
            }

            table[index] = value;
        }

        return table;
    }
}
