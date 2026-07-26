using Mission1937.MapEditor.Core;

var root = Path.Combine(
    Path.GetTempPath(), "1937-map-editor-tests");
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
    Y = 6
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
    MapValidator.Validate(restored).Count != 0)
{
    throw new InvalidOperationException(
        "Map document round-trip test failed.");
}

Console.WriteLine("MapEditor core tests passed.");

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
    Console.WriteLine(
        $"Original VWF import passed: " +
        $"{imported.Width}x{imported.Height}, " +
        $"{imported.Objects.Count} objects, " +
        $"background={imported.BackgroundAsset}.");
}
