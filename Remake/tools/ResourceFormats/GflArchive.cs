using System.Collections.ObjectModel;
using System.Text;

namespace Mission1937.Remake.Resources;

public sealed record GflEntry(
    int Index,
    string OriginalName,
    uint Attributes,
    long RecordOffset,
    long DataOffset,
    uint Length,
    string Type,
    string FileExtension);

public sealed record ExtractedGflEntry(
    int Index,
    string OriginalName,
    string Type,
    uint Length,
    string RelativePath);

public sealed class GflArchive
{
    public const int HeaderSize = 0x4E;
    private const int NameFieldSize = 0x100;
    private const int MetadataSize = 3;
    private const int LengthFieldSize = sizeof(uint);
    private const int EntryHeaderSize = NameFieldSize + MetadataSize + LengthFieldSize;
    private const string Magic = "GFL (Game File Library) Win32/V1.0";

    private GflArchive(string path, IReadOnlyList<GflEntry> entries)
    {
        Path = path;
        Entries = entries;
    }

    public string Path { get; }

    public IReadOnlyList<GflEntry> Entries { get; }

    public static GflArchive Open(string path, string? indexPath = null)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(path);

        var fullPath = System.IO.Path.GetFullPath(path);
        using var stream = new FileStream(fullPath, FileMode.Open, FileAccess.Read, FileShare.Read);
        if (stream.Length < HeaderSize)
        {
            throw new InvalidDataException("The file is shorter than a GFL header.");
        }

        var header = new byte[HeaderSize];
        stream.ReadExactly(header);
        if (!Encoding.ASCII.GetString(header).StartsWith(Magic, StringComparison.Ordinal))
        {
            throw new InvalidDataException("The file does not contain the expected GFL 1.0 header.");
        }

        var entries = new List<GflEntry>();
        using var reader = new BinaryReader(stream, Encoding.ASCII, leaveOpen: true);

        while (stream.Position < stream.Length)
        {
            var recordOffset = stream.Position;
            var remainingForHeader = stream.Length - recordOffset;
            if (remainingForHeader < EntryHeaderSize)
            {
                throw new InvalidDataException(
                    $"Truncated GFL entry header at 0x{recordOffset:X}; {remainingForHeader} bytes remain.");
            }

            var nameField = reader.ReadBytes(NameFieldSize);
            if (nameField.Length != NameFieldSize)
            {
                throw new EndOfStreamException("Unexpected EOF in GFL name field.");
            }

            var metadata = reader.ReadBytes(MetadataSize);
            if (metadata.Length != MetadataSize)
            {
                throw new EndOfStreamException("Unexpected EOF in GFL metadata field.");
            }

            var originalName = LegacyNameCodec.DecodeObfuscatedName(nameField);
            var attributes = (uint)(metadata[0] | metadata[1] << 8 | metadata[2] << 16);
            var length = reader.ReadUInt32();
            var dataOffset = stream.Position;
            var remainingPayload = stream.Length - dataOffset;
            if (length > remainingPayload)
            {
                throw new InvalidDataException(
                    $"GFL entry {entries.Count} declares {length} bytes at 0x{dataOffset:X}, " +
                    $"but only {remainingPayload} bytes remain.");
            }

            var prefixLength = checked((int)Math.Min(length, 16u));
            var prefix = new byte[prefixLength];
            stream.ReadExactly(prefix);
            var (type, extension) = DetectEntryType(prefix);

            entries.Add(new GflEntry(
                entries.Count,
                originalName,
                attributes,
                recordOffset,
                dataOffset,
                length,
                type,
                extension));

            stream.Position = checked(dataOffset + length);
        }

        var archive = new GflArchive(fullPath, new ReadOnlyCollection<GflEntry>(entries));
        if (!string.IsNullOrWhiteSpace(indexPath))
        {
            archive.ValidateIndex(GflIndex.Open(indexPath));
        }

