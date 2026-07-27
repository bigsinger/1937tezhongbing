using System.Collections.ObjectModel;
using System.IO;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using Microsoft.Win32;
using Mission1937.MapEditor.Core;

namespace Mission1937.MapEditor.App;

public partial class MainWindow : Window
{
    private MapDocument document =
        MapDocument.Create("新关卡", 64, 48);
    private readonly IReadOnlyList<AssetEntry> allAssets;
    private readonly string? assetRoot;
    private string? currentPath;
    private string? currentVwfSourcePath;
    private EditorLayerKind activeLayer = EditorLayerKind.MovementObstacle;
    private string activeTool = "select";
    private bool dirty;
    private readonly MapEditHistory history = new(150);
    private MapDocument? pendingGridEdit;
    private MapDocument? pendingNameEdit;
    private MapDocument? pendingLayerVisibilityEdit;

    public MainWindow()
    {
        InitializeComponent();
        if (!string.IsNullOrWhiteSpace(
                Environment.GetEnvironmentVariable(
                    "M1937_MAPEDITOR_SCREENSHOT")))
        {
            // Automated visual regression renders this window directly.
            // Keep it off-screen and never steal the user's active window.
            WindowStartupLocation = WindowStartupLocation.Manual;
            Left = -20_000;
            Top = -20_000;
            ShowActivated = false;
        }
        CommandBindings.Add(new CommandBinding(
            ApplicationCommands.New, New_Click));
        CommandBindings.Add(new CommandBinding(
            ApplicationCommands.Open, Open_Click));
        CommandBindings.Add(new CommandBinding(
            ApplicationCommands.Save, Save_Click));
        CommandBindings.Add(new CommandBinding(
            ApplicationCommands.Undo, Undo_Click));
        CommandBindings.Add(new CommandBinding(
            ApplicationCommands.Redo, Redo_Click));

        assetRoot = AssetLibrary.FindRoot();
        allAssets =
        [
            new AssetEntry
            {
                Id = 0,
                Name = "鼠标箭头（仅查看）",
                Category = "常用",
                Kind = "none",
                IsNone = true
            },
            .. AssetLibrary.Load(assetRoot)
        ];
        ConfigureAssetLibrary();
        EditorCanvas.AssetRoot = assetRoot;
        LoadDocument(document, null, null);
        Loaded += AutomatedPreview_Loaded;
    }

    private void ConfigureAssetLibrary()
    {
        AssetCategoryCombo.Items.Add("全部素材");
        foreach (var category in allAssets
                     .Where(asset => !asset.IsNone)
                     .Select(asset => asset.Category)
                     .Where(value => !string.IsNullOrWhiteSpace(value))
                     .Distinct(StringComparer.CurrentCultureIgnoreCase)
                     .OrderBy(value => value))
            AssetCategoryCombo.Items.Add(category);
        AssetCategoryCombo.SelectedIndex = 0;
        RefreshAssetFilter();
        AssetStatusText.Text = assetRoot is null
            ? "素材库：未找到（仍可编辑图层）"
            : $"素材库：{allAssets.Count - 1:N0} 项";
    }

    private void LoadDocument(
        MapDocument value,
        string? path,
        string? vwfSourcePath = null,
        bool resetHistory = true,
        bool restoredDirty = false)
    {
        document = value;
        currentPath = path;
        currentVwfSourcePath = vwfSourcePath;
        LayerList.ItemsSource = document.Layers;
        LayerList.SelectedItem = document.Layers.FirstOrDefault(
            layer => layer.Kind == EditorLayerKind.MovementObstacle)
            ?? document.Layers.FirstOrDefault();
        ObjectGrid.ItemsSource =
            new ObservableCollection<MapObject>(document.Objects);
        TaskGrid.ItemsSource =
            new ObservableCollection<MissionTask>(document.Tasks);
        MapNameText.Text = document.Name;
        MapSizeText.Text =
            $"{document.Width} × {document.Height} 格；" +
            $"每格 {document.EffectiveCellWidth}×" +
            $"{document.EffectiveCellHeight} 像素；" +
            $"{document.Objects.Count:N0} 个对象";
        EditorCanvas.Document = document;
        EditorCanvas.Zoom = ZoomSlider.Value;
        EditorCanvas.ShowPatrolRoutes =
            ShowRoutesCheck.IsChecked == true;
        EditorCanvas.MotionPreviewEnabled =
            MotionPreviewCheck.IsChecked == true;
        EditorCanvas.ShowConnectivityHeatmap =
            ConnectivityHeatmapCheck.IsChecked == true;
        EditorCanvas.ShowAiRanges =
            AiRangesCheck.IsChecked == true;
        UpdateAnalysisProfile();
        AssetList.SelectedIndex = 0;
        SelectMode.IsChecked = true;
        UpdateRouteStatus();
        RefreshQualityIssues();
        var nativeAvailable =
            document.ImportedFrom is not null;
        NativeVwfSaveMenu.IsEnabled = nativeAvailable;
        NativeVwfSaveButton.IsEnabled = nativeAvailable;
        if (resetHistory)
            history.Clear();
        dirty = restoredDirty;
        UpdateHistoryUi();
        UpdateTitle();
        StatusText.Text = path is null
            ? document.ImportedFrom is null
                ? "已新建空白地图"
                : $"已打开原版地图 {document.ImportedFrom}，请使用“另存为”保存副本"
            : $"已打开：{path}";

        Dispatcher.BeginInvoke(
            DispatcherPriority.ContextIdle,
            new Action(() =>
            {
                FitMapToWindow();
                UpdateVisibleViewport();
            }));
    }

