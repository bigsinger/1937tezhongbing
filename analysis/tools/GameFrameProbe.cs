using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Imaging;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

internal static class GameFrameProbe
{
    private const uint PROCESS_VM_OPERATION = 0x0008;
    private const uint PROCESS_VM_READ = 0x0010;
    private const uint PROCESS_VM_WRITE = 0x0020;
    private const uint PROCESS_QUERY_INFORMATION = 0x0400;
    private const int PW_CLIENTONLY = 0x00000001;

    // Valid only for the verified clean M1937.exe used by this project.
    private const int CursorX = 0x000E6EA0;
    private const int CursorY = 0x000E6FAC;
    private const int LeftPressed = 0x000E6E64;
    private const int LeftDown = 0x000E6E74;
    private const int LeftReleased = 0x000E6FB0;
    private const int MenuSelection = 0x000E7060;

    [StructLayout(LayoutKind.Sequential)]
    private struct RECT { public int Left, Top, Right, Bottom; }

    [StructLayout(LayoutKind.Sequential)]
    private struct POINT { public int X, Y; }

    [StructLayout(LayoutKind.Sequential)]
    private struct IO_COUNTERS
    {
        public ulong ReadOperationCount, WriteOperationCount, OtherOperationCount;
        public ulong ReadTransferCount, WriteTransferCount, OtherTransferCount;
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr OpenProcess(uint access, bool inherit, int processId);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool WriteProcessMemory(IntPtr process, IntPtr address,
        byte[] data, int size, out IntPtr written);

    [DllImport("kernel32.dll")]
    private static extern bool CloseHandle(IntPtr handle);

    [DllImport("kernel32.dll")]
    private static extern bool GetProcessIoCounters(IntPtr process, out IO_COUNTERS counters);

    [DllImport("user32.dll")]
    private static extern bool PrintWindow(IntPtr window, IntPtr dc, uint flags);

    [DllImport("user32.dll")]
    private static extern bool GetClientRect(IntPtr window, out RECT rect);

    [DllImport("user32.dll")]
    private static extern bool ClientToScreen(IntPtr window, ref POINT point);

    [DllImport("user32.dll")]
    private static extern bool SetForegroundWindow(IntPtr window);

    [DllImport("user32.dll")]
    private static extern bool SetWindowPos(IntPtr window, IntPtr insertAfter,
        int x, int y, int width, int height, uint flags);

    [DllImport("user32.dll")]
    private static extern bool SetCursorPos(int x, int y);

    [DllImport("user32.dll")]
    private static extern void mouse_event(uint flags, uint dx, uint dy,
        uint data, UIntPtr extraInfo);

    [DllImport("user32.dll")]
    private static extern void keybd_event(byte virtualKey, byte scan,
        uint flags, UIntPtr extraInfo);

    private sealed class Sample
    {
        public double Milliseconds;
        public int ChangedPixels;
        public bool Responding;
        public ulong ReadBytes;
        public double CpuMilliseconds;
    }

