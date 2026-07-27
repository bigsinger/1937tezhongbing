using System.Reflection;
using System.Runtime.Loader;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;

namespace Mission1937.MapEditor.Core;

public sealed record MapInterchangeContext(
    string SourcePath,
    string? AssetRoot,
    IReadOnlyDictionary<string, string> Options);

public interface IMapInterchangePlugin
{
    int ApiVersion { get; }
    string Id { get; }
    string DisplayName { get; }
    IReadOnlyList<string> ImportExtensions { get; }
    IReadOnlyList<string> ExportExtensions { get; }
    MapDocument Import(string path, MapInterchangeContext context);
    void Export(
        MapDocument document,
        string path,
        MapInterchangeContext context);
}

public sealed record MapInterchangePluginInfo(
    string Id,
    string DisplayName,
    int ApiVersion,
    bool Compatible,
    string Source);

public sealed class MapInterchangeRegistry
{
    public const int CurrentApiVersion = 1;
    private readonly Dictionary<string, IMapInterchangePlugin> plugins =
        new(StringComparer.OrdinalIgnoreCase);
    private readonly List<MapInterchangePluginInfo> inventory = [];

    public MapInterchangeRegistry()
    {
        Add(new MapJsonInterchangePlugin(), "内置");
        Add(new MissionSidecarInterchangePlugin(), "内置");
    }

    public IReadOnlyList<IMapInterchangePlugin> Plugins =>
        plugins.Values.OrderBy(item => item.DisplayName).ToArray();

    public IReadOnlyList<MapInterchangePluginInfo> Inventory => inventory;

    public void Discover(string pluginDirectory)
    {
        if (!Directory.Exists(pluginDirectory))
            return;
        foreach (var path in Directory.EnumerateFiles(
                     pluginDirectory, "*.dll"))
        {
            try
            {
                var assembly = AssemblyLoadContext.Default.LoadFromAssemblyPath(
                    Path.GetFullPath(path));
                foreach (var type in assembly.GetTypes().Where(type =>
                             !type.IsAbstract &&
                             typeof(IMapInterchangePlugin)
                                 .IsAssignableFrom(type)))
                {
                    if (Activator.CreateInstance(type) is
                        IMapInterchangePlugin plugin)
                        Add(plugin, path);
                }
            }
            catch (Exception exception)
            {
                inventory.Add(new MapInterchangePluginInfo(
                    Path.GetFileNameWithoutExtension(path),
                    exception.GetType().Name,
                    0,
                    false,
                    path));
            }
        }
    }

    public IMapInterchangePlugin FindForImport(string path) =>
        Find(path, plugin => plugin.ImportExtensions);

    public IMapInterchangePlugin FindForExport(string path) =>
        Find(path, plugin => plugin.ExportExtensions);

    private void Add(IMapInterchangePlugin plugin, string source)
    {
        var compatible = plugin.ApiVersion == CurrentApiVersion;
        inventory.Add(new MapInterchangePluginInfo(
            plugin.Id,
            plugin.DisplayName,
            plugin.ApiVersion,
            compatible,
            source));
        if (!compatible)
            return;
        if (!plugins.TryAdd(plugin.Id, plugin))
            throw new InvalidDataException(
                $"地图导入/导出插件 ID 重复：{plugin.Id}");
    }

    private IMapInterchangePlugin Find(
        string path,
        Func<IMapInterchangePlugin, IReadOnlyList<string>> extensions)
    {
        var fileName = Path.GetFileName(path);
        return Plugins
                   .SelectMany(plugin => extensions(plugin).Select(
                       extension => (plugin, extension)))
                   .Where(candidate => fileName.EndsWith(
                       candidate.extension,
                       StringComparison.OrdinalIgnoreCase))
                   .OrderByDescending(candidate =>
                       candidate.extension.Length)
                   .Select(candidate => candidate.plugin)
                   .FirstOrDefault()
               ?? throw new NotSupportedException(
                   $"没有插件支持文件 {fileName}。");
    }
}

