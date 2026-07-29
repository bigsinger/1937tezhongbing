param(
    [ValidateRange(0, 12)]
    [int]$Level = 0,
    [switch]$StartImmediately,
    [switch]$SafeWindow,
    [AllowEmptyString()]
    [string]$ValidateAliases,
    [string]$RenderPreviewPath = ''
)

$ErrorActionPreference = 'Stop'
$gameDirectory = [IO.Path]::GetFullPath($PSScriptRoot)
$gameExecutable = Join-Path $gameDirectory 'M1937.exe'
$runGameIni = Join-Path $gameDirectory 'rungame.ini'
$ddrawIni = Join-Path $gameDirectory 'ddraw.ini'
$catalogPath = Join-Path $gameDirectory '关卡名称.json'

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;

public static class M1937Ini {
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    public static extern int GetPrivateProfileString(
        string section, string key, string defaultValue,
        StringBuilder result, int size, string fileName);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    public static extern bool WritePrivateProfileString(
        string section, string key, string value, string fileName);

    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")]
    public static extern IntPtr GetWindowLongPtr(
        IntPtr window, int index);

    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW")]
    public static extern IntPtr SetWindowLongPtr(
        IntPtr window, int index, IntPtr value);

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(
        IntPtr window, int command);
}
'@

function Get-IniValue {
    param(
        [string]$Path,
        [string]$Section,
        [string]$Key,
        [string]$Default
    )
    $builder = New-Object Text.StringBuilder 1024
    [void][M1937Ini]::GetPrivateProfileString(
        $Section, $Key, $Default, $builder, $builder.Capacity, $Path)
    return $builder.ToString()
}

function Set-IniValue {
    param(
        [string]$Path,
        [string]$Section,
        [string]$Key,
        [string]$Value
    )
    if (-not [M1937Ini]::WritePrivateProfileString(
        $Section, $Key, $Value, $Path)) {
        throw "无法写入配置：$Path [$Section] $Key"
    }
}

function Get-IniInt {
    param(
        [string]$Path,
        [string]$Section,
        [string]$Key,
        [int]$Default
    )
    $parsed = 0
    $value = Get-IniValue $Path $Section $Key ([string]$Default)
    if ([int]::TryParse($value, [ref]$parsed)) {
        return $parsed
    }
    return $Default
}

function Set-DdrawProfile {
    param([int]$DisplayMode, [string]$Renderer)

    if (-not (Test-Path -LiteralPath $ddrawIni -PathType Leaf)) {
        return
    }
    Set-IniValue $ddrawIni 'ddraw' 'renderer' $Renderer
    Set-IniValue $ddrawIni 'ddraw' 'maxfps' '60'
    Set-IniValue $ddrawIni 'ddraw' 'vsync' 'true'
    Set-IniValue $ddrawIni 'ddraw' 'maxgameticks' '60'
    Set-IniValue $ddrawIni 'ddraw' 'limiter_type' '2'
    Set-IniValue $ddrawIni 'ddraw' 'boxing' 'false'
    # The proxy maps the free Windows cursor to the original 1024x768
    # DirectInput coordinates. Do not install a second cnc-ddraw mouse hook.
    Set-IniValue $ddrawIni 'ddraw' 'adjmouse' 'false'
    Set-IniValue $ddrawIni 'ddraw' 'no_dinput_hook' 'true'
    # Never confine or recenter the user's system cursor.
    Set-IniValue $ddrawIni 'ddraw' 'devmode' 'true'
    Set-IniValue $runGameIni 'mod' 'SystemCursorMapping' '1'
    Set-IniValue $runGameIni 'mod' 'TextBriefings' '1'
    Set-IniValue $ddrawIni 'ddraw' 'resizable' 'true'
    Set-IniValue $ddrawIni 'ddraw' 'savesettings' '1'
    Set-IniValue $ddrawIni 'ddraw' 'border' 'true'
    Set-IniValue $ddrawIni 'ddraw' 'hook_peekmessage' 'false'
    Set-IniValue $ddrawIni 'ddraw' 'center_cursor_fix' 'false'
    Set-IniValue $ddrawIni 'ddraw' 'lock_mouse_top_left' 'false'
    switch ($DisplayMode) {
        0 {
            Set-IniValue $ddrawIni 'ddraw' 'fullscreen' 'false'
            Set-IniValue $ddrawIni 'ddraw' 'windowed' 'true'
            Set-IniValue $ddrawIni 'ddraw' 'width' '1024'
            Set-IniValue $ddrawIni 'ddraw' 'height' '768'
            Set-IniValue $ddrawIni 'ddraw' 'maintas' 'true'
            # This fixed 1:1 window needs neither sensitivity scaling nor
            # cnc-ddraw cursor confinement. Confinement can pin the legacy
            # DirectInput cursor to the lower-right corner on modern Windows.
            Set-IniValue $ddrawIni 'ddraw' 'adjmouse' 'false'
            Set-IniValue $ddrawIni 'ddraw' 'devmode' 'true'
            Set-IniValue $ddrawIni 'ddraw' 'resizable' 'false'
            Set-IniValue $ddrawIni 'ddraw' 'savesettings' '0'
            Set-IniValue $ddrawIni 'ddraw' 'posX' '-32000'
            Set-IniValue $ddrawIni 'ddraw' 'posY' '-32000'
        }
        1 {
            Set-IniValue $ddrawIni 'ddraw' 'fullscreen' 'true'
            Set-IniValue $ddrawIni 'ddraw' 'windowed' 'true'
            Set-IniValue $ddrawIni 'ddraw' 'width' '0'
            Set-IniValue $ddrawIni 'ddraw' 'height' '0'
            Set-IniValue $ddrawIni 'ddraw' 'maintas' 'true'
            Set-IniValue $ddrawIni 'ddraw' 'adjmouse' 'false'
            Set-IniValue $ddrawIni 'ddraw' 'no_dinput_hook' 'true'
            Set-IniValue $ddrawIni 'ddraw' 'devmode' 'true'
            Set-IniValue $ddrawIni 'ddraw' 'resizable' 'false'
            Set-IniValue $ddrawIni 'ddraw' 'savesettings' '0'
            Set-IniValue $ddrawIni 'ddraw' 'posX' '-32000'
            Set-IniValue $ddrawIni 'ddraw' 'posY' '-32000'
        }
        2 {
            Set-IniValue $ddrawIni 'ddraw' 'fullscreen' 'true'
            Set-IniValue $ddrawIni 'ddraw' 'windowed' 'false'
            Set-IniValue $ddrawIni 'ddraw' 'width' '0'
            Set-IniValue $ddrawIni 'ddraw' 'height' '0'
            Set-IniValue $ddrawIni 'ddraw' 'maintas' 'true'
        }
        default {
            Set-IniValue $ddrawIni 'ddraw' 'fullscreen' 'true'
            Set-IniValue $ddrawIni 'ddraw' 'windowed' 'false'
            Set-IniValue $ddrawIni 'ddraw' 'width' '0'
            Set-IniValue $ddrawIni 'ddraw' 'height' '0'
            Set-IniValue $ddrawIni 'ddraw' 'maintas' 'false'
        }
    }
}

