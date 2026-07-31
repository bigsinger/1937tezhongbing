using System.Buffers.Binary;
using System.Security.Cryptography;

namespace Mission1937.Remake.Resources;

public sealed record LegacySaveLevelMatch(
    int LevelIndex,
    string LevelId,
    string BaseWorldPath,
    string TerrainSha256);

public sealed record LegacySaveEntityChange(
    int SceneIndex,
    int BaseDatabaseEntryId,
    int SavedDatabaseEntryId,
    int BaseReferenceX,
    int BaseReferenceY,
    int SavedReferenceX,
    int SavedReferenceY,
    uint BaseDirectionIndex,
    uint SavedDirectionIndex,
    uint BaseDeathState,
    uint SavedDeathState,
    uint BaseCrawlState,
    uint SavedCrawlState,
    uint BaseHitPoints,
    uint SavedHitPoints);

/// <summary>
/// A read-only original campaign save. The original SAV is a complete VWF
/// snapshot, so its static terrain can identify the source level exactly and
/// its SLIST1 can be compared by stable scene slot.
/// </summary>
public sealed class LegacySaveSnapshot
{
    private LegacySaveSnapshot(
        string path,
        LegacySaveLevelMatch level,
        VwfWorldHeader world,
        VwfTerrainGrid terrain,
        VwfSceneList sceneList,
        VwfSceneList baseSceneList,
        IReadOnlyList<int> removedSceneIndices,
        IReadOnlyList<VwfSceneEntity> addedEntities,
        IReadOnlyList<LegacySaveEntityChange> changedEntities)
    {
        Path = path;
        Level = level;
        World = world;
        Terrain = terrain;
        SceneList = sceneList;
        BaseSceneList = baseSceneList;
        RemovedSceneIndices = removedSceneIndices;
        AddedEntities = addedEntities;
        ChangedEntities = changedEntities;
    }

    public string Path { get; }

    public LegacySaveLevelMatch Level { get; }

    public VwfWorldHeader World { get; }

    public VwfTerrainGrid Terrain { get; }

    public VwfSceneList SceneList { get; }

    public VwfSceneList BaseSceneList { get; }

    public IReadOnlyList<int> RemovedSceneIndices { get; }

    public IReadOnlyList<VwfSceneEntity> AddedEntities { get; }

    public IReadOnlyList<LegacySaveEntityChange> ChangedEntities { get; }

    public static LegacySaveSnapshot Open(
        string savePath,
        string gameDirectory,
        DblDatabase? database = null)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(savePath);
        ArgumentException.ThrowIfNullOrWhiteSpace(gameDirectory);
        var fullSavePath = System.IO.Path.GetFullPath(savePath);
        var fullGameDirectory = System.IO.Path.GetFullPath(gameDirectory);
        if (!Directory.Exists(fullGameDirectory))
        {
            throw new DirectoryNotFoundException(
                $"The original game directory does not exist: {fullGameDirectory}");
        }

        var world = VwfWorldHeader.Open(fullSavePath);
        var terrain = VwfTerrainGrid.Open(fullSavePath, database);
        var saveTerrainFingerprint = TerrainIdentityFingerprint(terrain);
        var matches = new List<LegacySaveLevelMatch>();
        for (var levelIndex = 0; levelIndex < 12; levelIndex++)
        {
            var basePath = System.IO.Path.Combine(
                fullGameDirectory,
                $"1937m{levelIndex:D3}.vwf");
            if (!File.Exists(basePath))
            {
                continue;
            }

            var baseTerrain = VwfTerrainGrid.Open(basePath, database);
            var baseFingerprint = TerrainIdentityFingerprint(baseTerrain);
            if (baseFingerprint.Equals(
                    saveTerrainFingerprint,
                    StringComparison.OrdinalIgnoreCase))
            {
                matches.Add(new LegacySaveLevelMatch(
                    levelIndex,
                    $"m{levelIndex:D3}",
                    basePath,
                    baseFingerprint));
            }
        }

        if (matches.Count != 1)
        {
            throw new InvalidDataException(
                $"The legacy save terrain matched {matches.Count} formal levels; expected exactly one.");
        }

