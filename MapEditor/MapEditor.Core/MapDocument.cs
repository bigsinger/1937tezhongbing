using System.Text.Json;
using System.Text.Json.Serialization;
using Mission1937.Remake.Resources;

namespace Mission1937.MapEditor.Core;

public enum EditorLayerKind
{
    Terrain,
    LineOfSightObstacle,
    MovementObstacle,
    Event,
    ManualMovementCorrection
}

public sealed class EditorLayer
{
    public string Name { get; set; } = "";
    public EditorLayerKind Kind { get; set; }
    public bool Visible { get; set; } = true;
    public int[] Cells { get; set; } = [];
}

public sealed class MapWaypoint
{
    public int X { get; set; }
    public int Y { get; set; }
}

public sealed class MapObject
{
    public string Id { get; set; } = Guid.NewGuid().ToString("N");
    public string Kind { get; set; } = "decoration";
    public string Name { get; set; } = "新对象";
    public string Category { get; set; } = "其他";
    public string AssetPath { get; set; } = "";
    public int X { get; set; }
    public int Y { get; set; }
    public int Direction { get; set; }
    public string Faction { get; set; } = "neutral";
    public Dictionary<string, string> Properties { get; set; } = [];
    public List<MapWaypoint> PatrolWaypoints { get; set; } = [];
    public int PatrolCurrentWaypointIndex { get; set; }
    public bool PatrolEnabled { get; set; }

    [JsonIgnore]
    public bool IsLiving =>
        Kind is "character" or "vehicle" ||
        PatrolWaypoints.Count > 0;
}

public sealed class MissionTask
{
    public string Id { get; set; } = $"task-{Guid.NewGuid():N}";
    public string Title { get; set; } = "新任务";
    public string Description { get; set; } = "";
    public string Trigger { get; set; } = "level_start";
    public string TargetObjectId { get; set; } = "";
    public int RequiredCount { get; set; } = 1;
    public string NextTaskId { get; set; } = "";
    public bool FailureCondition { get; set; }
}

public sealed class MapDocument
{
    public const int CurrentSchemaVersion = 1;

    public int SchemaVersion { get; set; } = CurrentSchemaVersion;
    public string Name { get; set; } = "未命名关卡";
    public int Width { get; set; } = 64;
    public int Height { get; set; } = 48;

    // CellSize remains for compatibility with the first editor release.
    public int CellSize { get; set; } = 20;
    public int CellWidth { get; set; } = 20;
    public int CellHeight { get; set; } = 20;
    public string? ImportedFrom { get; set; }
    public string BackgroundAsset { get; set; } = "";
    public List<EditorLayer> Layers { get; set; } = [];
    public List<MapObject> Objects { get; set; } = [];
    public List<MissionTask> Tasks { get; set; } = [];

    [JsonIgnore]
    public int EffectiveCellWidth => CellWidth > 0 ? CellWidth : CellSize;

    [JsonIgnore]
    public int EffectiveCellHeight => CellHeight > 0 ? CellHeight : CellSize;

    public static MapDocument Create(string name, int width, int height)
    {
        if (width is < 8 or > 2048 || height is < 8 or > 2048)
        {
            throw new ArgumentOutOfRangeException(
                nameof(width), "地图尺寸必须在 8 到 2048 格之间。");
        }
        var count = checked(width * height);
        return new MapDocument
        {
            Name = name,
            Width = width,
            Height = height,
            Layers =
            [
                NewLayer("地表", EditorLayerKind.Terrain, count, true),
                NewLayer("视线障碍", EditorLayerKind.LineOfSightObstacle, count, false),
                NewLayer("移动障碍", EditorLayerKind.MovementObstacle, count, false),
                NewLayer("事件", EditorLayerKind.Event, count, false),
                NewLayer(
                    "人工通行修正",
                    EditorLayerKind.ManualMovementCorrection,
                    count, false)
            ],
            Tasks =
            [
                new MissionTask
                {
                    Id = "primary",
                    Title = "主要目标",
                    Description = "在任务面板中填写胜利条件。"
                }
            ]
        };
    }

