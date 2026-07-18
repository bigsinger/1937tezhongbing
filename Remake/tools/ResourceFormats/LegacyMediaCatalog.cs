using System.Collections.ObjectModel;
using System.Text.RegularExpressions;

namespace Mission1937.Remake.Resources;

public sealed record LegacyBriefingImage(
    string LevelId,
    int GflIndex,
    string ResourceName,
    string RelativePath);

public sealed record LegacyObjectiveMap(
    string LevelId,
    int GflIndex,
    string ResourceName,
    string RelativePath);

public sealed record LegacyEndingImage(
    int Width,
    int GflIndex,
    string ResourceName,
    string RelativePath);

public sealed record LegacyAudioCue(
    int GflIndex,
    string ResourceName,
    string RelativePath,
    string Category,
    string EventKey,
    string ActorKey,
    int VariantIndex,
    string Caption,
    string SourceStatus);

public sealed record LegacyMovie(
    string Id,
    string Role,
    string SourceName,
    string SourceFormat,
    string TranscodedRelativePath,
    bool ReferencedByOriginalGame,
    bool SourcePresent,
    int Width,
    int Height,
    double DurationSeconds,
    string Notes);

public sealed record LegacyMediaCatalog(
    int SchemaVersion,
    IReadOnlyList<LegacyBriefingImage> Briefings,
    IReadOnlyList<LegacyObjectiveMap> ObjectiveMaps,
    IReadOnlyList<LegacyEndingImage> EndingImages,
    IReadOnlyList<LegacyAudioCue> AudioCues,
    IReadOnlyList<LegacyMovie> Movies);

/// <summary>
/// Builds a metadata-only media catalogue. The catalogue contains no original bytes and points
/// exclusively at files generated under the ignored LocalAssets directory.
/// </summary>
public static partial class LegacyMediaCatalogBuilder
{
    private static readonly IReadOnlyDictionary<string, string> ActorKeys =
        new ReadOnlyDictionary<string, string>(new Dictionary<string, string>(StringComparer.Ordinal)
        {
            ["大牛"] = "daniu",
            ["古明"] = "guming",
            ["老赵"] = "laozhao",
            ["强子"] = "qiangzi",
            ["铁蛋"] = "tiedan",
            ["二狗"] = "ergou",
            ["龟田"] = "guitian",
            ["烂脚七"] = "lanjiaoqi",
            ["胖翻译"] = "translator",
            ["日本士兵"] = "japanese_soldier",
            ["山本"] = "shanben",
            ["孙大麻子"] = "sun_damazi"
        });

    public static LegacyMediaCatalog Build(
        IReadOnlyList<GflEntry> entries,
        string? gameDirectory = null,
        IReadOnlySet<string>? soundLibraryNames = null)
    {
        ArgumentNullException.ThrowIfNull(entries);

        var briefings = entries
            .Select(TryBriefing)
            .Where(value => value is not null)
            .Cast<LegacyBriefingImage>()
            .OrderBy(value => value.LevelId, StringComparer.Ordinal)
            .ToArray();
        var objectiveMaps = entries
            .Select(TryObjectiveMap)
            .Where(value => value is not null)
            .Cast<LegacyObjectiveMap>()
            .OrderBy(value => value.LevelId, StringComparer.Ordinal)
            .ToArray();
        var endingImages = entries
            .Select(TryEndingImage)
            .Where(value => value is not null)
            .Cast<LegacyEndingImage>()
            .OrderBy(value => value.Width)
            .ToArray();

        var audioCues = new List<LegacyAudioCue>();
        var variants = new Dictionary<string, int>(StringComparer.Ordinal);
        foreach (var entry in entries.Where(value => value.Type == "WAV").OrderBy(value => value.Index))
        {
            var classified = ClassifyAudio(entry.OriginalName);
            var variantKey = $"{classified.EventKey}\0{classified.ActorKey}";
            var variant = variants.GetValueOrDefault(variantKey);
            variants[variantKey] = variant + 1;
            audioCues.Add(new LegacyAudioCue(
                entry.Index,
                entry.OriginalName,
                $"audio/{entry.Index:D4}.wav",
                classified.Category,
                classified.EventKey,
                classified.ActorKey,
                variant,
                FileStem(entry.OriginalName),
                soundLibraryNames is null ? "not_checked"
                    : soundLibraryNames.Contains(entry.OriginalName) ? "slf"
                    : "gfl_only"));
        }

        return new LegacyMediaCatalog(
            1,
            briefings,
            objectiveMaps,
            endingImages,
            audioCues,
            BuildMovies(gameDirectory));
    }

