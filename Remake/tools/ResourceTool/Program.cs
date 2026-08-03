using System.Diagnostics;
using System.Text.Json;
using Mission1937.Remake.Resources;

namespace Mission1937.Remake.ResourceTool;

internal static class Program
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
        PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower
    };

    public static int Main(string[] args)
    {
        try
        {
            return Run(args);
        }
        catch (Exception exception) when (
            exception is IOException or UnauthorizedAccessException or ArgumentException or InvalidDataException)
        {
            Console.Error.WriteLine($"Error: {exception.Message}");
            return 2;
        }
    }

    private static int Run(string[] args)
    {
        if (args.Length == 0 || args[0] is "help" or "--help" or "-h")
        {
            PrintUsage();
            return args.Length == 0 ? 1 : 0;
        }

        return args[0].ToLowerInvariant() switch
        {
            "inspect" => Inspect(args),
            "inspect-dbl" => InspectDbl(args),
            "inspect-vwf" => InspectVwf(args),
            "inspect-save" => InspectSave(args),
            "import-save" => ImportSave(args),
            "world-pickup-baseline" => WorldPickupBaseline(args),
            "list-gfl" => ListGfl(args),
            "extract-gfl" => ExtractGfl(args),
            "strip-briefings" => StripBriefings(args),
            "prune-retired-briefings" => PruneRetiredBriefings(args),
            "render-text-briefings" => RenderTextBriefings(args),
            "install-text-briefings" => InstallTextBriefings(args),
            "import" => Import(args),
            "media-catalog" => MediaCatalog(args),
            _ => UnknownCommand(args[0])
        };
    }

    private static int WorldPickupBaseline(string[] args)
    {
        RequireArgumentCount(
            args,
            3,
            3,
            "world-pickup-baseline <1937db.dbl> <output.json>");
        var databasePath = System.IO.Path.GetFullPath(args[1]);
        var outputPath = System.IO.Path.GetFullPath(args[2]);
        var database = DblDatabase.Open(databasePath);
        var evidence = OriginalWorldPickupEvidence.Recover(database);
        var document = new
        {
            schema_version = 1,
            catalog_id = "original-world-pickups-v1",
            content_profile = "repository-mod-12-level-20260729",
            source = new
            {
                database_file = System.IO.Path.GetFileName(databasePath),
                database_sha256 = Convert.ToHexString(
                    System.Security.Cryptography.SHA256.HashData(
                        File.ReadAllBytes(databasePath))),
                runtime_item_id = "DBL sprite header[2]",
                container_and_quantity_mode = "M1937.exe sub_45AE10",
                grant_quantity = "M1937.exe sub_453F70",
            },
            pickup_grants = evidence.PickupGrants,
            explosive_props = new[] { evidence.GasolineBarrel },
        };
        var outputDirectory = System.IO.Path.GetDirectoryName(outputPath);
        if (!string.IsNullOrEmpty(outputDirectory))
        {
            Directory.CreateDirectory(outputDirectory);
        }
        File.WriteAllText(
            outputPath,
            JsonSerializer.Serialize(document, JsonOptions),
            new System.Text.UTF8Encoding(encoderShouldEmitUTF8Identifier: false));
        Console.WriteLine(
            $"Recovered {evidence.PickupGrants.Count} world pickups and " +
            $"gasoline barrel {evidence.GasolineBarrel.DatabaseEntryId}.");
        Console.WriteLine($"Wrote: {outputPath}");
        return 0;
    }

    private static int InspectVwf(string[] args)
    {
        RequireArgumentCount(
            args,
            2,
            8,
            "inspect-vwf <path.vwf> [1937db.dbl] [--entities] [--patrols] [--extended] [--auxiliary] [--scene=N]");
        var vwfPath = System.IO.Path.GetFullPath(args[1]);
        var entityDetails = args.Any(argument =>
            argument.Equals(
                "--entities",
                StringComparison.OrdinalIgnoreCase));
        var patrolDetails = args.Any(argument =>
            argument.Equals(
                "--patrols",
                StringComparison.OrdinalIgnoreCase));
        var extendedDetails = args.Any(argument =>
            argument.Equals(
                "--extended",
                StringComparison.OrdinalIgnoreCase));
        var auxiliaryDetails = args.Any(argument =>
            argument.Equals(
                "--auxiliary",
                StringComparison.OrdinalIgnoreCase));
        var sceneArgument = args.FirstOrDefault(argument =>
            argument.StartsWith(
                "--scene=",
                StringComparison.OrdinalIgnoreCase));
        int? sceneFilter = null;
        if (sceneArgument is not null)
        {
            if (!int.TryParse(sceneArgument["--scene=".Length..], out var parsedScene)
                || parsedScene < 0)
            {
                throw new ArgumentException(
                    $"Invalid scene filter '{sceneArgument}'. Expected --scene=<non-negative integer>.");
            }
            sceneFilter = parsedScene;
        }
        var databaseArgument = args
            .Skip(2)
            .FirstOrDefault(argument =>
                !argument.Equals(
                    "--entities",
                    StringComparison.OrdinalIgnoreCase) &&
                !argument.Equals(
                    "--patrols",
                    StringComparison.OrdinalIgnoreCase) &&
                !argument.Equals(
                    "--extended",
                    StringComparison.OrdinalIgnoreCase) &&
                !argument.Equals(
                    "--auxiliary",
                    StringComparison.OrdinalIgnoreCase) &&
                !argument.StartsWith(
                    "--scene=",
                    StringComparison.OrdinalIgnoreCase));
        DblDatabase? database = databaseArgument is not null
            ? DblDatabase.Open(System.IO.Path.GetFullPath(databaseArgument))
            : null;
        var world = VwfWorldHeader.Open(vwfPath);
        var terrain = VwfTerrainGrid.Open(vwfPath, database);
        var sceneList = VwfSceneList.Open(vwfPath, database);
        var selectedEntities = sceneList.Entities
            .Where(entity =>
                sceneFilter is null || entity.SceneIndex == sceneFilter.Value)
            .ToArray();
        if (sceneFilter is not null && selectedEntities.Length == 0)
        {
            throw new InvalidDataException(
                $"Scene {sceneFilter.Value} is not a present entity slot in {vwfPath}.");
        }
        var factionCounts = sceneList.Entities
            .GroupBy(entity => entity.ExtendedFields.Count > 8 ? entity.ExtendedFields[8] : 0)
            .OrderBy(group => group.Key)
            .ToDictionary(group => group.Key, group => group.Count());

        Console.WriteLine($"Path: {vwfPath}");
        Console.WriteLine($"Length: {new FileInfo(vwfPath).Length}");
        Console.WriteLine($"Grid: {world.GridWidth}x{world.GridHeight}");
        Console.WriteLine(
            $"World pixels: {checked(world.GridWidth * 32)}x{checked(world.GridHeight * 16)}");
        Console.WriteLine(
            $"Viewport: {world.ViewportWidth}x{world.ViewportHeight} " +
            $"({world.ViewportLeft},{world.ViewportTop})-({world.ViewportRight},{world.ViewportBottom})");
        Console.WriteLine($"Terrain layers: {terrain.Layers.Count}");
        Console.WriteLine($"SLIST1 offset: 0x{world.SceneListOffset:X}");
        Console.WriteLine(
            $"SLIST1: version {sceneList.FormatVersion}, slots {sceneList.SlotCount}, " +
            $"entities {sceneList.Entities.Count}, empty {sceneList.EmptySlotCount}");
        Console.WriteLine(
            "Factions: " +
            string.Join(", ", factionCounts.Select(pair => $"{pair.Key}={pair.Value}")));
        var patrolEntities = sceneList.Entities
            .Where(entity => entity.Patrol is not null)
            .ToArray();
        var totalPatrolPoints = patrolEntities.Sum(
            entity => entity.Patrol!.Waypoints.Count);
        var maximumPatrolPoints = patrolEntities.Length == 0
            ? 0
            : patrolEntities.Max(
                entity => entity.Patrol!.Waypoints.Count);
        Console.WriteLine(
            $"Patrols: actors {patrolEntities.Length}, " +
            $"points {totalPatrolPoints}, max {maximumPatrolPoints}");
        if (entityDetails)
        {
            Console.WriteLine(
                "Entities: scene,database_id,world_x,world_y,reference_x,reference_y,direction,faction,death");
            foreach (var entity in selectedEntities)
            {
                var faction = entity.ExtendedFields.Count > 8
                    ? entity.ExtendedFields[8]
                    : 0;
                Console.WriteLine(
                    $"  {entity.SceneIndex},{entity.DatabaseEntryId}," +
                    $"{entity.WorldX},{entity.WorldY}," +
                    $"{entity.ReferenceX},{entity.ReferenceY}," +
                    $"{entity.DirectionIndex},{faction},{entity.DeathState}");
            }
        }
        if (patrolDetails)
        {
            Console.WriteLine(
                "Patrols: scene,current,persistent,cached_x,cached_y,waypoints");
            foreach (var entity in patrolEntities.Where(entity =>
                         sceneFilter is null || entity.SceneIndex == sceneFilter.Value))
            {
                var patrol = entity.Patrol!;
                Console.WriteLine(
                    $"  {entity.SceneIndex}," +
                    $"{patrol.CurrentWaypointIndex}," +
                    $"{patrol.PersistentFlag}," +
                    $"{patrol.CachedWaypointWorldX}," +
                    $"{patrol.CachedWaypointWorldY}," +
                    string.Join(
                        ";",
                        patrol.Waypoints.Select(
                            point => $"{point.X}:{point.Y}")));
            }
        }
        if (extendedDetails)
        {
            Console.WriteLine(
                "Extended fields: scene,database_id,presence,field_0..field_40");
            foreach (var entity in selectedEntities)
            {
                Console.WriteLine(
                    $"  {entity.SceneIndex},{entity.DatabaseEntryId}," +
                    $"{entity.ExtendedDataPresence}," +
                    string.Join(",", entity.ExtendedFields));
            }
        }
        if (auxiliaryDetails)
        {
            Console.WriteLine(
                "Auxiliary entries: scene,array,index,item_id,quantity,quantity_mode");
            foreach (var entity in selectedEntities)
            {
                for (var arrayIndex = 0;
                     arrayIndex < entity.AuxiliaryArrays.Count;
                     arrayIndex++)
                {
                    var entries = entity.AuxiliaryArrays[arrayIndex];
                    for (var entryIndex = 0; entryIndex < entries.Count; entryIndex++)
                    {
                        var entry = entries[entryIndex];
                        Console.WriteLine(
                            $"  {entity.SceneIndex},{arrayIndex},{entryIndex}," +
                            $"{entry.ItemId},{entry.Quantity},{entry.QuantityMode}");
                    }
                }
            }
        }
        return 0;
    }

    private static int InspectSave(string[] args)
    {
        RequireArgumentCount(
            args,
            3,
            6,
            "inspect-save <path.SAV> <game-directory> [1937db.dbl] [M1937.SI#] [--entities]");
        var savePath = System.IO.Path.GetFullPath(args[1]);
        var gameDirectory = System.IO.Path.GetFullPath(args[2]);
        var entityDetails = args.Any(argument =>
            argument.Equals(
                "--entities",
                StringComparison.OrdinalIgnoreCase));
        var databaseArgument = args
            .Skip(3)
            .FirstOrDefault(argument =>
                argument.EndsWith(
                    ".dbl",
                    StringComparison.OrdinalIgnoreCase));
        var defaultDatabasePath = System.IO.Path.Combine(
            gameDirectory,
            "1937Database.dbl");
        DblDatabase? database = null;
        if (databaseArgument is not null)
        {
            database = DblDatabase.Open(
                System.IO.Path.GetFullPath(databaseArgument));
        }
        else if (File.Exists(defaultDatabasePath))
        {
            database = DblDatabase.Open(defaultDatabasePath);
        }

        var previewArgument = args
            .Skip(3)
            .FirstOrDefault(argument =>
                System.IO.Path.GetFileName(argument).StartsWith(
                    "M1937.SI",
                    StringComparison.OrdinalIgnoreCase));
        LegacySavePreview? preview = previewArgument is null
            ? null
            : LegacySavePreview.Open(
                System.IO.Path.GetFullPath(previewArgument));
        var snapshot = LegacySaveSnapshot.Open(
            savePath,
            gameDirectory,
            database);
        var actorStates = snapshot.SceneList.Entities
            .Where(entity =>
                entity.HasExtendedData &&
                (entity.AuxiliaryArrays[0].Count > 0 ||
                 entity.AuxiliaryArrays[1].Count > 0 ||
                 entity.CurrentHitPoints > 0))
            .ToArray();

        Console.WriteLine($"Save: {snapshot.Path}");
        Console.WriteLine(
            $"Level: {snapshot.Level.LevelId} " +
            $"(selector {snapshot.Level.LevelIndex + 1})");
        Console.WriteLine(
            $"Terrain SHA-256: {snapshot.Level.TerrainSha256}");
        Console.WriteLine(
            $"Camera viewport: " +
            $"({snapshot.World.ViewportLeft},{snapshot.World.ViewportTop})-" +
            $"({snapshot.World.ViewportRight},{snapshot.World.ViewportBottom})");
        Console.WriteLine(
            $"Scenes: base {snapshot.BaseSceneList.Entities.Count}, " +
            $"saved {snapshot.SceneList.Entities.Count}, " +
            $"removed {snapshot.RemovedSceneIndices.Count}, " +
            $"added {snapshot.AddedEntities.Count}, " +
            $"changed {snapshot.ChangedEntities.Count}");
        Console.WriteLine(
            $"State-bearing entities: {actorStates.Length}");
        if (preview is not null)
        {
            Console.WriteLine(
                $"Preview: {preview.Image.Width}x{preview.Image.Height} " +
                $"{preview.Image.BitsPerPixel}-bit RGB565, " +
                $"alpha={preview.Image.HasAlphaPlane}");
        }

        if (entityDetails)
        {
            Console.WriteLine(
                "Changed entities: scene,db,reference_x,reference_y,direction,death,crawl,hp,backpack,weapon");
            var savedByScene = snapshot.SceneList.Entities.ToDictionary(
                entity => entity.SceneIndex);
            foreach (var change in snapshot.ChangedEntities)
            {
                var saved = savedByScene[change.SceneIndex];
                Console.WriteLine(
                    $"  {saved.SceneIndex},{saved.DatabaseEntryId}," +
                    $"{saved.ReferenceX},{saved.ReferenceY}," +
                    $"{saved.DirectionIndex},{saved.DeathState}," +
                    $"{saved.CrawlState},{saved.CurrentHitPoints}," +
                    $"{saved.AuxiliaryArrays[0].Count}," +
                    $"{saved.AuxiliaryArrays[1].Count}");
            }
            Console.WriteLine(
                "Removed scenes: " +
                string.Join(",", snapshot.RemovedSceneIndices));
            Console.WriteLine(
                "Added scenes: " +
                string.Join(
                    ",",
                    snapshot.AddedEntities.Select(
                        entity =>
                            $"{entity.SceneIndex}:{entity.DatabaseEntryId}")));
        }

        return 0;
    }

    private static int ImportSave(string[] args)
    {
        RequireArgumentCount(
            args,
            4,
            7,
            "import-save <path.SAV> <game-directory> <output.json> [M1937.SI#] [--slot=legacy_N] [--data-dir=<Remake/game/data>]");
        var savePath = System.IO.Path.GetFullPath(args[1]);
        var gameDirectory = System.IO.Path.GetFullPath(args[2]);
        var outputPath = System.IO.Path.GetFullPath(args[3]);
        var slotArgument = args
            .Skip(4)
            .FirstOrDefault(argument =>
                argument.StartsWith(
                    "--slot=",
                    StringComparison.OrdinalIgnoreCase));
        var slotId = slotArgument is null
            ? $"legacy_{System.IO.Path.GetFileNameWithoutExtension(savePath).ToLowerInvariant()}"
            : slotArgument["--slot=".Length..];
        var dataDirectoryArgument = args
            .Skip(4)
            .FirstOrDefault(argument =>
                argument.StartsWith(
                    "--data-dir=",
                    StringComparison.OrdinalIgnoreCase));
        var dataDirectory = dataDirectoryArgument is null
            ? System.IO.Path.GetFullPath(
                System.IO.Path.Combine(
                    "Remake",
                    "game",
                    "data"))
            : System.IO.Path.GetFullPath(
                dataDirectoryArgument["--data-dir=".Length..]);
        var previewArgument = args
            .Skip(4)
            .FirstOrDefault(argument =>
                !argument.StartsWith(
                    "--",
                    StringComparison.Ordinal) &&
                System.IO.Path.GetFileName(argument).StartsWith(
                    "M1937.SI",
                    StringComparison.OrdinalIgnoreCase));
        var preview = previewArgument is null
            ? null
            : LegacySavePreview.Open(
                System.IO.Path.GetFullPath(previewArgument));
        var databasePath = System.IO.Path.Combine(
            gameDirectory,
            "1937Database.dbl");
        var database = DblDatabase.Open(databasePath);
        var snapshot = LegacySaveSnapshot.Open(
            savePath,
            gameDirectory,
            database);
        var result = LegacySaveImporter.Build(
            snapshot,
            dataDirectory,
            slotId,
            preview);

        var outputDirectory = System.IO.Path.GetDirectoryName(
            outputPath);
        if (!string.IsNullOrEmpty(outputDirectory))
        {
            Directory.CreateDirectory(outputDirectory);
        }
        File.WriteAllText(
            outputPath,
            result.Document.ToJsonString(JsonOptions) +
                Environment.NewLine,
            new System.Text.UTF8Encoding(
                encoderShouldEmitUTF8Identifier: false));
        if (preview is not null)
        {
            preview.Image.SavePng(
                System.IO.Path.ChangeExtension(
                    outputPath,
                    ".preview.png"));
        }

        Console.WriteLine(
            $"Imported original {snapshot.Level.LevelId} save as slot '{slotId}'.");
        Console.WriteLine(
            $"Actors {result.ActorCount}, dynamic enemies {result.DynamicEnemyCount}, " +
            $"buried {result.BuriedEnemyCount}, remaining pickups {result.RemainingPickupCount}, " +
            $"inferred objectives {result.InferredObjectiveCount}.");
        Console.WriteLine($"Wrote: {outputPath}");
        if (preview is not null)
        {
            Console.WriteLine(
                "Preview: " +
                System.IO.Path.ChangeExtension(
                    outputPath,
                    ".preview.png"));
        }
        return 0;
    }

    private static int Inspect(string[] args)
    {
        RequireArgumentCount(args, 2, 2, "inspect <game-directory>");
        var report = GameDirectoryProbe.Inspect(args[1]);

        Console.WriteLine($"Directory: {report.DirectoryPath}");
        Console.WriteLine($"Plausible original directory: {report.IsPlausibleOriginalDirectory}");
        Console.WriteLine($"Supported content profile: {report.KnownVersion.VersionId}");
        Console.WriteLine($"Supported content hashes match: {report.KnownVersion.IsMatch}");
        Console.WriteLine($"Formal VWF levels: {report.FormalLevelCount}/12");
        Console.WriteLine($"Files: {report.Files.Count}");

        if (report.ResourceArchive is not null)
        {
            Console.WriteLine($"GFL entries: {report.ResourceArchive.EntryCount}");
            Console.WriteLine($"Decoded GFL names: {report.ResourceArchive.NamedEntryCount}");
            foreach (var pair in report.ResourceArchive.TypeCounts)
            {
                Console.WriteLine($"  {pair.Key,-8} {pair.Value,4}");
            }
        }

        if (report.SoundLibrary is not null)
        {
            Console.WriteLine(
                $"SLF sounds mapped to GFL: {report.SoundLibrary.MappedToGflCount}/{report.SoundLibrary.EntryCount}");
        }

        foreach (var level in report.Levels)
        {
            Console.WriteLine(
                $"  {level.Name}: grid {level.GridWidth}x{level.GridHeight}, " +
                $"SLIST1 at 0x{level.SceneListOffset:X}");
        }

        foreach (var warning in report.Warnings)
        {
            Console.WriteLine($"Warning: {warning}");
        }

        return report.IsPlausibleOriginalDirectory ? 0 : 3;
    }

    private static int InspectDbl(string[] args)
    {
        RequireArgumentCount(
            args,
            2,
            4,
            "inspect-dbl <1937Database.dbl> [--id=N] [--runtime-type=N]");
        foreach (var argument in args.Skip(2))
        {
            if (!argument.StartsWith("--id=", StringComparison.OrdinalIgnoreCase) &&
                !argument.StartsWith(
                    "--runtime-type=",
                    StringComparison.OrdinalIgnoreCase))
            {
                throw new ArgumentException(
                    $"Unknown inspect-dbl filter '{argument}'. " +
                    "Expected --id=N or --runtime-type=N.");
            }
        }
        var database = DblDatabase.Open(args[1]);
        int? entryId = ParseOptionalNonNegativeFilter(args, "--id=");
        int? runtimeType = ParseOptionalNonNegativeFilter(args, "--runtime-type=");
        var entries = database.Entries
            .Where(entry => entryId is null || entry.Id == entryId.Value)
            .Where(entry =>
                runtimeType is null ||
                entry.HeaderValues.Count > 2 &&
                entry.HeaderValues[2] == checked((uint)runtimeType.Value))
            .ToArray();

        Console.WriteLine($"Path: {database.Path}");
        Console.WriteLine($"Format version: {database.FormatVersion}");
        Console.WriteLine($"Matched entries: {entries.Length}");
        Console.WriteLine(
            "Entries: id,kind,runtime_type,resource_name,display_name,category,element_count,headers");
        foreach (var entry in entries)
        {
            var resolvedRuntimeType = entry.HeaderValues.Count > 2
                ? entry.HeaderValues[2].ToString()
                : string.Empty;
            Console.WriteLine(
                $"  {entry.Id},{entry.Kind},{resolvedRuntimeType}," +
                $"{entry.ResourceName},{entry.DisplayName},{entry.CategoryName}," +
                $"{entry.ElementCount},[{string.Join(',', entry.HeaderValues)}]");
        }
        return entries.Length > 0 ? 0 : 3;
    }

    private static int? ParseOptionalNonNegativeFilter(
        string[] args,
        string prefix)
    {
        var matches = args
            .Skip(2)
            .Where(argument => argument.StartsWith(prefix, StringComparison.OrdinalIgnoreCase))
            .ToArray();
        if (matches.Length > 1)
        {
            throw new ArgumentException($"Filter '{prefix}' may be supplied only once.");
        }
        if (matches.Length == 0)
        {
            return null;
        }
        var valueText = matches[0][prefix.Length..];
        if (!int.TryParse(valueText, out var value) || value < 0)
        {
            throw new ArgumentException(
                $"Invalid filter '{matches[0]}'. Expected {prefix}<non-negative integer>.");
        }
        return value;
    }

    private static int ListGfl(string[] args)
    {
        RequireArgumentCount(
            args,
            2,
            4,
            "list-gfl <1937Resources.GFL> [InterMedia.GFL] [--all]");
        var listAll = args.Any(argument =>
            argument.Equals(
                "--all",
                StringComparison.OrdinalIgnoreCase));
        var indexArgument = args
            .Skip(2)
            .FirstOrDefault(argument =>
                !argument.Equals(
                    "--all",
                    StringComparison.OrdinalIgnoreCase));
        var archive = GflArchive.Open(args[1], indexArgument);
        foreach (var group in archive.Entries.GroupBy(entry => entry.Type).OrderByDescending(group => group.Count()))
        {
            Console.WriteLine($"{group.Key,-8} {group.Count(),4} entries, {group.Sum(entry => (long)entry.Length),12} bytes");
        }

        Console.WriteLine($"Total: {archive.Entries.Count} entries");
        foreach (var entry in listAll
                     ? archive.Entries
                     : archive.Entries.Take(10))
        {
            Console.WriteLine(
                $"  {entry.Index:D4} {entry.Type,-8} " +
                $"{entry.Length,9} {entry.OriginalName}");
        }
        return 0;
    }

    private static int ExtractGfl(string[] args)
    {
        RequireArgumentCount(
            args,
            3,
            4,
            "extract-gfl <1937Resources.GFL> <output-directory> [InterMedia.GFL]");
        var outputDirectory = System.IO.Path.GetFullPath(args[2]);
        EnsureOutputIsGitIgnoredIfNecessary(outputDirectory);
        var archive = GflArchive.Open(args[1], args.Length == 4 ? args[3] : null);
        var extracted = archive.ExtractAll(outputDirectory);
        WriteJson(System.IO.Path.Combine(outputDirectory, "gfl-manifest.json"), new
        {
            schema_version = 1,
            source_name = System.IO.Path.GetFileName(args[1]),
            entries = extracted
        });
        Console.WriteLine($"Extracted {extracted.Count} entries to {outputDirectory}");
        return 0;
    }

    private static int StripBriefings(string[] args)
    {
        RequireArgumentCount(
            args,
            5,
            5,
            "strip-briefings <1937Resources.GFL> <InterMedia.GFL> " +
            "<output-resources.GFL> <output-index.GFL>");
        var report = GflArchiveRewriter.RemoveLegacyBriefingPayloads(
            args[1],
            args[2],
            args[3],
            args[4]);
        Console.WriteLine(
            $"Preserved {report.EntryCount} resource indexes.");
        Console.WriteLine(
            "Cleared briefing payload indexes: " +
            string.Join(", ", report.ClearedEntryIndexes));
        Console.WriteLine(
            $"Removed {report.RemovedPayloadBytes} bytes; " +
            $"resource archive is now {report.OutputResourceBytes} bytes.");
        return 0;
    }

    private static int RenderTextBriefings(string[] args)
    {
        RequireArgumentCount(
            args,
            3,
            3,
            "render-text-briefings <关卡名称.json> <output-directory>");
        var briefings = TextBriefingRenderer.RenderCatalog(args[1]);
        TextBriefingRenderer.WritePreviewDirectory(
            briefings,
            args[2],
            includeIBlock: true);
        Console.WriteLine(
            $"Rendered {briefings.Count} in-game text briefings to " +
            Path.GetFullPath(args[2]));
        return 0;
    }

    private static int PruneRetiredBriefings(string[] args)
    {
        RequireArgumentCount(
            args,
            5,
            5,
            "prune-retired-briefings <1937Resources.GFL> <InterMedia.GFL> " +
            "<output-resources.GFL> <output-index.GFL>");
        var report = GflArchivePruner.RemoveTrailingEntries(
            args[1],
            args[2],
            args[3],
            args[4],
            ["Brief_012.psd", "Brief_013.psd", "Brief_014.psd"]);
        Console.WriteLine(
            $"Removed {string.Join(", ", report.RemovedNames)}.");
        Console.WriteLine(
            $"Preserved {report.EntryCount} original numeric indexes; " +
            $"archive size is {report.OutputResourceBytes} bytes.");
        return 0;
    }

    private static int InstallTextBriefings(string[] args)
    {
        RequireArgumentCount(
            args,
            6,
            7,
            "install-text-briefings <关卡名称.json> " +
            "<source-resources.GFL> <source-index.GFL> " +
            "<output-resources.GFL> <output-index.GFL> " +
            "[preview-directory]");
        var briefings = TextBriefingRenderer.RenderCatalog(args[1]);
        if (args.Length == 7)
        {
            TextBriefingRenderer.WritePreviewDirectory(
                briefings,
                args[6],
                includeIBlock: false);
        }
        var payloads = briefings.ToDictionary(
            briefing => briefing.ResourceName,
            briefing => briefing.IBlock,
            StringComparer.OrdinalIgnoreCase);
        var report = GflPayloadInstaller.Install(
            args[2],
            args[3],
            args[4],
            args[5],
            payloads,
            "Intro_000.psd");
        Console.WriteLine(
            $"Installed {report.ReplacedNames.Count} replacement and " +
            $"{report.AddedNames.Count} appended text briefings.");
        Console.WriteLine(
            $"Preserved {report.EntryCount} GFL resource indexes; " +
            $"archive size is {report.OutputResourceBytes} bytes.");
        return 0;
    }

    private static int Import(string[] args)
    {
        RequireArgumentCount(args, 3, 3, "import <game-directory> <output-directory>");

        var gameDirectory = System.IO.Path.GetFullPath(args[1]);
        var outputDirectory = System.IO.Path.GetFullPath(args[2]);
        EnsureOutputIsOutsideSource(gameDirectory, outputDirectory);
        EnsureOutputIsGitIgnoredIfNecessary(outputDirectory);

        var report = GameDirectoryProbe.Inspect(gameDirectory);
        if (!report.IsPlausibleOriginalDirectory)
        {
            throw new InvalidDataException("The selected directory does not match the expected original layout.");
        }
        if (!report.KnownVersion.IsMatch)
        {
            throw new InvalidDataException(
                "The selected directory does not match a supported original or stable Mod content profile. " +
                "Run inspect for the mismatched filenames before adding support for another release.");
        }

        Directory.CreateDirectory(outputDirectory);
        var gflPath = System.IO.Path.Combine(gameDirectory, "1937Resources.GFL");
        var gflIndexPath = System.IO.Path.Combine(gameDirectory, "InterMedia.GFL");
        var rawOutput = System.IO.Path.Combine(outputDirectory, "raw", "gfl");
        var archive = GflArchive.Open(gflPath, File.Exists(gflIndexPath) ? gflIndexPath : null);
        var extracted = archive.ExtractAll(rawOutput);
        var conversion = OriginalAssetConverter.Convert(
            gameDirectory,
            outputDirectory,
            archive,
            extracted);

        WriteJson(System.IO.Path.Combine(outputDirectory, "manifest.json"), new
        {
            schema_version = 1,
            tool = "Mission1937.Remake.ResourceTool",
            source = report,
            gfl_entries = extracted,
            converted_assets = conversion,
            conversion_status = new
            {
                gfl_container = "extracted",
                iblock_images = "converted_to_png",
                psd_composites = "converted_to_png",
                spr1_previews = "converted_to_png",
                spr1_frames = "converted_to_png_with_per_sprite_json_manifests",
                tlg1_atlases = "converted_to_png",
                vwf_maps = "m000_through_m011_converted_to_png_and_json",
                vwf_navigation = "line_of_sight_movement_event_and_manual_correction_layers_converted_to_binary",
                dbl_database = "parsed_and_linked",
                slf_sound_map = "validated",
                wav_audio = "copied"
            }
        });

        Console.WriteLine($"Imported {extracted.Count} GFL entries into {outputDirectory}");
        Console.WriteLine(
            $"Converted {conversion.IBlockPngCount} IBLOCK images, " +
            $"{conversion.PsdPngCount} PSD composites, " +
            $"{conversion.TileAtlasPngCount} tile atlases, " +
            $"{conversion.SpritePreviewPngCount} sprite previews, " +
            $"{conversion.SpriteFramePngCount} sprite frames and " +
            $"{conversion.WaveFileCount} WAV files.");
        Console.WriteLine(
            $"Wrote {conversion.SpriteAnimationManifestCount} sprite animation manifests " +
            $"covering {conversion.SpriteGroupCount} frame groups.");
        Console.WriteLine(
            $"Rendered {conversion.FormalLevelCount} formal levels with " +
            $"{conversion.TotalLevelEntityCount} entity records.");
        foreach (var level in conversion.Levels)
        {
            Console.WriteLine(
                $"  {level.LevelId}: {level.TerrainWidth}x{level.TerrainHeight}, " +
                $"{level.EntityCount} entities");
        }
        return 0;
    }

    private static int MediaCatalog(string[] args)
    {
        RequireArgumentCount(args, 3, 3, "media-catalog <game-directory> <converted-directory>");
        var gameDirectory = System.IO.Path.GetFullPath(args[1]);
        var convertedDirectory = System.IO.Path.GetFullPath(args[2]);
        EnsureOutputIsOutsideSource(gameDirectory, convertedDirectory);
        EnsureOutputIsGitIgnoredIfNecessary(convertedDirectory);

        var resourcePath = System.IO.Path.Combine(gameDirectory, "1937Resources.GFL");
        var indexPath = System.IO.Path.Combine(gameDirectory, "InterMedia.GFL");
        var archive = GflArchive.Open(resourcePath, File.Exists(indexPath) ? indexPath : null);
        var catalogPath = System.IO.Path.Combine(convertedDirectory, "legacy-media-catalog.json");
        var soundNames = SoundLibrary.Open(System.IO.Path.Combine(gameDirectory, "1937Sound.slf"))
            .Entries.Select(entry => entry.FileName).ToHashSet(StringComparer.OrdinalIgnoreCase);
        WriteJson(catalogPath, LegacyMediaCatalogBuilder.Build(archive.Entries, gameDirectory, soundNames));
        var audioCueCount = archive.Entries.Count(entry => entry.Type == "WAV");
        Console.WriteLine($"Wrote metadata for {audioCueCount} audio cues, " +
            $"12 mission briefings and 5 legacy movies to {catalogPath}");
        return 0;
    }

    private static void EnsureOutputIsOutsideSource(string source, string output)
    {
        var sourceWithSeparator = source.TrimEnd(System.IO.Path.DirectorySeparatorChar) + System.IO.Path.DirectorySeparatorChar;
        var outputWithSeparator = output.TrimEnd(System.IO.Path.DirectorySeparatorChar) + System.IO.Path.DirectorySeparatorChar;
        if (outputWithSeparator.StartsWith(sourceWithSeparator, StringComparison.OrdinalIgnoreCase) ||
            sourceWithSeparator.StartsWith(outputWithSeparator, StringComparison.OrdinalIgnoreCase))
        {
            throw new ArgumentException("Output directory must be separate from the original game directory.");
        }
    }

    private static void EnsureOutputIsGitIgnoredIfNecessary(string output)
    {
        var repositoryRoot = FindGitWorkTree(output);
        if (repositoryRoot is null)
        {
            return;
        }

        var relativeOutput = System.IO.Path.GetRelativePath(repositoryRoot, output)
            .Replace(System.IO.Path.DirectorySeparatorChar, '/');
        var startInfo = new ProcessStartInfo
        {
            FileName = "git",
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardError = true,
            RedirectStandardOutput = true
        };
        startInfo.ArgumentList.Add("-C");
        startInfo.ArgumentList.Add(repositoryRoot);
        startInfo.ArgumentList.Add("check-ignore");
        startInfo.ArgumentList.Add("--quiet");
        startInfo.ArgumentList.Add("--no-index");
        startInfo.ArgumentList.Add("--");
        startInfo.ArgumentList.Add(relativeOutput);

        try
        {
            using var process = Process.Start(startInfo)
                ?? throw new InvalidDataException("Unable to start Git for the output safety check.");
            var error = process.StandardError.ReadToEnd();
            process.WaitForExit();
            if (process.ExitCode != 0)
            {
                var detail = string.IsNullOrWhiteSpace(error) ? string.Empty : $" Git reported: {error.Trim()}";
                throw new ArgumentException(
                    "Output directory is inside a Git work tree but is not ignored. " +
                    $"Use an ignored LocalAssets directory or a location outside the repository.{detail}");
            }
        }
        catch (System.ComponentModel.Win32Exception exception)
        {
            throw new InvalidDataException(
                "Git is required to verify a repository-local output directory before extraction.",
                exception);
        }
    }

    private static string? FindGitWorkTree(string output)
    {
        for (var directory = new DirectoryInfo(output); directory is not null; directory = directory.Parent)
        {
            var marker = System.IO.Path.Combine(directory.FullName, ".git");
            if (Directory.Exists(marker) || File.Exists(marker))
            {
                return directory.FullName;
            }
        }

        return null;
    }

    private static void WriteJson(string path, object value)
    {
        Directory.CreateDirectory(System.IO.Path.GetDirectoryName(path)!);
        File.WriteAllText(path, JsonSerializer.Serialize(value, JsonOptions) + Environment.NewLine);
    }

    private static void RequireArgumentCount(string[] args, int minimum, int maximum, string usage)
    {
        if (args.Length < minimum || args.Length > maximum)
        {
            throw new ArgumentException($"Usage: ResourceTool {usage}");
        }
    }

    private static int UnknownCommand(string command)
    {
        Console.Error.WriteLine($"Unknown command: {command}");
        PrintUsage();
        return 1;
    }

    private static void PrintUsage()
    {
        Console.WriteLine("Mission 1937 remake resource research tool");
        Console.WriteLine();
        Console.WriteLine("Commands:");
        Console.WriteLine("  inspect <game-directory>");
        Console.WriteLine(
            "  inspect-dbl <1937Database.dbl> [--id=N] [--runtime-type=N]");
        Console.WriteLine(
            "  world-pickup-baseline <1937db.dbl> <output.json>");
        Console.WriteLine(
            "  inspect-vwf <path.vwf> [1937db.dbl] [--entities] [--patrols] [--extended] [--auxiliary] [--scene=N]");
        Console.WriteLine(
            "  inspect-save <path.SAV> <game-directory> [1937db.dbl] [M1937.SI#] [--entities]");
        Console.WriteLine(
            "  import-save <path.SAV> <game-directory> <output.json> [M1937.SI#] [--slot=legacy_N] [--data-dir=<Remake/game/data>]");
        Console.WriteLine(
            "  list-gfl <1937Resources.GFL> [InterMedia.GFL] [--all]");
        Console.WriteLine("  extract-gfl <1937Resources.GFL> <output-directory> [InterMedia.GFL]");
        Console.WriteLine(
            "  strip-briefings <1937Resources.GFL> <InterMedia.GFL> " +
            "<output-resources.GFL> <output-index.GFL>");
        Console.WriteLine(
            "  prune-retired-briefings <1937Resources.GFL> <InterMedia.GFL> " +
            "<output-resources.GFL> <output-index.GFL>");
        Console.WriteLine(
            "  render-text-briefings <关卡名称.json> <output-directory>");
        Console.WriteLine(
            "  install-text-briefings <关卡名称.json> " +
            "<source-resources.GFL> <source-index.GFL> " +
            "<output-resources.GFL> <output-index.GFL> " +
            "[preview-directory]");
        Console.WriteLine("  import <game-directory> <output-directory>");
        Console.WriteLine("  media-catalog <game-directory> <converted-directory>");
        Console.WriteLine();
        Console.WriteLine("Repository-local output directories must be ignored by Git.");
    }
}
