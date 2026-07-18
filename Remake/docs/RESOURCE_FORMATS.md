# 原版资源格式研究

> 状态：本文所述边界已经在本地已知版本上逐文件严格验证。解析器要求签名、计数、长度、引用和文件末尾一致；尚无充分证据的字段继续使用中性名称，不把“能够读取”误写成“已经理解玩法语义”。

## 已知输入版本

`ResourceTool import` 当前只接受以下锚点。哈希用于识别输入版本，不包含原版数据。

| 文件 | SHA-256 |
|---|---|
| `M1937.exe` | `F4DD1131DF6C993C01EA011F9439BC725E6DC6491B5FBBA47724D7D5B64DA3F3` |
| `1937Resources.GFL` | `A93DA9180C546A8F349F03BC6912583C5CC5511AC9458E4B910108614CA07211` |
| `InterMedia.GFL` | `3D937AAB4D3906A735B4E33280EA0F971A69B12B9B54F99E91BCA79FC438BB0D` |
| `1937Database.dbl` | `0017D8AB6A41F104BF0DE9A8282AB593B94E2BF7131038566AC281A8F15025D9` |
| `1937Sound.slf` | `258A890F8D5EAEB642C047E509479531CF1862C4D1395153EEE353C1C65EBEFB` |
| `1937m000.vwf` | `C98E4347A1E69D79566DD790059D41E653DBBC3209AC0B73E2511803091B0E5C` |

其他发行版本必须先独立验证，不能静默套用这些偏移。

## GFL 资源库与伴随索引

两个文件都使用 78 字节全局头，文本以 `GFL (Game File Library) Win32/V1.0` 开始。

### `1937Resources.GFL`

第一条记录从绝对偏移 `0x4E` 开始：

```text
name[256]
attr[3]
uint32le payload_size
payload[payload_size]
```

1394 条记录顺序扫描后精确到达文件末尾，所有 payload 范围均已验证无越界。

### `InterMedia.GFL`

这是固定长度伴随索引，不是第二份资源包：

```text
+0    name[256]
+256  attr[3]
+259  uint32le payload_size
+263  uint32le payload_data_offset
```

每条 267 字节，`78 + 1394 × 267 = 372276` 与文件长度完全一致。`payload_data_offset` 指向 `1937Resources.GFL` 内的 payload 魔数；工具逐条核对名称、属性、长度和偏移。

### GFL 名称解码

```text
name[0]      = 原始 GBK 文件名字节长度 L
name[1..L]   = 混淆字节
其余         = 0

plain[i] = (cipher[i] - key[i]) & 0xff
```

25 字节密钥：

```text
34,37,5,44,1,4,19,27,49,24,45,35,2,
4,30,3,31,5,21,15,7,36,14,5,4
```

本版本最长名称恰好为 25 个 GBK 字节；1394 个名称全部严格解码、全部唯一，扩展名与 payload 魔数一致。没有证据表明密钥会循环，因此 `L > 25` 被视为未知变体。

### 资源构成

| 类型 | 数量 | payload 字节数 | 当前处理方式 |
|---|---:|---:|---|
| `SPR1` | 980 | 81,275,320 | 980 张预览、2,775 个组 atlas、11,898 个逐帧 PNG 与动画清单 |
| `8BPS` | 207 | 14,347,924 | 识别为 Photoshop PSD，不转换 |
| `RIFF/WAVE` | 128 | 4,937,164 | 复制为本地 WAV |
| `TLG1` | 45 | 685,381 | 解码完整图集 PNG |
| `IBLOCK` | 34 | 9,028,443 | 解码完整 PNG |

WAV 共约 128.6 秒，以 22050 Hz/16-bit 单声道为主，少量为 8-bit 或 11025 Hz。

## LZO1X、RGB565 与旧引擎兼容行为

IBLOCK、TLG 内嵌图像和 SPR 帧使用 LZO1X 压缩。解码器执行严格长度和回引用检查，同时复现原引擎会接受的“目标图像已经完整、压缩流末尾仍有少量 slack”行为；它不会把任意损坏流当成有效数据。

