namespace Mission1937.MapEditor.Core;

public readonly record struct MapGridWindow(
    int Left,
    int Top,
    int RightExclusive,
    int BottomExclusive)
{
    public int Width => Math.Max(0, RightExclusive - Left);
    public int Height => Math.Max(0, BottomExclusive - Top);
    public int CellCount => checked(Width * Height);
    public bool IsEmpty => Width == 0 || Height == 0;

    public bool Contains(int x, int y) =>
        x >= Left && x < RightExclusive &&
        y >= Top && y < BottomExclusive;
}

public readonly record struct MapWorldPoint(double X, double Y);

public sealed record MapReachability(
    int Width,
    int Height,
    int[] Distances,
    int ReachableCellCount,
    int MaximumDistance)
{
    public int DistanceAt(int x, int y)
    {
        if (x < 0 || x >= Width || y < 0 || y >= Height)
            return -1;
        return Distances[checked(y * Width + x)];
    }

    public bool IsReachable(int x, int y) => DistanceAt(x, y) >= 0;
}

public sealed record EnemyPreviewProfile(
    int VisionRadiusWorld,
    double VisionHalfAngleDegrees,
    int HearingRadiusWorld,
    int AttackRadiusWorld,
    int AlertRadiusWorld,
    string VisionSource,
    string HearingSource,
    string AttackSource,
    string AlertSource)
{
    public static EnemyPreviewProfile EditorDefault { get; } = new(
        VisionRadiusWorld: 640,
        VisionHalfAngleDegrees: 45,
        HearingRadiusWorld: 224,
        AttackRadiusWorld: 256,
        AlertRadiusWorld: 640,
        VisionSource: "编辑器估算（90°扇形）",
        HearingSource: "Mod 配置默认值（原版近距值 128）",
        AttackSource: "编辑器估算",
        AlertSource: "Mod 配置默认值");

    public static EnemyPreviewProfile ForDifficulty(
        int difficultyLevel,
        int aiLevel)
    {
        var difficulty = Math.Clamp(difficultyLevel, 0, 3);
        var intelligence = Math.Clamp(aiLevel, 0, 3);
        var hearingBase = new[] { 128, 160, 192, 224 }[intelligence];
        var hearingBonus = new[] { -32, 0, 32, 64 }[difficulty];
        var alertBase = new[] { 640, 720, 800, 960 }[intelligence];
        var alertBonus = new[] { -160, 0, 160, 320 }[difficulty];
        return EditorDefault with
        {
            HearingRadiusWorld = Math.Clamp(
                hearingBase + hearingBonus, 64, 2048),
            AlertRadiusWorld = Math.Clamp(
                alertBase + alertBonus, 320, 4096),
            HearingSource =
                $"Mod 配置推演（AI {intelligence} / 难度 {difficulty}）",
            AlertSource =
                $"Mod 配置推演（AI {intelligence} / 难度 {difficulty}）"
        };
    }
}

public static class MapSpatialAnalysis
{
    private static readonly (int X, int Y)[] CardinalNeighbors =
    [
        (-1, 0),
        (1, 0),
        (0, -1),
        (0, 1)
    ];

    private static readonly (int X, int Y)[] EightWayNeighbors =
    [
        (-1, 0),
        (1, 0),
        (0, -1),
        (0, 1),
        (-1, -1),
        (1, -1),
        (-1, 1),
        (1, 1)
    ];

    public static MapGridWindow VisibleGridWindow(
        double viewportLeft,
        double viewportTop,
        double viewportWidth,
        double viewportHeight,
        double cellWidth,
        double cellHeight,
        int mapWidth,
        int mapHeight,
        int marginCells = 2)
    {
        if (cellWidth <= 0 || cellHeight <= 0 ||
            mapWidth <= 0 || mapHeight <= 0 ||
            viewportWidth <= 0 || viewportHeight <= 0)
        {
            return new MapGridWindow(0, 0, 0, 0);
        }

        var margin = Math.Max(0, marginCells);
        var left = Math.Clamp(
            (int)Math.Floor(viewportLeft / cellWidth) - margin,
            0,
            mapWidth);
        var top = Math.Clamp(
            (int)Math.Floor(viewportTop / cellHeight) - margin,
            0,
            mapHeight);
        var right = Math.Clamp(
            (int)Math.Ceiling(
                (viewportLeft + viewportWidth) / cellWidth) + margin,
            left,
            mapWidth);
        var bottom = Math.Clamp(
            (int)Math.Ceiling(
                (viewportTop + viewportHeight) / cellHeight) + margin,
            top,
            mapHeight);
        return new MapGridWindow(left, top, right, bottom);
    }

    public static bool IsTraversable(
        MapDocument document,
        int x,
        int y,
        int ownDynamicMarker = -1)
    {
        if (x < 0 || x >= document.Width ||
            y < 0 || y >= document.Height)
            return false;
        var value = document.Layer(
            EditorLayerKind.MovementObstacle).Cells[
            checked(y * document.Width + x)];
        return value == 0 ||
               value == ownDynamicMarker ||
               value >= 1000;
    }

