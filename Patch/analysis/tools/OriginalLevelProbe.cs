using System;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

internal static class OriginalLevelProbe
{
    private const uint ProcessVmOperation = 0x0008;
    private const uint ProcessVmRead = 0x0010;
    private const uint ProcessVmWrite = 0x0020;
    private const uint ProcessQueryInformation = 0x0400;
    private const int CursorX = 0x000E6EA0;
    private const int CursorY = 0x000E6FAC;
    private const int LeftPressed = 0x000E6E64;
    private const int LeftDown = 0x000E6E74;
    private const int LeftReleased = 0x000E6FB0;
    private const int CurrentMission = 0x000E7060;
    private const int NewGameImmediate = 0x00003B66;
    private const int FinalMissionVwfName = 0x000CF4A8;
    private const int PunishmentMissionVwfName = 0x000CF4F8;
    private const int SmoothScrollEntry = 0x0004C9B0;
    private const int HearingImmediate = 0x0005DD27;
    private const int AlertImmediate = 0x00056E62;
    private const int BriefingAdvance = 0x000E6EA9;
    private const int ScreenWidth = 0x000E6E0C;
    private const int ScreenHeight = 0x000E6E10;
    private const int RendererWidth = 0x000D6A8C;
    private const int RendererHeight = 0x000D6A88;

