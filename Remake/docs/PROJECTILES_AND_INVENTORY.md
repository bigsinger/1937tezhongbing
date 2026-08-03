# 投射物、背包与世界交互物

本模块已经接入主场景，不再只是独立原型。玩家的世界攻击、原版直接数量武器栏、武器切换、原关卡拾取物、地雷和汽油桶共用一条可测试的数据驱动链路。没有导入 `LocalAssets` 时，合成对象和占位图形仍可运行；导入原版资源后，拾取物和汽油桶使用关卡中的真实 scene、坐标和转换纹理。

## 1. 世界投射物

攻击动作仍在最后一帧复核目标、射程和视线。attack type 1—7 只有在目标
actor 与攻击者的 32×16 导航格在两轴都相差不超过一格时才直接命中；
手枪、步枪、机枪、飞镖和弹弓的非相邻目标，以及所有手榴弹目标，都在最后
攻击帧发出 `projectile_requested`，由 `ProjectileWorld` 按 world tick
推进后结算。

| 攻击 | 类型 | 原版投射生命周期 |
|---|---:|---|
| 手枪 | 1 | effect 1 / mode 0，无飞行 actor 或 SPR；含首尾点 Bresenham 路径每 tick 前进 64 像素，先查 L3 actor、再查 L2 障碍，伤害 2 |
| 步枪 | 2 | 与手枪相同；attacker runtime type 1 的伤害为 16，其余为 2 |
| 机枪 | 3 | 与手枪相同，但坐标目标生成 3 条独立弹路；活动 actor 目标使用中心、−1°、+1°，纯坐标目标使用中心、−2°、+2°，每条伤害 2 |
| 飞镖 | 6 | effect 13 创建 actor 80 / 首匹配 GFL 251；沿含首尾点的整数 Bresenham 路径每个 world tick 前进 16 像素，先命中 L3 当前格的第一个有效 actor，再检查 L2 障碍，直接伤害 8 |
| 弹弓 | 7 | effect 14 创建 actor 81 / 首匹配 GFL 635；同一整数路径每 tick 前进 5 像素，碰撞顺序与飞镖一致，直接伤害 1；原版这里是直线模式 4，不是人为添加的弧线 |
| 手榴弹 | 9 | effect 2 创建 actor 57 / 首匹配 GFL 528；每 tick 前进 8 像素，以 `8t - trunc((8 / floor(path_count / 8)) × t²)` 修正视觉高度；飞行中忽略 L3 actor 和 L2 障碍，到终点后的下一次更新立即创建 actor 61 / 首匹配 GFL 19，不存在 0.35 秒落地延时 |

六类投射规则的起点也不再使用角色节点中心。`IEngineSprite::SetCurrentSerial`
会把当前攻击方向 SPR 组的 primary triplet 写入 actor `+0x44..+0x4c`，
tertiary triplet 写入 `+0x50..+0x58`；原版路径起始 X 为
`world_x + tertiary.x - primary.x`，直线投射物的等价视觉高度为
`primary.z - tertiary.z`。转换器、通用动作加载器和角色运行时现在共同保留
并使用这两组值，因此武器从当前动作精灵的原锚点发出。

mode 0/3/4 会被路径上第一个有效 actor 拦下，原程序没有先做阵营过滤，
所以友军同样可以挡弹。命中 actor、L2 障碍或终点时，effect 8 创建一次性
actor 60；首匹配 GFL 306 `火花效果.spr` 的 4 帧各保持 2 world tick，
播放完即销毁，进度可随存档恢复。actor 61 在 `128 × 64` 等距椭圆内造成 128 点伤害，
包括敌人、友军和投掷者；并发布 800 半径警报。其 GFL 19 主动画为 10 帧、
每帧 3 tick。投射物命中、爆炸警报、战斗状态文字和原版音效事件均接入主
战斗事件链；未结算路径索引、弧线 tick、SPR 高度和视觉帧会进入存档。

