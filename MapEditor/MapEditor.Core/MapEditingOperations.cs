namespace Mission1937.MapEditor.Core;

public enum MapAlignment
{
    Left,
    HorizontalCenter,
    Right,
    Top,
    VerticalCenter,
    Bottom
}

public enum MapDistribution
{
    Horizontal,
    Vertical
}

public sealed record MapObjectFilter(
    string Search = "",
    string Scene = "",
    string Asset = "",
    string Faction = "",
    string Category = "");

public static class MapObjectEditing
{
    public static IReadOnlyList<MapObject> SelectRectangle(
        MapDocument document,
        int left,
        int top,
        int right,
        int bottom,
        MapObjectFilter? filter = null)
    {
        ArgumentNullException.ThrowIfNull(document);
        var minimumX = Math.Min(left, right);
        var maximumX = Math.Max(left, right);
        var minimumY = Math.Min(top, bottom);
        var maximumY = Math.Max(top, bottom);
        return Filter(document.Objects, filter ?? new MapObjectFilter())
            .Where(item =>
                item.X >= minimumX && item.X <= maximumX &&
                item.Y >= minimumY && item.Y <= maximumY)
            .ToArray();
    }

    public static IReadOnlyList<MapObject> Filter(
        IEnumerable<MapObject> objects,
        MapObjectFilter filter)
    {
        ArgumentNullException.ThrowIfNull(objects);
        ArgumentNullException.ThrowIfNull(filter);
        static bool Contains(string value, string term) =>
            string.IsNullOrWhiteSpace(term) ||
            value.Contains(
                term.Trim(), StringComparison.CurrentCultureIgnoreCase);

        return objects.Where(item =>
        {
            var scene = item.Id.StartsWith(
                "scene-", StringComparison.OrdinalIgnoreCase)
                ? item.Id[6..]
                : item.Properties.GetValueOrDefault("scene_index", "");
            var asset =
                item.Properties.GetValueOrDefault("asset_id", "") + " " +
                item.Properties.GetValueOrDefault("resource_name", "") + " " +
                item.AssetPath;
            var searchable =
                $"{item.Id} {item.Name} {item.Kind} {item.Category}";
            return Contains(searchable, filter.Search) &&
                   Contains(scene, filter.Scene) &&
                   Contains(asset, filter.Asset) &&
                   Contains(item.Faction, filter.Faction) &&
                   Contains(item.Category, filter.Category);
        }).ToArray();
    }

    public static void Align(
        IReadOnlyCollection<MapObject> selection,
        MapAlignment alignment)
    {
        if (selection.Count == 0)
            return;
        var minimumX = selection.Min(item => item.X);
        var maximumX = selection.Max(item => item.X);
        var minimumY = selection.Min(item => item.Y);
        var maximumY = selection.Max(item => item.Y);
        var centerX = (minimumX + maximumX) / 2;
        var centerY = (minimumY + maximumY) / 2;
        foreach (var item in selection)
        {
            switch (alignment)
            {
            case MapAlignment.Left:
                item.X = minimumX;
                break;
            case MapAlignment.HorizontalCenter:
                item.X = centerX;
                break;
            case MapAlignment.Right:
                item.X = maximumX;
                break;
            case MapAlignment.Top:
                item.Y = minimumY;
                break;
            case MapAlignment.VerticalCenter:
                item.Y = centerY;
                break;
            case MapAlignment.Bottom:
                item.Y = maximumY;
                break;
            }
        }
    }

    public static void Distribute(
        IReadOnlyCollection<MapObject> selection,
        MapDistribution distribution)
    {
        if (selection.Count < 3)
            return;
        var ordered = distribution == MapDistribution.Horizontal
            ? selection.OrderBy(item => item.X).ThenBy(item => item.Id).ToArray()
            : selection.OrderBy(item => item.Y).ThenBy(item => item.Id).ToArray();
        var start = distribution == MapDistribution.Horizontal
            ? ordered[0].X : ordered[0].Y;
        var end = distribution == MapDistribution.Horizontal
            ? ordered[^1].X : ordered[^1].Y;
        for (var index = 1; index < ordered.Length - 1; ++index)
        {
            var value = (int)Math.Round(
                start + (end - start) * index /
                (double)(ordered.Length - 1),
                MidpointRounding.AwayFromZero);
            if (distribution == MapDistribution.Horizontal)
                ordered[index].X = value;
            else
                ordered[index].Y = value;
        }
    }

