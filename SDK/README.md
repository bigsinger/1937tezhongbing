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
- `mission-routes.json` 统一描述 1—15 关的选择器编号、原引擎任务、
  VWF 文件要求与固定字符串重定向；
- CI 会重新生成并比对产物，同时扫描代理、探针和编辑器，禁止复制已知
  裸 RVA。

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
