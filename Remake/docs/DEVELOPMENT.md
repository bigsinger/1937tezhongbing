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

# 发布前 30 分钟、三轮十二关稳定性与存读档测试
.\tools\Run-StabilitySoak.ps1 `
  -GodotExecutable C:\path\to\Godot_v4.7.1-stable_win64_console.exe `
  -DurationSeconds 1800 -Passes 3

# 第二轮分层门禁：日常、真实内容、完整发布
.\tools\Invoke-RemakeGate.ps1 -Tier Quick `
  -GodotExecutable C:\path\to\Godot_v4.7.1-stable_win64_console.exe
.\tools\Invoke-RemakeGate.ps1 -Tier Content `
  -GodotExecutable C:\path\to\Godot_v4.7.1-stable_win64_console.exe
.\tools\Invoke-RemakeGate.ps1 -Tier Release -Resume `
  -GodotExecutable C:\path\to\Godot_v4.7.1-stable_win64_console.exe
```

`Quick` 只使用仓库中的源码和合成 fixture；`Content` 增加合法本地十二关资源、
产品输入和 UI；`Release` 再执行完整 Verify、十分钟严格性能和三十分钟稳定性。
`-Resume` 只复用输入摘要相同且报告完整的成功步骤，源码或参数变化会自动令旧步骤
失效，不能用残留报告冒充本次通过。

长测完整报告和日志留在忽略的 `LocalAssets/qa/stability-soak/`；确认同一实现
通过后，才把去除机器路径的摘要更新到
`validation/baselines/remake/stability-soak-30-minute-v1.json`。普通
`Verify.ps1` 会调用 `Test-StabilityBaseline.ps1`，拒绝少于 30 分钟、少于
三轮、未覆盖十二关、存读档不足、内存增长超限或控制桌面鼠标的基线。性能和
稳定性脚本每次启动都会先移除固定名称的旧输出，不能用残留报告伪造新结果。

如果只做开源仓库验证而没有原版目录，直接运行 `Verify.cmd` 即可；所有自动测试都使用人工合成数据。

### fresh checkout 的 Godot 校验顺序

Godot 的 `class_name` 类型注册缓存位于未纳入 Git 的 `.godot/global_script_class_cache.cfg`。如果 CI 在全新检出中直接按文件枚举顺序执行每个 `.gd` 的 `--check-only`，依赖 `NavigationGridData` 等全局类的脚本可能先于类型注册而报 `Identifier not found`，即使同一提交在打开过编辑器的开发机上能够通过。

`tools/Verify.ps1` 现在固定先运行：

```powershell
godot --headless --editor --path .\game --quit-after 2
```

由 Godot 自己扫描项目并生成类缓存，再逐脚本执行 `--check-only`、逻辑测试和场景冒烟测试。存在完整 `LocalAssets` 时，验证入口还会窗口化运行产品 UI 探针和 48 秒十二关性能冒烟，并在 `LocalAssets/qa/` 留下报告与 UI 截图。不要把本机 `.godot/`、原始性能日志或 QA 截图提交进仓库，也不要通过调整 PowerShell 文件枚举顺序来掩盖依赖；fresh checkout 和本机缓存热启动必须走同一验证入口。

验证入口依次执行 .NET 合成格式/媒体目录、Godot 核心逻辑、战斗/任务、投射物/背包、世界交互、type 8/10/11、无资产媒体、十二关导演、产品壳、存档/设置、确定性回放和主场景冒烟。存在完整 `LocalAssets` 时，先执行 `tools/Build-LevelFidelityBaselines.ps1 -Verify`，把当前稳定 MOD 的十二个 VWF、转换地形/导航 SHA-256、19,199 个实体结构和 258 个关键 scene 与提交基线逐项比较；随后追加真实关卡/任务绑定、真实媒体审计、`real_mission_world_loop_test.gd` 十二关世界动作胜利/逐必需目标物理磁盘存读闭环，以及 `real_mission_failure_matrix_test.gd` 的逐必要队员、逐护送 scene、精确限时和规则分支隔离失败矩阵。真实资源门禁还会逐关运行 `m000`—`m011` 的 `native-required-player-failure-v1`：用 Remake 的 `take_damage()` 产品入口重放原版 `sub_458700 → sub_405410 → result 2` 证据，并通过专用比较器每关执行 26 项死亡与任务失败语义核对。最后再运行 m004 高密度寻路压力测试和真实窗口短性能门禁。这些闭环只调用营救、地面拾取、战斗伤害、任务交互、引爆、占区、出口和任务计时等产品入口，禁止直接调用 `MissionRuntime.publish_world_event()` 伪造进度或失败。各套件会输出自己的当前计数；计数变化必须由功能或 fixture 变化解释，不能只改文档或放宽断言，说明文档也不复制容易过期的固定总数。

十二关“自然失败”和“作弊胜利”探针支持 `-StartLevel` / `-EndLevel`
（0—11）断点执行。它们只向 Godot 目标视口注入事件，禁止系统鼠标、系统键盘、
全局焦点调用和人工通关。长验收若被外层时限中断，应从未完成关卡续跑，不能改用
前台窗口操作代替确定性证据。

