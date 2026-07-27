# 任务 Sidecar 与原生插件开发指南

任务 sidecar 为原版引擎之外的新任务闭环提供稳定边界。主机只读受支持的
`M1937.exe` 世界对象快照，生成稳定事件；任务运行时和原生插件均不接收
引擎指针，也不能改写原版 SAV。

## 1. 架构

```text
M1937.exe（只读世界快照）
  └─ MissionSidecar.Host
       ├─ WorldEventDetector
       ├─ MissionRuntimeEngine
       ├─ 无激活、鼠标穿透目标叠加层
       ├─ 独立原子状态（绑定原 SAV SHA-256）
       └─ 可选 x64 原生插件 ABI
```

启动中心仅在以下条件同时满足时启动主机：

- `rungame.ini` 中 `MissionSidecar=1`；
- 所选关卡存在 `Missions/mNNN.m1937mission.json`；
- 主机发布产物存在；
- 游戏进程已启动。

插件还要求显式设置 `EnablePlugins=1`。任一条件失败时，游戏继续使用原版
任务逻辑。

## 2. 任务定义

正式 schema：

- `SDK/schemas/mission-sidecar-v1.schema.json`
- `schema_version = 1`
- `api_version = 65536`（`0x00010000`）

最小示例：

```json
{
  "schema_version": 1,
  "api_version": 65536,
  "id": "community-example",
  "title": "社区任务",
  "selector_level": 13,
  "engine_mission": 12,
  "objectives": [
    {
      "id": "destroy-radio",
      "title": "破坏电台",
      "event": "Exploded",
      "target_database_id": 1019
    },
    {
      "id": "evacuate",
      "title": "撤离",
      "event": "Evacuated",
      "depends_on": ["destroy-radio"],
      "subject_database_id": 924,
      "region": { "x": 48, "y": 416, "radius": 80 }
    }
  ]
}
```

事件枚举：

- `MissionStarted`
- `Reached`
- `Killed`
- `PickedUp`
- `Exploded`
- `Interacted`
- `Evacuated`
- `MissionSucceeded` / `MissionFailed`
- `SaveStarted` / `SaveCompleted`
- `LoadStarted` / `LoadCompleted`

目标支持依赖、计数、可选、失败目标、失败原因、目标/主体数据库 ID、
主体阵营、区域和毫秒截止时间。所有非可选、非失败目标完成后任务成功；
失败目标命中或活动目标超时后任务失败。

建议用 MapEditor 的“协同设计 → 插件导入/导出”打开或保存
`*.m1937mission.json`，再在“高级任务”页编辑 Sidecar ID、选择关号、
原版任务骨架，以及数据库 ID、区域、依赖、计数、可选、失败和超时字段；
复合后缀不会被普通 JSON 插件误识别。

## 3. 状态与存档

主机在游戏目录生成独立状态文件：

- 当前文件先写 `.tmp`；
- 重新解析和校验后原子替换；
- 上一版保留为 `.bak`；
- 状态包含任务定义 SHA-256 和原版 SAV SHA-256；
- 定义或 SAV 不匹配时拒绝读取；
- 崩溃残留 `.tmp` 不会污染已确认状态；
- 原版 SAV 始终只读。

每个原生插件的状态位于 `Mod/Plugins/State`。插件只能通过 ABI 的
`read_sidecar_state` / `write_sidecar_state` 访问自己的槽位，槽位名会
经过路径和长度校验。

## 4. 原生插件 ABI

头文件：

```cpp
#include <M1937SDK/M1937SDK.hpp>
```

插件必须是 x64 DLL，并导出：

```cpp
extern "C" __declspec(dllexport)
const m1937::sdk::plugin::PluginApiV1*
M1937QueryPluginV1();
```

`PluginApiV1` 必须声明：

- `size`；
- `abi_version = 0x00010000`；
- 支持的最小/最大任务 schema；
- 唯一、稳定的 ASCII `plugin_id`；
- `on_load`、`on_unload` 和 `on_world_event`。

`on_load` 应再次检查：

- Host/API 结构长度；
- ABI 和任务 schema；
- EXE SHA-256、映像长度及 PE 时间戳。

事件只包含序号、单调时钟、任务号、稳定主体/对象 ID 和整数值。不得跨 ABI
保存运行时指针；不得阻塞回调；不得调用全局鼠标、输入或焦点 API。

完整示例：

- `SDK/samples/mission-plugin/mission_plugin.cpp`
- `SDK/samples/mission-plugin/Build-SamplePlugin.ps1`

构建：

```powershell
.\SDK\samples\mission-plugin\Build-SamplePlugin.ps1 `
  -OutputDirectory E:\1937\sample-plugin
```

`Build-MissionSidecar.ps1` 会先清理受约束的发布目录，再生成
`Mod/Tools/MissionSidecar/build-manifest.json`；清单记录 x64/API 版本及
每个运行文件的长度和 SHA-256，避免旧 DLL 混入新发布。

把 DLL 复制到 `Mod/Plugins`，再在启动中心同时开启任务 sidecar 和原生
插件。样例插件只统计事件，并通过原子状态 API 保存计数。

## 5. 版本门禁和失败行为

主机始终先校验 SDK 中的唯一受支持 EXE 身份，再检查任务定义声明。插件
加载流程依次检查：

1. x64 DLL 可加载；
2. 存在 `M1937QueryPluginV1`；
3. 返回结构长度有效；
4. ABI 完全匹配；
5. 任务 schema 落在插件声明范围；
6. 插件 ID 合法且没有重复；
7. `on_load` 返回成功。

任何一步失败，该插件不会收到事件；错误写入
`MissionSidecarHost.log`，其他插件和原版游戏继续运行。

## 6. 验证

```powershell
.\Patch\tools\Build-MissionSidecar.ps1

.\Patch\analysis\tools\Test-MissionSidecarRuntime.ps1 `
  -OutputRoot E:\1937\mission-sidecar-runtime
```

自动验证覆盖六类世界事件、任务依赖/计数/可选/成功/失败、截止时间、
原子保存、崩溃回滚、SAV 指纹、schema/API 拒绝、三个发行任务、只读进程
快照、原生插件协商与事件投递。运行时探针还确认原 SAV 写入次数和系统
鼠标/焦点调用次数均为 0。
