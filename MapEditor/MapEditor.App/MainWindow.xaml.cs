using System.Collections.ObjectModel;
using System.IO;
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
    private EditorLayerKind activeLayer = EditorLayerKind.MovementObstacle;
    private string activeTool = "asset";
    private bool dirty;

    public MainWindow()
    {
        InitializeComponent();
        CommandBindings.Add(new CommandBinding(
            ApplicationCommands.New, New_Click));
        CommandBindings.Add(new CommandBinding(
            ApplicationCommands.Open, Open_Click));
        CommandBindings.Add(new CommandBinding(
            ApplicationCommands.Save, Save_Click));

        assetRoot = AssetLibrary.FindRoot();
        allAssets = AssetLibrary.Load(assetRoot);
        ConfigureAssetLibrary();
        EditorCanvas.AssetRoot = assetRoot;
        LoadDocument(document, null);
        Loaded += AutomatedPreview_Loaded;
    }

    private void ConfigureAssetLibrary()
    {
        AssetCategoryCombo.Items.Add("全部素材");
        foreach (var category in allAssets
                     .Select(asset => asset.Category)
                     .Where(value => !string.IsNullOrWhiteSpace(value))
                     .Distinct(StringComparer.CurrentCultureIgnoreCase)
                     .OrderBy(value => value))
            AssetCategoryCombo.Items.Add(category);
        AssetCategoryCombo.SelectedIndex = 0;
        RefreshAssetFilter();
        AssetStatusText.Text = assetRoot is null
            ? "素材库：未找到（仍可编辑图层）"
            : $"素材库：{allAssets.Count:N0} 项";
    }

    private void LoadDocument(MapDocument value, string? path)
    {
        document = value;
        currentPath = path;
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
        dirty = false;
        UpdateTitle();
        StatusText.Text = path is null
            ? document.ImportedFrom is null
                ? "已新建空白地图"
                : $"已打开原版地图 {document.ImportedFrom}，请使用“另存为”保存副本"
            : $"已打开：{path}";

        Dispatcher.BeginInvoke(
            DispatcherPriority.ContextIdle,
            new Action(FitMapToWindow));
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

    private void New_Click(object sender, RoutedEventArgs e)
    {
        if (!ConfirmDiscard())
            return;
        var dialog = new NewMapDialog { Owner = this };
        if (dialog.ShowDialog() == true)
            LoadDocument(
                MapDocument.Create(
                    dialog.MapName, dialog.MapWidth, dialog.MapHeight),
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
                OriginalVwfImporter.Import(path, assetRoot), null);
        }
        else
        {
            LoadDocument(MapDocumentSerializer.Load(path), path);
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
            await Dispatcher.InvokeAsync(
                FitMapToWindow, DispatcherPriority.ContextIdle);
            await Task.Delay(2500);
            UpdateLayout();
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

    private void Validate_Click(object sender, RoutedEventArgs e)
    {
        SyncCollections();
        var errors = MapValidator.Validate(document);
        MessageBox.Show(
            this,
            errors.Count == 0
                ? "地图、图层、对象引用和任务链均通过校验。"
                : string.Join(Environment.NewLine, errors),
            "校验结果", MessageBoxButton.OK,
            errors.Count == 0
                ? MessageBoxImage.Information
                : MessageBoxImage.Warning);
    }

    private void ClearLayer_Click(object sender, RoutedEventArgs e)
    {
        if (MessageBox.Show(
                this, "清空当前图层的所有格点？", "确认",
                MessageBoxButton.YesNo,
                MessageBoxImage.Warning) != MessageBoxResult.Yes)
            return;
        Array.Clear(document.Layer(activeLayer).Cells);
        MarkDirty();
        EditorCanvas.Refresh();
    }

    private void EditorCanvas_CellHovered(
        object? sender, CellEventArgs e) =>
        CoordinateText.Text = $"格点：{e.X}, {e.Y}";

    private void EditorCanvas_CellInvoked(
        object? sender, CellEventArgs e)
    {
        var erase = e.Erase || activeTool == "erase";
        if (activeTool == "asset" && !erase)
        {
            if (AssetList.SelectedItem is not AssetEntry asset)
            {
                StatusText.Text = "请先从左侧选择一个素材。";
                return;
            }
            if (asset.Kind == "map_background")
            {
                document.BackgroundAsset = asset.RelativePath;
                MarkDirty();
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
        MarkDirty();
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
    }

    private void DeleteObject_Click(object sender, RoutedEventArgs e)
    {
        if (ObjectGrid.SelectedItem is not MapObject selected)
            return;
        document.Objects.RemoveAll(item => item.Id == selected.Id);
        RefreshObjects();
        EditorCanvas.SelectedObjectId = null;
        MarkDirty();
        EditorCanvas.Refresh();
    }

    private void AddTask_Click(object sender, RoutedEventArgs e)
    {
        document.Tasks.Add(new MissionTask());
        RefreshTasks();
        MarkDirty();
    }

    private void DeleteTask_Click(object sender, RoutedEventArgs e)
    {
        if (TaskGrid.SelectedItem is not MissionTask selected)
            return;
        document.Tasks.RemoveAll(item => item.Id == selected.Id);
        RefreshTasks();
        MarkDirty();
    }

    private void LayerList_SelectionChanged(
        object sender, SelectionChangedEventArgs e)
    {
        if (LayerList.SelectedItem is EditorLayer layer)
            activeLayer = layer.Kind;
    }

    private void LayerVisibility_Click(object sender, RoutedEventArgs e)
    {
        MarkDirty();
        EditorCanvas.Refresh();
    }

    private void ToolMode_Checked(object sender, RoutedEventArgs e)
    {
        if (sender is RadioButton button && button.Tag is string mode)
        {
            activeTool = mode;
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
            (category == "全部素材" ||
             string.Equals(
                 asset.Category, category,
                 StringComparison.CurrentCultureIgnoreCase)) &&
            (search.Length == 0 ||
             asset.Name.Contains(
                 search, StringComparison.CurrentCultureIgnoreCase) ||
             asset.SourceName.Contains(
                 search, StringComparison.CurrentCultureIgnoreCase)))
            .Take(800)
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
        SelectedAssetText.Text = $"{asset.Name}\n{asset.Category}";
        StatusText.Text = $"当前素材：{asset.Name}；在地图上单击即可放置";
    }

    private void MapNameText_TextChanged(
        object sender, TextChangedEventArgs e)
    {
        if (document is null || MapNameText.Text == document.Name)
            return;
        document.Name = MapNameText.Text;
        MarkDirty();
    }

    private void ObjectGrid_SelectionChanged(
        object sender, SelectionChangedEventArgs e)
    {
        EditorCanvas.SelectedObjectId =
            (ObjectGrid.SelectedItem as MapObject)?.Id;
    }

    private void Help_Click(object sender, RoutedEventArgs e) =>
        MessageBox.Show(
            this,
            "只需三步：\n\n" +
            "1. 点击“打开地图”，直接选择 Mod 目录中的 .vwf 原版关卡，" +
            "或打开以前保存的 .m37map.json。\n\n" +
            "2. 从左侧选择素材，在地图上单击放置；右键可擦除，" +
            "Shift+单击可选择已有对象。\n\n" +
            "3. 点击“另存为新地图”，原版文件永远不会被覆盖。\n\n" +
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
