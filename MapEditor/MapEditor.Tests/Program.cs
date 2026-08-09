using Mission1937.MapEditor.Core;
using Mission1937.Remake.Resources;
using System.Text.Json;

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

var editingMap = MapDocument.Create("编辑效率", 20, 16);
editingMap.Objects.AddRange(
[
    new MapObject
    {
        Id = "a", Name = "甲", Kind = "character",
        Category = "角色", Faction = "player", X = 2, Y = 2
    },
    new MapObject
    {
        Id = "b", Name = "乙", Kind = "character",
        Category = "角色", Faction = "player", X = 8, Y = 5
    },
    new MapObject
    {
        Id = "c", Name = "丙", Kind = "character",
        Category = "角色", Faction = "player", X = 14, Y = 8
    }
]);
var selection = MapObjectEditing.SelectRectangle(
    editingMap, 0, 0, 15, 9,
    new MapObjectFilter(Faction: "player"));
MapObjectEditing.Align(selection, MapAlignment.Top);
MapObjectEditing.Distribute(selection, MapDistribution.Horizontal);
MapObjectEditing.SetBatchProperties(
    selection, category: "我方角色", direction: 3);
var duplicates = MapObjectEditing.Duplicate(
    editingMap, selection.Take(2).ToArray(), 1, 2);
if (selection.Count != 3 ||
    selection.Any(item => item.Y != 2) ||
    selection.Select(item => item.X).Order().SequenceEqual(
        new[] { 2, 8, 14 }) == false ||
    duplicates.Count != 2 ||
    editingMap.Objects.Select(item => item.Id).Distinct().Count() !=
        editingMap.Objects.Count)
{
    throw new InvalidOperationException(
        "Multi-select/align/distribute/duplicate/batch editing failed.");
}
MapLayerPainter.PaintRectangle(
    editingMap, EditorLayerKind.MovementObstacle,
    1, 1, 4, 4, 1);
MapLayerPainter.PaintBrush(
    editingMap, EditorLayerKind.MovementObstacle,
    10, 10, 2, 1);
var filled = MapLayerPainter.FloodFill(
    editingMap, EditorLayerKind.Event, 0, 0, 7);
if (filled != editingMap.Width * editingMap.Height)
    throw new InvalidOperationException("Layer flood-fill failed.");
editingMap.Layer(EditorLayerKind.Event).Locked = true;
ExpectRejected(
    "locked layer paint",
    () => MapLayerPainter.PaintBrush(
        editingMap, EditorLayerKind.Event, 1, 1, 1, 0));
editingMap.Layer(EditorLayerKind.Event).Locked = false;
var patrol = editingMap.Objects[0];
patrol.Properties["patrol_capacity"] = "2";
_ = PatrolRouteEditing.Insert(editingMap, patrol, 0, 3, 3);
_ = PatrolRouteEditing.Insert(editingMap, patrol, 1, 4, 4);
ExpectRejected(
    "patrol capacity",
    () => PatrolRouteEditing.Insert(editingMap, patrol, 2, 5, 5));
_ = PatrolRouteEditing.Move(editingMap, patrol, 1, 6, 6);
_ = PatrolRouteEditing.Delete(patrol, 0);
var preset = LayerViewService.BuiltInPresets().Single(
    item => item.Name == "通行校验");
LayerViewService.Apply(editingMap, preset);
LayerViewService.Solo(editingMap, EditorLayerKind.MovementObstacle);
if (!editingMap.Layer(EditorLayerKind.MovementObstacle).Visible ||
    editingMap.Layers.Count(layer => layer.Visible) != 1)
    throw new InvalidOperationException("Layer preset/solo failed.");
Console.WriteLine(
    "MapEditor selection, paint, patrol, filter and layer controls passed.");

var recoveryRoot = Path.Combine(root, "recovery");
var sourceForRecovery = Path.Combine(root, "recovery-source.json");
MapDocumentSerializer.Save(editingMap, sourceForRecovery);
editingMap.Name = "自动保存恢复";
var autosave = MapAutosaveService.Save(
    editingMap, recoveryRoot, sourceForRecovery);
var recovery = MapAutosaveService.Inspect(autosave);
if (recovery is null ||
    recovery.Document.Name != "自动保存恢复" ||
    MapAutosaveService.FindCandidates(recoveryRoot).Count != 1)
    throw new InvalidOperationException("Autosave recovery failed.");
MapAutosaveService.Discard(autosave);
if (File.Exists(autosave))
    throw new InvalidOperationException("Autosave discard failed.");
Console.WriteLine("MapEditor atomic autosave/recovery tests passed.");

