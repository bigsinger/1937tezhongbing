using System.Collections.ObjectModel;
using System.Security.Cryptography;

namespace Mission1937.Remake.Resources;

public sealed record GflPayloadInstallationReport(
    string ResourceArchivePath,
    string IndexArchivePath,
    int EntryCount,
    IReadOnlyList<string> ReplacedNames,
    IReadOnlyList<string> AddedNames,
    long OutputResourceBytes);

/// <summary>
/// Replaces named GFL payloads and appends missing named entries while
/// preserving every unrelated record and numeric index.
/// </summary>
public static class GflPayloadInstaller
{
    private const int NameFieldSize = 256;
    private const int AttributeFieldSize = 3;
    private const int MetadataSize =
        NameFieldSize + AttributeFieldSize;

    public static GflPayloadInstallationReport Install(
        string sourceResourcePath,
        string sourceIndexPath,
        string outputResourcePath,
        string outputIndexPath,
        IReadOnlyDictionary<string, byte[]> payloads,
        string metadataTemplateName)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(sourceResourcePath);
        ArgumentException.ThrowIfNullOrWhiteSpace(sourceIndexPath);
        ArgumentException.ThrowIfNullOrWhiteSpace(outputResourcePath);
        ArgumentException.ThrowIfNullOrWhiteSpace(outputIndexPath);
        ArgumentNullException.ThrowIfNull(payloads);
        if (payloads.Count == 0)
        {
            throw new ArgumentException(
                "At least one GFL payload is required.",
                nameof(payloads));
        }

        var sourceResource = Path.GetFullPath(sourceResourcePath);
        var sourceIndex = Path.GetFullPath(sourceIndexPath);
        var outputResource = Path.GetFullPath(outputResourcePath);
        var outputIndex = Path.GetFullPath(outputIndexPath);
        EnsureDistinct(
            sourceResource,
            sourceIndex,
            outputResource,
            outputIndex);
        if (File.Exists(outputResource) ||
            File.Exists(outputIndex))
        {
            throw new IOException(
                "GFL installer outputs must not already exist.");
        }

        var normalized = new Dictionary<string, byte[]>(
            StringComparer.OrdinalIgnoreCase);
        foreach (var pair in payloads)
        {
            if (string.IsNullOrWhiteSpace(pair.Key) ||
                pair.Value is null ||
                pair.Value.Length == 0)
            {
                throw new ArgumentException(
                    "GFL payload names and bytes must be non-empty.",
                    nameof(payloads));
            }
            normalized.Add(pair.Key, pair.Value);
        }

        var archive = GflArchive.Open(
            sourceResource,
            sourceIndex);
        var template = archive.Entries.FirstOrDefault(entry =>
            entry.OriginalName.Equals(
                metadataTemplateName,
                StringComparison.OrdinalIgnoreCase))
            ?? throw new InvalidDataException(
                $"GFL metadata template is missing: {metadataTemplateName}");
        var existingNames = archive.Entries
            .Select(entry => entry.OriginalName)
            .ToHashSet(StringComparer.OrdinalIgnoreCase);
        var replaced = normalized.Keys
            .Where(existingNames.Contains)
            .OrderBy(value => value, StringComparer.Ordinal)
            .ToArray();
        var added = normalized.Keys
            .Where(value => !existingNames.Contains(value))
            .OrderBy(value => value, StringComparer.Ordinal)
            .ToArray();