以上 delivery mode、步长、actor/GFL、直接伤害、碰撞顺序、抛物线公式、
actor 61 爆炸伤害/几何/警报和 SPR 发射锚点都来自原程序恢复结果，不再是
速度、碰撞半径、弧高或延时等重制默认。攻击类型 8/10 另有持久世界对象，
二者创建的 actor 62 主爆炸伤害、几何、特殊对象伤害带、警报范围及效果
粒子生命周期也已恢复；type 11 已按原程序注意力保持及释放条件实现。

## 2. 武器容器、角色物品背包与切换

`CombatInventory` 是动态角色武器和直接数量状态的权威来源，统一管理：

- 原攻击物品映射 `36..45` 与 `99`；
- m000—m011 共 660 个精确角色武器容器、761 个原版有序项目和 67 个
  空容器；其中 27 名可玩角色占 83 个项目；
- mode 0 逐次消费并在零时移除、mode 1 普通攻击耐久、mode 2 空枪保留；
- 已获得武器、当前武器以及版本化快照；
- 地雷 43、手榴弹 44、炸药 45 等世界项目的直接消耗。

`SquadUnit.magazine_ammo` 和 `reserve_ammo` 仅保留为旧存档/API 兼容镜像；
原版模式下前者显示当前项目的直接数量，后者恒为零。schema 2 存档保存数量模式、
拥有状态和当前武器；schema 1 的“弹匣 + 备弹”旧档会在读取时合并成一个直接
数量。敌方角色也保留原版 `+0x22C` 有序容器；`infinite_ammo` 对敌人只表示
`sub_456DF0` 的普通攻击不调用消费函数，不再表示“没有容器”。

`BackpackInventory` 另行实现 actor `+0x228`，不与上述 `+0x22C`
武器容器或 `field_inventory` 混用。`original_initial_item_inventory.json`
固化十二关 660 个精确动态角色、539 条有序物品记录，其中 27 名玩家共有
74 条；A 页显示当前选中角色自己的物品。弹药箱、医药箱、西瓜、中药和
服装的直接效果，丢弃、敌人拾取、死亡掉落及存档均已按恢复代码接线。
完整证据与物品表见
[原版角色物品背包恢复](ORIGINAL_ITEM_INVENTORY.md)。

当前数字键按原版项目次序处理，输入如下：

| 输入 | 行为 |
|---|---|
| `1` / `2` / `3` / `4` | 尝试选择匕首 39、弹弓 42、大刀 40、飞刀 41 |
| `5` / `6` / `7` | 尝试选择手枪 36、步枪 37、机枪 38 |
| `8` / `9` / `0` | 尝试选择 type 8 项目 43、手榴弹 44、type 10 炸药 45 |
| `W` / `A` | 打开右侧 276×421 五列武器栏/物品栏；选择格内项目后关闭栏位 |
| `Tab` / `Shift + Tab` | 在所选队员已经持有的武器中向前/向后轮换 |
| `Q` | 原版模式下无需换弹；仅兼容早期重制存档 |
| `B` 后左击阵亡敌人 | 执行当前复刻对原版“掩埋模式”的可玩解释；掩埋状态可存读档 |
| 左键拾取物 | 最近的所选队员自动寻路，进入原版 32×16 邻格范围后收入自己的容器 |
| `E` | 任务物件交互；保留早期试玩包的近距离拾取兼容入口。正式营救对象按指定角色与原版距离自动触发 |

数字键只会选择已经持有的项目，不会凭空授予。世界中的移动、攻击和特殊目标命令均由左键提交；右键只用于拖框选择，不提交移动或攻击。默认按住左 `Ctrl` 或 `↑` 再左击目标会进入强制目标/强制攻击路径，两条等价的按住通道也都可在设置中重映射。多选时命令会依次应用于各队员；界面左上方显示所选成员的当前武器、直接数量/耐久状态、生命和地雷数量。

type 11 的项目 99 没有原版数字快捷键，也不进入开局配置；它由古明使用
军服 54、在严格第 101 个角色 tick 切为 type 91/GFL 272 时自动取得，
脱下青衫 92 时移除。它与其他武器一样出现在 `W` 武器栏，不会在 `A` 页
重复出现。