`tests/real_input_campaign_journey_test.gd` 是十二关统一的产品输入回归。它不直接调用
菜单、存档或命令函数，而是向 Godot 目标视口发送 648 个键盘/鼠标事件，逐关验证
F2 镜头定位、地面移动、R/C、W/A、M、F1、Esc、S、普通攻击、B 的 101 tick
掩埋、物理磁盘快速存读、主要失败以及键盘重玩。测试使用进程唯一的
`user://qa-real-input-campaign/...` 存档目录，结束后清理；不会捕获、锁定、移动或
裁剪桌面鼠标。

`tests/main_input_harness.gd` 是供其他测试实例化的 Main 派生夹具，不是
`SceneTree`/`MainLoop` 入口。禁止把它直接传给 `godot --script`；直接执行会由
Godot 正确拒绝并显示 “doesn't inherit from SceneTree or MainLoop”。需要验证它时
运行引用它的 `real_input_*`、`parity_runtime_probe.gd` 或完整 `Verify.ps1`。

稳定 MOD 侧只在需要补充原生行为证据时运行进程私有的单动作探针：每次加载
指定关卡、提交一个预先声明的 DirectInput 动作、保存遥测并立即退出。禁止把
人工通关、长时间前台游玩或系统级键鼠控制当作开发门禁；任务可达性由寻路、
必需目标、事件闭环、失败矩阵和物理存读档测试分别证明。

`tools/Run-CampaignPerformance.ps1` 是发布性能入口。它启动真实的
1920×1080 Godot 窗口、关闭 VSync、限制 60 FPS，并只向目标视口循环提交
选人、移动、姿态、背包、武器、地图、视线、菜单和镜头事件。它不会调用任何
系统鼠标捕获、裁剪、移动或桌面坐标 API。发布候选应在电脑空闲时运行完整双轮：

```powershell
.\tools\Run-CampaignPerformance.ps1 `
  -GodotExecutable D:\Godot\Godot_v4.7.1-stable_win64_console.exe `
  -DurationSeconds 600 -Passes 2
```

门禁要求总体 P95 ≤ 18.5 ms、逐关 P95 ≤ 19.5 ms、足量样本下 P99 ≤ 25 ms、
稳态帧零个无法解释的 >50 ms、两轮都发生真实敌军移动，且第二轮静态内存净增长
不超过 8 MiB。Main 脚本和物理 CPU P95 分别限制为 18/15 ms，避免只用呈现帧
掩盖模拟尖峰。
提交的参考结果在
`validation/baselines/remake/campaign-performance-1920x1080-v1.json`；
原始日志和本机绝对路径报告只留在被忽略的 `LocalAssets/qa/`。

`save_settings_test.gd` 还必须用物理 `user://` 文件覆盖全部存档版本边界：
schema 0—3 迁移、schema 4 规范化及运行时/内容/工作区身份、模拟 tick、命令序列、
预约、AI 黑板、战术队列、损坏主文件回退
`.bak`、未来/过旧 schema
主文件与备份逐字节不变，以及十二次产品胜利后的完成度/解锁前沿磁盘回读。
新增 schema 时必须先更新 `GameSaveStore.migration_policy()` 和这些用例；
不允许仅提高版本号后把旧文件交给通用“损坏文件隔离”路径。

30 分钟 Release 稳定性在 headless 后端启用显式的
`qa_simulation_only_world_visuals` 测试策略。它仍构造所有任务、AI、动态角色、
导航、门、拾取和存读档状态，但跳过在 64×64 无显示后端反复解码地形及创建不可见
的纯装饰 CanvasItem。该开关只在同时满足 headless 与 `--stability-mode` 时启用，
不进入设置或存档；普通窗口、编辑器和性能探针始终使用完整视觉世界。长测脚本与
版本基线会断言该策略状态，防止测试通道意外污染产品路径。等待渲染同步时使用有界
帧循环，不能直接无限等待 `RenderingServer.frame_post_draw`。

可单独重放某一关：

```powershell
D:\Godot\Godot_v4.7.1-stable_win64_console.exe --headless `
  --path .\game `
  --script res://tests/real_input_campaign_journey_test.gd -- `
  --skip-briefing --journey-level=m010
```

任务世界闭环也支持只跑一关，适合验证救援、拾取、爆破、占点和撤离等短行为，
避免把不可重复的自动整关通关当作开发门禁：

```powershell
D:\Godot\Godot_v4.7.1-stable_win64_console.exe --headless `
  --path .\game `
  --script res://tests/real_mission_world_loop_test.gd -- `
  --skip-briefing --world-loop-level=m010
