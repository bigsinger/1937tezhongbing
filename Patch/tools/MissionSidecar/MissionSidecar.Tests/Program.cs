using System.Security.Cryptography;
using Mission1937.Sidecar;

var root = Path.Combine(
    Directory.Exists(@"E:\1937") ? @"E:\1937" : Path.GetTempPath(),
    "mission-sidecar-tests",
    Environment.ProcessId.ToString());
Directory.CreateDirectory(root);

var definition = new MissionSidecarDefinition
{
    Id = "test-mission",
    Title = "任务闭环测试",
    SelectorLevel = 13,
    EngineMission = 12,
    Objectives =
    [
        Objective("started", WorldEventKind.MissionStarted, optional: true),
        Objective(
            "reach", WorldEventKind.Reached,
            region: new MissionRegion { X = 100, Y = 200, Radius = 20 }),
        Objective(
            "kill", WorldEventKind.Killed,
            required: 2, dependsOn: ["reach"], databaseId: 77),
        Objective("pickup", WorldEventKind.PickedUp, optional: true),
        Objective(
            "explode", WorldEventKind.Exploded,
            dependsOn: ["reach"], databaseId: 88),
        Objective(
            "interact", WorldEventKind.Interacted,
            dependsOn: ["reach"]),
        Objective(
            "evacuate", WorldEventKind.Evacuated,
            dependsOn: ["kill", "explode", "interact"],
            region: new MissionRegion { X = 500, Y = 600, Radius = 30 })
    ]
};
var runtime = new MissionRuntimeEngine(definition);
ulong sequence = 0;
Apply(WorldEventKind.MissionStarted);
Apply(WorldEventKind.Reached, x: 100, y: 200);
Apply(WorldEventKind.Killed, databaseId: 77);
if (runtime.State.Objectives["kill"].Completed)
    throw new InvalidOperationException("Counted objective completed early.");
Apply(WorldEventKind.Killed, databaseId: 77);
Apply(WorldEventKind.PickedUp);
Apply(WorldEventKind.Exploded, databaseId: 88);
Apply(WorldEventKind.Interacted);
Apply(WorldEventKind.Evacuated, x: 500, y: 600);
if (runtime.State.Status != MissionRunStatus.Succeeded ||
    runtime.BuildView().Objectives.Count != 7 ||
    runtime.State.Objectives.Values.Count(item => item.Completed) != 7)
    throw new InvalidOperationException(
        "Mission dependency/count/optional/success runtime failed.");
Console.WriteLine(
    "Mission sidecar reached/killed/picked/exploded/interacted/evacuated closure passed.");

var failureDefinition = new MissionSidecarDefinition
{
    Id = "failure",
    Title = "失败测试",
    Objectives =
    [
        Objective("survive", WorldEventKind.Evacuated),
        new MissionObjectiveDefinition
        {
            Id = "player-dead",
            Title = "队员阵亡",
            Event = WorldEventKind.Killed,
            Failure = true,
            FailureReason = "关键队员阵亡。"
        }
    ]
};
var failureRuntime = new MissionRuntimeEngine(failureDefinition);
failureRuntime.Apply(new WorldEvent
{
    Sequence = 1,
    MonotonicMilliseconds = 100,
    Kind = WorldEventKind.Killed,
    Value = 1
});
if (failureRuntime.State.Status != MissionRunStatus.Failed ||
    failureRuntime.State.FailureReason != "关键队员阵亡。")
    throw new InvalidOperationException("Mission failure reason failed.");

var deadlineDefinition = new MissionSidecarDefinition
{
    Id = "deadline",
    Title = "超时测试",
    Objectives =
    [
        new MissionObjectiveDefinition
        {
            Id = "timed",
            Title = "限时撤离",
            Event = WorldEventKind.Evacuated,
            DeadlineMilliseconds = 1000,
            FailureReason = "未能按时撤离。"
        }
    ]
};
var deadlineRuntime = new MissionRuntimeEngine(deadlineDefinition);
deadlineRuntime.Apply(new WorldEvent
{
    Sequence = 1,
    MonotonicMilliseconds = 1,
    Kind = WorldEventKind.MissionStarted,
    Value = 1
});
deadlineRuntime.Apply(new WorldEvent
{
    Sequence = 2,
    MonotonicMilliseconds = 1500,
    Kind = WorldEventKind.Interacted,
    Value = 1
});
if (deadlineRuntime.State.Status != MissionRunStatus.Failed)
    throw new InvalidOperationException("Mission deadline failure failed.");
