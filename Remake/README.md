# 《1937特种兵》复刻工程

这是一个从零实现的新游戏工程。游戏运行时使用 Godot 4.7.1 Standard 与 typed GDScript，旧资源研究和本地转换工具使用 .NET 10。

## 里程碑状态

| 层次 | 当前成果 | 尚未完成 |
|---|---|---|
| 资源格式 | 1394 个 GFL 条目；IBLOCK、TLG1、SPR1、DBL、VWF、SLIST1、SLF/WAV；L1—L5、阵营、感知、生命值、攻击和巡逻字段 | 与后续玩法相关的剩余 DBL/SLIST 扩展字段 |
| 精灵动画 | 980 个精灵、2,775 个动画组、11,898 帧全部转换；20 动作 × 9 方向语义；精确帧保持；攻击末帧命中与死亡末帧保持；GFL 470/900 特殊对象帧接线 | 原版非致命受伤动作、逐层 baseline 和动作过渡校准 |
| 关卡 | `m000`—`m011` 全部生成地形、19,199 个实体和 L2/L3 数据；玩家/敌人/护送角色动态占位；真实拾取物和汽油桶 | 其余非角色实体精确足印和通用中立角色行为 |
| 任务 | 十二关任务图、scene 白名单、依赖/去重/限时/胜负与世界事件协议；逐关 DBL 998 爆破策略；m000 真实营救撤离闭环；m004/m009/m010 关键语义定案；十二关 43 个导演节点、45 行补写对白、教程、镜头请求、AI 协作与难度第一版 | 原版逐字对白/镜头证据升级、逐关完整通关后的节奏和平衡校准 |
| 玩法 | A*、动态占位、实际战斗；四渲染队列；右侧五列背包；6/7/9 投射物与 type 8/10/11 生命周期；实时右下角地图；十槽存档、按键重映射、分通道音量、失败重玩；原 WAV/简报与确定性事件回放 | S/B 原版命令细节、特殊动作数值、完整过场和长时间真实输入回放 |

“资源和任务结构已恢复”不等于“游戏已经复刻完成”。目前已经是带真实碰撞、寻路、动态角色、实际战斗、右下角实时地图、五列背包、特殊对象、完整局内存读档和通用任务事件的十二关可玩原型；十二关数据驱动目标均可达到胜利，m000 还通过了真实 scene 的营救—护送—撤离集成测试。十二关导演和难度已有可执行第一版，但其中补写对白、镜头时长、教程文本、AI 策略和数值明确标为 `remake_editorial`，不能冒充原版内容。确定性事件流会生成逐步状态哈希，但还不是十分钟真实输入录像。

## 动画与任务恢复结论

SPR 动画组参数 0 已确认使用：

```text
serial_id = action_index * 9 + direction_index
```

共 20 个动作槽和 9 个方向槽，其中方向 0 为“无”，1—8 为八方向。转换器保留每组全部帧、原始顺序、锚点参数、单组横向 atlas 和逐帧 PNG，并按原版 `parameters[2] + 1` 保存和播放每帧保持 tick。玩家和敌人的移动/站立、对应武器攻击及死亡动画已经接线；攻击进入最后一帧时复核射程/视线，类型 1—5 结算即时命中，类型 6/7/9 生成世界投射物后再结算，死亡播放一次并保持末帧。type 8 现在具有 faction 1 目标进入 32×16 椭圆后触发的 actor 84 / GFL 470 世界对象；type 10 是第 100 个 world tick 触发的 actor 85 / GFL 900 延时对象；type 11 建立可刷新、超时/死亡/切关释放并可存读档的 AI 控制状态。为让该生命周期可试玩，m011 会把物品 99 和 type 11 动作明确作为 `remake_editorial` bridge 配给首名存活队员（当前 m011 为老赵）；原版物品 99 的取得脚本和持有者尚未恢复。其伤害、爆炸几何、type 11 精确语义和时长仍标为 `unresolved_remake_default`。当前非致命伤仍使用 0.18 秒重制闪红/硬直，原受伤动作和过渡尚待校准。

原版 DBL `header[0]` 决定四条绘制队列：值 1 的庄稼地 a/b 是固定背景，始终先于人物绘制；值 0 的稻谷、人物和普通物件进入正常 Y/逐层基线排序。导入链现已保留并校验 `database_header_values`，而不是在生成 `ImportedLevelData` 时丢弃该数组；第一关真实资源回归确认 22 个 DBL 336/337 庄稼底图进入 queue 1、70 个 DBL 335 稻谷进入 queue 0。因此人物不会再被整块田地底片盖住，独立稻秆仍可按前后关系正常遮挡。复刻也已移除人物到移动目标之间的黄色命令线；多层 SPR 的逐层 baseline 仍需截图校准。

十二关的任务结构不是只能事后从零人工编排。现已从关卡锚点、原程序任务控制流和任务简报恢复出数据驱动目标图，通用状态机可以处理目标依赖、计数去重、限时、失败和最终胜利。m004 已确认 scene 2637 携带物品 101；m009 默认修复原控制流未使用全场敌军扫描的缺陷，要求全关清敌、两份文件和四处列车爆破；m010 自动检查老赵、强子、大牛、古明分别同时进入四个 128 像素制高点。`mission_direction.json` 进一步为十二关提供 43 个节奏节点、45 行提示对白、教程门控、镜头请求、AI 协作和逐关难度第一版。scene/objective 引用可追溯到恢复数据；对白措辞、镜头参数、教程、AI 策略和难度数值均标为 `remake_editorial`，仍需用原版录像和完整通关数据校准。详细证据见 [任务恢复说明](docs/MISSION_RECOVERY.md)与[十二关导演说明](docs/MISSION_DIRECTION.md)。

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

