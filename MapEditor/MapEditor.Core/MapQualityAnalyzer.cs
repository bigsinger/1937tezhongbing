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
    private const int EstimatedHearingRadius = 224;
    private const int EstimatedAttackRadius = 256;
    private const int EstimatedAlertRadius = 640;

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
        foreach (var item in document.Objects.Where(item =>
                     item.PatrolWaypoints.Count > 0))
        {
            foreach (var point in item.PatrolWaypoints)
            {
                var value = movement[document.Index(point.X, point.Y)];
                var ownMarker = TrySceneIndex(item.Id, out var sceneIndex)
                    ? sceneIndex + 1000
                    : -1;
                if (value != 0 && value != ownMarker)
                {
                    issues.Add(new MapIssue(
                        MapIssueSeverity.Error,
                        "PATROL_POINT_BLOCKED",
                        $"“{item.Name}”的巡逻点落在移动障碍上。",
                        point.X,
                        point.Y,
                        item.Id,
                        "移动层+巡逻数组"));
                }
                routeCells.TryAdd((point.X, point.Y), []);
                routeCells[(point.X, point.Y)].Add(item);
            }
        }
        foreach (var (point, occupants) in routeCells.Where(
                     pair => pair.Value
                         .Select(item => item.Id)
                         .Distinct()
                         .Count() >= 3))
        {
            issues.Add(new MapIssue(
                MapIssueSeverity.Warning,
                "PATROL_CONGESTION",
                $"{occupants.Select(item => item.Id).Distinct().Count()} " +
                "条巡逻路线共用该格，可能发生拥堵/会车。",
                point.X,
                point.Y,
                ValueSource: "巡逻点密度"));
        }
    }

    private static void CheckSpawnThreat(
        MapDocument document,
        List<MapIssue> issues)
    {
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
        if (nearest.distance <= EstimatedAttackRadius)
        {
            issues.Add(new MapIssue(
                MapIssueSeverity.Error,
                "SPAWN_IN_ATTACK_RANGE",
                $"玩家“{nearest.player.Name}”出生在敌军“" +
                $"{nearest.enemy.Name}”估算攻击半径内（" +
                $"{nearest.distance:F0}/{EstimatedAttackRadius} 世界单位）。",
                nearest.player.X,
                nearest.player.Y,
                nearest.player.Id,
                "编辑器估算"));
        }
        else if (nearest.distance <= EstimatedAlertRadius)
        {
            issues.Add(new MapIssue(
                MapIssueSeverity.Warning,
                nearest.distance <= EstimatedHearingRadius
                    ? "SPAWN_IN_HEARING_RANGE"
                    : "SPAWN_IN_ALERT_RANGE",
                $"最近敌军距玩家出生点 {nearest.distance:F0} 世界单位；" +
                "请结合朝向、遮挡和任务开场复核。",
                nearest.player.X,
                nearest.player.Y,
                nearest.player.Id,
                "Mod 配置默认值/编辑器估算"));
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
            x < 0 || y < 0 ||
            checked(y * width + x) >= Cells.Length
                ? -1
                : Cells[y * width + x];
    }
}
