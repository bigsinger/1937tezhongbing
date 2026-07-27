using System.Security.Cryptography;
using Mission1937.SDK.Generated;

namespace Mission1937.Sidecar.Host;

internal sealed record ExecutableIdentity(
    string Path,
    string Sha256,
    long FileSize,
    uint PeTimestamp);

internal static class SupportedExecutable
{
    public static ExecutableIdentity Verify(
        string executablePath,
        MissionSidecarDefinition definition)
    {
        var fullPath = Path.GetFullPath(executablePath);
        var info = new FileInfo(fullPath);
        using var stream = new FileStream(
            fullPath,
            FileMode.Open,
            FileAccess.Read,
            FileShare.ReadWrite | FileShare.Delete);
        var sha = Convert.ToHexString(SHA256.HashData(stream));
        stream.Position = 0x3C;
        Span<byte> offsetBytes = stackalloc byte[4];
        stream.ReadExactly(offsetBytes);
        var peOffset = BitConverter.ToInt32(offsetBytes);
        if (peOffset < 0x40 || peOffset > stream.Length - 12)
            throw new InvalidDataException("M1937.exe PE 头无效。");
        stream.Position = peOffset + 8;
        Span<byte> timestampBytes = stackalloc byte[4];
        stream.ReadExactly(timestampBytes);
        var timestamp = BitConverter.ToUInt32(timestampBytes);

        if (!sha.Equals(
                M1937ExecutableIdentity.Sha256,
                StringComparison.OrdinalIgnoreCase) ||
            info.Length != M1937ExecutableIdentity.FileSize ||
            timestamp !=
                unchecked((uint)M1937ExecutableIdentity.PeTimestamp))
            throw new InvalidDataException(
                "任务 sidecar 仅支持 SDK 已验证的 M1937.exe。");
        if (!string.IsNullOrWhiteSpace(definition.ExecutableSha256) &&
            !sha.Equals(
                definition.ExecutableSha256,
                StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException(
                "任务定义声明的 EXE SHA-256 不匹配。");
        if (definition.ExecutableFileSize > 0 &&
            definition.ExecutableFileSize != info.Length)
            throw new InvalidDataException(
                "任务定义声明的 EXE 长度不匹配。");
        if (definition.ExecutablePeTimestamp > 0 &&
            definition.ExecutablePeTimestamp != timestamp)
            throw new InvalidDataException(
                "任务定义声明的 EXE 时间戳不匹配。");
        return new ExecutableIdentity(
            fullPath, sha, info.Length, timestamp);
    }
}
