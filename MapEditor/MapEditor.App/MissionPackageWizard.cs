using System.Diagnostics;
using System.IO;
using System.Text;
using System.Windows;
using System.Windows.Controls;
using Microsoft.Win32;
using Mission1937.MapEditor.Core;

namespace Mission1937.MapEditor.App;

public sealed class MissionPackageWizard : Window
{
    private readonly string repositoryRoot;
    private readonly string? assetRoot;
    private MapDocument sourceDocument;
    private MissionPackageDraftResult? draft;
    private string? candidateHash;

    private readonly TextBox sourcePath = NewTextBox();
    private readonly TextBox title = NewTextBox("新扩展关卡");
    private readonly TextBox story = NewTextBox(
        "请说明年代、地点、敌我态势、行动目标和撤离条件。");
    private readonly ComboBox mode = NewComboBox();
    private readonly ComboBox engineMission = NewComboBox();
    private readonly ComboBox playerScene = NewComboBox();
    private readonly ComboBox contactScene = NewComboBox();
    private readonly ComboBox exitScene = NewComboBox();
    private readonly ListBox enemyScenes = NewSceneList();
    private readonly ListBox objectiveScenes = NewSceneList();
    private readonly TextBox enemyDistance = NewTextBox("800");
    private readonly TextBox patrolDistance = NewTextBox("800");
    private readonly TextBox reachableRatio = NewTextBox("0.95");
    private readonly TextBox blockWidth = NewTextBox("40");
    private readonly TextBox blockHeight = NewTextBox("50");
    private readonly TextBox output = NewReadOnlyTextBox();
    private readonly TextBox buildLog = NewReadOnlyTextBox();
    private readonly CheckBox manualAcceptance = new()
    {
        Content = new TextBlock
        {
            Text =
                "我已检查地图预览、质量问题与 validation.md，" +
                "接受上述 SHA-256 为基线",
            TextWrapping = TextWrapping.Wrap
        },
        IsEnabled = false,
        Margin = new Thickness(0, 8, 0, 8)
    };
    private readonly Button generateButton = new()
    {
        Content = "生成候选 VWF、预览和报告",
        Padding = new Thickness(14, 7, 14, 7),
        Margin = new Thickness(3)
    };
    private readonly Button acceptButton = new()
    {
        Content = "人工接受哈希并发布",
        Padding = new Thickness(14, 7, 14, 7),
        Margin = new Thickness(3),
        IsEnabled = false
    };
    private readonly TextBlock status = new()
    {
        Text = "尚未生成候选。",
        TextWrapping = TextWrapping.Wrap,
        Foreground = System.Windows.Media.Brushes.DarkSlateGray,
        Margin = new Thickness(0, 6, 0, 6)
    };

    public string? LastPublishedPath { get; private set; }

    public MissionPackageWizard(
        MapDocument currentDocument,
        string? currentVwfSourcePath,
        string? originalAssetRoot)
    {
        sourceDocument = currentDocument;
        assetRoot = originalAssetRoot;
        repositoryRoot =
            MissionPackageDraftService.FindRepositoryRoot(
                AppContext.BaseDirectory);
        Title = "新建可运行关卡包向导";
        Width = 980;
        Height = 820;
        MinWidth = 820;
        MinHeight = 650;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        FontFamily = new System.Windows.Media.FontFamily(
            "Microsoft YaHei UI");
        Background = new System.Windows.Media.SolidColorBrush(
            System.Windows.Media.Color.FromRgb(244, 242, 236));
        Content = BuildContent();

        mode.ItemsSource = new[] { "redeploy", "composite" };
        mode.SelectedIndex = 0;
        engineMission.ItemsSource = Enumerable.Range(1, 12);
        engineMission.SelectedItem = 12;
        sourcePath.Text = ResolveInitialSource(currentVwfSourcePath);
        PopulateScenes(sourceDocument);

        mode.SelectionChanged += (_, _) => UpdateCompositeFields();
        manualAcceptance.Checked += (_, _) =>
            acceptButton.IsEnabled = candidateHash is not null;
        manualAcceptance.Unchecked += (_, _) =>
            acceptButton.IsEnabled = false;
        generateButton.Click += GenerateCandidate_Click;
        acceptButton.Click += AcceptCandidate_Click;
        UpdateCompositeFields();
    }

