namespace Mission1937.Remake.Resources;

/// <summary>
/// Deterministic LZO1X encoder used for generated RGB565 briefing images.
/// </summary>
/// <remarks>
/// The encoder deliberately uses only literal runs and M3 matches with a
/// two-byte look-behind. RGB565 backgrounds contain long repeating pixel
/// runs, so this small, auditable subset is sufficient without introducing a
/// native compression dependency.
/// </remarks>
public static class Lzo1XEncoder
{
    public static byte[] EncodeRgb565(ReadOnlySpan<byte> source)
    {
        if (source.Length < 4)
        {
            throw new ArgumentOutOfRangeException(
                nameof(source),
                "Generated briefing payloads require at least four bytes.");
        }

        using var output = new MemoryStream(source.Length / 2);
        var firstMatch = FindMatch(source, 4);
        if (firstMatch < 0)
        {
            WriteLiteral(output, source, 0, source.Length, first: true);
            WriteTerminator(output);
            return output.ToArray();
        }

        WriteLiteral(output, source, 0, firstMatch, first: true);
        var position = firstMatch;
        while (position < source.Length)
        {
            var matchLength = MatchLength(source, position);
            if (matchLength < 4)
            {
                throw new InvalidDataException(
                    "The briefing LZO token scan lost match alignment.");
            }

            var matchEnd = checked(position + matchLength);
            var nextMatch = FindMatch(source, matchEnd);
            var literalEnd =
                nextMatch < 0 ? source.Length : nextMatch;
            var literalLength = checked(literalEnd - matchEnd);
            var trailingLength = literalLength <= 3
                ? literalLength
                : 0;
            WriteM3Match(
                output,
                distance: 2,
                matchLength,
                trailingLength);
            if (trailingLength > 0)
            {
                output.Write(
                    source.Slice(matchEnd, trailingLength));
                position = literalEnd;
                continue;
            }

            position = matchEnd;
            if (literalLength > 0)
            {
                WriteLiteral(
                    output,
                    source,
                    matchEnd,
                    literalLength,
                    first: false);
                position = literalEnd;
            }
        }

        WriteTerminator(output);
        return output.ToArray();
    }

    private static int FindMatch(
        ReadOnlySpan<byte> source,
        int start)
    {
        for (var position = Math.Max(4, start);
             position <= source.Length - 4;
             position++)
        {
            if (MatchLength(source, position) >= 4)
            {
                return position;
            }
        }
        return -1;
    }

    private static int MatchLength(
        ReadOnlySpan<byte> source,
        int position)
    {
        if (position < 2 || position >= source.Length)
        {
            return 0;
        }
        var length = 0;
        while (position + length < source.Length &&
               source[position + length] ==
               source[position + length - 2])
        {
            length++;
        }
        return length;
    }

    private static void WriteLiteral(
        Stream output,
        ReadOnlySpan<byte> source,
        int offset,
        int length,
        bool first)
    {
        if (length <= 0)
        {
            throw new InvalidDataException(
                "An LZO literal token cannot be empty.");
        }
        if (first && length <= 238)
        {
            output.WriteByte(checked((byte)(17 + length)));
        }
        else if (!first && length is >= 4 and <= 18)
        {
            output.WriteByte(checked((byte)(length - 3)));
        }
        else
        {
            if (length < 19)
            {
                throw new InvalidDataException(
                    "A non-initial short literal must trail a match.");
            }
            output.WriteByte(0);
            WriteExtendedLength(output, checked(length - 18));
        }
        output.Write(source.Slice(offset, length));
    }

    private static void WriteM3Match(
        Stream output,
        int distance,
        int length,
        int trailingLength)
    {
        if (distance is <= 0 or > 16_384 ||
            length < 3 ||
            trailingLength is < 0 or > 3)
        {
            throw new ArgumentOutOfRangeException();
        }
        if (length <= 33)
        {
            output.WriteByte(checked((byte)(0x20 | (length - 2))));
        }
        else
        {
            output.WriteByte(0x20);
            WriteExtendedLength(output, checked(length - 33));
        }
        var operand = checked(
            ((distance - 1) << 2) | trailingLength);
        output.WriteByte(checked((byte)(operand & 0xFF)));
        output.WriteByte(checked((byte)(operand >> 8)));
    }

    private static void WriteExtendedLength(
        Stream output,
        int value)
    {
        if (value <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(value));
        }
        while (value > 255)
        {
            output.WriteByte(0);
            value -= 255;
        }
        output.WriteByte(checked((byte)value));
    }

    private static void WriteTerminator(Stream output)
    {
        output.WriteByte(0x11);
        output.WriteByte(0);
        output.WriteByte(0);
    }
}
