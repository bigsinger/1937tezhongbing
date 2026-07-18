namespace Mission1937.Remake.Resources;

/// <summary>
/// Safely decodes a raw LZO1X block into a caller-sized output buffer.
/// </summary>
/// <remarks>
/// The instruction layout follows the public Linux kernel LZO stream-format
/// documentation. Mission 1937 stores a single raw LZO1X block without a
/// container header in each IBLOCK image.
/// </remarks>
public static class Lzo1XDecoder
{
    private const int MaximumZeroLengthBytes = (int.MaxValue / 255) - 2;

    public static byte[] Decode(ReadOnlySpan<byte> source, int expectedLength)
    {
        return DecodeCore(source, expectedLength, expectedLength, requireExactLength: true);
    }

    /// <summary>
    /// Reproduces the bounded slack used by the original Intuition Engine and
    /// returns the requested prefix of the decoded block.
    /// </summary>
    /// <remarks>
    /// A small set of shipped SPR1 streams expands beyond width*height*2. The
    /// original executable allocates <c>length + length/64 + 19</c> bytes, then
    /// uploads only the declared image extent. Keeping this behavior isolated
    /// here preserves strict decoding for normal callers without rejecting
    /// those original assets.
    /// </remarks>
    public static byte[] DecodePrefixWithLegacySlack(
        ReadOnlySpan<byte> source,
        int requiredLength)
    {
        ArgumentOutOfRangeException.ThrowIfNegative(requiredLength);
        var capacity = checked(requiredLength + (requiredLength >> 6) + 19);
        return DecodeCore(source, requiredLength, capacity, requireExactLength: false);
    }

    private static byte[] DecodeCore(
        ReadOnlySpan<byte> source,
        int requiredLength,
        int capacity,
        bool requireExactLength)
    {
        ArgumentOutOfRangeException.ThrowIfNegative(requiredLength);
        if (capacity < requiredLength)
        {
            throw new ArgumentOutOfRangeException(nameof(capacity));
        }

        if (source.Length < 3)
        {
            throw new InvalidDataException("An LZO1X block must contain at least the three-byte terminator.");
        }

        var destination = new byte[capacity];
        var sourceIndex = 0;
        var destinationIndex = 0;
        var state = 0;

        // LZO1X gives the first instruction a literal-only shorthand because
        // no look-behind dictionary exists at the beginning of a block.
        if (source[0] >= 22)
        {
            var literalLength = source[0] - 17;
            sourceIndex++;
            CopyLiterals(
                source,
                ref sourceIndex,
                destination,
                ref destinationIndex,
                literalLength);
            state = 4;
        }
        else if (source[0] >= 18)
        {
            var literalLength = source[0] - 17;
            sourceIndex++;
            CopyLiterals(
                source,
                ref sourceIndex,
                destination,
                ref destinationIndex,
                literalLength);
            state = literalLength;
        }

        while (true)
        {
            EnsureSource(source, sourceIndex, 1);
            var instruction = source[sourceIndex++];
            int matchLength;
            int distance;
            int nextState;

            if ((instruction & 0xC0) != 0)
            {
                // M2: 3..8 bytes from at most 2 KiB behind the output cursor.
                EnsureSource(source, sourceIndex, 1);
                distance = (source[sourceIndex++] << 3) + ((instruction >> 2) & 0x07) + 1;
                matchLength = (instruction >> 5) + 1;
                nextState = instruction & 0x03;
            }
            else if ((instruction & 0x20) != 0)
            {
                // M3: 3 or more bytes from at most 16 KiB behind.
                matchLength = (instruction & 0x1F) + 2;
                if (matchLength == 2)
                {
                    matchLength = checked(
                        matchLength + ReadExtendedLength(source, ref sourceIndex, 31));
                }

                var operand = ReadUInt16LittleEndian(source, ref sourceIndex);
                distance = (operand >> 2) + 1;
                nextState = operand & 0x03;
            }
            else if ((instruction & 0x10) != 0)
            {
                // M4: 3 or more bytes from 16..48 KiB behind. A zero encoded
                // distance is the canonical 0x11,0x00,0x00 end marker.
                matchLength = (instruction & 0x07) + 2;
                if (matchLength == 2)
                {
                    matchLength = checked(
                        matchLength + ReadExtendedLength(source, ref sourceIndex, 7));
                }

                var operand = ReadUInt16LittleEndian(source, ref sourceIndex);
                var encodedDistance = ((instruction & 0x08) << 11) + (operand >> 2);
                nextState = operand & 0x03;
                if (encodedDistance == 0)
                {
                    if (matchLength != 3)
                    {
                        throw new InvalidDataException("The LZO1X end marker has an invalid match length.");
                    }

                    if (sourceIndex != source.Length)
                    {
                        throw new InvalidDataException("The LZO1X block contains bytes after its end marker.");
                    }

                    if (requireExactLength && destinationIndex != requiredLength)
                    {
                        throw new InvalidDataException(
                            $"LZO1X produced {destinationIndex} bytes; {requiredLength} were expected.");
                    }

                    if (!requireExactLength && destinationIndex < requiredLength)
                    {
                        throw new InvalidDataException(
                            $"LZO1X produced {destinationIndex} bytes; at least {requiredLength} were expected.");
                    }

                    return destinationIndex == destination.Length &&
                           destination.Length == requiredLength
                        ? destination
                        : destination.AsSpan(0, requiredLength).ToArray();
                }

                distance = checked(encodedDistance + 16_384);
            }
            else if (state == 0)
            {
                // A 0..15 instruction after no trailing literals starts a
                // literal run rather than a dictionary match.
                var literalLength = instruction + 3;
                if (literalLength == 3)
                {
                    literalLength = checked(
                        literalLength + ReadExtendedLength(source, ref sourceIndex, 15));
                }

                CopyLiterals(
                    source,
                    ref sourceIndex,
                    destination,
                    ref destinationIndex,
                    literalLength);
                state = 4;
                continue;
            }
            else if (state != 4)
            {
                // M1: a two-byte match within 1 KiB, valid after 1..3
                // trailing literals.
                EnsureSource(source, sourceIndex, 1);
                nextState = instruction & 0x03;
                distance = (instruction >> 2) + (source[sourceIndex++] << 2) + 1;
                matchLength = 2;
            }
            else
            {
                // Three-byte M2 shorthand within the 2..3 KiB range, valid
                // after a long literal run.
                EnsureSource(source, sourceIndex, 1);
                nextState = instruction & 0x03;
                distance = (instruction >> 2) + (source[sourceIndex++] << 2) + 2_049;
                matchLength = 3;
            }

            CopyMatch(destination, ref destinationIndex, distance, matchLength);
            CopyLiterals(
                source,
                ref sourceIndex,
                destination,
                ref destinationIndex,
                nextState);
            state = nextState;
        }
    }