    [StructLayout(LayoutKind.Sequential)]
    private struct Rect
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct NativePoint
    {
        public int X;
        public int Y;
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr OpenProcess(
        uint access, bool inheritHandle, int processId);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool ReadProcessMemory(
        IntPtr process, IntPtr address, byte[] data, int size, out IntPtr read);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool WriteProcessMemory(
        IntPtr process, IntPtr address, byte[] data, int size, out IntPtr written);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    private static extern uint GetPrivateProfileInt(
        string section, string key, int defaultValue, string fileName);

    [DllImport("kernel32.dll")]
    private static extern bool CloseHandle(IntPtr handle);

    [DllImport("user32.dll")]
    private static extern bool GetWindowRect(IntPtr window, out Rect rect);

    [DllImport("user32.dll")]
    private static extern bool PrintWindow(IntPtr window, IntPtr dc, uint flags);

    [DllImport("user32.dll")]
    private static extern bool SetWindowPos(
        IntPtr window, IntPtr insertAfter, int x, int y, int width, int height,
        uint flags);

    [DllImport("user32.dll")]
    private static extern bool SetForegroundWindow(IntPtr window);

    [DllImport("user32.dll")]
    private static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    private static extern void keybd_event(
        byte virtualKey, byte scanCode, uint flags, UIntPtr extraInfo);

    [DllImport("user32.dll")]
    private static extern bool SetCursorPos(int x, int y);

    [DllImport("user32.dll")]
    private static extern bool GetCursorPos(out NativePoint point);

    [DllImport("user32.dll")]
    private static extern void mouse_event(
        uint flags, uint dx, uint dy, uint data, UIntPtr extraInfo);

    public static int Main(string[] args)
    {
        if (args.Length < 3)
        {
            Console.Error.WriteLine(
                "Usage: OriginalLevelProbe.exe GAME_DIR OUTPUT_DIR LEVEL [SECONDS] [nodrive] [hotkeys|autostart|mouseinput]");
            return 2;
        }

        string gameDirectory = Path.GetFullPath(args[0]);
        string outputDirectory = Path.GetFullPath(args[1]);
        int level = int.Parse(args[2]);
        int seconds = args.Length >= 4 ? int.Parse(args[3]) : 35;
        bool drive = args.Length < 5 ||
            !string.Equals(args[4], "nodrive", StringComparison.OrdinalIgnoreCase);
        bool testHotkeys = args.Any(argument => string.Equals(
            argument, "hotkeys", StringComparison.OrdinalIgnoreCase));
        bool testAutomaticStart = args.Any(argument => string.Equals(
            argument, "autostart", StringComparison.OrdinalIgnoreCase));
        bool testMouseInput = args.Any(argument => string.Equals(
            argument, "mouseinput", StringComparison.OrdinalIgnoreCase));
        if (level < 1 || level > 14)
        {
            throw new ArgumentOutOfRangeException("level");
        }
        int expectedEngineLevel =
            level == 13 ? 12 :
            level == 14 ? 7 :
            level;

        Directory.CreateDirectory(outputDirectory);
        string executable = Path.Combine(gameDirectory, "M1937.exe");
        var startInfo = new ProcessStartInfo(executable)
        {
            WorkingDirectory = gameDirectory,
            UseShellExecute = false
        };
        startInfo.EnvironmentVariables["M1937_START_LEVEL"] = level.ToString();
        if (testHotkeys || testAutomaticStart)
            startInfo.EnvironmentVariables["M1937_AUTO_START"] = "1";
        else if (testMouseInput)
            startInfo.EnvironmentVariables["M1937_AUTO_START"] = "0";
        else
            startInfo.EnvironmentVariables["M1937_AUTOTEST"] = "1";

        using (Process game = Process.Start(startInfo))
        {
            if (game == null)
            {
                throw new InvalidOperationException("Could not launch M1937.exe");
            }

            IntPtr process = OpenProcess(
                ProcessQueryInformation | ProcessVmOperation |
                ProcessVmRead | ProcessVmWrite,
                false,
                game.Id);
            if (process == IntPtr.Zero)
            {
                throw new InvalidOperationException("OpenProcess failed");
            }

            var report = new StringBuilder();
            NativePoint originalCursor = new NativePoint();
            bool restoreCursor =
                testMouseInput && GetCursorPos(out originalCursor);
            try
            {
                long imageBase = game.MainModule.BaseAddress.ToInt64();
                report.AppendLine("requested_level=" + level);
                report.AppendLine("expected_engine_level=" + expectedEngineLevel);

                IntPtr window = WaitForWindow(game, TimeSpan.FromSeconds(12));
                if (window == IntPtr.Zero)
                {
                    throw new InvalidOperationException("Game window did not appear");
                }

                int immediate = ReadInt(process, imageBase + NewGameImmediate);
                report.AppendLine("new_game_immediate=" + immediate);
                if (immediate != expectedEngineLevel)
                {
                    throw new InvalidOperationException(
                        "The runtime level patch did not apply.");
                }
                int missionVwfNameAddress = level == 14
                    ? PunishmentMissionVwfName
                    : FinalMissionVwfName;
                string missionVwf = ReadAscii(
                    process, imageBase + missionVwfNameAddress, 12);
                report.AppendLine("mission_vwf=" + missionVwf);
                if (level == 13 &&
                    !string.Equals(
                        missionVwf,
                        "1937M012.VWF",
                        StringComparison.Ordinal))
                {
                    throw new InvalidOperationException(
                        "The extension-mission VWF redirect did not apply.");
                }
                if (level == 14 &&
                    !string.Equals(
                        missionVwf,
                        "1937M013.VWF",
                        StringComparison.Ordinal))
                {
                    throw new InvalidOperationException(
                        "The anti-traitor mission VWF redirect did not apply.");
                }
                int scrollOpcode =
                    ReadInt(process, imageBase + SmoothScrollEntry) & 0xFF;
                int hearing = ReadInt(process, imageBase + HearingImmediate);
                int alert = ReadInt(process, imageBase + AlertImmediate);
                report.AppendLine(
                    "legacy_scroll_entry_opcode=0x" +
                    scrollOpcode.ToString("X2"));
                report.AppendLine("enhanced_hearing_radius=" + hearing);
                report.AppendLine("enhanced_alert_radius=" + alert);
                report.AppendLine(
                    "logical_viewport=" +
                    ReadInt(process, imageBase + ScreenWidth) + "x" +
                    ReadInt(process, imageBase + ScreenHeight));
                report.AppendLine(
                    "renderer_viewport=" +
                    ReadInt(process, imageBase + RendererWidth) + "x" +
                    ReadInt(process, imageBase + RendererHeight));
                int expectedHearing;
                int expectedAlert;
                ExpectedAiRadii(
                    Path.Combine(gameDirectory, "rungame.ini"),
                    out expectedHearing, out expectedAlert);
                report.AppendLine(
                    "expected_hearing_radius=" + expectedHearing);
                report.AppendLine(
                    "expected_alert_radius=" + expectedAlert);
                if (hearing != expectedHearing || alert != expectedAlert)
                {
                    throw new InvalidOperationException(
                        "The configured enemy-AI radius patches did not apply.");
                }

                // Keep the original game in a small corner window without
                // activating it or moving the physical mouse.
                SetWindowPos(
                    window,
                    IntPtr.Zero,
                    20,
                    20,
                    0,
                    0,
                    0x0001 | 0x0010);

                var clock = Stopwatch.StartNew();
                // The proxy returns the original Start Game command through
                // the menu's own polling function. No physical or synthetic
                // click is needed, so validation cannot disturb gameplay.
                double nextClick = testHotkeys
                    ? 2.0
                    : double.MaxValue;
                double releaseAt = -1.0;
                double clearReleaseAt = -1.0;
                double nextBriefingAdvance = 3.0;
                int observedMission = ReadInt(
                    process, imageBase + CurrentMission);
                Bitmap latest = null;
                Bitmap baselineUi = null;
                Bitmap helpUi = null;
                Bitmap minimapUi = null;
                bool helpOpened = false;
                bool helpClosed = false;
                bool minimapOpened = false;
                bool minimapClosed = false;
                double nextPhysicalAdvance = 2.0;
                bool mouseInputSampled = false;
                int mouseLogicalStartX = 0;
                int mouseLogicalEndX = 0;
                int mouseLeftDown = 0;
                int mouseLeftPressed = 0;

                while (clock.Elapsed.TotalSeconds < seconds && !game.HasExited)
                {
                    game.Refresh();
                    if (game.MainWindowHandle != IntPtr.Zero &&
                        game.MainWindowHandle != window)
                    {
                        // DirectDraw can recreate the top-level window while
                        // switching from the menu to the mission renderer.
                        window = game.MainWindowHandle;
                        SetWindowPos(
                            window,
                            IntPtr.Zero,
                            20,
                            20,
                            0,
                            0,
                            0x0001 | 0x0010);
                    }
                    double now = clock.Elapsed.TotalSeconds;
                    if (now >= nextClick)
                    {
                        // Expanded viewports keep the original UI artwork
                        // coordinates; this is the centre of "开始游戏".
                        WriteInt(process, imageBase + CursorX, 72);
                        WriteInt(process, imageBase + CursorY, 236);
                        WriteInt(process, imageBase + LeftPressed, 1);
                        WriteInt(process, imageBase + LeftDown, 1);
                        releaseAt = now + 0.10;
                        nextClick += 2.0;
                    }
                    if (releaseAt >= 0.0 && now >= releaseAt)
                    {
                        WriteInt(process, imageBase + LeftPressed, 0);
                        WriteInt(process, imageBase + LeftDown, 0);
                        WriteInt(process, imageBase + LeftReleased, 1);
                        clearReleaseAt = now + 0.10;
                        releaseAt = -1.0;
                        if (testHotkeys && nextClick > 55.0)
                            nextClick = double.MaxValue;
                    }
                    if (clearReleaseAt >= 0.0 && now >= clearReleaseAt)
                    {
                        WriteInt(process, imageBase + LeftReleased, 0);
                        clearReleaseAt = -1.0;
                    }

                    int current = ReadInt(process, imageBase + CurrentMission);
                    if (current >= 1 && current <= 12)
                    {
                        observedMission = current;
                        if (now >= nextBriefingAdvance &&
                            (!testHotkeys || now <= 55.0))
                        {
                            WriteByte(
                                process, imageBase + BriefingAdvance, 1);
                            nextBriefingAdvance += 2.0;
                        }
                    }

                    if (testHotkeys && current >= 1 && current <= 12)
                    {
                        if (now >= nextPhysicalAdvance && now <= 55.0)
                        {
                            Rect advanceRect;
                            if (GetWindowRect(window, out advanceRect))
                            {
                                SetForegroundWindow(window);
                                SetCursorPos(
                                    (advanceRect.Left + advanceRect.Right) / 2,
                                    (advanceRect.Top + advanceRect.Bottom) / 2);
                                mouse_event(
                                    0x0002, 0, 0, 0, UIntPtr.Zero);
                                Thread.Sleep(60);
                                mouse_event(
                                    0x0004, 0, 0, 0, UIntPtr.Zero);
                                PressKey(0x0D);
                            }
                            nextPhysicalAdvance += 2.0;
                        }
                        if (now >= 60.0 && baselineUi == null)
                        {
                            SetWindowPos(
                                window, new IntPtr(-1), 20, 20, 0, 0,
                                0x0001 | 0x0040);
                            SetForegroundWindow(window);
                            Thread.Sleep(150);
                            baselineUi = CaptureVisibleWindow(window);
                        }
                        if (now >= 63.0 && !helpOpened)
                        {
                            PressKey(0x70); // F1
                            helpOpened = true;
                        }
                        if (now >= 65.0 && helpUi == null)
                        {
                            helpUi = CaptureVisibleWindow(window);
                        }
                        if (now >= 66.0 && !helpClosed)
                        {
                            PressKey(0x70);
                            helpClosed = true;
                        }
                        if (now >= 68.0 && !minimapOpened)
                        {
                            PressKey(0x4D); // M
                            minimapOpened = true;
                        }
                        if (now >= 70.0 && minimapUi == null)
                        {
                            minimapUi = CaptureVisibleWindow(window);
                        }
                        if (now >= 71.0 && !minimapClosed)
                        {
                            PressKey(0x4D);
                            minimapClosed = true;
                        }
                    }
                    if (testMouseInput && !mouseInputSampled && now >= 5.0)
                    {
                        Rect mouseRect;
                        if (!GetWindowRect(window, out mouseRect))
                        {
                            throw new InvalidOperationException(
                                "Could not read the game window for mouse input.");
                        }
                        int mouseY = (mouseRect.Top + mouseRect.Bottom) / 2;
                        int mouseLeft = mouseRect.Left +
                            (mouseRect.Right - mouseRect.Left) / 4;
                        int mouseRight = mouseRect.Left +
                            (mouseRect.Right - mouseRect.Left) * 3 / 4;
                        SetForegroundWindow(window);
                        Thread.Sleep(250);
                        report.AppendLine(
                            "mouse_window_foreground=" +
                            (GetForegroundWindow() == window));
                        SetCursorPos(mouseLeft, mouseY);
                        Thread.Sleep(300);
                        mouseLogicalStartX =
                            ReadInt(process, imageBase + CursorX);
                        SetCursorPos(mouseRight, mouseY);
                        Thread.Sleep(400);
                        mouseLogicalEndX =
                            ReadInt(process, imageBase + CursorX);
                        mouse_event(0x0002, 0, 0, 0, UIntPtr.Zero);
                        Thread.Sleep(120);
                        mouseLeftDown =
                            ReadInt(process, imageBase + LeftDown);
                        mouseLeftPressed =
                            ReadInt(process, imageBase + LeftPressed);
                        mouse_event(0x0004, 0, 0, 0, UIntPtr.Zero);
                        report.AppendLine(
                            "mouse_logical_x=" + mouseLogicalStartX + "->" +
                            mouseLogicalEndX);
                        report.AppendLine(
                            "mouse_logical_delta=" +
                            (mouseLogicalEndX - mouseLogicalStartX));
                        report.AppendLine(
                            "mouse_left_state=" + mouseLeftPressed + "/" +
                            mouseLeftDown);
                        mouseInputSampled = true;
                    }

                    if (((int)(now * 10.0)) % 10 == 0)
                    {
                        Bitmap captured = CaptureVisibleWindow(window);
                        if (captured != null)
                        {
                            if (latest != null)
                            {
                                latest.Dispose();
                            }
                            latest = captured;
                        }
                    }
                    Thread.Sleep(20);
                }

                report.AppendLine("observed_mission=" + observedMission);
                if (!game.HasExited)
                {
                    report.AppendLine(
                        "final_logical_viewport=" +
                        ReadInt(process, imageBase + ScreenWidth) + "x" +
                        ReadInt(process, imageBase + ScreenHeight));
                    report.AppendLine(
                        "final_renderer_viewport=" +
                        ReadInt(process, imageBase + RendererWidth) + "x" +
                        ReadInt(process, imageBase + RendererHeight));
                }
                report.AppendLine("process_exited=" + game.HasExited);
                report.AppendLine(
                    "responding=" + (!game.HasExited && game.Responding));

                if (latest != null)
                {
                    string imagePath = Path.Combine(
                        outputDirectory,
                        "original-level-" + level.ToString("00") + "-window.jpg");
                    SaveCompressedJpeg(latest, imagePath, 960, 62L);
                    latest.Dispose();
                    report.AppendLine("compressed_window_capture=" + imagePath);
                    string ocrPath = RunLocalOcr(imagePath);
                    report.AppendLine(
                        "local_ocr=" + (
                            string.IsNullOrEmpty(ocrPath) ? "unavailable" : ocrPath));
                }
                if (testHotkeys)
                {
                    SaveUiCapture(
                        baselineUi, outputDirectory, "ui-baseline.jpg", report);
                    SaveUiCapture(
                        helpUi, outputDirectory, "ui-f1-help.jpg", report);
                    SaveUiCapture(
                        minimapUi, outputDirectory, "ui-m-minimap.jpg", report);
                }
                else if (latest == null)
                {
                    report.AppendLine("compressed_window_capture=unavailable");
                    report.AppendLine("local_ocr=unavailable");
                }

                if (game.HasExited)
                {
                    throw new InvalidOperationException(
                        "The game process exited before the stability window elapsed.");
                }
                if (drive && observedMission != expectedEngineLevel)
                {
                    throw new InvalidOperationException(
                        "New Game did not retain the expected engine mission number.");
                }
                if (testMouseInput &&
                    (!mouseInputSampled ||
                     (Math.Abs(mouseLogicalEndX - mouseLogicalStartX) < 64 &&
                      mouseLeftDown == 0 && mouseLeftPressed == 0)))
                {
                    throw new InvalidOperationException(
                        "Physical mouse movement did not reach the game cursor.");
                }
            }
            finally
            {
                CloseHandle(process);
                if (!game.HasExited)
                {
                    game.Kill();
                    game.WaitForExit(3000);
                }
                if (restoreCursor)
                {
                    SetCursorPos(originalCursor.X, originalCursor.Y);
                }
                File.WriteAllText(
                    Path.Combine(outputDirectory, "original-level-probe.txt"),
                    report.ToString(),
                    new UTF8Encoding(false));
            }
        }

        Console.WriteLine("Original level selector probe passed.");
        return 0;
    }

    private static void PressKey(byte virtualKey)
    {
        keybd_event(virtualKey, 0, 0, UIntPtr.Zero);
        Thread.Sleep(80);
        keybd_event(virtualKey, 0, 0x0002, UIntPtr.Zero);
    }

    private static void ExpectedAiRadii(
        string iniPath, out int hearing, out int alert)
    {
        int enabled = ReadIniInt(iniPath, "Enabled", 1);
        if (enabled == 0)
        {
            hearing = 128;
            alert = 640;
            return;
        }

        int difficulty = Clamp(
            ReadIniInt(iniPath, "Difficulty", 1), 0, 3);
        int aiLevel = Clamp(
            ReadIniInt(iniPath, "AILevel", 2), 0, 3);
        int configuredHearing = Clamp(
            ReadIniInt(iniPath, "HearingRadius", 0), 0, 2048);
        int configuredAlert = Clamp(
            ReadIniInt(iniPath, "AlertRadius", 0), 0, 4096);
        int[] hearingBase = { 128, 160, 192, 224 };
        int[] hearingAdjustment = { -32, 0, 32, 64 };
        int[] alertBase = { 640, 720, 800, 960 };
        int[] alertAdjustment = { -160, 0, 160, 320 };
        hearing = configuredHearing > 0
            ? configuredHearing
            : Clamp(
                hearingBase[aiLevel] + hearingAdjustment[difficulty],
                64, 2048);
        alert = configuredAlert > 0
            ? configuredAlert
            : Clamp(
                alertBase[aiLevel] + alertAdjustment[difficulty],
                320, 4096);
    }

    private static int ReadIniInt(
        string iniPath, string key, int defaultValue)
    {
        return unchecked((int)GetPrivateProfileInt(
            "mod", key, defaultValue, iniPath));
    }

    private static int Clamp(int value, int minimum, int maximum)
    {
        return Math.Max(minimum, Math.Min(maximum, value));
    }

    private static void SaveUiCapture(
        Bitmap bitmap, string outputDirectory, string fileName,
        StringBuilder report)
    {
        if (bitmap == null)
        {
            report.AppendLine(fileName + "=unavailable");
            return;
        }
        string path = Path.Combine(outputDirectory, fileName);
        SaveCompressedJpeg(bitmap, path, 1280, 72L);
        bitmap.Dispose();
        report.AppendLine(fileName + "=" + path);
    }

    private static IntPtr WaitForWindow(Process game, TimeSpan timeout)
    {
        Stopwatch clock = Stopwatch.StartNew();
        while (clock.Elapsed < timeout && !game.HasExited)
        {
            game.Refresh();
            if (game.MainWindowHandle != IntPtr.Zero)
            {
                return game.MainWindowHandle;
            }
            Thread.Sleep(50);
        }
        return IntPtr.Zero;
    }

    private static int ReadInt(IntPtr process, long address)
    {
        byte[] bytes = new byte[4];
        IntPtr read;
        if (!ReadProcessMemory(
            process, new IntPtr(address), bytes, bytes.Length, out read) ||
            read.ToInt64() != bytes.Length)
        {
            throw new InvalidOperationException("ReadProcessMemory failed");
        }
        return BitConverter.ToInt32(bytes, 0);
    }

    private static string ReadAscii(
        IntPtr process, long address, int length)
    {
        byte[] bytes = new byte[length];
        IntPtr read;
        if (!ReadProcessMemory(
            process, new IntPtr(address), bytes, bytes.Length, out read) ||
            read.ToInt64() != bytes.Length)
        {
            throw new InvalidOperationException("ReadProcessMemory failed");
        }
        return Encoding.ASCII.GetString(bytes);
    }

    private static void WriteInt(IntPtr process, long address, int value)
    {
        byte[] bytes = BitConverter.GetBytes(value);
        IntPtr written;
        if (!WriteProcessMemory(
            process, new IntPtr(address), bytes, bytes.Length, out written) ||
            written.ToInt64() != bytes.Length)
        {
            throw new InvalidOperationException("WriteProcessMemory failed");
        }
    }

    private static void WriteByte(IntPtr process, long address, byte value)
    {
        byte[] bytes = { value };
        IntPtr written;
        if (!WriteProcessMemory(
            process, new IntPtr(address), bytes, bytes.Length, out written) ||
            written.ToInt64() != bytes.Length)
        {
            throw new InvalidOperationException("WriteProcessMemory byte failed");
        }
    }

    private static Bitmap CaptureVisibleWindow(IntPtr window)
    {
        Rect rect;
        if (!GetWindowRect(window, out rect))
        {
            return null;
        }
        int width = rect.Right - rect.Left;
        int height = rect.Bottom - rect.Top;
        if (width <= 0 || height <= 0)
        {
            return null;
        }

        var bitmap = new Bitmap(width, height, PixelFormat.Format24bppRgb);
        using (Graphics graphics = Graphics.FromImage(bitmap))
        {
            IntPtr dc = graphics.GetHdc();
            bool rendered;
            try
            {
                rendered = PrintWindow(window, dc, 2);
            }
            finally
            {
                graphics.ReleaseHdc(dc);
            }
            if (!rendered)
            {
                bitmap.Dispose();
                return null;
            }
        }
        if (LooksBlank(bitmap))
        {
            bitmap.Dispose();
            bitmap = CaptureWindowFromScreen(window, rect, width, height);
        }
        return bitmap;
    }

    private static bool LooksBlank(Bitmap bitmap)
    {
        int minimum = 255;
        int maximum = 0;
        int startX = bitmap.Width / 10;
        int endX = Math.Max(startX + 1, bitmap.Width * 9 / 10);
        int startY = Math.Max(32, bitmap.Height / 10);
        int endY = Math.Max(startY + 1, bitmap.Height * 9 / 10);
        int stepX = Math.Max(1, (endX - startX) / 24);
        int stepY = Math.Max(1, (endY - startY) / 18);
        for (int y = startY; y < endY; y += stepY)
        {
            for (int x = startX; x < endX; x += stepX)
            {
                Color pixel = bitmap.GetPixel(x, y);
                minimum = Math.Min(
                    minimum, Math.Min(pixel.R, Math.Min(pixel.G, pixel.B)));
                maximum = Math.Max(
                    maximum, Math.Max(pixel.R, Math.Max(pixel.G, pixel.B)));
            }
        }
        return maximum - minimum < 16 || minimum > 242;
    }

    private static Bitmap CaptureWindowFromScreen(
        IntPtr window, Rect rect, int width, int height)
    {
        const uint noMoveNoSizeNoActivate = 0x0001 | 0x0002 | 0x0010;
        SetWindowPos(
            window, new IntPtr(-1), 0, 0, 0, 0,
            noMoveNoSizeNoActivate);
        Thread.Sleep(40);
        var bitmap = new Bitmap(width, height, PixelFormat.Format24bppRgb);
        using (Graphics graphics = Graphics.FromImage(bitmap))
        {
            graphics.CopyFromScreen(
                rect.Left, rect.Top, 0, 0,
                new Size(width, height), CopyPixelOperation.SourceCopy);
        }
        SetWindowPos(
            window, new IntPtr(-2), 0, 0, 0, 0,
            noMoveNoSizeNoActivate);
        return bitmap;
    }

    private static void SaveCompressedJpeg(
        Bitmap source, string path, int maximumWidth, long quality)
    {
        int outputWidth = Math.Min(source.Width, maximumWidth);
        int outputHeight = Math.Max(
            1,
            (int)Math.Round(
                source.Height * (outputWidth / (double)source.Width)));
        using (var resized = new Bitmap(
            outputWidth, outputHeight, PixelFormat.Format24bppRgb))
        using (Graphics graphics = Graphics.FromImage(resized))
        {
            graphics.DrawImage(
                source,
                new Rectangle(0, 0, outputWidth, outputHeight),
                0,
                0,
                source.Width,
                source.Height,
                GraphicsUnit.Pixel);
            ImageCodecInfo encoder = Array.Find(
                ImageCodecInfo.GetImageEncoders(),
                codec => codec.FormatID == ImageFormat.Jpeg.Guid);
            if (encoder == null)
            {
                resized.Save(path, ImageFormat.Jpeg);
                return;
            }
            using (var parameters = new EncoderParameters(1))
            {
                parameters.Param[0] = new EncoderParameter(
                    System.Drawing.Imaging.Encoder.Quality,
                    Math.Max(1L, Math.Min(quality, 100L)));
                resized.Save(path, encoder, parameters);
            }
        }
    }

    private static string RunLocalOcr(string imagePath)
    {
        string scriptPath = Path.Combine(
            AppDomain.CurrentDomain.BaseDirectory,
            "Invoke-LocalScreenshotOcr.ps1");
        if (!File.Exists(scriptPath))
        {
            return "";
        }

        string outputPath = Path.ChangeExtension(imagePath, ".ocr.txt");
        var startInfo = new ProcessStartInfo("powershell.exe")
        {
            UseShellExecute = false,
            CreateNoWindow = true
        };
        startInfo.Arguments =
            "-NoProfile -ExecutionPolicy Bypass -File \"" +
            scriptPath.Replace("\"", "\"\"") +
            "\" -ImagePath \"" +
            imagePath.Replace("\"", "\"\"") +
            "\" -OutputPath \"" +
            outputPath.Replace("\"", "\"\"") +
            "\"";
        using (Process ocr = Process.Start(startInfo))
        {
            if (ocr == null || !ocr.WaitForExit(15000) || ocr.ExitCode != 0)
            {
                return "";
            }
        }
        return File.Exists(outputPath) ? outputPath : "";
    }
}
