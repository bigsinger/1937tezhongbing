using System.Buffers.Binary;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace Mission1937.Remake.Resources;

/// <summary>
/// Bounded validation for declarative content payloads. The package layer
/// verifies paths, lengths and hashes; this policy additionally rejects small
/// compressed files that would expand into unreasonable images, audio tracks
/// or runtime entity graphs.
/// </summary>
public static partial class M1937PackContentPolicy
{
    public const int MaximumImageDimension = 16_384;
    public const long MaximumImagePixels = 67_108_864;
    public const double MaximumAudioSeconds = 1_800.0;
    public const int MaximumEntitiesPerLevel = 20_000;
    public const int MaximumObjectivesPerMission = 1_024;
    public const int MaximumDirectionSequences = 512;
    public const int MaximumLocalizationMessages = 10_000;
    public const int MaximumWorldDimension = 1_048_576;

    [GeneratedRegex("^(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)(?:-([0-9A-Za-z.-]+))?(?:\\+([0-9A-Za-z.-]+))?$", RegexOptions.CultureInvariant)]
    private static partial Regex SemanticVersionPattern();

    public static bool IsSemanticVersion(string value) =>
        !string.IsNullOrWhiteSpace(value) &&
        value.Length <= 64 &&
        SemanticVersionPattern().IsMatch(value);

    public static int CompareSemanticVersions(string left, string right)
    {
        var leftParts = ParseCoreVersion(left);
        var rightParts = ParseCoreVersion(right);
        for (var index = 0; index < 3; index++)
        {
            var comparison = leftParts[index].CompareTo(rightParts[index]);
            if (comparison != 0)
                return comparison;
        }
        var leftPrerelease = Prerelease(left);
        var rightPrerelease = Prerelease(right);
        if (leftPrerelease.Length == 0 && rightPrerelease.Length == 0)
            return 0;
        if (leftPrerelease.Length == 0)
            return 1;
        if (rightPrerelease.Length == 0)
            return -1;
        return ComparePrerelease(leftPrerelease, rightPrerelease);
    }

    public static void Validate(string relativePath, ReadOnlySpan<byte> payload)
    {
        var extension = Path.GetExtension(relativePath).ToLowerInvariant();
        switch (extension)
        {
            case ".png":
                ValidateImage(relativePath, PngDimensions(payload));
                break;
            case ".jpg":
            case ".jpeg":
                ValidateImage(relativePath, JpegDimensions(payload));
                break;
            case ".webp":
                ValidateImage(relativePath, WebpDimensions(payload));
                break;
            case ".wav":
                ValidateAudio(relativePath, WavDuration(payload));
                break;
            case ".ogg":
                ValidateAudio(relativePath, OggVorbisDuration(payload));
                break;
            case ".mp3":
                ValidateAudio(relativePath, Mp3Duration(payload));
                break;
            case ".json":
                ValidateJson(relativePath, payload);
                break;
        }
    }

    private static void ValidateJson(string path, ReadOnlySpan<byte> bytes)
    {
        JsonDocument document;
        try
        {
            document = JsonDocument.Parse(bytes.ToArray(), new JsonDocumentOptions
            {
                AllowTrailingCommas = false,
                CommentHandling = JsonCommentHandling.Disallow,
                MaxDepth = 64
            });
        }
        catch (JsonException exception)
        {
            throw new InvalidDataException($"Invalid JSON payload: {path}", exception);
        }
        using (document)
        {
            var root = document.RootElement;
            if (root.ValueKind != JsonValueKind.Object)
                throw new InvalidDataException($"JSON root must be an object: {path}");
            if (path.Equals("campaign.json", StringComparison.Ordinal))
            {
                var levels = RequiredArray(root, "levels", path);
                if (levels.GetArrayLength() is < 1 or > 128)
                    throw new InvalidDataException("campaign.json must contain 1..128 levels.");
            }
            else if (path.EndsWith("/level.json", StringComparison.Ordinal))
            {
                var entities = RequiredArray(root, "entities", path);
                if (entities.GetArrayLength() > MaximumEntitiesPerLevel)
                    throw new InvalidDataException(
                        $"Level exceeds {MaximumEntitiesPerLevel} entities: {path}");
                var world = RequiredObject(root, "world_size", path);
                ValidateBoundedInteger(world, "width", 1, MaximumWorldDimension, path);
                ValidateBoundedInteger(world, "height", 1, MaximumWorldDimension, path);
            }
            else if (path.EndsWith("/mission.json", StringComparison.Ordinal))
            {
                var objectives = RequiredArray(root, "objectives", path);
                if (objectives.GetArrayLength() > MaximumObjectivesPerMission)
                    throw new InvalidDataException(
                        $"Mission exceeds {MaximumObjectivesPerMission} objectives: {path}");
                if (root.TryGetProperty("failure_conditions", out var failures) &&
                    (failures.ValueKind != JsonValueKind.Array ||
                     failures.GetArrayLength() > MaximumObjectivesPerMission))
                    throw new InvalidDataException($"Invalid failure_conditions: {path}");
            }
            else if (path.EndsWith("/direction.json", StringComparison.Ordinal))
            {
                var sequences = RequiredArray(root, "sequences", path);
                if (sequences.GetArrayLength() > MaximumDirectionSequences)
                    throw new InvalidDataException(
                        $"Direction document exceeds {MaximumDirectionSequences} sequences: {path}");
            }
            else if (path.StartsWith("localization/", StringComparison.Ordinal) &&
                     root.EnumerateObject().Count() > MaximumLocalizationMessages)
                throw new InvalidDataException(
                    $"Localization exceeds {MaximumLocalizationMessages} messages: {path}");
        }
    }

