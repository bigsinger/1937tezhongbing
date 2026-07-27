using Mission1937.MapEditor.Core;
using Mission1937.Remake.Resources;

var preferredTestRoot =
    Environment.GetEnvironmentVariable("M1937_TEST_ROOT");
if (string.IsNullOrWhiteSpace(preferredTestRoot))
{
    preferredTestRoot = Directory.Exists(@"E:\1937")
        ? @"E:\1937\map-editor-tests"
        : Path.Combine(Path.GetTempPath(), "1937-map-editor-tests");
}
var root = Path.Combine(
    preferredTestRoot,
    Environment.ProcessId.ToString());
Directory.CreateDirectory(root);
var path = Path.Combine(root, "roundtrip.m37map.json");
var document = MapDocument.Create("往返测试", 16, 12);
document.CellWidth = 32;
document.CellHeight = 16;
document.BackgroundAsset = "maps/m000/terrain.png";
document.Layer(EditorLayerKind.Terrain)
    .Cells[document.Index(3, 4)] = 37;
document.Layer(EditorLayerKind.MovementObstacle)
    .Cells[document.Index(4, 4)] = 1;
document.Objects.Add(new MapObject
{
    Id = "enemy-1",
    Name = "哨兵",
    Category = "角色",
    AssetPath = "sprites/0001.png",
    X = 8,
    Y = 6,
    Kind = "character",
    PatrolEnabled = true,
    PatrolCurrentWaypointIndex = 1,
    PatrolWaypoints =
    [
        new MapWaypoint { X = 8, Y = 6 },
        new MapWaypoint { X = 12, Y = 6 }
    ]
});
document.Tasks[0].TargetObjectId = "enemy-1";
MapDocumentSerializer.Save(document, path);
var restored = MapDocumentSerializer.Load(path);

if (restored.Name != document.Name ||
    restored.EffectiveCellWidth != 32 ||
    restored.EffectiveCellHeight != 16 ||
    restored.BackgroundAsset != document.BackgroundAsset ||
    restored.Layer(EditorLayerKind.Terrain)
        .Cells[restored.Index(3, 4)] != 37 ||
    restored.Objects.Single().AssetPath != "sprites/0001.png" ||
    restored.Objects.Single().PatrolWaypoints.Count != 2 ||
    restored.Objects.Single().PatrolCurrentWaypointIndex != 1 ||
    !restored.Objects.Single().PatrolEnabled ||
    !restored.Objects.Single().IsLiving ||
    MapValidator.Validate(restored).Count != 0)
{
    throw new InvalidOperationException(
        "Map document round-trip test failed.");
}

Console.WriteLine("MapEditor core tests passed.");

var history = new MapEditHistory();
var historyBefore = MapDocument.Create("历史-前", 8, 8);
var historyAfter = MapDocumentSerializer.Clone(historyBefore);
historyAfter.Name = "历史-后";
history.Commit("修改名称", historyBefore, historyAfter);
if (!history.CanUndo ||
    history.Undo().Name != "历史-前" ||
    !history.CanRedo ||
    history.Redo().Name != "历史-后")
{
    throw new InvalidOperationException(
        "Map editor Undo/Redo command history test failed.");
}
var coalescedAfter = MapDocumentSerializer.Clone(historyAfter);
coalescedAfter.Name = "历史-合并";
history.Commit(
    "修改名称",
    historyAfter,
    coalescedAfter,
    "name");
var coalescedAgain = MapDocumentSerializer.Clone(coalescedAfter);
coalescedAgain.Name = "历史-合并-最终";
history.Commit(
    "修改名称",
    coalescedAfter,
    coalescedAgain,
    "name");
if (history.Undo().Name != "历史-后")
{
    throw new InvalidOperationException(
        "Map editor coalesced command test failed.");
}
Console.WriteLine("MapEditor Undo/Redo history tests passed.");

var qualityMap = MapDocument.Create("质量检查", 8, 8);
qualityMap.Objects.Add(new MapObject
{
    Id = "player",
    Name = "玩家",
    Kind = "character",
    Faction = "player",
    X = 1,
    Y = 1
});
qualityMap.Objects.Add(new MapObject
{
    Id = "enemy",
    Name = "敌军",
    Kind = "character",
    Faction = "enemy",
    X = 2,
    Y = 1
});
qualityMap.Objects.Add(new MapObject
{
    Id = "building",
    Name = "房屋",
    Kind = "building",
    X = 4,
    Y = 4
});
qualityMap.Tasks[0].TargetObjectId = "missing";
var qualityIssues = MapQualityAnalyzer.Analyze(qualityMap);
if (!qualityIssues.Any(issue =>
        issue.Code == "SPAWN_IN_ATTACK_RANGE") ||
    !qualityIssues.Any(issue =>
        issue.Code == "FOOTPRINT_MOVEMENT_MISMATCH") ||
    !qualityIssues.Any(issue =>
        issue.Code == "TASK_TARGET_MISSING"))
{
    throw new InvalidOperationException(
        "Map quality issue analyzer test failed.");
}
Console.WriteLine("MapEditor quality issue tests passed.");

