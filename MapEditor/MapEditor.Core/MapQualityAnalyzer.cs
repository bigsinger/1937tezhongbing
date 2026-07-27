namespace Mission1937.MapEditor.Core;

public enum MapIssueSeverity
{
    Error,
    Warning,
    Info
}

public sealed record MapIssue(
    MapIssueSeverity Severity,
    string Code,
    string Message,
    int? X = null,
    int? Y = null,
    string? ObjectId = null,
    string ValueSource = "编辑器估算")
{
    public string Location =>
        X is not null && Y is not null
            ? $"{X}, {Y}"
            : ObjectId ?? "—";
}

public static class MapQualityAnalyzer
{
    public static IReadOnlyList<MapIssue> Analyze(
        MapDocument document)
    {
        ArgumentNullException.ThrowIfNull(document);
        var issues = new List<MapIssue>();
        issues.AddRange(MapValidator.Validate(document).Select(message =>
            new MapIssue(
                MapIssueSeverity.Error,
                "DOCUMENT_INVALID",
                message,
                ValueSource: "工程约束")));
        if (issues.Count > 0)
            return issues;

        CheckSeams(document, issues);
        CheckFootprints(document, issues);
        var components = BuildComponents(document);
        CheckConnectivity(document, components, issues);
        CheckNarrowPassages(document, issues);
        CheckTasks(document, components, issues);
        CheckPatrols(document, issues);
        CheckSpawnThreat(document, issues);
        CheckSorting(document, issues);

        if (issues.Count == 0)
        {
            issues.Add(new MapIssue(
                MapIssueSeverity.Info,
                "QUALITY_OK",
                "未发现结构、连通性、巡逻或出生安全问题。",
                ValueSource: "编辑器分析"));
        }
        return issues
            .OrderBy(issue => issue.Severity)
            .ThenBy(issue => issue.Code, StringComparer.Ordinal)
            .ToArray();
    }

    private static void CheckSeams(
        MapDocument document,
        List<MapIssue> issues)
    {
        var movement =
            document.Layer(EditorLayerKind.MovementObstacle).Cells;
        var sight =
            document.Layer(EditorLayerKind.LineOfSightObstacle).Cells;
        foreach (var seamX in document.QualityVerticalSeams)
        {
            for (var y = 0; y < document.Height; ++y)
            {
                var left = document.Index(seamX - 1, y);
                var right = document.Index(seamX, y);
                if (!StrongObstacleMismatch(
                        movement[left], movement[right],
                        sight[left], sight[right]))
                    continue;
                issues.Add(new MapIssue(
                    MapIssueSeverity.Warning,
                    "SEAM_L2_L3_DISCONTINUITY",
                    $"垂直接缝 X={seamX} 两侧的视线/移动障碍不连续。",
                    seamX,
                    y,
                    ValueSource: "编辑器接缝规则"));
                if (issues.Count(issue =>
                        issue.Code == "SEAM_L2_L3_DISCONTINUITY") >= 24)
                    break;
            }
        }
        foreach (var seamY in document.QualityHorizontalSeams)
        {
            for (var x = 0; x < document.Width; ++x)
            {
                var top = document.Index(x, seamY - 1);
                var bottom = document.Index(x, seamY);
                if (!StrongObstacleMismatch(
                        movement[top], movement[bottom],
                        sight[top], sight[bottom]))
                    continue;
                issues.Add(new MapIssue(
                    MapIssueSeverity.Warning,
                    "SEAM_L2_L3_DISCONTINUITY",
                    $"水平接缝 Y={seamY} 两侧的视线/移动障碍不连续。",
                    x,
                    seamY,
                    ValueSource: "编辑器接缝规则"));
                if (issues.Count(issue =>
                        issue.Code == "SEAM_L2_L3_DISCONTINUITY") >= 24)
                    break;
            }
        }

        var seamsX = document.QualityVerticalSeams.ToHashSet();
        var seamsY = document.QualityHorizontalSeams.ToHashSet();
        foreach (var item in document.Objects.Where(item =>
                     IsLargeStatic(item) &&
                     (seamsX.Any(x => Math.Abs(item.X - x) <= 1) ||
                      seamsY.Any(y => Math.Abs(item.Y - y) <= 1))))
        {
            issues.Add(new MapIssue(
                MapIssueSeverity.Info,
                "OBJECT_CROSSES_COMPOSITE_SEAM",
                $"“{item.Name}”靠近合成区块切线，请检查建筑/门/墙是否完整。",
                item.X,
                item.Y,
                item.Id,
                "编辑器几何估算"));
        }
    }

