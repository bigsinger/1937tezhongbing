# 复刻工程架构

## 设计边界

工程把旧引擎格式解析、本地中间资产、新游戏数据和 Godot 运行时分开。Godot 不直接解析 GFL、VWF、DBL 或 SPR；.NET 工具先校验输入版本，再转换为 PNG、WAV 和版本化 JSON。任务目标则使用仓库内的新数据模型描述。

```text
仓库稳定 Mod/（默认）或受支持的原版目录（取证兼容）
      │ 只读探针、已知版本 SHA-256、结构边界校验
      ▼
.NET ResourceTool / ResourceFormats
  ├── GFL + InterMedia 索引交叉校验
  ├── IBLOCK / TLG1 / SPR1 图像与动画解码
  ├── DBL / VWF / SLIST1 实体、巡逻与任务锚点关联
  ├── VWF L2—L5 → M37NAV1 导航/视线中间网格
  ├── SLF / WAV 声音映射与媒体目录
  └── 旧 MPEG 媒体识别与可选 Theora 转码
      │
      ▼
Remake/LocalAssets/                      ← Git 忽略，本地可重复生成
  ├── raw/gfl/*
  └── converted/
      ├── iblock / tile-atlases / audio
      ├── legacy-media-catalog.json
      ├── media/video/*.ogv              ← 可选本地转码
      ├── sprites / sprite-frames
      └── levels/m000 ... m011
          ├── terrain.png / level.json
          └── navigation.bin
                 │
game/data/missions.json ────────────────┤ 任务图、依赖、胜负与兼容爆破策略
game/scripts/legacy_mission_rules.gd ───┤ 六关原生类型、距离、持有人与出口求值
game/data/projectile_profiles.json ─────┤ 原版投射规则/逐字段证据状态
game/data/world_pickups.json ───────────┤ 原实体身份与世界交互效果
                 │                      ▼
                 └──────────────► Godot 4.7 运行时
                                   ├── 十二关地形与 19,199 个实体
                                   ├── 通用动作/方向动画加载
                                   ├── 数据驱动任务状态机与确定性快照
                                   ├── 背包、投射物、拾取、地雷与可爆物
                                   ├── 简报、原 WAV、视频/对白框架
                                   └── L3 A*、动态占位、L2 视线与敌人巡逻/警戒核心
```

## 1. 输入探针与严格解析

`GameDirectoryProbe` 检查目录结构、十二个正式关卡和已知文件 SHA-256。
默认内容 profile 为 `repository-mod-12-level-20260729`；未知哈希版本不会
被静默套用既有偏移。

`GflArchive` 同时读取 `1937Resources.GFL` 和 `InterMedia.GFL`，逐条核对 1394 个名称、属性、payload 长度和绝对偏移。解析器采用“已知结构严格接受、未知变体明确拒绝”的策略；越界、尾随数据、重复名称或索引不一致都会终止导入。

`ResourceFormats` 负责旧格式，不依赖 Godot：

- `IBlockImage`：LZO1X → RGB565 → RGBA32，可选 alpha 平面；
- `TlgTileGroup`：读取 4×4 tile 区域和内嵌 IBLOCK 图集；
- `SprSprite`：读取三个容器版本、2,775 个动画组和 11,898 帧；
- `SprAnimationSemantics`：解码 20 个动作槽 × 9 个方向槽；
- `DblDatabase`：读取资源、显示名、分类、一对多元素记录，以及 sprite header 中已确认的阵营和特殊感知字段；
- `VwfTerrainGrid`：读取五个 plane-major 地图数组；
- `VwfNavigationGrid`：保真导出已验证的 VWF 视线、移动、事件与手工修正平面；
- `VwfSceneList`：读取实体、坐标、出生方向/姿态、生命值、默认攻击、巡逻数据和任务锚点；
- `TerrainRasterizer`：把十二关第一地形平面合成为普通 PNG。
- `LegacyMediaCatalogBuilder`：按名称、GFL/SLF 来源和已审计用途生成简报、示意图、结局图、128 个声音 cue 与旧视频元数据，不把媒体字节写进仓库。

尚未理解语义但已经能确定边界的字段继续使用中性名称，不以猜测命名。

## 2. 本地中间格式

一次 `ResourceTool import` 生成：

