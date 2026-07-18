# 开发环境与逆向分析说明

## 推荐环境

| 组件 | 用途 | 已验证版本 |
|---|---|---|
| .NET SDK | ResourceFormats、ResourceTool 和测试 | 10 |
| Godot Standard | 运行时、GDScript 测试和画面验证 | 4.7.1 |
| Git | 版本管理及导入目录忽略检查 | 当前 Windows 版本 |
| IDA Professional | 仅用于确认旧引擎读取逻辑 | 9.1 |
| CPython x64 | IDAPython runtime | 3.13.2 |

IDA 不是构建或运行复刻工程的依赖；它只用于在格式证据不足时核对原程序行为。仓库中的解析器必须通过可重复的文件结构检查和合成测试，而不能只依赖反编译器中的推测。

## 常用命令

以下命令都从 `Remake` 目录执行。

```powershell
# 构建 .NET 工具
dotnet build .\1937Remake.slnx --configuration Release

# 运行不含原版数据的格式测试
dotnet run --project .\tools\ResourceFormats.Tests --configuration Release --no-build

# 只读检查原版目录
dotnet run --project .\tools\ResourceTool -- inspect "E:\1937\1937tzb_1229"

# 导入到默认、已忽略的 LocalAssets
.\tools\Import-OriginalAssets.cmd "E:\1937\1937tzb_1229"

# 可选：用 FFmpeg 把原启动/历史视频转为 Godot 可播的 Ogg Theora
.\tools\Convert-LegacyMedia.cmd `
  -GameDirectory "E:\1937\1937tzb_1229" `
  -FfmpegExecutable "C:\path\to\ffmpeg.exe"

# 运行 Godot
godot --path .\game

# 直接从第十二关启动；m000—m011 均可用
godot --path .\game -- --level=m011

# 一次运行资产守卫、.NET 测试和 Godot 测试
.\tools\Verify.cmd C:\path\to\Godot_v4.7.1-stable_win64.exe

# 导入后逐关校验真实导航、实体出生格和全部动画清单
.\tools\Run-RealAssetTests.cmd C:\path\to\Godot_v4.7.1-stable_win64_console.exe

# 生成可双击启动的 Windows 本地试玩包
.\tools\Build-Playable.cmd `
  -GodotExecutable C:\path\to\Godot_v4.7.1-stable_win64_console.exe