        Directory.CreateDirectory(
            Path.GetDirectoryName(outputResource)!);
        Directory.CreateDirectory(
            Path.GetDirectoryName(outputIndex)!);
        var temporaryResource =
            outputResource + ".tmp-" + Guid.NewGuid().ToString("N");
        var temporaryIndex =
            outputIndex + ".tmp-" + Guid.NewGuid().ToString("N");
        try
        {
            var records = RewriteResource(
                archive,
                sourceResource,
                temporaryResource,
                normalized,
                template,
                added);
            RewriteIndex(
                sourceIndex,
                temporaryIndex,
                records);
            Validate(
                temporaryResource,
                temporaryIndex,
                archive,
                normalized,
                added.Length);
            File.Move(temporaryResource, outputResource);
            File.Move(temporaryIndex, outputIndex);
            return new GflPayloadInstallationReport(
                outputResource,
                outputIndex,
                archive.Entries.Count + added.Length,
                new ReadOnlyCollection<string>(replaced),
                new ReadOnlyCollection<string>(added),
                new FileInfo(outputResource).Length);
        }
        catch
        {
            TryDelete(temporaryResource);
            TryDelete(temporaryIndex);
            TryDelete(outputResource);
            TryDelete(outputIndex);
            throw;
        }
    }

    private static IReadOnlyList<Record> RewriteResource(
        GflArchive archive,
        string sourcePath,
        string outputPath,
        IReadOnlyDictionary<string, byte[]> payloads,
        GflEntry template,
        IReadOnlyList<string> added)
    {
        using var source = new FileStream(
            sourcePath,
            FileMode.Open,
            FileAccess.Read,
            FileShare.Read);
        using var output = new FileStream(
            outputPath,
            FileMode.CreateNew,
            FileAccess.Write,
            FileShare.None);
        var header = new byte[GflArchive.HeaderSize];
        source.ReadExactly(header);
        output.Write(header);
        using var writer = new BinaryWriter(output);
        var records = new List<Record>(
            archive.Entries.Count + added.Count);
        var copyBuffer = new byte[1024 * 1024];
        foreach (var entry in archive.Entries)
        {
            source.Position = entry.RecordOffset;
            var metadata = new byte[MetadataSize];
            source.ReadExactly(metadata);
            output.Write(metadata);
            var replacement = payloads.TryGetValue(
                entry.OriginalName,
                out var bytes)
                ? bytes
                : null;
            var length = replacement is null
                ? entry.Length
                : checked((uint)replacement.Length);
            writer.Write(length);
            var dataOffset = checked((uint)output.Position);
            if (replacement is not null)
            {
                output.Write(replacement);
            }
            else
            {
                CopyExactly(
                    source,
                    output,
                    entry.DataOffset,
                    entry.Length,
                    copyBuffer);
            }
            records.Add(new Record(metadata, length, dataOffset));
        }

        source.Position = template.RecordOffset + NameFieldSize;
        var attributes = new byte[AttributeFieldSize];
        source.ReadExactly(attributes);
        foreach (var name in added)
        {
            var metadata = new byte[MetadataSize];
            LegacyNameCodec.EncodeObfuscatedName(name)
                .CopyTo(metadata, 0);
            attributes.CopyTo(metadata, NameFieldSize);
            output.Write(metadata);
            var replacement = payloads[name];
            var length = checked((uint)replacement.Length);
            writer.Write(length);
            var dataOffset = checked((uint)output.Position);
            output.Write(replacement);
            records.Add(new Record(metadata, length, dataOffset));
        }
        output.Flush(flushToDisk: true);
        return new ReadOnlyCollection<Record>(records);
    }

    private static void RewriteIndex(
        string sourcePath,
        string outputPath,
        IReadOnlyList<Record> records)
    {
        using var source = new FileStream(
            sourcePath,
            FileMode.Open,
            FileAccess.Read,
            FileShare.Read);
        using var output = new FileStream(
            outputPath,
            FileMode.CreateNew,
            FileAccess.Write,
            FileShare.None);
        var header = new byte[GflIndex.HeaderSize];
        source.ReadExactly(header);
        output.Write(header);
        using var writer = new BinaryWriter(output);
        foreach (var record in records)
        {
            output.Write(record.Metadata);
            writer.Write(record.Length);
            writer.Write(record.DataOffset);
        }
        output.Flush(flushToDisk: true);
    }

    private static void Validate(
        string resourcePath,
        string indexPath,
        GflArchive source,
        IReadOnlyDictionary<string, byte[]> payloads,
        int addedCount)
    {
        var output = GflArchive.Open(resourcePath, indexPath);
        if (output.Entries.Count !=
            source.Entries.Count + addedCount)
        {
            throw new InvalidDataException(
                "The installed GFL entry count is incorrect.");
        }
        foreach (var entry in source.Entries)
        {
            var installed = output.Entries[entry.Index];
            var expectedLength = payloads.TryGetValue(
                entry.OriginalName,
                out var replacement)
                ? checked((uint)replacement.Length)
                : entry.Length;
            if (installed.OriginalName != entry.OriginalName ||
                installed.Attributes != entry.Attributes ||
                installed.Length != expectedLength)
            {
                throw new InvalidDataException(
                    $"GFL entry {entry.Index} metadata changed.");
            }
        }
        using var stream = File.OpenRead(resourcePath);
        foreach (var pair in payloads)
        {
            var entry = output.Entries.Single(candidate =>
                candidate.OriginalName.Equals(
                    pair.Key,
                    StringComparison.OrdinalIgnoreCase));
            var actual = new byte[entry.Length];
            stream.Position = entry.DataOffset;
            stream.ReadExactly(actual);
            if (!SHA256.HashData(actual).SequenceEqual(
                    SHA256.HashData(pair.Value)))
            {
                throw new InvalidDataException(
                    $"GFL payload verification failed: {pair.Key}");
            }
        }
    }

    private static void CopyExactly(
        Stream source,
        Stream destination,
        long offset,
        uint length,
        byte[] buffer)
    {
        source.Position = offset;
        long remaining = length;
        while (remaining > 0)
        {
            var requested = checked((int)Math.Min(
                buffer.Length,
                remaining));
            var read = source.Read(buffer, 0, requested);
            if (read == 0)
            {
                throw new EndOfStreamException(
                    "The GFL payload ended during installation.");
            }
            destination.Write(buffer, 0, read);
            remaining -= read;
        }
    }

    private static void EnsureDistinct(params string[] paths)
    {
        if (paths.Distinct(
                StringComparer.OrdinalIgnoreCase).Count() !=
            paths.Length)
        {
            throw new ArgumentException(
                "GFL source and output paths must be distinct.");
        }
    }

    private static void TryDelete(string path)
    {
        try
        {
            if (File.Exists(path))
            {
                File.Delete(path);
            }
        }
        catch
        {
            // Preserve the primary failure.
        }
    }

    private sealed record Record(
        byte[] Metadata,
        uint Length,
        uint DataOffset);
}