- 左键队员进行选择，左键地面下达自动寻路移动，左键敌人或汽油桶攻击；`Shift + 左键队员` 追加/取消选择；
- 世界中右键只用于拖框选择，不提交移动或攻击；菜单/背包等界面中松开右键返回上一级；
- `F2`—`F6` 选择本关第 1—5 名可玩队员，`R` 切换跑/走，`C` 切换匍匐/站立；
- `W` / `A` 打开右侧 276×421 的武器/物品五列方格；`M` 切换右下角实时地图；松开 `Esc` 打开或关闭当前菜单/模态层，`F1` 显示指南，`F7` 显示简报；
- `1`—`0` 按原版次序选择匕首、弹弓、大刀、飞刀、手枪、步枪、机枪、地雷、手榴弹、炸药包；
- `S` 显示敌军视野/攻击范围，`B` 进入阵亡目标清理模式；这两项是依据原版帮助标签作出的复刻增强/可玩解释，精确命令语义见取证文档；
- 默认按住左 `Ctrl` 或 `↑` 后左击存活角色/可破坏物，按原版路径下达强制目标/强制攻击；两条等价通道均可在设置中重映射；
- 复刻扩展：`E` 营救/拾取/任务交互，`Q` 装填，`F` 引爆已安放任务炸药，`Tab` 轮换武器，`Ctrl+F5` 写入 `quick`，`Ctrl+F9` 按时间读取当前最新有效槽；菜单读取始终打开多槽选择器；
- 鼠标移到窗口最外侧 1 像素平移相机；左右/下方向键、中键拖动和滚轮缩放是复刻扩展（原版 `↑` 是强制目标按住键）；
- `PageUp` / `PageDown` 仅在调试构建中切换上一关或下一关。

菜单提供 10 个手动存档槽，另有 `quick` 和胜利 `autosave`；任务失败时画面灰化，标题为“任务失败”，正文模板为 `任务失败：%s\n可重新开始本关，或从多槽存档选择器读取进度。`（`%s` 为失败原因），继续/保存按钮不可用。掩埋后的敌方 scene、type 8/10/11、导演节拍与 AI 协作状态均随局内存档恢复；胜利演出未看完的自动档会恢复胜利对白/镜头及结局，确认完成后再自动保存一次。全屏默认使用当前桌面分辨率，菜单可持久化按键映射、总静音、主音量/音乐/音效/语音、字幕、关卡简报和鼠标边缘卷屏开关；音乐/环境声由独立播放器进入 `Music`，影片音轨也进入 `Music`，不会误走语音或 SFX。

主场景会读取对应 `levels/mNNN/level.json`、地形、`navigation.bin`、实体预览和动画清单。缺少全部本地数据时会回退到程序化占位场景；正式地形存在但导航无效时会拒绝可能穿墙的移动命令。

## 4. 构建与验证

```powershell
.\tools\Verify.cmd
```

验证流程会扫描意外加入仓库的批量资产、构建 .NET 解决方案、运行合成格式测试，并在找到 Godot 时解析全部 GDScript，依次执行核心逻辑、战斗/任务、投射物/背包、世界交互、type 8/10/11 生命周期、无资产媒体、十二关导演、产品壳、存档/设置和确定性回放测试，再执行主场景冒烟。每个测试套件会在日志中输出自身当前检查数；文档不固定复制容易过期的计数。本地转换资产存在时，还会追加十二关真实资源/任务绑定、真实媒体审计、m004 高密度寻路压力测试，以及窗口化产品 UI 探针；后者会自动截取实时小地图、五列背包、暂停菜单和失败灰化界面，防止只验证逻辑而漏掉可见回归。如果 Godot 不在 `PATH`，可传入完整路径：

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
`Play-1937-Remake.cmd`、Windows 可执行文件、PCK 和资源目录，并分别通过 PCK 加载路径与
最终 `1937Remake.exe` 的 headless 冒烟测试。默认使用目录联接避免重复复制数百 MiB 资源；需要可移动目录时传入
`-AssetMode Copy`。完整说明见 [Windows 本地试玩包](docs/PLAYABLE_BUILD.md)。

## 文档

- [架构与本地数据流](docs/ARCHITECTURE.md)
- [已确认的资源格式](docs/RESOURCE_FORMATS.md)
- [原版操作、五列背包、地图与四队列取证](docs/ORIGINAL_BEHAVIOR_FORENSICS.md)
- [十二关任务恢复说明](docs/MISSION_RECOVERY.md)
- [十二关对白、镜头、教程、AI 与难度编排](docs/MISSION_DIRECTION.md)
- [导航、视线与战斗边界](docs/NAVIGATION_AND_COMBAT.md)
- [投射物、背包与世界交互物](docs/PROJECTILES_AND_INVENTORY.md)
- [对白、声音、任务简报与旧视频恢复](docs/MEDIA_RECOVERY.md)
- [开发路线图与里程碑边界](docs/ROADMAP.md)
- [开发环境、验证与 IDA Python 修复](docs/DEVELOPMENT.md)
- [Windows 本地试玩包](docs/PLAYABLE_BUILD.md)
- [资产收录与本地导入策略](ASSET_POLICY.md)

## 项目边界

这是非官方的技术保存与复刻工程。仓库中的新代码是否采用开源许可证，应以仓库实际出现的许可证文件为准；本说明不对原版素材的权属、授权或分发条件作判断。