## 3. 原关卡拾取物

`game/data/world_pickups.json` 不再根据显示名猜效果。DBL 精灵
`header[2]` 是运行时物品 ID；原程序 `sub_45AE10` 决定物品进入角色的
`+0x22C` 武器容器还是 `+0x228` 物品背包及其 mode，
`sub_453F70` 证明场景拾取每次加入 1 件。可复现证据保存在
`validation/baselines/mod/world-pickups-v1.json`，并由
`Test-OriginalWorldPickups.ps1` 在每次验证时与产品数据比对。
`sub_451020` 使用世界坐标与当前 SPR primary/宽高形成精灵点击框；
`sub_44FED0` 把命中的状态 3 世界对象提交为目标；`sub_456AB0` 在角色与
目标的 32×16 导航格两轴各相差不超过一格时转移容器并销毁源对象。因此
产品不再使用早期 36 像素圆形近似：左击远处拾取物会先 A* 接近，再自动
完成一次转移。

| DBL ID | 原显示名 | `header[2]` | 原容器/mode | 拾取结果 |
|---:|---|---:|---|---|
| 982 | 可拾取机枪 | 38 | 武器 / 2 | 增加 1 个机枪项目，不强制切换当前武器 |
| 983 | 可拾取弹药箱 | 46 | 背包 / 0 | 增加 1 个弹药箱；玩家之后在 `A` 栏使用 |
| 984 | 可拾取地雷 | 43 | 武器 / 0 | 增加 1 个地雷项目 |
| 986 | 可拾取手榴弹 | 44 | 武器 / 0 | 增加 1 个手榴弹项目 |
| 987 | 可拾取手枪 | 36 | 武器 / 2 | 增加 1 个手枪项目，不强制切换当前武器 |
| 988 | 放在地上的飞刀箱子 | 41 | 武器 / 0 | 增加 1 个飞刀项目 |
| 990 | 放在地上的军服箱子 | 54 | 背包 / 0 | 增加 1 件日军军服；m001 同时推进取得军服任务 |
| 993 | 放在地上的草药 | 51 | 背包 / 0 | 增加 1 份中药；拾取时不立即治疗 |
| 998 | 放在地上的炸药 | 45 | 武器 / 0 | 增加 1 个炸药项目 |
| 999 | 放在地上的医药箱 | 47 | 背包 / 0 | 增加 1 个医药箱；拾取时不立即治疗 |
| 1003 | 可爆炸汽油桶 | 53 | 场景爆炸物 | 保持可攻击场景物，不作为拾取物 |

所有拾取物都由距离最近且符合条件的所选队员收入自己的容器；左击后命令会
保持到邻格转移完成或被新的移动/攻击命令替换。没有选择时，兼容入口 `E`
仍会以所有存活队员作为候选交互者。弹药箱、中药、医药箱和军服都必须在
拾取后按原物品使用路径生效，满血角色也可以先收起治疗物。

### 3.1 任务爆破与角色炸药

DBL 998 的物品 45 明确位于拾取角色的武器容器，不是共享背包或
`field_inventory`。type 10 在攻击命中帧从该容器消费一次物品 45 并创建
actor 85；m003/m008 的原任务求值器只查询 type 98 严格 128 像素内是否
存在 actor 85，不会再从任务层扣一次。m001/m002/m004 则观察 type 98 的
生命是否归零，由手榴弹、油桶或定时炸药产生的真实 `128×64` 世界爆炸均可
满足，而对目标按 `E` 不会推进。

`missions.json` 继续保留来源为
`remake_policy_from_recovered_map_inventory` 的兼容策略，以便校验逐关地图
物资闭环和支持尚未恢复专用求值器的分支：