Console.WriteLine("Mission sidecar failure/deadline reasons passed.");

var originalSave = Path.Combine(root, "1937M000.SAV");
File.WriteAllBytes(
    originalSave,
    Enumerable.Range(0, 4096).Select(index => (byte)(index * 37)).ToArray());
var originalHash = Hash(originalSave);
var statePath = AtomicMissionStateStore.SidecarPathForSave(originalSave);
AtomicMissionStateStore.Save(
    statePath, runtime.State, originalSave);
var firstSequence = runtime.State.LastEventSequence;
runtime.State.LastEventSequence++;
AtomicMissionStateStore.Save(
    statePath, runtime.State, originalSave);
File.WriteAllText(statePath, "{simulated crash");
var rolledBack = AtomicMissionStateStore.Load(
    statePath, originalSave);
if (rolledBack.LastEventSequence != firstSequence ||
    Hash(originalSave) != originalHash)
    throw new InvalidOperationException(
        "Atomic sidecar rollback changed original save or restored wrong state.");
File.WriteAllText(statePath + ".tmp", "partial");
if (Hash(originalSave) != originalHash)
    throw new InvalidOperationException("Crash temp altered original save.");
var otherSave = Path.Combine(root, "other.SAV");
File.WriteAllText(otherSave, "different");
try
{
    _ = AtomicMissionStateStore.Load(statePath + ".bak", otherSave);
    throw new InvalidOperationException(
        "Mismatched original save fingerprint was accepted.");
}
catch (InvalidDataException)
{
}
Console.WriteLine(
    "Atomic sidecar save/load, crash rollback and original SAV fingerprint passed.");

var invalid = new MissionSidecarDefinition
{
    SchemaVersion = 2,
    Id = "bad",
    Objectives = [Objective("bad", WorldEventKind.Reached)]
};
try
{
    _ = new MissionRuntimeEngine(invalid);
    throw new InvalidOperationException("Unsupported schema was accepted.");
}
catch (InvalidDataException)
{
}
Console.WriteLine("Mission sidecar schema/API negotiation tests passed.");

var detectorDefinition = new MissionSidecarDefinition
{
    Id = "detector",
    Title = "事件观察器测试",
    Objectives =
    [
        Objective(
            "reach", WorldEventKind.Reached,
            region: new MissionRegion { X = 100, Y = 100, Radius = 10 }),
        Objective(
            "kill", WorldEventKind.Killed, databaseId: 77),
        Objective(
            "pickup", WorldEventKind.PickedUp, databaseId: 88),
        Objective(
            "explode", WorldEventKind.Exploded, databaseId: 99),
        Objective(
            "interact", WorldEventKind.Interacted,
            databaseId: 66, subjectDatabaseId: 1),
        Objective(
            "evacuate", WorldEventKind.Evacuated,
            region: new MissionRegion { X = 300, Y = 300, Radius = 10 })
    ]
};
var detector = new WorldEventDetector(detectorDefinition);
var initialActors = new[]
{
    Actor(1, 1, 0, 0, 0),
    Actor(2, 77, 1, 200, 200),
    Actor(3, 88, 1, 210, 210),
    Actor(4, 99, 1, 220, 220),
    Actor(5, 66, 1, 250, 250)
};
var initialEvents = detector.Detect(
    new RuntimeWorldSnapshot(12, 100, initialActors));
if (initialEvents.Count != 1 ||
    initialEvents[0].Kind != WorldEventKind.MissionStarted)
    throw new InvalidOperationException("Mission-start detection failed.");
