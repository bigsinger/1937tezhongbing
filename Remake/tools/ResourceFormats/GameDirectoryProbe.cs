namespace Mission1937.Remake.Resources;

public static class GameDirectoryProbe
{
    private static readonly string[] RequiredFiles =
    [
        "M1937.exe",
        "1937Resources.GFL",
        "1937Database.dbl",
        "1937Sound.slf",
        "1937m000.vwf"
    ];

    public static GameDirectoryReport Inspect(string directoryPath)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(directoryPath);

        var directory = new DirectoryInfo(directoryPath);
        if (!directory.Exists)
        {
            throw new DirectoryNotFoundException($"Game directory was not found: {directory.FullName}");
        }

        var files = directory.GetFiles()
            .OrderBy(file => file.Name, StringComparer.OrdinalIgnoreCase)
            .Select(file => LegacyFileDetector.Detect(file.FullName))
            .ToArray();
        var byName = files.ToDictionary(file => file.Name, StringComparer.OrdinalIgnoreCase);

        var warnings = new List<string>();
        foreach (var requiredFile in RequiredFiles)
        {
            if (!byName.ContainsKey(requiredFile))
            {
                warnings.Add($"Missing expected file: {requiredFile}");
            }
        }

        var levels = new List<VwfLevelSummary>();
        for (var index = 0; index <= 11; index++)
        {
            var name = $"1937m{index:D3}.vwf";
            if (byName.TryGetValue(name, out var level) && level.Format == "VWF")
            {
                try
                {
                    levels.Add(VwfWorldHeader.Open(System.IO.Path.Combine(directory.FullName, name)).ToSummary());
                }
                catch (InvalidDataException exception)
                {
                    warnings.Add($"Structurally invalid formal level {name}: {exception.Message}");
                }
            }
            else
            {
                warnings.Add($"Expected formal level is missing or has an unexpected format: {name}");
            }
        }

        if (byName.TryGetValue("1937m012.vwf", out var level12) && level12.Format != "VWF")
        {
            warnings.Add($"1937m012.vwf is actually {level12.Format}; it is not treated as a formal level.");
        }

        foreach (var index in Enumerable.Range(13, 3))
        {
            var name = $"1937m{index:D3}.vwf";
            if (byName.TryGetValue(name, out var extraLevel) && extraLevel.Format != "VWF")
            {
                warnings.Add($"{name} is actually {extraLevel.Format}; it is not treated as a formal level.");
            }
        }

        GflArchive? archive = null;
        GflArchiveSummary? resourceSummary = null;
        var resourcePath = System.IO.Path.Combine(directory.FullName, "1937Resources.GFL");
        if (File.Exists(resourcePath))
        {
            var indexPath = System.IO.Path.Combine(directory.FullName, "InterMedia.GFL");
            archive = GflArchive.Open(resourcePath, File.Exists(indexPath) ? indexPath : null);
            resourceSummary = archive.GetSummary();
        }

        SoundLibrarySummary? soundLibrarySummary = null;
        var soundLibraryPath = System.IO.Path.Combine(directory.FullName, "1937Sound.slf");
        if (File.Exists(soundLibraryPath))
        {
            var soundLibrary = SoundLibrary.Open(soundLibraryPath);
            var resourceNames = archive?.Entries
                .Where(entry => entry.Type == "WAV")
                .Select(entry => entry.OriginalName)
                .ToHashSet(StringComparer.OrdinalIgnoreCase) ?? [];
            var unmatchedNames = soundLibrary.Entries
                .Select(entry => entry.FileName)
                .Where(name => !resourceNames.Contains(name))
                .ToArray();
            soundLibrarySummary = new SoundLibrarySummary(
                soundLibrary.Entries.Count,
                soundLibrary.Entries.Count - unmatchedNames.Length,
                unmatchedNames);
            foreach (var unmatchedName in unmatchedNames)
            {
                warnings.Add($"SLF sound name is not present in the GFL WAV resources: {unmatchedName}");
            }
        }

        var knownVersion = KnownOriginalVersion.Validate(directory.FullName);
        if (!knownVersion.IsMatch)
        {
            foreach (var hash in knownVersion.Files.Where(hash => !hash.Matches))
            {
                warnings.Add($"Known-version hash mismatch: {hash.Name}");
            }
        }

        return new GameDirectoryReport(
            directory.FullName,
            RequiredFiles.All(byName.ContainsKey) && levels.Count == 12,
            levels.Count,
            warnings,
            files,
            levels,
            knownVersion,
            soundLibrarySummary,
            resourceSummary);
    }
}