    public static MapReachability BuildReachability(
        MapDocument document,
        int startX,
        int startY,
        bool allowDiagonal = true,
        int ownDynamicMarker = -1)
    {
        ArgumentNullException.ThrowIfNull(document);
        var count = checked(document.Width * document.Height);
        var distances = new int[count];
        Array.Fill(distances, -1);
        if (!IsTraversable(
                document, startX, startY, ownDynamicMarker))
        {
            return new MapReachability(
                document.Width, document.Height, distances, 0, 0);
        }

        var queue = new Queue<int>();
        var start = checked(startY * document.Width + startX);
        distances[start] = 0;
        queue.Enqueue(start);
        var reachable = 0;
        var maximumDistance = 0;
        var neighbors = allowDiagonal
            ? EightWayNeighbors
            : CardinalNeighbors;

        while (queue.TryDequeue(out var current))
        {
            reachable++;
            var x = current % document.Width;
            var y = current / document.Width;
            var nextDistance = checked(distances[current] + 1);
            maximumDistance = Math.Max(
                maximumDistance, distances[current]);
            foreach (var (offsetX, offsetY) in neighbors)
            {
                var nextX = x + offsetX;
                var nextY = y + offsetY;
                if (!IsTraversable(
                        document, nextX, nextY, ownDynamicMarker))
                    continue;
                var next = checked(nextY * document.Width + nextX);
                if (distances[next] >= 0)
                    continue;
                if (offsetX != 0 && offsetY != 0 &&
                    (!IsTraversable(
                         document, x + offsetX, y,
                         ownDynamicMarker) ||
                     !IsTraversable(
                         document, x, y + offsetY,
                         ownDynamicMarker)))
                {
                    continue;
                }
                distances[next] = nextDistance;
                queue.Enqueue(next);
            }
        }

        return new MapReachability(
            document.Width,
            document.Height,
            distances,
            reachable,
            maximumDistance);
    }

    public static IReadOnlyList<MapWaypoint> FindShortestPath(
        MapDocument document,
        int startX,
        int startY,
        int goalX,
        int goalY,
        int ownDynamicMarker = -1)
    {
        ArgumentNullException.ThrowIfNull(document);
        if (!IsTraversable(
                document, startX, startY, ownDynamicMarker) ||
            !IsTraversable(
                document, goalX, goalY, ownDynamicMarker))
            return [];

        var count = checked(document.Width * document.Height);
        var previous = new int[count];
        var costs = new int[count];
        var closed = new bool[count];
        Array.Fill(previous, -1);
        Array.Fill(costs, int.MaxValue);
        var start = checked(startY * document.Width + startX);
        var goal = checked(goalY * document.Width + goalX);
        previous[start] = start;
        costs[start] = 0;
        var open = new PriorityQueue<int, int>();
        open.Enqueue(start, Heuristic(startX, startY, goalX, goalY));

        while (open.TryDequeue(out var current, out _))
        {
            if (closed[current])
                continue;
            closed[current] = true;
            if (current == goal)
                break;
            var x = current % document.Width;
            var y = current / document.Width;
            foreach (var (offsetX, offsetY) in EightWayNeighbors)
            {
                var nextX = x + offsetX;
                var nextY = y + offsetY;
                if (!IsTraversable(
                        document, nextX, nextY, ownDynamicMarker))
                    continue;
                if (offsetX != 0 && offsetY != 0 &&
                    (!IsTraversable(
                         document, x + offsetX, y,
                         ownDynamicMarker) ||
                     !IsTraversable(
                         document, x, y + offsetY,
                         ownDynamicMarker)))
                {
                    continue;
                }
                var next = checked(nextY * document.Width + nextX);
                if (closed[next])
                    continue;
                var stepCost = offsetX == 0 || offsetY == 0 ? 10 : 14;
                var nextCost = checked(costs[current] + stepCost);
                if (nextCost >= costs[next])
                    continue;
                costs[next] = nextCost;
                previous[next] = current;
                open.Enqueue(
                    next,
                    checked(nextCost +
                        10 * Heuristic(
                            nextX, nextY, goalX, goalY)));
            }
        }

        if (previous[goal] < 0)
            return [];
        var result = new List<MapWaypoint>();
        for (var current = goal;; current = previous[current])
        {
            result.Add(new MapWaypoint
            {
                X = current % document.Width,
                Y = current / document.Width
            });
            if (current == start)
                break;
        }
        result.Reverse();
        return result;
    }

    public static double DirectionDegrees(int direction) =>
        direction switch
        {
            1 => -90,
            2 => -45,
            3 => 0,
            4 => 45,
            5 => 90,
            6 => 135,
            7 => 180,
            8 => -135,
            _ => -90
        };

