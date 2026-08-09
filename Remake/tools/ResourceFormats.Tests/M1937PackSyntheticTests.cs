using System.IO.Compression;
using System.Text;
using System.Text.Json;
using Mission1937.Remake.Resources;

namespace Mission1937.Remake.ResourceFormats.Tests;

internal static class M1937PackSyntheticTests
{
    private static int _checks;

    public static int Run(string temporaryRoot)
    {
        _checks = 0;
        BuildsValidatesAndExtracts(temporaryRoot);
        RejectsTraversal(temporaryRoot);
        RejectsExecutablePayload(temporaryRoot);
        RejectsCaseCollision(temporaryRoot);
        RejectsTamperedHash(temporaryRoot);
        RejectsInvalidSemanticVersion(temporaryRoot);
        RejectsOversizedImageHeader(temporaryRoot);
        return _checks;
    }

    private static void BuildsValidatesAndExtracts(string root)
    {
        var source = Path.Combine(root, "pack-source");
        Directory.CreateDirectory(Path.Combine(source, "levels", "training"));
        File.WriteAllText(
            Path.Combine(source, "campaign.json"),
            "{\"schema_version\":1,\"levels\":[{\"id\":\"training\"}]}");
        File.WriteAllText(
            Path.Combine(source, "levels", "training", "level.json"),
            "{\"schema_version\":1,\"world_size\":{\"width\":8,\"height\":8},\"entities\":[]}");
        File.WriteAllText(
            Path.Combine(source, "levels", "training", "mission.json"),
            "{\"schema_version\":1,\"objectives\":[]}");
        var manifest = new M1937PackManifest
        {
            PackId = "synthetic.training",
            Version = "1.2.3",
            DisplayName = "Synthetic training",
            LevelEntries = ["levels/training/level.json"]
        };
        File.WriteAllText(
            Path.Combine(source, "manifest.json"),
            M1937Pack.ManifestJson(manifest));

        var package = Path.Combine(root, "synthetic.m1937pack");
        var first = M1937Pack.Build(source, package);
        True(first.Manifest.Files.Count == 3, "pack manifest describes every payload");
        True(first.Manifest.PackId == "synthetic.training", "pack identity round trip");
        True(first.EntryCount == 4, "pack entry count includes manifest");

        var secondPackage = Path.Combine(root, "synthetic-2.m1937pack");
        var second = M1937Pack.Build(source, secondPackage);
        True(
            first.PackageSha256 == second.PackageSha256,
            "pack build is byte-for-byte deterministic");

        var extracted = Path.Combine(root, "safe-extract");
        var extraction = M1937Pack.ExtractSafe(package, extracted);
        True(
            extraction.PackageSha256 == first.PackageSha256 &&
            File.Exists(Path.Combine(extracted, "campaign.json")),
            "validated package extracts into an empty destination");
    }

    private static void RejectsTraversal(string root)
    {
        var path = Path.Combine(root, "traversal.m1937pack");
        CreateRawZip(path, [
            ("manifest.json", "{}"),
            ("campaign.json", "{}"),
            ("../escape.json", "{}")
        ]);
        Throws<InvalidDataException>(
            () => M1937Pack.Validate(path),
            "pack rejects parent traversal");
    }

    private static void RejectsExecutablePayload(string root)
    {
        var path = Path.Combine(root, "executable.m1937pack");
        CreateRawZip(path, [
            ("manifest.json", "{}"),
            ("campaign.json", "{}"),
            ("assets/plugin.dll", "not executable")
        ]);
        Throws<InvalidDataException>(
            () => M1937Pack.Validate(path),
            "pack rejects executable extensions");
    }

    private static void RejectsCaseCollision(string root)
    {
        var path = Path.Combine(root, "collision.m1937pack");
        CreateRawZip(path, [
            ("manifest.json", "{}"),
            ("campaign.json", "{}"),
            ("Campaign.JSON", "{}")
        ]);
        Throws<InvalidDataException>(
            () => M1937Pack.Validate(path),
            "pack rejects case-insensitive duplicate paths");
    }