    private static JsonElement RequiredArray(JsonElement root, string name, string path)
    {
        if (!root.TryGetProperty(name, out var value) || value.ValueKind != JsonValueKind.Array)
            throw new InvalidDataException($"{path} requires array '{name}'.");
        return value;
    }

    private static JsonElement RequiredObject(JsonElement root, string name, string path)
    {
        if (!root.TryGetProperty(name, out var value) || value.ValueKind != JsonValueKind.Object)
            throw new InvalidDataException($"{path} requires object '{name}'.");
        return value;
    }

    private static void ValidateBoundedInteger(
        JsonElement root,
        string name,
        int minimum,
        int maximum,
        string path)
    {
        if (!root.TryGetProperty(name, out var value) ||
            !value.TryGetInt32(out var parsed) || parsed < minimum || parsed > maximum)
            throw new InvalidDataException(
                $"{path}.{name} must be {minimum}..{maximum}.");
    }

    private static void ValidateImage(string path, (int Width, int Height) dimensions)
    {
        var (width, height) = dimensions;
        if (width <= 0 || height <= 0 ||
            width > MaximumImageDimension || height > MaximumImageDimension ||
            checked((long)width * height) > MaximumImagePixels)
            throw new InvalidDataException(
                $"Image dimensions exceed policy ({width}x{height}): {path}");
    }

    private static void ValidateAudio(string path, double seconds)
    {
        if (!double.IsFinite(seconds) || seconds < 0 || seconds > MaximumAudioSeconds)
            throw new InvalidDataException(
                $"Audio duration exceeds {MaximumAudioSeconds:0} seconds or is invalid: {path}");
    }

    private static (int Width, int Height) PngDimensions(ReadOnlySpan<byte> bytes)
    {
        ReadOnlySpan<byte> signature = [137, 80, 78, 71, 13, 10, 26, 10];
        if (bytes.Length < 24 || !bytes[..8].SequenceEqual(signature) ||
            !bytes.Slice(12, 4).SequenceEqual("IHDR"u8))
            throw new InvalidDataException("Invalid PNG header.");
        return (
            checked((int)BinaryPrimitives.ReadUInt32BigEndian(bytes.Slice(16, 4))),
            checked((int)BinaryPrimitives.ReadUInt32BigEndian(bytes.Slice(20, 4))));
    }

