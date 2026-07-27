using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Mission1937.MapEditor.Core;

public sealed record MapAutosaveSnapshot(
    int SchemaVersion,
    DateTimeOffset SavedUtc,
    string SourcePath,
    string SourceSha256,
    MapDocument Document);

public sealed record MapRecoveryCandidate(
    string AutosavePath,
    DateTimeOffset SavedUtc,
    string SourcePath,
    bool SourceChanged,
    MapDocument Document);

public static class MapAutosaveService
{
    private static readonly JsonSerializerOptions Options = new()
    {
        WriteIndented = true,
        PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower,
        Converters = { new JsonStringEnumConverter(JsonNamingPolicy.SnakeCaseLower) }
    };

    public static string AutosavePath(string recoveryRoot, string sourcePath)
    {
        var fullSource = Path.GetFullPath(sourcePath);
        var key = Convert.ToHexString(
            SHA256.HashData(Encoding.UTF8.GetBytes(
                fullSource.ToUpperInvariant())))[..20];
        var name = Path.GetFileNameWithoutExtension(fullSource);
        return Path.Combine(
            Path.GetFullPath(recoveryRoot),
            $"{SafeFileName(name)}-{key}.autosave.json");
    }

    public static string Save(
        MapDocument document,
        string recoveryRoot,
        string? sourcePath)
    {
        ArgumentNullException.ThrowIfNull(document);
        var logicalSource = string.IsNullOrWhiteSpace(sourcePath)
            ? Path.Combine(recoveryRoot, "untitled.m37map.json")
            : Path.GetFullPath(sourcePath);
        var output = AutosavePath(recoveryRoot, logicalSource);
        Directory.CreateDirectory(Path.GetDirectoryName(output)!);
        var snapshot = new MapAutosaveSnapshot(
            1,
            DateTimeOffset.UtcNow,
            logicalSource,
            FileSha256(logicalSource),
            MapDocumentSerializer.Clone(document));
        AtomicWrite(
            output,
            JsonSerializer.Serialize(snapshot, Options));
        return output;
    }

    public static MapRecoveryCandidate? Inspect(string autosavePath)
    {
        if (!File.Exists(autosavePath))
            return null;
        var snapshot = JsonSerializer.Deserialize<MapAutosaveSnapshot>(
            File.ReadAllText(autosavePath), Options);
        if (snapshot is null || snapshot.SchemaVersion != 1)
            throw new InvalidDataException("不支持的自动保存快照。");
        MapValidator.ThrowIfInvalid(snapshot.Document);
        return new MapRecoveryCandidate(
            Path.GetFullPath(autosavePath),
            snapshot.SavedUtc,
            snapshot.SourcePath,
            !string.Equals(
                snapshot.SourceSha256,
                FileSha256(snapshot.SourcePath),
                StringComparison.OrdinalIgnoreCase),
            snapshot.Document);
    }

    public static IReadOnlyList<MapRecoveryCandidate> FindCandidates(
        string recoveryRoot)
    {
        if (!Directory.Exists(recoveryRoot))
            return [];
        var result = new List<MapRecoveryCandidate>();
        foreach (var file in Directory.EnumerateFiles(
                     recoveryRoot, "*.autosave.json"))
        {
            try
            {
                var candidate = Inspect(file);
                if (candidate is not null)
                    result.Add(candidate);
            }
            catch (InvalidDataException)
            {
                // A corrupt autosave must never prevent the editor opening.
            }
            catch (JsonException)
            {
            }
        }
        return result
            .OrderByDescending(item => item.SavedUtc)
            .ToArray();
    }

    public static void Discard(string autosavePath)
    {
        if (File.Exists(autosavePath))
            File.Delete(autosavePath);
    }

    private static void AtomicWrite(string path, string content)
    {
        var temporary = path + ".tmp";
        File.WriteAllText(temporary, content, new UTF8Encoding(false));
        // Parsing the temporary file is the commit gate.
        _ = JsonSerializer.Deserialize<MapAutosaveSnapshot>(
            File.ReadAllText(temporary), Options)
            ?? throw new InvalidDataException("自动保存写入校验失败。");
        File.Move(temporary, path, true);
    }

    private static string FileSha256(string path)
    {
        if (!File.Exists(path))
            return "";
        using var stream = File.OpenRead(path);
        return Convert.ToHexString(SHA256.HashData(stream));
    }

    private static string SafeFileName(string value)
    {
        var invalid = Path.GetInvalidFileNameChars().ToHashSet();
        var result = new string(value
            .Select(character => invalid.Contains(character) ? '_' : character)
            .ToArray());
        return string.IsNullOrWhiteSpace(result) ? "untitled" : result;
    }
}