颜色平面解压后是小端 RGB565，转换为 RGBA32。SPR 中没有显式 alpha 平面的 direct-surface 帧使用 RGB(0,0,0) 作为 DirectDraw source color key；带 alpha 平面的帧必须保留 alpha 数据，包括不透明黑色像素。这个区分修复了早期预览中的黑色矩形背景。

## IBLOCK 1.0.0

独立 IBLOCK 的布局：

```text
0..33     ASCII 签名 + NUL，共 34 字节
34..848   embedded header，共 815 字节
849..     LZO1X RGB565 payload
[可选]    uint32 version=1, uint32 alpha_length, LZO1X alpha payload
```

已确认的独立文件偏移：

```text
42   uint32 width
46   uint32 height
841  uint32 bits_per_pixel = 16
845  uint32 compressed_length
```

embedded header 还包含 direct-surface/alpha 二选一标志。颜色平面解压长度必须是 `width × height × 2`；alpha 平面存在时必须是 `width × height`。34/34 个 GFL IBLOCK 已解析到精确 EOF 并转换为 PNG。

## TLG1 地表过渡图集

TLG1 的固定前缀为 381 字节：

```text
0..104    ASCII 签名 + NUL，共 105 字节
105       uint32 serialization_version = 1
109       uint32 flags
113       encoded_name[256]
369       uint32 tile_region_count
373       uint32 columns
377       uint32 rows
381..     tile_region_count × {int32 left, top, right, bottom}
随后       uint32 first_terrain_kind
           uint32 second_terrain_kind
           uint32 has_atlas
           [可选] embedded IBLOCK
```

内部名称采用每字节减 5 后按 GBK 解码。已知版本的 45/45 个 TLG 都是 4×4、共 16 个区域，区域尺寸统一为 32×16；内嵌图集全部可解码，区域边界都位于图集内。两个 terrain kind 的已知值为 1—6，对应深土、浅土、草、沙石、土石和砖地过渡。

## SPR1 精灵与动画容器

SPR1 使用 102 字节签名，容器序列化版本为 1、2 或 3：

```text
signature[102]
uint32 serialization_version
int32 header_values[4]
uint32 frame_group_count
[version > 1] int32 extended_header_values[50]
encoded_name[256]
frame_group[frame_group_count]
```

每个 frame group 有版本 1 或 2、帧数、若干三元组/参数和尺寸相关 lookup 数组，随后连续存储 embedded IBLOCK 帧。内部名称同样采用“每字节减 5 + GBK”。

已知 980 个 SPR 的验证结果：

| 容器版本 | 文件数 |
|---:|---:|
| 1 | 486 |
| 2 | 266 |
| 3 | 228 |

全部文件共 2,775 个 frame group、11,898 帧，980/980 精确解析到文件末尾；其中 194 帧带独立 LZO alpha 平面，其余帧按黑色透明键处理。导入器为每个 SPR 输出一张首帧预览、一份 `schema_version: 2` 的 `sprite.json`，并为每组输出横向 `atlas.png` 和全部逐帧 PNG。

### 动作与方向序列号

frame group 的 `parameters[0]` 已确认是 Intuition Engine 的动作/方向序列号。原程序的两个查找表与 980 个资源的全量审计一致：

```text
serial_id       = action_index * 9 + direction_index
action_index    = serial_id / 9
direction_index = serial_id % 9
serial_id 范围  = 0..179
```

| 动作索引 | Key | 中文语义 |
|---:|---|---|
| 0 | `none` | 无 |
| 1 | `stand` | 站立 |
| 2 | `stand_action` | 站立动作 |
| 3 | `walk` | 行走 |
| 4 | `run` | 跑 |
| 5 | `death` | 死亡 |
| 6 | `pistol_attack` | 手枪攻击 |
| 7 | `crawl` | 匍匐前进 |
| 8 | `active_action` | 主动动作 |
| 9 | `rifle_attack` | 步枪攻击 |
| 10 | `machine_gun_attack` | 机关枪攻击 |
| 11 | `grenade_attack` | 手榴弹攻击 |
| 12 | `broadsword_attack` | 大刀攻击 |
| 13 | `dagger_attack` | 匕首攻击 |
| 14 | `dart_attack` | 飞镖攻击 |
| 15 | `slingshot_attack` | 弹弓攻击 |
| 16—19 | `reserved_1`—`reserved_4` | 保留序列 |