| 关卡 | DBL 998 拾取数 | 爆破目标数 | 当前策略 |
|---|---:|---:|---|
| m001 | 1 | 2 | 原生 type 98 生命判定：接受真实世界爆炸 |
| m002 | 1 | 1 | 原生 type 98 生命判定：物品 45 由部署动作消费 |
| m003 | 6 | 5 | 原生 type 85 严格半径判定：每处部署一份 |
| m004 | 0 | 2 | 原生 type 98 生命判定：地图无强造的背包炸药 |
| m008 | 4 | 4 | 原生 type 85 严格半径判定：每处部署一份 |
| m009 | 9 | 4 | `inventory_required`：每个目标消耗 1 份炸药 |
| m011 | 4 | 6 | `preplanted`：六目标修复后物资不足，视为预置炸药 |

没有专用原生求值器的 `inventory_required` 兼容目标会先汇总角色容器中的物品 45，再经
`MissionRuntime.publish_world_event()` 校验当前关卡和 scene 绑定；只有发布
成功且没有运行时错误后，才按“当前选中角色优先、其余队员随后”的顺序扣除，
并把目标标记为已激活。缺炸药、无效策略、未配置运行时或被拒绝的 scene
均不会扣除，也不会留下“幽灵完成”状态。该路径不得用于覆盖 m001/m002/
m003/m004/m008 的原生世界状态规则。

## 4. type 8/10 特殊部署物与汽油桶

type 8/10 世界对象和汽油桶走统一的世界爆炸结算，可伤害单位、护送角色和其他可爆物，因此支持油桶连锁爆炸。

- type 8 / 项目 43：选择后左击目标，在攻击命中帧部署 actor 84 / GFL 470 对象；对象创建后即进入 ACTIVE，存活 faction 1 目标进入 `32 × 16` 椭圆后触发 actor 62。
- type 10 / 项目 45：选择后左击目标，在攻击命中帧部署 actor 85 / GFL 900 对象；从创建起按 world tick 计时，第 100 tick 触发 actor 62。
- actor 62：在 `128 × 64` 等距椭圆内造成 128 点主伤害并发布 800 半径警报；runtime type 34/86/87/88/94/95/96/97 在 `384 × 192` 椭圆内、type 66/67/68/77/93 在严格小于 256 的欧氏半径内，各另受一次 128 点伤害。两组原视觉效果编号分别为 11 和 15；每组尝试 1—2 个 64×32 散布粒子，使用原 MSVCRT 随机序列并完整播放 5 轮。可生成粒子的实际寿命为 90 或 150 world tick。
- 汽油桶：DBL 1003 的 35 个关卡实例都是 runtime actor 53、初始生命 8。任意一次有效伤害令生命偏离 8 后，actor 53 在自己的下一次 world tick 按 `sub_4551B0` 置结束动作 1，并通过效果类型 5 创建 actor 62；因此它不是“扣至 0 才爆”。爆炸完整复用上述 actor 62 的 128 点主伤害、`128 × 64` 椭圆、特殊伤害带、800 警报和 GFL 20 动画。

项目 43/45、actor 84/85/62、GFL 470/900、type 8 的 faction 1 与 `32 × 16` 触发、type 10 的 100 tick，以及上述伤害/几何/警报/粒子寿命均来自恢复路径。汽油桶的 actor 53、生命哨兵 8、效果类型 5 和 actor 62 链路也已由 35 条 VWF 状态与 `sub_4551B0`/`sub_4656C0`/`sub_4554A0` 闭合。早期秒制通用 `LandMine` 重制状态机及其默认数据已经删除；项目 43 只走原版 type 8 / actor 84 路径。

## 5. 实现边界

主要文件：

