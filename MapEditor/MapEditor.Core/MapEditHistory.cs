namespace Mission1937.MapEditor.Core;

public sealed class MapEditHistory
{
    private readonly int capacity;
    private readonly List<Entry> entries = [];
    private int position;

    public MapEditHistory(int capacity = 100)
    {
        if (capacity <= 0)
            throw new ArgumentOutOfRangeException(nameof(capacity));
        this.capacity = capacity;
    }

    public bool CanUndo => position > 0;
    public bool CanRedo => position < entries.Count;
    public string? UndoDescription =>
        CanUndo ? entries[position - 1].Description : null;
    public string? RedoDescription =>
        CanRedo ? entries[position].Description : null;

    public void Clear()
    {
        entries.Clear();
        position = 0;
    }

    public void Commit(
        string description,
        MapDocument before,
        MapDocument after,
        string? coalesceKey = null,
        TimeSpan? coalesceWindow = null)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(description);
        ArgumentNullException.ThrowIfNull(before);
        ArgumentNullException.ThrowIfNull(after);
        if (Equivalent(before, after))
            return;

        if (position < entries.Count)
            entries.RemoveRange(position, entries.Count - position);
        var now = DateTimeOffset.UtcNow;
        var window = coalesceWindow ?? TimeSpan.FromMilliseconds(700);
        if (!string.IsNullOrWhiteSpace(coalesceKey) &&
            position > 0 &&
            position == entries.Count)
        {
            var previous = entries[position - 1];
            if (previous.CoalesceKey == coalesceKey &&
                now - previous.Timestamp <= window)
            {
                entries[position - 1] = previous with
                {
                    After = MapDocumentSerializer.Clone(after),
                    Timestamp = now
                };
                return;
            }
        }

        entries.Add(new Entry(
            description,
            MapDocumentSerializer.Clone(before),
            MapDocumentSerializer.Clone(after),
            coalesceKey,
            now));
        position = entries.Count;
        if (entries.Count <= capacity)
            return;
        entries.RemoveAt(0);
        position--;
    }

    public MapDocument Undo()
    {
        if (!CanUndo)
            throw new InvalidOperationException("没有可撤销的操作。");
        position--;
        return MapDocumentSerializer.Clone(entries[position].Before);
    }

    public MapDocument Redo()
    {
        if (!CanRedo)
            throw new InvalidOperationException("没有可重做的操作。");
        var result = MapDocumentSerializer.Clone(entries[position].After);
        position++;
        return result;
    }

    private static bool Equivalent(
        MapDocument left,
        MapDocument right)
    {
        if (left.Name != right.Name ||
            left.Width != right.Width ||
            left.Height != right.Height ||
            left.BackgroundAsset != right.BackgroundAsset ||
            left.Objects.Count != right.Objects.Count ||
            left.Tasks.Count != right.Tasks.Count ||
            left.Layers.Count != right.Layers.Count)
            return false;
        for (var index = 0; index < left.Layers.Count; ++index)
        {
            var first = left.Layers[index];
            var second = right.Layers[index];
            if (first.Kind != second.Kind ||
                first.Visible != second.Visible ||
                !first.Cells.AsSpan().SequenceEqual(second.Cells))
                return false;
        }
        return System.Text.Json.JsonSerializer.Serialize(left) ==
            System.Text.Json.JsonSerializer.Serialize(right);
    }

    private sealed record Entry(
        string Description,
        MapDocument Before,
        MapDocument After,
        string? CoalesceKey,
        DateTimeOffset Timestamp);
}