```

该入口只向 Godot 目标视口发送键鼠事件，不捕获、移动或限制系统鼠标。省略
`--world-loop-level` 时才执行十二关完整回归；原版与 Remake 的真人整关通关
只属于发布验收，不应由自动机器人代替。

## 当前导入基线

已知版本完整导入应报告并生成：

- 34 个 IBLOCK PNG、45 个 TLG atlas、128 个 WAV；
- 980 个 SPR 预览、980 份动画清单、2,775 个动画组和 11,898 帧；
- 所有动画清单均为 schema 4；其中 1,137 个组的一基 SLF 引用必须唯一解析为 52 个 GFL WAV 绑定；
- `m000`—`m011` 十二关地形与 JSON，共 19,199 个实体；
- 每关经过数量校验的任务标记、爆破检测、出口、敌人出生和入口锚点。
- 每个实体的 `database_header_values` 必须被 `ImportedLevelData` 保留，并通过“字段为数组、各元素为整数”的校验；m000 应有 22 个 DBL 336/337 queue 1 庄稼底图和 70 个 DBL 335 queue 0 稻谷。当前检查计数以验证日志为准。
- `game/data/level_fidelity_baselines.json` 必须由 `tools/Build-LevelFidelityBaselines.ps1` 从上述完整输入生成；修改转换器后先重建并审查 diff，不能手工放宽哈希或数量。

这些计数属于输入版本不变量。少一项或多一项都应当让导入失败，不应通过放宽断言掩盖格式差异。

## 导航、视线与战术感知开发工作流

导入后，每个 `LocalAssets/converted/levels/mNNN/` 应同时包含 `terrain.png`、`level.json` 和 `navigation.bin`。`navigation.bin` 是版本化的 `M37NAV1` 文件，保留 VWF L2—L5 的原始 32 位值；不应手工修改本地导入结果，应修改转换器并重新导入。

开发时必须保持下列语义边界：

1. 地图绘制用 L1，视线/直射射击用 L2，移动与寻路只以 L3 为权威障碍层；
2. L4 在十二个正式关卡中全为零，不得从零值层臆造任务触发逻辑；
3. L5 是编辑期手工移动障碍修正标记，不得在运行时直接与 L3 做 OR；
4. `0` 表示开放，`1` 表示静态障碍，`scene_index + 1000` 是 scene 占用引用；
5. 动态单位和可移除实体不得永久烘焙成静态 solid，寻路者必须能忽略自己的 scene 占用；
6. 原版路线选择必须保留反向搜索、平方像素启发式、八方向展开顺序和开放表
   平局行为；动态多格足印与同帧角色迁移仍必须执行防穿墙安全检查。

Godot 端的责任分工为：

- `navigation_grid_data.gd`：`M37NAV1` 校验、只读源 L2/L3、以
  `AStarGrid2D` 保存 solidity、执行 `sub_45F680` 家族的原版反向寻路、
  静态连通分量目标重定向、门格增量合并、附近可走目标和 L2 格线视线；
- `dynamic_occupancy_grid.gd`：玩家/敌人足印、空间索引、目标预留、原子迁移、
  同帧对角交叉保护、稀疏图实时规划与密集图按解析终点连续预热的巡逻路线/
  后缀/静态失败/验证后平移复用、动态不可达预检、运行时可达多格足印的
  批量分阶段预计算与紧凑字节净空缓存、动态 L2 遮挡、静态连通通道的延迟
  终点、确定性会车优先级和阻挡重规划；
- `tactical_senses.gd`：原版等距椭圆、八方向扫描、近远识别区、军犬特殊感知、L2 遮挡和武器射程；
- `enemy_unit.gd`：巡逻、发现、追击、攻击态、最后位置搜索，以及按导航格/
  朝向缓存的红绿空心战术视线扇形；权威感知仍走实时 L2，不由显示缓存决定；
- `combat_profiles.gd` 与 `game/data/combat_profiles.json`：版本化、可校验的原版感知/武器参数。
- `combat_inventory.gd`：原版 mode 0/1/2 直接数量、多武器、旧档迁移和状态快照；
- `original_initial_weapon_inventory.gd`：按关卡和 scene ID 读取 660 名精确
  角色的 761 个有序开局武器条目和 67 个空容器；27 名玩家/83 条仍作为
  玩家身份兼容子集，敌军精确持有但按原规则不扣数量；
- `backpack_inventory.gd`：独立实现 actor `+0x228` 的有序物品容器、
  mode 0/1/2、强制丢弃和存档快照；
- `original_initial_item_inventory.gd`：按关卡和 scene ID 读取 660 个
  精确动态角色的开局背包；物品效果证据见
  [原版角色物品背包恢复](ORIGINAL_ITEM_INVENTORY.md)；
- `original_runtime_actor_catalog.gd`：读取 772 个运行时角色身份及阵营覆盖；
- `campaign_progress.gd`：十二个正式关卡的唯一完成度/顺序解锁状态机；
  MOD/命令行自由选关不写进度，只有产品胜利入口调用 `record_victory()`；
- `campaign_level_selector.gd`：启动页和 `Esc` 菜单共用的 3×4 原生关卡
  选择器；全部正式路由可用，同时只读展示当前关、完成度与顺序前沿；
- `game_save_store.gd`：schema 0—3→4 内存迁移、运行时/内容/工作区身份、
  模拟 tick/命令/预约/AI 黑板/战术队列、轻量槽索引、当前格式规范化、
  原子写入与未来/过旧 schema 的拒绝且不改文件策略；
- `legacy_projectile_rules.gd` / `legacy_combat_rules.gd` /
  `projectile_world.gd` / `combat_projectile.gd`：type 1/2/3/6/7/9 的
  原版整数 Bresenham 路径、逐 world-tick 步长、目标格门、机枪角度散布、
  SPR primary/tertiary 发射锚点、L3→L2 碰撞、actor 60 命中火花、
  手榴弹抛物线及终点 actor 61；
- `legacy_special_world_object.gd` / `legacy_explosion_effect.gd` / `legacy_explosion_visual_rules.gd` / `legacy_ai_control_effect.gd`：type 8/10 actor 84/85 部署物、独立 actor 62 主体/原粒子计划与 type 11 状态的建立、推进、释放和快照；
- `world_depth.gd`：地面、正常深度、固定前景和顶层四渲染队列；
- `imported_level_data.gd`：读取并校验 `database_header_values`，不能再次在导入链中丢弃 DBL `header[0]`；
- `world_pickup_catalog.gd`、`field_pickup.gd`、`explosive_prop.gd`：真实场景拾取和 actor 53 汽油桶；地雷只由 type 8 / actor 84 专用运行时承担。

`combat_profiles.json` 当前的普通敌人/军犬感知、11 类攻击距离、普通伤害、直接 actor 命中数、坐标弹道数、弹药物品 ID、每次消耗和末帧提交语义来自 `M1937.exe` 字段级逆向，不能随意当作手感参数改写。`LegacyCombatRules` 固定 `sub_456DF0` 的步枪 attacker runtime type 1（16 点）、匕首 attacker runtime type 56（1 点）、机枪直接 actor 只结算一次、末帧命中提交后同一次更新恢复待机且没有独立恢复计时，以及 `sub_458700` 的八类低于 32 伤害免疫；不得重新把机枪三条坐标散布弹道解释为同一 actor 三次扣血。每个新战斗字段都必须标记 `recovered`、`recovered_with_unresolved_override` 或 `unresolved_remake_default`。原版已确认不存在弹匣/备弹/装填抽象；正式关卡必须使用 `original_initial_weapon_inventory.json` 的直接数量和模式，profile 中旧字段只供 schema 1 迁移及合成测试兼容。十类场景拾取的 DBL `header[2]` 物品 ID、`sub_45AE10` 容器/mode 和 `sub_453F70` 单件数量已经恢复；type 1/2/3/6/7/9 的 delivery mode、逐 tick 步长、目标格门、机枪散布、actor/GFL、碰撞顺序、伤害、actor 60 火花、手榴弹抛物线/终点爆炸和 SPR 发射锚点也已恢复，不再使用速度、弧高、碰撞半径或落地延时等重制参数。拾取点击与敌军取物的 32×16 邻格、朝向扇区及 L2 遮挡也已恢复；物品 33/48/49/52/82/83 另有六组原版/Remake 零差异轨迹。汽油桶的 35 条 actor 53 / 8 HP 状态、任意生命变化触发、效果类型 5→actor 62 以及完整爆炸参数已经恢复；`sub_4554A0` 已确认爆炸伤害不查询地形视线遮挡并已按此恢复，仍待恢复的是 AI 战术层更多包抄/让路仲裁。普通警戒听觉已确认不做障碍遮挡，尸体发现也已进入原版生命周期。

type 8/10/11 已由专用运行时接管：type 8 创建 actor 84 / GFL 470、消费物品 43，并由存活 faction 1 进入 32×16 椭圆触发；type 10 创建 actor 85 / GFL 900、消费物品 45，在第 100 个 world tick 爆炸。actor 84/85 先消费四次成功局内动态工厂取数；触发后另建 actor 62，再消费原部署物四次派生/基类析构取数。`0x5BBBC` 已由原版进程短探针校正为 SAV actor 朝向恢复的独立取数，不再并入普通创建。actor 62 的主爆炸在 128×64 等距椭圆内造成 128 伤害并传播 800 半径警报，另按运行时 actor type 执行两组已恢复的 128 伤害带。效果 11/15 会按逐关原版启动检查点继续的 MSVCRT LCG 尝试 1—2 个 64×32 散布粒子，首匹配 GFL 动画完整播放 5 轮并在 90/150 tick 清理；全局随机状态进入 `GameSessionState`。type 11 不直接结算伤害、不消费物品 99；它设置目标 `+656/+0x290` 为注意力保持，暂停普通空闲移动并面向专用来源，来源开始移动或目标进入战斗状态时释放，不存在 180 tick 超时。活跃部署物、独立爆炸 actor 与控制状态均进入 `GameSessionState`。十二关启动流、首个完整更新轮次的 769 条调用和首批 AI/物品消费者已恢复；首轮观察门结果和 76 名绑定角色的路线等待、追击、候选扫描、阻塞重试及次级搜索更新后状态会应用到精确 runtime actor。m000 的 710 轮时间戳基线进一步证明观察门和主候选扫描按 59.930491 Hz 角色更新持续消费，Remake 已按 60 Hz 接线并保存相位。十二关无输入窗口现固定 5,845 个完整轮次；m000 另固定 413 轮、24,586 次调用的短移动输入分支。移动确认不在输入处理函数立即抽取随机数，而是排入被选 actor 18 的待确认队列，在它自己的更新槽调用 `0x5D7CF`；分支 ID、活动状态、待确认数量和序号均随 `GameSessionState` 保存。六条单动作/边界记录又证明随机选人、攻击、世界拾取、B 掩埋和背包丢弃沿用相同角色更新槽，S 视线不消费随机数；m000 存读档记录把原版完整世界重建抖动与现代存档的精确共享流恢复明确分开。机器目录会核对原记录 SHA-256、SDK 调用点和角色身份；证据窗口外长时输入仍不得从这些短分支外推。详见 [原版行为取证摘要](ORIGINAL_BEHAVIOR_FORENSICS.md)和[原版全局随机流恢复](ORIGINAL_CRT_RANDOM_STREAM.md)。

m011 不再编辑性发放项目 99。项目 99 已确认由古明使用军服 54、在严格
第 101 个角色 tick 变为 type 91/GFL 272 时自动加入；不得把它加入任何
正式关卡开局配置，只能由该换装事件取得。

古明 type 10/91 的换装和恢复、m007 铁蛋 type 9 的取物暴露/恢复都由
`sub_454960` 的 59.930 Hz actor update 驱动，禁止重新使用 30 Hz 近似。
type 9 只在物理取物提交后调用目击扫描；测试不得把“接近物品”或普通攻击
伪造成暴露。观察者接收目标/容器坐标而不是活目标，连续 101 个无观察更新才
恢复 faction 1，阵营与共享 `+0x294/+0x298/+0x29C` 计数必须进入局内存档。

导航/感知修改的合成测试至少应覆盖：原版反向搜索平局、等成本障碍阶梯、
绕墙、不可达目标的同连通分量落点、动态足印防穿墙、多格足印、障碍目标的附近
落点、空间索引跨格邻居、同帧对角交换、巡逻精确/后缀/不可达负缓存、门增量开闭、
静态断路反例、双角色窄通道换位、L2/L3 分离、scene 忽略/清除、视锥前后边界、战术扇形缓存、射程和视线组合，
以及 `M37NAV1` 截断/错版本拒绝。具有本地资产时，`Verify` 还会逐关校验
十二份导航文件、117,112 个静态 Layer 3 格与 768 个活动角色源足印，以 m004 执行高密度动态角色寻路压力回归，并运行十二关真实
窗口性能冒烟；固定 120 个物理帧内必须有敌人实际移动，A* 请求量必须处于
20—500 次且总寻路耗时不超过 2 秒，以防“AI 未运行”的假通过、退化巡逻点
或拥挤重规划重新形成请求风暴。m000 的无遮挡命令、树边障碍、54 敌军巡逻
运动学和自然接敌四条稳定 MOD 轨迹同样属于严格门禁；另有覆盖 m000—m011
全部 656 名巡逻敌军的双运行时运动学门禁，以及十二关逐关玩家跨障碍往返、
目标替换、最终朝向和每 5 帧实际轨迹折线的 4 像素门禁。

## 动画开发工作流

动作/方向语义集中定义在 `tools/ResourceFormats/SprAnimationSemantics.cs`，Godot 端对应实现位于 `game/scripts/imported_sprite_animation.gd`。两端都采用：

```text
serial_id = action_index * 9 + direction_index
```

共有 20 个动作槽和 9 个方向槽；方向 0 是“无”，1—8 才是可播放的八方向组。转换输出的每个 `sprite.json` 保存动作名、方向名、组参数、锚点、atlas 和逐帧路径。

`load_action_groups(preview_path, action_key)` 是通用入口。正式关卡实体使用可保留空方向槽的 sparse 模式：204 套角色动作具有完整八方向，轿车/卡车另有 8 套原生四方向动作；请求不存在的 serial 时保留当前动作和朝向，与 `IEngineSprite::SetCurrentSerial` 的失败路径一致，不能擅自镜像或用“最近方向”补图。增加战斗动作时，应让角色状态机请求已有动作 key，并由明确的玩法事件切换动画；不要为每种武器重新写资源解析器。玩家与敌人的 `run`/`walk`、`stand`、对应武器攻击和 `death` 已接入。加载器把同一路径的 `sprite.json` 作为不可变文档在一次关卡重建内只解析一次；`Main` 在重建开始和完成时清空文档缓存，动作纹理继续使用会话缓存。修改运行期生成的测试清单时必须先调用 `clear_manifest_document_cache()`，不得依赖陈旧文档。0.085 秒是基础 sprite tick，每组每帧实际保持 `0.085 × (parameters[2] + 1)` 秒；例如已导入强子的跑、走、匍匐分别保持 1、2、3 个 tick。真实资源门禁把 772 名运行时角色关联到 39 个原 SPR，并逐方向解码 212 套动作、1,664 组、9,896 帧，核对 serial、源组顺序、三组 triplet、绘制锚点、帧保持和帧数。

SPR 清单必须使用 schema 4：文件 triplet 1/2/3 分别对应
primary/tertiary/secondary，并把 `parameters[8]` 的一基 SLF 序号解析为
唯一的 GFL WAV 索引；schema 1/2 只能由加载器迁移，schema 3 只能作为关闭
精确动画音效的旧本地导入兼容，调用处不得猜测交换或按文件名猜声音。secondary
的第 0/2 分量是每个 60 Hz actor tick 的 X/Y 上限，
run 再乘 3。每 tick 最多推进一个路径点并丢弃该 tick 未用余量；但若本次
2/1 分量恰好到点，必须同 tick 推进游标，不能因浮点比较多停一帧。更改这些
规则必须同时通过组件边界测试和四条 m000 MOD 差分轨迹。

AI 待机动作必须遵守 `sub_4587E0/sub_458A80`：角色逻辑计数的首轮上限为
`rand()%160`，后续为 `rand()%160+40`；整数计数处于上限中间三分之一时
请求 action 2 `stand_action`，其余区间请求 action 1 `stand`。当前实现从
772 名活动角色的原版构造值取得首轮上限，后续重置消费唯一可存档的进程级
MSVCRT 流；不得重新引入逐 scene 私有流。真实资源门禁固定 30 套
`stand_action`、240 个方向和 1,912 帧；attack type 8/10 则由已恢复的武器
映射请求 action 8 `active_action`，唯一一套角色资源共 8 个方向、72 帧。

攻击只在**进入动作最后一帧**时复核射程/视线并提交相邻格直接命中或 type 1/2/3/6/7/9 坐标投射物；投射物在实际碰撞/爆炸时再伤害。死亡动作播放一次并保持末帧。`sub_458700` 的非致命路径只执行免疫门、扣血和零值死亡分派，没有命令、动作或反馈计时写入；因此不得再添加闪红硬直或中断当前攻击/移动。修改动作推进时必须覆盖“末帧前不伤害、末帧复核、单帧动作、投射物延迟结算、非致命伤保持状态、死亡幂等、死亡末帧保持”。

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

爆破关的数据仍必须通过 `charge_policy` schema 校验，并将来源状态保持为 `remake_policy_from_recovered_map_inventory`；其中 `inventory_item_id` 必须是 DBL 998 已恢复的物品 45。但稳定 MOD 的 m001/m002/m003/m004/m008 运行时必须优先使用 `legacy_mission_rules.gd` 的原生求值：m001/m002/m004 观察 type 98 被真实 `128×64` 爆炸摧毁，m003/m008 观察 type 98 严格 128 内生成 type 85。物品 45 只在 type 10 攻击命中帧从角色 `+0x22C` 容器消费一次，任务层不得二次扣除，也不得允许按 `E` 伪完成。`charge_policy` 的交互消费路径只用于 m009/m011 等尚无专用原分支求值器的兼容内容和合成 fixture；不要重新引入共享 `field_inventory`。

m004 的计划书来源已由物品 101/VWF 携带记录定案为 scene 2637；它可以被任意角色实际拾起，但稳定任务只在古明或大牛持有时推进。m006/m008/m009/m011 的 `stable_mod` 与 `repaired` 目标都由 `MissionData` 解析，默认稳定 MOD，设置与存档必须保留 profile 身份，不能在世界脚本里静默混用。m006 稳定规则必须记录实际拾取者并把 scene 1457 的物品 101 放入强子背包；m008 稳定规则不要求手动引爆；m011 稳定规则在 scene 1353 后仍要求老赵、强子进入 scene 1359。m010 的四个区域分别实时检查老赵、强子、大牛、古明之一是否在 128 像素内，不按 `E`、不累计、不要求停留或先清敌，也不额外发明原代码没有的身份去重条件。不要在新脚本中重新引入旧候选或临时近似。

任务媒体必须写入可选 `media_cues`，不得在关卡脚本里散落硬编码弹窗。只允许 `on_start`、`on_objective`、`on_story_anchor`、`on_victory` 四段和 `audio`、`dialogue`、`movie`、`ending` 四类 cue；每项必须标 `recovered_media_mapping`、`remake_editorial` 或 `mixed`。目标键必须引用真实 objective ID，剧情锚点键必须同时存在于 scene 绑定和 `story_anchor_reached` 目标。当前基线包括 m000 教程/彭鑫营救确认、m006 的 `repaired` 接头提示和 m011 结局；重复持久剧情事实不能重播模态媒体。

`runtime_state_snapshot.gd` 为合成战斗命令和十二关任务事件生成规范化 SHA-256 哈希链，并执行两遍比较。它验证状态确定性，不录制鼠标/键盘、物理帧或渲染时序；涉及长期稳定性时仍需另建真实输入回放和帧时间/内存基线。

## 产品壳、设置与存档开发工作流

`game_shell.gd` 管理 `Esc` 菜单、`F1` 指南、`A`/`W` 276×421 五列背包、十槽选择器、设置和任务失败灰化层；`Esc` 在松开时提交，菜单内右键也在松开时返回上一级。世界右键只负责拖框，不提交移动/攻击；世界左键提交选择、移动、攻击和使用，左 `Ctrl`/`↑` 按住时进入强制目标路径。这些模态层暂停 SceneTree，失败层不能“继续”或保存，只能重玩、读取或退出。`M` 地图改为独立右下角 HUD，显示时不暂停战斗；`tactical_map_view.gd` 只消费主场景提供的原版逐关静态图、敌我/任务标记和镜头矩形，不自行推断任务规则。动态红点、镜头框和点击卷屏是复刻增强。

`game_settings.gd` 管理版本化 `user://settings.json`。当前默认跟随桌面分辨率
全屏，菜单同时提供 1280×720/自定义窗口、无边框最大化、VSync、帧率上限、
窗口尺寸、UI/文字缩放、总静音、主音量/音乐/音效/语音、字幕、任务简报、鼠标
边缘卷屏、减少自动镜头运动、2 倍最近邻原版光标和按键重映射。经典/现代规则、
剧情/普通/困难/自定义难度和经典/现代 RTS 操作是三个独立维度。现代操作另含
控制组、相机书签、双击同类选择和可配置镜头。按键冲突采用动作间交换，支持
恢复默认值。显示与界面设置变更后立即应用并原子保存；任何显示模式都不得调用
系统级光标移动、裁剪或捕获 API。物理多显示器和更多 GPU 的剩余真机边界记录在
[现代化改造验收报告](现代化改造验收报告.md)，不得以离屏矩阵冒充真机性能。

