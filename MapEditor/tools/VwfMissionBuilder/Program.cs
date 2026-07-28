using System.Buffers.Binary;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using Mission1937.Remake.Resources;

if (args.Length is < 3 or > 4)
{
    Console.Error.WriteLine(
        "Usage: VwfMissionBuilder SOURCE.vwf OUTPUT.vwf DEFINITION.json [REPORT.md]");
    return 2;
}

var sourcePath = Path.GetFullPath(args[0]);
var outputPath = Path.GetFullPath(args[1]);
var definitionPath = Path.GetFullPath(args[2]);
var reportPath = args.Length == 4
    ? Path.GetFullPath(args[3])
    : Path.ChangeExtension(outputPath, ".validation.md");

var definition = JsonSerializer.Deserialize<MissionDefinition>(
    File.ReadAllText(definitionPath),
    new JsonSerializerOptions
    {
        PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower,
        PropertyNameCaseInsensitive = true,
        Converters = { new JsonStringEnumConverter(JsonNamingPolicy.SnakeCaseLower) }
    }) ?? throw new InvalidDataException("Mission definition is empty.");

var builder = new MissionBuilder(sourcePath, definition);
var report = builder.Build(outputPath);
Directory.CreateDirectory(Path.GetDirectoryName(reportPath)!);
File.WriteAllText(reportPath, report, new UTF8Encoding(false));
Console.WriteLine($"Built {outputPath}");
Console.WriteLine($"Validation report: {reportPath}");
return 0;

internal sealed class MissionDefinition
{
    public string Id { get; set; } = "";
    public string Title { get; set; } = "";
    public string Story { get; set; } = "";
    public string SourceSha256 { get; set; } = "";
    public List<int> PlayerSceneIndices { get; set; } = [];
    public List<int> EnemySceneIndices { get; set; } = [];
    public int MinimumSpawnEnemyDistanceWorld { get; set; }
    public int MinimumSpawnPatrolDistanceWorld { get; set; }
    public double MinimumReachableWalkableRatio { get; set; }
    public int MaximumPatrolSegmentPathLength { get; set; }
    public bool ValidateAllSerializedPatrols { get; set; }
    public GridCell PlayerSpawn { get; set; } = new();
    public ReachabilityTarget? MovementProbe { get; set; }
    public List<EntityEdit> EntityEdits { get; set; } = [];
    public List<ReachabilityTarget> RequiredReachability { get; set; } = [];
    public List<SceneReachabilityTarget> RequiredSceneReachability { get; set; } = [];
}

internal sealed class EntityEdit
{
    public int SceneIndex { get; set; }
    public int CellX { get; set; }
    public int CellY { get; set; }
    public int? Direction { get; set; }
    public List<GridCell>? Patrol { get; set; }
}

internal class GridCell
{
    public int X { get; set; }
    public int Y { get; set; }
}

internal sealed class ReachabilityTarget : GridCell
{
    public string Name { get; set; } = "";
}

internal sealed class SceneReachabilityTarget
{
    public string Name { get; set; } = "";
    public int SceneIndex { get; set; }
}

internal sealed class MissionBuilder
{
    private const int WorldViewportLeftOffset = 103;
    private const int WorldViewportTopOffset = 107;
    private const int WorldViewportRightOffset = 111;
    private const int WorldViewportBottomOffset = 115;
    private const int CellWidth = 32;
    private const int CellHeight = 16;
    private const int EntityPrefixWorldX = 60;
    private const int EntityPrefixWorldY = 64;
    private const int EntityPrefixReferenceX = 104;
    private const int EntityPrefixReferenceY = 112;
    private const int EntityPrefixDirection = 44;
    private const int PatrolRecordOffset = 204;

    private readonly string sourcePath;
    private readonly MissionDefinition definition;
    private readonly VwfWorldHeader world;
    private readonly VwfTerrainGrid terrain;
    private readonly VwfSceneList scenes;
    private readonly byte[] data;
    private readonly int cellCount;
    private readonly int groundLayerOffset;
    private readonly int lineOfSightLayerOffset;
    private readonly int movementLayerOffset;
    private readonly Dictionary<int, VwfSceneEntity> entities;
    private readonly HashSet<uint> editedOccupants;
    private readonly HashSet<int> playerScenes;

    public MissionBuilder(string sourcePath, MissionDefinition definition)
    {
        this.sourcePath = sourcePath;
        this.definition = definition;
        world = VwfWorldHeader.Open(sourcePath);
        terrain = VwfTerrainGrid.Open(sourcePath);
        scenes = VwfSceneList.Open(sourcePath);
        data = File.ReadAllBytes(sourcePath);
        cellCount = checked((int)(world.GridWidth * world.GridHeight));
        groundLayerOffset = LayerDataOffset(0);
        lineOfSightLayerOffset = LayerDataOffset(1);
        movementLayerOffset = LayerDataOffset(2);
        entities = scenes.Entities.ToDictionary(entity => entity.SceneIndex);
        playerScenes = definition.PlayerSceneIndices.ToHashSet();
        editedOccupants = definition.EntityEdits
            .Select(edit => checked((uint)(edit.SceneIndex + 1000)))
            .ToHashSet();
        ValidateSourceHash();
        ValidateDefinition();
    }