    private static (int Width, int Height) JpegDimensions(ReadOnlySpan<byte> bytes)
    {
        if (bytes.Length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8)
            throw new InvalidDataException("Invalid JPEG header.");
        var offset = 2;
        while (offset + 4 <= bytes.Length)
        {
            while (offset < bytes.Length && bytes[offset] == 0xFF)
                offset++;
            if (offset >= bytes.Length)
                break;
            var marker = bytes[offset++];
            if (marker is 0xD8 or 0xD9 || marker is >= 0xD0 and <= 0xD7)
                continue;
            if (offset + 2 > bytes.Length)
                break;
            var length = BinaryPrimitives.ReadUInt16BigEndian(bytes.Slice(offset, 2));
            if (length < 2 || offset + length > bytes.Length)
                break;
            if (marker is 0xC0 or 0xC1 or 0xC2 or 0xC3 or 0xC5 or 0xC6 or 0xC7 or
                0xC9 or 0xCA or 0xCB or 0xCD or 0xCE or 0xCF)
            {
                if (length < 7)
                    break;
                return (
                    BinaryPrimitives.ReadUInt16BigEndian(bytes.Slice(offset + 5, 2)),
                    BinaryPrimitives.ReadUInt16BigEndian(bytes.Slice(offset + 3, 2)));
            }
            offset += length;
        }
        throw new InvalidDataException("JPEG dimensions are missing.");
    }

    private static (int Width, int Height) WebpDimensions(ReadOnlySpan<byte> bytes)
    {
        if (bytes.Length < 30 || !bytes[..4].SequenceEqual("RIFF"u8) ||
            !bytes.Slice(8, 4).SequenceEqual("WEBP"u8))
            throw new InvalidDataException("Invalid WebP header.");
        var kind = bytes.Slice(12, 4);
        if (kind.SequenceEqual("VP8X"u8))
            return (1 + ReadUInt24(bytes.Slice(24, 3)), 1 + ReadUInt24(bytes.Slice(27, 3)));
        if (kind.SequenceEqual("VP8 "u8) && bytes.Length >= 30 &&
            bytes[23] == 0x9D && bytes[24] == 0x01 && bytes[25] == 0x2A)
            return (
                BinaryPrimitives.ReadUInt16LittleEndian(bytes.Slice(26, 2)) & 0x3FFF,
                BinaryPrimitives.ReadUInt16LittleEndian(bytes.Slice(28, 2)) & 0x3FFF);
        if (kind.SequenceEqual("VP8L"u8) && bytes.Length >= 25 && bytes[20] == 0x2F)
        {
            var bits = BinaryPrimitives.ReadUInt32LittleEndian(bytes.Slice(21, 4));
            return (1 + (int)(bits & 0x3FFF), 1 + (int)((bits >> 14) & 0x3FFF));
        }
        throw new InvalidDataException("Unsupported WebP header.");
    }

    private static double WavDuration(ReadOnlySpan<byte> bytes)
    {
        if (bytes.Length < 12 || !bytes[..4].SequenceEqual("RIFF"u8) ||
            !bytes.Slice(8, 4).SequenceEqual("WAVE"u8))
            throw new InvalidDataException("Invalid WAV header.");
        uint byteRate = 0;
        uint dataBytes = 0;
        var offset = 12;
        while (offset + 8 <= bytes.Length)
        {
            var size = BinaryPrimitives.ReadUInt32LittleEndian(bytes.Slice(offset + 4, 4));
            var payload = offset + 8;
            if (payload + size > bytes.Length)
                throw new InvalidDataException("Truncated WAV chunk.");
            if (bytes.Slice(offset, 4).SequenceEqual("fmt "u8) && size >= 16)
                byteRate = BinaryPrimitives.ReadUInt32LittleEndian(bytes.Slice(payload + 8, 4));
            else if (bytes.Slice(offset, 4).SequenceEqual("data"u8))
                dataBytes = size;
            offset = checked(payload + (int)size + ((int)size & 1));
        }
        if (byteRate == 0 || dataBytes == 0)
            throw new InvalidDataException("WAV format or data chunk is missing.");
        return dataBytes / (double)byteRate;
    }