    private static void RejectsTamperedHash(string root)
    {
        var source = Path.Combine(root, "tampered-source");
        Directory.CreateDirectory(Path.Combine(source, "levels", "one"));
        File.WriteAllText(
            Path.Combine(source, "campaign.json"),
            "{\"schema_version\":1,\"levels\":[{\"id\":\"one\"}]}");
        File.WriteAllText(
            Path.Combine(source, "levels", "one", "level.json"),
            "{\"schema_version\":1,\"world_size\":{\"width\":8,\"height\":8},\"entities\":[]}");
        File.WriteAllText(
            Path.Combine(source, "manifest.json"),
            M1937Pack.ManifestJson(new M1937PackManifest
            {
                PackId = "synthetic.tamper",
                DisplayName = "Tamper test",
                LevelEntries = ["levels/one/level.json"]
            }));
        var valid = Path.Combine(root, "tampered-valid.m1937pack");
        M1937Pack.Build(source, valid);
        var path = Path.Combine(root, "tampered.m1937pack");
        File.Copy(valid, path);
        using (var archive = ZipFile.Open(path, ZipArchiveMode.Update))
        {
            var entry = archive.GetEntry("campaign.json")!;
            entry.Delete();
            var replacement = archive.CreateEntry("campaign.json");
            using var writer = new StreamWriter(
                replacement.Open(),
                new UTF8Encoding(false));
            writer.Write("{\"tampered\":true}");
        }
        Throws<InvalidDataException>(
            () => M1937Pack.Validate(path),
            "pack rejects payload hash tampering");
    }

    private static void RejectsInvalidSemanticVersion(string root)
    {
        var source = Path.Combine(root, "invalid-version-source");
        Directory.CreateDirectory(Path.Combine(source, "levels", "one"));
        File.WriteAllText(
            Path.Combine(source, "campaign.json"),
            "{\"schema_version\":1,\"levels\":[{\"id\":\"one\"}]}");
        File.WriteAllText(
            Path.Combine(source, "levels", "one", "level.json"),
            "{\"schema_version\":1,\"world_size\":{\"width\":8,\"height\":8},\"entities\":[]}");
        File.WriteAllText(
            Path.Combine(source, "manifest.json"),
            M1937Pack.ManifestJson(new M1937PackManifest
            {
                PackId = "synthetic.invalid-version",
                Version = "latest",
                DisplayName = "Invalid version",
                LevelEntries = ["levels/one/level.json"]
            }));
        Throws<InvalidDataException>(
            () => M1937Pack.Build(source, Path.Combine(root, "invalid-version.m1937pack")),
            "pack rejects non-semantic versions");
    }

    private static void RejectsOversizedImageHeader(string root)
    {
        var png = new byte[24];
        new byte[] { 137, 80, 78, 71, 13, 10, 26, 10 }.CopyTo(png, 0);
        "IHDR"u8.CopyTo(png.AsSpan(12));
        System.Buffers.Binary.BinaryPrimitives.WriteUInt32BigEndian(
            png.AsSpan(16, 4), 20_000);
        System.Buffers.Binary.BinaryPrimitives.WriteUInt32BigEndian(
            png.AsSpan(20, 4), 20_000);
        Throws<InvalidDataException>(
            () => M1937PackContentPolicy.Validate("assets/oversized.png", png),
            "pack rejects decompression-bomb image dimensions");
    }

    private static void CreateRawZip(
        string path,
        IEnumerable<(string Name, string Content)> entries)
    {
        using var archive = ZipFile.Open(path, ZipArchiveMode.Create);
        foreach (var value in entries)
        {
            var entry = archive.CreateEntry(value.Name);
            using var writer = new StreamWriter(entry.Open(), new UTF8Encoding(false));
            writer.Write(value.Content);
        }
    }

    private static void True(bool condition, string message)
    {
        _checks++;
        if (!condition)
            throw new InvalidOperationException(message);
    }

    private static void Throws<T>(Action action, string message)
        where T : Exception
    {
        _checks++;
        try
        {
            action();
        }
        catch (T)
        {
            return;
        }
        throw new InvalidOperationException(message);
    }
}