    public string Build(string outputPath)
    {
        var sourceHash = Hash(sourcePath);
        var initialViewport = CenterInitialViewportOnPlayer();
        ClearOriginalOccupancy();
        foreach (var edit in definition.EntityEdits)
            ApplyEntityEdit(edit);

        var spawnSafety = ValidateSpawnSafety();
        var validations = ValidateNavigation();
        var navigationCoverage = ValidateNavigationCoverage();
        Directory.CreateDirectory(Path.GetDirectoryName(outputPath)!);
        var temporary = outputPath + ".tmp";
        File.WriteAllBytes(temporary, data);
        File.Move(temporary, outputPath, true);

        var outputWorld = VwfWorldHeader.Open(outputPath);
        var outputTerrain = VwfTerrainGrid.Open(outputPath);
        var outputScenes = VwfSceneList.Open(outputPath);
        if (outputWorld.GridWidth != world.GridWidth ||
            outputWorld.GridHeight != world.GridHeight ||
            outputWorld.ViewportLeft != initialViewport.Left ||
            outputWorld.ViewportTop != initialViewport.Top ||
            outputWorld.ViewportRight != initialViewport.Right ||
            outputWorld.ViewportBottom != initialViewport.Bottom ||
            outputScenes.SlotCount != scenes.SlotCount ||
            outputScenes.Entities.Count != scenes.Entities.Count ||
            outputTerrain.SceneListOffset != terrain.SceneListOffset)
        {
            throw new InvalidDataException(
                "The generated VWF failed structural equivalence checks.");
        }

        return BuildReport(
            sourceHash, Hash(outputPath), outputPath,
            outputScenes, initialViewport,
            spawnSafety, navigationCoverage, validations);
    }

    private InitialViewport CenterInitialViewportOnPlayer()
    {
        var spawnWorldX = checked(
            definition.PlayerSpawn.X * CellWidth +
            CellWidth / 2);
        var spawnWorldY = checked(
            definition.PlayerSpawn.Y * CellHeight +
            CellHeight / 2);
        var viewportWidth = checked((int)world.ViewportWidth);
        var viewportHeight = checked((int)world.ViewportHeight);
        var worldWidth = checked(
            (int)world.GridWidth * CellWidth);
        var worldHeight = checked(
            (int)world.GridHeight * CellHeight);
        var left = Math.Clamp(
            spawnWorldX - viewportWidth / 2,
            0,
            Math.Max(0, worldWidth - viewportWidth));
        var top = Math.Clamp(
            spawnWorldY - viewportHeight / 2,
            0,
            Math.Max(0, worldHeight - viewportHeight));
        var viewport = new InitialViewport(
            left,
            top,
            checked(left + viewportWidth),
            checked(top + viewportHeight));
        WriteInt32(WorldViewportLeftOffset, viewport.Left);
        WriteInt32(WorldViewportTopOffset, viewport.Top);
        WriteInt32(WorldViewportRightOffset, viewport.Right);
        WriteInt32(WorldViewportBottomOffset, viewport.Bottom);
        return viewport;
    }

