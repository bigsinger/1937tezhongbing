using System.Buffers.Binary;
using System.Security.Cryptography;
using Mission1937.Remake.Resources;

namespace Mission1937.MapEditor.Core;

public sealed record NativeVwfSemanticChange(
    string Category,
    string Target,
    string Description);

public sealed record NativeVwfBinaryChange(
    long Offset,
    int Length,
    string BeforeHex,
    string AfterHex);

public sealed record NativeVwfDiff(
    string SourceSha256,
    string OutputSha256,
    int ChangedByteCount,
    IReadOnlyList<NativeVwfBinaryChange> BinaryChanges,
    IReadOnlyList<NativeVwfSemanticChange> SemanticChanges);

public sealed record NativeVwfSaveResult(
    string OutputPath,
    string? BackupPath,
    NativeVwfDiff Diff);

public static class NativeVwfWriter
{
    private const int MaximumBinaryRanges = 4096;
    private const int BinaryPreviewBytes = 16;

    public static NativeVwfDiff Analyze(
        MapDocument document,
        string sourceVwfPath) =>
        BuildPlan(document, sourceVwfPath).Diff;

    public static NativeVwfSaveResult SaveAs(
        MapDocument document,
        string sourceVwfPath,
        string outputVwfPath)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(outputVwfPath);
        var sourcePath = Path.GetFullPath(sourceVwfPath);
        var outputPath = Path.GetFullPath(outputVwfPath);
        if (sourcePath.Equals(
                outputPath, StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidOperationException(
                "原始 VWF 保持只读；请选择一个新的输出文件名。");
        }

        var plan = BuildPlan(document, sourcePath);
        var outputDirectory = Path.GetDirectoryName(outputPath)
            ?? throw new InvalidOperationException("输出路径没有父目录。");
        Directory.CreateDirectory(outputDirectory);
        var temporaryPath = Path.Combine(
            outputDirectory,
            $".{Path.GetFileName(outputPath)}.{Guid.NewGuid():N}.tmp");
        string? backupPath = null;
        try
        {
            using (var stream = new FileStream(
                       temporaryPath,
                       FileMode.CreateNew,
                       FileAccess.Write,
                       FileShare.None,
                       64 * 1024,
                       FileOptions.WriteThrough))
            {
                stream.Write(plan.Output);
                stream.Flush(true);
            }

            ValidateWrittenFile(
                plan.SourceWorld,
                plan.SourceTerrain,
                plan.SourceScenes,
                document,
                plan.EffectiveLayers,
                plan.Output,
                temporaryPath);

            if (File.Exists(outputPath))
            {
                backupPath = outputPath + ".bak";
                File.Copy(outputPath, backupPath, true);
                File.Replace(
                    temporaryPath,
                    outputPath,
                    null,
                    ignoreMetadataErrors: true);
            }
            else
            {
                File.Move(temporaryPath, outputPath);
            }
        }
        finally
        {
            if (File.Exists(temporaryPath))
                File.Delete(temporaryPath);
        }

        return new NativeVwfSaveResult(
            outputPath,
            backupPath,
            plan.Diff);
    }

    private static WritePlan BuildPlan(
        MapDocument document,
        string sourceVwfPath)
    {
        ArgumentNullException.ThrowIfNull(document);
        ArgumentException.ThrowIfNullOrWhiteSpace(sourceVwfPath);
        MapValidator.ThrowIfInvalid(document);

        var sourcePath = Path.GetFullPath(sourceVwfPath);
        var sourceBytes = File.ReadAllBytes(sourcePath);
        var sourceHash = Hash(sourceBytes);
        ValidateSourceIdentity(document, sourcePath, sourceHash);

        var world = VwfWorldHeader.Open(sourcePath);
        var terrain = VwfTerrainGrid.Open(sourcePath);
        var scenes = VwfSceneList.Open(sourcePath);
        if (scenes.FormatVersion != VwfSceneList.SupportedFormatVersion)
        {
            throw new InvalidDataException(
                $"只支持 SLIST1 版本 " +
                $"{VwfSceneList.SupportedFormatVersion}。");
        }
        if (document.Width != checked((int)world.GridWidth) ||
            document.Height != checked((int)world.GridHeight) ||
            document.EffectiveCellWidth != 32 ||
            document.EffectiveCellHeight != 16)
        {
            throw new InvalidDataException(
                "工程尺寸或格尺寸与原始 VWF 不一致；原生另存不允许改变结构。");
        }

        var objectsByScene = ValidateSceneSet(document, scenes);
        var output = sourceBytes.ToArray();
        var semantic = new List<NativeVwfSemanticChange>();
        var effectiveLayers = BuildEffectiveLayers(
            document, terrain, scenes, objectsByScene, semantic);
        WriteLayers(
            output, world, terrain, effectiveLayers, semantic);
        WriteEntities(
            output, document, scenes, objectsByScene, semantic);

        var diff = BuildDiff(sourceBytes, output, sourceHash, semantic);
        return new WritePlan(
            output,
            world,
            terrain,
            scenes,
            effectiveLayers,
            diff);
    }

