using System.Collections.ObjectModel;

namespace Mission1937.Remake.Resources;

public sealed record GflBriefingRemovalReport(
    string ResourceArchivePath,
    string IndexArchivePath,
    int EntryCount,
    IReadOnlyList<int> ClearedEntryIndexes,
    long RemovedPayloadBytes,
    long OutputResourceBytes);

/// <summary>
/// Rewrites a GFL pair while preserving every resource index, encoded name and
/// attribute field. Only the twelve obsolete Intro_000..Intro_011 payloads are
/// cleared; their zero-length records remain so all later numeric indexes stay
/// stable for the original executable.
/// </summary>
public static class GflArchiveRewriter
{
    private const int EntryMetadataSize = 256 + 3;

    private static readonly IReadOnlySet<string> LegacyBriefingNames =
        new HashSet<string>(
            Enumerable.Range(0, 12)
                .Select(index => $"Intro_{index:D3}.psd"),
            StringComparer.OrdinalIgnoreCase);

    public static GflBriefingRemovalReport RemoveLegacyBriefingPayloads(
        string sourceResourcePath,
        string sourceIndexPath,
        string outputResourcePath,
        string outputIndexPath)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(sourceResourcePath);
        ArgumentException.ThrowIfNullOrWhiteSpace(sourceIndexPath);
        ArgumentException.ThrowIfNullOrWhiteSpace(outputResourcePath);
        ArgumentException.ThrowIfNullOrWhiteSpace(outputIndexPath);

        var sourceResource = System.IO.Path.GetFullPath(sourceResourcePath);
        var sourceIndex = System.IO.Path.GetFullPath(sourceIndexPath);
        var outputResource = System.IO.Path.GetFullPath(outputResourcePath);
        var outputIndex = System.IO.Path.GetFullPath(outputIndexPath);
        EnsureDistinctPaths(
            sourceResource,
            sourceIndex,
            outputResource,
            outputIndex);
        if (File.Exists(outputResource) || File.Exists(outputIndex))
        {
            throw new IOException(
                "GFL rewrite outputs must not already exist.");
        }

        var archive = GflArchive.Open(sourceResource, sourceIndex);
        var briefingEntries = archive.Entries
            .Where(entry =>
                LegacyBriefingNames.Contains(entry.OriginalName))
            .OrderBy(entry => entry.Index)
            .ToArray();
        if (briefingEntries.Length != LegacyBriefingNames.Count ||
            briefingEntries.Any(entry => entry.Length == 0))
        {
            throw new InvalidDataException(
                "The GFL pair does not contain twelve non-empty legacy " +
                "mission briefing payloads.");
        }

        var outputDirectory =
            System.IO.Path.GetDirectoryName(outputResource)!;
        var indexDirectory =
            System.IO.Path.GetDirectoryName(outputIndex)!;
        Directory.CreateDirectory(outputDirectory);
        Directory.CreateDirectory(indexDirectory);
        var resourceTemporary = outputResource + ".tmp-" +
            Guid.NewGuid().ToString("N");
        var indexTemporary = outputIndex + ".tmp-" +
            Guid.NewGuid().ToString("N");
        try
        {
            var rewritten = RewriteResourceArchive(
                archive,
                sourceResource,
                resourceTemporary);
            RewriteIndexArchive(
                sourceIndex,
                rewritten,
                indexTemporary);

            var validated = GflArchive.Open(
                resourceTemporary,
                indexTemporary);
            if (validated.Entries.Count != archive.Entries.Count)
            {
                throw new InvalidDataException(
                    "The rewritten GFL entry count changed.");
            }
            foreach (var sourceEntry in archive.Entries)
            {
                var outputEntry = validated.Entries[sourceEntry.Index];
                var expectedLength = LegacyBriefingNames.Contains(
                    sourceEntry.OriginalName)
                    ? 0u
                    : sourceEntry.Length;
                if (outputEntry.OriginalName != sourceEntry.OriginalName ||
                    outputEntry.Attributes != sourceEntry.Attributes ||
                    outputEntry.Length != expectedLength)
                {
                    throw new InvalidDataException(
                        $"The rewritten GFL entry {sourceEntry.Index} " +
                        "does not preserve its metadata.");
                }
            }

            File.Move(resourceTemporary, outputResource);
            File.Move(indexTemporary, outputIndex);
            return new GflBriefingRemovalReport(
                outputResource,
                outputIndex,
                validated.Entries.Count,
                new ReadOnlyCollection<int>(
                    briefingEntries.Select(entry => entry.Index).ToArray()),
                briefingEntries.Sum(entry => (long)entry.Length),
                new FileInfo(outputResource).Length);
        }
        catch
        {
            TryDelete(resourceTemporary);
            TryDelete(indexTemporary);
            TryDelete(outputResource);
            TryDelete(outputIndex);
            throw;
        }
    }

    private static IReadOnlyList<RewrittenEntry> RewriteResourceArchive(
        GflArchive archive,
        string sourcePath,
        string outputPath)
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
        using var writer = new BinaryWriter(
            output,
            System.Text.Encoding.ASCII,
            leaveOpen: true);
        var buffer = new byte[1024 * 1024];
        var rewritten = new List<RewrittenEntry>(
            archive.Entries.Count);
        foreach (var entry in archive.Entries)
        {
            source.Position = entry.RecordOffset;
            var metadata = new byte[EntryMetadataSize];
            source.ReadExactly(metadata);
            output.Write(metadata);
            var cleared = LegacyBriefingNames.Contains(
                entry.OriginalName);
            var outputLength = cleared ? 0u : entry.Length;
            writer.Write(outputLength);
            var outputDataOffset = checked((uint)output.Position);
            if (!cleared)
            {
                CopyExactly(
                    source,
                    output,
                    entry.DataOffset,
                    entry.Length,
                    buffer);
            }
            rewritten.Add(new RewrittenEntry(
                metadata,
                outputLength,
                outputDataOffset));
        }
        output.Flush(flushToDisk: true);
        return new ReadOnlyCollection<RewrittenEntry>(rewritten);
    }

    private static void RewriteIndexArchive(
        string sourcePath,
        IReadOnlyList<RewrittenEntry> entries,
        string outputPath)
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
        using var writer = new BinaryWriter(
            output,
            System.Text.Encoding.ASCII,
            leaveOpen: true);
        foreach (var entry in entries)
        {
            output.Write(entry.Metadata);
            writer.Write(entry.Length);
            writer.Write(entry.DataOffset);
        }
        output.Flush(flushToDisk: true);
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
            var requested = (int)Math.Min(buffer.Length, remaining);
            var read = source.Read(buffer, 0, requested);
            if (read == 0)
            {
                throw new EndOfStreamException(
                    "The GFL payload ended during rewrite.");
            }
            destination.Write(buffer, 0, read);
            remaining -= read;
        }
    }

    private static void EnsureDistinctPaths(
        params string[] paths)
    {
        if (paths.Distinct(
                StringComparer.OrdinalIgnoreCase).Count() != paths.Length)
        {
            throw new ArgumentException(
                "GFL rewrite source and output paths must be distinct.");
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
            // Preserve the original rewrite exception.
        }
    }

    private sealed record RewrittenEntry(
        byte[] Metadata,
        uint Length,
        uint DataOffset);
}