    private void ValidateDefinition()
    {
        if (string.IsNullOrWhiteSpace(definition.Id) ||
            string.IsNullOrWhiteSpace(definition.Title))
            throw new InvalidDataException("Mission id and title are required.");
        if (definition.EntityEdits.Count == 0)
            throw new InvalidDataException("At least one entity edit is required.");
        if (definition.PlayerSceneIndices.Count == 0)
            throw new InvalidDataException(
                "At least one player_scene_indices entry is required.");
        if (definition.MinimumSpawnEnemyDistanceWorld < 0 ||
            definition.MinimumSpawnPatrolDistanceWorld < 0 ||
            definition.MaximumPatrolSegmentPathLength < 0)
            throw new InvalidDataException(
                "Spawn safety distances and the patrol path limit cannot be negative.");
        if (definition.MinimumReachableWalkableRatio is < 0 or > 1)
            throw new InvalidDataException(
                "minimum_reachable_walkable_ratio must be between 0 and 1.");

        var duplicates = definition.EntityEdits
            .GroupBy(edit => edit.SceneIndex)
            .Where(group => group.Count() > 1)
            .Select(group => group.Key)
            .ToArray();
        if (duplicates.Length > 0)
            throw new InvalidDataException(
                $"Duplicate entity edits: {string.Join(", ", duplicates)}.");

        var targetCells = new HashSet<int>();
        foreach (var edit in definition.EntityEdits)
        {
            if (!entities.TryGetValue(edit.SceneIndex, out var entity))
                throw new InvalidDataException(
                    $"Scene entity {edit.SceneIndex} does not exist.");
            ValidateCell(edit.CellX, edit.CellY, $"entity {edit.SceneIndex}");
            if (!targetCells.Add(CellIndex(edit.CellX, edit.CellY)))
                throw new InvalidDataException(
                    $"More than one edited entity targets cell " +
                    $"({edit.CellX}, {edit.CellY}).");
            if (edit.Direction is < 0 or > 8)
                throw new InvalidDataException(
                    $"Entity {edit.SceneIndex} has invalid direction {edit.Direction}.");
            if (edit.Patrol is null)
                continue;
            if (entity.Patrol is null)
                throw new InvalidDataException(
                    $"Entity {edit.SceneIndex} has no patrol record.");
            if (edit.Patrol.Count != entity.Patrol.Waypoints.Count)
                throw new InvalidDataException(
                    $"Entity {edit.SceneIndex} patrol requires exactly " +
                    $"{entity.Patrol.Waypoints.Count} points, but the definition " +
                    $"contains {edit.Patrol.Count}.");
            foreach (var point in edit.Patrol)
                ValidateCell(
                    point.X, point.Y,
                    $"entity {edit.SceneIndex} patrol");
        }

        ValidateCell(
            definition.PlayerSpawn.X,
            definition.PlayerSpawn.Y,
            "player spawn");
        if (definition.MovementProbe is not null)
        {
            if (string.IsNullOrWhiteSpace(definition.MovementProbe.Name))
                throw new InvalidDataException(
                    "movement_probe requires a descriptive name.");
            ValidateCell(
                definition.MovementProbe.X,
                definition.MovementProbe.Y,
                definition.MovementProbe.Name);
        }
        foreach (var target in definition.RequiredReachability)
            ValidateCell(target.X, target.Y, target.Name);
        foreach (var target in definition.RequiredSceneReachability)
        {
            if (string.IsNullOrWhiteSpace(target.Name))
                throw new InvalidDataException(
                    "Every required scene target needs a name.");
            if (!entities.ContainsKey(target.SceneIndex))
                throw new InvalidDataException(
                    $"Required scene {target.SceneIndex} does not exist.");
        }

        var playerSet = definition.PlayerSceneIndices.ToHashSet();
        if (playerSet.Count != definition.PlayerSceneIndices.Count)
            throw new InvalidDataException(
                "player_scene_indices contains duplicates.");
        foreach (var sceneIndex in playerSet)
        {
            if (!definition.EntityEdits.Any(
                    edit => edit.SceneIndex == sceneIndex))
                throw new InvalidDataException(
                    $"Player scene {sceneIndex} must have an entity edit.");
        }
        var primaryPlayer = definition.EntityEdits.First(
            edit => edit.SceneIndex == definition.PlayerSceneIndices[0]);
        if (primaryPlayer.CellX != definition.PlayerSpawn.X ||
            primaryPlayer.CellY != definition.PlayerSpawn.Y)
            throw new InvalidDataException(
                "player_spawn must match the first player scene position.");

        var enemySet = definition.EnemySceneIndices.ToHashSet();
        if (enemySet.Count != definition.EnemySceneIndices.Count)
            throw new InvalidDataException(
                "enemy_scene_indices contains duplicates.");
        foreach (var sceneIndex in enemySet)
        {
            if (playerSet.Contains(sceneIndex))
                throw new InvalidDataException(
                    $"Scene {sceneIndex} cannot be both player and enemy.");
            if (!entities.ContainsKey(sceneIndex))
                throw new InvalidDataException(
                    $"Enemy scene {sceneIndex} does not exist.");
        }
    }