```

如果只做开源仓库验证而没有原版目录，直接运行 `Verify.cmd` 即可；所有自动测试都使用人工合成数据。

### fresh checkout 的 Godot 校验顺序

Godot 的 `class_name` 类型注册缓存位于未纳入 Git 的 `.godot/global_script_class_cache.cfg`。如果 CI 在全新检出中直接按文件枚举顺序执行每个 `.gd` 的 `--check-only`，依赖 `NavigationGridData` 等全局类的脚本可能先于类型注册而报 `Identifier not found`，即使同一提交在打开过编辑器的开发机上能够通过。

`tools/Verify.ps1` 现在固定先运行：

```powershell
godot --headless --editor --path .\game --quit-after 2
```

由 Godot 自己扫描项目并生成类缓存，再逐脚本执行 `--check-only`、逻辑测试和场景冒烟测试。存在完整 `LocalAssets` 时，验证入口还会窗口化运行产品 UI 探针，并在 `LocalAssets/qa/verify-product-ui/` 留下实时小地图、五列背包、暂停菜单和失败界面截图。不要把本机 `.godot/` 或 QA 截图提交进仓库，也不要通过调整 PowerShell 文件枚举顺序来掩盖依赖；fresh checkout 和本机缓存热启动必须走同一验证入口。

验证入口依次执行 .NET 合成格式/媒体目录、Godot 核心逻辑、战斗/任务、投射物/背包、世界交互、type 8/10/11、无资产媒体、十二关导演、产品壳、存档/设置、确定性回放和主场景冒烟。存在完整 `LocalAssets` 时再追加真实关卡/任务绑定、真实媒体审计和 m004 高密度寻路压力测试。各套件会输出自己的当前计数；计数变化必须由功能或 fixture 变化解释，不能只改文档或放宽断言，说明文档也不复制容易过期的固定总数。

## 当前导入基线

已知版本完整导入应报告并生成：

- 34 个 IBLOCK PNG、45 个 TLG atlas、128 个 WAV；
- 980 个 SPR 预览、980 份动画清单、2,775 个动画组和 11,898 帧；
- `m000`—`m011` 十二关地形与 JSON，共 19,199 个实体；
- 每关经过数量校验的任务标记、爆破检测、出口、敌人出生和入口锚点。
- 每个实体的 `database_header_values` 必须被 `ImportedLevelData` 保留，并通过“字段为数组、各元素为整数”的校验；m000 应有 22 个 DBL 336/337 queue 1 庄稼底图和 70 个 DBL 335 queue 0 稻谷。当前检查计数以验证日志为准。

这些计数属于输入版本不变量。少一项或多一项都应当让导入失败，不应通过放宽断言掩盖格式差异。

## 导航、视线与战术感知开发工作流

导入后，每个 `LocalAssets/converted/levels/mNNN/` 应同时包含 `terrain.png`、`level.json` 和 `navigation.bin`。`navigation.bin` 是版本化的 `M37NAV1` 文件，保留 VWF L2—L5 的原始 32 位值；不应手工修改本地导入结果，应修改转换器并重新导入。

开发时必须保持下列语义边界：

1. 地图绘制用 L1，视线/直射射击用 L2，移动与寻路只以 L3 为权威障碍层；
2. L4 在十二个正式关卡中全为零，不得从零值层臆造任务触发逻辑；
3. L5 是编辑期手工移动障碍修正标记，不得在运行时直接与 L3 做 OR；
4. `0` 表示开放，`1` 表示静态障碍，`scene_index + 1000` 是 scene 占用引用；
5. 动态单位和可移除实体不得永久烘焙成静态 solid，寻路者必须能忽略自己的 scene 占用；
6. 八方向寻路必须防止对角穿墙，不能因为允许斜向就跳过贴角障碍。

Godot 端的责任分工为：

- `navigation_grid_data.gd`：`M37NAV1` 校验、只读源 L2/L3、L3 `AStarGrid2D`、附近可走目标和 L2 格线视线；
- `dynamic_occupancy_grid.gd`：玩家/敌人足印、目标预留、原子迁移、动态 L2 遮挡和阻挡重规划；
- `tactical_senses.gd`：原版等距椭圆、八方向扫描、近远识别区、军犬特殊感知、L2 遮挡和武器射程；
- `enemy_unit.gd`：巡逻、发现、追击、攻击态和最后位置搜索；
- `combat_profiles.gd` 与 `game/data/combat_profiles.json`：版本化、可校验的原版感知/武器参数。
- `combat_inventory.gd`：玩家多武器、弹匣、备弹、装填和状态快照；
- `projectile_world.gd` / `combat_projectile.gd`：type 6/7/9 世界飞行、段碰撞、落地和椭圆爆炸；
- `legacy_special_world_object.gd` / `legacy_ai_control_effect.gd`：type 8/10 世界对象与 type 11 状态的建立、推进、释放和快照；
- `world_depth.gd`：地面、正常深度、固定前景和顶层四渲染队列；
- `imported_level_data.gd`：读取并校验 `database_header_values`，不能再次在导入链中丢弃 DBL `header[0]`；
- `world_pickup_catalog.gd`、`field_pickup.gd`、`land_mine.gd`、`explosive_prop.gd`：真实场景拾取、地雷和油桶。

`combat_profiles.json` 当前的普通敌人/军犬感知、11 类攻击距离、普通伤害、连发次数、弹药物品 ID、每次消耗和末帧提交语义来自 `M1937.exe` 字段级逆向，不能随意当作手感参数改写。每个新战斗字段都必须标记 `recovered`、`recovered_with_unresolved_override` 或 `unresolved_remake_default`。当前弹匣容量、初始备弹、装填/恢复秒数，投射物速度/弧高/碰撞半径，手榴弹、地雷、油桶和拾取效果参数均是重制默认；听觉遮挡、尸体发现和更高层走廊会车尚未完成。

type 8/10/11 已由专用运行时接管：type 8 创建 actor 84 / GFL 470、消费物品 43，并由存活 faction 1 进入 32×16 椭圆触发；type 10 创建 actor 85 / GFL 900、消费物品 45，在第 100 个 world tick 爆炸；type 11 不直接结算伤害、不消费物品 99，重复施加刷新状态，超时/死亡/切关释放。活跃对象与状态均进入 `GameSessionState`。最终伤害、爆炸几何、type 11 精确语义和 180 tick 时长仍是 `unresolved_remake_default`，修改时不得把它们伪标为原版数值。详见 [原版行为取证摘要](ORIGINAL_BEHAVIOR_FORENSICS.md)。

m011 为可试玩性以 `remake_editorial` bridge 把项目 99 与 type 11 动作配给首名存活队员（当前为老赵）；原版项目 99 的取得脚本和原持有者仍未知。不要把这段发放逻辑改标为 `recovered`。

导航/感知修改的合成测试至少应覆盖：绕墙、对角禁止穿墙、多格足印、障碍目标的附近落点、L2/L3 分离、scene 忽略/清除、视锥前后边界、射程和视线组合，以及 `M37NAV1` 截断/错版本拒绝。具有本地资产时，`Verify` 还会逐关校验十二份导航文件，并以 m004 的 98 个动态角色执行高密度寻路压力回归；固定 120 个物理帧内必须有敌人实际移动，A* 请求量必须处于 20—500 次且总寻路耗时不超过 2 秒，以防“AI 未运行”的假通过、退化巡逻点或拥挤重规划重新形成请求风暴。

## 动画开发工作流

动作/方向语义集中定义在 `tools/ResourceFormats/SprAnimationSemantics.cs`，Godot 端对应实现位于 `game/scripts/imported_sprite_animation.gd`。两端都采用：

```text
serial_id = action_index * 9 + direction_index
```

共有 20 个动作槽和 9 个方向槽；方向 0 是“无”，1—8 才是可播放的八方向组。转换输出的每个 `sprite.json` 保存动作名、方向名、组参数、锚点、atlas 和逐帧路径。

`load_action_groups(preview_path, action_key)` 是通用入口。增加战斗动作时，应让角色状态机请求已有动作 key，并由明确的玩法事件切换动画；不要为每种武器重新写资源解析器。玩家与敌人的 `run`/`walk`、`stand`、对应武器攻击和 `death` 已接入。0.085 秒是基础 sprite tick，每组每帧实际保持 `0.085 × (parameters[2] + 1)` 秒；例如已导入强子的跑、走、匍匐分别保持 1、2、3 个 tick。

攻击只在**进入动作最后一帧**时复核射程/视线并提交即时命中或 type 6/7/9 投射物；投射物在实际碰撞/爆炸时再伤害。死亡动作播放一次并保持末帧。当前没有证据表明资源中存在可直接使用的独立受伤动作，因此非致命伤使用 0.18 秒闪红/硬直，这是明确的重制反馈。修改动作推进时必须覆盖“末帧前不伤害、末帧复核、单帧动作、投射物延迟结算、死亡幂等、死亡末帧保持”。

## 任务开发工作流

十二关规范化任务图位于 `game/data/missions.json`，读取和状态推进分别位于：

- `game/scripts/mission_data.gd`：schema、ID、目标、依赖和触发清单校验；
- `game/scripts/mission_state.gd`：事件匹配、计数、去重、限时、失败与胜利；
- `game/scripts/mission_runtime.gd`：当前关卡 scene 白名单、锚点类型、持久事实重放和瞬时区域语义；
- `LocalAssets/converted/levels/mNNN/level.json`：实际实体坐标和 `task_anchors`。

任务开发应保持“关卡事实”和“任务规则”分离：锚点坐标来自本地转换数据，目标依赖与胜负规则进入 `missions.json`，战斗/交互系统只发送规范化事件。新事件至少需要覆盖：

1. 匹配与不匹配 payload；
2. `unique_by` 重复去除；
3. 依赖未完成时不推进；
4. 限时或角色损失失败；
5. 全部必需目标完成后的胜利。

世界系统不得直接调用 `MissionState.record_event()`；必须通过 `MissionRuntime.publish_world_event()`。运行时会确认 scene 同时属于已加载关卡和当前任务 `scene_bindings`，并拒绝缺失或未绑定引用。救援、拾取、任务角色击毙、剧情锚点、爆破/占点、清敌、撤离、限时和角色损失已经接线；持久事实会去重并在前置依赖完成后重放，出口则保持瞬时区域判定。`mission_direction.json` 已提供十二关对白、镜头请求、教程、AI 和难度第一版，但除恢复的 objective/scene 引用外均为 `remake_editorial`，仍需要逐关完整通关与原版录像校准。详见 [任务恢复说明](MISSION_RECOVERY.md)与[十二关导演说明](MISSION_DIRECTION.md)。

爆破关必须显式提供 `charge_policy`，并将来源状态保持为 `remake_policy_from_recovered_map_inventory`。m001/m004/m011 使用 `preplanted`；m002/m003/m008/m009 使用 `inventory_required`。验证器会将 `target_count` 与 explosion scene 绑定、`map_pickup_count` 与真实 DBL 998 逐关计数交叉核对，并拒绝物资不足的消耗模式。实现时必须先成功发布世界事件，再提交背包扣除；不要把检查和扣除顺序颠倒，也不要让预置目标因背包恰好有炸药而消费物品。

m004 的计划书携带者已由物品 101/VWF 携带记录定案为 scene 2637；m009 默认修复原版未使用的全关 faction 1 扫描，要求两份文件、全关清敌和四处爆破；m010 的四个区域由老赵、强子、大牛、古明在 128 像素内分别同时占据，不按 `E`、不累计、不要求停留或先清敌。不要在新脚本中重新引入旧候选或临时近似。

任务媒体必须写入可选 `media_cues`，不得在关卡脚本里散落硬编码弹窗。只允许 `on_start`、`on_objective`、`on_story_anchor`、`on_victory` 四段和 `audio`、`dialogue`、`movie`、`ending` 四类 cue；每项必须标 `recovered_media_mapping`、`remake_editorial` 或 `mixed`。目标键必须引用真实 objective ID，剧情锚点键必须同时存在于 scene 绑定和 `story_anchor_reached` 目标。当前基线包括 m000 教程/彭鑫营救确认、m006 接头提示和 m011 结局；重复持久剧情事实不能重播模态媒体。

`runtime_state_snapshot.gd` 为合成战斗命令和十二关任务事件生成规范化 SHA-256 哈希链，并执行两遍比较。它验证状态确定性，不录制鼠标/键盘、物理帧或渲染时序；涉及长期稳定性时仍需另建真实输入回放和帧时间/内存基线。

## 产品壳、设置与存档开发工作流

`game_shell.gd` 管理 `Esc` 菜单、`F1` 指南、`A`/`W` 276×421 五列背包、十槽选择器、设置和任务失败灰化层；`Esc` 在松开时提交，菜单内右键也在松开时返回上一级。世界右键只负责拖框，不提交移动/攻击；世界左键提交选择、移动、攻击和使用，左 `Ctrl`/`↑` 按住时进入强制目标路径。这些模态层暂停 SceneTree，失败层不能“继续”或保存，只能重玩、读取或退出。`M` 地图改为独立右下角 HUD，显示时不暂停战斗；`tactical_map_view.gd` 只消费主场景提供的原版逐关静态图、敌我/任务标记和镜头矩形，不自行推断任务规则。动态红点、镜头框和点击卷屏是复刻增强。

`game_settings.gd` 管理版本化 `user://settings.json`。当前菜单公开全屏、主音量/音乐/音效/语音、字幕、任务简报、鼠标边缘卷屏和按键重映射；全屏策略固定为当前桌面分辨率。按键冲突采用动作间交换，支持恢复默认值。底层 schema 仍预留无边框/自定义分辨率、静音和提示类别；没有菜单入口的字段不能写成玩家已经可配置。设置变更后应立即应用并原子保存。