    private static bool StrongObstacleMismatch(
        int movementA,
        int movementB,
        int sightA,
        int sightB)
    {
        var movementChanges = (movementA == 0) != (movementB == 0);
        var sightChanges = (sightA == 0) != (sightB == 0);
        return movementChanges != sightChanges;
    }

    private static void CheckFootprints(
        MapDocument document,
        List<MapIssue> issues)
    {
        var movement =
            document.Layer(EditorLayerKind.MovementObstacle).Cells;
        foreach (var item in document.Objects.Where(IsBlockingObject))
        {
            var index = document.Index(item.X, item.Y);
            if (movement[index] != 0)
                continue;
            issues.Add(new MapIssue(
                MapIssueSeverity.Warning,
                "FOOTPRINT_MOVEMENT_MISMATCH",
                $"阻挡物“{item.Name}”锚点没有移动障碍；请核对 footprint。",
                item.X,
                item.Y,
                item.Id,
                "素材类别+移动层"));
            if (issues.Count(issue =>
                    issue.Code == "FOOTPRINT_MOVEMENT_MISMATCH") >= 40)
                break;
        }
    }

    private static void CheckConnectivity(
        MapDocument document,
        ComponentMap components,
        List<MapIssue> issues)
    {
        if (components.Sizes.Count <= 1)
            return;
        var meaningfulThreshold = Math.Max(
            4,
            components.TraversableCount / 200);
        foreach (var pair in components.Sizes
                     .Where(pair => pair.Value < meaningfulThreshold)
                     .OrderBy(pair => pair.Value)
                     .Take(20))
        {
            var index = Array.IndexOf(components.Cells, pair.Key);
            issues.Add(new MapIssue(
                MapIssueSeverity.Warning,
                "ISOLATED_WALKABLE_REGION",
                $"发现仅 {pair.Value} 格的孤立通行区。",
                index % document.Width,
                index / document.Width,
                ValueSource: "四方向连通分析"));
        }
        issues.Add(new MapIssue(
            MapIssueSeverity.Info,
            "CONNECTIVITY_COMPONENTS",
            $"全图有 {components.Sizes.Count} 个通行连通分量，" +
            $"共 {components.TraversableCount:N0} 个可走格。",
            ValueSource: "四方向连通分析"));
    }

    private static void CheckTasks(
        MapDocument document,
        ComponentMap components,
        List<MapIssue> issues)
    {
        var objects = document.Objects.ToDictionary(item => item.Id);
        var players = document.Objects.Where(IsPlayer).ToArray();
        var playerComponents = players
            .Select(item => components.At(item.X, item.Y, document.Width))
            .Where(value => value >= 0)
            .ToHashSet();
        foreach (var task in document.Tasks)
        {
            if (string.IsNullOrWhiteSpace(task.TargetObjectId))
                continue;
            if (!objects.TryGetValue(task.TargetObjectId, out var target))
            {
                issues.Add(new MapIssue(
                    MapIssueSeverity.Error,
                    "TASK_TARGET_MISSING",
                    $"任务“{task.Title}”指向不存在的对象 " +
                    $"{task.TargetObjectId}。",
                    ObjectId: task.TargetObjectId,
                    ValueSource: "任务引用"));
                continue;
            }
            var targetComponent = components.At(
                target.X, target.Y, document.Width);
            if (playerComponents.Count > 0 &&
                !playerComponents.Contains(targetComponent))
            {
                issues.Add(new MapIssue(
                    MapIssueSeverity.Error,
                    "TASK_TARGET_UNREACHABLE",
                    $"任务“{task.Title}”的目标“{target.Name}”" +
                    "不在玩家可达连通区。",
                    target.X,
                    target.Y,
                    target.Id,
                    "移动层连通分析"));
            }
        }
    }