    private static double OggVorbisDuration(ReadOnlySpan<byte> bytes)
    {
        var offset = 0;
        uint sampleRate = 0;
        long lastGranule = 0;
        while (offset + 27 <= bytes.Length)
        {
            if (!bytes.Slice(offset, 4).SequenceEqual("OggS"u8))
                throw new InvalidDataException("Invalid Ogg page header.");
            var segments = bytes[offset + 26];
            if (offset + 27 + segments > bytes.Length)
                throw new InvalidDataException("Truncated Ogg segment table.");
            var payloadLength = 0;
            for (var index = 0; index < segments; index++)
                payloadLength += bytes[offset + 27 + index];
            var payloadOffset = offset + 27 + segments;
            if (payloadOffset + payloadLength > bytes.Length)
                throw new InvalidDataException("Truncated Ogg payload.");
            var granule = BinaryPrimitives.ReadInt64LittleEndian(bytes.Slice(offset + 6, 8));
            if (granule >= 0)
                lastGranule = Math.Max(lastGranule, granule);
            if (sampleRate == 0 && payloadLength >= 16 && bytes[payloadOffset] == 1 &&
                bytes.Slice(payloadOffset + 1, 6).SequenceEqual("vorbis"u8))
                sampleRate = BinaryPrimitives.ReadUInt32LittleEndian(
                    bytes.Slice(payloadOffset + 12, 4));
            offset = payloadOffset + payloadLength;
        }
        if (sampleRate == 0)
            throw new InvalidDataException("Ogg Vorbis identification header is missing.");
        return lastGranule / (double)sampleRate;
    }

    private static double Mp3Duration(ReadOnlySpan<byte> bytes)
    {
        var offset = 0;
        if (bytes.Length >= 10 && bytes[..3].SequenceEqual("ID3"u8))
            offset = 10 + ((bytes[6] & 0x7F) << 21) + ((bytes[7] & 0x7F) << 14) +
                     ((bytes[8] & 0x7F) << 7) + (bytes[9] & 0x7F);
        long samples = 0;
        var sampleRate = 0;
        while (offset + 4 <= bytes.Length)
        {
            var header = BinaryPrimitives.ReadUInt32BigEndian(bytes.Slice(offset, 4));
            if ((header & 0xFFE00000) != 0xFFE00000)
            {
                offset++;
                continue;
            }
            var versionBits = (int)((header >> 19) & 3);
            var layerBits = (int)((header >> 17) & 3);
            var bitrateIndex = (int)((header >> 12) & 0xF);
            var rateIndex = (int)((header >> 10) & 3);
            if (versionBits == 1 || layerBits != 1 || bitrateIndex is 0 or 15 || rateIndex == 3)
            {
                offset++;
                continue;
            }
            var baseRate = new[] { 44_100, 48_000, 32_000 }[rateIndex];
            sampleRate = versionBits switch { 3 => baseRate, 2 => baseRate / 2, _ => baseRate / 4 };
            var mpeg1 = versionBits == 3;
            var bitrates = mpeg1
                ? new[] { 0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320 }
                : new[] { 0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160 };
            var bitrate = bitrates[bitrateIndex] * 1000;
            var padding = (int)((header >> 9) & 1);
            var frameLength = (mpeg1 ? 144 : 72) * bitrate / sampleRate + padding;
            if (frameLength <= 4 || offset + frameLength > bytes.Length)
                break;
            samples += mpeg1 ? 1152 : 576;
            offset += frameLength;
        }
        if (samples == 0 || sampleRate == 0)
            throw new InvalidDataException("No valid MP3 frames were found.");
        return samples / (double)sampleRate;
    }

    private static int[] ParseCoreVersion(string value)
    {
        if (!IsSemanticVersion(value))
            throw new InvalidDataException($"Invalid semantic version: {value}");
        return value.Split('-', '+')[0].Split('.').Select(int.Parse).ToArray();
    }

    private static string Prerelease(string value)
    {
        var dash = value.IndexOf('-');
        if (dash < 0)
            return "";
        var plus = value.IndexOf('+', dash);
        return value[(dash + 1)..(plus < 0 ? value.Length : plus)];
    }

    private static int ComparePrerelease(string left, string right)
    {
        var leftParts = left.Split('.');
        var rightParts = right.Split('.');
        for (var index = 0; index < Math.Min(leftParts.Length, rightParts.Length); index++)
        {
            var leftNumeric = int.TryParse(leftParts[index], out var leftNumber);
            var rightNumeric = int.TryParse(rightParts[index], out var rightNumber);
            var comparison = leftNumeric && rightNumeric
                ? leftNumber.CompareTo(rightNumber)
                : leftNumeric ? -1
                : rightNumeric ? 1
                : string.CompareOrdinal(leftParts[index], rightParts[index]);
            if (comparison != 0)
                return comparison;
        }
        return leftParts.Length.CompareTo(rightParts.Length);
    }

    private static int ReadUInt24(ReadOnlySpan<byte> bytes) =>
        bytes[0] | bytes[1] << 8 | bytes[2] << 16;
}