var visibleWindow = MapSpatialAnalysis.VisibleGridWindow(
    viewportLeft: 2_400,
    viewportTop: 1_200,
    viewportWidth: 1_920,
    viewportHeight: 1_080,
    cellWidth: 3.2,
    cellHeight: 1.6,
    mapWidth: 2_048,
    mapHeight: 2_048,
    marginCells: 2);
if (visibleWindow.IsEmpty ||
    visibleWindow.CellCount >= 2_048 * 2_048 / 2 ||
    visibleWindow.Left < 0 ||
    visibleWindow.RightExclusive > 2_048)
{
    throw new InvalidOperationException(
        "Large-map visible-window culling test failed.");
}

var spatialMap = MapDocument.Create("空间分析", 20, 20);
spatialMap.CellWidth = 32;
spatialMap.CellHeight = 16;
var observer = new MapObject
{
    Id = "observer",
    Name = "观察者",
    Kind = "character",
    Faction = "enemy",
    X = 5,
    Y = 10,
    Direction = 3
};
var target = new MapObject
{
    Id = "target",
    Name = "目标",
    Kind = "character",
    Faction = "player",
    X = 10,
    Y = 10
};
spatialMap.Objects.Add(observer);
spatialMap.Objects.Add(target);
for (var y = 8; y <= 12; y++)
{
    spatialMap.Layer(EditorLayerKind.LineOfSightObstacle)
        .Cells[spatialMap.Index(8, y)] = 1;
}
for (var y = 0; y < spatialMap.Height; y++)
{
    spatialMap.Layer(EditorLayerKind.MovementObstacle)
        .Cells[spatialMap.Index(8, y)] = 1;
}
var boundary = MapSpatialAnalysis.BuildOccludedVisionBoundary(
    spatialMap,
    observer,
    EnemyPreviewProfile.EditorDefault);
if (MapSpatialAnalysis.DirectionDegrees(3) != 0 ||
    MapSpatialAnalysis.HasLineOfSight(
        spatialMap,
        observer,
        target,
        EnemyPreviewProfile.EditorDefault) ||
    boundary.Count < 10)
{
    throw new InvalidOperationException(
        "Direction/occluded-sector spatial analysis test failed.");
}
var reachable = MapSpatialAnalysis.BuildReachability(
    spatialMap, observer.X, observer.Y);
if (!reachable.IsReachable(7, 10) ||
    reachable.IsReachable(10, 10))
{
    throw new InvalidOperationException(
        "Reachability heat-map test failed.");
}
Console.WriteLine(
    "MapEditor viewport, heat-map and occluded-sector tests passed.");

var originalVwf =
    Environment.GetEnvironmentVariable("M1937_TEST_VWF");
var originalAssets =
    Environment.GetEnvironmentVariable("M1937_MAPEDITOR_ASSETS");
if (!string.IsNullOrWhiteSpace(originalVwf))
{
    var imported = OriginalVwfImporter.Import(
        originalVwf, originalAssets);
    Console.WriteLine(
        $"Imported diagnostic: {imported.Width}x{imported.Height}, " +
        $"layers={imported.Layers.Count}, objects={imported.Objects.Count}, " +
        $"cell={imported.EffectiveCellWidth}x" +
        $"{imported.EffectiveCellHeight}.");
    if (imported.Width <= 0 || imported.Height <= 0 ||
        imported.Layers.Count != 5 || imported.Objects.Count == 0 ||
        imported.EffectiveCellWidth != 32 ||
        imported.EffectiveCellHeight != 16)
    {
        throw new InvalidOperationException(
            "Original VWF import smoke test failed.");
    }
    if (!string.IsNullOrWhiteSpace(originalAssets) &&
        (string.IsNullOrWhiteSpace(imported.BackgroundAsset) ||
         imported.Objects.All(item =>
             string.IsNullOrWhiteSpace(item.AssetPath))))
    {
        throw new InvalidOperationException(
            "Original asset enrichment test failed.");
    }
    if (Path.GetFileName(originalVwf)
            .Equals("1937m014.vwf",
                StringComparison.OrdinalIgnoreCase) &&
        !imported.BackgroundAsset.Equals(
            "maps/m014/terrain.png",
            StringComparison.OrdinalIgnoreCase))
    {
        throw new InvalidOperationException(
            "Composite terrain/entity alias test failed.");
    }
    var importedRoutes = imported.Objects.Count(
        item => item.PatrolWaypoints.Count > 0);
    if (importedRoutes == 0 ||
        imported.Objects
            .Where(item => item.PatrolWaypoints.Count > 0)
            .Any(item => !item.IsLiving))
    {
        throw new InvalidOperationException(
            "Original VWF patrol-route import test failed.");
    }
    Console.WriteLine(
        $"Original VWF import passed: " +
        $"{imported.Width}x{imported.Height}, " +
        $"{imported.Objects.Count} objects, " +
        $"{importedRoutes} patrol routes, " +
        $"background={imported.BackgroundAsset}.");
}