    public static IReadOnlyList<MapWorldPoint> BuildOccludedVisionBoundary(
        MapDocument document,
        MapObject observer,
        EnemyPreviewProfile profile,
        int rayCount = 49)
    {
        ArgumentNullException.ThrowIfNull(document);
        ArgumentNullException.ThrowIfNull(observer);
        ArgumentNullException.ThrowIfNull(profile);
        var count = Math.Clamp(rayCount, 3, 257);
        if (count % 2 == 0)
            count++;
        var origin = ObjectWorldCenter(document, observer);
        var direction = DirectionDegrees(observer.Direction);
        var result = new List<MapWorldPoint>(count + 2) { origin };
        for (var index = 0; index < count; index++)
        {
            var ratio = count == 1
                ? 0
                : index / (double)(count - 1);
            var angleDegrees =
                direction - profile.VisionHalfAngleDegrees +
                ratio * profile.VisionHalfAngleDegrees * 2;
            var radians = angleDegrees * Math.PI / 180;
            result.Add(CastSightRay(
                document,
                origin,
                Math.Cos(radians),
                Math.Sin(radians),
                profile.VisionRadiusWorld));
        }
        result.Add(origin);
        return result;
    }

    public static bool HasLineOfSight(
        MapDocument document,
        MapObject observer,
        MapObject target,
        EnemyPreviewProfile profile)
    {
        ArgumentNullException.ThrowIfNull(document);
        ArgumentNullException.ThrowIfNull(observer);
        ArgumentNullException.ThrowIfNull(target);
        ArgumentNullException.ThrowIfNull(profile);
        var origin = ObjectWorldCenter(document, observer);
        var destination = ObjectWorldCenter(document, target);
        var dx = destination.X - origin.X;
        var dy = destination.Y - origin.Y;
        var distance = Math.Sqrt(dx * dx + dy * dy);
        if (distance > profile.VisionRadiusWorld)
            return false;
        var targetAngle = Math.Atan2(dy, dx) * 180 / Math.PI;
        var delta = NormalizeAngle(
            targetAngle - DirectionDegrees(observer.Direction));
        if (Math.Abs(delta) > profile.VisionHalfAngleDegrees)
            return false;
        if (distance <= 0.001)
            return true;
        var end = CastSightRay(
            document,
            origin,
            dx / distance,
            dy / distance,
            distance);
        return WorldDistance(end, destination) <=
               Math.Max(
                   document.EffectiveCellWidth,
                   document.EffectiveCellHeight);
    }

    public static MapWorldPoint ObjectWorldCenter(
        MapDocument document,
        MapObject item) =>
        new(
            item.X * document.EffectiveCellWidth +
            document.EffectiveCellWidth / 2.0,
            item.Y * document.EffectiveCellHeight +
            document.EffectiveCellHeight / 2.0);

    private static MapWorldPoint CastSightRay(
        MapDocument document,
        MapWorldPoint origin,
        double directionX,
        double directionY,
        double maximumDistance)
    {
        var sight = document.Layer(
            EditorLayerKind.LineOfSightObstacle).Cells;
        var stepLength = Math.Max(
            2,
            Math.Min(
                document.EffectiveCellWidth,
                document.EffectiveCellHeight) / 3.0);
        var previous = origin;
        for (var distance = stepLength;
             distance <= maximumDistance + stepLength;
             distance += stepLength)
        {
            var bounded = Math.Min(distance, maximumDistance);
            var current = new MapWorldPoint(
                origin.X + directionX * bounded,
                origin.Y + directionY * bounded);
            var x = (int)Math.Floor(
                current.X / document.EffectiveCellWidth);
            var y = (int)Math.Floor(
                current.Y / document.EffectiveCellHeight);
            if (x < 0 || x >= document.Width ||
                y < 0 || y >= document.Height)
                return previous;
            var originX = (int)Math.Floor(
                origin.X / document.EffectiveCellWidth);
            var originY = (int)Math.Floor(
                origin.Y / document.EffectiveCellHeight);
            if ((x != originX || y != originY) &&
                sight[checked(y * document.Width + x)] != 0)
            {
                return previous;
            }
            previous = current;
            if (bounded >= maximumDistance)
                break;
        }
        return previous;
    }

    private static int Heuristic(
        int x,
        int y,
        int goalX,
        int goalY) =>
        Math.Max(Math.Abs(goalX - x), Math.Abs(goalY - y));

    private static double NormalizeAngle(double degrees)
    {
        var normalized = degrees % 360;
        if (normalized > 180)
            normalized -= 360;
        else if (normalized < -180)
            normalized += 360;
        return normalized;
    }

    private static double WorldDistance(
        MapWorldPoint first,
        MapWorldPoint second)
    {
        var dx = first.X - second.X;
        var dy = first.Y - second.Y;
        return Math.Sqrt(dx * dx + dy * dy);
    }
}
