using System.Windows;
using System.Windows.Input;
using System.Windows.Media;
using Mission1937.MapEditor.Core;

namespace Mission1937.MapEditor.App;

public sealed class CellEventArgs(int x, int y, bool erase) : EventArgs
{
    public int X { get; } = x;
    public int Y { get; } = y;
    public bool Erase { get; } = erase;
}

public sealed class MapObjectEventArgs(MapObject mapObject) : EventArgs
{
    public MapObject MapObject { get; } = mapObject;
}

public sealed class MapCanvas : FrameworkElement
{
    private MapDocument? document;
    private double zoom = 1;
    private bool dragging;
    private bool eraseDrag;

    public event EventHandler<CellEventArgs>? CellHovered;
    public event EventHandler<CellEventArgs>? CellInvoked;
    public event EventHandler<MapObjectEventArgs>? ObjectSelected;

    public MapDocument? Document
    {
        get => document;
        set
        {
            document = value;
            UpdateExtent();
            InvalidateVisual();
        }
    }

    public double Zoom
    {
        get => zoom;
        set
        {
            zoom = Math.Clamp(value, 0.25, 3);
            UpdateExtent();
            InvalidateVisual();
        }
    }

    public void Refresh() => InvalidateVisual();

    protected override void OnRender(DrawingContext drawing)
    {
        base.OnRender(drawing);
        drawing.DrawRectangle(new SolidColorBrush(Color.FromRgb(18, 23, 29)), null,
            new Rect(0, 0, ActualWidth, ActualHeight));
        if (document is null) return;

        var cell = document.CellSize * zoom;
        DrawTerrain(drawing, document.Layer(EditorLayerKind.Terrain), cell);
        DrawSemantic(drawing, EditorLayerKind.LineOfSightObstacle,
            Color.FromArgb(85, 76, 175, 80), cell);
        DrawSemantic(drawing, EditorLayerKind.MovementObstacle,
            Color.FromArgb(100, 211, 55, 48), cell);
        DrawSemantic(drawing, EditorLayerKind.Event,
            Color.FromArgb(100, 54, 142, 219), cell);
        DrawSemantic(drawing, EditorLayerKind.ManualMovementCorrection,
            Color.FromArgb(105, 183, 106, 219), cell);

        if (zoom >= 0.5)
        {
            var pen = new Pen(new SolidColorBrush(Color.FromArgb(45, 220, 225, 230)), 1);
            for (var x = 0; x <= document.Width; x++)
                drawing.DrawLine(pen, new Point(x * cell, 0), new Point(x * cell, document.Height * cell));
            for (var y = 0; y <= document.Height; y++)
                drawing.DrawLine(pen, new Point(0, y * cell), new Point(document.Width * cell, y * cell));
        }

        foreach (var item in document.Objects)
        {
            var color = item.Faction == "player"
                ? Color.FromRgb(66, 142, 230)
                : item.Kind == "door"
                    ? Color.FromRgb(217, 148, 54)
                    : Color.FromRgb(205, 66, 60);
            var rect = new Rect(item.X * cell + 2, item.Y * cell + 2,
                Math.Max(5, cell - 4), Math.Max(5, cell - 4));
            drawing.DrawRectangle(new SolidColorBrush(color),
                new Pen(Brushes.White, 1), rect);
            if (zoom >= 0.75)
            {
                var text = new FormattedText(item.Name,
                    System.Globalization.CultureInfo.CurrentUICulture,
                    FlowDirection.LeftToRight,
                    new Typeface("Microsoft YaHei UI"),
                    Math.Max(9, 10 * zoom), Brushes.White, VisualTreeHelper.GetDpi(this).PixelsPerDip);
                drawing.DrawText(text, new Point(rect.Right + 3, rect.Top));
            }
        }
    }

    protected override void OnMouseMove(MouseEventArgs e)
    {
        base.OnMouseMove(e);
        if (!TryCell(e.GetPosition(this), out var x, out var y)) return;
        CellHovered?.Invoke(this, new CellEventArgs(x, y, false));
        if (dragging)
            CellInvoked?.Invoke(this, new CellEventArgs(x, y, eraseDrag));
    }

    protected override void OnMouseDown(MouseButtonEventArgs e)
    {
        base.OnMouseDown(e);
        Focus();
        if (!TryCell(e.GetPosition(this), out var x, out var y)) return;
        if (e.ChangedButton == MouseButton.Left)
        {
            var hit = document?.Objects.LastOrDefault(item => item.X == x && item.Y == y);
            if (hit is not null && Keyboard.Modifiers.HasFlag(ModifierKeys.Shift))
            {
                ObjectSelected?.Invoke(this, new MapObjectEventArgs(hit));
                return;
            }
        }
        dragging = true;
        eraseDrag = e.ChangedButton == MouseButton.Right;
        CaptureMouse();
        CellInvoked?.Invoke(this, new CellEventArgs(x, y, eraseDrag));
    }

    protected override void OnMouseUp(MouseButtonEventArgs e)
    {
        base.OnMouseUp(e);
        dragging = false;
        ReleaseMouseCapture();
    }

    private void DrawTerrain(DrawingContext drawing, EditorLayer layer, double cell)
    {
        if (!layer.Visible || document is null) return;
        for (var y = 0; y < document.Height; y++)
        for (var x = 0; x < document.Width; x++)
        {
            var value = layer.Cells[y * document.Width + x];
            if (value == 0) continue;
            var hash = unchecked((uint)value * 2654435761u);
            var color = Color.FromRgb(
                (byte)(65 + (hash & 63)),
                (byte)(75 + ((hash >> 8) & 63)),
                (byte)(55 + ((hash >> 16) & 63)));
            drawing.DrawRectangle(new SolidColorBrush(color), null,
                new Rect(x * cell, y * cell, cell + 0.5, cell + 0.5));
        }
    }

    private void DrawSemantic(
        DrawingContext drawing, EditorLayerKind kind, Color color, double cell)
    {
        if (document is null) return;
        var layer = document.Layer(kind);
        if (!layer.Visible) return;
        var brush = new SolidColorBrush(color);
        for (var y = 0; y < document.Height; y++)
        for (var x = 0; x < document.Width; x++)
        {
            if (layer.Cells[y * document.Width + x] == 0) continue;
            drawing.DrawRectangle(brush, null,
                new Rect(x * cell, y * cell, cell + 0.5, cell + 0.5));
        }
    }

    private bool TryCell(Point point, out int x, out int y)
    {
        x = y = -1;
        if (document is null) return false;
        var size = document.CellSize * zoom;
        x = (int)(point.X / size);
        y = (int)(point.Y / size);
        return x >= 0 && x < document.Width && y >= 0 && y < document.Height;
    }

    private void UpdateExtent()
    {
        if (document is null)
        {
            Width = Height = 1;
            return;
        }
        Width = document.Width * document.CellSize * zoom;
        Height = document.Height * document.CellSize * zoom;
    }
}
