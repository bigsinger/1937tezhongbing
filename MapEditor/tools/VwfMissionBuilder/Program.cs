using System.Buffers.Binary;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using Mission1937.Remake.Resources;

if (args.Length is < 3 or > 4)
{
    Console.Error.WriteLine(
        "Usage: VwfMissionBuilder SOURCE.vwf OUTPUT.vwf DEFINITION.json [REPORT.md]");
    return 2;
}

var sourcePath = Path.GetFullPath(args[0]);
var outputPath = Path.GetFullPath(args[1]);
var definitionPath = Path.GetFullPath(args[2]);
var reportPath = args.Length == 4
    ? Path.GetFullPath(args[3])
    : Path.ChangeExtension(outputPath, ".validation.md");

var definition = JsonSerializer.Deserialize<MissionDefinition>(
    File.ReadAllText(definitionPath),
    new JsonSerializerOptions
    {
        PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower,
        PropertyNameCaseInsensitive = true,
        Converters = { new JsonStringEnumConverter(JsonNamingPolicy.SnakeCaseLower) }
    }) ?? throw new InvalidDataException("Mission definition is empty.");

var builder = new MissionBuilder(sourcePath, definition);
var report = builder.Build(outputPath);
Directory.CreateDirectory(Path.GetDirectoryName(reportPath)!);
File.WriteAllText(reportPath, report, new UTF8Encoding(false));
Console.WriteLine($"Built {outputPath}");
Console.WriteLine($"Validation report: {reportPath}");
return 0;

internal sealed class MissionDefinition
{
    public string Id { get; set; } = "";
    public string Title { get; set; } = "";
    public string Story { get; set; } = "";
    public string SourceSha256 { get; set; } = "";
    public GridCell PlayerSpawn { get; set; } = new();
    public List<EntityEdit> EntityEdits { get; set; } = [];
    public List<ReachabilityTarget> RequiredReachability { get; set; } = [];
}

internal sealed class EntityEdit
{
    public int SceneIndex { get; set; }
    public int CellX { get; set; }
    public int CellY { get; set; }
    public int? Direction { get; set; }
    public List<GridCell>? Patrol { get; set; }
}

internal class GridCell
{
    public int X { get; set; }
    public int Y { get; set; }
}

internal sealed class ReachabilityTarget : GridCell
{
    public string Name { get; set; } = "";
}

internal sealed class MissionBuilder
{
    private const int EntityPrefixWorldX = 60;
    private const int EntityPrefixWorldY = 64;
    private const int EntityPrefixReferenceX = 104;
    private const int EntityPrefixReferenceY = 112;
    private const int EntityPrefixDirection = 44;
    private const int PatrolRecordOffset = 204;

    private readonly string sourcePath;
    private readonly MissionDefinition definition;
    private readonly VwfWorldHeader world;
    private readonly VwfTerrainGrid terrain;
    private readonly VwfSceneList scenes;
    private readonly byte[] data;
    private readonly int cellCount;
    private readonly int lineOfSightLayerOffset;
    private readonly int movementLayerOffset;
    private readonly Dictionary<int, VwfSceneEntity> entities;
    private readonly HashSet<uint> editedOccupants;

    public MissionBuilder(string sourcePath, MissionDefinition definition)
    {
        this.sourcePath = sourcePath;
        this.definition = definition;
        world = VwfWorldHeader.Open(sourcePath);
        terrain = VwfTerrainGrid.Open(sourcePath);
        scenes = VwfSceneList.Open(sourcePath);
        data = File.ReadAllBytes(sourcePath);
        cellCount = checked((int)(world.GridWidth * world.GridHeight));
        lineOfSightLayerOffset = LayerDataOffset(1);
        movementLayerOffset = LayerDataOffset(2);
        entities = scenes.Entities.ToDictionary(entity => entity.SceneIndex);
        editedOccupants = definition.EntityEdits
            .Select(edit => checked((uint)(edit.SceneIndex + 1000)))
            .ToHashSet();
        ValidateSourceHash();
        ValidateDefinition();
    }

