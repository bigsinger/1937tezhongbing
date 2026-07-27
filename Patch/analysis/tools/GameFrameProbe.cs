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
using EngineAddresses = Mission1937.SDK.Generated.M1937Addresses;

internal static class GameFrameProbe
{
    private const uint PROCESS_VM_OPERATION = 0x0008;
    private const uint PROCESS_VM_READ = 0x0010;
    private const uint PROCESS_VM_WRITE = 0x0020;
    private const uint PROCESS_QUERY_INFORMATION = 0x0400;
    private const int PW_CLIENTONLY = 0x00000001;

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

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool ReadProcessMemory(IntPtr process, IntPtr address,
        byte[] data, int size, out IntPtr read);

    [DllImport("kernel32.dll")]
    private static extern bool CloseHandle(IntPtr handle);

    [DllImport("kernel32.dll")]
    private static extern bool GetProcessIoCounters(IntPtr process, out IO_COUNTERS counters);

    [DllImport("user32.dll")]
    private static extern bool PrintWindow(IntPtr window, IntPtr dc, uint flags);

    [DllImport("user32.dll")]
    private static extern bool GetClientRect(IntPtr window, out RECT rect);

    private delegate bool EnumWindowsProc(IntPtr window, IntPtr parameter);

    [DllImport("user32.dll")]
    private static extern bool EnumWindows(
        EnumWindowsProc callback, IntPtr parameter);

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(
        IntPtr window, out uint processId);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetWindowText(
        IntPtr window, StringBuilder text, int maximum);

    [DllImport("user32.dll")]
    private static extern bool IsWindow(IntPtr window);

