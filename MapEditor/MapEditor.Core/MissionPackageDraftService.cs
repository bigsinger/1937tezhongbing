using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace Mission1937.MapEditor.Core;

public enum MissionPackageMode
{
    Redeploy,
    Composite
}

public sealed record MissionPackageDraftOptions
{
    public required string RepositoryRoot { get; init; }
    public required string SourceVwfPath { get; init; }
    public required string Title { get; init; }
    public required string Story { get; init; }
    public MissionPackageMode Mode { get; init; }
    public int EngineMission { get; init; } = 12;
    public required IReadOnlyList<int> PlayerSceneIndices { get; init; }
    public IReadOnlyList<int> EnemySceneIndices { get; init; } = [];
    public IReadOnlyList<int> ObjectiveSceneIndices { get; init; } = [];
    public int? ContactSceneIndex { get; init; }
    public int? ExitSceneIndex { get; init; }
    public int MinimumSpawnEnemyDistanceWorld { get; init; } = 800;
    public int MinimumSpawnPatrolDistanceWorld { get; init; } = 800;
    public double MinimumReachableWalkableRatio { get; init; } = 0.95;
    public int CompositeBlockWidth { get; init; } = 40;
    public int CompositeBlockHeight { get; init; } = 50;
    public string BackgroundAsset { get; init; } = "";
}

public sealed record MissionPackageDraftResult(
    string MissionId,
    int SelectorLevel,
    MissionPackageMode Mode,
    string SourceVwfPath,
    string MissionDirectory,
    string ManifestPath,
    string MissionDefinitionPath,
    string? BlueprintPath,
    string? ComposedWorkFile,
    string? PreviewSourceTerrainPath,
    string RouteDraftPath,
    string SourceSha256,
    string CandidateWorkDirectory);

