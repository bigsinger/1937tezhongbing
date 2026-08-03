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
| `8BPS` | 207 | 14,347,924 | 解码 PSD version 1 扁平复合图为 PNG |
| `RIFF/WAVE` | 128 | 4,937,164 | 复制为本地 WAV |
| `TLG1` | 45 | 685,381 | 解码完整图集 PNG |
| `IBLOCK` | 34 | 9,028,443 | 解码完整 PNG |

WAV 共约 128.6 秒，以 22050 Hz/16-bit 单声道为主，少量为 8-bit 或 11025 Hz。

### MOD 的原流程文字简报

最终方案不再清空简报资源或显示额外窗口。`ResourceTool
install-text-briefings` 读取 `Mod/关卡名称.json`，把十二关文字绘制为
640×480 RGB565，使用本项目的 LZO1X 编码器封装为 IBLOCK，再重建成对
GFL：

- `Intro_000.psd`—`Intro_011.psd`（原索引 1048—1059）原位替换；
- 所有原有名称、属性、非目标载荷及数字索引保持；
- 完成后用 `GflArchive.Open(resource, index)` 逐项重读验证。

```powershell
dotnet run --project .\tools\ResourceTool -c Release -- `
  install-text-briefings .\Mod\关卡名称.json `
  .\Mod\1937Resources.GFL .\Mod\InterMedia.GFL `
  .\输出\1937Resources.GFL .\输出\InterMedia.GFL `
  E:\1937\text-briefing-previews
```

仓库入口 `Patch/tools/Update-TextBriefings.ps1` 还会在生成成功后以同卷
临时文件成对替换 Mod 资源，异常时恢复备份。最终稳定 MOD 归档仍为
1,394 个条目，不追加不存在的第 13—15 关资源；受支持 profile 会同时
校验 GFL/伴随索引和十二个正式 VWF 的哈希。连续生成哈希一致。合成
fixture 覆盖 LZO1X/IBLOCK 往返、原位替换、非目标索引保持和伴随索引重读。

`strip-briefings` 作为容器研究与回归工具继续保留，但不再用于发布产品。

## LZO1X、RGB565 与旧引擎兼容行为

IBLOCK、TLG 内嵌图像和 SPR 帧使用 LZO1X 压缩。解码器执行严格长度和回引用检查，同时复现原引擎会接受的“目标图像已经完整、压缩流末尾仍有少量 slack”行为；它不会把任意损坏流当成有效数据。

颜色平面解压后是小端 RGB565，转换为 RGBA32。SPR 中没有显式 alpha 平面的 direct-surface 帧使用 RGB(0,0,0) 作为 DirectDraw source color key；带 alpha 平面的帧必须保留 alpha 数据，包括不透明黑色像素。这个区分修复了早期预览中的黑色矩形背景。

## Photoshop PSD 扁平复合图

207 个 `8BPS` 条目全部是 PSD version 1、8-bit RGB。转换器跳过颜色模式、
图像资源和图层/蒙版区，只读取文件末尾与原游戏实际显示一致的扁平复合图；
它同时支持原始平面和 PackBits 逐通道逐行压缩。每行压缩长度、PackBits
字面量/重复段、目标宽度、尾部字节和尺寸上限均严格校验。

输出位于 `converted/psd/<GFL index>.png`，资源总索引的
`psd_composites` 字段保留原名称、数字索引和相对路径。顶部角色/弹药格、
底部 HUD、角色头像、武器物品图标、菜单按钮及其亮态因此可以直接复用原画。合成测试覆盖 raw
RGB、PackBits RGBA、PNG 写出、截断数据和不支持位深，且不包含原游戏字节。

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

全部文件共 2,775 个 frame group、11,898 帧，980/980 精确解析到文件末尾；其中 194 帧带独立 LZO alpha 平面，其余帧按黑色透明键处理。导入器为每个 SPR 输出一张首帧预览、一份 `schema_version: 4` 的 `sprite.json`，并为每组输出横向 `atlas.png` 和全部逐帧 PNG。

frame group 的三个序列化 triplet 顺序已经由文件布局、运行时字段写入和
实际移动轨迹交叉确认：

