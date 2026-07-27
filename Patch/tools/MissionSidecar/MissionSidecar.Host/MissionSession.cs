namespace Mission1937.Sidecar.Host;

internal sealed class MissionSession : IDisposable
{
    private readonly RuntimeWorldReader reader;
    private readonly string gameDirectory;
    private readonly string logPath;
    private readonly MissionRuntimeEngine engine;
    private WorldEventDetector detector;
    private readonly NativePluginHost plugins;
    private int selectedSlot = int.MinValue;
    private string? selectedSave;
    private long saveLength = -1;
    private DateTime saveWriteUtc;
    private long saveObservedAt;
    private bool stateDirty;
    private RuntimePoll? lastPoll;

    public MissionSession(
        RuntimeWorldReader reader,
        MissionSidecarDefinition definition,
        ExecutableIdentity identity,
        bool enablePlugins)
    {
        this.reader = reader;
        gameDirectory = Path.GetDirectoryName(identity.Path)!;
        logPath = Path.Combine(
            gameDirectory, "MissionSidecarHost.log");
        engine = new MissionRuntimeEngine(definition);
        detector = new WorldEventDetector(definition);
        plugins = new NativePluginHost(
            gameDirectory,
            identity,
            engine,
            enablePlugins,
            WriteDiagnostic);
        WriteDiagnostic(
            "session_started",
            $"mission={definition.Id};plugins={plugins.LoadedCount}");
    }

    public event Action<MissionView>? ViewChanged;
    public MissionView View => engine.BuildView();
    public RuntimePoll? LastPoll => lastPoll;
    public bool ProcessExited => reader.Process.HasExited;
    public IntPtr GameWindowHandle
    {
        get
        {
            reader.Process.Refresh();
            return reader.Process.MainWindowHandle;
        }
    }

    public void Tick()
    {
        if (ProcessExited)
            return;
        RuntimePoll? poll;
        try
        {
            poll = reader.Poll();
        }
        catch (Exception exception) when (
            exception is IOException or InvalidOperationException or
                System.ComponentModel.Win32Exception)
        {
            WriteDiagnostic(
                "snapshot_skipped", exception.GetType().Name);
            return;
        }
        if (poll is null)
            return;
        lastPoll = poll;
        ObserveSaveSlot(poll.SelectedSaveSlot);
        foreach (var worldEvent in detector.Detect(poll.Snapshot))
            Apply(worldEvent);
        ObserveSaveFile(poll.Snapshot.MonotonicMilliseconds);
    }

    public void Dispose()
    {
        plugins.Dispose();
        WriteDiagnostic("session_stopped", "normal");
    }

    private void Apply(WorldEvent worldEvent)
    {
        plugins.Broadcast(worldEvent);
        var previousSequence = engine.State.LastEventSequence;
        var viewChanged = engine.Apply(worldEvent);
        var accepted =
            engine.State.LastEventSequence != previousSequence;
        if (!accepted)
            return;
        stateDirty = true;
        if (viewChanged)
            ViewChanged?.Invoke(engine.BuildView());
        WriteDiagnostic(
            "world_event",
            $"kind={worldEvent.Kind};sequence={worldEvent.Sequence};" +
            $"matched={viewChanged.ToString().ToLowerInvariant()}");
    }

    private void ObserveSaveSlot(int slot)
    {
        if (slot == selectedSlot)
            return;
        selectedSlot = slot;
        selectedSave = ResolveSavePath(slot);
        saveLength = -1;
        saveWriteUtc = default;
        saveObservedAt = 0;
        if (selectedSave is null)
        {
            WriteDiagnostic(
                "save_slot", $"slot={slot};file=unresolved");
            return;
        }
        var statePath =
            AtomicMissionStateStore.SidecarPathForSave(selectedSave);
        if (!File.Exists(statePath))
        {
            WriteDiagnostic(
                "save_slot",
                $"slot={slot};state=new");
            return;
        }
        try
        {
            var restored = AtomicMissionStateStore.Load(
                statePath, selectedSave);
            engine.ReplaceState(restored);
            detector = new WorldEventDetector(
                engine.Definition,
                restored.LastEventSequence);
            stateDirty = false;
            ViewChanged?.Invoke(engine.BuildView());
            WriteDiagnostic(
                "load_completed",
                $"slot={slot};sequence={restored.LastEventSequence}");
        }
        catch (Exception exception) when (
            exception is IOException or InvalidDataException)
        {
            WriteDiagnostic(
                "load_rejected", exception.GetType().Name);
        }
    }

    private void ObserveSaveFile(long monotonicMilliseconds)
    {
        if (selectedSave is null ||
            !File.Exists(selectedSave))
            return;
        var info = new FileInfo(selectedSave);
        if (info.Length != saveLength ||
            info.LastWriteTimeUtc != saveWriteUtc)
        {
            saveLength = info.Length;
            saveWriteUtc = info.LastWriteTimeUtc;
            saveObservedAt = monotonicMilliseconds;
            return;
        }
        if (!stateDirty ||
            saveObservedAt <= 0 ||
            monotonicMilliseconds - saveObservedAt < 1000)
            return;
        try
        {
            var sequence = engine.State.LastEventSequence;
            Apply(new WorldEvent
            {
                Sequence = sequence + 1,
                MonotonicMilliseconds = monotonicMilliseconds,
                Mission = lastPoll?.Snapshot.Mission ?? 0,
                Kind = WorldEventKind.SaveCompleted,
                Value = 1
            });
            AtomicMissionStateStore.Save(
                AtomicMissionStateStore.SidecarPathForSave(
                    selectedSave),
                engine.State,
                selectedSave);
            stateDirty = false;
            saveObservedAt = 0;
            WriteDiagnostic(
                "save_completed",
                $"slot={selectedSlot};sequence={engine.State.LastEventSequence}");
        }
        catch (Exception exception) when (
            exception is IOException or UnauthorizedAccessException)
        {
            WriteDiagnostic(
                "save_deferred", exception.GetType().Name);
            saveObservedAt = monotonicMilliseconds;
        }
    }

    private string? ResolveSavePath(int slot)
    {
        if (slot is < 0 or > 999)
            return null;
        var exact = Path.Combine(
            gameDirectory, $"1937M{slot:000}.SAV");
        if (File.Exists(exact))
            return exact;
        return Directory.EnumerateFiles(
                gameDirectory,
                "*.SAV",
                SearchOption.TopDirectoryOnly)
            .FirstOrDefault(path =>
                Path.GetFileNameWithoutExtension(path)
                    .EndsWith(
                        slot.ToString("000"),
                        StringComparison.OrdinalIgnoreCase));
    }

    private void WriteDiagnostic(string eventName, string detail)
    {
        var line =
            $"{DateTime.UtcNow:O}\t{eventName}\t{detail}{Environment.NewLine}";
        lock (logPath)
        {
            File.AppendAllText(logPath, line);
        }
    }
}