    private UIElement BuildContent()
    {
        var root = new DockPanel();
        var footer = new DockPanel
        {
            Margin = new Thickness(12, 8, 12, 12)
        };
        DockPanel.SetDock(footer, Dock.Bottom);
        var close = new Button
        {
            Content = "关闭",
            Padding = new Thickness(18, 7, 18, 7),
            Margin = new Thickness(3)
        };
        close.Click += (_, _) => Close();
        footer.Children.Add(close);
        DockPanel.SetDock(close, Dock.Right);
        footer.Children.Add(acceptButton);
        DockPanel.SetDock(acceptButton, Dock.Right);
        footer.Children.Add(generateButton);
        DockPanel.SetDock(generateButton, Dock.Right);
        root.Children.Add(footer);

        var scroll = new ScrollViewer
        {
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled
        };
        var body = new StackPanel
        {
            Margin = new Thickness(18)
        };
        body.Children.Add(new TextBlock
        {
            Text = "可运行关卡包向导",
            FontSize = 24,
            FontWeight = FontWeights.Bold
        });
        body.Children.Add(new TextBlock
        {
            Text =
                "向导只生成新的 mission 目录与候选文件，不覆盖源图。" +
                "候选哈希必须由你明确确认后才会写入清单并发布到 Mod。",
            TextWrapping = TextWrapping.Wrap,
            Foreground = System.Windows.Media.Brushes.DimGray,
            Margin = new Thickness(0, 4, 0, 14)
        });

        var sourceGrid = NewFormGrid();
        AddFormRow(sourceGrid, 0, "源 VWF", SourcePicker());
        AddFormRow(sourceGrid, 1, "构建模式", mode);
        AddFormRow(sourceGrid, 2, "原版任务骨架", engineMission);
        AddFormRow(sourceGrid, 3, "关卡标题", title);
        AddFormRow(sourceGrid, 4, "故事", story);
        body.Children.Add(Group("① 来源与任务骨架", sourceGrid));

        var roleGrid = new Grid();
        roleGrid.ColumnDefinitions.Add(new ColumnDefinition());
        roleGrid.ColumnDefinitions.Add(new ColumnDefinition());
        var leftRoles = new StackPanel
        {
            Margin = new Thickness(0, 0, 8, 0)
        };
        leftRoles.Children.Add(Label("玩家 scene"));
        leftRoles.Children.Add(playerScene);
        leftRoles.Children.Add(Label("接头 scene（可选）"));
        leftRoles.Children.Add(contactScene);
        leftRoles.Children.Add(Label("撤离 scene（可选）"));
        leftRoles.Children.Add(exitScene);
        var rightRoles = new StackPanel
        {
            Margin = new Thickness(8, 0, 0, 0)
        };
        rightRoles.Children.Add(Label(
            "敌军 scene（Ctrl/Shift 多选）"));
        enemyScenes.Height = 130;
        rightRoles.Children.Add(enemyScenes);
        rightRoles.Children.Add(Label(
            "任务目标 scene（Ctrl/Shift 多选）"));
        objectiveScenes.Height = 130;
        rightRoles.Children.Add(objectiveScenes);
        roleGrid.Children.Add(leftRoles);
        Grid.SetColumn(rightRoles, 1);
        roleGrid.Children.Add(rightRoles);
        body.Children.Add(Group("② Scene 角色", roleGrid));

        var thresholds = NewFormGrid();
        AddFormRow(
            thresholds, 0, "出生到敌军最小距离", enemyDistance);
        AddFormRow(
            thresholds, 1, "出生到巡逻最小距离", patrolDistance);
        AddFormRow(
            thresholds, 2, "最小全图可达率", reachableRatio);
        var compositeFields = new StackPanel
        {
            Name = "CompositeFields",
            Orientation = Orientation.Horizontal
        };
        blockWidth.Width = 90;
        blockHeight.Width = 90;
        compositeFields.Children.Add(blockWidth);
        compositeFields.Children.Add(new TextBlock
        {
            Text = " × ",
            VerticalAlignment = VerticalAlignment.Center
        });
        compositeFields.Children.Add(blockHeight);
        AddFormRow(
            thresholds, 3, "composite 区块宽高", compositeFields);
        body.Children.Add(Group("③ 安全与合成阈值", thresholds));

        body.Children.Add(Group(
            "④ 确定性候选与人工验收",
            new StackPanel
            {
                Children =
                {
                    status,
                    new TextBlock
                    {
                        Text =
                            "候选/发布位置与 SHA-256",
                        FontWeight = FontWeights.SemiBold
                    },
                    output,
                    manualAcceptance,
                    new TextBlock
                    {
                        Text = "构建日志",
                        FontWeight = FontWeights.SemiBold
                    },
                    buildLog
                }
            }));
        scroll.Content = body;
        root.Children.Add(scroll);
        return root;
    }