var missionMap = MapDocument.Create("任务图", 20, 20);
missionMap.Metadata["id"] = "editor-roundtrip";
missionMap.Metadata["selector_level"] = "12";
missionMap.Metadata["engine_mission"] = "11";
missionMap.Objects.Add(new MapObject
{
    Id = "player-1", Name = "队员", Kind = "character",
    Faction = "player", X = 1, Y = 1
});
missionMap.Objects.Add(new MapObject
{
    Id = "enemy-1", Name = "哨兵", Kind = "character",
    Faction = "enemy", X = 9, Y = 9, Direction = 3,
    Properties = { ["database_entry_id"] = "77" },
    PatrolEnabled = true,
    PatrolWaypoints =
    [
        new MapWaypoint { X = 9, Y = 9 },
        new MapWaypoint { X = 12, Y = 9 }
    ]
});
missionMap.Tasks =
[
    new MissionTask
    {
        Id = "infiltrate", Title = "潜入",
        Trigger = "arrival", TargetObjectId = "enemy-1",
        OriginalStateCode = 2
    },
    new MissionTask
    {
        Id = "evacuate", Title = "撤离",
        Trigger = "evacuation", DependsOn = ["infiltrate"],
        EvacuationCondition = "all_players_in_zone",
        OriginalStateCode = 7,
        Optional = true,
        FailureCondition = true,
        FailureReason = "未能按时撤离",
        SubjectDatabaseId = 77,
        SubjectFaction = 2,
        RegionX = 8,
        RegionY = 8,
        RegionRadius = 3,
        DeadlineMilliseconds = 45_000
    }
];
missionMap.Tasks[1].DependsOnText = "infiltrate, recon, infiltrate";
if (!missionMap.Tasks[1].DependsOn.SequenceEqual(
        new[] { "infiltrate", "recon" }))
    throw new InvalidOperationException(
        "Editable dependency list normalization failed.");
missionMap.Tasks[1].DependsOn = ["infiltrate"];
missionMap.PlayerTimeline.Add(new PlayerTimelineAction
{
    ActorId = "player-1",
    StartMilliseconds = 0,
    DurationMilliseconds = 5000,
    TargetX = 8,
    TargetY = 8
});
var graph = MissionGraphService.Build(missionMap);
var coordination = AiCoordinationSimulator.Simulate(
    missionMap, missionMap.Objects[1], 3, 3);
var timeline = PlayerTimelineSimulator.Simulate(
    missionMap, 6000, 500,
    EnemyPreviewProfile.ForDifficulty(3, 3));
if (graph.Errors.Count != 0 ||
    !graph.TopologicalOrder.SequenceEqual(
        new[] { "infiltrate", "evacuate" }) ||
    coordination.SearchPattern.Count != 4 ||
    timeline.Count != 13 ||
    timeline.All(frame => frame.PotentialDetections.Count == 0))
{
    throw new InvalidOperationException(
        "Mission graph/AI coordination/player timeline simulation failed.");
}
Console.WriteLine(
    "MapEditor mission graph, AI coordination and player timeline passed.");

var region = RegionLibraryService.Capture(
    missionMap, "哨所", 0, 0, 10, 10);
var regionPath = Path.Combine(root, "guard-post.m37region.json");
RegionLibraryService.Save(region, regionPath);
var targetMap = MapDocument.Create("区域目标", 30, 30);
var paste = RegionLibraryService.Paste(
    targetMap, RegionLibraryService.Load(regionPath), 10, 10);
if (paste.NewObjectIds.Count != 2 ||
    paste.IdRebindings.Count != 2 ||
    targetMap.Objects.Any(item => item.X < 10 || item.Y < 10))
    throw new InvalidOperationException(
        "Cross-map region capture/paste/rebinding failed.");

var mergeBase = MapDocument.Create("基础", 8, 8);
mergeBase.Objects.Add(new MapObject
{
    Id = "merge", Name = "对象", X = 1, Y = 1
});
var mergeOurs = MapDocumentSerializer.Clone(mergeBase);
mergeOurs.Objects[0].X = 2;
var mergeTheirs = MapDocumentSerializer.Clone(mergeBase);
mergeTheirs.Objects[0].Y = 3;
var semanticDiff = SemanticMapCollaboration.Diff(
    mergeBase, mergeOurs);
var semanticMerge = SemanticMapCollaboration.Merge(
    mergeBase, mergeOurs, mergeTheirs);
if (semanticDiff.Count == 0 ||
    semanticMerge.Conflicts.Count != 1)
    throw new InvalidOperationException(
        "Semantic diff/conflict detection failed.");

