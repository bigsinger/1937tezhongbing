using System.Text.Json;
using System.Text.Json.Serialization.Metadata;
using Mission1937.Remake.Resources;

namespace Mission1937.Remake.ResourceTool;

internal sealed record OriginalAssetConversionResult(
    int IBlockPngCount,
    int TileAtlasPngCount,
    int SpritePreviewPngCount,
    int SpriteFramePngCount,
    int SpriteAnimationManifestCount,
    int SpriteGroupCount,
    int WaveFileCount,
    int FormalLevelCount,
    int TotalLevelEntityCount,
    IReadOnlyList<ConvertedLevelSummary> Levels,
    string AssetManifest,
    string LevelManifest);

internal sealed record ConvertedLevelSummary(
    string LevelId,
    int TerrainWidth,
    int TerrainHeight,
    int EntityCount,
    string Manifest);

internal sealed record ConvertedSpriteSummary(
    int GflIndex,
    string ResourceName,
    uint SerializationVersion,
    int GroupCount,
    int FrameCount,
    string Manifest);

internal sealed record ExpectedTaskAnchorInventory(
    int Markers,
    int Explosion,
    int Exit,
    int Spawns,
    int Entrances);

/// <summary>
/// Converts the supported original resources into ordinary files consumed by the remake.
/// All output is derived from the user's local copy and must stay under an ignored directory.
/// </summary>
internal static class OriginalAssetConverter
{
    private const int ExpectedIBlockCount = 34;
    private const int ExpectedTileGroupCount = 45;
    private const int ExpectedSpriteCount = 980;
    private const int ExpectedSpriteFrameCount = 11_898;
    private const int ExpectedWaveCount = 128;
    private const int ExpectedFormalLevelCount = 12;