    private UIElement SourcePicker()
    {
        var grid = new Grid();
        grid.ColumnDefinitions.Add(new ColumnDefinition());
        grid.ColumnDefinitions.Add(new ColumnDefinition
        {
            Width = GridLength.Auto
        });
        grid.Children.Add(sourcePath);
        var browse = new Button
        {
            Content = "浏览并解析…",
            Margin = new Thickness(6, 0, 0, 0),
            Padding = new Thickness(10, 4, 10, 4)
        };
        browse.Click += BrowseSource_Click;
        Grid.SetColumn(browse, 1);
        grid.Children.Add(browse);
        return grid;
    }

    private async void GenerateCandidate_Click(
        object sender,
        RoutedEventArgs e)
    {
        if (draft is not null)
        {
            MessageBox.Show(
                this,
                "本向导已经为当前会话分配并生成了关卡目录。" +
                "请完成验收，或关闭后重新打开以创建另一个关卡。",
                "候选已存在",
                MessageBoxButton.OK,
                MessageBoxImage.Information);
            return;
        }
        try
        {
            SetBusy(true, "正在创建关卡清单并运行确定性构建……");
            var options = BuildOptions();
            draft = MissionPackageDraftService.CreateDraft(options);
            Directory.CreateDirectory(draft.CandidateWorkDirectory);

            var log = new StringBuilder();
            if (draft.Mode == MissionPackageMode.Composite)
            {
                var composedPath = Path.Combine(
                    draft.CandidateWorkDirectory,
                    draft.ComposedWorkFile!);
                var compositionReport = Path.Combine(
                    draft.CandidateWorkDirectory,
                    "composition-preflight.md");
                var composerProject = Path.Combine(
                    repositoryRoot,
                    "MapEditor",
                    "tools",
                    "VwfBlueprintComposer",
                    "VwfBlueprintComposer.csproj");
                var composeResult = await RunProcessAsync(
                    "dotnet",
                    [
                        "run",
                        "--project",
                        composerProject,
                        "-c",
                        "Release",
                        "--",
                        draft.SourceVwfPath,
                        composedPath,
                        draft.BlueprintPath!,
                        compositionReport
                    ]);
                log.AppendLine(composeResult.Output);
                if (composeResult.ExitCode != 0)
                {
                    throw new InvalidOperationException(
                        "合成预检失败：\n" + composeResult.Output);
                }
                MissionPackageDraftService.PrepareCompositeMissionHash(
                    draft, composedPath);
                var previewDirectory = Path.Combine(
                    draft.CandidateWorkDirectory, "preview");
                var previewScript = Path.Combine(
                    repositoryRoot,
                    "MapEditor",
                    "tools",
                    "VwfBlueprintComposer",
                    "Compose-PreviewAssets.ps1");
                var previewResult = await RunProcessAsync(
                    ResolvePowerShell(),
                    [
                        "-NoLogo",
                        "-NoProfile",
                        "-ExecutionPolicy",
                        "Bypass",
                        "-File",
                        previewScript,
                        "-SourceTerrain",
                        draft.PreviewSourceTerrainPath!,
                        "-Blueprint",
                        draft.BlueprintPath!,
                        "-OutputDirectory",
                        previewDirectory
                    ]);
                log.AppendLine(previewResult.Output);
                if (previewResult.ExitCode != 0)
                {
                    throw new InvalidOperationException(
                        "合成地图局部预览失败：\n" +
                        previewResult.Output);
                }
            }

            var buildResult = await RunBuildAsync(draft);
            log.AppendLine(buildResult.Output);
            var candidatePath =
                MissionPackageDraftService.CandidateOutputPath(draft);
            if (!File.Exists(candidatePath))
            {
                throw new InvalidOperationException(
                    "构建没有产生候选 VWF：\n" + buildResult.Output);
            }
            candidateHash =
                MissionPackageDraftService.CandidateSha256(draft);
            output.Text =
                $"关卡：{draft.MissionId}（选择器第 {draft.SelectorLevel} 关）\n" +
                $"候选：{candidatePath}\n" +
                $"SHA-256：{candidateHash}\n" +
                $"质量报告：{Path.Combine(draft.CandidateWorkDirectory, "validation.md")}\n" +
                (draft.Mode == MissionPackageMode.Composite
                    ? $"局部预览：{Path.Combine(draft.CandidateWorkDirectory, "preview")}\n"
                    : "局部预览：当前地图编辑器画布\n") +
                $"路由草案：{draft.RouteDraftPath}";
            buildLog.Text = log.ToString().Trim();
            manualAcceptance.IsEnabled = true;
            status.Text =
                "候选已生成，但尚未发布。请在主窗口检查地图/问题面板，" +
                "并阅读 validation.md；确认后勾选下方复选框。";
        }
        catch (Exception exception)
        {
            buildLog.Text = exception.ToString();
            status.Text = "候选生成失败；没有发布 VWF。";
            MessageBox.Show(
                this,
                exception.Message,
                "关卡包候选生成失败",
                MessageBoxButton.OK,
                MessageBoxImage.Error);
        }
        finally
        {
            SetBusy(false);
        }
    }

