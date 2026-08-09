using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using Mission1937.Remake.Resources;

namespace Mission1937.MapEditor.Core;

public sealed record NativeContentPackExportResult(
    string OutputPath,
    string PackId,
    string LevelId,
    string PackageSha256,
    int ObjectCount,
    int ObjectiveCount,
    IReadOnlyList<MapIssue> QualityIssues);

/// <summary>
/// One-click export from the editor's semantic document to the Remake-native,
/// declarative .m1937pack format. It never writes back to a VWF and it never
/// carries executable files into a package.
/// </summary>
public static class NativeContentPackExporter
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
        PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower,
        Converters = { new JsonStringEnumConverter(JsonNamingPolicy.SnakeCaseLower) }
    };

    public static NativeContentPackExportResult Export(
        MapDocument document,
        string outputPath,
        string? assetRoot = null)
    {
        ArgumentNullException.ThrowIfNull(document);
        var issues = MapQualityAnalyzer.Analyze(document);
        var errors = issues.Where(issue => issue.Severity == MapIssueSeverity.Error).ToArray();
        if (errors.Length > 0)
            throw new InvalidDataException(
                "地图质量检查未通过：" +
                string.Join("；", errors.Select(issue => $"{issue.Code}: {issue.Message}")));

        var output = Path.GetFullPath(outputPath);
        if (!output.EndsWith(M1937Pack.Extension, StringComparison.OrdinalIgnoreCase))
            throw new ArgumentException($"输出文件必须使用 {M1937Pack.Extension}。", nameof(outputPath));
        var levelId = SafeIdentifier(document.Metadata.GetValueOrDefault("level_id"), "level");
        var packId = SafePackId(
            document.Metadata.GetValueOrDefault("pack_id"),
            "user.mapeditor." + levelId);
        var stage = Path.Combine(
            Path.GetTempPath(),
            "m1937-pack-export-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(stage);
        try
        {
            var levelRoot = Path.Combine(stage, "levels", levelId);
            Directory.CreateDirectory(levelRoot);
            var assetPaths = CopyReferencedAssets(document, stage, assetRoot);
            var entities = BuildEntities(document, assetPaths);
            var navigation = BuildNavigation(document);
            navigation.Save(Path.Combine(levelRoot, "navigation.bin"));
            WriteJson(
                Path.Combine(levelRoot, "level.json"),
                BuildLevel(document, entities));
            var mission = BuildMission(document, levelId);
            WriteJson(Path.Combine(levelRoot, "mission.json"), mission);
            WriteJson(
                Path.Combine(levelRoot, "direction.json"),
                new
                {
                    schema_version = 1,
                    level_id = levelId,
                    sequences = Array.Empty<object>()
                });

            var terrainRelative = CopyTerrain(document, stage, assetRoot);
            WriteJson(
                Path.Combine(stage, "campaign.json"),
                new
                {
                    schema_version = 1,
                    display_name = document.Name,
                    levels = new[]
                    {
                        new
                        {
                            id = levelId,
                            number = ParsePositive(document.Metadata.GetValueOrDefault("number"), 1),
                            title = document.Name,
                            level = $"levels/{levelId}/level.json",
                            mission = $"levels/{levelId}/mission.json",
                            direction = $"levels/{levelId}/direction.json",
                            terrain = terrainRelative
                        }
                    }
                });
            var manifest = new M1937PackManifest
            {
                PackId = packId,
                Version = document.Metadata.GetValueOrDefault("version", "1.0.0"),
                DisplayName = document.Name,
                MinimumRuntimeVersion = "1.0.0",
                LevelEntries = [$"levels/{levelId}/level.json"],
                SourceDeclaration = document.Metadata.GetValueOrDefault(
                    "source_declaration",
                    "Created by 1937 MapEditor from user-authored content."),
                Capabilities = [
                    "terrain", "navigation", "line_of_sight", "mission",
                    "actors", "patrols", "doors", "pickups", "failures"
                ]
            };
            WriteText(
                Path.Combine(stage, "manifest.json"),
                M1937Pack.ManifestJson(manifest));
            var validation = M1937Pack.Build(stage, output);
            return new NativeContentPackExportResult(
                output,
                packId,
                levelId,
                validation.PackageSha256,
                // Report authored objects, not generated mission anchors.  The
                // latter are an implementation detail and previously made a
                // one-object map appear to contain two editor objects.
                document.Objects.Count,
                document.Tasks.Count(task => !task.FailureCondition),
                issues);
        }
        finally
        {
            if (Directory.Exists(stage))
                Directory.Delete(stage, recursive: true);
        }
    }

    private static List<object> BuildEntities(
        MapDocument document,
        IReadOnlyDictionary<string, string> assetPaths)
    {
        var objects = document.Objects
            .OrderBy(value => value.Id, StringComparer.Ordinal)
            .ToArray();
        var result = new List<object>(objects.Length);
        for (var index = 0; index < objects.Length; index++)
        {
            var item = objects[index];
            var sceneIndex = ParseSceneIndex(item.Id, index + 1);
            var x = checked(item.X * document.EffectiveCellWidth + document.EffectiveCellWidth / 2);
            var y = checked(item.Y * document.EffectiveCellHeight + document.EffectiveCellHeight / 2);
            var factionId = FactionId(item.Faction);
            var runtimeRole = RuntimeRole(item, factionId);
            result.Add(new
            {
                scene_index = sceneIndex,
                database_entry_id = ParseNonNegative(item.Properties.GetValueOrDefault("database_entry_id"), 0),
                resource_name = string.IsNullOrWhiteSpace(item.AssetPath) ? "synthetic" : Path.GetFileName(item.AssetPath),
                display_name = item.Name,
                category_name = item.IsLiving ? "角色" : item.Category,
                x,
                y,
                reference_x = x,
                reference_y = y,
                sprite_preview = assetPaths.TryGetValue(item.Id, out var asset)
                    ? "../../" + asset
                    : "",
                sprite_anchor = new { x = 0, y = 0 },
                database_header_values = new[] { 0, 0, ParseNonNegative(item.Properties.GetValueOrDefault("runtime_actor_type"), 0) },
                patrol_waypoints = item.PatrolWaypoints.Select(point => new
                {
                    x = checked(point.X * document.EffectiveCellWidth + document.EffectiveCellWidth / 2),
                    y = checked(point.Y * document.EffectiveCellHeight + document.EffectiveCellHeight / 2)
                }).ToArray(),
                patrol = new
                {
                    current_waypoint_index = Math.Max(0, item.PatrolCurrentWaypointIndex),
                    persistent_flag = item.PatrolEnabled ? 1 : 0
                },
                faction_id = factionId,
                direction_index = Math.Max(0, item.Direction),
                death_state = 0,
                crawl_state = 0,
                current_hit_points = ParsePositive(item.Properties.GetValueOrDefault("hit_points"), 8),
                default_attack_type = Math.Clamp(ParseNonNegative(item.Properties.GetValueOrDefault("attack_type"), 2), 0, 11),
                runtime_role = runtimeRole,
                runtime_actor_type = ParseNonNegative(item.Properties.GetValueOrDefault("runtime_actor_type"), runtimeRole == "scenery" ? 0 : 1),
                source_object_id = item.Id,
                native_interaction = BuildNativeInteraction(item, runtimeRole)
            });
        }
        var zoneTasks = document.Tasks
            .Where(task => !task.FailureCondition && task.RegionX is not null && task.RegionY is not null)
            .ToArray();
        for (var index = 0; index < zoneTasks.Length; index++)
        {
            var task = zoneTasks[index];
            var x = task.RegionX!.Value * document.EffectiveCellWidth + document.EffectiveCellWidth / 2;
            var y = task.RegionY!.Value * document.EffectiveCellHeight + document.EffectiveCellHeight / 2;
            result.Add(new
            {
                scene_index = 900000 + index,
                database_entry_id = 1020,
                resource_name = "native_exit_detector",
                display_name = "检测出口精灵",
                category_name = "任务触发器",
                x,
                y,
                reference_x = x,
                reference_y = y,
                sprite_preview = "",
                sprite_anchor = new { x = 0, y = 0 },
                database_header_values = new[] { 0, 0, 0 },
                patrol_waypoints = Array.Empty<object>(),
                patrol = new { current_waypoint_index = 0, persistent_flag = 0 },
                faction_id = 0,
                direction_index = 1,
                death_state = 0,
                crawl_state = 0,
                current_hit_points = 1,
                default_attack_type = 0,
                runtime_role = "scenery",
                runtime_actor_type = 0,
                source_object_id = task.Id
            });
        }
        return result;
    }

    private static object BuildLevel(MapDocument document, IReadOnlyList<object> entities) => new
    {
        schema_version = 1,
        world_size = new
        {
            width = checked(document.Width * document.EffectiveCellWidth),
            height = checked(document.Height * document.EffectiveCellHeight)
        },
        tile_size = new
        {
            width = document.EffectiveCellWidth,
            height = document.EffectiveCellHeight
        },
        terrain_image = "package-or-generated",
        entities,
        task_anchors = document.Tasks
            .Where(task => task.RegionX is not null && task.RegionY is not null)
            .Select((task, index) => new
            {
                scene_index = 900000 + index,
                database_entry_id = 0,
                kind = "exit_detector",
                x = task.RegionX!.Value * document.EffectiveCellWidth + document.EffectiveCellWidth / 2,
                y = task.RegionY!.Value * document.EffectiveCellHeight + document.EffectiveCellHeight / 2,
                reference_x = task.RegionX.Value * document.EffectiveCellWidth + document.EffectiveCellWidth / 2,
                reference_y = task.RegionY.Value * document.EffectiveCellHeight + document.EffectiveCellHeight / 2
            }).ToArray(),
        navigation = new
        {
            schema_version = 1,
            relative_path = "navigation.bin",
            width = document.Width,
            height = document.Height,
            cell_width = document.EffectiveCellWidth,
            cell_height = document.EffectiveCellHeight,
            layer_ids = new
            {
                line_of_sight_obstacle = 2,
                movement_obstacle = 3,
                event_layer = 4,
                manual_movement_correction = 5
            }
        }
    };

    private static dynamic BuildMission(MapDocument document, string levelId)
    {
        var objectives = document.Tasks
            .Where(task => !task.FailureCondition)
            .Select(task => (object)new
            {
                id = SafeIdentifier(task.Id, "objective"),
                label = task.Title,
                required = !task.Optional,
                depends_on = task.DependsOn.Select(value => SafeIdentifier(value, "objective")).ToArray(),
                condition = new
                {
                    @event = string.IsNullOrWhiteSpace(task.Trigger) ? "trigger_activated" : task.Trigger,
                    where = BuildTaskFilter(task),
                    required_count = Math.Max(1, task.RequiredCount),
                    unique_by = string.IsNullOrWhiteSpace(task.TargetObjectId) ? "" : "source_object_id"
                }
            }).ToArray();
        var failures = document.Tasks
            .Where(task => task.FailureCondition)
            .Select(task => (object)new
            {
                id = SafeIdentifier(task.Id, "failure"),
                @event = string.IsNullOrWhiteSpace(task.Trigger) ? "required_character_lost" : task.Trigger
            }).ToArray();
        return new
        {
            schema_version = 1,
            id = levelId,
            number = ParsePositive(document.Metadata.GetValueOrDefault("number"), 1),
            title = document.Name,
            time_limit_seconds = document.Tasks
                .Where(task => task.DeadlineMilliseconds is > 0)
                .Select(task => task.DeadlineMilliseconds!.Value / 1000)
                .DefaultIfEmpty(0)
                .Max(),
            scene_bindings = new Dictionary<string, int[]>
            {
                ["exit"] = document.Tasks
                    .Where(task => !task.FailureCondition && task.RegionX is not null && task.RegionY is not null)
                    .Select((_, index) => 900000 + index)
                    .ToArray()
            },
            objectives,
            failure_conditions = failures
        };
    }

    private static Dictionary<string, object> BuildTaskFilter(MissionTask task)
    {
        var where = new Dictionary<string, object>(StringComparer.Ordinal);
        if (!string.IsNullOrWhiteSpace(task.TargetObjectId))
            where["source_object_id"] = task.TargetObjectId;
        if (task.TargetDatabaseId is not null)
            where["database_entry_id"] = task.TargetDatabaseId.Value;
        if (task.SubjectFaction is not null)
            where["faction_id"] = task.SubjectFaction.Value;
        return where;
    }

    private static VwfNavigationGrid BuildNavigation(MapDocument document)
    {
        uint[] Layer(EditorLayerKind kind) =>
            document.Layer(kind).Cells.Select(value => checked((uint)Math.Max(0, value))).ToArray();
        var lineOfSight = Layer(EditorLayerKind.LineOfSightObstacle);
        var movement = Layer(EditorLayerKind.MovementObstacle);
        var orderedObjects = document.Objects
            .OrderBy(value => value.Id, StringComparer.Ordinal)
            .ToArray();
        for (var index = 0; index < orderedObjects.Length; index++)
        {
            var item = orderedObjects[index];
            if (RuntimeRole(item, FactionId(item.Faction)) != "door" ||
                item.X < 0 || item.X >= document.Width ||
                item.Y < 0 || item.Y >= document.Height)
                continue;
            // Native navigation uses the same reversible source encoding as
            // imported VWF layers. Opening scene N disables value N+1000 in
            // both L3 movement and L2 line-of-sight without rebuilding A*.
            var sceneIndex = ParseSceneIndex(item.Id, index + 1);
            var encoded = checked((uint)(sceneIndex + 1000));
            var cellIndex = document.Index(item.X, item.Y);
            movement[cellIndex] = encoded;
            lineOfSight[cellIndex] = encoded;
        }
        return VwfNavigationGrid.Create(
            checked((uint)document.Width),
            checked((uint)document.Height),
            checked((uint)document.EffectiveCellWidth),
            checked((uint)document.EffectiveCellHeight),
            new Dictionary<VwfSemanticLayer, IReadOnlyList<uint>>
            {
                [VwfSemanticLayer.LineOfSightObstacle] = lineOfSight,
                [VwfSemanticLayer.MovementObstacle] = movement,
                [VwfSemanticLayer.Event] = Layer(EditorLayerKind.Event),
                [VwfSemanticLayer.ManualMovementCorrection] = Layer(EditorLayerKind.ManualMovementCorrection)
            });
    }

    private static Dictionary<string, string> CopyReferencedAssets(
        MapDocument document,
        string stage,
        string? assetRoot)
    {
        var copied = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (var item in document.Objects.OrderBy(value => value.Id, StringComparer.Ordinal))
        {
            var source = ResolveAsset(item.AssetPath, assetRoot);
            if (source is null)
                continue;
            var extension = Path.GetExtension(source).ToLowerInvariant();
            if (extension is not (".png" or ".webp" or ".jpg" or ".jpeg"))
                continue;
            var hash = Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(source)))
                .ToLowerInvariant();
            var relative = $"assets/sprites/{hash}{extension}";
            var target = Path.Combine(stage, relative.Replace('/', Path.DirectorySeparatorChar));
            Directory.CreateDirectory(Path.GetDirectoryName(target)!);
            if (!File.Exists(target))
                File.Copy(source, target);
            copied[item.Id] = relative;
        }
        return copied;
    }

    private static string CopyTerrain(MapDocument document, string stage, string? assetRoot)
    {
        var source = ResolveAsset(document.BackgroundAsset, assetRoot);
        if (source is null)
            return "";
        var extension = Path.GetExtension(source).ToLowerInvariant();
        if (extension is not (".png" or ".webp" or ".jpg" or ".jpeg"))
            return "";
        var relative = "assets/terrain" + extension;
        var target = Path.Combine(stage, relative.Replace('/', Path.DirectorySeparatorChar));
        Directory.CreateDirectory(Path.GetDirectoryName(target)!);
        File.Copy(source, target, overwrite: true);
        return relative;
    }

    private static string? ResolveAsset(string value, string? assetRoot)
    {
        if (string.IsNullOrWhiteSpace(value))
            return null;
        var candidates = Path.IsPathRooted(value)
            ? new[] { value }
            : new[]
            {
                assetRoot is null ? "" : Path.Combine(assetRoot, value),
                Path.GetFullPath(value)
            };
        return candidates
            .Where(path => !string.IsNullOrWhiteSpace(path))
            .Select(Path.GetFullPath)
            .FirstOrDefault(File.Exists);
    }

    private static string RuntimeRole(MapObject item, int factionId)
    {
        var explicitRole = item.Properties.GetValueOrDefault("runtime_role")?
            .Trim().ToLowerInvariant();
        if (explicitRole is "player" or "enemy" or "ambient" or "escort" or
            "scenery" or "pickup" or "door" or "trigger")
            return explicitRole;
        var kind = item.Kind.Trim().ToLowerInvariant();
        if (kind is "door" or "gate")
            return "door";
        if (kind is "pickup" or "item")
            return "pickup";
        if (kind is "trigger")
            return "trigger";
        if (!item.IsLiving)
            return "scenery";
        return factionId switch
        {
            3 => "player",
            1 => "enemy",
            2 => "ambient",
            _ => "ambient"
        };
    }

    private static Dictionary<string, object> BuildNativeInteraction(
        MapObject item,
        string runtimeRole)
    {
        switch (runtimeRole)
        {
            case "door":
            {
                var startsOpen = ParseBoolean(
                    item.Properties.GetValueOrDefault("starts_open"), false);
                return new Dictionary<string, object>(StringComparer.Ordinal)
                {
                    ["kind"] = "door",
                    ["starts_open"] = startsOpen,
                    ["locked_open"] = startsOpen && ParseBoolean(
                        item.Properties.GetValueOrDefault("locked_open"), startsOpen)
                };
            }
            case "pickup":
            {
                var inventoryKind = item.Properties
                    .GetValueOrDefault("original_inventory_kind")?
                    .Trim().ToLowerInvariant();
                if (inventoryKind is not ("backpack" or "weapon"))
                    inventoryKind = "backpack";
                // 83 is the original cigarette/lure backpack item and is
                // accepted by Remake's authoritative inventory catalogue.
                var itemId = ParsePositive(
                    item.Properties.GetValueOrDefault("item_id"), 83);
                return new Dictionary<string, object>(StringComparer.Ordinal)
                {
                    ["kind"] = "pickup",
                    ["original_inventory_kind"] = inventoryKind,
                    ["item_id"] = itemId,
                    ["original_actor_type"] = itemId,
                    ["quantity"] = ParsePositive(
                        item.Properties.GetValueOrDefault("quantity"), 1),
                    ["quantity_mode"] = ParseNonNegative(
                        item.Properties.GetValueOrDefault("quantity_mode"), 0),
                    ["attack_type"] = Math.Clamp(ParseNonNegative(
                        item.Properties.GetValueOrDefault("attack_type"), 0), 0, 11),
                    ["item_name"] = item.Properties.GetValueOrDefault("item_name") ?? item.Name
                };
            }
            case "trigger":
                return new Dictionary<string, object>(StringComparer.Ordinal)
                {
                    ["kind"] = "trigger"
                };
            default:
                return new Dictionary<string, object>(StringComparer.Ordinal);
        }
    }

    private static int FactionId(string value) => value.ToLowerInvariant() switch
    {
        "player" or "faction-3" or "3" => 3,
        "enemy" or "faction-1" or "1" => 1,
        "neutral" or "faction-2" or "2" => 2,
        _ => 0
    };

    private static int ParseSceneIndex(string id, int fallback)
    {
        var digits = new string(id.Where(char.IsDigit).ToArray());
        return int.TryParse(digits, out var value) && value >= 0 ? value : fallback;
    }

    private static int ParsePositive(string? value, int fallback) =>
        int.TryParse(value, out var parsed) && parsed > 0 ? parsed : fallback;

    private static int ParseNonNegative(string? value, int fallback) =>
        int.TryParse(value, out var parsed) && parsed >= 0 ? parsed : fallback;

    private static bool ParseBoolean(string? value, bool fallback) =>
        string.Equals(value, "1", StringComparison.Ordinal) ||
        (bool.TryParse(value, out var parsed) ? parsed : fallback);

    private static string SafeIdentifier(string? value, string fallback)
    {
        var source = string.IsNullOrWhiteSpace(value) ? fallback : value;
        var normalized = new string(source.ToLowerInvariant()
            .Select(character => char.IsAsciiLetterOrDigit(character) || character is '_' or '-'
                ? character
                : '-')
            .ToArray()).Trim('-');
        return string.IsNullOrWhiteSpace(normalized) ? fallback : normalized[..Math.Min(48, normalized.Length)];
    }

    private static string SafePackId(string? value, string fallback)
    {
        var normalized = SafeIdentifier((value ?? fallback).Replace('.', '-'), "user-map");
        return "user." + normalized;
    }

    private static void WriteJson(string path, object value) =>
        WriteText(path, JsonSerializer.Serialize(value, JsonOptions));

    private static void WriteText(string path, string value)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, value + Environment.NewLine, new UTF8Encoding(false));
    }
}
