using System.Collections.ObjectModel;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using Microsoft.Win32;
using Mission1937.MapEditor.Core;

namespace Mission1937.MapEditor.App;

public partial class MainWindow : Window
{
    private MapDocument document = MapDocument.Create("新关卡", 64, 48);
    private string? currentPath;
    private EditorLayerKind activeLayer = EditorLayerKind.Terrain;
    private string activeTool = "paint";
    private bool dirty;

    public MainWindow()
    {
        InitializeComponent();
        CommandBindings.Add(new CommandBinding(ApplicationCommands.New, New_Click));
        CommandBindings.Add(new CommandBinding(ApplicationCommands.Open, Open_Click));
        CommandBindings.Add(new CommandBinding(ApplicationCommands.Save, Save_Click));
        LoadDocument(document, null);
    }

    private void LoadDocument(MapDocument value, string? path)
    {
        document = value;
        currentPath = path;
        LayerList.ItemsSource = document.Layers;
        LayerList.SelectedIndex = 0;
        ObjectGrid.ItemsSource = new ObservableCollection<MapObject>(document.Objects);
        TaskGrid.ItemsSource = new ObservableCollection<MissionTask>(document.Tasks);
        MapNameText.Text = document.Name;
        MapSizeText.Text = $"{document.Width} × {document.Height} 格；每格 {document.CellSize} 像素";
        EditorCanvas.Document = document;
        dirty = false;
        UpdateTitle();
        StatusText.Text = path is null ? "已新建地图" : $"已打开：{path}";
    }

    private void UpdateTitle()
    {
        Title = $"1937 特种兵地图与任务编辑器 — {document.Name}{(dirty ? " *" : "")}";
    }

    private void MarkDirty()
    {
        dirty = true;
        UpdateTitle();
    }

    private void New_Click(object sender, RoutedEventArgs e)
    {
        if (!ConfirmDiscard()) return;
        var dialog = new NewMapDialog { Owner = this };
        if (dialog.ShowDialog() == true)
            LoadDocument(MapDocument.Create(dialog.MapName, dialog.MapWidth, dialog.MapHeight), null);
    }