    public static int Main(string[] args)
    {
        if (args.Length < 3)
        {
            Console.Error.WriteLine("Usage: GameFrameProbe.exe GAME_DIR OUTPUT_DIR TEST_NAME [SECONDS]");
            return 2;
        }

        string gameDirectory = Path.GetFullPath(args[0]);
        string outputDirectory = Path.GetFullPath(args[1]);
        string testName = args[2];
        double durationSeconds = args.Length >= 4
            ? double.Parse(args[3], CultureInfo.InvariantCulture) : 24.0;
        bool captureFrames = args.Length < 5 ||
            !string.Equals(args[4], "nocapture", StringComparison.OrdinalIgnoreCase);
        string executable = Path.Combine(gameDirectory, "M1937.exe");
        Directory.CreateDirectory(outputDirectory);

        var startInfo = new ProcessStartInfo(executable)
        {
            WorkingDirectory = gameDirectory,
            UseShellExecute = false
        };

        using (Process game = Process.Start(startInfo))
        {
            if (game == null) throw new InvalidOperationException("Could not launch M1937.exe");
            IntPtr window = WaitForWindow(game, TimeSpan.FromSeconds(12));
            if (window == IntPtr.Zero) throw new InvalidOperationException("Game window did not appear");
            // Direct3D9 surfaces do not implement PrintWindow reliably. Keep the
            // small test window visible so desktop-composition capture measures
            // what the player actually sees.
            SetWindowPos(window, new IntPtr(-1), 40, 40, 0, 0, 0x0001 | 0x0040);
            SetForegroundWindow(window);

            IntPtr processHandle = OpenProcess(
                PROCESS_QUERY_INFORMATION | PROCESS_VM_OPERATION | PROCESS_VM_READ | PROCESS_VM_WRITE,
                false, game.Id);
            if (processHandle == IntPtr.Zero) throw new InvalidOperationException("OpenProcess failed");

            try
            {
                game.Refresh();
                long imageBase = game.MainModule.BaseAddress.ToInt64();
                var clock = Stopwatch.StartNew();
                var driveThread = new Thread(() => DriveGame(
                    processHandle, imageBase, window, clock, durationSeconds));
                driveThread.IsBackground = true;
                driveThread.Start();

                List<Sample> samples;
                Bitmap finalFrame;
                if (captureFrames)
                {
                    CaptureFrames(game, processHandle, window, clock, durationSeconds,
                        out samples, out finalFrame);
                }
                else
                {
                    CollectProcessSamples(game, processHandle, clock,
                        durationSeconds, out samples);
                    finalFrame = null;
                }
                driveThread.Join(1000);

                string csvPath = Path.Combine(outputDirectory, testName + ".csv");
                WriteCsv(csvPath, samples);
                if (finalFrame != null)
                {
                    string screenshotPath = Path.Combine(outputDirectory, testName + ".png");
                    finalFrame.Save(screenshotPath, ImageFormat.Png);
                    finalFrame.Dispose();
                }
                string summary = BuildSummary(testName, samples, durationSeconds);
                File.WriteAllText(Path.Combine(outputDirectory, testName + ".txt"), summary, Encoding.UTF8);
                Console.WriteLine(summary);
            }
            finally
            {
                CloseHandle(processHandle);
                StopLaunchedGame(game);
            }
        }
        return 0;
    }

    private static IntPtr WaitForWindow(Process game, TimeSpan timeout)
    {
        Stopwatch wait = Stopwatch.StartNew();
        while (wait.Elapsed < timeout && !game.HasExited)
        {
            game.Refresh();
            if (game.MainWindowHandle != IntPtr.Zero) return game.MainWindowHandle;
            Thread.Sleep(50);
        }
        return IntPtr.Zero;
    }

    private static void DriveGame(IntPtr process, long imageBase, IntPtr window,
        Stopwatch clock, double durationSeconds)
    {
        // Enter the first mission without relying on the physical mouse. The
        // write targets are volatile input-state globals, never executable code.
        double[] clickTimes = { 1.30, 4.00, 6.00, 8.00, 10.00, 12.00,
            14.00, 16.00, 18.00, 20.00 };
        bool[] clickStarted = new bool[clickTimes.Length];
        bool[] clickReleased = new bool[clickTimes.Length];
        int previousDirection = -1;

        while (clock.Elapsed.TotalSeconds < durationSeconds)
        {
            double t = clock.Elapsed.TotalSeconds;
            if (t < 2.60)
            {
                WriteInt(process, imageBase + CursorX, 270);
                WriteInt(process, imageBase + CursorY, 365);
                WriteInt(process, imageBase + MenuSelection, 1);
            }
            else if (t >= 22.00)
            {
                // Alternate edges so the camera never remains pinned at a map
                // boundary. This supplies deterministic continuous motion.
                int edgeX = ((int)((t - 22.0) / 1.5) & 1) == 0 ? 635 : 5;
                WriteInt(process, imageBase + CursorX, edgeX);
                WriteInt(process, imageBase + CursorY, 240);
            }

            for (int i = 0; i < clickTimes.Length; ++i)
            {
                if (!clickStarted[i] && t >= clickTimes[i])
                {
                    POINT point = new POINT { X = 270, Y = 365 };
                    ClientToScreen(window, ref point);
                    SetForegroundWindow(window);
                    SetCursorPos(point.X, point.Y);
                    mouse_event(0x0002, 0, 0, 0, UIntPtr.Zero);
                    if (i > 0) keybd_event(0x0D, 0, 0, UIntPtr.Zero);
                    WriteInt(process, imageBase + LeftPressed, 1);
                    WriteInt(process, imageBase + LeftDown, 1);
                    clickStarted[i] = true;
                }
                if (!clickReleased[i] && t >= clickTimes[i] + 0.10)
                {
                    mouse_event(0x0004, 0, 0, 0, UIntPtr.Zero);
                    if (i > 0) keybd_event(0x0D, 0, 0x0002, UIntPtr.Zero);
                    WriteInt(process, imageBase + LeftPressed, 0);
                    WriteInt(process, imageBase + LeftDown, 0);
                    WriteInt(process, imageBase + LeftReleased, 1);
                    clickReleased[i] = true;
                }
                if (clickReleased[i] && t >= clickTimes[i] + 0.20)
                {
                    WriteInt(process, imageBase + LeftReleased, 0);
                }
            }
            if (t >= 22.00)
            {
                int direction = ((int)((t - 22.0) / 1.5) & 1);
                int edgeX = direction == 0 ? 635 : 5;
                POINT edge = new POINT { X = edgeX, Y = 240 };
                ClientToScreen(window, ref edge);
                SetCursorPos(edge.X, edge.Y);
                if (direction != previousDirection)
                {
                    keybd_event(0x25, 0, 0x0002, UIntPtr.Zero);
                    keybd_event(0x27, 0, 0x0002, UIntPtr.Zero);
                    keybd_event(direction == 0 ? (byte)0x27 : (byte)0x25,
                        0, 0, UIntPtr.Zero);
                    previousDirection = direction;
                }
            }
            Thread.Sleep(2);
        }
        keybd_event(0x25, 0, 0x0002, UIntPtr.Zero);
        keybd_event(0x27, 0, 0x0002, UIntPtr.Zero);
    }

