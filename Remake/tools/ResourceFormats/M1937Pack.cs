using System.IO.Compression;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace Mission1937.Remake.Resources;

public sealed record M1937PackFile(
    string Path,
    long Length,
    string Sha256);

public sealed class M1937PackManifest
{
    public const int CurrentSchemaVersion = 1;

    public int SchemaVersion { get; set; } = CurrentSchemaVersion;
    public string PackId { get; set; } = "";
    public string Version { get; set; } = "1.0.0";
    public string DisplayName { get; set; } = "";
    public string MinimumRuntimeVersion { get; set; } = "1.0.0";
    public List<string> LevelEntries { get; set; } = [];
    public List<string> Dependencies { get; set; } = [];
    public List<string> Conflicts { get; set; } = [];
    public string SourceDeclaration { get; set; } = "synthetic-or-user-owned";
    public List<string> Capabilities { get; set; } = [];
    public List<M1937PackFile> Files { get; set; } = [];
}

public sealed record M1937PackValidationResult(
    M1937PackManifest Manifest,
    string PackageSha256,
    long TotalUncompressedBytes,
    int EntryCount);

/// <summary>
/// Deterministic, declarative and deliberately non-executable Remake content
/// packages. Validation never trusts ZipArchive extraction paths and always
/// verifies the manifest's byte length and SHA-256 for every payload.
/// </summary>
public static class M1937Pack
{
    public const string Extension = ".m1937pack";
    public const int MaximumEntries = 8192;
    public const long MaximumSingleFileBytes = 64L * 1024 * 1024;
    public const long MaximumTotalBytes = 512L * 1024 * 1024;
    public const long MaximumManifestBytes = 2L * 1024 * 1024;

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
        PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower,
        PropertyNameCaseInsensitive = false
    };

    private static readonly HashSet<string> AllowedExtensions = new(
        [
            ".json", ".bin", ".png", ".webp", ".jpg", ".jpeg",
            ".wav", ".ogg", ".mp3", ".md", ".txt"
        ],
        StringComparer.OrdinalIgnoreCase);

    private static readonly HashSet<string> ForbiddenExtensions = new(
        [
            ".gd", ".gdscript", ".cs", ".dll", ".exe", ".com",
            ".bat", ".cmd", ".ps1", ".vbs", ".js", ".msi", ".pck",
            ".so", ".dylib", ".lnk", ".url"
        ],
        StringComparer.OrdinalIgnoreCase);
    private static readonly DateTimeOffset DeterministicZipTimestamp =
        new(1980, 1, 1, 0, 0, 0, TimeSpan.Zero);

    public static M1937PackValidationResult Build(
        string sourceDirectory,
        string outputPath)
    {
        var source = Path.GetFullPath(sourceDirectory);
        if (!Directory.Exists(source))
            throw new DirectoryNotFoundException(source);
        var manifestPath = Path.Combine(source, "manifest.json");
        if (!File.Exists(manifestPath))
            throw new InvalidDataException("manifest.json is required.");
        if (!File.Exists(Path.Combine(source, "campaign.json")))
            throw new InvalidDataException("campaign.json is required.");

        var manifest = ReadManifest(File.ReadAllBytes(manifestPath));
        ValidateManifestIdentity(manifest);
        var payloads = Directory.EnumerateFiles(
                source,
                "*",
                SearchOption.AllDirectories)
            .Select(path => new
            {
                FullPath = path,
                RelativePath = NormalizeRelativePath(
                    Path.GetRelativePath(source, path).Replace(
                        Path.DirectorySeparatorChar,
                        '/'))
            })
            .Where(value => !value.RelativePath.Equals(
                "manifest.json",
                StringComparison.OrdinalIgnoreCase))
            .OrderBy(value => value.RelativePath, StringComparer.Ordinal)
            .ToArray();
        ValidateEntrySet(payloads.Select(value => value.RelativePath));

        long totalBytes = 0;
        manifest.Files = [];
        foreach (var payload in payloads)
        {
            var info = new FileInfo(payload.FullPath);
            ValidatePayloadLimits(payload.RelativePath, info.Length, ref totalBytes);
            M1937PackContentPolicy.Validate(
                payload.RelativePath,
                File.ReadAllBytes(payload.FullPath));
            manifest.Files.Add(new M1937PackFile(
                payload.RelativePath,
                info.Length,
                FileSha256(payload.FullPath)));
        }
        ValidateManifestReferences(manifest, payloads.Select(value => value.RelativePath));

        var output = Path.GetFullPath(outputPath);
        if (!output.EndsWith(Extension, StringComparison.OrdinalIgnoreCase))
            throw new ArgumentException($"Output must use {Extension}.", nameof(outputPath));
        var outputDirectory = Path.GetDirectoryName(output)
            ?? throw new ArgumentException("Output has no parent directory.", nameof(outputPath));
        Directory.CreateDirectory(outputDirectory);
        var temporary = output + ".tmp-" + Guid.NewGuid().ToString("N");
        try
        {
            using (var stream = new FileStream(
                temporary,
                FileMode.CreateNew,
                FileAccess.ReadWrite,
                FileShare.None))
            using (var archive = new ZipArchive(
                stream,
                ZipArchiveMode.Create,
                leaveOpen: false,
                entryNameEncoding: Encoding.UTF8))
            {
                WriteEntry(
                    archive,
                    "manifest.json",
                    JsonSerializer.SerializeToUtf8Bytes(manifest, JsonOptions));
                foreach (var payload in payloads)
                {
                    var entry = archive.CreateEntry(
                        payload.RelativePath,
                        CompressionLevel.Optimal);
                    entry.LastWriteTime = DeterministicZipTimestamp;
                    using var input = File.OpenRead(payload.FullPath);
                    using var target = entry.Open();
                    input.CopyTo(target);
                }
            }
            File.Move(temporary, output, overwrite: true);
        }
        finally
        {
            if (File.Exists(temporary))
                File.Delete(temporary);
        }
        return Validate(output);
    }

    public static M1937PackValidationResult Validate(string packagePath)
    {
        var package = Path.GetFullPath(packagePath);
        if (!File.Exists(package))
            throw new FileNotFoundException("Content package is missing.", package);
        if (!package.EndsWith(Extension, StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException($"Content package must use {Extension}.");

        using var stream = new FileStream(
            package,
            FileMode.Open,
            FileAccess.Read,
            FileShare.Read);
        using var archive = new ZipArchive(
            stream,
            ZipArchiveMode.Read,
            leaveOpen: false,
            entryNameEncoding: Encoding.UTF8);
        if (archive.Entries.Count is < 2 or > MaximumEntries)
            throw new InvalidDataException(
                $"Package entry count must be 2..{MaximumEntries}.");

        var normalizedEntries = new Dictionary<string, ZipArchiveEntry>(
            StringComparer.OrdinalIgnoreCase);
        long totalBytes = 0;
        foreach (var entry in archive.Entries)
        {
            var normalized = NormalizeRelativePath(entry.FullName);
            if (!normalizedEntries.TryAdd(normalized, entry))
                throw new InvalidDataException(
                    $"Duplicate case-insensitive package path: {normalized}");
            if (IsSymbolicLink(entry))
                throw new InvalidDataException(
                    $"Symbolic links are forbidden: {normalized}");
            ValidatePayloadLimits(normalized, entry.Length, ref totalBytes);
        }

        if (!normalizedEntries.TryGetValue("manifest.json", out var manifestEntry))
            throw new InvalidDataException("manifest.json is required.");
        if (manifestEntry.Length > MaximumManifestBytes)
            throw new InvalidDataException("manifest.json exceeds its size limit.");
        if (!normalizedEntries.ContainsKey("campaign.json"))
            throw new InvalidDataException("campaign.json is required.");

        var manifest = ReadManifest(ReadEntryBytes(manifestEntry, MaximumManifestBytes));
        ValidateManifestIdentity(manifest);
        var payloadEntries = normalizedEntries
            .Where(pair => !pair.Key.Equals(
                "manifest.json",
                StringComparison.OrdinalIgnoreCase))
            .ToDictionary(pair => pair.Key, pair => pair.Value, StringComparer.OrdinalIgnoreCase);
        ValidateManifestReferences(manifest, payloadEntries.Keys);
        if (manifest.Files.Count != payloadEntries.Count)
            throw new InvalidDataException(
                "Manifest file list must describe every payload exactly once.");

        var declaredPaths = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var declared in manifest.Files)
        {
            var path = NormalizeRelativePath(declared.Path);
            if (!declaredPaths.Add(path))
                throw new InvalidDataException($"Duplicate manifest file: {path}");
            if (!payloadEntries.TryGetValue(path, out var entry))
                throw new InvalidDataException($"Manifest payload is missing: {path}");
            if (declared.Length != entry.Length)
                throw new InvalidDataException($"Length mismatch: {path}");
            var actualHash = EntrySha256(entry);
            if (!IsSha256(declared.Sha256) || !actualHash.Equals(
                    declared.Sha256,
                    StringComparison.OrdinalIgnoreCase))
                throw new InvalidDataException($"SHA-256 mismatch: {path}");
            M1937PackContentPolicy.Validate(
                path,
                ReadEntryBytes(entry, MaximumSingleFileBytes));
        }

        return new M1937PackValidationResult(
            manifest,
            FileSha256(package),
            totalBytes,
            archive.Entries.Count);
    }

    public static M1937PackValidationResult ExtractSafe(
        string packagePath,
        string outputDirectory)
    {
        var validation = Validate(packagePath);
        var destination = Path.GetFullPath(outputDirectory);
        Directory.CreateDirectory(destination);
        if (Directory.EnumerateFileSystemEntries(destination).Any())
            throw new IOException("Safe extraction requires an empty destination directory.");
        using var archive = ZipFile.OpenRead(Path.GetFullPath(packagePath));
        foreach (var entry in archive.Entries.OrderBy(value => value.FullName, StringComparer.Ordinal))
        {
            var relative = NormalizeRelativePath(entry.FullName);
            var target = Path.GetFullPath(Path.Combine(
                destination,
                relative.Replace('/', Path.DirectorySeparatorChar)));
            EnsureContained(destination, target);
            Directory.CreateDirectory(Path.GetDirectoryName(target)!);
            var temporary = target + ".tmp-" + Guid.NewGuid().ToString("N");
            using (var input = entry.Open())
            using (var output = new FileStream(
                temporary,
                FileMode.CreateNew,
                FileAccess.Write,
                FileShare.None))
                input.CopyTo(output);
            File.Move(temporary, target, overwrite: false);
        }
        return validation;
    }

    public static string Hash(string packagePath) =>
        FileSha256(Path.GetFullPath(packagePath));

    public static string ManifestJson(M1937PackManifest manifest) =>
        JsonSerializer.Serialize(manifest, JsonOptions);

    private static M1937PackManifest ReadManifest(byte[] bytes)
    {
        try
        {
            return JsonSerializer.Deserialize<M1937PackManifest>(bytes, JsonOptions)
                ?? throw new InvalidDataException("manifest.json is empty.");
        }
        catch (JsonException exception)
        {
            throw new InvalidDataException("manifest.json is invalid JSON.", exception);
        }
    }

    private static void ValidateManifestIdentity(M1937PackManifest manifest)
    {
        if (manifest.SchemaVersion != M1937PackManifest.CurrentSchemaVersion)
            throw new InvalidDataException(
                $"Unsupported manifest schema {manifest.SchemaVersion}.");
        if (!IsIdentifier(manifest.PackId))
            throw new InvalidDataException(
                "pack_id must use 3..64 lowercase ASCII letters, digits, dots, underscores or hyphens.");
        if (string.IsNullOrWhiteSpace(manifest.DisplayName) || manifest.DisplayName.Length > 128)
            throw new InvalidDataException("display_name must contain 1..128 characters.");
        if (!M1937PackContentPolicy.IsSemanticVersion(manifest.Version))
            throw new InvalidDataException("version must be a semantic version.");
        if (!M1937PackContentPolicy.IsSemanticVersion(manifest.MinimumRuntimeVersion))
            throw new InvalidDataException(
                "minimum_runtime_version must be a semantic version.");
        if (manifest.LevelEntries.Count is < 1 or > 128)
            throw new InvalidDataException("level_entries must contain 1..128 entries.");
        if (string.IsNullOrWhiteSpace(manifest.SourceDeclaration) ||
            manifest.SourceDeclaration.Length > 512)
            throw new InvalidDataException(
                "source_declaration must contain 1..512 characters.");
        ValidateIdentifierList(manifest.Dependencies, "dependencies", manifest.PackId);
        ValidateIdentifierList(manifest.Conflicts, "conflicts", manifest.PackId);
        var overlap = manifest.Dependencies.Intersect(
            manifest.Conflicts,
            StringComparer.Ordinal).FirstOrDefault();
        if (overlap is not null)
            throw new InvalidDataException(
                $"Package cannot both depend on and conflict with '{overlap}'.");
        if (manifest.Capabilities.Count > 64 || manifest.Capabilities.Any(value =>
                !IsIdentifier(value)))
            throw new InvalidDataException(
                "capabilities must contain at most 64 valid identifiers.");
    }

    private static void ValidateIdentifierList(
        IReadOnlyList<string> values,
        string field,
        string packId)
    {
        if (values.Count > 128)
            throw new InvalidDataException($"{field} exceeds 128 entries.");
        var unique = new HashSet<string>(StringComparer.Ordinal);
        foreach (var value in values)
        {
            if (!IsIdentifier(value) || !unique.Add(value) || value == packId)
                throw new InvalidDataException($"Invalid {field} entry: {value}");
        }
    }

    private static void ValidateManifestReferences(
        M1937PackManifest manifest,
        IEnumerable<string> payloadPaths)
    {
        var paths = payloadPaths.ToHashSet(StringComparer.OrdinalIgnoreCase);
        foreach (var level in manifest.LevelEntries)
        {
            var normalized = NormalizeRelativePath(level);
            if (!normalized.StartsWith("levels/", StringComparison.Ordinal) ||
                !normalized.EndsWith("/level.json", StringComparison.Ordinal) ||
                !paths.Contains(normalized))
                throw new InvalidDataException(
                    $"Level entry must reference levels/<id>/level.json: {level}");
        }
        if (!paths.Contains("campaign.json"))
            throw new InvalidDataException("campaign.json is not declared as a payload.");
    }

    private static void ValidateEntrySet(IEnumerable<string> paths)
    {
        var unique = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var count = 1; // manifest
        foreach (var path in paths)
        {
            count++;
            if (count > MaximumEntries)
                throw new InvalidDataException($"Package exceeds {MaximumEntries} entries.");
            if (!unique.Add(NormalizeRelativePath(path)))
                throw new InvalidDataException(
                    $"Duplicate case-insensitive package path: {path}");
        }
    }

    private static void ValidatePayloadLimits(
        string relativePath,
        long length,
        ref long totalBytes)
    {
        ValidateAllowedExtension(relativePath);
        if (length < 0 || length > MaximumSingleFileBytes)
            throw new InvalidDataException(
                $"Payload exceeds {MaximumSingleFileBytes} bytes: {relativePath}");
        totalBytes = checked(totalBytes + length);
        if (totalBytes > MaximumTotalBytes)
            throw new InvalidDataException(
                $"Package exceeds {MaximumTotalBytes} uncompressed bytes.");
    }

    private static void ValidateAllowedExtension(string relativePath)
    {
        var extension = Path.GetExtension(relativePath);
        if (ForbiddenExtensions.Contains(extension) || !AllowedExtensions.Contains(extension))
            throw new InvalidDataException(
                $"Forbidden or unsupported payload extension '{extension}': {relativePath}");
    }

    public static string NormalizeRelativePath(string path)
    {
        if (string.IsNullOrWhiteSpace(path))
            throw new InvalidDataException("Package path is empty.");
        if (path.Contains('\\'))
            throw new InvalidDataException($"Backslashes are forbidden in package paths: {path}");
        if (path.StartsWith('/') || Path.IsPathRooted(path) || path.Contains(':'))
            throw new InvalidDataException($"Absolute package path is forbidden: {path}");
        var segments = path.Split('/');
        if (segments.Any(segment =>
                segment.Length == 0 || segment is "." or ".." ||
                segment.EndsWith(' ') || segment.EndsWith('.')))
            throw new InvalidDataException($"Unsafe package path: {path}");
        if (segments.Any(segment => segment.IndexOfAny(Path.GetInvalidFileNameChars()) >= 0))
            throw new InvalidDataException($"Invalid package path: {path}");
        return string.Join('/', segments);
    }

    private static bool IsIdentifier(string value) =>
        value.Length is >= 3 and <= 64 &&
        value.All(character =>
            character is >= 'a' and <= 'z' or >= '0' and <= '9' or '.' or '_' or '-');

    private static bool IsSha256(string value) =>
        value.Length == 64 && value.All(Uri.IsHexDigit);

    private static bool IsSymbolicLink(ZipArchiveEntry entry) =>
        ((entry.ExternalAttributes >> 16) & 0xF000) == 0xA000;

    private static byte[] ReadEntryBytes(ZipArchiveEntry entry, long maximum)
    {
        if (entry.Length > maximum)
            throw new InvalidDataException($"Entry is too large: {entry.FullName}");
        using var input = entry.Open();
        using var output = new MemoryStream((int)entry.Length);
        input.CopyTo(output);
        if (output.Length != entry.Length)
            throw new InvalidDataException($"Truncated ZIP entry: {entry.FullName}");
        return output.ToArray();
    }

    private static string EntrySha256(ZipArchiveEntry entry)
    {
        using var input = entry.Open();
        return Convert.ToHexString(SHA256.HashData(input)).ToLowerInvariant();
    }

    private static string FileSha256(string path)
    {
        using var input = File.OpenRead(path);
        return Convert.ToHexString(SHA256.HashData(input)).ToLowerInvariant();
    }

    private static void WriteEntry(
        ZipArchive archive,
        string name,
        byte[] bytes)
    {
        var entry = archive.CreateEntry(name, CompressionLevel.Optimal);
        entry.LastWriteTime = DeterministicZipTimestamp;
        using var output = entry.Open();
        output.Write(bytes);
    }

    private static void EnsureContained(string root, string path)
    {
        var prefix = root.TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
        if (!path.StartsWith(prefix, StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("Extraction target escaped its destination.");
    }
}