`game_save_store.gd` 管理 `user://saves/<slot>.json`，`game_session_state.gd` 负责主场景可变状态的捕获/恢复。菜单公开 `slot_1`—`slot_10` 十个手动槽并要求二次确认覆盖；菜单读取始终打开选择器，`Ctrl+F5` 写 `quick`，只有 `Ctrl+F9` 按保存时间读取最新有效槽，胜利写 `autosave`。任务失败时禁止覆盖有效存档。存档边界包括：

- 关卡、任务耗时、完成/进度/去重、失败和持久事实；
- 队员/敌人/护送角色的位置、阵营、生命/死亡、选择、背包/武器/弹药，以及 AI 巡逻/搜索和护送关系；
- 已激活任务 scene、公共物品、剩余拾取物、可爆物状态、任务掉落、地雷、type 8/10 世界对象、type 11 状态和未结算投射物；
- 已掩埋敌人的 scene 索引，读取后保持隐藏；
- 十二关导演节拍/教程门控/持久事件/计时、AI 姿态/增援预算/命令序号；
- 镜头和战役完成/解锁进度。

资源、纹理、导航缓存、节点/信号引用、当前动画精确帧和尚未提交的移动/直接攻击命令不进入 JSON。读取必须先按 `level_id` 重建静态关卡，再调用 `apply_after_level_loaded()` 恢复可变状态；角色从安全状态继续，而已经生成的在途投射物继续其生命周期。