| 文件 | 职责 |
|---|---|
| `game/data/projectile_profiles.json` | 1/2/3/6/7/9 六类投射规则及逐字段证据状态 |
| `game/scripts/legacy_projectile_rules.gd` | 原版含首尾点 Bresenham、步进 tick、格坐标与抛物线公式 |
| `game/scripts/legacy_explosion_rules.gd` | actor 61/62 的共同爆炸伤害、范围、警报和视觉身份 |
| `game/scripts/combat_projectile.gd` | 原版离散路径、L3→L2 碰撞、actor 60 命中火花、终点 actor 61、动画和版本化快照 |
| `game/scripts/projectile_world.gd` | 投射物生成、战斗候选与命中/爆炸信号 |
| `game/scripts/combat_inventory.gd` | 原版数量模式、多武器切换、旧档迁移和快照 |
| `game/data/original_initial_weapon_inventory.json` | 十二关 660 个精确角色的 761 个取证武器条目；含 27 名玩家/83 条子集 |
| `game/scripts/backpack_inventory.gd` | actor +0x228 有序物品、mode、丢弃和快照 |
| `game/data/original_initial_item_inventory.json` | 十二关 660 个精确角色的 539 个取证开局条目 |
| `game/data/world_pickups.json` | 真实拾取实体及 actor 53 汽油桶的数据配置；不含虚构通用地雷参数 |
| `tools/ResourceFormats/OriginalWorldPickupEvidence.cs` | 从 DBL 恢复并严格分类十类原版世界拾取物 |
| `validation/baselines/mod/world-pickups-v1.json` | MOD 数据库哈希、item ID、容器/mode，以及 35 个 actor 53 汽油桶和 actor 62 爆炸链的可复现基线 |
| `validation/baselines/mod/m001-mine-pickup-inventory-v1.json` | scene 2280 左击 scene 2096 后项目 43 的 `2→3` 稳定 MOD 运行基线 |
| `validation/baselines/mod/m000-pistol-attack-inventory-v1.json` | scene 1436 手枪攻击 scene 1598 后项目 36 的 `7→6` 稳定 MOD 运行基线 |
| `validation/baselines/mod/m010-rifle-attack-inventory-v1.json` | scene 1589 步枪攻击 scene 1126 后项目 37 的 `20→19` 稳定 MOD 运行基线 |
| `validation/baselines/mod/m010-machine-gun-attack-inventory-v1.json` | scene 1589 机枪攻击 scene 1126 后项目 38 的 `10→9` 稳定 MOD 运行基线 |
| `validation/baselines/mod/m004-dart-attack-inventory-v1.json` | scene 2629 飞镖攻击 scene 2685 后项目 41 的 `20→19` 稳定 MOD 运行基线 |
| `validation/baselines/mod/m007-slingshot-attack-inventory-v1.json` | 可控但实时 faction 1 的铁蛋 scene 2298 强制攻击相邻古明；项目 42 保持 `1→1`、目标生命 `8→7` |
| `validation/baselines/mod/m010-dagger-attack-inventory-v1.json` | scene 1591 匕首攻击 scene 1126，项目 39 保持 `1→1` 且目标生命 `8→0` |
| `validation/baselines/mod/m010-broadsword-attack-inventory-v1.json` | scene 1591 大刀攻击 scene 1126，项目 40 保持 `1→1` 且目标生命 `8→0` |
| `validation/baselines/mod/m010-grenade-attack-inventory-v1.json` | scene 1589 手榴弹攻击 scene 1126 后项目 44 的 `3→2` 稳定 MOD 运行基线 |
| `validation/baselines/mod/m010-mine-deploy-inventory-v1.json` | scene 1590 部署地雷后项目 43 `3→2`、运行时对象 `+1` |
| `validation/baselines/mod/m010-explosive-deploy-inventory-v1.json` | scene 1590 部署定时炸药后项目 45 `3→2`、运行时对象 `+1` |
| `validation/baselines/mod/*-world-item-v1.json` | 物品 33/48/49/52/82/83 的原版敌军拾取、保留/强制消耗、控制、分神和毒伤差分基线 |
| `tools/Compare-InventoryParityTrace.ps1` | 严格比较有序双容器、mode、当前攻击类型和所需数量变化 |
| `tools/Capture-InventoryParity.ps1` | 在隔离 MOD 与 Remake 中成对复测；只使用目标窗口/进程私有输入 |
| `../SDK/include/M1937SDK/Inventory.hpp` | MOD/工具可共用的原版物品容器路由与拾取物常量 |
| `../SDK/include/M1937SDK/Projectiles.hpp` | 0x44 投射物布局、六类规则、路径/弧线/SPR 锚点公式及 RVA 配套接口 |
| `game/scripts/field_pickup.gd` | 一次性场景拾取物 |
| `game/scripts/legacy_special_world_object.gd` | type 8/10 部署、触发/计时、爆炸、清理和快照 |
| `game/scripts/legacy_ai_control_effect.gd` | type 11 应用、刷新、解除和快照 |
| `game/scripts/inventory_grid_view.gd` | 276×421 右侧五列武器/物品栏 |
| `game/scripts/explosive_prop.gd` | actor 53 生命哨兵更新、actor 62 爆炸请求和存档状态 |
| `game/scripts/main.gd` | 输入、原 scene 生成、背包 UI、任务与警报接线 |