    private static void WriteInt(IntPtr process, long address, int value)
    {
        byte[] bytes = BitConverter.GetBytes(value);
        IntPtr ignored;
        WriteProcessMemory(process, new IntPtr(address), bytes, bytes.Length, out ignored);
    }

    private static void CaptureFrames(Process game, IntPtr processHandle, IntPtr window,
        Stopwatch clock, double durationSeconds, out List<Sample> samples,
        out Bitmap finalFrame)
    {
        RECT rect;
        if (!GetClientRect(window, out rect)) throw new InvalidOperationException("GetClientRect failed");
        int clientWidth = Math.Max(1, rect.Right - rect.Left);
        int clientHeight = Math.Max(1, rect.Bottom - rect.Top);
        int width = Math.Min(320, clientWidth);
        int height = Math.Min(240, clientHeight);
        int captureOffsetX = (clientWidth - width) / 2;
        int captureOffsetY = (clientHeight - height) / 2;
        var frame = new Bitmap(width, height, PixelFormat.Format32bppArgb);
        byte[] previous = null;
        samples = new List<Sample>();
        double nextSample = 0;

        while (clock.Elapsed.TotalSeconds < durationSeconds && !game.HasExited)
        {
            double now = clock.Elapsed.TotalSeconds;
            if (now < nextSample)
            {
                int wait = (int)Math.Max(0, Math.Min(5, (nextSample - now) * 1000));
                if (wait > 0) Thread.Sleep(wait);
                else Thread.Yield();
                continue;
            }
            nextSample += 0.020; // 50 Hz observation, enough to reveal >80 ms hitches.

            POINT clientOrigin = new POINT { X = captureOffsetX, Y = captureOffsetY };
            ClientToScreen(window, ref clientOrigin);
            using (Graphics graphics = Graphics.FromImage(frame))
                graphics.CopyFromScreen(clientOrigin.X, clientOrigin.Y, 0, 0,
                    new Size(width, height), CopyPixelOperation.SourceCopy);

            int changed;
            previous = CompareAndCopy(frame, previous, out changed);
            IO_COUNTERS io;
            GetProcessIoCounters(processHandle, out io);
            game.Refresh();
            samples.Add(new Sample
            {
                Milliseconds = clock.Elapsed.TotalMilliseconds,
                ChangedPixels = changed,
                Responding = game.Responding,
                ReadBytes = io.ReadTransferCount,
                CpuMilliseconds = game.TotalProcessorTime.TotalMilliseconds
            });
        }
        finalFrame = (Bitmap)frame.Clone();
        frame.Dispose();
    }

    private static void CollectProcessSamples(Process game, IntPtr processHandle,
        Stopwatch clock, double durationSeconds, out List<Sample> samples)
    {
        samples = new List<Sample>();
        while (clock.Elapsed.TotalSeconds < durationSeconds && !game.HasExited)
        {
            IO_COUNTERS io;
            GetProcessIoCounters(processHandle, out io);
            game.Refresh();
            samples.Add(new Sample
            {
                Milliseconds = clock.Elapsed.TotalMilliseconds,
                ChangedPixels = 0,
                Responding = game.Responding,
                ReadBytes = io.ReadTransferCount,
                CpuMilliseconds = game.TotalProcessorTime.TotalMilliseconds
            });
            Thread.Sleep(20);
        }
    }