    public static IReadOnlyList<MapObject> Duplicate(
        MapDocument document,
        IReadOnlyCollection<MapObject> selection,
        int offsetX = 1,
        int offsetY = 1)
    {
        ArgumentNullException.ThrowIfNull(document);
        var clones = new List<MapObject>(selection.Count);
        foreach (var source in selection)
        {
            var wrapper = new MapDocument
            {
                Name = "object-clone",
                Width = document.Width,
                Height = document.Height,
                CellSize = document.CellSize,
                CellWidth = document.CellWidth,
                CellHeight = document.CellHeight,
                Layers = document.Layers.Select(layer => new EditorLayer
                {
                    Name = layer.Name,
                    Kind = layer.Kind,
                    Cells = new int[document.Width * document.Height]
                }).ToList(),
                Objects = [source]
            };
            var clone = MapDocumentSerializer.Clone(wrapper).Objects[0];
            clone.Id = Guid.NewGuid().ToString("N");
            clone.Name = source.Name + " 副本";
            clone.X = Math.Clamp(source.X + offsetX, 0, document.Width - 1);
            clone.Y = Math.Clamp(source.Y + offsetY, 0, document.Height - 1);
            foreach (var point in clone.PatrolWaypoints)
            {
                point.X = Math.Clamp(point.X + offsetX, 0, document.Width - 1);
                point.Y = Math.Clamp(point.Y + offsetY, 0, document.Height - 1);
            }
            document.Objects.Add(clone);
            clones.Add(clone);
        }
        return clones;
    }

    public static void SetBatchProperties(
        IEnumerable<MapObject> selection,
        string? faction = null,
        string? category = null,
        int? direction = null,
        IReadOnlyDictionary<string, string>? properties = null)
    {
        foreach (var item in selection)
        {
            if (faction is not null)
                item.Faction = faction;
            if (category is not null)
                item.Category = category;
            if (direction.HasValue)
                item.Direction = direction.Value;
            if (properties is null)
                continue;
            foreach (var property in properties)
                item.Properties[property.Key] = property.Value;
        }
    }
}

public static class MapLayerPainter
{
    public static int PaintBrush(
        MapDocument document,
        EditorLayerKind kind,
        int centerX,
        int centerY,
        int radius,
        int value)
    {
        var layer = WritableLayer(document, kind);
        var changed = 0;
        radius = Math.Clamp(radius, 0, 64);
        for (var y = centerY - radius; y <= centerY + radius; ++y)
        for (var x = centerX - radius; x <= centerX + radius; ++x)
        {
            if (!InBounds(document, x, y))
                continue;
            if ((x - centerX) * (x - centerX) +
                (y - centerY) * (y - centerY) >
                radius * radius + radius)
                continue;
            changed += SetCell(document, layer, x, y, value);
        }
        return changed;
    }

    public static int PaintRectangle(
        MapDocument document,
        EditorLayerKind kind,
        int x1,
        int y1,
        int x2,
        int y2,
        int value,
        bool outline = false)
    {
        var layer = WritableLayer(document, kind);
        var left = Math.Clamp(Math.Min(x1, x2), 0, document.Width - 1);
        var right = Math.Clamp(Math.Max(x1, x2), 0, document.Width - 1);
        var top = Math.Clamp(Math.Min(y1, y2), 0, document.Height - 1);
        var bottom = Math.Clamp(Math.Max(y1, y2), 0, document.Height - 1);
        var changed = 0;
        for (var y = top; y <= bottom; ++y)
        for (var x = left; x <= right; ++x)
        {
            if (outline &&
                x != left && x != right && y != top && y != bottom)
                continue;
            changed += SetCell(document, layer, x, y, value);
        }
        return changed;
    }

    public static int FloodFill(
        MapDocument document,
        EditorLayerKind kind,
        int startX,
        int startY,
        int replacement)
    {
        var layer = WritableLayer(document, kind);
        if (!InBounds(document, startX, startY))
            return 0;
        var target = layer.Cells[document.Index(startX, startY)];
        if (target == replacement)
            return 0;
        var pending = new Queue<(int X, int Y)>();
        pending.Enqueue((startX, startY));
        var changed = 0;
        while (pending.TryDequeue(out var cell))
        {
            if (!InBounds(document, cell.X, cell.Y))
                continue;
            var index = document.Index(cell.X, cell.Y);
            if (layer.Cells[index] != target)
                continue;
            layer.Cells[index] = replacement;
            ++changed;
            pending.Enqueue((cell.X - 1, cell.Y));
            pending.Enqueue((cell.X + 1, cell.Y));
            pending.Enqueue((cell.X, cell.Y - 1));
            pending.Enqueue((cell.X, cell.Y + 1));
        }
        return changed;
    }

    private static EditorLayer WritableLayer(
        MapDocument document,
        EditorLayerKind kind)
    {
        ArgumentNullException.ThrowIfNull(document);
        var layer = document.Layer(kind);
        if (layer.Locked)
            throw new InvalidOperationException($"图层“{layer.Name}”已锁定。");
        return layer;
    }

