using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Windows;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
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

public readonly record struct MapRenderStatistics(
    MapGridWindow VisibleCells,
    int DrawnObjects,
    int TotalObjects,
    long ElapsedMicroseconds);

public sealed class MapCanvas : FrameworkElement
{
    private readonly Dictionary<string, BitmapSource?> imageCache =
        new(StringComparer.OrdinalIgnoreCase);
    private readonly Dictionary<string, IReadOnlyList<MapWaypoint>>
        expandedRouteCache = new(StringComparer.Ordinal);
    private readonly DrawingVisual routeOverlay = new();
    private readonly DrawingVisual motionOverlay = new();
    private readonly DispatcherTimer motionTimer;
    private readonly Stopwatch motionClock = Stopwatch.StartNew();
    private MapDocument? document;
    private HashSet<int>? livingOccupants;
    private string? assetRoot;
    private string? selectedObjectId;
    private double zoom = 1;
    private bool dragging;
    private bool eraseDrag;
    private bool showPatrolRoutes = true;
    private bool motionPreviewEnabled = true;
    private bool showConnectivityHeatmap;
    private bool showAiRanges = true;
    private Rect visibleViewport = Rect.Empty;
    private MapReachability? reachabilityCache;
    private string? reachabilitySourceId;
    private EnemyPreviewProfile enemyPreviewProfile =
        EnemyPreviewProfile.EditorDefault;