    private static void CheckPatrols(
        MapDocument document,
        List<MapIssue> issues)
    {
        var movement =
            document.Layer(EditorLayerKind.MovementObstacle).Cells;
        var routeCells = new Dictionary<(int X, int Y), List<MapObject>>();
        var expandedRoutes = new List<(
            MapObject Object,
            IReadOnlyList<MapWaypoint> Route)>();
        foreach (var item in document.Objects.Where(item =>
                     item.PatrolWaypoints.Count > 0))
        {
            var ownMarker = TrySceneIndex(item.Id, out var sceneIndex)
                ? sceneIndex + 1000
                : -1;
            var anchors = new List<MapWaypoint>
            {
                new() { X = item.X, Y = item.Y }
            };
            anchors.AddRange(item.PatrolWaypoints.Select(point =>
                new MapWaypoint { X = point.X, Y = point.Y }));
            var expanded = new List<MapWaypoint> { anchors[0] };
            for (var anchorIndex = 1;
                 anchorIndex < anchors.Count;
                 anchorIndex++)
            {
                var from = anchors[anchorIndex - 1];
                var to = anchors[anchorIndex];
                var segment = MapSpatialAnalysis.FindShortestPath(
                    document,
                    from.X,
                    from.Y,
                    to.X,
                    to.Y,
                    ownMarker);
                if (segment.Count == 0)
                {
                    issues.Add(new MapIssue(
                        MapIssueSeverity.Error,
                        "PATROL_SEGMENT_UNREACHABLE",
                        $"“{item.Name}”的巡逻段 {anchorIndex} " +
                        $"({from.X},{from.Y}) → ({to.X},{to.Y}) 不可达。",
                        to.X,
                        to.Y,
                        item.Id,
                        "移动层+A*路径"));
                    continue;
                }
                expanded.AddRange(segment.Skip(1));
            }

            foreach (var point in expanded)
            {
                var value = movement[document.Index(point.X, point.Y)];
                if (value != 0 && value != ownMarker)
                {
                    issues.Add(new MapIssue(
                        MapIssueSeverity.Error,
                        "PATROL_PATH_BLOCKED",
                        $"“{item.Name}”的巡逻路径经过移动障碍。",
                        point.X,
                        point.Y,
                        item.Id,
                        "移动层+A*展开路径"));
                }
                routeCells.TryAdd((point.X, point.Y), []);
                routeCells[(point.X, point.Y)].Add(item);
            }
            if (expanded.Count > 1)
                expandedRoutes.Add((item, expanded));
        }
        var congested = routeCells
            .Select(pair => new
            {
                pair.Key,
                Objects = pair.Value
                    .Select(item => item.Id)
                    .Distinct(StringComparer.Ordinal)
                    .ToArray()
            })
            .Where(pair => pair.Objects.Length >= 2)
            .ToArray();
        foreach (var point in congested.Take(30))
        {
            issues.Add(new MapIssue(
                MapIssueSeverity.Warning,
                "PATROL_CONGESTION",
                $"{point.Objects.Length} 条 A* 展开巡逻路线共用该格，" +
                "可能发生交叉或狭路会车。",
                point.Key.X,
                point.Key.Y,
                ValueSource: "巡逻时间轴/A*路径估算"));
        }
        if (congested.Length > 30)
        {
            issues.Add(new MapIssue(
                MapIssueSeverity.Info,
                "PATROL_CONGESTION_SUMMARY",
                $"另有 {congested.Length - 30:N0} 个路线交叉格未逐项显示。",
                ValueSource: "巡逻时间轴/A*路径估算"));
        }
        CheckPatrolTimeline(expandedRoutes, issues);
    }

