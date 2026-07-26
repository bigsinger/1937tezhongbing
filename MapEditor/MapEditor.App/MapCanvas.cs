using System.Globalization;
using System.IO;
using System.Windows;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
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
    private readonly Dictionary<string, BitmapSource?> imageCache =
        new(StringComparer.OrdinalIgnoreCase);
    private MapDocument? document;
    private string? assetRoot;
    private string? selectedObjectId;
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
            selectedObjectId = null;
            UpdateExtent();
            InvalidateVisual();
        }
    }

    public string? AssetRoot
    {
        get => assetRoot;
        set
        {
            assetRoot = value;
            imageCache.Clear();
            InvalidateVisual();
        }
    }

    public string? SelectedObjectId
    {
        get => selectedObjectId;
        set
        {
            selectedObjectId = value;
            InvalidateVisual();
        }
    }

    public double Zoom
    {
        get => zoom;
        set
        {
            zoom = Math.Clamp(value, 0.1, 3);
            UpdateExtent();
            InvalidateVisual();
        }
    }

    public void Refresh() => InvalidateVisual();

    protected override void OnRender(DrawingContext drawing)
    {
        base.OnRender(drawing);
        drawing.DrawRectangle(
            new SolidColorBrush(Color.FromRgb(221, 218, 208)), null,
            new Rect(0, 0, ActualWidth, ActualHeight));
        if (document is null)
            return;

        var cellWidth = document.EffectiveCellWidth * zoom;
        var cellHeight = document.EffectiveCellHeight * zoom;
        var mapRect = new Rect(
            0, 0, document.Width * cellWidth, document.Height * cellHeight);

        var background = LoadAsset(document.BackgroundAsset);
        if (background is not null)
        {
            drawing.DrawRectangle(
                new SolidColorBrush(Color.FromRgb(58, 51, 38)), null,
                mapRect);
            drawing.DrawImage(background, mapRect);
        }
        else
        {
            DrawTerrain(drawing, document.Layer(EditorLayerKind.Terrain),
                cellWidth, cellHeight);
        }

        DrawSemantic(drawing, EditorLayerKind.LineOfSightObstacle,
            Color.FromArgb(92, 44, 125, 50), cellWidth, cellHeight);
        DrawSemantic(drawing, EditorLayerKind.MovementObstacle,
            Color.FromArgb(105, 190, 45, 38), cellWidth, cellHeight);
        DrawSemantic(drawing, EditorLayerKind.Event,
            Color.FromArgb(105, 36, 105, 176), cellWidth, cellHeight);
        DrawSemantic(drawing, EditorLayerKind.ManualMovementCorrection,
            Color.FromArgb(110, 137, 67, 170), cellWidth, cellHeight);

        if (zoom >= 0.65)
            DrawGrid(drawing, cellWidth, cellHeight);
        DrawObjects(drawing, cellWidth, cellHeight);
    }

    protected override void OnMouseMove(MouseEventArgs e)
    {
        base.OnMouseMove(e);
        if (!TryCell(e.GetPosition(this), out var x, out var y))
            return;
        CellHovered?.Invoke(this, new CellEventArgs(x, y, false));
        if (dragging)
            CellInvoked?.Invoke(this, new CellEventArgs(x, y, eraseDrag));
    }

    protected override void OnMouseDown(MouseButtonEventArgs e)
    {
        base.OnMouseDown(e);
        Focus();
        if (!TryCell(e.GetPosition(this), out var x, out var y))
            return;
        if (e.ChangedButton == MouseButton.Left)
        {
            var hit = FindObjectAt(x, y);
            if (hit is not null &&
                Keyboard.Modifiers.HasFlag(ModifierKeys.Shift))
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

    private void DrawTerrain(
        DrawingContext drawing, EditorLayer layer,
        double cellWidth, double cellHeight)
    {
        if (!layer.Visible || document is null)
            return;
        for (var y = 0; y < document.Height; y++)
            for (var x = 0; x < document.Width; x++)
            {
                var value = layer.Cells[y * document.Width + x];
                if (value == 0)
                    continue;
                var hash = unchecked((uint)value * 2654435761u);
                var color = Color.FromRgb(
                    (byte)(88 + (hash & 47)),
                    (byte)(101 + ((hash >> 8) & 47)),
                    (byte)(72 + ((hash >> 16) & 47)));
                drawing.DrawRectangle(
                    new SolidColorBrush(color), null,
                    new Rect(
                        x * cellWidth, y * cellHeight,
                        cellWidth + 0.5, cellHeight + 0.5));
            }
    }

    private void DrawSemantic(
        DrawingContext drawing, EditorLayerKind kind, Color color,
        double cellWidth, double cellHeight)
    {
        if (document is null)
            return;
        var layer = document.Layer(kind);
        if (!layer.Visible)
            return;
        var brush = new SolidColorBrush(color);
        for (var y = 0; y < document.Height; y++)
            for (var x = 0; x < document.Width; x++)
            {
                if (layer.Cells[y * document.Width + x] == 0)
                    continue;
                drawing.DrawRectangle(
                    brush, null,
                    new Rect(
                        x * cellWidth, y * cellHeight,
                        cellWidth + 0.5, cellHeight + 0.5));
            }
    }

    private void DrawGrid(
        DrawingContext drawing, double cellWidth, double cellHeight)
    {
        if (document is null)
            return;
        var pen = new Pen(
            new SolidColorBrush(Color.FromArgb(58, 30, 33, 36)), 0.75);
        for (var x = 0; x <= document.Width; x++)
            drawing.DrawLine(
                pen, new Point(x * cellWidth, 0),
                new Point(x * cellWidth, document.Height * cellHeight));
        for (var y = 0; y <= document.Height; y++)
            drawing.DrawLine(
                pen, new Point(0, y * cellHeight),
                new Point(document.Width * cellWidth, y * cellHeight));
    }

    private void DrawObjects(
        DrawingContext drawing, double cellWidth, double cellHeight)
    {
        if (document is null)
            return;
        var visible = new Rect(0, 0, RenderSize.Width, RenderSize.Height);
        foreach (var item in document.Objects)
        {
            var anchor = ObjectAnchor(item, cellWidth, cellHeight);
            var selected = item.Id == selectedObjectId;
            var image = LoadAsset(item.AssetPath);
            Rect rect;
            if (image is not null)
            {
                var width = Math.Max(8, image.PixelWidth * zoom);
                var height = Math.Max(8, image.PixelHeight * zoom);
                rect = new Rect(
                    anchor.X - width / 2, anchor.Y - height, width, height);
                if (rect.IntersectsWith(visible))
                    drawing.DrawImage(image, rect);
            }
            else
            {
                if (zoom < 0.7 && !selected)
                {
                    if (item.Kind is "character" or "door" or "item")
                    {
                        var marker = item.Kind == "character"
                            ? Color.FromRgb(188, 45, 39)
                            : Color.FromRgb(207, 133, 29);
                        drawing.DrawEllipse(
                            new SolidColorBrush(marker), null,
                            anchor, 2.5, 2.5);
                    }
                    continue;
                }
                rect = new Rect(
                    anchor.X - Math.Max(4, cellWidth * 0.3),
                    anchor.Y - Math.Max(4, cellHeight * 0.65),
                    Math.Max(8, cellWidth * 0.6),
                    Math.Max(8, cellHeight * 0.65));
                if (!rect.IntersectsWith(visible))
                    continue;
                var color = item.Faction == "player"
                    ? Color.FromRgb(42, 111, 181)
                    : item.Kind == "door"
                        ? Color.FromRgb(176, 111, 34)
                        : Color.FromRgb(165, 48, 42);
                drawing.DrawRectangle(
                    new SolidColorBrush(color), new Pen(Brushes.White, 1), rect);
            }

            if (selected)
            {
                var outline = rect;
                outline.Inflate(3, 3);
                drawing.DrawRectangle(
                    null, new Pen(new SolidColorBrush(
                        Color.FromRgb(255, 196, 42)), 2), outline);
            }
            if (selected || zoom >= 1.2)
                DrawLabel(drawing, item.Name, rect);
        }
    }

    private void DrawLabel(DrawingContext drawing, string text, Rect rect)
    {
        var formatted = new FormattedText(
            text, CultureInfo.CurrentUICulture, FlowDirection.LeftToRight,
            new Typeface("Microsoft YaHei UI"),
            Math.Max(10, 11 * zoom),
            new SolidColorBrush(Color.FromRgb(24, 25, 27)),
            VisualTreeHelper.GetDpi(this).PixelsPerDip);
        var origin = new Point(rect.Left, rect.Bottom + 2);
        drawing.DrawRectangle(
            new SolidColorBrush(Color.FromArgb(205, 255, 252, 240)), null,
            new Rect(
                origin.X - 2, origin.Y - 1,
                formatted.Width + 4, formatted.Height + 2));
        drawing.DrawText(formatted, origin);
    }

    private Point ObjectAnchor(
        MapObject item, double cellWidth, double cellHeight)
    {
        if (item.Properties.TryGetValue("world_x", out var worldX) &&
            item.Properties.TryGetValue("world_y", out var worldY) &&
            int.TryParse(worldX, out var pixelX) &&
            int.TryParse(worldY, out var pixelY))
        {
            return new Point(pixelX * zoom, pixelY * zoom);
        }
        return new Point(
            (item.X + 0.5) * cellWidth, (item.Y + 1.0) * cellHeight);
    }

    private MapObject? FindObjectAt(int x, int y) =>
        document?.Objects.LastOrDefault(
            item => Math.Abs(item.X - x) <= 1 && Math.Abs(item.Y - y) <= 1);

    private BitmapSource? LoadAsset(string relativePath)
    {
        if (string.IsNullOrWhiteSpace(relativePath) ||
            string.IsNullOrWhiteSpace(assetRoot))
            return null;
        var fullPath = Path.GetFullPath(Path.Combine(
            assetRoot, relativePath.Replace('/', '\\')));
        if (imageCache.TryGetValue(fullPath, out var cached))
            return cached;
        if (!File.Exists(fullPath))
        {
            imageCache[fullPath] = null;
            return null;
        }
        try
        {
            var bitmap = new BitmapImage();
            bitmap.BeginInit();
            bitmap.CacheOption = BitmapCacheOption.OnLoad;
            bitmap.UriSource = new Uri(fullPath, UriKind.Absolute);
            bitmap.EndInit();
            bitmap.Freeze();
            imageCache[fullPath] = bitmap;
            return bitmap;
        }
        catch
        {
            imageCache[fullPath] = null;
            return null;
        }
    }

    private bool TryCell(Point point, out int x, out int y)
    {
        x = y = -1;
        if (document is null)
            return false;
        x = (int)(point.X / (document.EffectiveCellWidth * zoom));
        y = (int)(point.Y / (document.EffectiveCellHeight * zoom));
        return x >= 0 && x < document.Width &&
               y >= 0 && y < document.Height;
    }

    private void UpdateExtent()
    {
        if (document is null)
        {
            Width = Height = 1;
            return;
        }
        Width = document.Width * document.EffectiveCellWidth * zoom;
        Height = document.Height * document.EffectiveCellHeight * zoom;
    }
}
