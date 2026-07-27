using System.Security.Cryptography;
using System.Text.Json;

namespace Mission1937.Sidecar;

public static class AtomicMissionStateStore
{
    public static void Save(
        string statePath,
        MissionRuntimeState state,
        string originalSavePath)
    {
        ArgumentNullException.ThrowIfNull(state);
        var originalHash = FileHash(originalSavePath);
        state.SaveSha256 = originalHash;
        var fullPath = Path.GetFullPath(statePath);
        Directory.CreateDirectory(Path.GetDirectoryName(fullPath)!);
        var temporary = fullPath + ".tmp";
        var backup = fullPath + ".bak";
        File.WriteAllText(
            temporary,
            JsonSerializer.Serialize(
                state,
                MissionJsonContext.Default.MissionRuntimeState));
        _ = ParseAndValidate(temporary, originalSavePath);
        if (File.Exists(fullPath))
            File.Replace(temporary, fullPath, backup, true);
        else
            File.Move(temporary, fullPath);
        // The original SAV is only hashed; never opened for write.
        if (FileHash(originalSavePath) != originalHash)
            throw new IOException(
                "原版存档在 sidecar 保存期间发生变化。");
    }

    public static MissionRuntimeState Load(
        string statePath,
        string originalSavePath)
    {
        try
        {
            return ParseAndValidate(statePath, originalSavePath);
        }
        catch (Exception exception) when (
            exception is IOException or JsonException or InvalidDataException)
        {
            var backup = statePath + ".bak";
            if (!File.Exists(backup))
                throw;
            return ParseAndValidate(backup, originalSavePath);
        }
    }

    public static string SidecarPathForSave(
        string originalSavePath) =>
        originalSavePath + ".m1937state.json";

    private static MissionRuntimeState ParseAndValidate(
        string path,
        string originalSavePath)
    {
        var state = JsonSerializer.Deserialize(
            File.ReadAllText(path),
            MissionJsonContext.Default.MissionRuntimeState)
            ?? throw new InvalidDataException("sidecar 状态为空。");
        if (state.SchemaVersion != 1 ||
            !string.Equals(
                state.SaveSha256,
                FileHash(originalSavePath),
                StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException(
                "sidecar 状态与原版存档指纹不匹配。");
        return state;
    }

    private static string FileHash(string path)
    {
        if (!File.Exists(path))
            throw new FileNotFoundException("找不到原版存档。", path);
        using var stream = new FileStream(
            path,
            FileMode.Open,
            FileAccess.Read,
            FileShare.ReadWrite | FileShare.Delete);
        return Convert.ToHexString(SHA256.HashData(stream));
    }
}
