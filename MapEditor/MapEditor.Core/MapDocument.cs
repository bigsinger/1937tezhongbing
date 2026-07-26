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

public sealed class MapObject
{
    public string Id { get; set; } = Guid.NewGuid().ToString("N");
    public string Kind { get; set; } = "enemy";
    public string Name { get; set; } = "新对象";
    public int X { get; set; }
    public int Y { get; set; }
    public int Direction { get; set; }
    public string Faction { get; set; } = "enemy";
    public Dictionary<string, string> Properties { get; set; } = [];
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
    public int CellSize { get; set; } = 20;
    public string? ImportedFrom { get; set; }
    public List<EditorLayer> Layers { get; set; } = [];
    public List<MapObject> Objects { get; set; } = [];
    public List<MissionTask> Tasks { get; set; } = [];

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
                NewLayer("地表", EditorLayerKind.Terrain, count),
                NewLayer("视线障碍", EditorLayerKind.LineOfSightObstacle, count),
                NewLayer("移动障碍", EditorLayerKind.MovementObstacle, count),
                NewLayer("事件", EditorLayerKind.Event, count),
                NewLayer("人工通行修正", EditorLayerKind.ManualMovementCorrection, count)
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
        {
            throw new ArgumentOutOfRangeException(nameof(x));
        }
        return checked(y * Width + x);
    }

    private static EditorLayer NewLayer(
        string name, EditorLayerKind kind, int count) =>
        new() { Name = name, Kind = kind, Cells = new int[count] };
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
        MapValidator.ThrowIfInvalid(document);
        return document;
    }

    public static void Save(MapDocument document, string path)
    {
        MapValidator.ThrowIfInvalid(document);
        var fullPath = Path.GetFullPath(path);
        Directory.CreateDirectory(Path.GetDirectoryName(fullPath)!);
        var temporary = fullPath + ".tmp";
        File.WriteAllText(temporary, JsonSerializer.Serialize(document, Options));
        File.Move(temporary, fullPath, true);
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
        var expected = (long)document.Width * document.Height;
        foreach (var layer in document.Layers)
        {
            if (layer.Cells.LongLength != expected)
                errors.Add($"图层“{layer.Name}”包含 {layer.Cells.LongLength} 格，应为 {expected} 格。");
        }
        foreach (var duplicate in document.Objects.GroupBy(item => item.Id).Where(group => group.Count() > 1))
            errors.Add($"对象 ID 重复：{duplicate.Key}");
        foreach (var item in document.Objects)
        {
            if (item.X < 0 || item.X >= document.Width ||
                item.Y < 0 || item.Y >= document.Height)
                errors.Add($"对象“{item.Name}”位于地图范围外。");
        }
        foreach (var duplicate in document.Tasks.GroupBy(item => item.Id).Where(group => group.Count() > 1))
            errors.Add($"任务 ID 重复：{duplicate.Key}");
        var taskIds = document.Tasks.Select(item => item.Id).ToHashSet();
        foreach (var task in document.Tasks)
        {
            if (task.NextTaskId.Length > 0 && !taskIds.Contains(task.NextTaskId))
                errors.Add($"任务“{task.Title}”指向不存在的后继任务 {task.NextTaskId}。");
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
    public static MapDocument Import(string vwfPath)
    {
        var world = VwfWorldHeader.Open(vwfPath);
        var terrain = VwfTerrainGrid.Open(vwfPath);
        var scenes = VwfSceneList.Open(vwfPath);
        var document = MapDocument.Create(
            Path.GetFileNameWithoutExtension(vwfPath),
            checked((int)terrain.Width),
            checked((int)terrain.Height));
        document.CellSize = VwfWorldHeader.GridCellSize;
        document.ImportedFrom = Path.GetFileName(vwfPath);

        for (var index = 0; index < document.Width * document.Height; index++)
        {
            var rawTerrain = terrain.Layers[0].Values[index];
            document.Layer(EditorLayerKind.Terrain).Cells[index] =
                unchecked((int)rawTerrain);
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
            document.Objects.Add(new MapObject
            {
                Id = $"scene-{entity.SceneIndex}",
                Kind = entity.DatabaseEntryId switch
                {
                    < 0 => "unknown",
                    _ => "legacy_object"
                },
                Name = $"原版对象 {entity.SceneIndex}",
                X = Math.Clamp(entity.WorldX / document.CellSize, 0, document.Width - 1),
                Y = Math.Clamp(entity.WorldY / document.CellSize, 0, document.Height - 1),
                Direction = checked((int)entity.DirectionIndex),
                Properties =
                {
                    ["database_entry_id"] = entity.DatabaseEntryId.ToString(),
                    ["world_x"] = entity.WorldX.ToString(),
                    ["world_y"] = entity.WorldY.ToString(),
                    ["hit_points"] = entity.CurrentHitPoints.ToString()
                }
            });
        }
        document.Tasks[0].Description =
            $"从 {Path.GetFileName(vwfPath)} 导入；请按原任务脚本补充胜负条件。";
        return document;
    }
}
