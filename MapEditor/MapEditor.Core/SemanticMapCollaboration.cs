using System.Text.Json;

namespace Mission1937.MapEditor.Core;

public sealed record SemanticMapChange(
    string Kind,
    string EntityId,
    string Field,
    string Before,
    string After);

public sealed record SemanticMapConflict(
    string Kind,
    string EntityId,
    string Field,
    string Base,
    string Ours,
    string Theirs);

public sealed record SemanticMergeResult(
    MapDocument Document,
    IReadOnlyList<SemanticMapConflict> Conflicts);

public static class SemanticMapCollaboration
{
    public static IReadOnlyList<SemanticMapChange> Diff(
        MapDocument before,
        MapDocument after)
    {
        var changes = new List<SemanticMapChange>();
        CompareScalar(
            changes, "map", "document", "name",
            before.Name, after.Name);
        CompareEntities(
            changes,
            "object",
            before.Objects.ToDictionary(item => item.Id),
            after.Objects.ToDictionary(item => item.Id));
        CompareEntities(
            changes,
            "task",
            before.Tasks.ToDictionary(item => item.Id),
            after.Tasks.ToDictionary(item => item.Id));
        foreach (var kind in Enum.GetValues<EditorLayerKind>())
        {
            var left = before.Layer(kind);
            var right = after.Layer(kind);
            CompareScalar(
                changes, "layer", kind.ToString(), "visibility",
                $"{left.Visible}/{left.Locked}/{left.Opacity:F3}",
                $"{right.Visible}/{right.Locked}/{right.Opacity:F3}");
            var length = Math.Min(left.Cells.Length, right.Cells.Length);
            for (var index = 0; index < length; ++index)
            {
                if (left.Cells[index] == right.Cells[index])
                    continue;
                changes.Add(new SemanticMapChange(
                    "layer-cell",
                    kind.ToString(),
                    $"{index % before.Width},{index / before.Width}",
                    left.Cells[index].ToString(),
                    right.Cells[index].ToString()));
            }
        }
        return changes;
    }

    public static SemanticMergeResult Merge(
        MapDocument @base,
        MapDocument ours,
        MapDocument theirs)
    {
        if (@base.Width != ours.Width ||
            @base.Height != ours.Height ||
            @base.Width != theirs.Width ||
            @base.Height != theirs.Height)
            throw new InvalidDataException(
                "三方语义合并要求地图尺寸一致。");
        var merged = MapDocumentSerializer.Clone(@base);
        var conflicts = new List<SemanticMapConflict>();
        merged.Name = MergeValue(
            "map", "document", "name",
            @base.Name, ours.Name, theirs.Name, conflicts);
        merged.Objects = MergeEntities(
            "object", @base.Objects, ours.Objects, theirs.Objects,
            item => item.Id, conflicts);
        merged.Tasks = MergeEntities(
            "task", @base.Tasks, ours.Tasks, theirs.Tasks,
            item => item.Id, conflicts);

        foreach (var kind in Enum.GetValues<EditorLayerKind>())
        {
            var baseLayer = @base.Layer(kind);
            var ourLayer = ours.Layer(kind);
            var theirLayer = theirs.Layer(kind);
            var output = merged.Layer(kind);
            output.Visible = MergeValue(
                "layer", kind.ToString(), "visible",
                baseLayer.Visible, ourLayer.Visible,
                theirLayer.Visible, conflicts);
            output.Locked = MergeValue(
                "layer", kind.ToString(), "locked",
                baseLayer.Locked, ourLayer.Locked,
                theirLayer.Locked, conflicts);
            output.Opacity = MergeValue(
                "layer", kind.ToString(), "opacity",
                baseLayer.Opacity, ourLayer.Opacity,
                theirLayer.Opacity, conflicts);
            for (var index = 0; index < output.Cells.Length; ++index)
            {
                output.Cells[index] = MergeValue(
                    "layer-cell",
                    kind.ToString(),
                    $"{index % merged.Width},{index / merged.Width}",
                    baseLayer.Cells[index],
                    ourLayer.Cells[index],
                    theirLayer.Cells[index],
                    conflicts);
            }
        }
        return new SemanticMergeResult(merged, conflicts);
    }