var interchange = new MapInterchangeRegistry();
var sidecarPath = Path.Combine(root, "mission.m1937mission.json");
var sidecarPlugin = interchange.FindForExport(sidecarPath);
sidecarPlugin.Export(
    missionMap, sidecarPath,
    new MapInterchangeContext("", null,
        new Dictionary<string, string>()));
var sidecarImported = interchange.FindForImport(sidecarPath).Import(
    sidecarPath,
    new MapInterchangeContext("", null,
        new Dictionary<string, string>()));
if (sidecarImported.Tasks.Count != missionMap.Tasks.Count ||
    sidecarImported.Metadata["id"] != "editor-roundtrip" ||
    sidecarImported.Metadata["selector_level"] != "12" ||
    sidecarImported.Metadata["engine_mission"] != "11" ||
    sidecarImported.Tasks[1].SubjectDatabaseId != 77 ||
    sidecarImported.Tasks[1].RegionRadius != 3 ||
    sidecarImported.Tasks[1].DeadlineMilliseconds != 45_000 ||
    !sidecarImported.Tasks[1].Optional ||
    !sidecarImported.Tasks[1].FailureCondition ||
    interchange.Inventory.Any(item => !item.Compatible))
    throw new InvalidOperationException(
        "Pluggable sidecar import/export failed.");

var publication = MapPublicationService.Publish(
    missionMap,
    Path.Combine(root, "publication"),
    "武工队趁夜潜入哨所，完成侦察后从河岸撤离。",
    MapQualityAnalyzer.Analyze(missionMap));
if (!File.Exists(publication.ReadmePath) ||
    !File.Exists(publication.ThumbnailPath) ||
    !File.Exists(publication.StoryPath) ||
    !File.Exists(publication.ValidationPath))
    throw new InvalidOperationException(
        "One-click map publication generation failed.");
Console.WriteLine(
    "MapEditor region, semantic collaboration, plugins and publishing passed.");

var shippedSidecarDirectory = Path.Combine(
    Environment.CurrentDirectory, "Mod", "Missions");
if (Directory.Exists(shippedSidecarDirectory))
{
    foreach (var shippedSidecar in Directory.GetFiles(
                 shippedSidecarDirectory,
                 "*.m1937mission.json"))
    {
        var shippedDocument = interchange
            .FindForImport(shippedSidecar)
            .Import(
                shippedSidecar,
                new MapInterchangeContext(
                    shippedSidecar, null,
                    new Dictionary<string, string>()));
        if (shippedDocument.Tasks.Count == 0 ||
            shippedDocument.Tasks.All(task =>
                !task.TargetDatabaseId.HasValue &&
                !task.SubjectDatabaseId.HasValue &&
                !task.RegionX.HasValue))
            throw new InvalidOperationException(
                $"Shipped sidecar import lost objective bindings: " +
                shippedSidecar);
        if (MissionGraphService.Build(shippedDocument).Errors.Any(error =>
                error.Contains("引用不存在的对象", StringComparison.Ordinal)))
            throw new InvalidOperationException(
                $"Shipped sidecar database binding was treated as a " +
                $"missing map object: {shippedSidecar}");
        var roundTripPath = Path.Combine(
            root,
            Path.GetFileName(shippedSidecar));
        interchange.FindForExport(roundTripPath).Export(
            shippedDocument,
            roundTripPath,
            new MapInterchangeContext(
                shippedSidecar, null,
                new Dictionary<string, string>()));
        using var roundTripJson = JsonDocument.Parse(
            File.ReadAllText(roundTripPath));
        if (roundTripJson.RootElement
                .GetProperty("api_version").GetUInt32() != 0x00010000 ||
            roundTripJson.RootElement
                .GetProperty("objectives").GetArrayLength() !=
            shippedDocument.Tasks.Count)
            throw new InvalidOperationException(
                $"Shipped sidecar schema round-trip failed: {shippedSidecar}");
    }
    Console.WriteLine(
        "Shipped .m1937mission.json files passed editor round-trip.");
}

var assetCatalogForTest = Path.Combine(
    Environment.CurrentDirectory,
    "MapEditor", "Assets", "Original", "catalog.json");
if (File.Exists(assetCatalogForTest))
{
    var metadata = AssetMetadataService.GenerateFromAssetCatalog(
        assetCatalogForTest);
    var metadataPath = Path.Combine(root, "asset-metadata.json");
    AssetMetadataService.Save(metadata, metadataPath);
    var loadedMetadata = AssetMetadataService.Load(metadataPath);
    if (AssetMetadataService.CoverageErrors(
            assetCatalogForTest, loadedMetadata).Count != 0 ||
        loadedMetadata.Assets.Count != 1037 ||
        loadedMetadata.Assets.Any(item =>
            item.FootprintWidth <= 0 ||
            item.FootprintHeight <= 0 ||
            string.IsNullOrWhiteSpace(item.PreferredLayer)))
        throw new InvalidOperationException(
            "Per-asset placement metadata coverage failed.");
    Console.WriteLine(
        "MapEditor 1,037-asset metadata coverage passed.");
}

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