public sealed class MapJsonInterchangePlugin : IMapInterchangePlugin
{
    public int ApiVersion => 1;
    public string Id => "m1937.map-json";
    public string DisplayName => "M1937 地图工程 JSON";
    public IReadOnlyList<string> ImportExtensions => [".json", ".m37map"];
    public IReadOnlyList<string> ExportExtensions => [".json", ".m37map"];

    public MapDocument Import(
        string path,
        MapInterchangeContext context) =>
        MapDocumentSerializer.Load(path);

    public void Export(
        MapDocument document,
        string path,
        MapInterchangeContext context) =>
        MapDocumentSerializer.Save(document, path);
}

public sealed class MissionSidecarInterchangePlugin : IMapInterchangePlugin
{
    private static readonly HashSet<string> SupportedEvents =
    [
        "MissionStarted",
        "Reached",
        "Killed",
        "PickedUp",
        "Exploded",
        "Interacted",
        "Evacuated",
        "MissionSucceeded",
        "MissionFailed",
        "SaveStarted",
        "SaveCompleted",
        "LoadStarted",
        "LoadCompleted"
    ];

    public int ApiVersion => 1;
    public string Id => "m1937.mission-sidecar";
    public string DisplayName => "M1937 任务 Sidecar";
    public IReadOnlyList<string> ImportExtensions =>
        [".m1937mission.json", ".m1937mission"];
    public IReadOnlyList<string> ExportExtensions =>
        [".m1937mission.json", ".m1937mission"];

    public MapDocument Import(
        string path,
        MapInterchangeContext context)
    {
        using var json = JsonDocument.Parse(File.ReadAllText(path));
        var root = json.RootElement;
        if (root.GetProperty("schema_version").GetInt32() != 1)
            throw new InvalidDataException("不支持的 sidecar schema。");
        if (!root.TryGetProperty("api_version", out var apiVersion) ||
            apiVersion.GetUInt32() != 0x00010000)
            throw new InvalidDataException("不支持的 sidecar API。");
        var document = MapDocument.Create(
            root.TryGetProperty("title", out var title)
                ? title.GetString() ?? "Sidecar 任务"
                : "Sidecar 任务",
            64,
            48);
        CopyMetadata(root, document, "id");
        CopyMetadata(root, document, "selector_level");
        CopyMetadata(root, document, "engine_mission");
        CopyMetadata(root, document, "executable_sha256");
        CopyMetadata(root, document, "executable_file_size");
        CopyMetadata(root, document, "executable_pe_timestamp");
        document.Tasks.Clear();
        foreach (var objective in root
                     .GetProperty("objectives").EnumerateArray())
        {
            document.Tasks.Add(new MissionTask
            {
                Id = Text(objective, "id"),
                Title = Text(objective, "title"),
                Description = Text(objective, "description"),
                Trigger = Text(objective, "event"),
                TargetObjectId = DatabaseReference(
                    objective, "target_database_id"),
                RequiredCount = objective.TryGetProperty(
                    "required_count", out var count)
                    ? count.GetInt32() : 1,
                DependsOn = objective.TryGetProperty(
                    "depends_on", out var dependencies)
                    ? dependencies.EnumerateArray()
                        .Select(value => value.GetString() ?? "")
                        .Where(value => value.Length > 0)
                        .ToList()
                    : [],
                Optional = objective.TryGetProperty(
                    "optional", out var optional) && optional.GetBoolean(),
                FailureReason = Text(objective, "failure_reason"),
                FailureCondition = objective.TryGetProperty(
                    "failure", out var failure) && failure.GetBoolean(),
                TargetDatabaseId = UInt32(
                    objective, "target_database_id"),
                SubjectDatabaseId = UInt32(
                    objective, "subject_database_id"),
                SubjectFaction = Int32(
                    objective, "subject_faction"),
                RegionX = RegionInt32(objective, "x"),
                RegionY = RegionInt32(objective, "y"),
                RegionRadius = RegionInt32(objective, "radius"),
                DeadlineMilliseconds = Int32(
                    objective, "deadline_milliseconds")
            });
        }
        MapValidator.ThrowIfInvalid(document);
        return document;
    }