    public static void ExportDiff(
        IReadOnlyList<SemanticMapChange> changes,
        string path)
    {
        var payload = new
        {
            schema_version = 1,
            generated_utc = DateTimeOffset.UtcNow,
            changes
        };
        Directory.CreateDirectory(Path.GetDirectoryName(
            Path.GetFullPath(path))!);
        File.WriteAllText(
            path,
            JsonSerializer.Serialize(payload, new JsonSerializerOptions
            {
                WriteIndented = true,
                PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower
            }));
    }

    private static void CompareEntities<T>(
        List<SemanticMapChange> changes,
        string kind,
        IReadOnlyDictionary<string, T> before,
        IReadOnlyDictionary<string, T> after)
    {
        foreach (var id in before.Keys.Union(after.Keys).Order())
        {
            before.TryGetValue(id, out var left);
            after.TryGetValue(id, out var right);
            var leftJson = left is null ? "" : Canonical(left);
            var rightJson = right is null ? "" : Canonical(right);
            if (leftJson == rightJson)
                continue;
            changes.Add(new SemanticMapChange(
                kind, id,
                left is null ? "added" :
                right is null ? "removed" :
                "properties",
                leftJson,
                rightJson));
        }
    }

    private static List<T> MergeEntities<T>(
        string kind,
        IEnumerable<T> baseItems,
        IEnumerable<T> ourItems,
        IEnumerable<T> theirItems,
        Func<T, string> id,
        List<SemanticMapConflict> conflicts)
        where T : class
    {
        var baseMap = baseItems.ToDictionary(id);
        var ourMap = ourItems.ToDictionary(id);
        var theirMap = theirItems.ToDictionary(id);
        var output = new List<T>();
        foreach (var key in baseMap.Keys
                     .Union(ourMap.Keys)
                     .Union(theirMap.Keys)
                     .Order())
        {
            baseMap.TryGetValue(key, out var baseValue);
            ourMap.TryGetValue(key, out var ourValue);
            theirMap.TryGetValue(key, out var theirValue);
            var baseJson = baseValue is null ? "" : Canonical(baseValue);
            var ourJson = ourValue is null ? "" : Canonical(ourValue);
            var theirJson = theirValue is null ? "" : Canonical(theirValue);
            string chosen;
            if (ourJson == theirJson)
                chosen = ourJson;
            else if (ourJson == baseJson)
                chosen = theirJson;
            else if (theirJson == baseJson)
                chosen = ourJson;
            else
            {
                conflicts.Add(new SemanticMapConflict(
                    kind, key, "entity",
                    baseJson, ourJson, theirJson));
                chosen = ourJson;
            }
            if (chosen.Length > 0)
                output.Add(JsonSerializer.Deserialize<T>(chosen)!);
        }
        return output;
    }

    private static T MergeValue<T>(
        string kind,
        string id,
        string field,
        T baseValue,
        T ourValue,
        T theirValue,
        List<SemanticMapConflict> conflicts)
    {
        if (EqualityComparer<T>.Default.Equals(ourValue, theirValue))
            return ourValue;
        if (EqualityComparer<T>.Default.Equals(ourValue, baseValue))
            return theirValue;
        if (EqualityComparer<T>.Default.Equals(theirValue, baseValue))
            return ourValue;
        conflicts.Add(new SemanticMapConflict(
            kind, id, field,
            $"{baseValue}", $"{ourValue}", $"{theirValue}"));
        return ourValue;
    }

    private static void CompareScalar(
        List<SemanticMapChange> changes,
        string kind,
        string id,
        string field,
        string before,
        string after)
    {
        if (before != after)
            changes.Add(new SemanticMapChange(
                kind, id, field, before, after));
    }

    private static string Canonical<T>(T value) =>
        JsonSerializer.Serialize(value);
}