function Start-M1937Process {
    param(
        [int]$MissionNumber,
        [bool]$AutomaticStart,
        [bool]$ExpandedViewport,
        [int]$ViewportWidth,
        [int]$ViewportHeight
    )

    $route = @()
    if ($MissionNumber -gt 0) {
        $route = @($catalog.missions | Where-Object {
            [int]$_.number -eq $MissionNumber
        })
        if ($route.Count -ne 1) {
            throw "关卡路由表中没有唯一的第 $MissionNumber 关。"
        }
        if ([bool]$route[0].requires_file) {
            $requiredVwf = Join-Path $gameDirectory ([string]$route[0].vwf_name)
            if (-not (Test-Path -LiteralPath $requiredVwf -PathType Leaf)) {
                throw "第 $MissionNumber 关需要当前目录中的 $(
                    [string]$route[0].vwf_name)。"
            }
        }
    }
    $startInfo = New-Object Diagnostics.ProcessStartInfo
    $startInfo.FileName = $gameExecutable
    $startInfo.WorkingDirectory = $gameDirectory
    $startInfo.UseShellExecute = $false
    $startInfo.EnvironmentVariables['M1937_START_LEVEL'] = [string]$MissionNumber
    $startInfo.EnvironmentVariables['M1937_AUTO_START'] =
        $(if ($AutomaticStart) { '1' } else { '0' })
    $startInfo.EnvironmentVariables['M1937_EXPANDED_VIEWPORT'] =
        $(if ($ExpandedViewport) { '1' } else { '0' })
    $startInfo.EnvironmentVariables['M1937_VIEWPORT_WIDTH'] =
        [string]$ViewportWidth
    $startInfo.EnvironmentVariables['M1937_VIEWPORT_HEIGHT'] =
        [string]$ViewportHeight
    $replaceLegacyBriefing =
        @($catalog.missions).Count -gt 0 -and
        @($catalog.missions | Where-Object {
            -not (
                $_.PSObject.Properties.Name -contains
                    'replace_legacy_briefing') -or
            -not [bool]$_.replace_legacy_briefing
        }).Count -eq 0
    $startInfo.EnvironmentVariables['M1937_REPLACE_LEGACY_BRIEFING'] =
        $(if ($replaceLegacyBriefing) { '1' } else { '0' })
    $gameProcess = [Diagnostics.Process]::Start($startInfo)
    if ($null -eq $gameProcess) {
        throw 'M1937.exe 未能创建进程。'
    }

    $sidecarEnabled =
        (Get-IniInt $runGameIni 'mod' 'MissionSidecar' 0) -ne 0
    if ($MissionNumber -gt 0 -and $sidecarEnabled) {
        $missionId = [string]$route[0].id
        $definition = Join-Path $gameDirectory (
            "Missions\$missionId.m1937mission.json")
        $host = Join-Path $gameDirectory (
            'Tools\MissionSidecar\MissionSidecar.Host.exe')
        if ((Test-Path -LiteralPath $definition -PathType Leaf) -and
            (Test-Path -LiteralPath $host -PathType Leaf)) {
            $hostInfo = New-Object Diagnostics.ProcessStartInfo
            $hostInfo.FileName = $host
            $hostInfo.WorkingDirectory = $gameDirectory
            $hostInfo.UseShellExecute = $false
            $hostInfo.CreateNoWindow = $true
            $hostInfo.Arguments = (
                '--pid {0} --sidecar "{1}"{2}' -f @(
                    $gameProcess.Id,
                    $definition,
                    $(if ((Get-IniInt $runGameIni 'mod' 'EnablePlugins' 0) -ne 0) {
                        ' --plugins'
                    } else {
                        ''
                    })
                ))
            [Diagnostics.Process]::Start($hostInfo) | Out-Null
        }
    }
    return $gameProcess
}

if (-not (Test-Path -LiteralPath $gameExecutable -PathType Leaf)) {
    [Windows.Forms.MessageBox]::Show(
        "没有在当前目录找到 M1937.exe：`r`n$gameDirectory",
        '《1937特种兵》现代启动中心',
        [Windows.Forms.MessageBoxButtons]::OK,
        [Windows.Forms.MessageBoxIcon]::Error
    ) | Out-Null
    exit 2
}

$catalog = Get-Content -LiteralPath $catalogPath -Raw -Encoding UTF8 |
    ConvertFrom-Json