    public void Export(
        MapDocument document,
        string path,
        MapInterchangeContext context)
    {
        var selectorLevel = MetadataInt(
            document, context, "selector_level", 13);
        var engineMission = MetadataInt(
            document, context, "engine_mission", 12);
        var missionId = Metadata(
            document, context, "id",
            SafeId(document.Name));
        if (!Regex.IsMatch(missionId, "^[A-Za-z0-9_.-]{1,80}$"))
            throw new InvalidDataException(
                "任务 Sidecar ID 只能包含英文字母、数字、点、下划线或连字符，且最多 80 个字符。");
        if (selectorLevel is < 1 or > 15)
            throw new InvalidDataException(
                "selector_level 必须在 1 到 15 之间。");
        if (engineMission is < 1 or > 12)
            throw new InvalidDataException(
                "engine_mission 必须在 1 到 12 之间。");

        var objectives = document.Tasks.Select(task =>
        {
            if (!Regex.IsMatch(
                    task.Id ?? "",
                    "^[A-Za-z0-9_.-]{1,80}$"))
                throw new InvalidDataException(
                    $"任务 ID“{task.Id}”不符合 Sidecar 命名规则。");
            var eventName = NormalizeEvent(task.Trigger);
            var targetDatabaseId =
                task.TargetDatabaseId ??
                ResolveDatabaseId(document, task.TargetObjectId);
            object? region = null;
            if (task.RegionX.HasValue ||
                task.RegionY.HasValue ||
                task.RegionRadius.HasValue)
            {
                if (!task.RegionX.HasValue ||
                    !task.RegionY.HasValue ||
                    !task.RegionRadius.HasValue ||
                    task.RegionRadius.Value < 0)
                    throw new InvalidDataException(
                        $"任务 {task.Id} 的区域必须完整填写 x/y/radius。");
                region = new
                {
                    x = task.RegionX.Value,
                    y = task.RegionY.Value,
                    radius = task.RegionRadius.Value
                };
            }
            return new
            {
                id = task.Id,
                title = task.Title,
                description = EmptyToNull(task.Description),
                @event = eventName,
                depends_on = task.DependsOn.Count > 0
                    ? task.DependsOn : null,
                required_count = task.RequiredCount == 1
                    ? (int?)null : task.RequiredCount,
                optional = task.Optional ? true : (bool?)null,
                failure = task.FailureCondition ? true : (bool?)null,
                failure_reason = EmptyToNull(task.FailureReason),
                target_database_id = targetDatabaseId,
                subject_database_id = task.SubjectDatabaseId,
                subject_faction = task.SubjectFaction,
                region,
                deadline_milliseconds = task.DeadlineMilliseconds
            };
        }).ToArray();
        var payload = new
        {
            schema_version = 1,
            api_version = 0x00010000,
            id = missionId,
            title = document.Name,
            selector_level = selectorLevel,
            engine_mission = engineMission,
            executable_sha256 = EmptyToNull(Metadata(
                document, context, "executable_sha256", "")),
            executable_file_size = MetadataNullableLong(
                document, context, "executable_file_size"),
            executable_pe_timestamp = MetadataNullableLong(
                document, context, "executable_pe_timestamp"),
            objectives
        };
        AtomicJson(
            path,
            JsonSerializer.Serialize(payload, new JsonSerializerOptions
            {
                WriteIndented = true,
                DefaultIgnoreCondition =
                    JsonIgnoreCondition.WhenWritingNull
            }));
    }