    private static LegacyBriefingImage? TryBriefing(GflEntry entry)
    {
        var match = BriefingName().Match(entry.OriginalName);
        if (!match.Success || !int.TryParse(match.Groups[1].Value, out var index) || index is < 0 or > 11)
        {
            return null;
        }

        return new LegacyBriefingImage(
            $"m{index:D3}", entry.Index, entry.OriginalName, $"iblock/{entry.Index:D4}.png");
    }

    private static LegacyObjectiveMap? TryObjectiveMap(GflEntry entry)
    {
        var match = ObjectiveMapName().Match(entry.OriginalName);
        if (!match.Success || !int.TryParse(match.Groups[1].Value, out var mission) || mission is < 1 or > 12)
        {
            return null;
        }

        return new LegacyObjectiveMap(
            $"m{mission - 1:D3}", entry.Index, entry.OriginalName, $"iblock/{entry.Index:D4}.png");
    }

    private static LegacyEndingImage? TryEndingImage(GflEntry entry)
    {
        var match = EndingName().Match(entry.OriginalName);
        if (!match.Success || !int.TryParse(match.Groups[1].Value, out var width))
        {
            return null;
        }

        return new LegacyEndingImage(width, entry.Index, entry.OriginalName, $"iblock/{entry.Index:D4}.png");
    }

    private static IReadOnlyList<LegacyMovie> BuildMovies(string? gameDirectory)
    {
        bool Present(string name) =>
            !string.IsNullOrWhiteSpace(gameDirectory) && File.Exists(System.IO.Path.Combine(gameDirectory, name));

        return
        [
            new("logo", "publisher_logo", "GamekingLogo.svt", "mpeg_ps",
                "media/video/logo.ogv", true, Present("GamekingLogo.svt"), 640, 480, 10.396733,
                "Original startup logo; optional and always skippable."),
            new("historical_intro", "historical_intro", "1937Intro.svt", "mpeg_ps",
                "media/video/historical_intro.ogv", true, Present("1937Intro.svt"), 640, 240, 139.916667,
                "Historical montage used by the original startup flow."),
            new("bonus_013", "unreferenced_bonus", "1937m013.vwf", "mpeg_ps",
                "media/video/bonus_013.ogv", false, Present("1937m013.vwf"), 352, 288, 125.14,
                "Unreferenced dance footage; not a mission cutscene."),
            new("bonus_014", "unreferenced_bonus", "1937m014.vwf", "mpeg_ps",
                "media/video/bonus_014.ogv", false, Present("1937m014.vwf"), 352, 288, 81.760411,
                "Unreferenced dance footage; not a mission cutscene."),
            new("bonus_015", "unreferenced_bonus", "1937m015.vwf", "mpeg_ps",
                "media/video/bonus_015.ogv", false, Present("1937m015.vwf"), 352, 288, 267.746533,
                "Unreferenced bonus/CG footage; not a mission cutscene.")
        ];
    }