- 34 张 IBLOCK PNG；
- 45 张 TLG 图集 PNG；
- 980 张 SPR 首帧预览；
- 980 份 `sprite.json`、2,775 个组 atlas 和 11,898 个逐帧 PNG；
- 128 个 PCM WAV；
- 一份 `legacy-media-catalog.json`，记录逐关简报/示意图、结局图、声音事件和旧视频身份；
- `m000`—`m011` 的十二张地形 PNG、`level.json` 和 `navigation.bin`；
- 共 19,199 条实体记录及关卡任务锚点；
- 资源总清单和十二关索引。

`level.json` 的实体记录包含场景槽号、DBL ID、资源名、显示名、分类、世界/参考坐标、精灵预览、阵营、特殊感知、出生方向/姿态、生命值、默认攻击和巡逻数据。巡逻字段区分当前航点索引、原始持久标志与缓存航点世界坐标；`task_anchors` 单独标出剧情标记、爆破检测、出口检测、敌人出生和入口等锚点。普通 actor 伤害不直接照抄 profile 常量：`LegacyCombatRules` 复现 `sub_456DF0/sub_458700` 的 attacker runtime type 例外、直接命中数和 target runtime type 低伤害免疫，防止机枪坐标三弹道被错误结算成同一目标三次扣血。

VWF 五层的主要用途已由原程序的层名表和实际读取路径交叉验证：L1 是地块索引，L2 是视线/射击遮挡，L3 是移动障碍与八方向寻路的权威平面，L4 在十二个正式关卡中全为零，L5 是编辑期的手工移动障碍修正标记。这一结论不代表 DBL/SLIST 的所有扩展字段都已理解，也不代表完整 AI 和交互已经还原。详见 [导航、视线与战斗边界](NAVIGATION_AND_COMBAT.md)。

仓库中的 `game/data/level_fidelity_baselines.json` 是本地批量资源之外的可审计结构指纹。它由 `tools/Build-LevelFidelityBaselines.ps1` 从受支持的稳定 MOD profile 和十二关转换结果确定性生成，固定源 VWF/DBL 身份、地形和导航哈希、逐关结构计数及任务/玩家/地标关键 scene；真实资源验证会先以 `-Verify` 重算，再由 Godot 对实际加载结果执行字段和文件哈希校验。该结构门禁不能替代画面像素基线，但能阻止地图、层、路线、任务对象或出生点在不可见处静默漂移。

## 3. 动画模型

SPR 每个 frame group 的参数 0 是动作/方向序列号：

```text
serial_id = action_index * 9 + direction_index
action_index    = serial_id / 9
direction_index = serial_id % 9
```

动作槽共 20 个：无、站立、站立动作、行走、跑、死亡、手枪攻击、匍匐前进、主动动作、步枪攻击、机关枪攻击、手榴弹攻击、大刀攻击、匕首攻击、飞镖攻击、弹弓攻击和 4 个保留槽。方向槽 0 为“无”，1—8 为上、上右、右、下右、下、下左、左、左上。

转换器保留组内帧顺序、三个参数 triplet、lookup 数组和逐帧尺寸，并输出单组横向 atlas。Godot 的 `ImportedSpriteAnimation.load_action_groups()` 是通用加载器，能读取任一已知非保留动作，并要求一个八方向动作的八组都齐全。

当前动画接线包括：

- 移动优先使用 `run`，缺失时回退 `walk`；
- 停止时使用对应方向 `stand` 的第一帧；
- 每帧按原版 `parameters[2] + 1` 个 0.085 秒基础 tick 保持；
- 当前武器的攻击/近战动作由战斗状态触发，进入最后一帧时复核并结算命中；
- `death` 播放一次并保持末帧；非致命 `sub_458700` 只扣生命，不改变当前
  命令、动作或计时，复刻不再插入独立闪红/硬直。

类型 1、2、3、6、7、9 在非相邻目标或手榴弹攻击末帧发出世界投射物请求，
使用原版含首尾点整数 Bresenham 路径、64/64/64/16/5/8 像素逐 tick 步长、
当前 SPR 组 primary/tertiary 锚点和原 L3→L2 碰撞顺序。普通枪弹为不可见
mode 0，机枪恢复三路角度散布，命中时创建 actor 60 / GFL 306 火花；
飞镖/弹弓分别创建 actor 80/81，手榴弹使用原抛物线创建 actor 57，并在
终点下一 tick 创建 actor 61；伤害、GFL、爆炸椭圆和警报均已恢复。
type 8/10 在同一末帧协议上创建专用世界对象并
共用已恢复的 actor 62 爆炸语义；其效果 11/15 按原 MSVCRT 随机序列、
首匹配 GFL 和五轮动画生命周期生成 90/150 tick 粒子。type 11 创建按
来源移动/战斗转换释放的注意力保持状态；三者均能跨存读档恢复。因此
“全部序列帧已处理”描述的是数据管线能力，仍不等于全部过渡
或全局随机调用顺序已经完全定案。

