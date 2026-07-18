using System.Buffers.Binary;

namespace Mission1937.Remake.Resources;

public static class Rgb565
{
    public static byte[] ToRgba32(ReadOnlySpan<byte> pixels)
    {
        if ((pixels.Length & 1) != 0)
        {
            throw new ArgumentException("An RGB565 buffer must contain complete 16-bit pixels.", nameof(pixels));
        }

        var pixelCount = pixels.Length / sizeof(ushort);
        var rgba32 = new byte[checked(pixelCount * 4)];
        for (var pixelIndex = 0; pixelIndex < pixelCount; pixelIndex++)
        {
            var packed = BinaryPrimitives.ReadUInt16LittleEndian(
                pixels.Slice(pixelIndex * sizeof(ushort), sizeof(ushort)));
            var red = (packed >> 11) & 0x1F;
            var green = (packed >> 5) & 0x3F;
            var blue = packed & 0x1F;
            var rgbaOffset = pixelIndex * 4;

            // Bit replication preserves both endpoints and is the conventional
            // exact expansion from RGB565 to eight-bit channels.
            rgba32[rgbaOffset] = checked((byte)((red << 3) | (red >> 2)));
            rgba32[rgbaOffset + 1] = checked((byte)((green << 2) | (green >> 4)));
            rgba32[rgbaOffset + 2] = checked((byte)((blue << 3) | (blue >> 2)));
            rgba32[rgbaOffset + 3] = 0xFF;
        }

        return rgba32;
    }
}
