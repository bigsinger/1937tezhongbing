using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Imaging;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using System.Web.Script.Serialization;
using EngineAddresses = Mission1937.SDK.Generated.M1937Addresses;
using MissionRoutes = Mission1937.SDK.Generated.M1937MissionRoutes;

internal static class ModRegressionProbe
{
    private const uint ProcessVmRead = 0x0010;
    private const uint ProcessQueryInformation = 0x0400;
    private const uint PclientOnly = 0x00000001;
    private const uint SwpNoSize = 0x0001;
    private const uint SwpNoMove = 0x0002;
    private const uint SwpNoZOrder = 0x0004;
    private const uint SwpNoActivate = 0x0010;
    private static readonly IntPtr HwndTopmost = new IntPtr(-1);
    private static readonly IntPtr HwndNotTopmost = new IntPtr(-2);
    private const uint ReplayMessage = 0x8000 + 0x137;
    private const int ReplayKeyDown = 1;
    private const int ReplayKeyUp = 2;
    private const int ReplayMouseDelta = 3;
    private const int ReplayMouseButtonDown = 4;
    private const int ReplayMouseButtonUp = 5;
    private const int ReplayMenuCommand = 6;
    private const int ReplayAiAlert = 8;
    private const int ReplayCameraCenter = 9;
    private const uint WmActivate = 0x0006;
    private const uint WmSetFocus = 0x0007;
    private const uint WmActivateApp = 0x001C;
    private const int DikF1 = 0x3B;
    private const int DikF4 = 0x3E;
    private const int DikM = 0x32;
    private const int DikUp = 0xC8;
    private const int DikLeft = 0xCB;
    private const int DikRight = 0xCD;
    private const int DikDown = 0xD0;
    private const int SmXVirtualScreen = 76;
    private const int SmYVirtualScreen = 77;
    private const int SmCxVirtualScreen = 78;
    private const int SmCyVirtualScreen = 79;
    private const int ActorRuntimeTypeOffset = 0x064;
    private const int ActorFactionOffset = 0x074;
    private const int ActorWorldXOffset = 0x0D8;
    private const int ActorWorldYOffset = 0x0E0;
    private const int ActorFacingDirectionOffset = 0x178;
    private const int ActorDeadOffset = 0x188;
    private const int ActorTargetStatusOffset = 0x190;
    private const int ActorGoalKindOffset = 0x194;
    private const int ActorGoalXOffset = 0x198;
    private const int ActorGoalYOffset = 0x19C;
    private const int ActorInterestAddressOffset = 0x1A0;
    private const int ActorCommandVariantOffset = 0x1A4;
    private const int ActorCommandPendingOffset = 0x1A8;
    private const int ActorSelectedForCommandOffset = 0x1AC;
    private const int ActorCurrentHitPointsOffset = 0x1C0;
    private const int ActorSearchOrReturnActiveOffset = 0x1D4;
    private const int ActorMovementActiveOffset = 0x1D8;
    private const int ActorMovementPathStateOffset = 0x1FC;
    private const int ActorMovementModeOffset = 0x208;
    private const int ActorDefaultAttackTypeOffset = 0x20C;
    private const int ActorTargetAddressOffset = 0x214;
    private const int ActorResolvedGoalXOffset = 0x218;
    private const int ActorResolvedGoalYOffset = 0x220;
    private const int ActorInventoryAddressOffset = 0x22C;
    private const int ActorSearchDelayLimitOffset = 0x248;
    private const int ActorSearchDelayCounterOffset = 0x24C;
    private const int ActorContactStateOffset = 0x250;
    private const int ActorTargetLostOffset = 0x254;
    private const int ActorReactionStateOffset = 0x25C;
    private const int ActorPathOverrideActiveOffset = 0x290;