    public string Build(string outputPath)
    {
        var sourceHash = Hash(sourcePath);
        ClearOriginalOccupancy();
        foreach (var edit in definition.EntityEdits)
            ApplyEntityEdit(edit);

        var validations = ValidateNavigation();
        Directory.CreateDirectory(Path.GetDirectoryName(outputPath)!);
        var temporary = outputPath + ".tmp";
        File.WriteAllBytes(temporary, data);
        File.Move(temporary, outputPath, true);

        var outputWorld = VwfWorldHeader.Open(outputPath);
        var outputTerrain = VwfTerrainGrid.Open(outputPath);
        var outputScenes = VwfSceneList.Open(outputPath);
        if (outputWorld.GridWidth != world.GridWidth ||
            outputWorld.GridHeight != world.GridHeight ||
            outputScenes.SlotCount != scenes.SlotCount ||
            outputScenes.Entities.Count != scenes.Entities.Count ||
            outputTerrain.SceneListOffset != terrain.SceneListOffset)
        {
            throw new InvalidDataException(
                "The generated VWF failed structural equivalence checks.");
        }

        return BuildReport(
            sourceHash, Hash(outputPath), outputPath,
            outputScenes, validations);
    }

    private void ValidateDefinition()
    {
        if (string.IsNullOrWhiteSpace(definition.Id) ||
            string.IsNullOrWhiteSpace(definition.Title))
            throw new InvalidDataException("Mission id and title are required.");
        if (definition.EntityEdits.Count == 0)
            throw new InvalidDataException("At least one entity edit is required.");

        var duplicates = definition.EntityEdits
            .GroupBy(edit => edit.SceneIndex)
            .Where(group => group.Count() > 1)
            .Select(group => group.Key)
            .ToArray();
        if (duplicates.Length > 0)
            throw new InvalidDataException(
                $"Duplicate entity edits: {string.Join(", ", duplicates)}.");

        var targetCells = new HashSet<int>();
        foreach (var edit in definition.EntityEdits)
        {
            if (!entities.TryGetValue(edit.SceneIndex, out var entity))
                throw new InvalidDataException(
                    $"Scene entity {edit.SceneIndex} does not exist.");
            ValidateCell(edit.CellX, edit.CellY, $"entity {edit.SceneIndex}");
            if (!targetCells.Add(CellIndex(edit.CellX, edit.CellY)))
                throw new InvalidDataException(
                    $"More than one edited entity targets cell " +
                    $"({edit.CellX}, {edit.CellY}).");
            if (edit.Direction is < 0 or > 8)
                throw new InvalidDataException(
                    $"Entity {edit.SceneIndex} has invalid direction {edit.Direction}.");
            if (edit.Patrol is null)
                continue;
            if (entity.Patrol is null)
                throw new InvalidDataException(
                    $"Entity {edit.SceneIndex} has no patrol record.");
            if (edit.Patrol.Count != entity.Patrol.Waypoints.Count)
                throw new InvalidDataException(
                    $"Entity {edit.SceneIndex} patrol requires exactly " +
                    $"{entity.Patrol.Waypoints.Count} points, but the definition " +
                    $"contains {edit.Patrol.Count}.");
            foreach (var point in edit.Patrol)
                ValidateCell(
                    point.X, point.Y,
                    $"entity {edit.SceneIndex} patrol");
        }

        ValidateCell(
            definition.PlayerSpawn.X,
            definition.PlayerSpawn.Y,
            "player spawn");
        foreach (var target in definition.RequiredReachability)
            ValidateCell(target.X, target.Y, target.Name);
    }