正式十二关不会编辑性发放项目 99；古明由军服 54 在严格第 101 个角色 tick
切为 type 91/GFL 272 时，原版取得事件会自动把 mode-1 项目 99 加入武器栏；
脱下军服时移除。

## 4. 任务数据与运行时状态

任务恢复由三类数据共同完成：

1. `level.json` 提供关卡中的实际实体、坐标和任务锚点；
2. `game/data/missions.json` 提供十二关标题、目标、依赖、计数、限时、失败条件、兼容爆破策略和可选任务媒体 cue；
3. `legacy_mission_rules.gd` 固定 m001/m002/m003/m004/m005/m006/m008 从 `sub_404BB0/sub_405410` 恢复的运行时类型、严格/包含 128 边界、物品持有人和出口成员规则。

`MissionData` 校验任务 ID、目标唯一性、依赖引用和触发器清单。`MissionState` 是通用事件计数器，支持：

- 目标依赖；
- 按实体或来源去重；
- 必需与可选目标；
- 限时失败和条件性失败；
- 全部必需目标完成后的胜利判定。

`MissionState` 本身只做条件匹配和进度计算；`MissionRuntime` 在它前面建立当前关卡 `scene_bindings` 白名单，确认 scene 存在并核对爆破/出口锚点类型。世界系统只能通过运行时发布事件，跨关卡、未绑定或缺少 scene 引用的场景事件会被拒绝。持久事实会去重并在依赖完成后重放，出口进入则保持瞬时判定。

七个原生任务分支优先观察真实世界状态。m001/m002/m004 只有 type 98 被 `128×64` 世界爆炸摧毁才推进；m003/m008 在 type 85 实际生成时，对各 type 98 执行严格 `<128` 查询；m004 物品 101 只接受古明或大牛持有，m005 要求 type 24 目标死亡且只接受老赵、强子或古明持有其物品 101，m006 只接受强子持有。通用 `E` 热点不能完成这些条件，库存也不会由任务层重复扣除。`charge_policy` 仅保留给 m009/m011 等没有专用求值器的兼容路径及合成 fixture；它不能覆盖已恢复的原分支。

主场景切关时按持久化 `mission_rule_mode` 加载任务图并显示目标列表；救援、任务角色击毙/掉落、物品取得（含实际拾取者）、爆破/占点、区域清敌、出口、限时和必要队员/护送者死亡已经转成规范化事件。`m000` 已具备营救两名 NPC、护送到出口及成功/失败的端到端闭环。m001/m002/m003/m004/m005/m006/m008 的专用求值在确认原世界条件成立后再发布同一规范化事件，因此目标图和存档协议无需复制七套；m006/m008/m009/m011 同时保留稳定 MOD 实际控制流和按简报修复的增强 profile，默认前者；m010 自动实时判定四个 128 像素区域是否分别存在四名指定角色之一，不附加原代码没有的身份去重。

`MissionDirectionRuntime` 在任务图上再消费 `mission_direction.json`：十二关第一版共有 43 个节奏节点、45 行提示对白、教程门控、镜头请求和 AI 指令；`MissionAiCoordinator` 应用逐关协作与 Easy/Normal/Hard 数值换算。objective/scene 引用来自恢复事实，补写对白、镜头参数、教程、AI 策略和难度均为 `remake_editorial`。导演节拍、教程门控、持久事件/计时及 AI 姿态、增援预算、命令序号已经接入产品级 `GameSessionState`；仍需用完整通关校准节奏。

任务媒体层把 `on_start`、`on_objective`、`on_story_anchor`、`on_victory` 映射为 `audio`、`dialogue`、`movie` 或 `ending`，并要求每项标记 `recovered_media_mapping`、`remake_editorial` 或 `mixed`。当前 m000 教程/营救确认、m006 `repaired` 规则的接头提示和 m011 结局已接线；剧情锚点只在产生新目标进度时播放，因此持久事实重放不会重复弹出对白。它是受 schema 约束的编排接口，不代表其余关卡已有完整原版演出。