    private async void AcceptCandidate_Click(
        object sender,
        RoutedEventArgs e)
    {
        if (draft is null ||
            candidateHash is null ||
            manualAcceptance.IsChecked != true)
            return;
        try
        {
            SetBusy(true, "正在写入人工验收凭据并发布……");
            MissionPackageDraftService.AcceptCandidateHash(
                draft, candidateHash);
            var result = await RunBuildAsync(draft);
            buildLog.Text = result.Output;
            if (result.ExitCode != 0)
            {
                throw new InvalidOperationException(
                    "最终发布构建失败：\n" + result.Output);
            }
            LastPublishedPath = Path.Combine(
                repositoryRoot,
                "Mod",
                $"1937{draft.MissionId}.vwf");
            status.Text =
                $"已发布 {LastPublishedPath}；" +
                "路由仍保持 draft，需代码评审后合并 SDK/mission-routes.json。";
            acceptButton.IsEnabled = false;
            generateButton.IsEnabled = false;
            manualAcceptance.IsEnabled = false;
            MessageBox.Show(
                this,
                $"关卡包已确定性发布。\n\n{LastPublishedPath}\n\n" +
                $"SHA-256：{candidateHash}",
                "发布完成",
                MessageBoxButton.OK,
                MessageBoxImage.Information);
        }
        catch (Exception exception)
        {
            status.Text =
                "验收信息已保留，但发布未完成；可从关卡目录重新运行 Build-Mission.ps1。";
            MessageBox.Show(
                this,
                exception.Message,
                "关卡包发布失败",
                MessageBoxButton.OK,
                MessageBoxImage.Error);
        }
        finally
        {
            SetBusy(false);
        }
    }