    private void ValidateSourceHash()
    {
        if (string.IsNullOrWhiteSpace(definition.SourceSha256))
            throw new InvalidDataException(
                "source_sha256 is required so the mission cannot be " +
                "generated from an incompatible source map.");
        var actual = Hash(sourcePath);
        if (!actual.Equals(
                definition.SourceSha256,
                StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidDataException(
                $"Source VWF hash mismatch. Expected " +
                $"{definition.SourceSha256}, actual {actual}.");
        }
    }

    private void ClearOriginalOccupancy()
    {
        for (var index = 0; index < cellCount; index++)
        {
            ClearEditedOccupant(lineOfSightLayerOffset, index);
            ClearEditedOccupant(movementLayerOffset, index);
        }
    }

    private void ClearEditedOccupant(int layerOffset, int index)
    {
        var offset = checked(layerOffset + index * sizeof(uint));
        var value = ReadUInt32(offset);
        if (editedOccupants.Contains(value))
            WriteUInt32(offset, 0);
    }

    private void ApplyEntityEdit(EntityEdit edit)
    {
        var entity = entities[edit.SceneIndex];
        var targetIndex = CellIndex(edit.CellX, edit.CellY);
        EnsureTargetOpen(lineOfSightLayerOffset, targetIndex, edit);
        EnsureTargetOpen(movementLayerOffset, targetIndex, edit);

        var occupancyValue = checked((uint)(edit.SceneIndex + 1000));
        WriteUInt32(
            checked(lineOfSightLayerOffset + targetIndex * sizeof(uint)),
            occupancyValue);
        WriteUInt32(
            checked(movementLayerOffset + targetIndex * sizeof(uint)),
            occupancyValue);

        var record = checked((int)entity.RecordOffset);
        var worldX = checked(edit.CellX * 32 + 16);
        var worldY = checked(edit.CellY * 16 + 8);
        var referenceDeltaX = entity.ReferenceX - entity.WorldX;
        var referenceDeltaY = entity.ReferenceY - entity.WorldY;
        WriteInt32(record + EntityPrefixWorldX, worldX);
        WriteInt32(record + EntityPrefixWorldY, worldY);
        WriteInt32(
            record + EntityPrefixReferenceX,
            checked(worldX + referenceDeltaX));
        WriteInt32(
            record + EntityPrefixReferenceY,
            checked(worldY + referenceDeltaY));
        if (edit.Direction.HasValue)
            WriteUInt32(
                record + EntityPrefixDirection,
                checked((uint)edit.Direction.Value));

        if (edit.Patrol is not null)
            ApplyPatrolEdit(entity, edit.Patrol);
    }

    private void EnsureTargetOpen(
        int layerOffset, int targetIndex, EntityEdit edit)
    {
        var value = ReadUInt32(
            checked(layerOffset + targetIndex * sizeof(uint)));
        if (value != 0)
            throw new InvalidDataException(
                $"Entity {edit.SceneIndex} target cell " +
                $"({edit.CellX}, {edit.CellY}) is occupied by grid value {value}.");
    }

    private void ApplyPatrolEdit(
        VwfSceneEntity entity, IReadOnlyList<GridCell> route)
    {
        var patrol = entity.Patrol!;
        var count = route.Count;
        var patrolOffset = checked((int)entity.RecordOffset + PatrolRecordOffset);
        var serializedCount = checked((int)ReadUInt32(patrolOffset + 4));
        if (serializedCount != count)
            throw new InvalidDataException(
                $"Entity {entity.SceneIndex} patrol count changed while editing.");

        var workingPointsOffset = patrolOffset + 12;
        var currentIndexOffset = checked(patrolOffset + 16 + count * 8);
        var cachedXOffset = checked(patrolOffset + 24 + count * 8);
        var cachedYOffset = checked(patrolOffset + 28 + count * 8);
        var waypointOffset = checked(patrolOffset + 32 + count * 8);
        for (var index = 0; index < count; index++)
        {
            var point = route[index];
            WriteUInt32(
                checked(workingPointsOffset + index * 8),
                checked((uint)point.X));
            WriteUInt32(
                checked(workingPointsOffset + index * 8 + 4),
                checked((uint)point.Y));
            WriteUInt32(
                checked(waypointOffset + index * 8),
                checked((uint)point.X));
            WriteUInt32(
                checked(waypointOffset + index * 8 + 4),
                checked((uint)point.Y));
        }
        WriteUInt32(currentIndexOffset, 0);
        if (count > 0)
        {
            WriteInt32(cachedXOffset, checked(route[0].X * 32 + 16));
            WriteInt32(cachedYOffset, checked(route[0].Y * 16 + 8));
        }
        else
        {
            WriteInt32(cachedXOffset, patrol.CachedWaypointWorldX);
            WriteInt32(cachedYOffset, patrol.CachedWaypointWorldY);
        }
    }

    private IReadOnlyList<PathValidation> ValidateNavigation()
    {
        var results = new List<PathValidation>();
        var failures = new List<string>();
        var spawn = definition.PlayerSpawn;
        foreach (var target in definition.RequiredReachability)
        {
            var length = FindPathLength(spawn, target);
            if (length < 0)
            {
                failures.Add(
                    $"No traversable path from player spawn to “{target.Name}” " +
                    $"at ({target.X}, {target.Y}).");
            }
            else
            {
                results.Add(new PathValidation(
                    $"玩家出生点 → {target.Name}",
                    spawn.X, spawn.Y, target.X, target.Y, length));
            }
        }

        foreach (var edit in definition.EntityEdits
                     .Where(edit => edit.Patrol is { Count: > 0 }))
        {
            var points = new List<GridCell>
            {
                new() { X = edit.CellX, Y = edit.CellY }
            };
            points.AddRange(edit.Patrol!);
            for (var index = 1; index < points.Count; index++)
            {
                var length = FindPathLength(points[index - 1], points[index]);
                if (length < 0)
                {
                    failures.Add(
                        $"Entity {edit.SceneIndex} patrol segment " +
                        $"{index} is not traversable: " +
                        $"({points[index - 1].X}, {points[index - 1].Y}) → " +
                        $"({points[index].X}, {points[index].Y}).");
                }
                else
                {
                    results.Add(new PathValidation(
                        $"场景 {edit.SceneIndex} 巡逻段 {index}",
                        points[index - 1].X, points[index - 1].Y,
                        points[index].X, points[index].Y, length));
                }
            }
        }
        if (failures.Count > 0)
            throw new InvalidDataException(string.Join(
                Environment.NewLine, failures));
        return results;
    }

    private int FindPathLength(GridCell start, GridCell goal)
    {
        var startIndex = CellIndex(start.X, start.Y);
        var goalIndex = CellIndex(goal.X, goal.Y);
        var distances = new int[cellCount];
        Array.Fill(distances, int.MaxValue);
        var closed = new bool[cellCount];
        var open = new PriorityQueue<int, int>();
        distances[startIndex] = 0;
        open.Enqueue(
            startIndex,
            GridHeuristic(start.X, start.Y, goal.X, goal.Y));
        ReadOnlySpan<int> dx = [-1, 1, 0, 0, -1, 1, -1, 1];
        ReadOnlySpan<int> dy = [0, 0, -1, 1, -1, -1, 1, 1];

        while (open.TryDequeue(out var current, out _))
        {
            if (closed[current])
                continue;
            closed[current] = true;
            if (current == goalIndex)
                return distances[current];
            var x = current % checked((int)world.GridWidth);
            var y = current / checked((int)world.GridWidth);
            for (var direction = 0; direction < dx.Length; direction++)
            {
                var nextX = x + dx[direction];
                var nextY = y + dy[direction];
                if (!InBounds(nextX, nextY))
                    continue;
                var next = CellIndex(nextX, nextY);
                if (closed[next] || !IsTraversable(next))
                    continue;
                if (dx[direction] != 0 && dy[direction] != 0 &&
                    (!IsTraversable(CellIndex(x + dx[direction], y)) ||
                     !IsTraversable(CellIndex(x, y + dy[direction]))))
                    continue;
                var nextDistance = distances[current] + 1;
                if (nextDistance >= distances[next])
                    continue;
                distances[next] = nextDistance;
                open.Enqueue(
                    next,
                    nextDistance + GridHeuristic(
                        nextX, nextY, goal.X, goal.Y));
            }
        }
        return -1;
    }

    private static int GridHeuristic(
        int x, int y, int goalX, int goalY) =>
        Math.Max(Math.Abs(goalX - x), Math.Abs(goalY - y));

    private bool IsTraversable(int index)
    {
        var value = ReadUInt32(
            checked(movementLayerOffset + index * sizeof(uint)));
        return value == 0 || editedOccupants.Contains(value);
    }

    private string BuildReport(
        string sourceHash,
        string outputHash,
        string outputPath,
        VwfSceneList outputScenes,
        IReadOnlyList<PathValidation> validations)
    {
        var builder = new StringBuilder();
        builder.AppendLine($"# {definition.Title}（{definition.Id}）生成与验证报告");
        builder.AppendLine();
        builder.AppendLine(definition.Story);
        builder.AppendLine();
        builder.AppendLine("## 文件与结构");
        builder.AppendLine();
        builder.AppendLine($"- 源文件：`{Path.GetFileName(sourcePath)}`");
        builder.AppendLine($"- 输出文件：`{Path.GetFileName(outputPath)}`");
        builder.AppendLine($"- 地图网格：{world.GridWidth} × {world.GridHeight}");
        builder.AppendLine($"- 场景槽位：{outputScenes.SlotCount}");
        builder.AppendLine($"- 有效场景对象：{outputScenes.Entities.Count}");
        builder.AppendLine($"- 重部署活动对象：{definition.EntityEdits.Count}");
        builder.AppendLine($"- 源 SHA-256：`{sourceHash}`");
        builder.AppendLine($"- 输出 SHA-256：`{outputHash}`");
        builder.AppendLine();
        builder.AppendLine("## 可达性验证");
        builder.AppendLine();
        builder.AppendLine("| 路径 | 起点 | 终点 | A* 步数 |");
        builder.AppendLine("|---|---:|---:|---:|");
        foreach (var validation in validations)
        {
            builder.AppendLine(
                $"| {validation.Name} | " +
                $"({validation.StartX}, {validation.StartY}) | " +
                $"({validation.EndX}, {validation.EndY}) | " +
                $"{validation.Length} |");
        }
        builder.AppendLine();
        builder.AppendLine(
            "所有必达目标和每一段巡逻路线均通过八方向 A* 校验；" +
            "对角移动禁止穿越两块相邻障碍物的夹角。");
        return builder.ToString();
    }

    private int LayerDataOffset(int zeroBasedLayer)
    {
        var planeSize = checked(16 + cellCount * sizeof(uint));
        return checked(
            VwfTerrainGrid.PreambleSize +
            zeroBasedLayer * planeSize + 16);
    }

    private int CellIndex(int x, int y) =>
        checked(y * checked((int)world.GridWidth) + x);

    private bool InBounds(int x, int y) =>
        x >= 0 && x < world.GridWidth &&
        y >= 0 && y < world.GridHeight;

    private void ValidateCell(int x, int y, string description)
    {
        if (!InBounds(x, y))
            throw new InvalidDataException(
                $"{description} cell ({x}, {y}) lies outside " +
                $"{world.GridWidth}x{world.GridHeight}.");
    }

    private uint ReadUInt32(int offset) =>
        BinaryPrimitives.ReadUInt32LittleEndian(data.AsSpan(offset, 4));

    private void WriteUInt32(int offset, uint value) =>
        BinaryPrimitives.WriteUInt32LittleEndian(
            data.AsSpan(offset, 4), value);

    private void WriteInt32(int offset, int value) =>
        BinaryPrimitives.WriteInt32LittleEndian(
            data.AsSpan(offset, 4), value);

    private static string Hash(string path)
    {
        using var stream = File.OpenRead(path);
        return Convert.ToHexString(SHA256.HashData(stream));
    }

    private sealed record PathValidation(
        string Name,
        int StartX,
        int StartY,
        int EndX,
        int EndY,
        int Length);
}