`atomic_json_store.gd` 的顺序必须保持“同目录临时文件写入 → 关闭并重新读取校验 → 有效旧主文件轮换为 `.bak` → 安装新主文件”。损坏主文件隔离为 `.corrupt`，不得挤掉有效备份；读取主文件失败时应回退 `.bak`。任何 schema 变更都要增加迁移和损坏/备份测试，禁止靠放宽 JSON 校验兼容旧档。

## 媒体开发工作流

完整导入会生成 `LocalAssets/converted/legacy-media-catalog.json`，记录十二张简报、十二张目标图、三张结局图、128 个 WAV 和五段已审计旧视频的元数据。原 WAV、PNG、SVT/VWF 媒体及转码 OGV 均留在被忽略的 `LocalAssets`，不能提交到 Git。

`legacy_media_catalog.gd` 负责安全解析本地/回退元数据，`media_director.gd` 负责简报、声音、Theora 视频、字幕和文字/可选语音对白。主场景已经在切关时显示简报，并把攻击、投射物命中、爆炸、警报、角色选择/确认、死亡和 UI 事件映射到原 WAV；任务运行时进一步按 `media_cues` 在开场、目标、剧情锚点和胜利时调用同一导演。独立音乐/环境声播放器、专用语音/对白播放器和固定 8 路 SFX 池分别路由到 `Music`、`Voice`、`Sfx`，影片播放器音轨同样进入 `Music`。简报、对白、视频或结局图打开时，导演暂停任务、AI 和战斗；模态媒体中的 `Esc` 在松开时关闭/跳过，Enter/Space 继续。十二关补写对白与镜头请求已进入 `MissionDirectionRuntime`，但均保留 `remake_editorial` 来源；视频和经原版逐字核对的对白/镜头仍需继续编排，不能从 WAV 文件名猜造剧情。

