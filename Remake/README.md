# 《1937特种兵》复刻工程

这是一个从零实现的新游戏工程。游戏运行时使用 Godot 4.7.1 Standard 与 typed GDScript，旧资源研究和本地转换工具使用 .NET 10。

## 里程碑状态

| 层次 | 当前成果 | 尚未完成 |
|---|---|---|
| 资源格式 | 1394 个 GFL 条目；IBLOCK、TLG1、SPR1、DBL、VWF、SLIST1、SLF/WAV；L1—L5、阵营、感知、生命值、攻击和巡逻字段 | 与后续玩法相关的剩余 DBL/SLIST 扩展字段 |
| 精灵动画 | 980 个精灵、2,775 个动画组、11,898 帧全部转换；20 动作 × 9 方向语义；精确帧保持；攻击末帧命中与死亡末帧保持 | 特殊攻击对象、受伤原动作和过渡校准 |
| 关卡 | `m000`—`m011` 全部生成地形、19,199 个实体和 L2/L3 数据；玩家/敌人/护送角色动态占位；真实拾取物和汽油桶 | 其余非角色实体精确足印和通用中立角色行为 |
| 任务 | 十二关任务图、scene 白名单、依赖/去重/限时/胜负与世界事件协议；逐关 DBL 998 爆破策略；可追溯的任务媒体 cue；m000 真实营救撤离闭环；m004/m009/m010 关键语义定案 | 十二关完整对白、镜头、AI 配合、触发节奏和难度校准 |
| 玩法 | A*、动态占位、实际战斗；背包/武器切换；6/7/9 世界投射物；真实拾取、地雷/油桶；战术地图、游戏菜单、失败重玩与完整局内存读档；显示/声音/字幕/简报/边缘卷屏设置；原 WAV/简报、有界并发音效与确定性事件回放 | type 8/10/11 原对象、按键重映射、完整过场和长时间实机回放 |

“资源和任务结构已恢复”不等于“游戏已经复刻完成”。目前已经是带真实碰撞、寻路、动态角色、实际战斗、战术地图、背包、世界投射物、拾取/爆炸物、完整局内存读档和通用任务事件的十二关可玩原型；十二关数据驱动目标均可达到胜利，m000 还通过了真实 scene 的营救—护送—撤离集成测试。确定性事件流会对战斗和十二关任务图逐步生成状态哈希，但还不是十分钟真实输入录像。逐关对白、镜头、难度和其余产品功能仍在开发中。

## 动画与任务恢复结论

SPR 动画组参数 0 已确认使用：

```text
serial_id = action_index * 9 + direction_index
```

共 20 个动作槽和 9 个方向槽，其中方向 0 为“无”，1—8 为八方向。转换器保留每组全部帧、原始顺序、锚点参数、单组横向 atlas 和逐帧 PNG，并按原版 `parameters[2] + 1` 保存和播放每帧保持 tick。玩家和敌人的移动/站立、对应武器攻击及死亡动画已经接线；攻击进入最后一帧时复核射程/视线，类型 1—5 结算即时命中，类型 6/7/9 生成世界投射物后再结算，死亡播放一次并保持末帧。当前非致命伤为 0.18 秒重制闪红/硬直；type 8/10/11 的专用状态对象、原受伤动作和动作过渡仍待恢复。

十二关的任务结构不是只能事后从零人工编排。现已从关卡锚点、原程序任务控制流和任务简报恢复出数据驱动目标图，通用状态机可以处理目标依赖、计数去重、限时、失败和最终胜利。m004 已确认 scene 2637 携带物品 101；m009 默认修复原控制流未使用全场敌军扫描的缺陷，要求全关清敌、两份文件和四处列车爆破；m010 自动检查老赵、强子、大牛、古明分别同时进入四个 128 像素制高点。任务数据还可在开场、目标完成、剧情锚点和胜利时播放带来源标签的声音、对白、视频或结局；当前只正式接入 m000 两处提示、m006 一处提示和 m011 结局图，仍需人工逐关编排完整对白、镜头、AI 配合和难度节奏。详细证据见 [任务恢复说明](docs/MISSION_RECOVERY.md)。

爆破交互不会笼统地“见点就扣炸药”。真实关卡 DBL 998 拾取物与爆破目标的逐关计数决定重制策略：m001、m004、m011 使用预置炸药且不扣背包；m002、m003、m008、m009 每个目标需要并消耗一份背包炸药，且只有 `MissionRuntime` 接受事件后才扣除。该策略是由地图物资闭环作出的重制规则，不冒充已逐字节恢复的原版消耗实现。

## 环境要求

