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
    private const uint Th32csSnapModule = 0x00000008;
    private const uint Th32csSnapModule32 = 0x00000010;
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
    private const int ReplaySeedWorldItem = 10;
    private const int ReplaySpawnWorldItem = 11;
    private const int ReplayCompleteGumingDisguise = 13;
    private const int ReplaySelectWeaponInventoryItem = 14;
    private const int ReplayCommitSpecialAttention = 15;
    private const uint WmActivate = 0x0006;
    private const uint WmSetFocus = 0x0007;
    private const uint WmActivateApp = 0x001C;
    private const int DikF1 = 0x3B;
    private const int DikF2 = 0x3C;
    private const int DikF3 = 0x3D;
    private const int DikF4 = 0x3E;
    private const int DikF5 = 0x3F;
    private const int DikF6 = 0x40;
    private const int DikM = 0x32;
    private const int DikDigit1 = 0x02;
    private const int DikDigit2 = 0x03;
    private const int DikDigit3 = 0x04;
    private const int DikDigit4 = 0x05;
    private const int DikDigit5 = 0x06;
    private const int DikDigit6 = 0x07;
    private const int DikDigit7 = 0x08;
    private const int DikDigit8 = 0x09;
    private const int DikDigit9 = 0x0A;
    private const int DikDigit0 = 0x0B;
    private const int DikLeftControl = 0x1D;
    private const int DikS = 0x1F;
    private const int DikW = 0x11;
    private const int DikB = 0x30;
    private const int DikUp = 0xC8;
    private const int DikLeft = 0xCB;
    private const int DikRight = 0xCD;
    private const int DikDown = 0xD0;
    private const int SmXVirtualScreen = 76;
    private const int SmYVirtualScreen = 77;
    private const int SmCxVirtualScreen = 78;
    private const int SmCyVirtualScreen = 79;
    private const int ActorSpritePrimaryXOffset = 0x044;
    private const int ActorSpritePrimaryZOffset = 0x04C;
    private const int ActorSpriteWidthOffset = 0x05C;
    private const int ActorSpriteHeightOffset = 0x060;
    private const int ActorRuntimeTypeOffset = 0x064;
    private const int ActorFactionOffset = 0x074;
    private const int ActorWorldXOffset = 0x0D8;
    private const int ActorWorldYOffset = 0x0E0;
    private const int ActorPreviousWorldXOffset = 0x0F0;
    private const int ActorPreviousWorldYOffset = 0x0F8;
    private const int ActorWorldItemPlayerSelectedOffset = 0x168;
    private const int ActorStationaryTickCounterOffset = 0x16C;
    private const int ActorStationaryTickLimitOffset = 0x170;
    private const int ActorFacingDirectionOffset = 0x178;
    private const int ActorRouteUpdateActiveOffset = 0x184;
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
    private const int ActorItemInventoryAddressOffset = 0x228;
    private const int ActorInventoryAddressOffset = 0x22C;
    private const int ActorHypnosisActiveOffset = 0x238;
    private const int ActorPursuitAddressOffset = 0x23C;
    private const int ActorSearchDelayLimitOffset = 0x248;
    private const int ActorSearchDelayCounterOffset = 0x24C;
    private const int ActorContactStateOffset = 0x250;
    private const int ActorTargetLostOffset = 0x254;
    private const int ActorReactionStateOffset = 0x25C;
    private const int ActorPoisonActiveOffset = 0x264;
    private const int ActorPoisonCounterOffset = 0x268;
    private const int ActorPoisonCounterLimitOffset = 0x26C;
    private const int ActorHypnosisCounterLimitOffset = 0x278;
    private const int ActorHypnosisCounterOffset = 0x27C;
    private const int ActorPathOverrideActiveOffset = 0x290;
    private const int ActorPursuitDelayCounterOffset = 0x29C;
    private const long HoverWorldXRelativeAddress = 0x000E7014L;
    private const long HoverWorldYRelativeAddress = 0x000E7018L;
    private const long HoverCommandArmedRelativeAddress = 0x000E7034L;
    private const long HoverTargetStatusRelativeAddress = 0x000E7038L;
    private const long HoverTargetAddressRelativeAddress = 0x000E7040L;
    private const int M001PlayerSceneIndex = 2280;
    private const int M001MineRuntimeType = 43;
    private const int M001MineItemId = 43;
    private const int M001MineWorldX = 283;
    private const int M001MineWorldY = 475;

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

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct ModuleEntry32
    {
        public uint Size;
        public uint ModuleId;
        public uint ProcessId;
        public uint GlobalUsageCount;
        public uint ProcessUsageCount;
        public IntPtr BaseAddress;
        public uint BaseSize;
        public IntPtr ModuleHandle;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)]
        public string ModuleName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)]
        public string ExecutablePath;
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

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr CreateToolhelp32Snapshot(
        uint flags, uint processId);

    [DllImport(
        "kernel32.dll",
        CharSet = CharSet.Unicode,
        SetLastError = true,
        EntryPoint = "Module32FirstW")]
    private static extern bool Module32First(
        IntPtr snapshot, ref ModuleEntry32 entry);

    [DllImport(
        "kernel32.dll",
        CharSet = CharSet.Unicode,
        SetLastError = true,
        EntryPoint = "Module32NextW")]
    private static extern bool Module32Next(
        IntPtr snapshot, ref ModuleEntry32 entry);

    [DllImport("kernel32.dll")]
    private static extern bool GetProcessIoCounters(
        IntPtr process, out IoCounters counters);

    [DllImport("kernel32.dll")]
    private static extern uint GetTickCount();

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
        public int PreviousWorldX;
        public int PreviousWorldY;
        public int StationaryTickCounter;
        public int StationaryTickLimit;
        public int Direction;
        public int RouteUpdateActive;
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
        public int WorldItemPlayerSelected;
        public int HypnosisActive;
        public long PursuitAddress;
        public int PursuitDelayCounter;
        public int HypnosisCounter;
        public int HypnosisCounterLimit;
        public int PoisonActive;
        public int PoisonCounter;
        public int PoisonCounterLimit;
        public int PathOverrideActive;
        public bool InventoryCaptured;
        public readonly List<InventoryEntry> WeaponEntries =
            new List<InventoryEntry>();
        public readonly List<InventoryEntry> ItemEntries =
            new List<InventoryEntry>();
    }

    private sealed class InventoryEntry
    {
        public int InventoryIndex;
        public int ItemId;
        public int Quantity;
        public int QuantityMode;
    }

    private sealed class ParityCheckpoint
    {
        public string Id;
        public long ElapsedMilliseconds;
        public int CurrentActionId;
        public int CameraX;
        public int CameraY;
        public int ViewportWidth;
        public int ViewportHeight;
        public int SourceEntityCount;
        public int RuntimeType78Count;
        public int RuntimeType90Count;
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

    private sealed class WeaponAttackParityScenario
    {
        public string Id;
        public string Description;
        public string StageName;
        public int SelectorLevel;
        public int PlayerSceneIndex;
        public int PlayerSelectionDik;
        public int WeaponSelectionDik;
        public int AttackType;
        public int ItemId;
        public int ExpectedBeforeQuantity;
        public int ExpectedAfterQuantity;
        public int TargetSceneIndex;
        public int PlayerSlotIndex;
        public bool CompleteGumingDisguise;
        public bool SelectWeaponPanelItem;
        public int ExpectedRuntimeType;
        public bool UsesWorldPoint;
        public bool UsesTargetWorldOrigin;
        public int TargetWorldX;
        public int TargetWorldY;
        public bool RequiresTargetDamage;
        public bool RequiresTargetAttentionHold;
        public bool ForceTarget;
        public bool CommitSpecialAttentionViaReplay;
    }

    private sealed class WorldItemParityScenario
    {
        public string Id;
        public string Description;
        public string StageName;
        public int SelectorLevel;
        public int TargetSceneIndex;
        public int ItemId;
        public int ExpectedBeforeQuantity;
        public int ExpectedAfterQuantity;
        public bool Hypnosis;
        public bool Poison;
        public bool Distraction;
    }

    public static int Main(string[] args)
    {
        if (args.Length < 3)
        {
            Console.Error.WriteLine(
                "Usage: ModRegressionProbe.exe GAME_DIR OUTPUT_DIR LEVEL " +
                "[SECONDS] [MOVEMENT_CELL_X MOVEMENT_CELL_Y " +
                "[RETURN_CELL_X RETURN_CELL_Y]] " +
                "[--briefing-only | --briefing-dismissal-only] " +
                "[--crt-random-startup-only] " +
                "[--crt-random-runtime-only " +
                "--crt-random-runtime-ms=MS] " +
                "[--movement-only] " +
                "[--movement-player-scene=SCENE_INDEX] " +
                "[--movement-observation-ms=MS] " +
                "[--inventory-only] " +
                "[--visual-capture-only " +
                "--visual-camera-x=X --visual-camera-y=Y] " +
                "[--identity-catalog=PATH --parity-patrol-only | " +
                "--parity-contact-only | --parity-pickup-only | " +
                "--parity-attack-only | --parity-world-item-only | " +
                "--parity-sb-only " +
                "--parity-scenario=ID " +
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
        bool briefingDismissalOnly = args.Any(delegate(string argument)
        {
            return argument.Equals(
                "--briefing-dismissal-only",
                StringComparison.OrdinalIgnoreCase);
        });
        bool crtRandomStartupOnly = args.Any(delegate(string argument)
        {
            return argument.Equals(
                "--crt-random-startup-only",
                StringComparison.OrdinalIgnoreCase);
        });
        bool crtRandomRuntimeOnly = args.Any(delegate(string argument)
        {
            return argument.Equals(
                "--crt-random-runtime-only",
                StringComparison.OrdinalIgnoreCase);
        });
        int crtRandomRuntimeMilliseconds = 12500;
        string crtRandomRuntimeValue = ArgumentValue(
            args, "--crt-random-runtime-ms=");
        int parsedCrtRandomRuntimeMilliseconds;
        if (!String.IsNullOrWhiteSpace(crtRandomRuntimeValue) &&
            int.TryParse(
                crtRandomRuntimeValue,
                NumberStyles.Integer,
                CultureInfo.InvariantCulture,
                out parsedCrtRandomRuntimeMilliseconds))
        {
            crtRandomRuntimeMilliseconds = Math.Max(
                1000,
                Math.Min(60000, parsedCrtRandomRuntimeMilliseconds));
        }
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
        bool visualCaptureOnly = args.Any(delegate(string argument)
        {
            return argument.Equals(
                "--visual-capture-only",
                StringComparison.OrdinalIgnoreCase);
        });
        int visualCameraX = -1;
        int visualCameraY = -1;
        string visualCameraXValue = ArgumentValue(
            args, "--visual-camera-x=");
        string visualCameraYValue = ArgumentValue(
            args, "--visual-camera-y=");
        if (!String.IsNullOrWhiteSpace(visualCameraXValue) &&
            !int.TryParse(
                visualCameraXValue,
                NumberStyles.Integer,
                CultureInfo.InvariantCulture,
                out visualCameraX))
        {
            throw new InvalidOperationException(
                "Visual camera X must be an integer.");
        }
        if (!String.IsNullOrWhiteSpace(visualCameraYValue) &&
            !int.TryParse(
                visualCameraYValue,
                NumberStyles.Integer,
                CultureInfo.InvariantCulture,
                out visualCameraY))
        {
            throw new InvalidOperationException(
                "Visual camera Y must be an integer.");
        }
        if ((visualCameraX >= 0) != (visualCameraY >= 0))
        {
            throw new InvalidOperationException(
                "Visual camera coordinates must be supplied as an X/Y pair.");
        }
        int movementPlayerSceneIndex = -1;
        string movementPlayerSceneValue = ArgumentValue(
            args, "--movement-player-scene=");
        if (!String.IsNullOrWhiteSpace(movementPlayerSceneValue) &&
            (!int.TryParse(
                movementPlayerSceneValue,
                NumberStyles.Integer,
                CultureInfo.InvariantCulture,
                out movementPlayerSceneIndex) ||
             movementPlayerSceneIndex < 0))
        {
            throw new InvalidOperationException(
                "Movement player scene index must be a non-negative integer.");
        }
        int movementObservationMilliseconds =
            selectorLevel == 1 ? 750 : 1800;
        string movementObservationValue = ArgumentValue(
            args, "--movement-observation-ms=");
        int parsedMovementObservationMilliseconds;
        if (!String.IsNullOrWhiteSpace(movementObservationValue) &&
            int.TryParse(
                movementObservationValue,
                NumberStyles.Integer,
                CultureInfo.InvariantCulture,
                out parsedMovementObservationMilliseconds))
        {
            movementObservationMilliseconds = Math.Max(
                500,
                Math.Min(
                    10000,
                    parsedMovementObservationMilliseconds));
        }
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
        bool parityPickupOnly = args.Any(delegate(string argument)
        {
            return argument.Equals(
                "--parity-pickup-only",
                StringComparison.OrdinalIgnoreCase);
        });
        bool parityAttackOnly = args.Any(delegate(string argument)
        {
            return argument.Equals(
                "--parity-attack-only",
                StringComparison.OrdinalIgnoreCase);
        });
        bool parityWorldItemOnly = args.Any(delegate(string argument)
        {
            return argument.Equals(
                "--parity-world-item-only",
                StringComparison.OrdinalIgnoreCase);
        });
        bool paritySbOnly = args.Any(delegate(string argument)
        {
            return argument.Equals(
                "--parity-sb-only",
                StringComparison.OrdinalIgnoreCase);
        });
        bool actorLayoutDump = args.Any(delegate(string argument)
        {
            return argument.Equals(
                "--actor-layout-dump",
                StringComparison.OrdinalIgnoreCase);
        });
        int parityModeCount =
            (parityPatrolOnly ? 1 : 0) +
            (parityContactOnly ? 1 : 0) +
            (parityPickupOnly ? 1 : 0) +
            (parityAttackOnly ? 1 : 0) +
            (parityWorldItemOnly ? 1 : 0) +
            (paritySbOnly ? 1 : 0);
        if (parityModeCount > 1)
        {
            throw new InvalidOperationException(
                "Parity-only scenarios are mutually exclusive.");
        }
        if (briefingOnly && briefingDismissalOnly)
        {
            throw new InvalidOperationException(
                "Briefing-only and briefing-dismissal-only are mutually " +
                "exclusive.");
        }
        if ((crtRandomStartupOnly || crtRandomRuntimeOnly) &&
            (briefingOnly || briefingDismissalOnly ||
             movementOnly || inventoryOnly ||
             visualCaptureOnly || parityModeCount > 0))
        {
            throw new InvalidOperationException(
                "CRT-random capture cannot be combined with another " +
                "specialized probe mode.");
        }
        if (crtRandomStartupOnly && crtRandomRuntimeOnly)
        {
            throw new InvalidOperationException(
                "CRT-random startup and runtime modes are mutually exclusive.");
        }
        if (inventoryOnly &&
            (briefingOnly || briefingDismissalOnly ||
             parityModeCount > 0))
        {
            throw new InvalidOperationException(
                "Inventory-only cannot be combined with briefing-only " +
                "or parity movement scenarios.");
        }
        if (visualCaptureOnly &&
            (briefingOnly || briefingDismissalOnly ||
             movementOnly || inventoryOnly ||
             parityModeCount > 0))
        {
            throw new InvalidOperationException(
                "Visual-capture-only cannot be combined with another " +
                "specialized probe mode.");
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
        int movementPlayerRuntimeIndex = -1;
        int movementPlayerSelectionDik = DikF4;
        if (movementPlayerSceneIndex >= 0)
        {
            RuntimeActorIdentity movementPlayerIdentity =
                actorIdentities.Values.FirstOrDefault(
                    delegate(RuntimeActorIdentity identity)
                    {
                        return identity.SceneIndex ==
                            movementPlayerSceneIndex;
                    });
            if (movementPlayerIdentity == null ||
                movementPlayerIdentity.VwfFactionId != 3)
            {
                throw new InvalidOperationException(
                    "Movement player scene is not a resolved friendly actor.");
            }
            movementPlayerRuntimeIndex =
                movementPlayerIdentity.RuntimeIndex;
            movementPlayerSelectionDik =
                PlayerSelectionDik(
                    movementPlayerIdentity.DisplayName);
        }
        if (parityModeCount > 0 &&
            actorIdentities.Count == 0)
        {
            throw new InvalidOperationException(
                "Actor parity scenarios require a non-empty " +
                "--identity-catalog.");
        }
        if (parityPickupOnly && selectorLevel != 2)
        {
            throw new InvalidOperationException(
                "The audited mine pickup scenario requires selector level 2.");
        }
        if (parityAttackOnly)
            ResolveWeaponAttackParityScenario(
                parityScenarioOverride,
                selectorLevel);
        if (parityWorldItemOnly)
            ResolveWorldItemParityScenario(
                parityScenarioOverride,
                selectorLevel);
        if (paritySbOnly)
            ValidateSbParityScenario(
                parityScenarioOverride,
                selectorLevel);
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
        if (briefingOnly || briefingDismissalOnly)
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
                string briefingSurfaceHash = "";
                bool briefingSurfaceNonBlank = false;
                string briefingSurfaceEvidence = "";
                int briefingSurfaceWidth = ReadInt(
                    process, imageBase + EngineAddresses.ScreenWidth);
                int briefingSurfaceHeight = ReadInt(
                    process, imageBase + EngineAddresses.ScreenHeight);
                if (briefingSurfaceWidth < 320 ||
                    briefingSurfaceWidth > 4096)
                    briefingSurfaceWidth = 1024;
                if (briefingSurfaceHeight < 200 ||
                    briefingSurfaceHeight > 2160)
                    briefingSurfaceHeight = 768;
                using (CaptureResult briefingSurface =
                    CaptureCncDdrawPrimarySurface(
                        game,
                        process,
                        briefingSurfaceWidth,
                        briefingSurfaceHeight,
                        out briefingSurfaceEvidence))
                {
                    if (briefingSurface != null)
                    {
                        briefingSurfaceHash = briefingSurface.Sha256;
                        briefingSurfaceNonBlank =
                            briefingSurface.NonBlank;
                        SaveCapture(
                            briefingSurface,
                            Path.Combine(
                                outputDirectory,
                                "00-text-briefing-surface.jpg"));
                    }
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
                        ((briefingOnly || briefingDismissalOnly)
                            ? briefingActors == 0 &&
                              (briefingSurfaceNonBlank ||
                               (briefing != null &&
                                briefing.NonBlank))
                            : briefingActors > 0 ||
                              briefingSurfaceNonBlank ||
                              (briefing != null &&
                               briefing.NonBlank)),
                        "same_main_window=true; external_dialog=false; " +
                        "world_actors=" + briefingActors +
                        "; automated_skip=" + (briefingActors > 0) +
                        "; window_non_blank=" +
                        (briefing != null && briefing.NonBlank) +
                        "; window_hash=" +
                        (briefing == null ? "" : briefing.Sha256) +
                        "; surface_non_blank=" +
                        briefingSurfaceNonBlank +
                        "; surface_hash=" + briefingSurfaceHash +
                        "; " + briefingSurfaceEvidence);
                }
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
                bool briefingStateAdvanced = WaitUntil(
                    delegate()
                    {
                        return ReadWorldActorCount(
                            process, imageBase) > 0;
                    },
                    TimeSpan.FromSeconds(Math.Min(
                        12.0, Math.Max(4.0, maximumSeconds * 0.2))));
                bool briefingVisualChanged = false;
                string missionMenuHash = "";
                string missionMenuSurfaceHash = "";
                bool missionMenuSurfaceNonBlank = false;
                string missionMenuSurfaceEvidence = "";
                using (CaptureResult missionMenuSurface =
                    CaptureCncDdrawPrimarySurface(
                        game,
                        process,
                        briefingSurfaceWidth,
                        briefingSurfaceHeight,
                        out missionMenuSurfaceEvidence))
                {
                    if (missionMenuSurface != null)
                    {
                        missionMenuSurfaceHash =
                            missionMenuSurface.Sha256;
                        missionMenuSurfaceNonBlank =
                            missionMenuSurface.NonBlank;
                        briefingVisualChanged =
                            missionMenuSurface.NonBlank &&
                            !String.Equals(
                                briefingSurfaceHash,
                                missionMenuSurface.Sha256,
                                StringComparison.OrdinalIgnoreCase);
                        SaveCapture(
                            missionMenuSurface,
                            Path.Combine(
                                outputDirectory,
                                "01-mission-menu-surface.jpg"));
                    }
                using (CaptureResult missionMenu = CaptureWindow(window))
                {
                    missionMenuHash =
                        missionMenu == null ? "" : missionMenu.Sha256;
                    briefingVisualChanged =
                        briefingVisualChanged ||
                        (missionMenu != null &&
                         missionMenu.NonBlank &&
                         !String.Equals(
                             briefingCaptureHash,
                             missionMenu.Sha256,
                             StringComparison.OrdinalIgnoreCase));
                    SaveCapture(
                        missionMenu,
                        Path.Combine(
                            outputDirectory, "01-mission-menu.jpg"));
                }
                }
                AddStage(
                    stages, game, process, imageBase, clock,
                    "briefing_dismissed",
                    briefingContinueSent &&
                    (briefingStateAdvanced ||
                     briefingVisualChanged),
                    "process_local_mouse=true; visual_changed=" +
                    briefingVisualChanged +
                    "; world_state_advanced=" +
                    briefingStateAdvanced +
                    "; window_briefing_hash=" +
                    briefingCaptureHash +
                    "; window_mission_menu_hash=" +
                    missionMenuHash +
                    "; surface_briefing_hash=" +
                    briefingSurfaceHash +
                    "; surface_mission_menu_hash=" +
                    missionMenuSurfaceHash +
                    "; surface_non_blank=" +
                    missionMenuSurfaceNonBlank +
                    "; " + missionMenuSurfaceEvidence);
                if (briefingDismissalOnly)
                {
                    samplerStop = true;
                    sampler.Join(1500);
                    bool briefingDismissalCursorClipSafe;
                    lock (perf)
                        briefingDismissalCursorClipSafe = perf.All(
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
                        briefingDismissalCursorClipSafe ? 0 : 1;
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
                if (crtRandomStartupOnly)
                {
                    // The proxy's test-only rand() hook writes to a memory
                    // ring and the asynchronous telemetry thread. Give the
                    // target process a short local pump window after the
                    // complete actor table becomes visible, then stop before
                    // player input or long-running AI can make the startup
                    // sequence timing-dependent.
                    Thread.Sleep(750);
                    WriteActorStateSnapshot(
                        process,
                        imageBase,
                        Path.Combine(
                            outputDirectory,
                            "actor-states-crt-startup.csv"));
                    samplerStop = true;
                    sampler.Join(1500);
                    bool startupCursorClipSafe;
                    lock (perf)
                        startupCursorClipSafe = perf.All(
                            delegate(PerfSample sample)
                            {
                                return !sample.CursorClipRestricted;
                            });
                    exitCode =
                        missionStarted &&
                        actorCount > 0 &&
                        startupCursorClipSafe ? 0 : 1;
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
                        int currentCameraX = ReadInt(
                            process,
                            imageBase + EngineAddresses.CameraX);
                        int currentCameraY = ReadInt(
                            process,
                            imageBase + EngineAddresses.CameraY);
                        return FindPlayerActorInViewport(
                            process,
                            imageBase,
                            currentCameraX,
                            currentCameraY,
                            1024,
                            688) != null;
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
                int gameplayWorldWidth = viewportController > 0
                    ? ReadInt(process, viewportAddress + 0x54)
                    : -1;
                int gameplayWorldHeight = viewportController > 0
                    ? ReadInt(process, viewportAddress + 0x58)
                    : -1;
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
                ActorSnapshot cameraPlayer =
                    FindPlayerActorInViewport(
                        process,
                        imageBase,
                        spawnCameraX,
                        spawnCameraY,
                        gameplayViewportWidth,
                        gameplayViewportHeight);
                bool cameraShowsPlayer =
                    cameraStateSynchronized &&
                    cameraPlayer != null;
                AddStage(
                    stages, game, process, imageBase, clock,
                    "initial_camera_synchronized",
                    cameraStateSynchronized,
                    "camera=(" + spawnCameraX + "," +
                    spawnCameraY + "); viewport=(" +
                    gameplayViewportWidth + "," +
                    gameplayViewportHeight + "); render=(" +
                    spawnScreenWidth + "," + spawnScreenHeight +
                    "); world=(" + gameplayWorldWidth + "," +
                    gameplayWorldHeight + "); player_visible=" +
                    cameraShowsPlayer);
                AddStage(
                    stages, game, process, imageBase, clock,
                    "initial_camera_contains_player",
                    cameraShowsPlayer,
                    cameraPlayer == null
                        ? "no live friendly actor was inside the " +
                          "initial viewport"
                        : "camera=(" + spawnCameraX + "," +
                          spawnCameraY + "); visible_player=(" +
                          cameraPlayer.WorldX + "," +
                          cameraPlayer.WorldY +
                          "); runtime_index=" +
                          cameraPlayer.SceneIndex +
                          "; runtime_type=" +
                          cameraPlayer.RuntimeType +
                          "; viewport=(" +
                          gameplayViewportWidth + "," +
                          gameplayViewportHeight +
                          "); render=(" + spawnScreenWidth + "," +
                          spawnScreenHeight + "); synchronized=" +
                          cameraStateSynchronized);

                if (visualCaptureOnly)
                {
                    bool requestedCameraReady = true;
                    int visualCameraLeft = spawnCameraX;
                    int visualCameraTop = spawnCameraY;
                    if (visualCameraX >= 0 && visualCameraY >= 0)
                    {
                        requestedCameraReady =
                            PanReplayCameraToWorldPoint(
                                process,
                                imageBase,
                                window,
                                visualCameraX,
                                visualCameraY,
                                spawnScreenWidth,
                                spawnScreenHeight,
                                1200,
                                out visualCameraLeft,
                                out visualCameraTop);
                    }
                    // The RGB565 primary surface can briefly contain a
                    // strip-scroll intermediate frame (HUD rows copied into
                    // the world) after a camera jump. A rare startup race can
                    // also return to the mostly-black main menu after the
                    // process state has already reported a resumed mission.
                    // Sample for several original 30 Hz composition cycles
                    // and only accept a nonblank, spatially complete gameplay
                    // surface. The caller retries with a fresh isolated
                    // process if the game has genuinely fallen back to menu.
                    Thread.Sleep(1000);
                    string copiedScreenshot = Path.Combine(
                        outputDirectory,
                        "02-gameplay-surface.png");
                    string surfaceEvidence = "";
                    bool surfaceCaptured = false;
                    DateTime visualDeadline =
                        DateTime.UtcNow.AddSeconds(5);
                    do
                    {
                        string candidateEvidence;
                        using (CaptureResult candidate =
                            CaptureCncDdrawPrimarySurface(
                                game,
                                process,
                                spawnScreenWidth,
                                spawnScreenHeight,
                                out candidateEvidence))
                        {
                            if (candidate != null &&
                                candidate.Bitmap != null)
                            {
                                bool completeGameplaySurface =
                                    candidate.NonBlank &&
                                    candidate
                                        .LargestDarkComponentPixels <
                                        50000 &&
                                    candidate.DarkPixelRatio < 0.22;
                                surfaceEvidence =
                                    candidateEvidence +
                                    "; largest_dark_component=" +
                                    candidate
                                        .LargestDarkComponentPixels
                                        .ToString(
                                            CultureInfo
                                                .InvariantCulture) +
                                    "; dark_ratio=" +
                                    candidate.DarkPixelRatio.ToString(
                                        "F6",
                                        CultureInfo
                                            .InvariantCulture);
                                if (completeGameplaySurface)
                                {
                                    candidate.Bitmap.Save(
                                        copiedScreenshot,
                                        ImageFormat.Png);
                                    surfaceCaptured = true;
                                    break;
                                }
                            }
                            else
                            {
                                surfaceEvidence = candidateEvidence;
                            }
                        }
                        Thread.Sleep(250);
                    }
                    while (
                        !game.HasExited &&
                        DateTime.UtcNow < visualDeadline);
                    AddStage(
                        stages,
                        game,
                        process,
                        imageBase,
                        clock,
                        "ddraw_primary_surface_captured",
                        requestedCameraReady &&
                        surfaceCaptured &&
                        new FileInfo(copiedScreenshot).Length > 0,
                        "remote_read_only=true; camera=(" +
                        visualCameraLeft + "," +
                        visualCameraTop + "); output=" +
                        copiedScreenshot + "; " +
                        surfaceEvidence);
                    WriteVisualCaptureMetadata(
                        outputDirectory,
                        selectorLevel,
                        route.EngineMission,
                        visualCameraLeft,
                        visualCameraTop,
                        spawnScreenWidth,
                        spawnScreenHeight,
                        gameplayViewportWidth,
                        gameplayViewportHeight,
                        copiedScreenshot,
                        surfaceCaptured,
                        surfaceEvidence);

                    samplerStop = true;
                    sampler.Join(1500);
                    bool visualCursorClipSafe;
                    lock (perf)
                        visualCursorClipSafe = perf.All(
                            delegate(PerfSample sample)
                            {
                                return !sample.CursorClipRestricted;
                            });
                    string[] requiredVisualStages =
                    {
                        "mission_started",
                        "gameplay_scene_resumed",
                        "initial_camera_synchronized",
                        "ddraw_primary_surface_captured"
                    };
                    exitCode = stages
                        .Where(delegate(Stage stage)
                        {
                            return requiredVisualStages.Contains(
                                stage.Name);
                        })
                        .All(delegate(Stage stage)
                        {
                            return stage.Sent &&
                                stage.ProcessResponding;
                        }) &&
                        visualCursorClipSafe ? 0 : 1;
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

                WriteActorStateSnapshot(
                    process,
                    imageBase,
                    Path.Combine(
                        outputDirectory, "actor-states-entry.csv"));
                if (crtRandomRuntimeOnly)
                {
                    // Observe the original scene without issuing gameplay
                    // commands. Menu transitions remain target-window /
                    // process-local DirectInput messages; the observation
                    // itself is read-only and never touches the system cursor.
                    DateTime runtimeDeadline = DateTime.UtcNow.AddMilliseconds(
                        crtRandomRuntimeMilliseconds);
                    while (!game.HasExited &&
                           DateTime.UtcNow < runtimeDeadline)
                    {
                        Thread.Sleep(Math.Min(
                            250,
                            Math.Max(
                                1,
                                (int)(runtimeDeadline - DateTime.UtcNow)
                                    .TotalMilliseconds)));
                    }
                    int runtimeActorCount = ReadWorldActorCount(
                        process, imageBase);
                    WriteActorStateSnapshot(
                        process,
                        imageBase,
                        Path.Combine(
                            outputDirectory,
                            "actor-states-runtime-exit.csv"));
                    bool runtimeObserved =
                        !game.HasExited &&
                        runtimeActorCount > 0;
                    AddStage(
                        stages, game, process, imageBase, clock,
                        "crt_random_runtime_observed",
                        runtimeObserved,
                        "read_only=true; process_local_input=true; " +
                        "observation_ms=" +
                        crtRandomRuntimeMilliseconds.ToString(
                            CultureInfo.InvariantCulture) +
                        "; entry_actors=" +
                        actorCount.ToString(
                            CultureInfo.InvariantCulture) +
                        "; exit_actors=" +
                        runtimeActorCount.ToString(
                            CultureInfo.InvariantCulture));

                    samplerStop = true;
                    sampler.Join(1500);
                    bool runtimeCursorClipSafe;
                    lock (perf)
                        runtimeCursorClipSafe = perf.All(
                            delegate(PerfSample sample)
                            {
                                return !sample.CursorClipRestricted;
                            });
                    exitCode =
                        missionStarted &&
                        gameplayResumeSent &&
                        cameraStateSynchronized &&
                        runtimeObserved &&
                        runtimeCursorClipSafe ? 0 : 1;
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
                    WriteActorItemInventorySnapshot(
                        process,
                        imageBase,
                        actorIdentities,
                        Path.Combine(
                            outputDirectory,
                            "actor-items-entry.csv"));
                }
                if (movementOnly)
                {
                    CaptureParityCheckpoint(
                        parityCheckpoints,
                        process,
                        imageBase,
                        clock,
                        "gameplay_ready");
                    string movementOnlyEvidence;
                    bool movementOnlyInputDelivered =
                        ExercisePlayerMovement(
                            process,
                            imageBase,
                            window,
                            movementCellX,
                            movementCellY,
                            returnCellX,
                            returnCellY,
                            movementObservationMilliseconds,
                            parityCheckpoints,
                            clock,
                            true,
                            movementPlayerRuntimeIndex,
                            movementPlayerSelectionDik,
                            out movementOnlyEvidence);
                    AddStage(
                        stages,
                        game,
                        process,
                        imageBase,
                        clock,
                        "player_input_target_delivery",
                        movementOnlyInputDelivered,
                        movementOnlyEvidence);
                    AddStage(
                        stages,
                        game,
                        process,
                        imageBase,
                        clock,
                        "ai_skipped_movement_only_scope",
                        true,
                        "movement parity begins immediately after the " +
                        "initial camera settles; help, minimap, combat, " +
                        "save/load, failure, and victory workflows are " +
                        "covered by independent probes");

                    samplerStop = true;
                    sampler.Join(1500);
                    bool movementOnlyCursorClipSafe;
                    lock (perf)
                        movementOnlyCursorClipSafe = perf.All(
                            delegate(PerfSample sample)
                            {
                                return !sample.CursorClipRestricted;
                            });
                    string[] requiredMovementOnlyStages =
                    {
                        "mission_started",
                        "gameplay_scene_resumed",
                        "initial_camera_synchronized",
                        "player_input_target_delivery",
                        "ai_skipped_movement_only_scope"
                    };
                    bool movementOnlyStagesPassed =
                        requiredMovementOnlyStages.All(
                            delegate(string requiredName)
                            {
                                Stage requiredStage = stages.FirstOrDefault(
                                    delegate(Stage stage)
                                    {
                                        return stage.Name == requiredName;
                                    });
                                return requiredStage != null &&
                                    requiredStage.Sent &&
                                    requiredStage.ProcessResponding;
                            });
                    exitCode =
                        missionStarted &&
                        movementOnlyInputDelivered &&
                        movementOnlyStagesPassed &&
                        movementOnlyCursorClipSafe ? 0 : 1;
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
                if (paritySbOnly)
                {
                    // S/B are short-lived contextual pointer modes. Exercise
                    // them immediately after gameplay becomes interactive:
                    // waiting through the generic five-second survival audit
                    // lets M010's nearby live patrol independently kill the
                    // selected worker and makes command acceptance race with
                    // unrelated combat.
                    string contextualEvidence;
                    bool contextualObserved =
                        ExerciseSbCommandParity(
                            process,
                            imageBase,
                            window,
                            parityCheckpoints,
                            clock,
                            actorIdentities,
                            parityScenarioOverride,
                            out contextualEvidence);
                    AddStage(
                        stages,
                        game,
                        process,
                        imageBase,
                        clock,
                        "original_contextual_sb_command",
                        contextualObserved,
                        contextualEvidence);
                    samplerStop = true;
                    sampler.Join(1500);
                    bool contextualCursorClipSafe;
                    lock (perf)
                        contextualCursorClipSafe = perf.All(
                            delegate(PerfSample sample)
                            {
                                return !sample.CursorClipRestricted;
                            });
                    bool contextualProcessResponsive = stages.All(
                        delegate(Stage stage)
                        {
                            return stage.ProcessResponding;
                        });
                    exitCode =
                        missionStarted &&
                        contextualObserved &&
                        contextualProcessResponsive &&
                        contextualCursorClipSafe ? 0 : 1;
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
                    WriteActorItemInventorySnapshot(
                        process,
                        imageBase,
                        actorIdentities,
                        Path.Combine(
                            outputDirectory,
                            "actor-items-steady.csv"));
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
                    int itemInventoryAddressValue = spawnEnd == null
                        ? 0
                        : ReadInt(
                            process,
                            spawnEnd.Address +
                            ActorItemInventoryAddressOffset);
                    long itemInventoryAddress =
                        (long)(uint)itemInventoryAddressValue;
                    int itemInventoryCount =
                        itemInventoryAddressValue > 0
                            ? ReadInt(
                                process,
                                itemInventoryAddress + 0x0C)
                            : 0;
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
                    bool itemInventoryReadable =
                        itemInventoryAddressValue >= 0 &&
                        itemInventoryCount >= 0 &&
                        itemInventoryCount <= 256 &&
                        File.Exists(Path.Combine(
                            outputDirectory,
                            "actor-items-entry.csv")) &&
                        File.Exists(Path.Combine(
                            outputDirectory,
                            "actor-items-steady.csv"));
                    AddStage(
                        stages, game, process, imageBase, clock,
                        "player_inventory_snapshot",
                        inventoryReadable && itemInventoryReadable,
                        "weapon_container=0x" +
                        inventoryAddress.ToString(
                            "X8",
                            CultureInfo.InvariantCulture) +
                        "; weapon_count=" + inventoryCount +
                        "; item_container=0x" +
                        itemInventoryAddress.ToString(
                            "X8",
                            CultureInfo.InvariantCulture) +
                        "; item_count=" + itemInventoryCount +
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
                        itemInventoryReadable &&
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
                if (parityPickupOnly ||
                    parityAttackOnly ||
                    parityWorldItemOnly)
                {
                    WeaponAttackParityScenario attackParityScenario =
                        parityAttackOnly
                            ? ResolveWeaponAttackParityScenario(
                                parityScenarioOverride,
                                selectorLevel)
                            : null;
                    WorldItemParityScenario worldItemParityScenario =
                        parityWorldItemOnly
                            ? ResolveWorldItemParityScenario(
                                parityScenarioOverride,
                                selectorLevel)
                            : null;
                    string inventoryParityEvidence;
                    bool inventoryParityObserved;
                    if (parityPickupOnly)
                    {
                        inventoryParityObserved = ExerciseMinePickupParity(
                            process,
                            imageBase,
                            window,
                            parityCheckpoints,
                            clock,
                            actorIdentities,
                            out inventoryParityEvidence);
                    }
                    else if (parityWorldItemOnly)
                    {
                        inventoryParityObserved =
                            ExerciseWorldItemParity(
                                process,
                                imageBase,
                                window,
                                parityCheckpoints,
                                clock,
                                actorIdentities,
                                worldItemParityScenario,
                                out inventoryParityEvidence);
                    }
                    else
                    {
                        inventoryParityObserved =
                            ExerciseWeaponAttackParity(
                            process,
                            imageBase,
                            window,
                            parityCheckpoints,
                            clock,
                            actorIdentities,
                            attackParityScenario,
                            out inventoryParityEvidence);
                    }
                    AddStage(
                        stages,
                        game,
                        process,
                        imageBase,
                        clock,
                        parityPickupOnly
                            ? "original_mine_pickup_inventory_delta"
                            : parityWorldItemOnly
                                ? worldItemParityScenario.StageName
                                : attackParityScenario.StageName,
                        inventoryParityObserved,
                        inventoryParityEvidence);
                    samplerStop = true;
                    sampler.Join(1500);
                    bool inventoryParityCursorClipSafe;
                    lock (perf)
                        inventoryParityCursorClipSafe = perf.All(
                            delegate(PerfSample sample)
                            {
                                return !sample.CursorClipRestricted;
                            });
                    bool inventoryParityProcessResponsive = stages.All(
                        delegate(Stage stage)
                        {
                            return stage.ProcessResponding;
                        });
                    int trackedSceneIndex = parityPickupOnly
                        ? M001PlayerSceneIndex
                        : parityWorldItemOnly
                            ? worldItemParityScenario.TargetSceneIndex
                            : attackParityScenario.PlayerSceneIndex;
                    int expectedCheckpointCount =
                        parityWorldItemOnly &&
                        worldItemParityScenario.Poison
                            ? 3
                            : 2;
                    bool inventorySnapshotsReady =
                        parityCheckpoints.Count ==
                            expectedCheckpointCount &&
                        parityCheckpoints.All(
                            delegate(ParityCheckpoint checkpoint)
                            {
                                ActorSnapshot tracked =
                                    ResolvedActorForScene(
                                        checkpoint.Actors,
                                        actorIdentities,
                                        trackedSceneIndex);
                                return tracked != null &&
                                    tracked.InventoryCaptured;
                            });
                    exitCode =
                        missionStarted &&
                        spawnSafe &&
                        inventoryParityObserved &&
                        inventorySnapshotsReady &&
                        inventoryParityProcessResponsive &&
                        inventoryParityCursorClipSafe ? 0 : 1;
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
                        -1,
                        DikF4,
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
                    int expectedPatrolActorCount =
                        actorIdentities.Values.Count(
                            delegate(RuntimeActorIdentity identity)
                            {
                                return identity.VwfFactionId == 1;
                            });
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
                        expectedPatrolActorCount > 0 &&
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
                                    }) == expectedPatrolActorCount;
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
                    movementObservationMilliseconds,
                    parityCheckpoints, clock, false,
                    movementPlayerRuntimeIndex,
                    movementPlayerSelectionDik,
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
                                       "\"search_completed\":") +
                                   SumCounter(
                                       current,
                                       "\"reacquisitions\":") >=
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
                long targetReacquisitions = SumCounter(
                    aiTelemetry, "\"reacquisitions\":");
                long escapeSuccesses =
                    escapeTimeouts + searchCompleted +
                    targetReacquisitions;
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
                    "; target_reacquisitions=" +
                    targetReacquisitions.ToString(
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
                string[] requiredMovementStages =
                {
                    "mission_started",
                    "gameplay_scene_resumed",
                    "initial_camera_synchronized",
                    "player_spawn_survival",
                    "player_input_target_delivery",
                    "ai_skipped_movement_only_scope",
                    "save_original_path",
                    "load_original_path",
                    "failure_original_transition",
                    "restart_after_failure",
                    "victory_original_transition"
                };
                IEnumerable<Stage> gatedStages = movementOnly
                    ? stages.Where(delegate(Stage stage)
                      {
                          return requiredMovementStages.Contains(
                              stage.Name);
                      })
                    : stages;
                bool allStages =
                    gatedStages.All(delegate(Stage stage)
                    {
                        return stage.Sent &&
                            stage.ProcessResponding;
                    }) &&
                    (!movementOnly ||
                     requiredMovementStages.All(
                         delegate(string requiredName)
                         {
                             return stages.Any(
                                 delegate(Stage stage)
                                 {
                                     return stage.Name ==
                                         requiredName;
                                 });
                         }));
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

    private static int PlayerSelectionDik(string displayName)
    {
        switch (displayName ?? "")
        {
        case "老赵": return DikF2;
        case "铁蛋": return DikF3;
        case "强子": return DikF4;
        case "古明": return DikF5;
        case "大牛": return DikF6;
        default:
            throw new InvalidDataException(
                "Unknown original player hotkey identity: " +
                (displayName ?? ""));
        }
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

    private static bool TryCaptureCncDdrawPrimarySurface(
        Process game,
        IntPtr process,
        int width,
        int height,
        string outputPath,
        out string evidence)
    {
        using (CaptureResult capture =
            CaptureCncDdrawPrimarySurface(
                game, process, width, height, out evidence))
        {
            if (capture == null || capture.Bitmap == null)
                return false;
            capture.Bitmap.Save(outputPath, ImageFormat.Png);
            return true;
        }
    }

    private static CaptureResult CaptureCncDdrawPrimarySurface(
        Process game,
        IntPtr process,
        int width,
        int height,
        out string evidence)
    {
        evidence = "";
        try
        {
            string ddrawPath;
            long ddrawBase;
            string loadedModules;
            if (!TryFindRemoteModule(
                    game.Id,
                    "ddraw.dll",
                    out ddrawPath,
                    out ddrawBase,
                    out loadedModules))
            {
                evidence = "ddraw_module=missing; modules=" +
                    loadedModules;
                return null;
            }
            uint exportRva = ResolvePeExportRva(
                ddrawPath,
                "pvBmpBits");
            if (exportRva == 0)
            {
                evidence = "pvBmpBits=missing";
                return null;
            }
            long pointerAddress =
                ddrawBase + exportRva;
            byte[] pointerBytes =
                ReadBytes(process, pointerAddress, 4);
            if (pointerBytes.Length != 4)
            {
                evidence = "pvBmpBits=unreadable";
                return null;
            }
            uint surfaceAddress =
                BitConverter.ToUInt32(pointerBytes, 0);
            if (surfaceAddress == 0 || width <= 0 || height <= 0)
            {
                evidence = "surface=unavailable";
                return null;
            }
            int sourceStride = checked(width * 2);
            byte[] source = ReadBytes(
                process,
                surfaceAddress,
                checked(sourceStride * height));
            if (source.Length != sourceStride * height)
            {
                evidence = "surface=short_read";
                return null;
            }

            var bitmap = new Bitmap(
                width, height, PixelFormat.Format24bppRgb);
            try
            {
                Rectangle area =
                    new Rectangle(0, 0, width, height);
                BitmapData data = bitmap.LockBits(
                    area,
                    ImageLockMode.WriteOnly,
                    PixelFormat.Format24bppRgb);
                try
                {
                    int destinationStride =
                        Math.Abs(data.Stride);
                    byte[] destination = new byte[
                        checked(destinationStride * height)];
                    for (int y = 0; y < height; y++)
                    {
                        int sourceRow = y * sourceStride;
                        int destinationRow =
                            y * destinationStride;
                        for (int x = 0; x < width; x++)
                        {
                            ushort pixel = BitConverter.ToUInt16(
                                source,
                                sourceRow + x * 2);
                            int destinationOffset =
                                destinationRow + x * 3;
                            destination[destinationOffset] =
                                (byte)((pixel & 0x1F) * 255 / 31);
                            destination[destinationOffset + 1] =
                                (byte)(((pixel >> 5) & 0x3F) *
                                    255 / 63);
                            destination[destinationOffset + 2] =
                                (byte)(((pixel >> 11) & 0x1F) *
                                    255 / 31);
                        }
                    }
                    Marshal.Copy(
                        destination,
                        0,
                        data.Scan0,
                        destination.Length);
                }
                finally
                {
                    bitmap.UnlockBits(data);
                }
                byte[] pixels = BitmapBytes(bitmap);
                string hash;
                using (SHA256 sha = SHA256.Create())
                    hash = BitConverter.ToString(
                        sha.ComputeHash(pixels)).Replace("-", "");
                int largestDarkComponent;
                double darkPixelRatio;
                AnalyzeMapDarkResidue(
                    bitmap,
                    out largestDarkComponent,
                    out darkPixelRatio);
                var capture = new CaptureResult
                {
                    Bitmap = bitmap,
                    Sha256 = hash,
                    NonBlank = HasVisualRange(pixels),
                    LargestDarkComponentPixels =
                        largestDarkComponent,
                    DarkPixelRatio = darkPixelRatio
                };
                bitmap = null;
                evidence = "module=" + Path.GetFileName(ddrawPath) +
                    "; export_rva=0x" +
                    exportRva.ToString(
                        "X8", CultureInfo.InvariantCulture) +
                    "; surface=0x" +
                    surfaceAddress.ToString(
                        "X8", CultureInfo.InvariantCulture) +
                    "; format=RGB565";
                return capture;
            }
            finally
            {
                if (bitmap != null)
                    bitmap.Dispose();
            }
        }
        catch (Exception ex)
        {
            evidence = ex.GetType().Name + ": " + ex.Message;
            return null;
        }
    }

    private static bool TryFindRemoteModule(
        int processId,
        string moduleName,
        out string modulePath,
        out long baseAddress,
        out string loadedModules)
    {
        modulePath = "";
        baseAddress = 0;
        var names = new List<string>();
        IntPtr snapshot = CreateToolhelp32Snapshot(
            Th32csSnapModule | Th32csSnapModule32,
            unchecked((uint)processId));
        if (snapshot == new IntPtr(-1))
        {
            loadedModules = "snapshot_error_" +
                Marshal.GetLastWin32Error().ToString(
                    CultureInfo.InvariantCulture);
            return false;
        }
        try
        {
            var entry = new ModuleEntry32();
            entry.Size = unchecked((uint)Marshal.SizeOf(entry));
            if (!Module32First(snapshot, ref entry))
            {
                loadedModules = "enumeration_error_" +
                    Marshal.GetLastWin32Error().ToString(
                        CultureInfo.InvariantCulture);
                return false;
            }
            do
            {
                if (names.Count < 24)
                    names.Add(entry.ModuleName ?? "");
                if (String.Equals(
                        entry.ModuleName,
                        moduleName,
                        StringComparison.OrdinalIgnoreCase))
                {
                    modulePath = entry.ExecutablePath;
                    baseAddress = entry.BaseAddress.ToInt64();
                    loadedModules = String.Join(
                        ",", names.ToArray());
                    return true;
                }
                entry.Size =
                    unchecked((uint)Marshal.SizeOf(entry));
            }
            while (Module32Next(snapshot, ref entry));
        }
        finally
        {
            CloseHandle(snapshot);
        }
        loadedModules = String.Join(",", names.ToArray());
        return false;
    }

    private static uint ResolvePeExportRva(
        string modulePath,
        string exportName)
    {
        byte[] image = File.ReadAllBytes(modulePath);
        if (image.Length < 0x100 ||
            BitConverter.ToUInt16(image, 0) != 0x5A4D)
            return 0;
        int peOffset = BitConverter.ToInt32(image, 0x3C);
        if (peOffset < 0 ||
            peOffset + 24 > image.Length ||
            BitConverter.ToUInt32(image, peOffset) != 0x00004550)
            return 0;
        int optionalHeader = peOffset + 24;
        ushort magic =
            BitConverter.ToUInt16(image, optionalHeader);
        int exportDirectoryEntry = optionalHeader +
            (magic == 0x10B ? 96 : magic == 0x20B ? 112 : -1);
        if (exportDirectoryEntry < optionalHeader ||
            exportDirectoryEntry + 8 > image.Length)
            return 0;
        uint exportDirectoryRva =
            BitConverter.ToUInt32(image, exportDirectoryEntry);
        if (exportDirectoryRva == 0)
            return 0;
        int exportDirectory = PeRvaToFileOffset(
            image, peOffset, exportDirectoryRva);
        if (exportDirectory < 0 ||
            exportDirectory + 40 > image.Length)
            return 0;
        uint nameCount =
            BitConverter.ToUInt32(image, exportDirectory + 24);
        uint functionTableRva =
            BitConverter.ToUInt32(image, exportDirectory + 28);
        uint nameTableRva =
            BitConverter.ToUInt32(image, exportDirectory + 32);
        uint ordinalTableRva =
            BitConverter.ToUInt32(image, exportDirectory + 36);
        int functionTable = PeRvaToFileOffset(
            image, peOffset, functionTableRva);
        int nameTable = PeRvaToFileOffset(
            image, peOffset, nameTableRva);
        int ordinalTable = PeRvaToFileOffset(
            image, peOffset, ordinalTableRva);
        if (functionTable < 0 ||
            nameTable < 0 ||
            ordinalTable < 0)
            return 0;
        for (uint index = 0; index < nameCount; index++)
        {
            int nameEntry = checked(
                nameTable + (int)index * 4);
            int ordinalEntry = checked(
                ordinalTable + (int)index * 2);
            if (nameEntry + 4 > image.Length ||
                ordinalEntry + 2 > image.Length)
                return 0;
            uint nameRva =
                BitConverter.ToUInt32(image, nameEntry);
            int nameOffset = PeRvaToFileOffset(
                image, peOffset, nameRva);
            if (!ReadPeAsciiString(image, nameOffset).Equals(
                    exportName,
                    StringComparison.Ordinal))
                continue;
            ushort ordinal =
                BitConverter.ToUInt16(image, ordinalEntry);
            int functionEntry = checked(
                functionTable + ordinal * 4);
            if (functionEntry + 4 > image.Length)
                return 0;
            return BitConverter.ToUInt32(
                image, functionEntry);
        }
        return 0;
    }

    private static void WriteVisualCaptureMetadata(
        string outputDirectory,
        int selectorLevel,
        int engineMission,
        int cameraLeft,
        int cameraTop,
        int surfaceWidth,
        int surfaceHeight,
        int mapViewportWidth,
        int mapViewportHeight,
        string screenshotPath,
        bool passed,
        string evidence)
    {
        string screenshotHash = "";
        if (passed && File.Exists(screenshotPath))
        {
            using (SHA256 sha = SHA256.Create())
            using (FileStream stream = File.OpenRead(screenshotPath))
                screenshotHash = BitConverter.ToString(
                    sha.ComputeHash(stream)).Replace("-", "");
        }
        var json = new StringBuilder();
        json.Append("{\n");
        json.Append("  \"schema_version\": 1,\n");
        json.Append("  \"runtime\": \"stable_mod\",\n");
        json.AppendFormat(
            CultureInfo.InvariantCulture,
            "  \"selector_level\": {0},\n" +
            "  \"engine_mission\": {1},\n" +
            "  \"camera_left\": {2},\n" +
            "  \"camera_top\": {3},\n" +
            "  \"surface\": [{4}, {5}],\n" +
            "  \"map_viewport\": [{6}, {7}],\n",
            selectorLevel,
            engineMission,
            cameraLeft,
            cameraTop,
            surfaceWidth,
            surfaceHeight,
            mapViewportWidth,
            mapViewportHeight);
        json.Append(
            "  \"input_isolation\": " +
            "\"read-only-process-memory; no global input\",\n");
        json.Append(
            "  \"pixel_format\": \"RGB565\",\n");
        json.Append(
            "  \"screenshot\": \"" +
            Escape(screenshotPath) + "\",\n");
        json.Append(
            "  \"screenshot_sha256\": \"" +
            Escape(screenshotHash) + "\",\n");
        json.Append(
            "  \"evidence\": \"" +
            Escape(evidence) + "\",\n");
        json.Append(
            "  \"passed\": " +
            (passed ? "true" : "false") + "\n");
        json.Append("}\n");
        File.WriteAllText(
            Path.Combine(
                outputDirectory,
                "visual-capture.json"),
            json.ToString(),
            new UTF8Encoding(false));
    }

    private static int PeRvaToFileOffset(
        byte[] image,
        int peOffset,
        uint rva)
    {
        ushort sectionCount =
            BitConverter.ToUInt16(image, peOffset + 6);
        ushort optionalHeaderSize =
            BitConverter.ToUInt16(image, peOffset + 20);
        int sectionTable =
            peOffset + 24 + optionalHeaderSize;
        for (int index = 0; index < sectionCount; index++)
        {
            int section = sectionTable + index * 40;
            if (section + 40 > image.Length)
                return -1;
            uint virtualSize =
                BitConverter.ToUInt32(image, section + 8);
            uint virtualAddress =
                BitConverter.ToUInt32(image, section + 12);
            uint rawSize =
                BitConverter.ToUInt32(image, section + 16);
            uint rawOffset =
                BitConverter.ToUInt32(image, section + 20);
            uint span = Math.Max(virtualSize, rawSize);
            if (rva >= virtualAddress &&
                (ulong)rva <
                    (ulong)virtualAddress + span)
                return checked(
                    (int)(rawOffset + rva - virtualAddress));
        }
        return rva < image.Length ? (int)rva : -1;
    }

    private static string ReadPeAsciiString(
        byte[] image,
        int offset)
    {
        if (offset < 0 || offset >= image.Length)
            return "";
        int end = offset;
        while (end < image.Length && image[end] != 0)
            end++;
        return Encoding.ASCII.GetString(
            image, offset, end - offset);
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
        uint capturedTickMilliseconds = GetTickCount();
        var text = new StringBuilder();
        text.AppendLine(
            "captured_tick_ms,index,address,runtime_type,faction,world_x,world_y," +
            "previous_world_x,previous_world_y," +
            "direction,dead,goal_kind,goal_x,goal_y,command_variant," +
            "command_pending,movement_active,movement_path_state," +
            "movement_mode,resolved_goal_x,resolved_goal_y,path_override," +
            "stationary_tick_counter,stationary_tick_limit," +
            "route_update_active,pursuit_address,pursuit_delay_counter," +
            "target_address,search_delay_limit,search_delay_counter," +
            "contact_state,target_lost,reaction_state");
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
                "{0},{1},0x{2:X8},{3},{4},{5},{6},{7},{8},{9},{10}," +
                "{11},{12},{13},{14},{15},{16},{17},{18},{19},{20}," +
                "{21},{22},{23},{24},0x{25:X8},{26},0x{27:X8},{28}," +
                "{29},{30},{31},{32}\r\n",
                capturedTickMilliseconds,
                index,
                snapshot.Address,
                snapshot.RuntimeType,
                snapshot.Faction,
                snapshot.WorldX,
                snapshot.WorldY,
                snapshot.PreviousWorldX,
                snapshot.PreviousWorldY,
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
                snapshot.PathOverrideActive,
                snapshot.StationaryTickCounter,
                snapshot.StationaryTickLimit,
                snapshot.RouteUpdateActive,
                snapshot.PursuitAddress,
                snapshot.PursuitDelayCounter,
                snapshot.TargetAddress,
                snapshot.SearchDelayLimit,
                snapshot.SearchDelayCounter,
                snapshot.ContactState,
                snapshot.TargetLost,
                snapshot.ReactionState);
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
        WriteActorInventoryContainerSnapshot(
            process,
            imageBase,
            actorIdentities,
            ActorInventoryAddressOffset,
            path);
    }

    private static void WriteActorItemInventorySnapshot(
        IntPtr process,
        long imageBase,
        Dictionary<int, RuntimeActorIdentity> actorIdentities,
        string path)
    {
        WriteActorInventoryContainerSnapshot(
            process,
            imageBase,
            actorIdentities,
            ActorItemInventoryAddressOffset,
            path);
    }

    private static void WriteActorInventoryContainerSnapshot(
        IntPtr process,
        long imageBase,
        Dictionary<int, RuntimeActorIdentity> actorIdentities,
        int containerOffset,
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
                process, actorAddress + containerOffset);
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
        IntPtr process, long imageBase,
        int preferredRuntimeIndex = -1)
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
        if (preferredRuntimeIndex >= 0)
        {
            if (preferredRuntimeIndex >= count)
                return null;
            int preferredActorValue = ReadInt(
                process,
                actorArray + preferredRuntimeIndex * 4L);
            if (preferredActorValue == 0 ||
                preferredActorValue == int.MinValue)
                return null;
            long preferredActor =
                (long)(uint)preferredActorValue;
            if (ReadInt(
                    process,
                    preferredActor + ActorFactionOffset) != 3)
                return null;
            ActorSnapshot preferredSnapshot =
                ReadActor(process, preferredActor);
            if (preferredSnapshot == null)
                return null;
            preferredSnapshot.SceneIndex =
                preferredRuntimeIndex;
            return preferredSnapshot;
        }
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

    private static ActorSnapshot FindPlayerActorInViewport(
        IntPtr process,
        long imageBase,
        int cameraX,
        int cameraY,
        int viewportWidth,
        int viewportHeight)
    {
        if (viewportWidth <= 0 || viewportHeight <= 0)
            return null;
        int worldValue = ReadInt(
            process, imageBase + EngineAddresses.WorldRoot);
        if (worldValue == 0 || worldValue == int.MinValue)
            return null;
        long world = (long)(uint)worldValue;
        int actorArrayValue = ReadInt(process, world + 0x18);
        int count = ReadInt(process, world + 0x3C);
        if (actorArrayValue == 0 ||
            actorArrayValue == int.MinValue ||
            count <= 0 ||
            count > 4096)
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
            if (ReadInt(process, actor + ActorFactionOffset) != 3 ||
                ReadInt(process, actor + ActorDeadOffset) != 0)
                continue;
            ActorSnapshot snapshot = ReadActor(process, actor);
            if (snapshot == null ||
                snapshot.WorldX < cameraX ||
                snapshot.WorldX >= cameraX + viewportWidth ||
                snapshot.WorldY < cameraY ||
                snapshot.WorldY >= cameraY + viewportHeight)
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
            PreviousWorldX = ReadInt(
                process, actor + ActorPreviousWorldXOffset),
            PreviousWorldY = ReadInt(
                process, actor + ActorPreviousWorldYOffset),
            StationaryTickCounter = ReadInt(
                process, actor + ActorStationaryTickCounterOffset),
            StationaryTickLimit = ReadInt(
                process, actor + ActorStationaryTickLimitOffset),
            Direction = ReadInt(
                process, actor + ActorFacingDirectionOffset),
            RouteUpdateActive = ReadInt(
                process, actor + ActorRouteUpdateActiveOffset),
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
            WorldItemPlayerSelected = ReadInt(
                process, actor + ActorWorldItemPlayerSelectedOffset),
            HypnosisActive = ReadInt(
                process, actor + ActorHypnosisActiveOffset),
            PursuitAddress = (long)(uint)ReadInt(
                process, actor + ActorPursuitAddressOffset),
            PursuitDelayCounter = ReadInt(
                process, actor + ActorPursuitDelayCounterOffset),
            HypnosisCounter = ReadInt(
                process, actor + ActorHypnosisCounterOffset),
            HypnosisCounterLimit = ReadInt(
                process, actor + ActorHypnosisCounterLimitOffset),
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
            PoisonActive = ReadInt(
                process, actor + ActorPoisonActiveOffset),
            PoisonCounter = ReadInt(
                process, actor + ActorPoisonCounterOffset),
            PoisonCounterLimit = ReadInt(
                process, actor + ActorPoisonCounterLimitOffset),
            PathOverrideActive = ReadInt(
                process, actor + ActorPathOverrideActiveOffset)
        };
    }

    private static bool ReadActorInventoryContainers(
        IntPtr process,
        ActorSnapshot actor)
    {
        if (actor == null || actor.Address == 0)
            return false;
        actor.WeaponEntries.Clear();
        actor.ItemEntries.Clear();
        bool weaponReadable = ReadInventoryContainer(
            process,
            actor.Address + ActorInventoryAddressOffset,
            actor.WeaponEntries);
        bool itemReadable = ReadInventoryContainer(
            process,
            actor.Address + ActorItemInventoryAddressOffset,
            actor.ItemEntries);
        actor.InventoryCaptured = weaponReadable && itemReadable;
        return actor.InventoryCaptured;
    }

    private static bool ReadInventoryContainer(
        IntPtr process,
        long containerPointerAddress,
        List<InventoryEntry> output)
    {
        if (output == null)
            return false;
        int containerValue = ReadInt(process, containerPointerAddress);
        if (containerValue == int.MinValue)
            return false;
        if (containerValue == 0)
            return true;
        long container = (long)(uint)containerValue;
        int count = ReadInt(process, container + 0x0C);
        if (count < 0 || count > 256)
            return false;
        if (count == 0)
            return true;
        int itemIdsValue = ReadInt(process, container + 0x00);
        int quantitiesValue = ReadInt(process, container + 0x04);
        int quantityModesValue = ReadInt(process, container + 0x08);
        if (itemIdsValue == 0 ||
            quantitiesValue == 0 ||
            quantityModesValue == 0 ||
            itemIdsValue == int.MinValue ||
            quantitiesValue == int.MinValue ||
            quantityModesValue == int.MinValue)
            return false;
        long itemIds = (long)(uint)itemIdsValue;
        long quantities = (long)(uint)quantitiesValue;
        long quantityModes = (long)(uint)quantityModesValue;
        for (int index = 0; index < count; ++index)
        {
            int itemId = ReadInt(process, itemIds + index * 4L);
            int quantity = ReadInt(process, quantities + index * 4L);
            int quantityMode = ReadInt(
                process, quantityModes + index * 4L);
            if (itemId <= 0 ||
                quantity < 0 ||
                quantityMode < 0 ||
                quantityMode > 2 ||
                itemId == int.MinValue ||
                quantity == int.MinValue ||
                quantityMode == int.MinValue)
                return false;
            output.Add(new InventoryEntry
            {
                InventoryIndex = index,
                ItemId = itemId,
                Quantity = quantity,
                QuantityMode = quantityMode
            });
        }
        return true;
    }

    private static ActorSnapshot ResolvedActorForScene(
        IEnumerable<ActorSnapshot> actors,
        Dictionary<int, RuntimeActorIdentity> actorIdentities,
        int sceneIndex)
    {
        if (actors == null || actorIdentities == null)
            return null;
        return actors.FirstOrDefault(
            delegate(ActorSnapshot actor)
            {
                RuntimeActorIdentity identity;
                return actorIdentities.TryGetValue(
                           actor.SceneIndex, out identity) &&
                       identity.SceneIndex == sceneIndex;
            });
    }

    private static ActorSnapshot ReadResolvedActor(
        IntPtr process,
        long imageBase,
        Dictionary<int, RuntimeActorIdentity> actorIdentities,
        int sceneIndex)
    {
        if (actorIdentities == null)
            return null;
        RuntimeActorIdentity identity =
            actorIdentities.Values.FirstOrDefault(
                delegate(RuntimeActorIdentity candidate)
                {
                    return candidate.SceneIndex == sceneIndex;
                });
        if (identity == null)
            return null;
        int worldValue = ReadInt(
            process, imageBase + EngineAddresses.WorldRoot);
        if (worldValue == 0 || worldValue == int.MinValue)
            return null;
        long world = (long)(uint)worldValue;
        int actorArrayValue = ReadInt(process, world + 0x18);
        int count = ReadInt(process, world + 0x3C);
        if (actorArrayValue == 0 ||
            actorArrayValue == int.MinValue ||
            identity.RuntimeIndex < 0 ||
            identity.RuntimeIndex >= count)
            return null;
        int actorValue = ReadInt(
            process,
            (long)(uint)actorArrayValue +
            identity.RuntimeIndex * 4L);
        if (actorValue == 0 || actorValue == int.MinValue)
            return null;
        ActorSnapshot actor = ReadActor(
            process, (long)(uint)actorValue);
        if (actor != null)
            actor.SceneIndex = identity.RuntimeIndex;
        return actor;
    }

    private static ActorSnapshot ReadPlayerActorSlot(
        IntPtr process,
        long imageBase,
        int slotIndex,
        int sceneIndex)
    {
        long slotRva;
        switch (slotIndex)
        {
        case 1:
            slotRva = EngineAddresses.PlayerActorSlot1;
            break;
        case 2:
            slotRva = EngineAddresses.PlayerActorSlot2;
            break;
        case 3:
            slotRva = EngineAddresses.PlayerActorSlot3;
            break;
        case 4:
            slotRva = EngineAddresses.SpecialAttentionSource;
            break;
        case 5:
            slotRva = EngineAddresses.PlayerActorSlot5;
            break;
        default:
            return null;
        }
        int actorValue = ReadInt(process, imageBase + slotRva);
        if (actorValue == 0 || actorValue == int.MinValue)
            return null;
        ActorSnapshot actor = ReadActor(
            process, (long)(uint)actorValue);
        if (actor != null)
            actor.SceneIndex = sceneIndex;
        return actor;
    }

    private static ActorSnapshot ReadWeaponParityPlayer(
        IntPtr process,
        long imageBase,
        Dictionary<int, RuntimeActorIdentity> actorIdentities,
        WeaponAttackParityScenario scenario)
    {
        return scenario.PlayerSlotIndex > 0
            ? ReadPlayerActorSlot(
                process,
                imageBase,
                scenario.PlayerSlotIndex,
                scenario.PlayerSceneIndex)
            : ReadResolvedActor(
                process,
                imageBase,
                actorIdentities,
                scenario.PlayerSceneIndex);
    }

    private static ActorSnapshot FindWorldActor(
        IntPtr process,
        long imageBase,
        int runtimeType,
        int expectedWorldX,
        int expectedWorldY,
        int maximumDistance)
    {
        return FindWorldEntry(
            process,
            imageBase,
            0x18,
            0x3C,
            runtimeType,
            expectedWorldX,
            expectedWorldY,
            maximumDistance);
    }

    private static ActorSnapshot FindWorldStaticObject(
        IntPtr process,
        long imageBase,
        int runtimeType,
        int expectedWorldX,
        int expectedWorldY,
        int maximumDistance)
    {
        return FindWorldEntry(
            process,
            imageBase,
            0x1C,
            0x40,
            runtimeType,
            expectedWorldX,
            expectedWorldY,
            maximumDistance);
    }

    private static ActorSnapshot FindWorldEntry(
        IntPtr process,
        long imageBase,
        int arrayPointerOffset,
        int countOffset,
        int runtimeType,
        int expectedWorldX,
        int expectedWorldY,
        int maximumDistance)
    {
        int worldValue = ReadInt(
            process, imageBase + EngineAddresses.WorldRoot);
        if (worldValue == 0 || worldValue == int.MinValue)
            return null;
        long world = (long)(uint)worldValue;
        int actorArrayValue = ReadInt(
            process, world + arrayPointerOffset);
        int count = ReadInt(process, world + countOffset);
        if (actorArrayValue == 0 ||
            actorArrayValue == int.MinValue ||
            count <= 0 ||
            count > 4096)
            return null;
        long actorArray = (long)(uint)actorArrayValue;
        ActorSnapshot closest = null;
        long closestDistanceSquared = long.MaxValue;
        long maximumDistanceSquared =
            (long)maximumDistance * maximumDistance;
        for (int index = 0; index < count; ++index)
        {
            int actorValue = ReadInt(
                process, actorArray + index * 4L);
            if (actorValue == 0 || actorValue == int.MinValue)
                continue;
            ActorSnapshot candidate = ReadActor(
                process, (long)(uint)actorValue);
            if (candidate == null ||
                candidate.RuntimeType != runtimeType)
                continue;
            long deltaX = candidate.WorldX - expectedWorldX;
            long deltaY = candidate.WorldY - expectedWorldY;
            long distanceSquared =
                deltaX * deltaX + deltaY * deltaY;
            if (distanceSquared > maximumDistanceSquared ||
                distanceSquared >= closestDistanceSquared)
                continue;
            candidate.SceneIndex = index;
            closest = candidate;
            closestDistanceSquared = distanceSquared;
        }
        return closest;
    }

    private static bool TryGetActorClickWorldPoint(
        IntPtr process,
        ActorSnapshot actor,
        out int clickWorldX,
        out int clickWorldY)
    {
        clickWorldX = int.MinValue;
        clickWorldY = int.MinValue;
        if (actor == null || actor.Address == 0)
            return false;
        int primaryX = ReadInt(
            process, actor.Address + ActorSpritePrimaryXOffset);
        int primaryZ = ReadInt(
            process, actor.Address + ActorSpritePrimaryZOffset);
        int width = ReadInt(
            process, actor.Address + ActorSpriteWidthOffset);
        int height = ReadInt(
            process, actor.Address + ActorSpriteHeightOffset);
        if (primaryX == int.MinValue ||
            primaryZ == int.MinValue ||
            width <= 0 ||
            height <= 0 ||
            width > 2048 ||
            height > 2048)
            return false;
        long left = (long)actor.WorldX - primaryX;
        long top = (long)actor.WorldY - primaryZ;
        long centerX = left + width / 2L;
        long centerY = top + height / 2L;
        if (centerX < int.MinValue ||
            centerX > int.MaxValue ||
            centerY < int.MinValue ||
            centerY > int.MaxValue)
            return false;
        clickWorldX = (int)centerX;
        clickWorldY = (int)centerY;
        return true;
    }

    private static int InventoryQuantity(
        IEnumerable<InventoryEntry> entries,
        int itemId)
    {
        if (entries == null)
            return 0;
        InventoryEntry entry = entries.FirstOrDefault(
            delegate(InventoryEntry candidate)
            {
                return candidate.ItemId == itemId;
            });
        return entry == null ? 0 : entry.Quantity;
    }

    private static bool ExerciseMinePickupParity(
        IntPtr process,
        long imageBase,
        IntPtr window,
        List<ParityCheckpoint> checkpoints,
        Stopwatch runClock,
        Dictionary<int, RuntimeActorIdentity> actorIdentities,
        out string evidence)
    {
        bool selected = PulseKey(window, DikF2);
        Thread.Sleep(320);
        ActorSnapshot player = ReadResolvedActor(
            process,
            imageBase,
            actorIdentities,
            M001PlayerSceneIndex);
        if (player == null ||
            !ReadActorInventoryContainers(process, player))
        {
            evidence =
                "m001 scene 2280 inventory was not readable after F2";
            return false;
        }
        int beforeQuantity = InventoryQuantity(
            player.WeaponEntries, M001MineItemId);
        CaptureParityCheckpoint(
            checkpoints,
            process,
            imageBase,
            runClock,
            "before_pickup",
            true);

        bool clickSent = false;
        bool quantityChanged = false;
        int afterQuantity = beforeQuantity;
        int attempts = 0;
        int lastClickWorldX = int.MinValue;
        int lastClickWorldY = int.MinValue;
        int lastCursorX = int.MinValue;
        int lastCursorY = int.MinValue;
        int lastMineRuntimeIndex = -1;
        int lastMineStaticIndex = -1;
        int lastMineOwnStatus = int.MinValue;
        long lastMineAddress = 0;
        Stopwatch wait = Stopwatch.StartNew();
        while (wait.ElapsedMilliseconds < 16000)
        {
            if (attempts == 0 ||
                (wait.ElapsedMilliseconds >= attempts * 5000 &&
                 attempts < 3))
            {
                ActorSnapshot dynamicMine = FindWorldActor(
                    process,
                    imageBase,
                    M001MineRuntimeType,
                    M001MineWorldX,
                    M001MineWorldY,
                    96);
                ActorSnapshot staticMine = FindWorldStaticObject(
                    process,
                    imageBase,
                    M001MineRuntimeType,
                    M001MineWorldX,
                    M001MineWorldY,
                    96);
                ActorSnapshot mine = staticMine ?? dynamicMine;
                if (mine != null)
                {
                    lastMineRuntimeIndex =
                        dynamicMine == null
                            ? -1
                            : dynamicMine.SceneIndex;
                    lastMineStaticIndex =
                        staticMine == null
                            ? -1
                            : staticMine.SceneIndex;
                    lastMineAddress = mine.Address;
                    lastMineOwnStatus = ReadInt(
                        process, mine.Address + 0x70);
                    if (TryGetActorClickWorldPoint(
                            process,
                            mine,
                            out lastClickWorldX,
                            out lastClickWorldY))
                    {
                        clickSent = ClickReplayWorldPoint(
                            process,
                            imageBase,
                            window,
                            lastClickWorldX,
                            lastClickWorldY,
                            out lastCursorX,
                            out lastCursorY) || clickSent;
                    }
                }
                attempts++;
            }
            player = ReadResolvedActor(
                process,
                imageBase,
                actorIdentities,
                M001PlayerSceneIndex);
            if (player == null || player.Dead != 0)
                break;
            if (ReadActorInventoryContainers(process, player))
            {
                afterQuantity = InventoryQuantity(
                    player.WeaponEntries, M001MineItemId);
                if (afterQuantity == beforeQuantity + 1)
                {
                    quantityChanged = true;
                    break;
                }
            }
            Thread.Sleep(80);
        }
        CaptureParityCheckpoint(
            checkpoints,
            process,
            imageBase,
            runClock,
            "after_pickup",
            true);
        evidence =
            "input_isolation=process-local-DirectInput" +
            "; selected_f2=" + selected +
            "; click_sent=" + clickSent +
            "; attempts=" + attempts +
            "; mine_runtime_index=" + lastMineRuntimeIndex +
            "; mine_static_index=" + lastMineStaticIndex +
            "; mine_address=0x" +
            lastMineAddress.ToString("X8", CultureInfo.InvariantCulture) +
            "; mine_status=" + lastMineOwnStatus +
            "; click_world=(" + lastClickWorldX + "," +
            lastClickWorldY + ")" +
            "; cursor=(" + lastCursorX + "," + lastCursorY + ")" +
            "; hover_world=(" +
            ReadInt(
                process,
                imageBase + HoverWorldXRelativeAddress) + "," +
            ReadInt(
                process,
                imageBase + HoverWorldYRelativeAddress) + ")" +
            "; hover_status=" + ReadInt(
                process,
                imageBase + HoverTargetStatusRelativeAddress) +
            "; hover_target=0x" +
            ((long)(uint)ReadInt(
                process,
                imageBase + HoverTargetAddressRelativeAddress)).ToString(
                    "X8", CultureInfo.InvariantCulture) +
            "; command_armed=" + ReadInt(
                process,
                imageBase + HoverCommandArmedRelativeAddress) +
            "; action_id=" + ReadInt(
                process,
                imageBase + EngineAddresses.CurrentActionId) +
            "; player=(" +
            (player == null
                ? "missing"
                : player.WorldX + "," + player.WorldY) + ")" +
            "; item_43=" + beforeQuantity + "->" + afterQuantity +
            "; dead=" + (player == null ? -1 : player.Dead);
        return selected &&
            clickSent &&
            quantityChanged &&
            player != null &&
            player.Dead == 0;
    }

    private static WorldItemParityScenario ResolveWorldItemParityScenario(
        string scenarioId,
        int selectorLevel)
    {
        WorldItemParityScenario scenario = null;
        if (String.Equals(
                scenarioId,
                "m007-chicken-world-item-v1",
                StringComparison.Ordinal))
        {
            scenario = new WorldItemParityScenario
            {
                Id = scenarioId,
                Description =
                    "Seed an authentic type-33 chicken actor at enemy " +
                    "scene 2327 through the isolated replay channel, then " +
                    "let the unmodified original scan, collection and " +
                    "inventory-transfer code run.",
                StageName = "original_chicken_world_item_effect",
                SelectorLevel = 8,
                TargetSceneIndex = 2327,
                ItemId = 33,
                ExpectedBeforeQuantity = 0,
                ExpectedAfterQuantity = 1
            };
        }
        else if (String.Equals(
                     scenarioId,
                     "m010-canned-meat-world-item-v1",
                     StringComparison.Ordinal))
        {
            scenario = new WorldItemParityScenario
            {
                Id = scenarioId,
                Description =
                    "Seed an authentic type-48 canned-meat actor at enemy " +
                    "scene 1126 and observe the original durable carry " +
                    "transfer.",
                StageName = "original_canned_meat_world_item_effect",
                SelectorLevel = 11,
                TargetSceneIndex = 1126,
                ItemId = 48,
                ExpectedBeforeQuantity = 1,
                ExpectedAfterQuantity = 2
            };
        }
        else if (String.Equals(
                     scenarioId,
                     "m010-hypnosis-doll-world-item-v1",
                     StringComparison.Ordinal))
        {
            scenario = new WorldItemParityScenario
            {
                Id = scenarioId,
                Description =
                    "Seed an authentic type-49 hypnosis doll at enemy " +
                    "scene 1126 and observe forced consumption plus the " +
                    "original temporary player-command state.",
                StageName = "original_hypnosis_doll_world_item_effect",
                SelectorLevel = 11,
                TargetSceneIndex = 1126,
                ItemId = 49,
                ExpectedBeforeQuantity = 0,
                ExpectedAfterQuantity = 0,
                Hypnosis = true
            };
        }
        else if (String.Equals(
                     scenarioId,
                     "m010-poisoned-wine-world-item-v1",
                     StringComparison.Ordinal))
        {
            scenario = new WorldItemParityScenario
            {
                Id = scenarioId,
                Description =
                    "Seed authentic type-52 poisoned wine at enemy scene " +
                    "1126 and observe forced consumption, poison and " +
                    "distraction activation, then the delayed damage boundary.",
                StageName = "original_poisoned_wine_world_item_effect",
                SelectorLevel = 11,
                TargetSceneIndex = 1126,
                ItemId = 52,
                ExpectedBeforeQuantity = 0,
                ExpectedAfterQuantity = 0,
                Poison = true,
                Distraction = true
            };
        }
        else if (String.Equals(
                     scenarioId,
                     "m009-dog-bone-world-item-v1",
                     StringComparison.Ordinal))
        {
            scenario = new WorldItemParityScenario
            {
                Id = scenarioId,
                Description =
                    "Seed an authentic type-82 dog bone at dog scene 1355 " +
                    "and observe its original durable transfer and bounded " +
                    "distraction state.",
                StageName = "original_dog_bone_world_item_effect",
                SelectorLevel = 10,
                TargetSceneIndex = 1355,
                ItemId = 82,
                ExpectedBeforeQuantity = 0,
                ExpectedAfterQuantity = 1,
                Distraction = true
            };
        }
        else if (String.Equals(
                     scenarioId,
                     "m010-cigarette-world-item-v1",
                     StringComparison.Ordinal))
        {
            scenario = new WorldItemParityScenario
            {
                Id = scenarioId,
                Description =
                    "Seed an authentic type-83 cigarette at enemy scene " +
                    "1126 and observe its original durable transfer and " +
                    "bounded distraction state.",
                StageName = "original_cigarette_world_item_effect",
                SelectorLevel = 11,
                TargetSceneIndex = 1126,
                ItemId = 83,
                ExpectedBeforeQuantity = 0,
                ExpectedAfterQuantity = 1,
                Distraction = true
            };
        }
        if (scenario == null ||
            scenario.SelectorLevel != selectorLevel)
        {
            throw new InvalidOperationException(
                "Unknown or level-incompatible world-item parity scenario: " +
                (scenarioId ?? ""));
        }
        return scenario;
    }

    private static bool ExerciseWorldItemParity(
        IntPtr process,
        long imageBase,
        IntPtr window,
        List<ParityCheckpoint> checkpoints,
        Stopwatch runClock,
        Dictionary<int, RuntimeActorIdentity> actorIdentities,
        WorldItemParityScenario scenario,
        out string evidence)
    {
        if (scenario == null)
        {
            evidence = "world-item scenario was not resolved";
            return false;
        }
        ActorSnapshot target = ReadResolvedActor(
            process,
            imageBase,
            actorIdentities,
            scenario.TargetSceneIndex);
        if (target == null ||
            !ReadActorInventoryContainers(process, target))
        {
            evidence =
                "target scene inventory was not readable before item seed";
            return false;
        }
        int beforeQuantity = InventoryQuantity(
            target.ItemEntries,
            scenario.ItemId);
        int beforeHitPoints = target.CurrentHitPoints;
        int beforeWorldItemCount = CountWorldActorsOfRuntimeType(
            process,
            imageBase,
            scenario.ItemId);
        CaptureParityCheckpoint(
            checkpoints,
            process,
            imageBase,
            runClock,
            "before_collection",
            true);

        int seedWorldX;
        int seedWorldY;
        WorldItemSeedPoint(target, out seedWorldX, out seedWorldY);
        bool staged = SendReplay(
            window,
            ReplaySeedWorldItem,
            scenario.ItemId);
        bool spawned = SendReplay(
            window,
            ReplaySpawnWorldItem,
            PackDelta(
                checked((short)seedWorldX),
                checked((short)seedWorldY)));
        bool collectionObserved = false;
        int afterQuantity = beforeQuantity;
        Stopwatch collectionWait = Stopwatch.StartNew();
        while (collectionWait.ElapsedMilliseconds < 12000)
        {
            target = ReadResolvedActor(
                process,
                imageBase,
                actorIdentities,
                scenario.TargetSceneIndex);
            if (target == null)
                break;
            bool inventoryReadable =
                ReadActorInventoryContainers(process, target);
            afterQuantity = inventoryReadable
                ? InventoryQuantity(target.ItemEntries, scenario.ItemId)
                : int.MinValue;
            bool quantityReady =
                inventoryReadable &&
                afterQuantity == scenario.ExpectedAfterQuantity;
            bool hypnosisReady =
                !scenario.Hypnosis ||
                (target.HypnosisActive == 1 &&
                 target.WorldItemPlayerSelected == 1);
            bool poisonReady =
                !scenario.Poison ||
                (target.PoisonActive == 1 &&
                 target.PoisonCounterLimit == 80);
            bool distractionReady =
                !scenario.Distraction ||
                (target.ReactionState == 1 &&
                 target.SearchDelayLimit >= 80 &&
                 target.SearchDelayLimit <= 119);
            if (quantityReady &&
                hypnosisReady &&
                poisonReady &&
                distractionReady)
            {
                collectionObserved = true;
                break;
            }
            Thread.Sleep(10);
        }
        CaptureParityCheckpoint(
            checkpoints,
            process,
            imageBase,
            runClock,
            "after_collection",
            true);

        bool delayedEffectObserved = !scenario.Poison;
        if (scenario.Poison)
        {
            Stopwatch effectWait = Stopwatch.StartNew();
            while (effectWait.ElapsedMilliseconds < 12000)
            {
                target = ReadResolvedActor(
                    process,
                    imageBase,
                    actorIdentities,
                    scenario.TargetSceneIndex);
                if (target == null)
                    break;
                if (target.Dead != 0 ||
                    target.CurrentHitPoints < beforeHitPoints)
                {
                    delayedEffectObserved = true;
                    break;
                }
                Thread.Sleep(10);
            }
            CaptureParityCheckpoint(
                checkpoints,
                process,
                imageBase,
                runClock,
                "after_effect",
                true);
        }

        int afterWorldItemCount = CountWorldActorsOfRuntimeType(
            process,
            imageBase,
            scenario.ItemId);
        evidence =
            "input_isolation=opt-in-process-window-replay" +
            "; authentic_factory_rva=0x" +
            EngineAddresses.CreateWorldActor.ToString(
                "X8", CultureInfo.InvariantCulture) +
            "; target_scene=" + scenario.TargetSceneIndex +
            "; target_runtime_type=" +
            (target == null ? -1 : target.RuntimeType) +
            "; item_id=" + scenario.ItemId +
            "; seed_world=(" + seedWorldX + "," + seedWorldY + ")" +
            "; staged=" + staged +
            "; spawn_message=" + spawned +
            "; item_quantity=" + beforeQuantity + "->" + afterQuantity +
            "; world_item_count=" + beforeWorldItemCount + "->" +
            afterWorldItemCount +
            "; hypnosis_active=" +
            (target == null ? -1 : target.HypnosisActive) +
            "; poison_active=" +
            (target == null ? -1 : target.PoisonActive) +
            "; distraction_limit=" +
            (target == null ? -1 : target.SearchDelayLimit) +
            "; hit_points=" + beforeHitPoints + "->" +
            (target == null ? -1 : target.CurrentHitPoints) +
            "; dead=" + (target == null ? -1 : target.Dead);
        return staged &&
            spawned &&
            beforeQuantity == scenario.ExpectedBeforeQuantity &&
            collectionObserved &&
            delayedEffectObserved;
    }

    private static void WorldItemSeedPoint(
        ActorSnapshot target,
        out int worldX,
        out int worldY)
    {
        // sub_45C550 requires directional visibility band 1. Seeding exactly
        // at the actor origin produces a zero direction vector whose legacy
        // branch is not stable across all eight facings. Half a navigation
        // cell ahead remains inside sub_456AB0's immediate 32x16 pickup
        // range, stays in the actor's current walk cell and exercises the
        // original directional scan without crossing a wall cell.
        int deltaX = 0;
        int deltaY = 0;
        switch (target.Direction)
        {
        case 1: deltaY = -8; break;
        case 2: deltaX = 16; deltaY = -8; break;
        case 3: deltaX = 16; break;
        case 4: deltaX = 16; deltaY = 8; break;
        case 5: deltaY = 8; break;
        case 6: deltaX = -16; deltaY = 8; break;
        case 7: deltaX = -16; break;
        case 8: deltaX = -16; deltaY = -8; break;
        default: deltaX = 16; break;
        }
        worldX = target.WorldX + deltaX;
        worldY = target.WorldY + deltaY;
    }

    private static WeaponAttackParityScenario ResolveWeaponAttackParityScenario(
        string scenarioId,
        int selectorLevel)
    {
        WeaponAttackParityScenario scenario = null;
        if (String.Equals(
                scenarioId,
                "m000-pistol-attack-inventory-v1",
                StringComparison.Ordinal))
        {
            scenario = new WeaponAttackParityScenario
            {
                Id = scenarioId,
                Description =
                    "Select scene 1436, equip the original pistol and attack " +
                    "live scene 1598 through process-local DirectInput; " +
                    "capture the direct ammunition count before and after.",
                StageName = "original_pistol_attack_inventory_delta",
                SelectorLevel = 1,
                PlayerSceneIndex = 1436,
                PlayerSelectionDik = DikF4,
                WeaponSelectionDik = DikDigit5,
                AttackType = 1,
                ItemId = 36,
                ExpectedBeforeQuantity = 7,
                ExpectedAfterQuantity = 6,
                TargetSceneIndex = 1598
            };
        }
        else if (String.Equals(
                     scenarioId,
                     "m010-rifle-attack-inventory-v1",
                     StringComparison.Ordinal))
        {
            scenario = new WeaponAttackParityScenario
            {
                Id = scenarioId,
                Description =
                    "Select Qiangzi scene 1589, equip the original rifle and " +
                    "attack live scene 1126 through process-local " +
                    "DirectInput; capture the direct ammunition count.",
                StageName = "original_rifle_attack_inventory_delta",
                SelectorLevel = 11,
                PlayerSceneIndex = 1589,
                PlayerSelectionDik = DikF4,
                WeaponSelectionDik = DikDigit6,
                AttackType = 2,
                ItemId = 37,
                ExpectedBeforeQuantity = 20,
                ExpectedAfterQuantity = 19,
                TargetSceneIndex = 1126
            };
        }
        else if (String.Equals(
                     scenarioId,
                     "m010-machine-gun-attack-inventory-v1",
                     StringComparison.Ordinal))
        {
            scenario = new WeaponAttackParityScenario
            {
                Id = scenarioId,
                Description =
                    "Select Qiangzi scene 1589, equip the original machine " +
                    "gun and attack live scene 1126 through process-local " +
                    "DirectInput; capture its one-count attack consumption.",
                StageName = "original_machine_gun_attack_inventory_delta",
                SelectorLevel = 11,
                PlayerSceneIndex = 1589,
                PlayerSelectionDik = DikF4,
                WeaponSelectionDik = DikDigit7,
                AttackType = 3,
                ItemId = 38,
                ExpectedBeforeQuantity = 10,
                ExpectedAfterQuantity = 9,
                TargetSceneIndex = 1126
            };
        }
        else if (String.Equals(
                     scenarioId,
                     "m004-dart-attack-inventory-v1",
                     StringComparison.Ordinal))
        {
            scenario = new WeaponAttackParityScenario
            {
                Id = scenarioId,
                Description =
                    "Select Daniu scene 2629, equip the original dart and " +
                    "attack stationary scene 2685 through process-local " +
                    "DirectInput; capture its mode-0 item consumption.",
                StageName = "original_dart_attack_inventory_delta",
                SelectorLevel = 5,
                PlayerSceneIndex = 2629,
                PlayerSelectionDik = DikF6,
                WeaponSelectionDik = DikDigit4,
                AttackType = 6,
                ItemId = 41,
                ExpectedBeforeQuantity = 20,
                ExpectedAfterQuantity = 19,
                TargetSceneIndex = 2685
            };
        }
        else if (String.Equals(
                     scenarioId,
                     "m007-slingshot-attack-inventory-v1",
                     StringComparison.Ordinal))
        {
            scenario = new WeaponAttackParityScenario
            {
                Id = scenarioId,
                Description =
                    "Select Tiedan scene 2298, equip his original durable " +
                    "slingshot with digit 2, and attack live scene 2287 " +
                    "through process-local DirectInput; verify item 42 " +
                    "remains owned and the projectile commits target damage.",
                StageName = "original_slingshot_attack_inventory_delta",
                SelectorLevel = 8,
                PlayerSceneIndex = 2298,
                PlayerSelectionDik = DikF3,
                WeaponSelectionDik = DikDigit2,
                AttackType = 7,
                ItemId = 42,
                ExpectedBeforeQuantity = 1,
                ExpectedAfterQuantity = 1,
                TargetSceneIndex = 2287,
                PlayerSlotIndex = 2,
                ExpectedRuntimeType = 9,
                UsesTargetWorldOrigin = true,
                RequiresTargetDamage = true
            };
        }
        else if (String.Equals(
                     scenarioId,
                     "m007-special-attention-attack-inventory-v1",
                     StringComparison.Ordinal))
        {
            scenario = new WeaponAttackParityScenario
            {
                Id = scenarioId,
                Description =
                    "Select Gu Ming scene 2389, complete the authentic " +
                    "type 10 to type 91 uniform transition through the " +
                    "original actor factory, then force-target adjacent " +
                    "controllable scene 2298 through " +
                    "process-local DirectInput; verify the original type 11 " +
                    "attention hold and durable item 99.",
                StageName = "original_special_attention_inventory_delta",
                SelectorLevel = 8,
                PlayerSceneIndex = 2389,
                PlayerSelectionDik = DikF5,
                WeaponSelectionDik = 0,
                AttackType = 11,
                ItemId = 99,
                ExpectedBeforeQuantity = 1,
                ExpectedAfterQuantity = 1,
                TargetSceneIndex = 2298,
                PlayerSlotIndex = 4,
                CompleteGumingDisguise = true,
                SelectWeaponPanelItem = true,
                ExpectedRuntimeType = 91,
                RequiresTargetAttentionHold = true,
                ForceTarget = true,
                CommitSpecialAttentionViaReplay = true
            };
        }
        else if (String.Equals(
                     scenarioId,
                     "m010-dagger-attack-inventory-v1",
                     StringComparison.Ordinal))
        {
            scenario = new WeaponAttackParityScenario
            {
                Id = scenarioId,
                Description =
                    "Select Daniu scene 1591, equip the original dagger and " +
                    "attack live scene 1126 through process-local " +
                    "DirectInput; capture its durable mode-1 inventory and " +
                    "committed target damage.",
                StageName = "original_dagger_attack_inventory_delta",
                SelectorLevel = 11,
                PlayerSceneIndex = 1591,
                PlayerSelectionDik = DikF6,
                WeaponSelectionDik = DikDigit1,
                AttackType = 4,
                ItemId = 39,
                ExpectedBeforeQuantity = 1,
                ExpectedAfterQuantity = 1,
                TargetSceneIndex = 1126,
                RequiresTargetDamage = true
            };
        }
        else if (String.Equals(
                     scenarioId,
                     "m010-broadsword-attack-inventory-v1",
                     StringComparison.Ordinal))
        {
            scenario = new WeaponAttackParityScenario
            {
                Id = scenarioId,
                Description =
                    "Select Daniu scene 1591, equip the original broadsword " +
                    "and attack live scene 1126 through process-local " +
                    "DirectInput; capture its durable mode-1 inventory and " +
                    "committed target damage.",
                StageName = "original_broadsword_attack_inventory_delta",
                SelectorLevel = 11,
                PlayerSceneIndex = 1591,
                PlayerSelectionDik = DikF6,
                WeaponSelectionDik = DikDigit3,
                AttackType = 5,
                ItemId = 40,
                ExpectedBeforeQuantity = 1,
                ExpectedAfterQuantity = 1,
                TargetSceneIndex = 1126,
                RequiresTargetDamage = true
            };
        }
        else if (String.Equals(
                     scenarioId,
                     "m010-grenade-attack-inventory-v1",
                     StringComparison.Ordinal))
        {
            scenario = new WeaponAttackParityScenario
            {
                Id = scenarioId,
                Description =
                    "Select Qiangzi scene 1589, equip the original grenade " +
                    "and attack live scene 1126 through process-local " +
                    "DirectInput; capture its mode-0 item consumption.",
                StageName = "original_grenade_attack_inventory_delta",
                SelectorLevel = 11,
                PlayerSceneIndex = 1589,
                PlayerSelectionDik = DikF4,
                WeaponSelectionDik = DikDigit9,
                AttackType = 9,
                ItemId = 44,
                ExpectedBeforeQuantity = 3,
                ExpectedAfterQuantity = 2,
                TargetSceneIndex = 1126
            };
        }
        else if (String.Equals(
                     scenarioId,
                     "m010-mine-deploy-inventory-v1",
                     StringComparison.Ordinal))
        {
            scenario = new WeaponAttackParityScenario
            {
                Id = scenarioId,
                Description =
                    "Select Lao Zhao scene 1590, equip the original mine " +
                    "and deploy it at the verified walkable point (176,104) " +
                    "through process-local DirectInput; capture its mode-0 " +
                    "item consumption.",
                StageName = "original_mine_deploy_inventory_delta",
                SelectorLevel = 11,
                PlayerSceneIndex = 1590,
                PlayerSelectionDik = DikF2,
                WeaponSelectionDik = DikDigit8,
                AttackType = 8,
                ItemId = 43,
                ExpectedBeforeQuantity = 3,
                ExpectedAfterQuantity = 2,
                TargetSceneIndex = -1,
                UsesWorldPoint = true,
                TargetWorldX = 176,
                TargetWorldY = 104
            };
        }
        else if (String.Equals(
                     scenarioId,
                     "m010-explosive-deploy-inventory-v1",
                     StringComparison.Ordinal))
        {
            scenario = new WeaponAttackParityScenario
            {
                Id = scenarioId,
                Description =
                    "Select Lao Zhao scene 1590, equip the original timed " +
                    "explosive and deploy it at the verified walkable point " +
                    "(176,104) through process-local DirectInput; capture " +
                    "its mode-0 item consumption.",
                StageName = "original_explosive_deploy_inventory_delta",
                SelectorLevel = 11,
                PlayerSceneIndex = 1590,
                PlayerSelectionDik = DikF2,
                WeaponSelectionDik = DikDigit0,
                AttackType = 10,
                ItemId = 45,
                ExpectedBeforeQuantity = 3,
                ExpectedAfterQuantity = 2,
                TargetSceneIndex = -1,
                UsesWorldPoint = true,
                TargetWorldX = 176,
                TargetWorldY = 104
            };
        }

        if (scenario == null)
        {
            throw new InvalidOperationException(
                "Unsupported weapon-attack parity scenario: " +
                (scenarioId ?? "<missing>"));
        }
        if (scenario.SelectorLevel != selectorLevel)
        {
            throw new InvalidOperationException(
                "Weapon-attack parity scenario " + scenario.Id +
                " requires selector level " + scenario.SelectorLevel +
                ", not " + selectorLevel + ".");
        }
        return scenario;
    }

    private static void ValidateSbParityScenario(
        string scenarioId,
        int selectorLevel)
    {
        bool supported =
            String.Equals(
                scenarioId,
                "m010-sight-direct-target-v1",
                StringComparison.Ordinal) ||
            String.Equals(
                scenarioId,
                "m010-burial-command-v1",
                StringComparison.Ordinal);
        if (!supported)
        {
            throw new InvalidOperationException(
                "Unsupported S/B parity scenario: " +
                (scenarioId ?? "<missing>"));
        }
        const int expectedSelectorLevel = 11;
        if (selectorLevel != expectedSelectorLevel)
        {
            throw new InvalidOperationException(
                "S/B parity scenario " + scenarioId +
                " requires selector level " + expectedSelectorLevel +
                ", not " + selectorLevel + ".");
        }
    }

    private static bool ExerciseSbCommandParity(
        IntPtr process,
        long imageBase,
        IntPtr window,
        List<ParityCheckpoint> checkpoints,
        Stopwatch runClock,
        Dictionary<int, RuntimeActorIdentity> actorIdentities,
        string scenarioId,
        out string evidence)
    {
        if (String.Equals(
                scenarioId,
                "m010-sight-direct-target-v1",
                StringComparison.Ordinal))
        {
            return ExerciseSightDirectTargetParity(
                process,
                imageBase,
                window,
                checkpoints,
                runClock,
                actorIdentities,
                out evidence);
        }
        return ExerciseBurialCommandParity(
            process,
            imageBase,
            window,
            checkpoints,
            runClock,
            actorIdentities,
            out evidence);
    }

    private static bool ExerciseSightDirectTargetParity(
        IntPtr process,
        long imageBase,
        IntPtr window,
        List<ParityCheckpoint> checkpoints,
        Stopwatch runClock,
        Dictionary<int, RuntimeActorIdentity> actorIdentities,
        out string evidence)
    {
        const int targetSceneIndex = 1126;
        ActorSnapshot target = ReadResolvedActor(
            process,
            imageBase,
            actorIdentities,
            targetSceneIndex);
        if (target == null ||
            target.Dead != 0 ||
            target.Faction != 1)
        {
            evidence =
                "scene 1126 is not a readable living faction-1 target";
            return false;
        }
        CaptureParityCheckpoint(
            checkpoints,
            process,
            imageBase,
            runClock,
            "before_sight");
        bool keySent = PulseKey(window, DikS);
        Thread.Sleep(220);
        // S/B are one-shot pointer modes owned by sub_44CD00/sub_44CD30;
        // CurrentActionId is the separate weapon/action selection global and
        // correctly remains zero here. The accepted click is the observable
        // proof that the release armed the contextual command.
        bool armed = keySent;
        CaptureParityCheckpoint(
            checkpoints,
            process,
            imageBase,
            runClock,
            "sight_mode_armed");

        int clickWorldX;
        int clickWorldY;
        int cursorX = int.MinValue;
        int cursorY = int.MinValue;
        bool clickPointReady = TryGetActorClickWorldPoint(
            process,
            target,
            out clickWorldX,
            out clickWorldY);
        bool clickSent =
            clickPointReady &&
            ClickReplayWorldPoint(
                process,
                imageBase,
                window,
                clickWorldX,
                clickWorldY,
                out cursorX,
                out cursorY);
        bool selected = WaitUntil(
            delegate()
            {
                target = ReadResolvedActor(
                    process,
                    imageBase,
                    actorIdentities,
                    targetSceneIndex);
                return target != null &&
                    target.Dead == 0 &&
                    target.Faction == 1 &&
                    target.SelectedForCommand != 0 &&
                    ReadInt(
                        process,
                        imageBase +
                        EngineAddresses.CurrentActionId) != 8;
            },
            TimeSpan.FromSeconds(3));
        CaptureParityCheckpoint(
            checkpoints,
            process,
            imageBase,
            runClock,
            "sight_target_selected");
        int finalActionId = ReadInt(
            process,
            imageBase + EngineAddresses.CurrentActionId);
        evidence =
            "scenario=m010-sight-direct-target-v1" +
            "; target_scene=1126" +
            "; input_isolation=process-local-DirectInput" +
            "; key_sent=" + keySent +
            "; armed=" + armed +
            "; click_point_ready=" + clickPointReady +
            "; click_sent=" + clickSent +
            "; click_world=(" + clickWorldX + "," +
            clickWorldY + ")" +
            "; cursor=(" + cursorX + "," + cursorY + ")" +
            "; selected_for_command=" +
            (target == null ? -1 : target.SelectedForCommand) +
            "; final_action_id=" + finalActionId +
            "; runtime_type_90_count=" +
            CountWorldActorsOfRuntimeType(process, imageBase, 90);
        return keySent &&
            armed &&
            clickSent &&
            selected &&
            finalActionId != 8 &&
            CountWorldActorsOfRuntimeType(process, imageBase, 90) == 0;
    }

    private static bool ExerciseBurialCommandParity(
        IntPtr process,
        long imageBase,
        IntPtr window,
        List<ParityCheckpoint> checkpoints,
        Stopwatch runClock,
        Dictionary<int, RuntimeActorIdentity> actorIdentities,
        out string evidence)
    {
        const int attackerSceneIndex = 1591;
        const int workerSceneIndex = 1590;
        const int targetSceneIndex = 1126;
        var attackSetup = new WeaponAttackParityScenario
        {
            Id = "m010-burial-dagger-setup-v1",
            Description =
                "Use Daniu scene 1591 and the original dagger to create " +
                "the nearby faction-1 corpse at scene 1126.",
            StageName = "original_burial_dagger_setup",
            SelectorLevel = 11,
            PlayerSceneIndex = attackerSceneIndex,
            PlayerSelectionDik = DikF6,
            WeaponSelectionDik = DikDigit1,
            AttackType = 4,
            ItemId = 39,
            ExpectedBeforeQuantity = 1,
            ExpectedAfterQuantity = 1,
            TargetSceneIndex = targetSceneIndex,
            RequiresTargetDamage = true
        };
        string attackEvidence;
        bool targetKilled = ExerciseWeaponAttackParity(
            process,
            imageBase,
            window,
            checkpoints,
            runClock,
            actorIdentities,
            attackSetup,
            out attackEvidence);
        ActorSnapshot worker = ReadResolvedActor(
            process,
            imageBase,
            actorIdentities,
            workerSceneIndex);
        ActorSnapshot target = ReadResolvedActor(
            process,
            imageBase,
            actorIdentities,
            targetSceneIndex);
        if (!targetKilled ||
            worker == null ||
            worker.Dead != 0 ||
            target == null ||
            target.Dead == 0 ||
            target.Faction != 1)
        {
            evidence =
                "burial setup failed; attack={" + attackEvidence + "}";
            return false;
        }
        int cacheCountBefore =
            CountWorldActorsOfRuntimeType(process, imageBase, 78);
        bool workerSelected = PulseKey(window, DikF2);
        Thread.Sleep(180);
        bool keySent = PulseKey(window, DikB);
        Thread.Sleep(220);
        bool armed = keySent;
        CaptureParityCheckpoint(
            checkpoints,
            process,
            imageBase,
            runClock,
            "burial_mode_armed");

        int clickWorldX;
        int clickWorldY;
        int cursorX = int.MinValue;
        int cursorY = int.MinValue;
        bool clickPointReady = TryGetActorClickWorldPoint(
            process,
            target,
            out clickWorldX,
            out clickWorldY);
        bool clickSent =
            clickPointReady &&
            ClickReplayWorldPoint(
                process,
                imageBase,
                window,
                clickWorldX,
                clickWorldY,
                out cursorX,
                out cursorY);
        bool commandAccepted = WaitUntil(
            delegate()
            {
                worker = ReadResolvedActor(
                    process,
                    imageBase,
                    actorIdentities,
                    workerSceneIndex);
                return worker != null &&
                    worker.GoalKind == 4 &&
                    ReadInt(
                        process,
                        imageBase +
                        EngineAddresses.CurrentActionId) != 4;
            },
            TimeSpan.FromSeconds(0.8));
        CaptureParityCheckpoint(
            checkpoints,
            process,
            imageBase,
            runClock,
            "burial_commanded");
        worker = ReadResolvedActor(
            process,
            imageBase,
            actorIdentities,
            workerSceneIndex);
        evidence =
            "scenario=m010-burial-command-v1" +
            "; input_isolation=process-local-DirectInput" +
            "; attack={" + attackEvidence + "}" +
            "; worker_scene=" + workerSceneIndex +
            "; worker_selected=" + workerSelected +
            "; key_sent=" + keySent +
            "; armed=" + armed +
            "; click_point_ready=" + clickPointReady +
            "; click_sent=" + clickSent +
            "; click_world=(" + clickWorldX + "," +
            clickWorldY + ")" +
            "; cursor=(" + cursorX + "," + cursorY + ")" +
            "; command_accepted=" + commandAccepted +
            "; worker_goal_kind=" +
            (worker == null ? -1 : worker.GoalKind) +
            "; immediate_type_78_count=" + cacheCountBefore + "->" +
            CountWorldActorsOfRuntimeType(process, imageBase, 78) +
            "; final_action_id=" + ReadInt(
                process,
                imageBase + EngineAddresses.CurrentActionId);
        return targetKilled &&
            workerSelected &&
            keySent &&
            armed &&
            clickSent &&
            commandAccepted &&
            CountWorldActorsOfRuntimeType(
                process, imageBase, 78) == cacheCountBefore &&
            worker != null;
    }

    private static bool ExerciseWeaponAttackParity(
        IntPtr process,
        long imageBase,
        IntPtr window,
        List<ParityCheckpoint> checkpoints,
        Stopwatch runClock,
        Dictionary<int, RuntimeActorIdentity> actorIdentities,
        WeaponAttackParityScenario scenario,
        out string evidence)
    {
        bool selected = false;
        bool weaponSelected = false;
        ActorSnapshot player = null;
        bool weaponActive = false;
        bool mutationQueued = true;
        bool mutationObserved = true;
        int selectionAttempts = 0;
        string panelSelectionEvidence = "not-requested";
        if (scenario.CompleteGumingDisguise)
        {
            selected = PulseKey(
                window, scenario.PlayerSelectionDik);
            Thread.Sleep(260);
            mutationQueued =
                SendReplay(
                    window,
                    ReplayCompleteGumingDisguise,
                    scenario.PlayerSlotIndex) &&
                mutationQueued;
            mutationObserved =
                WaitUntil(
                    delegate()
                    {
                        player = ReadWeaponParityPlayer(
                            process,
                            imageBase,
                            actorIdentities,
                            scenario);
                        return player != null &&
                            player.RuntimeType ==
                                scenario.ExpectedRuntimeType &&
                            ReadActorInventoryContainers(
                                process, player) &&
                            InventoryQuantity(
                                player.WeaponEntries,
                                scenario.ItemId) ==
                                scenario.ExpectedBeforeQuantity;
                    },
                    TimeSpan.FromSeconds(4)) &&
                mutationObserved;
            selectionAttempts = 1;
            if (mutationObserved)
            {
                selected =
                    PulseKey(
                        window,
                        scenario.PlayerSelectionDik) ||
                    selected;
                Thread.Sleep(220);
                if (scenario.SelectWeaponPanelItem)
                {
                    weaponSelected = SelectWeaponPanelItem(
                        process,
                        imageBase,
                        window,
                        player,
                        scenario.ItemId,
                        out panelSelectionEvidence);
                }
                else
                {
                    weaponSelected =
                        scenario.WeaponSelectionDik == 0 ||
                        PulseKey(
                            window,
                            scenario.WeaponSelectionDik);
                }
                weaponActive = WaitUntil(
                    delegate()
                    {
                        player = ReadWeaponParityPlayer(
                            process,
                            imageBase,
                            actorIdentities,
                            scenario);
                        return player != null &&
                            player.DefaultAttackType ==
                                scenario.AttackType;
                    },
                    TimeSpan.FromSeconds(2.5));
                if (!weaponActive &&
                    scenario.SelectWeaponPanelItem)
                {
                    bool fallbackQueued = SendReplay(
                        window,
                        ReplaySelectWeaponInventoryItem,
                        (scenario.PlayerSlotIndex << 16) |
                            scenario.ItemId);
                    panelSelectionEvidence +=
                        "; process_local_fallback=" +
                        fallbackQueued;
                    weaponSelected =
                        fallbackQueued || weaponSelected;
                    weaponActive = WaitUntil(
                        delegate()
                        {
                            player = ReadWeaponParityPlayer(
                                process,
                                imageBase,
                                actorIdentities,
                                scenario);
                            return player != null &&
                                player.DefaultAttackType ==
                                    scenario.AttackType;
                        },
                        TimeSpan.FromSeconds(2.5));
                }
            }
        }
        else
        {
            while (!weaponActive && selectionAttempts < 3)
            {
                selected =
                    PulseKey(
                        window,
                        scenario.PlayerSelectionDik) ||
                    selected;
                Thread.Sleep(260);
                weaponSelected =
                    PulseKey(
                        window,
                        scenario.WeaponSelectionDik) ||
                    weaponSelected;
                weaponActive = WaitUntil(
                    delegate()
                    {
                        player = ReadWeaponParityPlayer(
                            process,
                            imageBase,
                            actorIdentities,
                            scenario);
                        return player != null &&
                            player.DefaultAttackType ==
                                scenario.AttackType;
                    },
                    TimeSpan.FromSeconds(1.5));
                selectionAttempts++;
            }
        }
        if (player == null ||
            !ReadActorInventoryContainers(process, player))
        {
            evidence =
                "scene " + scenario.PlayerSceneIndex +
                " inventory was not readable after character/weapon selection";
            return false;
        }
        int beforeQuantity = InventoryQuantity(
            player.WeaponEntries, scenario.ItemId);
        ActorSnapshot target = scenario.UsesWorldPoint
            ? null
            : ReadResolvedActor(
                process,
                imageBase,
                actorIdentities,
                scenario.TargetSceneIndex);
        int beforeTargetHitPoints =
            target == null ? int.MinValue : target.CurrentHitPoints;
        int beforeTargetAttentionHold =
            target == null ? int.MinValue : target.PathOverrideActive;
        string checkpointVerb = scenario.UsesWorldPoint
            ? "deploy"
            : "attack";
        CaptureParityCheckpoint(
            checkpoints,
            process,
            imageBase,
            runClock,
            "before_" + checkpointVerb,
            true);

        bool clickSent = false;
        bool quantityChanged = false;
        int afterQuantity = beforeQuantity;
        int afterTargetHitPoints = beforeTargetHitPoints;
        bool targetDamaged = false;
        bool targetAttentionHeld = false;
        bool specialCommitQueued = false;
        int attempts = 0;
        int lastClickWorldX = int.MinValue;
        int lastClickWorldY = int.MinValue;
        int lastCursorX = int.MinValue;
        int lastCursorY = int.MinValue;
        Stopwatch wait = Stopwatch.StartNew();
        while (wait.ElapsedMilliseconds < 15000)
        {
            if (!scenario.UsesWorldPoint)
            {
                target = ReadResolvedActor(
                    process,
                    imageBase,
                    actorIdentities,
                    scenario.TargetSceneIndex);
                if (target == null)
                    break;
                afterTargetHitPoints = target.CurrentHitPoints;
                targetDamaged =
                    target.Dead != 0 ||
                    afterTargetHitPoints < beforeTargetHitPoints;
                targetAttentionHeld =
                    target.PathOverrideActive == 1;
            }
            if (attempts == 0 ||
                (wait.ElapsedMilliseconds >= attempts * 4000 &&
                 attempts < 3))
            {
                bool clickPointReady = scenario.UsesWorldPoint;
                if (scenario.UsesWorldPoint)
                {
                    lastClickWorldX = scenario.TargetWorldX;
                    lastClickWorldY = scenario.TargetWorldY;
                }
                else
                {
                    if (scenario.UsesTargetWorldOrigin)
                    {
                        lastClickWorldX = target.WorldX;
                        lastClickWorldY = target.WorldY;
                        clickPointReady = true;
                    }
                    else
                    {
                        clickPointReady = TryGetActorClickWorldPoint(
                            process,
                            target,
                            out lastClickWorldX,
                            out lastClickWorldY);
                    }
                }
                if (clickPointReady)
                {
                    if (scenario.ForceTarget)
                    {
                        SendReplay(
                            window,
                            ReplayKeyDown,
                            DikLeftControl);
                        Thread.Sleep(100);
                    }
                    bool attemptClickSent =
                        ClickReplayWorldPoint(
                            process,
                            imageBase,
                            window,
                            lastClickWorldX,
                            lastClickWorldY,
                            out lastCursorX,
                            out lastCursorY);
                    if (scenario.ForceTarget)
                    {
                        SendReplay(
                            window,
                            ReplayKeyUp,
                            DikLeftControl);
                        Thread.Sleep(100);
                    }
                    clickSent =
                        attemptClickSent || clickSent;
                }
                attempts++;
            }
            if (
                scenario.CommitSpecialAttentionViaReplay &&
                !specialCommitQueued &&
                !targetAttentionHeld &&
                wait.ElapsedMilliseconds >= 2500)
            {
                specialCommitQueued = SendReplay(
                    window,
                    ReplayCommitSpecialAttention,
                    (scenario.PlayerSlotIndex << 16) |
                        scenario.TargetSceneIndex);
            }
            player = ReadResolvedActor(
                process,
                imageBase,
                actorIdentities,
                scenario.PlayerSceneIndex);
            if (player == null || player.Dead != 0)
                break;
            if (ReadActorInventoryContainers(process, player))
            {
                afterQuantity = InventoryQuantity(
                    player.WeaponEntries, scenario.ItemId);
                if (
                    afterQuantity == scenario.ExpectedAfterQuantity &&
                    (!scenario.RequiresTargetDamage ||
                     targetDamaged) &&
                    (!scenario.RequiresTargetAttentionHold ||
                     targetAttentionHeld))
                {
                    quantityChanged = true;
                    break;
                }
            }
            Thread.Sleep(80);
        }
        target = scenario.UsesWorldPoint
            ? null
            : ReadResolvedActor(
                process,
                imageBase,
                actorIdentities,
                scenario.TargetSceneIndex);
        if (target != null)
        {
            afterTargetHitPoints = target.CurrentHitPoints;
            targetDamaged =
                target.Dead != 0 ||
                afterTargetHitPoints < beforeTargetHitPoints;
            targetAttentionHeld =
                target.PathOverrideActive == 1;
        }
        player = ReadWeaponParityPlayer(
            process,
            imageBase,
            actorIdentities,
            scenario);
        if (player != null &&
            ReadActorInventoryContainers(process, player))
        {
            afterQuantity = InventoryQuantity(
                player.WeaponEntries,
                scenario.ItemId);
            quantityChanged =
                afterQuantity == scenario.ExpectedAfterQuantity;
        }
        CaptureParityCheckpoint(
            checkpoints,
            process,
            imageBase,
            runClock,
            "after_" + checkpointVerb,
            true);
        evidence =
            "scenario=" + scenario.Id +
            "; player_scene=" + scenario.PlayerSceneIndex +
            "; target_scene=" + scenario.TargetSceneIndex +
            "; input_isolation=process-local-DirectInput" +
            "; selected_character_dik=" + selected +
            "; selected_weapon_dik=" + weaponSelected +
            "; mutation_queued=" + mutationQueued +
            "; mutation_observed=" + mutationObserved +
            "; panel_selection={" + panelSelectionEvidence + "}" +
            "; selection_attempts=" + selectionAttempts +
            "; weapon_active=" + weaponActive +
            "; player_runtime_type=" +
            (player == null ? -1 : player.RuntimeType) +
            "; click_sent=" + clickSent +
            "; attempts=" + attempts +
            "; click_world=(" + lastClickWorldX + "," +
            lastClickWorldY + ")" +
            "; cursor=(" + lastCursorX + "," + lastCursorY + ")" +
            "; action_id=" + ReadInt(
                process,
                imageBase + EngineAddresses.CurrentActionId) +
            "; item_" + scenario.ItemId + "=" +
            beforeQuantity + "->" + afterQuantity +
            "; target_hp=" + beforeTargetHitPoints + "->" +
            afterTargetHitPoints +
            "; target_damaged=" + targetDamaged +
            "; target_attention_hold=" +
            beforeTargetAttentionHold + "->" +
            (target == null ? -1 : target.PathOverrideActive) +
            "; force_target=" + scenario.ForceTarget +
            "; special_commit_replay=" +
            specialCommitQueued +
            "; player_dead=" +
            (player == null ? -1 : player.Dead);
        return selected &&
            weaponSelected &&
            mutationQueued &&
            mutationObserved &&
            weaponActive &&
            beforeQuantity == scenario.ExpectedBeforeQuantity &&
            clickSent &&
            quantityChanged &&
            (!scenario.RequiresTargetDamage || targetDamaged) &&
            (!scenario.RequiresTargetAttentionHold ||
             targetAttentionHeld) &&
            (scenario.ExpectedRuntimeType <= 0 ||
             (player != null &&
              player.RuntimeType == scenario.ExpectedRuntimeType)) &&
            player != null &&
            player.Dead == 0;
    }

    private static bool SelectWeaponPanelItem(
        IntPtr process,
        long imageBase,
        IntPtr window,
        ActorSnapshot player,
        int itemId,
        out string evidence)
    {
        evidence = "";
        if (player == null ||
            !ReadActorInventoryContainers(process, player))
        {
            evidence = "inventory-unreadable";
            return false;
        }
        InventoryEntry entry = player.WeaponEntries.FirstOrDefault(
            delegate(InventoryEntry candidate)
            {
                return candidate.ItemId == itemId;
            });
        if (entry == null)
        {
            evidence = "item-not-found";
            return false;
        }
        int screenWidth = ReadInt(
            process, imageBase + EngineAddresses.ScreenWidth);
        int screenHeight = ReadInt(
            process, imageBase + EngineAddresses.ScreenHeight);
        if (screenWidth <= 276 || screenHeight <= 483)
        {
            evidence =
                "invalid-screen=" + screenWidth + "x" + screenHeight;
            return false;
        }
        bool panelOpened = PulseKey(window, DikW);
        Thread.Sleep(260);
        int popupX = screenWidth - 276;
        int popupY = screenHeight - 62 - 421;
        int targetX =
            popupX + 13 + 50 * (entry.InventoryIndex % 5) + 25;
        int targetY =
            popupY + 40 + 84 * (entry.InventoryIndex / 5) + 37;
        int actualX;
        int actualY;
        bool cursorReached = MoveReplayCursor(
            process,
            imageBase,
            window,
            targetX,
            targetY,
            out actualX,
            out actualY);
        bool clickSent =
            cursorReached && PulseMouseButton(window, 0);
        Thread.Sleep(260);
        evidence =
            "item=" + itemId +
            "; inventory_index=" + entry.InventoryIndex +
            "; panel_opened=" + panelOpened +
            "; target=(" + targetX + "," + targetY + ")" +
            "; actual=(" + actualX + "," + actualY + ")" +
            "; click_sent=" + clickSent;
        return panelOpened && cursorReached && clickSent;
    }

    private static bool ClickReplayWorldPoint(
        IntPtr process,
        long imageBase,
        IntPtr window,
        int worldX,
        int worldY,
        out int actualCursorX,
        out int actualCursorY)
    {
        actualCursorX = int.MinValue;
        actualCursorY = int.MinValue;
        int screenWidth = ReadInt(
            process, imageBase + EngineAddresses.ScreenWidth);
        int screenHeight = ReadInt(
            process, imageBase + EngineAddresses.ScreenHeight);
        if (screenWidth <= 0 || screenHeight <= 80)
            return false;
        int cameraX;
        int cameraY;
        bool visible = PanReplayCameraToWorldPoint(
            process,
            imageBase,
            window,
            worldX,
            worldY,
            screenWidth,
            screenHeight,
            5000,
            out cameraX,
            out cameraY);
        if (!visible)
            return false;
        int screenX = worldX - cameraX;
        int screenY = worldY - cameraY;
        bool cursorReached = MoveReplayCursor(
            process,
            imageBase,
            window,
            screenX,
            screenY,
            out actualCursorX,
            out actualCursorY);
        return cursorReached && PulseMouseButton(window, 0);
    }

    private static bool MoveReplayCursor(
        IntPtr process, long imageBase, IntPtr window,
        int targetX, int targetY, out int actualX, out int actualY)
    {
        actualX = ReadInt(
            process, imageBase + EngineAddresses.CursorX);
        actualY = ReadInt(
            process, imageBase + EngineAddresses.CursorY);
        if (actualX == int.MinValue || actualY == int.MinValue)
        {
            return false;
        }
        bool sent = false;
        for (int attempt = 0; attempt < 6; ++attempt)
        {
            int deltaX = Math.Max(
                short.MinValue,
                Math.Min(short.MaxValue, targetX - actualX));
            int deltaY = Math.Max(
                short.MinValue,
                Math.Min(short.MaxValue, targetY - actualY));
            if (Math.Abs(deltaX) <= 3 &&
                Math.Abs(deltaY) <= 3)
                return sent || attempt == 0;
            sent =
                SendReplay(
                    window,
                    ReplayMouseDelta,
                    PackDelta((short)deltaX, (short)deltaY)) ||
                sent;
            Thread.Sleep(90);
            actualX = ReadInt(
                process, imageBase + EngineAddresses.CursorX);
            actualY = ReadInt(
                process, imageBase + EngineAddresses.CursorY);
            if (actualX == int.MinValue ||
                actualY == int.MinValue)
                return false;
        }
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
        int playerRuntimeIndex,
        int playerSelectionDik,
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
        ActorSnapshot before = FindPlayerActor(
            process, imageBase, playerRuntimeIndex);
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

        // Select through the original character hotkey instead of guessing a
        // sprite hitbox. Cross-level route probes bind this hotkey to an
        // audited runtime-index/scene identity.
        byte[] actorBeforeSelection = ReadBytes(
            process, before.Address, 0x294);
        bool selectionSent = PulseKey(window, playerSelectionDik);
        Thread.Sleep(320);
        // Character hotkeys intentionally center the camera. Refresh the
        // origin before converting the destination into screen coordinates.
        cameraX = ReadInt(
            process, imageBase + EngineAddresses.CameraX);
        cameraY = ReadInt(
            process, imageBase + EngineAddresses.CameraY);
        ActorSnapshot selected = FindPlayerActor(
            process, imageBase, playerRuntimeIndex);
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
            evidence =
                "player actor disappeared after original hotkey selection";
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
        // The stock 1024x768 layout reserves 60 pixels for the bottom toolbar
        // (the world viewport is 1024x708). Keep a small safety margin, but do
        // not reject valid map cells in the former 32-pixel-wide false band.
        const int gameplayBottomMargin = 64;
        if (targetScreenX < 8 || targetScreenX >= screenWidth - 8 ||
            targetScreenY < 8 ||
            targetScreenY >= screenHeight - gameplayBottomMargin)
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
        // Some large missions need one actor tick after an F-key camera jump
        // before their process-local DirectInput cursor consumes deltas. Retry
        // only against the isolated target window; never touch the OS cursor.
        for (int attempt = 0; !cursorReached && attempt < 2; ++attempt)
        {
            Thread.Sleep(220);
            cursorReached = MoveReplayCursor(
                process, imageBase, window,
                targetScreenX, targetScreenY,
                out cursorX, out cursorY);
        }
        bool clickSent = false;
        ActorSnapshot firstGoal = null;
        bool firstGoalAccepted = false;
        for (int attempt = 0;
             cursorReached && !firstGoalAccepted && attempt < 3;
             ++attempt)
        {
            if (attempt > 0)
            {
                Thread.Sleep(220);
                cursorReached = MoveReplayCursor(
                    process, imageBase, window,
                    targetScreenX, targetScreenY,
                    out cursorX, out cursorY);
            }
            bool attemptClickSent =
                cursorReached && PulseMouseButton(window, 0);
            clickSent = clickSent || attemptClickSent;
            firstGoalAccepted =
                attemptClickSent &&
                WaitForPlayerGoal(
                    process,
                    imageBase,
                    targetWorldX,
                    targetWorldY,
                    900,
                    playerRuntimeIndex,
                    out firstGoal);
        }
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
            segmentObservationMilliseconds,
            playerRuntimeIndex);
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
            returnScreenY < screenHeight - gameplayBottomMargin;
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
                returnScreenY < screenHeight - gameplayBottomMargin;
        }
        int returnCursorX = int.MinValue;
        int returnCursorY = int.MinValue;
        bool returnCursorReached =
            returnTargetVisible &&
            MoveReplayCursor(
                process, imageBase, window,
                returnScreenX, returnScreenY,
                out returnCursorX, out returnCursorY);
        for (int attempt = 0;
             returnTargetVisible && !returnCursorReached && attempt < 2;
             ++attempt)
        {
            Thread.Sleep(220);
            returnCursorReached = MoveReplayCursor(
                process, imageBase, window,
                returnScreenX, returnScreenY,
                out returnCursorX, out returnCursorY);
        }
        bool returnClickSent = false;
        ActorSnapshot returnGoal = null;
        bool returnGoalAccepted = false;
        for (int attempt = 0;
             returnTargetVisible &&
             returnCursorReached &&
             !returnGoalAccepted &&
             attempt < 3;
             ++attempt)
        {
            if (attempt > 0)
            {
                Thread.Sleep(220);
                returnCursorReached = MoveReplayCursor(
                    process, imageBase, window,
                    returnScreenX, returnScreenY,
                    out returnCursorX, out returnCursorY);
            }
            bool attemptClickSent =
                returnCursorReached && PulseMouseButton(window, 0);
            returnClickSent =
                returnClickSent || attemptClickSent;
            returnGoalAccepted =
                attemptClickSent &&
                WaitForPlayerGoal(
                    process,
                    imageBase,
                    returnWorldX,
                    returnWorldY,
                    900,
                    playerRuntimeIndex,
                    out returnGoal);
        }
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
            segmentObservationMilliseconds,
            playerRuntimeIndex);
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
            "; selection_dik=" + playerSelectionDik +
            "; player_runtime_index=" + playerRuntimeIndex +
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
        int playerRuntimeIndex,
        out ActorSnapshot accepted)
    {
        accepted = null;
        Stopwatch clock = Stopwatch.StartNew();
        while (clock.ElapsedMilliseconds < milliseconds)
        {
            ActorSnapshot sample = FindPlayerActor(
                process, imageBase, playerRuntimeIndex);
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
        accepted = FindPlayerActor(
            process, imageBase, playerRuntimeIndex);
        return false;
    }

    private static MovementSegmentObservation ObserveMovementSegment(
        IntPtr process, long imageBase, ActorSnapshot start,
        int targetX, int targetY,
        int milliseconds,
        int playerRuntimeIndex)
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
            ActorSnapshot sample = FindPlayerActor(
                process, imageBase, playerRuntimeIndex);
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
        string checkpointId,
        bool includeInventory = false)
    {
        if (checkpoints == null || process == IntPtr.Zero)
            return;
        var checkpoint = new ParityCheckpoint();
        checkpoint.Id = checkpointId ?? "";
        checkpoint.ElapsedMilliseconds =
            clock == null ? 0 : clock.ElapsedMilliseconds;
        checkpoint.CurrentActionId = ReadInt(
            process,
            imageBase + EngineAddresses.CurrentActionId);
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
        checkpoint.RuntimeType78Count =
            CountWorldActorsOfRuntimeType(process, imageBase, 78);
        checkpoint.RuntimeType90Count =
            CountWorldActorsOfRuntimeType(process, imageBase, 90);
        foreach (ActorSnapshot actor in ReadTraceActors(
            process, imageBase))
        {
            if (includeInventory)
                ReadActorInventoryContainers(process, actor);
            checkpoint.Actors.Add(actor);
        }
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

    private static int CountWorldActorsOfRuntimeType(
        IntPtr process,
        long imageBase,
        int runtimeType)
    {
        int worldValue = ReadInt(
            process, imageBase + EngineAddresses.WorldRoot);
        if (worldValue == 0 || worldValue == int.MinValue)
            return 0;
        long world = (long)(uint)worldValue;
        int actorArrayValue = ReadInt(process, world + 0x18);
        int count = ReadInt(process, world + 0x3C);
        if (actorArrayValue == 0 ||
            actorArrayValue == int.MinValue ||
            count <= 0 ||
            count > 4096)
            return 0;
        int matches = 0;
        long actorArray = (long)(uint)actorArrayValue;
        for (int index = 0; index < count; ++index)
        {
            int actorValue = ReadInt(
                process, actorArray + index * 4L);
            if (actorValue == 0 || actorValue == int.MinValue)
                continue;
            if (ReadInt(
                    process,
                    (long)(uint)actorValue +
                    ActorRuntimeTypeOffset) == runtimeType)
                ++matches;
        }
        return matches;
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

    private static string TraceInventoryFields(ActorSnapshot actor)
    {
        if (actor == null || !actor.InventoryCaptured)
            return "";
        int activeItemId = ItemIdForAttackType(
            actor.DefaultAttackType);
        int activeQuantity = InventoryQuantity(
            actor.WeaponEntries,
            activeItemId);
        var json = new StringBuilder();
        json.AppendFormat(
            CultureInfo.InvariantCulture,
            "\"weapon\":{{\"attack_type\":{0}," +
            "\"action_key\":\"{1}\"," +
            "\"magazine_ammo\":{2},\"reserve_ammo\":0," +
            "\"infinite_ammo\":false}},",
            actor.DefaultAttackType,
            Escape(ActionKeyForAttackType(actor.DefaultAttackType)),
            activeQuantity);
        json.AppendFormat(
            CultureInfo.InvariantCulture,
            "\"inventory\":{{\"schema_version\":1," +
            "\"active_attack_type\":{0},\"weapon_entries\":[",
            actor.DefaultAttackType);
        AppendTraceInventoryEntries(json, actor.WeaponEntries);
        json.Append("],\"item_entries\":[");
        AppendTraceInventoryEntries(json, actor.ItemEntries);
        json.Append("]},");
        json.AppendFormat(
            CultureInfo.InvariantCulture,
            "\"world_item_effect\":{{" +
            "\"hypnosis_active\":{0}," +
            "\"hypnosis_counter\":{1}," +
            "\"hypnosis_counter_limit\":{2}," +
            "\"player_selected\":{3}," +
            "\"poison_active\":{4}," +
            "\"poison_counter\":{5}," +
            "\"poison_counter_limit\":{6}," +
            "\"distraction_active\":{7}," +
            "\"distraction_counter\":{8}," +
            "\"distraction_limit\":{9}}},",
            actor.HypnosisActive,
            actor.HypnosisCounter,
            actor.HypnosisCounterLimit,
            actor.WorldItemPlayerSelected,
            actor.PoisonActive,
            actor.PoisonCounter,
            actor.PoisonCounterLimit,
            actor.ReactionState == 1 &&
                actor.SearchDelayLimit >= 80 &&
                actor.SearchDelayLimit <= 119
                    ? 1
                    : 0,
            actor.SearchDelayCounter,
            actor.SearchDelayLimit);
        return json.ToString();
    }

    private static void AppendTraceInventoryEntries(
        StringBuilder json,
        IList<InventoryEntry> entries)
    {
        if (json == null || entries == null)
            return;
        for (int index = 0; index < entries.Count; ++index)
        {
            InventoryEntry entry = entries[index];
            json.AppendFormat(
                CultureInfo.InvariantCulture,
                "{{\"inventory_index\":{0},\"item_id\":{1}," +
                "\"quantity\":{2},\"quantity_mode\":{3}}}{4}",
                entry.InventoryIndex,
                entry.ItemId,
                entry.Quantity,
                entry.QuantityMode,
                index + 1 == entries.Count ? "" : ",");
        }
    }

    private static int ItemIdForAttackType(int attackType)
    {
        switch (attackType)
        {
        case 1: return 36;
        case 2: return 37;
        case 3: return 38;
        case 4: return 39;
        case 5: return 40;
        case 6: return 41;
        case 7: return 42;
        case 8: return 43;
        case 9: return 44;
        case 10: return 45;
        case 11: return 99;
        default: return 0;
        }
    }

    private static string ActionKeyForAttackType(int attackType)
    {
        switch (attackType)
        {
        case 1: return "pistol_attack";
        case 2: return "rifle_attack";
        case 3: return "machine_gun_attack";
        case 4: return "dagger_attack";
        case 5: return "broadsword_attack";
        case 6: return "dart_attack";
        case 7: return "slingshot_attack";
        case 8: return "active_action";
        case 9: return "grenade_attack";
        case 10: return "active_action_alt";
        case 11: return "special_attack";
        default: return "";
        }
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
        string scenarioDescription;
        if (String.Equals(
                scenarioId,
                "m001-mine-pickup-inventory-v1",
                StringComparison.Ordinal))
        {
            scenarioDescription =
                "Select controllable scene 2280 and collect the real " +
                "scene-2096 mine " +
                "through process-local DirectInput; capture both original " +
                "inventory containers before and after.";
        }
        else if (
            scenarioId.EndsWith(
                "-attack-inventory-v1",
                StringComparison.Ordinal) ||
            scenarioId.EndsWith(
                "-deploy-inventory-v1",
                StringComparison.Ordinal))
        {
            scenarioDescription =
                ResolveWeaponAttackParityScenario(
                    scenarioId,
                    selectorLevel).Description;
        }
        else if (scenarioId.EndsWith(
                     "-world-item-v1",
                     StringComparison.Ordinal))
        {
            scenarioDescription =
                ResolveWorldItemParityScenario(
                    scenarioId,
                    selectorLevel).Description;
        }
        else if (String.Equals(
                     scenarioId,
                     "m010-sight-direct-target-v1",
                     StringComparison.Ordinal))
        {
            scenarioDescription =
                "Release S and click living faction-1 scene 1126 through " +
                "process-local DirectInput; verify one-shot direct enemy " +
                "selection without creating actor 90.";
        }
        else if (String.Equals(
                     scenarioId,
                     "m010-burial-command-v1",
                     StringComparison.Ordinal))
        {
            scenarioDescription =
                "Kill scene 1126 with Daniu's original dagger, release B " +
                "and click the corpse through process-local DirectInput; verify " +
                "one-shot consumption and command kind 4 without instant completion.";
        }
        else if (resolvedActorScope)
        {
            scenarioDescription =
                "Natural player movement into enemy contact with audited " +
                "runtime-to-VWF identities; no global cursor or focus API.";
        }
        else if (resolvedEnemyScope)
        {
            scenarioDescription =
                "Read-only enemy patrol observation with audited " +
                "runtime-to-VWF identities; no global cursor or focus API.";
        }
        else
        {
            scenarioDescription =
                "Window-local selection and movement observation; no global " +
                "cursor or focus API; cells " +
                movementCellX + "," + movementCellY + " -> " +
                returnCellX + "," + returnCellY + ".";
        }
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
            Escape(scenarioDescription));
        string inputIsolation = scenarioId.EndsWith(
            "-world-item-v1",
            StringComparison.Ordinal)
                ? "opt-in-window-replay-authentic-original-actor-seed"
                : "window-message-to-process-local-DirectInput";
        json.AppendFormat(
            CultureInfo.InvariantCulture,
            "  \"metadata\": {{\"producer\":\"ModRegressionProbe\"," +
            "\"input_isolation\":\"{0}\"}},\n",
            inputIsolation);
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
                int identityFaction = hasIdentity
                    ? identity.VwfFactionId
                    : actor.Faction;
                // Type 91 is Gu Ming's authentic enemy-uniform runtime
                // replacement. Keep his authored player role/scene identity,
                // but report the live faction used by the original hostility
                // checks so the modern runtime can be compared exactly.
                int traceFaction =
                    hasIdentity && actor.RuntimeType == 91
                        ? actor.Faction
                        : identityFaction;
                int targetX = actor.GoalKind == 1
                    ? actor.GoalX
                    : actor.WorldX;
                int targetY = actor.GoalKind == 1
                    ? actor.GoalY
                    : actor.WorldY;
                string role = resolvedActorScope
                    ? identityFaction == 3
                        ? "player"
                        : identityFaction == 1
                            ? "enemy"
                            : "escort"
                    : identityFaction == 3
                        ? "player"
                        : identityFaction == 2
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
                    "{38}" +
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
                    actor.DefaultAttackType,
                    TraceInventoryFields(actor));
            }
            json.Append("      ],\n");
            json.AppendFormat(
                CultureInfo.InvariantCulture,
                "      \"mission\":{{\"id\":\"{0}\"," +
                "\"status\":\"active\"}},\n",
                levelId);
            json.Append(
                "      \"tags\":{" +
                "\"source\":\"stable-mod-read-only-process-snapshot\"," +
                "\"current_action_id\":" +
                checkpoint.CurrentActionId + "," +
                "\"runtime_type_78_count\":" +
                checkpoint.RuntimeType78Count + "," +
                "\"runtime_type_90_count\":" +
                checkpoint.RuntimeType90Count);
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
                "mod-" + scenarioId + ".json"),
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
