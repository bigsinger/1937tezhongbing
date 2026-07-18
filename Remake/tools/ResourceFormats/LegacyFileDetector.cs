using System.Text;

namespace Mission1937.Remake.Resources;

public static class LegacyFileDetector
{
    private const int ProbeLength = 128;

    public static LegacyAssetFile Detect(string path)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(path);

        var file = new FileInfo(path);
        if (!file.Exists)
        {
            throw new FileNotFoundException("Legacy asset file was not found.", path);
        }

        var header = new byte[Math.Min(ProbeLength, checked((int)Math.Min(file.Length, ProbeLength)))];
        using (var stream = file.OpenRead())
        {
            stream.ReadExactly(header);
        }

        var (format, detail) = DetectHeader(header);
        return new LegacyAssetFile(file.Name, file.Length, format, detail);
    }

    public static (string Format, string? Detail) DetectHeader(ReadOnlySpan<byte> header)
    {
        if (StartsWithAscii(header, "GFL (Game File Library)"))
        {
            return ("GFL", "Intuition Engine Game File Library 1.0");
        }

        if (StartsWithAscii(header, "VWL1 Intuition Engine Virtual World File"))
        {
            return ("VWF", "Intuition Engine Virtual World File 1.0");
        }

        if (StartsWithAscii(header, "DBL1 Intuition Engine Database File"))
        {
            return ("DBL", "Intuition Engine Database File 1.0");
        }

        if (StartsWithAscii(header, "SLF1 Intuition Engine Professional Sound Library"))
        {
            return ("SLF", "Intuition Engine Sound Library 1.0");
        }

        if (StartsWithAscii(header, "SPR1"))
        {
            return ("SPR1", "Intuition Engine sprite");
        }

        if (StartsWithAscii(header, "TLG1"))
        {
            return ("TLG1", "Intuition Engine tile group");
        }

        if (StartsWithAscii(header, "IBLOCK"))
        {
            return ("IBLOCK", "Intuition Engine block resource");
        }

        if (StartsWithAscii(header, "8BPS"))
        {
            return ("PSD", "Adobe Photoshop image");
        }

        if (header.Length >= 12 && StartsWithAscii(header, "RIFF"))
        {
            var formType = Encoding.ASCII.GetString(header.Slice(8, 4));
            return formType switch
            {
                "WAVE" => ("WAV", "RIFF/WAVE audio"),
                "CDXA" => ("CDXA", "RIFF/CDXA media container"),
                _ => ("RIFF", $"RIFF form type {SanitizeAscii(formType)}")
            };
        }

        if (header.Length >= 4 && header[0] == 0x50 && header[1] == 0x4B && header[2] == 0x03 && header[3] == 0x04)
        {
            return ("ZIP", "ZIP archive");
        }

        if (header.Length >= 4 && header[0] == 0x00 && header[1] == 0x00 && header[2] == 0x01 && header[3] == 0xBA)
        {
            return ("MPEG-PS", "MPEG program stream");
        }

        if (StartsWithAscii(header, "MZ"))
        {
            return ("PE", "Windows executable image");
        }

        return ("UNKNOWN", null);
    }

    private static bool StartsWithAscii(ReadOnlySpan<byte> bytes, string text)
    {
        if (bytes.Length < text.Length)
        {
            return false;
        }

        for (var index = 0; index < text.Length; index++)
        {
            if (bytes[index] != (byte)text[index])
            {
                return false;
            }
        }

        return true;
    }

    private static string SanitizeAscii(string value) =>
        new(value.Select(character => char.IsAsciiLetterOrDigit(character) ? character : '?').ToArray());
}