```text
文件第 1 组 triplet  -> runtime primary
文件第 2 组 triplet  -> runtime tertiary
文件第 3 组 triplet  -> runtime secondary
```

早期 `sprite.json` schema 1/2 曾把后两组名称对调。schema 3 修正转换器
字段名；schema 4 保留该修正，并增加帧组的 `sound_slf_index` 与
`sound_gfl_index`。Godot 加载器仍会对 schema 1/2 做显式交换迁移；schema
1—3 仍可加载，但因没有可验证的 GFL 声音身份而禁用精确帧音效，不能靠文件名
猜测。合成解析测试用三组互不相同的值固定文件顺序，真实资源门禁还要求所有
运行时可达的 walk/crawl 方向都能取得合法 secondary 运动分量。

### 三套 lookup 的原版语义

frame group 的 `parameters[5]` / `parameters[6]` 是 lookup 的列数和行数。
`sub_427560` 把三套表分别装入运行时 frame group 的 `+0x08`、`+0x0c`
和 `+0x04`。访问器与 actor 网格写入路径已经逐条交叉确认：

| 文件/旧清单字段 | 运行时字段 | 原版用途 |
|---|---:|---|
| `first_lookup` | `+0x08` | Layer 3 移动占位遮罩 |
| `second_lookup` | `+0x0c` | Layer 2 视线占位遮罩 |
| `row_lookup` | `+0x04` | 每个贴图列的绘制遮挡基线 |

前两套遮罩按行优先排列，非零值表示占用。原版
`sub_451060/sub_451090` 使用当前 actor 格坐标和 primary triplet 计算遮罩
左上角：

```text
mask_left = actor_cell_x - trunc(primary.x / cell_width)
mask_top  = actor_cell_y - trunc(primary.z / cell_height)
```

随后 `sub_451B70/sub_451FA0/sub_452360` 分别增补、登记和移除遮罩。
Remake 现在会在站立、行走、奔跑、匍匐、攻击、主动动作及朝向改变时，把
当前组的两套遮罩原子替换到动态 Layer 3/Layer 2 overlay；替换会去重、重绑
目标格预留，并清除旧动作/旧朝向留下的 ghost cell。没有合法 lookup 元数据
时才沿用 VWF scene 足印。`row_lookup` 已完整保留并确认是
`sub_44D980/sub_44E2D0` 的逐列排序基线。原版以 `sub_424F10` 把帧裁成
32 像素列（末列可短），按
`reference_y - primary.z + row_lookup[column]` 建立记录，
`sub_44E000` 稳定升序后由 `sub_44EF50` 绘制。Remake 对非均匀表使用缓存
AtlasTexture 分列，对均匀表保持一个 draw item；静态场景、移动 actor、
177 个门状态（97 个关闭、80 个已开放）、拾取物、爆炸物和特殊世界对象都使用相同规则。
`row_lookup` 不能误用于碰撞。

三个 triplet 的 middle 分量也全部保留。980 个真实 SPR 的 primary/tertiary
middle 均为 0；secondary middle 的全量分布是
0:1233、1:1293、2:241、3:8。`sub_455E30` 根据移动模式选择 actor
`+0xB4/+0xC0/+0xCC` 的 walk/run/crawl triplet，只读取第 0/2 分量并保持
`world_height` 不变。十二关没有非二维消费者；这些 middle 仍作为兼容
元数据无损保留，但不映射成额外速度、高度或遮罩锚点。

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

组内帧顺序、尺寸、三个 triplet、lookup 数组和其他参数均写入清单。Godot
通用加载器可以加载任一已知非保留动作的八方向组；玩家与敌人已接入
`run`/`walk` 和 `stand`。每帧实际保持
`0.085 × (parameters[2] + 1)` 秒，不再使用统一帧长。原程序
`sub_41C060/sub_41C190` 已确认把 current serial 的 primary triplet 复制到
actor `+0x44..+0x4c`，tertiary triplet 复制到 `+0x50..+0x58`；
`sub_463290` 使用两者的 X 差和 Z 差建立投射物，所以运行时加载器会保留
这两组值。actor 移动则读取 secondary 的第 0/2 分量作为 60 Hz 每 tick
的独立 X/Y 上限；常见 walk/crawl 值 `[2,1,1]` 对应 120/60 px/s，
run 为三倍的 360/180 px/s。攻击、投掷、近战和死亡的末帧提交已经接入，
仍需继续恢复的是动作之间的全部原版过渡；非致命伤已由原函数确认没有独立
反馈写入。

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

