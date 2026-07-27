namespace Mission1937.Sidecar;

public sealed record RuntimeActorSnapshot(
    uint Id,
    uint DatabaseId,
    int Faction,
    int X,
    int Y,
    int Facing,
    bool Dead,
    int GoalKind,
    int ContactState);

public sealed record RuntimeWorldSnapshot(
    int Mission,
    long MonotonicMilliseconds,
    IReadOnlyList<RuntimeActorSnapshot> Actors);

/// <summary>
/// Converts read-only snapshots of the supported executable into stable
/// sidecar events. It never follows runtime pointers after a snapshot has
/// been captured and never writes to the game process.
/// </summary>
public sealed class WorldEventDetector
{
    private readonly MissionSidecarDefinition definition;
    private readonly Dictionary<uint, RuntimeActorSnapshot> previous = [];
    private readonly HashSet<string> inside = new(
        StringComparer.OrdinalIgnoreCase);
    private ulong sequence;
    private int mission = -1;
    private bool primed;

    public WorldEventDetector(
        MissionSidecarDefinition definition,
        ulong initialSequence = 0)
    {
        MissionRuntimeEngine.ValidateDefinition(definition);
        this.definition = definition;
        sequence = initialSequence;
    }

    public IReadOnlyList<WorldEvent> Detect(RuntimeWorldSnapshot snapshot)
    {
        var events = new List<WorldEvent>();
        if (snapshot.Mission != mission)
        {
            mission = snapshot.Mission;
            previous.Clear();
            inside.Clear();
            primed = false;
            if (mission > 0)
                events.Add(NewEvent(
                    snapshot, WorldEventKind.MissionStarted, null));
        }

        var current = snapshot.Actors
            .Where(actor => actor.Id != 0)
            .GroupBy(actor => actor.Id)
            .Select(group => group.First())
            .ToDictionary(actor => actor.Id);
        if (!primed)
        {
            PrimeSpatialState(snapshot);
            CopyCurrent(current);
            primed = true;
            return events;
        }

        foreach (var actor in current.Values)
        {
            if (!previous.TryGetValue(actor.Id, out var old) ||
                old.Dead || !actor.Dead)
                continue;
            events.Add(NewEvent(
                snapshot, WorldEventKind.Killed, actor));
            if (definition.Objectives.Any(objective =>
                    objective.Event == WorldEventKind.Exploded &&
                    MatchesTarget(objective, actor)))
                events.Add(NewEvent(
                    snapshot, WorldEventKind.Exploded, actor));
        }

        foreach (var old in previous.Values)
        {
            if (current.ContainsKey(old.Id) || old.Dead)
                continue;
            if (definition.Objectives.Any(objective =>
                    objective.Event == WorldEventKind.PickedUp &&
                    MatchesTarget(objective, old)))
                events.Add(NewEvent(
                    snapshot, WorldEventKind.PickedUp, old));
        }

        DetectSpatialEvents(snapshot, events);
        DetectTargetInteractions(snapshot, events);
        CopyCurrent(current);
        return events;
    }

    private void PrimeSpatialState(RuntimeWorldSnapshot snapshot)
    {
        foreach (var objective in definition.Objectives.Where(objective =>
                     objective.Region is not null &&
                     objective.Event is WorldEventKind.Reached or
                         WorldEventKind.Evacuated or
                         WorldEventKind.Interacted))
        foreach (var actor in EligibleSubjects(objective, snapshot.Actors))
            if (Inside(actor, objective.Region!))
                inside.Add(SpatialKey(objective.Id, actor.Id));
    }

    private void DetectSpatialEvents(
        RuntimeWorldSnapshot snapshot,
        List<WorldEvent> events)
    {
        foreach (var objective in definition.Objectives.Where(objective =>
                     objective.Region is not null &&
                     objective.Event is WorldEventKind.Reached or
                         WorldEventKind.Evacuated or
                         WorldEventKind.Interacted))
        {
            foreach (var actor in EligibleSubjects(
                         objective, snapshot.Actors))
            {
                var key = SpatialKey(objective.Id, actor.Id);
                var isInside = Inside(actor, objective.Region!);
                var wasInside = inside.Contains(key);
                if (isInside)
                    inside.Add(key);
                else
                    inside.Remove(key);
                if (isInside && !wasInside)
                    events.Add(NewEvent(
                        snapshot, objective.Event, actor));
            }
        }
    }

