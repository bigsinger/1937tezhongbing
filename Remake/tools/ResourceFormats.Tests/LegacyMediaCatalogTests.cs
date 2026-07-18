using Mission1937.Remake.Resources;

namespace Mission1937.Remake.ResourceFormats.Tests;

internal static class LegacyMediaCatalogTests
{
    public static int Run(string directory)
    {
        var entries = new[]
        {
            Entry(1048, "Intro_000.psd", "IBLOCK"),
            Entry(1059, "Intro_011.psd", "IBLOCK"),
            Entry(1060, "Intro_0121024.psd", "IBLOCK"),
            Entry(1025, "m1937.m12", "IBLOCK"),
            Entry(1036, "m1937.m01", "IBLOCK"),
            Entry(1328, "老赵恩.wav", "WAV"),
            Entry(1331, "老赵什么.wav", "WAV"),
            Entry(1355, "日本士兵警报.wav", "WAV"),
            Entry(1363, "手枪声（单）01.wav", "WAV"),
            Entry(1364, "手枪声（单）02.wav", "WAV"),
            Entry(1368, "死亡（好）01.wav", "WAV")
        };
        var catalog = LegacyMediaCatalogBuilder.Build(
            entries,
            directory,
            new HashSet<string>(entries.Where(entry => entry.Type == "WAV")
                .Select(entry => entry.OriginalName), StringComparer.Ordinal));
        var checks = 0;

        Equal(1, catalog.SchemaVersion, "media schema version", ref checks);
        Equal("m000", catalog.Briefings[0].LevelId, "first briefing mapping", ref checks);
        Equal("m011", catalog.Briefings[1].LevelId, "last briefing mapping", ref checks);
        Equal("m000", catalog.ObjectiveMaps[0].LevelId, "mission one objective-map mapping", ref checks);
        Equal(1036, catalog.ObjectiveMaps[0].GflIndex, "mission one objective-map index", ref checks);
        Equal("m011", catalog.ObjectiveMaps[1].LevelId, "mission twelve objective-map mapping", ref checks);
        Equal(1024, catalog.EndingImages.Single().Width, "ending resolution extraction", ref checks);

        var acknowledge = catalog.AudioCues.Single(cue => cue.GflIndex == 1328);
        Equal("voice", acknowledge.Category, "friendly voice category", ref checks);
        Equal("acknowledge", acknowledge.EventKey, "friendly acknowledgement event", ref checks);
        Equal("laozhao", acknowledge.ActorKey, "friendly actor mapping", ref checks);
        Equal("slf", acknowledge.SourceStatus, "SLF membership status", ref checks);
        Equal("selected", catalog.AudioCues.Single(cue => cue.GflIndex == 1331).EventKey,
            "selection voice event", ref checks);
        Equal("alert", catalog.AudioCues.Single(cue => cue.GflIndex == 1355).EventKey,
            "hostile alert event", ref checks);
        Equal(1, catalog.AudioCues.Single(cue => cue.GflIndex == 1364).VariantIndex,
            "event variants remain deterministic", ref checks);
        Equal("death", catalog.AudioCues.Single(cue => cue.GflIndex == 1368).EventKey,
            "death cue event", ref checks);
        Equal(5, catalog.Movies.Count, "known movie inventory", ref checks);
        Equal(false, catalog.Movies.Single(movie => movie.Id == "bonus_013").ReferencedByOriginalGame,
            "unreferenced bonus video is never treated as a mission cutscene", ref checks);
        return checks;
    }

    private static GflEntry Entry(int index, string name, string type) =>
        new(index, name, 0, 0, 0, 0, type, type == "WAV" ? ".wav" : ".iblock");

    private static void Equal<T>(T expected, T actual, string description, ref int checks)
    {
        checks++;
        if (!EqualityComparer<T>.Default.Equals(expected, actual))
        {
            throw new InvalidOperationException(
                $"{description}: expected '{expected}', actual '{actual}'.");
        }
    }
}