实体 prefix 的 `+44/+48/+56` 已确认分别是方向、死亡/存活状态和匍匐状态。扩展 presence 后固定保存 41 个 `uint32` actor 字段。`sub_453FE0` 证明它们不是一段连续的运行时结构，而是依序写入 `RuntimeActorV1` 的 41 个非连续偏移。此前把 ext1 标成“反应状态”、把 ext8 标成“阵营”的解释均已纠正：ext1 是 `+0x250` 接敌状态，真正的反应状态是 ext23/`+0x25C`；阵营来自 DBL，ext8 是 `sub_455760` 所绘计时进度条的活动标志。

当前已接入的玩法字段还包括：ext5/6/8 的计时动作上限、计数和进度显示；ext10 以 `scene_index` 保存的追随目标；ext11 丢到地面的物品数量；ext15 已接受的地面坐标移动命令；ext24 五步局部搜索计数；ext31 L2/L3 动态占位开关；ext32/33 重合双航点守卫的固定朝向及恢复开关；ext40 m002/m004 一次性护送招募完成标志。它们分别由 `sub_4553B0`、`sub_455760`、`sub_45D2A0`、`sub_4583F0`、`sub_458A80`、`sub_45E4B0`、`sub_451B70`、`sub_469820`、`sub_45E950`、`sub_4590E0` 和 `sub_459290` 的读写路径证明。现只剩 ext19/`+0x21C` 与 ext30/`+0x274` 两个槽尚未发现正式 actor 消费者，二者在十二关及现有七份 SAV 中也始终为 0，继续按偏移命名而不猜测。其后的 24 个值会被原加载器读入临时区后丢弃；解析器仍完整保留它们以支持审计和无损往返，十二关 19,199 个实体中的这些尾字段均为 0。

十二关共导出 19,199 个实体；`level.json` 同时保留 DBL header、阵营、特殊感知、上述角色字段、世界/参考坐标、精灵预览和巡逻数据。41 个字段中有 22 个在正式关卡或存档样本中出现过非零值。

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

对场景拾取精灵，`header[2]` 是原运行时物品 ID。ResourceTool 的
`world-pickup-baseline` 命令直接读取稳定 MOD 的 DBL，再按已恢复的
`sub_45AE10` 分支输出角色武器/背包容器和 mode，并按 `sub_453F70`
固定每次拾取数量为 1。当前基线覆盖 DBL 982/983/984/986/987/988/
990/993/998/999 和场景爆炸物 1003；持续验证会拒绝产品数据中任何
“立即治疗、猜测备弹或共享任务库存”的旧语义。

## 十二关地形合成

`TerrainRasterizer` 使用 DBL 的 45 项 tile-group 顺序解析 VWF 第一平面，从对应 TLG 图集复制 32×16 tile。`m000` 的 155×140 网格生成 4960×2240 RGBA PNG；其余十一关按各自网格尺寸使用同一算法。group 0 按原程序行为保持透明，不会因为低 16 位恰好为 1—6 而误画地形。

ResourceTool 现会批量生成 `m000`—`m011` 的 `terrain.png`、`level.json` 和 `navigation.bin`，并写出 `levels/index.json`。Godot 可按启动参数或 `PageUp` / `PageDown` 加载十二关，并已具备基于 L3 的原版反向寻路、动态占位和窄通道会车、七组门的 closed/open 差分足印、基于 L2 的格线视线、敌人巡逻/感知/攻击、640 参数坐标警戒、五点局部搜索、尸体发现/type 93 增援，以及背包、type 1/2/3/6/7/9 原版坐标投射规则与 actor 60 命中火花、type 8/10 世界对象、actor 62 的五轮效果粒子、type 11 注意力保持状态和任务世界事件闭环。十二关 117,112 个静态 Layer 3 格与 6,710 个编码非角色 scene 足印已进入真实运行时逐格门禁；第一版 `MissionAiCoordinator` 提供带 `remake_editorial` 标签的协作/增援与难度调校。仍需恢复的是普通敌军警戒与持久巡逻脚本的精确仲裁、特殊 actor 覆盖、全局随机调用顺序，以及用原版录像校准的逐关导演内容；声音遮挡不是原版普通警戒规则。

