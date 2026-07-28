using System.Buffers.Binary;
using System.Text;

namespace Mission1937.Remake.Resources;

public static class IBlockImageEncoder
{
    private const string Magic =
        "IBLOCK 1.0.0 Copyright U.M.E 2000";

    public static byte[] EncodeRgb565(
        int width,
        int height,
        ReadOnlySpan<byte> rgb565)
    {
        if (width <= 0 || height <= 0)
        {
            throw new ArgumentOutOfRangeException(
                nameof(width),
                "IBLOCK dimensions must be positive.");
        }
        var required = checked(width * height * sizeof(ushort));
        if (rgb565.Length != required)
        {
            throw new ArgumentException(
                $"RGB565 data has {rgb565.Length} bytes; " +
                $"{required} are required.",
                nameof(rgb565));
        }

        var compressed = Lzo1XEncoder.EncodeRgb565(rgb565);
        var output = new byte[
            checked(IBlockImage.HeaderSize + compressed.Length)];
        Encoding.ASCII.GetBytes(Magic).CopyTo(output, 0);
        Write(output, IBlockImage.SignatureSize + 0, 1);
        Write(output, IBlockImage.SignatureSize + 4, 1);
        Write(output, IBlockImage.WidthOffset, checked((uint)width));
        Write(output, IBlockImage.HeightOffset, checked((uint)height));
        // Direct-surface payload; no separate alpha plane.
        Write(output, IBlockImage.SignatureSize + 20, 1);
        Write(output, IBlockImage.BitsPerPixelOffset, 16);
        Write(
            output,
            IBlockImage.CompressedLengthOffset,
            checked((uint)compressed.Length));
        compressed.CopyTo(
            output.AsSpan(IBlockImage.HeaderSize));

        using var verification = new MemoryStream(
            output, writable: false);
        var decoded = IBlockImage.Read(verification);
        if (decoded.Width != width ||
            decoded.Height != height)
        {
            throw new InvalidDataException(
                "Generated IBLOCK verification failed.");
        }
        return output;
    }

    private static void Write(
        byte[] output,
        int offset,
        uint value) =>
        BinaryPrimitives.WriteUInt32LittleEndian(
            output.AsSpan(offset, sizeof(uint)),
            value);
}