if ($SafeWindow) {
    $safeRenderer =
        Get-IniValue $runGameIni 'mod' 'Renderer' 'direct3d9'
    if ($safeRenderer -notin @('direct3d9', 'direct3d9on12', 'opengl')) {
        $safeRenderer = 'direct3d9'
    }
    # Reset to the profile validated in both the original menu and mission:
    # a centred 1024x768 window with no cursor confinement or ddraw input hook.
    Set-DdrawProfile 0 $safeRenderer
    Set-IniValue $runGameIni 'mod' 'DisplayMode' '0'
}

if ($StartImmediately) {
    if ($Level -lt 1 -or $Level -gt 12) {
        throw 'StartImmediately requires Level in the range 1..12.'
    }
    $screen = [Windows.Forms.Screen]::PrimaryScreen.Bounds
    $startExpanded =
        (Get-IniInt $runGameIni 'mod' 'ExpandedViewport' 0) -ne 0
    $startWidth = Get-IniInt $runGameIni 'mod' 'ViewportWidth' $screen.Width
    $startHeight = Get-IniInt $runGameIni 'mod' 'ViewportHeight' $screen.Height
    if ($startWidth -le 0) { $startWidth = $screen.Width }
    if ($startHeight -le 0) { $startHeight = $screen.Height }
    # Compatibility note: the old switch is retained for existing shortcuts,
    # but the mission now starts through the original menu and input loop. The
    # game process displays its text briefing after New Game is activated.
    Start-M1937Process $Level $false $startExpanded $startWidth $startHeight
    exit 0
}

[Windows.Forms.Application]::EnableVisualStyles()

$background = [Drawing.Color]::FromArgb(22, 27, 34)
$panelColor = [Drawing.Color]::FromArgb(31, 38, 48)
$panelAlt = [Drawing.Color]::FromArgb(39, 48, 60)
$accent = [Drawing.Color]::FromArgb(190, 48, 44)
$accentHover = [Drawing.Color]::FromArgb(220, 67, 59)
$textPrimary = [Drawing.Color]::FromArgb(240, 238, 230)
$textMuted = [Drawing.Color]::FromArgb(177, 186, 196)

function Set-FlatButtonStyle {
    param([Windows.Forms.Button]$Button, [bool]$Primary)
    $Button.FlatStyle = [Windows.Forms.FlatStyle]::Flat
    $Button.FlatAppearance.BorderSize = 0
    $Button.Cursor = [Windows.Forms.Cursors]::Hand
    if ($Primary) {
        $Button.BackColor = $accent
        $Button.ForeColor = [Drawing.Color]::White
        $Button.Add_MouseEnter({ $this.BackColor = $accentHover })
        $Button.Add_MouseLeave({ $this.BackColor = $accent })
    }
    else {
        $Button.BackColor = $panelAlt
        $Button.ForeColor = $textPrimary
    }
}

function Get-ValidatedPreviewPath {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Description
    )

    $fullPath = [IO.Path]::GetFullPath($Path)
    $allowedRoots = @(
        [IO.Path]::GetFullPath('E:\1937\'),
        [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    )
    $isAllowed = $false
    foreach ($root in $allowedRoots) {
        $rootPrefix = $root.TrimEnd(
            [IO.Path]::DirectorySeparatorChar,
            [IO.Path]::AltDirectorySeparatorChar) +
            [IO.Path]::DirectorySeparatorChar
        if (($fullPath.TrimEnd(
                    [IO.Path]::DirectorySeparatorChar,
                    [IO.Path]::AltDirectorySeparatorChar) +
                [IO.Path]::DirectorySeparatorChar).StartsWith(
                $rootPrefix,
                [StringComparison]::OrdinalIgnoreCase)) {
            $isAllowed = $true
            break
        }
    }
    if (-not $isAllowed) {
        throw "$Description must stay under E:\1937 or the system temporary directory."
    }
    return $fullPath
}

function Test-KeyName {
    param([string]$Name)
    $key = $Name.Trim().ToUpperInvariant()
    $numeric = 0
    if ([int]::TryParse($key, [ref]$numeric)) {
        return $numeric -ge 1 -and $numeric -le 255
    }
    $names = @(
        'ESC', 'ESCAPE', 'TAB', 'ENTER', 'SPACE', 'BACKSPACE',
        'F1', 'F2', 'F3', 'F4', 'F5', 'F6',
        'F7', 'F8', 'F9', 'F10', 'F11', 'F12',
        'UP', 'DOWN', 'LEFT', 'RIGHT', 'HOME', 'END',
        'PGUP', 'PGDN', 'INSERT', 'DELETE',
        'CTRL', 'SHIFT', 'ALT',
        'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J',
        'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T',
        'U', 'V', 'W', 'X', 'Y', 'Z',
        '0', '1', '2', '3', '4', '5', '6', '7', '8', '9')
    return $key -in $names
}

function Get-ValidatedKeyAliases {
    param([string]$Text)
    $result = [Collections.Generic.List[string]]::new()
    $sources = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::OrdinalIgnoreCase)
    $targets = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::OrdinalIgnoreCase)
    foreach ($rawLine in ($Text -split '\r?\n')) {
        $line = $rawLine.Trim()
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $parts = @($line -split ',')
        if ($parts.Count -ne 2) {
            throw "按键映射 [$line] 必须使用 来源键,目标键 格式。"
        }
        $source = $parts[0].Trim().ToUpperInvariant()
        $target = $parts[1].Trim().ToUpperInvariant()
        if (-not (Test-KeyName $source) -or
            -not (Test-KeyName $target)) {
            throw "按键映射 [$line] 含有不支持的键名。"
        }
        if ($source -eq $target) {
            throw "按键映射 [$line] 来源和目标不能相同。"
        }
        if (-not $sources.Add($source)) {
            throw "来源键 $source 被重复映射。"
        }
        if (-not $targets.Add($target)) {
            throw "目标键 $target 存在冲突。"
        }
        $result.Add("$source,$target")
        if ($result.Count -gt 16) {
            throw '按键映射最多允许 16 条。'
        }
    }
    return @($result)
}

