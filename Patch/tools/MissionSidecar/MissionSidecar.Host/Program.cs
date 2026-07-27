using System.Diagnostics;

namespace Mission1937.Sidecar.Host;

internal static class Program
{
    [STAThread]
    private static int Main(string[] args)
    {
        string? logPath = null;
        try
        {
            var options = HostOptions.Parse(args);
            var definition =
                MissionRuntimeEngine.LoadDefinition(options.SidecarPath);
            using var process =
                Process.GetProcessById(options.ProcessId);
            using var reader = new RuntimeWorldReader(process);
            var executable = reader.ExecutablePath();
            logPath = Path.Combine(
                Path.GetDirectoryName(executable)!,
                "MissionSidecarHost.log");
            var identity = SupportedExecutable.Verify(
                executable, definition);
            using var session = new MissionSession(
                reader,
                definition,
                identity,
                options.Plugins);
            if (options.Headless)
            {
                var clock = Stopwatch.StartNew();
                while (!session.ProcessExited &&
                       (options.DurationSeconds == 0 ||
                        clock.Elapsed.TotalSeconds <
                            options.DurationSeconds))
                {
                    session.Tick();
                    Thread.Sleep(100);
                }
                return 0;
            }
            ApplicationConfiguration.Initialize();
            using var overlay = new MissionOverlayForm(session);
            Application.Run(overlay);
            return 0;
        }
        catch (Exception exception)
        {
            if (!string.IsNullOrWhiteSpace(logPath))
                File.AppendAllText(
                    logPath,
                    $"{DateTime.UtcNow:O}\tfatal\t{exception}{Environment.NewLine}");
            return 2;
        }
    }
}
