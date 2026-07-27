using System.Runtime.InteropServices;

namespace Mission1937.Sidecar.Host;

internal sealed class NativePluginHost : IDisposable
{
    private const uint AbiVersion = 0x00010000;
    private const uint SchemaVersion = 1;
    private readonly List<LoadedPlugin> loaded = [];
    private readonly List<Delegate> rootedDelegates = [];
    private readonly List<IntPtr> rootedStrings = [];
    private readonly string stateDirectory;
    private readonly MissionRuntimeEngine engine;
    private readonly Action<string, string> diagnostic;
    private HostApiNative hostApi;

    public NativePluginHost(
        string gameDirectory,
        ExecutableIdentity identity,
        MissionRuntimeEngine engine,
        bool enabled,
        Action<string, string> diagnostic)
    {
        this.engine = engine;
        this.diagnostic = diagnostic;
        stateDirectory = Path.Combine(
            gameDirectory, "Plugins", "State");
        if (!enabled)
            return;
        Directory.CreateDirectory(stateDirectory);
        var emit = new EmitEventDelegate(EmitEvent);
        var read = new ReadStateDelegate(ReadState);
        var write = new WriteStateDelegate(WriteState);
        rootedDelegates.AddRange([emit, read, write]);
        var sha = Marshal.StringToCoTaskMemUTF8(identity.Sha256);
        rootedStrings.Add(sha);
        hostApi = new HostApiNative
        {
            Size = checked((uint)Marshal.SizeOf<HostApiNative>()),
            Info = new HostInfoNative
            {
                Size = checked((uint)Marshal.SizeOf<HostInfoNative>()),
                AbiVersion = AbiVersion,
                MissionSchemaVersion = SchemaVersion,
                ExecutablePeTimestamp = identity.PeTimestamp,
                ExecutableImageSize = 0x00124000,
                ExecutableSha256 = sha
            },
            EmitEvent = Marshal.GetFunctionPointerForDelegate(emit),
            ReadState = Marshal.GetFunctionPointerForDelegate(read),
            WriteState = Marshal.GetFunctionPointerForDelegate(write)
        };
        var pluginDirectory = Path.Combine(
            gameDirectory, "Plugins");
        if (!Directory.Exists(pluginDirectory))
            return;
        foreach (var path in Directory.EnumerateFiles(
                     pluginDirectory,
                     "*.dll",
                     SearchOption.TopDirectoryOnly))
            TryLoad(path);
    }

    public int LoadedCount => loaded.Count;

    public void Broadcast(WorldEvent worldEvent)
    {
        if (loaded.Count == 0)
            return;
        var native = new WorldEventNative
        {
            Size = checked((uint)Marshal.SizeOf<WorldEventNative>()),
            Kind = (uint)worldEvent.Kind,
            Sequence = worldEvent.Sequence,
            MonotonicMilliseconds =
                unchecked((ulong)worldEvent.MonotonicMilliseconds),
            Mission = unchecked((uint)worldEvent.Mission),
            SubjectId = worldEvent.SubjectId,
            ObjectId = worldEvent.ObjectId,
            Value = worldEvent.Value
        };
        foreach (var plugin in loaded.ToArray())
        {
            try
            {
                plugin.OnWorldEvent?.Invoke(ref native);
            }
            catch (Exception exception)
            {
                diagnostic(
                    "plugin_event_failed",
                    $"{plugin.Id};{exception.GetType().Name}");
            }
        }
    }

    public void Dispose()
    {
        for (var index = loaded.Count - 1; index >= 0; --index)
        {
            var plugin = loaded[index];
            try
            {
                plugin.OnUnload?.Invoke();
            }
            catch
            {
            }
            NativeLibrary.Free(plugin.Library);
        }
        loaded.Clear();
        foreach (var pointer in rootedStrings)
            Marshal.FreeCoTaskMem(pointer);
        rootedStrings.Clear();
        rootedDelegates.Clear();
    }

    private void TryLoad(string path)
    {
        IntPtr library = IntPtr.Zero;
        try
        {
            library = NativeLibrary.Load(path);
            if (!NativeLibrary.TryGetExport(
                    library,
                    "M1937QueryPluginV1",
                    out var queryPointer))
                throw new InvalidDataException(
                    "missing_query_export");
            var query =
                Marshal.GetDelegateForFunctionPointer<QueryDelegate>(
                    queryPointer);
            var apiPointer = query();
            if (apiPointer == IntPtr.Zero)
                throw new InvalidDataException("null_api");
            var api = Marshal.PtrToStructure<PluginApiNative>(
                apiPointer);
            if (api.Size <
                    Marshal.SizeOf<PluginApiNative>() ||
                api.AbiVersion != AbiVersion ||
                api.MinimumMissionSchema > SchemaVersion ||
                api.MaximumMissionSchema < SchemaVersion)
                throw new InvalidDataException(
                    "version_negotiation_failed");
            var id = Marshal.PtrToStringUTF8(api.PluginId);
            if (string.IsNullOrWhiteSpace(id))
                throw new InvalidDataException("missing_plugin_id");
            var onLoad = api.OnLoad == IntPtr.Zero
                ? null
                : Marshal.GetDelegateForFunctionPointer<OnLoadDelegate>(
                    api.OnLoad);
            var onUnload = api.OnUnload == IntPtr.Zero
                ? null
                : Marshal.GetDelegateForFunctionPointer<OnUnloadDelegate>(
                    api.OnUnload);
            var onEvent = api.OnWorldEvent == IntPtr.Zero
                ? null
                : Marshal.GetDelegateForFunctionPointer<
                    OnWorldEventDelegate>(api.OnWorldEvent);
            if (onLoad is not null && !onLoad(ref hostApi))
                throw new InvalidDataException("plugin_rejected_host");
            loaded.Add(new LoadedPlugin(
                id, library, onUnload, onEvent));
            diagnostic("plugin_loaded", id);
        }
        catch (Exception exception)
        {
            if (library != IntPtr.Zero)
                NativeLibrary.Free(library);
            diagnostic(
                "plugin_rejected",
                $"{Path.GetFileName(path)};{exception.Message}");
        }
    }