    public EditorLayer Layer(EditorLayerKind kind) =>
        Layers.First(layer => layer.Kind == kind);

    public int Index(int x, int y)
    {
        if (x < 0 || x >= Width || y < 0 || y >= Height)
            throw new ArgumentOutOfRangeException(nameof(x));
        return checked(y * Width + x);
    }

    private static EditorLayer NewLayer(
        string name, EditorLayerKind kind, int count, bool visible) =>
        new()
        {
            Name = name,
            Kind = kind,
            Visible = visible,
            Cells = new int[count]
        };
}

public static class MapDocumentSerializer
{
    private static readonly JsonSerializerOptions Options = new()
    {
        WriteIndented = true,
        PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower,
        Converters = { new JsonStringEnumConverter(JsonNamingPolicy.SnakeCaseLower) }
    };

    public static MapDocument Load(string path)
    {
        var document = JsonSerializer.Deserialize<MapDocument>(
            File.ReadAllText(path), Options)
            ?? throw new InvalidDataException("地图文件没有有效内容。");
        Normalize(document);
        MapValidator.ThrowIfInvalid(document);
        return document;
    }

    public static void Save(MapDocument document, string path)
    {
        Normalize(document);
        MapValidator.ThrowIfInvalid(document);
        var fullPath = Path.GetFullPath(path);
        Directory.CreateDirectory(Path.GetDirectoryName(fullPath)!);
        var temporary = fullPath + ".tmp";
        File.WriteAllText(temporary, JsonSerializer.Serialize(document, Options));
        File.Move(temporary, fullPath, true);
    }

    private static void Normalize(MapDocument document)
    {
        if (document.CellWidth <= 0)
            document.CellWidth = document.CellSize > 0 ? document.CellSize : 20;
        if (document.CellHeight <= 0)
            document.CellHeight = document.CellSize > 0 ? document.CellSize : 20;
        document.CellSize = document.CellWidth;
        document.BackgroundAsset ??= "";
        foreach (var item in document.Objects)
        {
            item.AssetPath ??= "";
            item.Category ??= "其他";
            item.Properties ??= [];
            item.PatrolWaypoints ??= [];
            if (item.PatrolWaypoints.Count > 0)
            {
                item.PatrolCurrentWaypointIndex = Math.Clamp(
                    item.PatrolCurrentWaypointIndex,
                    0, item.PatrolWaypoints.Count - 1);
            }
            else
            {
                item.PatrolCurrentWaypointIndex = 0;
                item.PatrolEnabled = false;
            }
        }
    }
}

public static class MapValidator
{
    public static IReadOnlyList<string> Validate(MapDocument document)
    {
        var errors = new List<string>();
        if (document.SchemaVersion != MapDocument.CurrentSchemaVersion)
            errors.Add($"不支持的 schema_version：{document.SchemaVersion}");
        if (document.Width <= 0 || document.Height <= 0)
            errors.Add("地图宽高必须为正数。");
        if (document.EffectiveCellWidth <= 0 || document.EffectiveCellHeight <= 0)
            errors.Add("地图格宽和格高必须为正数。");

        var expected = (long)document.Width * document.Height;
        foreach (var layer in document.Layers)
        {
            if (layer.Cells.LongLength != expected)
                errors.Add(
                    $"图层“{layer.Name}”包含 {layer.Cells.LongLength} 格，应为 {expected} 格。");
        }
        foreach (var duplicate in document.Objects
                     .GroupBy(item => item.Id).Where(group => group.Count() > 1))
            errors.Add($"对象 ID 重复：{duplicate.Key}");
        foreach (var item in document.Objects)
        {
            if (item.X < 0 || item.X >= document.Width ||
                item.Y < 0 || item.Y >= document.Height)
                errors.Add($"对象“{item.Name}”位于地图范围外。");
            for (var waypointIndex = 0;
                 waypointIndex < item.PatrolWaypoints.Count;
                 waypointIndex++)
            {
                var waypoint = item.PatrolWaypoints[waypointIndex];
                if (waypoint.X < 0 || waypoint.X >= document.Width ||
                    waypoint.Y < 0 || waypoint.Y >= document.Height)
                {
                    errors.Add(
                        $"对象“{item.Name}”的路线点 {waypointIndex + 1} " +
                        $"({waypoint.X}, {waypoint.Y}) 位于地图范围外。");
                }
            }
        }
        foreach (var duplicate in document.Tasks
                     .GroupBy(item => item.Id).Where(group => group.Count() > 1))
            errors.Add($"任务 ID 重复：{duplicate.Key}");
        var taskIds = document.Tasks.Select(item => item.Id).ToHashSet();
        foreach (var task in document.Tasks)
        {
            if (task.NextTaskId.Length > 0 && !taskIds.Contains(task.NextTaskId))
                errors.Add($"任务“{task.Title}”指向不存在的后续任务 {task.NextTaskId}。");
        }
        return errors;
    }