function Show-AdvancedSettingsDialog {
    $dialog = New-Object Windows.Forms.Form
    $dialog.Text = '高级增强设置'
    $dialog.StartPosition = 'CenterParent'
    $dialog.ClientSize = New-Object Drawing.Size(600, 560)
    $dialog.MinimumSize = New-Object Drawing.Size(600, 560)
    $dialog.BackColor = $background
    $dialog.ForeColor = $textPrimary
    $dialog.Font = New-Object Drawing.Font('Microsoft YaHei UI', 9)
    $dialog.FormBorderStyle =
        [Windows.Forms.FormBorderStyle]::FixedDialog
    $dialog.MaximizeBox = $false
    $dialog.MinimizeBox = $false

    $heading = New-Object Windows.Forms.Label
    $heading.Text = '诊断、任务与按键'
    $heading.Location = New-Object Drawing.Point(24, 20)
    $heading.AutoSize = $true
    $heading.Font = New-Object Drawing.Font(
        'Microsoft YaHei UI', 14, [Drawing.FontStyle]::Bold)
    $dialog.Controls.Add($heading)

    $diagnosticsCheck = New-Object Windows.Forms.CheckBox
    $diagnosticsCheck.Text = '记录兼容性诊断（不含截图和个人信息）'
    $diagnosticsCheck.Location = New-Object Drawing.Point(28, 70)
    $diagnosticsCheck.AutoSize = $true
    $diagnosticsCheck.Checked =
        (Get-IniInt $runGameIni 'mod' 'Diagnostics' 1) -ne 0
    $dialog.Controls.Add($diagnosticsCheck)

    $telemetryCheck = New-Object Windows.Forms.CheckBox
    $telemetryCheck.Text = '记录本地性能遥测（帧、输入、消息泵、AI）'
    $telemetryCheck.Location = New-Object Drawing.Point(28, 103)
    $telemetryCheck.AutoSize = $true
    $telemetryCheck.Checked =
        (Get-IniInt $runGameIni 'mod' 'Telemetry' 0) -ne 0
    $dialog.Controls.Add($telemetryCheck)

    $sidecarCheck = New-Object Windows.Forms.CheckBox
    $sidecarCheck.Text = '为扩展关启用任务 sidecar 目标面板（实验）'
    $sidecarCheck.Location = New-Object Drawing.Point(28, 136)
    $sidecarCheck.AutoSize = $true
    $sidecarCheck.Checked =
        (Get-IniInt $runGameIni 'mod' 'MissionSidecar' 0) -ne 0
    $dialog.Controls.Add($sidecarCheck)

    $pluginsCheck = New-Object Windows.Forms.CheckBox
    $pluginsCheck.Text = '加载通过 ABI 版本协商的本地任务插件'
    $pluginsCheck.Location = New-Object Drawing.Point(52, 169)
    $pluginsCheck.AutoSize = $true
    $pluginsCheck.Checked =
        (Get-IniInt $runGameIni 'mod' 'EnablePlugins' 0) -ne 0
    $pluginsCheck.Enabled = $sidecarCheck.Checked
    $sidecarCheck.Add_CheckedChanged({
        $pluginsCheck.Enabled = $sidecarCheck.Checked
        if (-not $sidecarCheck.Checked) {
            $pluginsCheck.Checked = $false
        }
    })
    $dialog.Controls.Add($pluginsCheck)

    $keyMapCheck = New-Object Windows.Forms.CheckBox
    $keyMapCheck.Text = '启用按键别名映射（原按键仍保留，不吞 F1/M）'
    $keyMapCheck.Location = New-Object Drawing.Point(28, 216)
    $keyMapCheck.AutoSize = $true
    $keyMapCheck.Checked =
        (Get-IniInt $runGameIni 'mod' 'KeyRemapping' 0) -ne 0
    $dialog.Controls.Add($keyMapCheck)

    $aliasLabel = New-Object Windows.Forms.Label
    $aliasLabel.Text = (
        '每行一条“来源键,目标键”，例如 F2,M；最多 16 条，' +
        '保存时检查重复和冲突。')
    $aliasLabel.Location = New-Object Drawing.Point(28, 248)
    $aliasLabel.Size = New-Object Drawing.Size(540, 38)
    $aliasLabel.ForeColor = $textMuted
    $dialog.Controls.Add($aliasLabel)

    $aliasText = New-Object Windows.Forms.TextBox
    $aliasText.Location = New-Object Drawing.Point(28, 290)
    $aliasText.Size = New-Object Drawing.Size(540, 150)
    $aliasText.Multiline = $true
    $aliasText.ScrollBars = [Windows.Forms.ScrollBars]::Vertical
    $aliasText.BackColor = $panelAlt
    $aliasText.ForeColor = $textPrimary
    $existingAliases = [Collections.Generic.List[string]]::new()
    foreach ($index in 1..16) {
        $value = Get-IniValue $runGameIni 'keymap' "Alias$index" ''
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            $existingAliases.Add($value)
        }
    }
    $aliasText.Text = [string]::Join(
        [Environment]::NewLine, $existingAliases)
    $dialog.Controls.Add($aliasText)

    $logButton = New-Object Windows.Forms.Button
    $logButton.Text = '查看本地诊断'
    $logButton.Location = New-Object Drawing.Point(28, 478)
    $logButton.Size = New-Object Drawing.Size(128, 38)
    Set-FlatButtonStyle $logButton $false
    $logButton.Add_Click({
        $log = Join-Path $gameDirectory 'M1937Mod.log'
        if (Test-Path -LiteralPath $log -PathType Leaf) {
            Start-Process notepad.exe -ArgumentList "`"$log`""
        }
        else {
            [Windows.Forms.MessageBox]::Show(
                '尚未生成诊断日志。启用诊断并运行一次游戏后再查看。',
                '本地诊断') | Out-Null
        }
    })
    $dialog.Controls.Add($logButton)

    $cancel = New-Object Windows.Forms.Button
    $cancel.Text = '取消'
    $cancel.Location = New-Object Drawing.Point(360, 478)
    $cancel.Size = New-Object Drawing.Size(96, 38)
    Set-FlatButtonStyle $cancel $false
    $cancel.DialogResult = [Windows.Forms.DialogResult]::Cancel
    $dialog.Controls.Add($cancel)

    $accept = New-Object Windows.Forms.Button
    $accept.Text = '保存'
    $accept.Location = New-Object Drawing.Point(472, 478)
    $accept.Size = New-Object Drawing.Size(96, 38)
    Set-FlatButtonStyle $accept $true
    $accept.Add_Click({
        try {
            $aliases = @()
            if ($keyMapCheck.Checked) {
                $aliases = @(Get-ValidatedKeyAliases $aliasText.Text)
            }
            Set-IniValue $runGameIni 'mod' 'Diagnostics' $(
                if ($diagnosticsCheck.Checked) { '1' } else { '0' })
            Set-IniValue $runGameIni 'mod' 'Telemetry' $(
                if ($telemetryCheck.Checked) { '1' } else { '0' })
            Set-IniValue $runGameIni 'mod' 'TelemetryIntervalMs' '1000'
            Set-IniValue $runGameIni 'mod' 'MissionSidecar' $(
                if ($sidecarCheck.Checked) { '1' } else { '0' })
            Set-IniValue $runGameIni 'mod' 'EnablePlugins' $(
                if ($pluginsCheck.Checked) { '1' } else { '0' })
            Set-IniValue $runGameIni 'mod' 'KeyRemapping' $(
                if ($keyMapCheck.Checked) { '1' } else { '0' })
            foreach ($index in 1..16) {
                $value = if ($index -le $aliases.Count) {
                    [string]$aliases[$index - 1]
                } else {
                    ''
                }
                Set-IniValue $runGameIni 'keymap' "Alias$index" $value
            }
            $dialog.DialogResult = [Windows.Forms.DialogResult]::OK
            $dialog.Close()
        }
        catch {
            [Windows.Forms.MessageBox]::Show(
                $_.Exception.Message,
                '按键映射检查失败',
                [Windows.Forms.MessageBoxButtons]::OK,
                [Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        }
    })
    $dialog.Controls.Add($accept)
    $dialog.AcceptButton = $accept
    $dialog.CancelButton = $cancel
    return $dialog.ShowDialog($form)
}

if ($PSBoundParameters.ContainsKey('ValidateAliases')) {
    $validated = @(Get-ValidatedKeyAliases $ValidateAliases)
    [pscustomobject]@{
        Valid = $true
        AliasCount = $validated.Count
        Aliases = $validated
        PreservesOriginalKeys = $true
        SystemCursorCalls = 0
    }
    exit 0
}

$form = New-Object Windows.Forms.Form
$form.Text = '《1937特种兵》现代启动中心'
$form.StartPosition = 'CenterScreen'
$form.ClientSize = New-Object Drawing.Size(1060, 690)
$form.MinimumSize = New-Object Drawing.Size(960, 640)
$form.BackColor = $background
$form.ForeColor = $textPrimary
$form.Font = New-Object Drawing.Font('Microsoft YaHei UI', 9)
$form.AutoScaleMode = [Windows.Forms.AutoScaleMode]::Dpi
$iconPath = Join-Path $gameDirectory 'M1937.ico'
if (Test-Path -LiteralPath $iconPath) {
    $form.Icon = New-Object Drawing.Icon($iconPath)
}

$header = New-Object Windows.Forms.Panel
$header.Dock = [Windows.Forms.DockStyle]::Top
$header.Height = 92
$header.BackColor = [Drawing.Color]::FromArgb(126, 32, 29)
$form.Controls.Add($header)

$title = New-Object Windows.Forms.Label
$title.Text = '1937 特种兵 · 现代增强版'
$title.Location = New-Object Drawing.Point(28, 17)
$title.AutoSize = $true
$title.Font = New-Object Drawing.Font(
    'Microsoft YaHei UI', 20, [Drawing.FontStyle]::Bold)
$header.Controls.Add($title)

$subtitle = New-Object Windows.Forms.Label
$subtitle.Text = '选择任务、调整现代显示与敌军强度，然后直接进入游戏'
$subtitle.Location = New-Object Drawing.Point(31, 59)
$subtitle.AutoSize = $true
$subtitle.ForeColor = [Drawing.Color]::FromArgb(238, 207, 195)
$header.Controls.Add($subtitle)

$missionPanel = New-Object Windows.Forms.Panel
$missionPanel.Location = New-Object Drawing.Point(22, 112)
$missionPanel.Size = New-Object Drawing.Size(580, 505)
$missionPanel.Anchor = 'Top,Bottom,Left'
$missionPanel.BackColor = $panelColor
$form.Controls.Add($missionPanel)

$missionHeading = New-Object Windows.Forms.Label
$missionHeading.Text = '任务选择'
$missionHeading.Location = New-Object Drawing.Point(20, 16)
$missionHeading.AutoSize = $true
$missionHeading.Font = New-Object Drawing.Font(
    'Microsoft YaHei UI', 12, [Drawing.FontStyle]::Bold)
$missionPanel.Controls.Add($missionHeading)

$missionHint = New-Object Windows.Forms.Label
$missionHint.Text = '12 个原版任务，全部使用稳定 MOD 运行路径'
$missionHint.Location = New-Object Drawing.Point(20, 45)
$missionHint.AutoSize = $true
$missionHint.ForeColor = $textMuted
$missionPanel.Controls.Add($missionHint)

$missionList = New-Object Windows.Forms.ListView
$missionList.Location = New-Object Drawing.Point(20, 78)
$missionList.Size = New-Object Drawing.Size(540, 405)
$missionList.Anchor = 'Top,Bottom,Left,Right'
$missionList.View = [Windows.Forms.View]::Details
$missionList.FullRowSelect = $true
$missionList.MultiSelect = $false
$missionList.HideSelection = $false
$missionList.BackColor = $panelAlt
$missionList.ForeColor = $textPrimary
$missionList.BorderStyle = [Windows.Forms.BorderStyle]::None
[void]$missionList.Columns.Add('关卡', 78)
[void]$missionList.Columns.Add('任务名称', 205)
[void]$missionList.Columns.Add('资源', 120)
foreach ($mission in $catalog.missions) {
    $item = New-Object Windows.Forms.ListViewItem(
        ('第 {0:D2} 关' -f [int]$mission.number))
    [void]$item.SubItems.Add([string]$mission.title)
    [void]$item.SubItems.Add([string]$mission.vwf_name)
    $item.Tag = [int]$mission.number
    [void]$missionList.Items.Add($item)
}
$missionPanel.Controls.Add($missionList)

$settingsPanel = New-Object Windows.Forms.Panel
$settingsPanel.Location = New-Object Drawing.Point(620, 112)
$settingsPanel.Size = New-Object Drawing.Size(418, 505)
$settingsPanel.Anchor = 'Top,Bottom,Left,Right'
$settingsPanel.BackColor = $panelColor
$form.Controls.Add($settingsPanel)

$settingsHeading = New-Object Windows.Forms.Label
$settingsHeading.Text = '增强设置（自动保存到 rungame.ini）'
$settingsHeading.Location = New-Object Drawing.Point(20, 16)
$settingsHeading.AutoSize = $true
$settingsHeading.Font = New-Object Drawing.Font(
    'Microsoft YaHei UI', 12, [Drawing.FontStyle]::Bold)
$settingsPanel.Controls.Add($settingsHeading)

function Add-SettingLabel {
    param([string]$Text, [int]$Y)
    $label = New-Object Windows.Forms.Label
    $label.Text = $Text
    $label.Location = New-Object Drawing.Point(22, $Y)
    $label.Size = New-Object Drawing.Size(105, 26)
    $label.ForeColor = $textMuted
    $settingsPanel.Controls.Add($label)
}

function Add-ComboBox {
    param([string[]]$Items, [int]$Y)
    $combo = New-Object Windows.Forms.ComboBox
    $combo.Location = New-Object Drawing.Point(135, $Y)
    $combo.Size = New-Object Drawing.Size(255, 28)
    $combo.DropDownStyle = [Windows.Forms.ComboBoxStyle]::DropDownList
    $combo.BackColor = $panelAlt
    $combo.ForeColor = $textPrimary
    [void]$combo.Items.AddRange($Items)
    $settingsPanel.Controls.Add($combo)
    return $combo
}

Add-SettingLabel '显示模式' 62
$displayCombo = Add-ComboBox @(
    '稳定窗口 1024×768（推荐、已验证）',
    '无边框最大窗口（实验）',
    '全屏缩放（实验、保持原比例）',
    '全屏铺满（实验）'
) 58

Add-SettingLabel '渲染后端' 105
$rendererCombo = Add-ComboBox @(
    'Direct3D 9（稳定）',
    'Direct3D 9 on 12（实验）',
    'OpenGL（兼容备用）'
) 101

Add-SettingLabel '游戏难度' 148
$difficultyCombo = Add-ComboBox @('轻松', '标准', '困难', '专家') 144

Add-SettingLabel '敌军智能' 191
$aiCombo = Add-ComboBox @(
    '原版',
    '增强',
    '战术协同',
    '老兵搜索'
) 187

$smoothScroll = New-Object Windows.Forms.CheckBox
$smoothScroll.Text = '使用原版鼠标与原版边缘卷屏（固定）'
$smoothScroll.Location = New-Object Drawing.Point(22, 236)
$smoothScroll.AutoSize = $true
$smoothScroll.ForeColor = $textPrimary
$smoothScroll.Checked = $false
$smoothScroll.Enabled = $false
$settingsPanel.Controls.Add($smoothScroll)

$disableIme = New-Object Windows.Forms.CheckBox
$disableIme.Text = '游戏内屏蔽输入法'
$disableIme.Location = New-Object Drawing.Point(212, 236)
$disableIme.AutoSize = $true
$disableIme.ForeColor = $textPrimary
$settingsPanel.Controls.Add($disableIme)

$timerCheck = New-Object Windows.Forms.CheckBox
$timerCheck.Text = '启用 1 ms 高精度计时'
$timerCheck.Location = New-Object Drawing.Point(22, 269)
$timerCheck.AutoSize = $true
$timerCheck.ForeColor = $textPrimary
$settingsPanel.Controls.Add($timerCheck)

$rememberLevel = New-Object Windows.Forms.CheckBox
$rememberLevel.Text = '记住所选关卡'
$rememberLevel.Location = New-Object Drawing.Point(212, 269)
$rememberLevel.AutoSize = $true
$rememberLevel.ForeColor = $textPrimary
$settingsPanel.Controls.Add($rememberLevel)

$screen = [Windows.Forms.Screen]::PrimaryScreen.Bounds
$screenInfo = New-Object Windows.Forms.Label
$screenInfo.Text = "当前桌面：$($screen.Width) × $($screen.Height)"
$screenInfo.Location = New-Object Drawing.Point(22, 313)
$screenInfo.AutoSize = $true
$screenInfo.ForeColor = $textMuted
$settingsPanel.Controls.Add($screenInfo)

$profileInfo = New-Object Windows.Forms.Label
$profileInfo.Text = (
    '推荐“稳定窗口 1024×768”：菜单、第一关和窗口卷屏均已验证；' +
    [Environment]::NewLine +
    '补丁不会锁定、重置或主动移动 Windows 系统光标。')
$profileInfo.Location = New-Object Drawing.Point(22, 343)
$profileInfo.Size = New-Object Drawing.Size(370, 53)
$profileInfo.ForeColor = $textMuted
$settingsPanel.Controls.Add($profileInfo)

$saveButton = New-Object Windows.Forms.Button
$saveButton.Text = '保存设置'
$saveButton.Location = New-Object Drawing.Point(22, 409)
$saveButton.Size = New-Object Drawing.Size(96, 40)
Set-FlatButtonStyle $saveButton $false
$settingsPanel.Controls.Add($saveButton)

$advancedButton = New-Object Windows.Forms.Button
$advancedButton.Text = '高级增强设置'
$advancedButton.Location = New-Object Drawing.Point(130, 409)
$advancedButton.Size = New-Object Drawing.Size(124, 40)
Set-FlatButtonStyle $advancedButton $false
$settingsPanel.Controls.Add($advancedButton)

$configButton = New-Object Windows.Forms.Button
$configButton.Text = '高级渲染配置'
$configButton.Location = New-Object Drawing.Point(266, 409)
$configButton.Size = New-Object Drawing.Size(130, 40)
Set-FlatButtonStyle $configButton $false
$settingsPanel.Controls.Add($configButton)

$folderButton = New-Object Windows.Forms.Button
$folderButton.Text = '打开游戏目录'
$folderButton.Location = New-Object Drawing.Point(22, 457)
$folderButton.Size = New-Object Drawing.Size(374, 32)
Set-FlatButtonStyle $folderButton $false
$settingsPanel.Controls.Add($folderButton)

$launchSelected = New-Object Windows.Forms.Button
$launchSelected.Text = '进入原版菜单（所选任务）'
$launchSelected.Location = New-Object Drawing.Point(620, 631)
$launchSelected.Size = New-Object Drawing.Size(196, 43)
$launchSelected.Anchor = 'Bottom,Right'
$launchSelected.Font = New-Object Drawing.Font(
    'Microsoft YaHei UI', 10, [Drawing.FontStyle]::Bold)
Set-FlatButtonStyle $launchSelected $true
$form.Controls.Add($launchSelected)

$launchMenu = New-Object Windows.Forms.Button
$launchMenu.Text = '进入原版完整菜单'
$launchMenu.Location = New-Object Drawing.Point(828, 631)
$launchMenu.Size = New-Object Drawing.Size(210, 43)
$launchMenu.Anchor = 'Bottom,Right'
Set-FlatButtonStyle $launchMenu $false
$form.Controls.Add($launchMenu)

$status = New-Object Windows.Forms.Label
$status.Text = '设置由增强 DLL 直接读取；即使以后直接运行 M1937.exe 也会生效。'
$status.Location = New-Object Drawing.Point(24, 642)
$status.Size = New-Object Drawing.Size(570, 26)
$status.Anchor = 'Bottom,Left'
$status.ForeColor = $textMuted
$form.Controls.Add($status)

$savedLevel = Get-IniInt $runGameIni 'mod' 'StartLevel' 1
if ($savedLevel -lt 1 -or $savedLevel -gt 12) { $savedLevel = 1 }
$savedItem = $null
foreach ($candidate in $missionList.Items) {
    if ([int]$candidate.Tag -eq $savedLevel) {
        $savedItem = $candidate
        break
    }
}
if ($null -eq $savedItem) {
    $savedItem = $missionList.Items[0]
}
$savedItem.Selected = $true
$savedItem.Focused = $true
$missionList.EnsureVisible($savedItem.Index)

$difficultyCombo.SelectedIndex =
    [Math]::Max(0, [Math]::Min(3, (Get-IniInt $runGameIni 'mod' 'Difficulty' 1)))
$aiCombo.SelectedIndex =
    [Math]::Max(0, [Math]::Min(3, (Get-IniInt $runGameIni 'mod' 'AILevel' 2)))
$smoothScroll.Checked = $false
$disableIme.Checked = (Get-IniInt $runGameIni 'mod' 'DisableIME' 1) -ne 0
$timerCheck.Checked =
    (Get-IniInt $runGameIni 'mod' 'HighResolutionTimer' 1) -ne 0
$rememberLevel.Checked = (Get-IniInt $runGameIni 'mod' 'RememberLevel' 1) -ne 0
$windowed = (Get-IniValue $ddrawIni 'ddraw' 'windowed' 'true') -eq 'true'
$fullscreen =
    (Get-IniValue $ddrawIni 'ddraw' 'fullscreen' 'false') -eq 'true'
$maintainAspect =
    (Get-IniValue $ddrawIni 'ddraw' 'maintas' 'true') -eq 'true'
$displayCombo.SelectedIndex =
    $(if ($windowed -and $fullscreen) { 1 }
      elseif ($windowed) { 0 }
      elseif ($maintainAspect) { 2 }
      else { 3 })
$renderer = Get-IniValue $ddrawIni 'ddraw' 'renderer' 'direct3d9'
$rendererCombo.SelectedIndex = switch ($renderer.ToLowerInvariant()) {
    'direct3d9on12' { 1 }
    'opengl' { 2 }
    default { 0 }
}

function Save-Settings {
    if ($missionList.SelectedItems.Count -eq 0) {
        $missionList.Items[0].Selected = $true
    }
    $selectedLevel = [int]$missionList.SelectedItems[0].Tag
    # Keep the original 1024x768 logical UI surface. cnc-ddraw performs the
    # desktop-sized output scaling; changing the engine surface itself breaks
    # the original toolbar, help and minimap artwork.
    $isExpanded = $false
    $rendererName = @('direct3d9', 'direct3d9on12', 'opengl')[
        $rendererCombo.SelectedIndex]

    Set-IniValue $runGameIni 'mod' 'Enabled' '1'
    Set-IniValue $runGameIni 'mod' 'Difficulty' ([string]$difficultyCombo.SelectedIndex)
    Set-IniValue $runGameIni 'mod' 'AILevel' ([string]$aiCombo.SelectedIndex)
    Set-IniValue $runGameIni 'mod' 'HearingRadius' '0'
    Set-IniValue $runGameIni 'mod' 'AlertRadius' '0'
    Set-IniValue $runGameIni 'mod' 'SmoothEdgeScroll' '0'
    Set-IniValue $runGameIni 'mod' 'EdgeZone' '2'
    Set-IniValue $runGameIni 'mod' 'ScrollResponse' '8'
    Set-IniValue $runGameIni 'mod' 'DisableIME' $(if ($disableIme.Checked) { '1' } else { '0' })
    Set-IniValue $runGameIni 'mod' 'HighResolutionTimer' $(if ($timerCheck.Checked) { '1' } else { '0' })
    Set-IniValue $runGameIni 'mod' 'ExpandedViewport' $(if ($isExpanded) { '1' } else { '0' })
    Set-IniValue $runGameIni 'mod' 'PreserveLegacyUI' '1'
    Set-IniValue $runGameIni 'mod' 'ViewportWidth' $(if ($isExpanded) { [string]$screen.Width } else { '0' })
    Set-IniValue $runGameIni 'mod' 'ViewportHeight' $(if ($isExpanded) { [string]$screen.Height } else { '0' })
    Set-IniValue $runGameIni 'mod' 'MessagePumpIntervalMs' '8'
    Set-IniValue $runGameIni 'mod' 'MessagePumpBudget' '4'
    Set-IniValue $runGameIni 'mod' 'SystemCursorMapping' '1'
    Set-IniValue $runGameIni 'mod' 'TextBriefings' '1'
    Set-IniValue $runGameIni 'mod' 'RememberLevel' $(if ($rememberLevel.Checked) { '1' } else { '0' })
    Set-IniValue $runGameIni 'mod' 'StartLevel' $(if ($rememberLevel.Checked) { [string]$selectedLevel } else { '0' })
    Set-IniValue $runGameIni 'mod' 'AutoStart' '0'
    Set-IniValue $runGameIni 'mod' 'Renderer' $rendererName
    Set-IniValue $runGameIni 'mod' 'DisplayMode' ([string]$displayCombo.SelectedIndex)
    Set-DdrawProfile $displayCombo.SelectedIndex $rendererName
    $status.Text = "设置已持久化：难度=$($difficultyCombo.Text)，敌军=$($aiCombo.Text)，显示=$($displayCombo.Text)"
    return @{
        Level = $selectedLevel
        Expanded = $isExpanded
    }
}

$saveButton.Add_Click({
    try { [void](Save-Settings) }
    catch {
        [Windows.Forms.MessageBox]::Show(
            $_.Exception.Message, '保存失败',
            [Windows.Forms.MessageBoxButtons]::OK,
            [Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    }
})

$configButton.Add_Click({
    $configExe = Join-Path $gameDirectory 'cnc-ddraw config.exe'
    if (Test-Path -LiteralPath $configExe) {
        Start-Process -FilePath $configExe -WorkingDirectory $gameDirectory
    }
})

$advancedButton.Add_Click({
    if ((Show-AdvancedSettingsDialog) -eq
        [Windows.Forms.DialogResult]::OK) {
        $status.Text = (
            '高级设置已保存：诊断、遥测、任务 sidecar、插件和按键映射' +
            '将在下次启动时生效。')
    }
})

$folderButton.Add_Click({
    Start-Process explorer.exe -ArgumentList $gameDirectory
})

$launchSelected.Add_Click({
    try {
        $saved = Save-Settings
        Start-M1937Process $saved.Level $false $saved.Expanded $screen.Width $screen.Height
        $form.Close()
    }
    catch {
        [Windows.Forms.MessageBox]::Show(
            $_.Exception.Message, '启动失败',
            [Windows.Forms.MessageBoxButtons]::OK,
            [Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    }
})

$missionList.Add_DoubleClick({ $launchSelected.PerformClick() })

$launchMenu.Add_Click({
    try {
        $saved = Save-Settings
        Start-M1937Process 0 $false $saved.Expanded $screen.Width $screen.Height
        $form.Close()
    }
    catch {
        [Windows.Forms.MessageBox]::Show(
            $_.Exception.Message, '启动失败',
            [Windows.Forms.MessageBoxButtons]::OK,
            [Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    }
})

if (-not [string]::IsNullOrWhiteSpace($RenderPreviewPath)) {
    $preview = Get-ValidatedPreviewPath `
        $RenderPreviewPath 'Launcher preview output'
    [IO.Directory]::CreateDirectory(
        [IO.Path]::GetDirectoryName($preview)) | Out-Null
    $form.StartPosition = [Windows.Forms.FormStartPosition]::Manual
    $form.Location = New-Object Drawing.Point(-32000, -32000)
    $form.ShowInTaskbar = $false
    $handle = $form.Handle
    $style = [M1937Ini]::GetWindowLongPtr($handle, -20).ToInt64()
    [void][M1937Ini]::SetWindowLongPtr(
        $handle, -20,
        [IntPtr]($style -bor 0x08000080))
    [void][M1937Ini]::ShowWindow($handle, 4)
    [Windows.Forms.Application]::DoEvents()
    $form.PerformLayout()
    $form.Refresh()
    [Windows.Forms.Application]::DoEvents()
    $previewWidth = $form.Width
    $previewHeight = $form.Height
    $bitmap = New-Object Drawing.Bitmap(
        $previewWidth, $previewHeight)
    try {
        $form.DrawToBitmap(
            $bitmap,
            (New-Object Drawing.Rectangle(
                0, 0,
                $previewWidth,
                $previewHeight)))
        $bitmap.Save(
            $preview,
            [Drawing.Imaging.ImageFormat]::Png)
    }
    finally {
        [void][M1937Ini]::ShowWindow($handle, 0)
        $bitmap.Dispose()
        $form.Dispose()
    }
    [pscustomobject]@{
        Preview = $preview
        Width = $previewWidth
        Height = $previewHeight
        SystemCursorCalls = 0
    }
    exit 0
}

[void]$form.ShowDialog()