var vwfDirectory =
    Environment.GetEnvironmentVariable("M1937_TEST_VWF_DIRECTORY");
if (!string.IsNullOrWhiteSpace(vwfDirectory))
{
    RunNativeVwfTests(Path.GetFullPath(vwfDirectory), root);
}

static void RunNativeVwfTests(
    string vwfDirectory,
    string testRoot)
{
    var roundTripRoot = Path.Combine(testRoot, "native-vwf-roundtrip");
    Directory.CreateDirectory(roundTripRoot);
    var levels = Enumerable.Range(0, 15)
        .Select(index => Path.Combine(
            vwfDirectory, $"1937m{index:D3}.vwf"))
        .ToArray();
    if (levels.Any(path => !File.Exists(path)))
    {
        throw new InvalidOperationException(
            "Native VWF matrix requires 1937m000.vwf through " +
            "1937m014.vwf.");
    }

    foreach (var source in levels)
    {
        var imported = OriginalVwfImporter.Import(source);
        var output = Path.Combine(
            roundTripRoot, Path.GetFileName(source));
        var result = NativeVwfWriter.SaveAs(
            imported, source, output);
        if (result.Diff.ChangedByteCount != 0 ||
            result.Diff.BinaryChanges.Count != 0 ||
            result.Diff.SemanticChanges.Count != 0 ||
            !File.ReadAllBytes(source).AsSpan().SequenceEqual(
                File.ReadAllBytes(output)))
        {
            throw new InvalidOperationException(
                $"No-change native VWF round-trip failed for " +
                $"{Path.GetFileName(source)}.");
        }
    }
    Console.WriteLine(
        "Native VWF no-change round-trip passed for m000-m014.");

    var baselineSource = levels[0];
    var changed = OriginalVwfImporter.Import(baselineSource);
    var changedObject = changed.Objects[0];
    changedObject.Direction = checked(changedObject.Direction + 1);
    var changedDiff = NativeVwfWriter.Analyze(
        changed, baselineSource);
    if (changedDiff.ChangedByteCount == 0 ||
        changedDiff.BinaryChanges.Count == 0 ||
        changedDiff.SemanticChanges.All(
            item => item.Category != "entity"))
    {
        throw new InvalidOperationException(
            "Native VWF binary/semantic diff did not report an edit.");
    }
    var existingOutput = Path.Combine(
        roundTripRoot, Path.GetFileName(baselineSource));
    var changedResult = NativeVwfWriter.SaveAs(
        changed, baselineSource, existingOutput);
    if (changedResult.BackupPath is null ||
        !File.Exists(changedResult.BackupPath) ||
        !File.ReadAllBytes(baselineSource).AsSpan().SequenceEqual(
            File.ReadAllBytes(changedResult.BackupPath)))
    {
        throw new InvalidOperationException(
            "Native VWF atomic replace did not preserve a .bak baseline.");
    }

    TestEntityOccupancyMove(
        baselineSource,
        roundTripRoot);
    TestPatrolSynchronization(
        baselineSource,
        roundTripRoot);

    ExpectRejected("scene count change", () =>
    {
        var candidate = OriginalVwfImporter.Import(baselineSource);
        candidate.Objects.Add(new MapObject
        {
            Id = "new-object",
            X = 1,
            Y = 1
        });
        _ = NativeVwfWriter.Analyze(candidate, baselineSource);
    });
    ExpectRejected("out-of-bounds object", () =>
    {
        var candidate = OriginalVwfImporter.Import(baselineSource);
        candidate.Objects[0].X = -1;
        _ = NativeVwfWriter.Analyze(candidate, baselineSource);
    });
    ExpectRejected("patrol capacity change", () =>
    {
        var candidate = OriginalVwfImporter.Import(baselineSource);
        var patrolObject = candidate.Objects.First(
            item => item.PatrolWaypoints.Count > 0);
        patrolObject.PatrolWaypoints.Add(new MapWaypoint
        {
            X = patrolObject.PatrolWaypoints[0].X,
            Y = patrolObject.PatrolWaypoints[0].Y
        });
        _ = NativeVwfWriter.Analyze(candidate, baselineSource);
    });
    ExpectRejected("damaged source", () =>
    {
        var corruptRoot = Path.Combine(testRoot, "damaged");
        Directory.CreateDirectory(corruptRoot);
        var corrupt = Path.Combine(
            corruptRoot, Path.GetFileName(baselineSource));
        var bytes = File.ReadAllBytes(baselineSource);
        File.WriteAllBytes(corrupt, bytes[..(bytes.Length / 2)]);
        var candidate = OriginalVwfImporter.Import(baselineSource);
        candidate.ImportedSourceSha256 = "";
        _ = NativeVwfWriter.Analyze(candidate, corrupt);
    });

    TestMissionPackageDraftService(
        baselineSource,
        testRoot);

    Console.WriteLine(
        "Native VWF negative and atomic-backup tests passed.");
}