| 方向索引 | Key | 中文语义 |
|---:|---|---|
| 0 | `none` | 无 |
| 1 | `north` | 上 |
| 2 | `northeast` | 上右 |
| 3 | `east` | 右 |
| 4 | `southeast` | 下右 |
| 5 | `south` | 下 |
| 6 | `southwest` | 下左 |
| 7 | `west` | 左 |
| 8 | `northwest` | 左上 |

组内帧顺序、尺寸、三个 triplet、lookup 数组和其他参数均写入清单。Godot 通用加载器可以加载任一已知非保留动作的八方向组；玩家与敌人已接入 `run`/`walk` 和 `stand`。每帧实际保持 `0.085 × (parameters[2] + 1)` 秒，不再使用统一帧长；攻击、投掷、近战和死亡动作的命中/过渡仍需在玩法阶段校准。

## DBL1 对象数据库

DBL 使用 78 字节签名头，随后是版本号与条目数量。本版本为 version 1、1023 条记录；解析器支持两种条目：

- kind 1：SPR 资源、显示名、精灵头及可变长度元素数据；
- kind 2：TLG 资源、16 字节 tile 元素数组和尺寸字段。

资源名和显示名是 256 字节定长字段，按每字节减 5 后以 GBK 解码。记录区之后是分类名称表和 1023 条分类映射。解析器验证每个分类 ID，最终精确到达文件末尾，并把所有 DBL 资源名与 GFL 中的 SPR/TLG 类型交叉核对。

kind 1 的 14 个 sprite header `uint32` 已完整保留。h8（原记录 `+548`）是阵营：1 敌方、2 中立、3 友方；h12（`+564`）是特殊感知标记，已知数据中只由 DBL 1007 军犬使用。kind 2 没有该 header，解析接口返回空数组而不是伪造默认值。

VWF 地形中的 tile-group ID 是 DBL kind-2 条目的从 1 开始序号：`0` 表示空；`1..45` 分别映射 DBL 的第 `0..44` 个 TLG 条目。该映射同时由文件数据、地形输出和原程序相关反汇编路径验证。

DBL 精灵元素内部的许多数组目前只完成安全跳读和边界验证，尚未赋予碰撞、姿态或导航等语义。

## VWF 地形网格

`M1937.exe` 只引用 `1937M000.VWF`—`1937M011.VWF`。十二个正式关卡具有一致的 `VWL1` 结构。

早期可用公式仍然成立：

```text
slist_offset = 331 + grid_width × grid_height × 20
```

现在已确认这里不是“每格一个 20 字节交错结构”，而是五个 plane-major `uint32` 数组：

```text
0..234    VWF preamble，共 235 字节
重复 5 次：
  uint32 layer_id        // 1..5
  uint32 width
  uint32 height
  uint32 value_count
  uint32 values[value_count]
随后       int32 local_viewport_left/top/right/bottom，共 16 字节
随后       SLIST1
```

因此总长度仍是 `235 + 5 × (16 + N × 4) + 16 = 331 + 20N`。第一平面的每个值已经确认：

```text
low 16 bits   tile index，范围 0..15
high 16 bits  one-based DBL tile-group ID；0 表示不绘制
```

原程序的 VWF 层名表与移动/视线读取路径交叉验证了五层的主要语义：

| 层 ID | 原版语义 | 已验证的运行时关系 |
|---:|---|---|
| 1 | 地块索引层 | 地表组/地块索引，用于绘制 |
| 2 | 视线障碍层 | 视线与直射线格检查的遮挡数据 |
| 3 | 移动障碍层 | 移动碰撞与八方向寻路的权威平面 |
| 4 | 事件设定层 | 十二个正式关卡的全部单元均为 0 |
| 5 | 手动移动障碍修正层 | 编辑期修正标记；原版运行时移动检查仍以 L3 为准 |

