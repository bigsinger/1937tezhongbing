using System.Text;

namespace Mission1937.Remake.Resources;

public static class LegacyNameCodec
{
    private static readonly byte[] NameKey =
    [
        34, 37, 5, 44, 1, 4, 19, 27, 49, 24,
        45, 35, 2, 4, 30, 3, 31, 5, 21, 15,
        7, 36, 14, 5, 4
    ];

    private static readonly Encoding StrictGbk;

    static LegacyNameCodec()
    {
        Encoding.RegisterProvider(CodePagesEncodingProvider.Instance);
        StrictGbk = Encoding.GetEncoding(
            936,
            EncoderFallback.ExceptionFallback,
            DecoderFallback.ExceptionFallback);
    }

    public static string DecodeObfuscatedName(ReadOnlySpan<byte> nameField)
    {
        if (nameField.IsEmpty)
        {
            throw new InvalidDataException("The legacy name field is empty.");
        }

        var length = nameField[0];
        if (length > NameKey.Length)
        {
            throw new NotSupportedException(
                $"The legacy name uses {length} bytes, exceeding the known {NameKey.Length}-byte key.");
        }

        if (nameField.Length < length + 1)
        {
            throw new InvalidDataException("The legacy name field is truncated.");
        }

        var decoded = new byte[length];
        for (var index = 0; index < length; index++)
        {
            decoded[index] = unchecked((byte)(nameField[index + 1] - NameKey[index]));
        }

        try
        {
            return StrictGbk.GetString(decoded);
        }
        catch (DecoderFallbackException exception)
        {
            throw new InvalidDataException("The decoded legacy name is not valid GBK.", exception);
        }
    }

    public static string DecodeNullTerminatedGbk(ReadOnlySpan<byte> nameField)
    {
        var terminator = nameField.IndexOf((byte)0);
        var encoded = terminator >= 0 ? nameField[..terminator] : nameField;
        try
        {
            return StrictGbk.GetString(encoded);
        }
        catch (DecoderFallbackException exception)
        {
            throw new InvalidDataException("The legacy string is not valid GBK.", exception);
        }
    }

    internal static byte[] EncodeObfuscatedNameForTests(string value, int fieldLength = 256)
    {
        var encoded = StrictGbk.GetBytes(value);
        if (encoded.Length > NameKey.Length || encoded.Length + 1 > fieldLength)
        {
            throw new ArgumentOutOfRangeException(nameof(value));
        }

        var field = new byte[fieldLength];
        field[0] = (byte)encoded.Length;
        for (var index = 0; index < encoded.Length; index++)
        {
            field[index + 1] = unchecked((byte)(encoded[index] + NameKey[index]));
        }

        return field;
    }
}