static void TestMissionPackageDraftService(
    string sourceFixture,
    string testRoot)
{
    var repository = Path.Combine(
        testRoot, "mission-package-draft-repository");
    Directory.CreateDirectory(Path.Combine(repository, ".git"));
    Directory.CreateDirectory(
        Path.Combine(repository, "MapEditor", "Missions"));
    Directory.CreateDirectory(Path.Combine(repository, "Mod"));
    var source = Path.Combine(
        repository, "Mod", "1937m000.vwf");
    File.Copy(sourceFixture, source, overwrite: true);
    var imported = OriginalVwfImporter.Import(source);
    var firstScene = int.Parse(
        imported.Objects[0].Id.AsSpan(6));
    var options = new MissionPackageDraftOptions
    {
        RepositoryRoot = repository,
        SourceVwfPath = source,
        Title = "向导测试关",
        Story = "用于验证关卡包草案、候选哈希和人工接受边界。",
        Mode = MissionPackageMode.Redeploy,
        EngineMission = 1,
        PlayerSceneIndices = [firstScene]
    };
    var draft = MissionPackageDraftService.CreateDraft(options);
    if (draft.MissionId != "m001" ||
        draft.SelectorLevel != 2 ||
        !File.Exists(draft.ManifestPath) ||
        !File.Exists(draft.RouteDraftPath))
    {
        throw new InvalidOperationException(
            "Mission-package draft allocation/scaffold test failed.");
    }
    Directory.CreateDirectory(draft.CandidateWorkDirectory);
    File.Copy(
        source,
        MissionPackageDraftService.CandidateOutputPath(draft),
        overwrite: true);
    var hash = MissionPackageDraftService.CandidateSha256(draft);
    MissionPackageDraftService.AcceptCandidateHash(draft, hash);
    if (!File.Exists(Path.Combine(
            draft.MissionDirectory,
            "baseline-acceptance.json")) ||
        !File.ReadAllText(draft.ManifestPath)
            .Contains(hash, StringComparison.Ordinal))
    {
        throw new InvalidOperationException(
            "Mission-package explicit baseline acceptance test failed.");
    }
    ExpectRejected("second baseline acceptance", () =>
        MissionPackageDraftService.AcceptCandidateHash(draft, hash));

    var terrain = Path.Combine(
        repository,
        "MapEditor",
        "Assets",
        "Original",
        "maps",
        "m000",
        "terrain.png");
    Directory.CreateDirectory(Path.GetDirectoryName(terrain)!);
    File.WriteAllBytes(terrain, [0]);
    var composite = MissionPackageDraftService.CreateDraft(
        options with
        {
            Title = "合成向导测试关",
            Mode = MissionPackageMode.Composite,
            CompositeBlockWidth = 1,
            CompositeBlockHeight = imported.Height,
            BackgroundAsset = "maps/m000/terrain.png"
        });
    if (composite.MissionId != "m002" ||
        composite.BlueprintPath is null ||
        !File.Exists(composite.BlueprintPath) ||
        composite.ComposedWorkFile is null)
    {
        throw new InvalidOperationException(
            "Composite mission-package scaffold test failed.");
    }
    Console.WriteLine(
        "Mission-package GUI scaffold and manual hash tests passed.");
}