`game_save_store.gd` 管理 `user://saves/<slot>.json`，`game_session_state.gd` 负责主场景可变状态的捕获/恢复。菜单公开 `slot_1`—`slot_10` 十个手动槽并要求二次确认覆盖；菜单读取始终打开选择器，`Ctrl+F5` 写 `quick`，只有 `Ctrl+F9` 按保存时间读取最新有效槽，胜利写 `autosave`。任务失败时禁止覆盖有效存档。存档边界包括：

- 关卡、任务耗时、完成/进度/去重、失败和持久事实；
- 队员/敌人/护送角色的位置、阵营、生命/死亡、选择、背包/武器/弹药，以及 AI 巡逻/搜索和护送关系；
- 已激活任务 scene、公共物品、剩余拾取物、可爆物状态、任务掉落、type 8 地雷/type 10 定时世界对象、type 11 状态和未结算投射物；
- 已掩埋敌人的 scene 索引、type 78/GFL 64 藏尸处双容器和未完成 B 命令的执行者/目标/计数，读取后保持一致；type 90/GFL 341 观察标记按原版明确不保存；
- 十二关导演节拍/教程门控/持久事件/计时、AI 姿态/增援预算/命令序号；
- 镜头和战役完成/解锁进度。

资源、纹理、导航缓存、节点/信号引用、当前动画精确帧和尚未提交的移动/直接攻击命令不进入 JSON。读取必须先按 `level_id` 重建静态关卡，再调用 `apply_after_level_loaded()` 恢复可变状态；角色从安全状态继续，而已经生成的在途投射物继续其生命周期。