    [StructLayout(LayoutKind.Sequential)]
    private struct Rect
    {
        public int Left, Top, Right, Bottom;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct Point
    {
        public int X, Y;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct IoCounters
    {
        public ulong ReadOperationCount;
        public ulong WriteOperationCount;
        public ulong OtherOperationCount;
        public ulong ReadTransferCount;
        public ulong WriteTransferCount;
        public ulong OtherTransferCount;
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr OpenProcess(
        uint access, bool inherit, int processId);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool ReadProcessMemory(
        IntPtr process, IntPtr address, byte[] data, int size,
        out IntPtr read);

    [DllImport("kernel32.dll")]
    private static extern bool CloseHandle(IntPtr handle);

    [DllImport("kernel32.dll")]
    private static extern bool GetProcessIoCounters(
        IntPtr process, out IoCounters counters);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool PostMessage(
        IntPtr window, uint message, IntPtr wparam, IntPtr lparam);

    [DllImport("user32.dll")]
    private static extern bool GetClientRect(IntPtr window, out Rect rect);

    [DllImport("user32.dll")]
    private static extern bool PrintWindow(
        IntPtr window, IntPtr dc, uint flags);

    [DllImport("user32.dll")]
    private static extern bool ClientToScreen(
        IntPtr window, ref Point point);

    [DllImport("user32.dll")]
    private static extern bool SetWindowPos(
        IntPtr window, IntPtr insertAfter, int x, int y,
        int width, int height, uint flags);
    [DllImport("user32.dll")]
    private static extern bool GetClipCursor(out Rect rect);
    [DllImport("user32.dll")]
    private static extern int GetSystemMetrics(int index);

    [DllImport("dwmapi.dll")]
    private static extern int DwmFlush();

    private sealed class Stage
    {
        public string Name;
        public bool Sent;
        public bool ProcessResponding;
        public int Mission;
        public long ElapsedMilliseconds;
        public string Evidence;
    }

    private sealed class PerfSample
    {
        public double TimeMilliseconds;
        public double CpuMilliseconds;
        public ulong ReadBytes;
        public bool Responding;
        public double CompositorWaitMilliseconds;
        public bool CursorClipRestricted;
    }

    private sealed class CaptureResult : IDisposable
    {
        public Bitmap Bitmap;
        public string Sha256;
        public bool NonBlank;
        public int LargestDarkComponentPixels;
        public double DarkPixelRatio;

        public void Dispose()
        {
            if (Bitmap != null)
            {
                Bitmap.Dispose();
                Bitmap = null;
            }
        }
    }

    private sealed class RenderAuditObservation
    {
        public bool HasVisualCapture;
        public bool CompleteRender;
        public string CaptureName = "";
        public int LargestDarkComponentPixels = -1;
        public double DarkPixelRatio = 1.0;
        public int MapPixels;
    }

    private sealed class ActorSnapshot
    {
        public int SceneIndex;
        public long Address;
        public int RuntimeType;
        public int Faction;
        public int WorldX;
        public int WorldY;
        public int Direction;
        public int Dead;
        public int TargetStatus;
        public int GoalKind;
        public int GoalX;
        public int GoalY;
        public long InterestAddress;
        public int CommandVariant;
        public int CommandPending;
        public int SelectedForCommand;
        public int CurrentHitPoints;
        public int SearchOrReturnActive;
        public int MovementActive;
        public int MovementPathState;
        public int MovementMode;
        public int DefaultAttackType;
        public long TargetAddress;
        public int ResolvedGoalX;
        public int ResolvedGoalY;
        public int SearchDelayLimit;
        public int SearchDelayCounter;
        public int ContactState;
        public int TargetLost;
        public int ReactionState;
        public int PathOverrideActive;
    }

    private sealed class ParityCheckpoint
    {
        public string Id;
        public long ElapsedMilliseconds;
        public int CameraX;
        public int CameraY;
        public int ViewportWidth;
        public int ViewportHeight;
        public int SourceEntityCount;
        public readonly List<ActorSnapshot> Actors =
            new List<ActorSnapshot>();
        public readonly List<Point> ObservedPositions =
            new List<Point>();
    }

    private sealed class MovementSegmentObservation
    {
        public ActorSnapshot Last;
        public int Samples;
        public int MovingSamples;
        public int AlignedSamples;
        public int OppositeSamples;
        public int PerpendicularSamples;
        public int MaximumDisplacement;
        public int StartTargetDistance;
        public int EndTargetDistance;
        public int MinimumTargetDistance;
        public readonly HashSet<int> Directions = new HashSet<int>();
        public readonly List<Point> Positions = new List<Point>();
    }

    private sealed class RuntimeActorIdentity
    {
        public int RuntimeIndex;
        public int SceneIndex;
        public int DatabaseEntryId;
        public int VwfFactionId;
        public string DisplayName;
        public int AuthoredHitPoints;
        public int AuthoredAttackType;
    }

    public static int Main(string[] args)
    {
        if (args.Length < 3)
        {
            Console.Error.WriteLine(
                "Usage: ModRegressionProbe.exe GAME_DIR OUTPUT_DIR LEVEL " +
                "[SECONDS] [MOVEMENT_CELL_X MOVEMENT_CELL_Y " +
                "[RETURN_CELL_X RETURN_CELL_Y]] " +
                "[--briefing-only] [--movement-only] " +
                "[--inventory-only] " +
                "[--identity-catalog=PATH --parity-patrol-only | " +
                "--parity-contact-only --parity-scenario=ID " +
                "--patrol-observation-ms=MS " +
                "--contact-observation-ms=MS] [--actor-layout-dump]");
            return 2;
        }

        string gameDirectory = Path.GetFullPath(args[0]);
        string outputDirectory = Path.GetFullPath(args[1]);
        int selectorLevel = int.Parse(args[2], CultureInfo.InvariantCulture);
        double maximumSeconds = args.Length >= 4
            ? double.Parse(args[3], CultureInfo.InvariantCulture)
            : 60.0;
        bool briefingOnly = args.Any(delegate(string argument)
        {
            return argument.Equals(
                "--briefing-only",
                StringComparison.OrdinalIgnoreCase);
        });
        bool movementOnly = args.Any(delegate(string argument)
        {
            return argument.Equals(
                "--movement-only",
                StringComparison.OrdinalIgnoreCase);
        });
        bool inventoryOnly = args.Any(delegate(string argument)
        {
            return argument.Equals(
                "--inventory-only",
                StringComparison.OrdinalIgnoreCase);
        });
        int movementCellX;
        int movementCellY;
        DefaultMovementTarget(
            selectorLevel, out movementCellX, out movementCellY);
        int parsedCellX;
        int parsedCellY;
        if (args.Length >= 6 &&
            int.TryParse(
                args[4],
                NumberStyles.Integer,
                CultureInfo.InvariantCulture,
                out parsedCellX) &&
            int.TryParse(
                args[5],
                NumberStyles.Integer,
                CultureInfo.InvariantCulture,
                out parsedCellY))
        {
            movementCellX = parsedCellX;
            movementCellY = parsedCellY;
        }
        int returnCellX;
        int returnCellY;
        DefaultMovementReturnTarget(
            selectorLevel, out returnCellX, out returnCellY);
        int parsedReturnCellX;
        int parsedReturnCellY;
        if (args.Length >= 8 &&
            int.TryParse(
                args[6],
                NumberStyles.Integer,
                CultureInfo.InvariantCulture,
                out parsedReturnCellX) &&
            int.TryParse(
                args[7],
                NumberStyles.Integer,
                CultureInfo.InvariantCulture,
                out parsedReturnCellY))
        {
            returnCellX = parsedReturnCellX;
            returnCellY = parsedReturnCellY;
        }
        string identityCatalogPath = ArgumentValue(
            args, "--identity-catalog=");
        string parityScenarioOverride = ArgumentValue(
            args, "--parity-scenario=");
        bool parityPatrolOnly = args.Any(delegate(string argument)
        {
            return argument.Equals(
                "--parity-patrol-only",
                StringComparison.OrdinalIgnoreCase);
        });
        bool parityContactOnly = args.Any(delegate(string argument)
        {
            return argument.Equals(
                "--parity-contact-only",
                StringComparison.OrdinalIgnoreCase);
        });
        bool actorLayoutDump = args.Any(delegate(string argument)
        {
            return argument.Equals(
                "--actor-layout-dump",
                StringComparison.OrdinalIgnoreCase);
        });
        if (parityPatrolOnly && parityContactOnly)
        {
            throw new InvalidOperationException(
                "Patrol-only and contact-only parity scenarios are " +
                "mutually exclusive.");
        }
        if (inventoryOnly &&
            (briefingOnly || parityPatrolOnly || parityContactOnly))
        {
            throw new InvalidOperationException(
                "Inventory-only cannot be combined with briefing-only " +
                "or parity movement scenarios.");
        }
        int patrolObservationMilliseconds = 1000;
        string patrolObservationValue = ArgumentValue(
            args, "--patrol-observation-ms=");
        int parsedPatrolObservationMilliseconds;
        if (!String.IsNullOrWhiteSpace(patrolObservationValue) &&
            int.TryParse(
                patrolObservationValue,
                NumberStyles.Integer,
                CultureInfo.InvariantCulture,
                out parsedPatrolObservationMilliseconds))
        {
            patrolObservationMilliseconds = Math.Max(
                100,
                Math.Min(10000, parsedPatrolObservationMilliseconds));
        }
        int contactObservationMilliseconds = 1800;
        string contactObservationValue = ArgumentValue(
            args, "--contact-observation-ms=");
        int parsedContactObservationMilliseconds;
        if (!String.IsNullOrWhiteSpace(contactObservationValue) &&
            int.TryParse(
                contactObservationValue,
                NumberStyles.Integer,
                CultureInfo.InvariantCulture,
                out parsedContactObservationMilliseconds))
        {
            contactObservationMilliseconds = Math.Max(
                500,
                Math.Min(10000, parsedContactObservationMilliseconds));
        }
        Dictionary<int, RuntimeActorIdentity> actorIdentities =
            String.IsNullOrWhiteSpace(identityCatalogPath)
                ? new Dictionary<int, RuntimeActorIdentity>()
                : ReadIdentityCatalog(identityCatalogPath);
        if ((parityPatrolOnly || parityContactOnly) &&
            actorIdentities.Count == 0)
        {
            throw new InvalidOperationException(
                "Actor parity scenarios require a non-empty " +
                "--identity-catalog.");
        }
        var route = MissionRoutes.Find(selectorLevel);
        if (route == null)
            throw new InvalidOperationException("Unknown selector level.");
        var parityCheckpoints = new List<ParityCheckpoint>();
        bool extensionGameplaySmoke = selectorLevel >= 13;
        bool renderAuditEnabled = String.Equals(
            Environment.GetEnvironmentVariable("M1937_RENDER_AUDIT"),
            "1",
            StringComparison.Ordinal);
        var renderAudit = new RenderAuditObservation();

        Directory.CreateDirectory(outputDirectory);
        string executable = Path.Combine(gameDirectory, "M1937.exe");
        if (!File.Exists(executable))
            throw new FileNotFoundException("M1937.exe is missing.", executable);

        var startInfo = new ProcessStartInfo(executable);
        startInfo.WorkingDirectory = gameDirectory;
        startInfo.UseShellExecute = false;
        startInfo.EnvironmentVariables["M1937_AUTOTEST"] = "1";
        startInfo.EnvironmentVariables["M1937_WINDOW_REPLAY"] = "1";
        startInfo.EnvironmentVariables["M1937_TELEMETRY"] = "1";
        startInfo.EnvironmentVariables["M1937_START_LEVEL"] =
            selectorLevel.ToString(CultureInfo.InvariantCulture);
        if (briefingOnly)
            startInfo.EnvironmentVariables[
                "M1937_AUTOTEST_BRIEFING_HOLD"] = "1";

        var stages = new List<Stage>();
        var perf = new List<PerfSample>();
        var clock = Stopwatch.StartNew();
        bool samplerStop = false;
        int exitCode = 1;

        using (Process game = Process.Start(startInfo))
        {
            if (game == null)
                throw new InvalidOperationException("Game process did not start.");
            IntPtr window = WaitForWindow(game, TimeSpan.FromSeconds(15));
            if (window == IntPtr.Zero)
                throw new InvalidOperationException("Game window did not appear.");
            SetWindowPos(
                window, IntPtr.Zero, 36, 36, 0, 0,
                SwpNoSize | SwpNoZOrder | SwpNoActivate);

            IntPtr process = OpenProcess(
                ProcessVmRead | ProcessQueryInformation, false, game.Id);
            if (process == IntPtr.Zero)
                throw new InvalidOperationException("OpenProcess failed.");

            try
            {
                game.Refresh();
                long imageBase = game.MainModule.BaseAddress.ToInt64();
                var sampler = new Thread(delegate()
                {
                    SamplePerformance(
                        game, process, clock, perf,
                        delegate() { return samplerStop; });
                });
                sampler.IsBackground = true;
                sampler.Start();

                bool briefingEntered = WaitUntil(
                    delegate()
                    {
                        return ReadInt(
                            process,
                            imageBase + EngineAddresses.CurrentMission) ==
                            route.EngineMission;
                    },
                    TimeSpan.FromSeconds(12));
                Thread.Sleep(550);
                string briefingCaptureHash = "";
                using (CaptureResult briefing = CaptureWindow(window))
                {
                    briefingCaptureHash =
                        briefing == null ? "" : briefing.Sha256;
                    SaveCapture(
                        briefing,
                        Path.Combine(
                            outputDirectory, "00-text-briefing.jpg"));
                    int briefingActors = ReadWorldActorCount(
                        process, imageBase);
                    AddStage(
                        stages, game, process, imageBase, clock,
                        "briefing_route_and_original_flow",
                        briefingEntered &&
                        (briefingOnly
                            ? briefingActors == 0 &&
                              briefing != null &&
                              briefing.NonBlank
                            : briefingActors > 0 ||
                              (briefing != null &&
                               briefing.NonBlank)),
                        "same_main_window=true; external_dialog=false; " +
                        "world_actors=" + briefingActors +
                        "; automated_skip=" + (briefingActors > 0) +
                        "; non_blank=" +
                        (briefing != null && briefing.NonBlank) +
                        "; hash=" +
                        (briefing == null ? "" : briefing.Sha256));
                }
                if (briefingOnly)
                {
                    samplerStop = true;
                    sampler.Join(1500);
                    bool briefingCursorClipSafe;
                    lock (perf)
                        briefingCursorClipSafe = perf.All(
                            delegate(PerfSample sample)
                            {
                                return !sample.CursorClipRestricted;
                            });
                    exitCode =
                        stages.All(delegate(Stage stage)
                        {
                            return stage.Sent &&
                                stage.ProcessResponding;
                        }) &&
                        briefingCursorClipSafe ? 0 : 1;
                    WriteArtifacts(
                        outputDirectory,
                        selectorLevel,
                        route.EngineMission,
                        stages,
                        perf,
                        transitionsLogged: false,
                        replayConsumed: false,
                        passed: exitCode == 0);
                    return exitCode;
                }
                // Reproduce the player's second click after choosing
                // "Start Game". The proxy consumes this through the tested
                // process' private DirectInput replay queue; no system cursor
                // or desktop input is touched.
                PostMessage(
                    window, WmActivateApp, new IntPtr(1), IntPtr.Zero);
                PostMessage(
                    window, WmActivate, new IntPtr(1), IntPtr.Zero);
                PostMessage(
                    window, WmSetFocus, IntPtr.Zero, IntPtr.Zero);
                bool briefingContinueSent = PulseMouseButton(window, 0);
                Thread.Sleep(1200);
                bool briefingVisualChanged = false;
                string missionMenuHash = "";
                using (CaptureResult missionMenu = CaptureWindow(window))
                {
                    missionMenuHash =
                        missionMenu == null ? "" : missionMenu.Sha256;
                    briefingVisualChanged =
                        missionMenu != null &&
                        !String.Equals(
                            briefingCaptureHash,
                            missionMenu.Sha256,
                            StringComparison.OrdinalIgnoreCase);
                    SaveCapture(
                        missionMenu,
                        Path.Combine(
                            outputDirectory, "01-mission-menu.jpg"));
                }
                AddStage(
                    stages, game, process, imageBase, clock,
                    "briefing_dismissed",
                    briefingContinueSent && briefingVisualChanged,
                    "process_local_mouse=true; visual_changed=" +
                    briefingVisualChanged + "; briefing_hash=" +
                    briefingCaptureHash + "; mission_menu_hash=" +
                    missionMenuHash);

                bool missionStarted = WaitUntil(
                    delegate()
                    {
                        return ReadInt(
                            process,
                            imageBase + EngineAddresses.CurrentMission) ==
                            route.EngineMission &&
                            ReadWorldActorCount(process, imageBase) > 0;
                    },
                    TimeSpan.FromSeconds(Math.Min(
                        45.0, Math.Max(12.0, maximumSeconds * 0.72))));
                int actorCount = ReadWorldActorCount(
                    process, imageBase);
                AddStage(
                    stages, game, process, imageBase, clock,
                    "mission_started", missionStarted,
                    missionStarted
                        ? "engine mission matched route; world_actors=" +
                          actorCount.ToString(CultureInfo.InvariantCulture)
                        : "world object table was not ready");

                // After the original briefing closes, the loaded mission
                // remains behind the full menu. Resume it through the third
                // "Return to Mission" entry. The first entry is New Game and
                // would deliberately reopen the briefing.
                int returnToMissionCursorX;
                int returnToMissionCursorY;
                bool gameplayResumeSent =
                    MoveReplayCursor(
                        process,
                        imageBase,
                        window,
                        272,
                        365,
                        out returnToMissionCursorX,
                        out returnToMissionCursorY) &&
                    PulseMouseButton(window, 0);
                Thread.Sleep(4200);
                bool gameplayVisualChanged = false;
                string gameplayHash = "";
                using (CaptureResult gameplay = CaptureWindow(window))
                {
                    gameplayHash =
                        gameplay == null ? "" : gameplay.Sha256;
                    gameplayVisualChanged =
                        gameplay != null &&
                        gameplay.NonBlank &&
                        !String.Equals(
                            missionMenuHash,
                            gameplay.Sha256,
                            StringComparison.OrdinalIgnoreCase);
                    SaveCapture(
                        gameplay,
                        Path.Combine(outputDirectory, "02-gameplay.jpg"));
                    if (renderAuditEnabled)
                        ObserveRenderAudit(
                            gameplay, "02-gameplay", renderAudit);
                }
                AddStage(
                    stages, game, process, imageBase, clock,
                    "gameplay_scene_resumed",
                    gameplayResumeSent,
                    "original Return to Mission click; cursor=(" +
                    returnToMissionCursorX + "," +
                    returnToMissionCursorY + "); " +
                    "visual_changed=" + gameplayVisualChanged +
                    "; mission_menu_hash=" + missionMenuHash +
                    "; gameplay_hash=" + gameplayHash);

                WaitUntil(
                    delegate()
                    {
                        ActorSnapshot candidate =
                            FindPlayerActor(process, imageBase);
                        if (candidate == null)
                            return false;
                        int currentCameraX = ReadInt(
                            process,
                            imageBase + EngineAddresses.CameraX);
                        int currentCameraY = ReadInt(
                            process,
                            imageBase + EngineAddresses.CameraY);
                        return candidate.WorldX - currentCameraX >= 0 &&
                            candidate.WorldX - currentCameraX < 1024 &&
                            candidate.WorldY - currentCameraY >= 0 &&
                            candidate.WorldY - currentCameraY < 688;
                    },
                    TimeSpan.FromSeconds(2));
                ActorSnapshot spawnStart =
                    FindPlayerActor(process, imageBase);
                int spawnCameraX = ReadInt(
                    process, imageBase + EngineAddresses.CameraX);
                int spawnCameraY = ReadInt(
                    process, imageBase + EngineAddresses.CameraY);
                int spawnScreenWidth = ReadInt(
                    process, imageBase + EngineAddresses.ScreenWidth);
                int spawnScreenHeight = ReadInt(
                    process, imageBase + EngineAddresses.ScreenHeight);
                int viewportController = ReadInt(
                    process,
                    imageBase + EngineAddresses.ViewportController);
                long viewportAddress = (long)(uint)viewportController;
                int gameplayViewportWidth = viewportController > 0
                    ? ReadInt(process, viewportAddress + 0x28)
                    : spawnScreenWidth;
                int gameplayViewportHeight = viewportController > 0
                    ? ReadInt(process, viewportAddress + 0x2C)
                    : spawnScreenHeight - 80;
                bool cameraStateSynchronized =
                    viewportController > 0 &&
                    ReadInt(process, viewportAddress + 0x30) ==
                        spawnCameraX &&
                    ReadInt(process, viewportAddress + 0x34) ==
                        spawnCameraY &&
                    ReadInt(process, viewportAddress + 0x44) ==
                        spawnCameraX &&
                    ReadInt(process, viewportAddress + 0x48) ==
                        spawnCameraY;
                bool cameraShowsPlayer =
                    spawnStart != null &&
                    cameraStateSynchronized &&
                    spawnStart.WorldX - spawnCameraX >= 0 &&
                    spawnStart.WorldX - spawnCameraX <
                        gameplayViewportWidth &&
                    spawnStart.WorldY - spawnCameraY >= 0 &&
                    spawnStart.WorldY - spawnCameraY <
                        gameplayViewportHeight;
                AddStage(
                    stages, game, process, imageBase, clock,
                    "initial_camera_contains_player",
                    cameraShowsPlayer,
                    spawnStart == null
                        ? "player actor was not readable"
                        : "camera=(" + spawnCameraX + "," +
                          spawnCameraY + "); player=(" +
                          spawnStart.WorldX + "," +
                          spawnStart.WorldY + "); viewport=(" +
                          gameplayViewportWidth + "," +
                          gameplayViewportHeight +
                          "); render=(" + spawnScreenWidth + "," +
                          spawnScreenHeight + "); synchronized=" +
                          cameraStateSynchronized);

                WriteActorStateSnapshot(
                    process,
                    imageBase,
                    Path.Combine(
                        outputDirectory, "actor-states-entry.csv"));
                if (actorLayoutDump)
                {
                    WriteActorLayoutSnapshot(
                        process,
                        imageBase,
                        actorIdentities,
                        Path.Combine(
                            outputDirectory,
                            "actor-layout-entry.csv"));
                    WriteActorInventorySnapshot(
                        process,
                        imageBase,
                        actorIdentities,
                        Path.Combine(
                            outputDirectory,
                            "actor-inventory-entry.csv"));
                }
                Thread.Sleep(5000);
                WriteActorStateSnapshot(
                    process,
                    imageBase,
                    Path.Combine(
                        outputDirectory, "actor-states-steady.csv"));
                if (renderAuditEnabled)
                {
                    Thread.Sleep(250);
                    using (CaptureResult settled = CaptureWindow(window))
                    {
                        SaveCapture(
                            settled,
                            Path.Combine(
                                outputDirectory,
                                "03-settled-gameplay.jpg"));
                        ObserveRenderAudit(
                            settled,
                            "03-settled-gameplay",
                            renderAudit);
                    }
                }
                ActorSnapshot spawnEnd =
                    FindPlayerActor(process, imageBase);
                if (actorLayoutDump)
                {
                    WriteActorInventorySnapshot(
                        process,
                        imageBase,
                        actorIdentities,
                        Path.Combine(
                            outputDirectory,
                            "actor-inventory-steady.csv"));
                }
                bool spawnSafe =
                    spawnStart != null && spawnEnd != null &&
                    spawnStart.Dead == 0 && spawnEnd.Dead == 0;
                AddStage(
                    stages, game, process, imageBase, clock,
                    "player_spawn_survival", spawnSafe,
                    spawnStart == null || spawnEnd == null
                        ? "player actor was not readable"
                        : "start=(" + spawnStart.WorldX + "," +
                          spawnStart.WorldY + "); end=(" +
                          spawnEnd.WorldX + "," + spawnEnd.WorldY +
                          "); dead=" + spawnEnd.Dead);
                if (inventoryOnly)
                {
                    int inventoryAddressValue = spawnEnd == null
                        ? 0
                        : ReadInt(
                            process,
                            spawnEnd.Address +
                            ActorInventoryAddressOffset);
                    long inventoryAddress =
                        (long)(uint)inventoryAddressValue;
                    int inventoryCount = inventoryAddressValue > 0
                        ? ReadInt(
                            process,
                            inventoryAddress + 0x0C)
                        : int.MinValue;
                    int selectedActionId = ReadInt(
                        process,
                        imageBase + EngineAddresses.CurrentActionId);
                    bool inventoryReadable =
                        inventoryAddressValue > 0 &&
                        inventoryCount >= 0 &&
                        inventoryCount <= 256 &&
                        File.Exists(Path.Combine(
                            outputDirectory,
                            "actor-inventory-entry.csv")) &&
                        File.Exists(Path.Combine(
                            outputDirectory,
                            "actor-inventory-steady.csv"));
                    AddStage(
                        stages, game, process, imageBase, clock,
                        "player_inventory_snapshot",
                        inventoryReadable,
                        "container=0x" +
                        inventoryAddress.ToString(
                            "X8",
                            CultureInfo.InvariantCulture) +
                        "; item_count=" + inventoryCount +
                        "; selected_action_id=" +
                        selectedActionId);
                    samplerStop = true;
                    sampler.Join(1500);
                    bool inventoryCursorClipSafe;
                    lock (perf)
                        inventoryCursorClipSafe = perf.All(
                            delegate(PerfSample sample)
                            {
                                return !sample.CursorClipRestricted;
                            });
                    bool inventoryProcessResponsive = stages.All(
                        delegate(Stage stage)
                        {
                            return stage.ProcessResponding;
                        });
                    exitCode =
                        missionStarted &&
                        spawnSafe &&
                        inventoryReadable &&
                        inventoryProcessResponsive &&
                        inventoryCursorClipSafe ? 0 : 1;
                    WriteArtifacts(
                        outputDirectory,
                        selectorLevel,
                        route.EngineMission,
                        stages,
                        perf,
                        transitionsLogged: false,
                        replayConsumed: true,
                        passed: exitCode == 0);
                    return exitCode;
                }
                if (parityContactOnly)
                {
                    CaptureParityCheckpoint(
                        parityCheckpoints,
                        process,
                        imageBase,
                        clock,
                        "contact_ready");
                    string contactMovementEvidence;
                    bool contactInputDelivered = ExercisePlayerMovement(
                        process,
                        imageBase,
                        window,
                        movementCellX,
                        movementCellY,
                        returnCellX,
                        returnCellY,
                        contactObservationMilliseconds,
                        parityCheckpoints,
                        clock,
                        true,
                        out contactMovementEvidence);
                    AddStage(
                        stages, game, process, imageBase, clock,
                        "natural_contact_input",
                        contactInputDelivered,
                        contactMovementEvidence);
                    Thread.Sleep(1000);
                    CaptureParityCheckpoint(
                        parityCheckpoints,
                        process,
                        imageBase,
                        clock,
                        "contact_settled");
                    samplerStop = true;
                    sampler.Join(1500);
                    bool contactCursorClipSafe;
                    lock (perf)
                        contactCursorClipSafe = perf.All(
                            delegate(PerfSample sample)
                            {
                                return !sample.CursorClipRestricted;
                            });
                    bool contactProcessResponsive = stages.All(
                        delegate(Stage stage)
                        {
                            return stage.ProcessResponding;
                        });
                    bool contactActorsReady =
                        parityCheckpoints.Count >= 7 &&
                        parityCheckpoints.All(
                            delegate(ParityCheckpoint checkpoint)
                            {
                                return checkpoint.Actors.Count(
                                    delegate(ActorSnapshot actor)
                                    {
                                        return actorIdentities.ContainsKey(
                                            actor.SceneIndex);
                                    }) == 54;
                            });
                    bool naturalContactObserved =
                        HasResolvedPlayerContact(
                            parityCheckpoints,
                            actorIdentities);
                    exitCode =
                        missionStarted &&
                        spawnSafe &&
                        contactInputDelivered &&
                        contactProcessResponsive &&
                        contactActorsReady &&
                        naturalContactObserved &&
                        contactCursorClipSafe ? 0 : 1;
                    WriteParityTrace(
                        outputDirectory,
                        selectorLevel,
                        route.EngineMission,
                        movementCellX,
                        movementCellY,
                        returnCellX,
                        returnCellY,
                        parityCheckpoints,
                        parityScenarioOverride,
                        actorIdentities,
                        false,
                        true);
                    WriteArtifacts(
                        outputDirectory,
                        selectorLevel,
                        route.EngineMission,
                        stages,
                        perf,
                        transitionsLogged: false,
                        replayConsumed: true,
                        passed: exitCode == 0);
                    return exitCode;
                }
                if (parityPatrolOnly)
                {
                    CaptureParityCheckpoint(
                        parityCheckpoints,
                        process,
                        imageBase,
                        clock,
                        "patrol_interval_1_commanded");
                    Thread.Sleep(patrolObservationMilliseconds);
                    CaptureParityCheckpoint(
                        parityCheckpoints,
                        process,
                        imageBase,
                        clock,
                        "patrol_interval_1_observed");
                    CaptureParityCheckpoint(
                        parityCheckpoints,
                        process,
                        imageBase,
                        clock,
                        "patrol_interval_2_commanded");
                    Thread.Sleep(patrolObservationMilliseconds);
                    CaptureParityCheckpoint(
                        parityCheckpoints,
                        process,
                        imageBase,
                        clock,
                        "patrol_interval_2_observed");
                    samplerStop = true;
                    sampler.Join(1500);
                    bool patrolCursorClipSafe;
                    lock (perf)
                        patrolCursorClipSafe = perf.All(
                            delegate(PerfSample sample)
                            {
                                return !sample.CursorClipRestricted;
                            });
                    bool patrolProcessResponsive = stages.All(
                        delegate(Stage stage)
                        {
                            return stage.ProcessResponding;
                        });
                    bool patrolActorsReady =
                        parityCheckpoints.Count == 4 &&
                        parityCheckpoints.All(
                            delegate(ParityCheckpoint checkpoint)
                            {
                                return checkpoint.Actors.Count(
                                    delegate(ActorSnapshot actor)
                                    {
                                        RuntimeActorIdentity identity;
                                        return actorIdentities.TryGetValue(
                                                   actor.SceneIndex,
                                                   out identity) &&
                                               identity.VwfFactionId == 1;
                                    }) == 46;
                            });
                    exitCode =
                        missionStarted &&
                        spawnSafe &&
                        patrolProcessResponsive &&
                        patrolActorsReady &&
                        patrolCursorClipSafe ? 0 : 1;
                    WriteParityTrace(
                        outputDirectory,
                        selectorLevel,
                        route.EngineMission,
                        movementCellX,
                        movementCellY,
                        returnCellX,
                        returnCellY,
                        parityCheckpoints,
                        parityScenarioOverride,
                        actorIdentities,
                        true,
                        false);
                    WriteArtifacts(
                        outputDirectory,
                        selectorLevel,
                        route.EngineMission,
                        stages,
                        perf,
                        transitionsLogged: false,
                        replayConsumed: false,
                        passed: exitCode == 0);
                    return exitCode;
                }
                CaptureParityCheckpoint(
                    parityCheckpoints,
                    process,
                    imageBase,
                    clock,
                    "gameplay_ready");

                using (CaptureResult baseline = CaptureWindow(window))
                {
                    SaveCapture(
                        baseline,
                        Path.Combine(outputDirectory, "03-baseline.jpg"));
                    if (renderAuditEnabled)
                    {
                        ObserveRenderAudit(
                            baseline, "03-baseline", renderAudit);
                        AddStage(
                            stages, game, process, imageBase, clock,
                            "gameplay_render_has_no_loading_residue",
                            renderAudit.HasVisualCapture &&
                            renderAudit.CompleteRender,
                            string.Format(
                                CultureInfo.InvariantCulture,
                                "capture={0}; " +
                                "largest_near_black_component={1}; " +
                                "near_black_ratio={2:F4}; " +
                                "map_pixels={3}",
                                renderAudit.CaptureName,
                                renderAudit.LargestDarkComponentPixels,
                                renderAudit.DarkPixelRatio,
                                renderAudit.MapPixels));
                    }
                    ExerciseToggle(
                        stages, game, process, imageBase, window, clock,
                        outputDirectory, "help_f1", DikF1,
                        EngineAddresses.InputRawHelp,
                        EngineAddresses.InputActionHelp,
                        baseline, "04-help.jpg");
                }

                using (CaptureResult mapBaseline = CaptureWindow(window))
                {
                    ExerciseToggle(
                        stages, game, process, imageBase, window, clock,
                        outputDirectory, "minimap_m", DikM,
                        EngineAddresses.InputRawMap,
                        EngineAddresses.InputActionMap,
                        mapBaseline, "05-minimap.jpg");
                }

                string movementEvidence;
                bool mouseSent = ExercisePlayerMovement(
                    process, imageBase, window,
                    movementCellX, movementCellY,
                    returnCellX, returnCellY,
                    selectorLevel == 1 ? 750 : 1800,
                    parityCheckpoints, clock, false,
                    out movementEvidence);
                if (renderAuditEnabled)
                {
                    Thread.Sleep(500);
                    using (CaptureResult afterMovement =
                        CaptureWindow(window))
                    {
                        SaveCapture(
                            afterMovement,
                            Path.Combine(
                                outputDirectory,
                                "06-after-player-hotkey.jpg"));
                    }
                }
                AddStage(
                    stages, game, process, imageBase, clock,
                    "player_input_target_delivery", mouseSent,
                    movementEvidence);

                string telemetryPath = Path.Combine(
                    gameDirectory, "M1937Telemetry.jsonl");
                bool aiSent =
                    movementOnly ||
                    SendReplay(window, ReplayAiAlert, 0);
                bool aiObserved =
                    movementOnly ||
                    WaitUntil(
                    delegate()
                    {
                        return HasPositiveCounter(
                            ReadSharedText(telemetryPath),
                            "\"alerts\":");
                    }, TimeSpan.FromSeconds(3));
                string aiTelemetry = ReadSharedText(telemetryPath);
                long maximumReinforcements = movementOnly
                    ? 0
                    : MaximumCounter(
                        aiTelemetry, "\"reinforcements\":");
                bool reactionObserved =
                    maximumReinforcements <= 0 ||
                    WaitUntil(
                        delegate()
                        {
                            return HasPositiveCounter(
                                ReadSharedText(telemetryPath),
                                "\"reaction_samples\":");
                        }, TimeSpan.FromSeconds(2));
                bool escapeObserved =
                    maximumReinforcements <= 0 ||
                    WaitUntil(
                        delegate()
                        {
                            string current = ReadSharedText(telemetryPath);
                            return SumCounter(
                                       current,
                                       "\"escape_timeouts\":") +
                                   SumCounter(
                                       current,
                                       "\"search_completed\":") >=
                                   maximumReinforcements;
                        }, TimeSpan.FromSeconds(21));
                aiTelemetry = ReadSharedText(telemetryPath);
                long reactionMaximum = MaximumCounter(
                    aiTelemetry, "\"reaction_max_ms\":");
                long searchesStarted = SumCounter(
                    aiTelemetry, "\"searches_started\":");
                long searchReplans = SumCounter(
                    aiTelemetry, "\"search_replans\":");
                long aiTickMaximum = MaximumCounter(
                    aiTelemetry, "\"tick_max_us\":");
                long escapeTimeouts = SumCounter(
                    aiTelemetry, "\"escape_timeouts\":");
                long searchCompleted = SumCounter(
                    aiTelemetry, "\"search_completed\":");
                long escapeSuccesses =
                    escapeTimeouts + searchCompleted;
                long escapeTrials =
                    maximumReinforcements;
                bool boundedReinforcements =
                    maximumReinforcements >= 0 &&
                    maximumReinforcements <= 4;
                AddStage(
                    stages, game, process, imageBase, clock,
                    movementOnly
                        ? "ai_skipped_movement_only_scope"
                        : "ai_last_known_coordination",
                    aiSent && aiObserved &&
                    boundedReinforcements && reactionObserved &&
                    escapeObserved,
                    "alert_event=" + aiObserved +
                    "; max_reinforcements=" +
                    maximumReinforcements.ToString(
                        CultureInfo.InvariantCulture) +
                    "; reaction_max_ms=" +
                    reactionMaximum.ToString(
                        CultureInfo.InvariantCulture) +
                    "; searches_started=" +
                    searchesStarted.ToString(
                        CultureInfo.InvariantCulture) +
                    "; path_replans=" +
                    searchReplans.ToString(
                        CultureInfo.InvariantCulture) +
                    "; escape_trials=" +
                    escapeTrials.ToString(
                        CultureInfo.InvariantCulture) +
                    "; escape_successes=" +
                    escapeSuccesses.ToString(
                        CultureInfo.InvariantCulture) +
                    "; ai_tick_max_us=" +
                    aiTickMaximum.ToString(
                        CultureInfo.InvariantCulture) +
                    "; live_target_sampling=false");

                if (extensionGameplaySmoke)
                {
                    AddStage(
                        stages, game, process, imageBase, clock,
                        "extension_gameplay_smoke_scope", true,
                        "save/load/failure/victory transitions are covered " +
                        "by original-level regression; extension smoke " +
                        "keeps the loaded world intact");
                }
                else
                {
                    DateTime saveRequest = DateTime.UtcNow;
                    bool saveSent =
                        SendReplay(window, ReplayMenuCommand, 7);
                    bool saveCreated = WaitUntil(
                        delegate()
                        {
                            return Directory.GetFiles(
                                gameDirectory, "1937M*.SAV")
                                .Any(delegate(string path)
                                {
                                    return File.GetLastWriteTimeUtc(path) >=
                                        saveRequest.AddSeconds(-1);
                                });
                        }, TimeSpan.FromSeconds(4));
                    AddStage(
                        stages, game, process, imageBase, clock,
                        "save_original_path", saveSent && saveCreated,
                        saveCreated
                            ? "original SAV writer changed an isolated slot"
                            : "no isolated SAV update observed");

                    ulong beforeLoadRead = ReadIoBytes(process);
                    bool loadSent =
                        SendReplay(window, ReplayMenuCommand, 17);
                    Thread.Sleep(2200);
                    ulong afterLoadRead = ReadIoBytes(process);
                    AddStage(
                        stages, game, process, imageBase, clock,
                        "load_original_path",
                        loadSent && afterLoadRead > beforeLoadRead,
                        "read_delta=" +
                        (afterLoadRead - beforeLoadRead).ToString(
                            CultureInfo.InvariantCulture));

                    bool failureSent =
                        SendReplay(window, ReplayMenuCommand, 42);
                    Thread.Sleep(900);
                    AddStage(
                        stages, game, process, imageBase, clock,
                        "failure_original_transition", failureSent,
                        "original UI transition code 42");

                    bool restartSent =
                        SendReplay(window, ReplayMenuCommand, 17);
                    Thread.Sleep(1400);
                    AddStage(
                        stages, game, process, imageBase, clock,
                        "restart_after_failure", restartSent,
                        "loaded isolated checkpoint through original path");

                    bool victorySent =
                        SendReplay(window, ReplayMenuCommand, 43);
                    Thread.Sleep(1100);
                    AddStage(
                        stages, game, process, imageBase, clock,
                        "victory_original_transition", victorySent,
                        "original UI transition code 43");
                }

                while (clock.Elapsed.TotalSeconds < maximumSeconds &&
                       !game.HasExited)
                    Thread.Sleep(50);

                samplerStop = true;
                sampler.Join(1500);
                string diagnostics = ReadSharedText(
                    Path.Combine(gameDirectory, "M1937Mod.log"));
                string telemetry = ReadSharedText(
                    Path.Combine(gameDirectory, "M1937Telemetry.jsonl"));
                bool transitionsLogged =
                    extensionGameplaySmoke ||
                    (diagnostics.Contains(
                         "\"detail\":\"save\"") &&
                     diagnostics.Contains(
                         "\"detail\":\"load\"") &&
                     diagnostics.Contains(
                         "\"detail\":\"failure\"") &&
                     diagnostics.Contains(
                         "\"detail\":\"victory\""));
                bool replayConsumed =
                    HasPositiveCounter(telemetry, "\"messages\":") &&
                    HasPositiveCounter(telemetry, "\"reads\":");
                bool allStages = stages.All(delegate(Stage stage)
                {
                    return stage.Sent && stage.ProcessResponding;
                });
                bool cursorClipSafe;
                lock (perf)
                    cursorClipSafe = perf.All(delegate(PerfSample sample)
                    {
                        return !sample.CursorClipRestricted;
                    });
                exitCode =
                    missionStarted && allStages &&
                    transitionsLogged && replayConsumed &&
                    cursorClipSafe ? 0 : 1;
                WriteParityTrace(
                    outputDirectory,
                    selectorLevel,
                    route.EngineMission,
                    movementCellX,
                    movementCellY,
                    returnCellX,
                    returnCellY,
                    parityCheckpoints,
                    parityScenarioOverride,
                    actorIdentities,
                    false,
                    false);
                WriteArtifacts(
                    outputDirectory, selectorLevel, route.EngineMission,
                    stages, perf, transitionsLogged, replayConsumed,
                    exitCode == 0);
            }
            finally
            {
                samplerStop = true;
                CloseHandle(process);
                StopLaunchedGame(game);
            }
        }
        return exitCode;
    }

    private static string ArgumentValue(
        IEnumerable<string> arguments,
        string prefix)
    {
        if (arguments == null || String.IsNullOrEmpty(prefix))
            return "";
        foreach (string argument in arguments)
        {
            if (argument != null &&
                argument.StartsWith(
                    prefix,
                    StringComparison.OrdinalIgnoreCase))
            {
                return argument.Substring(prefix.Length).Trim();
            }
        }
        return "";
    }

    private static int JsonInteger(
        IDictionary<string, object> item,
        string key)
    {
        object value;
        if (item == null ||
            !item.TryGetValue(key, out value) ||
            value == null)
        {
            throw new InvalidDataException(
                "Identity catalog integer is missing: " + key);
        }
        return Convert.ToInt32(value, CultureInfo.InvariantCulture);
    }

    private static string JsonString(
        IDictionary<string, object> item,
        string key)
    {
        object value;
        if (item == null ||
            !item.TryGetValue(key, out value) ||
            value == null)
            return "";
        return Convert.ToString(value, CultureInfo.InvariantCulture) ?? "";
    }

    private static Dictionary<int, RuntimeActorIdentity>
        ReadIdentityCatalog(string path)
    {
        string fullPath = Path.GetFullPath(path);
        if (!File.Exists(fullPath))
        {
            throw new FileNotFoundException(
                "Runtime actor identity catalog is missing.",
                fullPath);
        }
        var serializer = new JavaScriptSerializer();
        serializer.MaxJsonLength = Int32.MaxValue;
        object parsed = serializer.DeserializeObject(
            File.ReadAllText(fullPath, Encoding.UTF8));
        var root = parsed as Dictionary<string, object>;
        if (root == null ||
            JsonInteger(root, "schema_version") != 1 ||
            !String.Equals(
                JsonString(root, "content_profile"),
                "repository-mod-12-level-20260729",
                StringComparison.Ordinal))
        {
            throw new InvalidDataException(
                "Unsupported runtime actor identity catalog.");
        }
        object rawIdentities;
        if (!root.TryGetValue("identities", out rawIdentities))
        {
            throw new InvalidDataException(
                "Identity catalog has no identities array.");
        }
        var identities = rawIdentities as object[];
        if (identities == null)
        {
            throw new InvalidDataException(
                "Identity catalog identities are not an array.");
        }
        var result = new Dictionary<int, RuntimeActorIdentity>();
        foreach (object rawIdentity in identities)
        {
            var item = rawIdentity as Dictionary<string, object>;
            if (item == null ||
                !String.Equals(
                    JsonString(item, "status"),
                    "resolved",
                    StringComparison.Ordinal))
                continue;
            var identity = new RuntimeActorIdentity();
            identity.RuntimeIndex = JsonInteger(
                item, "runtime_index");
            identity.SceneIndex = JsonInteger(
                item, "scene_index");
            identity.DatabaseEntryId = JsonInteger(
                item, "database_entry_id");
            identity.VwfFactionId = JsonInteger(
                item, "vwf_faction_id");
            identity.DisplayName = JsonString(
                item, "display_name");
            identity.AuthoredHitPoints = JsonInteger(
                item, "authored_hit_points");
            identity.AuthoredAttackType = JsonInteger(
                item, "authored_attack_type");
            if (identity.SceneIndex < 0 ||
                identity.DatabaseEntryId < 0 ||
                identity.AuthoredHitPoints <= 0 ||
                identity.AuthoredAttackType < 0 ||
                identity.AuthoredAttackType > 11 ||
                identity.VwfFactionId < 1 ||
                identity.VwfFactionId > 3 ||
                result.ContainsKey(identity.RuntimeIndex))
            {
                throw new InvalidDataException(
                    "Invalid or duplicate resolved runtime identity.");
            }
            result.Add(identity.RuntimeIndex, identity);
        }
        return result;
    }

    private static void ExerciseToggle(
        List<Stage> stages, Process game, IntPtr process,
        long imageBase, IntPtr window, Stopwatch clock,
        string outputDirectory, string name, int dik,
        long rawRva,
        long actionRva,
        CaptureResult baseline, string captureName)
    {
        bool rawObserved;
        bool actionObserved;
        bool sent = PulseKeyAndObserve(
            window, dik, process, imageBase + rawRva,
            imageBase + actionRva,
            out rawObserved, out actionObserved);
        Thread.Sleep(260);
        using (CaptureResult changed = CaptureWindow(window))
        {
            SaveCapture(changed, Path.Combine(outputDirectory, captureName));
            double difference = CompareCaptures(baseline, changed);
            AddStage(
                stages, game, process, imageBase, clock, name,
                sent && rawObserved,
                string.Format(
                    CultureInfo.InvariantCulture,
                    "raw_game_state={0}; original_action_pulse={1}; " +
                    "window_hash_changed={2}; sampled_difference={3:F4}",
                    rawObserved,
                    actionObserved,
                    baseline != null && changed != null &&
                    baseline.Sha256 != changed.Sha256,
                    difference));
        }
        PulseKey(window, dik);
        Thread.Sleep(180);
    }

    private static bool PulseKey(IntPtr window, int dik)
    {
        bool down = SendReplay(window, ReplayKeyDown, dik);
        Thread.Sleep(180);
        bool up = SendReplay(window, ReplayKeyUp, dik);
        return down && up;
    }

    private static bool PulseKeyAndObserve(
        IntPtr window, int dik, IntPtr process,
        long rawAddress, long actionAddress,
        out bool rawObserved, out bool actionObserved)
    {
        rawObserved = false;
        actionObserved = false;
        bool down = SendReplay(window, ReplayKeyDown, dik);
        Stopwatch clock = Stopwatch.StartNew();
        while (clock.ElapsedMilliseconds < 260)
        {
            if ((ReadByte(process, rawAddress) & 0x80) != 0)
                rawObserved = true;
            if (ReadInt(process, actionAddress) == 1)
                actionObserved = true;
            Thread.Sleep(4);
        }
        bool up = SendReplay(window, ReplayKeyUp, dik);
        return down && up;
    }

    private static bool PulseMouseButton(IntPtr window, int button)
    {
        bool down = SendReplay(window, ReplayMouseButtonDown, button);
        Thread.Sleep(120);
        bool up = SendReplay(window, ReplayMouseButtonUp, button);
        return down && up;
    }

    private static int PackDelta(short x, short y)
    {
        return ((ushort)x) | (((int)(ushort)y) << 16);
    }

    private static bool SendReplay(IntPtr window, int command, int argument)
    {
        return PostMessage(
            window, ReplayMessage,
            new IntPtr(command), new IntPtr(argument));
    }

    private static void AddStage(
        List<Stage> stages, Process game, IntPtr process,
        long imageBase, Stopwatch clock, string name,
        bool sent, string evidence)
    {
        game.Refresh();
        stages.Add(new Stage
        {
            Name = name,
            Sent = sent,
            ProcessResponding = !game.HasExited && game.Responding,
            Mission = ReadInt(
                process, imageBase + EngineAddresses.CurrentMission),
            ElapsedMilliseconds = clock.ElapsedMilliseconds,
            Evidence = evidence
        });
    }

    private static void SamplePerformance(
        Process game, IntPtr process, Stopwatch clock,
        List<PerfSample> samples, Func<bool> shouldStop)
    {
        while (!shouldStop() && !game.HasExited)
        {
            var wait = Stopwatch.StartNew();
            int dwmResult = DwmFlush();
            wait.Stop();
            IoCounters io;
            GetProcessIoCounters(process, out io);
            game.Refresh();
            lock (samples)
            {
                samples.Add(new PerfSample
                {
                    TimeMilliseconds = clock.Elapsed.TotalMilliseconds,
                    CpuMilliseconds =
                        game.TotalProcessorTime.TotalMilliseconds,
                    ReadBytes = io.ReadTransferCount,
                    Responding = game.Responding,
                    CompositorWaitMilliseconds =
                        dwmResult == 0 ? wait.Elapsed.TotalMilliseconds : 0,
                    CursorClipRestricted = IsCursorClipRestricted()
                });
            }
            Thread.Sleep(10);
        }
    }

    private static ulong ReadIoBytes(IntPtr process)
    {
        IoCounters io;
        return GetProcessIoCounters(process, out io)
            ? io.ReadTransferCount : 0;
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

    private static IntPtr WaitForWindow(Process game, TimeSpan timeout)
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

    private static int ReadInt(IntPtr process, long address)
    {
        byte[] buffer = new byte[4];
        IntPtr read;
        return ReadProcessMemory(
            process, new IntPtr(address), buffer, buffer.Length,
            out read) && read.ToInt64() == buffer.Length
            ? BitConverter.ToInt32(buffer, 0)
            : int.MinValue;
    }

    private static int ReadByte(IntPtr process, long address)
    {
        byte[] buffer = new byte[1];
        IntPtr read;
        return ReadProcessMemory(
            process, new IntPtr(address), buffer, 1, out read) &&
            read.ToInt64() == 1 ? buffer[0] : -1;
    }

    private static byte[] ReadBytes(
        IntPtr process, long address, int length)
    {
        byte[] buffer = new byte[length];
        IntPtr read;
        return ReadProcessMemory(
            process, new IntPtr(address), buffer, buffer.Length,
            out read) && read.ToInt64() == buffer.Length
            ? buffer : new byte[0];
    }

    private static int ReadWorldActorCount(
        IntPtr process, long imageBase)
    {
        int worldAddress = ReadInt(
            process, imageBase + EngineAddresses.WorldRoot);
        if (worldAddress <= 0) return 0;
        int count = ReadInt(
            process, ((long)(uint)worldAddress) + 0x3C);
        return count > 0 && count <= 4096 ? count : 0;
    }

    private static void DefaultMovementTarget(
        int selectorLevel, out int cellX, out int cellY)
    {
        switch (selectorLevel)
        {
        case 1:
            cellX = 1;
            cellY = 3;
            break;
        default:
            cellX = -1;
            cellY = -1;
            break;
        }
    }

    private static void DefaultMovementReturnTarget(
        int selectorLevel, out int cellX, out int cellY)
    {
        switch (selectorLevel)
        {
        case 1:
            cellX = 5;
            cellY = 3;
            break;
        default:
            cellX = -1;
            cellY = -1;
            break;
        }
    }

    private static void WriteActorStateSnapshot(
        IntPtr process, long imageBase, string path)
    {
        int worldValue = ReadInt(
            process, imageBase + EngineAddresses.WorldRoot);
        if (worldValue == 0 || worldValue == int.MinValue)
            return;
        long world = (long)(uint)worldValue;
        int actorArrayValue = ReadInt(process, world + 0x18);
        int count = ReadInt(process, world + 0x3C);
        if (actorArrayValue == 0 || actorArrayValue == int.MinValue ||
            count <= 0 || count > 4096)
            return;

        long actorArray = (long)(uint)actorArrayValue;
        var text = new StringBuilder();
        text.AppendLine(
            "index,address,runtime_type,faction,world_x,world_y," +
            "direction,dead,goal_kind,goal_x,goal_y,command_variant," +
            "command_pending,movement_active,movement_path_state," +
            "movement_mode,resolved_goal_x,resolved_goal_y,path_override");
        for (int index = 0; index < count; ++index)
        {
            int actorValue = ReadInt(
                process, actorArray + index * 4L);
            if (actorValue == 0 || actorValue == int.MinValue)
                continue;
            long actor = (long)(uint)actorValue;
            ActorSnapshot snapshot = ReadActor(process, actor);
            if (snapshot == null)
                continue;
            snapshot.SceneIndex = index;
            text.AppendFormat(
                CultureInfo.InvariantCulture,
                "{0},0x{1:X8},{2},{3},{4},{5},{6},{7},{8},{9},{10}," +
                "{11},{12},{13},{14},{15},{16},{17},{18}\r\n",
                index,
                snapshot.Address,
                snapshot.RuntimeType,
                snapshot.Faction,
                snapshot.WorldX,
                snapshot.WorldY,
                snapshot.Direction,
                snapshot.Dead,
                snapshot.GoalKind,
                snapshot.GoalX,
                snapshot.GoalY,
                snapshot.CommandVariant,
                snapshot.CommandPending,
                snapshot.MovementActive,
                snapshot.MovementPathState,
                snapshot.MovementMode,
                snapshot.ResolvedGoalX,
                snapshot.ResolvedGoalY,
                snapshot.PathOverrideActive);
        }
        File.WriteAllText(path, text.ToString(), new UTF8Encoding(false));
    }

    private static void WriteActorLayoutSnapshot(
        IntPtr process,
        long imageBase,
        Dictionary<int, RuntimeActorIdentity> actorIdentities,
        string path)
    {
        int worldValue = ReadInt(
            process, imageBase + EngineAddresses.WorldRoot);
        if (worldValue == 0 || worldValue == int.MinValue)
            return;
        long world = (long)(uint)worldValue;
        int actorArrayValue = ReadInt(process, world + 0x18);
        int count = ReadInt(process, world + 0x3C);
        if (actorArrayValue == 0 || actorArrayValue == int.MinValue ||
            count <= 0 || count > 4096)
            return;

        const int actorSize = 0x294;
        long actorArray = (long)(uint)actorArrayValue;
        var text = new StringBuilder();
        text.Append(
            "runtime_index,scene_index,database_entry_id,address");
        for (int offset = 0; offset < actorSize; offset += 4)
        {
            text.AppendFormat(
                CultureInfo.InvariantCulture,
                ",off_{0:X3}",
                offset);
        }
        text.AppendLine();
        for (int runtimeIndex = 0;
             runtimeIndex < count;
             ++runtimeIndex)
        {
            int actorValue = ReadInt(
                process, actorArray + runtimeIndex * 4L);
            if (actorValue == 0 || actorValue == int.MinValue)
                continue;
            long actorAddress = (long)(uint)actorValue;
            byte[] bytes = ReadBytes(
                process, actorAddress, actorSize);
            if (bytes.Length != actorSize)
                continue;
            RuntimeActorIdentity identity = null;
            bool resolved =
                actorIdentities != null &&
                actorIdentities.TryGetValue(
                    runtimeIndex, out identity);
            text.AppendFormat(
                CultureInfo.InvariantCulture,
                "{0},{1},{2},0x{3:X8}",
                runtimeIndex,
                resolved ? identity.SceneIndex : -1,
                resolved ? identity.DatabaseEntryId : -1,
                actorAddress);
            for (int offset = 0; offset < actorSize; offset += 4)
            {
                text.AppendFormat(
                    CultureInfo.InvariantCulture,
                    ",{0}",
                    BitConverter.ToInt32(bytes, offset));
            }
            text.AppendLine();
        }
        File.WriteAllText(
            path, text.ToString(), new UTF8Encoding(false));
    }

    private static void WriteActorInventorySnapshot(
        IntPtr process,
        long imageBase,
        Dictionary<int, RuntimeActorIdentity> actorIdentities,
        string path)
    {
        int worldValue = ReadInt(
            process, imageBase + EngineAddresses.WorldRoot);
        if (worldValue == 0 || worldValue == int.MinValue)
            return;
        long world = (long)(uint)worldValue;
        int actorArrayValue = ReadInt(process, world + 0x18);
        int actorCount = ReadInt(process, world + 0x3C);
        if (actorArrayValue == 0 ||
            actorArrayValue == int.MinValue ||
            actorCount <= 0 ||
            actorCount > 4096)
            return;

        int selectedActionId = ReadInt(
            process, imageBase + EngineAddresses.CurrentActionId);
        long actorArray = (long)(uint)actorArrayValue;
        var text = new StringBuilder();
        text.AppendLine(
            "runtime_index,scene_index,database_entry_id,faction," +
            "default_attack_type,selected_action_id,actor_address," +
            "container_address,item_count,inventory_index,item_id," +
            "quantity,quantity_mode");

        for (int runtimeIndex = 0;
             runtimeIndex < actorCount;
             ++runtimeIndex)
        {
            int actorValue = ReadInt(
                process, actorArray + runtimeIndex * 4L);
            if (actorValue == 0 || actorValue == int.MinValue)
                continue;
            long actorAddress = (long)(uint)actorValue;
            int faction = ReadInt(
                process, actorAddress + ActorFactionOffset);
            int defaultAttackType = ReadInt(
                process, actorAddress + ActorDefaultAttackTypeOffset);
            int containerValue = ReadInt(
                process, actorAddress + ActorInventoryAddressOffset);
            if (containerValue == int.MinValue)
                continue;
            long containerAddress = (long)(uint)containerValue;
            int itemCount = containerAddress == 0
                ? 0
                : ReadInt(process, containerAddress + 0x0C);
            int itemIdsValue = containerAddress == 0
                ? 0
                : ReadInt(process, containerAddress + 0x00);
            int quantitiesValue = containerAddress == 0
                ? 0
                : ReadInt(process, containerAddress + 0x04);
            int quantityModesValue = containerAddress == 0
                ? 0
                : ReadInt(process, containerAddress + 0x08);
            bool validContainer =
                containerAddress != 0 &&
                itemCount >= 0 &&
                itemCount <= 256 &&
                (itemCount == 0 ||
                 (itemIdsValue > 0 &&
                  quantitiesValue > 0 &&
                  quantityModesValue > 0));
            if (!validContainer)
                continue;

            RuntimeActorIdentity identity = null;
            bool resolved =
                actorIdentities != null &&
                actorIdentities.TryGetValue(
                    runtimeIndex, out identity);
            int sceneIndex = resolved ? identity.SceneIndex : -1;
            int databaseEntryId =
                resolved ? identity.DatabaseEntryId : -1;
            if (itemCount == 0)
            {
                AppendInventoryRow(
                    text,
                    runtimeIndex,
                    sceneIndex,
                    databaseEntryId,
                    faction,
                    defaultAttackType,
                    selectedActionId,
                    actorAddress,
                    containerAddress,
                    itemCount,
                    -1,
                    0,
                    0,
                    0);
                continue;
            }

            long itemIdsAddress = (long)(uint)itemIdsValue;
            long quantitiesAddress = (long)(uint)quantitiesValue;
            long quantityModesAddress =
                (long)(uint)quantityModesValue;
            for (int inventoryIndex = 0;
                 inventoryIndex < itemCount;
                 ++inventoryIndex)
            {
                int itemId = ReadInt(
                    process,
                    itemIdsAddress + inventoryIndex * 4L);
                int quantity = ReadInt(
                    process,
                    quantitiesAddress + inventoryIndex * 4L);
                int quantityMode = ReadInt(
                    process,
                    quantityModesAddress + inventoryIndex * 4L);
                if (itemId == int.MinValue ||
                    quantity == int.MinValue ||
                    quantityMode == int.MinValue)
                    continue;
                AppendInventoryRow(
                    text,
                    runtimeIndex,
                    sceneIndex,
                    databaseEntryId,
                    faction,
                    defaultAttackType,
                    selectedActionId,
                    actorAddress,
                    containerAddress,
                    itemCount,
                    inventoryIndex,
                    itemId,
                    quantity,
                    quantityMode);
            }
        }

        File.WriteAllText(
            path, text.ToString(), new UTF8Encoding(false));
    }

    private static void AppendInventoryRow(
        StringBuilder text,
        int runtimeIndex,
        int sceneIndex,
        int databaseEntryId,
        int faction,
        int defaultAttackType,
        int selectedActionId,
        long actorAddress,
        long containerAddress,
        int itemCount,
        int inventoryIndex,
        int itemId,
        int quantity,
        int quantityMode)
    {
        text.AppendFormat(
            CultureInfo.InvariantCulture,
            "{0},{1},{2},{3},{4},{5},0x{6:X8},0x{7:X8}," +
            "{8},{9},{10},{11},{12}\r\n",
            runtimeIndex,
            sceneIndex,
            databaseEntryId,
            faction,
            defaultAttackType,
            selectedActionId,
            actorAddress,
            containerAddress,
            itemCount,
            inventoryIndex,
            itemId,
            quantity,
            quantityMode);
    }

    private static ActorSnapshot FindPlayerActor(
        IntPtr process, long imageBase)
    {
        int worldValue = ReadInt(
            process, imageBase + EngineAddresses.WorldRoot);
        if (worldValue == 0 || worldValue == int.MinValue)
            return null;
        long world = (long)(uint)worldValue;
        int actorArrayValue = ReadInt(process, world + 0x18);
        int count = ReadInt(process, world + 0x3C);
        if (actorArrayValue == 0 || actorArrayValue == int.MinValue ||
            count <= 0 || count > 4096)
            return null;
        long actorArray = (long)(uint)actorArrayValue;
        ActorSnapshot fallback = null;
        for (int index = 0; index < count; ++index)
        {
            int actorValue = ReadInt(
                process, actorArray + index * 4L);
            if (actorValue == 0 || actorValue == int.MinValue)
                continue;
            long actor = (long)(uint)actorValue;
            int faction = ReadInt(
                process, actor + ActorFactionOffset);
            if (faction != 3)
                continue;
            var snapshot = ReadActor(process, actor);
            if (snapshot == null)
                continue;
            snapshot.SceneIndex = index;
            if (snapshot.RuntimeType == 1)
                return snapshot;
            if (fallback == null)
                fallback = snapshot;
        }
        return fallback;
    }

    private static ActorSnapshot ReadActor(
        IntPtr process, long actor)
    {
        int worldX = ReadInt(process, actor + ActorWorldXOffset);
        int worldY = ReadInt(process, actor + ActorWorldYOffset);
        if (worldX == int.MinValue || worldY == int.MinValue)
            return null;
        return new ActorSnapshot
        {
            Address = actor,
            RuntimeType = ReadInt(
                process, actor + ActorRuntimeTypeOffset),
            Faction = ReadInt(process, actor + ActorFactionOffset),
            WorldX = worldX,
            WorldY = worldY,
            Direction = ReadInt(
                process, actor + ActorFacingDirectionOffset),
            Dead = ReadInt(process, actor + ActorDeadOffset),
            TargetStatus = ReadInt(
                process, actor + ActorTargetStatusOffset),
            GoalKind = ReadInt(process, actor + ActorGoalKindOffset),
            GoalX = ReadInt(process, actor + ActorGoalXOffset),
            GoalY = ReadInt(process, actor + ActorGoalYOffset),
            InterestAddress = (long)(uint)ReadInt(
                process, actor + ActorInterestAddressOffset),
            CommandVariant = ReadInt(
                process, actor + ActorCommandVariantOffset),
            CommandPending = ReadInt(
                process, actor + ActorCommandPendingOffset),
            SelectedForCommand = ReadInt(
                process, actor + ActorSelectedForCommandOffset),
            CurrentHitPoints = ReadInt(
                process, actor + ActorCurrentHitPointsOffset),
            SearchOrReturnActive = ReadInt(
                process, actor + ActorSearchOrReturnActiveOffset),
            MovementActive = ReadInt(
                process, actor + ActorMovementActiveOffset),
            MovementPathState = ReadInt(
                process, actor + ActorMovementPathStateOffset),
            MovementMode = ReadInt(
                process, actor + ActorMovementModeOffset),
            DefaultAttackType = ReadInt(
                process, actor + ActorDefaultAttackTypeOffset),
            TargetAddress = (long)(uint)ReadInt(
                process, actor + ActorTargetAddressOffset),
            ResolvedGoalX = ReadInt(
                process, actor + ActorResolvedGoalXOffset),
            ResolvedGoalY = ReadInt(
                process, actor + ActorResolvedGoalYOffset),
            SearchDelayLimit = ReadInt(
                process, actor + ActorSearchDelayLimitOffset),
            SearchDelayCounter = ReadInt(
                process, actor + ActorSearchDelayCounterOffset),
            ContactState = ReadInt(
                process, actor + ActorContactStateOffset),
            TargetLost = ReadInt(
                process, actor + ActorTargetLostOffset),
            ReactionState = ReadInt(
                process, actor + ActorReactionStateOffset),
            PathOverrideActive = ReadInt(
                process, actor + ActorPathOverrideActiveOffset)
        };
    }

    private static bool MoveReplayCursor(
        IntPtr process, long imageBase, IntPtr window,
        int targetX, int targetY, out int actualX, out int actualY)
    {
        int currentX = ReadInt(
            process, imageBase + EngineAddresses.CursorX);
        int currentY = ReadInt(
            process, imageBase + EngineAddresses.CursorY);
        if (currentX == int.MinValue || currentY == int.MinValue)
        {
            actualX = currentX;
            actualY = currentY;
            return false;
        }
        int deltaX = Math.Max(
            short.MinValue, Math.Min(short.MaxValue, targetX - currentX));
        int deltaY = Math.Max(
            short.MinValue, Math.Min(short.MaxValue, targetY - currentY));
        bool sent = SendReplay(
            window, ReplayMouseDelta,
            PackDelta((short)deltaX, (short)deltaY));
        Thread.Sleep(180);
        actualX = ReadInt(
            process, imageBase + EngineAddresses.CursorX);
        actualY = ReadInt(
            process, imageBase + EngineAddresses.CursorY);
        return sent &&
            Math.Abs(actualX - targetX) <= 3 &&
            Math.Abs(actualY - targetY) <= 3;
    }

    private static bool ExercisePlayerMovement(
        IntPtr process, long imageBase, IntPtr window,
        int targetCellX, int targetCellY,
        int returnCellX, int returnCellY,
        int segmentObservationMilliseconds,
        List<ParityCheckpoint> parityCheckpoints,
        Stopwatch runClock,
        bool allowContactInterruption,
        out string evidence)
    {
        if (targetCellX < 0 || targetCellY < 0)
        {
            evidence = "no deterministic movement target for this level";
            return true;
        }
        if (returnCellX < 0 || returnCellY < 0)
        {
            evidence =
                "no deterministic second movement target for this level";
            return false;
        }
        ActorSnapshot before = FindPlayerActor(process, imageBase);
        if (before == null)
        {
            evidence = "player actor was not readable";
            return false;
        }
        int cameraX = ReadInt(
            process, imageBase + EngineAddresses.CameraX);
        int cameraY = ReadInt(
            process, imageBase + EngineAddresses.CameraY);
        int screenWidth = ReadInt(
            process, imageBase + EngineAddresses.ScreenWidth);
        int screenHeight = ReadInt(
            process, imageBase + EngineAddresses.ScreenHeight);
        if (cameraX == int.MinValue || cameraY == int.MinValue ||
            screenWidth <= 0 || screenHeight <= 0)
        {
            evidence = "camera or logical viewport was not readable";
            return false;
        }

        // The original F1 help identifies F4 as 强子. Extension missions
        // deliberately use 强子 (database entry 924), so select through the
        // game's documented hotkey instead of guessing a sprite hitbox.
        byte[] actorBeforeSelection = ReadBytes(
            process, before.Address, 0x294);
        bool selectionSent = PulseKey(window, DikF4);
        Thread.Sleep(320);
        // Character hotkeys intentionally center the camera. Refresh the
        // origin before converting the destination into screen coordinates.
        cameraX = ReadInt(
            process, imageBase + EngineAddresses.CameraX);
        cameraY = ReadInt(
            process, imageBase + EngineAddresses.CameraY);
        ActorSnapshot selected = FindPlayerActor(process, imageBase);
        byte[] actorAfterSelection = ReadBytes(
            process, before.Address, 0x294);
        int selectionActorChangeCount = 0;
        if (actorBeforeSelection.Length == actorAfterSelection.Length)
        {
            for (int index = 0;
                 index < actorBeforeSelection.Length;
                 ++index)
            {
                if (actorBeforeSelection[index] !=
                    actorAfterSelection[index])
                    selectionActorChangeCount++;
            }
        }
        if (selected == null)
        {
            evidence = "player actor disappeared after F4 selection";
            return false;
        }
        CaptureParityCheckpoint(
            parityCheckpoints,
            process,
            imageBase,
            runClock,
            "player_selected");

        int targetWorldX = checked(targetCellX * 32 + 16);
        int targetWorldY = checked(targetCellY * 16 + 8);
        int targetScreenX = targetWorldX - cameraX;
        int targetScreenY = targetWorldY - cameraY;
        bool outboundCameraPanned = false;
        if (targetScreenX < 8 || targetScreenX >= screenWidth - 8 ||
            targetScreenY < 8 || targetScreenY >= screenHeight - 96)
        {
            outboundCameraPanned = PanReplayCameraToWorldPoint(
                process,
                imageBase,
                window,
                targetWorldX,
                targetWorldY,
                screenWidth,
                screenHeight,
                5000,
                out cameraX,
                out cameraY);
            targetScreenX = targetWorldX - cameraX;
            targetScreenY = targetWorldY - cameraY;
            if (!outboundCameraPanned)
            {
                evidence =
                    "movement target is outside the visible map viewport; " +
                    "camera=(" + cameraX + "," + cameraY +
                    "); target_screen=(" + targetScreenX + "," +
                    targetScreenY + "); process-local edge pan failed";
                return false;
            }
        }

        int cursorX;
        int cursorY;
        bool cursorReached = MoveReplayCursor(
            process, imageBase, window,
            targetScreenX, targetScreenY,
            out cursorX, out cursorY);
        bool clickSent = cursorReached && PulseMouseButton(window, 0);
        ActorSnapshot firstGoal = null;
        bool firstGoalAccepted = clickSent && WaitForPlayerGoal(
            process, imageBase,
            targetWorldX, targetWorldY, 900,
            out firstGoal);
        CaptureParityCheckpoint(
            parityCheckpoints,
            process,
            imageBase,
            runClock,
            "move_outbound_commanded");
        MovementSegmentObservation outbound = ObserveMovementSegment(
            process, imageBase,
            firstGoal ?? selected,
            targetWorldX, targetWorldY,
            segmentObservationMilliseconds);
        CaptureParityCheckpoint(
            parityCheckpoints,
            process,
            imageBase,
            runClock,
            "move_outbound_observed");
        AttachObservedPositions(
            parityCheckpoints, outbound.Positions);
        bool firstMoved =
            outbound.MaximumDisplacement >= 24 &&
            outbound.EndTargetDistance <
                outbound.StartTargetDistance - 8;
        bool firstFacingAligned =
            outbound.MovingSamples >= 2 &&
            outbound.AlignedSamples > 0 &&
            outbound.OppositeSamples == 0;

        // A second primary click must replace the still-active first goal.
        // Click a second verified open cell on the other side of the route.
        // Do not reuse the original spawn: the legacy occupancy grid may keep
        // that cell reserved briefly while the actor is leaving it.
        ActorSnapshot returnStart = outbound.Last;
        int returnWorldX = checked(returnCellX * 32 + 16);
        int returnWorldY = checked(returnCellY * 16 + 8);
        cameraX = ReadInt(
            process, imageBase + EngineAddresses.CameraX);
        cameraY = ReadInt(
            process, imageBase + EngineAddresses.CameraY);
        int returnScreenX = returnWorldX - cameraX;
        int returnScreenY = returnWorldY - cameraY;
        bool returnCameraPanned = false;
        bool returnTargetVisible =
            returnScreenX >= 8 &&
            returnScreenX < screenWidth - 8 &&
            returnScreenY >= 8 &&
            returnScreenY < screenHeight - 96;
        if (!returnTargetVisible)
        {
            returnCameraPanned = PanReplayCameraToWorldPoint(
                process,
                imageBase,
                window,
                returnWorldX,
                returnWorldY,
                screenWidth,
                screenHeight,
                5000,
                out cameraX,
                out cameraY);
            returnScreenX = returnWorldX - cameraX;
            returnScreenY = returnWorldY - cameraY;
            returnTargetVisible =
                returnCameraPanned &&
                returnScreenX >= 8 &&
                returnScreenX < screenWidth - 8 &&
                returnScreenY >= 8 &&
                returnScreenY < screenHeight - 96;
        }
        int returnCursorX = int.MinValue;
        int returnCursorY = int.MinValue;
        bool returnCursorReached =
            returnTargetVisible &&
            MoveReplayCursor(
                process, imageBase, window,
                returnScreenX, returnScreenY,
                out returnCursorX, out returnCursorY);
        bool returnClickSent =
            returnCursorReached && PulseMouseButton(window, 0);
        ActorSnapshot returnGoal = null;
        bool returnGoalAccepted = returnClickSent && WaitForPlayerGoal(
            process, imageBase,
            returnWorldX, returnWorldY, 900,
            out returnGoal);
        CaptureParityCheckpoint(
            parityCheckpoints,
            process,
            imageBase,
            runClock,
            "move_return_commanded");
        MovementSegmentObservation inbound = ObserveMovementSegment(
            process, imageBase,
            returnGoal ?? returnStart,
            returnWorldX, returnWorldY,
            segmentObservationMilliseconds);
        CaptureParityCheckpoint(
            parityCheckpoints,
            process,
            imageBase,
            runClock,
            "move_return_observed");
        AttachObservedPositions(
            parityCheckpoints, inbound.Positions);
        bool returnMoved =
            inbound.MaximumDisplacement >= 16 &&
            inbound.EndTargetDistance <
                inbound.StartTargetDistance - 8;
        bool returnFacingAligned =
            inbound.MovingSamples >= 2 &&
            inbound.AlignedSamples > 0 &&
            inbound.OppositeSamples == 0;

        var directions = new HashSet<int>(outbound.Directions);
        directions.UnionWith(inbound.Directions);
        bool goalReplaced =
            firstGoalAccepted && returnGoalAccepted &&
            (targetWorldX != returnWorldX ||
             targetWorldY != returnWorldY);
        bool turned = directions.Count >= 2;
        ActorSnapshot after = inbound.Last ?? outbound.Last ?? selected;
        bool alive = after != null && after.Dead == 0;
        bool directionValid = after != null &&
            after.Direction >= 1 && after.Direction <= 8;
        evidence =
            "target_cell=(" + targetCellX + "," + targetCellY + ")" +
            "; target_screen=(" + targetScreenX + "," + targetScreenY + ")" +
            "; outbound_camera_panned=" + outboundCameraPanned +
            "; cursor=(" + cursorX + "," + cursorY + ")" +
            "; selection_sent=" + selectionSent +
            "; selection_actor_bytes_changed=" +
            selectionActorChangeCount +
            "; primary_click_sent=" + clickSent +
            "; primary_goal_exact=" + firstGoalAccepted +
            "; outbound_displacement=" +
            outbound.MaximumDisplacement +
            "; outbound_distance=" +
            outbound.StartTargetDistance + "->" +
            outbound.EndTargetDistance + " (min=" +
            outbound.MinimumTargetDistance + ")" +
            "; outbound_end=(" +
            outbound.Last.WorldX + "," +
            outbound.Last.WorldY + ")" +
            "; outbound_facing=" +
            outbound.AlignedSamples + "/" +
            outbound.MovingSamples +
            "; outbound_opposite=" +
            outbound.OppositeSamples +
            "; return_target_screen=(" +
            returnScreenX + "," + returnScreenY + ")" +
            "; return_target_cell=(" +
            returnCellX + "," + returnCellY + ")" +
            "; return_camera_panned=" + returnCameraPanned +
            "; return_cursor=(" +
            returnCursorX + "," + returnCursorY + ")" +
            "; return_click_sent=" + returnClickSent +
            "; return_goal_exact=" + returnGoalAccepted +
            "; return_displacement=" +
            inbound.MaximumDisplacement +
            "; return_distance=" +
            inbound.StartTargetDistance + "->" +
            inbound.EndTargetDistance + " (min=" +
            inbound.MinimumTargetDistance + ")" +
            "; return_end=(" +
            inbound.Last.WorldX + "," +
            inbound.Last.WorldY + ")" +
            "; return_facing=" +
            inbound.AlignedSamples + "/" +
            inbound.MovingSamples +
            "; return_opposite=" +
            inbound.OppositeSamples +
            "; goal_replaced=" + goalReplaced +
            "; directions=" + string.Join(",", directions) +
            "; both_segments_moved=" +
            (firstMoved && returnMoved) +
            "; both_segments_face_motion=" +
            (firstFacingAligned && returnFacingAligned) +
            "; turn_observable_while_background=" + turned +
            "; goal=(" + after.GoalKind + "," + after.GoalX + "," +
            after.GoalY + "); path_state=(" +
            after.CommandVariant + "," +
            after.CommandPending + "," +
            after.MovementActive + "," +
            after.MovementPathState + "," +
            after.MovementMode + "," +
            after.ResolvedGoalX + "," +
            after.ResolvedGoalY + "," +
            after.PathOverrideActive + "); dead=" + after.Dead;
        bool commandDelivery =
            selectionSent && clickSent && cursorReached &&
            returnTargetVisible && returnClickSent &&
            returnCursorReached && directionValid &&
            firstGoalAccepted && returnGoalAccepted &&
            goalReplaced && firstMoved &&
            firstFacingAligned && returnFacingAligned && turned;
        if (allowContactInterruption)
            return commandDelivery;
        return commandDelivery && alive && returnMoved;
    }

    private static bool PanReplayCameraToWorldPoint(
        IntPtr process,
        long imageBase,
        IntPtr window,
        int worldX,
        int worldY,
        int screenWidth,
        int screenHeight,
        int milliseconds,
        out int cameraX,
        out int cameraY)
    {
        cameraX = ReadInt(
            process, imageBase + EngineAddresses.CameraX);
        cameraY = ReadInt(
            process, imageBase + EngineAddresses.CameraY);
        int mapBottom = Math.Max(24, screenHeight - 96);
        if (worldX >= 0 && worldX <= UInt16.MaxValue &&
            worldY >= 0 && worldY <= UInt16.MaxValue)
        {
            SendReplay(
                window,
                ReplayCameraCenter,
                PackDelta((short)worldX, (short)worldY));
            int centeredCameraX = cameraX;
            int centeredCameraY = cameraY;
            bool replayCentered = WaitUntil(
                    delegate()
                    {
                        centeredCameraX = ReadInt(
                            process,
                            imageBase + EngineAddresses.CameraX);
                        centeredCameraY = ReadInt(
                            process,
                            imageBase + EngineAddresses.CameraY);
                        int candidateX = worldX - centeredCameraX;
                        int candidateY = worldY - centeredCameraY;
                        return candidateX >= 8 &&
                            candidateX < screenWidth - 8 &&
                            candidateY >= 8 &&
                            candidateY < mapBottom;
                    },
                    TimeSpan.FromSeconds(1));
            if (replayCentered)
            {
                cameraX = centeredCameraX;
                cameraY = centeredCameraY;
                return true;
            }
        }
        Stopwatch clock = Stopwatch.StartNew();
        while (clock.ElapsedMilliseconds < milliseconds)
        {
            cameraX = ReadInt(
                process, imageBase + EngineAddresses.CameraX);
            cameraY = ReadInt(
                process, imageBase + EngineAddresses.CameraY);
            if (cameraX == int.MinValue || cameraY == int.MinValue)
                return false;
            int screenX = worldX - cameraX;
            int screenY = worldY - cameraY;
            if (screenX >= 8 && screenX < screenWidth - 8 &&
                screenY >= 8 && screenY < mapBottom)
                return true;

            int edgeX = screenX < 8
                ? 1
                : screenX >= screenWidth - 8
                    ? screenWidth - 2
                    : Math.Max(16, Math.Min(screenWidth - 17, screenX));
            int edgeY = screenY < 8
                ? 1
                : screenY >= mapBottom
                    ? mapBottom - 2
                    : Math.Max(16, Math.Min(mapBottom - 17, screenY));
            int actualX;
            int actualY;
            if (!MoveReplayCursor(
                    process,
                    imageBase,
                    window,
                    edgeX,
                    edgeY,
                    out actualX,
                    out actualY))
                return false;
            int horizontalPanKey = screenX < 8
                ? DikLeft
                : screenX >= screenWidth - 8 ? DikRight : -1;
            int verticalPanKey = screenY < 8
                ? DikUp
                : screenY >= mapBottom ? DikDown : -1;
            if (horizontalPanKey >= 0)
                SendReplay(window, ReplayKeyDown, horizontalPanKey);
            if (verticalPanKey >= 0)
                SendReplay(window, ReplayKeyDown, verticalPanKey);
            Thread.Sleep(120);
            if (horizontalPanKey >= 0)
                SendReplay(window, ReplayKeyUp, horizontalPanKey);
            if (verticalPanKey >= 0)
                SendReplay(window, ReplayKeyUp, verticalPanKey);
        }
        cameraX = ReadInt(
            process, imageBase + EngineAddresses.CameraX);
        cameraY = ReadInt(
            process, imageBase + EngineAddresses.CameraY);
        int finalScreenX = worldX - cameraX;
        int finalScreenY = worldY - cameraY;
        return finalScreenX >= 8 &&
            finalScreenX < screenWidth - 8 &&
            finalScreenY >= 8 &&
            finalScreenY < mapBottom;
    }

    private static bool WaitForPlayerGoal(
        IntPtr process, long imageBase,
        int expectedX, int expectedY, int milliseconds,
        out ActorSnapshot accepted)
    {
        accepted = null;
        Stopwatch clock = Stopwatch.StartNew();
        while (clock.ElapsedMilliseconds < milliseconds)
        {
            ActorSnapshot sample = FindPlayerActor(process, imageBase);
            if (sample != null &&
                sample.GoalKind == 1 &&
                sample.GoalX == expectedX &&
                sample.GoalY == expectedY)
            {
                accepted = sample;
                return true;
            }
            Thread.Sleep(25);
        }
        accepted = FindPlayerActor(process, imageBase);
        return false;
    }

    private static MovementSegmentObservation ObserveMovementSegment(
        IntPtr process, long imageBase, ActorSnapshot start,
        int targetX, int targetY,
        int milliseconds)
    {
        var observation = new MovementSegmentObservation();
        observation.Last = start;
        if (start == null)
            return observation;
        observation.Positions.Add(new Point
        {
            X = start.WorldX,
            Y = start.WorldY
        });
        observation.Directions.Add(start.Direction);
        observation.StartTargetDistance =
            ManhattanDistance(start.WorldX, start.WorldY, targetX, targetY);
        observation.EndTargetDistance =
            observation.StartTargetDistance;
        observation.MinimumTargetDistance =
            observation.StartTargetDistance;

        ActorSnapshot previous = start;
        Stopwatch clock = Stopwatch.StartNew();
        while (clock.ElapsedMilliseconds < milliseconds)
        {
            Thread.Sleep(40);
            ActorSnapshot sample = FindPlayerActor(process, imageBase);
            if (sample == null)
                continue;
            observation.Samples++;
            observation.Last = sample;
            observation.Directions.Add(sample.Direction);
            Point lastPosition =
                observation.Positions[
                    observation.Positions.Count - 1];
            if (lastPosition.X != sample.WorldX ||
                lastPosition.Y != sample.WorldY)
                observation.Positions.Add(new Point
                {
                    X = sample.WorldX,
                    Y = sample.WorldY
                });
            int displacement =
                ManhattanDistance(
                    sample.WorldX, sample.WorldY,
                    start.WorldX, start.WorldY);
            observation.MaximumDisplacement =
                Math.Max(
                    observation.MaximumDisplacement,
                    displacement);
            observation.EndTargetDistance =
                ManhattanDistance(
                    sample.WorldX, sample.WorldY,
                    targetX, targetY);
            observation.MinimumTargetDistance =
                Math.Min(
                    observation.MinimumTargetDistance,
                    observation.EndTargetDistance);

            int deltaX = sample.WorldX - previous.WorldX;
            int deltaY = sample.WorldY - previous.WorldY;
            if (deltaX != 0 || deltaY != 0)
            {
                observation.MovingSamples++;
                int currentDot = DirectionDot(
                    sample.Direction, deltaX, deltaY);
                int previousDot = DirectionDot(
                    previous.Direction, deltaX, deltaY);
                if (Math.Max(currentDot, previousDot) > 0)
                    observation.AlignedSamples++;
                else if (currentDot < 0 && previousDot < 0)
                    observation.OppositeSamples++;
                else
                    observation.PerpendicularSamples++;
            }
            previous = sample;
        }
        return observation;
    }

    private static int ManhattanDistance(
        int x1, int y1, int x2, int y2)
    {
        return Math.Abs(x1 - x2) + Math.Abs(y1 - y2);
    }

    private static int DirectionDot(
        int direction, int deltaX, int deltaY)
    {
        int directionX = 0;
        int directionY = 0;
        switch (direction)
        {
        case 1: directionY = -1; break;
        case 2: directionX = 1; directionY = -1; break;
        case 3: directionX = 1; break;
        case 4: directionX = 1; directionY = 1; break;
        case 5: directionY = 1; break;
        case 6: directionX = -1; directionY = 1; break;
        case 7: directionX = -1; break;
        case 8: directionX = -1; directionY = -1; break;
        default: return int.MinValue;
        }
        return checked(directionX * deltaX + directionY * deltaY);
    }

    private static CaptureResult CaptureWindow(IntPtr window)
    {
        Rect rect;
        if (!GetClientRect(window, out rect))
            return new CaptureResult
            {
                Bitmap = null, Sha256 = "", NonBlank = false
            };
        bool raisedForAudit = String.Equals(
            Environment.GetEnvironmentVariable("M1937_RENDER_AUDIT"),
            "1",
            StringComparison.Ordinal);
        if (raisedForAudit)
        {
            SetWindowPos(
                window, HwndTopmost, 0, 0, 0, 0,
                SwpNoMove | SwpNoSize | SwpNoActivate);
            try { DwmFlush(); } catch { }
            // SetWindowPos is intentionally non-activating. Give DWM one
            // composition interval to expose the legacy DirectDraw surface
            // before the window-only screen copy.
            Thread.Sleep(120);
            try { DwmFlush(); } catch { }
        }
        int width = Math.Max(1, Math.Min(1024, rect.Right - rect.Left));
        int height = Math.Max(1, Math.Min(768, rect.Bottom - rect.Top));
        var bitmap = new Bitmap(width, height, PixelFormat.Format24bppRgb);
        bool success;
        using (Graphics graphics = Graphics.FromImage(bitmap))
        {
            IntPtr dc = graphics.GetHdc();
            try { success = PrintWindow(window, dc, PclientOnly); }
            finally { graphics.ReleaseHdc(dc); }
        }
        // Legacy Direct3D surfaces often return a valid but unchanged
        // PrintWindow image. Capture exactly the client rectangle from the
        // compositor as a window-only fallback; this does not activate the
        // window or touch any input device.
        var origin = new Point { X = 0, Y = 0 };
        if (ClientToScreen(window, ref origin))
        {
            var compositorBitmap =
                new Bitmap(width, height, PixelFormat.Format24bppRgb);
            try
            {
                using (Graphics graphics =
                    Graphics.FromImage(compositorBitmap))
                    graphics.CopyFromScreen(
                        origin.X, origin.Y, 0, 0,
                        new Size(width, height),
                        CopyPixelOperation.SourceCopy);
                // Keep PrintWindow as a fallback. A non-activating window can
                // need more than one DWM interval before CopyFromScreen sees
                // its DirectDraw surface; an all-white compositor copy must
                // not overwrite a useful PrintWindow result.
                if (HasVisualRange(compositorBitmap))
                {
                    bitmap.Dispose();
                    bitmap = compositorBitmap;
                    compositorBitmap = null;
                    success = true;
                }
            }
            catch { }
            finally
            {
                if (compositorBitmap != null)
                    compositorBitmap.Dispose();
            }
        }
        if (raisedForAudit)
        {
            SetWindowPos(
                window, HwndNotTopmost, 0, 0, 0, 0,
                SwpNoMove | SwpNoSize | SwpNoActivate);
        }
        byte[] pixels = BitmapBytes(bitmap);
        string hash;
        using (SHA256 sha = SHA256.Create())
            hash = BitConverter.ToString(sha.ComputeHash(pixels))
                .Replace("-", "");
        bool nonBlank = success && HasVisualRange(pixels);
        int largestDarkComponent;
        double darkPixelRatio;
        AnalyzeMapDarkResidue(
            bitmap,
            out largestDarkComponent,
            out darkPixelRatio);
        return new CaptureResult
        {
            Bitmap = bitmap,
            Sha256 = hash,
            NonBlank = nonBlank,
            LargestDarkComponentPixels = largestDarkComponent,
            DarkPixelRatio = darkPixelRatio
        };
    }

    private static bool HasVisualRange(Bitmap bitmap)
    {
        return bitmap != null && HasVisualRange(BitmapBytes(bitmap));
    }

    private static bool HasVisualRange(byte[] pixels)
    {
        if (pixels == null || pixels.Length == 0)
            return false;
        byte minimum = byte.MaxValue;
        byte maximum = byte.MinValue;
        for (int index = 0; index < pixels.Length; index += 97)
        {
            minimum = Math.Min(minimum, pixels[index]);
            maximum = Math.Max(maximum, pixels[index]);
        }
        return maximum - minimum >= 16;
    }

    private static void AnalyzeMapDarkResidue(
        Bitmap bitmap,
        out int largestComponent,
        out double darkPixelRatio)
    {
        largestComponent = 0;
        darkPixelRatio = 0;
        if (bitmap == null || bitmap.Width <= 0 || bitmap.Height <= 80)
            return;

        int width = bitmap.Width;
        int mapHeight = bitmap.Height - 80;
        var area = new Rectangle(0, 0, width, bitmap.Height);
        BitmapData data = bitmap.LockBits(
            area, ImageLockMode.ReadOnly, PixelFormat.Format24bppRgb);
        try
        {
            int stride = Math.Abs(data.Stride);
            byte[] pixels = new byte[stride * bitmap.Height];
            Marshal.Copy(data.Scan0, pixels, 0, pixels.Length);
            bool[] dark = new bool[width * mapHeight];
            int darkCount = 0;
            for (int y = 0; y < mapHeight; ++y)
            {
                int sourceY =
                    data.Stride >= 0 ? y : bitmap.Height - 1 - y;
                int row = sourceY * stride;
                int output = y * width;
                for (int x = 0; x < width; ++x)
                {
                    int pixel = row + x * 3;
                    // The stale loading surface is exact or near black.
                    // A very low threshold avoids treating roof texture,
                    // shadows and night scenery as missing tiles.
                    bool isDark =
                        pixels[pixel] <= 4 &&
                        pixels[pixel + 1] <= 4 &&
                        pixels[pixel + 2] <= 4;
                    dark[output + x] = isDark;
                    if (isDark) ++darkCount;
                }
            }

            int[] queue = new int[dark.Length];
            for (int index = 0; index < dark.Length; ++index)
            {
                if (!dark[index]) continue;
                int head = 0;
                int tail = 0;
                int component = 0;
                dark[index] = false;
                queue[tail++] = index;
                while (head < tail)
                {
                    int current = queue[head++];
                    ++component;
                    int x = current % width;
                    int y = current / width;
                    int neighbor;
                    if (x > 0)
                    {
                        neighbor = current - 1;
                        if (dark[neighbor])
                        {
                            dark[neighbor] = false;
                            queue[tail++] = neighbor;
                        }
                    }
                    if (x + 1 < width)
                    {
                        neighbor = current + 1;
                        if (dark[neighbor])
                        {
                            dark[neighbor] = false;
                            queue[tail++] = neighbor;
                        }
                    }
                    if (y > 0)
                    {
                        neighbor = current - width;
                        if (dark[neighbor])
                        {
                            dark[neighbor] = false;
                            queue[tail++] = neighbor;
                        }
                    }
                    if (y + 1 < mapHeight)
                    {
                        neighbor = current + width;
                        if (dark[neighbor])
                        {
                            dark[neighbor] = false;
                            queue[tail++] = neighbor;
                        }
                    }
                }
                largestComponent =
                    Math.Max(largestComponent, component);
            }
            darkPixelRatio =
                dark.Length == 0
                    ? 0
                    : darkCount / (double)dark.Length;
        }
        finally
        {
            bitmap.UnlockBits(data);
        }
    }

    private static void ObserveRenderAudit(
        CaptureResult capture,
        string captureName,
        RenderAuditObservation observation)
    {
        if (capture == null ||
            capture.Bitmap == null ||
            !capture.NonBlank ||
            observation == null)
            return;

        bool complete =
            capture.LargestDarkComponentPixels < 50000 &&
            capture.DarkPixelRatio < 0.22;
        // Prefer a complete frame over an earlier corrupt frame, but never
        // let an all-white/occluded desktop copy count as render evidence.
        if (!observation.HasVisualCapture ||
            (complete && !observation.CompleteRender))
        {
            observation.HasVisualCapture = true;
            observation.CompleteRender = complete;
            observation.CaptureName = captureName;
            observation.LargestDarkComponentPixels =
                capture.LargestDarkComponentPixels;
            observation.DarkPixelRatio = capture.DarkPixelRatio;
            observation.MapPixels =
                capture.Bitmap.Width *
                Math.Max(1, capture.Bitmap.Height - 80);
        }
    }

    private static byte[] BitmapBytes(Bitmap bitmap)
    {
        var area = new Rectangle(0, 0, bitmap.Width, bitmap.Height);
        BitmapData data = bitmap.LockBits(
            area, ImageLockMode.ReadOnly, PixelFormat.Format24bppRgb);
        try
        {
            byte[] bytes = new byte[Math.Abs(data.Stride) * bitmap.Height];
            Marshal.Copy(data.Scan0, bytes, 0, bytes.Length);
            return bytes;
        }
        finally { bitmap.UnlockBits(data); }
    }

    private static double CompareCaptures(
        CaptureResult left, CaptureResult right)
    {
        if (left == null || right == null ||
            left.Bitmap == null || right.Bitmap == null ||
            left.Bitmap.Size != right.Bitmap.Size)
            return 0;
        byte[] a = BitmapBytes(left.Bitmap);
        byte[] b = BitmapBytes(right.Bitmap);
        long total = 0;
        long count = 0;
        for (int index = 0; index < a.Length; index += 48)
        {
            total += Math.Abs(a[index] - b[index]);
            ++count;
        }
        return count == 0 ? 0 : total / (count * 255.0);
    }

    private static void SaveCapture(
        CaptureResult capture, string path)
    {
        if (capture == null || capture.Bitmap == null)
            return;
        ImageCodecInfo codec = ImageCodecInfo.GetImageEncoders()
            .First(delegate(ImageCodecInfo item)
            {
                return item.FormatID == ImageFormat.Jpeg.Guid;
            });
        using (var parameters = new EncoderParameters(1))
        {
            parameters.Param[0] = new EncoderParameter(
                System.Drawing.Imaging.Encoder.Quality, 55L);
            capture.Bitmap.Save(path, codec, parameters);
        }
    }

    private static string ReadSharedText(string path)
    {
        if (!File.Exists(path)) return "";
        for (int attempt = 0; attempt < 5; ++attempt)
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

    private static bool HasPositiveCounter(string text, string marker)
    {
        int start = 0;
        while (text != null &&
               (start = text.IndexOf(
                   marker, start, StringComparison.Ordinal)) >= 0)
        {
            start += marker.Length;
            long value = 0;
            int digits = 0;
            while (start < text.Length &&
                   text[start] >= '0' && text[start] <= '9')
            {
                value = value * 10 + (text[start] - '0');
                ++start;
                ++digits;
            }
            if (digits > 0 && value > 0) return true;
        }
        return false;
    }

    private static long MaximumCounter(string text, string marker)
    {
        long maximum = -1;
        int start = 0;
        while (text != null &&
               (start = text.IndexOf(
                   marker, start, StringComparison.Ordinal)) >= 0)
        {
            start += marker.Length;
            long value = 0;
            int digits = 0;
            while (start < text.Length &&
                   text[start] >= '0' && text[start] <= '9')
            {
                value = value * 10 + (text[start] - '0');
                ++start;
                ++digits;
            }
            if (digits > 0)
                maximum = Math.Max(maximum, value);
        }
        return maximum;
    }

    private static long SumCounter(string text, string marker)
    {
        long total = 0;
        int start = 0;
        while (text != null &&
               (start = text.IndexOf(
                   marker, start, StringComparison.Ordinal)) >= 0)
        {
            start += marker.Length;
            long value = 0;
            int digits = 0;
            while (start < text.Length &&
                   text[start] >= '0' && text[start] <= '9')
            {
                value = value * 10 + (text[start] - '0');
                ++start;
                ++digits;
            }
            if (digits > 0)
                total += value;
        }
        return total;
    }

    private static double Percentile(
        IEnumerable<double> values, double percentile)
    {
        double[] ordered = values.OrderBy(delegate(double value)
        {
            return value;
        }).ToArray();
        if (ordered.Length == 0) return 0;
        int index = (int)Math.Ceiling(percentile * ordered.Length) - 1;
        return ordered[Math.Max(0, Math.Min(ordered.Length - 1, index))];
    }

    private static void CaptureParityCheckpoint(
        List<ParityCheckpoint> checkpoints,
        IntPtr process,
        long imageBase,
        Stopwatch clock,
        string checkpointId)
    {
        if (checkpoints == null || process == IntPtr.Zero)
            return;
        var checkpoint = new ParityCheckpoint();
        checkpoint.Id = checkpointId ?? "";
        checkpoint.ElapsedMilliseconds =
            clock == null ? 0 : clock.ElapsedMilliseconds;
        checkpoint.CameraX = ReadInt(
            process, imageBase + EngineAddresses.CameraX);
        checkpoint.CameraY = ReadInt(
            process, imageBase + EngineAddresses.CameraY);
        checkpoint.ViewportWidth = ReadInt(
            process, imageBase + EngineAddresses.ScreenWidth);
        checkpoint.ViewportHeight = Math.Max(
            0,
            ReadInt(
                process,
                imageBase + EngineAddresses.ScreenHeight) - 80);
        int viewportValue = ReadInt(
            process, imageBase + EngineAddresses.ViewportController);
        if (viewportValue > 0)
        {
            long viewport = (long)(uint)viewportValue;
            int width = ReadInt(process, viewport + 0x28);
            int height = ReadInt(process, viewport + 0x2C);
            if (width > 0 && width <= 8192)
                checkpoint.ViewportWidth = width;
            if (height > 0 && height <= 8192)
                checkpoint.ViewportHeight = height;
        }
        checkpoint.SourceEntityCount =
            ReadWorldActorCount(process, imageBase);
        foreach (ActorSnapshot actor in ReadTraceActors(
            process, imageBase))
            checkpoint.Actors.Add(actor);
        checkpoints.Add(checkpoint);
    }

    private static List<ActorSnapshot> ReadTraceActors(
        IntPtr process, long imageBase)
    {
        var result = new List<ActorSnapshot>();
        int worldValue = ReadInt(
            process, imageBase + EngineAddresses.WorldRoot);
        if (worldValue == 0 || worldValue == int.MinValue)
            return result;
        long world = (long)(uint)worldValue;
        int actorArrayValue = ReadInt(process, world + 0x18);
        int count = ReadInt(process, world + 0x3C);
        if (actorArrayValue == 0 ||
            actorArrayValue == int.MinValue ||
            count <= 0 ||
            count > 4096)
            return result;
        long actorArray = (long)(uint)actorArrayValue;
        for (int index = 0; index < count; ++index)
        {
            int actorValue = ReadInt(
                process, actorArray + index * 4L);
            if (actorValue == 0 || actorValue == int.MinValue)
                continue;
            ActorSnapshot snapshot = ReadActor(
                process, (long)(uint)actorValue);
            if (snapshot == null)
                continue;
            snapshot.SceneIndex = index;
            if (snapshot.Faction < 1 || snapshot.Faction > 3)
                continue;
            if (snapshot.RuntimeType < 0 ||
                snapshot.Direction < 0 ||
                snapshot.Direction > 8 ||
                snapshot.WorldX < -4096 ||
                snapshot.WorldY < -4096 ||
                snapshot.WorldX > 131072 ||
                snapshot.WorldY > 131072)
                continue;
            result.Add(snapshot);
        }
        return result;
    }

    private static void AttachObservedPositions(
        List<ParityCheckpoint> checkpoints,
        IEnumerable<Point> positions)
    {
        if (checkpoints == null ||
            checkpoints.Count == 0 ||
            positions == null)
            return;
        ParityCheckpoint checkpoint =
            checkpoints[checkpoints.Count - 1];
        foreach (Point position in positions)
            checkpoint.ObservedPositions.Add(position);
    }

    private static int RuntimeIndexForAddress(
        IEnumerable<ActorSnapshot> actors,
        long address)
    {
        if (address == 0 || actors == null)
            return -1;
        ActorSnapshot match = actors.FirstOrDefault(
            delegate(ActorSnapshot candidate)
            {
                return candidate.Address == address;
            });
        return match == null ? -1 : match.SceneIndex;
    }

    private static bool HasResolvedPlayerContact(
        IEnumerable<ParityCheckpoint> checkpoints,
        Dictionary<int, RuntimeActorIdentity> actorIdentities)
    {
        if (checkpoints == null || actorIdentities == null)
            return false;
        foreach (ParityCheckpoint checkpoint in checkpoints)
        {
            var playerAddresses = new HashSet<long>(
                checkpoint.Actors.Where(
                    delegate(ActorSnapshot actor)
                    {
                        RuntimeActorIdentity identity;
                        return actorIdentities.TryGetValue(
                                   actor.SceneIndex, out identity) &&
                               identity.VwfFactionId == 3;
                    }).Select(
                    delegate(ActorSnapshot actor)
                    {
                        return actor.Address;
                    }));
            if (playerAddresses.Count == 0)
                continue;
            foreach (ActorSnapshot actor in checkpoint.Actors)
            {
                RuntimeActorIdentity identity;
                if (!actorIdentities.TryGetValue(
                        actor.SceneIndex, out identity) ||
                    identity.VwfFactionId != 1)
                    continue;
                if (playerAddresses.Contains(actor.InterestAddress) ||
                    playerAddresses.Contains(actor.TargetAddress))
                    return true;
            }
        }
        return false;
    }

    private static int ResolvedSceneForRuntimeIndex(
        Dictionary<int, RuntimeActorIdentity> actorIdentities,
        int runtimeIndex)
    {
        RuntimeActorIdentity identity;
        return runtimeIndex >= 0 &&
               actorIdentities != null &&
               actorIdentities.TryGetValue(runtimeIndex, out identity)
            ? identity.SceneIndex
            : -1;
    }

    private static void WorldSizeForSelector(
        int selectorLevel,
        out int width,
        out int height,
        out int sourceEntityCount)
    {
        int[,] sizes =
        {
            { 4960, 2240, 1630 },
            { 4096, 4096, 2525 },
            { 3200, 1920, 898 },
            { 4096, 3200, 1254 },
            { 5440, 3200, 2721 },
            { 3840, 3200, 771 },
            { 3840, 3200, 1470 },
            { 4800, 3200, 2408 },
            { 2880, 1920, 805 },
            { 3200, 3200, 1720 },
            { 4800, 3360, 1629 },
            { 3200, 3200, 1368 }
        };
        int index = selectorLevel - 1;
        if (index < 0 || index >= sizes.GetLength(0))
        {
            width = 0;
            height = 0;
            sourceEntityCount = 0;
            return;
        }
        width = sizes[index, 0];
        height = sizes[index, 1];
        sourceEntityCount = sizes[index, 2];
    }

    private static void WriteParityTrace(
        string outputDirectory,
        int selectorLevel,
        int engineMission,
        int movementCellX,
        int movementCellY,
        int returnCellX,
        int returnCellY,
        List<ParityCheckpoint> checkpoints,
        string scenarioOverride,
        Dictionary<int, RuntimeActorIdentity> actorIdentities,
        bool resolvedEnemyScope,
        bool resolvedActorScope)
    {
        if (checkpoints == null || checkpoints.Count == 0)
            return;
        int worldWidth;
        int worldHeight;
        int sourceEntityCount;
        WorldSizeForSelector(
            selectorLevel,
            out worldWidth,
            out worldHeight,
            out sourceEntityCount);
        string levelId = String.Format(
            CultureInfo.InvariantCulture,
            "m{0:D3}",
            selectorLevel - 1);
        string scenarioId = scenarioOverride ?? "";
        if (String.IsNullOrWhiteSpace(scenarioId) &&
            selectorLevel == 1 &&
            movementCellX == 1 && movementCellY == 3 &&
            returnCellX == 5 && returnCellY == 3)
            scenarioId = "m000-basic-movement-v1";
        else if (String.IsNullOrWhiteSpace(scenarioId) &&
                 selectorLevel == 1 &&
                 movementCellX == 16 && movementCellY == 34 &&
                 returnCellX == 9 && returnCellY == 8)
            scenarioId = "m000-obstacle-route-v1";
        else if (String.IsNullOrWhiteSpace(scenarioId))
            scenarioId = selectorLevel == 1
                ? "m000-custom-movement-v1"
                : "level-smoke-v1";
        var json = new StringBuilder();
        json.Append("{\n");
        json.Append("  \"schema_version\": 1,\n");
        json.AppendFormat(
            CultureInfo.InvariantCulture,
            "  \"trace_id\": \"mod-{0}-{1}\",\n",
            levelId,
            scenarioId);
        json.Append("  \"runtime\": \"mod\",\n");
        json.Append(
            "  \"content_profile\": " +
            "\"repository-mod-12-level-20260729\",\n");
        json.AppendFormat(
            CultureInfo.InvariantCulture,
            "  \"level\": {{\"id\":\"{0}\"," +
            "\"selector_level\":{1},\"engine_mission\":{2}}},\n",
            levelId, selectorLevel, engineMission);
        json.AppendFormat(
            CultureInfo.InvariantCulture,
            "  \"scenario\": {{\"id\":\"{0}\"," +
            "\"coordinate_space\":\"legacy-world-pixels\"," +
            "\"description\":\"{1}\"}},\n",
            scenarioId,
            Escape(
                resolvedActorScope
                    ? "Natural player movement into enemy contact with " +
                      "audited runtime-to-VWF identities; no global " +
                      "cursor or focus API."
                    : resolvedEnemyScope
                        ? "Read-only enemy patrol observation with audited " +
                          "runtime-to-VWF identities; no global cursor or " +
                          "focus API."
                        : "Window-local selection and movement observation; " +
                          "no global cursor or focus API; cells " +
                          movementCellX + "," + movementCellY + " -> " +
                          returnCellX + "," + returnCellY + "."));
        json.Append(
            "  \"metadata\": {" +
            "\"producer\":\"ModRegressionProbe\"," +
            "\"input_isolation\":" +
            "\"window-message-to-process-local-DirectInput\"},\n");
        json.Append("  \"checkpoints\": [\n");
        for (int checkpointIndex = 0;
             checkpointIndex < checkpoints.Count;
             ++checkpointIndex)
        {
            ParityCheckpoint checkpoint =
                checkpoints[checkpointIndex];
            List<ActorSnapshot> outputActors;
            if (resolvedActorScope)
            {
                outputActors = checkpoint.Actors.Where(
                    delegate(ActorSnapshot actor)
                    {
                        return actorIdentities.ContainsKey(
                            actor.SceneIndex);
                    }).OrderBy(
                    delegate(ActorSnapshot actor)
                    {
                        return actorIdentities[
                            actor.SceneIndex].SceneIndex;
                    }).ToList();
            }
            else if (resolvedEnemyScope)
            {
                outputActors = checkpoint.Actors.Where(
                    delegate(ActorSnapshot actor)
                    {
                        RuntimeActorIdentity identity;
                        return actorIdentities.TryGetValue(
                                   actor.SceneIndex, out identity) &&
                               identity.VwfFactionId == 1;
                    }).OrderBy(
                    delegate(ActorSnapshot actor)
                    {
                        return actorIdentities[
                            actor.SceneIndex].SceneIndex;
                    }).ToList();
            }
            else
            {
                outputActors = selectorLevel == 1
                    ? checkpoint.Actors.Where(
                        delegate(ActorSnapshot actor)
                        {
                            return actor.Faction == 3;
                        }).ToList()
                    : checkpoint.Actors;
            }
            json.Append("    {\n");
            json.AppendFormat(
                CultureInfo.InvariantCulture,
                "      \"id\":\"{0}\",\"sequence\":{1}," +
                "\"elapsed_ms\":{2},\n",
                Escape(checkpoint.Id),
                checkpointIndex,
                Math.Max(
                    0,
                    checkpoint.ElapsedMilliseconds -
                    checkpoints[0].ElapsedMilliseconds));
            json.AppendFormat(
                CultureInfo.InvariantCulture,
                "      \"camera\":{{\"position\":[{0},{1}]," +
                "\"viewport\":[{2},{3}],\"zoom\":[1,1]}},\n",
                checkpoint.CameraX,
                checkpoint.CameraY,
                checkpoint.ViewportWidth,
                checkpoint.ViewportHeight);
            json.AppendFormat(
                CultureInfo.InvariantCulture,
                "      \"world\":{{\"size\":[{0},{1}]," +
                "\"tracked_actor_count\":{2}," +
                "\"source_entity_count\":{3}," +
                "\"runtime_object_count\":{4}}},\n",
                worldWidth,
                worldHeight,
                outputActors.Count,
                sourceEntityCount,
                checkpoint.SourceEntityCount);
            json.Append("      \"actors\": [\n");
            for (int actorIndex = 0;
                 actorIndex < outputActors.Count;
                 ++actorIndex)
            {
                ActorSnapshot actor =
                    outputActors[actorIndex];
                RuntimeActorIdentity identity;
                bool hasIdentity = actorIdentities.TryGetValue(
                    actor.SceneIndex, out identity);
                int traceSceneIndex = hasIdentity
                    ? identity.SceneIndex
                    : selectorLevel == 1 && actor.Faction == 3
                        ? 1436
                        : actor.SceneIndex;
                int traceDatabaseEntry = hasIdentity
                    ? identity.DatabaseEntryId
                    : selectorLevel == 1 && actor.Faction == 3
                        ? 924
                        : Math.Max(actor.RuntimeType, 0);
                int traceFaction = hasIdentity
                    ? identity.VwfFactionId
                    : actor.Faction;
                int targetX = actor.GoalKind == 1
                    ? actor.GoalX
                    : actor.WorldX;
                int targetY = actor.GoalKind == 1
                    ? actor.GoalY
                    : actor.WorldY;
                string role = resolvedActorScope
                    ? traceSceneIndex == 1436
                        ? "player"
                        : traceFaction == 1
                            ? "enemy"
                            : "escort"
                    : traceFaction == 3
                        ? "player"
                        : traceFaction == 2
                            ? "escort"
                            : "enemy";
                int interestRuntimeIndex = RuntimeIndexForAddress(
                    checkpoint.Actors, actor.InterestAddress);
                int targetRuntimeIndex = RuntimeIndexForAddress(
                    checkpoint.Actors, actor.TargetAddress);
                int interestSceneIndex = ResolvedSceneForRuntimeIndex(
                    actorIdentities, interestRuntimeIndex);
                int targetSceneIndex = ResolvedSceneForRuntimeIndex(
                    actorIdentities, targetRuntimeIndex);
                json.AppendFormat(
                    CultureInfo.InvariantCulture,
                    "        {{\"actor_id\":\"scene:{0}\"," +
                    "\"role\":\"{1}\",\"scene_index\":{0}," +
                    "\"database_entry_id\":{2}," +
                    "\"display_name\":\"{3}\"," +
                    "\"faction_id\":{4}," +
                    "\"position\":[{5},{6}]," +
                    "\"target_position\":[{7},{8}]," +
                    "\"facing_direction\":{9}," +
                    "\"alive\":{10}," +
                    "\"hit_points\":{{\"current\":{35}," +
                    "\"maximum\":{36}}}," +
                    "\"native\":{{\"goal_kind\":{11}," +
                    "\"command_variant\":{12}," +
                    "\"command_pending\":{13}," +
                    "\"movement_active\":{14}," +
                    "\"movement_path_state\":{15}," +
                    "\"movement_mode\":{16}," +
                    "\"resolved_goal_x\":{17}," +
                    "\"resolved_goal_y\":{18}," +
                    "\"path_override_active\":{19}," +
                    "\"runtime_index\":{20}," +
                    "\"runtime_type\":{21}," +
                    "\"target_status\":{22}," +
                    "\"selected_for_command\":{23}," +
                    "\"search_or_return_active\":{24}," +
                    "\"search_delay_limit\":{25}," +
                    "\"search_delay_counter\":{26}," +
                    "\"contact_state\":{27}," +
                    "\"target_lost\":{28}," +
                    "\"reaction_state\":{29}," +
                    "\"current_hit_points\":{35}," +
                    "\"default_attack_type\":{37}," +
                    "\"interest_runtime_index\":{30}," +
                    "\"interest_scene_index\":{31}," +
                    "\"target_runtime_index\":{32}," +
                    "\"target_scene_index\":{33}}}}}{34}\n",
                    traceSceneIndex,
                    role,
                    traceDatabaseEntry,
                    Escape(hasIdentity
                        ? identity.DisplayName
                        : ""),
                    traceFaction,
                    actor.WorldX,
                    actor.WorldY,
                    targetX,
                    targetY,
                    actor.Direction,
                    actor.Dead == 0 ? "true" : "false",
                    actor.GoalKind,
                    actor.CommandVariant,
                    actor.CommandPending,
                    actor.MovementActive,
                    actor.MovementPathState,
                    actor.MovementMode,
                    actor.ResolvedGoalX,
                    actor.ResolvedGoalY,
                    actor.PathOverrideActive,
                    actor.SceneIndex,
                    actor.RuntimeType,
                    actor.TargetStatus,
                    actor.SelectedForCommand,
                    actor.SearchOrReturnActive,
                    actor.SearchDelayLimit,
                    actor.SearchDelayCounter,
                    actor.ContactState,
                    actor.TargetLost,
                    actor.ReactionState,
                    interestRuntimeIndex,
                    interestSceneIndex,
                    targetRuntimeIndex,
                    targetSceneIndex,
                    actorIndex + 1 == outputActors.Count
                        ? ""
                        : ",",
                    actor.CurrentHitPoints,
                    hasIdentity
                        ? identity.AuthoredHitPoints
                        : actor.CurrentHitPoints,
                    actor.DefaultAttackType);
            }
            json.Append("      ],\n");
            json.AppendFormat(
                CultureInfo.InvariantCulture,
                "      \"mission\":{{\"id\":\"{0}\"," +
                "\"status\":\"active\"}},\n",
                levelId);
            json.Append(
                "      \"tags\":{" +
                "\"source\":\"stable-mod-read-only-process-snapshot\"");
            if (checkpoint.ObservedPositions.Count > 0)
            {
                json.Append(",\"observed_positions\":[");
                for (int sampleIndex = 0;
                     sampleIndex < checkpoint.ObservedPositions.Count;
                     ++sampleIndex)
                {
                    Point sample =
                        checkpoint.ObservedPositions[sampleIndex];
                    json.AppendFormat(
                        CultureInfo.InvariantCulture,
                        "[{0},{1}]{2}",
                        sample.X,
                        sample.Y,
                        sampleIndex + 1 ==
                            checkpoint.ObservedPositions.Count
                            ? ""
                            : ",");
                }
                json.Append("]");
            }
            json.Append("}\n");
            json.Append(
                checkpointIndex + 1 == checkpoints.Count
                    ? "    }\n"
                    : "    },\n");
        }
        json.Append("  ]\n");
        json.Append("}\n");
        File.WriteAllText(
            Path.Combine(
                outputDirectory,
                selectorLevel == 1
                    ? "mod-" + scenarioId + ".json"
                    : "mod-level-smoke-v1.json"),
            json.ToString(),
            new UTF8Encoding(false));
    }

    private static void WriteArtifacts(
        string outputDirectory, int selectorLevel, int engineMission,
        List<Stage> stages, List<PerfSample> perf,
        bool transitionsLogged, bool replayConsumed, bool passed)
    {
        PerfSample[] samples;
        lock (perf) samples = perf.ToArray();
        double elapsed = samples.Length >= 2
            ? samples[samples.Length - 1].TimeMilliseconds -
              samples[0].TimeMilliseconds : 0;
        double cpu = samples.Length >= 2
            ? samples[samples.Length - 1].CpuMilliseconds -
              samples[0].CpuMilliseconds : 0;
        ulong reads = samples.Length >= 2
            ? samples[samples.Length - 1].ReadBytes -
              samples[0].ReadBytes : 0;
        double[] compositor = samples
            .Select(delegate(PerfSample sample)
            {
                return sample.CompositorWaitMilliseconds;
            }).Where(delegate(double value) { return value > 0; })
            .ToArray();
        int cursorClipRestricted = samples.Count(
            delegate(PerfSample sample)
            {
                return sample.CursorClipRestricted;
            });

        var json = new StringBuilder();
        json.Append("{\n");
        json.AppendFormat(
            CultureInfo.InvariantCulture,
            "  \"schema\": 1,\n  \"selector_level\": {0},\n" +
            "  \"engine_mission\": {1},\n  \"passed\": {2},\n",
            selectorLevel, engineMission, passed ? "true" : "false");
        json.AppendFormat(
            CultureInfo.InvariantCulture,
            "  \"transitions_logged\": {0},\n" +
            "  \"replay_consumed\": {1},\n",
            transitionsLogged ? "true" : "false",
            replayConsumed ? "true" : "false");
        json.Append("  \"stages\": [\n");
        for (int index = 0; index < stages.Count; ++index)
        {
            Stage stage = stages[index];
            json.Append("    {");
            json.AppendFormat(
                CultureInfo.InvariantCulture,
                "\"name\":\"{0}\",\"sent\":{1}," +
                "\"responding\":{2},\"mission\":{3}," +
                "\"elapsed_ms\":{4},\"evidence\":\"{5}\"",
                Escape(stage.Name), stage.Sent ? "true" : "false",
                stage.ProcessResponding ? "true" : "false",
                stage.Mission, stage.ElapsedMilliseconds,
                Escape(stage.Evidence));
            json.Append(index + 1 == stages.Count ? "}\n" : "},\n");
        }
        json.Append("  ],\n");
        json.AppendFormat(
            CultureInfo.InvariantCulture,
            "  \"performance\": {{\"samples\":{0}," +
            "\"cpu_one_core_percent\":{1:F2}," +
            "\"disk_read_bytes\":{2}," +
            "\"unresponsive_samples\":{3}," +
            "\"cursor_clip_restricted_samples\":{5}," +
            "\"compositor_wait_p95_ms\":{4:F3},",
            samples.Length,
            elapsed <= 0 ? 0 : cpu / elapsed * 100.0,
            reads,
            samples.Count(delegate(PerfSample sample)
            {
                return !sample.Responding;
            }),
            Percentile(compositor, 0.95),
            cursorClipRestricted);
        json.Append("\"compositor_wait_p99_ms\":");
        json.Append(Percentile(compositor, 0.99).ToString(
            "F3", CultureInfo.InvariantCulture));
        json.Append("}\n");
        json.Append("}\n");
        File.WriteAllText(
            Path.Combine(outputDirectory, "result.json"),
            json.ToString(), new UTF8Encoding(false));

        var markdown = new StringBuilder();
        markdown.AppendLine(
            "# Level " + selectorLevel + " Isolated Regression");
        markdown.AppendLine();
        markdown.AppendLine("- Result: " + (passed ? "pass" : "fail"));
        markdown.AppendLine(
            "- Input: game-window messages only; no global mouse/focus API");
        markdown.AppendLine("- Engine mission: " + engineMission);
        markdown.AppendLine("- Process reads: " + reads + " bytes");
        markdown.AppendLine(
            "- Cursor clip restricted samples: " +
            cursorClipRestricted);
        markdown.AppendLine(string.Format(
            CultureInfo.InvariantCulture,
            "- Compositor wait P95/P99: {0:F3}/{1:F3} ms",
            Percentile(compositor, 0.95),
            Percentile(compositor, 0.99)));
        markdown.AppendLine();
        markdown.AppendLine("| Stage | Sent | Responding | Evidence |");
        markdown.AppendLine("|---|---:|---:|---|");
        foreach (Stage stage in stages)
            markdown.AppendLine("| " + stage.Name + " | " +
                (stage.Sent ? "yes" : "no") + " | " +
                (stage.ProcessResponding ? "yes" : "no") + " | " +
                stage.Evidence.Replace("|", "\\|") + " |");
        File.WriteAllText(
            Path.Combine(outputDirectory, "result.md"),
            markdown.ToString(), new UTF8Encoding(false));
    }

    private static string Escape(string value)
    {
        return (value ?? "").Replace("\\", "\\\\")
            .Replace("\"", "\\\"")
            .Replace("\r", "\\r").Replace("\n", "\\n");
    }

    private static void StopLaunchedGame(Process game)
    {
        if (game.HasExited) return;
        try { game.CloseMainWindow(); }
        catch { }
        if (game.WaitForExit(1200)) return;
        try { game.Kill(); game.WaitForExit(1200); }
        catch { }
    }
}
