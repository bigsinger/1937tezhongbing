using System.Text;
using Mission1937.Remake.Resources;

namespace Mission1937.Remake.ResourceFormats.Tests;

internal static class Program
{
    private static int _checks;

    public static int Main()
    {
        var temporaryDirectory = System.IO.Path.Combine(
            System.IO.Path.GetTempPath(),
            "mission1937-resource-tests-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(temporaryDirectory);

        try
        {
            ReadsSyntheticGfl(temporaryDirectory);
            RejectsTruncatedGfl(temporaryDirectory);
            DetectsLegacyHeaders();
            ReadsSyntheticSoundLibrary(temporaryDirectory);
            ReadsSyntheticVwfHeader(temporaryDirectory);
            _checks += IBlockSyntheticTests.Run(temporaryDirectory);
            _checks += TlgSyntheticTests.Run();
            _checks += SprSyntheticTests.Run();
            _checks += SprAnimationSemanticsTests.Run();
            _checks += LegacyMediaCatalogTests.Run(temporaryDirectory);
            _checks += VwfSceneListSyntheticTests.Run(temporaryDirectory);
            _checks += VwfNavigationGridSyntheticTests.Run();
            _checks += TerrainRasterizerSyntheticTests.Run();
            Console.WriteLine($"Resource format tests passed ({_checks} checks). No original game data was used.");
            return 0;
        }
        catch (Exception exception)
        {
            Console.Error.WriteLine(exception);
            return 1;
        }
        finally
        {
            Directory.Delete(temporaryDirectory, recursive: true);
        }
    }

    private static void ReadsSyntheticGfl(string directory)
    {
        var path = System.IO.Path.Combine(directory, "synthetic.gfl");
        CreateSyntheticGfl(path,
        [
            ("测试精灵.spr", Encoding.ASCII.GetBytes("SPR1 synthetic fixture")),
            ("测试音效.wav", CreateWaveFixture())
        ]);

        var archive = GflArchive.Open(path);
        Equal(2, archive.Entries.Count, "synthetic GFL entry count");
        Equal("SPR1", archive.Entries[0].Type, "SPR1 signature detection");
        Equal("WAV", archive.Entries[1].Type, "WAV signature detection");
        Equal("测试精灵.spr", archive.Entries[0].OriginalName, "obfuscated GBK name decoding");

        var indexPath = System.IO.Path.Combine(directory, "synthetic-index.gfl");
        CreateSyntheticIndex(indexPath, archive);
        var validatedArchive = GflArchive.Open(path, indexPath);
        Equal(2, validatedArchive.Entries.Count, "GFL companion index validation");

        var output = System.IO.Path.Combine(directory, "extracted");
        var extracted = archive.ExtractAll(output);
        Equal(2, extracted.Count, "synthetic GFL extraction count");
        True(
            File.Exists(System.IO.Path.Combine(output, "spr1", "0000_测试精灵.spr")),
            "named SPR1 extraction path");
        True(
            File.Exists(System.IO.Path.Combine(output, "wav", "0001_测试音效.wav")),
            "named WAV extraction path");
    }

    private static void RejectsTruncatedGfl(string directory)
    {
        var path = System.IO.Path.Combine(directory, "truncated.gfl");
        using (var stream = new FileStream(path, FileMode.Create, FileAccess.Write))
        using (var writer = new BinaryWriter(stream, Encoding.ASCII, leaveOpen: false))
        {
            WriteHeader(writer);
            writer.Write(new byte[256]);
            writer.Write(new byte[3]);
            writer.Write(100u);
            writer.Write(new byte[4]);
        }

        Throws<InvalidDataException>(() => GflArchive.Open(path), "truncated GFL rejection");
    }

    private static void DetectsLegacyHeaders()
    {
        var vwf = Encoding.ASCII.GetBytes("VWL1 Intuition Engine Virtual World File Version 1.0.0");
        Equal("VWF", LegacyFileDetector.DetectHeader(vwf).Format, "VWF signature detection");

        byte[] zip = [0x50, 0x4B, 0x03, 0x04];
        Equal("ZIP", LegacyFileDetector.DetectHeader(zip).Format, "ZIP masquerading as VWF detection");

        byte[] mpeg = [0x00, 0x00, 0x01, 0xBA];
        Equal("MPEG-PS", LegacyFileDetector.DetectHeader(mpeg).Format, "SVT MPEG program stream detection");
    }

    private static void ReadsSyntheticSoundLibrary(string directory)
    {
        Encoding.RegisterProvider(CodePagesEncodingProvider.Instance);
        var gbk = Encoding.GetEncoding(936);
        var path = System.IO.Path.Combine(directory, "synthetic.slf");
        var header = new byte[SoundLibrary.HeaderSize];
        Encoding.ASCII.GetBytes("SLF1 Intuition Engine Professional Sound Library").CopyTo(header, 0);
        BitConverter.GetBytes(2u).CopyTo(header, 117);

        using (var stream = new FileStream(path, FileMode.Create, FileAccess.Write))
        using (var writer = new BinaryWriter(stream, Encoding.ASCII, leaveOpen: false))
        {
            writer.Write(header);
            foreach (var name in new[] { "脚步.wav", "警报.wav" })
            {
                writer.Write(1u);
                var field = new byte[256];
                gbk.GetBytes(name).CopyTo(field, 0);
                writer.Write(field);
            }
        }

        var library = SoundLibrary.Open(path);
        Equal(2, library.Entries.Count, "SLF entry count");
        Equal("警报.wav", library.Entries[1].FileName, "SLF GBK name decoding");
        Equal(1u, library.Entries[0].UnknownFlag, "SLF unknown flag preservation");
    }

    private static void ReadsSyntheticVwfHeader(string directory)
    {
        var path = System.IO.Path.Combine(directory, "synthetic.vwf");
        var header = new byte[VwfWorldHeader.HeaderSize];
        Encoding.ASCII.GetBytes("VWL1 Intuition Engine Virtual World File").CopyTo(header, 0);
        BitConverter.GetBytes(796u).CopyTo(header, 95);
        BitConverter.GetBytes(611u).CopyTo(header, 99);
        BitConverter.GetBytes(2u).CopyTo(header, 135);
        BitConverter.GetBytes(3u).CopyTo(header, 139);
        BitConverter.GetBytes(16u).CopyTo(header, 143);

        using (var stream = new FileStream(path, FileMode.Create, FileAccess.Write))
        {
            stream.Write(header);
            stream.Write(new byte[2 * 3 * VwfWorldHeader.GridCellSize]);
            stream.Write(Encoding.ASCII.GetBytes("SLIST1"));
        }

        var world = VwfWorldHeader.Open(path);
        Equal(2u, world.GridWidth, "VWF grid width");
        Equal(3u, world.GridHeight, "VWF grid height");
        Equal(451L, world.SceneListOffset, "VWF SLIST1 offset formula");
    }

    private static void CreateSyntheticGfl(
        string path,
        IReadOnlyList<(string Name, byte[] Payload)> resources)
    {
        using var stream = new FileStream(path, FileMode.Create, FileAccess.Write);
        using var writer = new BinaryWriter(stream, Encoding.ASCII, leaveOpen: false);
        WriteHeader(writer);
        foreach (var resource in resources)
        {
            writer.Write(LegacyNameCodec.EncodeObfuscatedNameForTests(resource.Name));
            writer.Write(new byte[3]);
            writer.Write((uint)resource.Payload.Length);
            writer.Write(resource.Payload);
        }
    }

    private static void CreateSyntheticIndex(string path, GflArchive archive)
    {
        using var stream = new FileStream(path, FileMode.Create, FileAccess.Write);
        using var writer = new BinaryWriter(stream, Encoding.ASCII, leaveOpen: false);
        WriteHeader(writer);
        foreach (var entry in archive.Entries)
        {
            writer.Write(LegacyNameCodec.EncodeObfuscatedNameForTests(entry.OriginalName));
            writer.Write(new byte[3]);
            writer.Write(entry.Length);
            writer.Write(checked((uint)entry.DataOffset));
        }
    }

    private static void WriteHeader(BinaryWriter writer)
    {
        var header = new byte[GflArchive.HeaderSize];
        var magic = Encoding.ASCII.GetBytes("GFL (Game File Library) Win32/V1.0 Copyright Test Fixture");
        magic.CopyTo(header, 0);
        writer.Write(header);
    }

    private static byte[] CreateWaveFixture()
    {
        byte[] wave = new byte[16];
        Encoding.ASCII.GetBytes("RIFF").CopyTo(wave, 0);
        Encoding.ASCII.GetBytes("WAVE").CopyTo(wave, 8);
        return wave;
    }

    private static void Equal<T>(T expected, T actual, string description)
    {
        _checks++;
        if (!EqualityComparer<T>.Default.Equals(expected, actual))
        {
            throw new InvalidOperationException(
                $"{description}: expected '{expected}', actual '{actual}'.");
        }
    }

    private static void True(bool value, string description)
    {
        _checks++;
        if (!value)
        {
            throw new InvalidOperationException($"{description}: expected true.");
        }
    }

    private static void Throws<TException>(Action action, string description)
        where TException : Exception
    {
        _checks++;
        try
        {
            action();
        }
        catch (TException)
        {
            return;
        }

        throw new InvalidOperationException($"{description}: expected {typeof(TException).Name}.");
    }
}