`atomic_json_store.gd` 的顺序必须保持“同目录临时文件写入 → 关闭并重新读取校验 → 有效旧主文件轮换为 `.bak` → 安装新主文件”。损坏主文件隔离为 `.corrupt`，不得挤掉有效备份；读取主文件失败时应回退 `.bak`。任何 schema 变更都要增加迁移和损坏/备份测试，禁止靠放宽 JSON 校验兼容旧档。

原版存档导入由 `LegacySaveSnapshot`、`LegacySavePreview` 和
`ResourceTool import-save` 承担。SAV 必须按 L1 唯一匹配正式关卡，SLIST
及 SI 必须精确 EOF；四个辅助容器必须按 item/quantity/mode 三个平行数组
读取，不能退回交错记录解释。`tools/Test-LegacySaveCompatibility.ps1`
会转换三组正式 SAV/SI，先通过 `GameSaveStore`，再在真实关卡中调用
`apply_after_level_loaded()` 核对角色、容器、埋藏物、拾取物和镜头。
导入槽只在读取页出现，防止原始转换被菜单直接覆盖。用户流程见
[原版 SAV/SI 存档导入](LEGACY_SAVE_IMPORT.md)。

## 固定时钟、回放与原生内容开发工作流

会影响玩法结果的新系统必须实现 `SimulationSystem` 并由
`SimulationCoordinator` 按稳定顺序推进。禁止在 `_process(delta)` 中累计决定
任务、AI、攻击、物品或导航结果；表现层只能提交 `ScheduledGameCommand` 或消费
`PresentationEventRouter` 事件。同一输入序列必须通过
`fixed_tick_persistence_test.gd` 的 30/60/120/不限渲染帧率测试和存读档下一 tick
比较。