## 任务控制流恢复

VWF/SLIST 提供实体、巡逻和锚点，却不包含一份可直接提取的完整任务图；SAV 也按其已知结构精确结束，没有追加任务脚本。十二关目标关系来自“静态锚点 + 原程序任务控制流 + 简报文本”的联合恢复，规范化结果保存在 `game/data/missions.json`。

当前已恢复目标依赖、计数、限时、失败和胜利骨架。`m006`、`m008`、`m009`、`m011` 对实际控制流与按简报修复的设计意图提供显式双规则：例如 m006 默认要求强子取得孙大麻子携带的物品 101，m008 默认没有额外手动引爆步骤，m011 默认检查 scene 1353 后仍要求老赵和强子抵达 scene 1359；`repaired` 才启用补写的接头/引爆/全清敌/六目标等流程。`MissionRuntime` 已在通用状态机前校验当前关卡 `scene_bindings` 白名单和锚点类型，世界系统不能绕过它直接提交场景事件；七个爆破关还按真实 DBL 998 数量声明预置或背包消耗策略。任务数据可为开场、目标、剧情锚点和胜利声明带来源标签的媒体 cue，当前 m006 接头提示只存在于 `repaired` 规则。详细证据、逐关图和自动/人工边界见 [任务恢复说明](MISSION_RECOVERY.md)。

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

SPR frame group 的 `parameters[8]` 是一基的 SLF 序号，0 表示没有声音。
`sub_427C80` 在调用 `sub_40B800` 前将正数减 1，因此转换器必须先按 SLF
文件名与 GFL WAV 做唯一匹配，再把一基 SLF 序号和实际 GFL 索引同时写入
schema 4；缺失或同名歧义会直接令导入失败。已知 2,775 个组中 1,137 个组
引用声音，共覆盖 52 个不同的 SLF/GFL 对。

帧触发时机来自 `sub_41D6F0`：action 0 进入第 2 帧时请求一次；action
5/6/9/10/12/13/14/15 进入末帧时请求一次；其余非零 action 在每个 actor
更新中请求。后者并非反复重启声音，原声音对象会按同一帧请求数启动足够的空闲
DirectSound buffer。Remake 对人物、爆炸主体和每个燃烧粒子采用相同规则，并
按请求实例聚合，避免每帧重新分配播放器或抢占仍在播放的音效。

## 非正式关卡与污染文件

- `1937m012.vwf` 实际是 ZIP，内容属于 EA Sports 1997《FIFA 足球经理》中文文件；
- `1937m013.vwf`—`1937m015.vwf` 实际是 RIFF/CDXA MPEG 媒体；
- 原程序没有引用 012—015，导入器明确排除它们；
- `*.SAV` 和 `M1937.SI#` 是运行生成数据，不属于关卡；
- `1937Intro.svt` 和 `GamekingLogo.svt` 是 MPEG Program Stream，可交给现代视频解码器。

## 原版 SAV/SI

`*.SAV` 已确认为完整 VWF 世界快照，而不是未知前缀或附加块。它沿用同一
VWF 头、五层地形和 SLIST1，并在已知结构末尾精确 EOF。原版会重写 L2/L3
中的动态角色足印，因此存档归属关卡必须只用不变的 L1 地表层 SHA-256
识别，并要求在 m000—m011 中恰好匹配一关。

SLIST 实体差分确认 `reference_x/reference_y` 保存当前世界位置，
`world_x/world_y` 仍可保留初始/编排值；方向、生死、匍匐、ext1 接敌状态、
ext2 默认/当前所选攻击、ext3 当前生命、ext18/20 目标坐标、ext21/22 搜索计时、
ext23 反应状态以及中毒、催眠、尸体发现和换装恢复状态均可直接恢复。实体后的四个辅助数组不是
逐项交错结构，而是：

```text
presence
count
uint32 item_ids[count]
uint32 quantities[count]
uint32 quantity_modes[count]
```