    [DllImport("user32.dll")]
    private static extern bool IsWindowVisible(IntPtr window);

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
        public int CameraX;
        public int CameraY;
        public int Mission;
        public int CursorX;
        public int CursorY;
        public int ScrollActionBlock;
        public int ScrollDisabled;
        public int ScrollVelocity;
        public int ScrollVelocityLimit;
        public int ScrollDirection;
        public int WorldActorCount;
    }

    public static int Main(string[] args)
    {
        Console.OutputEncoding = Encoding.UTF8;
        try
        {
            return Run(args);
        }
        catch (Exception exception)
        {
            Console.Error.WriteLine(
                exception.GetType().FullName + ": " + exception.Message);
            return 1;
        }
    }

    private static int Run(string[] args)
    {
        if (args.Length < 3)
        {
            Console.Error.WriteLine(
                "Usage: GameFrameProbe.exe GAME_DIR OUTPUT_DIR TEST_NAME [SECONDS] " +
                "[nocapture] [nonintrusive] [forcecameracorners] " +
                "[replacementbriefing] [level=1..15]");
            return 2;
        }

        string gameDirectory = Path.GetFullPath(args[0]);
        string outputDirectory = Path.GetFullPath(args[1]);
        string testName = args[2];
        double durationSeconds = args.Length >= 4
            ? double.Parse(args[3], CultureInfo.InvariantCulture) : 24.0;
        bool captureFrames = args.Length < 5 ||
            !args.Any(argument => string.Equals(
                argument, "nocapture", StringComparison.OrdinalIgnoreCase));
        bool nonIntrusive = args.Any(argument => string.Equals(
            argument, "nonintrusive", StringComparison.OrdinalIgnoreCase));
        bool forceCameraCorners = args.Any(argument => string.Equals(
            argument, "forcecameracorners", StringComparison.OrdinalIgnoreCase));
        bool replacementBriefing = args.Any(argument => string.Equals(
            argument, "replacementbriefing", StringComparison.OrdinalIgnoreCase));
        int requestedSelectorLevel = 0;
        string levelArgument = args.FirstOrDefault(argument =>
            argument.StartsWith(
                "level=", StringComparison.OrdinalIgnoreCase));
        if (levelArgument != null &&
            (!int.TryParse(
                levelArgument.Substring("level=".Length),
                NumberStyles.Integer,
                CultureInfo.InvariantCulture,
                out requestedSelectorLevel) ||
             requestedSelectorLevel < 1 ||
             requestedSelectorLevel > 15))
            throw new ArgumentOutOfRangeException(
                "level", "Selector level must be between 1 and 15.");
        int cameraMaximumX = -1;
        int cameraMaximumY = -1;
        if (forceCameraCorners)
            ReadSelectedMapCameraBounds(
                gameDirectory, out cameraMaximumX, out cameraMaximumY);
        string executable = Path.Combine(gameDirectory, "M1937.exe");
        Directory.CreateDirectory(outputDirectory);

        var startInfo = new ProcessStartInfo(executable)
        {
            WorkingDirectory = gameDirectory,
            UseShellExecute = false
        };
        if (nonIntrusive && !replacementBriefing)
            startInfo.EnvironmentVariables["M1937_AUTOTEST"] = "1";
        if (replacementBriefing)
        {
            int selectorLevel = requestedSelectorLevel > 0
                ? requestedSelectorLevel
                : ReadConfiguredSelectorLevel(gameDirectory);
            startInfo.EnvironmentVariables["M1937_START_LEVEL"] =
                selectorLevel.ToString(CultureInfo.InvariantCulture);
            startInfo.EnvironmentVariables["M1937_AUTO_START"] = "1";
            startInfo.EnvironmentVariables[
                "M1937_REPLACE_LEGACY_BRIEFING"] = "1";
            startInfo.EnvironmentVariables[
                "M1937_BRIEFING_AUTOCLOSE_MS"] = "5000";
        }

        using (Process game = Process.Start(startInfo))
        {
            if (game == null) throw new InvalidOperationException("Could not launch M1937.exe");
            IntPtr window = WaitForWindow(game, TimeSpan.FromSeconds(12));
            if (window == IntPtr.Zero) throw new InvalidOperationException("Game window did not appear");
            // Direct3D9 surfaces do not implement PrintWindow reliably. Keep the
            // small test window visible so desktop-composition capture measures
            // what the player actually sees.
            SetWindowPos(
                window,
                nonIntrusive ? IntPtr.Zero : new IntPtr(-1),
                40,
                40,
                0,
                0,
                nonIntrusive ? 0x0001u | 0x0004u | 0x0010u : 0x0001u | 0x0040u);
            if (!nonIntrusive) SetForegroundWindow(window);

            string briefingTitle = string.Empty;
            if (replacementBriefing)
            {
                IntPtr briefingWindow = WaitForTextBriefingWindow(
                    game.Id, TimeSpan.FromSeconds(12), out briefingTitle);
                if (briefingWindow == IntPtr.Zero)
                    throw new InvalidOperationException(
                        "The in-game text briefing window did not appear.");
                CaptureNativeWindow(
                    briefingWindow,
                    Path.Combine(
                        outputDirectory,
                        testName + "-briefing.png"));
                File.WriteAllText(
                    Path.Combine(
                        outputDirectory,
                        testName + "-briefing.txt"),
                    briefingTitle,
                    Encoding.UTF8);
                Stopwatch closing = Stopwatch.StartNew();
                while (IsWindow(briefingWindow) &&
                    closing.Elapsed < TimeSpan.FromSeconds(8))
                    Thread.Sleep(50);
                if (IsWindow(briefingWindow))
                    throw new InvalidOperationException(
                        "The in-game text briefing did not auto-close.");
            }

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
                    processHandle, imageBase, window, clock, durationSeconds,
                    nonIntrusive, forceCameraCorners,
                    cameraMaximumX, cameraMaximumY));
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
                        durationSeconds, imageBase, out samples);
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
                if (replacementBriefing)
                    summary +=
                        "text_briefing_window=captured\r\n" +
                        "text_briefing_title=" + briefingTitle + "\r\n";
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

    private static IntPtr WaitForTextBriefingWindow(
        int processId, TimeSpan timeout, out string title)
    {
        Stopwatch wait = Stopwatch.StartNew();
        IntPtr match = IntPtr.Zero;
        string foundTitle = string.Empty;
        while (wait.Elapsed < timeout && match == IntPtr.Zero)
        {
            EnumWindows(delegate(IntPtr candidate, IntPtr unused)
            {
                uint ownerProcess;
                GetWindowThreadProcessId(candidate, out ownerProcess);
                if (ownerProcess != (uint)processId ||
                    !IsWindowVisible(candidate))
                    return true;
                var buffer = new StringBuilder(256);
                GetWindowText(candidate, buffer, buffer.Capacity);
                string candidateTitle = buffer.ToString();
                if (!candidateTitle.Contains("游戏内文字任务简报"))
                    return true;
                match = candidate;
                foundTitle = candidateTitle;
                return false;
            }, IntPtr.Zero);
            if (match == IntPtr.Zero) Thread.Sleep(50);
        }
        title = foundTitle;
        return match;
    }

    private static void CaptureNativeWindow(IntPtr window, string path)
    {
        RECT rect;
        if (!GetClientRect(window, out rect))
            throw new InvalidOperationException(
                "GetClientRect failed for the text briefing.");
        int width = Math.Max(1, rect.Right - rect.Left);
        int height = Math.Max(1, rect.Bottom - rect.Top);
        using (var bitmap = new Bitmap(
            width, height, PixelFormat.Format32bppArgb))
        using (Graphics graphics = Graphics.FromImage(bitmap))
        {
            IntPtr dc = graphics.GetHdc();
            bool captured;
            try
            {
                captured = PrintWindow(window, dc, PW_CLIENTONLY);
            }
            finally
            {
                graphics.ReleaseHdc(dc);
            }
            if (!captured)
                throw new InvalidOperationException(
                    "PrintWindow failed for the text briefing.");
            bitmap.Save(path, ImageFormat.Png);
        }
    }

    private static void DriveGame(IntPtr process, long imageBase, IntPtr window,
        Stopwatch clock, double durationSeconds, bool nonIntrusive,
        bool forceCameraCorners, int cameraMaximumX, int cameraMaximumY)
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
            int screenWidth = ReadInt(
                process, imageBase + EngineAddresses.ScreenWidth);
            int screenHeight = ReadInt(
                process, imageBase + EngineAddresses.ScreenHeight);
            if (screenWidth < 320 || screenWidth > 4096) screenWidth = 800;
            if (screenHeight < 240 || screenHeight > 2160) screenHeight = 600;
            int menuX = (int)Math.Round(screenWidth * 0.265);
            int menuY = (int)Math.Round(screenHeight * 0.473);
            if (t < 2.60)
            {
                WriteInt(
                    process, imageBase + EngineAddresses.CursorX, menuX);
                WriteInt(
                    process, imageBase + EngineAddresses.CursorY, menuY);
            }
            else if (t >= 22.00)
            {
                // Hold each cardinal edge long enough for the original
                // acceleration ramp to move across a large map. Input is
                // written only to this process's legacy cursor globals.
                int phase = (int)((t - 22.0) / 8.0) & 3;
                int edgeX = phase == 0
                    ? screenWidth - 1
                    : phase == 2 ? 1 : screenWidth / 2;
                int edgeY = phase == 1
                    ? screenHeight - 1
                    : phase == 3 ? 1 : screenHeight / 2;
                WriteInt(
                    process, imageBase + EngineAddresses.CursorX, edgeX);
                WriteInt(
                    process, imageBase + EngineAddresses.CursorY,
                    edgeY);

                // A no-activate test deliberately leaves the user's foreground
                // window alone, and the legacy engine therefore suppresses
                // normal edge scrolling. For map-extent validation only, move
                // the launched process's camera state through all four legal
                // corners. This never moves, clips or reads the physical cursor.
                if (forceCameraCorners)
                {
                    int cameraX = phase == 0 || phase == 3
                        ? 0 : cameraMaximumX;
                    int cameraY = phase == 0 || phase == 1
                        ? 0 : cameraMaximumY;
                    WriteInt(
                        process,
                        imageBase + EngineAddresses.CameraX,
                        cameraX);
                    WriteInt(
                        process,
                        imageBase + EngineAddresses.CameraY,
                        cameraY);
                }
            }

            for (int i = 0; i < clickTimes.Length; ++i)
            {
                if (!clickStarted[i] && t >= clickTimes[i])
                {
                    if (!nonIntrusive)
                    {
                        POINT point = new POINT { X = menuX, Y = menuY };
                        ClientToScreen(window, ref point);
                        SetForegroundWindow(window);
                        SetCursorPos(point.X, point.Y);
                        mouse_event(0x0002, 0, 0, 0, UIntPtr.Zero);
                        if (i > 0) keybd_event(0x0D, 0, 0, UIntPtr.Zero);
                    }
                    WriteInt(
                        process,
                        imageBase + EngineAddresses.MouseLeftPressed, 1);
                    WriteInt(
                        process,
                        imageBase + EngineAddresses.MouseLeftDown, 1);
                    clickStarted[i] = true;
                }
                if (!clickReleased[i] && t >= clickTimes[i] + 0.10)
                {
                    if (!nonIntrusive)
                    {
                        mouse_event(0x0004, 0, 0, 0, UIntPtr.Zero);
                        if (i > 0) keybd_event(0x0D, 0, 0x0002, UIntPtr.Zero);
                    }
                    WriteInt(
                        process,
                        imageBase + EngineAddresses.MouseLeftPressed, 0);
                    WriteInt(
                        process,
                        imageBase + EngineAddresses.MouseLeftDown, 0);
                    WriteInt(
                        process,
                        imageBase + EngineAddresses.MouseLeftReleased, 1);
                    clickReleased[i] = true;
                }
                if (clickReleased[i] && t >= clickTimes[i] + 0.20)
                {
                    WriteInt(
                        process,
                        imageBase + EngineAddresses.MouseLeftReleased, 0);
                }
            }
            if (t >= 22.00)
            {
                int direction = (int)((t - 22.0) / 8.0) & 3;
                int edgeX = direction == 0
                    ? screenWidth - 1
                    : direction == 2 ? 1 : screenWidth / 2;
                int edgeY = direction == 1
                    ? screenHeight - 1
                    : direction == 3 ? 1 : screenHeight / 2;
                if (!nonIntrusive)
                {
                    POINT edge = new POINT { X = edgeX, Y = edgeY };
                    ClientToScreen(window, ref edge);
                    SetCursorPos(edge.X, edge.Y);
                    if (direction != previousDirection)
                    {
                        keybd_event(0x25, 0, 0x0002, UIntPtr.Zero);
                        keybd_event(0x27, 0, 0x0002, UIntPtr.Zero);
                        keybd_event(0x26, 0, 0x0002, UIntPtr.Zero);
                        keybd_event(0x28, 0, 0x0002, UIntPtr.Zero);
                        byte key = direction == 0
                            ? (byte)0x27
                            : direction == 1
                                ? (byte)0x28
                                : direction == 2
                                    ? (byte)0x25
                                    : (byte)0x26;
                        keybd_event(key, 0, 0, UIntPtr.Zero);
                        previousDirection = direction;
                    }
                }
            }
            Thread.Sleep(2);
        }
        if (!nonIntrusive)
        {
            keybd_event(0x25, 0, 0x0002, UIntPtr.Zero);
            keybd_event(0x27, 0, 0x0002, UIntPtr.Zero);
            keybd_event(0x26, 0, 0x0002, UIntPtr.Zero);
            keybd_event(0x28, 0, 0x0002, UIntPtr.Zero);
        }
    }

    private static void WriteInt(IntPtr process, long address, int value)
    {
        byte[] bytes = BitConverter.GetBytes(value);
        IntPtr ignored;
        WriteProcessMemory(process, new IntPtr(address), bytes, bytes.Length, out ignored);
    }

    private static void ReadSelectedMapCameraBounds(
        string gameDirectory, out int maximumX, out int maximumY)
    {
        int selectorLevel = ReadConfiguredSelectorLevel(gameDirectory);
        string vwfPath = Path.Combine(
            gameDirectory,
            string.Format(
                CultureInfo.InvariantCulture,
                "1937m{0:D3}.vwf",
                selectorLevel - 1));
        byte[] header = new byte[144];
        using (var stream = new FileStream(
            vwfPath, FileMode.Open, FileAccess.Read, FileShare.Read))
        {
            int offset = 0;
            while (offset < header.Length)
            {
                int read = stream.Read(header, offset, header.Length - offset);
                if (read == 0) throw new EndOfStreamException(vwfPath);
                offset += read;
            }
        }
        const string magic = "VWL1 Intuition Engine Virtual World File";
        if (!Encoding.ASCII.GetString(header).StartsWith(
                magic, StringComparison.Ordinal))
            throw new InvalidDataException(
                "Selected file is not a VWF world: " + vwfPath);

        uint viewportWidth = BitConverter.ToUInt32(header, 95);
        uint viewportHeight = BitConverter.ToUInt32(header, 99);
        uint gridWidth = BitConverter.ToUInt32(header, 135);
        uint gridHeight = BitConverter.ToUInt32(header, 139);
        long boundX = checked((long)gridWidth * 32 - viewportWidth);
        long boundY = checked((long)gridHeight * 16 - viewportHeight);
        if (boundX < 0 || boundX > int.MaxValue ||
            boundY < 0 || boundY > int.MaxValue)
            throw new InvalidDataException(
                "Selected VWF contains invalid camera bounds.");
        maximumX = (int)boundX;
        maximumY = (int)boundY;
    }

    private static int ReadConfiguredSelectorLevel(string gameDirectory)
    {
        string iniPath = Path.Combine(gameDirectory, "rungame.ini");
        int selectorLevel = 0;
        bool inModSection = false;
        foreach (string rawLine in File.ReadAllLines(iniPath))
        {
            string line = rawLine.Trim();
            if (line.StartsWith("[") && line.EndsWith("]"))
            {
                inModSection = string.Equals(
                    line, "[mod]", StringComparison.OrdinalIgnoreCase);
                continue;
            }
            if (!inModSection) continue;
            int equals = line.IndexOf('=');
            if (equals <= 0 ||
                !string.Equals(
                    line.Substring(0, equals).Trim(),
                    "StartLevel",
                    StringComparison.OrdinalIgnoreCase))
                continue;
            int.TryParse(
                line.Substring(equals + 1).Trim(),
                NumberStyles.Integer,
                CultureInfo.InvariantCulture,
                out selectorLevel);
            break;
        }
        if (selectorLevel < 1)
            throw new InvalidDataException(
                "The probe requires [mod] StartLevel in rungame.ini.");
        return selectorLevel;
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
        Stopwatch clock, double durationSeconds, long imageBase,
        out List<Sample> samples)
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
                CpuMilliseconds = game.TotalProcessorTime.TotalMilliseconds,
                CameraX = ReadInt(
                    processHandle, imageBase + EngineAddresses.CameraX),
                CameraY = ReadInt(
                    processHandle, imageBase + EngineAddresses.CameraY),
                Mission = ReadInt(
                    processHandle,
                    imageBase + EngineAddresses.CurrentMission),
                CursorX = ReadInt(
                    processHandle, imageBase + EngineAddresses.CursorX),
                CursorY = ReadInt(
                    processHandle, imageBase + EngineAddresses.CursorY),
                ScrollActionBlock = ReadInt(
                    processHandle,
                    imageBase + EngineAddresses.InputScrollBlock),
                WorldActorCount = ReadWorldActorCount(
                    processHandle, imageBase)
            });
            int viewportController = ReadInt(
                processHandle,
                imageBase + EngineAddresses.ViewportController);
            if (viewportController > 0)
            {
                Sample current = samples[samples.Count - 1];
                current.ScrollVelocity = ReadInt(
                    processHandle, viewportController + 0x5C);
                current.ScrollVelocityLimit = ReadInt(
                    processHandle, viewportController + 0x60);
                current.ScrollDirection = ReadInt(
                    processHandle, viewportController + 0x64);
                current.ScrollDisabled = ReadInt(
                    processHandle, viewportController + 0x70);
            }
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

    private static int ReadInt(IntPtr process, long address)
    {
        byte[] bytes = new byte[4];
        IntPtr read;
        return ReadProcessMemory(
            process, new IntPtr(address), bytes, bytes.Length, out read) &&
            read.ToInt64() == bytes.Length
            ? BitConverter.ToInt32(bytes, 0)
            : int.MinValue;
    }

    private static int ReadWorldActorCount(IntPtr process, long imageBase)
    {
        int world = ReadInt(
            process, imageBase + EngineAddresses.WorldRoot);
        if (world <= 0) return 0;
        int count = ReadInt(process, (long)(uint)world + 0x3C);
        return count > 0 && count <= 4096 ? count : 0;
    }

    private static void WriteCsv(string path, List<Sample> samples)
    {
        using (var writer = new StreamWriter(path, false, new UTF8Encoding(false)))
        {
            writer.WriteLine(
                "time_ms,changed_pixels,responding,read_bytes,cpu_ms," +
                "camera_x,camera_y,mission,cursor_x,cursor_y," +
                "scroll_action_block,scroll_disabled,scroll_velocity," +
                "scroll_velocity_limit,scroll_direction,world_actor_count");
            foreach (Sample sample in samples)
            {
                writer.WriteLine(string.Format(CultureInfo.InvariantCulture,
                    "{0:F3},{1},{2},{3},{4:F3},{5},{6},{7}," +
                    "{8},{9},{10},{11},{12},{13},{14},{15}",
                    sample.Milliseconds,
                    sample.ChangedPixels, sample.Responding ? 1 : 0,
                    sample.ReadBytes, sample.CpuMilliseconds,
                    sample.CameraX, sample.CameraY, sample.Mission,
                    sample.CursorX, sample.CursorY,
                    sample.ScrollActionBlock, sample.ScrollDisabled,
                    sample.ScrollVelocity, sample.ScrollVelocityLimit,
                    sample.ScrollDirection, sample.WorldActorCount));
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
        var validCamera = samples.Where(
            s => s.CameraX != int.MinValue && s.CameraY != int.MinValue).ToList();
        int cameraRangeX = validCamera.Count == 0
            ? 0 : validCamera.Max(s => s.CameraX) - validCamera.Min(s => s.CameraX);
        int cameraRangeY = validCamera.Count == 0
            ? 0 : validCamera.Max(s => s.CameraY) - validCamera.Min(s => s.CameraY);
        int observedMission = validCamera.Count == 0
            ? 0 : validCamera.Max(s => s.Mission);
        int maximumWorldActors = samples.Count == 0
            ? 0 : samples.Max(s => s.WorldActorCount);

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
            "unresponsive_samples={12}\r\n" +
            "camera_range_x={13}\r\n" +
            "camera_range_y={14}\r\n" +
            "observed_mission={15}\r\n" +
            "world_actor_count_max={16}\r\n",
            name, durationSeconds, samples.Count, changedTimes.Count,
            percentile(0.50), percentile(0.95), percentile(0.99),
            intervals.Count == 0 ? 0 : intervals[intervals.Count - 1],
            intervals.Count(x => x > 80), intervals.Count(x => x > 120),
            elapsedMs <= 0 ? 0 : cpuMs / elapsedMs * 100.0,
            readBytes, unresponsive, cameraRangeX, cameraRangeY,
            observedMission, maximumWorldActors);
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