static void TestEntityOccupancyMove(
    string sourcePath,
    string outputRoot)
{
    var document = OriginalVwfImporter.Import(sourcePath);
    var terrain = VwfTerrainGrid.Open(sourcePath);
    var scenes = VwfSceneList.Open(sourcePath);
    var movement = terrain.Layers[
        (int)EditorLayerKind.MovementObstacle].Values;
    foreach (var entity in scenes.Entities)
    {
        var marker = checked((uint)(entity.SceneIndex + 1000));
        var occupied = Enumerable.Range(0, movement.Count)
            .Where(index => movement[index] == marker)
            .ToArray();
        if (occupied.Length == 0)
            continue;
        var item = document.Objects.Single(
            candidate => candidate.Id == $"scene-{entity.SceneIndex}");
        foreach (var delta in new[]
                 {
                     (X: 1, Y: 0),
                     (X: -1, Y: 0),
                     (X: 0, Y: 1),
                     (X: 0, Y: -1)
                 })
        {
            if (item.X + delta.X < 0 ||
                item.X + delta.X >= document.Width ||
                item.Y + delta.Y < 0 ||
                item.Y + delta.Y >= document.Height)
                continue;
            var sourceSet = occupied.ToHashSet();
            var targets = occupied.Select(index =>
            {
                var x = index % document.Width + delta.X;
                var y = index / document.Width + delta.Y;
                return x < 0 || x >= document.Width ||
                       y < 0 || y >= document.Height
                    ? -1
                    : y * document.Width + x;
            }).ToArray();
            if (targets.Any(index => index < 0) ||
                targets.Any(index =>
                    !sourceSet.Contains(index) &&
                    movement[index] != 0))
                continue;

            item.X += delta.X;
            item.Y += delta.Y;
            var output = Path.Combine(
                outputRoot, "entity-occupancy-move.vwf");
            _ = NativeVwfWriter.SaveAs(
                document, sourcePath, output);
            var outputScenes = VwfSceneList.Open(output);
            var moved = outputScenes.Entities.Single(
                candidate =>
                    candidate.SceneIndex == entity.SceneIndex);
            if (moved.WorldX - entity.WorldX != delta.X * 32 ||
                moved.WorldY - entity.WorldY != delta.Y * 16 ||
                moved.ReferenceX - entity.ReferenceX != delta.X * 32 ||
                moved.ReferenceY - entity.ReferenceY != delta.Y * 16)
            {
                throw new InvalidOperationException(
                    "Native VWF entity/reference coordinate sync failed.");
            }
            var outputMovement = VwfTerrainGrid.Open(output).Layers[
                (int)EditorLayerKind.MovementObstacle].Values;
            if (targets.Any(index => outputMovement[index] != marker))
            {
                throw new InvalidOperationException(
                    "Native VWF dynamic occupancy sync failed.");
            }
            Console.WriteLine(
                "Native VWF entity/reference/occupancy sync passed.");
            return;
        }
    }
    throw new InvalidOperationException(
        "Could not find a safe dynamic-occupancy move fixture.");
}

static void TestPatrolSynchronization(
    string sourcePath,
    string outputRoot)
{
    var document = OriginalVwfImporter.Import(sourcePath);
    var item = document.Objects.First(
        candidate => candidate.PatrolWaypoints.Count > 0);
    var sceneIndex = int.Parse(item.Id.AsSpan(6));
    var point = item.PatrolWaypoints[0];
    point.X = Math.Min(document.Width - 1, point.X + 1);
    item.PatrolCurrentWaypointIndex = 0;
    item.PatrolEnabled = !item.PatrolEnabled;
    var output = Path.Combine(
        outputRoot, "patrol-sync.vwf");
    _ = NativeVwfWriter.SaveAs(
        document, sourcePath, output);
    var patrol = VwfSceneList.Open(output).Entities.Single(
        entity => entity.SceneIndex == sceneIndex).Patrol
        ?? throw new InvalidOperationException(
            "Patrol record disappeared after native VWF save.");
    if (patrol.WorkingPoints[0].X != checked((uint)point.X) ||
        patrol.WorkingPoints[0].Y != checked((uint)point.Y) ||
        patrol.Waypoints[0].X != checked((uint)point.X) ||
        patrol.Waypoints[0].Y != checked((uint)point.Y) ||
        (patrol.PersistentFlag != 0) != item.PatrolEnabled)
    {
        throw new InvalidOperationException(
            "Native VWF patrol working/waypoint synchronization failed.");
    }
    Console.WriteLine("Native VWF patrol synchronization passed.");
}

static void ExpectRejected(
    string description,
    Action action)
{
    try
    {
        action();
    }
    catch (Exception exception) when (
        exception is InvalidDataException or
            InvalidOperationException or
            ArgumentException or
            OverflowException)
    {
        return;
    }
    throw new InvalidOperationException(
        $"Expected native VWF rejection: {description}.");
}
