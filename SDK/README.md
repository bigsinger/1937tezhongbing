# M1937SDK

M1937SDK 是面向《1937 特种兵》原版 32 位引擎补丁/插件的原生 C++ SDK。
它借鉴 YRpp 的“用头文件固定原引擎类型与地址”做法，但不直接使用不可重定位
的绝对地址：所有符号均采用 **M1937.exe 模块基址 + RVA**，并在写入前校验
PE 指纹和原始指令字节。

## 当前能力

- 固定唯一受支持绿色版 `M1937.exe` 的 SHA-256、文件长度、PE 时间戳、
  映像大小和入口 RVA；
- 以类型安全接口访问当前关卡、逻辑/渲染分辨率、原版鼠标状态和任务说明
  确认标志；
- `Input.hpp` 固定完整 DIK 扫描码、按下/松开/按住相位、输入状态块偏移、
  鼠标三态、GFL 16 光标 serial，以及客户区边缘与 `limit/8` 卷屏公式；
- 集中维护启动、选关、听觉、警报传播、菜单轮询和安全绘制等已验证地址；
- 提供“期望字节匹配后才写入”的补丁、32 位立即数和相对跳转 API；
- 固定 VWF 版本 5 场景前缀、扩展字段和巡逻动态数组布局；
- 固定 S/B 的目标过滤、type 90/78 与 GFL 341/64、32×16 邻接格、
  100 计数上限/第 101 tick 完成，以及相关命令字段和函数入口；
- `WorldItems.hpp` 固定物品 33/48/49/52/82/83 的敌军 runtime type
  接受矩阵、近区可见性要求、消费策略、随机分神上限、木偶/毒酒 tick，
  以及相关 actor 字段和九个反编译入口；
- `OriginalEnemyAI.hpp` 固定原版枪声的严格 640 参数方向边界
  `(640*cos(a), 320*sin(a))`、type 91 排除、只传播坐标而不传播目标
  指针，以及五次 `±31×±15` 局部搜索、40—79/40—199 计数区间和
  16 像素世界边界；
- `Projectiles.hpp` 固定 type 1/2/3/6/7/9 的 effect/mode、
  64/64/64/16/5/8 步长、actor/GFL、直接伤害、L3→L2 碰撞顺序、
  actor 60 命中火花、0x44 运行时投射物布局、Bresenham/抛物线公式和
  SPR primary/tertiary 发射锚点；
- `OrdinaryCombat.hpp` 固定 attack type 1—7 的直接 actor 伤害、
  步枪/匕首 attacker runtime type 例外、32×16 目标格门、机枪活动目标
  ±1°/纯坐标 ±2° 三路散布，以及八类 target runtime type 的低于 32
  伤害免疫；
- `address-catalog.json` 是地址的唯一机器源；生成器同时产出 C++ 头文件
  和 C# 探针常量；
- `mission-routes.json` 统一描述 1—12 关的选择器编号、原引擎任务和
  VWF 文件要求；
- `schemas/runtime-parity-trace-v1.schema.json` 固定 MOD 与 Remake 共用的
  运行轨迹格式，供位置、朝向、武器、背包、任务与 AI 行为逐项差分；
- `schemas/runtime-actor-identity-catalog-v1.schema.json` 固定原版活动对象
  到 VWF scene/DBL 的证据映射，禁止用运行时数组下标猜 scene；
- CI 会重新生成并比对产物，同时扫描代理、探针和编辑器，禁止复制已知
  裸 RVA。
- 提供不可变最后目击观察、有界增援/搜索/截击策略及难度调校类型；
- 提供版本化世界事件、任务 schema 和 x64 原生插件 ABI；
- 附带可编译示例插件和独立任务 sidecar 主机。

## 使用

```cpp
#include <M1937SDK/M1937SDK.hpp>

auto module = m1937::sdk::ModuleView::current_process();
if (!module.is_supported())
    return;

m1937::sdk::RuntimeState runtime(module);
const auto mission = runtime.current_mission();

m1937::sdk::patch::immediate_i32(
    module,
    m1937::sdk::rva::close_hearing_radius_immediate,
    128,
    192);
```

构建并验证：

```bat
SDK\build.cmd
```