可复现问题使用 `CommandReplay` 记录规范化 tick 命令、规则/难度、内容哈希、随机
初态和检查点身份。回放不记录桌面坐标或原始系统输入；版本或内容不匹配时必须
拒绝。新增可回放命令要同步更新 `tactical_replay_test.gd` 的命令序列、周期哈希和
首次分歧断言。

Remake 原生关卡使用声明式 `.m1937pack`，不要写回 VWF。常用命令如下：

```powershell
dotnet run --project .\tools\ResourceTool -- pack build `
  .\examples\synthetic-pack-source `
  .\LocalAssets\qa\native-content\synthetic.m1937pack
dotnet run --project .\tools\ResourceTool -- pack validate `
  .\LocalAssets\qa\native-content\synthetic.m1937pack
dotnet run --project .\tools\ResourceTool -- pack inspect `
  .\LocalAssets\qa\native-content\synthetic.m1937pack
```

源码只提交 schema、解析/验证工具、合成示例和测试。`.m1937pack` 成品、原版素材、
试玩包和 QA 输出必须留在忽略目录。格式、安全限制、MapEditor 一键导出与试玩见
[原生内容包与 MapEditor 工作流](原生内容包与MapEditor工作流.md)。

## 媒体开发工作流

完整导入会生成 `LocalAssets/converted/legacy-media-catalog.json`，记录十二张简报、十二张目标图、三张结局图、128 个 WAV 和五段已审计旧视频的元数据。原 WAV、PNG、SVT/VWF 媒体及转码 OGV 均留在被忽略的 `LocalAssets`，不能提交到 Git。

