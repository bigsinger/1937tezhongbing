using System.Buffers.Binary;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Mission1937.Remake.Resources;

if (args.Length is < 3 or > 4)
{
    Console.Error.WriteLine(
        "Usage: VwfBlueprintComposer SOURCE.vwf OUTPUT.vwf BLUEPRINT.json [REPORT.md]");
    return 2;
}

var sourcePath = Path.GetFullPath(args[0]);
var outputPath = Path.GetFullPath(args[1]);
var blueprintPath = Path.GetFullPath(args[2]);
var reportPath = args.Length == 4
    ? Path.GetFullPath(args[3])
    : Path.ChangeExtension(outputPath, ".composition.md");

var blueprint = JsonSerializer.Deserialize<BlueprintDefinition>(
    File.ReadAllText(blueprintPath),
    new JsonSerializerOptions
    {
        PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower,
        PropertyNameCaseInsensitive = true
    }) ?? throw new InvalidDataException("Blueprint definition is empty.");

var composer = new BlueprintComposer(sourcePath, blueprint);
var report = composer.Compose(outputPath);
Directory.CreateDirectory(Path.GetDirectoryName(reportPath)!);
File.WriteAllText(reportPath, report, new UTF8Encoding(false));
Console.WriteLine($"Composed {outputPath}");
Console.WriteLine($"Composition report: {reportPath}");
return 0;

internal sealed class BlueprintDefinition
{
    public string Id { get; set; } = "";
    public string Title { get; set; } = "";
    public string Story { get; set; } = "";
    public string SourceSha256 { get; set; } = "";
    public int BlockWidth { get; set; }
    public int BlockHeight { get; set; }
    public bool RequireAllBlocksMoved { get; set; } = true;
    public List<int> DestinationToSourceBlocks { get; set; } = [];
}

internal sealed class BlueprintComposer
{
    private const int EntityWorldXOffset = 60;
    private const int EntityWorldYOffset = 64;
    private const int EntityReferenceXOffset = 104;
    private const int EntityReferenceYOffset = 112;
    private const int PatrolRecordOffset = 204;

    private readonly string sourcePath;
    private readonly BlueprintDefinition blueprint;
    private readonly VwfWorldHeader world;
    private readonly VwfTerrainGrid terrain;
    private readonly VwfSceneList scenes;
    private readonly byte[] source;
    private readonly byte[] output;
    private readonly int width;
    private readonly int height;
    private readonly int cellCount;
    private readonly int blockColumns;
    private readonly int blockRows;
    private readonly int blockCount;
    private readonly int[] sourceToDestinationBlocks;

    public BlueprintComposer(
        string sourcePath,
        BlueprintDefinition blueprint)
    {
        this.sourcePath = sourcePath;
        this.blueprint = blueprint;
        world = VwfWorldHeader.Open(sourcePath);
        terrain = VwfTerrainGrid.Open(sourcePath);
        scenes = VwfSceneList.Open(sourcePath);
        source = File.ReadAllBytes(sourcePath);
        output = source.ToArray();
        width = checked((int)world.GridWidth);
        height = checked((int)world.GridHeight);
        cellCount = checked(width * height);

        ValidateDefinition();
        blockColumns = width / blueprint.BlockWidth;
        blockRows = height / blueprint.BlockHeight;
        blockCount = checked(blockColumns * blockRows);
        sourceToDestinationBlocks = BuildInversePermutation();
    }

    public string Compose(string outputPath)
    {
        for (var layer = 0; layer < VwfTerrainGrid.LayerCount; layer++)
            ComposeLayer(layer);
        foreach (var entity in scenes.Entities)
            ComposeEntity(entity);

        Directory.CreateDirectory(Path.GetDirectoryName(outputPath)!);
        var temporary = outputPath + ".tmp";
        File.WriteAllBytes(temporary, output);
        File.Move(temporary, outputPath, true);

        var outputWorld = VwfWorldHeader.Open(outputPath);
        var outputTerrain = VwfTerrainGrid.Open(outputPath);
        var outputScenes = VwfSceneList.Open(outputPath);
        if (outputWorld.GridWidth != world.GridWidth ||
            outputWorld.GridHeight != world.GridHeight ||
            outputTerrain.SceneListOffset != terrain.SceneListOffset ||
            outputScenes.SlotCount != scenes.SlotCount ||
            outputScenes.Entities.Count != scenes.Entities.Count)
        {
            throw new InvalidDataException(
                "The composed VWF failed structural equivalence checks.");
        }

        return BuildReport(outputPath, outputTerrain, outputScenes);
    }