    private static int ReadExtendedLength(
        ReadOnlySpan<byte> source,
        ref int sourceIndex,
        int baseLength)
    {
        var zeroByteCount = 0;
        while (true)
        {
            EnsureSource(source, sourceIndex, 1);
            var value = source[sourceIndex++];
            if (value != 0)
            {
                return checked(baseLength + (zeroByteCount * 255) + value);
            }

            zeroByteCount++;
            if (zeroByteCount > MaximumZeroLengthBytes)
            {
                throw new InvalidDataException("The LZO1X extended length is too large.");
            }
        }
    }

    private static int ReadUInt16LittleEndian(ReadOnlySpan<byte> source, ref int sourceIndex)
    {
        EnsureSource(source, sourceIndex, 2);
        var value = source[sourceIndex] | (source[sourceIndex + 1] << 8);
        sourceIndex += 2;
        return value;
    }

    private static void CopyLiterals(
        ReadOnlySpan<byte> source,
        ref int sourceIndex,
        Span<byte> destination,
        ref int destinationIndex,
        int length)
    {
        EnsureSource(source, sourceIndex, length);
        EnsureDestination(destination, destinationIndex, length);
        source.Slice(sourceIndex, length).CopyTo(destination[destinationIndex..]);
        sourceIndex += length;
        destinationIndex += length;
    }

    private static void CopyMatch(
        Span<byte> destination,
        ref int destinationIndex,
        int distance,
        int length)
    {
        if (distance <= 0 || distance > destinationIndex)
        {
            throw new InvalidDataException(
                $"LZO1X match distance {distance} exceeds the {destinationIndex}-byte dictionary.");
        }

        EnsureDestination(destination, destinationIndex, length);
        for (var index = 0; index < length; index++)
        {
            destination[destinationIndex] = destination[destinationIndex - distance];
            destinationIndex++;
        }
    }

    private static void EnsureSource(ReadOnlySpan<byte> source, int offset, int count)
    {
        if (count < 0 || offset < 0 || offset > source.Length - count)
        {
            throw new InvalidDataException("The LZO1X block ends in the middle of an instruction.");
        }
    }

    private static void EnsureDestination(Span<byte> destination, int offset, int count)
    {
        if (count < 0 || offset < 0 || offset > destination.Length - count)
        {
            throw new InvalidDataException("The LZO1X block exceeds its declared output size.");
        }
    }
}