    public MapCanvas()
    {
        AddVisualChild(routeOverlay);
        AddVisualChild(motionOverlay);
        motionTimer = new DispatcherTimer(
            TimeSpan.FromMilliseconds(80),
            DispatcherPriority.Background,
            (_, _) => DrawMotionOverlay(),
            Dispatcher);
        motionTimer.Stop();
        Loaded += (_, _) => UpdateMotionTimer();
        Unloaded += (_, _) => motionTimer.Stop();
        IsVisibleChanged += (_, _) => UpdateMotionTimer();
    }

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
            expandedRouteCache.Clear();
            livingOccupants = null;
            ClearAnalysisCache();
            UpdateExtent();
            InvalidateVisual();
            DrawPatrolRoutes();
            DrawMotionOverlay();
            UpdateMotionTimer();
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
            ClearAnalysisCache();
            InvalidateVisual();
            DrawPatrolRoutes();
            DrawMotionOverlay();
        }
    }

    public double Zoom
    {
        get => zoom;
        set
        {
            zoom = Math.Clamp(value, 0.1, 3);
            ClearAnalysisCache();
            UpdateExtent();
            InvalidateVisual();
            DrawPatrolRoutes();
            DrawMotionOverlay();
        }
    }

    public bool ShowPatrolRoutes
    {
        get => showPatrolRoutes;
        set
        {
            showPatrolRoutes = value;
            DrawPatrolRoutes();
            DrawMotionOverlay();
            UpdateMotionTimer();
        }
    }

    public bool MotionPreviewEnabled
    {
        get => motionPreviewEnabled;
        set
        {
            motionPreviewEnabled = value;
            DrawMotionOverlay();
            UpdateMotionTimer();
        }
    }

    public bool ObjectSelectionEnabled { get; set; } = true;

    public bool ShowConnectivityHeatmap
    {
        get => showConnectivityHeatmap;
        set
        {
            if (showConnectivityHeatmap == value)
                return;
            showConnectivityHeatmap = value;
            InvalidateVisual();
        }
    }

    public bool ShowAiRanges
    {
        get => showAiRanges;
        set
        {
            if (showAiRanges == value)
                return;
            showAiRanges = value;
            InvalidateVisual();
        }
    }

    public EnemyPreviewProfile EnemyPreviewProfile
    {
        get => enemyPreviewProfile;
        set
        {
            enemyPreviewProfile = value ??
                throw new ArgumentNullException(nameof(value));
            InvalidateVisual();
        }
    }

    public MapRenderStatistics LastRenderStatistics { get; private set; }

    public void SetVisibleViewport(
        double left,
        double top,
        double width,
        double height)
    {
        var next = width > 0 && height > 0
            ? new Rect(
                Math.Max(0, left),
                Math.Max(0, top),
                width,
                height)
            : Rect.Empty;
        if (visibleViewport == next)
            return;
        visibleViewport = next;
        InvalidateVisual();
        DrawPatrolRoutes();
        DrawMotionOverlay();
    }

    public void Refresh()
    {
        expandedRouteCache.Clear();
        livingOccupants = null;
        ClearAnalysisCache();
        InvalidateVisual();
        DrawPatrolRoutes();
        DrawMotionOverlay();
    }

    protected override int VisualChildrenCount => 2;

    protected override Visual GetVisualChild(int index) =>
        index switch
        {
            0 => routeOverlay,
            1 => motionOverlay,
            _ => throw new ArgumentOutOfRangeException(nameof(index))
        };

    protected override void OnRender(DrawingContext drawing)
    {
        var started = Stopwatch.GetTimestamp();
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
        var viewport = EffectiveVisibleViewport(mapRect);
        var visibleCells = MapSpatialAnalysis.VisibleGridWindow(
            viewport.Left,
            viewport.Top,
            viewport.Width,
            viewport.Height,
            cellWidth,
            cellHeight,
            document.Width,
            document.Height,
            marginCells: 2);

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
                cellWidth, cellHeight, visibleCells);
        }

        DrawSemantic(drawing, EditorLayerKind.LineOfSightObstacle,
            Color.FromArgb(92, 44, 125, 50), cellWidth, cellHeight,
            visibleCells);
        DrawSemantic(drawing, EditorLayerKind.MovementObstacle,
            Color.FromArgb(105, 190, 45, 38), cellWidth, cellHeight,
            visibleCells);
        DrawSemantic(drawing, EditorLayerKind.Event,
            Color.FromArgb(105, 36, 105, 176), cellWidth, cellHeight,
            visibleCells);
        DrawSemantic(drawing, EditorLayerKind.ManualMovementCorrection,
            Color.FromArgb(110, 137, 67, 170), cellWidth, cellHeight,
            visibleCells);

        DrawAnalysis(
            drawing, cellWidth, cellHeight, visibleCells, viewport);
        if (zoom >= 0.65)
            DrawGrid(drawing, cellWidth, cellHeight, visibleCells);
        var drawnObjects = DrawObjects(
            drawing, cellWidth, cellHeight, viewport);
        LastRenderStatistics = new MapRenderStatistics(
            visibleCells,
            drawnObjects,
            document.Objects.Count,
            (long)(Stopwatch.GetElapsedTime(started).TotalMilliseconds *
                   1000));
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
                (ObjectSelectionEnabled ||
                 Keyboard.Modifiers.HasFlag(ModifierKeys.Shift)))
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
        double cellWidth, double cellHeight,
        MapGridWindow visible)
    {
        if (!layer.Visible || document is null)
            return;
        for (var y = visible.Top; y < visible.BottomExclusive; y++)
            for (var x = visible.Left; x < visible.RightExclusive; x++)
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
        double cellWidth, double cellHeight,
        MapGridWindow visible)
    {
        if (document is null)
            return;
        var layer = document.Layer(kind);
        if (!layer.Visible)
            return;
        var brush = new SolidColorBrush(color);
        for (var y = visible.Top; y < visible.BottomExclusive; y++)
            for (var x = visible.Left; x < visible.RightExclusive; x++)
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
        DrawingContext drawing,
        double cellWidth,
        double cellHeight,
        MapGridWindow visible)
    {
        if (document is null)
            return;
        var pen = new Pen(
            new SolidColorBrush(Color.FromArgb(58, 30, 33, 36)), 0.75);
        var top = visible.Top * cellHeight;
        var bottom = visible.BottomExclusive * cellHeight;
        var left = visible.Left * cellWidth;
        var right = visible.RightExclusive * cellWidth;
        for (var x = visible.Left;
             x <= visible.RightExclusive;
             x++)
            drawing.DrawLine(
                pen, new Point(x * cellWidth, top),
                new Point(x * cellWidth, bottom));
        for (var y = visible.Top;
             y <= visible.BottomExclusive;
             y++)
            drawing.DrawLine(
                pen, new Point(left, y * cellHeight),
                new Point(right, y * cellHeight));
    }

    private int DrawObjects(
        DrawingContext drawing,
        double cellWidth,
        double cellHeight,
        Rect visible)
    {
        if (document is null)
            return 0;
        var anchorVisibility = visible;
        anchorVisibility.Inflate(
            Math.Max(256, 640 * zoom),
            Math.Max(256, 640 * zoom));
        var drawn = 0;
        foreach (var item in document.Objects)
        {
            var anchor = ObjectAnchor(item, cellWidth, cellHeight);
            if (!anchorVisibility.Contains(anchor))
                continue;
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
                {
                    drawing.DrawImage(image, rect);
                    drawn++;
                }
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
                drawn++;
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
        return drawn;
    }

    private void DrawAnalysis(
        DrawingContext drawing,
        double cellWidth,
        double cellHeight,
        MapGridWindow visible,
        Rect viewport)
    {
        if (document is null)
            return;
        if (showConnectivityHeatmap)
            DrawConnectivityHeatmap(
                drawing, cellWidth, cellHeight, visible);
        if (showAiRanges)
            DrawSelectedEnemyRanges(drawing, viewport);
    }

    private void DrawConnectivityHeatmap(
        DrawingContext drawing,
        double cellWidth,
        double cellHeight,
        MapGridWindow visible)
    {
        if (document is null)
            return;
        var source = SelectedOrFirstPlayer();
        if (source is null)
            return;
        if (reachabilityCache is null ||
            reachabilitySourceId != source.Id)
        {
            var ownMarker = TrySceneIndex(
                source.Id, out var sceneIndex)
                ? sceneIndex + 1000
                : -1;
            reachabilityCache =
                MapSpatialAnalysis.BuildReachability(
                    document,
                    source.X,
                    source.Y,
                    allowDiagonal: true,
                    ownMarker);
            reachabilitySourceId = source.Id;
        }

        var reachability = reachabilityCache;
        if (reachability.ReachableCellCount == 0)
            return;
        var palette = BuildHeatmapPalette();
        var maximum = Math.Max(1, reachability.MaximumDistance);
        for (var y = visible.Top; y < visible.BottomExclusive; y++)
        {
            for (var x = visible.Left; x < visible.RightExclusive; x++)
            {
                var distance = reachability.DistanceAt(x, y);
                if (distance < 0)
                    continue;
                var bucket = Math.Clamp(
                    (int)Math.Floor(
                        distance / (double)maximum * palette.Length),
                    0,
                    palette.Length - 1);
                drawing.DrawRectangle(
                    palette[bucket],
                    null,
                    new Rect(
                        x * cellWidth,
                        y * cellHeight,
                        cellWidth + 0.5,
                        cellHeight + 0.5));
            }
        }

        var target = HeatmapTarget(source);
        if (target is null)
            return;
        var ownDynamicMarker = TrySceneIndex(
            source.Id, out var sourceSceneIndex)
            ? sourceSceneIndex + 1000
            : -1;
        var path = MapSpatialAnalysis.FindShortestPath(
            document,
            source.X,
            source.Y,
            target.X,
            target.Y,
            ownDynamicMarker);
        if (path.Count < 2)
            return;
        var pathPen = new Pen(
            new SolidColorBrush(
                Color.FromArgb(230, 20, 231, 255)),
            Math.Clamp(2.0 * zoom, 1.2, 3.5));
        for (var index = 1; index < path.Count; index++)
        {
            drawing.DrawLine(
                pathPen,
                WaypointCenter(
                    path[index - 1], cellWidth, cellHeight),
                WaypointCenter(
                    path[index], cellWidth, cellHeight));
        }
    }

    private void DrawSelectedEnemyRanges(
        DrawingContext drawing,
        Rect viewport)
    {
        if (document is null)
            return;
        var enemy = document.Objects.FirstOrDefault(item =>
            item.Id == selectedObjectId && IsEnemy(item));
        if (enemy is null)
            return;

        var originWorld =
            MapSpatialAnalysis.ObjectWorldCenter(document, enemy);
        var origin = new Point(
            originWorld.X * zoom,
            originWorld.Y * zoom);
        var maximumRadius =
            enemyPreviewProfile.AlertRadiusWorld * zoom;
        var rangeBounds = new Rect(
            origin.X - maximumRadius,
            origin.Y - maximumRadius,
            maximumRadius * 2,
            maximumRadius * 2);
        if (!rangeBounds.IntersectsWith(viewport))
            return;

        var visionPoints =
            MapSpatialAnalysis.BuildOccludedVisionBoundary(
                document,
                enemy,
                enemyPreviewProfile,
                rayCount: 49);
        if (visionPoints.Count >= 3)
        {
            var geometry = new StreamGeometry();
            using (var context = geometry.Open())
            {
                var first = visionPoints[0];
                context.BeginFigure(
                    new Point(first.X * zoom, first.Y * zoom),
                    isFilled: false,
                    isClosed: true);
                context.PolyLineTo(
                    visionPoints.Skip(1).Select(point =>
                        new Point(
                            point.X * zoom,
                            point.Y * zoom)).ToArray(),
                    isStroked: true,
                    isSmoothJoin: true);
            }
            geometry.Freeze();
            drawing.DrawGeometry(
                null,
                new Pen(
                    new SolidColorBrush(
                        Color.FromArgb(245, 48, 219, 83)),
                    Math.Clamp(2.1 * zoom, 1.2, 3.2)),
                geometry);
        }

        DrawWorldRadius(
            drawing,
            origin,
            enemyPreviewProfile.AttackRadiusWorld,
            Color.FromArgb(230, 227, 51, 43),
            null);
        DrawWorldRadius(
            drawing,
            origin,
            enemyPreviewProfile.HearingRadiusWorld,
            Color.FromArgb(225, 38, 139, 219),
            new DashStyle([5.0, 4.0], 0));
        DrawWorldRadius(
            drawing,
            origin,
            enemyPreviewProfile.AlertRadiusWorld,
            Color.FromArgb(205, 238, 164, 38),
            new DashStyle([10.0, 6.0], 0));

        var directionRadians =
            MapSpatialAnalysis.DirectionDegrees(enemy.Direction) *
            Math.PI / 180;
        var arrowLength = Math.Max(14, 30 * zoom);
        drawing.DrawLine(
            new Pen(
                new SolidColorBrush(
                    Color.FromArgb(255, 250, 250, 245)),
                2),
            origin,
            new Point(
                origin.X + Math.Cos(directionRadians) * arrowLength,
                origin.Y + Math.Sin(directionRadians) * arrowLength));
    }

    private void DrawWorldRadius(
        DrawingContext drawing,
        Point origin,
        int radiusWorld,
        Color color,
        DashStyle? dashStyle)
    {
        var pen = new Pen(
            new SolidColorBrush(color),
            Math.Clamp(1.4 * zoom, 0.9, 2.4))
        {
            DashStyle = dashStyle ?? DashStyles.Solid
        };
        var radius = radiusWorld * zoom;
        drawing.DrawEllipse(null, pen, origin, radius, radius);
    }

    private static Brush[] BuildHeatmapPalette()
    {
        var palette = new Brush[16];
        for (var index = 0; index < palette.Length; index++)
        {
            var ratio = index / (double)(palette.Length - 1);
            var color = ratio < 0.5
                ? Color.FromArgb(
                    55,
                    (byte)(30 + ratio * 90),
                    (byte)(210 - ratio * 30),
                    82)
                : Color.FromArgb(
                    58,
                    (byte)(120 + (ratio - 0.5) * 240),
                    (byte)(180 - (ratio - 0.5) * 220),
                    48);
            var brush = new SolidColorBrush(color);
            brush.Freeze();
            palette[index] = brush;
        }
        return palette;
    }

    private MapObject? SelectedOrFirstPlayer()
    {
        if (document is null)
            return null;
        var selected = document.Objects.FirstOrDefault(item =>
            item.Id == selectedObjectId && IsPlayer(item));
        return selected ?? document.Objects.FirstOrDefault(IsPlayer);
    }

    private MapObject? HeatmapTarget(MapObject source)
    {
        if (document is null)
            return null;
        var selected = document.Objects.FirstOrDefault(item =>
            item.Id == selectedObjectId && item.Id != source.Id);
        if (selected is not null)
            return selected;
        var targetIds = document.Tasks
            .Select(task => task.TargetObjectId)
            .Where(id => !string.IsNullOrWhiteSpace(id))
            .ToHashSet(StringComparer.Ordinal);
        return document.Objects.FirstOrDefault(item =>
            targetIds.Contains(item.Id));
    }

    private static bool IsPlayer(MapObject item) =>
        item.Faction.Equals(
            "player", StringComparison.OrdinalIgnoreCase) ||
        item.Faction.Equals(
            "faction-3", StringComparison.OrdinalIgnoreCase);

    private static bool IsEnemy(MapObject item) =>
        item.Faction.Equals(
            "enemy", StringComparison.OrdinalIgnoreCase) ||
        item.Faction.Equals(
            "faction-1", StringComparison.OrdinalIgnoreCase);

    private static bool TrySceneIndex(
        string id,
        out int sceneIndex)
    {
        sceneIndex = -1;
        return id.StartsWith("scene-", StringComparison.Ordinal) &&
               int.TryParse(id.AsSpan(6), out sceneIndex);
    }

    private Rect EffectiveVisibleViewport(Rect mapRect)
    {
        if (visibleViewport.IsEmpty)
        {
            return new Rect(
                0,
                0,
                Math.Min(mapRect.Width, Math.Max(1, RenderSize.Width)),
                Math.Min(mapRect.Height, Math.Max(1, RenderSize.Height)));
        }
        var result = Rect.Intersect(visibleViewport, mapRect);
        return result.IsEmpty
            ? new Rect(0, 0, 1, 1)
            : result;
    }

    private void ClearAnalysisCache()
    {
        reachabilityCache = null;
        reachabilitySourceId = null;
    }

    private IReadOnlyList<MapObject> PatrolObjects() =>
        document?.Objects
            .Where(item =>
                item.IsLiving &&
                item.PatrolWaypoints.Count > 0)
            .ToList() ?? [];

    private void DrawPatrolRoutes()
    {
        using var drawing = routeOverlay.RenderOpen();
        if (!showPatrolRoutes || document is null)
            return;

        var cellWidth = document.EffectiveCellWidth * zoom;
        var cellHeight = document.EffectiveCellHeight * zoom;
        var viewport = EffectiveVisibleViewport(new Rect(
            0,
            0,
            document.Width * cellWidth,
            document.Height * cellHeight));
        var routes = PatrolObjects();
        if (routes.Count == 0)
            return;

        var normalPen = new Pen(
            new SolidColorBrush(Color.FromArgb(105, 26, 122, 149)),
            Math.Clamp(1.15 * zoom, 0.7, 1.5))
        {
            DashStyle = new DashStyle([5.0, 4.0], 0)
        };
        var selectedPen = new Pen(
            new SolidColorBrush(Color.FromArgb(245, 255, 190, 42)),
            Math.Clamp(2.4 * zoom, 1.8, 3.2));
        var selected = routes.FirstOrDefault(
            item => item.Id == selectedObjectId);

        foreach (var item in routes.Where(item =>
                     item != selected &&
                     RouteIntersectsViewport(
                         item, cellWidth, cellHeight, viewport)))
            DrawRoute(drawing, item, normalPen, cellWidth, cellHeight, false);
        if (selected is not null &&
            RouteIntersectsViewport(
                selected, cellWidth, cellHeight, viewport))
            DrawRoute(
                drawing, selected, selectedPen,
                cellWidth, cellHeight, true);
    }

    private void DrawMotionOverlay()
    {
        using var drawing = motionOverlay.RenderOpen();
        if (!showPatrolRoutes ||
            !motionPreviewEnabled ||
            document is null)
            return;

        var cellWidth = document.EffectiveCellWidth * zoom;
        var cellHeight = document.EffectiveCellHeight * zoom;
        var viewport = EffectiveVisibleViewport(new Rect(
            0,
            0,
            document.Width * cellWidth,
            document.Height * cellHeight));
        foreach (var item in PatrolObjects().Where(item =>
                     item.PatrolEnabled &&
                     RouteIntersectsViewport(
                         item, cellWidth, cellHeight, viewport) &&
                     HasMovement(ExpandedRoute(item))))
        {
            var position = AnimatedRoutePosition(
                ExpandedRoute(item), cellWidth, cellHeight);
            var isSelected = item.Id == selectedObjectId;
            var radius = isSelected ? 5.5 : 3.6;
            var fill = isSelected
                ? Color.FromArgb(255, 255, 205, 58)
                : Color.FromArgb(235, 33, 201, 228);
            drawing.DrawEllipse(
                new SolidColorBrush(fill),
                new Pen(new SolidColorBrush(
                    Color.FromArgb(235, 22, 30, 34)), 1),
                position, radius, radius);
        }
    }

    private static bool RouteIntersectsViewport(
        MapObject item,
        double cellWidth,
        double cellHeight,
        Rect viewport)
    {
        MapWaypoint[] points = item.PatrolWaypoints.Count == 0
            ? [new MapWaypoint { X = item.X, Y = item.Y }]
            :
            [
                new MapWaypoint { X = item.X, Y = item.Y },
                .. item.PatrolWaypoints
            ];
        var left = points.Min(point => point.X) * cellWidth;
        var right = (points.Max(point => point.X) + 1) * cellWidth;
        var top = points.Min(point => point.Y) * cellHeight;
        var bottom = (points.Max(point => point.Y) + 1) * cellHeight;
        var routeBounds = new Rect(
            left,
            top,
            Math.Max(cellWidth, right - left),
            Math.Max(cellHeight, bottom - top));
        routeBounds.Inflate(cellWidth * 3, cellHeight * 3);
        return routeBounds.IntersectsWith(viewport);
    }

    private void DrawRoute(
        DrawingContext drawing,
        MapObject item,
        Pen pen,
        double cellWidth,
        double cellHeight,
        bool selected)
    {
        var points = ExpandedRoute(item)
            .Select(point => WaypointCenter(point, cellWidth, cellHeight))
            .ToList();
        if (points.Count == 0)
            return;

        for (var index = 1; index < points.Count; index++)
            drawing.DrawLine(pen, points[index - 1], points[index]);

        if (!selected)
            return;
        var waypoints = item.PatrolWaypoints
            .Select(point => WaypointCenter(point, cellWidth, cellHeight))
            .ToList();
        for (var index = 0; index < waypoints.Count; index++)
        {
            var active = index == item.PatrolCurrentWaypointIndex;
            drawing.DrawEllipse(
                active
                    ? new SolidColorBrush(Color.FromRgb(255, 196, 42))
                    : new SolidColorBrush(Color.FromRgb(252, 246, 221)),
                new Pen(new SolidColorBrush(Color.FromRgb(92, 61, 18)), 1),
                waypoints[index], active ? 5 : 4, active ? 5 : 4);
            DrawWaypointNumber(drawing, index + 1, waypoints[index]);
        }
    }

    private IReadOnlyList<MapWaypoint> ExpandedRoute(MapObject item)
    {
        if (expandedRouteCache.TryGetValue(item.Id, out var cached))
            return cached;
        if (document is null)
            return [];

        var anchors = new List<MapWaypoint>
        {
            new() { X = item.X, Y = item.Y }
        };
        foreach (var waypoint in item.PatrolWaypoints)
        {
            var previous = anchors[^1];
            if (previous.X != waypoint.X || previous.Y != waypoint.Y)
                anchors.Add(new MapWaypoint
                {
                    X = waypoint.X,
                    Y = waypoint.Y
                });
        }
        if (anchors.Count == 1)
        {
            expandedRouteCache[item.Id] = anchors;
            return anchors;
        }

        var expanded = new List<MapWaypoint> { anchors[0] };
        for (var index = 1; index < anchors.Count; index++)
        {
            var segment = FindGridPath(
                anchors[index - 1], anchors[index]);
            if (segment is null)
            {
                expanded.Add(anchors[index]);
                continue;
            }
            expanded.AddRange(segment.Skip(1));
        }
        expandedRouteCache[item.Id] = expanded;
        return expanded;
    }

    private IReadOnlyList<MapWaypoint>? FindGridPath(
        MapWaypoint start, MapWaypoint goal)
    {
        if (document is null ||
            !InBounds(start.X, start.Y) ||
            !InBounds(goal.X, goal.Y))
            return null;

        var width = document.Width;
        var count = checked(width * document.Height);
        var startIndex = checked(start.Y * width + start.X);
        var goalIndex = checked(goal.Y * width + goal.X);
        var previous = new int[count];
        Array.Fill(previous, -1);
        previous[startIndex] = startIndex;
        var costs = new int[count];
        Array.Fill(costs, int.MaxValue);
        costs[startIndex] = 0;
        var closed = new bool[count];
        var open = new PriorityQueue<int, int>();
        open.Enqueue(
            startIndex,
            GridHeuristic(start.X, start.Y, goal.X, goal.Y));
        ReadOnlySpan<int> dx = [-1, 1, 0, 0, -1, 1, -1, 1];
        ReadOnlySpan<int> dy = [0, 0, -1, 1, -1, -1, 1, 1];

        while (open.TryDequeue(out var current, out _))
        {
            if (closed[current])
                continue;
            closed[current] = true;
            if (current == goalIndex)
                break;
            var x = current % width;
            var y = current / width;
            for (var direction = 0; direction < dx.Length; direction++)
            {
                var nextX = x + dx[direction];
                var nextY = y + dy[direction];
                if (!InBounds(nextX, nextY))
                    continue;
                var next = checked(nextY * width + nextX);
                if (closed[next] ||
                    !IsRouteCellOpen(next, startIndex, goalIndex))
                    continue;
                if (dx[direction] != 0 && dy[direction] != 0)
                {
                    var horizontal = checked(y * width + nextX);
                    var vertical = checked(nextY * width + x);
                    if (!IsRouteCellOpen(
                            horizontal, startIndex, goalIndex) ||
                        !IsRouteCellOpen(
                            vertical, startIndex, goalIndex))
                        continue;
                }
                var nextCost = costs[current] + 1;
                if (nextCost >= costs[next])
                    continue;
                costs[next] = nextCost;
                previous[next] = current;
                open.Enqueue(
                    next,
                    nextCost + GridHeuristic(
                        nextX, nextY, goal.X, goal.Y));
            }
        }
        if (previous[goalIndex] < 0)
            return null;

        var reversed = new List<MapWaypoint>();
        for (var current = goalIndex;; current = previous[current])
        {
            reversed.Add(new MapWaypoint
            {
                X = current % width,
                Y = current / width
            });
            if (current == startIndex)
                break;
        }
        reversed.Reverse();
        return reversed;
    }

    private bool IsRouteCellOpen(
        int index, int startIndex, int goalIndex)
    {
        if (document is null)
            return false;
        if (index == startIndex || index == goalIndex)
            return true;
        var value = document.Layer(
            EditorLayerKind.MovementObstacle).Cells[index];
        if (value == 0)
            return true;
        livingOccupants ??= document.Objects
            .Where(item =>
                item.IsLiving &&
                item.Id.StartsWith(
                    "scene-", StringComparison.Ordinal))
            .Select(item =>
                int.TryParse(item.Id.AsSpan(6), out var sceneIndex)
                    ? sceneIndex + 1000
                    : -1)
            .Where(item => item >= 0)
            .ToHashSet();
        return livingOccupants.Contains(value);
    }

    private bool InBounds(int x, int y) =>
        document is not null &&
        x >= 0 && x < document.Width &&
        y >= 0 && y < document.Height;

    private static int GridHeuristic(
        int x, int y, int goalX, int goalY) =>
        Math.Max(Math.Abs(goalX - x), Math.Abs(goalY - y));

    private void DrawWaypointNumber(
        DrawingContext drawing, int number, Point center)
    {
        var text = new FormattedText(
            number.ToString(CultureInfo.InvariantCulture),
            CultureInfo.InvariantCulture,
            FlowDirection.LeftToRight,
            new Typeface("Segoe UI"),
            9,
            Brushes.Black,
            VisualTreeHelper.GetDpi(this).PixelsPerDip);
        drawing.DrawText(
            text,
            new Point(
                center.X - text.Width / 2,
                center.Y - text.Height / 2));
    }

    private Point AnimatedRoutePosition(
        IReadOnlyList<MapWaypoint> route,
        double cellWidth,
        double cellHeight)
    {
        var points = route
            .Select(point => WaypointCenter(point, cellWidth, cellHeight))
            .ToList();
        if (points.Count == 1)
            return points[0];

        var lengths = new double[points.Count - 1];
        var total = 0.0;
        for (var index = 0; index < lengths.Length; index++)
        {
            lengths[index] = (points[index + 1] - points[index]).Length;
            total += lengths[index];
        }
        if (total <= 0.01)
            return points[0];

        var pixelsPerSecond = Math.Max(
            18.0, Math.Min(cellWidth, cellHeight) * 4.0);
        var distance = motionClock.Elapsed.TotalSeconds *
                       pixelsPerSecond % (total * 2.0);
        if (distance > total)
            distance = total * 2.0 - distance;
        for (var index = 0; index < lengths.Length; index++)
        {
            if (distance <= lengths[index] && lengths[index] > 0.01)
            {
                var progress = distance / lengths[index];
                return points[index] +
                       (points[index + 1] - points[index]) * progress;
            }
            distance -= lengths[index];
        }
        return points[^1];
    }

    private static bool HasMovement(
        IReadOnlyList<MapWaypoint> route) =>
        route.Count > 1 &&
        route.Skip(1).Any(point =>
            point.X != route[0].X || point.Y != route[0].Y);

    private static Point WaypointCenter(
        MapWaypoint point, double cellWidth, double cellHeight) =>
        new(
            (point.X + 0.5) * cellWidth,
            (point.Y + 0.5) * cellHeight);

    private void UpdateMotionTimer()
    {
        var shouldRun =
            IsLoaded && IsVisible &&
            showPatrolRoutes && motionPreviewEnabled &&
            document?.Objects.Any(item =>
                item.PatrolEnabled &&
                HasMovement(ExpandedRoute(item))) == true;
        if (shouldRun)
        {
            if (!motionTimer.IsEnabled)
                motionTimer.Start();
        }
        else
        {
            motionTimer.Stop();
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

    private MapObject? FindObjectAt(int x, int y)
    {
        var candidates = document?.Objects
            .Where(item =>
                Math.Abs(item.X - x) <= 1 &&
                Math.Abs(item.Y - y) <= 1)
            .ToList();
        if (candidates is null || candidates.Count == 0)
            return null;
        return candidates.LastOrDefault(item => item.IsLiving) ??
               candidates[^1];
    }

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
