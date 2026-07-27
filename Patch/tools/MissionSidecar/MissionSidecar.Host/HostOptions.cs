namespace Mission1937.Sidecar.Host;

internal sealed record HostOptions(
    int ProcessId,
    string SidecarPath,
    bool Plugins,
    bool Headless,
    int DurationSeconds)
{
    public static HostOptions Parse(string[] args)
    {
        var values = new Dictionary<string, string>(
            StringComparer.OrdinalIgnoreCase);
        var switches = new HashSet<string>(
            StringComparer.OrdinalIgnoreCase);
        for (var index = 0; index < args.Length; ++index)
        {
            if (!args[index].StartsWith("--", StringComparison.Ordinal))
                throw new ArgumentException(
                    $"未知参数：{args[index]}");
            var name = args[index][2..];
            if (name is "plugins" or "headless")
            {
                switches.Add(name);
                continue;
            }
            if (++index >= args.Length)
                throw new ArgumentException(
                    $"参数 --{name} 缺少值。");
            values[name] = args[index];
        }
        if (!values.TryGetValue("pid", out var pidText) ||
            !int.TryParse(pidText, out var pid) ||
            pid <= 0)
            throw new ArgumentException("--pid 必须是有效进程 ID。");
        if (!values.TryGetValue("sidecar", out var sidecar) ||
            string.IsNullOrWhiteSpace(sidecar))
            throw new ArgumentException("--sidecar 必须指向任务定义。");
        var duration = 0;
        if (values.TryGetValue("duration-seconds", out var durationText) &&
            (!int.TryParse(durationText, out duration) ||
             duration is < 1 or > 86400))
            throw new ArgumentException(
                "--duration-seconds 必须在 1..86400 之间。");
        return new HostOptions(
            pid,
            Path.GetFullPath(sidecar),
            switches.Contains("plugins"),
            switches.Contains("headless"),
            duration);
    }
}