public static class MissionPackageDraftService
{
    private const string PendingHash =
        "0000000000000000000000000000000000000000000000000000000000000000";

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
        PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower
    };

    public static string FindRepositoryRoot(string startPath)
    {
        var directory = new DirectoryInfo(Path.GetFullPath(startPath));
        if (directory.Exists && !string.IsNullOrEmpty(directory.Extension))
            directory = directory.Parent ??
                throw new DirectoryNotFoundException(startPath);
        for (var depth = 0;
             directory is not null && depth < 12;
             depth++, directory = directory.Parent)
        {
            if (Directory.Exists(Path.Combine(directory.FullName, ".git")) &&
                Directory.Exists(Path.Combine(
                    directory.FullName, "MapEditor", "Missions")) &&
                Directory.Exists(Path.Combine(
                    directory.FullName, "Mod")))
            {
                return directory.FullName;
            }
        }
        throw new DirectoryNotFoundException(
            "未找到同时包含 .git、MapEditor/Missions 和 Mod 的项目根目录。");
    }

    public static string AllocateMissionId(string repositoryRoot)
    {
        var root = Path.GetFullPath(repositoryRoot);
        var missions = Path.Combine(
            root,
            "MapEditor",
            "Missions");
        var maximum = -1;
        if (Directory.Exists(missions))
        {
            foreach (var path in Directory.EnumerateDirectories(
                         missions, "m???", SearchOption.TopDirectoryOnly))
            {
                var name = Path.GetFileName(path);
                if (name.Length == 4 &&
                    int.TryParse(name.AsSpan(1), out var value))
                {
                    maximum = Math.Max(maximum, value);
                }
            }
        }
        var mod = Path.Combine(root, "Mod");
        if (Directory.Exists(mod))
        {
            foreach (var path in Directory.EnumerateFiles(
                         mod,
                         "1937m???.vwf",
                         SearchOption.TopDirectoryOnly))
            {
                var name = Path.GetFileNameWithoutExtension(path);
                if (name.Length == 8 &&
                    int.TryParse(name.AsSpan(5), out var value))
                    maximum = Math.Max(maximum, value);
            }
        }
        return $"m{checked(maximum + 1):D3}";
    }

    public static MissionPackageDraftResult CreateDraft(
        MissionPackageDraftOptions options)
    {
        ArgumentNullException.ThrowIfNull(options);
        var repositoryRoot = Path.GetFullPath(options.RepositoryRoot);
        var sourcePath = Path.GetFullPath(options.SourceVwfPath);
        EnsureInsideRepository(repositoryRoot, sourcePath, "源 VWF");
        if (!File.Exists(sourcePath))
            throw new FileNotFoundException("源 VWF 不存在。", sourcePath);
        if (string.IsNullOrWhiteSpace(options.Title))
            throw new ArgumentException("关卡标题不能为空。");
        if (string.IsNullOrWhiteSpace(options.Story))
            throw new ArgumentException("关卡故事不能为空。");
        if (options.EngineMission is < 1 or > 12)
            throw new ArgumentOutOfRangeException(
                nameof(options.EngineMission),
                "原版任务骨架必须为 1..12。");
        if (options.PlayerSceneIndices.Count == 0)
            throw new ArgumentException("至少选择一个玩家 scene。");
        if (options.MinimumSpawnEnemyDistanceWorld < 0 ||
            options.MinimumSpawnPatrolDistanceWorld < 0 ||
            options.MinimumReachableWalkableRatio is < 0 or > 1)
        {
            throw new ArgumentOutOfRangeException(
                nameof(options),
                "安全距离必须非负，可达率必须为 0..1。");
        }

        var document = OriginalVwfImporter.Import(sourcePath);
        var sceneObjects = document.Objects.ToDictionary(
            item => ParseSceneIndex(item.Id));
        var selectedScenes = options.PlayerSceneIndices
            .Concat(options.EnemySceneIndices)
            .Concat(options.ObjectiveSceneIndices)
            .Concat(options.ContactSceneIndex is int contact
                ? [contact]
                : [])
            .Concat(options.ExitSceneIndex is int exit
                ? [exit]
                : [])
            .Distinct()
            .ToArray();
        foreach (var sceneIndex in selectedScenes)
        {
            if (!sceneObjects.ContainsKey(sceneIndex))
            {
                throw new InvalidDataException(
                    $"所选 scene {sceneIndex} 不存在于源 VWF。");
            }
        }

        var missionId = AllocateMissionId(repositoryRoot);
        var numericId = int.Parse(missionId.AsSpan(1));
        var selectorLevel = checked(numericId + 1);
        var missionDirectory = Path.Combine(
            repositoryRoot, "MapEditor", "Missions", missionId);
        if (Directory.Exists(missionDirectory))
        {
            throw new IOException(
                $"关卡目录已存在，拒绝覆盖：{missionDirectory}");
        }
        Directory.CreateDirectory(missionDirectory);

        try
        {
            var sourceHash = Sha256(sourcePath);
            var sourceRelative = RepositoryRelative(
                repositoryRoot, sourcePath);
            var outputRelative = $"Mod/1937{missionId}.vwf";
            var missionRelative =
                $"MapEditor/Missions/{missionId}/mission.json";
            var reportRelative =
                $"MapEditor/Missions/{missionId}/validation.md";
            var firstPlayer = sceneObjects[
                options.PlayerSceneIndices[0]];
            var requiredReachability = BuildReachabilityTargets(
                options, sceneObjects);

            var mission = new
            {
                id = missionId,
                title = options.Title.Trim(),
                story = options.Story.Trim(),
                source_sha256 = sourceHash,
                player_scene_indices =
                    options.PlayerSceneIndices.Distinct().ToArray(),
                enemy_scene_indices =
                    options.EnemySceneIndices.Distinct().ToArray(),
                minimum_spawn_enemy_distance_world =
                    options.MinimumSpawnEnemyDistanceWorld,
                minimum_spawn_patrol_distance_world =
                    options.MinimumSpawnPatrolDistanceWorld,
                minimum_reachable_walkable_ratio =
                    options.MinimumReachableWalkableRatio,
                player_spawn = new
                {
                    x = firstPlayer.X,
                    y = firstPlayer.Y
                },
                required_scene_reachability = requiredReachability,
                entity_edits = Array.Empty<object>()
            };
            var missionPath = Path.Combine(
                missionDirectory, "mission.json");
            WriteJsonAtomically(missionPath, mission);

            string? blueprintPath = null;
            string? blueprintRelative = null;
            string? compositionReportRelative = null;
            string? composedWorkFile = null;
            string? previewSourceRelative = null;
            string? previewOutputRelative = null;
            if (options.Mode == MissionPackageMode.Composite)
            {
                var blockWidth = options.CompositeBlockWidth;
                var blockHeight = options.CompositeBlockHeight;
                if (blockWidth <= 0 || blockHeight <= 0 ||
                    document.Width % blockWidth != 0 ||
                    document.Height % blockHeight != 0)
                {
                    throw new InvalidDataException(
                        $"合成块 {blockWidth}×{blockHeight} 必须整除地图 " +
                        $"{document.Width}×{document.Height}。");
                }
                var blockCount =
                    checked(document.Width / blockWidth *
                            (document.Height / blockHeight));
                if (blockCount < 2)
                    throw new InvalidDataException(
                        "composite 至少需要两个区块，才能保证所有区块发生换位。");
                var mapping = Enumerable.Range(0, blockCount)
                    .Select(index => (index + 1) % blockCount)
                    .ToArray();
                var blueprint = new
                {
                    id = $"{missionId}-composite",
                    title = $"{options.Title.Trim()}：合成底图",
                    story = "由关卡包向导按区块循环换位生成；所有区块均发生移动。",
                    source_sha256 = sourceHash,
                    block_width = blockWidth,
                    block_height = blockHeight,
                    require_all_blocks_moved = true,
                    destination_to_source_blocks = mapping
                };
                blueprintPath = Path.Combine(
                    missionDirectory, "blueprint.json");
                WriteJsonAtomically(blueprintPath, blueprint);
                blueprintRelative =
                    $"MapEditor/Missions/{missionId}/blueprint.json";
                compositionReportRelative =
                    $"MapEditor/Missions/{missionId}/composition.md";
                composedWorkFile = $"{missionId}-composed.vwf";
                previewSourceRelative = ResolvePreviewSource(
                    repositoryRoot,
                    sourcePath,
                    options.BackgroundAsset);
                previewOutputRelative =
                    $"MapEditor/Assets/Original/maps/{missionId}";
            }

            var manifest = BuildManifest(
                missionId,
                options.Title.Trim(),
                options.Mode,
                selectorLevel,
                options.EngineMission,
                sourceRelative,
                outputRelative,
                missionRelative,
                reportRelative,
                blueprintRelative,
                compositionReportRelative,
                composedWorkFile,
                previewSourceRelative,
                previewOutputRelative);
            var manifestPath = Path.Combine(
                missionDirectory, "mission-package.json");
            WriteJsonNodeAtomically(manifestPath, manifest);

            var routeDraft = new
            {
                schema_version = 1,
                status = "draft_requires_manual_acceptance",
                selector_level = selectorLevel,
                display_name = options.Title.Trim(),
                engine_mission = options.EngineMission,
                runtime_vwf = $"1937{missionId}.VWF".ToUpperInvariant(),
                required_files = new[]
                {
                    $"1937{missionId}.VWF".ToUpperInvariant()
                },
                manifest =
                    $"MapEditor/Missions/{missionId}/mission-package.json",
                note =
                    "候选哈希通过人工验收并发布后，再合并到 SDK/mission-routes.json。"
            };
            var routeDraftPath = Path.Combine(
                missionDirectory, "mission-route.draft.json");
            WriteJsonAtomically(routeDraftPath, routeDraft);
            WriteReadme(
                Path.Combine(missionDirectory, "README.md"),
                missionId,
                options,
                selectorLevel);
            WriteBuildWrapper(
                Path.Combine(missionDirectory, "Build-Mission.ps1"),
                missionId);

            var workRoot = Directory.Exists(@"E:\1937")
                ? @"E:\1937\mission-wizard"
                : Path.Combine(
                    Path.GetTempPath(), "1937-mission-wizard");
            return new MissionPackageDraftResult(
                missionId,
                selectorLevel,
                options.Mode,
                sourcePath,
                missionDirectory,
                manifestPath,
                missionPath,
                blueprintPath,
                composedWorkFile,
                previewSourceRelative is null
                    ? null
                    : Path.Combine(
                        repositoryRoot,
                        previewSourceRelative.Replace(
                            '/',
                            Path.DirectorySeparatorChar)),
                routeDraftPath,
                sourceHash,
                Path.Combine(workRoot, missionId));
        }
        catch
        {
            Directory.Delete(missionDirectory, recursive: true);
            throw;
        }
    }

    public static string CandidateOutputPath(
        MissionPackageDraftResult draft) =>
        Path.Combine(
            draft.CandidateWorkDirectory,
            $"1937{draft.MissionId}.vwf");

    public static string CandidateSha256(
        MissionPackageDraftResult draft)
    {
        var candidate = CandidateOutputPath(draft);
        if (!File.Exists(candidate))
        {
            throw new FileNotFoundException(
                "候选 VWF 尚未生成。", candidate);
        }
        return Sha256(candidate);
    }

    public static void PrepareCompositeMissionHash(
        MissionPackageDraftResult draft,
        string composedVwfPath)
    {
        if (draft.Mode != MissionPackageMode.Composite)
            return;
        if (!File.Exists(composedVwfPath))
        {
            throw new FileNotFoundException(
                "合成候选 VWF 尚未生成。", composedVwfPath);
        }
        var mission = JsonNode.Parse(
            File.ReadAllText(
                draft.MissionDefinitionPath,
                Encoding.UTF8))
            ?.AsObject()
            ?? throw new InvalidDataException("mission.json 无效。");
        mission["source_sha256"] = Sha256(composedVwfPath);
        WriteJsonNodeAtomically(
            draft.MissionDefinitionPath, mission);
    }

    public static void AcceptCandidateHash(
        MissionPackageDraftResult draft,
        string candidateSha256)
    {
        if (!candidateSha256.Equals(
                CandidateSha256(draft),
                StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidDataException(
                "候选哈希与当前工作目录中的 VWF 不一致。");
        }
        if (candidateSha256.Length != 64 ||
            candidateSha256.Any(character =>
                !Uri.IsHexDigit(character)))
        {
            throw new InvalidDataException("候选 SHA-256 格式无效。");
        }
        var manifest = JsonNode.Parse(
            File.ReadAllText(draft.ManifestPath, Encoding.UTF8))
            ?.AsObject()
            ?? throw new InvalidDataException(
                "mission-package.json 无效。");
        if (!string.Equals(
                manifest["expected_output_sha256"]?.GetValue<string>(),
                PendingHash,
                StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidOperationException(
                "清单已经接受过哈希；拒绝隐式覆盖既有基线。");
        }
        manifest["expected_output_sha256"] =
            candidateSha256.ToUpperInvariant();
        WriteJsonNodeAtomically(draft.ManifestPath, manifest);
        var receipt = new
        {
            schema_version = 1,
            mission_id = draft.MissionId,
            accepted_sha256 = candidateSha256.ToUpperInvariant(),
            accepted_at_utc = DateTimeOffset.UtcNow,
            acceptance =
                "manual_confirmation_in_map_editor"
        };
        WriteJsonAtomically(
            Path.Combine(
                draft.MissionDirectory,
                "baseline-acceptance.json"),
            receipt);
    }

    private static JsonObject BuildManifest(
        string missionId,
        string title,
        MissionPackageMode mode,
        int selectorLevel,
        int engineMission,
        string sourceRelative,
        string outputRelative,
        string missionRelative,
        string reportRelative,
        string? blueprintRelative,
        string? compositionReportRelative,
        string? composedWorkFile,
        string? previewSourceRelative,
        string? previewOutputRelative)
    {
        var manifest = new JsonObject
        {
            ["$schema"] = "../mission-package.schema.json",
            ["schema_version"] = 1,
            ["id"] = missionId,
            ["title"] = title,
            ["mode"] = mode == MissionPackageMode.Composite
                ? "composite"
                : "redeploy",
            ["selector_level"] = selectorLevel,
            ["engine_mission"] = engineMission,
            ["runtime_vwf"] =
                $"1937{missionId}.VWF".ToUpperInvariant(),
            ["source_vwf"] = sourceRelative,
            ["output_vwf"] = outputRelative,
            ["mission_definition"] = missionRelative,
            ["mission_report"] = reportRelative,
            ["expected_output_sha256"] = PendingHash
        };
        if (mode == MissionPackageMode.Composite)
        {
            manifest["blueprint_definition"] = blueprintRelative;
            manifest["composition_report"] =
                compositionReportRelative;
            manifest["composed_work_file"] = composedWorkFile;
            manifest["preview_source_terrain"] =
                previewSourceRelative;
            manifest["preview_output_directory"] =
                previewOutputRelative;
        }
        return manifest;
    }

    private static object[] BuildReachabilityTargets(
        MissionPackageDraftOptions options,
        IReadOnlyDictionary<int, MapObject> objects)
    {
        var targets = new List<(string Role, int Scene)>();
        if (options.ContactSceneIndex is int contact)
            targets.Add(("接头对象", contact));
        targets.AddRange(options.ObjectiveSceneIndices
            .Select(scene => ("任务目标", scene)));
        if (options.ExitSceneIndex is int exit)
            targets.Add(("撤离点", exit));
        return targets
            .DistinctBy(item => item.Scene)
            .Select(item => (object)new
            {
                name =
                    $"{item.Role}：{objects[item.Scene].Name}",
                scene_index = item.Scene
            })
            .ToArray();
    }

    private static string ResolvePreviewSource(
        string repositoryRoot,
        string sourcePath,
        string backgroundAsset)
    {
        if (!string.IsNullOrWhiteSpace(backgroundAsset))
        {
            var candidate = Path.Combine(
                repositoryRoot,
                "MapEditor",
                "Assets",
                "Original",
                backgroundAsset.Replace('/', Path.DirectorySeparatorChar));
            if (File.Exists(candidate))
                return RepositoryRelative(repositoryRoot, candidate);
        }
        var name = Path.GetFileNameWithoutExtension(sourcePath);
        var levelId = name.Length >= 4
            ? name[^4..].ToLowerInvariant()
            : "";
        var fallback = Path.Combine(
            repositoryRoot,
            "MapEditor",
            "Assets",
            "Original",
            "maps",
            levelId,
            "terrain.png");
        if (!File.Exists(fallback))
        {
            throw new FileNotFoundException(
                "composite 需要可定位的 terrain.png 生成局部预览。",
                fallback);
        }
        return RepositoryRelative(repositoryRoot, fallback);
    }

    private static int ParseSceneIndex(string id)
    {
        if (id.StartsWith("scene-", StringComparison.Ordinal) &&
            int.TryParse(id.AsSpan(6), out var value))
            return value;
        throw new InvalidDataException(
            $"原生对象 ID 不是 scene-N 格式：{id}");
    }

    private static void EnsureInsideRepository(
        string repositoryRoot,
        string path,
        string description)
    {
        var rootPrefix = repositoryRoot.TrimEnd(
            Path.DirectorySeparatorChar,
            Path.AltDirectorySeparatorChar) +
            Path.DirectorySeparatorChar;
        if (!path.StartsWith(
                rootPrefix,
                StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidDataException(
                $"{description}必须位于 Git 项目内，确保他人可复现构建。");
        }
    }

    private static string RepositoryRelative(
        string repositoryRoot,
        string path) =>
        Path.GetRelativePath(repositoryRoot, path)
            .Replace(Path.DirectorySeparatorChar, '/');

    private static string Sha256(string path)
    {
        using var stream = File.OpenRead(path);
        return Convert.ToHexString(SHA256.HashData(stream));
    }

    private static void WriteJsonAtomically<T>(
        string path,
        T value) =>
        WriteTextAtomically(
            path,
            JsonSerializer.Serialize(value, JsonOptions) +
            Environment.NewLine);

    private static void WriteJsonNodeAtomically(
        string path,
        JsonNode value) =>
        WriteTextAtomically(
            path,
            value.ToJsonString(JsonOptions) +
            Environment.NewLine);

    private static void WriteTextAtomically(
        string path,
        string content)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        var temporary = path + $".tmp.{Environment.ProcessId}";
        try
        {
            File.WriteAllText(
                temporary,
                content,
                new UTF8Encoding(encoderShouldEmitUTF8Identifier: false));
            File.Move(temporary, path, overwrite: true);
        }
        finally
        {
            if (File.Exists(temporary))
                File.Delete(temporary);
        }
    }

    private static void WriteReadme(
        string path,
        string missionId,
        MissionPackageDraftOptions options,
        int selectorLevel)
    {
        var mode = options.Mode == MissionPackageMode.Composite
            ? "composite"
            : "redeploy";
        WriteTextAtomically(
            path,
            $"# {options.Title.Trim()}\n\n" +
            $"{options.Story.Trim()}\n\n" +
            $"- 关卡包：`{missionId}`\n" +
            $"- 选择器关卡：{selectorLevel}\n" +
            $"- 原版任务骨架：{options.EngineMission}\n" +
            $"- 构建模式：`{mode}`\n\n" +
            "先在地图编辑器向导中生成候选并检查报告；" +
            "只有勾选人工确认后，候选 SHA-256 才会写入清单并发布。\n");
    }

    private static void WriteBuildWrapper(
        string path,
        string missionId) =>
        WriteTextAtomically(
            path,
            "[CmdletBinding()]\n" +
            "param([string]$WorkDirectory = '')\n" +
            "$arguments = @{" +
            $" MissionId = '{missionId}'; " +
            "RepositoryRoot = [IO.Path]::GetFullPath(" +
            "(Join-Path $PSScriptRoot '..\\..\\..')) }\n" +
            "if (-not [string]::IsNullOrWhiteSpace($WorkDirectory)) " +
            "{ $arguments.WorkDirectory = $WorkDirectory }\n" +
            "& (Join-Path $arguments.RepositoryRoot " +
            "'MapEditor\\tools\\Build-MissionPackage.ps1') @arguments\n" +
            "exit $LASTEXITCODE\n");
}