- Windows 10/11；
- [.NET 10 SDK](https://dotnet.microsoft.com/)；
- Godot 4.7.1 Standard（无须 .NET 版）；
- 一份与当前已知哈希版本匹配的原版目录；
- 若导入目标位于 Git 工作树中，需要命令行可调用的 Git，以检查输出目录是否已被忽略。

## 1. 检查原版目录

以下命令只读检查目录，不提取资源：

```powershell
dotnet run --project .\tools\ResourceTool -- inspect "E:\1937\1937tzb_1229"
```

已知版本的输出应包括 `Known version hashes match: True`、`GFL entries: 1394` 和 `Formal VWF levels: 12/12`。未知哈希版本不会被静默套用既有偏移。

## 2. 本地导入资源

在 `Remake` 目录运行：

```powershell
.\tools\Import-OriginalAssets.cmd "E:\1937\1937tzb_1229"
```

也可以显式指定输出目录：

```powershell
.\tools\Import-OriginalAssets.cmd "E:\1937\1937tzb_1229" "D:\Mission1937-LocalAssets"
```

等价的底层命令：

```powershell
dotnet run --project .\tools\ResourceTool --configuration Release -- `
  import "E:\1937\1937tzb_1229" ".\LocalAssets"
```

导入器会先完成版本哈希、输入/输出目录隔离和 Git 忽略规则检查。默认输出结构为：

```text
LocalAssets/
├── manifest.json                         导入记录与源版本校验结果
├── raw/gfl/                              1394 个本地提取条目
└── converted/
    ├── asset-manifest.json               资源总索引
    ├── iblock/*.png                      34 张
    ├── tile-atlases/*.png                45 张 4×4 过渡图集
    ├── sprites/*.png                     980 张首帧预览
    ├── sprite-frames/<id>/sprite.json    980 份动画清单，schema_version = 2
    ├── sprite-frames/<id>/gNNN/
    │   ├── atlas.png                     2,775 个动画组 atlas
    │   └── fNNNN.png                     共 11,898 个逐帧 PNG
    ├── audio/*.wav                       128 个
    ├── legacy-media-catalog.json         简报、示意图、声音与旧视频元数据
    └── levels/
        ├── index.json                    十二关索引
        └── m000/ ... m011/
            ├── terrain.png
            ├── navigation.bin            VWF L2—L5 的 M37NAV1 数据
            └── level.json                实体、巡逻点、任务锚点和导航元数据
```

批量资源不直接进入 Git 仓库，原因和边界见 [资产收录与本地导入策略](ASSET_POLICY.md)。

## 3. 运行 Godot 原型

```powershell
godot --path .\game --editor
godot --path .\game
```

直接打开某一关：

```powershell
godot --path .\game -- --level=m007
```

操作方式：

- 左键选择队员，`Shift + 左键` 多选；
- 右键下达自动绕障碍的移动命令，或攻击敌人与汽油桶；`R` 重置当前关；
- `Esc` 打开游戏菜单；`M` 打开战术地图，`B` 或 `I` 打开小队背包；`F5` 快速保存，`F9` 读取最近存档；
- `E` 营救/拾取/任务交互，`Q` 装填，`1`—`8` 或 `Tab` 切换已持有武器，`X` 布雷；m008 的炸药必须按 `F` 手动引爆，不能用通用 `E` 爆破交互代替；
- `WASD`、方向键或鼠标移动到屏幕边缘平移相机；
- 中键拖动相机，滚轮缩放；
- `PageUp` / `PageDown` 切换上一关或下一关。

菜单中的保存/读取与 `F5`/`F9` 使用同一套存档。任务失败时画面灰化并强制弹出失败菜单，可重新开始本关或读取最近存档；`R` 也可直接重玩。全屏默认使用当前桌面分辨率，菜单可持久化主音量、字幕、关卡简报和鼠标边缘卷屏开关。

主场景会读取对应 `levels/mNNN/level.json`、地形、`navigation.bin`、实体预览和动画清单。缺少全部本地数据时会回退到程序化占位场景；正式地形存在但导航无效时会拒绝可能穿墙的移动命令。

## 4. 构建与验证

```powershell
.\tools\Verify.cmd
```

验证流程会扫描意外加入仓库的批量资产、构建 .NET 解决方案、运行 171 项合成格式测试，并在找到 Godot 时解析全部 GDScript，依次运行 123 项核心逻辑、160 项战斗/任务、82 项投射物/背包、120 项世界交互、46 项无资产媒体、21 项产品壳、81 项存档/设置和 93 项确定性回放测试，再执行主场景冒烟；本地转换资产存在时，还会追加 6,753 项十二关真实资源/任务绑定、310 项真实媒体审计和 m004 高密度寻路压力测试。如果 Godot 不在 `PATH`，可传入完整路径：

```powershell
.\tools\Verify.cmd C:\path\to\Godot_v4.7.1-stable_win64.exe
```

`.cmd` 入口只为本次调用使用 `ExecutionPolicy Bypass`，不会修改系统 PowerShell 执行策略。

导入本地资源后，可再执行 12 关与全部动画清单的真实资产回归；该测试会校验 6,000 余项尺寸、层值、出生格和动画时序：

```powershell
.\tools\Run-RealAssetTests.cmd C:\path\to\Godot_v4.7.1-stable_win64_console.exe
```

## 5. 生成 Windows 本地试玩程序

本地资源导入完成后运行：

```powershell
.\tools\Build-Playable.cmd
```

脚本会在已被 Git 忽略的 `LocalBuild/1937Remake/` 生成
`Play-1937-Remake.cmd`、Windows 可执行文件、PCK 和资源目录，并自动完成一次导出产物
headless 冒烟测试。默认使用目录联接避免重复复制数百 MiB 资源；需要可移动目录时传入
`-AssetMode Copy`。完整说明见 [Windows 本地试玩包](docs/PLAYABLE_BUILD.md)。

## 文档

- [架构与本地数据流](docs/ARCHITECTURE.md)
- [已确认的资源格式](docs/RESOURCE_FORMATS.md)
- [十二关任务恢复说明](docs/MISSION_RECOVERY.md)
- [导航、视线与战斗边界](docs/NAVIGATION_AND_COMBAT.md)
- [投射物、背包与世界交互物](docs/PROJECTILES_AND_INVENTORY.md)
- [对白、声音、任务简报与旧视频恢复](docs/MEDIA_RECOVERY.md)
- [开发路线图与里程碑边界](docs/ROADMAP.md)
- [开发环境、验证与 IDA Python 修复](docs/DEVELOPMENT.md)
- [Windows 本地试玩包](docs/PLAYABLE_BUILD.md)
- [资产收录与本地导入策略](ASSET_POLICY.md)

## 项目边界

这是非官方的技术保存与复刻工程。仓库中的新代码是否采用开源许可证，应以仓库实际出现的许可证文件为准；本说明不对原版素材的权属、授权或分发条件作判断。