var moved = initialActors
    .Select(actor => actor.Id == 1
        ? actor with { X = 100, Y = 100 }
        : actor)
    .ToArray();
var reachEvents = detector.Detect(
    new RuntimeWorldSnapshot(12, 200, moved));
if (reachEvents.Count(item =>
        item.Kind == WorldEventKind.Reached) != 1)
    throw new InvalidOperationException("Region entry detection failed.");
var transitions = moved
    .Where(actor => actor.Id != 3)
    .Select(actor => actor.Id switch
    {
        1 => actor with { X = 250, Y = 250 },
        2 => actor with { Dead = true },
        4 => actor with { Dead = true },
        _ => actor
    })
    .ToArray();
var transitionEvents = detector.Detect(
    new RuntimeWorldSnapshot(12, 300, transitions));
foreach (var kind in new[]
         {
             WorldEventKind.Killed,
             WorldEventKind.PickedUp,
             WorldEventKind.Exploded,
             WorldEventKind.Interacted
         })
    if (!transitionEvents.Any(item => item.Kind == kind))
        throw new InvalidOperationException(
            $"World snapshot failed to detect {kind}.");
var evacuated = transitions
    .Select(actor => actor.Id == 1
        ? actor with { X = 300, Y = 300 }
        : actor)
    .ToArray();
if (!detector.Detect(
        new RuntimeWorldSnapshot(12, 400, evacuated))
        .Any(item => item.Kind == WorldEventKind.Evacuated))
    throw new InvalidOperationException("Evacuation detection failed.");
Console.WriteLine(
    "Read-only world snapshot event detection passed.");

var repository = FindRepository();
var shippedDirectory = Path.Combine(repository, "Mod", "Missions");
var shippedDefinitions = Directory.Exists(shippedDirectory)
    ? Directory.GetFiles(
        shippedDirectory,
        "*.m1937mission.json",
        SearchOption.TopDirectoryOnly)
    : [];
if (shippedDefinitions.Length != 0)
    throw new InvalidOperationException(
        "Stable Mod must not ship retired extension sidecars.");
Console.WriteLine(
    "Stable Mod ships no extension sidecars.");

return;

void Apply(
    WorldEventKind kind,
    int x = 0,
    int y = 0,
    uint databaseId = 0)
{
    runtime.Apply(new WorldEvent
    {
        Sequence = ++sequence,
        MonotonicMilliseconds = (long)sequence * 100,
        Mission = 12,
        Kind = kind,
        SubjectX = x,
        SubjectY = y,
        SubjectDatabaseId = databaseId,
        Value = 1
    });
}

static MissionObjectiveDefinition Objective(
    string id,
    WorldEventKind kind,
    int required = 1,
    IEnumerable<string>? dependsOn = null,
    bool optional = false,
    uint? databaseId = null,
    uint? subjectDatabaseId = null,
    MissionRegion? region = null) =>
    new()
    {
        Id = id,
        Title = id,
        Description = id,
        Event = kind,
        RequiredCount = required,
        DependsOn = dependsOn?.ToList() ?? [],
        Optional = optional,
        TargetDatabaseId = databaseId,
        SubjectDatabaseId = subjectDatabaseId,
        Region = region
    };

static string Hash(string path)
{
    using var stream = File.OpenRead(path);
    return Convert.ToHexString(SHA256.HashData(stream));
}

static RuntimeActorSnapshot Actor(
    uint id,
    uint databaseId,
    int faction,
    int x,
    int y,
    bool dead = false) =>
    new(id, databaseId, faction, x, y, 1, dead, 0, 0);

static string FindRepository()
{
    for (var directory = new DirectoryInfo(Environment.CurrentDirectory);
         directory is not null;
         directory = directory.Parent)
    {
        if (File.Exists(Path.Combine(
                directory.FullName,
                "SDK",
                "address-catalog.json")) &&
            Directory.Exists(Path.Combine(
                directory.FullName,
                "Mod")))
            return directory.FullName;
    }
    throw new DirectoryNotFoundException(
        "Could not locate the repository for shipped sidecar tests.");
}