        var level = matches[0];
        var sceneList = VwfSceneList.Open(fullSavePath, database);
        var baseSceneList = VwfSceneList.Open(level.BaseWorldPath, database);
        var savedByScene = sceneList.Entities.ToDictionary(
            entity => entity.SceneIndex);
        var baseByScene = baseSceneList.Entities.ToDictionary(
            entity => entity.SceneIndex);
        var removedSceneIndices = baseByScene.Keys
            .Where(sceneIndex => !savedByScene.ContainsKey(sceneIndex))
            .Order()
            .ToArray();
        var addedEntities = savedByScene
            .Where(pair => !baseByScene.ContainsKey(pair.Key))
            .OrderBy(pair => pair.Key)
            .Select(pair => pair.Value)
            .ToArray();
        var changedEntities = baseByScene
            .Where(pair =>
                savedByScene.TryGetValue(pair.Key, out var saved) &&
                EntityStateChanged(pair.Value, saved))
            .OrderBy(pair => pair.Key)
            .Select(pair =>
            {
                var original = pair.Value;
                var saved = savedByScene[pair.Key];
                return new LegacySaveEntityChange(
                    pair.Key,
                    original.DatabaseEntryId,
                    saved.DatabaseEntryId,
                    original.ReferenceX,
                    original.ReferenceY,
                    saved.ReferenceX,
                    saved.ReferenceY,
                    original.DirectionIndex,
                    saved.DirectionIndex,
                    original.DeathState,
                    saved.DeathState,
                    original.CrawlState,
                    saved.CrawlState,
                    original.CurrentHitPoints,
                    saved.CurrentHitPoints);
            })
            .ToArray();

        return new LegacySaveSnapshot(
            fullSavePath,
            level,
            world,
            terrain,
            sceneList,
            baseSceneList,
            removedSceneIndices,
            addedEntities,
            changedEntities);
    }

    public static string TerrainFingerprint(VwfTerrainGrid terrain)
    {
        ArgumentNullException.ThrowIfNull(terrain);
        using var hash = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
        var valueBytes = new byte[sizeof(uint)];
        Append(terrain.Width);
        Append(terrain.Height);
        foreach (var layer in terrain.Layers)
        {
            Append(layer.Id);
            Append(layer.Width);
            Append(layer.Height);
            Append(checked((uint)layer.Values.Count));
            foreach (var value in layer.Values)
            {
                Append(value);
            }
        }

        return Convert.ToHexString(hash.GetHashAndReset());

        void Append(uint value)
        {
            BinaryPrimitives.WriteUInt32LittleEndian(valueBytes, value);
            hash.AppendData(valueBytes);
        }
    }

    /// <summary>
    /// Stable level identity derived from L1 only. Original saves rewrite
    /// dynamic actor footprints in L2/L3, while the authored ground tile
    /// plane remains immutable.
    /// </summary>
    public static string TerrainIdentityFingerprint(VwfTerrainGrid terrain)
    {
        ArgumentNullException.ThrowIfNull(terrain);
        using var hash = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
        var valueBytes = new byte[sizeof(uint)];
        Append(terrain.Width);
        Append(terrain.Height);
        var ground = terrain.Layers[0];
        Append(ground.Id);
        Append(checked((uint)ground.Values.Count));
        foreach (var value in ground.Values)
        {
            Append(value);
        }

        return Convert.ToHexString(hash.GetHashAndReset());

        void Append(uint value)
        {
            BinaryPrimitives.WriteUInt32LittleEndian(valueBytes, value);
            hash.AppendData(valueBytes);
        }
    }

    private static bool EntityStateChanged(
        VwfSceneEntity original,
        VwfSceneEntity saved) =>
        original.DatabaseEntryId != saved.DatabaseEntryId ||
        original.ReferenceX != saved.ReferenceX ||
        original.ReferenceY != saved.ReferenceY ||
        original.DirectionIndex != saved.DirectionIndex ||
        original.DeathState != saved.DeathState ||
        original.CrawlState != saved.CrawlState ||
        original.CurrentHitPoints != saved.CurrentHitPoints ||
        !original.AuxiliaryArrays
            .SelectMany(array => array)
            .SequenceEqual(saved.AuxiliaryArrays.SelectMany(array => array)) ||
        !original.AuxiliaryArrayLengths.SequenceEqual(
            saved.AuxiliaryArrayLengths);
}