手工更新机器清单后先重新生成：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File SDK\tools\Generate-SdkArtifacts.ps1
```

生成物包括：

- `include/M1937SDK/Addresses.hpp`
- `include/M1937SDK/MissionRoutes.hpp`
- `generated/M1937Addresses.cs`
- `generated/M1937MissionRoutes.cs`
- `Patch/src/level-selector/关卡名称.json`

跨运行时轨迹不是地址清单生成物；其 schema 由 SDK 版本化维护，MOD
只读探针与 Remake 回放器共同消费。已证明的原版对象映射才能写入轨迹，
运行时活动对象数组下标不得直接冒充 VWF `scene_index`。

第一关身份目录由
`Remake/tools/Build-ModRuntimeIdentityCatalog.ps1` 生成并由
`Test-ModRuntimeIdentityCatalog.ps1` 校验。当前 62 个动态阵营对象中
54 个已一对一解析，8 个脚本编队对象保留 unresolved。字段语义必须保持：
`RuntimeActorV1 +0x064` 是对应 VWF
`database_header_values[2]` 的运行时类型，不是 DBL id；实际 DBL id 是
`database_entry_id`。`+0x1C0` 已由 54 个身份与自然接敌扣血序列证明为
当前生命值，`+0x20C` 与所有已解析 VWF 对象精确对应，证明为默认攻击类型。
46 名已解析敌军已用于 m000 巡逻差分门禁。

不要直接编辑这些文件；`Test-SdkSingleSource.ps1` 会验证它们与两个 JSON
机器源一致。

验证程序会以离线方式读取 `Mod\M1937.exe`，检查 PE 身份、关键函数签名、
原始关卡文件名和已建模结构的 `static_assert`。SDK 不会在不兼容版本上
“猜地址”；若要支持另一发行版，应新增独立版本描述和签名，而不是覆盖当前
常量。

## 与 YRpp 的关系

[`YRpp`](https://github.com/Phobos-developers/YRpp) 的核心价值是把多年
逆向所得的类、全局量和函数入口从零散魔数提升为
可复用的 C++ 头文件接口。M1937SDK 沿用这一工程思想，同时针对本项目补上
三项约束：

1. 地址使用 RVA，以兼容模块重定位；
2. 运行时先做版本/签名校验；
3. 未证明语义的字段明确保留为 `unknown_*`，不把推测伪装成确定事实。

首版 SDK 已由 `Patch/src/dinput-proxy` 实际引用，因此它不是只供阅读的
地址文档，而是 MOD 增强层的公共底座。

`RuntimeActorV1` 现已固定角色世界坐标、导航网格缓存、地面命令、
寻路状态、当前生命、默认攻击类型、接敌/丢失状态、解析后目标和八方向
朝向字段，以及 `+0x228` 物品容器、`+0x22C` 武器容器两个独立指针。
`RuntimeInventoryContainerV1`
固定项目 ID、数量、数量模式三数组和项目数的四字段 `0x10` 布局；
`Inventory.hpp` 进一步把 `sub_45AE10` 的完整容器分派表，以及十类真实
DBL 世界拾取物的 item ID、单次数量、目标容器和 mode 固化为 `constexpr`
接口。该表来自原程序指令与 `1937Database.dbl`，不是按物品名称猜测；
DBL 1003/物品 53 仍明确归入可受伤汽油桶生命周期，不会误作拾取物。
`CurrentActionId` 也进入单一地址目录。地址表同时收录地面命令分派点及
原版的移动重置/命令清理函数。
兼容层只在签名完全匹配时修复导航缓存，随后仍由原版 A*、动作状态机和
序列帧系统完成寻路与朝向更新。

`SpecialActions.hpp` 固化 type 8/10/11 的原版语义：actor 84/GFL 470
触发部署、actor 85/GFL 900 的 100 world-tick 定时部署、两者共用的 actor 62
主爆炸与两组特殊对象伤害带，以及 type 11 在 actor `+0x290` 的来源锚定
注意力保持。它同时说明 type 11 不消费项目 99、不是定时眩晕，并由来源移动或
目标战斗转换释放。actor 62 的效果 11/15 粒子类型、首匹配 GFL、64×32
散布、五轮动画寿命和默认状态 1 的 MSVCRT `rand()` 步进也由同一头文件
固定；runtime type 102 无匹配 SPR，必须保留“消费随机数但不生成粒子”的
语义。相关函数入口和 `SpecialAttentionSource` 全局量均由
`address-catalog.json` 生成到 C++/C# 常量，补丁和 Remake 不再各自复制魔数。

`Projectiles.hpp` 固化 type 1 手枪、type 2 步枪、type 3 机枪、type 6
飞镖、type 7 弹弓和 type 9 手榴弹：0x44 字节投射对象、12 字节路径点、
含首尾点 Bresenham、逐 world-tick 步长、原抛物线、普通弹 actor 60 /
GFL 306 火花、投射 actor/GFL 和终点 actor 61。`RuntimeActorV1` 的
`+0x44..+0x58` 现在按 current SPR serial 的 primary/tertiary triplet
命名；公共 helper 直接计算 `tertiary.x-primary.x` 发射偏移和
`primary.z-tertiary.z` 视觉高度。相关投射路径、命中 actor 和一次性特效
RVA 同样来自
`address-catalog.json`，可供补丁探针与 Remake 使用同一证据源。

`Commands.hpp` 固化 S/B 命令：S 只直接选择存活 faction 1 敌军，空地使用
唯一 actor 90 / GFL 341 并按当前扇区、LOS 和 CRT `rand()%2` 检测后消费；
B 只接受死亡 faction 1 敌军，使用命令类型 4、32×16 邻接格和严格
`counter > 100` 完成条件，并把两个库存容器复制到 actor 78 / GFL 64。

`Input.hpp` 固化 `DirectInputPoll` 的状态块布局及 HUD/世界消费者：数字键和
F2—F6 在按下沿提交，Esc/F1/F7/W/A/B/R/S/C/M 在松开沿提交，Ctrl/↑
持续采样；世界左键在按下沿提交，右键在松开沿取消一次性模式或结束框选。
它还定义 `mouse.spr` 的 0/1/2/3/4/6/8/9/10 serial、零基客户区边缘分类和
每更新 `velocity_limit / 8` 的卷屏加减速。相关函数和独立全局字段均来自
地址目录，补丁可复用而无需复制裸地址。

任务定义、事件、原子状态和原生插件开发详见
[`docs/任务Sidecar与原生插件开发指南.md`](docs/任务Sidecar与原生插件开发指南.md)。
