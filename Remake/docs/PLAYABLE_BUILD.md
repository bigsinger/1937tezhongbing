# Windows 本地试玩包

本工程不会把原版或本地转换资源提交到 Git。试玩包只在开发者电脑的
`Remake/LocalBuild/1937Remake/` 中生成，该目录已由根 `.gitignore` 排除。

当前开发机的默认启动入口为：

```text
F:\bigsinger\1937tezhongbing\Remake\LocalBuild\1937Remake\Play-1937-Remake.cmd
```

它是本机生成物；源码、任务或资源转换结果发生变化后应重新构建，不要把旧 PCK 当作最新试玩版本。

## 一键生成

先完成本地资源导入，确保存在
`Remake/LocalAssets/converted/levels/m000/level.json`，然后在 `Remake` 目录运行：

```powershell
.\tools\Build-Playable.cmd
```

如果 Godot 4.7.1 不在 `PATH`，显式传入标准版控制台程序：

```powershell
.\tools\Build-Playable.cmd `
  -GodotExecutable "C:\Tools\Godot_v4.7.1-stable_win64_console.exe"
```

生成结果：

```text
LocalBuild/1937Remake/
├── Play-1937-Remake.cmd       双击启动入口
├── README.txt
├── build-info.json
├── smoke-test.log
├── game/
│   ├── 1937Remake.exe
│   └── 1937Remake.pck
└── LocalAssets/               转换资源目录或本机目录联接
```

默认的 `Junction` 模式不会再次复制数百 MiB 转换资源，适合当前电脑快速反复构建。
生成可移动目录时使用复制模式：

```powershell
.\tools\Build-Playable.cmd -AssetMode Copy
```

复制模式只放入运行所需的 `converted/`，不会复制 `raw/`、转换测试目录或原始 GFL
提取结果。无论采用哪一种模式，生成目录都不会进入 Git。

## 运行与切关

双击 `Play-1937-Remake.cmd` 启动。不要只移动 `game/1937Remake.exe`，因为当前运行时按
`game/` 的上一级寻找 `LocalAssets/converted/`；启动器也会固定进程工作目录，保证 PCK
运行方式下该相对路径稳定。

命令行可直接选择关卡：

```powershell
.\LocalBuild\1937Remake\Play-1937-Remake.cmd -- --level=m007
```

可用关卡 ID 为 `m000`—`m011`。游戏内也可以按 `PageUp` / `PageDown` 切关，按 `R` 重置当前关卡。

## 当前操作

| 操作 | 输入 |
|---|---|
| 选择单个队员 | 左键 |
| 追加/取消选择 | `Shift` + 左键 |
| 编队移动 | 右键地面 |
| 攻击 | 先选队员，再右键敌人 |
| 营救、拾取、激活爆破点/制高点 | 靠近后按 `E` |
| m008 手动引爆（提前引爆会失败） | `F` |
| 主动装填 | 选中队员后按 `Q` |
| 平移镜头 | `WASD` 或按住鼠标中键拖动 |
| 缩放 | 鼠标滚轮 |
| 重玩当前关 | `R` |

界面右侧显示任务进度。出口每 0.2 秒自动检查 128 像素范围；默认要求全部存活队员和本关护送角色，存在 `exit_party` 规则时按剧情指定成员判定，例如 m001 只要求古明与铁蛋爹、m002 要求老赵与获救的强子。

## 本轮试玩范围与已知边界

当前包已经包含实际伤害、玩家有限弹药/装填、攻击动作末帧命中、受伤闪红/硬直、死亡动作、攻击/友军死亡警报、任务角色掉落，以及救援—击毙—拾取—爆破/占点—撤离—胜负事件链。`m000` 是当前完成度最高、绑定最明确的端到端流程。

以下内容仍属于开发中，不应据此判断最终品质：

- 受伤使用 0.18 秒闪红/硬直，没有冒充尚未找到的原版独立受伤动画；
- 敌人暂为无限弹药；弹匣、备弹、装填时间和玩家攻击恢复时间是重制默认值；
- 手榴弹和特殊动作尚未恢复原版投射物/爆炸对象，暂按末帧直接伤害；
- m004 计划书军官暂用候选 scene 2637（另有候选 2548）；m005/m006 的显示名差异、m009 车站区域和 m010 制高点占领细节仍需对照原版校准；
- 对白、镜头、过场、存档、完整声音系统和逐关难度尚未完成。

反馈问题时请同时提供 `build-info.json`、关卡 ID、复现步骤和截图；如果是启动失败，再附上 `smoke-test.log`。

## 导出模板与回退方式

`game/export_presets.cfg` 提供 `Windows Desktop` 预设。构建脚本会检查
`%APPDATA%\Godot\export_templates\4.7.1.stable\windows_release_x86_64.exe`：

- 已安装匹配模板：生成标准 Godot release 导出；
- 未安装模板：导出相同内容的 PCK，并复制当前 Godot 4.7.1 标准版作为本地运行器。

后一种方式无需为了 Windows 本机试玩下载约 1.28 GB 的全平台模板包，生成目录仍可直接
运行；它只用于本地且不会提交。两种方式最后都会从生成目录启动 8 个 headless 帧，日志中
只要出现 Godot 或 GDScript 错误，构建即失败。

`build-info.json` 会记录 Git 提交、Godot 版本、构建方式和资产模式，便于确认反馈对应的源码版本。构建脚本只允许输出到 `Remake/LocalBuild/` 的子目录，并在替换旧输出前拒绝删除重解析点，避免误删目录联接目标。
