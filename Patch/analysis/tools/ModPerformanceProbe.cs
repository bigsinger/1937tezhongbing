using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using EngineAddresses = Mission1937.SDK.Generated.M1937Addresses;

internal static class ModPerformanceProbe
{
    private const uint ProcessVmRead = 0x0010;
    private const uint ProcessQueryInformation = 0x0400;
    private const uint ReplayMessage = 0x8000 + 0x137;
    private const int ReplayMouseDelta = 3;
    private const int SmXVirtualScreen = 76;
    private const int SmYVirtualScreen = 77;
    private const int SmCxVirtualScreen = 78;
    private const int SmCyVirtualScreen = 79;

    [StructLayout(LayoutKind.Sequential)]
    private struct Rect
    {
        public int Left, Top, Right, Bottom;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct IoCounters
    {
        public ulong ReadOperationCount, WriteOperationCount;
        public ulong OtherOperationCount, ReadTransferCount;
        public ulong WriteTransferCount, OtherTransferCount;
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr OpenProcess(
        uint access, bool inherit, int processId);
    [DllImport("kernel32.dll")]
    private static extern bool CloseHandle(IntPtr handle);
    [DllImport("kernel32.dll")]
    private static extern bool GetProcessIoCounters(
        IntPtr process, out IoCounters counters);
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool ReadProcessMemory(
        IntPtr process, IntPtr address, byte[] data, int size,
        out IntPtr read);
    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool PostMessage(
        IntPtr window, uint message, IntPtr wparam, IntPtr lparam);
    [DllImport("user32.dll")]
    private static extern bool GetClipCursor(out Rect rect);
    [DllImport("user32.dll")]
    private static extern int GetSystemMetrics(int index);
    [DllImport("dwmapi.dll")]
    private static extern int DwmFlush();

    private sealed class Sample
    {
        public double TimeMs;
        public double CpuMs;
        public ulong ReadBytes;
        public double CompositorMs;
        public bool Responding;
        public int CursorX;
        public int CursorY;
        public int CameraX;
        public int CameraY;
        public bool CursorClipRestricted;
    }

    public static int Main(string[] args)
    {
        if (args.Length != 5)
        {
            Console.Error.WriteLine(
                "Usage: ModPerformanceProbe GAME_DIR OUTPUT PROFILE LEVEL SECONDS");
            return 2;
        }
        string gameDirectory = Path.GetFullPath(args[0]);
        string output = Path.GetFullPath(args[1]);
        string profile = args[2];
        int level = int.Parse(args[3], CultureInfo.InvariantCulture);
        int seconds = int.Parse(args[4], CultureInfo.InvariantCulture);
        Directory.CreateDirectory(output);

        var start = new ProcessStartInfo(
            Path.Combine(gameDirectory, "M1937.exe"));
        start.WorkingDirectory = gameDirectory;
        start.UseShellExecute = false;
        start.EnvironmentVariables["M1937_TELEMETRY"] = "1";
        start.EnvironmentVariables["M1937_WINDOW_REPLAY"] = "1";
        if (level > 0)
        {
            start.EnvironmentVariables["M1937_AUTOTEST"] = "1";
            start.EnvironmentVariables["M1937_START_LEVEL"] =
                level.ToString(CultureInfo.InvariantCulture);
        }

        var samples = new List<Sample>();
        var clock = Stopwatch.StartNew();
        using (Process game = Process.Start(start))
        {
            if (game == null)
                throw new InvalidOperationException("Game did not start.");
            IntPtr window = WaitWindow(game, TimeSpan.FromSeconds(15));
            if (window == IntPtr.Zero)
                throw new InvalidOperationException("Game window missing.");
            IntPtr process = OpenProcess(
                ProcessVmRead | ProcessQueryInformation,
                false, game.Id);
            if (process == IntPtr.Zero)
                throw new InvalidOperationException("OpenProcess failed.");
            try
            {
                game.Refresh();
                long imageBase = game.MainModule.BaseAddress.ToInt64();
                bool ready = level == 0
                    ? WaitUntil(delegate()
                    {
                        return ReadInt(
                            process,
                            imageBase + EngineAddresses.CurrentMission) == 0;
                    }, TimeSpan.FromSeconds(20))
                    : WaitUntil(delegate()
                    {
                        return ReadWorldActorCount(process, imageBase) > 0;
                    }, TimeSpan.FromSeconds(45));
                if (!ready)
                    throw new InvalidOperationException(
                        "Requested performance phase was not ready.");

                // Exclude launch/briefing from the steady-state percentile,
                // while telemetry still preserves first-load evidence.
                Thread.Sleep(10000);
                clock.Restart();
                bool positive = true;
                long nextReplay = level > 0 ? 1000 : long.MaxValue;
                long nextDirectionChange =
                    level > 0 ? 6000 : long.MaxValue;
                while (clock.Elapsed.TotalSeconds < seconds &&
                       !game.HasExited)
                {
                    if (clock.ElapsedMilliseconds >= nextDirectionChange)
                    {
                        positive = !positive;
                        nextDirectionChange += 5000;
                    }
                    if (clock.ElapsedMilliseconds >= nextReplay)
                    {
                        // Hold the in-game cursor against one client edge for
                        // five seconds, then the opposite edge. Repeated small
                        // process-local deltas exercise the original scroll
                        // loop without SetCursorPos, focus changes or the
                        // user's physical mouse.
                        short delta = positive
                            ? (short)96 : (short)-96;
                        int cursorY = ReadInt(
                            process,
                            imageBase + EngineAddresses.CursorY);
                        short centerY = cursorY == int.MinValue
                            ? (short)0
                            : (short)Math.Max(
                                -96,
                                Math.Min(96, 384 - cursorY));
                        int packedDelta =
                            (ushort)delta |
                            ((ushort)centerY << 16);
                        PostMessage(
                            window, ReplayMessage,
                            new IntPtr(ReplayMouseDelta),
                            new IntPtr(packedDelta));
                        nextReplay += 100;
                    }
                    var flush = Stopwatch.StartNew();
                    int flushResult = DwmFlush();
                    flush.Stop();
                    IoCounters io;
                    GetProcessIoCounters(process, out io);
                    game.Refresh();
                    samples.Add(new Sample
                    {
                        TimeMs = clock.Elapsed.TotalMilliseconds,
                        CpuMs = game.TotalProcessorTime.TotalMilliseconds,
                        ReadBytes = io.ReadTransferCount,
                        CompositorMs = flushResult == 0
                            ? flush.Elapsed.TotalMilliseconds : 0,
                        Responding = game.Responding,
                        CursorX = ReadInt(
                            process,
                            imageBase + EngineAddresses.CursorX),
                        CursorY = ReadInt(
                            process,
                            imageBase + EngineAddresses.CursorY),
                        CameraX = ReadInt(
                            process,
                            imageBase + EngineAddresses.CameraX),
                        CameraY = ReadInt(
                            process,
                            imageBase + EngineAddresses.CameraY),
                        CursorClipRestricted = IsCursorClipRestricted()
                    });
                    Thread.Sleep(40);
                }
                string telemetry = ReadSharedText(
                    Path.Combine(
                        gameDirectory, "M1937Telemetry.jsonl"));
                WriteResult(
                    output, profile, level, seconds,
                    samples, telemetry);
            }
            finally
            {
                CloseHandle(process);
                Stop(game);
            }
        }
        return 0;
    }

    private static void WriteResult(
        string output,
        string profile,
        int level,
        int seconds,
        IList<Sample> samples,
        string telemetry)
    {
        double elapsed = samples.Count > 1
            ? samples[samples.Count - 1].TimeMs - samples[0].TimeMs : 0;
        double cpu = samples.Count > 1
            ? samples[samples.Count - 1].CpuMs - samples[0].CpuMs : 0;
        ulong reads = samples.Count > 1
            ? samples[samples.Count - 1].ReadBytes -
              samples[0].ReadBytes : 0;
        ulong steadyPeakRead = 0;
        for (int index = 1; index < samples.Count; ++index)
            steadyPeakRead = Math.Max(
                steadyPeakRead,
                samples[index].ReadBytes -
                samples[index - 1].ReadBytes);
        double[] compositor = samples
            .Select(item => item.CompositorMs)
            .Where(value => value > 0)
            .ToArray();
        long pumpMax = Maximum(telemetry, "\"pump\":", "\"max_us\":");
        long inputMax = Maximum(
            telemetry, "\"input\":", "\"state_max_us\":");
        long replayLatencyMax = Maximum(
            telemetry, "\"replay\":", "\"latency_max_us\":");
        long aiTickMax = Maximum(
            telemetry, "\"ai\":", "\"tick_max_us\":");
        long telemetryDrops = Maximum(
            telemetry, "\"schema\":", "\"writer_queue_dropped\":");
        long telemetryReadPeak = Maximum(
            telemetry, "\"schema\":", "\"disk_read_bytes\":");
        ulong peakRead = Math.Max(
            steadyPeakRead,
            SafeUInt64(telemetryReadPeak));
        long cameraMoves = CountTrue(telemetry, "\"camera_moved\":true");
        long firstLoads = CountTrue(telemetry, "\"first_load_io\":true");
        int cursorSpanX = Span(samples.Select(item => item.CursorX));
        int cursorSpanY = Span(samples.Select(item => item.CursorY));
        int cameraSpanX = Span(samples.Select(item => item.CameraX));
        int cameraSpanY = Span(samples.Select(item => item.CameraY));
        double p95 = Percentile(compositor, 0.95);
        double p99 = Percentile(compositor, 0.99);
        int unresponsive = samples.Count(item => !item.Responding);
        int cursorClipRestricted = samples.Count(
            item => item.CursorClipRestricted);
        bool passed =
            samples.Count >= seconds * 8 &&
            unresponsive == 0 &&
            p99 < 25.0 &&
            replayLatencyMax < 50000 &&
            pumpMax < 50000 &&
            telemetryDrops == 0 &&
            cursorClipRestricted == 0;
        string bottleneck =
            firstLoads > 0 && peakRead >= 1024 * 1024
                ? "first_resource_load"
                : pumpMax >= 20000
                    ? "message_pump"
                    : replayLatencyMax >= 16000
                        ? "input_delivery"
                        : p99 >= 25
                            ? "compositor_present"
                            : aiTickMax >= 10000
                                ? "ai_tick"
                                : "no_dominant_hitch_source";
        string json = string.Format(
            CultureInfo.InvariantCulture,
            "{{\n  \"schema\": 1,\n  \"profile\": \"{0}\",\n" +
            "  \"selector_level\": {1},\n  \"duration_seconds\": {2},\n" +
            "  \"samples\": {3},\n  \"cpu_one_core_percent\": {4:F3},\n" +
            "  \"disk_read_bytes\": {5},\n" +
            "  \"disk_peak_sample_bytes\": {6},\n" +
            "  \"steady_disk_peak_sample_bytes\": {25},\n" +
            "  \"compositor_p95_ms\": {7:F3},\n" +
            "  \"compositor_p99_ms\": {8:F3},\n" +
            "  \"hitches_over_25ms\": {9},\n" +
            "  \"hitches_over_50ms\": {10},\n" +
            "  \"unresponsive_samples\": {11},\n" +
            "  \"input_latency_max_us\": {12},\n" +
            "  \"message_pump_max_us\": {13},\n" +
            "  \"directinput_state_max_us\": {14},\n" +
            "  \"ai_tick_max_us\": {15},\n" +
            "  \"telemetry_queue_dropped\": {16},\n" +
            "  \"camera_moved_intervals\": {17},\n" +
            "  \"cursor_span_x\": {18},\n" +
            "  \"cursor_span_y\": {19},\n" +
            "  \"camera_span_x\": {20},\n" +
            "  \"camera_span_y\": {21},\n" +
            "  \"first_load_intervals\": {22},\n" +
            "  \"classified_bottleneck\": \"{23}\",\n" +
            "  \"system_cursor_calls\": 0,\n" +
            "  \"global_focus_calls\": 0,\n" +
            "  \"cursor_clip_restricted_samples\": {26},\n" +
            "  \"passed\": {24}\n}}\n",
            profile, level, seconds, samples.Count,
            elapsed <= 0 ? 0 : cpu / elapsed * 100,
            reads, peakRead, p95, p99,
            compositor.Count(value => value >= 25),
            compositor.Count(value => value >= 50),
            unresponsive,
            replayLatencyMax, pumpMax, inputMax,
            aiTickMax, telemetryDrops, cameraMoves,
            cursorSpanX, cursorSpanY, cameraSpanX, cameraSpanY,
            firstLoads, bottleneck,
            passed ? "true" : "false",
            steadyPeakRead,
            cursorClipRestricted);
        File.WriteAllText(
            Path.Combine(output, "performance.json"),
            json, new UTF8Encoding(false));
    }

    private static long Maximum(
        string text, string objectMarker, string valueMarker)
    {
        long result = 0;
        int start = 0;
        while ((start = text.IndexOf(
                   objectMarker, start,
                   StringComparison.Ordinal)) >= 0)
        {
            int end = text.IndexOf('}', start);
            if (end < 0) break;
            string part = text.Substring(start, end - start);
            Match match = Regex.Match(
                part,
                Regex.Escape(valueMarker) + "([0-9]+)");
            long value;
            if (match.Success &&
                long.TryParse(
                    match.Groups[1].Value,
                    NumberStyles.None,
                    CultureInfo.InvariantCulture,
                    out value))
                result = Math.Max(result, value);
            start = end + 1;
        }
        return result;
    }

    private static bool IsCursorClipRestricted()
    {
        Rect clip;
        if (!GetClipCursor(out clip))
            return true;
        int left = GetSystemMetrics(SmXVirtualScreen);
        int top = GetSystemMetrics(SmYVirtualScreen);
        int right = left + GetSystemMetrics(SmCxVirtualScreen);
        int bottom = top + GetSystemMetrics(SmCyVirtualScreen);
        return clip.Left > left || clip.Top > top ||
               clip.Right < right || clip.Bottom < bottom;
    }

    private static ulong SafeUInt64(long value)
    {
        return value > 0 ? (ulong)value : 0UL;
    }

    private static long CountTrue(string text, string marker)
    {
        long count = 0;
        int index = 0;
        while ((index = text.IndexOf(
                   marker, index,
                   StringComparison.Ordinal)) >= 0)
        {
            ++count;
            index += marker.Length;
        }
        return count;
    }

    private static double Percentile(
        IEnumerable<double> values, double percentile)
    {
        double[] ordered = values.OrderBy(value => value).ToArray();
        if (ordered.Length == 0) return 0;
        int index = (int)Math.Ceiling(percentile * ordered.Length) - 1;
        return ordered[Math.Max(0, Math.Min(ordered.Length - 1, index))];
    }

    private static int Span(IEnumerable<int> values)
    {
        int[] valid = values
            .Where(value => value != int.MinValue)
            .ToArray();
        return valid.Length == 0
            ? 0
            : valid.Max() - valid.Min();
    }

    private static IntPtr WaitWindow(Process game, TimeSpan timeout)
    {
        Stopwatch clock = Stopwatch.StartNew();
        while (clock.Elapsed < timeout && !game.HasExited)
        {
            game.Refresh();
            if (game.MainWindowHandle != IntPtr.Zero)
                return game.MainWindowHandle;
            Thread.Sleep(50);
        }
        return IntPtr.Zero;
    }

    private static bool WaitUntil(Func<bool> condition, TimeSpan timeout)
    {
        Stopwatch clock = Stopwatch.StartNew();
        while (clock.Elapsed < timeout)
        {
            if (condition()) return true;
            Thread.Sleep(50);
        }
        return false;
    }

    private static int ReadInt(IntPtr process, long address)
    {
        byte[] data = new byte[4];
        IntPtr read;
        return ReadProcessMemory(
            process, new IntPtr(address), data, 4, out read) &&
            read.ToInt64() == 4
            ? BitConverter.ToInt32(data, 0)
            : int.MinValue;
    }

    private static int ReadWorldActorCount(IntPtr process, long imageBase)
    {
        int world = ReadInt(process, imageBase + EngineAddresses.WorldRoot);
        if (world <= 0) return 0;
        int count = ReadInt(process, (long)(uint)world + 0x3C);
        return count > 0 && count <= 4096 ? count : 0;
    }

    private static string ReadSharedText(string path)
    {
        if (!File.Exists(path)) return "";
        for (int attempt = 0; attempt < 8; ++attempt)
        {
            try
            {
                using (var stream = new FileStream(
                    path, FileMode.Open, FileAccess.Read,
                    FileShare.ReadWrite | FileShare.Delete))
                using (var reader = new StreamReader(
                    stream, Encoding.UTF8, true))
                    return reader.ReadToEnd();
            }
            catch (IOException) { Thread.Sleep(100); }
        }
        return "";
    }

    private static void Stop(Process game)
    {
        if (game.HasExited) return;
        try { game.CloseMainWindow(); }
        catch { }
        if (game.WaitForExit(1200)) return;
        try { game.Kill(); game.WaitForExit(1200); }
        catch { }
    }
}