    private void FitMapToWindow()
    {
        var availableWidth = Math.Max(320, MapScroll.ActualWidth - 30);
        var availableHeight = Math.Max(240, MapScroll.ActualHeight - 30);
        var fullWidth = document.Width * document.EffectiveCellWidth;
        var fullHeight = document.Height * document.EffectiveCellHeight;
        if (fullWidth <= 0 || fullHeight <= 0)
            return;
        ZoomSlider.Value = Math.Clamp(
            Math.Min(availableWidth / fullWidth, availableHeight / fullHeight),
            ZoomSlider.Minimum, 1.0);
    }

    private void UpdateTitle()
    {
        Title =
            $"1937 特种兵地图编辑器 — {document.Name}" +
            $"{(dirty ? " *" : "")}";
    }

    private void MarkDirty()
    {
        dirty = true;
        UpdateTitle();
    }

    private MapDocument Snapshot() =>
        MapDocumentSerializer.Clone(document);

    private void CommitEdit(
        MapDocument before,
        string description,
        string? coalesceKey = null)
    {
        SyncCollections();
        history.Commit(
            description,
            before,
            document,
            coalesceKey);
        MarkDirty();
        UpdateHistoryUi();
    }

    private void UpdateHistoryUi()
    {
        if (UndoMenu is null || RedoMenu is null)
            return;
        UndoMenu.IsEnabled = history.CanUndo;
        RedoMenu.IsEnabled = history.CanRedo;
        UndoMenu.Header = history.CanUndo
            ? $"撤销：{history.UndoDescription}"
            : "撤销";
        RedoMenu.Header = history.CanRedo
            ? $"重做：{history.RedoDescription}"
            : "重做";
    }

    private void Undo_Click(object sender, RoutedEventArgs e)
    {
        if (!history.CanUndo)
            return;
        var description = history.UndoDescription;
        LoadDocument(
            history.Undo(),
            currentPath,
            currentVwfSourcePath,
            resetHistory: false,
            restoredDirty: true);
        StatusText.Text = $"已撤销：{description}";
        UpdateHistoryUi();
    }

    private void Redo_Click(object sender, RoutedEventArgs e)
    {
        if (!history.CanRedo)
            return;
        var description = history.RedoDescription;
        LoadDocument(
            history.Redo(),
            currentPath,
            currentVwfSourcePath,
            resetHistory: false,
            restoredDirty: true);
        StatusText.Text = $"已重做：{description}";
        UpdateHistoryUi();
    }

    private void New_Click(object sender, RoutedEventArgs e)
    {
        if (!ConfirmDiscard())
            return;
        var dialog = new NewMapDialog { Owner = this };
        if (dialog.ShowDialog() == true)
            LoadDocument(
                MapDocument.Create(
                    dialog.MapName, dialog.MapWidth, dialog.MapHeight),
                null,
                null);
    }