## Windows 本地试玩包

导入本地资源后，运行 `tools/Build-Playable.cmd` 会在已忽略的 `LocalBuild/1937Remake/` 生成 `Play-1937-Remake.cmd`。默认使用目录联接复用 `LocalAssets`；需要复制到另一台已获授权的电脑时使用 `-AssetMode Copy`。构建会固定 Godot 4.7.1、生成 release 导出或 PCK 回退包，并分别执行 PCK 路径和最终 `1937Remake.exe` 的 headless 冒烟测试。详细目录结构、切关参数和导出模板行为见 [Windows 本地试玩包](PLAYABLE_BUILD.md)。

## IDA 9.1 的 IDAPython 致命初始化错误

### 症状

启动 IDA 时出现：

```text
Unexpected fatal error while initializing Python runtime.
Please run idapyswitch to confirm or change the used Python runtime
```

这通常不是目标 EXE 的问题，而是 IDA 记录的 `Python3TargetDLL` 已不存在、位数不匹配，或仍指向旧 Python（本机故障时为 Python 3.8.10）。在修复前，不应继续依赖 IDAPython 自动分析结果。

### 已验证修复步骤

1. 关闭所有 IDA 进程。
2. 准备与 IDA 同为 x64 的完整 CPython 安装。不要选择虚拟环境里的 `python.exe`；`idapyswitch` 需要基础安装目录中的 `python3xx.dll`。
3. 查看当前配置：

