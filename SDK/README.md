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
- 集中维护启动、选关、听觉、警报传播、菜单轮询和安全绘制等已验证地址；
- 提供“期望字节匹配后才写入”的补丁、32 位立即数和相对跳转 API；
- 固定 VWF 版本 5 场景前缀、扩展字段和巡逻动态数组布局；
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
朝向字段，以及 `+0x22C` 武器容器指针。`RuntimeInventoryContainerV1`
固定项目 ID、数量、数量模式三数组和项目数的四字段 `0x10` 布局；
`CurrentActionId` 也进入单一地址目录。地址表同时收录地面命令分派点及
原版的移动重置/命令清理函数。
兼容层只在签名完全匹配时修复导航缓存，随后仍由原版 A*、动作状态机和
序列帧系统完成寻路与朝向更新。

任务定义、事件、原子状态和原生插件开发详见
[`docs/任务Sidecar与原生插件开发指南.md`](docs/任务Sidecar与原生插件开发指南.md)。