var nativePackDocument = MapDocument.Create("Synthetic native package", 16, 12);
nativePackDocument.CellWidth = 32;
nativePackDocument.CellHeight = 16;
nativePackDocument.Metadata["pack_id"] = "tests.synthetic";
nativePackDocument.Metadata["level_id"] = "training";
nativePackDocument.Objects.Add(new MapObject
{
    Id = "player-1",
    Name = "Test player",
    Kind = "character",
    Category = "角色",
    Faction = "player",
    X = 1,
    Y = 1
});
nativePackDocument.Objects.Add(new MapObject
{
    Id = "enemy-20",
    Name = "Patrol guard",
    Kind = "character",
    Category = "角色",
    Faction = "enemy",
    X = 11,
    Y = 4,
    PatrolEnabled = true,
    PatrolWaypoints =
    [
        new MapWaypoint { X = 11, Y = 4 },
        new MapWaypoint { X = 13, Y = 6 }
    ]
});
nativePackDocument.Objects.Add(new MapObject
{
    Id = "door-70",
    Name = "Training gate",
    Kind = "door",
    Category = "门",
    X = 8,
    Y = 6,
    Properties = new Dictionary<string, string>
    {
        ["starts_open"] = "false",
        ["locked_open"] = "false"
    }
});
nativePackDocument.Objects.Add(new MapObject
{
    Id = "pickup-80",
    Name = "Smoke lure",
    Kind = "pickup",
    Category = "物品",
    X = 3,
    Y = 2,
    Properties = new Dictionary<string, string>
    {
        ["item_id"] = "83",
        ["quantity"] = "2",
        ["quantity_mode"] = "0",
        ["original_inventory_kind"] = "backpack",
        ["item_name"] = "Smoke lure"
    }
});
nativePackDocument.Layer(EditorLayerKind.MovementObstacle).Cells[
    nativePackDocument.Index(8, 6)] = 70;
nativePackDocument.Layer(EditorLayerKind.LineOfSightObstacle).Cells[
    nativePackDocument.Index(8, 6)] = 70;
nativePackDocument.Tasks[0].Title = "Reach the exit";
nativePackDocument.Tasks[0].Trigger = "trigger_activated";
nativePackDocument.Tasks[0].RegionX = 14;
nativePackDocument.Tasks[0].RegionY = 10;
nativePackDocument.Tasks.Add(new MissionTask
{
    Id = "player-lost",
    Title = "Keep the scout alive",
    Trigger = "required_character_lost",
    FailureCondition = true,
    FailureReason = "The scout was lost."
});
var nativePackPath = Path.Combine(root, "mapeditor-synthetic.m1937pack");
var nativePackResult = NativeContentPackExporter.Export(
    nativePackDocument,
    nativePackPath);
var nativePackValidation = M1937Pack.Validate(nativePackPath);
if (!File.Exists(nativePackPath) ||
    nativePackResult.ObjectCount != 4 ||
    nativePackResult.ObjectiveCount != 1 ||
    nativePackValidation.Manifest.LevelEntries.Count != 1 ||
    !nativePackValidation.Manifest.Capabilities.Contains("doors") ||
    !nativePackValidation.Manifest.Capabilities.Contains("pickups") ||
    nativePackValidation.Manifest.Files.All(file =>
        !file.Path.EndsWith("navigation.bin", StringComparison.Ordinal)))
{
    throw new InvalidOperationException(
        "MapEditor native .m1937pack export test failed.");
}
Console.WriteLine("MapEditor native .m1937pack export passed.");

static void RunNativeVwfTests(
    string vwfDirectory,
    string testRoot)
{
    var roundTripRoot = Path.Combine(testRoot, "native-vwf-roundtrip");
    Directory.CreateDirectory(roundTripRoot);
    var levels = Enumerable.Range(0, 12)
        .Select(index => Path.Combine(
            vwfDirectory, $"1937m{index:D3}.vwf"))
        .ToArray();
    if (levels.Any(path => !File.Exists(path)))
    {
        throw new InvalidOperationException(
            "Native VWF matrix requires 1937m000.vwf through " +
            "1937m011.vwf.");
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
        "Native VWF no-change round-trip passed for m000-m011.");

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