    private void BrowseSource_Click(
        object sender,
        RoutedEventArgs e)
    {
        var dialog = new OpenFileDialog
        {
            Filter = "原版关卡 (*.vwf)|*.vwf",
            InitialDirectory = Path.Combine(repositoryRoot, "Mod"),
            CheckFileExists = true
        };
        if (dialog.ShowDialog(this) != true)
            return;
        try
        {
            var fullPath = Path.GetFullPath(dialog.FileName);
            sourceDocument = OriginalVwfImporter.Import(
                fullPath, assetRoot);
            sourcePath.Text = fullPath;
            PopulateScenes(sourceDocument);
            status.Text =
                $"已解析 {sourceDocument.Width}×{sourceDocument.Height}，" +
                $"{sourceDocument.Objects.Count:N0} 个 scene。";
        }
        catch (Exception exception)
        {
            MessageBox.Show(
                this,
                exception.Message,
                "解析源图失败",
                MessageBoxButton.OK,
                MessageBoxImage.Error);
        }
    }

    private MissionPackageDraftOptions BuildOptions()
    {
        if (playerScene.SelectedItem is not SceneChoice player)
            throw new InvalidOperationException("请选择玩家 scene。");
        var selectedMode =
            mode.SelectedItem?.ToString() == "composite"
                ? MissionPackageMode.Composite
                : MissionPackageMode.Redeploy;
        return new MissionPackageDraftOptions
        {
            RepositoryRoot = repositoryRoot,
            SourceVwfPath = Path.GetFullPath(sourcePath.Text.Trim()),
            Title = title.Text,
            Story = story.Text,
            Mode = selectedMode,
            EngineMission =
                (int)(engineMission.SelectedItem ?? 12),
            PlayerSceneIndices = [player.SceneIndex],
            EnemySceneIndices = enemyScenes.SelectedItems
                .Cast<SceneChoice>()
                .Select(item => item.SceneIndex)
                .ToArray(),
            ObjectiveSceneIndices = objectiveScenes.SelectedItems
                .Cast<SceneChoice>()
                .Select(item => item.SceneIndex)
                .ToArray(),
            ContactSceneIndex =
                (contactScene.SelectedItem as SceneChoice)?.SceneIndex,
            ExitSceneIndex =
                (exitScene.SelectedItem as SceneChoice)?.SceneIndex,
            MinimumSpawnEnemyDistanceWorld =
                ParseInt(enemyDistance, "出生到敌军最小距离", 0, 100_000),
            MinimumSpawnPatrolDistanceWorld =
                ParseInt(patrolDistance, "出生到巡逻最小距离", 0, 100_000),
            MinimumReachableWalkableRatio =
                ParseDouble(reachableRatio, "最小全图可达率", 0, 1),
            CompositeBlockWidth =
                ParseInt(blockWidth, "合成块宽", 1, 2_048),
            CompositeBlockHeight =
                ParseInt(blockHeight, "合成块高", 1, 2_048),
            BackgroundAsset = sourceDocument.BackgroundAsset
        };
    }

    private void PopulateScenes(MapDocument document)
    {
        var choices = document.Objects
            .Select(item => new SceneChoice(
                ParseSceneIndex(item.Id),
                item.Name,
                item.Faction,
                item.X,
                item.Y,
                item.IsLiving))
            .OrderBy(item => item.SceneIndex)
            .ToArray();
        var living = choices.Where(item => item.IsLiving).ToArray();
        var available = living.Length > 0 ? living : choices;
        playerScene.ItemsSource = available;
        contactScene.ItemsSource =
            new SceneChoice?[] { null }.Concat(choices).ToArray();
        exitScene.ItemsSource =
            new SceneChoice?[] { null }.Concat(choices).ToArray();
        enemyScenes.ItemsSource = available;
        objectiveScenes.ItemsSource = choices;

        playerScene.SelectedItem = available.FirstOrDefault(item =>
            IsPlayerFaction(item.Faction)) ??
            available.FirstOrDefault();
        contactScene.SelectedIndex = 0;
        exitScene.SelectedIndex = 0;
        enemyScenes.UnselectAll();
        foreach (var enemy in available.Where(item =>
                     IsEnemyFaction(item.Faction)))
            enemyScenes.SelectedItems.Add(enemy);
    }

