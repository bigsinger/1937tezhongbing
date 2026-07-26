using Mission1937.MapEditor.Core;

var root = Path.Combine(Path.GetTempPath(), "1937-map-editor-tests");
Directory.CreateDirectory(root);
var path = Path.Combine(root, "roundtrip.m37map.json");
var document = MapDocument.Create("往返测试", 16, 12);
document.Layer(EditorLayerKind.Terrain).Cells[document.Index(3, 4)] = 37;
document.Layer(EditorLayerKind.MovementObstacle).Cells[document.Index(4, 4)] = 1;
document.Objects.Add(new MapObject { Id = "enemy-1", Name = "哨兵", X = 8, Y = 6 });
document.Tasks[0].TargetObjectId = "enemy-1";
MapDocumentSerializer.Save(document, path);
var restored = MapDocumentSerializer.Load(path);

if (restored.Name != document.Name ||
    restored.Layer(EditorLayerKind.Terrain).Cells[restored.Index(3, 4)] != 37 ||
    restored.Objects.Single().Id != "enemy-1" ||
    MapValidator.Validate(restored).Count != 0)
{
    throw new InvalidOperationException("Map document round-trip test failed.");
}

Console.WriteLine("MapEditor core tests passed.");

var originalVwf = Environment.GetEnvironmentVariable("M1937_TEST_VWF");
if (!string.IsNullOrWhiteSpace(originalVwf))
{
    var imported = OriginalVwfImporter.Import(originalVwf);
    if (imported.Width <= 0 || imported.Height <= 0 ||
        imported.Layers.Count != 5 || imported.Objects.Count == 0)
    {
        throw new InvalidOperationException("Original VWF import smoke test failed.");
    }
    Console.WriteLine(
        $"Original VWF import passed: {imported.Width}x{imported.Height}, " +
        $"{imported.Objects.Count} objects.");
}
