using Mission1937.Remake.Resources;

namespace Mission1937.Remake.ResourceFormats.Tests;

internal static class LegacySaveFormatTests
{
    public static int Run(string directory)
    {
        var checks = 0;
        var previewPath = System.IO.Path.Combine(directory, "synthetic.SI0");
        var rgb565 = new byte[320 * 240 * sizeof(ushort)];
        for (var index = 0; index < rgb565.Length; index++)
        {
            rgb565[index] = checked((byte)(index % 251));
        }
        File.WriteAllBytes(
            previewPath,
            IBlockImageEncoder.EncodeRgb565(320, 240, rgb565));
        var signedBlock = File.ReadAllBytes(previewPath);
        File.WriteAllBytes(
            previewPath,
            signedBlock.AsSpan(IBlockImage.SignatureSize).ToArray());

        var preview = LegacySavePreview.Open(previewPath);
        Equal(320, preview.Image.Width, "legacy SI width", ref checks);
        Equal(240, preview.Image.Height, "legacy SI height", ref checks);
        Equal(16, preview.Image.BitsPerPixel, "legacy SI bit depth", ref checks);
        Equal(
            Rgb565.ToRgba32(rgb565),
            preview.Image.Rgba32.ToArray(),
            "legacy SI decoded pixels",
            ref checks);

        var gameDirectory = System.IO.Path.Combine(directory, "legacy-game");
        Directory.CreateDirectory(gameDirectory);
        var sourceWorld = System.IO.Path.Combine(
            directory,
            "scene-list-synthetic.vwf");
        var savePath = System.IO.Path.Combine(directory, "synthetic.SAV");
        File.Copy(sourceWorld, savePath);
        File.Copy(
            sourceWorld,
            System.IO.Path.Combine(gameDirectory, "1937m000.vwf"));
        var snapshot = LegacySaveSnapshot.Open(savePath, gameDirectory);
        Equal("m000", snapshot.Level.LevelId, "legacy SAV level match", ref checks);
        Equal(
            LegacySaveSnapshot.TerrainIdentityFingerprint(snapshot.Terrain),
            snapshot.Level.TerrainSha256,
            "legacy SAV terrain fingerprint",
            ref checks);
        Equal(0, snapshot.RemovedSceneIndices.Count, "legacy SAV removed scenes", ref checks);
        Equal(0, snapshot.AddedEntities.Count, "legacy SAV added scenes", ref checks);
        Equal(0, snapshot.ChangedEntities.Count, "legacy SAV changed scenes", ref checks);

        return checks;
    }

    private static void Equal<T>(
        T expected,
        T actual,
        string description,
        ref int checks)
    {
        checks++;
        if (expected is Array expectedArray && actual is Array actualArray)
        {
            if (expectedArray.Length == actualArray.Length &&
                expectedArray.Cast<object?>().SequenceEqual(
                    actualArray.Cast<object?>()))
            {
                return;
            }
        }
        else if (EqualityComparer<T>.Default.Equals(expected, actual))
        {
            return;
        }

        throw new InvalidOperationException(
            $"{description}: expected '{expected}', actual '{actual}'.");
    }
}