    private async Task<ProcessResult> RunBuildAsync(
        MissionPackageDraftResult value)
    {
        var script = Path.Combine(
            repositoryRoot,
            "MapEditor",
            "tools",
            "Build-MissionPackage.ps1");
        return await RunProcessAsync(
            ResolvePowerShell(),
            [
                "-NoLogo",
                "-NoProfile",
                "-ExecutionPolicy",
                "Bypass",
                "-File",
                script,
                "-MissionId",
                value.MissionId,
                "-RepositoryRoot",
                repositoryRoot,
                "-WorkDirectory",
                value.CandidateWorkDirectory
            ]);
    }

    private static async Task<ProcessResult> RunProcessAsync(
        string fileName,
        IReadOnlyList<string> arguments)
    {
        var startInfo = new ProcessStartInfo(fileName)
        {
            UseShellExecute = false,
            CreateNoWindow = true,
            WindowStyle = ProcessWindowStyle.Hidden,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            StandardOutputEncoding = Encoding.UTF8,
            StandardErrorEncoding = Encoding.UTF8
        };
        foreach (var argument in arguments)
            startInfo.ArgumentList.Add(argument);
        using var process = Process.Start(startInfo)
            ?? throw new InvalidOperationException(
                $"无法启动 {fileName}。");
        var standardOutput = process.StandardOutput.ReadToEndAsync();
        var standardError = process.StandardError.ReadToEndAsync();
        await process.WaitForExitAsync();
        return new ProcessResult(
            process.ExitCode,
            (await standardOutput) +
            Environment.NewLine +
            (await standardError));
    }

    private static string ResolvePowerShell()
    {
        var programFiles = Environment.GetFolderPath(
            Environment.SpecialFolder.ProgramFiles);
        var pwshRoot = Path.Combine(programFiles, "PowerShell");
        if (Directory.Exists(pwshRoot))
        {
            var candidate = Directory.EnumerateFiles(
                    pwshRoot,
                    "pwsh.exe",
                    SearchOption.AllDirectories)
                .OrderByDescending(path => path)
                .FirstOrDefault();
            if (candidate is not null)
                return candidate;
        }
        return "powershell.exe";
    }

    private void SetBusy(bool busy, string? message = null)
    {
        generateButton.IsEnabled = !busy && draft is null;
        acceptButton.IsEnabled =
            !busy &&
            candidateHash is not null &&
            manualAcceptance.IsChecked == true;
        if (message is not null)
            status.Text = message;
    }

    private void UpdateCompositeFields()
    {
        blockWidth.IsEnabled =
            mode.SelectedItem?.ToString() == "composite";
        blockHeight.IsEnabled = blockWidth.IsEnabled;
    }

    private string ResolveInitialSource(string? explicitPath)
    {
        if (!string.IsNullOrWhiteSpace(explicitPath) &&
            File.Exists(explicitPath))
            return Path.GetFullPath(explicitPath);
        if (!string.IsNullOrWhiteSpace(sourceDocument.ImportedFrom))
        {
            var candidate = Path.Combine(
                repositoryRoot,
                "Mod",
                sourceDocument.ImportedFrom);
            if (File.Exists(candidate))
                return candidate;
        }
        return Path.Combine(repositoryRoot, "Mod", "1937m011.vwf");
    }

    private static int ParseSceneIndex(string id)
    {
        if (id.StartsWith("scene-", StringComparison.Ordinal) &&
            int.TryParse(id.AsSpan(6), out var value))
            return value;
        throw new InvalidDataException($"对象 ID 不是 scene-N：{id}");
    }

    private static bool IsPlayerFaction(string value) =>
        value.Equals("player", StringComparison.OrdinalIgnoreCase) ||
        value.Equals("faction-3", StringComparison.OrdinalIgnoreCase);