`RuntimeStateSnapshot` 把战斗单位、背包和任务进度规范化为稳定文本并计算 SHA-256。测试会对同一合成事件流执行两遍并逐步比较哈希，覆盖战斗和十二关任务图的胜利、失败及重置；该层不是用户输入录制器。独立的 `campaign_performance_probe.gd` 已负责十二关双轮十分钟真实窗口输入、帧时间和内存门禁，但两者都不替代稳定 MOD/Remake 的真人完整通关差分。

对白、镜头、演出先后、触发半径、AI 配合和难度节奏不能仅靠静态锚点完整恢复，需要根据简报、运行观察和历史资料人工校准。详见 [任务恢复说明](MISSION_RECOVERY.md)。

## 5. Godot 运行时

Godot 从 `res://../LocalAssets/converted/` 读取本地数据：

- 仅接受支持的 `schema_version`；
- 相对资源路径解析后必须仍位于转换目录内；
- PNG 使用 `Image`/`ImageTexture` 加载，纹理和动画组按路径缓存；
- `navigation.bin` 的魔数、版本、尺寸、层顺序和文件长度都必须通过校验；
- 地形左上角对齐世界原点；实体按原版四队列放置，正常对象再按脚底/导出 baseline 稳定排序；
- 相机边界自动采用当前关卡尺寸；
- `PageUp` / `PageDown` 切换 `m000`—`m011`，也支持 `--level=mNNN` 启动参数。

当前可控队员使用关卡中对应角色的坐标和已转换动画。玩家、faction 1 敌人和任务护送角色都注册进同一个 `DynamicOccupancyGrid`，并在分流构造前统一绑定原版运行时数组索引：源 L2/L3 只读，以源 `ReferenceX/Y` 的八连通分量恢复足印，运行时单独维护角色足印、目标预留、密集移动段检查和第三方视线遮挡。营救不是统一的 `E` 交互：m000/m001/m002/m004/m007 的七名正式对象按运行时类型处理器自动检查指定角色、角色类型和严格欧氏/2:1 等距距离；m002 强子与 m004 古明获救后加入可操作队伍，其余证实对象按 `sub_45D330` 的随机追随调度执行，m001 司机还保留 faction 2。L3 A* 禁止斜穿贴角障碍；敌人读取原巡逻点、方向、感知类型、生命和默认武器，执行巡逻、发现、追击、攻击、实际伤害、基础警报和最后位置搜索。稳定 MOD 的巡逻时间线在原版五个静止 handoff tick 内按 scene ID 确定性错峰预热；相同证据路径及经过逐格验证的平移路径可复用，动态障碍导致的不可达请求先用原生连通性快速证明，再沿既有局部路径退化。原版 recovered A* 的子图采用固定八槽紧凑数组，仍保持原邻居插入顺序、闭集改善传播和最终路径逐点等价，避免大地图上的 Dictionary/Array 分配尖峰。

`ImportedLevelData` 保留并校验转换结果中的 `database_header_values`；`WorldDepth` 据 DBL `header[0]` 把地面/固定背景、正常深度、固定前景和顶层映射到四个互不重叠的 z 区间。正常队列再由 `LegacyRowSliceSprite` 复现原版 32 像素列：非均匀 RowLookup 才拆成缓存的 AtlasTexture，均匀表保留单 draw item，并以 `reference_y - primary.z + row_lookup[column]` 计算绝对深度。它覆盖静态场景、移动 actor、门两态、拾取物、爆炸物和特殊世界对象；动态 actor 每次动作、朝向或帧变化都会原子刷新锚点、足印与列基线。m000 真实资源回归已确认 22 个 DBL 336/337 庄稼底图在 queue 1，70 个 DBL 335 稻谷在 queue 0；因此前者固定在人物后，后者才参与人物基线排序。玩家身份不再只按姓名猜测，而由 `original_initial_weapon_inventory.json` 的 level + scene ID 确定；`original_runtime_actor_catalog.json` 还固化 772 个已解析运行时角色、5 个 VWF/运行时阵营差异和 656 条稳定 MOD 巡逻时间线。十二关 660 个精确动态角色都持有原版直接数量语义的 `CombatInventory`，共恢复 761 个 `+0x22C` 有序武器条目和 67 个空容器，其中 27 名玩家占 83 条；敌军的“不消耗”只改变扣除规则，不删除其精确容器。另由 `original_initial_item_inventory.json` 和独立 `BackpackInventory` 固化同一批 660 个角色、539 条 actor `+0x228` 物品记录，绝不再与武器或全队公共物资混用。`InventoryGridView` 以右侧 276×421 五列方格分别呈现 W 武器/A 物品；`ProjectileWorld` 负责 type 1/2/3/6/7/9 的原版坐标弹路、命中火花与爆炸，`LegacySpecialWorldObject` 和 `LegacyAiControlEffect` 负责 type 8/10/11。`FieldPickup` 读取 DBL `header[2]` 的真实 item ID，并按原程序 `sub_45AE10` 路由到拾取角色自己的武器或物品容器；DBL 1003 则保留为可受伤汽油桶，绝不按名称猜成普通物品。`LandMine` 和 `ExplosiveProp` 通过统一椭圆爆炸请求支持地雷、油桶和连锁伤害。世界命令不绘制黄色目标线。