    private static void ValidateSourceIdentity(
        MapDocument document,
        string sourcePath,
        string sourceHash)
    {
        if (string.IsNullOrWhiteSpace(document.ImportedFrom))
        {
            throw new InvalidOperationException(
                "该工程不是从原始 VWF 导入，不能执行原生另存。");
        }
        if (!Path.GetFileName(sourcePath).Equals(
                document.ImportedFrom,
                StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidDataException(
                $"源文件名应为 {document.ImportedFrom}。");
        }
        if (!string.IsNullOrWhiteSpace(document.ImportedSourceSha256) &&
            !sourceHash.Equals(
                document.ImportedSourceSha256,
                StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidDataException(
                "源 VWF 的 SHA-256 与导入时不一致，已拒绝写回。");
        }
    }

    private static Dictionary<int, MapObject> ValidateSceneSet(
        MapDocument document,
        VwfSceneList scenes)
    {
        var result = new Dictionary<int, MapObject>();
        foreach (var item in document.Objects)
        {
            if (!TrySceneIndex(item.Id, out var sceneIndex))
            {
                throw new InvalidDataException(
                    $"对象“{item.Name}”没有原始 scene 槽位；" +
                    "当前安全格式不允许增加 scene 记录。");
            }
            if (!result.TryAdd(sceneIndex, item))
            {
                throw new InvalidDataException(
                    $"scene-{sceneIndex} 在工程中出现多次。");
            }
        }

        var expected = scenes.Entities
            .Select(entity => entity.SceneIndex)
            .ToHashSet();
        if (!expected.SetEquals(result.Keys))
        {
            var missing = expected.Except(result.Keys).Take(8);
            var added = result.Keys.Except(expected).Take(8);
            throw new InvalidDataException(
                "原生另存不允许增加或删除 scene。缺少：" +
                $"{string.Join(", ", missing)}；额外：" +
                $"{string.Join(", ", added)}。");
        }
        return result;
    }

    private static uint[][] BuildEffectiveLayers(
        MapDocument document,
        VwfTerrainGrid terrain,
        VwfSceneList scenes,
        IReadOnlyDictionary<int, MapObject> objects,
        List<NativeVwfSemanticChange> semantic)
    {
        var layers = new uint[VwfTerrainGrid.LayerCount][];
        for (var layerIndex = 0;
             layerIndex < VwfTerrainGrid.LayerCount;
             ++layerIndex)
        {
            var kind = (EditorLayerKind)layerIndex;
            var source = document.Layer(kind).Cells;
            layers[layerIndex] = source
                .Select(value => unchecked((uint)value))
                .ToArray();
        }

        var movement = layers[(int)EditorLayerKind.MovementObstacle];
        var sourceMovement =
            terrain.Layers[(int)EditorLayerKind.MovementObstacle].Values;
        var moves = new List<OccupancyMove>();
        foreach (var entity in scenes.Entities)
        {
            var item = objects[entity.SceneIndex];
            var originalX = Math.Clamp(
                entity.WorldX / document.EffectiveCellWidth,
                0, document.Width - 1);
            var originalY = Math.Clamp(
                entity.WorldY / document.EffectiveCellHeight,
                0, document.Height - 1);
            if (item.X == originalX && item.Y == originalY)
                continue;

            var marker = checked((uint)(entity.SceneIndex + 1000));
            var occupied = Enumerable.Range(0, sourceMovement.Count)
                .Where(index => sourceMovement[index] == marker)
                .ToArray();
            if (occupied.Length == 0)
                continue;
            moves.Add(new OccupancyMove(
                entity.SceneIndex,
                marker,
                item.X - originalX,
                item.Y - originalY,
                occupied));
            foreach (var index in Enumerable.Range(0, movement.Length)
                         .Where(index => movement[index] == marker))
            {
                movement[index] = 0;
            }
        }

        foreach (var move in moves)
        {
            foreach (var sourceIndex in move.SourceIndices)
            {
                var sourceX = sourceIndex % document.Width;
                var sourceY = sourceIndex / document.Width;
                var targetX = sourceX + move.DeltaX;
                var targetY = sourceY + move.DeltaY;
                if (targetX < 0 || targetX >= document.Width ||
                    targetY < 0 || targetY >= document.Height)
                {
                    throw new InvalidDataException(
                        $"scene-{move.SceneIndex} 的动态占用移动后越界。");
                }
                var targetIndex = checked(
                    targetY * document.Width + targetX);
                if (movement[targetIndex] != 0 &&
                    movement[targetIndex] != move.Marker)
                {
                    throw new InvalidDataException(
                        $"scene-{move.SceneIndex} 的动态占用与格 " +
                        $"({targetX}, {targetY}) 现有障碍冲突。");
                }
                movement[targetIndex] = move.Marker;
            }
            semantic.Add(new NativeVwfSemanticChange(
                "occupancy",
                $"scene-{move.SceneIndex}",
                $"动态占用平移 ({move.DeltaX}, {move.DeltaY})，" +
                $"{move.SourceIndices.Count} 格"));
        }
        return layers;
    }

    private static void WriteLayers(
        byte[] output,
        VwfWorldHeader world,
        VwfTerrainGrid terrain,
        IReadOnlyList<uint[]> layers,
        List<NativeVwfSemanticChange> semantic)
    {
        for (var layerIndex = 0;
             layerIndex < VwfTerrainGrid.LayerCount;
             ++layerIndex)
        {
            var offset = checked((int)VwfTerrainGrid.LayerDataOffset(
                world.GridWidth, world.GridHeight, layerIndex));
            var changed = 0;
            for (var index = 0; index < layers[layerIndex].Length; ++index)
            {
                var value = layers[layerIndex][index];
                if (value == terrain.Layers[layerIndex].Values[index])
                    continue;
                WriteUInt32(
                    output,
                    checked(offset + index * sizeof(uint)),
                    value);
                changed++;
            }
            if (changed > 0)
            {
                semantic.Add(new NativeVwfSemanticChange(
                    "layer",
                    ((EditorLayerKind)layerIndex).ToString(),
                    $"{changed} 个网格值变化"));
            }
        }
    }

    private static void WriteEntities(
        byte[] output,
        MapDocument document,
        VwfSceneList scenes,
        IReadOnlyDictionary<int, MapObject> objects,
        List<NativeVwfSemanticChange> semantic)
    {
        foreach (var entity in scenes.Entities)
        {
            var item = objects[entity.SceneIndex];
            if (item.Direction < 0)
            {
                throw new InvalidDataException(
                    $"scene-{entity.SceneIndex} 的朝向不能为负数。");
            }
            var originalCellX = Math.Clamp(
                entity.WorldX / document.EffectiveCellWidth,
                0, document.Width - 1);
            var originalCellY = Math.Clamp(
                entity.WorldY / document.EffectiveCellHeight,
                0, document.Height - 1);
            var moved = item.X != originalCellX || item.Y != originalCellY;
            var worldX = moved
                ? checked(
                    item.X * document.EffectiveCellWidth +
                    PositiveModulo(
                        entity.WorldX,
                        document.EffectiveCellWidth))
                : entity.WorldX;
            var worldY = moved
                ? checked(
                    item.Y * document.EffectiveCellHeight +
                    PositiveModulo(
                        entity.WorldY,
                        document.EffectiveCellHeight))
                : entity.WorldY;
            var referenceX = moved
                ? checked(worldX + entity.ReferenceX - entity.WorldX)
                : entity.ReferenceX;
            var referenceY = moved
                ? checked(worldY + entity.ReferenceY - entity.WorldY)
                : entity.ReferenceY;
            var record = checked((int)entity.RecordOffset);

            if (moved)
            {
                WriteInt32(
                    output,
                    record + VwfSceneList.EntityWorldXOffset,
                    worldX);
                WriteInt32(
                    output,
                    record + VwfSceneList.EntityWorldYOffset,
                    worldY);
                WriteInt32(
                    output,
                    record + VwfSceneList.EntityReferenceXOffset,
                    referenceX);
                WriteInt32(
                    output,
                    record + VwfSceneList.EntityReferenceYOffset,
                    referenceY);
                semantic.Add(new NativeVwfSemanticChange(
                    "entity",
                    item.Id,
                    $"位置 ({originalCellX}, {originalCellY}) → " +
                    $"({item.X}, {item.Y})，参考坐标同步"));
            }

            if (checked((uint)item.Direction) != entity.DirectionIndex)
            {
                WriteUInt32(
                    output,
                    record + VwfSceneList.EntityDirectionOffset,
                    checked((uint)item.Direction));
                semantic.Add(new NativeVwfSemanticChange(
                    "entity",
                    item.Id,
                    $"朝向 {entity.DirectionIndex} → {item.Direction}"));
            }

            WritePatrol(output, document, entity, item, semantic);
        }
    }

    private static void WritePatrol(
        byte[] output,
        MapDocument document,
        VwfSceneEntity entity,
        MapObject item,
        List<NativeVwfSemanticChange> semantic)
    {
        var patrol = entity.Patrol;
        if (patrol is null)
        {
            if (item.PatrolWaypoints.Count != 0 ||
                item.PatrolEnabled ||
                item.PatrolCurrentWaypointIndex != 0)
            {
                throw new InvalidDataException(
                    $"{item.Id} 原记录没有巡逻容量，不能新增巡逻数组。");
            }
            return;
        }
        if (item.PatrolWaypoints.Count != patrol.Waypoints.Count)
        {
            throw new InvalidDataException(
                $"{item.Id} 的巡逻容量必须保持 " +
                $"{patrol.Waypoints.Count}，当前为 " +
                $"{item.PatrolWaypoints.Count}。");
        }
        if (item.PatrolWaypoints.Count == 0 &&
            item.PatrolCurrentWaypointIndex != 0)
        {
            throw new InvalidDataException(
                $"{item.Id} 的空巡逻路线索引必须为 0。");
        }
        if (item.PatrolWaypoints.Count > 0 &&
            (item.PatrolCurrentWaypointIndex < 0 ||
             item.PatrolCurrentWaypointIndex >=
             item.PatrolWaypoints.Count))
        {
            throw new InvalidDataException(
                $"{item.Id} 的巡逻索引超出容量。");
        }

        var pointsChanged = item.PatrolWaypoints
            .Select((point, index) =>
                point.X != checked((int)patrol.Waypoints[index].X) ||
                point.Y != checked((int)patrol.Waypoints[index].Y))
            .Any(changed => changed);
        var indexChanged =
            checked((uint)item.PatrolCurrentWaypointIndex) !=
            patrol.CurrentWaypointIndex;
        var desiredPersistentFlag =
            item.PatrolEnabled == (patrol.PersistentFlag != 0)
                ? patrol.PersistentFlag
                : item.PatrolEnabled ? 1u : 0u;
        var flagChanged = desiredPersistentFlag != patrol.PersistentFlag;
        if (!pointsChanged && !indexChanged && !flagChanged)
            return;

        var count = item.PatrolWaypoints.Count;
        var patrolOffset = checked(
            (int)entity.RecordOffset +
            VwfSceneList.EntityPatrolRecordOffset);
        var workingPointsOffset = patrolOffset + 12;
        var currentIndexOffset = checked(patrolOffset + 16 + count * 8);
        var persistentFlagOffset = checked(patrolOffset + 20 + count * 8);
        var cachedXOffset = checked(patrolOffset + 24 + count * 8);
        var cachedYOffset = checked(patrolOffset + 28 + count * 8);
        var waypointOffset = checked(patrolOffset + 32 + count * 8);

        for (var index = 0; index < count; ++index)
        {
            var point = item.PatrolWaypoints[index];
            WritePoint(
                output,
                checked(workingPointsOffset + index * 8),
                point);
            WritePoint(
                output,
                checked(waypointOffset + index * 8),
                point);
        }
        WriteUInt32(
            output,
            currentIndexOffset,
            checked((uint)item.PatrolCurrentWaypointIndex));
        WriteUInt32(
            output,
            persistentFlagOffset,
            desiredPersistentFlag);
        if (count > 0)
        {
            var current =
                item.PatrolWaypoints[item.PatrolCurrentWaypointIndex];
            WriteInt32(
                output,
                cachedXOffset,
                checked(
                    current.X * document.EffectiveCellWidth +
                    document.EffectiveCellWidth / 2));
            WriteInt32(
                output,
                cachedYOffset,
                checked(
                    current.Y * document.EffectiveCellHeight +
                    document.EffectiveCellHeight / 2));
        }
        semantic.Add(new NativeVwfSemanticChange(
            "patrol",
            item.Id,
            $"同步 {count} 个工作点/路线点、当前索引和持久标志"));
    }

    private static void ValidateWrittenFile(
        VwfWorldHeader sourceWorld,
        VwfTerrainGrid sourceTerrain,
        VwfSceneList sourceScenes,
        MapDocument document,
        IReadOnlyList<uint[]> effectiveLayers,
        byte[] expectedBytes,
        string temporaryPath)
    {
        var actualBytes = File.ReadAllBytes(temporaryPath);
        if (!actualBytes.AsSpan().SequenceEqual(expectedBytes))
            throw new IOException("临时 VWF 落盘内容与写入计划不一致。");

        var world = VwfWorldHeader.Open(temporaryPath);
        var terrain = VwfTerrainGrid.Open(temporaryPath);
        var scenes = VwfSceneList.Open(temporaryPath);
        if (actualBytes.Length != expectedBytes.Length ||
            world.GridWidth != sourceWorld.GridWidth ||
            world.GridHeight != sourceWorld.GridHeight ||
            world.SceneListOffset != sourceWorld.SceneListOffset ||
            terrain.SceneListOffset != sourceTerrain.SceneListOffset ||
            scenes.FormatVersion != sourceScenes.FormatVersion ||
            scenes.SlotCount != sourceScenes.SlotCount ||
            scenes.Entities.Count != sourceScenes.Entities.Count)
        {
            throw new InvalidDataException(
                "临时 VWF 重解析后的顶层结构发生变化。");
        }

        for (var layerIndex = 0;
             layerIndex < VwfTerrainGrid.LayerCount;
             ++layerIndex)
        {
            if (!terrain.Layers[layerIndex].Values.SequenceEqual(
                    effectiveLayers[layerIndex]))
            {
                throw new InvalidDataException(
                    $"临时 VWF 的第 {layerIndex + 1} 层语义校验失败。");
            }
        }

        var sourceById = sourceScenes.Entities.ToDictionary(
            entity => entity.SceneIndex);
        var outputById = scenes.Entities.ToDictionary(
            entity => entity.SceneIndex);
        foreach (var (sceneIndex, source) in sourceById)
        {
            if (!outputById.TryGetValue(sceneIndex, out var output) ||
                output.RecordLength != source.RecordLength ||
                output.DatabaseEntryId != source.DatabaseEntryId ||
                output.FormatVersion != source.FormatVersion ||
                !output.AuxiliaryArrayLengths.SequenceEqual(
                    source.AuxiliaryArrayLengths) ||
                (output.Patrol is null) != (source.Patrol is null) ||
                output.Patrol?.Waypoints.Count !=
                    source.Patrol?.Waypoints.Count)
            {
                throw new InvalidDataException(
                    $"scene-{sceneIndex} 的记录长度、引用或容量发生变化。");
            }

            var item = document.Objects.Single(
                candidate => candidate.Id == $"scene-{sceneIndex}");
            var expectedCellX = Math.Clamp(
                output.WorldX / document.EffectiveCellWidth,
                0, document.Width - 1);
            var expectedCellY = Math.Clamp(
                output.WorldY / document.EffectiveCellHeight,
                0, document.Height - 1);
            if (expectedCellX != item.X ||
                expectedCellY != item.Y ||
                output.DirectionIndex != checked((uint)item.Direction))
            {
                throw new InvalidDataException(
                    $"scene-{sceneIndex} 的位置或朝向语义校验失败。");
            }
            if (output.Patrol is not null &&
                (!output.Patrol.Waypoints
                     .Select((point, index) =>
                         point.X == checked((uint)item.PatrolWaypoints[index].X) &&
                         point.Y == checked((uint)item.PatrolWaypoints[index].Y))
                     .All(equal => equal) ||
                 output.Patrol.CurrentWaypointIndex !=
                     checked((uint)item.PatrolCurrentWaypointIndex) ||
                 (output.Patrol.PersistentFlag != 0) !=
                     item.PatrolEnabled))
            {
                throw new InvalidDataException(
                    $"scene-{sceneIndex} 的巡逻语义校验失败。");
            }
        }
    }

    private static NativeVwfDiff BuildDiff(
        byte[] source,
        byte[] output,
        string sourceHash,
        IReadOnlyList<NativeVwfSemanticChange> semantic)
    {
        var ranges = new List<NativeVwfBinaryChange>();
        var changedBytes = 0;
        var index = 0;
        while (index < source.Length)
        {
            if (source[index] == output[index])
            {
                index++;
                continue;
            }
            var start = index;
            while (index < source.Length &&
                   source[index] != output[index])
            {
                changedBytes++;
                index++;
            }
            if (ranges.Count >= MaximumBinaryRanges)
                continue;
            var length = index - start;
            var previewLength = Math.Min(length, BinaryPreviewBytes);
            ranges.Add(new NativeVwfBinaryChange(
                start,
                length,
                Convert.ToHexString(
                    source.AsSpan(start, previewLength)),
                Convert.ToHexString(
                    output.AsSpan(start, previewLength))));
        }
        return new NativeVwfDiff(
            sourceHash,
            Hash(output),
            changedBytes,
            ranges,
            semantic.ToArray());
    }

    private static bool TrySceneIndex(
        string id,
        out int sceneIndex)
    {
        sceneIndex = -1;
        return id.StartsWith("scene-", StringComparison.Ordinal) &&
            int.TryParse(id.AsSpan(6), out sceneIndex) &&
            sceneIndex >= 0;
    }

    private static int PositiveModulo(int value, int modulus)
    {
        var remainder = value % modulus;
        return remainder < 0 ? remainder + modulus : remainder;
    }

    private static void WritePoint(
        byte[] output,
        int offset,
        MapWaypoint point)
    {
        WriteUInt32(output, offset, checked((uint)point.X));
        WriteUInt32(output, offset + sizeof(uint), checked((uint)point.Y));
    }

    private static void WriteUInt32(
        byte[] output,
        int offset,
        uint value) =>
        BinaryPrimitives.WriteUInt32LittleEndian(
            output.AsSpan(offset, sizeof(uint)),
            value);

    private static void WriteInt32(
        byte[] output,
        int offset,
        int value) =>
        BinaryPrimitives.WriteInt32LittleEndian(
            output.AsSpan(offset, sizeof(int)),
            value);

    private static string Hash(byte[] data) =>
        Convert.ToHexString(SHA256.HashData(data));

    private sealed record OccupancyMove(
        int SceneIndex,
        uint Marker,
        int DeltaX,
        int DeltaY,
        IReadOnlyList<int> SourceIndices);

    private sealed record WritePlan(
        byte[] Output,
        VwfWorldHeader SourceWorld,
        VwfTerrainGrid SourceTerrain,
        VwfSceneList SourceScenes,
        IReadOnlyList<uint[]> EffectiveLayers,
        NativeVwfDiff Diff);
}
