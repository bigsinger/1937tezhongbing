using System.Text.Json;
using System.Text.Json.Serialization;

namespace Mission1937.MapEditor.Core;

public sealed class AssetPlacementMetadata
{
    public int AssetId { get; set; }
    public string SourceName { get; set; } = "";
    public string Category { get; set; } = "其他";
    public string Kind { get; set; } = "decoration";
    public int FootprintWidth { get; set; } = 1;
    public int FootprintHeight { get; set; } = 1;
    public bool BlocksMovement { get; set; }
    public bool BlocksLineOfSight { get; set; }
    public bool IsDoor { get; set; }
    public string PreferredLayer { get; set; } = "objects";
    public int OcclusionHeight { get; set; }
    public string ValueSource { get; set; } =
        "按原版资源名称和类别推断，可在编辑器中覆盖";
}

public sealed class AssetMetadataCatalog
{
    public int SchemaVersion { get; set; } = 1;
    public List<AssetPlacementMetadata> Assets { get; set; } = [];

    public AssetPlacementMetadata? Find(int assetId) =>
        Assets.FirstOrDefault(item => item.AssetId == assetId);
}

public static class AssetMetadataService
{
    private static readonly JsonSerializerOptions Options = new()
    {
        WriteIndented = true,
        PropertyNameCaseInsensitive = true,
        PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower,
        Converters = { new JsonStringEnumConverter(JsonNamingPolicy.SnakeCaseLower) }
    };

    public static AssetMetadataCatalog Load(string path)
    {
        var catalog = JsonSerializer.Deserialize<AssetMetadataCatalog>(
            File.ReadAllText(path), Options)
            ?? throw new InvalidDataException("素材元数据没有有效内容。");
        if (catalog.SchemaVersion != 1)
            throw new InvalidDataException(
                $"不支持的素材元数据版本 {catalog.SchemaVersion}。");
        var duplicate = catalog.Assets
            .GroupBy(item => item.AssetId)
            .FirstOrDefault(group => group.Count() > 1);
        if (duplicate is not null)
            throw new InvalidDataException(
                $"素材元数据 ID 重复：{duplicate.Key}");
        foreach (var item in catalog.Assets)
        {
            if (item.FootprintWidth <= 0 || item.FootprintHeight <= 0)
                throw new InvalidDataException(
                    $"素材 {item.AssetId} footprint 无效。");
        }
        return catalog;
    }

    public static AssetMetadataCatalog GenerateFromAssetCatalog(
        string catalogPath)
    {
        using var source = JsonDocument.Parse(File.ReadAllText(catalogPath));
        var result = new AssetMetadataCatalog();
        foreach (var asset in source.RootElement
                     .GetProperty("assets").EnumerateArray())
        {
            var id = asset.GetProperty("id").GetInt32();
            var name = Text(asset, "name");
            var sourceName = Text(asset, "source_name");
            var category = Text(asset, "category");
            var kind = Text(asset, "kind");
            result.Assets.Add(Infer(
                id, name, sourceName, category, kind));
        }
        return result;
    }

    public static void Save(AssetMetadataCatalog catalog, string path)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(
            Path.GetFullPath(path))!);
        var temporary = path + ".tmp";
        var json = JsonSerializer.Serialize(catalog, Options)
            .Replace("\r\n", "\n", StringComparison.Ordinal);
        File.WriteAllText(temporary, json);
        _ = Load(temporary);
        File.Move(temporary, path, true);
    }

    public static IReadOnlyList<string> CoverageErrors(
        string assetCatalogPath,
        AssetMetadataCatalog metadata)
    {
        using var source = JsonDocument.Parse(
            File.ReadAllText(assetCatalogPath));
        var expected = source.RootElement.GetProperty("assets")
            .EnumerateArray()
            .Select(asset => asset.GetProperty("id").GetInt32())
            .ToHashSet();
        var actual = metadata.Assets
            .Select(item => item.AssetId)
            .ToHashSet();
        return expected.Except(actual)
            .Select(id => $"素材 {id} 缺少 footprint/遮挡/门/层级/类别元数据。")
            .Concat(actual.Except(expected)
                .Select(id => $"元数据引用未知素材 {id}。"))
            .ToArray();
    }

    private static AssetPlacementMetadata Infer(
        int id,
        string name,
        string sourceName,
        string category,
        string kind)
    {
        var text = $"{name} {sourceName} {category} {kind}";
        var door = ContainsAny(text, "门", "door");
        var building =
            kind == "building" ||
            ContainsAny(text, "房", "屋", "楼", "仓", "站", "塔");
        var wall =
            kind == "wall" ||
            ContainsAny(text, "墙", "栅栏", "铁丝网");
        var vegetation =
            kind == "vegetation" ||
            ContainsAny(text, "树", "灌木", "竹");
        var vehicle =
            kind == "vehicle" ||
            ContainsAny(text, "车", "坦克", "马车");
        var character = kind == "character";
        var terrain =
            kind is "terrain" or "map_background" ||
            category.Contains("地图", StringComparison.OrdinalIgnoreCase);
        var width = building ? 4 :
            vehicle ? 2 :
            vegetation ? 2 :
            1;
        var height = building ? 3 :
            wall ? 2 :
            vehicle || vegetation ? 2 :
            1;
        return new AssetPlacementMetadata
        {
            AssetId = id,
            SourceName = sourceName,
            Category = category,
            Kind = kind,
            FootprintWidth = width,
            FootprintHeight = height,
            BlocksMovement =
                !terrain &&
                (building || wall || vegetation || vehicle || door),
            BlocksLineOfSight =
                building || wall || vegetation,
            IsDoor = door,
            PreferredLayer = terrain ? "terrain" :
                character ? "characters" :
                door ? "doors" :
                building || wall ? "structures" :
                vegetation ? "foreground" :
                "objects",
            OcclusionHeight = building ? 3 :
                wall || vegetation ? 2 :
                vehicle ? 1 :
                0
        };
    }

    private static string Text(JsonElement element, string name) =>
        element.TryGetProperty(name, out var value)
            ? value.GetString() ?? ""
            : "";

    private static bool ContainsAny(string value, params string[] values) =>
        values.Any(item => value.Contains(
            item, StringComparison.OrdinalIgnoreCase));
}