L2 和 L3 的已知格值约定为：`0` 开放，`1` 静态障碍，`scene_index + 1000` 表示相应 SLIST scene 的占用。后一种不能在转换时永久压平为静态墙：移动角色、死亡单位或被移除实体的占用需要按生命周期忽略或清除。

L5 不是一张需要在运行时逐格 OR 到 L3 的附加碰撞层。这样合并会产生原版不存在的封路。详细的复刻约束和测试边界见 [导航、视线与战斗边界](NAVIGATION_AND_COMBAT.md)。

十二关的 SLIST 偏移：

| 关卡 | Grid | 头部参数 | SLIST 偏移 |
|---:|---|---:|---:|
| 000 | 155×140 | 64 | 434331 |
| 001 | 128×256 | 16 | 655691 |
| 002 | 100×120 | 64 | 240331 |
| 003 | 128×200 | 16 | 512331 |
| 004 | 170×200 | 16 | 680331 |
| 005 | 120×200 | 64 | 480331 |
| 006 | 120×200 | 16 | 480331 |
| 007 | 150×200 | 16 | 600331 |
| 008 | 90×120 | 16 | 216331 |
| 009 | 100×200 | 64 | 400331 |
| 010 | 150×210 | 16 | 630331 |
| 011 | 100×200 | 64 | 400331 |

## `M37NAV1` 导航/视线中间格式

转换器不让 Godot 直接解析 VWF，而是为每关写出 `navigation.bin`。文件完整保留 L2—L5 的 `uint32` 值，不在导入时合并语义不同的层：

```text
char[8] magic = "M37NAV1\0"
uint32  version = 1
uint32  width
uint32  height
uint32  cell_width
uint32  cell_height
uint32  layer_count = 4

固定顺序的四个块：
  uint32 layer_id                 // 2, 3, 4, 5
  uint32 values[width * height]
```

所有数值为小端。已知版本的单元尺寸是 32×16，但文件显式保存该尺寸，不要由运行时硬编码。`level.json.navigation` 同时写入相对路径、schema 版本、网格/单元尺寸和语义层 ID，Godot 加载器会将它们与二进制头交叉校验。

## SLIST1 场景实体

SLIST1 位于 VWF 地形之后。当前解析器确认：

- 固定头 137 字节，格式版本为 2；
- 头中再次保存 grid 尺寸、参数和 viewport，并与 VWF 头交叉校验；
- 每个场景槽先有 0/1 presence 标志；
- 已知实体记录版本为 5，包含 DBL ID、世界坐标、参考坐标、出生方向/死亡/匍匐状态和扩展数组；
- 可选巡逻块签名为 1001、版本为 1；原先暂称 `behavior` 的字段现已确认是当前航点索引，原先暂称 `origin` 的两个字段是当前航点的缓存世界坐标，并非路线原点；
- 十二个正式关卡均能解析到精确 EOF，实体 DBL ID 均在有效范围内。

实体 prefix 的 `+44/+48/+56` 已确认分别是方向、死亡/存活状态和匍匐状态。扩展 presence 后固定保留 41 个 `uint32` actor 字段，再跳过 24 个已确认边界但未命名的尾字段；ext1/ext2/ext3 分别是警戒反应状态、默认攻击类型和当前生命值。十二关共导出 19,199 个实体；`level.json` 同时保留 DBL header、阵营、特殊感知、上述角色字段、世界/参考坐标、精灵预览和巡逻数据。

巡逻块的已确认顺序如下：

```text
uint32 signature = 1001
uint32 point_count
uint32 format_version = 1
point_count * { uint32 working_0, uint32 working_1 }
uint32 repeated_point_count
uint32 current_waypoint_index
uint32 persistent_flag
int32  cached_waypoint_world_x
int32  cached_waypoint_world_y
point_count * { uint32 waypoint_grid_x, uint32 waypoint_grid_y }
```

`M1937.exe` 的 `sub_4691E0` 按 `current_waypoint_index` 取出当前网格航点；`sub_469130` 在单位到达后让索引循环递增，并把下一个航点换算成缓存世界坐标。十二关中巡逻对象存在 780 次，其中 516 条路线非空；这 516 条记录的缓存坐标全部满足 `x = 32 * grid_x + 16`、`y = 16 * grid_y + 8`。另 264 个对象的点列为空，所以“存在巡逻对象”不能直接解释成“单位一定会巡逻”。

