# MOD 性能与 AI 回归验收报告

> 实验性第 13—15 关已经撤下。当前稳定 MOD、选择关卡入口和自动回归
> 范围均严格限定为 12 个原版关卡。

本报告对应 `MOD与MapEditor持续改进评估.md` 中性能基线、逐关闭环、
输入安全和有限敌军智能的最终验收。测试日期为 2026-07-27，测试对象为
当前 `Mod` 成品；所有运行都发生在 `E:\1937` 下的隔离副本。

## 1. 安全边界

- 自动化只向被测游戏窗口和进程内 DirectInput 私有队列发送消息；
- 系统鼠标移动、输入注入和前台焦点 API 调用次数均为 0；
- 源码门禁拒绝 `SetCursorPos`、`ClipCursor`、`mouse_event`、
  `SendInput`、`SetCapture`、`ReleaseCapture`、`SetForegroundWindow`
  和 `SwitchToThisWindow`；
- 运行探针只读调用 `GetClipCursor`，若限制区域小于虚拟桌面即判失败；
- 稳定配置固定为 `windowed=true`、`fullscreen=false`、
  `adjmouse=false`、`devmode=true`、`no_dinput_hook=true`。

菜单与第一关各 60 秒的光标专项回归共取得 1,914 个样本：
光标裁剪限制、未响应、全局光标/输入/焦点调用均为 0。场景内进程光标
覆盖 0—1023 的完整横向逻辑范围。此验证不会移动或锁定 Windows 光标。

## 2. 四类 10 分钟性能基线

每组持续 600 秒，记录 CPU、合成器等待、消息泵、输入、AI、磁盘读取和
遥测队列。性能遥测采用固定 64 槽有界队列和低优先级写盘线程，输入与
消息泵热路径不执行文件打开、写入或关闭。

| 场景 | 样本 | CPU | P95 | P99 | 25—50 ms | >50 ms | 未响应 |
|---|---:|---:|---:|---:|---:|---:|---:|
| 菜单 | 9,733 | 9.433% | 7.542 ms | 12.837 ms | 0 | 0 | 0 |
| 小地图 | 9,692 | 11.504% | 7.490 ms | 9.414 ms | 0 | 0 | 0 |
| 中地图 | 9,665 | 12.185% | 7.634 ms | 12.011 ms | 1 | 0 | 0 |
| 大地图 | 9,649 | 16.080% | 7.614 ms | 11.569 ms | 0 | 0 | 0 |

总计 38,739 个样本，遥测丢失为 0。唯一一个 25—50 ms 离群点与中地图
一次约 15.8 MB 的延迟资源读取重合；输入、消息泵和 AI tick 均不是该
离群点来源。该结果把仍可能偶发的停顿归类为资源首次或延迟加载，而不是
同步日志写盘、卷屏输入或 Present 持续阻塞。

## 3. 12 关十六阶段闭环

每关分别覆盖进程启动、窗口就绪、任务配置、简报加载、简报关闭、
进入世界、初始镜头、F1、M、鼠标、AI 警报、保存、读取、失败、
失败后重玩和胜利，共 192 个阶段：

- 12/12 关通过，192/192 阶段通过；
- 未响应次数 0，光标裁剪限制样本 0；
- 各关合成器 P99 为 8.44—14.07 ms；
- 各关 CPU 为 8.4%—30.7%；
- F1、M 和原始源按键保持原语义，按键别名不会吞掉源键；
- 存档测试使用隔离副本，不修改仓库内用户存档。

完整逐关数据见
`Patch/analysis/results/continuous-improvement/mod-regression-summary.md`
和同名 JSON。

## 4. 有界最后目击点 AI

AI 增强仅使用警报发生时的最后目击快照。它按距离选择有限队友，在最后
位置执行确定性邻近搜索和前向截击，超时后脱离并交还原版巡逻；不会在
视线外持续采样玩家实时位置。

| 指标 | 最终结果 |
|---|---:|
| 发生警报的关卡 | 12/12 |
| 最大反应时间 | 344 ms |
| 同次最大增援数 | 3 |
| 搜索启动 | 38 |
| 路径重规划 | 128 |
| 脱离成功 | 35/35（100%） |
| 最大 AI tick | 1,325 μs |
| 警报后实时采样视线外玩家 | 否 |

关卡、难度和 AI 等级仍会约束反应延迟、增援上限、搜索点数、截击距离及
超时。增强失败或身份签名不匹配时完整回退原版 AI，不形成半启用状态。

## 5. 结论与复验

性能、光标、12 关闭环和 AI 约束均达到发布门槛。可重复执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\Patch\analysis\tools\Test-ModRegression.ps1 `
  -LevelList 1,2,3,4,5,6,7,8,9,10,11,12 `
  -DurationSeconds 60 `
  -OutputRoot E:\1937\mod-regression

powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\Patch\analysis\tools\Test-ModPerformance.ps1 `
  -DurationSeconds 600 `
  -Profiles menu,small,medium,large `
  -OutputRoot E:\1937\mod-performance
```

体积受控的最终汇总保存在
`Patch/analysis/results/continuous-improvement/`；高频原始 JSONL 和
隔离游戏目录只保留在本机测试目录，不进入发行包。
