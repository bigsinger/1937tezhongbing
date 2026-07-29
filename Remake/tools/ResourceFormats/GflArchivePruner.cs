using System.Collections.ObjectModel;

namespace Mission1937.Remake.Resources;

public sealed record GflTrailingPruneReport(
    string ResourceArchivePath,
    string IndexArchivePath,
    int EntryCount,
    IReadOnlyList<string> RemovedNames,
    long RemovedPayloadBytes,
    long OutputResourceBytes);

/// <summary>
/// Removes an explicitly named, contiguous suffix from a GFL pair.
/// Original numeric resource indexes are never shifted: the operation is
/// rejected unless every removed entry is after every retained entry.
/// </summary>
public static class GflArchivePruner
{
    private const int NameFieldSize = 256;
    private const int AttributeFieldSize = 3;
    private const int MetadataSize = NameFieldSize + AttributeFieldSize;

    public static GflTrailingPruneReport RemoveTrailingEntries(
        string sourceResourcePath,
        string sourceIndexPath,
        string outputResourcePath,
        string outputIndexPath,
        IReadOnlyCollection<string> names)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(sourceResourcePath);
        ArgumentException.ThrowIfNullOrWhiteSpace(sourceIndexPath);
        ArgumentException.ThrowIfNullOrWhiteSpace(outputResourcePath);
        ArgumentException.ThrowIfNullOrWhiteSpace(outputIndexPath);
        ArgumentNullException.ThrowIfNull(names);
        if (names.Count == 0 || names.Any(string.IsNullOrWhiteSpace))
        {
            throw new ArgumentException(
                "At least one non-empty trailing entry name is required.",
                nameof(names));
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
        if (File.Exists(outputResource) || File.Exists(outputIndex))
        {
            throw new IOException(
                "GFL prune outputs must not already exist.");
        }

        var removalNames = names.ToHashSet(
            StringComparer.OrdinalIgnoreCase);
        if (removalNames.Count != names.Count)
        {
            throw new ArgumentException(
                "Trailing entry names must be unique.",
                nameof(names));
        }

        var archive = GflArchive.Open(sourceResource, sourceIndex);
        var suffixStart = archive.Entries.Count - removalNames.Count;
        if (suffixStart < 0)
        {
            throw new InvalidDataException(
                "The GFL contains fewer entries than the requested suffix.");
        }
        var suffix = archive.Entries.Skip(suffixStart).ToArray();
        if (suffix.Length != removalNames.Count ||
            suffix.Any(entry => !removalNames.Contains(entry.OriginalName)) ||
            archive.Entries.Take(suffixStart).Any(
                entry => removalNames.Contains(entry.OriginalName)))
        {
            throw new InvalidDataException(
                "Requested GFL removals are not the exact contiguous archive suffix; " +
                "numeric resource indexes would be shifted.");
        }

        Directory.CreateDirectory(Path.GetDirectoryName(outputResource)!);
        Directory.CreateDirectory(Path.GetDirectoryName(outputIndex)!);
        var temporaryResource =
            outputResource + ".tmp-" + Guid.NewGuid().ToString("N");
        var temporaryIndex =
            outputIndex + ".tmp-" + Guid.NewGuid().ToString("N");
        try
        {
            var records = RewriteRetainedResource(
                archive,
                sourceResource,
                temporaryResource,
                suffixStart);
            RewriteIndex(
                sourceIndex,
                temporaryIndex,
                records);
            Validate(
                archive,
                temporaryResource,
                temporaryIndex,
                suffixStart,
                removalNames);
            File.Move(temporaryResource, outputResource);
            File.Move(temporaryIndex, outputIndex);
            return new GflTrailingPruneReport(
                outputResource,
                outputIndex,
                suffixStart,
                new ReadOnlyCollection<string>(
                    suffix.Select(entry => entry.OriginalName).ToArray()),
                suffix.Sum(entry => (long)entry.Length),
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

    private static IReadOnlyList<Record> RewriteRetainedResource(
        GflArchive archive,
        string sourcePath,
        string outputPath,
        int retainedCount)
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
        var buffer = new byte[1024 * 1024];
        var records = new List<Record>(retainedCount);
        foreach (var entry in archive.Entries.Take(retainedCount))
        {
            source.Position = entry.RecordOffset;
            var metadata = new byte[MetadataSize];
            source.ReadExactly(metadata);
            output.Write(metadata);
            writer.Write(entry.Length);
            var dataOffset = checked((uint)output.Position);
            CopyExactly(
                source,
                output,
                entry.DataOffset,
                entry.Length,
                buffer);
            records.Add(new Record(metadata, entry.Length, dataOffset));
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
        GflArchive source,
        string resourcePath,
        string indexPath,
        int retainedCount,
        IReadOnlySet<string> removedNames)
    {
        var output = GflArchive.Open(resourcePath, indexPath);
        if (output.Entries.Count != retainedCount ||
            output.Entries.Any(
                entry => removedNames.Contains(entry.OriginalName)))
        {
            throw new InvalidDataException(
                "The pruned GFL entry set is incorrect.");
        }
        for (var index = 0; index < retainedCount; index++)
        {
            var before = source.Entries[index];
            var after = output.Entries[index];
            if (before.OriginalName != after.OriginalName ||
                before.Attributes != after.Attributes ||
                before.Length != after.Length)
            {
                throw new InvalidDataException(
                    $"The pruned GFL changed retained entry {index}.");
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
            var requested = checked((int)Math.Min(buffer.Length, remaining));
            var read = source.Read(buffer, 0, requested);
            if (read == 0)
            {
                throw new EndOfStreamException(
                    "The GFL payload ended during pruning.");
            }
            destination.Write(buffer, 0, read);
            remaining -= read;
        }
    }

    private static void EnsureDistinct(params string[] paths)
    {
        if (paths.Distinct(
                StringComparer.OrdinalIgnoreCase).Count() != paths.Length)
        {
            throw new ArgumentException(
                "GFL prune source and output paths must be distinct.");
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
            // Preserve the primary prune exception.
        }
    }

    private sealed record Record(
        byte[] Metadata,
        uint Length,
        uint DataOffset);
}