`persistent_flag` 对应原对象 `+0x0C`：十二关 780 条记录均为 1，构造器也默认写 1，但目前尚未找到把它作为巡逻启停开关读取的运行时代码。因此转换 JSON 以原始数值 `persistent_flag` 为准；`enabled` 只作为旧调用方的布尔兼容投影。`cached_waypoint_world` 是规范字段；旧 `origin` JSON 仍暂时输出为兼容别名，但不得再按路线原点解释。

| 关卡 | 实体 | 任务标记 | 爆破检测 | 出口检测 | 敌人出生 | 入口 |
|---:|---:|---:|---:|---:|---:|---:|
| m000 | 1,630 | 1 | 0 | 1 | 4 | 0 |
| m001 | 2,525 | 4 | 2 | 1 | 5 | 8 |
| m002 | 898 | 3 | 1 | 1 | 7 | 2 |
| m003 | 1,254 | 6 | 5 | 1 | 2 | 4 |
| m004 | 2,721 | 3 | 2 | 0 | 4 | 15 |
| m005 | 771 | 1 | 0 | 0 | 1 | 10 |
| m006 | 1,470 | 2 | 0 | 1 | 4 | 7 |
| m007 | 2,408 | 3 | 0 | 1 | 5 | 8 |
| m008 | 805 | 5 | 4 | 1 | 4 | 1 |
| m009 | 1,720 | 4 | 4 | 0 | 3 | 11 |
| m010 | 1,629 | 4 | 0 | 4 | 4 | 11 |
| m011 | 1,368 | 7 | 6 | 1 | 7 | 8 |
| **合计** | **19,199** | **43** | **24** | **12** | **50** | **85** |

任务锚点对应的 DBL ID 已确认：1001 藏尸状态、1008 视线检测、1010 入口、1011 敌人出生、1018 标记、1019 爆破检测、1020 出口检测。转换器会把这些实体另行写入 `task_anchors`，并逐关验证上述清单数量。

36 个爆破/出口检测锚点都能在 32 像素范围内唯一配对到可见任务标记；另有 7 个独立标记承担军服箱、剧情 NPC 等叙事位置语义。坐标和配对可以自动恢复，但具体对白、触发半径和演出时序仍需玩法验证。

DBL sprite 的 `header[0]` 还是运行时绘制队列的权威字段：1 为地面/固定背景，0 为与人物一起按 Y/基线排序的正常深度，2 为固定前景，3 为顶层。ResourceTool 将每个实体对应值写入 `level.json.database_header_values`；Godot 的 `ImportedLevelData` 现在保留并校验该数组，不再在解析时丢弃。m000 真实资产回归明确核对 22 个 DBL 336/337 庄稼底图为 queue 1、70 个 DBL 335 稻谷为 queue 0，因此田地底片不会覆盖人物，而独立稻谷仍能按前后关系遮挡。

## 十二关地形合成

`TerrainRasterizer` 使用 DBL 的 45 项 tile-group 顺序解析 VWF 第一平面，从对应 TLG 图集复制 32×16 tile。`m000` 的 155×140 网格生成 4960×2240 RGBA PNG；其余十一关按各自网格尺寸使用同一算法。group 0 按原程序行为保持透明，不会因为低 16 位恰好为 1—6 而误画地形。

ResourceTool 现会批量生成 `m000`—`m011` 的 `terrain.png`、`level.json` 和 `navigation.bin`，并写出 `levels/index.json`。Godot 可按启动参数或 `PageUp` / `PageDown` 加载十二关，并已具备基于 L3 的 A* 寻路、动态占位、基于 L2 的格线视线、敌人巡逻/感知/攻击，以及背包、投射物、type 8/10 世界对象、type 11 AI 状态和任务世界事件闭环。十二关第一版 `MissionAiCoordinator` 已提供带 `remake_editorial` 标签的协作/增援与难度调校。仍需恢复的是其余非角色实体精确足印、声音遮挡/尸体发现等高层 AI、特殊动作原版数值，以及用原版录像校准的逐关导演内容。