`legacy_media_catalog.gd` 负责安全解析本地/回退元数据，`media_director.gd` 负责简报、声音、Theora 视频、字幕和文字/可选语音对白。主场景已经在切关时显示简报，并把攻击、投射物命中、爆炸、警报、角色选择/确认、死亡和 UI 事件映射到原 WAV；任务运行时进一步按 `media_cues` 在开场、目标、剧情锚点和胜利时调用同一导演。独立音乐/环境声播放器、专用模态对白播放器、按需并发的战场角色语音播放器和 8 路预热 SFX 池分别路由到 `Music`、`Voice`、`Sfx`，影片播放器音轨同样进入 `Music`。战场语音与 SFX 忙满时扩展、结束后复用，不会抢占另一条正在播放的声音；这一点来自原版 `sub_40B080/sub_40B090/sub_40AFB0` 的每声音对象请求计数和 DirectSound 缓冲复制逻辑。简报、对白、视频或结局图打开时，导演暂停任务、AI 和战斗；模态媒体中的 `Esc` 在松开时关闭/跳过，Enter/Space 继续。稳定 MOD 简报的进程私有左键关闭已形成差分基线；Remake 的全屏媒体层吞掉按下并在松开时关闭，禁止同一次点击穿透到世界。十二关补写对白与镜头请求已进入 `MissionDirectionRuntime`，但均保留 `remake_editorial` 来源；视频和经原版逐字核对的对白/镜头仍需继续编排，不能从 WAV 文件名猜造剧情。