    [return: MarshalAs(UnmanagedType.I1)]
    private bool EmitEvent(ref WorldEventNative native)
    {
        if (native.Size < Marshal.SizeOf<WorldEventNative>() ||
            !Enum.IsDefined(
                typeof(WorldEventKind),
                native.Kind))
            return false;
        return engine.Apply(new WorldEvent
        {
            Sequence = native.Sequence,
            MonotonicMilliseconds =
                checked((long)native.MonotonicMilliseconds),
            Mission = checked((int)native.Mission),
            Kind = (WorldEventKind)native.Kind,
            SubjectId = native.SubjectId,
            ObjectId = native.ObjectId,
            Value = native.Value
        });
    }

    [return: MarshalAs(UnmanagedType.I1)]
    private bool ReadState(
        IntPtr slotPointer,
        IntPtr buffer,
        ref uint size)
    {
        try
        {
            var path = StatePath(slotPointer);
            if (!File.Exists(path))
            {
                size = 0;
                return true;
            }
            var bytes = File.ReadAllBytes(path);
            if (buffer == IntPtr.Zero || size < bytes.Length)
            {
                size = checked((uint)bytes.Length);
                return buffer == IntPtr.Zero;
            }
            Marshal.Copy(bytes, 0, buffer, bytes.Length);
            size = checked((uint)bytes.Length);
            return true;
        }
        catch
        {
            return false;
        }
    }

    [return: MarshalAs(UnmanagedType.I1)]
    private bool WriteState(
        IntPtr slotPointer,
        IntPtr buffer,
        uint size)
    {
        try
        {
            if (size > 16 * 1024 * 1024 ||
                (size > 0 && buffer == IntPtr.Zero))
                return false;
            var path = StatePath(slotPointer);
            var bytes = new byte[size];
            if (size > 0)
                Marshal.Copy(
                    buffer, bytes, 0, checked((int)size));
            var temporary = path + ".tmp";
            var backup = path + ".bak";
            File.WriteAllBytes(temporary, bytes);
            if (File.Exists(path))
                File.Replace(temporary, path, backup, true);
            else
                File.Move(temporary, path);
            return true;
        }
        catch
        {
            return false;
        }
    }

    private string StatePath(IntPtr slotPointer)
    {
        var slot = Marshal.PtrToStringUTF8(slotPointer) ?? "";
        if (slot.Length is < 1 or > 80 ||
            slot.Any(character =>
                !(char.IsAsciiLetterOrDigit(character) ||
                  character is '-' or '_' or '.')))
            throw new InvalidDataException("invalid_state_slot");
        var path = Path.GetFullPath(
            Path.Combine(stateDirectory, slot + ".bin"));
        if (!path.StartsWith(
                Path.GetFullPath(stateDirectory) +
                Path.DirectorySeparatorChar,
                StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("state_path_escape");
        return path;
    }

    private sealed record LoadedPlugin(
        string Id,
        IntPtr Library,
        OnUnloadDelegate? OnUnload,
        OnWorldEventDelegate? OnWorldEvent);

    [StructLayout(LayoutKind.Sequential)]
    private struct WorldEventNative
    {
        public uint Size;
        public uint Kind;
        public ulong Sequence;
        public ulong MonotonicMilliseconds;
        public uint Mission;
        public uint SubjectId;
        public uint ObjectId;
        public int Value;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct HostInfoNative
    {
        public uint Size;
        public uint AbiVersion;
        public uint MissionSchemaVersion;
        public uint ExecutablePeTimestamp;
        public uint ExecutableImageSize;
        public IntPtr ExecutableSha256;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct HostApiNative
    {
        public uint Size;
        public HostInfoNative Info;
        public IntPtr EmitEvent;
        public IntPtr ReadState;
        public IntPtr WriteState;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct PluginApiNative
    {
        public uint Size;
        public uint AbiVersion;
        public uint MinimumMissionSchema;
        public uint MaximumMissionSchema;
        public IntPtr PluginId;
        public IntPtr OnLoad;
        public IntPtr OnUnload;
        public IntPtr OnWorldEvent;
    }

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate IntPtr QueryDelegate();

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    [return: MarshalAs(UnmanagedType.I1)]
    private delegate bool OnLoadDelegate(ref HostApiNative host);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate void OnUnloadDelegate();

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate void OnWorldEventDelegate(
        ref WorldEventNative worldEvent);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    [return: MarshalAs(UnmanagedType.I1)]
    private delegate bool EmitEventDelegate(
        ref WorldEventNative worldEvent);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    [return: MarshalAs(UnmanagedType.I1)]
    private delegate bool ReadStateDelegate(
        IntPtr slotId,
        IntPtr buffer,
        ref uint size);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    [return: MarshalAs(UnmanagedType.I1)]
    private delegate bool WriteStateDelegate(
        IntPtr slotId,
        IntPtr buffer,
        uint size);
}
