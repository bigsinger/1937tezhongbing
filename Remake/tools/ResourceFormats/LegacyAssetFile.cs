namespace Mission1937.Remake.Resources;

public sealed record LegacyAssetFile(
    string Name,
    long Length,
    string Format,
    string? Detail);

public sealed record GameDirectoryReport(
    string DirectoryPath,
    bool IsPlausibleOriginalDirectory,
    int FormalLevelCount,
    IReadOnlyList<string> Warnings,
    IReadOnlyList<LegacyAssetFile> Files,
    IReadOnlyList<VwfLevelSummary> Levels,
    KnownVersionValidation KnownVersion,
    SoundLibrarySummary? SoundLibrary,
    GflArchiveSummary? ResourceArchive);

public sealed record GflArchiveSummary(
    int EntryCount,
    int NamedEntryCount,
    long PayloadBytes,
    IReadOnlyDictionary<string, int> TypeCounts);

public sealed record SoundLibrarySummary(
    int EntryCount,
    int MappedToGflCount,
    IReadOnlyList<string> UnmatchedNames);

public sealed record VwfLevelSummary(
    string Name,
    uint ViewportWidth,
    uint ViewportHeight,
    int ViewportLeft,
    int ViewportTop,
    int ViewportRight,
    int ViewportBottom,
    uint GridWidth,
    uint GridHeight,
    uint GridCellParameter,
    long SceneListOffset);

public sealed record KnownVersionFileHash(
    string Name,
    string ExpectedSha256,
    string? ActualSha256,
    bool Matches);

public sealed record KnownVersionValidation(
    string VersionId,
    bool IsMatch,
    IReadOnlyList<KnownVersionFileHash> Files);