    private static byte[] CompareAndCopy(Bitmap bitmap, byte[] previous, out int changed)
    {
        Rectangle area = new Rectangle(0, 0, bitmap.Width, bitmap.Height);
        BitmapData data = bitmap.LockBits(area, ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
        try
        {
            int length = Math.Abs(data.Stride) * bitmap.Height;
            byte[] current = new byte[length];
            Marshal.Copy(data.Scan0, current, 0, length);
            changed = 0;
            if (previous == null || previous.Length != current.Length)
            {
                changed = bitmap.Width * bitmap.Height;
            }
            else
            {
                // Subsample every 3 pixels. Ignore tiny RGB differences caused by
                // composition/dithering; this tracks real scene motion.
                int pixelStep = 12;
                for (int offset = 0; offset + 2 < length; offset += pixelStep)
                {
                    int difference = Math.Abs(current[offset] - previous[offset])
                        + Math.Abs(current[offset + 1] - previous[offset + 1])
                        + Math.Abs(current[offset + 2] - previous[offset + 2]);
                    if (difference >= 18) ++changed;
                }
            }
            return current;
        }
        finally { bitmap.UnlockBits(data); }
    }

    private static void WriteCsv(string path, List<Sample> samples)
    {
        using (var writer = new StreamWriter(path, false, new UTF8Encoding(false)))
        {
            writer.WriteLine("time_ms,changed_pixels,responding,read_bytes,cpu_ms");
            foreach (Sample sample in samples)
            {
                writer.WriteLine(string.Format(CultureInfo.InvariantCulture,
                    "{0:F3},{1},{2},{3},{4:F3}", sample.Milliseconds,
                    sample.ChangedPixels, sample.Responding ? 1 : 0,
                    sample.ReadBytes, sample.CpuMilliseconds));
            }
        }
    }

    private static string BuildSummary(string name, List<Sample> allSamples,
        double durationSeconds)
    {
        // Exclude startup/menu/briefing; evaluate only continuous map scrolling.
        List<Sample> samples = allSamples.Where(s => s.Milliseconds >= 23000).ToList();
        List<double> changedTimes = samples.Where(s => s.ChangedPixels >= 20)
            .Select(s => s.Milliseconds).ToList();
        var intervals = new List<double>();
        for (int i = 1; i < changedTimes.Count; ++i) intervals.Add(changedTimes[i] - changedTimes[i - 1]);
        intervals.Sort();

        double elapsedMs = samples.Count >= 2
            ? samples[samples.Count - 1].Milliseconds - samples[0].Milliseconds : 0;
        double cpuMs = samples.Count >= 2
            ? samples[samples.Count - 1].CpuMilliseconds - samples[0].CpuMilliseconds : 0;
        ulong readBytes = samples.Count >= 2
            ? samples[samples.Count - 1].ReadBytes - samples[0].ReadBytes : 0;
        int unresponsive = samples.Count(s => !s.Responding);

        Func<double, double> percentile = p =>
        {
            if (intervals.Count == 0) return 0;
            int index = (int)Math.Ceiling(p * intervals.Count) - 1;
            return intervals[Math.Max(0, Math.Min(intervals.Count - 1, index))];
        };

        return string.Format(CultureInfo.InvariantCulture,
            "test={0}\r\n" +
            "duration_s={1:F1}\r\n" +
            "gameplay_samples={2}\r\n" +
            "changed_frames={3}\r\n" +
            "frame_interval_p50_ms={4:F2}\r\n" +
            "frame_interval_p95_ms={5:F2}\r\n" +
            "frame_interval_p99_ms={6:F2}\r\n" +
            "frame_interval_max_ms={7:F2}\r\n" +
            "gaps_over_80ms={8}\r\n" +
            "gaps_over_120ms={9}\r\n" +
            "cpu_one_logical_core_percent={10:F1}\r\n" +
            "read_during_gameplay_bytes={11}\r\n" +
            "unresponsive_samples={12}\r\n",
            name, durationSeconds, samples.Count, changedTimes.Count,
            percentile(0.50), percentile(0.95), percentile(0.99),
            intervals.Count == 0 ? 0 : intervals[intervals.Count - 1],
            intervals.Count(x => x > 80), intervals.Count(x => x > 120),
            elapsedMs <= 0 ? 0 : cpuMs / elapsedMs * 100.0,
            readBytes, unresponsive);
    }

    private static void StopLaunchedGame(Process game)
    {
        if (game.HasExited) return;
        try { game.CloseMainWindow(); }
        catch { }
        if (game.WaitForExit(1500)) return;
        try { game.Kill(); game.WaitForExit(1500); }
        catch { }
    }
}