`GameShell` 管理暂停菜单、十槽选择器、按键重映射、四通道音量、失败灰化和五列背包。世界左键提交选择/移动/攻击/使用，左 `Ctrl` 或 `↑` 按住时进入强制目标；世界右键只拖框，菜单右键松开返回。右下角地图属于独立 HUD，不暂停 SceneTree；它优先显示原版逐关静态目标图，并增加实时敌我/任务点、镜头框和点击卷屏。`MediaDirector` 在切关时显示原简报图；音乐/环境声和影片音轨进入 `Music`，对白进入 `Voice`，攻击、命中、警报、角色、死亡和 UI WAV 进入 `Sfx`，媒体 `Esc` 在松开时关闭/跳过。当前关卡队员的全部移动应答 WAV 会在世界构造阶段静默解码进持久缓存，不启动播放、不推进变体种子；因此第一次地面命令不会把冷音频解码、分配和 A* 同时压到一个显示帧。导演节拍/教程/持久事件和 AI 姿态/增援预算、已掩埋敌人的 scene 索引及特殊对象等可变状态均随 `GameSessionState` 保存恢复。仍未完成的是通用中立角色行为、原版 S/B 命令细节、经证据核对的逐关演出、真人完整通关差分和跨 Windows 机器验收。

## 6. 为什么选择 Godot 4.7

本作适合俯视角 2D 即时战术架构。Godot 提供 2D 渲染、动画、导航、音频、UI、场景编辑器和现代 Windows 导出，可以把后续工作集中在规则、AI 和任务系统上。

运行时使用 Standard 版本与 typed GDScript，不依赖 .NET；资源工具使用 .NET 10，以便严格处理二进制边界、合成 fixture 和命令行批量转换。默认采用 Compatibility renderer，目标是兼顾学校环境中的旧集成显卡。逻辑时钟为 60 Hz；Windows 10/GTX 1050 Ti 的十二关双轮 600 秒窗口基线共 33,125 帧，整体 P95 18.167 ms、P99 20.936 ms、零个 >50 ms 帧，第二轮静态内存增长 1,063,804 字节，24 次关卡载入均低于 3.4 秒。仍需补稳定 MOD/Remake 真人完整通关差分、异步关卡预载、Windows 11 和更多硬件验收。

## 7. 仓库与本地资产隔离

- 导入输出不能与输入目录重叠；
- 位于 Git 工作树内的输出必须通过 `git check-ignore`；
- 根 `.gitignore` 排除 `Remake/LocalAssets/` 和常见旧资源扩展名；
- `Check-NoOriginalAssets.ps1` 扫描文件名、格式签名、导入目录和压缩包内容；
- CI 与提交验证只使用人工生成的合成 fixture。

批量资产不入库是仓库体积和可重复导入策略；本文不对素材的权属或发布条件作法律判断。

## 子目录

```text
game/                         Godot 工程
game/data/                    十二关任务图、战斗/投射物/拾取与媒体元数据
game/scripts/                 运行时、动画、任务、背包、投射物、媒体、相机与小队
game/tests/                   不含批量原版数据的 GDScript 测试
tools/ResourceFormats/        旧格式读取、语义解码和地形合成库
tools/ResourceTool/           inspect/list/extract/import 命令行工具
tools/ResourceFormats.Tests/  合成二进制 fixture 测试程序
docs/                         格式、任务恢复、开发和路线图文档
LocalAssets/                  本地转换结果，不进入 Git
```