取证更新：`SDK/media-routes.json/original_direction_flow` 已通过 27 条演示资源引用、
两个摄像机直接调用、全部相机写入者和十二个 VWF 对象流证明原版没有关内脚本
对白、任务镜头或逐关教程。开发时不得再为 `original` 补猜测演出；现有导演只在
增强难度中作为 `remake_editorial` 使用，也不需要运行或尝试通关第一关来恢复它。

## Windows 本地试玩包

导入本地资源后，运行 `tools/Build-Playable.cmd` 会在已忽略的
`LocalBuild/1937Remake/` 生成 `Play-1937-Remake.cmd`。默认使用 `Copy`，并生成
内容 manifest、文件校验表、便携 ZIP 和 ZIP 的 SHA-256；`Junction` 仅供显式
选择的本机快速迭代。正式构建要求 Godot 4.7.1 官方 Windows release 模板，
分别执行 PCK 路径和最终 `1937Remake.exe` 的 headless 冒烟测试。详细目录结构、
切关参数和导出模板行为见 [Windows 本地试玩包](PLAYABLE_BUILD.md)。

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

### 角色语音选择器的离线恢复范式

角色语音恢复使用同样的仓库边界：IDA 脚本、数据库、反汇编文本和 SLF 原文件仅保存在被忽略的 `Remake/LocalAssets/analysis/ida`，Git 只提交语义、索引表、重新实现和合成测试。证据链为：

1. 从四个 runtime-type switch 跟踪到 `sub_45D780`；
2. 证明其进入 `sub_40B800` 的声音数组边界检查与 `sub_40B080` 播放调用；
3. 按 `1937Sound.slf` 的 126 条磁盘顺序将立即数映射到 GFL/WAV 身份；
4. 在 `SDK/crt-rand-call-sites.json` 修正调用点语义并重新生成 SDK/Godot 目录；
5. 用 `legacy_actor_audio_test.gd` 验证全部表项、奇偶分支和共享 CRT 流，不加载原声音。

不要用长时间自动通关来证明此类局部语义。只有触发条件无法由静态字段闭合时，才做几秒级、仅目标窗口的读取型差分，并禁止系统鼠标定位、裁剪或捕获。