仍待恢复或校准的相邻内容包括：actor 61/62 与其他系统共享的完整全局随机
调用顺序，以及爆炸对地形/遮挡的原规则。汽油桶数值、触发时序和 actor 62 动画已经恢复。六类投射规则自身
的路径、步长、碰撞、伤害、普通命中 actor 60、终点爆炸和 SPR 发射锚点已经恢复。原版物品容器
`actor+552`、武器容器 `actor+556` 的布局、
数量模式和十二关开局内容已经恢复，不再把不存在的弹匣/装填时间或已确认的
医药箱/西瓜/中药直接效果列为待校准项。

## 6. 验证

`projectile_inventory_test.gd` 覆盖六类投射规则、11 个物品 ID、兼容背包切换/
快照、最后攻击帧发射、整数路径、逐 tick 步长、L3→L2 顺序、友军拦截、
SPR primary/tertiary 发射锚点、手榴弹终点 tick、actor 60 火花存读档、
actor 61 的 128 伤害和 `ProjectileWorld` 分流。`original_inventory_test.gd` 覆盖武器 mode
0/1/2、空枪保留、无换弹和 schema 1→2 迁移；`backpack_inventory_test.gd`
与 `original_item_runtime_test.gd` 覆盖独立物品容器、真实治疗/补给、A 页、
丢弃、敌人拾取和死亡掉落；`real_original_inventory_test.gd` 在真实十二关
逐一核对 660 个角色/761 个武器条目（含 27 名玩家/83 条子集），以及
660 个角色/539 个物品条目。
`world_interactables_test.gd` 覆盖原关卡拾取点击框、32×16 邻格、
远距离自动寻路和一次转移，以及 type 8 基础世界交互、汽油桶
受伤与连锁爆炸，以及七关爆破策略的 schema、真实 DBL 998 计数、成功后
扣除和失败不扣除；`legacy_mission_rules_test.gd` 与真实关卡短闭环额外固定
五关 type 98/type 85 求值、严格/包含 128 边界并拒绝 `E` 伪完成；
`legacy_special_actions_test.gd` 覆盖 type 8/10/11
生命周期，`legacy_explosion_visual_test.gd` 固定 actor 61/62 主动画、粒子
目录、随机序列、散布、缺失 type 102 和 90/150 tick 边界。各套件在日志中
报告当前检查数，文档不固定复制计数。真实导入资源存在时，`Verify.ps1`
还会重放上述十条攻击/部署轨迹和六条世界诱饵轨迹：严格核对有序双容器、
当前攻击类型和数量/耐久变化；近战额外核对目标 `8→0`，部署额外核对
运行时对象 `+1`，诱饵额外核对临时控制、分神以及毒酒严格第 81 tick 的
死亡边界。位置只作诊断，因为移动巡逻目标在两个独立进程中的启动相位不同。

```powershell
godot --headless --path Remake/game --script res://tests/projectile_inventory_test.gd
godot --headless --path Remake/game --script res://tests/world_interactables_test.gd
godot --headless --path Remake/game --script res://tests/legacy_special_actions_test.gd
godot --headless --path Remake/game --script res://tests/legacy_explosion_visual_test.gd
```
