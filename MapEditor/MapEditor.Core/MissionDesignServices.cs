namespace Mission1937.MapEditor.Core;

public sealed record MissionGraphNode(
    string Id,
    string Title,
    bool Optional,
    bool Failure,
    int OriginalStateCode);

public sealed record MissionGraphEdge(
    string From,
    string To,
    string Kind);

public sealed record MissionGraph(
    IReadOnlyList<MissionGraphNode> Nodes,
    IReadOnlyList<MissionGraphEdge> Edges,
    IReadOnlyList<string> TopologicalOrder,
    IReadOnlyList<string> Errors);

public static class MissionGraphService
{
    public static MissionGraph Build(MapDocument document)
    {
        ArgumentNullException.ThrowIfNull(document);
        var errors = new List<string>();
        var nodes = document.Tasks.Select(task => new MissionGraphNode(
            task.Id,
            task.Title,
            task.Optional,
            task.FailureCondition,
            task.OriginalStateCode)).ToArray();
        var ids = nodes.Select(node => node.Id).ToHashSet(
            StringComparer.OrdinalIgnoreCase);
        var edges = new List<MissionGraphEdge>();
        foreach (var task in document.Tasks)
        {
            foreach (var dependency in task.DependsOn.Distinct(
                         StringComparer.OrdinalIgnoreCase))
            {
                if (!ids.Contains(dependency))
                {
                    errors.Add(
                        $"任务 {task.Id} 依赖不存在的任务 {dependency}。");
                    continue;
                }
                edges.Add(new MissionGraphEdge(
                    dependency, task.Id, "dependency"));
            }
            if (!string.IsNullOrWhiteSpace(task.NextTaskId))
            {
                if (!ids.Contains(task.NextTaskId))
                    errors.Add(
                        $"任务 {task.Id} 的后续 {task.NextTaskId} 不存在。");
                else
                    edges.Add(new MissionGraphEdge(
                        task.Id, task.NextTaskId, "next"));
            }
            if (task.RequiredCount <= 0)
                errors.Add($"任务 {task.Id} 的计数必须大于 0。");
            if (task.FailureCondition &&
                string.IsNullOrWhiteSpace(task.FailureReason))
                errors.Add($"失败任务 {task.Id} 缺少失败原因。");
            if (task.Trigger.Contains(
                    "evac", StringComparison.OrdinalIgnoreCase) &&
                string.IsNullOrWhiteSpace(task.EvacuationCondition))
                errors.Add($"撤离任务 {task.Id} 缺少撤离条件。");
            if (!string.IsNullOrWhiteSpace(task.TargetObjectId) &&
                !task.TargetDatabaseId.HasValue &&
                !task.TargetObjectId.StartsWith(
                    "db:", StringComparison.OrdinalIgnoreCase) &&
                document.Objects.All(item =>
                    !string.Equals(
                        item.Id,
                        task.TargetObjectId,
                        StringComparison.OrdinalIgnoreCase)))
                errors.Add(
                    $"任务 {task.Id} 引用不存在的对象 {task.TargetObjectId}。");
        }

        var incoming = nodes.ToDictionary(
            node => node.Id,
            _ => 0,
            StringComparer.OrdinalIgnoreCase);
        foreach (var edge in edges)
            incoming[edge.To]++;
        var ready = new SortedSet<string>(
            incoming.Where(item => item.Value == 0)
                .Select(item => item.Key),
            StringComparer.OrdinalIgnoreCase);
        var order = new List<string>();
        while (ready.Count > 0)
        {
            var current = ready.Min!;
            ready.Remove(current);
            order.Add(current);
            foreach (var edge in edges.Where(edge =>
                         string.Equals(
                             edge.From, current,
                             StringComparison.OrdinalIgnoreCase)))
            {
                incoming[edge.To]--;
                if (incoming[edge.To] == 0)
                    ready.Add(edge.To);
            }
        }
        if (order.Count != nodes.Length)
            errors.Add("任务依赖图存在环，无法确定执行顺序。");
        if (nodes.Length > 0 &&
            nodes.All(node => node.Optional || node.Failure))
            errors.Add("任务图没有必做的成功目标。");

        return new MissionGraph(nodes, edges, order, errors);
    }

    public static IReadOnlyDictionary<int, string> OriginalStateMapping(
        MapDocument document) =>
        document.Tasks
            .Where(task => task.OriginalStateCode >= 0)
            .GroupBy(task => task.OriginalStateCode)
            .ToDictionary(
                group => group.Key,
                group => string.Join(", ", group.Select(task => task.Id)));
}

public sealed record AiCoordinationPreview(
    string SourceActorId,
    IReadOnlyList<string> ReinforcementActorIds,
    IReadOnlyList<MapWaypoint> SearchPattern,
    int ReactionDelayMilliseconds,
    string ValueSource);

