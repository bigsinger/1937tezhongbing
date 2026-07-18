# 复刻工程架构

## 设计边界

工程把旧引擎格式解析、本地中间资产、新游戏数据和 Godot 运行时分开。Godot 不直接解析 GFL、VWF、DBL 或 SPR；.NET 工具先校验输入版本，再转换为 PNG、WAV 和版本化 JSON。任务目标则使用仓库内的新数据模型描述。

```text
本地原版目录
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
game/data/missions.json ────────────────┤ 任务图、依赖、胜负与逐关爆破策略
game/data/projectile_profiles.json ─────┤ 投射物重制参数/证据状态
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

`GameDirectoryProbe` 检查目录结构、十二个正式关卡和已知文件 SHA-256。未知哈希版本不会被静默套用既有偏移。

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

`level.json` 的实体记录包含场景槽号、DBL ID、资源名、显示名、分类、世界/参考坐标、精灵预览、阵营、特殊感知、出生方向/姿态、生命值、默认攻击和巡逻数据。巡逻字段区分当前航点索引、原始持久标志与缓存航点世界坐标；`task_anchors` 单独标出剧情标记、爆破检测、出口检测、敌人出生和入口等锚点。

VWF 五层的主要用途已由原程序的层名表和实际读取路径交叉验证：L1 是地块索引，L2 是视线/射击遮挡，L3 是移动障碍与八方向寻路的权威平面，L4 在十二个正式关卡中全为零，L5 是编辑期的手工移动障碍修正标记。这一结论不代表 DBL/SLIST 的所有扩展字段都已理解，也不代表完整 AI 和交互已经还原。详见 [导航、视线与战斗边界](NAVIGATION_AND_COMBAT.md)。

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
- `death` 播放一次并保持末帧；当前没有确认可用的独立受伤动作，非致命伤采用 0.18 秒闪红/硬直的重制反馈。

类型 6、7、9 在攻击末帧发出世界投射物请求，分别进入飞镖、弹弓和手榴弹的飞行/爆炸链路。因此“全部序列帧已处理”描述的是数据管线能力；已接线的攻击、投射物和死亡也不等于 type 8/10/11 专用状态对象、原受伤动作和所有过渡都已恢复。

## 4. 任务数据与运行时状态

任务恢复由两类数据共同完成：

1. `level.json` 提供关卡中的实际实体、坐标和任务锚点；
2. `game/data/missions.json` 提供十二关标题、目标、依赖、计数、限时、失败条件、爆破策略和可选任务媒体 cue。

`MissionData` 校验任务 ID、目标唯一性、依赖引用和触发器清单。`MissionState` 是通用事件计数器，支持：

- 目标依赖；
- 按实体或来源去重；
- 必需与可选目标；
- 限时失败和条件性失败；
- 全部必需目标完成后的胜利判定。

`MissionState` 本身只做条件匹配和进度计算；`MissionRuntime` 在它前面建立当前关卡 `scene_bindings` 白名单，确认 scene 存在并核对爆破/出口锚点类型。世界系统只能通过运行时发布事件，跨关卡、未绑定或缺少 scene 引用的场景事件会被拒绝。持久事实会去重并在依赖完成后重放，出口进入则保持瞬时判定。

爆破目标另由 `charge_policy` 声明 `preplanted` 或 `inventory_required`。模式来自真实 DBL 998 拾取数量与爆破目标数量的逐关闭环，而非未经证明的原版消耗调用：m001/m004/m011 不扣背包，m002/m003/m008/m009 每个目标消耗一份。主场景只在 `MissionRuntime` 成功接受事件后提交库存扣除，拒绝事件、缺少物资和重复 scene 都保持背包与任务状态不变。

主场景切关时加载任务图并显示目标列表；救援、任务角色击毙/掉落、物品取得、爆破/占点、区域清敌、出口、限时和必要角色死亡已经转成规范化事件。`m000` 已具备营救两名 NPC、护送到出口及成功/失败的端到端闭环。m004 已确认 scene 2637/物品 101；m009 默认修复为全关日军清零、两份文件和四处爆破；m010 自动判定老赵、强子、大牛、古明分别同时占据四个 128 像素区域。其他逐关对白、镜头、AI 配合和难度仍未人工编排完成。

任务媒体层把 `on_start`、`on_objective`、`on_story_anchor`、`on_victory` 映射为 `audio`、`dialogue`、`movie` 或 `ending`，并要求每项标记 `recovered_media_mapping`、`remake_editorial` 或 `mixed`。当前 m000 教程/营救确认、m006 接头提示和 m011 结局已接线；剧情锚点只在产生新目标进度时播放，因此持久事实重放不会重复弹出对白。它是受 schema 约束的编排接口，不代表其余九关已有完整演出。

`RuntimeStateSnapshot` 把战斗单位、背包和任务进度规范化为稳定文本并计算 SHA-256。测试会对同一合成事件流执行两遍并逐步比较哈希，覆盖战斗和十二关任务图的胜利、失败及重置；该层不是用户输入录制器，也不替代十分钟实机回放。

对白、镜头、演出先后、触发半径、AI 配合和难度节奏不能仅靠静态锚点完整恢复，需要根据简报、运行观察和历史资料人工校准。详见 [任务恢复说明](MISSION_RECOVERY.md)。

## 5. Godot 运行时

Godot 从 `res://../LocalAssets/converted/` 读取本地数据：