    private void Open_Click(object sender, RoutedEventArgs e)
    {
        if (!ConfirmDiscard()) return;
        var dialog = new OpenFileDialog
        {
            Filter = "1937 地图工程 (*.m37map.json)|*.m37map.json|JSON (*.json)|*.json"
        };
        if (dialog.ShowDialog(this) == true)
            LoadDocument(MapDocumentSerializer.Load(dialog.FileName), dialog.FileName);
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
            FileName = $"{SafeName(document.Name)}.m37map.json"
        };
        if (dialog.ShowDialog(this) != true) return;
        currentPath = dialog.FileName;
        Save_Click(sender, e);
    }

    private void ImportVwf_Click(object sender, RoutedEventArgs e)
    {
        if (!ConfirmDiscard()) return;
        var dialog = new OpenFileDialog { Filter = "原版 VWF (*.vwf)|*.vwf" };
        if (dialog.ShowDialog(this) != true) return;
        try
        {
            LoadDocument(OriginalVwfImporter.Import(dialog.FileName), null);
            StatusText.Text = $"已解析导入：{dialog.FileName}";
        }
        catch (Exception exception)
        {
            MessageBox.Show(this, exception.Message, "VWF 导入失败",
                MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    private void Export_Click(object sender, RoutedEventArgs e)
    {
        SyncCollections();
        var errors = MapValidator.Validate(document);
        if (errors.Count > 0)
        {
            MessageBox.Show(this, string.Join(Environment.NewLine, errors),
                "导出前校验失败", MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }
        var dialog = new SaveFileDialog
        {
            Filter = "1937 任务包 (*.m37pack.json)|*.m37pack.json",
            FileName = $"{SafeName(document.Name)}.m37pack.json"
        };
        if (dialog.ShowDialog(this) != true) return;
        MapDocumentSerializer.Save(document, dialog.FileName);
        StatusText.Text = $"任务包已导出：{dialog.FileName}";
    }

    private void Validate_Click(object sender, RoutedEventArgs e)
    {
        SyncCollections();
        var errors = MapValidator.Validate(document);
        MessageBox.Show(this,
            errors.Count == 0 ? "地图、图层、对象引用和任务链均通过校验。" :
                string.Join(Environment.NewLine, errors),
            "校验结果", MessageBoxButton.OK,
            errors.Count == 0 ? MessageBoxImage.Information : MessageBoxImage.Warning);
    }

    private void ClearLayer_Click(object sender, RoutedEventArgs e)
    {
        if (MessageBox.Show(this, "清空当前图层的所有格点？", "确认",
            MessageBoxButton.YesNo, MessageBoxImage.Warning) != MessageBoxResult.Yes) return;
        Array.Clear(document.Layer(activeLayer).Cells);
        MarkDirty();
        EditorCanvas.Refresh();
    }

    private void EditorCanvas_CellHovered(object? sender, CellEventArgs e) =>
        CoordinateText.Text = $"格点：{e.X}, {e.Y}";

    private void EditorCanvas_CellInvoked(object? sender, CellEventArgs e)
    {
        var erase = e.Erase || activeTool == "erase";
        if (activeTool == "object" && !erase)
        {
            var kind = ((ComboBoxItem)ObjectKindCombo.SelectedItem).Tag?.ToString() ?? "enemy";
            var item = new MapObject
            {
                Kind = kind,
                Name = $"{((ComboBoxItem)ObjectKindCombo.SelectedItem).Content} {document.Objects.Count + 1}",
                Faction = kind == "player" ? "player" : "enemy",
                X = e.X,
                Y = e.Y
            };
            document.Objects.Add(item);
            RefreshObjects(item);
        }
        else if (activeTool == "select")
        {
            var item = document.Objects.LastOrDefault(value => value.X == e.X && value.Y == e.Y);
            if (item is not null) SelectObject(item);
            return;
        }
        else
        {
            var value = 1;
            _ = int.TryParse(BrushValueText.Text, out value);
            document.Layer(activeLayer).Cells[document.Index(e.X, e.Y)] = erase ? 0 : value;
        }
        MarkDirty();
        EditorCanvas.Refresh();
    }

    private void EditorCanvas_ObjectSelected(object? sender, MapObjectEventArgs e) =>
        SelectObject(e.MapObject);

    private void SelectObject(MapObject item)
    {
        ObjectGrid.SelectedItem = ObjectGrid.Items.Cast<MapObject>()
            .FirstOrDefault(value => value.Id == item.Id);
        ObjectGrid.ScrollIntoView(ObjectGrid.SelectedItem);
    }

    private void DeleteObject_Click(object sender, RoutedEventArgs e)
    {
        if (ObjectGrid.SelectedItem is not MapObject selected) return;
        document.Objects.RemoveAll(item => item.Id == selected.Id);
        RefreshObjects();
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
        if (TaskGrid.SelectedItem is not MissionTask selected) return;
        document.Tasks.RemoveAll(item => item.Id == selected.Id);
        RefreshTasks();
        MarkDirty();
    }

    private void LayerList_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (LayerList.SelectedItem is EditorLayer layer) activeLayer = layer.Kind;
    }

    private void LayerVisibility_Click(object sender, RoutedEventArgs e)
    {
        MarkDirty();
        EditorCanvas.Refresh();
    }

    private void ToolCombo_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (ToolCombo?.SelectedItem is ComboBoxItem item)
            activeTool = item.Tag?.ToString() ?? "paint";
    }

    private void ZoomSlider_ValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        if (EditorCanvas is not null) EditorCanvas.Zoom = e.NewValue;
    }

    private void MapScroll_PreviewMouseWheel(object sender, MouseWheelEventArgs e)
    {
        if (!Keyboard.Modifiers.HasFlag(ModifierKeys.Control)) return;
        ZoomSlider.Value = Math.Clamp(ZoomSlider.Value + Math.Sign(e.Delta) * 0.25,
            ZoomSlider.Minimum, ZoomSlider.Maximum);
        e.Handled = true;
    }

    private void MapNameText_TextChanged(object sender, TextChangedEventArgs e)
    {
        if (document is null || MapNameText.Text == document.Name) return;
        document.Name = MapNameText.Text;
        MarkDirty();
    }

    private void ObjectGrid_SelectionChanged(object sender, SelectionChangedEventArgs e) =>
        EditorCanvas.Refresh();

    private void Help_Click(object sender, RoutedEventArgs e) =>
        MessageBox.Show(this,
            "画笔：在当前图层写入“值”。右键始终擦除。\n" +
            "对象：选择类型后点击地图放置；选择工具可编辑列表。\n" +
            "任务：用 ID、触发器、目标对象 ID 和后继 ID 组成任务链。\n" +
            "VWF 导入会解析五个图层和场景对象，保存为可版本管理的 JSON。",
            "操作说明", MessageBoxButton.OK, MessageBoxImage.Information);

    private void Exit_Click(object sender, RoutedEventArgs e) => Close();

    protected override void OnClosing(System.ComponentModel.CancelEventArgs e)
    {
        if (!ConfirmDiscard()) e.Cancel = true;
        base.OnClosing(e);
    }

    private bool ConfirmDiscard() =>
        !dirty || MessageBox.Show(this, "当前工程尚未保存，继续并放弃修改？",
            "未保存修改", MessageBoxButton.YesNo,
            MessageBoxImage.Warning) == MessageBoxResult.Yes;

    private void SyncCollections()
    {
        document.Objects = ObjectGrid.Items.Cast<MapObject>().ToList();
        document.Tasks = TaskGrid.Items.Cast<MissionTask>().ToList();
    }

    private void RefreshObjects(MapObject? selected = null)
    {
        ObjectGrid.ItemsSource = new ObservableCollection<MapObject>(document.Objects);
        if (selected is not null) ObjectGrid.SelectedItem = ObjectGrid.Items.Cast<MapObject>()
            .First(item => item.Id == selected.Id);
    }

    private void RefreshTasks() =>
        TaskGrid.ItemsSource = new ObservableCollection<MissionTask>(document.Tasks);

    private static string SafeName(string value) =>
        string.Concat(value.Select(character =>
            Path.GetInvalidFileNameChars().Contains(character) ? '_' : character));
}