    private void ValidateDefinition()
    {
        if (string.IsNullOrWhiteSpace(blueprint.Id) ||
            string.IsNullOrWhiteSpace(blueprint.Title))
        {
            throw new InvalidDataException(
                "Blueprint id and title are required.");
        }
        var sourceHash = Hash(sourcePath);
        if (string.IsNullOrWhiteSpace(blueprint.SourceSha256) ||
            !sourceHash.Equals(
                blueprint.SourceSha256,
                StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidDataException(
                $"Source VWF hash mismatch. Expected " +
                $"{blueprint.SourceSha256}, actual {sourceHash}.");
        }
        if (blueprint.BlockWidth <= 0 || blueprint.BlockHeight <= 0 ||
            width % blueprint.BlockWidth != 0 ||
            height % blueprint.BlockHeight != 0)
        {
            throw new InvalidDataException(
                $"Block size {blueprint.BlockWidth}x{blueprint.BlockHeight} " +
                $"must divide map size {width}x{height} exactly.");
        }

        var expectedCount =
            checked(width / blueprint.BlockWidth) *
            checked(height / blueprint.BlockHeight);
        if (blueprint.DestinationToSourceBlocks.Count != expectedCount)
        {
            throw new InvalidDataException(
                $"The map requires {expectedCount} block mappings, but the " +
                $"blueprint contains " +
                $"{blueprint.DestinationToSourceBlocks.Count}.");
        }
        var actual = blueprint.DestinationToSourceBlocks
            .OrderBy(value => value)
            .ToArray();
        var expected = Enumerable.Range(0, expectedCount).ToArray();
        if (!actual.SequenceEqual(expected))
        {
            throw new InvalidDataException(
                "destination_to_source_blocks must be a permutation of " +
                $"0 through {expectedCount - 1}.");
        }
        if (blueprint.RequireAllBlocksMoved &&
            blueprint.DestinationToSourceBlocks
                .Select((sourceBlock, destinationBlock) =>
                    sourceBlock == destinationBlock)
                .Any(equal => equal))
        {
            throw new InvalidDataException(
                "The blueprint requires every district to move, but at least " +
                "one block maps to its original position.");
        }
    }

    private int[] BuildInversePermutation()
    {
        var inverse = new int[blockCount];
        for (var destination = 0; destination < blockCount; destination++)
        {
            var sourceBlock =
                blueprint.DestinationToSourceBlocks[destination];
            inverse[sourceBlock] = destination;
        }
        return inverse;
    }

    private void ComposeLayer(int layer)
    {
        var sourceOffset = LayerDataOffset(layer);
        var destinationOffset = LayerDataOffset(layer);
        for (var destinationY = 0; destinationY < height; destinationY++)
        {
            for (var destinationX = 0;
                 destinationX < width;
                 destinationX++)
            {
                var sourceCell = SourceCellForDestination(
                    destinationX, destinationY);
                var value = ReadUInt32(
                    source,
                    checked(
                        sourceOffset +
                        CellIndex(sourceCell.X, sourceCell.Y) *
                        sizeof(uint)));
                WriteUInt32(
                    output,
                    checked(
                        destinationOffset +
                        CellIndex(destinationX, destinationY) *
                        sizeof(uint)),
                    value);
            }
        }
    }

    private void ComposeEntity(VwfSceneEntity entity)
    {
        var destinationWorld = DestinationWorldForSource(
            entity.WorldX, entity.WorldY);
        var deltaX = destinationWorld.X - entity.WorldX;
        var deltaY = destinationWorld.Y - entity.WorldY;
        var record = checked((int)entity.RecordOffset);
        WriteInt32(
            output, record + EntityWorldXOffset, destinationWorld.X);
        WriteInt32(
            output, record + EntityWorldYOffset, destinationWorld.Y);
        WriteInt32(
            output, record + EntityReferenceXOffset,
            checked(entity.ReferenceX + deltaX));
        WriteInt32(
            output, record + EntityReferenceYOffset,
            checked(entity.ReferenceY + deltaY));

        if (entity.Patrol is not null)
            ComposePatrol(entity, record + PatrolRecordOffset);
    }

    private void ComposePatrol(VwfSceneEntity entity, int patrolOffset)
    {
        var patrol = entity.Patrol!;
        var count = patrol.Waypoints.Count;
        var serializedCount =
            checked((int)ReadUInt32(output, patrolOffset + 4));
        if (serializedCount != count)
        {
            throw new InvalidDataException(
                $"Entity {entity.SceneIndex} patrol count changed while composing.");
        }

        var workingPointsOffset = patrolOffset + 12;
        var cachedXOffset = checked(patrolOffset + 24 + count * 8);
        var cachedYOffset = checked(patrolOffset + 28 + count * 8);
        var waypointOffset = checked(patrolOffset + 32 + count * 8);
        for (var index = 0; index < count; index++)
        {
            var working = DestinationCellForSource(
                checked((int)patrol.WorkingPoints[index].X),
                checked((int)patrol.WorkingPoints[index].Y));
            var waypoint = DestinationCellForSource(
                checked((int)patrol.Waypoints[index].X),
                checked((int)patrol.Waypoints[index].Y));
            WritePoint(
                output,
                checked(workingPointsOffset + index * 8),
                working);
            WritePoint(
                output,
                checked(waypointOffset + index * 8),
                waypoint);
        }

        if (count > 0)
        {
            var currentIndex = checked((int)Math.Min(
                patrol.CurrentWaypointIndex,
                checked((uint)(count - 1))));
            var cached = DestinationCellForSource(
                checked((int)patrol.Waypoints[currentIndex].X),
                checked((int)patrol.Waypoints[currentIndex].Y));
            WriteInt32(
                output, cachedXOffset, checked(cached.X * 32 + 16));
            WriteInt32(
                output, cachedYOffset, checked(cached.Y * 16 + 8));
        }
    }

    private Cell SourceCellForDestination(
        int destinationX, int destinationY)
    {
        var destinationBlockX =
            destinationX / blueprint.BlockWidth;
        var destinationBlockY =
            destinationY / blueprint.BlockHeight;
        var destinationBlock =
            destinationBlockY * blockColumns + destinationBlockX;
        var sourceBlock =
            blueprint.DestinationToSourceBlocks[destinationBlock];
        var sourceBlockX = sourceBlock % blockColumns;
        var sourceBlockY = sourceBlock / blockColumns;
        return new Cell(
            sourceBlockX * blueprint.BlockWidth +
                destinationX % blueprint.BlockWidth,
            sourceBlockY * blueprint.BlockHeight +
                destinationY % blueprint.BlockHeight);
    }

    private Cell DestinationCellForSource(int sourceX, int sourceY)
    {
        sourceX = Math.Clamp(sourceX, 0, width - 1);
        sourceY = Math.Clamp(sourceY, 0, height - 1);
        var sourceBlockX = sourceX / blueprint.BlockWidth;
        var sourceBlockY = sourceY / blueprint.BlockHeight;
        var sourceBlock = sourceBlockY * blockColumns + sourceBlockX;
        var destinationBlock = sourceToDestinationBlocks[sourceBlock];
        var destinationBlockX = destinationBlock % blockColumns;
        var destinationBlockY = destinationBlock / blockColumns;
        return new Cell(
            destinationBlockX * blueprint.BlockWidth +
                sourceX % blueprint.BlockWidth,
            destinationBlockY * blueprint.BlockHeight +
                sourceY % blueprint.BlockHeight);
    }

    private Cell DestinationWorldForSource(int sourceX, int sourceY)
    {
        var sourceCellX = Math.Clamp(sourceX / 32, 0, width - 1);
        var sourceCellY = Math.Clamp(sourceY / 16, 0, height - 1);
        var withinCellX = sourceX - sourceCellX * 32;
        var withinCellY = sourceY - sourceCellY * 16;
        var destination = DestinationCellForSource(
            sourceCellX, sourceCellY);
        return new Cell(
            checked(destination.X * 32 + withinCellX),
            checked(destination.Y * 16 + withinCellY));
    }

    private string BuildReport(
        string outputPath,
        VwfTerrainGrid outputTerrain,
        VwfSceneList outputScenes)
    {
        var movedBlocks = blueprint.DestinationToSourceBlocks
            .Select((sourceBlock, destinationBlock) =>
                sourceBlock == destinationBlock ? 0 : 1)
            .Sum();
        var changedTerrainCells = 0;
        for (var index = 0; index < cellCount; index++)
        {
            if (terrain.Layers[0].Values[index] !=
                outputTerrain.Layers[0].Values[index])
                changedTerrainCells++;
        }
        var sourceEntities = scenes.Entities.ToDictionary(
            entity => entity.SceneIndex);
        var movedEntities = outputScenes.Entities.Count(entity =>
        {
            var original = sourceEntities[entity.SceneIndex];
            return entity.WorldX != original.WorldX ||
                entity.WorldY != original.WorldY;
        });
        var sourceGroundHash = HashLayer(terrain.Layers[0].Values);
        var outputGroundHash = HashLayer(outputTerrain.Layers[0].Values);
        var changedPercent =
            changedTerrainCells * 100.0 / cellCount;

        var builder = new StringBuilder();
        builder.AppendLine(
            $"# {blueprint.Title}（{blueprint.Id}）区块合成报告");
        builder.AppendLine();
        builder.AppendLine(blueprint.Story);
        builder.AppendLine();
        builder.AppendLine("## 合成方式");
        builder.AppendLine();
        builder.AppendLine(
            $"- 网格：{width} × {height}，区块：" +
            $"{blueprint.BlockWidth} × {blueprint.BlockHeight}");
        builder.AppendLine(
            $"- 城区矩阵：{blockColumns} 列 × {blockRows} 行，" +
            $"共 {blockCount} 块");
        builder.AppendLine(
            $"- 已移动城区：{movedBlocks}/{blockCount}");
        builder.AppendLine(
            "- 目标到来源排列（按目标区块顺序）：" +
            $"`{string.Join(", ", blueprint.DestinationToSourceBlocks)}`");
        builder.AppendLine(
            "- 五个地形/视线/移动/事件/人工修正图层同步换位；" +
            "全部 scene 世界坐标、参考坐标和巡逻数组同步映射。");
        builder.AppendLine();
        builder.AppendLine("## 新地图差异量化");
        builder.AppendLine();
        builder.AppendLine(
            $"- 原位置地表发生变化：{changedTerrainCells}/{cellCount} " +
            $"格（{changedPercent:F2}%）");
        builder.AppendLine(
            $"- scene 世界坐标发生变化：{movedEntities}/" +
            $"{outputScenes.Entities.Count}");
        builder.AppendLine(
            $"- 源地表指纹：`{sourceGroundHash}`");
        builder.AppendLine(
            $"- 新地表指纹：`{outputGroundHash}`");
        builder.AppendLine();
        builder.AppendLine("## 文件与结构");
        builder.AppendLine();
        builder.AppendLine(
            $"- 源文件：`{Path.GetFileName(sourcePath)}`");
        builder.AppendLine(
            $"- 输出文件：`{Path.GetFileName(outputPath)}`");
        builder.AppendLine(
            $"- 场景槽位/有效对象：" +
            $"{outputScenes.SlotCount}/{outputScenes.Entities.Count}");
        builder.AppendLine(
            $"- 源 SHA-256：`{Hash(sourcePath)}`");
        builder.AppendLine(
            $"- 合成 SHA-256：`{Hash(outputPath)}`");
        builder.AppendLine();
        builder.AppendLine(
            "该文件是任务再部署前的结构化合成底图。最终关卡还必须经过 " +
            "VwfMissionBuilder 的出生安全、任务锚点和逐段 A* 校验。");
        return builder.ToString();
    }

    private int LayerDataOffset(int zeroBasedLayer)
    {
        var planeSize = checked(16 + cellCount * sizeof(uint));
        return checked(
            VwfTerrainGrid.PreambleSize +
            zeroBasedLayer * planeSize + 16);
    }

    private int CellIndex(int x, int y) => checked(y * width + x);

    private static void WritePoint(byte[] data, int offset, Cell point)
    {
        WriteUInt32(data, offset, checked((uint)point.X));
        WriteUInt32(data, offset + 4, checked((uint)point.Y));
    }

    private static uint ReadUInt32(byte[] data, int offset) =>
        BinaryPrimitives.ReadUInt32LittleEndian(data.AsSpan(offset, 4));

    private static void WriteUInt32(
        byte[] data, int offset, uint value) =>
        BinaryPrimitives.WriteUInt32LittleEndian(
            data.AsSpan(offset, 4), value);

    private static void WriteInt32(
        byte[] data, int offset, int value) =>
        BinaryPrimitives.WriteInt32LittleEndian(
            data.AsSpan(offset, 4), value);

    private static string Hash(string path)
    {
        using var stream = File.OpenRead(path);
        return Convert.ToHexString(SHA256.HashData(stream));
    }

    private static string HashLayer(IReadOnlyList<uint> values)
    {
        var bytes = new byte[checked(values.Count * sizeof(uint))];
        for (var index = 0; index < values.Count; index++)
        {
            BinaryPrimitives.WriteUInt32LittleEndian(
                bytes.AsSpan(index * sizeof(uint), sizeof(uint)),
                values[index]);
        }
        return Convert.ToHexString(SHA256.HashData(bytes));
    }

    private readonly record struct Cell(int X, int Y);
}