    private void Open_Click(object sender, RoutedEventArgs e)
    {
        if (!ConfirmDiscard())
            return;
        var dialog = new OpenFileDialog
        {
            Filter =
                "支持的地图 (*.vwf;*.m37map.json)|*.vwf;*.m37map.json|" +
                "原版关卡 (*.vwf)|*.vwf|" +
                "地图工程 (*.m37map.json)|*.m37map.json|" +
                "JSON (*.json)|*.json",
            InitialDirectory = FindInitialMapDirectory()
        };
        if (dialog.ShowDialog(this) != true)
            return;
        try
        {
            OpenMapFile(dialog.FileName);
        }
        catch (Exception exception)
        {
            MessageBox.Show(
                this, exception.Message, "打开地图失败",
                MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    private void OpenMapFile(string path)
    {
        if (string.Equals(
                Path.GetExtension(path), ".vwf",
                StringComparison.OrdinalIgnoreCase))
        {
            LoadDocument(
                OriginalVwfImporter.Import(path, assetRoot),
                null,
                Path.GetFullPath(path));
        }
        else
        {
            LoadDocument(MapDocumentSerializer.Load(path), path, null);
        }
    }

    private async void AutomatedPreview_Loaded(
        object sender, RoutedEventArgs e)
    {
        var screenshotPath = Environment.GetEnvironmentVariable(
            "M1937_MAPEDITOR_SCREENSHOT");
        if (string.IsNullOrWhiteSpace(screenshotPath))
            return;
        try
        {
            var mapPath = Environment.GetEnvironmentVariable(
                "M1937_MAPEDITOR_OPEN");
            if (!string.IsNullOrWhiteSpace(mapPath) && File.Exists(mapPath))
                OpenMapFile(mapPath);
            MapObject? automatedSelection = null;
            var selectedScene = Environment.GetEnvironmentVariable(
                "M1937_MAPEDITOR_SELECT_SCENE");
            if (int.TryParse(selectedScene, out var sceneIndex))
            {
                automatedSelection = document.Objects.FirstOrDefault(
                    item => item.Id == $"scene-{sceneIndex}");
                if (automatedSelection is not null)
                    SelectObject(automatedSelection);
            }
            await Dispatcher.InvokeAsync(
                FitMapToWindow, DispatcherPriority.ContextIdle);
            var requestedZoom = Environment.GetEnvironmentVariable(
                "M1937_MAPEDITOR_ZOOM");
            if (double.TryParse(
                    requestedZoom,
                    System.Globalization.NumberStyles.Float,
                    System.Globalization.CultureInfo.InvariantCulture,
                    out var automationZoom))
            {
                ZoomSlider.Value = Math.Clamp(
                    automationZoom,
                    ZoomSlider.Minimum,
                    ZoomSlider.Maximum);
            }
            if (string.Equals(
                    Environment.GetEnvironmentVariable(
                        "M1937_MAPEDITOR_HEATMAP"),
                    "1",
                    StringComparison.Ordinal))
            {
                ConnectivityHeatmapCheck.IsChecked = true;
            }
            await Dispatcher.InvokeAsync(
                UpdateLayout, DispatcherPriority.ContextIdle);
            if (automatedSelection is not null)
                CenterViewportAt(automatedSelection.X, automatedSelection.Y);
            await Task.Delay(2500);
            UpdateLayout();
            var metricsPath = Environment.GetEnvironmentVariable(
                "M1937_MAPEDITOR_METRICS");
            if (!string.IsNullOrWhiteSpace(metricsPath))
            {
                var metrics = EditorCanvas.LastRenderStatistics;
                var fullMetricsPath = Path.GetFullPath(metricsPath);
                Directory.CreateDirectory(
                    Path.GetDirectoryName(fullMetricsPath)!);
                File.WriteAllText(
                    fullMetricsPath,
                    JsonSerializer.Serialize(
                        new
                        {
                            schema_version = 1,
                            map_width = document.Width,
                            map_height = document.Height,
                            zoom = EditorCanvas.Zoom,
                            visible_cells =
                                metrics.VisibleCells.CellCount,
                            drawn_objects = metrics.DrawnObjects,
                            total_objects = metrics.TotalObjects,
                            render_microseconds =
                                metrics.ElapsedMicroseconds
                        },
                        new JsonSerializerOptions
                        {
                            WriteIndented = true
                        }));
            }
            var dpi = VisualTreeHelper.GetDpi(this);
            var width = Math.Max(
                1, (int)Math.Ceiling(ActualWidth * dpi.DpiScaleX));
            var height = Math.Max(
                1, (int)Math.Ceiling(ActualHeight * dpi.DpiScaleY));
            var bitmap = new RenderTargetBitmap(
                width, height, dpi.PixelsPerInchX, dpi.PixelsPerInchY,
                PixelFormats.Pbgra32);
            bitmap.Render(this);
            var encoder = new PngBitmapEncoder();
            encoder.Frames.Add(BitmapFrame.Create(bitmap));
            var fullPath = Path.GetFullPath(screenshotPath);
            Directory.CreateDirectory(Path.GetDirectoryName(fullPath)!);
            using var stream = File.Create(fullPath);
            encoder.Save(stream);
        }
        catch (Exception exception)
        {
            File.WriteAllText(
                Path.GetFullPath(screenshotPath) + ".error.txt",
                exception.ToString());
        }
        finally
        {
            Close();
        }
    }

    private string FindInitialMapDirectory()
    {
        var directory = new DirectoryInfo(AppContext.BaseDirectory);
        for (var depth = 0; directory is not null && depth < 8;
             depth++, directory = directory.Parent)
        {
            var candidate = Path.Combine(
                directory.FullName, "Mod");
            if (File.Exists(Path.Combine(candidate, "1937m000.vwf")))
                return candidate;
        }
        return Environment.GetFolderPath(
            Environment.SpecialFolder.MyDocuments);
    }

    private void Save_Click(object sender, RoutedEventArgs e)
    {
        if (currentPath is null)
        {
            SaveAs_Click(sender, e);
            return;
        }
        SyncCollections();
        MapDocumentSerializer.Save(document, currentPath);
        dirty = false;
        UpdateTitle();
        StatusText.Text = $"已保存：{currentPath}";
    }

    private void SaveAs_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new SaveFileDialog
        {
            Filter = "1937 地图工程 (*.m37map.json)|*.m37map.json",
            FileName = $"{SafeName(document.Name)}-副本.m37map.json"
        };
        if (dialog.ShowDialog(this) != true)
            return;
        currentPath = dialog.FileName;
        Save_Click(sender, e);
    }

    private void NativeVwfSaveAs_Click(
        object sender,
        RoutedEventArgs e)
    {
        try
        {
            SyncCollections();
            var sourcePath = ResolveNativeVwfSource();
            if (sourcePath is null)
                return;
            var diff = NativeVwfWriter.Analyze(document, sourcePath);
            var preview = new NativeVwfDiffDialog(
                Path.GetFileName(sourcePath), diff)
            {
                Owner = this
            };
            if (preview.ShowDialog() != true)
                return;

            var dialog = new SaveFileDialog
            {
                Filter = "原生关卡 (*.vwf)|*.vwf",
                InitialDirectory = Path.GetDirectoryName(sourcePath),
                FileName =
                    $"{Path.GetFileNameWithoutExtension(sourcePath)}" +
                    "-编辑副本.vwf",
                AddExtension = true,
                DefaultExt = ".vwf",
                OverwritePrompt = true
            };
            if (dialog.ShowDialog(this) != true)
                return;
            var result = NativeVwfWriter.SaveAs(
                document, sourcePath, dialog.FileName);
            StatusText.Text =
                $"原生 VWF 已安全另存：{result.OutputPath}";
            MessageBox.Show(
                this,
                $"已写入：{result.OutputPath}\n" +
                $"变化字节：{result.Diff.ChangedByteCount:N0}\n" +
                $"语义变化：{result.Diff.SemanticChanges.Count:N0}\n" +
                (result.BackupPath is null
                    ? "输出为新文件，没有覆盖任何已有文件。"
                    : $"原输出备份：{result.BackupPath}"),
                "原生 VWF 另存完成",
                MessageBoxButton.OK,
                MessageBoxImage.Information);
        }
        catch (Exception exception)
        {
            MessageBox.Show(
                this,
                exception.Message,
                "原生 VWF 另存被安全拒绝",
                MessageBoxButton.OK,
                MessageBoxImage.Error);
        }
    }

    private string? ResolveNativeVwfSource()
    {
        if (!string.IsNullOrWhiteSpace(currentVwfSourcePath) &&
            File.Exists(currentVwfSourcePath))
        {
            return currentVwfSourcePath;
        }
        if (string.IsNullOrWhiteSpace(document.ImportedFrom))
            return null;
        var dialog = new OpenFileDialog
        {
            Title = $"定位导入源 {document.ImportedFrom}",
            Filter = "原生关卡 (*.vwf)|*.vwf",
            FileName = document.ImportedFrom,
            InitialDirectory = FindInitialMapDirectory(),
            CheckFileExists = true
        };
        if (dialog.ShowDialog(this) != true)
            return null;
        currentVwfSourcePath = Path.GetFullPath(dialog.FileName);
        return currentVwfSourcePath;
    }

    private void ImportVwf_Click(object sender, RoutedEventArgs e) =>
        Open_Click(sender, e);

    private void Export_Click(object sender, RoutedEventArgs e)
    {
        SyncCollections();
        var errors = MapValidator.Validate(document);
        if (errors.Count > 0)
        {
            MessageBox.Show(
                this, string.Join(Environment.NewLine, errors),
                "导出前校验失败",
                MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }
        var dialog = new SaveFileDialog
        {
            Filter = "1937 任务包 (*.m37pack.json)|*.m37pack.json",
            FileName = $"{SafeName(document.Name)}.m37pack.json"
        };
        if (dialog.ShowDialog(this) != true)
            return;
        MapDocumentSerializer.Save(document, dialog.FileName);
        StatusText.Text = $"任务包已导出：{dialog.FileName}";
    }

    private void MissionPackageWizard_Click(
        object sender,
        RoutedEventArgs e)
    {
        var wizard = new MissionPackageWizard(
            document,
            currentVwfSourcePath,
            assetRoot)
        {
            Owner = this
        };
        wizard.ShowDialog();
        if (!string.IsNullOrWhiteSpace(wizard.LastPublishedPath))
            StatusText.Text =
                $"关卡包已生成：{wizard.LastPublishedPath}";
    }

    private void Validate_Click(object sender, RoutedEventArgs e)
    {
        SyncCollections();
        var errors = MapValidator.Validate(document);
        RefreshQualityIssues();
        var qualityErrors = IssueGrid.Items
            .Cast<MapIssue>()
            .Count(issue => issue.Severity == MapIssueSeverity.Error);
        var qualityWarnings = IssueGrid.Items
            .Cast<MapIssue>()
            .Count(issue => issue.Severity == MapIssueSeverity.Warning);
        MessageBox.Show(
            this,
            errors.Count == 0
                ? $"结构校验通过；质量面板有 {qualityErrors} 个错误、" +
                  $"{qualityWarnings} 个警告。点击问题行可定位。"
                : string.Join(Environment.NewLine, errors),
            "校验结果", MessageBoxButton.OK,
            errors.Count == 0
                ? MessageBoxImage.Information
                : MessageBoxImage.Warning);
    }

    private void RefreshIssues_Click(
        object sender,
        RoutedEventArgs e) =>
        RefreshQualityIssues();

    private void RefreshQualityIssues()
    {
        if (IssueGrid is null || IssueSummaryText is null)
            return;
        SyncCollections();
        var issues = MapQualityAnalyzer.Analyze(document);
        IssueGrid.ItemsSource =
            new ObservableCollection<MapIssue>(issues);
        var errors = issues.Count(
            issue => issue.Severity == MapIssueSeverity.Error);
        var warnings = issues.Count(
            issue => issue.Severity == MapIssueSeverity.Warning);
        var information = issues.Count(
            issue => issue.Severity == MapIssueSeverity.Info);
        IssueSummaryText.Text =
            $"Error {errors} · Warning {warnings} · Info {information}；" +
            "单击问题会定位到地图和对象。";
    }

    private void IssueGrid_SelectionChanged(
        object sender,
        SelectionChangedEventArgs e)
    {
        if (IssueGrid.SelectedItem is not MapIssue issue)
            return;
        if (!string.IsNullOrWhiteSpace(issue.ObjectId))
        {
            var item = document.Objects.FirstOrDefault(
                candidate => candidate.Id == issue.ObjectId);
            if (item is not null)
                SelectObject(item);
        }
        if (issue.X is not int x || issue.Y is not int y)
            return;
        var targetX =
            (x + 0.5) * document.EffectiveCellWidth *
            EditorCanvas.Zoom - MapScroll.ViewportWidth / 2;
        var targetY =
            (y + 0.5) * document.EffectiveCellHeight *
            EditorCanvas.Zoom - MapScroll.ViewportHeight / 2;
        MapScroll.ScrollToHorizontalOffset(Math.Max(0, targetX));
        MapScroll.ScrollToVerticalOffset(Math.Max(0, targetY));
        StatusText.Text =
            $"已定位问题 {issue.Code}：({x}, {y})";
    }

    private void ClearLayer_Click(object sender, RoutedEventArgs e)
    {
        if (MessageBox.Show(
                this, "清空当前图层的所有格点？", "确认",
                MessageBoxButton.YesNo,
                MessageBoxImage.Warning) != MessageBoxResult.Yes)
            return;
        var before = Snapshot();
        Array.Clear(document.Layer(activeLayer).Cells);
        CommitEdit(before, $"清空图层 {activeLayer}");
        EditorCanvas.Refresh();
    }

    private void EditorCanvas_CellHovered(
        object? sender, CellEventArgs e) =>
        CoordinateText.Text = $"格点：{e.X}, {e.Y}";

    private void EditorCanvas_CellInvoked(
        object? sender, CellEventArgs e)
    {
        var before = Snapshot();
        var erase = e.Erase || activeTool == "erase";
        if (activeTool == "asset" && !erase)
        {
            if (AssetList.SelectedItem is not AssetEntry asset)
            {
                StatusText.Text = "请先从左侧选择一个素材。";
                return;
            }
            if (asset.IsNone)
            {
                StatusText.Text = "当前为仅查看模式，不会向地图添加素材。";
                return;
            }
            if (asset.Kind == "map_background")
            {
                document.BackgroundAsset = asset.RelativePath;
                CommitEdit(before, $"更换背景 {asset.Name}");
                EditorCanvas.Refresh();
                StatusText.Text = $"已更换地图背景：{asset.Name}";
                return;
            }
            var item = new MapObject
            {
                Kind = asset.Kind,
                Name = asset.Name,
                Category = asset.Category,
                AssetPath = asset.RelativePath,
                Faction = asset.Kind == "character" ? "neutral" : "neutral",
                X = e.X,
                Y = e.Y,
                Properties =
                {
                    ["asset_id"] = asset.Id.ToString(),
                    ["source_name"] = asset.SourceName
                }
            };
            document.Objects.Add(item);
            RefreshObjects(item);
            CommitEdit(
                before,
                $"放置 {asset.Name}",
                "place-asset");
            StatusText.Text = $"已放置：{asset.Name}";
        }
        else if (activeTool == "select")
        {
            var item = document.Objects.LastOrDefault(
                value => Math.Abs(value.X - e.X) <= 1 &&
                         Math.Abs(value.Y - e.Y) <= 1);
            if (item is not null)
                SelectObject(item);
            return;
        }
        else if (activeTool == "paint" || erase)
        {
            document.Layer(activeLayer).Cells[
                document.Index(e.X, e.Y)] = erase ? 0 : 1;
        }
        if (activeTool == "paint" || erase)
        {
            CommitEdit(
                before,
                erase ? "擦除格点" : "绘制格点",
                $"paint-{activeLayer}-{erase}");
        }
        EditorCanvas.Refresh();
    }

    private void EditorCanvas_ObjectSelected(
        object? sender, MapObjectEventArgs e) =>
        SelectObject(e.MapObject);

    private void SelectObject(MapObject item)
    {
        ObjectGrid.SelectedItem = ObjectGrid.Items.Cast<MapObject>()
            .FirstOrDefault(value => value.Id == item.Id);
        if (ObjectGrid.SelectedItem is not null)
            ObjectGrid.ScrollIntoView(ObjectGrid.SelectedItem);
        EditorCanvas.SelectedObjectId = item.Id;
        UpdateRouteStatus(item);
    }

    private void CenterViewportAt(int x, int y)
    {
        var targetX =
            (x + 0.5) * document.EffectiveCellWidth *
            EditorCanvas.Zoom - MapScroll.ViewportWidth / 2;
        var targetY =
            (y + 0.5) * document.EffectiveCellHeight *
            EditorCanvas.Zoom - MapScroll.ViewportHeight / 2;
        MapScroll.ScrollToHorizontalOffset(Math.Max(0, targetX));
        MapScroll.ScrollToVerticalOffset(Math.Max(0, targetY));
    }

    private void DeleteObject_Click(object sender, RoutedEventArgs e)
    {
        if (ObjectGrid.SelectedItem is not MapObject selected)
            return;
        var before = Snapshot();
        document.Objects.RemoveAll(item => item.Id == selected.Id);
        RefreshObjects();
        EditorCanvas.SelectedObjectId = null;
        CommitEdit(before, $"删除对象 {selected.Name}");
        EditorCanvas.Refresh();
    }

    private void AddTask_Click(object sender, RoutedEventArgs e)
    {
        var before = Snapshot();
        document.Tasks.Add(new MissionTask());
        RefreshTasks();
        CommitEdit(before, "新增任务");
    }

    private void DeleteTask_Click(object sender, RoutedEventArgs e)
    {
        if (TaskGrid.SelectedItem is not MissionTask selected)
            return;
        var before = Snapshot();
        document.Tasks.RemoveAll(item => item.Id == selected.Id);
        RefreshTasks();
        CommitEdit(before, $"删除任务 {selected.Title}");
    }

    private void LayerList_SelectionChanged(
        object sender, SelectionChangedEventArgs e)
    {
        if (LayerList.SelectedItem is EditorLayer layer)
            activeLayer = layer.Kind;
    }

    private void LayerVisibility_PreviewMouseDown(
        object sender,
        MouseButtonEventArgs e) =>
        pendingLayerVisibilityEdit = Snapshot();

    private void LayerVisibility_Click(object sender, RoutedEventArgs e)
    {
        if (pendingLayerVisibilityEdit is not null)
        {
            CommitEdit(
                pendingLayerVisibilityEdit,
                "切换图层显示");
            pendingLayerVisibilityEdit = null;
        }
        EditorCanvas.Refresh();
    }

    private void ToolMode_Checked(object sender, RoutedEventArgs e)
    {
        if (sender is RadioButton button && button.Tag is string mode)
        {
            activeTool = mode;
            EditorCanvas.ObjectSelectionEnabled = mode == "select";
            if (mode == "paint")
            {
                document.Layer(activeLayer).Visible = true;
                EditorCanvas.Refresh();
            }
            StatusText.Text = mode switch
            {
                "asset" => "放置模式：选择左侧素材后单击地图",
                "select" => "选择模式：单击对象",
                "paint" => "障碍绘制模式：左键绘制、右键擦除",
                _ => "擦除模式：在地图上拖动"
            };
        }
    }

    private void ZoomSlider_ValueChanged(
        object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        if (EditorCanvas is not null)
            EditorCanvas.Zoom = e.NewValue;
        if (ZoomText is not null)
            ZoomText.Text = $"{e.NewValue * 100:0}%";
    }

    private void PatrolPreview_Changed(object sender, RoutedEventArgs e)
    {
        if (EditorCanvas is null ||
            ShowRoutesCheck is null ||
            MotionPreviewCheck is null)
            return;
        EditorCanvas.ShowPatrolRoutes =
            ShowRoutesCheck.IsChecked == true;
        EditorCanvas.MotionPreviewEnabled =
            MotionPreviewCheck.IsChecked == true;
    }

    private void AnalysisPreview_Changed(
        object sender,
        RoutedEventArgs e)
    {
        if (EditorCanvas is null)
            return;
        EditorCanvas.ShowConnectivityHeatmap =
            ConnectivityHeatmapCheck?.IsChecked == true;
        EditorCanvas.ShowAiRanges =
            AiRangesCheck?.IsChecked == true;
        UpdateRenderStatus();
    }

    private void AnalysisProfile_Changed(
        object sender,
        SelectionChangedEventArgs e) =>
        UpdateAnalysisProfile();

    private void UpdateAnalysisProfile()
    {
        if (EditorCanvas is null ||
            AiLevelCombo is null ||
            DifficultyCombo is null)
            return;
        var profile = EnemyPreviewProfile.ForDifficulty(
            DifficultyCombo.SelectedIndex,
            AiLevelCombo.SelectedIndex);
        EditorCanvas.EnemyPreviewProfile = profile;
        if (AnalysisLegendText is not null)
        {
            AnalysisLegendText.Text =
                $"绿色=带遮挡视线 {profile.VisionRadiusWorld}；" +
                $"红=攻击 {profile.AttackRadiusWorld}（{profile.AttackSource}）；" +
                $"蓝=听觉 {profile.HearingRadiusWorld}（{profile.HearingSource}）；" +
                $"橙=警报 {profile.AlertRadiusWorld}（{profile.AlertSource}）。";
        }
    }

    private void MapScroll_ScrollChanged(
        object sender,
        ScrollChangedEventArgs e) =>
        UpdateVisibleViewport();

    private void MapScroll_SizeChanged(
        object sender,
        SizeChangedEventArgs e) =>
        UpdateVisibleViewport();

    private void UpdateVisibleViewport()
    {
        if (MapScroll is null || EditorCanvas is null)
            return;
        EditorCanvas.SetVisibleViewport(
            MapScroll.HorizontalOffset,
            MapScroll.VerticalOffset,
            Math.Max(1, MapScroll.ViewportWidth),
            Math.Max(1, MapScroll.ViewportHeight));
        Dispatcher.BeginInvoke(
            DispatcherPriority.ContextIdle,
            new Action(UpdateRenderStatus));
    }

    private void UpdateRenderStatus()
    {
        if (RenderStatusText is null || EditorCanvas is null)
            return;
        var stats = EditorCanvas.LastRenderStatistics;
        RenderStatusText.Text =
            $"局部绘制：{stats.VisibleCells.CellCount:N0} 格 / " +
            $"{stats.DrawnObjects:N0} 对象 / " +
            $"{stats.ElapsedMicroseconds / 1000.0:F1} ms";
    }

    private void MapScroll_PreviewMouseWheel(
        object sender, MouseWheelEventArgs e)
    {
        if (!Keyboard.Modifiers.HasFlag(ModifierKeys.Control))
            return;
        ZoomSlider.Value = Math.Clamp(
            ZoomSlider.Value + Math.Sign(e.Delta) * 0.1,
            ZoomSlider.Minimum, ZoomSlider.Maximum);
        e.Handled = true;
    }

    private void AssetFilter_Changed(
        object sender, EventArgs e) =>
        RefreshAssetFilter();

    private void RefreshAssetFilter()
    {
        if (AssetList is null || AssetCategoryCombo is null ||
            AssetSearchText is null)
            return;
        var category = AssetCategoryCombo.SelectedItem?.ToString()
                       ?? "全部素材";
        var search = AssetSearchText.Text.Trim();
        var filtered = allAssets.Where(asset =>
            asset.IsNone ||
            ((category == "全部素材" ||
              string.Equals(
                  asset.Category, category,
                  StringComparison.CurrentCultureIgnoreCase)) &&
             (search.Length == 0 ||
              asset.Name.Contains(
                  search, StringComparison.CurrentCultureIgnoreCase) ||
              asset.SourceName.Contains(
                  search, StringComparison.CurrentCultureIgnoreCase))))
            .ToList();
        AssetList.ItemsSource = filtered;
        if (filtered.Count > 0)
            AssetList.SelectedIndex = 0;
    }

    private void AssetList_SelectionChanged(
        object sender, SelectionChangedEventArgs e)
    {
        if (AssetList.SelectedItem is not AssetEntry asset)
            return;
        if (asset.IsNone)
        {
            SelectMode.IsChecked = true;
            SelectedAssetText.Text = "鼠标箭头：仅查看，不放置素材";
            StatusText.Text = "仅查看模式：可以浏览地图或选择已有对象";
            return;
        }
        PlaceAssetMode.IsChecked = true;
        SelectedAssetText.Text = $"{asset.Name}\n{asset.Category}";
        StatusText.Text = $"当前素材：{asset.Name}；在地图上单击即可放置";
    }

    private void MapNameText_TextChanged(
        object sender, TextChangedEventArgs e)
    {
        if (document is null || MapNameText.Text == document.Name)
            return;
        document.Name = MapNameText.Text;
    }

    private void MapNameText_GotKeyboardFocus(
        object sender,
        KeyboardFocusChangedEventArgs e) =>
        pendingNameEdit = Snapshot();

    private void MapNameText_LostKeyboardFocus(
        object sender,
        KeyboardFocusChangedEventArgs e)
    {
        if (pendingNameEdit is null)
            return;
        CommitEdit(
            pendingNameEdit,
            "修改关卡名称",
            "map-name");
        pendingNameEdit = null;
    }

    private void Grid_BeginningEdit(
        object sender,
        DataGridBeginningEditEventArgs e) =>
        pendingGridEdit = Snapshot();

    private void Grid_CellEditEnding(
        object sender,
        DataGridCellEditEndingEventArgs e)
    {
        if (pendingGridEdit is null)
            return;
        var before = pendingGridEdit;
        pendingGridEdit = null;
        var description = sender == ObjectGrid
            ? "修改对象属性"
            : "修改任务属性";
        Dispatcher.BeginInvoke(
            DispatcherPriority.DataBind,
            new Action(() =>
            {
                CommitEdit(
                    before,
                    description,
                    sender == ObjectGrid
                        ? "object-grid"
                        : "task-grid");
                EditorCanvas.Refresh();
            }));
    }

    private void ObjectGrid_SelectionChanged(
        object sender, SelectionChangedEventArgs e)
    {
        var selected = ObjectGrid.SelectedItem as MapObject;
        EditorCanvas.SelectedObjectId = selected?.Id;
        UpdateRouteStatus(selected);
    }

    private void UpdateRouteStatus(MapObject? selected = null)
    {
        if (RouteStatusText is null)
            return;
        if (selected is not null &&
            selected.IsLiving &&
            selected.PatrolWaypoints.Count > 0)
        {
            RouteStatusText.Text =
                $"所选路线：{selected.Name}，" +
                $"{selected.PatrolWaypoints.Count} 个路线点";
            return;
        }

        var routeCount = document.Objects.Count(
            item => item.IsLiving &&
                    item.PatrolWaypoints.Count > 0);
        var movingCount = document.Objects.Count(
            item => item.PatrolEnabled &&
                    item.PatrolWaypoints.Count > 1 &&
                    item.PatrolWaypoints.Skip(1).Any(point =>
                        point.X != item.PatrolWaypoints[0].X ||
                        point.Y != item.PatrolWaypoints[0].Y));
        RouteStatusText.Text =
            $"活动路线：{routeCount} 条，运动 {movingCount} 条";
    }

    private void Help_Click(object sender, RoutedEventArgs e) =>
        MessageBox.Show(
            this,
            "只需三步：\n\n" +
            "1. 点击“打开地图”，直接选择 Mod 目录中的 .vwf 原版关卡，" +
            "或打开以前保存的 .m37map.json。\n\n" +
            "2. 默认选中素材列表第一项“鼠标箭头”，此时只查看、不添加。" +
            "需要编辑时再选择其他素材并在地图上单击放置；右键可擦除，" +
            "Shift+单击可选择已有对象。\n\n" +
            "3. 点击“另存为新地图”，原版文件永远不会被覆盖。\n\n" +
            "从 VWF 打开的地图还可使用“安全另存为原生 VWF”：编辑器会先" +
            "显示二进制/语义差异，再写临时文件、重解析并原子替换输出；" +
            "已有输出会保留 .bak。\n\n" +
            "高级图层和任务编辑仍然保留，但默认收起，不影响简单使用。",
            "三步使用说明",
            MessageBoxButton.OK, MessageBoxImage.Information);

    private void Exit_Click(object sender, RoutedEventArgs e) => Close();

    protected override void OnClosing(
        System.ComponentModel.CancelEventArgs e)
    {
        if (!ConfirmDiscard())
            e.Cancel = true;
        base.OnClosing(e);
    }

    private bool ConfirmDiscard() =>
        !dirty || MessageBox.Show(
            this, "当前地图尚未保存，继续并放弃修改？",
            "未保存的修改", MessageBoxButton.YesNo,
            MessageBoxImage.Warning) == MessageBoxResult.Yes;

    private void SyncCollections()
    {
        document.Objects =
            ObjectGrid.Items.Cast<MapObject>().ToList();
        document.Tasks =
            TaskGrid.Items.Cast<MissionTask>().ToList();
    }

    private void RefreshObjects(MapObject? selected = null)
    {
        ObjectGrid.ItemsSource =
            new ObservableCollection<MapObject>(document.Objects);
        if (selected is not null)
        {
            ObjectGrid.SelectedItem =
                ObjectGrid.Items.Cast<MapObject>()
                    .First(item => item.Id == selected.Id);
            EditorCanvas.SelectedObjectId = selected.Id;
        }
    }

    private void RefreshTasks() =>
        TaskGrid.ItemsSource =
            new ObservableCollection<MissionTask>(document.Tasks);

    private static string SafeName(string value) =>
        string.Concat(value.Select(character =>
            Path.GetInvalidFileNameChars().Contains(character)
                ? '_'
                : character));
}

internal sealed class NativeVwfDiffDialog : Window
{
    public NativeVwfDiffDialog(
        string sourceName,
        NativeVwfDiff diff)
    {
        Title = "原生 VWF 写入前差异";
        Width = 920;
        Height = 680;
        MinWidth = 720;
        MinHeight = 520;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        Background = Brushes.White;
        Foreground = Brushes.Black;

        var root = new DockPanel { Margin = new Thickness(18) };
        var buttons = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            HorizontalAlignment = HorizontalAlignment.Right,
            Margin = new Thickness(0, 12, 0, 0)
        };
        var cancel = new Button
        {
            Content = "取消",
            IsCancel = true,
            MinWidth = 90
        };
        var accept = new Button
        {
            Content = "确认并选择输出文件",
            IsDefault = true,
            MinWidth = 180
        };
        accept.Click += (_, _) => DialogResult = true;
        buttons.Children.Add(cancel);
        buttons.Children.Add(accept);
        DockPanel.SetDock(buttons, Dock.Bottom);
        root.Children.Add(buttons);

        var summary = new TextBlock
        {
            Text =
                $"只读源：{sourceName}\n" +
                $"变化字节：{diff.ChangedByteCount:N0}；" +
                $"二进制区段：{diff.BinaryChanges.Count:N0}；" +
                $"语义变化：{diff.SemanticChanges.Count:N0}\n" +
                $"源 SHA-256：{diff.SourceSha256}\n" +
                $"输出 SHA-256：{diff.OutputSha256}",
            TextWrapping = TextWrapping.Wrap,
            FontFamily = new FontFamily("Consolas"),
            Margin = new Thickness(0, 0, 0, 12)
        };
        DockPanel.SetDock(summary, Dock.Top);
        root.Children.Add(summary);

        var tabs = new TabControl();
        tabs.Items.Add(new TabItem
        {
            Header = $"语义差异 ({diff.SemanticChanges.Count})",
            Content = NewGrid(
                diff.SemanticChanges,
                ("类别", "Category"),
                ("目标", "Target"),
                ("说明", "Description"))
        });
        tabs.Items.Add(new TabItem
        {
            Header = $"二进制差异 ({diff.BinaryChanges.Count})",
            Content = NewGrid(
                diff.BinaryChanges,
                ("偏移", "Offset"),
                ("长度", "Length"),
                ("原字节预览", "BeforeHex"),
                ("新字节预览", "AfterHex"))
        });
        root.Children.Add(tabs);
        Content = root;
    }

    private static DataGrid NewGrid<T>(
        IReadOnlyList<T> items,
        params (string Header, string Property)[] columns)
    {
        var grid = new DataGrid
        {
            ItemsSource = items,
            AutoGenerateColumns = false,
            IsReadOnly = true,
            CanUserAddRows = false,
            HeadersVisibility = DataGridHeadersVisibility.Column,
            GridLinesVisibility = DataGridGridLinesVisibility.Horizontal
        };
        foreach (var column in columns)
        {
            grid.Columns.Add(new DataGridTextColumn
            {
                Header = column.Header,
                Binding = new System.Windows.Data.Binding(column.Property),
                Width = column.Property == "Description"
                    ? new DataGridLength(1, DataGridLengthUnitType.Star)
                    : DataGridLength.Auto
            });
        }
        return grid;
    }
}

internal sealed class NewMapDialog : Window
{
    private readonly TextBox name = new()
    {
        Text = "新关卡",
        Margin = new Thickness(0, 4, 0, 10)
    };
    private readonly TextBox width = new()
    {
        Text = "64",
        Margin = new Thickness(0, 4, 0, 10)
    };
    private readonly TextBox height = new()
    {
        Text = "48",
        Margin = new Thickness(0, 4, 0, 10)
    };

    public string MapName =>
        name.Text.Trim().Length == 0 ? "未命名关卡" : name.Text.Trim();
    public int MapWidth => int.Parse(width.Text);
    public int MapHeight => int.Parse(height.Text);

    public NewMapDialog()
    {
        Title = "新建地图";
        Width = 360;
        Height = 340;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        Background = System.Windows.Media.Brushes.White;
        Foreground = System.Windows.Media.Brushes.Black;
        var panel = new StackPanel { Margin = new Thickness(22) };
        panel.Children.Add(new TextBlock
        {
            Text = "名称",
            Foreground = System.Windows.Media.Brushes.Black
        });
        panel.Children.Add(name);
        panel.Children.Add(new TextBlock
        {
            Text = "宽（格）",
            Foreground = System.Windows.Media.Brushes.Black
        });
        panel.Children.Add(width);
        panel.Children.Add(new TextBlock
        {
            Text = "高（格）",
            Foreground = System.Windows.Media.Brushes.Black
        });
        panel.Children.Add(height);
        var ok = new Button
        {
            Content = "创建",
            IsDefault = true,
            Margin = new Thickness(0, 8, 0, 0)
        };
        ok.Click += (_, _) =>
        {
            if (!int.TryParse(width.Text, out var w) ||
                !int.TryParse(height.Text, out var h) ||
                w is < 8 or > 2048 || h is < 8 or > 2048)
            {
                MessageBox.Show(this, "宽高必须是 8—2048 的整数。");
                return;
            }
            DialogResult = true;
        };
        panel.Children.Add(ok);
        Content = panel;
    }
}