    private void DetectTargetInteractions(
        RuntimeWorldSnapshot snapshot,
        List<WorldEvent> events)
    {
        foreach (var objective in definition.Objectives.Where(objective =>
                     objective.Event == WorldEventKind.Interacted &&
                     objective.Region is null &&
                     objective.TargetDatabaseId.HasValue))
        {
            foreach (var target in snapshot.Actors.Where(actor =>
                         !actor.Dead && MatchesTarget(objective, actor)))
            foreach (var player in snapshot.Actors.Where(actor =>
                         !actor.Dead &&
                         actor.Id != target.Id &&
                         (!objective.SubjectDatabaseId.HasValue ||
                          objective.SubjectDatabaseId.Value ==
                              actor.DatabaseId) &&
                         (objective.SubjectFaction ?? 0) == actor.Faction))
            {
                var key = SpatialKey(
                    objective.Id, player.Id, target.Id);
                var isNear = DistanceSquared(player, target) <= 48L * 48L;
                var wasNear = inside.Contains(key);
                if (isNear)
                    inside.Add(key);
                else
                    inside.Remove(key);
                if (isNear && !wasNear)
                    events.Add(NewEvent(
                        snapshot,
                        WorldEventKind.Interacted,
                        player,
                        target.Id,
                        target.DatabaseId));
            }
        }
    }

    private IEnumerable<RuntimeActorSnapshot> EligibleSubjects(
        MissionObjectiveDefinition objective,
        IReadOnlyList<RuntimeActorSnapshot> actors)
    {
        var faction = objective.SubjectFaction ?? 0;
        return actors.Where(actor =>
            !actor.Dead &&
            actor.Faction == faction &&
            (!objective.SubjectDatabaseId.HasValue ||
             objective.SubjectDatabaseId.Value == actor.DatabaseId) &&
            (!objective.TargetDatabaseId.HasValue ||
             objective.TargetDatabaseId.Value == actor.DatabaseId));
    }

    private WorldEvent NewEvent(
        RuntimeWorldSnapshot snapshot,
        WorldEventKind kind,
        RuntimeActorSnapshot? subject,
        uint objectId = 0,
        uint objectDatabaseId = 0) =>
        new()
        {
            Sequence = ++sequence,
            MonotonicMilliseconds = snapshot.MonotonicMilliseconds,
            Mission = snapshot.Mission,
            Kind = kind,
            SubjectId = subject?.Id ?? 0,
            ObjectId = objectId,
            Value = 1,
            SubjectFaction = subject?.Faction ?? 0,
            SubjectX = subject?.X ?? 0,
            SubjectY = subject?.Y ?? 0,
            SubjectDatabaseId = subject?.DatabaseId ?? 0,
            ObjectDatabaseId = objectDatabaseId
        };

    private void CopyCurrent(
        Dictionary<uint, RuntimeActorSnapshot> current)
    {
        previous.Clear();
        foreach (var pair in current)
            previous[pair.Key] = pair.Value;
    }

    private static bool MatchesTarget(
        MissionObjectiveDefinition objective,
        RuntimeActorSnapshot actor) =>
        !objective.TargetDatabaseId.HasValue ||
        objective.TargetDatabaseId.Value == actor.DatabaseId;

    private static bool Inside(
        RuntimeActorSnapshot actor,
        MissionRegion region)
    {
        var dx = (long)actor.X - region.X;
        var dy = (long)actor.Y - region.Y;
        return dx * dx + dy * dy <=
            (long)region.Radius * region.Radius;
    }

    private static long DistanceSquared(
        RuntimeActorSnapshot left,
        RuntimeActorSnapshot right)
    {
        var dx = (long)left.X - right.X;
        var dy = (long)left.Y - right.Y;
        return dx * dx + dy * dy;
    }

    private static string SpatialKey(
        string objectiveId,
        uint subjectId,
        uint objectId = 0) =>
        $"{objectiveId}:{subjectId:X8}:{objectId:X8}";
}
