using System.Text.Json;
using System.Text.Json.Serialization;

namespace Mission1937.MapEditor.Core;

public sealed class MapRegionAsset
{
    public int SchemaVersion { get; set; } = 1;
    public string Name { get; set; } = "未命名区域";
    public int Width { get; set; }
    public int Height { get; set; }
    public List<EditorLayer> Layers { get; set; } = [];
    public List<MapObject> Objects { get; set; } = [];
    public string SourceMap { get; set; } = "";
}

public sealed record RegionPasteResult(
    IReadOnlyList<string> NewObjectIds,
    IReadOnlyDictionary<string, string> IdRebindings,
    int ChangedCells);

public static class RegionLibraryService
{
    private static readonly JsonSerializerOptions Options = new()
    {
        WriteIndented = true,
        PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower,
        Converters = { new JsonStringEnumConverter(JsonNamingPolicy.SnakeCaseLower) }
    };

    public static MapRegionAsset Capture(
        MapDocument document,
        string name,
        int left,
        int top,
        int right,
        int bottom)
    {
        var x1 = Math.Clamp(Math.Min(left, right), 0, document.Width - 1);
        var x2 = Math.Clamp(Math.Max(left, right), 0, document.Width - 1);
        var y1 = Math.Clamp(Math.Min(top, bottom), 0, document.Height - 1);
        var y2 = Math.Clamp(Math.Max(top, bottom), 0, document.Height - 1);
        var width = x2 - x1 + 1;
        var height = y2 - y1 + 1;
        var region = new MapRegionAsset
        {
            Name = name,
            Width = width,
            Height = height,
            SourceMap = document.Name
        };
        foreach (var layer in document.Layers)
        {
            var output = new EditorLayer
            {
                Name = layer.Name,
                Kind = layer.Kind,
                Visible = layer.Visible,
                Locked = false,
                Opacity = layer.Opacity,
                Cells = new int[width * height]
            };
            for (var y = 0; y < height; ++y)
            for (var x = 0; x < width; ++x)
                output.Cells[y * width + x] =
                    layer.Cells[(y + y1) * document.Width + x + x1];
            region.Layers.Add(output);
        }
        var selected = document.Objects.Where(item =>
            item.X >= x1 && item.X <= x2 &&
            item.Y >= y1 && item.Y <= y2).ToArray();
        var wrapper = RegionWrapper(document, selected);
        foreach (var item in MapDocumentSerializer.Clone(wrapper).Objects)
        {
            item.Properties["region_source_id"] = item.Id;
            item.X -= x1;
            item.Y -= y1;
            foreach (var point in item.PatrolWaypoints)
            {
                point.X -= x1;
                point.Y -= y1;
            }
            region.Objects.Add(item);
        }
        return region;
    }

    public static RegionPasteResult Paste(
        MapDocument document,
        MapRegionAsset region,
        int targetX,
        int targetY,
        bool overwriteCells = false)
    {
        Validate(region);
        var idMap = new Dictionary<string, string>(
            StringComparer.OrdinalIgnoreCase);
        var newIds = new List<string>();
        var nextScene = document.Objects
            .Select(item => TrySceneIndex(item.Id))
            .Where(value => value >= 0)
            .DefaultIfEmpty(-1)
            .Max() + 1;
        var changedCells = 0;
        foreach (var sourceLayer in region.Layers)
        {
            var targetLayer = document.Layer(sourceLayer.Kind);
            if (targetLayer.Locked)
                throw new InvalidOperationException(
                    $"图层“{targetLayer.Name}”已锁定，不能粘贴区域。");
            for (var y = 0; y < region.Height; ++y)
            for (var x = 0; x < region.Width; ++x)
            {
                var destinationX = targetX + x;
                var destinationY = targetY + y;
                if (destinationX < 0 || destinationY < 0 ||
                    destinationX >= document.Width ||
                    destinationY >= document.Height)
                    continue;
                var value = sourceLayer.Cells[y * region.Width + x];
                if (!overwriteCells && value == 0)
                    continue;
                var index = document.Index(destinationX, destinationY);
                if (targetLayer.Cells[index] == value)
                    continue;
                targetLayer.Cells[index] = value;
                ++changedCells;
            }
        }

        var wrapper = RegionWrapper(document, region.Objects);
        foreach (var clone in MapDocumentSerializer.Clone(wrapper).Objects)
        {
            var originalId = clone.Id;
            var newId = originalId.StartsWith(
                "scene-", StringComparison.OrdinalIgnoreCase)
                ? $"scene-{nextScene++}"
                : Guid.NewGuid().ToString("N");
            idMap[originalId] = newId;
            clone.Id = newId;
            clone.X += targetX;
            clone.Y += targetY;
            foreach (var point in clone.PatrolWaypoints)
            {
                point.X += targetX;
                point.Y += targetY;
            }
            if (clone.X < 0 || clone.Y < 0 ||
                clone.X >= document.Width || clone.Y >= document.Height)
                continue;
            clone.PatrolWaypoints.RemoveAll(point =>
                point.X < 0 || point.Y < 0 ||
                point.X >= document.Width ||
                point.Y >= document.Height);
            clone.Properties["region_source_id"] = originalId;
            if (newId.StartsWith("scene-", StringComparison.OrdinalIgnoreCase))
                clone.Properties["scene_index"] = newId[6..];
            document.Objects.Add(clone);
            newIds.Add(newId);
        }
        return new RegionPasteResult(newIds, idMap, changedCells);
    }

    public static void Save(MapRegionAsset region, string path)
    {
        Validate(region);
        Directory.CreateDirectory(Path.GetDirectoryName(
            Path.GetFullPath(path))!);
        var temporary = path + ".tmp";
        File.WriteAllText(
            temporary,
            JsonSerializer.Serialize(region, Options));
        _ = Load(temporary);
        File.Move(temporary, path, true);
    }

    public static MapRegionAsset Load(string path)
    {
        var region = JsonSerializer.Deserialize<MapRegionAsset>(
            File.ReadAllText(path), Options)
            ?? throw new InvalidDataException("区域素材没有有效内容。");
        Validate(region);
        return region;
    }

    private static void Validate(MapRegionAsset region)
    {
        if (region.SchemaVersion != 1)
            throw new InvalidDataException("不支持的区域素材版本。");
        if (region.Width <= 0 || region.Height <= 0)
            throw new InvalidDataException("区域素材尺寸无效。");
        foreach (var layer in region.Layers)
        {
            if (layer.Cells.Length != region.Width * region.Height)
                throw new InvalidDataException(
                    $"区域图层 {layer.Name} 格点数无效。");
        }
    }

    private static MapDocument RegionWrapper(
        MapDocument template,
        IEnumerable<MapObject> objects) =>
        new()
        {
            Name = "region-wrapper",
            Width = template.Width,
            Height = template.Height,
            CellSize = template.CellSize,
            CellWidth = template.CellWidth,
            CellHeight = template.CellHeight,
            Layers = template.Layers.Select(layer => new EditorLayer
            {
                Name = layer.Name,
                Kind = layer.Kind,
                Cells = new int[template.Width * template.Height]
            }).ToList(),
            Objects = objects.ToList()
        };

    private static int TrySceneIndex(string id) =>
        id.StartsWith("scene-", StringComparison.OrdinalIgnoreCase) &&
        int.TryParse(id[6..], out var value)
            ? value
            : -1;
}
