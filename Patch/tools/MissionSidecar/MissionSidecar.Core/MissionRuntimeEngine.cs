using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace Mission1937.Sidecar;

public sealed class MissionRuntimeEngine
{
    private readonly MissionSidecarDefinition definition;
    private readonly string definitionSha256;
    private MissionRuntimeState state;

    public MissionRuntimeEngine(
        MissionSidecarDefinition definition,
        MissionRuntimeState? restored = null)
    {
        this.definition = definition;
        ValidateDefinition(definition);
        definitionSha256 = HashDefinition(definition);
        state = restored ?? NewState(definition, definitionSha256);
        ValidateState(state);
        if (!string.Equals(
                state.MissionId,
                definition.Id,
                StringComparison.OrdinalIgnoreCase) ||
            !string.Equals(
                state.DefinitionSha256,
                definitionSha256,
                StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException(
                "任务状态与当前 sidecar 定义不兼容。");
    }

    public MissionRuntimeState State => state;
    public MissionSidecarDefinition Definition => definition;

    public bool Apply(WorldEvent worldEvent)
    {
        if (worldEvent.Sequence <= state.LastEventSequence)
            return false;
        state.LastEventSequence = worldEvent.Sequence;
        if (state.StartedAtMilliseconds == 0)
            state.StartedAtMilliseconds =
                worldEvent.MonotonicMilliseconds;
        if (state.Status != MissionRunStatus.Running)
            return false;

        var changed = false;
        foreach (var objective in definition.Objectives)
        {
            var runtime = state.Objectives[objective.Id];
            if (runtime.Completed ||
                !DependenciesComplete(objective) ||
                !Matches(objective, worldEvent))
                continue;
            runtime.Count = checked(runtime.Count + Math.Max(1, worldEvent.Value));
            changed = true;
            if (runtime.Count < objective.RequiredCount)
                continue;
            runtime.Completed = true;
            runtime.CompletedAtMilliseconds =
                worldEvent.MonotonicMilliseconds;
            if (objective.Failure)
            {
                state.Status = MissionRunStatus.Failed;
                state.FailureReason =
                    string.IsNullOrWhiteSpace(objective.FailureReason)
                        ? objective.Title
                        : objective.FailureReason;
                return true;
            }
        }

        foreach (var objective in definition.Objectives.Where(item =>
                     item.DeadlineMilliseconds.HasValue &&
                     !state.Objectives[item.Id].Completed &&
                     DependenciesComplete(item)))
        {
            if (worldEvent.MonotonicMilliseconds -
                state.StartedAtMilliseconds <
                objective.DeadlineMilliseconds!.Value)
                continue;
            state.Status = MissionRunStatus.Failed;
            state.FailureReason =
                string.IsNullOrWhiteSpace(objective.FailureReason)
                    ? $"目标“{objective.Title}”超时。"
                    : objective.FailureReason;
            return true;
        }

        var mandatory = definition.Objectives.Where(item =>
            !item.Optional && !item.Failure).ToArray();
        if (mandatory.Length > 0 &&
            mandatory.All(item => state.Objectives[item.Id].Completed))
        {
            state.Status = MissionRunStatus.Succeeded;
            changed = true;
        }
        return changed;
    }

    public MissionView BuildView()
    {
        var objectives = definition.Objectives
            .Where(item => !item.Failure)
            .Select(item =>
            {
                var runtime = state.Objectives[item.Id];
                return new MissionViewObjective(
                    item.Id,
                    item.Title,
                    item.Description,
                    runtime.Count,
                    item.RequiredCount,
                    DependenciesComplete(item),
                    item.Optional,
                    runtime.Completed);
            }).ToArray();
        var active = objectives.FirstOrDefault(item =>
            item.Active && !item.Completed);
        var hint = state.Status switch
        {
            MissionRunStatus.Failed => state.FailureReason,
            MissionRunStatus.Succeeded => "任务完成，可以继续原版关卡流程。",
            _ => active?.Description ?? "等待新的任务阶段。"
        };
        return new MissionView(
            definition.Title,
            state.Status,
            state.FailureReason,
            hint,
            objectives);
    }

    public void ReplaceState(MissionRuntimeState restored)
    {
        ValidateState(restored);
        if (restored.MissionId != definition.Id ||
            restored.DefinitionSha256 != definitionSha256)
            throw new InvalidDataException("读取状态与任务定义不匹配。");
        state = restored;
    }

    public static MissionSidecarDefinition LoadDefinition(string path)
    {
        var definition = JsonSerializer.Deserialize(
            File.ReadAllText(path),
            MissionJsonContext.Default.MissionSidecarDefinition)
            ?? throw new InvalidDataException("sidecar 定义为空。");
        ValidateDefinition(definition);
        return definition;
    }

    public static void ValidateDefinition(
        MissionSidecarDefinition definition)
    {
        if (definition.SchemaVersion != 1 ||
            definition.ApiVersion != 0x00010000)
            throw new InvalidDataException(
                "sidecar schema/API 版本不兼容。");
        if (string.IsNullOrWhiteSpace(definition.Id) ||
            definition.Objectives.Count == 0)
            throw new InvalidDataException(
                "sidecar 必须有 ID 和至少一个目标。");
        var duplicate = definition.Objectives
            .GroupBy(item => item.Id, StringComparer.OrdinalIgnoreCase)
            .FirstOrDefault(group => group.Count() > 1);
        if (duplicate is not null)
            throw new InvalidDataException(
                $"目标 ID 重复：{duplicate.Key}");
        var ids = definition.Objectives
            .Select(item => item.Id)
            .ToHashSet(StringComparer.OrdinalIgnoreCase);
        foreach (var objective in definition.Objectives)
        {
            if (string.IsNullOrWhiteSpace(objective.Id) ||
                string.IsNullOrWhiteSpace(objective.Title) ||
                objective.RequiredCount <= 0)
                throw new InvalidDataException("sidecar 目标字段无效。");
            if (objective.DependsOn.Any(id => !ids.Contains(id)))
                throw new InvalidDataException(
                    $"目标 {objective.Id} 存在未知依赖。");
            if (objective.Region is { Radius: < 0 })
                throw new InvalidDataException(
                    $"目标 {objective.Id} 区域半径无效。");
        }
        var visiting = new HashSet<string>(
            StringComparer.OrdinalIgnoreCase);
        var visited = new HashSet<string>(
            StringComparer.OrdinalIgnoreCase);
        bool Visit(string id)
        {
            if (!visiting.Add(id))
                return false;
            if (visited.Contains(id))
            {
                visiting.Remove(id);
                return true;
            }
            foreach (var dependency in definition.Objectives
                         .Single(item => item.Id.Equals(
                             id, StringComparison.OrdinalIgnoreCase))
                         .DependsOn)
                if (!Visit(dependency))
                    return false;
            visiting.Remove(id);
            visited.Add(id);
            return true;
        }
        if (definition.Objectives.Any(item => !Visit(item.Id)))
            throw new InvalidDataException("sidecar 目标依赖存在环。");
    }

    private bool DependenciesComplete(
        MissionObjectiveDefinition objective) =>
        objective.DependsOn.All(id => state.Objectives[id].Completed);

    private static bool Matches(
        MissionObjectiveDefinition objective,
        WorldEvent worldEvent)
    {
        if (objective.Event != worldEvent.Kind)
            return false;
        if (objective.TargetDatabaseId.HasValue &&
            objective.TargetDatabaseId.Value !=
                worldEvent.SubjectDatabaseId &&
            objective.TargetDatabaseId.Value !=
                worldEvent.ObjectDatabaseId &&
            objective.TargetDatabaseId.Value != worldEvent.ObjectId)
            return false;
        if (objective.SubjectDatabaseId.HasValue &&
            objective.SubjectDatabaseId.Value !=
                worldEvent.SubjectDatabaseId)
            return false;
        if (objective.SubjectFaction.HasValue &&
            objective.SubjectFaction.Value != worldEvent.SubjectFaction)
            return false;
        if (objective.Region is not null)
        {
            var dx = (long)worldEvent.SubjectX - objective.Region.X;
            var dy = (long)worldEvent.SubjectY - objective.Region.Y;
            if (dx * dx + dy * dy >
                (long)objective.Region.Radius * objective.Region.Radius)
                return false;
        }
        return true;
    }

    private static MissionRuntimeState NewState(
        MissionSidecarDefinition definition,
        string definitionSha256) =>
        new()
        {
            MissionId = definition.Id,
            DefinitionSha256 = definitionSha256,
            Objectives = definition.Objectives.ToDictionary(
                item => item.Id,
                item => new ObjectiveRuntimeState { Id = item.Id },
                StringComparer.OrdinalIgnoreCase)
        };

    private void ValidateState(MissionRuntimeState value)
    {
        if (value.SchemaVersion != 1)
            throw new InvalidDataException("任务状态版本不兼容。");
        foreach (var objective in definition.Objectives)
            if (!value.Objectives.ContainsKey(objective.Id))
                throw new InvalidDataException(
                    $"任务状态缺少目标 {objective.Id}。");
    }

    private static string HashDefinition(
        MissionSidecarDefinition definition)
    {
        var json = JsonSerializer.Serialize(
            definition,
            MissionJsonContext.Default.MissionSidecarDefinition);
        return Convert.ToHexString(
            SHA256.HashData(Encoding.UTF8.GetBytes(json)));
    }
}