## 任务控制流恢复

VWF/SLIST 提供实体、巡逻和锚点，却不包含一份可直接提取的完整任务图；SAV 也按其已知结构精确结束，没有追加任务脚本。十二关目标关系来自“静态锚点 + 原程序任务控制流 + 简报文本”的联合恢复，规范化结果保存在 `game/data/missions.json`。

当前已恢复目标依赖、计数、限时、失败和胜利骨架。`m011` 的原程序初始化会反复覆盖爆破目标指针，导致实际只检查最后一个 scene 1353；复刻任务数据按简报把 scene 1348—1353 绑定为六个不同目标，并要求按 `scene_index` 去重计数六次。`MissionRuntime` 已在通用状态机前校验当前关卡 `scene_bindings` 白名单和锚点类型，世界系统不能绕过它直接提交场景事件；七个爆破关还按真实 DBL 998 数量声明预置或背包消耗策略。任务数据可为开场、目标、剧情锚点和胜利声明带来源标签的媒体 cue，当前只接入 m000、m006 与 m011 的首批触发点。详细证据、逐关图和自动/人工边界见 [任务恢复说明](MISSION_RECOVERY.md)。

## SLF 声音映射

`1937Sound.slf` 的固定头为 121 字节：

```text
offset 117  uint32le count = 126
offset 121  第一条记录

每条 260 字节：
uint32le unknown_flag
char gbk_name[256]
```

126 条记录的 `unknown_flag` 当前均为 1，但语义未知，因此代码保留为 `UnknownFlag`。126 个 GBK 名称全部映射到 GFL WAV；GFL 另有 `燃烧开始.wav` 和 `燃烧停止.wav` 两个未列入 SLF 的声音。

## 非正式关卡与污染文件

- `1937m012.vwf` 实际是 ZIP，内容属于 EA Sports 1997《FIFA 足球经理》中文文件；
- `1937m013.vwf`—`1937m015.vwf` 实际是 RIFF/CDXA MPEG 媒体；
- 原程序没有引用 012—015，导入器明确排除它们；
- `*.SAV` 和 `M1937.SI0` 是运行生成数据；已审计 SAV 按已知结构精确结束，没有附加任务图，`M1937.SI0` 中可识别的 IBLOCK 是 320×240 存档缩略图；
- `1937Intro.svt` 和 `GamekingLogo.svt` 是 MPEG Program Stream，可交给现代视频解码器。

## 验证方式与剩余研究

解析器测试由人工生成的微型二进制 fixture 覆盖正常和错误边界，不把批量原版字节提交到仓库。本地已知版本的批量审计还验证了 34/34 IBLOCK、45/45 TLG、980/980 SPR、2,775/2,775 动画组、11,898/11,898 帧、十二个 VWF/SLIST、19,199 个实体、1023 条 DBL 记录，以及 GFL/SLF 的完整引用关系。真实资产套件同时覆盖 DBL 绘制队列回归；各套件的当前检查计数以验证日志为准。

仍需研究的重点：

1. DBL 精灵元素数组与实体足印、交互区域之间的关系；
2. SLIST 扩展数组、L4 在其他工具/版本中的用法，以及 L5 的编辑器写入流程；
3. 攻击末帧命中已经由原程序路径确认并接入；仍需研究动作过渡、独立受伤动作和部分 triplet/lookup 参数；
4. 射击、救援、任务击毙/掉落、物品、爆破/占点和出口已经接入通用任务运行时；m008 提前引爆失败、m009 全关清敌修复语义和七关炸药策略已经定案，仍需校准逐关特定角色条件、触发节奏和演出；
5. 基础攻击/友军死亡警报已经接入；仍需研究声音遮挡、尸体发现、难度、剧情对白、镜头演出和存档格式。

社区研究线索：[Revora 的 Mission 1937 modding 讨论](https://forums.revora.net/topic/101296-help-mission-1937-modding-chinese-related-stuff/)。论坛附件及其中的原版提取资产不会进入本仓库。