        return archive;
    }

    public GflArchiveSummary GetSummary()
    {
        var typeCounts = Entries
            .GroupBy(entry => entry.Type, StringComparer.Ordinal)
            .OrderByDescending(group => group.Count())
            .ThenBy(group => group.Key, StringComparer.Ordinal)
            .ToDictionary(group => group.Key, group => group.Count(), StringComparer.Ordinal);

        return new GflArchiveSummary(
            Entries.Count,
            Entries.Count(entry => !string.IsNullOrWhiteSpace(entry.OriginalName)),
            Entries.Sum(entry => (long)entry.Length),
            new ReadOnlyDictionary<string, int>(typeCounts));
    }

    public IReadOnlyList<ExtractedGflEntry> ExtractAll(string outputDirectory)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(outputDirectory);
        var outputRoot = System.IO.Path.GetFullPath(outputDirectory);
        Directory.CreateDirectory(outputRoot);

        using var source = new FileStream(Path, FileMode.Open, FileAccess.Read, FileShare.Read);
        var extracted = new List<ExtractedGflEntry>(Entries.Count);
        var buffer = new byte[1024 * 1024];

        foreach (var entry in Entries)
        {
            var typeDirectory = System.IO.Path.Combine(outputRoot, entry.Type.ToLowerInvariant());
            Directory.CreateDirectory(typeDirectory);

            var safeOriginalName = SanitizeFileName(entry.OriginalName);
            var fileName = string.IsNullOrWhiteSpace(safeOriginalName)
                ? $"{entry.Index:D4}{entry.FileExtension}"
                : $"{entry.Index:D4}_{safeOriginalName}";
            var destinationPath = System.IO.Path.Combine(typeDirectory, fileName);
            source.Position = entry.DataOffset;
            using var destination = new FileStream(destinationPath, FileMode.Create, FileAccess.Write, FileShare.None);

            var remaining = (long)entry.Length;
            while (remaining > 0)
            {
                var requested = (int)Math.Min(buffer.Length, remaining);
                var read = source.Read(buffer, 0, requested);
                if (read == 0)
                {
                    throw new EndOfStreamException($"Unexpected EOF while extracting GFL entry {entry.Index}.");
                }

                destination.Write(buffer, 0, read);
                remaining -= read;
            }

            var relativePath = System.IO.Path.GetRelativePath(outputRoot, destinationPath)
                .Replace('\\', '/');
            extracted.Add(new ExtractedGflEntry(
                entry.Index,
                entry.OriginalName,
                entry.Type,
                entry.Length,
                relativePath));
        }

        return extracted;
    }

    private static (string Type, string Extension) DetectEntryType(ReadOnlySpan<byte> prefix)
    {
        var (format, _) = LegacyFileDetector.DetectHeader(prefix);
        return format switch
        {
            "TLG1" => ("TLG1", ".tlg1"),
            "SPR1" => ("SPR1", ".spr1"),
            "PSD" => ("PSD", ".psd"),
            "WAV" => ("WAV", ".wav"),
            "IBLOCK" => ("IBLOCK", ".iblock"),
            _ => ("UNKNOWN", ".bin")
        };
    }

    private void ValidateIndex(GflIndex index)
    {
        if (index.Entries.Count != Entries.Count)
        {
            throw new InvalidDataException(
                $"GFL index has {index.Entries.Count} entries, resource archive has {Entries.Count}.");
        }

        for (var position = 0; position < Entries.Count; position++)
        {
            var resource = Entries[position];
            var indexed = index.Entries[position];
            if (resource.OriginalName != indexed.OriginalName ||
                resource.Attributes != indexed.Attributes ||
                resource.Length != indexed.Length ||
                resource.DataOffset != indexed.DataOffset)
            {
                throw new InvalidDataException($"GFL index mismatch at entry {position}.");
            }
        }
    }

    private static string SanitizeFileName(string value)
    {
        var invalidCharacters = System.IO.Path.GetInvalidFileNameChars().ToHashSet();
        var sanitized = new string(value
            .Select(character => invalidCharacters.Contains(character) ? '_' : character)
            .ToArray())
            .Trim()
            .TrimEnd('.');
        return sanitized.Length <= 120 ? sanitized : sanitized[..120];
    }
}