    public static void ThrowIfInvalid(MapDocument document)
    {
        var errors = Validate(document);
        if (errors.Count > 0)
            throw new InvalidDataException(string.Join(Environment.NewLine, errors));
    }
}

public static class OriginalVwfImporter
{
    public static MapDocument Import(string vwfPath, string? originalAssetRoot = null)
    {
        _ = VwfWorldHeader.Open(vwfPath);
        var terrain = VwfTerrainGrid.Open(vwfPath);
        var scenes = VwfSceneList.Open(vwfPath);
        var levelId = Path.GetFileNameWithoutExtension(vwfPath).ToLowerInvariant();
        if (levelId.StartsWith("1937m", StringComparison.Ordinal) &&
            levelId.Length == 8)
            levelId = levelId[4..];
        var document = MapDocument.Create(
            levelId, checked((int)terrain.Width), checked((int)terrain.Height));

        // Original maps use an isometric 32x16 pixel grid.
        document.CellSize = 32;
        document.CellWidth = 32;
        document.CellHeight = 16;
        document.ImportedFrom = Path.GetFileName(vwfPath);

        for (var index = 0; index < document.Width * document.Height; index++)
        {
            document.Layer(EditorLayerKind.Terrain).Cells[index] =
                unchecked((int)terrain.Layers[0].Values[index]);
            document.Layer(EditorLayerKind.LineOfSightObstacle).Cells[index] =
                unchecked((int)terrain.Layers[1].Values[index]);
            document.Layer(EditorLayerKind.MovementObstacle).Cells[index] =
                unchecked((int)terrain.Layers[2].Values[index]);
            document.Layer(EditorLayerKind.Event).Cells[index] =
                unchecked((int)terrain.Layers[3].Values[index]);
            document.Layer(EditorLayerKind.ManualMovementCorrection).Cells[index] =
                unchecked((int)terrain.Layers[4].Values[index]);
        }

        foreach (var entity in scenes.Entities)
        {
            var patrol = entity.Patrol;
            document.Objects.Add(new MapObject
            {
                Id = $"scene-{entity.SceneIndex}",
                Kind = "legacy_object",
                Name = $"原版对象 {entity.SceneIndex}",
                X = Math.Clamp(
                    entity.WorldX / document.EffectiveCellWidth,
                    0, document.Width - 1),
                Y = Math.Clamp(
                    entity.WorldY / document.EffectiveCellHeight,
                    0, document.Height - 1),
                Direction = checked((int)entity.DirectionIndex),
                PatrolWaypoints = patrol?.Waypoints
                    .Select(point => new MapWaypoint
                    {
                        X = checked((int)point.X),
                        Y = checked((int)point.Y)
                    })
                    .ToList() ?? [],
                PatrolCurrentWaypointIndex = patrol is null
                    ? 0
                    : checked((int)patrol.CurrentWaypointIndex),
                PatrolEnabled = patrol?.PersistentFlag != 0,
                Properties =
                {
                    ["database_entry_id"] = entity.DatabaseEntryId.ToString(),
                    ["world_x"] = entity.WorldX.ToString(),
                    ["world_y"] = entity.WorldY.ToString(),
                    ["hit_points"] = entity.CurrentHitPoints.ToString(),
                    ["patrol_persistent_flag"] =
                        (patrol?.PersistentFlag ?? 0).ToString()
                }
            });
        }

        EnrichFromConvertedLevel(document, levelId, originalAssetRoot);
        document.Tasks[0].Description =
            $"从 {Path.GetFileName(vwfPath)} 导入；请根据原任务脚本补充胜负条件。";
        return document;
    }