    private static void CheckPatrolTimeline(
        IReadOnlyList<(
            MapObject Object,
            IReadOnlyList<MapWaypoint> Route)> routes,
        List<MapIssue> issues)
    {
        const int horizon = 240;
        var occupancy = new Dictionary<
            (int Tick, int X, int Y),
            List<MapObject>>();
        var transitions = new Dictionary<
            (int Tick, int FromX, int FromY, int ToX, int ToY),
            MapObject>();
        var headOn = new List<(
            int Tick,
            MapWaypoint Position,
            MapObject First,
            MapObject Second)>();
        foreach (var (item, route) in routes)
        {
            for (var tick = 0; tick < horizon; tick++)
            {
                var position = TimelinePoint(route, tick);
                var key = (tick, position.X, position.Y);
                occupancy.TryAdd(key, []);
                occupancy[key].Add(item);
                var next = TimelinePoint(route, tick + 1);
                var reverseKey = (
                    tick,
                    next.X,
                    next.Y,
                    position.X,
                    position.Y);
                if (transitions.TryGetValue(
                        reverseKey, out var other) &&
                    other.Id != item.Id)
                {
                    headOn.Add((tick, position, other, item));
                }
                transitions[(
                    tick,
                    position.X,
                    position.Y,
                    next.X,
                    next.Y)] = item;
            }
        }

        var collisions = occupancy
            .Select(pair => new
            {
                pair.Key,
                Objects = pair.Value
                    .DistinctBy(item => item.Id)
                    .ToArray()
            })
            .Where(pair => pair.Objects.Length >= 2)
            .Take(20)
            .ToArray();
        foreach (var collision in collisions)
        {
            issues.Add(new MapIssue(
                MapIssueSeverity.Warning,
                "PATROL_TIMELINE_COLLISION",
                $"等速同步预览第 {collision.Key.Tick} 拍有 " +
                $"{collision.Objects.Length} 名活物占用同一格；" +
                "建议错开起点或路线。",
                collision.Key.X,
                collision.Key.Y,
                ValueSource: "编辑器等速/同步起步估算"));
        }
        foreach (var collision in headOn
                     .DistinctBy(item =>
                         (item.Tick,
                          item.Position.X,
                          item.Position.Y,
                          string.CompareOrdinal(
                              item.First.Id,
                              item.Second.Id) < 0
                              ? item.First.Id
                              : item.Second.Id))
                     .Take(20))
        {
            issues.Add(new MapIssue(
                MapIssueSeverity.Warning,
                "PATROL_HEAD_ON_RISK",
                $"“{collision.First.Name}”与“{collision.Second.Name}”" +
                $"在第 {collision.Tick} 拍可能迎面会车。",
                collision.Position.X,
                collision.Position.Y,
                ValueSource: "编辑器等速/同步起步估算"));
        }
    }

    private static MapWaypoint TimelinePoint(
        IReadOnlyList<MapWaypoint> route,
        int tick)
    {
        if (route.Count <= 1)
            return route[0];
        var last = route.Count - 1;
        var period = checked(last * 2);
        var phase = tick % period;
        var index = phase <= last
            ? phase
            : period - phase;
        return route[index];
    }

