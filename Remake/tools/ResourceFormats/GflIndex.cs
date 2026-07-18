using System.Collections.ObjectModel;
using System.Text;

namespace Mission1937.Remake.Resources;

public sealed record GflIndexEntry(
    int Index,
    string OriginalName,
    uint Attributes,
    uint Length,
    uint DataOffset);

public sealed class GflIndex
{
    public const int HeaderSize = 0x4E;
    public const int RecordSize = 267;
    private const string Magic = "GFL (Game File Library) Win32/V1.0";

    private GflIndex(string path, IReadOnlyList<GflIndexEntry> entries)
    {
        Path = path;
        Entries = entries;
    }

    public string Path { get; }

    public IReadOnlyList<GflIndexEntry> Entries { get; }

    public static GflIndex Open(string path)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(path);
        var fullPath = System.IO.Path.GetFullPath(path);
        using var stream = new FileStream(fullPath, FileMode.Open, FileAccess.Read, FileShare.Read);
        if (stream.Length < HeaderSize || (stream.Length - HeaderSize) % RecordSize != 0)
        {
            throw new InvalidDataException("The GFL index length does not match its fixed record layout.");
        }

        var header = new byte[HeaderSize];
        stream.ReadExactly(header);
        if (!Encoding.ASCII.GetString(header).StartsWith(Magic, StringComparison.Ordinal))
        {
            throw new InvalidDataException("The file does not contain the expected GFL index header.");
        }

        var count = checked((int)((stream.Length - HeaderSize) / RecordSize));
        var entries = new List<GflIndexEntry>(count);
        using var reader = new BinaryReader(stream, Encoding.ASCII, leaveOpen: true);
        for (var index = 0; index < count; index++)
        {
            var nameField = reader.ReadBytes(256);
            if (nameField.Length != 256)
            {
                throw new EndOfStreamException("Unexpected EOF in GFL index name field.");
            }

            var attributes = ReadUInt24(reader);
            var length = reader.ReadUInt32();
            var dataOffset = reader.ReadUInt32();
            entries.Add(new GflIndexEntry(
                index,
                LegacyNameCodec.DecodeObfuscatedName(nameField),
                attributes,
                length,
                dataOffset));
        }

        return new GflIndex(fullPath, new ReadOnlyCollection<GflIndexEntry>(entries));
    }

    private static uint ReadUInt24(BinaryReader reader)
    {
        var bytes = reader.ReadBytes(3);
        if (bytes.Length != 3)
        {
            throw new EndOfStreamException("Unexpected EOF in 24-bit attribute field.");
        }

        return (uint)(bytes[0] | bytes[1] << 8 | bytes[2] << 16);
    }
}
