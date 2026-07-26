using System.IO;
using System.Text.Json;

namespace Mission1937.MapEditor.App;

public sealed class AssetEntry
{
    public int Id { get; set; }
    public string Name { get; set; } = "";
    public string Category { get; set; } = "其他";
    public string Kind { get; set; } = "decoration";
    public string RelativePath { get; set; } = "";
    public string ThumbnailRelativePath { get; set; } = "";
    public string SourceName { get; set; } = "";
    public string ThumbnailPath { get; set; } = "";
}

public sealed class AssetCatalog
{
    public int SchemaVersion { get; set; } = 1;
    public List<AssetEntry> Assets { get; set; } = [];
}

public static class AssetLibrary
{
    public static string? FindRoot()
    {
        var configured = Environment.GetEnvironmentVariable(
            "M1937_MAPEDITOR_ASSETS");
        if (!string.IsNullOrWhiteSpace(configured))
        {
            var full = Path.GetFullPath(configured);
            if (File.Exists(Path.Combine(full, "catalog.json")))
                return full;
        }

        var starts = new[]
        {
            AppContext.BaseDirectory,
            Environment.CurrentDirectory
        };
        foreach (var start in starts)
        {
            var directory = new DirectoryInfo(Path.GetFullPath(start));
            for (var depth = 0; directory is not null && depth < 8;
                 depth++, directory = directory.Parent)
            {
                foreach (var candidate in new[]
                {
                    Path.Combine(directory.FullName, "Assets", "Original"),
                    Path.Combine(
                        directory.FullName, "MapEditor", "Assets", "Original")
                })
                {
                    if (File.Exists(Path.Combine(candidate, "catalog.json")))
                        return candidate;
                }
            }
        }
        return null;
    }

    public static IReadOnlyList<AssetEntry> Load(string? root)
    {
        if (string.IsNullOrWhiteSpace(root))
            return [];
        var catalogPath = Path.Combine(root, "catalog.json");
        if (!File.Exists(catalogPath))
            return [];

        var options = new JsonSerializerOptions
        {
            PropertyNameCaseInsensitive = true,
            PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower
        };
        var catalog = JsonSerializer.Deserialize<AssetCatalog>(
            File.ReadAllText(catalogPath), options) ?? new AssetCatalog();
        foreach (var asset in catalog.Assets)
        {
            var thumbnail = string.IsNullOrWhiteSpace(
                asset.ThumbnailRelativePath)
                ? asset.RelativePath
                : asset.ThumbnailRelativePath;
            asset.ThumbnailPath = Path.GetFullPath(
                Path.Combine(root, thumbnail.Replace('/', '\\')));
        }
        return catalog.Assets;
    }
}