    private static (string Category, string EventKey, string ActorKey) ClassifyAudio(string fileName)
    {
        var stem = FileStem(fileName);
        foreach (var pair in ActorKeys.OrderByDescending(value => value.Key.Length))
        {
            if (stem.StartsWith(pair.Key, StringComparison.Ordinal))
            {
                var phrase = stem[pair.Key.Length..];
                var friendly = pair.Value is "daniu" or "guming" or "laozhao" or "qiangzi" or "tiedan";
                return friendly
                    ? ("voice", FriendlyVoiceEvent(phrase), pair.Value)
                    : ("voice", HostileVoiceEvent(phrase), pair.Value);
            }
        }

        if (stem.StartsWith("死亡", StringComparison.Ordinal))
        {
            var actor = stem.Contains("坏", StringComparison.Ordinal) ? "enemy"
                : stem.Contains("军犬", StringComparison.Ordinal) ? "war_dog"
                : stem.Contains("女", StringComparison.Ordinal) ? "civilian_woman"
                : stem.Contains("孩", StringComparison.Ordinal) ? "civilian_child"
                : "ally";
            return ("voice", "death", actor);
        }

        if (stem.Contains("手枪声", StringComparison.Ordinal)) return ("weapon", "attack_pistol", "");
        if (stem.Contains("步枪声", StringComparison.Ordinal)) return ("weapon", "attack_rifle", "");
        if (stem.Contains("轻机枪声", StringComparison.Ordinal))
            return ("weapon", stem.Contains("连", StringComparison.Ordinal) ? "attack_light_machinegun_burst" : "attack_light_machinegun", "");
        if (stem.Contains("重机枪", StringComparison.Ordinal)) return ("weapon", "attack_heavy_machinegun", "");
        if (stem.Contains("匕首攻击", StringComparison.Ordinal)) return ("weapon", "attack_dagger", "");
        if (stem.Contains("大刀攻击", StringComparison.Ordinal)) return ("weapon", "attack_broadsword", "");
        if (stem.Contains("弹弓攻击", StringComparison.Ordinal)) return ("weapon", "attack_slingshot", "");
        if (stem.Contains("飞标攻击", StringComparison.Ordinal)) return ("weapon", "attack_dart", "");
        if (stem.Contains("弹痕", StringComparison.Ordinal)) return ("weapon", "projectile_impact", "");
        if (stem.Contains("警报", StringComparison.Ordinal)) return ("alert", "alert", "");
        if (stem.Contains("爆炸", StringComparison.Ordinal)) return ("world", "explosion", "");
        if (stem.Contains("燃烧开始", StringComparison.Ordinal)) return ("world", "fire_start", "");
        if (stem.Contains("燃烧停止", StringComparison.Ordinal)) return ("world", "fire_stop", "");
        if (stem == "燃烧") return ("world", "fire_loop", "");
        if (stem.Contains("雨声", StringComparison.Ordinal)) return ("ambience", "rain", "");
        if (stem.Contains("雷声", StringComparison.Ordinal)) return ("ambience", "thunder", "");
        if (stem.Contains("按钮", StringComparison.Ordinal)) return ("ui", "ui_confirm", "");
        if (stem.Contains("奔跑", StringComparison.Ordinal)) return ("movement", "run", "");
        if (stem.Contains("行走", StringComparison.Ordinal) || stem == "匍匐") return ("movement", "move", "");
        if (stem.Contains("火车", StringComparison.Ordinal)) return ("vehicle", "train", "");
        if (stem.Contains("汽车", StringComparison.Ordinal)) return ("vehicle", "car", "");
        if (stem.Contains("摩托车", StringComparison.Ordinal)) return ("vehicle", "motorcycle", "");
        if (stem.Contains("船", StringComparison.Ordinal)) return ("vehicle", "boat", "");
        if (stem.Contains("独轮车", StringComparison.Ordinal)) return ("vehicle", "handcart", "");
        if (stem.Contains("海鸥", StringComparison.Ordinal)) return ("animal", "seagull", "");
        if (stem.Contains("军犬", StringComparison.Ordinal) || stem.Contains("狗", StringComparison.Ordinal)) return ("animal", "dog", "");
        if (stem.Contains("鸡", StringComparison.Ordinal)) return ("animal", "chicken", "");
        if (stem.Contains("猪", StringComparison.Ordinal)) return ("animal", "pig", "");
        if (stem.Contains("牛", StringComparison.Ordinal)) return ("animal", "cattle", "");
        if (stem.Contains("瘙痒", StringComparison.Ordinal)) return ("foley", "scratch", "");
        return ("uncategorized", "legacy_uncategorized", "");
    }

    private static string FriendlyVoiceEvent(string phrase) =>
        phrase.Contains("什么", StringComparison.Ordinal) || phrase.Contains("干什么", StringComparison.Ordinal)
            ? "selected"
            : phrase.Contains("怒吼", StringComparison.Ordinal) ? "battle_cry" : "acknowledge";

    private static string HostileVoiceEvent(string phrase)
    {
        if (phrase.Contains("警报", StringComparison.Ordinal)) return "alert";
        if (phrase.Contains("别跑", StringComparison.Ordinal)) return "challenge_chase";
        if (phrase.Contains("不许动", StringComparison.Ordinal) || phrase.Contains("站住", StringComparison.Ordinal) || phrase.Contains("站到", StringComparison.Ordinal)) return "challenge_stop";
        if (phrase.Contains("抓住", StringComparison.Ordinal)) return "challenge_attack";
        if (phrase.Contains("开枪", StringComparison.Ordinal)) return "threat_shoot";
        return "investigate";
    }

    private static string FileStem(string value) =>
        System.IO.Path.GetFileNameWithoutExtension(value).Trim();

    [GeneratedRegex("^Intro_(\\d{3})\\.psd$", RegexOptions.CultureInvariant | RegexOptions.IgnoreCase)]
    private static partial Regex BriefingName();

    [GeneratedRegex("^m1937\\.m(\\d{2})$", RegexOptions.CultureInvariant | RegexOptions.IgnoreCase)]
    private static partial Regex ObjectiveMapName();

    [GeneratedRegex("^Intro_012(640|800|1024)\\.psd$", RegexOptions.CultureInvariant | RegexOptions.IgnoreCase)]
    private static partial Regex EndingName();
}