internal sealed class NewMapDialog : Window
{
    private readonly TextBox name = new() { Text = "新关卡", Margin = new Thickness(0, 4, 0, 10) };
    private readonly TextBox width = new() { Text = "64", Margin = new Thickness(0, 4, 0, 10) };
    private readonly TextBox height = new() { Text = "48", Margin = new Thickness(0, 4, 0, 10) };

    public string MapName => name.Text.Trim().Length == 0 ? "未命名关卡" : name.Text.Trim();
    public int MapWidth => int.Parse(width.Text);
    public int MapHeight => int.Parse(height.Text);

    public NewMapDialog()
    {
        Title = "新建地图";
        Width = 340;
        Height = 320;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        Background = System.Windows.Media.Brushes.White;
        var panel = new StackPanel { Margin = new Thickness(22) };
        panel.Children.Add(new TextBlock { Text = "名称" });
        panel.Children.Add(name);
        panel.Children.Add(new TextBlock { Text = "宽（格）" });
        panel.Children.Add(width);
        panel.Children.Add(new TextBlock { Text = "高（格）" });
        panel.Children.Add(height);
        var ok = new Button { Content = "创建", IsDefault = true, Margin = new Thickness(0, 8, 0, 0) };
        ok.Click += (_, _) =>
        {
            if (!int.TryParse(width.Text, out var w) || !int.TryParse(height.Text, out var h) ||
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