    private static void EnrichFromConvertedLevel(
        MapDocument document, string levelId, string? originalAssetRoot)
    {
        if (string.IsNullOrWhiteSpace(originalAssetRoot))
            return;
        var assetLevelId = ResolveAssetLevelId(
            originalAssetRoot, levelId);
        var levelPath = Path.Combine(
            originalAssetRoot, "maps", assetLevelId, "level.json");
        if (!File.Exists(levelPath))
            return;

        using var json = JsonDocument.Parse(File.ReadAllText(levelPath));
        if (!json.RootElement.TryGetProperty("entities", out var entities))
            return;
        var byId = document.Objects.ToDictionary(item => item.Id);
        foreach (var entity in entities.EnumerateArray())
        {
            if (!entity.TryGetProperty("scene_index", out var sceneIndex))
                continue;
            if (!byId.TryGetValue($"scene-{sceneIndex.GetInt32()}", out var item))
                continue;

            var resourceName = Text(entity, "resource_name");
            item.Name = Text(entity, "display_name");
            if (string.IsNullOrWhiteSpace(item.Name))
                item.Name = Path.GetFileNameWithoutExtension(resourceName);
            item.Category = Text(entity, "category_name");
            if (string.IsNullOrWhiteSpace(item.Category))
                item.Category = Classify(resourceName);
            item.Kind = Classify(resourceName);

            var preview = Text(entity, "sprite_preview");
            if (!string.IsNullOrWhiteSpace(preview))
                item.AssetPath = "sprites/" + Path.GetFileName(preview);

            if (entity.TryGetProperty("faction_id", out var faction))
            {
                var factionId = faction.GetInt32();
                item.Faction = factionId == 0 ? "neutral" : $"faction-{factionId}";
                item.Properties["faction_id"] = factionId.ToString();
            }
            item.Properties["resource_name"] = resourceName;
        }

        var background = Path.Combine(
            originalAssetRoot, "maps", assetLevelId, "terrain.png");
        if (File.Exists(background))
            document.BackgroundAsset =
                $"maps/{assetLevelId}/terrain.png";
    }

    private static string ResolveAssetLevelId(
        string originalAssetRoot, string levelId)
    {
        var aliasPath = Path.Combine(
            originalAssetRoot, "maps", levelId, "level-alias.json");
        if (!File.Exists(aliasPath))
            return levelId;
        using var alias = JsonDocument.Parse(
            File.ReadAllText(aliasPath));
        var baseLevelId = Text(alias.RootElement, "base_level_id");
        if (baseLevelId.Length == 4 &&
            baseLevelId[0] == 'm' &&
            baseLevelId[1..].All(char.IsAsciiDigit))
            return baseLevelId;
        throw new InvalidDataException(
            $"Invalid map asset alias in {aliasPath}.");
    }

    private static string Text(JsonElement value, string name) =>
        value.TryGetProperty(name, out var property)
            ? property.GetString() ?? ""
            : "";

    private static string Classify(string name)
    {
        if (ContainsAny(name, "树", "草", "花", "灌木"))
            return "vegetation";
        if (ContainsAny(name, "墙", "栅栏", "铁丝网"))
            return "wall";
        if (ContainsAny(name, "房", "屋", "楼", "仓库", "岗楼", "车站"))
            return "building";
        if (ContainsAny(name, "门"))
            return "door";
        if (ContainsAny(name, "桥", "道路", "地面"))
            return "terrain";
        if (ContainsAny(name, "古明", "强子", "王二", "龟田", "兵", "军官", "人"))
            return "character";
        if (ContainsAny(name, "箱", "枪", "刀", "药", "弹", "物品"))
            return "item";
        if (ContainsAny(name, "石", "木", "桌", "椅", "桶", "车"))
            return "obstacle";
        return "decoration";
    }

    private static bool ContainsAny(string value, params string[] needles) =>
        needles.Any(value.Contains);
}
