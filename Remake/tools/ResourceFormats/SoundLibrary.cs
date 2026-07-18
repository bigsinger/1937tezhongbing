using System.Collections.ObjectModel;
using System.Text;

namespace Mission1937.Remake.Resources;

public sealed record SoundLibraryEntry(int Index, uint UnknownFlag, string FileName);

public sealed class SoundLibrary
{
    public const int HeaderSize = 121;
    public const int RecordSize = 260;
    private const int CountOffset = 117;
    private const string Magic = "SLF1 Intuition Engine Professional Sound Library";

    private SoundLibrary(string path, IReadOnlyList<SoundLibraryEntry> entries)
    {
        Path = path;
        Entries = entries;
    }

    public string Path { get; }

    public IReadOnlyList<SoundLibraryEntry> Entries { get; }

    public static SoundLibrary Open(string path)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(path);
        var fullPath = System.IO.Path.GetFullPath(path);
        using var stream = new FileStream(fullPath, FileMode.Open, FileAccess.Read, FileShare.Read);
        if (stream.Length < HeaderSize)
        {
            throw new InvalidDataException("The sound library is shorter than its fixed header.");
        }

        var header = new byte[HeaderSize];
        stream.ReadExactly(header);
        if (!Encoding.ASCII.GetString(header).StartsWith(Magic, StringComparison.Ordinal))
        {
            throw new InvalidDataException("The file does not contain the expected SLF1 header.");
        }

        var count = BitConverter.ToUInt32(header, CountOffset);
        var expectedLength = checked(HeaderSize + (long)count * RecordSize);
        if (stream.Length != expectedLength)
        {
            throw new InvalidDataException(
                $"The SLF record count predicts {expectedLength} bytes, actual length is {stream.Length}.");
        }

        var entries = new List<SoundLibraryEntry>(checked((int)count));
        using var reader = new BinaryReader(stream, Encoding.ASCII, leaveOpen: true);
        for (var index = 0; index < count; index++)
        {
            var flag = reader.ReadUInt32();
            var nameField = reader.ReadBytes(256);
            if (nameField.Length != 256)
            {
                throw new EndOfStreamException("Unexpected EOF in SLF name field.");
            }

            entries.Add(new SoundLibraryEntry(
                index,
                flag,
                LegacyNameCodec.DecodeNullTerminatedGbk(nameField)));
        }

        return new SoundLibrary(fullPath, new ReadOnlyCollection<SoundLibraryEntry>(entries));
    }
}