    private static readonly ExpectedTaskAnchorInventory[] ExpectedTaskAnchors =
    [
        new(1, 0, 1, 4, 0),
        new(4, 2, 1, 5, 8),
        new(3, 1, 1, 7, 2),
        new(6, 5, 1, 2, 4),
        new(3, 2, 0, 4, 15),
        new(1, 0, 0, 1, 10),
        new(2, 0, 1, 4, 7),
        new(3, 0, 1, 5, 8),
        new(5, 4, 1, 4, 1),
        new(4, 4, 0, 3, 11),
        new(4, 0, 4, 4, 11),
        new(7, 6, 1, 7, 8)
    ];

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
        PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower,
        TypeInfoResolver = new DefaultJsonTypeInfoResolver()
    };

    public static OriginalAssetConversionResult Convert(
        string gameDirectory,
        string outputDirectory,
        GflArchive archive,
        IReadOnlyList<ExtractedGflEntry> extractedEntries)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(gameDirectory);
        ArgumentException.ThrowIfNullOrWhiteSpace(outputDirectory);
        ArgumentNullException.ThrowIfNull(archive);
        ArgumentNullException.ThrowIfNull(extractedEntries);

        var gameRoot = System.IO.Path.GetFullPath(gameDirectory);
        var outputRoot = System.IO.Path.GetFullPath(outputDirectory);
        var rawGflRoot = System.IO.Path.Combine(outputRoot, "raw", "gfl");
        var convertedRoot = System.IO.Path.Combine(outputRoot, "converted");
        var sourcePaths = ValidateExtraction(archive, extractedEntries, rawGflRoot);

        var entriesByType = archive.Entries
            .GroupBy(entry => entry.Type, StringComparer.Ordinal)
            .ToDictionary(group => group.Key, group => group.ToArray(), StringComparer.Ordinal);
        var iBlockEntries = GetExpectedEntries(
            entriesByType,
            "IBLOCK",
            ExpectedIBlockCount);
        var tileGroupEntries = GetExpectedEntries(
            entriesByType,
            "TLG1",
            ExpectedTileGroupCount);
        var spriteEntries = GetExpectedEntries(
            entriesByType,
            "SPR1",
            ExpectedSpriteCount);
        var waveEntries = GetExpectedEntries(
            entriesByType,
            "WAV",
            ExpectedWaveCount);

        var databasePath = System.IO.Path.Combine(gameRoot, "1937Database.dbl");
        var database = DblDatabase.Open(databasePath);
        var databaseResources = ValidateDatabaseResourceMap(database, archive);

        var iBlockDirectory = System.IO.Path.Combine(convertedRoot, "iblock");
        var tileDirectory = System.IO.Path.Combine(convertedRoot, "tile-atlases");
        var spriteDirectory = System.IO.Path.Combine(convertedRoot, "sprites");
        var spriteFramesDirectory = System.IO.Path.Combine(convertedRoot, "sprite-frames");
        var audioDirectory = System.IO.Path.Combine(convertedRoot, "audio");
        Directory.CreateDirectory(iBlockDirectory);
        Directory.CreateDirectory(tileDirectory);
        Directory.CreateDirectory(spriteDirectory);
        Directory.CreateDirectory(spriteFramesDirectory);
        Directory.CreateDirectory(audioDirectory);

        foreach (var entry in iBlockEntries)
        {
            IBlockImage.Open(sourcePaths[entry.Index]).SavePng(
                IBlockOutputPath(iBlockDirectory, entry));
        }

        var decodedTileGroups = new List<TlgTileGroup>(tileGroupEntries.Length);
        foreach (var entry in tileGroupEntries)
        {
            var tileGroup = TlgTileGroup.Open(sourcePaths[entry.Index]);
            if (tileGroup.Atlas is null)
            {
                throw new InvalidDataException(
                    $"TLG1 resource '{entry.OriginalName}' does not contain an atlas.");
            }

            tileGroup.Atlas.SavePng(TileAtlasOutputPath(tileDirectory, entry));
            decodedTileGroups.Add(tileGroup);
        }

        var spriteSummaries = new List<ConvertedSpriteSummary>(spriteEntries.Length);
        foreach (var entry in spriteEntries)
        {
            // Keep decoding in a helper so every complete SPR object becomes collectible
            // before the next file is opened; no decoded frame arrays are retained here.
            spriteSummaries.Add(ConvertSprite(
                sourcePaths[entry.Index],
                SpriteOutputPath(spriteDirectory, entry),
                spriteFramesDirectory,
                convertedRoot,
                entry));
        }

        var spriteFrameCount = spriteSummaries.Sum(sprite => sprite.FrameCount);
        if (spriteFrameCount != ExpectedSpriteFrameCount)
        {
            throw new InvalidDataException(
                $"The supported original version requires {ExpectedSpriteFrameCount} SPR1 frames; " +
                $"the archive contains {spriteFrameCount}.");
        }

        foreach (var entry in waveEntries)
        {
            File.Copy(
                sourcePaths[entry.Index],
                WaveOutputPath(audioDirectory, entry),
                overwrite: true);
        }

        var tileCatalog = TerrainTileCatalog.FromDatabase(database, decodedTileGroups);
        var spritePreviews = spriteEntries.ToDictionary(
            entry => entry.Index,
            entry => SpriteOutputPath(spriteDirectory, entry));
        var levelsRoot = System.IO.Path.Combine(convertedRoot, "levels");
        var levelSummaries = Enumerable.Range(0, ExpectedFormalLevelCount)
            .Select(levelIndex => ConvertLevel(
                levelIndex,
                gameRoot,
                levelsRoot,
                database,
                databaseResources,
                tileCatalog,
                spritePreviews))
            .ToArray();
        var levelManifestPath = System.IO.Path.Combine(levelsRoot, "index.json");
        WriteJson(levelManifestPath, new
        {
            schema_version = 1,
            levels = levelSummaries
        });

        var assetManifestPath = System.IO.Path.Combine(convertedRoot, "asset-manifest.json");
        WriteJson(assetManifestPath, new
        {
            schema_version = 1,
            source_archive = System.IO.Path.GetFileName(archive.Path),
            iblock = iBlockEntries.Select(entry => AssetManifestEntry(
                entry,
                convertedRoot,
                IBlockOutputPath(iBlockDirectory, entry))),
            tile_atlases = tileGroupEntries.Select(entry => AssetManifestEntry(
                entry,
                convertedRoot,
                TileAtlasOutputPath(tileDirectory, entry))),
            sprite_previews = spriteEntries.Select(entry => AssetManifestEntry(
                entry,
                convertedRoot,
                SpriteOutputPath(spriteDirectory, entry))),
            sprite_animations = spriteSummaries,
            audio = waveEntries.Select(entry => AssetManifestEntry(
                entry,
                convertedRoot,
                WaveOutputPath(audioDirectory, entry))),
            levels = levelSummaries
        });

        return new OriginalAssetConversionResult(
            iBlockEntries.Length,
            tileGroupEntries.Length,
            spriteEntries.Length,
            spriteFrameCount,
            spriteSummaries.Count,
            spriteSummaries.Sum(sprite => sprite.GroupCount),
            waveEntries.Length,
            levelSummaries.Length,
            levelSummaries.Sum(level => level.EntityCount),
            levelSummaries,
            RelativePath(outputRoot, assetManifestPath),
            RelativePath(outputRoot, levelManifestPath));
    }

    private static ConvertedLevelSummary ConvertLevel(
        int levelIndex,
        string gameRoot,
        string levelsRoot,
        DblDatabase database,
        IReadOnlyDictionary<int, GflEntry> databaseResources,
        TerrainTileCatalog tileCatalog,
        IReadOnlyDictionary<int, string> spritePreviews)
    {
        var levelId = $"m{levelIndex:D3}";
        var levelDirectory = System.IO.Path.Combine(levelsRoot, levelId);
        Directory.CreateDirectory(levelDirectory);
        var levelPath = System.IO.Path.Combine(gameRoot, $"1937{levelId}.vwf");
        if (!File.Exists(levelPath))
        {
            throw new FileNotFoundException($"Formal level {levelId} is missing.", levelPath);
        }

        var terrain = VwfTerrainGrid.Open(levelPath, database);
        var terrainImage = TerrainRasterizer.Rasterize(terrain, tileCatalog);
        var terrainPngPath = System.IO.Path.Combine(levelDirectory, "terrain.png");
        terrainImage.SavePng(terrainPngPath);

        var sceneList = VwfSceneList.Open(levelPath, database);
        var navigationGrid = VwfNavigationGrid.FromTerrain(
            terrain,
            checked((uint)tileCatalog.TileWidth),
            checked((uint)tileCatalog.TileHeight));
        var navigationPath = System.IO.Path.Combine(levelDirectory, "navigation.bin");
        navigationGrid.Save(navigationPath);
        var levelEntities = sceneList.Entities.Select(entity =>
        {
            var databaseEntry = entity.DatabaseEntry
                ?? throw new InvalidDataException(
                    $"SLIST1 entity {entity.SceneIndex} in {levelId} was not resolved through the DBL.");
            var resource = databaseResources[databaseEntry.Id];
            var spritePreview = resource.Type == "SPR1"
                ? RelativePath(levelDirectory, spritePreviews[resource.Index])
                : string.Empty;
            var patrolWaypoints = entity.Patrol?.Waypoints.Select(point => new
            {
                x = point.X,
                y = point.Y
            }).ToArray() ?? [];
            object? patrol = entity.Patrol is null
                ? null
                : new
                {
                    format_version = entity.Patrol.FormatVersion,
                    current_waypoint_index = entity.Patrol.CurrentWaypointIndex,
                    persistent_flag = entity.Patrol.PersistentFlag,
                    // Legacy convenience projection. The original executable
                    // persists this value, but its use as an enable gate is not proven.
                    enabled = entity.Patrol.PersistentFlag != 0,
                    cached_waypoint_world = new
                    {
                        x = entity.Patrol.CachedWaypointWorldX,
                        y = entity.Patrol.CachedWaypointWorldY
                    },
                    // Backward-compatible JSON alias. This coordinate is a cache
                    // for the current waypoint and must not be treated as an origin.
                    origin = new
                    {
                        x = entity.Patrol.CachedWaypointWorldX,
                        y = entity.Patrol.CachedWaypointWorldY
                    },
                    working_points = entity.Patrol.WorkingPoints.Select(point => new
                    {
                        x = point.X,
                        y = point.Y
                    }),
                    waypoints = patrolWaypoints
                };

            return new
            {
                scene_index = entity.SceneIndex,
                database_entry_id = databaseEntry.Id,
                resource_name = databaseEntry.ResourceName,
                display_name = databaseEntry.DisplayName,
                category_name = databaseEntry.CategoryName,
                database_header_values = databaseEntry.HeaderValues,
                faction_id = databaseEntry.FactionId,
                team_id = databaseEntry.TeamId,
                special_sensor = databaseEntry.SpecialSensor,
                direction_index = entity.DirectionIndex,
                death_state = entity.DeathState,
                crawl_state = entity.CrawlState,
                extended_data_present = entity.HasExtendedData,
                reaction_state = entity.ReactionState,
                default_attack_type = entity.DefaultAttackType,
                current_hit_points = entity.CurrentHitPoints,
                x = entity.WorldX,
                y = entity.WorldY,
                reference_x = entity.ReferenceX,
                reference_y = entity.ReferenceY,
                reference = new
                {
                    x = entity.ReferenceX,
                    y = entity.ReferenceY
                },
                sprite_preview = spritePreview,
                patrol_waypoints = patrolWaypoints,
                patrol
            };
        }).ToArray();

        var taskAnchors = sceneList.Entities
            .Where(entity => TaskAnchorKind(entity.DatabaseEntryId) is not null)
            .Select(entity => new
            {
                scene_index = entity.SceneIndex,
                database_entry_id = entity.DatabaseEntryId,
                kind = TaskAnchorKind(entity.DatabaseEntryId)!,
                x = entity.WorldX,
                y = entity.WorldY,
                reference_x = entity.ReferenceX,
                reference_y = entity.ReferenceY
            })
            .ToArray();
        ValidateTaskAnchorInventory(levelIndex, levelId, taskAnchors.Select(anchor => anchor.kind));

        var levelJsonPath = System.IO.Path.Combine(levelDirectory, "level.json");
        WriteJson(levelJsonPath, new
        {
            schema_version = 1,
            level_id = levelId,
            world_size = new
            {
                width = terrainImage.Width,
                height = terrainImage.Height
            },
            tile_size = new
            {
                width = tileCatalog.TileWidth,
                height = tileCatalog.TileHeight
            },
            terrain_image = RelativePath(levelDirectory, terrainPngPath),
            navigation = new
            {
                schema_version = VwfNavigationGrid.FormatVersion,
                relative_path = RelativePath(levelDirectory, navigationPath),
                width = navigationGrid.Width,
                height = navigationGrid.Height,
                cell_width = navigationGrid.CellWidth,
                cell_height = navigationGrid.CellHeight,
                layer_ids = new
                {
                    line_of_sight_obstacle = (uint)VwfSemanticLayer.LineOfSightObstacle,
                    movement_obstacle = (uint)VwfSemanticLayer.MovementObstacle,
                    event_layer = (uint)VwfSemanticLayer.Event,
                    manual_movement_correction = (uint)VwfSemanticLayer.ManualMovementCorrection
                }
            },
            entities = levelEntities,
            task_anchors = taskAnchors
        });

        return new ConvertedLevelSummary(
            levelId,
            terrainImage.Width,
            terrainImage.Height,
            levelEntities.Length,
            RelativePath(levelsRoot, levelJsonPath));
    }

    private static string? TaskAnchorKind(int databaseEntryId) => databaseEntryId switch
    {
        1001 => "corpse_state",
        1008 => "sight_detector",
        1010 => "entrance",
        1011 => "enemy_spawn",
        1018 => "marker",
        1019 => "explosion_detector",
        1020 => "exit_detector",
        _ => null
    };

    private static void ValidateTaskAnchorInventory(
        int levelIndex,
        string levelId,
        IEnumerable<string> kinds)
    {
        var counts = kinds
            .GroupBy(kind => kind, StringComparer.Ordinal)
            .ToDictionary(group => group.Key, group => group.Count(), StringComparer.Ordinal);
        int Count(string kind) => counts.GetValueOrDefault(kind);
        var actual = new ExpectedTaskAnchorInventory(
            Count("marker"),
            Count("explosion_detector"),
            Count("exit_detector"),
            Count("enemy_spawn"),
            Count("entrance"));
        var expected = ExpectedTaskAnchors[levelIndex];
        if (actual != expected)
        {
            throw new InvalidDataException(
                $"Task-anchor inventory for {levelId} is {actual}, expected {expected}.");
        }
    }

    private static IReadOnlyDictionary<int, string> ValidateExtraction(
        GflArchive archive,
        IReadOnlyList<ExtractedGflEntry> extractedEntries,
        string rawGflRoot)
    {
        if (extractedEntries.Count != archive.Entries.Count)
        {
            throw new InvalidDataException(
                $"The extraction contains {extractedEntries.Count} entries, " +
                $"but the GFL contains {archive.Entries.Count}.");
        }

        var extractedByIndex = new Dictionary<int, ExtractedGflEntry>();
        foreach (var extracted in extractedEntries)
        {
            if (!extractedByIndex.TryAdd(extracted.Index, extracted))
            {
                throw new InvalidDataException(
                    $"The extraction contains duplicate GFL index {extracted.Index}.");
            }
        }

        var paths = new Dictionary<int, string>();
        foreach (var entry in archive.Entries)
        {
            if (!extractedByIndex.TryGetValue(entry.Index, out var extracted) ||
                !string.Equals(entry.OriginalName, extracted.OriginalName, StringComparison.Ordinal) ||
                !string.Equals(entry.Type, extracted.Type, StringComparison.Ordinal) ||
                entry.Length != extracted.Length)
            {
                throw new InvalidDataException(
                    $"Extracted metadata does not match GFL entry {entry.Index}.");
            }

            var sourcePath = ResolveContainedPath(rawGflRoot, extracted.RelativePath);
            if (!File.Exists(sourcePath))
            {
                throw new FileNotFoundException(
                    $"Extracted GFL entry {entry.Index} is missing.",
                    sourcePath);
            }
            if (new FileInfo(sourcePath).Length != entry.Length)
            {
                throw new InvalidDataException(
                    $"Extracted GFL entry {entry.Index} has the wrong length.");
            }

            paths.Add(entry.Index, sourcePath);
        }

        return paths;
    }

    private static IReadOnlyDictionary<int, GflEntry> ValidateDatabaseResourceMap(
        DblDatabase database,
        GflArchive archive)
    {
        var archiveByName = new Dictionary<string, GflEntry>(StringComparer.OrdinalIgnoreCase);
        foreach (var resource in archive.Entries.Where(entry => entry.Type is "SPR1" or "TLG1"))
        {
            if (string.IsNullOrWhiteSpace(resource.OriginalName))
            {
                throw new InvalidDataException(
                    $"GFL entry {resource.Index} has no resource name for DBL matching.");
            }
            if (!archiveByName.TryAdd(resource.OriginalName, resource))
            {
                throw new InvalidDataException(
                    $"The GFL contains more than one resource named '{resource.OriginalName}'.");
            }
        }

        var result = new Dictionary<int, GflEntry>();
        foreach (var databaseEntry in database.Entries)
        {
            if (!archiveByName.TryGetValue(databaseEntry.ResourceName, out var resource))
            {
                throw new InvalidDataException(
                    $"DBL entry {databaseEntry.Id} references missing GFL resource " +
                    $"'{databaseEntry.ResourceName}'.");
            }

            var expectedType = databaseEntry.Kind switch
            {
                DblEntryKind.Sprite => "SPR1",
                DblEntryKind.TileGroup => "TLG1",
                _ => throw new InvalidDataException(
                    $"DBL entry {databaseEntry.Id} has unsupported kind {databaseEntry.Kind}.")
            };
            if (!string.Equals(resource.Type, expectedType, StringComparison.Ordinal))
            {
                throw new InvalidDataException(
                    $"DBL entry {databaseEntry.Id} names '{databaseEntry.ResourceName}' as " +
                    $"{databaseEntry.Kind}, but the GFL resource is {resource.Type}.");
            }

            result.Add(databaseEntry.Id, resource);
        }

        return result;
    }

    private static GflEntry[] GetExpectedEntries(
        IReadOnlyDictionary<string, GflEntry[]> entriesByType,
        string type,
        int expectedCount)
    {
        if (!entriesByType.TryGetValue(type, out var entries) || entries.Length != expectedCount)
        {
            var actualCount = entries?.Length ?? 0;
            throw new InvalidDataException(
                $"The supported original version requires {expectedCount} {type} entries; " +
                $"the archive contains {actualCount}.");
        }

        return entries.OrderBy(entry => entry.Index).ToArray();
    }

    private static ConvertedSpriteSummary ConvertSprite(
        string sourcePath,
        string previewDestinationPath,
        string spriteFramesRoot,
        string convertedRoot,
        GflEntry entry)
    {
        var sprite = SprSprite.Open(sourcePath);
        if (sprite.Groups.Count == 0 || sprite.Groups[0].Frames.Count == 0)
        {
            throw new InvalidDataException(
                $"SPR1 resource '{entry.OriginalName}' does not contain a first frame.");
        }

        sprite.Groups[0].Frames[0].SavePng(previewDestinationPath);

        // Resource names and embedded names are metadata only. Output paths are
        // composed solely from validated numeric indices, so a malformed archive
        // name can never escape the ignored local-assets directory.
        var spriteRelativeDirectory = entry.Index.ToString("D4", System.Globalization.CultureInfo.InvariantCulture);
        var spriteDirectory = ResolveContainedPath(spriteFramesRoot, spriteRelativeDirectory);
        Directory.CreateDirectory(spriteDirectory);

        var groupManifests = new object[sprite.Groups.Count];
        for (var groupIndex = 0; groupIndex < sprite.Groups.Count; groupIndex++)
        {
            var group = sprite.Groups[groupIndex];
            var semantic = SprAnimationSemantics.Decode(group.Parameters[0]);
            var frameTickThreshold = group.Parameters[2];
            if (frameTickThreshold < 0)
            {
                throw new InvalidDataException(
                    $"SPR1 resource '{entry.OriginalName}' group {groupIndex} " +
                    $"has a negative frame tick threshold {frameTickThreshold}.");
            }
            var frameHoldTicks = checked(frameTickThreshold + 1);
            var groupName = $"g{groupIndex:D3}";
            var groupDirectory = ResolveContainedPath(spriteDirectory, groupName);
            Directory.CreateDirectory(groupDirectory);

            var frameWidth = group.Frames[0].Width;
            var frameHeight = group.Frames[0].Height;
            if (group.Frames.Any(frame => frame.Width != frameWidth || frame.Height != frameHeight))
            {
                throw new InvalidDataException(
                    $"SPR1 resource '{entry.OriginalName}' group {groupIndex} " +
                    "contains frames with different canvas dimensions.");
            }
            var atlasWidth = checked(frameWidth * group.Frames.Count);
            var atlasPixels = new byte[checked(atlasWidth * frameHeight * 4)];

            var frameManifests = new object[group.Frames.Count];
            for (var frameIndex = 0; frameIndex < group.Frames.Count; frameIndex++)
            {
                var frame = group.Frames[frameIndex];
                var framePath = ResolveContainedPath(
                    groupDirectory,
                    $"f{frameIndex:D4}.png");
                frame.SavePng(framePath);
                CopyFrameIntoHorizontalAtlas(
                    frame.Rgba32.Span,
                    frameWidth,
                    frameHeight,
                    atlasPixels,
                    atlasWidth,
                    frameIndex * frameWidth);
                frameManifests[frameIndex] = new
                {
                    frame_index = frameIndex,
                    width = frame.Width,
                    height = frame.Height,
                    bits_per_pixel = frame.BitsPerPixel,
                    has_alpha_plane = frame.HasAlphaPlane,
                    relative_path = RelativePath(spriteDirectory, framePath)
                };
            }

            var atlasPath = ResolveContainedPath(groupDirectory, "atlas.png");
            using (var atlasStream = new FileStream(
                atlasPath,
                FileMode.Create,
                FileAccess.Write,
                FileShare.None))
            {
                PngWriter.WriteRgba32(
                    atlasStream,
                    atlasWidth,
                    frameHeight,
                    atlasPixels);
            }

            groupManifests[groupIndex] = new
            {
                group_index = groupIndex,
                serial_id = semantic.SerialId,
                action_index = semantic.ActionIndex,
                action_key = semantic.ActionKey,
                action_name = semantic.ActionName,
                direction_index = semantic.DirectionIndex,
                direction_key = semantic.DirectionKey,
                direction_name = semantic.DirectionName,
                is_reserved_action = semantic.IsReserved,
                serialization_version = group.SerializationVersion,
                primary_triplet = group.PrimaryTriplet,
                secondary_triplet = group.SecondaryTriplet,
                tertiary_triplet = group.TertiaryTriplet,
                parameters = group.Parameters,
                frame_tick_threshold = frameTickThreshold,
                frame_hold_ticks = frameHoldTicks,
                first_lookup = group.FirstLookup,
                second_lookup = group.SecondLookup,
                row_lookup = group.RowLookup,
                trailing_value = group.TrailingValue,
                frame_count = group.Frames.Count,
                atlas = new
                {
                    relative_path = RelativePath(spriteDirectory, atlasPath),
                    width = atlasWidth,
                    height = frameHeight,
                    frame_width = frameWidth,
                    frame_height = frameHeight,
                    columns = group.Frames.Count,
                    rows = 1
                },
                frames = frameManifests
            };
        }

        var manifestPath = ResolveContainedPath(spriteDirectory, "sprite.json");
        WriteJson(manifestPath, new
        {
            schema_version = 2,
            gfl_index = entry.Index,
            resource_name = entry.OriginalName,
            internal_name = sprite.InternalName,
            serialization_version = sprite.SerializationVersion,
            header_values = sprite.HeaderValues,
            extended_header_values = sprite.ExtendedHeaderValues,
            group_count = sprite.Groups.Count,
            frame_count = sprite.FrameCount,
            preview = RelativePath(spriteDirectory, previewDestinationPath),
            groups = groupManifests
        });

        return new ConvertedSpriteSummary(
            entry.Index,
            entry.OriginalName,
            sprite.SerializationVersion,
            sprite.Groups.Count,
            sprite.FrameCount,
            RelativePath(convertedRoot, manifestPath));
    }

    private static void CopyFrameIntoHorizontalAtlas(
        ReadOnlySpan<byte> framePixels,
        int frameWidth,
        int frameHeight,
        Span<byte> atlasPixels,
        int atlasWidth,
        int atlasX)
    {
        var frameRowBytes = checked(frameWidth * 4);
        var atlasRowBytes = checked(atlasWidth * 4);
        for (var row = 0; row < frameHeight; row++)
        {
            framePixels.Slice(row * frameRowBytes, frameRowBytes).CopyTo(
                atlasPixels.Slice(
                    checked((row * atlasRowBytes) + (atlasX * 4)),
                    frameRowBytes));
        }
    }

    private static object AssetManifestEntry(
        GflEntry entry,
        string convertedRoot,
        string outputPath) => new
        {
            gfl_index = entry.Index,
            resource_name = entry.OriginalName,
            relative_path = RelativePath(convertedRoot, outputPath)
        };

    private static string IBlockOutputPath(string directory, GflEntry entry) =>
        System.IO.Path.Combine(directory, $"{entry.Index:D4}.png");

    private static string TileAtlasOutputPath(string directory, GflEntry entry) =>
        System.IO.Path.Combine(directory, $"{entry.Index:D4}.png");

    private static string SpriteOutputPath(string directory, GflEntry entry) =>
        System.IO.Path.Combine(directory, $"{entry.Index:D4}.png");

    private static string WaveOutputPath(string directory, GflEntry entry) =>
        System.IO.Path.Combine(directory, $"{entry.Index:D4}.wav");

    private static string ResolveContainedPath(string root, string relativePath)
    {
        if (string.IsNullOrWhiteSpace(relativePath) ||
            System.IO.Path.IsPathFullyQualified(relativePath))
        {
            throw new InvalidDataException("An extracted GFL path is not a relative path.");
        }

        var fullRoot = System.IO.Path.GetFullPath(root);
        var fullPath = System.IO.Path.GetFullPath(
            System.IO.Path.Combine(
                fullRoot,
                relativePath.Replace('/', System.IO.Path.DirectorySeparatorChar)));
        var rootWithSeparator = fullRoot.TrimEnd(
            System.IO.Path.DirectorySeparatorChar,
            System.IO.Path.AltDirectorySeparatorChar) + System.IO.Path.DirectorySeparatorChar;
        if (!fullPath.StartsWith(rootWithSeparator, StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidDataException(
                $"Extracted GFL path escapes its output directory: '{relativePath}'.");
        }

        return fullPath;
    }

    private static string RelativePath(string root, string path) =>
        System.IO.Path.GetRelativePath(root, path).Replace(
            System.IO.Path.DirectorySeparatorChar,
            '/');

    private static void WriteJson(string path, object value)
    {
        Directory.CreateDirectory(System.IO.Path.GetDirectoryName(path)!);
        File.WriteAllText(
            path,
            JsonSerializer.Serialize(value, JsonOptions) + Environment.NewLine);
    }
}