    private static bool IsEnemyFaction(string value) =>
        value.Equals("enemy", StringComparison.OrdinalIgnoreCase) ||
        value.Equals("faction-1", StringComparison.OrdinalIgnoreCase);

    private static int ParseInt(
        TextBox field,
        string name,
        int minimum,
        int maximum)
    {
        if (!int.TryParse(field.Text, out var value) ||
            value < minimum ||
            value > maximum)
        {
            throw new InvalidDataException(
                $"{name}必须为 {minimum}..{maximum} 的整数。");
        }
        return value;
    }

    private static double ParseDouble(
        TextBox field,
        string name,
        double minimum,
        double maximum)
    {
        if (!double.TryParse(field.Text, out var value) ||
            value < minimum ||
            value > maximum)
        {
            throw new InvalidDataException(
                $"{name}必须为 {minimum}..{maximum} 的数值。");
        }
        return value;
    }

    private static GroupBox Group(
        string header,
        UIElement content) =>
        new()
        {
            Header = header,
            Content = content,
            Padding = new Thickness(12),
            Margin = new Thickness(0, 0, 0, 12),
            Foreground = System.Windows.Media.Brushes.Black
        };

    private static Grid NewFormGrid()
    {
        var grid = new Grid();
        grid.ColumnDefinitions.Add(new ColumnDefinition
        {
            Width = new GridLength(165)
        });
        grid.ColumnDefinitions.Add(new ColumnDefinition());
        return grid;
    }

    private static void AddFormRow(
        Grid grid,
        int row,
        string label,
        UIElement field)
    {
        grid.RowDefinitions.Add(new RowDefinition
        {
            Height = GridLength.Auto
        });
        var text = Label(label);
        Grid.SetRow(text, row);
        grid.Children.Add(text);
        Grid.SetRow(field, row);
        Grid.SetColumn(field, 1);
        grid.Children.Add(field);
    }

    private static TextBlock Label(string value) =>
        new()
        {
            Text = value,
            VerticalAlignment = VerticalAlignment.Center,
            Margin = new Thickness(0, 5, 8, 5),
            FontWeight = FontWeights.SemiBold
        };

    private static TextBox NewTextBox(string value = "") =>
        new()
        {
            Text = value,
            Margin = new Thickness(0, 3, 0, 3),
            Padding = new Thickness(6, 4, 6, 4),
            Foreground = System.Windows.Media.Brushes.Black,
            Background = System.Windows.Media.Brushes.White,
            TextWrapping = TextWrapping.Wrap
        };

    private static TextBox NewReadOnlyTextBox() =>
        new()
        {
            IsReadOnly = true,
            MinHeight = 72,
            MaxHeight = 180,
            Margin = new Thickness(0, 4, 0, 8),
            Padding = new Thickness(7),
            TextWrapping = TextWrapping.Wrap,
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            Foreground = System.Windows.Media.Brushes.Black,
            Background = new System.Windows.Media.SolidColorBrush(
                System.Windows.Media.Color.FromRgb(250, 249, 245))
        };

    private static ComboBox NewComboBox() =>
        new()
        {
            Margin = new Thickness(0, 3, 0, 3),
            Padding = new Thickness(5, 3, 5, 3),
            Foreground = System.Windows.Media.Brushes.Black,
            Background = System.Windows.Media.Brushes.White
        };

    private static ListBox NewSceneList() =>
        new()
        {
            SelectionMode = SelectionMode.Extended,
            Margin = new Thickness(0, 3, 0, 6),
            Foreground = System.Windows.Media.Brushes.Black,
            Background = System.Windows.Media.Brushes.White
        };

    private sealed record SceneChoice(
        int SceneIndex,
        string Name,
        string Faction,
        int X,
        int Y,
        bool IsLiving)
    {
        public override string ToString() =>
            $"{SceneIndex}: {Name} [{Faction}] ({X},{Y})";
    }

    private sealed record ProcessResult(
        int ExitCode,
        string Output);
}
