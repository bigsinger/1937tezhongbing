using System.Security.Cryptography;

namespace Mission1937.Remake.Resources;

/// <summary>
/// Exact content contract for the repository's stable twelve-level Mod.
/// Runtime-only files such as saves, rungame.ini and the compatibility DLL are
/// intentionally excluded; every resource consumed by the remake is hashed.
/// </summary>
public static class KnownStableModVersion
{
    public const string VersionId = "repository-mod-12-level-20260729";

    private static readonly IReadOnlyDictionary<string, string> ExpectedHashes =
        new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        {
            ["M1937.exe"] = "F4DD1131DF6C993C01EA011F9439BC725E6DC6491B5FBBA47724D7D5B64DA3F3",
            ["1937Resources.GFL"] = "320456C9C0487AF3E650FB8207D62D1D971E8E949C19BC09334A0ECB7395626D",
            ["InterMedia.GFL"] = "D283CAC7EB015D6ACA9C7A37046E33461769C9161D0BFF7238C71AE420FE2836",
            ["1937Database.dbl"] = "0017D8AB6A41F104BF0DE9A8282AB593B94E2BF7131038566AC281A8F15025D9",
            ["1937Sound.slf"] = "258A890F8D5EAEB642C047E509479531CF1862C4D1395153EEE353C1C65EBEFB",
            ["1937m000.vwf"] = "C98E4347A1E69D79566DD790059D41E653DBBC3209AC0B73E2511803091B0E5C",
            ["1937m001.vwf"] = "3DD59A05BCA101A954D76716F89A532352F1D9B7A6DD909B651C88DCF8F266F8",
            ["1937m002.vwf"] = "2454CF53BA0FA3780BB472BE549F3BE0FFD9F45D863B901691BBAEC2DABA082F",
            ["1937m003.vwf"] = "BB279AD66F1368D7B0F7A1E1474F81745DD4BB543B36B8C6E57042EE55F0B3AF",
            ["1937m004.vwf"] = "06355CF3E2F7E868D83CA6BC6AB76F5AC8BD952AA541EBE70D5342ED13FEBA43",
            ["1937m005.vwf"] = "3BB1BFBABA3AEDF465E07476191E7791413412446C4CCEECB345ACCFED5DA44E",
            ["1937m006.vwf"] = "28A48B7295A8C390BB4D35DE1E2D6B154FA0F7536ACB7A9DA3EB8D5C7CEE2090",
            ["1937m007.vwf"] = "E482D66F0E57E3A970D82FAD5270620563519E3EA58C83FE74AB8B97FF68E87C",
            ["1937m008.vwf"] = "10801B71778D21A88B5C4134A8E0C48DD35375E515273021CEE972201EBC7ED7",
            ["1937m009.vwf"] = "32245944731DB2EF0E46C965893E29B4189B55589FBA21CB7382007FF403ACAC",
            ["1937m010.vwf"] = "577927C7939B88F053106BE2C991C7B872F9C304B4EB9900202CB6DFF0960E0F",
            ["1937m011.vwf"] = "5BB97802376BC965A85F55E3D11698B94D1403D06055E931C18055056865EDAA"
        };

    public static KnownVersionValidation Validate(string gameDirectory)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(gameDirectory);
        var results = new List<KnownVersionFileHash>(ExpectedHashes.Count);
        foreach (var pair in ExpectedHashes)
        {
            var path = Path.Combine(gameDirectory, pair.Key);
            string? actual = null;
            if (File.Exists(path))
            {
                using var stream = new FileStream(
                    path,
                    FileMode.Open,
                    FileAccess.Read,
                    FileShare.Read);
                actual = Convert.ToHexString(SHA256.HashData(stream));
            }
            results.Add(new KnownVersionFileHash(
                pair.Key,
                pair.Value,
                actual,
                string.Equals(
                    pair.Value,
                    actual,
                    StringComparison.OrdinalIgnoreCase)));
        }
        return new KnownVersionValidation(
            VersionId,
            results.All(result => result.Matches),
            results);
    }
}