    private static void AtomicJson(string path, string content)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(
            Path.GetFullPath(path))!);
        var temporary = path + ".tmp";
        File.WriteAllText(temporary, content);
        using (JsonDocument.Parse(File.ReadAllText(temporary)))
        {
        }
        File.Move(temporary, path, true);
    }

    private static string Text(JsonElement value, string name) =>
        value.TryGetProperty(name, out var property)
            ? property.GetString() ?? ""
            : "";

    private static void CopyMetadata(
        JsonElement source,
        MapDocument document,
        string name)
    {
        if (source.TryGetProperty(name, out var value))
            document.Metadata[name] = value.ValueKind == JsonValueKind.String
                ? value.GetString() ?? ""
                : value.GetRawText();
    }

    private static uint? UInt32(JsonElement value, string name) =>
        value.TryGetProperty(name, out var property)
            ? property.GetUInt32()
            : null;

    private static int? Int32(JsonElement value, string name) =>
        value.TryGetProperty(name, out var property)
            ? property.GetInt32()
            : null;

    private static int? RegionInt32(JsonElement value, string name) =>
        value.TryGetProperty("region", out var region) &&
        region.TryGetProperty(name, out var property)
            ? property.GetInt32()
            : null;

    private static string DatabaseReference(
        JsonElement value,
        string name) =>
        UInt32(value, name) is { } id ? $"db:{id}" : "";

    private static uint? ResolveDatabaseId(
        MapDocument document,
        string reference)
    {
        if (string.IsNullOrWhiteSpace(reference))
            return null;
        var objectMatch = document.Objects.FirstOrDefault(item =>
            item.Id.Equals(reference, StringComparison.OrdinalIgnoreCase));
        if (objectMatch is not null)
        {
            foreach (var propertyName in new[]
                     {
                         "database_entry_id",
                         "database_id"
                     })
            {
                if (objectMatch.Properties.TryGetValue(
                        propertyName, out var databaseId) &&
                    uint.TryParse(databaseId, out var parsedObjectId))
                    return parsedObjectId;
            }
        }
        var normalized = Regex.Replace(
            reference.Trim(),
            "^(db|database):",
            "",
            RegexOptions.IgnoreCase);
        return uint.TryParse(normalized, out var parsed)
            ? parsed
            : throw new InvalidDataException(
                $"任务目标引用“{reference}”既不是对象 ID，也不是 db:数字。");
    }

    private static string NormalizeEvent(string value)
    {
        var match = SupportedEvents.FirstOrDefault(item =>
            item.Equals(value, StringComparison.OrdinalIgnoreCase));
        if (match is not null)
            return match;
        return value.Trim().ToLowerInvariant() switch
        {
            "level_start" or "mission_start" => "MissionStarted",
            "arrival" or "reach" => "Reached",
            "kill" => "Killed",
            "pickup" or "pick_up" => "PickedUp",
            "explode" or "destroy" => "Exploded",
            "interact" => "Interacted",
            "evacuation" or "evacuate" => "Evacuated",
            "success" or "mission_success" => "MissionSucceeded",
            "failure" or "mission_failure" => "MissionFailed",
            "save_start" => "SaveStarted",
            "save_complete" => "SaveCompleted",
            "load_start" => "LoadStarted",
            "load_complete" => "LoadCompleted",
            _ => throw new InvalidDataException(
                $"Sidecar 不支持任务事件“{value}”。")
        };
    }

    private static string? EmptyToNull(string value) =>
        string.IsNullOrWhiteSpace(value) ? null : value;

    private static string Metadata(
        MapDocument document,
        MapInterchangeContext context,
        string key,
        string fallback)
    {
        if (context.Options.TryGetValue(key, out var option))
            return option;
        return document.Metadata.TryGetValue(key, out var value)
            ? value
            : fallback;
    }

    private static int MetadataInt(
        MapDocument document,
        MapInterchangeContext context,
        string key,
        int fallback) =>
        int.TryParse(
            Metadata(document, context, key, fallback.ToString()),
            out var value)
            ? value
            : throw new InvalidDataException($"{key} 不是有效整数。");

    private static long? MetadataNullableLong(
        MapDocument document,
        MapInterchangeContext context,
        string key)
    {
        var value = Metadata(document, context, key, "");
        if (string.IsNullOrWhiteSpace(value))
            return null;
        return long.TryParse(value, out var parsed) && parsed >= 0
            ? parsed
            : throw new InvalidDataException($"{key} 不是有效非负整数。");
    }

    private static string SafeId(string value)
    {
        var safe = Regex.Replace(value, "[^A-Za-z0-9_.-]", "-").Trim('-');
        if (safe.Length == 0)
            safe = "community-mission";
        return safe.Length <= 80 ? safe : safe[..80];
    }
}