    private static void CheckSpawnThreat(
        MapDocument document,
        List<MapIssue> issues)
    {
        var profile = EnemyPreviewProfile.EditorDefault;
        var players = document.Objects.Where(IsPlayer).ToArray();
        var enemies = document.Objects.Where(IsEnemy).ToArray();
        var nearest = (
            from player in players
            from enemy in enemies
            let distance = WorldDistance(document, player, enemy)
            orderby distance
            select (player, enemy, distance)).FirstOrDefault();
        if (nearest.player is null || nearest.enemy is null)
            return;
        if (nearest.distance <= profile.AttackRadiusWorld)
        {
            issues.Add(new MapIssue(
                MapIssueSeverity.Error,
                "SPAWN_IN_ATTACK_RANGE",
                $"玩家“{nearest.player.Name}”出生在敌军“" +
                 $"{nearest.enemy.Name}”估算攻击半径内（" +
                 $"{nearest.distance:F0}/{profile.AttackRadiusWorld} 世界单位）。",
                nearest.player.X,
                nearest.player.Y,
                nearest.player.Id,
                profile.AttackSource));
        }
        else if (nearest.distance <= profile.AlertRadiusWorld)
        {
            issues.Add(new MapIssue(
                MapIssueSeverity.Warning,
                nearest.distance <= profile.HearingRadiusWorld
                    ? "SPAWN_IN_HEARING_RANGE"
                    : "SPAWN_IN_ALERT_RANGE",
                $"最近敌军距玩家出生点 {nearest.distance:F0} 世界单位；" +
                "请结合朝向、遮挡和任务开场复核。",
                nearest.player.X,
                nearest.player.Y,
                nearest.player.Id,
                nearest.distance <= profile.HearingRadiusWorld
                    ? profile.HearingSource
                    : profile.AlertSource));
        }
        foreach (var (player, enemy) in
                 from player in players
                 from enemy in enemies
                 where MapSpatialAnalysis.HasLineOfSight(
                     document, enemy, player, profile)
                 select (player, enemy))
        {
            issues.Add(new MapIssue(
                MapIssueSeverity.Error,
                "SPAWN_IN_ENEMY_VISION",
                $"玩家“{player.Name}”出生在敌军“{enemy.Name}”" +
                "带障碍遮挡的估算视线扇形内。",
                player.X,
                player.Y,
                player.Id,
                profile.VisionSource));
            if (issues.Count(issue =>
                    issue.Code == "SPAWN_IN_ENEMY_VISION") >= 12)
                break;
        }
    }

    private static void CheckNarrowPassages(
        MapDocument document,
        List<MapIssue> issues)
    {
        var candidates = new bool[
            checked(document.Width * document.Height)];
        for (var y = 1; y < document.Height - 1; y++)
        {
            for (var x = 1; x < document.Width - 1; x++)
            {
                if (!MapSpatialAnalysis.IsTraversable(document, x, y))
                    continue;
                var left = MapSpatialAnalysis.IsTraversable(
                    document, x - 1, y);
                var right = MapSpatialAnalysis.IsTraversable(
                    document, x + 1, y);
                var top = MapSpatialAnalysis.IsTraversable(
                    document, x, y - 1);
                var bottom = MapSpatialAnalysis.IsTraversable(
                    document, x, y + 1);
                var horizontalCorridor = left && right && !top && !bottom;
                var verticalCorridor = top && bottom && !left && !right;
                if (horizontalCorridor || verticalCorridor)
                    candidates[document.Index(x, y)] = true;
            }
        }

        var visited = new bool[candidates.Length];
        var queue = new Queue<int>();
        var clusters = new List<(int Index, int Size)>();
        for (var start = 0; start < candidates.Length; start++)
        {
            if (!candidates[start] || visited[start])
                continue;
            visited[start] = true;
            queue.Enqueue(start);
            var size = 0;
            while (queue.TryDequeue(out var current))
            {
                size++;
                var x = current % document.Width;
                var y = current / document.Width;
                foreach (var (nextX, nextY) in new[]
                         {
                             (x - 1, y),
                             (x + 1, y),
                             (x, y - 1),
                             (x, y + 1)
                         })
                {
                    if (nextX < 0 || nextX >= document.Width ||
                        nextY < 0 || nextY >= document.Height)
                        continue;
                    var next = checked(
                        nextY * document.Width + nextX);
                    if (!candidates[next] || visited[next])
                        continue;
                    visited[next] = true;
                    queue.Enqueue(next);
                }
            }
            clusters.Add((start, size));
        }

        foreach (var cluster in clusters
                     .OrderByDescending(item => item.Size)
                     .Take(20))
        {
            issues.Add(new MapIssue(
                MapIssueSeverity.Info,
                "NARROW_PASSAGE",
                $"发现宽 1 格、长约 {cluster.Size} 格的窄通道；" +
                "请结合巡逻路线检查会车和封堵风险。",
                cluster.Index % document.Width,
                cluster.Index / document.Width,
                ValueSource: "移动层局部宽度估算"));
        }
    }

