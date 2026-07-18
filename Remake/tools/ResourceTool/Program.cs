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
            "list-gfl" => ListGfl(args),
            "extract-gfl" => ExtractGfl(args),
            "import" => Import(args),
            "media-catalog" => MediaCatalog(args),
            _ => UnknownCommand(args[0])
        };
    }

    private static int Inspect(string[] args)
    {
        RequireArgumentCount(args, 2, 2, "inspect <game-directory>");
        var report = GameDirectoryProbe.Inspect(args[1]);

        Console.WriteLine($"Directory: {report.DirectoryPath}");
        Console.WriteLine($"Plausible original directory: {report.IsPlausibleOriginalDirectory}");
        Console.WriteLine($"Known version hashes match: {report.KnownVersion.IsMatch}");
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

    private static int ListGfl(string[] args)
    {
        RequireArgumentCount(args, 2, 3, "list-gfl <1937Resources.GFL> [InterMedia.GFL]");
        var archive = GflArchive.Open(args[1], args.Length == 3 ? args[2] : null);
        foreach (var group in archive.Entries.GroupBy(entry => entry.Type).OrderByDescending(group => group.Count()))
        {
            Console.WriteLine($"{group.Key,-8} {group.Count(),4} entries, {group.Sum(entry => (long)entry.Length),12} bytes");
        }

        Console.WriteLine($"Total: {archive.Entries.Count} entries");
        foreach (var entry in archive.Entries.Take(10))
        {
            Console.WriteLine($"  {entry.Index:D4} {entry.Type,-8} {entry.OriginalName}");
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
                "The selected directory does not match the known supported hashes. " +
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
        Console.WriteLine("  list-gfl <1937Resources.GFL> [InterMedia.GFL]");
        Console.WriteLine("  extract-gfl <1937Resources.GFL> <output-directory> [InterMedia.GFL]");
        Console.WriteLine("  import <game-directory> <output-directory>");
        Console.WriteLine("  media-catalog <game-directory> <converted-directory>");
        Console.WriteLine();
        Console.WriteLine("Repository-local output directories must be ignored by Git.");
    }
}