数组 0 对应当前背包（运行时 `+0x228`），数组 1 对应当前武器
（`+0x22C`）；数组 2/3 属于模板/兴趣状态，不能误当第二份玩家库存。

离线查询单条 DBL 身份时不需要启动游戏或打开 IDA。`ResourceTool inspect-dbl`
可按数据库 ID、运行时类型或两者组合筛选，并输出资源名、显示名、类别、元素数
及完整 header：

```powershell
dotnet run --project .\tools\ResourceTool -c Release -- `
  inspect-dbl .\Mod\1937Database.dbl --runtime-type=101
```

无匹配时返回退出码 3；重复筛选器、负数或非整数会直接拒绝。该命令用于定位
m006 的 DBL 1021/runtime type 101 文件袋等动态对象，不会修改输入文件。

同编号 `M1937.SI#` 是无外层签名的嵌入 IBLOCK，固定为 320×240 RGB565，
并在图像负载后精确 EOF。`LegacySaveSnapshot`、`LegacySavePreview` 和
`ResourceTool import-save` 共同把这些状态转换为 Remake schema 1。
三组正式 SAV/SI 已通过产品存档加载器和真实转换关卡恢复门禁；详细用法及
无法从世界快照唯一推出的任务历史边界见
[原版 SAV/SI 存档导入](LEGACY_SAVE_IMPORT.md)。

## 验证方式与剩余研究

解析器测试由人工生成的微型二进制 fixture 覆盖正常和错误边界，不把批量原版字节提交到仓库。本地已知版本的批量审计还验证了 34/34 IBLOCK、45/45 TLG、980/980 SPR、2,775/2,775 动画组、11,898/11,898 帧、十二个 VWF/SLIST、19,199 个实体、1023 条 DBL 记录，以及 GFL/SLF 的完整引用关系。运行时角色门禁进一步把 772 名已恢复角色关联到 39 个原 SPR，实际加载 212 套动作、1,664 组、9,896 帧；其中 204 套为完整八方向，8 套车辆动作保留原生四方向，并逐组核对 serial、源顺序、primary/secondary/tertiary triplet、绘制锚点、时序及 atlas/frame 几何。门禁还固定 AI 可达的 30 套 `stand_action`（240 个方向、1,912 帧）和 attack type 8/10 可达的 1 套 `active_action`（8 个方向、72 帧），防止资源仍在仓库但状态机无法使用的“假接入”。十二关结构化 fidelity baseline 同时固定源 VWF/DBL 身份、转换地形/导航 SHA-256、四绘制队列、敌军/巡逻/特殊感知、世界拾取、任务锚点和 258 个关键 scene；PowerShell 重建校验与 Godot 实际加载校验均进入真实资产门禁。各套件的当前检查计数以验证日志为准。

仍需研究的重点：

1. DBL 精灵元素数组与实体足印、交互区域之间的关系；
2. SLIST ext19/`+0x21C` 与 ext30/`+0x274` 的潜在休眠消费者、L4 在其他工具/版本中的用法，以及 L5 的编辑器写入流程；
3. primary/tertiary 的投射锚点、secondary 第 0/2 分量的 60 Hz
   角色移动、first/second lookup 的动态 Layer 3/Layer 2 足印、secondary
   middle 的消费者边界和 RowLookup 逐列稳定遮挡已经由原程序路径、全量
   统计、MOD 轨迹与十二关像素差分确认并接入；仍需研究少数特殊攻击过渡和
   全局随机调用顺序；
4. 射击、救援、任务击毙/掉落、带拾取者的物品、爆破/占点和出口已经接入通用任务运行时；m006/m008/m009/m011 稳定/修复双规则、必要队员/护送者、m010 四区存在性和七关炸药策略已经定案，仍需校准触发节奏和演出；
5. 原版 SAV/SI 的世界快照、缩略图、角色/容器差分、接敌/反应状态、目标坐标、
   尸体发现和中毒/催眠计时的单向导入已恢复；仍需研究声音遮挡、难度、剧情对白与镜头演出。

社区研究线索：[Revora 的 Mission 1937 modding 讨论](https://forums.revora.net/topic/101296-help-mission-1937-modding-chinese-related-stuff/)。论坛附件及其中的原版提取资产不会进入本仓库。