    private static void CheckSorting(
        MapDocument document,
        List<MapIssue> issues)
    {
        var characters = document.Objects.Where(item =>
            item.Kind == "character").ToArray();
        foreach (var item in document.Objects.Where(IsLargeStatic))
        {
            var overlap = characters.FirstOrDefault(character =>
                character.X == item.X && character.Y == item.Y);
            if (overlap is null)
                continue;
            issues.Add(new MapIssue(
                MapIssueSeverity.Warning,
                "FOREGROUND_SORTING_RISK",
                $"角色“{overlap.Name}”与“{item.Name}”共用锚点，" +
                "可能出现前景遮挡顺序异常。",
                item.X,
                item.Y,
                item.Id,
                "对象锚点估算"));
        }
    }

    private static ComponentMap BuildComponents(
        MapDocument document)
    {
        var movement =
            document.Layer(EditorLayerKind.MovementObstacle).Cells;
        var cells = new int[movement.Length];
        Array.Fill(cells, -1);
        var sizes = new Dictionary<int, int>();
        var queue = new Queue<int>();
        var nextComponent = 0;
        var traversable = 0;
        for (var start = 0; start < movement.Length; ++start)
        {
            if (!IsTraversable(movement[start]) || cells[start] >= 0)
                continue;
            traversable++;
            cells[start] = nextComponent;
            queue.Enqueue(start);
            var size = 0;
            while (queue.TryDequeue(out var current))
            {
                size++;
                var x = current % document.Width;
                var y = current / document.Width;
                Visit(x - 1, y);
                Visit(x + 1, y);
                Visit(x, y - 1);
                Visit(x, y + 1);
            }
            sizes[nextComponent] = size;
            nextComponent++;

            void Visit(int x, int y)
            {
                if (x < 0 || x >= document.Width ||
                    y < 0 || y >= document.Height)
                    return;
                var index = y * document.Width + x;
                if (cells[index] >= 0 ||
                    !IsTraversable(movement[index]))
                    return;
                traversable++;
                cells[index] = nextComponent;
                queue.Enqueue(index);
            }
        }
        return new ComponentMap(cells, sizes, traversable);
    }

    private static bool IsTraversable(int value) =>
        value == 0 || value >= 1000;

    private static bool IsBlockingObject(MapObject item) =>
        item.Kind is "building" or "wall" or "door" or "obstacle" ||
        item.Category.Contains("建筑", StringComparison.Ordinal) ||
        item.Category.Contains("墙", StringComparison.Ordinal) ||
        item.Category.Contains("障碍", StringComparison.Ordinal);

    private static bool IsLargeStatic(MapObject item) =>
        item.Kind is "building" or "wall" or "door" ||
        item.Category.Contains("建筑", StringComparison.Ordinal) ||
        item.Category.Contains("墙", StringComparison.Ordinal);

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

    private static double WorldDistance(
        MapDocument document,
        MapObject first,
        MapObject second)
    {
        var dx = (first.X - second.X) *
            document.EffectiveCellWidth;
        var dy = (first.Y - second.Y) *
            document.EffectiveCellHeight;
        return Math.Sqrt((double)dx * dx + (double)dy * dy);
    }

    private static bool TrySceneIndex(
        string id,
        out int sceneIndex)
    {
        sceneIndex = -1;
        return id.StartsWith("scene-", StringComparison.Ordinal) &&
            int.TryParse(id.AsSpan(6), out sceneIndex);
    }

    private sealed record ComponentMap(
        int[] Cells,
        IReadOnlyDictionary<int, int> Sizes,
        int TraversableCount)
    {
        public int At(int x, int y, int width) =>
            x < 0 || x >= width || y < 0 ||
            checked(y * width + x) >= Cells.Length
                ? -1
                : Cells[y * width + x];
    }
}