public static class AiCoordinationSimulator
{
    public static AiCoordinationPreview Simulate(
        MapDocument document,
        MapObject source,
        int aiLevel,
        int difficulty)
    {
        var ai = Math.Clamp(aiLevel, 0, 3);
        var level = Math.Clamp(difficulty, 0, 3);
        var maximum = new[] { 1, 1, 2, 3 }[ai] +
            (level == 3 && ai > 0 ? 1 : 0);
        maximum = Math.Clamp(maximum, 1, 4);
        var reaction = Math.Max(
            100, new[] { 900, 650, 425, 250 }[ai] - level * 75);
        var searchCount = new[] { 0, 2, 3, 4 }[ai];
        var stepWorld = new[] { 0, 48, 72, 96 }[ai];
        var stepX = Math.Max(
            1, stepWorld / Math.Max(1, document.EffectiveCellWidth));
        var stepY = Math.Max(
            1, stepWorld / Math.Max(1, document.EffectiveCellHeight));
        var allies = document.Objects
            .Where(item =>
                item.Id != source.Id &&
                item.IsLiving &&
                string.Equals(
                    item.Faction, source.Faction,
                    StringComparison.OrdinalIgnoreCase))
            .OrderBy(item =>
                (long)(item.X - source.X) * (item.X - source.X) +
                (long)(item.Y - source.Y) * (item.Y - source.Y))
            .ThenBy(item => item.Id)
            .Take(maximum)
            .Select(item => item.Id)
            .ToArray();

        var direction = MapSpatialAnalysis.DirectionDegrees(source.Direction);
        var radians = direction * Math.PI / 180.0;
        var forwardX = (int)Math.Round(Math.Cos(radians) * stepX);
        var forwardY = (int)Math.Round(Math.Sin(radians) * stepY);
        var pattern = new (int Forward, int Lateral)[]
        {
            (1, 0), (0, -1), (0, 1), (-1, 0)
        };
        var points = pattern.Take(searchCount).Select(offset =>
            new MapWaypoint
            {
                X = Math.Clamp(
                    source.X +
                    forwardX * offset.Forward -
                    forwardY * offset.Lateral,
                    0, document.Width - 1),
                Y = Math.Clamp(
                    source.Y +
                    forwardY * offset.Forward +
                    forwardX * offset.Lateral,
                    0, document.Height - 1)
            }).ToArray();
        return new AiCoordinationPreview(
            source.Id,
            allies,
            points,
            reaction,
            $"Mod EnemyAI 策略（AI {ai}/难度 {level}；最后目击点快照）");
    }
}

public sealed record TimelineActorState(
    string ActorId,
    double X,
    double Y,
    string Source);

public sealed record TimelineFrame(
    int TimeMilliseconds,
    IReadOnlyList<TimelineActorState> PlayerStates,
    IReadOnlyList<TimelineActorState> PatrolStates,
    IReadOnlyList<string> PotentialDetections);

public static class PlayerTimelineSimulator
{
    public static IReadOnlyList<TimelineFrame> Simulate(
        MapDocument document,
        int durationMilliseconds,
        int stepMilliseconds,
        EnemyPreviewProfile profile)
    {
        if (durationMilliseconds < 0 || stepMilliseconds <= 0)
            throw new ArgumentOutOfRangeException(nameof(stepMilliseconds));
        var players = document.Objects.Where(IsPlayer).ToArray();
        var patrols = document.Objects.Where(item =>
            item.PatrolEnabled && item.PatrolWaypoints.Count > 0).ToArray();
        var result = new List<TimelineFrame>();
        for (var time = 0;
             time <= durationMilliseconds;
             time += stepMilliseconds)
        {
            var playerStates = players.Select(player =>
                PlayerAt(document, player, time)).ToArray();
            var patrolStates = patrols.Select(patrol =>
                PatrolAt(patrol, time)).ToArray();
            var detections = new List<string>();
            foreach (var enemy in patrolStates)
            foreach (var player in playerStates)
            {
                var dx = (enemy.X - player.X) * document.EffectiveCellWidth;
                var dy = (enemy.Y - player.Y) * document.EffectiveCellHeight;
                if (dx * dx + dy * dy <=
                    (long)profile.VisionRadiusWorld *
                    profile.VisionRadiusWorld)
                    detections.Add($"{enemy.ActorId}->{player.ActorId}");
            }
            result.Add(new TimelineFrame(
                time, playerStates, patrolStates,
                detections.Distinct().ToArray()));
        }
        return result;
    }

    private static TimelineActorState PlayerAt(
        MapDocument document,
        MapObject player,
        int time)
    {
        var actions = document.PlayerTimeline
            .Where(action => action.ActorId == player.Id)
            .OrderBy(action => action.StartMilliseconds)
            .ToArray();
        double x = player.X;
        double y = player.Y;
        foreach (var action in actions)
        {
            if (time < action.StartMilliseconds)
                break;
            if (time >= action.StartMilliseconds +
                action.DurationMilliseconds)
            {
                x = action.TargetX;
                y = action.TargetY;
                continue;
            }
            var progress =
                (time - action.StartMilliseconds) /
                (double)action.DurationMilliseconds;
            x += (action.TargetX - x) * progress;
            y += (action.TargetY - y) * progress;
            break;
        }
        return new TimelineActorState(
            player.Id, x, y, "玩家行动时间轴（编辑器估算）");
    }

    private static TimelineActorState PatrolAt(
        MapObject patrol,
        int time)
    {
        var route = new List<MapWaypoint>
        {
            new() { X = patrol.X, Y = patrol.Y }
        };
        route.AddRange(patrol.PatrolWaypoints);
        if (route.Count == 1)
            return new TimelineActorState(
                patrol.Id, patrol.X, patrol.Y, "原版恢复巡逻点");
        const double millisecondsPerSegment = 1800.0;
        var phase = (time / millisecondsPerSegment) % route.Count;
        var index = (int)Math.Floor(phase);
        var next = (index + 1) % route.Count;
        var progress = phase - index;
        return new TimelineActorState(
            patrol.Id,
            route[index].X +
                (route[next].X - route[index].X) * progress,
            route[index].Y +
                (route[next].Y - route[index].Y) * progress,
            "原版恢复路线 + 编辑器速度估算");
    }

    private static bool IsPlayer(MapObject item) =>
        item.IsLiving &&
        (item.Faction.Contains(
             "player", StringComparison.OrdinalIgnoreCase) ||
         item.Faction is "2" or "faction-2");
}
