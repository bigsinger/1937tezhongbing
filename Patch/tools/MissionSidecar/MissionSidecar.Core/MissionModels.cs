using System.Text.Json.Serialization;

namespace Mission1937.Sidecar;

public enum WorldEventKind : uint
{
    MissionStarted = 1,
    Reached = 2,
    Killed = 3,
    PickedUp = 4,
    Exploded = 5,
    Interacted = 6,
    Evacuated = 7,
    MissionSucceeded = 8,
    MissionFailed = 9,
    SaveStarted = 10,
    SaveCompleted = 11,
    LoadStarted = 12,
    LoadCompleted = 13
}

public enum MissionRunStatus
{
    Running,
    Succeeded,
    Failed
}

public sealed class MissionRegion
{
    public int X { get; set; }
    public int Y { get; set; }
    public int Radius { get; set; } = 32;
}

public sealed class MissionObjectiveDefinition
{
    public string Id { get; set; } = "";
    public string Title { get; set; } = "";
    public string Description { get; set; } = "";
    public WorldEventKind Event { get; set; } = WorldEventKind.Reached;
    public List<string> DependsOn { get; set; } = [];
    public int RequiredCount { get; set; } = 1;
    public bool Optional { get; set; }
    public bool Failure { get; set; }
    public string FailureReason { get; set; } = "";
    public uint? TargetDatabaseId { get; set; }
    public uint? SubjectDatabaseId { get; set; }
    public int? SubjectFaction { get; set; }
    public MissionRegion? Region { get; set; }
    public int? DeadlineMilliseconds { get; set; }
}

public sealed class MissionSidecarDefinition
{
    public int SchemaVersion { get; set; } = 1;
    public uint ApiVersion { get; set; } = 0x00010000;
    public string Id { get; set; } = "";
    public string Title { get; set; } = "";
    public int SelectorLevel { get; set; }
    public int EngineMission { get; set; }
    public string ExecutableSha256 { get; set; } = "";
    public long ExecutableFileSize { get; set; }
    public long ExecutablePeTimestamp { get; set; }
    public List<MissionObjectiveDefinition> Objectives { get; set; } = [];
}

public sealed class WorldEvent
{
    public ulong Sequence { get; set; }
    public long MonotonicMilliseconds { get; set; }
    public int Mission { get; set; }
    public WorldEventKind Kind { get; set; }
    public uint SubjectId { get; set; }
    public uint ObjectId { get; set; }
    public int Value { get; set; }
    public int SubjectFaction { get; set; }
    public int SubjectX { get; set; }
    public int SubjectY { get; set; }
    public uint SubjectDatabaseId { get; set; }
    public uint ObjectDatabaseId { get; set; }
}

public sealed class ObjectiveRuntimeState
{
    public string Id { get; set; } = "";
    public int Count { get; set; }
    public bool Completed { get; set; }
    public long? CompletedAtMilliseconds { get; set; }
}

public sealed class MissionRuntimeState
{
    public int SchemaVersion { get; set; } = 1;
    public string MissionId { get; set; } = "";
    public string DefinitionSha256 { get; set; } = "";
    public string SaveSha256 { get; set; } = "";
    public ulong LastEventSequence { get; set; }
    public long StartedAtMilliseconds { get; set; }
    public MissionRunStatus Status { get; set; } = MissionRunStatus.Running;
    public string FailureReason { get; set; } = "";
    public Dictionary<string, ObjectiveRuntimeState> Objectives { get; set; } =
        new(StringComparer.OrdinalIgnoreCase);
}

public sealed record MissionViewObjective(
    string Id,
    string Title,
    string Description,
    int Count,
    int RequiredCount,
    bool Active,
    bool Optional,
    bool Completed);

public sealed record MissionView(
    string Title,
    MissionRunStatus Status,
    string FailureReason,
    string Hint,
    IReadOnlyList<MissionViewObjective> Objectives);

[JsonSourceGenerationOptions(
    WriteIndented = true,
    PropertyNamingPolicy = JsonKnownNamingPolicy.SnakeCaseLower,
    UseStringEnumConverter = true)]
[JsonSerializable(typeof(MissionSidecarDefinition))]
[JsonSerializable(typeof(MissionRuntimeState))]
[JsonSerializable(typeof(WorldEvent))]
public partial class MissionJsonContext : JsonSerializerContext;
