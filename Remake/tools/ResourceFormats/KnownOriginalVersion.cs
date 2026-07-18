using System.Security.Cryptography;

namespace Mission1937.Remake.Resources;

public static class KnownOriginalVersion
{
    public const string VersionId = "green-2001-known-good-20260718";

    private static readonly IReadOnlyDictionary<string, string> ExpectedHashes =
        new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        {
            ["M1937.exe"] = "F4DD1131DF6C993C01EA011F9439BC725E6DC6491B5FBBA47724D7D5B64DA3F3",
            ["1937Resources.GFL"] = "A93DA9180C546A8F349F03BC6912583C5CC5511AC9458E4B910108614CA07211",
            ["InterMedia.GFL"] = "3D937AAB4D3906A735B4E33280EA0F971A69B12B9B54F99E91BCA79FC438BB0D",
            ["1937Database.dbl"] = "0017D8AB6A41F104BF0DE9A8282AB593B94E2BF7131038566AC281A8F15025D9",
            ["1937Sound.slf"] = "258A890F8D5EAEB642C047E509479531CF1862C4D1395153EEE353C1C65EBEFB",
            ["1937m000.vwf"] = "C98E4347A1E69D79566DD790059D41E653DBBC3209AC0B73E2511803091B0E5C"
        };

    public static KnownVersionValidation Validate(string gameDirectory)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(gameDirectory);
        var results = new List<KnownVersionFileHash>(ExpectedHashes.Count);
        foreach (var pair in ExpectedHashes)
        {
            var path = System.IO.Path.Combine(gameDirectory, pair.Key);
            string? actual = null;
            if (File.Exists(path))
            {
                using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read);
                actual = Convert.ToHexString(SHA256.HashData(stream));
            }

            results.Add(new KnownVersionFileHash(
                pair.Key,
                pair.Value,
                actual,
                string.Equals(pair.Value, actual, StringComparison.OrdinalIgnoreCase)));
        }

        return new KnownVersionValidation(VersionId, results.All(result => result.Matches), results);
    }
}
