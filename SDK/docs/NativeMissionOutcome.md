# 原版任务结果观察

本文固定稳定 MOD 中已验证的任务结果布局与观察边界，供补丁、探针和
Remake 差分测试复用。

## 已恢复入口

| 符号 | RVA | 作用 |
|---|---:|---|
| `InitializeMissionBindings` | `0x00004BB0` | 初始化当前任务的对象绑定 |
| `EvaluateMission` | `0x00005410` | 执行当前任务的成功/失败判断 |
| `EvaluateMissionThunk` | `0x0000106E` | 世界循环调用的 evaluator thunk |
| `UpdateGameWorld` | `0x00006AD0` | 推进游戏世界 |

地址与期望字节的唯一机器源是 `SDK/address-catalog.json`；代码不得另行
复制裸 RVA。

## 控制器状态

`SDK/include/M1937SDK/Mission.hpp` 的
`RuntimeControllerStateV1` 只命名了十二关控制流共同证明的三个字段：

- `+0xA4 game_flow_state`
- `+0xBC evaluation_active`
- `+0xC0 result_state`

已证实的结果值为 `0`（未结束/未知）、`2`（失败）和 `3`（胜利）。
观察者必须在原 evaluator 返回之后读取状态，不得把推测结果写回控制器。

## 安全诊断

设置 `M1937_MISSION_TRACE=1` 后，DirectInput 代理启用只读任务观察并把
当前任务、原始状态、调用次数、转换序号和 tick 附加到遥测。该开关默认
关闭，不改变正常 MOD 的输入、光标或任务行为。

`ModRegressionProbe --native-mission-failure-only` 还可在隔离副本中把
“致命伤害”命令排入目标进程自己的 DirectInput 边界；代理随后调用原
`sub_458700` 伤害入口。任务失败仍由下一次原 `sub_405410` 求值自然产生，
探针不写任务结果，也不控制系统鼠标。

已提交的 `m000`—`m011-native-required-player-failure-v1.json` 逐关证明
evaluator 必要角色从 8 HP 变为死亡后，原结果从 0 变为 2。Remake 使用
同一角色与位置，通过产品 `take_damage()` 路径产生
`required_character_lost`；专用比较器每关执行 26 项严格差分。
`Remake/tools/Capture-TwelveLevelNativeMissionFailureParity.ps1` 可在隔离
MOD 中重采全部十二关并重放 Remake 对应轨迹。