    private static int SetCell(
        MapDocument document,
        EditorLayer layer,
        int x,
        int y,
        int value)
    {
        var index = document.Index(x, y);
        if (layer.Cells[index] == value)
            return 0;
        layer.Cells[index] = value;
        return 1;
    }

    private static bool InBounds(MapDocument document, int x, int y) =>
        x >= 0 && y >= 0 && x < document.Width && y < document.Height;
}

public sealed record PatrolEditResult(
    int Count,
    int Capacity,
    int Remaining);

public static class PatrolRouteEditing
{
    public static int Capacity(MapObject item)
    {
        if (item.Properties.TryGetValue(
                "patrol_capacity", out var raw) &&
            int.TryParse(raw, out var value))
            return Math.Clamp(value, 0, 256);
        return Math.Max(16, item.PatrolWaypoints.Count);
    }

    public static PatrolEditResult Insert(
        MapDocument document,
        MapObject item,
        int index,
        int x,
        int y)
    {
        ValidateCell(document, x, y);
        var capacity = Capacity(item);
        if (item.PatrolWaypoints.Count >= capacity)
            throw new InvalidOperationException(
                $"路线容量已满（{capacity} 个点）。");
        index = Math.Clamp(index, 0, item.PatrolWaypoints.Count);
        item.PatrolWaypoints.Insert(index, new MapWaypoint { X = x, Y = y });
        item.PatrolEnabled = item.PatrolWaypoints.Count > 0;
        return Result(item, capacity);
    }

    public static PatrolEditResult Move(
        MapDocument document,
        MapObject item,
        int index,
        int x,
        int y)
    {
        ValidateCell(document, x, y);
        if (index < 0 || index >= item.PatrolWaypoints.Count)
            throw new ArgumentOutOfRangeException(nameof(index));
        item.PatrolWaypoints[index].X = x;
        item.PatrolWaypoints[index].Y = y;
        return Result(item, Capacity(item));
    }

    public static PatrolEditResult Delete(MapObject item, int index)
    {
        if (index < 0 || index >= item.PatrolWaypoints.Count)
            throw new ArgumentOutOfRangeException(nameof(index));
        item.PatrolWaypoints.RemoveAt(index);
        if (item.PatrolWaypoints.Count == 0)
        {
            item.PatrolCurrentWaypointIndex = 0;
            item.PatrolEnabled = false;
        }
        else
        {
            item.PatrolCurrentWaypointIndex = Math.Clamp(
                item.PatrolCurrentWaypointIndex,
                0, item.PatrolWaypoints.Count - 1);
        }
        return Result(item, Capacity(item));
    }

    private static PatrolEditResult Result(MapObject item, int capacity) =>
        new(item.PatrolWaypoints.Count, capacity,
            Math.Max(0, capacity - item.PatrolWaypoints.Count));

    private static void ValidateCell(
        MapDocument document, int x, int y)
    {
        if (x < 0 || y < 0 || x >= document.Width || y >= document.Height)
            throw new ArgumentOutOfRangeException(nameof(x), "路线点位于地图外。");
    }
}

public static class LayerViewService
{
    public static IReadOnlyList<LayerViewPreset> BuiltInPresets() =>
    [
        new()
        {
            Name = "美术预览",
            Visibility = Enum.GetValues<EditorLayerKind>()
                .ToDictionary(kind => kind, kind => kind == EditorLayerKind.Terrain)
        },
        new()
        {
            Name = "通行校验",
            Visibility = Enum.GetValues<EditorLayerKind>().ToDictionary(
                kind => kind,
                kind => kind is EditorLayerKind.Terrain or
                    EditorLayerKind.MovementObstacle or
                    EditorLayerKind.ManualMovementCorrection)
        },
        new()
        {
            Name = "任务与视线",
            Visibility = Enum.GetValues<EditorLayerKind>().ToDictionary(
                kind => kind,
                kind => kind is EditorLayerKind.Terrain or
                    EditorLayerKind.LineOfSightObstacle or
                    EditorLayerKind.Event)
        }
    ];

    public static void Apply(
        MapDocument document,
        LayerViewPreset preset)
    {
        foreach (var layer in document.Layers)
        {
            if (preset.Visibility.TryGetValue(layer.Kind, out var visible))
                layer.Visible = visible;
            if (preset.Opacity.TryGetValue(layer.Kind, out var opacity))
                layer.Opacity = Math.Clamp(opacity, 0, 1);
            layer.Solo = false;
        }
    }

    public static void Solo(MapDocument document, EditorLayerKind kind)
    {
        foreach (var layer in document.Layers)
        {
            layer.Solo = layer.Kind == kind;
            layer.Visible = layer.Kind == kind;
        }
    }
}