    private void ValidateSourceHash()
    {
        if (string.IsNullOrWhiteSpace(definition.SourceSha256))
            throw new InvalidDataException(
                "source_sha256 is required so the mission cannot be " +
                "generated from an incompatible source map.");
        var actual = Hash(sourcePath);
        if (!actual.Equals(
                definition.SourceSha256,
                StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidDataException(
                $"Source VWF hash mismatch. Expected " +
                $"{definition.SourceSha256}, actual {actual}.");
        }
    }

    private void ClearOriginalOccupancy()
    {
        for (var index = 0; index < cellCount; index++)
        {
            ClearEditedOccupant(lineOfSightLayerOffset, index);
            ClearEditedOccupant(movementLayerOffset, index);
        }
    }

    private void ClearEditedOccupant(int layerOffset, int index)
    {
        var offset = checked(layerOffset + index * sizeof(uint));
        var value = ReadUInt32(offset);
        if (editedOccupants.Contains(value))
            WriteUInt32(offset, 0);
    }

    private void ApplyEntityEdit(EntityEdit edit)
    {
        var entity = entities[edit.SceneIndex];
        var targetIndex = CellIndex(edit.CellX, edit.CellY);
        EnsureTargetOpen(lineOfSightLayerOffset, targetIndex, edit);
        EnsureTargetOpen(movementLayerOffset, targetIndex, edit);

        var occupancyValue = checked((uint)(edit.SceneIndex + 1000));
        WriteUInt32(
            checked(lineOfSightLayerOffset + targetIndex * sizeof(uint)),
            occupancyValue);
        WriteUInt32(
            checked(movementLayerOffset + targetIndex * sizeof(uint)),
            occupancyValue);

        var record = checked((int)entity.RecordOffset);
        var worldX = checked(edit.CellX * 32 + 16);
        var worldY = checked(edit.CellY * 16 + 8);
        var referenceDeltaX = entity.ReferenceX - entity.WorldX;
        var referenceDeltaY = entity.ReferenceY - entity.WorldY;
        WriteInt32(record + EntityPrefixWorldX, worldX);
        WriteInt32(record + EntityPrefixWorldY, worldY);
        WriteInt32(
            record + EntityPrefixReferenceX,
            checked(worldX + referenceDeltaX));
        WriteInt32(
            record + EntityPrefixReferenceY,
            checked(worldY + referenceDeltaY));
        if (edit.Direction.HasValue)
            WriteUInt32(
                record + EntityPrefixDirection,
                checked((uint)edit.Direction.Value));

        if (edit.Patrol is not null)
            ApplyPatrolEdit(
                entity,
                NormalizePatrolStart(
                    edit.Patrol,
                    new GridCell { X = edit.CellX, Y = edit.CellY }));
        else if (entity.Patrol is not null)
            ApplyPatrolEdit(
                entity,
                NormalizePatrolStart(
                    entity.Patrol.Waypoints
                        .Select(point => new GridCell
                        {
                            X = checked((int)point.X),
                            Y = checked((int)point.Y)
                        })
                        .ToList(),
                    new GridCell { X = edit.CellX, Y = edit.CellY }));
    }

    private void EnsureTargetOpen(
        int layerOffset, int targetIndex, EntityEdit edit)
    {
        if (layerOffset == lineOfSightLayerOffset &&
            playerScenes.Contains(edit.SceneIndex))
        {
            var ground = ReadUInt32(checked(
                groundLayerOffset + targetIndex * sizeof(uint)));
            if (ground == 0)
                throw new InvalidDataException(
                    $"Entity {edit.SceneIndex} target cell " +
                    $"({edit.CellX}, {edit.CellY}) has no ground tile. " +
                    $"Nearby open cells: " +
                    $"{NearbyOpenCells(edit.CellX, edit.CellY)}.");
        }
        var value = ReadUInt32(
            checked(layerOffset + targetIndex * sizeof(uint)));
        if (value != 0)
            throw new InvalidDataException(
                $"Entity {edit.SceneIndex} target cell " +
                $"({edit.CellX}, {edit.CellY}) is occupied by grid value {value}. " +
                $"Nearby open cells: {NearbyOpenCells(edit.CellX, edit.CellY)}.");
    }

    private string NearbyOpenCells(int originX, int originY)
    {
        var candidates = new List<string>();
        for (var radius = 1; radius <= 12 && candidates.Count < 8; radius++)
        {
            for (var y = originY - radius;
                 y <= originY + radius && candidates.Count < 8;
                 y++)
            {
                for (var x = originX - radius;
                     x <= originX + radius && candidates.Count < 8;
                     x++)
                {
                    if (Math.Max(
                            Math.Abs(x - originX),
                            Math.Abs(y - originY)) != radius ||
                        !InBounds(x, y))
                        continue;
                    var index = CellIndex(x, y);
                    var ground = ReadUInt32(checked(
                        groundLayerOffset + index * sizeof(uint)));
                    var lineOfSight = ReadUInt32(checked(
                        lineOfSightLayerOffset + index * sizeof(uint)));
                    var movement = ReadUInt32(checked(
                        movementLayerOffset + index * sizeof(uint)));
                    if (ground != 0 &&
                        lineOfSight == 0 &&
                        movement == 0)
                        candidates.Add($"({x},{y})");
                }
            }
        }
        return candidates.Count == 0
            ? "none within 12 cells"
            : string.Join(", ", candidates);
    }

    private void ApplyPatrolEdit(
        VwfSceneEntity entity, IReadOnlyList<GridCell> route)
    {
        var patrol = entity.Patrol!;
        var count = route.Count;
        var patrolOffset = checked((int)entity.RecordOffset + PatrolRecordOffset);
        var serializedCount = checked((int)ReadUInt32(patrolOffset + 4));
        if (serializedCount != count)
            throw new InvalidDataException(
                $"Entity {entity.SceneIndex} patrol count changed while editing.");

        var workingPointsOffset = patrolOffset + 12;
        var currentIndexOffset = checked(patrolOffset + 16 + count * 8);
        var cachedXOffset = checked(patrolOffset + 24 + count * 8);
        var cachedYOffset = checked(patrolOffset + 28 + count * 8);
        var waypointOffset = checked(patrolOffset + 32 + count * 8);
        for (var index = 0; index < count; index++)
        {
            var point = route[index];
            WriteUInt32(
                checked(workingPointsOffset + index * 8),
                checked((uint)point.X));
            WriteUInt32(
                checked(workingPointsOffset + index * 8 + 4),
                checked((uint)point.Y));
            WriteUInt32(
                checked(waypointOffset + index * 8),
                checked((uint)point.X));
            WriteUInt32(
                checked(waypointOffset + index * 8 + 4),
                checked((uint)point.Y));
        }
        WriteUInt32(currentIndexOffset, 0);
        if (count > 0)
        {
            WriteInt32(cachedXOffset, checked(route[0].X * 32 + 16));
            WriteInt32(cachedYOffset, checked(route[0].Y * 16 + 8));
        }
        else
        {
            WriteInt32(cachedXOffset, patrol.CachedWaypointWorldX);
            WriteInt32(cachedYOffset, patrol.CachedWaypointWorldY);
        }
    }

    private IReadOnlyList<PathValidation> ValidateNavigation()
    {
        var results = new List<PathValidation>();
        var failures = new List<string>();
        var spawn = definition.PlayerSpawn;
        if (definition.MovementProbe is not null)
        {
            var probe = definition.MovementProbe;
            var probeIndex = CellIndex(probe.X, probe.Y);
            var ground = ReadUInt32(checked(
                groundLayerOffset + probeIndex * sizeof(uint)));
            var occupant = ReadUInt32(checked(
                movementLayerOffset + probeIndex * sizeof(uint)));
            var length = FindPathLength(spawn, probe);
            if (ground == 0)
            {
                failures.Add(
                    $"Movement probe “{probe.Name}” at " +
                    $"({probe.X}, {probe.Y}) has no visible ground tile. " +
                    $"Nearby open cells: " +
                    $"{NearbyOpenCells(probe.X, probe.Y)}.");
            }
            else if (occupant != 0)
            {
                failures.Add(
                    $"Movement probe “{probe.Name}” at " +
                    $"({probe.X}, {probe.Y}) is occupied by grid value " +
                    $"{occupant}. Nearby open cells: " +
                    $"{NearbyOpenCells(probe.X, probe.Y)}.");
            }
            else if (length <= 0)
            {
                failures.Add(
                    $"Movement probe “{probe.Name}” must be a distinct, " +
                    "reachable empty cell.");
            }
            else
            {
                results.Add(new PathValidation(
                    $"自动实机移动探针 → {probe.Name}",
                    spawn.X, spawn.Y, probe.X, probe.Y, length));
            }
        }
        foreach (var target in definition.RequiredReachability)
        {
            var length = FindPathLength(spawn, target);
            if (length < 0)
            {
                failures.Add(
                    $"No traversable path from player spawn to “{target.Name}” " +
                    $"at ({target.X}, {target.Y}).");
            }
            else
            {
                results.Add(new PathValidation(
                    $"玩家出生点 → {target.Name}",
                    spawn.X, spawn.Y, target.X, target.Y, length));
            }
        }
        foreach (var target in definition.RequiredSceneReachability)
        {
            var targetCell = EffectiveCell(target.SceneIndex);
            var length = FindPathLength(spawn, targetCell);
            if (length < 0)
            {
                failures.Add(
                    $"No traversable path from player spawn to scene " +
                    $"{target.SceneIndex} “{target.Name}” at " +
                    $"({targetCell.X}, {targetCell.Y}).");
            }
            else
            {
                results.Add(new PathValidation(
                    $"玩家出生点 → {target.Name}（scene {target.SceneIndex}）",
                    spawn.X, spawn.Y,
                    targetCell.X, targetCell.Y, length));
            }
        }

        // A full district composition can opt into auditing every serialized
        // patrol. Topology-preserving missions validate only their edited
        // deployment because the original mission script owns the remaining
        // routes and may rewrite them after load.
        var patrolSceneIndices =
            definition.ValidateAllSerializedPatrols
                ? entities.Values.Select(entity => entity.SceneIndex)
                : definition.EntityEdits.Select(edit => edit.SceneIndex);
        foreach (var sceneIndex in patrolSceneIndices.Distinct())
        {
            var route = EffectivePatrol(sceneIndex);
            if (route.Count == 0)
                continue;
            var start = EffectiveCell(sceneIndex);
            var points = new List<GridCell>
            {
                start
            };
            points.AddRange(route);
            for (var index = 1; index < points.Count; index++)
            {
                var length = FindPathLength(points[index - 1], points[index]);
                if (length < 0)
                {
                    failures.Add(
                        $"Entity {sceneIndex} patrol segment " +
                        $"{index} is not traversable: " +
                        $"({points[index - 1].X}, {points[index - 1].Y}) → " +
                        $"({points[index].X}, {points[index].Y}).");
                }
                else
                {
                    if (definition.MaximumPatrolSegmentPathLength > 0 &&
                        length >
                        definition.MaximumPatrolSegmentPathLength)
                    {
                        failures.Add(
                            $"Entity {sceneIndex} patrol segment " +
                            $"{index} requires {length} A* steps; the mission " +
                            $"limit is " +
                            $"{definition.MaximumPatrolSegmentPathLength}. " +
                            "Long live patrol replans can stall the original " +
                            "single-threaded engine.");
                        continue;
                    }
                    results.Add(new PathValidation(
                        $"场景 {sceneIndex} 巡逻段 {index}",
                        points[index - 1].X, points[index - 1].Y,
                        points[index].X, points[index].Y, length));
                }
            }
        }
        if (failures.Count > 0)
            throw new InvalidDataException(string.Join(
                Environment.NewLine, failures));
        return results;
    }

    private SpawnSafetyValidation ValidateSpawnSafety()
    {
        var playerSet = definition.PlayerSceneIndices.ToHashSet();
        var players = definition.EntityEdits
            .Where(edit => playerSet.Contains(edit.SceneIndex))
            .ToList();
        var enemySceneIndices = definition.EnemySceneIndices.Count > 0
            ? definition.EnemySceneIndices
            : definition.EntityEdits
                .Where(edit => !playerSet.Contains(edit.SceneIndex))
                .Select(edit => edit.SceneIndex)
                .ToList();
        if (enemySceneIndices.Count == 0)
            throw new InvalidDataException(
                "Spawn safety validation requires at least one enemy scene.");

        var failures = new List<string>();
        var minimumInitial = int.MaxValue;
        var minimumPatrol = int.MaxValue;
        var initialPair = "";
        var patrolPair = "";
        foreach (var player in players)
        {
            var playerCell = new GridCell
            {
                X = player.CellX,
                Y = player.CellY
            };
            foreach (var enemySceneIndex in enemySceneIndices)
            {
                var enemyCell = EffectiveCell(enemySceneIndex);
                var initialDistance = WorldDistance(
                    playerCell, enemyCell);
                if (initialDistance < minimumInitial)
                {
                    minimumInitial = initialDistance;
                    initialPair =
                        $"玩家 {player.SceneIndex} / 敌方 {enemySceneIndex}";
                }
                if (initialDistance <
                    definition.MinimumSpawnEnemyDistanceWorld)
                {
                    failures.Add(
                        $"Player {player.SceneIndex} is only " +
                        $"{initialDistance} world units from enemy " +
                        $"{enemySceneIndex}; required minimum is " +
                        $"{definition.MinimumSpawnEnemyDistanceWorld}.");
                }

                foreach (var point in EffectivePatrol(enemySceneIndex))
                {
                    var patrolDistance = WorldDistance(
                        playerCell, point);
                    if (patrolDistance < minimumPatrol)
                    {
                        minimumPatrol = patrolDistance;
                        patrolPair =
                            $"玩家 {player.SceneIndex} / 敌方 " +
                            $"{enemySceneIndex} 巡逻点 " +
                            $"({point.X},{point.Y})";
                    }
                    if (patrolDistance <
                        definition.MinimumSpawnPatrolDistanceWorld)
                    {
                        failures.Add(
                            $"Player {player.SceneIndex} is only " +
                            $"{patrolDistance} world units from enemy " +
                            $"{enemySceneIndex} patrol point " +
                            $"({point.X}, {point.Y}); required minimum is " +
                            $"{definition.MinimumSpawnPatrolDistanceWorld}.");
                    }
                }
            }
        }
        if (failures.Count > 0)
            throw new InvalidDataException(string.Join(
                Environment.NewLine, failures));
        if (minimumPatrol == int.MaxValue)
        {
            minimumPatrol = minimumInitial;
            patrolPair = "无独立巡逻点；采用最近初始部署";
        }
        return new SpawnSafetyValidation(
            minimumInitial, initialPair,
            minimumPatrol, patrolPair);
    }

    private GridCell EffectiveCell(int sceneIndex)
    {
        var edit = definition.EntityEdits.FirstOrDefault(
            item => item.SceneIndex == sceneIndex);
        if (edit is not null)
            return new GridCell { X = edit.CellX, Y = edit.CellY };
        var entity = entities[sceneIndex];
        return new GridCell
        {
            X = entity.WorldX / 32,
            Y = entity.WorldY / 16
        };
    }

    private IReadOnlyList<GridCell> EffectivePatrol(int sceneIndex)
    {
        var edit = definition.EntityEdits.FirstOrDefault(
            item => item.SceneIndex == sceneIndex);
        if (edit?.Patrol is not null)
            return NormalizePatrolStart(
                edit.Patrol,
                new GridCell { X = edit.CellX, Y = edit.CellY });
        var patrol = entities[sceneIndex].Patrol;
        if (patrol is null)
            return [];
        return NormalizePatrolStart(
            patrol.Waypoints
            .Select(point => new GridCell
            {
                X = checked((int)point.X),
                Y = checked((int)point.Y)
            })
            .ToList(),
            EffectiveCell(sceneIndex));
    }

    private static IReadOnlyList<GridCell> NormalizePatrolStart(
        IReadOnlyList<GridCell> route, GridCell spawn)
    {
        // The original engine immediately replans every zero-length first
        // segment. A mission with many redeployed patrols can therefore hitch
        // on its first active frame. Patrol arrays are cyclic, so rotating a
        // leading spawn waypoint to the end preserves the route while making
        // every actor begin with a real movement segment.
        if (route.Count <= 1 ||
            route[0].X != spawn.X ||
            route[0].Y != spawn.Y)
            return route;

        var normalized = new List<GridCell>(route.Count);
        for (var index = 1; index < route.Count; index++)
            normalized.Add(route[index]);
        normalized.Add(route[0]);
        return normalized;
    }

    private static int WorldDistance(GridCell left, GridCell right)
    {
        var deltaX = checked((left.X - right.X) * 32L);
        var deltaY = checked((left.Y - right.Y) * 16L);
        return checked((int)Math.Round(
            Math.Sqrt(deltaX * deltaX + deltaY * deltaY)));
    }

    private int FindPathLength(GridCell start, GridCell goal)
    {
        var startIndex = CellIndex(start.X, start.Y);
        var goalIndex = CellIndex(goal.X, goal.Y);
        var distances = new int[cellCount];
        Array.Fill(distances, int.MaxValue);
        var closed = new bool[cellCount];
        var open = new PriorityQueue<int, int>();
        distances[startIndex] = 0;
        open.Enqueue(
            startIndex,
            GridHeuristic(start.X, start.Y, goal.X, goal.Y));
        ReadOnlySpan<int> dx = [-1, 1, 0, 0, -1, 1, -1, 1];
        ReadOnlySpan<int> dy = [0, 0, -1, 1, -1, -1, 1, 1];

        while (open.TryDequeue(out var current, out _))
        {
            if (closed[current])
                continue;
            closed[current] = true;
            if (current == goalIndex)
                return distances[current];
            var x = current % checked((int)world.GridWidth);
            var y = current / checked((int)world.GridWidth);
            for (var direction = 0; direction < dx.Length; direction++)
            {
                var nextX = x + dx[direction];
                var nextY = y + dy[direction];
                if (!InBounds(nextX, nextY))
                    continue;
                var next = CellIndex(nextX, nextY);
                if (closed[next] || !IsTraversable(next))
                    continue;
                if (dx[direction] != 0 && dy[direction] != 0 &&
                    (!IsTraversable(CellIndex(x + dx[direction], y)) ||
                     !IsTraversable(CellIndex(x, y + dy[direction]))))
                    continue;
                var nextDistance = distances[current] + 1;
                if (nextDistance >= distances[next])
                    continue;
                distances[next] = nextDistance;
                open.Enqueue(
                    next,
                    nextDistance + GridHeuristic(
                        nextX, nextY, goal.X, goal.Y));
            }
        }
        return -1;
    }

    private static int GridHeuristic(
        int x, int y, int goalX, int goalY) =>
        Math.Max(Math.Abs(goalX - x), Math.Abs(goalY - y));

    private NavigationCoverage ValidateNavigationCoverage()
    {
        var traversable = Enumerable.Range(0, cellCount)
            .Count(IsTraversable);
        var visited = new bool[cellCount];
        var queue = new Queue<int>();
        var start = CellIndex(
            definition.PlayerSpawn.X,
            definition.PlayerSpawn.Y);
        if (!IsTraversable(start))
            throw new InvalidDataException(
                "Player spawn is not on a traversable cell.");

        visited[start] = true;
        queue.Enqueue(start);
        var reachable = 0;
        ReadOnlySpan<int> dx = [-1, 1, 0, 0, -1, 1, -1, 1];
        ReadOnlySpan<int> dy = [0, 0, -1, 1, -1, -1, 1, 1];
        while (queue.TryDequeue(out var current))
        {
            reachable++;
            var x = current % checked((int)world.GridWidth);
            var y = current / checked((int)world.GridWidth);
            for (var direction = 0; direction < dx.Length; direction++)
            {
                var nextX = x + dx[direction];
                var nextY = y + dy[direction];
                if (!InBounds(nextX, nextY))
                    continue;
                var next = CellIndex(nextX, nextY);
                if (visited[next] || !IsTraversable(next))
                    continue;
                if (dx[direction] != 0 && dy[direction] != 0 &&
                    (!IsTraversable(CellIndex(x + dx[direction], y)) ||
                     !IsTraversable(CellIndex(x, y + dy[direction]))))
                    continue;
                visited[next] = true;
                queue.Enqueue(next);
            }
        }

        var ratio = traversable == 0
            ? 0
            : reachable / (double)traversable;
        if (ratio + 1e-9 <
            definition.MinimumReachableWalkableRatio)
        {
            throw new InvalidDataException(
                $"Only {reachable}/{traversable} traversable cells " +
                $"({ratio:P2}) are reachable from the player spawn; " +
                $"required minimum is " +
                $"{definition.MinimumReachableWalkableRatio:P2}.");
        }
        return new NavigationCoverage(reachable, traversable, ratio);
    }

    private bool IsTraversable(int index)
    {
        var movement = ReadUInt32(
            checked(movementLayerOffset + index * sizeof(uint)));
        // Mirror the original engine: navigation is governed by the movement
        // plane, while the ground plane is visual data. Actor/task endpoints
        // are checked separately by EnsureTargetOpen so they can never be
        // deployed into an invisible ground hole.
        return movement == 0 || editedOccupants.Contains(movement);
    }

    private string BuildReport(
        string sourceHash,
        string outputHash,
        string outputPath,
        VwfSceneList outputScenes,
        InitialViewport initialViewport,
        SpawnSafetyValidation spawnSafety,
        NavigationCoverage navigationCoverage,
        IReadOnlyList<PathValidation> validations)
    {
        var builder = new StringBuilder();
        builder.AppendLine($"# {definition.Title}（{definition.Id}）生成与验证报告");
        builder.AppendLine();
        builder.AppendLine(definition.Story);
        builder.AppendLine();
        builder.AppendLine("## 文件与结构");
        builder.AppendLine();
        builder.AppendLine($"- 源文件：`{Path.GetFileName(sourcePath)}`");
        builder.AppendLine($"- 输出文件：`{Path.GetFileName(outputPath)}`");
        builder.AppendLine($"- 地图网格：{world.GridWidth} × {world.GridHeight}");
        builder.AppendLine($"- 场景槽位：{outputScenes.SlotCount}");
        builder.AppendLine($"- 有效场景对象：{outputScenes.Entities.Count}");
        builder.AppendLine($"- 重部署活动对象：{definition.EntityEdits.Count}");
        builder.AppendLine($"- 源 SHA-256：`{sourceHash}`");
        builder.AppendLine($"- 输出 SHA-256：`{outputHash}`");
        builder.AppendLine();
        builder.AppendLine("## 出生区安全");
        builder.AppendLine();
        builder.AppendLine(
            $"- 最近敌方初始部署：{spawnSafety.MinimumInitialDistance} " +
            $"世界单位（{spawnSafety.InitialPair}）");
        builder.AppendLine(
            $"- 最近敌方巡逻点：{spawnSafety.MinimumPatrolDistance} " +
            $"世界单位（{spawnSafety.PatrolPair}）");
        builder.AppendLine(
            $"- 硬性阈值：初始部署 " +
            $"{definition.MinimumSpawnEnemyDistanceWorld}，巡逻点 " +
            $"{definition.MinimumSpawnPatrolDistanceWorld} 世界单位");
        builder.AppendLine();
        builder.AppendLine("## 全图连通性");
        builder.AppendLine();
        builder.AppendLine(
            $"- 从出生点可达通行格：" +
            $"{navigationCoverage.ReachableCells:N0}/" +
            $"{navigationCoverage.TraversableCells:N0} " +
            $"（{navigationCoverage.Ratio:P2}）");
        builder.AppendLine(
            $"- 关卡要求的最低覆盖率：" +
            $"{definition.MinimumReachableWalkableRatio:P2}");
        if (definition.MaximumPatrolSegmentPathLength > 0)
        {
            builder.AppendLine(
                $"- 单段巡逻 A* 硬上限：" +
                $"{definition.MaximumPatrolSegmentPathLength} 步");
        }
        builder.AppendLine();
        builder.AppendLine("## 可达性验证");
        builder.AppendLine();
        builder.AppendLine("| 路径 | 起点 | 终点 | A* 步数 |");
        builder.AppendLine("|---|---:|---:|---:|");
        foreach (var validation in validations)
        {
            builder.AppendLine(
                $"| {validation.Name} | " +
                $"({validation.StartX}, {validation.StartY}) | " +
                $"({validation.EndX}, {validation.EndY}) | " +
                $"{validation.Length} |");
        }
        builder.AppendLine();
        builder.AppendLine(
            "所有必达目标和每一段巡逻路线均通过八方向 A* 校验；" +
            "对角移动禁止穿越两块相邻障碍物的夹角。");
        return builder.ToString();
    }

    private int LayerDataOffset(int zeroBasedLayer)
    {
        var planeSize = checked(16 + cellCount * sizeof(uint));
        return checked(
            VwfTerrainGrid.PreambleSize +
            zeroBasedLayer * planeSize + 16);
    }

    private int CellIndex(int x, int y) =>
        checked(y * checked((int)world.GridWidth) + x);

    private bool InBounds(int x, int y) =>
        x >= 0 && x < world.GridWidth &&
        y >= 0 && y < world.GridHeight;

    private void ValidateCell(int x, int y, string description)
    {
        if (!InBounds(x, y))
            throw new InvalidDataException(
                $"{description} cell ({x}, {y}) lies outside " +
                $"{world.GridWidth}x{world.GridHeight}.");
    }

    private uint ReadUInt32(int offset) =>
        BinaryPrimitives.ReadUInt32LittleEndian(data.AsSpan(offset, 4));

    private void WriteUInt32(int offset, uint value) =>
        BinaryPrimitives.WriteUInt32LittleEndian(
            data.AsSpan(offset, 4), value);

    private void WriteInt32(int offset, int value) =>
        BinaryPrimitives.WriteInt32LittleEndian(
            data.AsSpan(offset, 4), value);

    private static string Hash(string path)
    {
        using var stream = File.OpenRead(path);
        return Convert.ToHexString(SHA256.HashData(stream));
    }

    private sealed record PathValidation(
        string Name,
        int StartX,
        int StartY,
        int EndX,
        int EndY,
        int Length);

    private sealed record SpawnSafetyValidation(
        int MinimumInitialDistance,
        string InitialPair,
        int MinimumPatrolDistance,
        string PatrolPair);

    private sealed record NavigationCoverage(
        int ReachableCells,
        int TraversableCells,
        double Ratio);

    private sealed record InitialViewport(
        int Left,
        int Top,
        int Right,
        int Bottom);
}
