# 原版全局随机流恢复

## 目标

原版没有为角色、AI、爆炸等系统分别创建随机数生成器。受支持的
`M1937.exe` 直接调用 MSVCRT `rand()`，且程序没有调用 `srand()`；所有系统
因此共享从状态 `1` 开始的一条进程级 LCG：

```text
state = state * 214013 + 2531011 (mod 2^32)
value = (state >> 16) & 0x7fff
```

只复现公式还不够。要逐次一致，还必须恢复每关加载阶段消耗了多少次、角色按
什么顺序更新，以及运行期每个调用点何时消费。本文记录可重复的取证和当前接线
边界，避免把“确定性”误称为“已经与原版逐次一致”。

## 安全的原版取证

`Patch/src/dinput-proxy/dinput_proxy.cpp` 提供显式环境变量
`M1937_RNG_TRACE=1` 才启用的测试钩子。它只修改本次启动的游戏进程：

- 在 `crt_rand` 入口记录返回值、调用点 RVA、线程和调用者保存的 ESI；
- 热路径只写入固定容量内存环，不执行磁盘 I/O；
- 低优先级后台遥测线程批量写 JSONL；
- 不移动、锁定、裁剪或读取桌面全局鼠标；
- 正常玩家启动时环境变量不存在，钩子完全不安装。

启动阶段探针使用 `--crt-random-startup-only`。角色表就绪后，它只等待一个
很短的目标进程本地时间窗，保存角色地址/索引快照并退出，不发送全局输入。

典型取证流程：

```powershell
$env:M1937_RNG_TRACE = '1'
.\Patch\analysis\tools\Test-ModRegression.ps1 `
  -Levels 0 `
  -CrtRandomStartupOnly `
  -OutputRoot E:\1937\rng-capture

.\Remake\tools\Summarize-CrtRandomTrace.ps1 `
  -TelemetryPath E:\1937\rng-capture\level-01\crt-random-telemetry.jsonl `
  -ActorStatePath E:\1937\rng-capture\level-01\actor-states-crt-startup.csv `
  -LevelId m000
```

`Summarize-CrtRandomTrace.ps1` 会拒绝序号断裂、LCG 值不连续、SDK 未登记调用点
或无法映射的观察门角色。十二关摘要再由
`Build-CrtRandomStartupBaseline.ps1` 合并为运行时目录。

## 十二关启动基线

机器可读结果位于
`game/data/original_crt_random_startup_catalog.json`，并由
`Test-CrtRandomStartupBaseline.ps1` 在每次 `Verify.ps1` 中校验。它固定：

- 受支持 EXE 的 SHA-256；
- m000—m011 各自的启动消耗次数和最终 32 位 LCG 状态；
- 启动调用点序列及“调用点+返回值”序列的 SHA-256；
- 772 名已解析活动角色的 runtime index/scene identity；
- 每名角色构造时的待机上限、初始方向值、AI 相位和反应上限；
- 第一轮实际进入 `sub_45C710` 观察门的 656 名角色及精确顺序。

每关共同先消耗 1,960 次环境构造调用，第一名活动角色从第 1,961 次开始。
不同地图的完整初始化结束点不同：

| 关卡 | 启动消耗 | 最终状态 |
|---|---:|---|
| m000 | 8,489 | `0xCEBEAFA8` |
| m001 | 12,060 | `0x41EC09CD` |
| m002 | 5,552 | `0x44F598F1` |
| m003 | 6,976 | `0x18C06E41` |
| m004 | 12,844 | `0xCC28B19D` |
| m005 | 5,044 | `0x2B243B05` |
| m006 | 7,840 | `0xD2297C21` |
| m007 | 11,592 | `0xE16B18A9` |
| m008 | 5,180 | `0x3C0EB06D` |
| m009 | 8,858 | `0x41CD28FB` |
| m010 | 8,476 | `0xF09B13CD` |
| m011 | 7,432 | `0x776D4169` |

Remake 加载正式关卡时先重置全局流，建立角色后直接恢复到对应的原版
“初始化完成”检查点。原版独有但 Remake 不构造的环境对象不会被伪造出来，
同时第一个游戏逻辑消费仍从正确状态继续。

## 当前运行时接线

已接入同一可存档/回放流的部分包括：

- actor 62 爆炸效果粒子；
- type 90 观察标记的 `rand()%2` 门；
- AI 待机周期后续重置；
- 五点局部搜索的偏移、符号和下一等待上限；
- 尸体反应与骨头/香烟/毒酒分神转换；
- 动态增援的四个角色构造调用；
- 攻击状态转换的调用点消费。

`GameSessionState` 同时保存全局 state/draw index 和逐角色 30 Hz 观察门相位。
type 90 仍按原版为一次性对象，不进入持久化记录。

攻击间隔有一个刻意的过渡保护：调用点会在正确状态转换上消费，但在所有更早
的运行期消费者都迁移前，实际间隔继续使用已经通过稳定 MOD 差分的确定性值。
如果此时直接使用“部分迁移后”的流值，前置缺失调用会使取值错位，第一关目标
可能在第二发步枪前离开视野。此保护不是最终等价声明；完整迁移后应以成对实机
轨迹为门禁移除。

## 完成标准

只有同时满足以下条件，parity contract 中的全局随机缺口才能关闭：

1. 119 个直接调用点的所有正式关卡可达消费者都接入同一流；
2. 各消费者的调用时机、同 tick 仲裁和 actor 顺序都有原版证据；
3. 十二关至少各有一条长时 MOD/Remake 调用序列哈希与可见行为差分；
4. 移除攻击间隔等过渡保护后，现有自然接敌、物品、特殊攻击和性能门禁仍通过；
5. 存档恢复后继续消费的序号、值和可见结果均与不中断运行一致。