```powershell
Get-ItemProperty -Path 'HKCU:\Software\Hex-Rays\IDA' -Name Python3TargetDLL
```

4. 使用 IDA 9.1 自带的切换器写入正确 DLL。以下是本机已经验证通过的命令：

```powershell
& 'D:\IDA Professional 9.1\idapyswitch.exe' -s `
  'D:\pyenv\pyenv-win\versions\3.13.2\python313.dll'
```

路径应替换为本机实际安装位置。不要从网上单独下载一个 DLL；它必须与完整 Python runtime 和 IDA 架构匹配。

5. 再次核对注册表：

```powershell
Get-ItemPropertyValue `
  -Path 'HKCU:\Software\Hex-Rays\IDA' `
  -Name Python3TargetDLL
```

6. 启动 IDA 9.1，在 Python console 中运行：

```python
import sys, ida_kernwin, ida_pro
print(sys.version)
```

本机最终结果为 CPython 3.13.2 x64，IDA 9.1 能正常导入 `ida_kernwin` 和 `ida_pro`。

### 可选的无界面冒烟测试

建立一个只包含以下内容的临时 `ida-python-smoke.py`：

```python
import sys
import ida_kernwin
import ida_pro

ida_kernwin.msg("IDAPYTHON_SMOKE_OK %s\n" % sys.version.replace("\n", " "))
ida_pro.qexit(0)
```

然后用 IDA 的文本模式执行。临时脚本、日志和 `.i64` 必须保存在仓库外的工作目录：

```powershell
$idaText = 'D:\IDA Professional 9.1\idat.exe'
$smokeRoot = 'E:\1937\ida-python-smoke'
New-Item -ItemType Directory -Force -Path $smokeRoot | Out-Null
Copy-Item -LiteralPath 'E:\1937\1937tzb_1229\M1937.exe' `
  -Destination (Join-Path $smokeRoot 'm1937-smoke.exe') -Force

$target = Join-Path $smokeRoot 'm1937-smoke.exe'
$script = 'E:\1937\ida-python-smoke.py'
$log = Join-Path $smokeRoot 'ida-python.log'

& $idaText -A "-L$log" "-S$script" $target
Select-String -LiteralPath $log -Pattern 'IDAPYTHON_SMOKE_OK'
```

出现 `IDAPYTHON_SMOKE_OK` 且进程退出码为 0，才说明 core IDAPython 初始化成功。

### IDA 9.0 旧插件提示

本机 IDA 9.0 在切换到 Python 3.13 后也能通过 core smoke test，但部分第三方旧插件会报 `IdaPluginForm` 等 API 兼容错误。这与 Python runtime 致命初始化是两个问题。当前分析统一使用 IDA 9.1；如果 core smoke test 已通过而仍有插件异常，应更新或暂时禁用对应第三方插件，不要反复切换 Python DLL。

## 逆向分析的仓库边界

- 原版 EXE、GFL、VWF、DBL、SLF、IDA 数据库、反编译日志和导出图必须留在仓库外；
- 仓库只记录字段边界、可验证算法、合成 fixture 和重新实现的源码；
- 不复制原程序函数体或大段反编译代码；
- 每个新结论应尽量由至少两类证据支持，例如“文件全量审计 + 原程序读取路径”或“合成测试 + 实际渲染对齐”；
- 不确定的字段继续用中性名称，直到能由多份资源或运行时行为确认。

本轮 IDA 核对确认了 VWF 第一平面中高 16 位 tile-group ID 的处理：0 不绘制，1—45 作为 DBL TLG 条目的一基序号。后续层名表和引用路径核对还确认了 L2 视线/射击遮挡、L3 移动/八方向寻路权威层、L4 正式关卡全零和 L5 编辑期手工修正标记。这些结论已落实为中间格式、运行时核心和合成测试，不要求构建或运行复刻时安装 IDA。