- 仅接受支持的 `schema_version`；
- 相对资源路径解析后必须仍位于转换目录内；
- PNG 使用 `Image`/`ImageTexture` 加载，纹理和动画组按路径缓存；
- `navigation.bin` 的魔数、版本、尺寸、层顺序和文件长度都必须通过校验；
- 地形左上角对齐世界原点，实体按世界坐标放置并按 Y 值排序；
- 相机边界自动采用当前关卡尺寸；
- `PageUp` / `PageDown` 切换 `m000`—`m011`，也支持 `--level=mNNN` 启动参数。

当前可控队员使用关卡中对应角色的坐标和已转换动画。玩家、faction 1 敌人和任务护送角色都注册进同一个 `DynamicOccupancyGrid`：源 L2/L3 只读，以源 `ReferenceX/Y` 的八连通分量恢复足印，运行时单独维护角色足印、目标预留、密集移动段检查和第三方视线遮挡。未营救护送角色保持 faction 2 中立，敌人不会提前攻击；营救后切换到 faction 3 并跟随队员。L3 A* 禁止斜穿贴角障碍；敌人读取原巡逻点、方向、感知类型、生命和默认武器，执行巡逻、发现、追击、攻击、实际伤害、基础警报和最后位置搜索。退化巡逻点和拥挤重规划使用确定性错峰退避，避免 A* 重算风暴。

玩家单位各自持有 `CombatInventory`；`ProjectileWorld` 负责 type 6/7/9 的世界飞行与命中；`FieldPickup` 从 10 类真实 DBL 拾取实体生成；`LandMine` 和 `ExplosiveProp` 通过统一椭圆爆炸请求支持地雷、油桶和连锁伤害。`MediaDirector` 在切关时显示原简报图，并播放已分类的攻击、命中、警报、角色、死亡和 UI WAV；本地媒体缺失时安全降级。简报、对白、视频和结局图采用模态暂停，打开期间冻结任务时限与战斗，关闭后恢复先前暂停状态。导演也提供 Theora 视频和文本/可选语音对白接口，但主任务尚未逐关编排对白和镜头。仍未完成的是通用中立角色行为、听觉遮挡/尸体发现、type 8/10/11、存档和逐关演出。

## 6. 为什么选择 Godot 4.7

本作适合俯视角 2D 即时战术架构。Godot 提供 2D 渲染、动画、导航、音频、UI、场景编辑器和现代 Windows 导出，可以把后续工作集中在规则、AI 和任务系统上。

运行时使用 Standard 版本与 typed GDScript，不依赖 .NET；资源工具使用 .NET 10，以便严格处理二进制边界、合成 fixture 和命令行批量转换。默认采用 Compatibility renderer，目标是兼顾学校环境中的旧集成显卡。逻辑时钟为 60 Hz；m000 已在 54 名敌人、动态占位和巡逻同时运行时完成 360 帧实测，合成事件流也已有确定性哈希。仍需补真实帧输入长回放、异步关卡预载以及包含投射物、拾取、爆炸和媒体切换的新性能基线。

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
